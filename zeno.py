#!/usr/bin/env python3

import typing
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
  data: typing.Union[str, typing.List["Code"]]

def parse_code(s, p, file):
  indents = []
  tuple_kinds = []
  codes = []
  while True:
    start = p
    newline_was_skipped = False
    beginning_of_line = p
    while True:
      while p < len(s) and s[p].isspace():
        if s[p] == '\n': newline_was_skipped = True; beginning_of_line = p + 1
        p += 1
      if p < len(s) and s[p] == ';':
        while p < len(s) and s[p] != '\n': p += 1
        continue
      break
    if p >= len(s): break
    first_exp_of_line = newline_was_skipped or start == 0
    indent = p - beginning_of_line
    if first_exp_of_line:
      if len(indents) == 0 or indent > indents[-1]: indents.append(indent)
      if s[p] != '(' and s[p] != ')':
        tuple_kinds.append(True)
        codes.append(Code(start, Code_Kind.TUPLE, []))

    explicit_was_closed = False
    start = p
    if s[p] == '(':
      p += 1
      tuple_kinds.append(False)
      codes.append(Code(start, Code_Kind.TUPLE, []))
    elif s[p] == ')':
      p += 1

      if len(tuple_kinds) > 0 and tuple_kinds[-1]:
        tuple_kinds.pop()
        popped = codes.pop()
        (codes[-1].data if len(codes) > 0 else codes).append(popped)

      if len(tuple_kinds) == 0: raise SyntaxError(f"{file}[{p}] Unexpected closing parenthesis.")
      assert not tuple_kinds[-1]
      tuple_kinds.pop()
      explicit_was_closed = len(tuple_kinds) == 0
      popped = codes.pop()
      (codes[-1].data if len(codes) > 0 else codes).append(popped)
    elif s[p] == "'":
      p += 1
      code, next_pos = parse_code(s, p, file)
      if code is None: raise SyntaxError(f"{file}[{start}] Attempted to take $code of nothing.")
      p = next_pos
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.TUPLE, [Code(start, Code_Kind.IDENTIFIER, "$code"), code]))
    elif s[p] == ',':
      p += 1
      code, next_pos = parse_code(s, p, file)
      if code is None: raise SyntaxError(f"{file}[{start}] Attempted to $insert nothing.")
      p = next_pos
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.TUPLE, [Code(start, Code_Kind.IDENTIFIER, "$insert"), Code(start, Code_Kind.STRING, "\"%\""), code]))
    elif s[p].isdigit():
      while p < len(s) and s[p].isdigit(): p += 1
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.INTEGER, s[start:p]))
    else:
      while p < len(s) and not s[p].isspace() and s[p] != '(' and s[p] != ')' and s[p] != ';': p += 1
      (codes[-1].data if len(codes) > 0 else codes).append(Code(start, Code_Kind.IDENTIFIER, s[start:p]))

    peek = p
    while peek < len(s) and (s[peek] == ')' or s[peek].isspace()) and s[peek] != '\n' and s[peek] != ';': peek += 1
    last_exp_of_line = peek >= len(s) or s[peek] == '\n' or s[peek] == ';'
    beginning_of_next_line = peek
    while True:
      while peek < len(s) and s[peek].isspace():
        if s[peek] == '\n': beginning_of_next_line = peek + 1
        peek += 1
      if peek < len(s) and s[peek] == ';':
        while peek < len(s) and s[peek] != '\n': peek += 1
        continue
      break
    next_indent = peek - beginning_of_next_line
    if last_exp_of_line:
      if len(tuple_kinds) > 0 and tuple_kinds[-1]:
        tuple_kinds.pop()
        while len(indents) > 0 and next_indent <= indents[-1]:
          indents.pop()
          popped = codes.pop()
          (codes[-1].data if len(codes) > 0 else codes).append(popped)

    if explicit_was_closed:
      popped = codes.pop()
      (codes[-1].data if len(codes) > 0 else codes).append(popped)

    if len(tuple_kinds) == 0 and (explicit_was_closed or (len(indents) == 0 or next_indent < indents[0])): break
  if len(tuple_kinds) != 0: raise SyntaxError(f"{file}[{p}] Missing closing parenthesis.")
  assert len(codes) <= 1
  return codes.pop() if len(codes) > 0 else None, p

