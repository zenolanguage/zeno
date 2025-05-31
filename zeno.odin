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
  NULL,
  VOID,
  BOOL,
  COMPTIME_NUMBER,
  INTEGER,
  POINTER,
  ARRAY,
  PROCEDURE,
}

Type :: struct {
  kind: Type_Kind,
}

Type_Integer :: struct {
  using base: Type,
  bits: u8,
  signed: bool,
}

Type_Pointer_Kind :: enum {
  ONE,
  MANY,
  SLICE,
}

Type_Pointer :: struct {
  using base: Type,
  pointer_kind: Type_Pointer_Kind,
  child: ^Type,
  sentinel: ^Value,
}

Type_Array :: struct {
  using base: Type,
  child: ^Type,
  count: uintptr,
  sentinel: ^Value,
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
type_null: ^Type
type_void: ^Type
type_bool: ^Type
type_comptime_number: ^Type
type_u8: ^Type
type_pointers: [dynamic]Type_Pointer
type_arrays: [dynamic]Type_Array
type_procedures: [dynamic]Type_Procedure

init_global_types :: proc() {
  type_type = New(Type{.TYPE})
  type_code = New(Type{.CODE})
  type_any = New(Type{.ANY})
  type_null = New(Type{.NULL})
  type_void = New(Type{.VOID})
  type_bool = New(Type{.BOOL})
  type_comptime_number = New(Type{.COMPTIME_NUMBER})
  type_u8 = New(Type_Integer{{.INTEGER}, 8, false})
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

get_array_type :: proc(child: ^Type, count: uintptr, sentinel: ^Value = nil) -> ^Type_Array {
  key := Type_Array{{.ARRAY}, child, count, sentinel}
  for &type_array in type_arrays {
    if type_array.child != key.child do continue
    if type_array.count != key.count do continue
    if is_equal(type_array.sentinel, key.sentinel) do continue
    return &type_array
  }
  append(&type_arrays, key)
  return &type_arrays[len(type_arrays) - 1]
}

get_pointer_type :: proc(kind: Type_Pointer_Kind, child: ^Type, sentinel: ^Value = nil) -> ^Type_Pointer {
  key := Type_Pointer{{.POINTER}, kind, child, sentinel}
  for &type_pointer in type_pointers {
    if type_pointer.kind != key.kind do continue
    if type_pointer.child != key.child do continue
    if is_equal(type_pointer.sentinel, key.sentinel) do continue
    return &type_pointer
  }
  append(&type_pointers, key)
  return &type_pointers[len(type_pointers) - 1]
}

type_as_string :: proc(type: ^Type) -> string {
  if type.kind == .TYPE do return "($type ($code TYPE))"
  if type.kind == .CODE do return "($type ($code CODE))"
  if type.kind == .VOID do return "($type ($code VOID))"
  if type.kind == .BOOL do return "($type ($code BOOL))"
  if type.kind == .COMPTIME_NUMBER do return "($type ($code COMPTIME_NUMBER))"
  if type.kind == .INTEGER {
    type_integer := cast(^Type_Integer) type
    return fmt.tprintf("($type ($code INTEGER) #bits %d #signed ($cast ($type ($code BOOL)) %d))", type_integer.bits, 1 if type_integer.signed else 0)
  }
  if type.kind == .POINTER {
    type_pointer := cast(^Type_Pointer) type
    b := strings.builder_make_none(context.temp_allocator)
    fmt.sbprintf(&b, "($type ($code POINTER) #pointer_kind ")
    switch type_pointer.pointer_kind {
      case .ONE: fmt.sbprintf(&b, "($code ONE)")
      case .MANY: fmt.sbprintf(&b, "($code MANY)")
      case .SLICE: fmt.sbprintf(&b, "($code SLICE)")
    }
    fmt.sbprintf(&b, " #child %s", type_as_string(type_pointer.child))
    if type_pointer.sentinel != nil {
      fmt.sbprintf(&b, " #sentinel %s", value_as_string(type_pointer.sentinel))
    }
    fmt.sbprintf(&b, ")")
    return strings.to_string(b)
  }
  if type.kind == .ARRAY {
    type_array := cast(^Type_Array) type
    b := strings.builder_make_none(context.temp_allocator)
    fmt.sbprintf(&b, "($type ($code ARRAY) #child %s #count %d", type_as_string(type_array.child), type_array.count)
    if type_array.sentinel != nil {
      fmt.sbprintf(&b, " #sentinel %s", value_as_string(type_array.sentinel))
    }
    fmt.sbprintf(&b, ")")
    return strings.to_string(b)
  }
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
  die("unimplemented str(%s)\n", type.kind)
}

is_coercible :: proc(from, to: ^Type) -> bool {
  if from == to do return true
  return false
}

Value :: struct {
  type: ^Type,
  using data: struct #raw_union {
    as_type: ^Type,
    as_code: ^Code,
    as_comptime_number: f64,
    as_pointer: rawptr,
    as_slice: []u8,
    as_procedure: proc(args: []^Value, calling_env: ^Env) -> (^Value, Evaluation_Error),
  },
}

value_void: ^Value
value_true: ^Value
value_false: ^Value
value_null: ^Value

init_global_values :: proc() {
  value_void = New(Value{type_void, {}})
  value_true = New(Value{type_bool, {}})
  value_false = New(Value{type_bool, {}})
  value_null = New(Value{type_null, {}})
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
    case .NUMBER:
      return New(Value{type_comptime_number, {as_comptime_number=code.as_number}}), {ok=true}
    case .STRING:
      return New(Value{get_pointer_type(.ONE, get_array_type(type_u8, uintptr(len(code.as_string) - 2), New(Value{type_comptime_number, {as_comptime_number=0}}))), {as_pointer=raw_data(code.as_string[1:])}}), {ok=true}
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
      // TODO: handle keyword arguments
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
      if !is_coercible(result.type, type_proc.return_type) do return nil, {fmt.tprintf("Returned value of type \"%s\" was not coercible to return type \"%s\".", type_as_string(result.type), type_as_string(type_proc.return_type)), op_code, false}
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
  if value.type == type_comptime_number {
    buf, err := new([32]u8, context.temp_allocator)
    assert(err == nil)
    return strconv.ftoa(buf[:], value.as_comptime_number, 'f', 8, 64)
  }
  if value.type.kind == .POINTER {
    type_pointer := cast(^Type_Pointer) value.type
    if type_pointer.pointer_kind == .ONE && type_pointer.child.kind == .ARRAY {
      type_array := cast(^Type_Array) type_pointer.child
      if type_array.child == type_u8 {
        return fmt.tprintf("\"%s\"", strings.string_from_ptr(cast([^]u8) value.as_pointer, int(type_array.count)))
      }
    }
  }
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
  die("Unimplemented str(%s)\n", value.type.kind)
}

is_equal :: proc(a, b: ^Value) -> bool {
  if a.type.kind == .COMPTIME_NUMBER && b.type.kind == .COMPTIME_NUMBER do return a.as_comptime_number == b.as_comptime_number
  die("unimplemented %s == %s\n", a.type.kind, b.type.kind)
}

builtin_define :: proc(args: []^Value, calling_env: ^Env) -> (^Value, Evaluation_Error) {
  name, value := args[0], args[1]
  if name.as_code.kind != .IDENTIFIER do return nil, {"$define expects a Code.IDENTIFIER as its first argument.", name.as_code, false}
  if name.as_code.as_string in calling_env.table do return nil, {"$define is not allowed to redefine a variable in the same scope.", name.as_code, false}
  calling_env.table[name.as_code.as_string] = Env_Entry{value}
  return value_void, {ok=true}
}

builtin_code :: proc(args: []^Value, calling_env: ^Env) -> (^Value, Evaluation_Error) {
  return args[0], {ok=true}
}

builtin_type_of :: proc(args: []^Value, calling_env: ^Env) -> (^Value, Evaluation_Error) {
  return New(Value{type_type, {as_type=args[0].type}}), {ok=true}
}

default_env: Env

init_default_env :: proc() {
  default_env.table["$define"] = {New(Value{get_procedure_type(type_void, {type_code, type_any}), {as_procedure=builtin_define}})}
  default_env.table["$code"] = {New(Value{get_procedure_type(type_code, {type_code}, is_macro=true), {as_procedure=builtin_code}})}
  default_env.table["$type-of"] = {New(Value{get_procedure_type(type_type, {type_any}), {as_procedure=builtin_type_of}})}
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
