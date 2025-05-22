INTERPRETED :: true;

#import "Basic";
#import "Compiler";
#import "File";
#import "String";

die :: (format: string, args: ..Any) {
	print(format, ..args, to_standard_error=true);
	exit(1);
}

Code_ :: struct {
	Kind :: enum {
		IDENTIFIER :: 0;
		KEYWORD :: 1;
		INTEGER :: 2;
		FLOAT :: 3;
		STRING :: 4;
		TUPLE :: 5;
	}

	location: int;
	kind: Kind;
	using data: union {
		as_integer: int;
		as_float: float64;
		as_string: string;
		as_tuple: [..]*Code_;
	};
}

Parse_Error :: struct {
	message: string;
	location: int;
	ok: bool;
}

parse_code :: (s: string, p: int) -> (*Code_, int, Parse_Error) {
	explicit_top_level_was_closed := false;
	implicitnesses := ([..]bool).{allocator = temporary_allocator};
	codes := ([..]*Code_).{allocator = temporary_allocator};
	indents := ([..]int).{allocator = temporary_allocator};

	while true {
		start := p;
		newline_was_skipped := false;
		beginning_of_line := start;
		while true {
			while p < s.count && is_space(s[p]) {
				if s[p] == #char "\n" {
					newline_was_skipped = true;
					beginning_of_line = p + 1;
				}
				p += 1;
			}
			if p < s.count && s[p] == #char ";" {
				while p < s.count && s[p] != #char "\n" p += 1;
				continue;
			}
			break;
		}
		if p >= s.count break;

		indent := p - beginning_of_line;
		first_exp_of_line := newline_was_skipped || start == 0;

		if first_exp_of_line {
			if indents.count == 0 || indent > indents[indents.count - 1] array_add(*indents, indent);
			if s[p] != #char "(" && s[p] != #char ")" {
				array_add(*implicitnesses, true);
				code := New(Code_);
				code.location = p;
				code.kind = .TUPLE;
				array_add(*codes, code);
			}
		}

		start = p;
		if s[p] == #char "(" {
			p += 1;
			array_add(*implicitnesses, false);
			code := New(Code_);
			code.location = start;
			code.kind = .TUPLE;
			array_add(*codes, code);
		} else if s[p] == #char ")" {
			p += 1;

			if implicitnesses.count == 0 return null, p, .{"You have an extraneous closing parenthesis.", start, false};
			pop(*implicitnesses);
			explicit_top_level_was_closed = implicitnesses.count == 0;
			if codes.count > 1 {
				popped := pop(*codes);
				array_add(*codes[codes.count - 1].as_tuple, popped);
			}
		} else if s[p] == #char "'" {
			p += 1;
			code, next_pos, error := parse_code(s, p);
			if !error.ok return null, p, error;
			if !code return null, p, .{"You attempted to $quote nothing.", start, false};
			p = next_pos;

			tuple := New(Code_);
			tuple.location = start;
			tuple.kind = .TUPLE;
			identifier := New(Code_);
			identifier.location = start;
			identifier.kind = .IDENTIFIER;
			identifier.as_string = "$quote";
			array_add(*tuple.as_tuple, identifier);
			array_add(*tuple.as_tuple, code);
			array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, tuple);
		} else if s[p] == #char "," {
			p += 1;
			code, next_pos, error := parse_code(s, p);
			if !error.ok return null, p, error;
			if !code return null, p, .{"You attempted to $unquote nothing.", start, false};
			p = next_pos;

			tuple := New(Code_);
			tuple.location = start;
			tuple.kind = .TUPLE;
			identifier := New(Code_);
			identifier.location = start;
			identifier.kind = .IDENTIFIER;
			identifier.as_string = "$unquote";
			array_add(*tuple.as_tuple, identifier);
			array_add(*tuple.as_tuple, code);
			array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, tuple);
		} else if is_digit(s[p]) || ((s[p] == #char "+" || s[p] == #char "-") && p + 1 < s.count && is_digit(s[p + 1])) {
			p += 1;
			while p < s.count && is_digit(s[p]) p += 1;
			code := New(Code_);
			code.location = start;
			if p < s.count && s[p] == #char "." {
				p += 1;
				while p < s.count && is_digit(s[p]) p += 1;
				code.kind = .FLOAT;
				to_convert := string.{p - start, s.data + start};
				result, success, remainder := string_to_float64(to_convert);
				if !success return null, p, .{tprint("You gave me \"%\" which is an invalid float64 literal.", to_convert), start, false};
				code.as_float = result;
			} else {
				code.kind = .INTEGER;
				code.as_integer = to_integer(string.{p - start, s.data + start});
			}
			array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, code);
		} else if s[p] == #char "\"" {
			p += 1;
			while p < s.count && (s[p - 1] == #char "\\" || s[p] != #char "\"") p += 1;
			if p >= s.count || s[p] != #char "\"" return null, p, .{"You have an unterminated string literal.", p, false};
			p += 1;
			code := New(Code_);
			code.location = start;
			code.kind = .STRING;
			code.as_string = string.{p - start, s.data + start};
			array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, code);
		} else {
			while p < s.count && !is_space(s[p]) && s[p] != #char "(" && s[p] != #char ")" && s[p] != #char ";" p += 1;
			code := New(Code_);
			code.location = start;
			code.kind = ifx s[start] != #char "#" then .IDENTIFIER else .KEYWORD;
			code.as_string = string.{p - start, s.data + start};
			components := split(code.as_string, ".");
			if code.kind == .KEYWORD || components.count == 1 {
				array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, code);
			} else {
				tuple := New(Code_);
				tuple.location = start;
				tuple.kind = .TUPLE;
				identifier := New(Code_);
				identifier.location = start;
				identifier.kind = .IDENTIFIER;
				identifier.as_string = "$field";
				array_add(*tuple.as_tuple, identifier);
				target := New(Code_);
				target.location = start;
				target.kind = .IDENTIFIER;
				target.as_string = components[0];
				array_add(*tuple.as_tuple, target);
				for ([]string).{components.count - 1, components.data + 1} {
					identifier := New(Code_);
					identifier.location = start;
					identifier.kind = .STRING;
					identifier.as_string = sprint("\"%\"", it);
					array_add(*tuple.as_tuple, identifier);
				}
				array_add(ifx codes.count > 0 then *codes[codes.count - 1].as_tuple else *codes, tuple);
			}
		}

		peek := p;
		while peek < s.count && (is_space(s[peek]) || s[peek] == #char ")") && s[peek] != #char "\n" && s[peek] != #char ";" peek += 1;
		last_exp_of_line := peek >= s.count || s[peek] == #char "\n" || s[peek] == #char ";";
		beginning_of_next_line := peek;
		while true {
			while peek < s.count && is_space(s[peek]) {
				if s[peek] == #char "\n" beginning_of_next_line = peek + 1;
				peek += 1;
			}
			if peek < s.count && s[peek] == #char ";" {
				while peek < s.count && s[peek] != #char "\n" peek += 1;
				continue;
			}
			break;
		}

		next_indent := ifx peek < s.count peek - beginning_of_next_line else 0;

		if last_exp_of_line {
			if implicitnesses.count > 0 && implicitnesses[implicitnesses.count - 1] pop(*implicitnesses);
			while indents.count > 0 && next_indent <= indents[indents.count - 1] {
				pop(*indents);
				if codes.count > 1 {
					popped := pop(*codes);
					// TODO(dfra): we should probably be popping from implicitnesses here, no? Until then this may not work when we use explicit parentheses.
					array_add(*codes[codes.count - 1].as_tuple, popped);
				}
			}
		}

		if implicitnesses.count == 0 && (explicit_top_level_was_closed || (indents.count == 0 || next_indent <= indents[0])) break;
	}

	if implicitnesses.count != 0 return null, p, .{"You are missing a closing parenthesis.", p, false};

	assert(indents.count == 0);
	assert(codes.count <= 1);

	return ifx codes.count > 0 pop(*codes), p, .{ok=true};
}

code_as_string :: (code: *Code_) -> string {
	if #complete code.kind == {
		case .IDENTIFIER; return code.as_string;
		case .KEYWORD; return code.as_string;
		case .INTEGER; return tprint("%", code.as_integer);
		case .FLOAT; return tprint("%", code.as_float);
		case .STRING; return code.as_string;
		case .TUPLE;
			b := String_Builder.{allocator = temporary_allocator};
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
	die("The repl is not implemented yet. Sorry. Try giving me a file to compile instead, like this: \"jai zeno.jai - file.z\".\n");
}

compile :: (file: string) {
	src, success := read_entire_file(file);
	if !success die("I failed to find \"%\" on your drive. Maybe you need to quote the entire path?\n", file);

	pos := 0;
	while true {
		reset_temporary_storage();

		code, next_pos, error := parse_code(src, pos);
		if !error.ok die("%[%] %\n", file, error.location, error.message);
		if !code break;
		pos = next_pos;
		print("%\n", code_as_string(code));
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
