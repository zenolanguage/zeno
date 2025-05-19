package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"

die :: proc(format: string, args: ..any) -> ! {
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

parse_code :: proc(s: string, p: int, file: string) -> (^Code, int) {
  p := p
  indents: [dynamic]int
  defer delete(indents)
  implicitnesses: [dynamic]bool
  defer delete(implicitnesses)
  codes: [dynamic]^Code
  defer delete(codes)

  for {
    start := p
    newline_was_skipped := false
    beginning_of_line := p
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
      if s[p] != '(' && s[p] != ')' {
        append(&implicitnesses, true)
        tuple := new(Code)
        tuple.location = p
        tuple.kind = .TUPLE
        append(&codes, tuple)
      }
    }

    start = p
    explicitly_closed_top_level := false
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
        if len(codes) > 1 {
          popped := pop(&codes)
          append(&codes[len(codes) - 1].as_tuple, popped)
        }
      }

      if len(implicitnesses) == 0 {
        fmt.eprintf("%s[%d] You have an extraneous closing parenthesis.\n", file, start)
        return nil, p
      }
      pop(&implicitnesses)
      explicitly_closed_top_level = len(implicitnesses) == 0
      if len(codes) > 1 {
        popped := pop(&codes)
        append(&codes[len(codes) - 1].as_tuple, popped)
      }
    } else if s[p] == '\'' {
      p += 1
      code, next_pos := parse_code(s, p, file)
      if code == nil {
        fmt.eprintf("%s[%d] You attempted to take the $code of nothing.\n", file, start)
        return nil, p
      }
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
      code, next_pos := parse_code(s, p, file)
      if code == nil {
        fmt.eprintf("%s[%d] You attempted to $insert nothing.\n", file, start)
        return nil, p
      }
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
    } else if s[p] == '"' {
      p += 1
      for p < len(s) && (s[p - 1] == '\\' || s[p] != '"') do p += 1
      if p >= len(s) || s[p] != '"' {
        fmt.eprintf("%s[%d] You have an unterminated string literal.\n", file, start)
        return nil, p
      }
      p += 1
      string_ := new(Code)
      string_.location = start
      string_.kind = .STRING
      string_.as_string = s[start:p]
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, string_)
    } else if s[p] >= '0' && s[p] <= '9' {
      for p < len(s) && (s[p] >= '0' && s[p] <= '9') do p += 1
      if p < len(s) && s[p] == '.' {
        p += 1
        for p < len(s) && (s[p] >= '0' && s[p] <= '9') do p += 1
        float_ := new(Code)
        float_.location = start
        float_.kind = .FLOAT
        float_.as_float = strconv.atof(s[start:p])
        append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, float_)
      } else {
        integer := new(Code)
        integer.location = start
        integer.kind = .INTEGER
        integer.as_integer = strconv.atoi(s[start:p])
        append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, integer)
      }
    } else {
      for p < len(s) && !strings.is_space(rune(s[p])) && s[p] != '(' && s[p] != ')' && s[p] != ';' do p += 1
      identifier := new(Code)
      identifier.location = start
      identifier.kind = .IDENTIFIER if s[start] != '#' else .KEYWORD
      identifier.as_string = s[start:p]
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, identifier)
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
    next_indent := peek - beginning_of_next_line
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

    if len(implicitnesses) == 0 && (explicitly_closed_top_level || (len(indents) == 0 || next_indent <= indents[0])) do break
  }
  if len(implicitnesses) != 0 {
    fmt.eprintf("%s[%d] You are missing a closing parenthesis.\n", file, p)
    return nil, p
  }
  assert(len(codes) <= 1)
  return pop(&codes) if len(codes) > 0 else nil, p
}

code_as_string :: proc(code: ^Code) -> string {
  switch code.kind {
    case .IDENTIFIER: fallthrough
    case .KEYWORD: fallthrough
    case .STRING: return code.as_string
    case .INTEGER:
      buf := new([8]byte)
      return strconv.append_int(buf[:], i64(code.as_integer), 10)
    case .FLOAT:
      buf := new([8]byte)
      return strconv.append_float(buf[:], code.as_float, 'f', 2, 64)
    case .TUPLE:
      b: strings.Builder
      fmt.sbprintf(&b, "(")
      for c, i in code.as_tuple {
        fmt.sbprintf(&b, "%s%s", code_as_string(c), " " if i != len(code.as_tuple) - 1 else "")
      }
      fmt.sbprintf(&b, ")")
      return strings.to_string(b)
  }
  assert(false)
  return ""
}

Type_Kind :: enum {
  TYPE,
  CODE,
  NULL,
  NORETURN,
  VOID,
  BOOL,
  ANYTYPE,
  ANYOPAQUE,
  ANYERROR,
  COMPTIME_INTEGER,
  COMPTIME_FLOAT,
  ERROR_SET,
  ERROR_UNION,
  INTEGER,
  FLOAT,
  OPTIONAL,
  POINTER,
  ARRAY,
  MATRIX,
  MAP,
  STRUCT,
  UNION,
  ENUM,
  PROCEDURE,
}

Type :: struct {
  kind: Type_Kind,
}

Value :: struct {
  type: ^Type,
  using data: struct #raw_union {
    as_code: ^Code,
    as_type: ^Type,
  },
}

Env_Entry :: struct {
  value: ^Value,
}

Env :: struct {
  parent: ^Env,
  table: map[string]Env_Entry,
}

Evaluation_Error :: enum {
  NONE = 0,
}

evaluate_code :: proc(code: ^Code, env: ^Env, file: string) -> (^Value, Evaluation_Error) {
  assert(false, "Unimplemented.")
  return nil, .NONE
}

repl :: proc() {
  file := "repl"
  line_buffer: [256]u8 = ---
  env: Env
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
        // fmt.printf("%s\n", code_as_string(code))
        value, err := evaluate_code(code, &env, file)
        if err != .NONE do break
        // if value != value_void do fmt.printf("%s\n", value_as_string(value))
      }
    }
  }
}

compile :: proc(file: string) {
  src, success := os.read_entire_file(file)
  if !success do die("I failed to find '%s' on your drive. Maybe you need to quote the entire path?\n", file)

  pos := 0
  env: Env
  for {
    code, next_pos := parse_code(string(src), pos, file)
    if code == nil do break
    pos = next_pos
    value, err := evaluate_code(code, &env, file)
    if err != .NONE {
      fmt.eprintf("%s\n", err)
      break
    }
  }
}

main :: proc() {
  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
