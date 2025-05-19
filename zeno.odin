package main

import "core:os"
import "core:fmt"
import "core:strings"

Code_Kind :: enum {
  IDENTIFIER,
  KEYWORD,
  INTEGER,
  FLOAT,
  STRING,
  TUPLE,
}

Code :: struct {
  location: int,
  kind: Code_Kind,
  using data: struct #raw_union {
    as_string: string,
    as_integer: int,
    as_float: f64,
    as_tuple: [dynamic]^Code,
  },
}

parse_code :: proc(s: string, p: int, file: string) -> (^Code, int) {
  return nil, p
}

repl :: proc() {
  file := "repl"
  line_buffer: [256]u8 = ---
  for {
    fmt.printf("> ")
    if n, err := os.read(os.stdin, line_buffer[:]); err == nil {
      line := string(line_buffer[:n])
      trimmed := strings.trim_space(line)
      if trimmed == "quit" || trimmed == "exit" do break

      pos := 0
      for {
        code, next_pos := parse_code(line, pos, file)
        if code == nil do break
        pos = next_pos
      }
    }
  }
}

compile :: proc(file: string) {
  src, success := os.read_entire_file(file)
  if !success do fmt.panicf("I failed to find '%s' on your drive. Maybe you need to quote the entire path?\n", file)

  pos := 0
  for {
    code, next_pos := parse_code(string(src), pos, file)
    if code == nil do break
    pos = next_pos
  }
}

main :: proc() {
  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
