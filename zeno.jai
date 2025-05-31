#import "Basic";
#import "Compiler";
#import "File";
#import "Hash_Table";
#import "String";

die :: (format: string, args: ..Any) {
  print(format, ..args);
  exit(1);
}

repl :: () {
  die("The repl is not currently implemented. Sorry! Pass a file to compile instead, like this: \"jai zeno.jai - file.z\".\n");
}

compile :: (file: string) {
  src, success := read_entire_file(file);
  if !success die("I failed to find \"%\" on your drive. Maybe you need to quote the entire path?\n", file);
  print("%\n", src);
}

INTERPRETED :: true;
#if INTERPRETED {
  #run {
    set_build_options_dc(.{do_output = false});

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
