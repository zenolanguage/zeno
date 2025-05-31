package main

import "core:os"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode"

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
    } else if s[p] == '"' {
      p += 1
      for p < u32(len(s)) && (s[p - 1] == '\\' || s[p] != '"') do p += 1
      if p >= u32(len(s)) || s[p] != '"' do return nil, p, {"You have an unterminated string literal.", start, false}
      p += 1
      if len(codes) > 0 do assert(codes[len(codes) - 1].kind == .TUPLE)
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, New(Code{start, .STRING, {as_string=s[start:p]}}))
    } else if unicode.is_digit(rune(s[p])) || (p + 1 < u32(len(s)) && (s[p] == '+' || s[p] == '-') && unicode.is_digit(rune(s[p + 1]))) {
      if s[p] == '+' || s[p] == '-' do p += 1
      for p < u32(len(s)) && unicode.is_digit(rune(s[p])) do p += 1
      if p < u32(len(s)) && s[p] == '.' {
        p += 1
        for p < u32(len(s)) && unicode.is_digit(rune(s[p])) do p += 1
      }
      if len(codes) > 0 do assert(codes[len(codes) - 1].kind == .TUPLE)
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, New(Code{start, .NUMBER, {as_number=strconv.atof(s[start:p])}}))
    } else {
      for p < u32(len(s)) && !strings.is_space(rune(s[p])) && s[p] != '(' && s[p] != ')' && s[p] != ';' do p += 1
      if len(codes) > 0 do assert(codes[len(codes) - 1].kind == .TUPLE)
      append(&codes[len(codes) - 1].as_tuple if len(codes) > 0 else &codes, New(Code{start, .IDENTIFIER if s[start] != '#' else .KEYWORD, {as_string=s[start:p]}}))
    }

    if p < u32(len(s)) && s[p - 1] != '(' && !strings.is_space(rune(s[p])) && s[p] != ')' && s[p] != ';' {
      return nil, p, {"You have two or more conjoined expressions without whitespace between them.", start, false}
    }

    if level == 0 do break
  }
  if level != 0 do return nil, p, {"You have an unclosed parentheses pair.", p, false}
  assert(len(&codes) <= 1)
  return pop(&codes) if len(codes) > 0 else nil, p, {ok=true}
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

Type_Kind :: enum {
  TYPE,
  CODE,
  ANY,
  VOID,
  PROCEDURE,
}

Type :: struct {
  kind: Type_Kind,
}

Type_Procedure :: struct {
  using base: Type,
  return_type: ^Type,
  parameter_types: []^Type,
  is_macro: bool,
}

type_type: ^Type
type_code: ^Type
type_any: ^Type
type_void: ^Type
type_procedures: [dynamic]Type_Procedure

init_global_types :: proc() {
  type_type = New(Type{.TYPE})
  type_code = New(Type{.CODE})
  type_any = New(Type{.ANY})
  type_void = New(Type{.VOID})
}

get_procedure_type :: proc(return_type: ^Type, parameter_types: []^Type, is_macro := false) -> ^Type_Procedure {
  key := Type_Procedure{{.PROCEDURE}, return_type, parameter_types, is_macro}
  for &type_procedure in type_procedures {
    if type_procedure.return_type != key.return_type do continue
    for parameter_type, i in type_procedure.parameter_types do if parameter_type != key.parameter_types[i] do continue
    if type_procedure.is_macro != key.is_macro do continue
    return &type_procedure
  }
  append(&type_procedures, key)
  return &type_procedures[len(type_procedures) - 1]
}

type_as_string :: proc(type: ^Type) -> string {
  if type.kind == .TYPE do return "($type ($code TYPE))"
  if type.kind == .CODE do return "($type ($code CODE))"
  if type.kind == .VOID do return "($type ($code VOID))"
  if type.kind == .PROCEDURE {
    type_proc := cast(^Type_Procedure) type
    b := strings.builder_make_none(context.temp_allocator)
    fmt.sbprintf(&b, "($type ($code PROCEDURE) ($code (")
    for type2, i in type_proc.parameter_types do fmt.sbprintf(&b, "($insert \"%%\" %s)%s", type_as_string(type2), " " if i != len(type_proc.parameter_types) - 1 else "")
    fmt.sbprintf(&b, ")) ")
    fmt.sbprintf(&b, type_as_string(type_proc.return_type))
    fmt.sbprintf(&b, " #is_macro ($cast ($type ($code BOOL)) %d)", 1 if type_proc.is_macro else 0)
    fmt.sbprintf(&b, ")")
    return strings.to_string(b)
  }
  die("unimplemented %s\n", type.kind)
}

Value :: struct {
  type: ^Type,
  using data: struct #raw_union {
    as_type: ^Type,
    as_code: ^Code,
    as_procedure: proc(args: []^Value, calling_env: ^Env) -> (^Value, Evaluation_Error),
  },
}

value_void: ^Value

init_global_values :: proc() {
  value_void = New(Value{type_void, {}})
}

Env_Entry :: struct {
  value: ^Value,
}

Env :: struct {
  parent: ^Env,
  table: map[string]Env_Entry,
}

