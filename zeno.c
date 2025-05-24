#define ASSERT(X) do if (!(X)) assertion_failed_proc(#X, __FILE__, __LINE__); while (0)

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdbool.h>

#define allocator_resize(ALLOCATOR, OLD_DATA, OLD_SIZE, NEW_SIZE) (ALLOCATOR).proc((ALLOCATOR).data, ALLOCATOR_RESIZE, (OLD_DATA), (OLD_SIZE), (NEW_SIZE));

typedef enum {
  ALLOCATOR_ALLOC,
  ALLOCATOR_RESIZE,
  ALLOCATOR_FREE,
  ALLOCATOR_FREE_ALL,
} Allocator_Mode;

typedef struct {
  void* (*proc)(void* data, Allocator_Mode mode, void* old_data, size_t old_size, size_t new_size);
  void* data;
} Allocator;

extern Allocator allocator;
extern Allocator temporary_allocator;
extern void (*assertion_failed_proc)(char* exp, char* file, int line);

#define DEFSLICE(NAME, T)       \
  typedef struct Slice_##NAME { \
    size_t count;               \
    T* data;                    \
  } Slice_##NAME;

#define DEFARRAY(NAME, T)       \
  typedef struct Array_##NAME { \
    Slice_##NAME items;         \
    size_t capacity;            \
    Allocator allocator;        \
  } Array_##NAME;

DEFSLICE(U8, unsigned char)
DEFSLICE(CodePtr, struct Code*)
DEFARRAY(CodePtr, struct Code*)
typedef Slice_U8 String;

typedef enum {
  CODE_IDENTIFIER,
  CODE_KEYWORD,
  CODE_INTEGER,
  CODE_FLOAT,
  CODE_STRING,
  CODE_TUPLE,
} Code_Kind;

typedef struct {
  Code_Kind kind;
  union {
    String as_string;
    Array_CodePtr as_tuple;
  } u;
} Code;

#if !defined(ZENO_NO_DEFAULT_ALLOCATORS)
static Allocator c_allocator;
static Allocator c_temporary_allocator;

static void* c_allocator_proc(void* data, Allocator_Mode mode, void* old_data, size_t old_size, size_t new_size) {
  switch (mode) {
    case ALLOCATOR_ALLOC: return malloc(new_size);
    case ALLOCATOR_RESIZE: return realloc(old_data, new_size);
    case ALLOCATOR_FREE: free(old_data); return NULL;
    case ALLOCATOR_FREE_ALL: ASSERT(false); return NULL;
  }
}

static struct C_Temporary_Allocator_Data {
  void* base;
  size_t size;
  size_t capacity;
  Allocator backup_allocator;
  size_t init_capacity;
} c_temporary_allocator_data;
static void* c_temporary_allocator_proc(void* data, Allocator_Mode mode, void* old_data, size_t old_size, size_t new_size) {
  struct C_Temporary_Allocator_Data* t = data;
  ASSERT(&c_temporary_allocator_data == t);
  switch (mode) {
    case ALLOCATOR_ALLOC: {
      if (t->size + new_size >= t->capacity) {
        size_t save_capacity = t->capacity;
        if (t->capacity == 0) t->capacity = t->init_capacity;
        else t->capacity *= 2;
        t->base = allocator_resize(t->backup_allocator, t->base, save_capacity, t->capacity);
      }
      char* result = (char*) t->base + t->size;
      t->size += new_size;
      return result;
    }
    case ALLOCATOR_RESIZE: {
      ASSERT(false);
      return NULL;
    }
    case ALLOCATOR_FREE: {
      // ignore temporary frees.
      return NULL;
    }
    case ALLOCATOR_FREE_ALL: {
      c_temporary_allocator_data.size = 0;
      return NULL;
    }
  }
}
#endif /* !ZENO_NO_DEFAULT_ALLOCATORS */

#if !defined(ZENO_NO_ENTRY)
Allocator allocator;
Allocator temporary_allocator;
void (*assertion_failed_proc)(char* exp, char* file, int line);

static void assertion_failed_proc_impl(char* exp, char* file, int line) {
  fprintf(stderr, "%s(%d) assertion failed: \"%s\".\n", file, line, exp);
  exit(1);
}

int main(int argc, char** argv) {
  c_allocator.proc = c_allocator_proc;
  c_temporary_allocator.proc = c_temporary_allocator_proc;
  c_temporary_allocator.data = &c_temporary_allocator_data;
  c_temporary_allocator_data.backup_allocator = c_allocator;
  c_temporary_allocator_data.init_capacity = 8096;

  allocator = c_allocator;
  temporary_allocator = c_temporary_allocator;
  assertion_failed_proc = assertion_failed_proc_impl;

  return EXIT_SUCCESS;
}
#endif /* !ZENO_NO_ENTRY */
