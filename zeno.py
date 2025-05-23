import typing
from dataclasses import dataclass
from enum import IntEnum

class Parse_Error(Exception):
  def __init__(self, message:str, location:int) -> None:
    super().__init__(message)
    self.location = location

class Code_Kind(IntEnum):
  IDENTIFIER = 0
  KEYWORD = 1
  INTEGER = 2
  FLOAT = 3
  STRING = 4
  TUPLE = 5

@dataclass
class Code:
  location: int
  kind: Code_Kind
  data: typing.Union[str, int, float, typing.List["Code"]]

def parse_code(s:str, p:int, no_implicit_parentheses=False) -> typing.Tuple[Code, int]:
  indents = []
  implicitnesses = []
  codes = []
  explicit_new_line_was_closed = False

  while True:
    start = p
    newline_was_skipped = False
    beginning_of_line = start
    while True:
      while p < len(s) and s[p].isspace():
        if s[p] == '\n':
          newline_was_skipped = True
          beginning_of_line = p + 1
        p += 1
      if p < len(s) and s[p] == ';':
        while p < len(s) and s[p] != '\n': p += 1
        continue
      break
    if p >= len(s): break

    indent = p - beginning_of_line
    first_exp_of_line = newline_was_skipped or start == 0
    if first_exp_of_line:
      if len(indents) == 0 or indent > indents[-1]: indents.append(indent)
      if not no_implicit_parentheses and s[p] not in "()":
        implicitnesses.append(True)
        codes.append(Code(start, Code_Kind.TUPLE, []))

    start = p
    if s[p] == '(':
      p += 1
      implicitnesses.append(False)
      codes.append(Code(start, Code_Kind.TUPLE, []))
    elif s[p] == ')':
      p += 1
      if len(implicitnesses) == 0: raise Parse_Error("You have an extraneous closing parenthesis.", p)
      implicitnesses.pop()
      if len(implicitnesses) == 0: explicit_new_line_was_closed = True
      if len(codes) > 1:
        popped = codes.pop()
        (codes[-1].data if len(codes) > 0 else codes).append(popped)
    elif s[p] == "'":
      p += 1
      code, next_pos = parse_code(s, p)
      if code is None: raise Parse_Error("You tried to $quote nothing.", p)
      p = next_pos
      code = Code(start, Code_Kind.TUPLE, [Code(start, Code_Kind.IDENTIFIER, "$quote"), code])
      (codes[-1].data if len(codes) > 0 else codes).append(code)
    elif s[p] == ',':
      p += 1
      code, next_pos = parse_code(s, p)
      if code is None: raise Parse_Error("You tried to $unquote nothing.", p)
      p = next_pos
      code = Code(start, Code_Kind.TUPLE, [Code(start, Code_Kind.IDENTIFIER, "$unquote"), code])
      (codes[-1].data if len(codes) > 0 else codes).append(code)
    elif s[p].isdigit() or (p + 1 < len(s) and s[p] in "+-" and s[p + 1].isdigit()):
      p += 1
      while p < len(s) and s[p].isdigit(): p += 1
      if p >= len(s) or s[p] != '.': (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.INTEGER, int(s[start:p])))
      else:
        p += 1
        while p < len(s) and s[p].isdigit(): p += 1
        (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.FLOAT, float(s[start:p])))
    elif s[p] == '"':
      p += 1
      while p < len(s) and (s[p - 1] == '\\' or s[p] != '"'): p += 1
      if p >= len(s) or s[p] != '"': raise Parse_Error("You have an unterminated string literal.", p)
      p += 1
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.STRING, s[start:p]))
    else:
      while p < len(s) and not s[p].isspace() and s[p] not in "();": p += 1
      code = Code(start, Code_Kind.IDENTIFIER if s[start] != '#' else Code_Kind.KEYWORD, s[start:p])
      (codes[-1].data if len(codes) > 0 else codes).append(code)

    peek = p
    while peek < len(s) and (s[peek].isspace() or s[peek] == ')') and s[peek] != '\n' and s[peek] != ';': peek += 1
    last_exp_of_line = peek >= len(s) or s[peek] in "\n;"
    beginning_of_next_line = peek
    while True:
      while peek < len(s) and s[peek].isspace():
        if s[peek] == '\n':
          newline_was_skipped = True
          beginning_of_next_line = peek + 1
        peek += 1
      if peek < len(s) and s[peek] == ';':
        while peek < len(s) and s[peek] != '\n': peek += 1
        continue
      break
    next_indent = peek - beginning_of_next_line if peek < len(s) else 0

    if last_exp_of_line:
      if len(implicitnesses) > 0 and implicitnesses[-1]: implicitnesses.pop()
      while len(indents) > 0 and next_indent <= indents[-1]:
        indents.pop()
        if len(codes) > 1:
          popped = codes.pop()
          (codes[-1].data if len(codes) > 0 else codes).append(popped)

    if len(implicitnesses) == 0 and (explicit_new_line_was_closed or len(indents) == 0 or next_indent <= indents[0]): break

  if len(implicitnesses) != 0: raise Parse_Error("You are missing a closing parenthesis.", p)

  assert len(indents) <= 1
  assert len(codes) <= 1
  return codes[-1] if len(codes) > 0 else None, p