env_find :: proc(env: ^Env, key: string) -> ^Env_Entry {
  if key in env.table do return &env.table[key]
  if env.parent != nil do return env_find(env.parent, key)
  return nil
}

Evaluation_Error :: struct {
  message: string,
  offending_code: ^Code,
  ok: bool,
}

evaluate_code :: proc(code: ^Code, env: ^Env) -> (^Value, Evaluation_Error) {
  switch code.kind {
    case .IDENTIFIER:
      entry := env_find(env, code.as_string)
      if entry == nil do return nil, {fmt.tprintf("I failed to find \"%s\" in the environment.", code.as_string), code, false}
      return entry.value, {ok=true}
    case .KEYWORD:
      return New(Value{type_code, {as_code=code}}), {ok=true}
    case .NUMBER: die("NUMBER unimplemented.\n")
    case .STRING: die("STRING unimplemented.\n")
    case .TUPLE:
      op_code, arg_codes := code.as_tuple[0], code.as_tuple[1:]
      op, err := evaluate_code(op_code, env)
      if !err.ok do return nil, err
      if op.type.kind != .PROCEDURE do return nil, {fmt.tprintf("You tried to call \"%s\", but this was not a procedure.", code_as_string(op_code)), op_code, false}
      type_proc := cast(^Type_Procedure) op.type
      // TODO: allow varargs
      if len(arg_codes) != len(type_proc.parameter_types) {
        return nil, {fmt.tprintf("You tried to call \"%s\" with %d argument%s, but it expected %d argument%s.", code_as_string(op_code), len(arg_codes), "s" if len(arg_codes) != 1 else "", len(type_proc.parameter_types), "s" if len(type_proc.parameter_types) != 1 else ""), op_code, false}
      }
      args: [dynamic]^Value
      defer delete(args)
      for arg_code, i in arg_codes {
        if type_proc.is_macro && type_proc.parameter_types[i] == type_code do append(&args, New(Value{type_code, {as_code=arg_code}}))
        else {
          arg, err := evaluate_code(arg_code, env)
          if !err.ok {
            if err.offending_code == nil do err.offending_code = arg_code
            return nil, err
          }
          append(&args, arg)
        }
      }
      result, err2 := op.as_procedure(args[:], env)
      if !err2.ok do return nil, err2
      if type_proc.is_macro && type_proc.return_type == type_code && op != default_env.table["$code"].value {
        result2, err := evaluate_code(result.as_code, env)
        if !err.ok do return nil, err
        result = result2
      }
      return result, {ok=true}
  }
  die("You shouldn't have gotten here. (compiler bug)\n")
}

value_as_string :: proc(value: ^Value) -> string {
  if value.type == type_type do return type_as_string(value.as_type)
  if value.type == type_code do return code_as_string(value.as_code)
  if value.type == type_void do return "($cast ($type ($code VOID)) 0)"
  if value.type.kind == .PROCEDURE {
    type_proc := cast(^Type_Procedure) value.type
    b := strings.builder_make_none(context.temp_allocator)
    fmt.sbprintf(&b, "($proc (")
    for type2, i in type_proc.parameter_types do fmt.sbprintf(&b, "%s%s", type_as_string(type2), " " if i != len(type_proc.parameter_types) - 1 else "")
    fmt.sbprintf(&b, ") ")
    fmt.sbprintf(&b, type_as_string(type_proc.return_type))
    fmt.sbprintf(&b, " #is_macro ($cast ($type ($code BOOL)) %d)", 1 if type_proc.is_macro else 0)
    fmt.sbprintf(&b, " TODO.body)")
    return strings.to_string(b)
  }
  die("Unimplemented %s\n", value.type.kind)
}

builtin_code :: proc(args: []^Value, calling_env: ^Env) -> (^Value, Evaluation_Error) {
  return args[0], {ok=true}
}

default_env: Env

init_default_env :: proc() {
  default_env.table["$code"] = {New(Value{get_procedure_type(type_code, {type_code}, is_macro=true), {as_procedure=builtin_code}})}
}

repl :: proc() {
  file := "repl"
  buf: [1024]u8 = ---
  env := Env{parent=&default_env}
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
      // fmt.printf("%s\n", code_as_string(code)) // NOTE: for debugging parser
      result, err2 := evaluate_code(code, &env)
      if !err2.ok {
        fmt.eprintf("%s[%d] %s\n", file, err2.offending_code.location, err2.message)
        break
      }
      if result != value_void do fmt.printf("%s\n", value_as_string(result))
    }
  }
}

compile :: proc(file: string) {
  src, success := os.read_entire_file(file)
  if !success do die("I failed to read \"%s\" from your drive. Maybe you need to quote the entire path?\n", file)

  pos: u32 = 0
  env := Env{parent=&default_env}
  for {
    free_all(context.temp_allocator)

    code, next_pos, err := parse_code(string(src), pos)
    if !err.ok do die("%s\n", err.message)
    if code == nil do break
    pos = next_pos
    result, err2 := evaluate_code(code, &env)
    if !err2.ok do die("%s[%d] %s\n", file, err2.offending_code.location, err2.message)
  }
}

main :: proc() {
  init_global_temporary_allocator(8096)
  init_global_types()
  init_global_values()
  init_default_env()

  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
