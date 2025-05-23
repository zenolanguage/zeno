# Zeno Programming Language

## Big Ideas™

- A statically typed Lisp-like systems programming language.
- One level of implicit parentheses per line.
- Indentation-aware parsing reduces grouping parentheses.
- Small amount of builtins (they start with $).
- Code is data, Types are data: pass around, modify, pass back.
- Allow the user to create their own "standard library" without any external imports.
- All programs can/should be freestanding.
- Zero is initialization.
- The user will be given the path to the compiler at compile time.
- Compile-time variables modify what code is generated throughout interpretation of the program and are compiled out of the native executable.

## Builtins

```z
; $define, $define-caller
; $declare, $declare-caller
; $assign, $assign-caller
; $field, $field-caller
; $break, $break-caller
; $continue, $continue-caller
; $defer, $defer-caller
; $return, $return-caller
; $if, $for, $while
; $proc, $macro, $foreign, $block
; $code, $code-of, $code-node-of
; $type, $type-of, $type-info-of, $cast
; $quote, $unquote, $insert, $compiles?
; $rest, $splice
; $using, $import
; $operator
; $assert
; $compiler
```
