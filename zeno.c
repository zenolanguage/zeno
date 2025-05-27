/* See LICENSE file for copyright and license details.
 *
 * This project follows the [suckless coding style](https://suckless.org/coding_style).
 */

#include <assert.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ALLOC(ALLOCATOR, SIZE) (ALLOCATOR).proc((ALLOCATOR).data, ALLOCATOR_ALLOC, NULL, 0, (SIZE))
#define RESIZE(ALLOCATOR, OLD_DATA, OLD_SIZE, NEW_SIZE) (ALLOCATOR).proc((ALLOCATOR).data, ALLOCATOR_RESIZE, (OLD_DATA), (OLD_SIZE), (NEW_SIZE))
#define FREE_ALL(ALLOCATOR) (ALLOCATOR).proc((ALLOCATOR).data, ALLOCATOR_FREE_ALL, NULL, 0, 0)
#define Slice(T) SliceT
#define Array(T) ArrayT

typedef enum Allocator_Mode {
  ALLOCATOR_ALLOC,
  ALLOCATOR_RESIZE,
  ALLOCATOR_FREE,
  ALLOCATOR_FREE_ALL,
} Allocator_Mode;

typedef struct Allocator {
  void *(*proc)(void *data, Allocator_Mode mode, void *old_data, size_t old_size, size_t new_size);
  void *data;
} Allocator;

typedef struct Temporary_Allocator_Data {
  size_t size;
  void *base;
  size_t capacity;
  size_t requested_initial_capacity_from_backing_allocator;
  Allocator backing_allocator;
} Temporary_Allocator_Data;

typedef struct String {
  size_t count;
  char *data;
} String;

typedef struct SliceT {
  size_t count;
  size_t element_size;
  void *data;
} SliceT;

typedef struct ArrayT {
  SliceT items;
  size_t capacity;
  Allocator allocator;
} ArrayT;

typedef enum Code_Kind {
  CODE_IDENTIFIER,
  CODE_NUMBER,
  CODE_STRING,
  CODE_TUPLE,
} Code_Kind;

typedef struct Code {
  uint32_t location;
  Code_Kind kind;
  union {
    String as_identifier;
    String as_string;
    double as_number;
    Array(Code) as_tuple;
  };
} Code;

typedef struct Parse_Result {
  union {
    struct {
      Code *code;
      uint32_t next_pos;
    };
    struct {
      String error_message;
      uint32_t location;
    };
  };
  uint8_t ok;
} Parse_Result;

static Allocator c_allocator;
static Allocator temporary_allocator;
static Temporary_Allocator_Data temporary_allocator_data;

static void
die(char *format, ...)
{
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  exit(EXIT_FAILURE);
}

static String
tprintf(char *format, ...)
{
  va_list ap;
  char *buf;
  int len;

  if ((buf = (char*) ALLOC(temporary_allocator, 1024)) == NULL)
    die("Temporary allocator ran out of memory.\n");
  va_start(ap, format);
  len = vsnprintf(buf, 1024, format, ap);
  va_end(ap);
  return (String){len, buf};
}

static void*
c_allocator_proc(void *data, Allocator_Mode mode, void *old_data, size_t old_size, size_t new_size)
{
  (void) data;
  (void) old_size;

  switch (mode) {
  case ALLOCATOR_ALLOC:
    return malloc(new_size);
  case ALLOCATOR_RESIZE:
    return realloc(old_data, new_size);
  case ALLOCATOR_FREE:
    free(old_data);
    return NULL;
  case ALLOCATOR_FREE_ALL:
    die("The c_allocator doesn't support freeing everything.\n");
    return NULL;
  }
}

static void*
temporary_allocator_proc(void *data_, Allocator_Mode mode, void *old_data, size_t old_size, size_t new_size)
{
  Temporary_Allocator_Data *data = (Temporary_Allocator_Data*) data_;
  void *result;
  size_t initial_capacity;

  (void) old_data;
  (void) old_size;

  switch (mode) {
  case ALLOCATOR_ALLOC:
    if (data->size + new_size >= data->capacity) {
      initial_capacity = data->capacity;
      if (data->capacity == 0)
        data->capacity = data->requested_initial_capacity_from_backing_allocator;
      else
        data->capacity *= 2;
      data->base = RESIZE(data->backing_allocator, data->base, initial_capacity, data->capacity);
      if (data->base == NULL)
        die("temporary_allocator failed to acquire more memory from backing_allocator.\n");
    }
    result = (uint8_t*) data->base + data->size;
    data->size += new_size;
    return result;
  case ALLOCATOR_RESIZE:
    die("temporary_allocator doesn't support resizing.\n");
    return NULL;
  case ALLOCATOR_FREE:
    return NULL;
  case ALLOCATOR_FREE_ALL:
    data->size = 0;
    return NULL;
  }
}

