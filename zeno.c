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

#define ALLOC(ALLOCATOR, T, COUNT) ((T*) (ALLOCATOR).proc((ALLOCATOR).data, ALLOCATOR_ALLOC, NULL, 0, sizeof(T) * (COUNT)))

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

typedef struct String {
  size_t count;
  char *data;
} String;

static Allocator c_allocator;

static void
die(char *format, ...)
{
  va_list ap;
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  exit(EXIT_FAILURE);
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
    result.data = ALLOC(allocator, char, result.count);
    if (result.data != NULL)
      fread(result.data, 1, result.count, f);
    fclose(f);
  }
  return result;
}

int
main(int argc, char **argv)
{
  c_allocator.proc = c_allocator_proc;

  if (argc <= 1)
    die("I expected a file to compile, like this: \"%s file.z\".\n", argc == 1 ? argv[0] : "zeno");

  char *file = argv[1];
  String src = read_entire_file(file, c_allocator);
  if (src.data == NULL)
    die("I failed to find \"%s\" on your drive. Maybe you need to quote the entire path?\n", file);

  printf("%.*s\n", (int) src.count, src.data);

  return EXIT_SUCCESS;
}
