import typing
from dataclasses import dataclass
from enum import IntEnum

class Code_Kind(IntEnum):
  IDENTIFIER = 0
  KEYWORD = 1
  NUMBER = 2
  STRING = 3
  TUPLE = 4

@dataclass(frozen=True)
class Code:
  location: int
  kind: Code_Kind
  data: typing.Union[str, float, typing.List["Code"]]

class Parse_Error(Exception):
  def __init__(self, message:str, location:Code)->None:
    super().__init__(message)
    self.location = location

def parse_code(s:str, p:int)->typing.Tuple[Code, int]:
  codes: typing.List[Code] = []
  level = 0
  while True:
    while True:
      while p < len(s) and s[p].isspace(): p += 1
      if p < len(s) and s[p] == ';':
        while p < len(s) and s[p] != '\n': p += 1
        continue
      break
    if p >= len(s): break
    start = p
    if s[p] == '(':
      p += 1
      level += 1
      codes.append(Code(start, Code_Kind.TUPLE, []))
    elif s[p] == ')':
      p += 1
      if level == 0: raise Parse_Error("You have an extraneous closing parenthesis.", start)
      level -= 1
      if len(codes) > 1:
        popped = codes.pop()
        assert isinstance(codes[-1].data, list)
        codes[-1].data.append(popped)
    elif s[p] == '"':
      p += 1
      while p < len(s) and (s[p - 1] == '\\' or s[p] != '"'): p += 1
      if p >= len(s) or s[p] != '"': raise Parse_Error("You have an unterminated string literal.", start)
      p += 1
      code = Code(start, Code_Kind.STRING, s[start:p])
      if len(codes) == 0: codes.append(code)
      else: assert isinstance(codes[-1].data, list); codes[-1].data.append(code)
    elif s[p].isdigit() or (p + 1 < len(s) and s[p] in "+-" and s[p + 1].isdigit()):
      base = 10
      if s[p] in "+-": p += 1
      if p + 2 < len(s) and s[p] == '0' and s[p + 1] in "box" and s[p + 2].isdigit():
        base = 2 if s[p + 1] == 'b' else 8 if s[p + 1] == 'o' else 16
        p += 3
      while p < len(s) and s[p].isdigit(): p += 1
      if p < len(s) and s[p] == '.':
        p += 1
        if p >= len(s) or not s[p].isdigit(): raise Parse_Error("You have an invalid float literal. I expected a digit after the period.", start)
        while p < len(s) and s[p].isdigit(): p += 1
      if p < len(s) and s[p] == 'e':
        if base != 10: raise Parse_Error("You have an invalid float literal. I don't think it makes sense to exponentiate a non-base-10 literal.", start)
        p += 1
        if p >= len(s) or not s[p].isdigit(): raise Parse_Error("You have an invalid float literal. I expected digits to represent an exponent.", start)
        while p < len(s) and s[p].isdigit(): p += 1
      try: code = Code(start, Code_Kind.NUMBER, float(s[start:p]))
      except ValueError: code = Code(start, Code_Kind.NUMBER, float(int(s[start:p], base)))
      if len(codes) == 0: codes.append(code)
      else: assert isinstance(codes[-1].data, list); codes[-1].data.append(code)
    else:
      while p < len(s) and not s[p].isspace() and s[p] not in "()": p += 1
      code = Code(start, Code_Kind.IDENTIFIER if s[start] != '#' else Code_Kind.KEYWORD, s[start:p])
      if len(codes) == 0: codes.append(code)
      else: assert isinstance(codes[-1].data, list); codes[-1].data.append(code)
    if level == 0: break
  if p < len(s) and not s[p].isspace() and s[p] != ')': raise Parse_Error("You have two expressions with no whitespace between them.", p)
  if level != 0: raise Parse_Error("You are missing a closing parenthesis.", p)
  assert len(codes) <= 1
  return codes.pop() if len(codes) > 0 else None, p

def code_as_string(code:Code)->str:
  if code.kind in [Code_Kind.IDENTIFIER, Code_Kind.KEYWORD, Code_Kind.STRING]:
    assert isinstance(code.data, str)
    return code.data
  if code.kind == Code_Kind.NUMBER:
    assert isinstance(code.data, float)
    return str(code.data)
  assert isinstance(code.data, list)
  return "(" + " ".join(map(code_as_string, code.data)) + ")"

class Evaluation_Error(Exception):
  def __init__(self, message:str, code:Code)->None:
    super().__init__(message)
    self.code = code

class Type_Kind(IntEnum):
  TYPE = 0
  CODE = 1
  ANY = 3
  VOID = 4
  BOOL = 5
  COMPTIME_INTEGER = 6
  COMPTIME_FLOAT = 7
  PROCEDURE = 20

@dataclass(frozen=True)
class Type:
  kind: Type_Kind

@dataclass(frozen=True)
class Type_Procedure(Type):
  return_type: Type
  parameter_types: typing.Tuple[Type, ...]
  is_macro: bool

type_type = Type(Type_Kind.TYPE)
type_code = Type(Type_Kind.CODE)
type_any = Type(Type_Kind.ANY)
type_void = Type(Type_Kind.VOID)
type_comptime_float = Type(Type_Kind.COMPTIME_FLOAT)
type_procedures = {}

