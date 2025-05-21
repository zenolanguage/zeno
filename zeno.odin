package main

import "core:os"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:strconv"

New :: proc(init: $T, allocator := context.allocator, loc := #caller_location) -> ^T {
  result := new(T, allocator, loc)
  result^ = init
  return result
}

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

Type_Kind :: enum {
  TYPE,
  CODE,
  NULL,
  NORETURN,
  VOID,
  BOOL,
  ANYOPAQUE,
  COMPTIME_INTEGER,
  COMPTIME_FLOAT,
  INTEGER,
  POINTER,
  ARRAY,
  PROCEDURE,
  MACRO,
}

Type :: struct {
  kind: Type_Kind,
}

Type_Integer :: struct {
  using base: Type,
  bits: u16,
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

Type_Array_Kind :: enum {
  STATIC,
  DYNAMIC,
}

Type_Array :: struct {
  using base: Type,
  array_kind: Type_Array_Kind,
  child: ^Type,
  count: uintptr,
  sentinel: ^Value,
}

Type_Procedure :: struct {
  using base: Type,
  parameter_types: []^Type,
  return_type: ^Type,
  is_varargs: bool,
}

Type_Macro :: struct {
  using base: Type,
  parameter_types: []^Type,
  return_type: ^Type,
  is_varargs: bool,
}

type_type: ^Type
type_code: ^Type
type_void: ^Type
type_comptime_int: ^Type
type_comptime_float: ^Type
type_u8: ^Type_Integer
type_pointers: [dynamic]^Type_Pointer
type_arrays: [dynamic]^Type_Array
type_macros: [dynamic]^Type_Macro

type_string: ^Type

init_global_types :: proc() {
  type_type = New(Type{kind = .TYPE})
  type_code = New(Type{kind = .CODE})
  type_void = New(Type{kind = .VOID})
  type_comptime_int = New(Type{kind = .COMPTIME_INTEGER})
  type_comptime_float = New(Type{kind = .COMPTIME_FLOAT})
  type_u8 = New(Type_Integer{kind = .INTEGER, bits = 8, signed = false})

  type_string = get_pointer_type(.SLICE, type_u8)
}

get_pointer_type :: proc(pointer_kind: Type_Pointer_Kind, child: ^Type, sentinel: ^Value = nil) -> ^Type_Pointer {
  // TODO(dfra): check contents of sentinel instead of address? Or have a constant intern store as well?
  for type in type_pointers {
    if type.pointer_kind == pointer_kind && type.child == child && type.sentinel == sentinel {
      return type
    }
  }
  append(&type_pointers, New(Type_Pointer{kind = .POINTER, pointer_kind = pointer_kind, child = child, sentinel = sentinel}))
  return type_pointers[len(type_pointers) - 1]
}

get_array_type :: proc(array_kind: Type_Array_Kind, child: ^Type, count: uintptr = 0, sentinel: ^Value = nil) -> ^Type_Array {
  // TODO(dfra): check contents of sentinel instead of address? Or have a constant intern store as well?
  for type in type_arrays {
    if type.array_kind == array_kind && type.child == child && type.count == count && type.sentinel == sentinel {
      return type
    }
  }
  append(&type_arrays, New(Type_Array{kind = .ARRAY, array_kind = array_kind, child = child, count = count, sentinel = sentinel}))
  return type_arrays[len(type_arrays) - 1]
}

get_macro_type :: proc(parameter_types: []^Type, return_type: ^Type, is_varargs: bool) -> ^Type_Macro {
  for type in type_macros {
    if len(type.parameter_types) != len(parameter_types) do continue
    for v in soa_zip(a=type.parameter_types, b=parameter_types) do if v.a != v.b do continue
    if type.return_type == return_type && type.is_varargs == is_varargs do return type
  }
  append(&type_macros, New(Type_Macro{kind = .MACRO, parameter_types = parameter_types, return_type = return_type}))
  return type_macros[len(type_macros) - 1]
}

type_as_string :: proc(type: ^Type) -> string {
  switch type.kind {
    case .TYPE: return "($type ($code TYPE))"
    case .CODE: return "($type ($code CODE))"
    case .NULL: return "($type ($code NULL))"
    case .NORETURN: return "($type ($code NORETURN))"
    case .VOID: return "($type ($code VOID))"
    case .BOOL: return "($type ($code BOOL))"
    case .ANYOPAQUE: return "($type ($code ANYOPAQUE))"
    case .COMPTIME_INTEGER: return "($type ($code COMPTIME_INTEGER))"
    case .COMPTIME_FLOAT: return "($type ($code COMPTIME_FLOAT))"
    case .INTEGER: return fmt.tprintf("($type ($code INTEGER) ($code #bits %d $signed %s))", (^Type_Integer)(type).bits, "true" if (^Type_Integer)(type).signed else "false")
    case .POINTER: return fmt.tprintf("($type ($code POINTER) ($code #pointer_kind ($code %s) #child %s $sentinel %s))", (^Type_Pointer)(type).pointer_kind, type_as_string((^Type_Pointer)(type).child), value_as_string((^Type_Pointer)(type).sentinel) if (^Type_Pointer)(type).sentinel != nil else "($cast ($type ($code NULL)) 0)")
    case .ARRAY: return fmt.tprintf("($type ($code ARRAY) ($code #array_kind ($code %s) #child %s #count %d $sentinel %s))", (^Type_Array)(type).array_kind, type_as_string((^Type_Array)(type).child), (^Type_Array)(type).count, value_as_string((^Type_Array)(type).sentinel) if (^Type_Array)(type).sentinel != nil else "($cast ($type ($code NULL)) 0)")
    // TODO(dfra): handle parameters and is_varargs
    case .PROCEDURE: return fmt.tprintf("($type ($code PROCEDURE) #parameters ... #return %s)", type_as_string((^Type_Procedure)(type).return_type))
    case .MACRO: return fmt.tprintf("($type ($code MACRO) #parameters ... #return %s)", type_as_string((^Type_Procedure)(type).return_type))
  }
  assert(false, "unimplemented")
  return ""
}

Value :: struct {
  type: ^Type,
  using data: struct #raw_union {
    as_type: ^Type,
    as_code: ^Code,
    as_comptime_int: int,
    as_comptime_float: f64,
    as_pointer: rawptr,
    as_slice: []byte,
    as_procedure: proc(calling_code: ^Code, env: ^Env, values: ..^Value) -> (^Value, Evaluation_Error),
  },
}