def code_as_string(code:Code) -> str:
  if code.kind in [Code_Kind.IDENTIFIER, Code_Kind.KEYWORD, Code_Kind.STRING]: return code.data
  if code.kind in [Code_Kind.INTEGER, Code_Kind.FLOAT]: return str(code.data)
  if code.kind == Code_Kind.TUPLE: return "(" + " ".join(map(code_as_string, code.data)) + ")"
  raise NotImplementedError()

class Type_Kind(IntEnum):
  TYPE = 0
  CODE = 1
  NULL = 2
  NORETURN = 3
  VOID = 4
  BOOL = 5
  ANYTYPE = 6
  ANYOPAQUE = 7
  ANYERROR = 8
  COMPTIME_INTEGER = 9
  COMPTIME_FLOAT = 9
  PROCEDURE = 14
  MACRO = 15

@dataclass(frozen=True)
class Type:
  kind: Type_Kind

@dataclass(frozen=True)
class Type_Procedure(Type):
  parameter_types: typing.List[Type]
  return_type: Type
  is_varargs: bool

@dataclass(frozen=True)
class Type_Macro(Type):
  parameter_types: typing.List[Type]
  return_type: Type
  is_varargs: bool

type_type = Type(Type_Kind.TYPE)
type_code = Type(Type_Kind.CODE)
type_null = Type(Type_Kind.NULL)
type_noreturn = Type(Type_Kind.NORETURN)
type_void = Type(Type_Kind.VOID)
type_bool = Type(Type_Kind.BOOL)
type_anytype = Type(Type_Kind.ANYTYPE)
type_comptime_integer = Type(Type_Kind.COMPTIME_INTEGER)
type_comptime_float = Type(Type_Kind.COMPTIME_FLOAT)
type_procedures = {}
type_macros = {}

def get_procedure_type(parameter_types:typing.List[Type], return_type:Type, is_varargs:bool) -> Type:
  key = (tuple(parameter_types),return_type,is_varargs)
  if key not in type_procedures: type_procedures[key] = Type_Procedure(Type_Kind.PROCEDURE, parameter_types, return_type, is_varargs)
  return type_procedures[key]

def get_macro_type(parameter_types:typing.List[Type], return_type:Type, is_varargs:bool) -> Type:
  key = (tuple(parameter_types),return_type,is_varargs)
  if key not in type_macros: type_macros[key] = Type_Macro(Type_Kind.MACRO, parameter_types, return_type, is_varargs)
  return type_macros[key]

def type_as_string(ty:Type) -> str:
  if ty.kind == Type_Kind.TYPE: return "($type ($quote TYPE))"
  if ty.kind == Type_Kind.CODE: return "($type ($quote CODE))"
  if ty.kind == Type_Kind.NULL: return "($type ($quote NULL))"
  if ty.kind == Type_Kind.NORETURN: return "($type ($quote NORETURN))"
  if ty.kind == Type_Kind.VOID: return "($type ($quote VOID))"
  if ty.kind == Type_Kind.BOOL: return "($type ($quote BOOL))"
  if ty.kind == Type_Kind.ANYTYPE: return "($type ($quote ANYTYPE))"
  if ty.kind == Type_Kind.COMPTIME_INTEGER: return "($type ($quote COMPTIME_INTEGER))"
  if ty.kind == Type_Kind.COMPTIME_FLOAT: return "($type ($quote COMPTIME_FLOAT))"
  if ty.kind == Type_Kind.PROCEDURE: return "$(type ($quote PROCEDURE) #parameter_types ... #return_type ... #is_varargs ...)"
  raise NotImplementedError(ty.kind)

