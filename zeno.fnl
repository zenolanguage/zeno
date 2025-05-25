(local fennel (require :fennel))
(local ffi (require :ffi))

(fn c-type-repr [T]
  (if
    (= T.kind :float) (do
      (assert (or (= T.bits 32) (= T.bits 64)))
      (if (= T.bits 32) "float" "double"))
    (error (.. "Unimplemented " (tostring T)))))

(macro struct-definition-to-string [name ...]
  `(.. "typedef struct " ,(tostring name) " {\n" ,(accumulate [acc# "" i# [ident# T#] (ipairs [...])] `(.. ,acc# "\t" (c-type-repr ,T#) " " ,(tostring ident#) ";\n")) "} " ,(tostring name) ";"))

(macro struct [name ...]
  `(let [ffi# (require :ffi)]
    (ffi#.cdef (struct-definition-to-string ,name ,...))
    (global ,name (fn [init#] (ffi#.new ,(tostring name) init#)))))

(local CFloat {:kind :float :bits 32})
(struct Point (x CFloat) (y CFloat))
(print (Point {:x 5 :y 20}))
