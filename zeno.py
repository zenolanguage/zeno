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

@dataclass(frozen=True)
class Code:
  location: int
  kind: Code_Kind
  data: typing.Union[str, int, float, typing.List["Code"], None]

class Parse_Error(Exception):
  def __init__(self, message:str, location:int)->None:
    super().__init__(message)
    self.location = location

def parse_code(s:str, p:int)->typing.Tuple[typing.Optional[Code], int]:
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
      if p >= len(s) or s[p] != '"': raise Parse_Error("You have an unterminated string literal.", p)
      p += 1
      code = Code(start, Code_Kind.STRING, s[start:p])
      if len(codes) != 0: assert isinstance(codes[-1].data, list); codes[-1].data.append(code)
      else: codes.append(code)
    elif s[p].isdigit():
      while p < len(s) and s[p].isdigit(): p += 1
      code = Code(start, Code_Kind.INTEGER, int(s[start:p]))
      if len(codes) != 0: assert isinstance(codes[-1].data, list); codes[-1].data.append(code)
      else: codes.append(code)
    else:
      while p < len(s) and not s[p].isspace() and s[p] not in "();": p += 1
      code = Code(start, Code_Kind.IDENTIFIER if s[start] != '#' else Code_Kind.KEYWORD, s[start:p])
      if len(codes) != 0: assert isinstance(codes[-1].data, list); codes[-1].data.append(code)
      else: codes.append(code)
    if level == 0: break
  if level != 0: raise Parse_Error("You are missing a closing parenthesis.", p)
  assert len(codes) <= 1
  return codes.pop() if len(codes) > 0 else None, p

def code_as_string(code:Code)->str:
  if code.kind in [Code_Kind.IDENTIFIER, Code_Kind.KEYWORD, Code_Kind.STRING]:
    return code.data
  if code.kind in [Code_Kind.INTEGER, Code_Kind.FLOAT]:
    return str(code.data)
  if code.kind == Code_Kind.TUPLE:
    return "(" + " ".join(map(code_as_string, code.data)) + ")"
  raise NotImplementedError(code.kind)

def repl()->None:
  file = "repl"
  while True:
    src = input("> ")
    pos = 0
    while True:
      try: code, next_pos = parse_code(src, pos)
      except Parse_Error as e: print(f"{file}[{e.location}] {e}"); break
      if code is None: break
      pos = next_pos
      print(code_as_string(code))

def compile(file:str)->None:
  with open(file) as f: src = f.read()
  pos = 0
  while True:
    try: code, next_pos = parse_code(src, pos)
    except Parse_Error as e: print(f"{file}[{e.location}] {e}"); exit(1)
    if code is None: break
    pos = next_pos
    print(code_as_string(code))

if __name__ == "__main__":
  import sys
  if len(sys.argv) <= 1: repl()
  else: compile(sys.argv[1])