def get_procedure_type(return_type: Type, parameter_types: typing.List[Type], is_macro = False)->Type_Procedure:
  key = Type_Procedure(Type_Kind.PROCEDURE, return_type, tuple(parameter_types), is_macro)
  return type_procedures.setdefault(key, key)

def type_as_string(ty:Type)->str:
  raise NotImplementedError(ty.kind)

@dataclass(frozen=True)
class Procedure:
  parameter_names: typing.Tuple[str, ...]
  body: typing.Callable[..., "Value"]

  def __call__(self, *args, **kwargs)->"Value":
    return self.body(*args)

@dataclass(frozen=True)
class Value:
  type: Type
  data: typing.Union[str, float, Type, Code, Procedure, None]

def value_as_string(value:Value)->str:
  if value.type == type_type: return type_as_string(value.data)
  if value.type == type_code: return code_as_string(value.data)
  if value.type == type_comptime_float: return str(value.data)
  raise NotImplementedError(value.type)

value_void = Value(type_void, None)

@dataclass(frozen=True)
class Env_Entry:
  value: Value

@dataclass(frozen=True)
class Env:
  parent: typing.Optional["Env"]
  table: typing.Dict[str, Env_Entry]

  def find(self, key:str)->typing.Optional[Env_Entry]:
    if key in self.table: return self.table[key]
    if self.parent is not None: return self.parent.find(key)
    return None

def evaluate_code(code:Code, env:Env)->Value:
  if code.kind == Code_Kind.IDENTIFIER:
    assert isinstance(code.data, str)
    entry = env.find(code.data)
    if entry is None: raise Evaluation_Error(f"I failed to find \"{code.data}\" in the environment.", code)
    return entry.value
  if code.kind == Code_Kind.NUMBER:
    assert isinstance(code.data, float)
    return Value(type_comptime_float, code.data)
  if code.kind == Code_Kind.TUPLE:
    assert isinstance(code.data, list)
    op_code, *arg_codes = code.data
    op = evaluate_code(op_code, env)
    if op.type.kind != Type_Kind.PROCEDURE: raise Evaluation_Error(f"You tried to call \"{code_as_string(op_code)}\", which is not a procedure.", op_code)
    assert callable(op.data)
    args = [evaluate_code(arg_code, env) if not op.type.is_macro else arg_code for arg_code in arg_codes]
    result = op.data(*args, env=env)
    assert isinstance(result, Value)
    if op.type.is_macro and op.type.return_type == type_code and op != default_env.table["$code"].value:
      assert isinstance(result.data, Code)
      return evaluate_code(result.data, env)
    return result
  raise NotImplementedError(code.kind)

def builtin_define(name:Value, value:Value, **kwargs)->Value:
  env = kwargs["env"]
  assert name.type == type_code
  if name.data.kind != Code_Kind.IDENTIFIER: raise Evaluation_Error(f"$define expects an identifier but got \"{code_as_string(name.data)}\".", name.data)
  name_str = name.data.data
  if name_str in env.table: raise Evaluation_Error(f"$define can not redefine an identifier in the same scope.", name.data)
  env.table[name_str] = Env_Entry(value=value)
  return value_void

# def builtin_insert(format:Value, *codes, **kwargs)->Value:
#   return evaluate_code()

default_env = Env(None, {
  "$define": Env_Entry(value=Value(get_procedure_type(type_void, [type_code, type_any]), builtin_define)),
  "$code": Env_Entry(value=Value(get_procedure_type(type_code, [type_code], is_macro=True), Procedure(["code"], lambda code: Value(type_code, code)))),
  # "$insert": Env_Entry(value=Value(get_procedure_type(type_code, [type_string], varargs_type=type_code), builtin_insert)),
})

def repl()->None:
  file = "repl"
  env = Env(default_env, {})
  while True:
    try: src = input("> ")
    except (KeyboardInterrupt, EOFError): print(""); break
    pos = 0
    while True:
      try: code, next_pos = parse_code(src, pos)
      except Parse_Error as e: print(f"{file}[{e.location}] {e}"); break
      except Exception as e: print(f"{file}[{pos}] {type(e)} {e}"); break
      pos = next_pos
      if code is None: break
      # print(code_as_string(code)) # NOTE: for debugging parser
      try: result = evaluate_code(code, env)
      except Evaluation_Error as e: print(f"{file}[{e.code.location}] {e}"); break
      except Exception as e: print(f"{file}[{pos}] {type(e)} {e}"); break
      if result != value_void: print(value_as_string(result))

def compile(file:str)->None:
  with open(file) as f: src = f.read()
  pos = 0
  env = Env(default_env, {})
  while True:
    try: code, next_pos = parse_code(src, pos)
    except Parse_Error as e: print(f"{file}[{e.location}] {e}"); exit(1)
    except Exception as e: print(f"{file}[{pos}] {type(e)} {e}"); exit(1)
    pos = next_pos
    if code is None: break
    try: result = evaluate_code(code, env)
    except Evaluation_Error as e: print(f"{file}[{e.code.location}] {e}"); exit(1)
    except Exception as e: print(f"{file}[{pos}] {type(e)} {e}"); exit(1)

if __name__ == "__main__":
  import sys
  if len(sys.argv) <= 1: repl()
  else: compile(sys.argv[1])
