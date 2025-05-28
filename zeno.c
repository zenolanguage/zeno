#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define null NULL
#define true (cast(Bool8) 1)
#define false (cast(Bool8) 0)
#define cast(T) (T)

typedef uint8_t U8;
typedef size_t USize;
typedef U8 Bool8;

#define allocator_alloc(ALLOCATOR, SIZE) (ALLOCATOR).proc((ALLOCATOR).data, ALLOCATOR_ALLOCATE, null, 0, (SIZE))

typedef enum Allocator_Mode {
  ALLOCATOR_ALLOCATE,
  ALLOCATOR_RESIZE,
  ALLOCATOR_FREE,
  ALLOCATOR_FREE_ALL,
} Allocator_Mode;

typedef struct Allocator {
  void* (*proc)(void* data, Allocator_Mode mode, void* old_data, USize old_size, USize new_size);
  void* data;
} Allocator;

#define slice(T, ARRAY, START, END) (cast(Slice(T)){(END) - (START), (ARRAY) + (START)})
#define Slice(T) Slice_##T
#define DEFINE_SLICE(T)     \
  typedef struct Slice(T) { \
    USize count;            \
    T* data;                \
  } Slice(T);

#define string_from_literal(LIT) (cast(Slice(U8)){sizeof(LIT) - 1, cast(U8*) (LIT)})
DEFINE_SLICE(U8)

Allocator c_allocator;

void* c_allocator_proc(void* data, Allocator_Mode mode, void* old_data, USize old_size, USize new_size) {
  (void) data;
  (void) old_size;
  void* result;
  switch (mode) {
    case ALLOCATOR_ALLOCATE:
      result = malloc(new_size);
      memset(result, 0, new_size);
      return result;
    case ALLOCATOR_RESIZE:
      result = realloc(old_data, new_size);
      memset(cast(U8*) result + old_size, 0, new_size - old_size);
      return result;
    case ALLOCATOR_FREE:
      free(old_data);
      return null;
    case ALLOCATOR_FREE_ALL:
      return null;
  }
  return null; // for the dumb compilers.
}

void die(char* format, ...) {
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  exit(EXIT_FAILURE);
}

Slice(U8) read_entire_file(char* file, Allocator allocator) {
  Slice(U8) result = {0};
  FILE* f = fopen(file, "rb");
  if (f != null) {
    fseek(f, 0, SEEK_END);
    result.count = ftell(f);
    fseek(f, 0, SEEK_SET);
    result.data = allocator_alloc(allocator, result.count + 1);
    if (result.data != null) {
      fread(result.data, 1, result.count, f);
      result.data[result.count] = '\0';
    }
    fclose(f);
  }
  return result;
}

Slice(U8) trim_spaces_left(Slice(U8) s) {
  while (s.count > 0 && isspace(s.data[0])) s.data += 1, s.count -= 1;
  return s;
}

Slice(U8) trim_spaces_right(Slice(U8) s) {
  while (s.count > 0 && isspace(s.data[s.count - 1])) s.count -= 1;
  return s;
}

Slice(U8) trim_spaces(Slice(U8) s) {
  return trim_spaces_left(trim_spaces_right(s));
}

#define string_equal_literal(A, LIT) string_equal((A), string_from_literal(LIT))
Bool8 string_equal(Slice(U8) a, Slice(U8) b) {
  if (a.count != b.count) return false;
  return memcmp(a.data, b.data, a.count) == 0;
}

void repl(void) {
  char* file = "repl";
  static char line_buffer[1024];
  while (!feof(stdin)) {
    printf("> ");
    if (fgets(line_buffer, sizeof line_buffer, stdin) == null) break;
    Slice(U8) line = slice(U8, cast(U8*) line_buffer, 0, strlen(line_buffer));
    Slice(U8) trimmed = trim_spaces(line);
    if (trimmed.count == 0) continue;
    if (string_equal_literal(trimmed, ",quit") || string_equal_literal(trimmed, ",exit")) break;
    printf("%s", line_buffer);
  }
}

void compile(char* file) {
  Slice(U8) src = read_entire_file(file, c_allocator);
  if (src.data == null) die("I failed to read \"%s\" from your drive. Maybe you need to quote the entire path?\n", file);
  printf("%.*s\n", cast(int) src.count, src.data);
}

int main(int argc, char** argv) {
  c_allocator.proc = c_allocator_proc;

  if (argc <= 1) repl();
  else compile(argv[1]);

  return EXIT_SUCCESS;
}
