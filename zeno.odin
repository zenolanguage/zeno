package main

import "core:os"
import "core:fmt"
import "core:strconv"
import "core:strings"

die :: proc(format: string, args: ..any) -> ! {
  fmt.eprintf(format, ..args)
  os.exit(1)
}

New :: proc(init: $T, allocator := context.allocator) -> ^T {
  value := new(T, allocator)
  value^ = init
  return value
}

Code_Kind :: enum {
  IDENTIFIER,
  KEYWORD,
  NUMBER,
  STRING,
  TUPLE,
}

Code :: struct {
  location: u32,
  kind: Code_Kind,
  using data: struct #raw_union {
    as_string: string,
    as_number: f64,
    as_tuple: [dynamic]^Code,
  },
}

Parse_Error :: struct {
  message: string,
  location: u32,
  ok: bool,
}

parse_code :: proc(s: string, p: u32) -> (^Code, u32, Parse_Error) {
  p := p
  level := 0
  codes: [dynamic]^Code
  defer delete(codes)
  for {
    start := p
    for {
      for p < u32(len(s)) && strings.is_space(rune(s[p])) do p += 1
      if p < u32(len(s)) && s[p] == ';' {
        for p < u32(len(s)) && s[p] != '\n' do p += 1
        continue
      }
      break
    }
    if p >= u32(len(s)) do break
    start = p
    if s[p] == '(' {
      p += 1
      level += 1
      append(&codes, New(Code{start, .TUPLE, {}}))
    } else if s[p] == ')' {
      p += 1
      if level == 0 do return nil, p, {"You have an extraneous closing parenthesis.", start, false}
      level -= 1
      if len(codes) > 1 {
        popped := pop(&codes)
        assert(codes[len(codes) - 1].kind == .TUPLE)
        append(&codes[len(codes) - 1].as_tuple, popped)
      }
    } else {
      for p < u32(len(s)) && !strings.is_space(rune(s[p])) && s[p] != '(' && s[p] != ')' && s[p] != ';' do p += 1
      if len(codes) > 0 do assert(codes[len(codes) - 1].kind == .TUPLE)
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, New(Code{start, .IDENTIFIER if s[start] != '#' else .KEYWORD, {as_string=s[start:p]}}))
    }
    if level == 0 do break
  }
  if level != 0 do return nil, p, {"You have an unclosed parentheses pair.", p, false}
  assert(len(&codes) <= 1)
  return pop(&codes) if len(codes) > 0 else nil, p, {"", 0, true}
}

code_as_string :: proc(code: ^Code, allocator := context.temp_allocator) -> string {
  switch code.kind {
    case .IDENTIFIER: return code.as_string
    case .KEYWORD: return code.as_string
    case .NUMBER: buf, err := new([32]u8, allocator); return strconv.ftoa(buf[:], code.as_number, 'f', 8, 64) if err != nil else ""
    case .STRING: return code.as_string
    case .TUPLE:
      b := strings.builder_make_none(allocator)
      fmt.sbprintf(&b, "(")
      for code2, i in code.as_tuple do fmt.sbprintf(&b, "%s%s", code_as_string(code2), " " if i != len(code.as_tuple) - 1 else "")
      fmt.sbprintf(&b, ")")
      return strings.to_string(b)
  }
  die("You shouldn't have gotten here. (compiler bug)\n")
}

repl :: proc() {
  init_global_temporary_allocator(8096)

  file := "repl"
  buf: [1024]u8 = ---
  for {
    free_all(context.temp_allocator)

    fmt.printf("> ")
    n, err := os.read(os.stdin, buf[:])
    if err != nil do break
    src := string(buf[:n])
    trimmed := strings.trim_space(src)
    if trimmed == "quit" || trimmed == "exit" do break
    pos: u32 = 0
    for {
      code, next_pos, err := parse_code(src, pos)
      if !err.ok {
        fmt.eprintf("%s[%d] %s\n", file, err.location, err.message)
        break
      }
      if code == nil do break
      pos = next_pos
      fmt.printf("%s\n", code_as_string(code))
    }
  }
}

compile :: proc(file: string) {
  src, success := os.read_entire_file(file)
  if !success do die("I failed to read \"%s\" from your drive. Maybe you need to quote the entire path?\n", file)

  pos: u32 = 0
  for {
    code, next_pos, err := parse_code(string(src), pos)
    if !err.ok do die("%s\n", err.message)
    if code == nil do break
    pos = next_pos
  }
}

main :: proc() {
  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
