#!/usr/bin/env rdmd -betterC

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;

enum Allocator_Mode {
  ALLOC,
  RESIZE,
  CLEAR,
  FREE,
}

struct Allocator {
  void* function(void*, Allocator_Mode, void*, size_t, size_t) proc;
  void* data;
}

struct Array(T) {
  T[] elements;
  alias this = elements;
  size_t capacity;
  Allocator allocator;
}

struct String {
  char[] data;
  alias this = data;
  this(string x) { data = (cast(char*) x.ptr)[0..x.length]; }
  this(char* x) { data = x[0..strlen(x)]; }
}

__gshared Allocator c_allocator;

void init_global_allocators() {
  c_allocator.proc = (data, mode, old_data, old_size, new_size) {
    final switch (mode) {
      case Allocator_Mode.ALLOC:
        return malloc(new_size);
      case Allocator_Mode.RESIZE:
        return realloc(old_data, new_size);
      case Allocator_Mode.CLEAR:
        assert(false);
        return null;
      case Allocator_Mode.FREE:
        free(old_data);
        return null;
    }
  };
}

struct Context {
  Allocator allocator;
}

__gshared Context context;

void init_context() {
  context.allocator = c_allocator;
}

enum push_context(alias new_context) = "
  Context save_context = context;
  scope(exit) context = save_context;
  context = "~new_context.stringof~";
";

T* New(T)(T init = T.init, Allocator allocator = context.allocator) {
  auto ptr = cast(T*) allocator.proc(allocator.data, Allocator_Mode.ALLOC, null, 0, T.sizeof);
  *ptr = init;
  return ptr;
}

void Free(T)(T* ptr, Allocator allocator = context.allocator) {
  allocator.proc(allocator.data, Allocator_Mode.FREE, ptr, 0, 0);
}

enum Code_Kind {
  IDENTIFIER,
  KEYWORD,
  INTEGER,
  FLOAT,
  STRING,
  TUPLE,
}

struct Code {
  Code_Kind kind;
  union {
    String as_atom;
    Array!(Code*) as_tuple;
  }
}

void repl() {
  String file = "repl";
}

void compile(String file) {

}

extern(C) void main(int argc, char** argv) {
  init_global_allocators();
  init_context();

  if (argc <= 1) repl();
  else compile(argv[1].String);
}