def code_as_string(code):
  if code.kind != Code_Kind.TUPLE: return str(code.data)
  else: return "(" + " ".join(map(code_as_string, code.data)) + ")"

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
  COMPTIME_FLOAT = 10
  ERROR_SET = 11
  ERROR_UNION = 12
  INTEGER = 13
  FLOAT = 14
  POINTER = 15
  ARRAY = 16
  MATRIX = 17
  MAP = 18
  STRUCT = 19
  UNION = 20
  ENUM = 21
  PROCEDURE = 22

@dataclass
class Type:
  kind: Type_Kind

type_code = Type(Type_Kind.CODE)
type_void = Type(Type_Kind.VOID)
type_comptime_integer = Type(Type_Kind.COMPTIME_INTEGER)

@dataclass
class Value:
  type: Type
  data: typing.Union[Code, Type, None]

value_void = Value(type_void, None)

@dataclass
class Env_Entry:
  value: Value

@dataclass
class Env:
  parent: "Env"
  table: typing.Dict[str, Env_Entry]

  def find(self, key: str) -> Value:
    if key in self.table: return self.table[key]
    if self.parent is not None: return self.parent.find(key)
    return None

def evaluate_code(code, env, file) -> Value:
  if code.kind != Code_Kind.TUPLE:
    if code.kind == Code_Kind.IDENTIFIER:
      entry = env.find(code.data)
      if entry is None: raise SyntaxError(f"{file}[{code.location}] Failed to find identifier \"{code_as_string(code)}\" in the environment.")
      return entry.value
    elif code.kind == Code_Kind.INTEGER:
      return Value(type_comptime_integer, code)
    else: raise NotImplementedError(code.kind)
  op, *args = code.data
  if op.kind == Code_Kind.IDENTIFIER:
    if op.data == "$define":
      name_code, value_code = args
      name = evaluate_code(name_code, env, file)
      if name.type != type_code or name.data.kind != Code_Kind.IDENTIFIER: raise SyntaxError(f"{file}[{code.location}] $define expects \"{code_as_string(name.data.data)}\" to be an identifier.")
      if name.data.data in env.table: raise SyntaxError(f"{file}[{code.location}] \"{name.data.data}\" was already defined in this scope.")
      env.table[name.data.data] = Env_Entry(evaluate_code(value_code, env, file))
      return value_void
    elif op.data == "$code":
      assert len(args) == 1
      code = args[0]
      return Value(type_code, code)
    elif op.data == "$insert":
      assert len(args) == 1
      code = args[0]
      value = evaluate_code(code, env, file)
      if value.type != type_code: raise SyntaxError(f"{file}[{code.location}] $insert expects a value of type CODE.")
      return evaluate_code(value.data, env, file)

  proc = evaluate_code(op, env, file)
  pargs = args # todo: decide if code should be evaluated based on type of proc.
  return proc(*pargs)

def value_as_string(value) -> str:
  if value.type in [type_code, type_comptime_integer]: return code_as_string(value.data)
  raise NotImplementedError(value.type)

default_env = Env(None, {})

def repl():
  file = "repl"
  env = Env(default_env, {})
  while True:
    try: src = input("> ")
    except KeyboardInterrupt: print(); break
    if src.strip() in ["quit", "exit"]: break
    pos = 0
    while True:
      code, next_pos = parse_code(src, pos, file)
      if code is None: break
      pos = next_pos
      # print(code_as_string(code))
      try: value = evaluate_code(code, env, file)
      except Exception as e: print(e); break
      if value != value_void: print("=>", value_as_string(value))

def compile(file):
  with open(file) as f: src = f.read()
  pos = 0
  env = Env(default_env, {})
  while True:
    code, next_pos = parse_code(src, pos, file)
    if code is None: break
    pos = next_pos
    # print(code_as_string(code))
    value = evaluate_code(code, env, file)
    # print(value_as_string(value))

if __name__ == "__main__":
  import sys
  if len(sys.argv) <= 1: repl()
  else: compile(sys.argv[1])