value_void: ^Value

init_global_values :: proc() {
  value_void = New(Value{type = type_void})
}

cast_value :: proc(value: ^Value, type: ^Type) -> (casted: ^Value, success: bool, was_implicitly_possible: bool) {
  from, to := value.type, type
  if from == to do return value, true, true
  if from.kind == .POINTER && to.kind == .POINTER {
    from_pointer := (^Type_Pointer)(from)
    to_pointer := (^Type_Pointer)(to)
    if from_pointer.pointer_kind == .ONE && from_pointer.child.kind == .ARRAY && to_pointer.pointer_kind == .SLICE {
      from_pointer_child_array := (^Type_Array)(from_pointer.child)
      if from_pointer_child_array.child == to_pointer.child {
        new_value := New(Value{type = to, as_slice = slice.bytes_from_ptr(value.as_pointer, int(from_pointer_child_array.count))})
        return new_value, true, true
      }
    }
  }
  return nil, false, false
}

Env_Entry :: struct {
  value: ^Value,
}

Env :: struct {
  parent: ^Env,
  table: map[string]Env_Entry,
}

default_env: Env

init_default_env :: proc() {
  default_env.table["$code"] = Env_Entry{value = New(Value{type = get_macro_type({type_code}, type_code, false), as_procedure = proc(calling_code: ^Code, env: ^Env, values: ..^Value) -> (^Value, Evaluation_Error) {
      return values[0], {ok = true}
    }})
  }
  default_env.table["$insert"] = Env_Entry{value = New(Value{type = get_macro_type({type_string}, type_code, true), as_procedure = proc(calling_code: ^Code, env: ^Env, values: ..^Value) -> (^Value, Evaluation_Error) {
      b: strings.Builder
      format := string(values[0].as_slice)
      fmt.printf("Format `%s`\n", format)
      i := 0
      argi := 1
      for i < len(format) {
        if format[i] == '%' {
          if i + 1 < len(format) && format[i + 1] != '%' {
            if argi >= len(values) do return nil, {"I expected an argument based on your format string but didn't receive one.", calling_code, false}
            fmt.sbprintf(&b, "%s", code_as_string(values[argi].as_code))
            i += 1
            argi += 1
            continue
          }
          i += 1
        }
        fmt.sbprintf(&b, "%c", format[i])
        i += 1
      }
      if argi != len(values) do return nil, {"You gave me more arguments than your format string specified.", calling_code, false}
      src := strings.to_string(b)
      code, next_pos, error := parse_code(src, 0, no_implicit_parentheses = true)
      if !error.ok do return nil, {error.message, calling_code, false}
      {
        code, next_pos, error := parse_code(src, next_pos, no_implicit_parentheses = true)
        if code != nil do return nil, {"I found multiple expressions in $insert, but only one was expected.", calling_code, false}
      }
      if code == nil do return nil, {"$insert expects one expression, but you gave me zero.", calling_code, false}
      return New(Value{type = type_code, as_code = code}), {ok = true}
    }})
  }
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
      return entry.value, {ok = true}
    case .KEYWORD:
      return New(Value{type = type_code, as_code = code}), {ok = true}
    case .INTEGER:
      return New(Value{type = type_comptime_int, as_comptime_int = code.as_integer}), {ok = true}
    case .FLOAT:
      return New(Value{type = type_comptime_float, as_comptime_float = code.as_float}), {ok = true}
    case .STRING:
      return New(Value{type = get_pointer_type(.ONE, get_array_type(.STATIC, type_u8, uintptr(len(code.as_string) - 2), sentinel = New(Value{type = type_comptime_int, as_comptime_int = 0}))), as_pointer = raw_data(code.as_string[1:])}), {ok = true}
    case .TUPLE:
      if len(code.as_tuple) == 0 do return nil, {fmt.tprintf("You tried to call a procedure but didn't give me its name."), code, false}
      op_code, arg_codes := code.as_tuple[0], code.as_tuple[1:]
      op, error := evaluate_code(op_code, env)
      if !error.ok do return nil, error
      if op.type.kind != .PROCEDURE && op.type.kind != .MACRO do return nil, {"You tried to call something that wasn't a procedure or a macro.", op_code, false}
      args: [dynamic]^Value
      defer delete(args)
      for arg_code, i in arg_codes {
        if op.type.kind == .MACRO && ((^Type_Macro)(op.type).parameter_types[i] == type_code if i < len((^Type_Macro)(op.type).parameter_types) else (^Type_Macro)(op.type).is_varargs) {
          append(&args, New(Value{type = type_code, as_code = arg_code}))
          continue
        }
        arg, error := evaluate_code(arg_code, env)
        if !error.ok do return nil, error
        if i >= len((^Type_Procedure)(op.type).parameter_types if op.type.kind == .PROCEDURE else (^Type_Macro)(op.type).parameter_types) {
          return nil, {"You tried to call a procedure or macro with the incorrect arity.", arg_code, false}
        }
        check_against_type := (^Type_Procedure)(op.type).parameter_types[i] if op.type.kind == .PROCEDURE else (^Type_Macro)(op.type).parameter_types[i]
        casted, success, was_implicitly_possible := cast_value(arg, check_against_type)
        if !was_implicitly_possible do return nil, {fmt.tprintf("I am not allowed to implicitly cast from type \"%s\" to type \"%s\".", type_as_string(arg.type), type_as_string(check_against_type)), arg_code, false}
        append(&args, casted)
      }
      if op.type.kind == .MACRO {
        value, error := op.as_procedure(op_code, env, ..args[:])
        if !error.ok do return nil, error
        if op.as_procedure == default_env.table["$code"].value.as_procedure {
          return value, {ok = true}
        } else {
          return evaluate_code(value.as_code, env)
        }
      } else {
        return op.as_procedure(op_code, env, ..args[:])
      }
  }
  return nil, {"How did we get here? (compiler bug)", code, false}
}

