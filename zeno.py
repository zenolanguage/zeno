from dataclasses import dataclass
from enum import IntEnum

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
  data: str | int | float | list

def parse_code(s, p, file, no_implicit=False):
  indents = []
  implicitnesses = []
  codes = []
  explicit_closed_top_level = False
  while True:
    start = p
    newline_was_skipped = False
    beginning_of_line = p
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
      if not no_implicit and  s[p] != '(' and s[p] != ')':
        implicitnesses.append(True)
        codes.append(Code(start, Code_Kind.TUPLE, []))
    start = p
    if s[p] == '(':
      p += 1
      implicitnesses.append(False)
      codes.append(Code(start, Code_Kind.TUPLE, []))
    elif s[p] == ')':
      p += 1

      if len(implicitnesses) > 0 and implicitnesses[-1]:
        implicitnesses.pop()
        popped = codes.pop()
        (codes[-1].data if len(codes) > 0 else codes).append(popped)

      if len(implicitnesses) == 0: raise SyntaxError(f"{file}[{start}] You have an extraneous closing parenthesis.")
      implicitnesses.pop()
      explicit_closed_top_level = len(implicitnesses) == 0
      popped = codes.pop()
      (codes[-1].data if len(codes) > 0 else codes).append(popped)
    elif s[p] == "'":
      p += 1
      code, next_pos = parse_code(s, p, file)
      if code is None: raise SyntaxError(f"{file}[{start}] You attempted to take the $code of nothing.")
      p = next_pos
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.TUPLE, [Code(start, Code_Kind.IDENTIFIER, "$code"), code]))
    elif s[p] == ',':
      p += 1
      code, next_pos = parse_code(s, p, file)
      if code is None: raise SyntaxError(f"{file}[{start}] You attempted to $insert nothing.")
      p = next_pos
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.TUPLE, [Code(start, Code_Kind.IDENTIFIER, "$insert"), Code(start, Code_Kind.STRING, "\"%\""), code]))
    elif s[p].isdigit():
      while p < len(s) and s[p].isdigit(): p += 1
      if p < len(s) and s[p] == '.':
        p += 1
        while p < len(s) and s[p].isdigit(): p += 1
        (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.FLOAT, float(s[start:p])))
      else:
        (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.INTEGER, int(s[start:p])))
    elif s[p] == '"':
      p += 1
      while p < len(s) and (s[p - 1] == '\\' or s[p] != '"'): p += 1
      if p >= len(s) or s[p] != '"': raise SyntaxError(f"{file}[{p}] You have an unterminated string literal.")
      p += 1
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.STRING, s[start:p]))
    else:
      while p < len(s) and not s[p].isspace() and s[p] not in '();': p += 1
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.IDENTIFIER if s[start] != '#' else Code_Kind.KEYWORD, s[start:p]))

    peek = p
    while peek < len(s) and (s[peek].isspace() or s[peek] == ')') and s[peek] not in "\n;": peek += 1
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
    next_indent = peek - beginning_of_next_line
    if last_exp_of_line:
      if len(implicitnesses) > 0 and implicitnesses[-1]:
        implicitnesses.pop()
      while len(indents) > 0 and next_indent <= indents[-1]:
        indents.pop()
        if len(codes) > 1:
          popped = codes.pop()
          (codes[-1].data if len(codes) > 0 else codes).append(popped)
    if len(implicitnesses) == 0 and (explicit_closed_top_level or len(indents) == 0 or next_indent <= indents[0]): break
  if len(implicitnesses) != 0: raise SyntaxError(f"{file}[{p}] You are missing a closing parenthesis.")
  assert len(codes) <= 1
  return codes.pop() if len(codes) > 0 else None, p

def code_as_string(code):
  if code.kind in [Code_Kind.IDENTIFIER, Code_Kind.STRING]: return code.data
  if code.kind in [Code_Kind.INTEGER, Code_Kind.FLOAT]: return str(code.data)
  assert code.kind == Code_Kind.TUPLE
  return '(' + " ".join(code_as_string(c) for c in code.data) + ')'

class Type_Kind(IntEnum):
  TYPE = 0
  CODE = 1
  NULL = 2
  UNDEFINED = 3
  NORETURN = 4
  VOID = 5
  BOOL = 6
  ANYERROR = 7
  ANYTYPE = 8
  ANYOPAQUE = 9
  COMPTIME_INTEGER = 10
  COMPTIME_FLOAT = 11
  ERROR_SET = 12
  ERROR_UNION = 13
  INTEGER = 14
  FLOAT = 15
  OPTIONAL = 16
  POINTER = 17
  ARRAY = 18
  MATRIX = 19
  MAP = 20
  STRUCT = 21
  UNION = 22
  ENUM = 23
  PROCEDURE = 24
  MACRO = 25

