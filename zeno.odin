package main

import "core:os"
import "core:fmt"

repl :: proc() {
  file := "repl"
}

compile :: proc(file: string) {

}

main :: proc() {
  if len(os.args) <= 1 do repl()
  else do compile(os.args[1])
}
