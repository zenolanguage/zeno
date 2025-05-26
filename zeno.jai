INTERPRETED :: true;

#import "Basic";
#import "Compiler";
#import "String";
#import "File";

die :: (format: string, args: ..Any) {
  print(format, ..args, to_standard_error=true);
  print("\n", to_standard_error=true);
  exit(1);
}

Result :: struct(T: Type, E: Type) {
  using _: union {
    using value: T;
    error: E;
  };
  ok: bool;
}

return_ok :: (value: Code) #expand {
  `return .{value = #insert value, ok = true};
}

return_err :: (error: Code) #expand {
  `return .{error = #insert error, ok = false};
}

Code_ :: struct {
  Kind :: enum {
    IDENTIFIER :: 0;
    NUMBER :: 1;
    STRING :: 2;
    TUPLE :: 3;
  }

  location: u32;
  kind: Kind;
  using data: union {
    as_string: string;
    as_number: float64;
    as_tuple: [..]*Code_;
  };
}

Parse_Result :: struct {
  code: *Code_;
  next_pos: u32;
}

Parse_Error :: struct {
  message: string;
  location: u32;
}

parse_code :: (s: string, p: u32) -> Result(Parse_Result, Parse_Error) {
  implicitnesses := ([..]bool).{allocator = temporary_allocator};
  codes := ([..]*Code_).{allocator = temporary_allocator};
  while true {
    start := p;
    while true {
      while p < s.count && is_space(s[p]) p += 1;
      if p < s.count && s[p] == ";" {
        while p < s.count && s[p] != "\n" p += 1;
        continue;
      }
      break;
    }
    if p >= s.count break;
    start = p;
    if s[p] == "(" {
      p += 1;
      array_add(*implicitnesses, false);
      code := New(Code_);
      code.location = start;
      code.kind = .TUPLE;
      array_add(*codes, code);
    } else if s[p] == ")" {
      p += 1;
      if implicitnesses.count == 0 return_err(.{"You are missing a closing parenthesis.", `p});
      pop(*implicitnesses);
      if codes.count > 1 {
        popped := pop(*codes);
        array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, popped);
      }
    } else {
      while p < s.count && !is_space(s[p]) && s[p] != "(" && s[p] != ")" && s[p] != "\"" p += 1;
      code := New(Code_);
      code.location = start;
      code.kind = .IDENTIFIER;
      code.as_string = string.{p - start, s.data + start};
      array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, code);
    }
    if implicitnesses.count == 0 break;
  }
  return_ok(.{ifx `codes.count > 0 pop(*`codes), `p});
}

code_as_string :: (code: *Code_) -> string {
  if #complete code.kind == {
    case .IDENTIFIER; #through;
    case .STRING; return code.as_string;
    case .NUMBER; b: String_Builder; print(*b, "%", code.as_number); return builder_to_string(*b);
    case .TUPLE;
      b: String_Builder;
      print(*b, "(");
      for code.as_tuple {
        print(*b, "%", code_as_string(it));
        if it_index != code.as_tuple.count - 1 print(*b, " ");
      }
      print(*b, ")");
      return builder_to_string(*b);
  }
}

repl :: () {
  file := "repl";
  die("The repl is currently not implemented. Sorry. You can interpret a file instead, like this: \"jai zeno.jai - file.z\".");
}

compile :: (file: string) {
  src, success := read_entire_file(file);
  if !success die("I failed to find \"%\" on your drive. Maybe you need to quote the entire path?", file);
  pos: u32 = 0;
  while true {
    reset_temporary_storage();

    result := parse_code(src, pos);
    if !result.ok die("%[%] parse error: %\n", file, result.error.location, result.error.message);
    if !result.code break;
    pos = result.next_pos;
    print("%\n", code_as_string(result.code));
  }
}

#if INTERPRETED {
  #run {
    set_build_options_dc(.{do_output=false});
    args := get_build_options().compile_time_command_line;
    if args.count == 0 repl();
    else compile(args[0]);
  }
} else {
  main :: () {
    args := get_command_line_arguments();
    if args.count <= 1 repl();
    else compile(args[1]);
  }
}