@dataclass
class Procedure:
  body: typing.Tuple["Value"]

  def __call__(self, *args: typing.Tuple["Value"], **kwargs) -> "Value":
    env = Env(kwargs["env"], {})
    for code in self.body:
      if code.data.data[0].data == "$return":
        return evaluate_code(code.data.data[1], env)
      evaluate_code(code.data, env)
    return value_void

@dataclass
class Value:
  type: Type
  data: typing.Optional[typing.Union[Type, Code, int, float, str, typing.Callable[..., "Value"], Procedure]]

value_void = Value(type_void, None)
value_true = Value(type_bool, None)
value_false = Value(type_bool, None)

@dataclass
class Env_Entry:
  value: Value

class Env:
  def __init__(self, parent:typing.Optional["Env"], table:typing.Dict[str, Env_Entry]) -> None:
    self.parent = parent
    self.table = table
  def find(self, key:str) -> typing.Optional[Value]:
    if key in self.table: return self.table[key]
    if self.parent is not None: return self.parent.find(key)
    return None

class Evaluation_Error(Exception):
  def __init__(self, message:str, code:Code) -> None:
    super().__init__(message)
    self.message = message
    self.code = code

def evaluate_code(code:Code, env:Env, is_inside_quote=False) -> Value:
  if code.kind != Code_Kind.TUPLE:
    if code.kind == Code_Kind.IDENTIFIER:
      entry = env.find(code.data)
      if entry is None: raise Evaluation_Error(f"I failed to find \"{code.data}\" in the environment.", code)
      return entry.value
    elif code.kind == Code_Kind.KEYWORD:
      return Value(type_code, code)
    elif code.kind == Code_Kind.INTEGER:
      return Value(type_comptime_integer, code.data)
    elif code.kind == Code_Kind.FLOAT:
      return Value(type_comptime_integer, code.data)
    # elif code.kind == Code_Kind.STRING:
    #   return Value(get_pointer_type(Type_Pointer_Kind.ONE, get_array_type(Type_Array_Kind.STATIC, type_u8, count=len(code.data), sentinel=Value(type_comptime_integer, 0))), code.data)
    raise NotImplementedError()
  op_code, *arg_codes = code.data
  op = evaluate_code(op_code, env, is_inside_quote)
  if op.type.kind not in [Type_Kind.PROCEDURE, Type_Kind.MACRO]: raise Evaluation_Error(f"You tried to call something [{code_as_string(op_code)}] that was not a procedure or macro.", op_code)
  if op.type.is_varargs:
    if len(op.type.parameter_types) > len(arg_codes): raise Evaluation_Error(f"Arity mismatch of procedure/macro \"{code_as_string(op_code)}\". Expected at least {len(op.type.parameter_types)} arguments, got {len(arg_codes)}.", op_code)
  else:
    if len(op.type.parameter_types) != len(arg_codes): raise Evaluation_Error(f"Arity mismatch of procedure/macro \"{code_as_string(op_code)}\". Expected {len(op.type.parameter_types)} arguments, got {len(arg_codes)}.", op_code)
  args = [evaluate_code(arg_code, env, is_inside_quote) if op.type.kind == Type_Kind.PROCEDURE or (i < len(op.type.parameter_types) and op.type.parameter_types[i].kind != Type_Kind.CODE) else Value(type_code, arg_code) for i, arg_code in enumerate(arg_codes)]
  for i, arg in enumerate(args):
    if i < len(op.type.parameter_types) and op.type.parameter_types[i].kind != Type_Kind.ANYTYPE and op.type.parameter_types[i] != arg.type: raise Evaluation_Error(f"The procedure/macro \"{code_as_string(op_code)}\" argument {i} expected type \"{type_as_string(op.type.parameter_types[i])}\" but found type \"{type_as_string(arg.type)}\".", op_code)
  result_value = op.data(*args, env=env, is_inside_quote=is_inside_quote)
  # TODO(dfra): this seems a bit hacky. Evaluate + convert to string + reparse feels icky.
  if op == default_env.find("$quote").value:
    def visit(code_value:Value) -> None:
      assert code_value.type == type_code
      code = code_value.data
      if code.kind == Code_Kind.TUPLE:
        for c in code.data: visit(Value(type_code, c))
        if len(code.data) > 0 and evaluate_code(code.data[0], env, is_inside_quote) == default_env.find("$unquote").value:
          new_code, _ = parse_code(value_as_string(evaluate_code(code.data[1], env, is_inside_quote=True)), 0, no_implicit_parentheses=True)
          code.kind = new_code.kind
          code.data = new_code.data
    visit(result_value)
  return evaluate_code(result_value.data, env) if op.type.kind == Type_Kind.MACRO and op.type.return_type == type_code and op != default_env.find("$quote").value else result_value

