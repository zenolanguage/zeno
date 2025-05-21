package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"

die :: proc(format: string, args: ..any) {
  fmt.eprintf(format, ..args)
  os.exit(1)
}

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

Parse_Error :: struct {
  message: string,
  location: int,
  ok: bool,
}

parse_code :: proc(s: string, p: int, no_implicit_parentheses := false) -> (^Code, int, Parse_Error) {
  p := p

  explicit_top_level_was_closed := false
  indents: [dynamic]int
  implicitnesses: [dynamic]bool
  codes: [dynamic]^Code

  defer delete(indents)
  defer delete(implicitnesses)
  defer delete(codes)

  for {
    start := p
    newline_was_skipped := false
    beginning_of_line := start
    for {
      for p < len(s) && strings.is_space(rune(s[p])) {
        if s[p] == '\n' {
          newline_was_skipped = true
          beginning_of_line = p + 1
        }
        p += 1
      }
      if p < len(s) && s[p] == ';' {
        for p < len(s) && s[p] != '\n' do p += 1
        continue
      }
      break
    }
    if p >= len(s) do break

    indent := p - beginning_of_line
    first_exp_of_line := newline_was_skipped || start == 0
    if first_exp_of_line {
      if len(indents) == 0 || indent > indents[len(indents) - 1] do append(&indents, indent)
      if !no_implicit_parentheses && s[p] != '(' && s[p] != ')' {
        append(&implicitnesses, true)
        tuple := new(Code)
        tuple.location = start
        tuple.kind = .TUPLE
        append(&codes, tuple)
      }
    }

    start = p
    if s[p] == '(' {
      p += 1
      append(&implicitnesses, false)
      tuple := new(Code)
      tuple.location = start
      tuple.kind = .TUPLE
      append(&codes, tuple)
    } else if s[p] == ')' {
      p += 1

      if len(implicitnesses) > 0 && implicitnesses[len(implicitnesses) - 1] {
        pop(&implicitnesses)
      }

      if len(implicitnesses) == 0 do return nil, p, {"You have an extraneous closing parenthesis.", start, false}
      pop(&implicitnesses)
      explicit_top_level_was_closed = len(implicitnesses) == 0
      if len(codes) > 1 {
        popped := pop(&codes)
        append(&codes[len(codes) - 1].as_tuple, popped)
      }
    } else if s[p] == '\'' {
      p += 1
      code, next_pos, error := parse_code(s, p, no_implicit_parentheses)
      if !error.ok do return nil, next_pos, error
      if code == nil do return nil, next_pos, {"You tried to take the $code of nothing.", start, false}
      p = next_pos

      tuple := new(Code)
      tuple.location = start
      tuple.kind = .TUPLE
      identifier := new(Code)
      identifier.location = start
      identifier.kind = .IDENTIFIER
      identifier.as_string = "$code"
      append(&tuple.as_tuple, identifier)
      append(&tuple.as_tuple, code)
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, tuple)
    } else if s[p] == ',' {
      p += 1
      code, next_pos, error := parse_code(s, p, no_implicit_parentheses)
      if !error.ok do return nil, next_pos, error
      if code == nil do return nil, next_pos, {"You tried to $insert nothing.", start, false}
      p = next_pos

      tuple := new(Code)
      tuple.location = start
      tuple.kind = .TUPLE
      identifier := new(Code)
      identifier.location = start
      identifier.kind = .IDENTIFIER
      identifier.as_string = "$insert"
      string_ := new(Code)
      string_.location = start
      string_.kind = .STRING
      string_.as_string = "\"%\""
      append(&tuple.as_tuple, identifier)
      append(&tuple.as_tuple, string_)
      append(&tuple.as_tuple, code)
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, tuple)
    } else if s[p] >= '0' && s[p] <= '9' || ((s[p] == '+' || s[p] == '-') && p + 1 < len(s) && s[p + 1] >= '0' && s[p + 1] <= '9') {
      p += 1
      for p < len(s) && s[p] >= '0' && s[p] <= '9' do p += 1
      code := new(Code)
      code.location = start
      if p < len(s) && s[p] == '.' {
        p += 1
        for p < len(s) && s[p] >= '0' && s[p] <= '9' do p += 1
        code.kind = .FLOAT
        code.as_float = strconv.atof(s[start:p])
      } else {
        code.kind = .INTEGER
        code.as_integer = strconv.atoi(s[start:p])
      }
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, code)
    } else if s[p] == '"' {
      p += 1
      for p < len(s) && (s[p - 1] == '\\' || s[p] != '"') do p += 1
      if p >= len(s) || s[p] != '"' do return nil, p, {"You have an unterminated string literal.", start, false}
      p += 1
      code := new(Code)
      code.location = start
      code.kind = .STRING
      code.as_string = s[start:p]
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, code)
    } else {
      for p < len(s) && !strings.is_space(rune(s[p])) && s[p] != '(' && s[p] != ')' && s[p] != ';' do p += 1
      code := new(Code)
      code.location = start
      code.kind = .IDENTIFIER if s[start] != '#' else .KEYWORD
      code.as_string = s[start:p]
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, code)
    }

    peek := p
    for peek < len(s) && (strings.is_space(rune(s[peek])) || s[peek] == ')') && s[peek] != '\n' && s[peek] != ';' do peek += 1
    last_exp_of_line := peek >= len(s) || s[peek] == '\n' || s[peek] == ';'

    beginning_of_next_line := peek
    for {
      for peek < len(s) && strings.is_space(rune(s[peek])) {
        if s[peek] == '\n' do beginning_of_next_line = peek + 1
        peek += 1
      }
      if peek < len(s) && s[peek] == ';' {
        for peek < len(s) && s[peek] != '\n' do peek += 1
        continue
      }
      break
    }

    next_indent := peek - beginning_of_next_line if peek != len(s) else 0
    if last_exp_of_line {
      if len(implicitnesses) > 0 && implicitnesses[len(implicitnesses) - 1] do pop(&implicitnesses)
      for len(indents) > 0 && next_indent <= indents[len(indents) - 1] {
        pop(&indents)
        if len(codes) > 1 {
          popped := pop(&codes)
          append(&codes[len(codes) - 1].as_tuple, popped)
        }
      }
    }

    if len(implicitnesses) == 0 && (explicit_top_level_was_closed || (len(indents) == 0 || next_indent <= indents[0])) do break
  }

  if len(implicitnesses) != 0 do return nil, p, {"You are missing a closing parenthesis.", p, false}

  assert(len(codes) <= 1)
  assert(len(codes) == 0 || explicit_top_level_was_closed || len(indents) == 0)

  return pop(&codes) if len(codes) > 0 else nil, p, {ok = true}
}

