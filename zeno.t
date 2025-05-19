local C = terralib.includecstring[[
  #include <stdio.h>
  #include <stdlib.h>
  #include <string.h>
]]

function MakeSlice(T)
  local struct SliceT {
    data: &T
    count: ptrdiff
  }
  terra SliceT:init(data: &T, count: ptrdiff)
    self.data = data
    self.count = count
  end
  terra SliceT:sub(start: intptr, end_: intptr): SliceT
    var result: SliceT
    result:init(self.data + start, end_ - start)
    return result
  end
  return SliceT
end

Int8Slice = MakeSlice(int8)
String = Int8Slice

terra String.methods.from_cstring(data: &int8): String
  var s: String
  s:init(data, C.strlen(data))
  return s
end

terra repl()
  while true do
    C.printf("> ")
    var buf: int8[256]
    if C.fgets([&int8](&buf), [buf.type.N], [C.__stdinp or C.stdin]) ~= nil then
      var line = String.from_cstring([&int8](&buf))
      C.printf("%.*s", line.count, line.data)
    end
  end
end

terra compile(file: String)
  C.printf("%.*s\n", file.count, file.data)
end

terra main(argc: int, argv: &rawstring)
  if argc <= 1 then repl() else compile(String.from_cstring(argv[1])) end
end

local INTERPRET = true
if INTERPRET then
  function parse_args(args)
    local argv = terralib.new(rawstring[#args])
    for i=0,#args-1 do
      argv[i] = terralib.cast(rawstring, args[i + 1])
    end
    return #args, argv
  end

  local argc, argv = parse_args({"zeno", ...}) -- NOTE(dfra): `...` is lua magic for process varargs apparently.
  main(argc, argv)
end
