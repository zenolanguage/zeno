(local ffi (require :ffi))

(ffi.cdef "
// ctype.h
int isspace(int);
int isdigit(int);
")

(fn type->c [T]
  (if
    (= T.kind :float)
      (if
        (= T.bits 32) "float"
        (= T.bits 64) "double"
        (error (.. "unhandled bits " T.bits)))
    (error (.. "unhandled kind " T.kind))))

(macro struct->c [name & fields]
  `(.. "typedef struct " ,(tostring name) " {\n"
    ,(accumulate [acc# "" i# [ident# T#] (pairs fields)]
      `(.. ,acc# "\t" (type->c ,T#) " " ,(tostring ident#) ";\n"))
    "} " ,(tostring name) ";"))

(macro struct [name ...]
  `(do
    (ffi.cdef (struct->c ,name ,...))
    (global ,name (fn [init#] (ffi.new ,(tostring name) init#)))))

(local CFloat {:kind :float :bits 32})
(struct Point
  (x CFloat)
  (y CFloat))

(fn main [argc argv]
  (print (Point {})))

(let [args [...]] (main (# args) args))