code_as_string :: proc(code: ^Code) -> string {
  switch code.kind {
    case .IDENTIFIER: return code.as_string
    case .KEYWORD: return code.as_string
    case .INTEGER: buf := new([32]u8); return strconv.itoa(buf[:], code.as_integer)
    case .FLOAT: buf := new([32]u8); return strconv.ftoa(buf[:], code.as_float, 'f', 6, 64)
    case .STRING: return code.as_string
    case .TUPLE:
      b: strings.Builder
      fmt.sbprintf(&b, "(")
      for c, index in code.as_tuple do fmt.sbprintf(&b, "%s%s", code_as_string(c), " " if index != len(code.as_tuple) - 1 else "")
      fmt.sbprintf(&b, ")")
      return strings.to_string(b)
  }
  assert(false)
  return ""
}

repl :: proc() {
  file := "repl"
  line_buffer: [256]u8 = ---
  for {
    fmt.printf("> ")

    n, err := os.read(os.stdin, line_buffer[:])
    if err != nil do continue
    line := string(line_buffer[0:n])
    trimmed := strings.trim_space(line)
    if trimmed == "quit" || trimmed == "exit" do break

    pos := 0
    for {
      code, next_pos, error := parse_code(line, pos)
      if !error.ok {
        fmt.eprintf("parse error: %s[%d] %s\n", file, error.location, error.message)
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
  if !success do die("I failed to find \"%s\" on your drive. Maybe you need to quote the entire path?\n", file)

  pos := 0
  for {
    code, next_pos, error := parse_code(string(src), pos)
    if !error.ok do die("parse error: %s[%d] %s\n", file, error.location, error.message)
    if code == nil do break
    pos = next_pos
    fmt.printf("%s\n", code_as_string(code))
  }
}

main :: proc() {
  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