static void*
array_add(ArrayT *array)
{
  void *result;
  size_t initial_capacity;

  if (array->items.count + 1 >= array->capacity) {
    initial_capacity = array->capacity;
    if (array->capacity == 0)
      array->capacity = array->items.element_size * 16;
    else
      array->capacity *= 2;
    array->items.data = RESIZE(array->allocator, array->items.data, array->items.element_size * initial_capacity, array->items.element_size * array->capacity);
    if (array->items.data == NULL)
      die("Failed to reallocate dynamic array.\n");
  }

  result = (uint8_t*) array->items.data + (array->items.element_size * array->items.count);
  array->items.count += 1;
  memset(result, 0, array->items.element_size);
  return result;
}

static void*
array_pop(ArrayT *array)
{
  if (array->items.count == 0)
    die("You can't pop from an empty array.\n");
  return (uint8_t*) array->items.data + (array->items.element_size * --array->items.count);
}

static String
read_entire_file(char *path, Allocator allocator)
{
  String result;
  FILE *f;

  result.data = NULL;
  if ((f = fopen(path, "rb")) != NULL) {
    fseek(f, 0, SEEK_END);
    result.count = (size_t) ftell(f);
    fseek(f, 0, SEEK_SET);
    result.data = (char*) ALLOC(allocator, result.count);
    if (result.data != NULL)
      fread(result.data, 1, result.count, f);
    fclose(f);
  }
  return result;
}

static Parse_Result
parse_code(String s, uint32_t p, Allocator allocator)
{
  Parse_Result result = {0};
  Array(uint8_t) implicitnesses = {.items.element_size = sizeof(uint8_t), .allocator = temporary_allocator};
  Array(Code*) codes = {.items.element_size = sizeof(Code*), .allocator = temporary_allocator};
  uint32_t start;
  Code *code, **codeptr;

  for (;;) {
    start = p;
    for (;;) {
      while (p < s.count && isspace(s.data[p])) p += 1;
      if (p < s.count && s.data[p] == ';') {
        while (p < s.count && s.data[p] != '\n') p += 1;
        continue;
      }
      break;
    }
    if (p >= s.count) break;
    start = p;
    if (s.data[p] == '(') {
      p += 1;
      code = (Code*) ALLOC(allocator, sizeof(Code));
      code->location = start;
      code->kind = CODE_TUPLE;
      codeptr = (Code**) array_add(&codes);
      *codeptr = code;
    } else if (s.data[p] == ')') {
      p += 1;
      codeptr = (Code**) array_add(&codes);
      *codeptr = *(Code**) array_pop(&codes);
    } else {
      while (p < s.count && !isspace(s.data[p]) && s.data[p] != '(' && s.data[p] != ')' && s.data[p] != ';') p += 1;
      code = (Code*) ALLOC(allocator, sizeof(Code));
      code->location = start;
      code->kind = CODE_IDENTIFIER;
      code->as_identifier = (String){p - start, s.data + start};
      // NOTE: I gave up at this point.
      // (Code**) array_add(&codes.items.data &codes);
    }
    if (implicitnesses.items.count == 0) break;
  }

  result.code = codes.items.count > 0 ? *(Code**) array_pop(&codes) : NULL;
  result.next_pos = p;
  result.ok = 1;
  return result;
}

static void
compile(char *file)
{
  String src;
  uint32_t pos;

  src = read_entire_file(file, c_allocator);
  if (src.data == NULL)
    die("I failed to find \"%s\" on your drive. Maybe you need to quote the entire path?\n", file);

  pos = 0;
  for (;;) {
    FREE_ALL(temporary_allocator);

    Parse_Result result = parse_code(src, pos, c_allocator);
    if (!result.ok)
      die("%s[%u] parse error: %.*s\n", file, pos, result.error_message);
    if (result.code == NULL)
      break;
    pos = result.next_pos;
  }
}

int
main(int argc, char **argv)
{
  c_allocator.proc = c_allocator_proc;
  temporary_allocator_data.requested_initial_capacity_from_backing_allocator = 2048;
  temporary_allocator_data.backing_allocator = c_allocator;
  temporary_allocator.proc = temporary_allocator_proc;
  temporary_allocator.data = &temporary_allocator_data;

  if (argc <= 1)
    die("I expected a file to compile, like this: \"%s file.z\".\n", argc == 1 ? argv[0] : "zeno");

  compile(argv[1]);

  return EXIT_SUCCESS;
}