def value_as_string(value:Value) -> str:
  if value.type.kind == Type_Kind.TYPE: return type_as_string(value.data)
  if value.type.kind == Type_Kind.CODE: return code_as_string(value.data)
  if value.type.kind == Type_Kind.NULL: return f"($cast {type_as_string(type_null)} 0)"
  if value.type.kind == Type_Kind.NORETURN: return f"($cast {type_as_string(type_noreturn)} 0)"
  if value.type.kind == Type_Kind.VOID: return f"($cast {type_as_string(type_void)} 0)"
  if value.type.kind == Type_Kind.BOOL: return f"($cast {type_as_string(type_bool)} {'1' if value == value_true else '0'})"
  if value.type.kind in [Type_Kind.COMPTIME_INTEGER, Type_Kind.COMPTIME_FLOAT]: return str(value.data)
  raise NotImplementedError(value.type.kind)

def define(name:Value, value:Value, **kwargs) -> Value:
  env = kwargs["env"]
  if name.data.kind != Code_Kind.IDENTIFIER: raise Evaluation_Error(f"$define expects an identifier as its first argument.", name.data)
  if name.data.data in env.table: raise Evaluation_Error(f"$define can't redefine \"{name.data.data}\" in the same scope.", name.data)
  env.table[name.data.data] = Env_Entry(value=value)
  return value_void

def quote(code_value:Value, **kwargs) -> Value:
  return code_value

def unquote(code_value:Value, **kwargs) -> Value:
  if not kwargs["is_inside_quote"]: raise Evaluation_Error(f"You can't $unquote outside of a $quote expression.", code_value.data)
  return code_value

def proc(parameters_tuple:Value, return_type:Type, *body, **kwargs) -> Value:
  types = []
  for ty in parameters_tuple.data.data: types.append(True)
  return Value(Type_Procedure(Type_Kind.PROCEDURE, types, return_type, False), Procedure(body))

def type_(type_kind:Value, *args, **kwargs) -> Value:
  assert type_kind.type == type_code
  type_kind = type_kind.data
  if type_kind.kind != Code_Kind.IDENTIFIER: raise Evaluation_Error(f"$type argument 'kind' expects an identifier.", type_kind)
  if type_kind.data == "TYPE": return Value(type_type, type_type)
  if type_kind.data == "VOID": return Value(type_type, type_void)
  if type_kind.data == "NULL": return Value(type_type, type_null)
  if type_kind.data == "COMPTIME_INTEGER": return Value(type_type, type_comptime_integer)
  raise NotImplementedError(type_kind.data)

default_env = Env(None, {
  "$define": Env_Entry(value=Value(get_procedure_type([type_code, type_anytype], type_void, False), define)),
  "$quote": Env_Entry(value=Value(get_macro_type([type_code], type_code, False), quote)),
  "$unquote": Env_Entry(value=Value(get_macro_type([type_code], type_code, False), unquote)),
  "$proc": Env_Entry(value=Value(get_macro_type([type_code, type_type], type_anytype, True), proc)),
  "$type": Env_Entry(value=Value(get_procedure_type([type_code], type_type, True), type_)),
})

def repl() -> None:
  file = "repl"
  env = Env(default_env, {})
  while True:
    try: src = input("> ")
    except (KeyboardInterrupt, EOFError): print(""); exit(0)
    pos = 0
    while True:
      try: code, next_pos = parse_code(src, pos)
      except Parse_Error as e: print(f"{file}[{e.location}] parse error: {e}"); break
      if code is None: break
      pos = next_pos
      # print(code_as_string(code))
      try: value = evaluate_code(code, env)
      except Evaluation_Error as e: print(f"{file}[{e.code.location}] evaluation error: {e}"); break
      if value != value_void: print(value_as_string(value))

def compile(file:str) -> None:
  with open(file) as f: src = f.read()
  pos = 0
  env = Env(default_env, {})
  while True:
    try: code, next_pos = parse_code(src, pos)
    except Parse_Error as e: print(f"{file}[{e.location}] parse error: {e}"); break
    if code is None: break
    pos = next_pos
    try: value = evaluate_code(code, env)
    except Evaluation_Error as e: print(f"{file}[{e.code.location}] evaluation error: {e}"); break

if __name__ == "__main__":
  import sys
  if len(sys.argv) <= 1: repl()
  else: compile(sys.argv[1])