value_as_string :: proc(value: ^Value) -> string {
  if value.type == type_type do return type_as_string(value.as_type)
  if value.type == type_code do return code_as_string(value.as_code)
  if value.type == type_comptime_int do return fmt.tprintf("%d", value.as_comptime_int)
  if value.type.kind == .POINTER {
    return fmt.tprintf("($cast ($type ($code POINTER) #pointer_kind ($code ONE) #child ($type ($code ANYOPAQUE))) %x)", value.as_pointer)
  }
  fmt.panicf("Unimplemented %s\n", type_as_string(value.type))
}

repl :: proc() {
  file := "repl"
  line_buffer: [256]u8 = ---
  env := Env{parent = &default_env}
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
        fmt.eprintf("%s[%d] parse error: %s\n", file, error.location, error.message)
        break
      }
      if code == nil do break
      pos = next_pos
      // fmt.printf("%s\n", code_as_string(code))
      {
        value, error := evaluate_code(code, &env)
        if !error.ok {
          fmt.eprintf("%s[%d] evaluation error: %s\n", file, error.offending_code.location, error.message)
          break
        }
        fmt.printf("%s\n", value_as_string(value))
      }
    }
  }
}

compile :: proc(file: string) {
  src, success := os.read_entire_file(file)
  if !success do die("I failed to find \"%s\" on your drive. Maybe you need to quote the entire path?\n", file)

  env := Env{parent = &default_env}
  pos := 0
  for {
    code, next_pos, error := parse_code(string(src), pos)
    if !error.ok do die("%s[%d] parse error: %s\n", file, error.location, error.message)
    if code == nil do break
    pos = next_pos
    {
      value, error := evaluate_code(code, &env)
      if !error.ok {
        fmt.eprintf("%s[%d] evaluation error: %s\n", file, error.offending_code.location, error.message)
        break
      }
    }
  }
}

main :: proc() {
  init_global_types()
  init_global_values()
  init_default_env()

  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