@dataclass
class Type:
  kind: Type_Kind

type_type = Type(Type_Kind.TYPE)
type_code = Type(Type_Kind.CODE)
type_void = Type(Type_Kind.VOID)
type_comptime_int = Type(Type_Kind.COMPTIME_INTEGER)
type_comptime_float = Type(Type_Kind.COMPTIME_FLOAT)
type_procedure_any = Type(Type_Kind.PROCEDURE)
type_macro_any = Type(Type_Kind.MACRO)

@dataclass
class Value:
  type: Type
  data: Code | Type | None

def value_as_string(value):
  if value.type == type_code: return code_as_string(value.data)
  if value.type in [type_comptime_int, type_comptime_float]: return str(value.data.data)
  raise NotImplementedError(value.type)

value_void = Value(type_void, None)

@dataclass
class Env_Entry:
  value: Value

@dataclass
class Env:
  parent: "Env"
  table: dict

  def find(self, key):
    if key in self.table: return self.table[key]
    if self.parent is not None: return self.parent.find(key)
    return None

def evaluate_code(code, env, file):
  if code.kind == Code_Kind.IDENTIFIER:
    entry = env.find(code.data)
    if entry is None: raise SyntaxError(f"{file}[{code.location}] I failed to find '{code.data}' in the environment.")
    return entry.value
  elif code.kind == Code_Kind.KEYWORD:
    raise SyntaxError(f"{file}[{code.location}] I didn't expect to find a keyword ('{code.data}') here.")
  elif code.kind == Code_Kind.INTEGER:
    return Value(type_comptime_int, code)
  elif code.kind == Code_Kind.FLOAT:
    return Value(type_comptime_float, code)
  elif code.kind == Code_Kind.STRING:
    return Value(type_string, code)
  else:
    op_code, *arg_codes = code.data
    proc = evaluate_code(op_code, env, file)
    assert proc.type in [type_procedure_any, type_macro_any], "tried to call non-procedure/macro"
    pargs = [evaluate_code(arg_code, env, file) for arg_code in arg_codes] if proc.type.kind == Type_Kind.PROCEDURE else arg_codes
    return proc.data(*pargs, env=env, file=file)

def let(name, value, **kwargs):
  assert name.type == type_code and name.data.kind == Code_Kind.IDENTIFIER, "identifier expected"
  assert name.data.data not in kwargs["env"].table, "declaration already in environment"
  kwargs["env"].table[name.data.data] = Env_Entry(value)
  return value_void

def code(some_code, **kwargs):
  return Value(type_code, some_code)

def insert(fmt, *args, **kwargs):
  argi = 0
  result = ""
  for c in fmt.data[1:-1]:
    if c == '%':
      result += code_as_string(args[argi])
      argi += 1
    else:
      result += c
  code, next_pos = parse_code(result, 0, kwargs["file"] + "-mixin", no_implicit=True)
  assert code is not None, "Failed to parse any expressions"
  code2, next_pos = parse_code(result, next_pos, kwargs["file"] + "-mixin", no_implicit=True)
  assert code2 is None, "Multiple expressions were found inside an $insert"
  return evaluate_code(code, kwargs["env"], kwargs["file"])

default_env = Env(None, {
  "$let": Env_Entry(Value(type_procedure_any, let)),
  "$code": Env_Entry(Value(type_macro_any, code)),
  "$insert": Env_Entry(Value(type_macro_any, insert)),
})

def repl():
  file = "repl"
  env = Env(default_env, {})
  while True:
    src = input("> ")
    if src.strip() in ["quit", "exit"]: break
    pos = 0
    while True:
      try: code, next_pos = parse_code(src, pos, file)
      except SyntaxError as e: print(e); break
      if code is None: break
      pos = next_pos
      # print(code_as_string(code))
      try: value = evaluate_code(code, env, file)
      except Exception as e: print(e); break
      if value != value_void: print(value_as_string(value))

def compile(file):
  with open(file) as f: src = f.read()
  env = Env(default_env, {})
  pos = 0
  while True:
    code, next_pos = parse_code(src, pos, file)
    if code is None: break
    pos = next_pos
    evaluate_code(code, env, file)
  print("=====Environment=====")
  for k,v in env.table.items():
    print(k + ": " + value_as_string(v.value))

if __name__ == "__main__":
  import sys
  if len(sys.argv) <= 1: repl()
  else: compile(sys.argv[1])
