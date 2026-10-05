; Written for Opus: Helix's Ruby indent query, plus the blocks it leaves
; out — `do … end`, `unless`, `while`, `until`, `for` and `case … in`.
; tools/port-helix-language.py never overwrites a file starting this way.

; A block whose `end` hasn't been typed is often not parsed as a block
; at all: its keyword is left alone inside an error. An error holding
; one is a block that was being opened.
(ERROR [
  "begin"
  "case"
  "class"
  "def"
  "do"
  "for"
  "if"
  "module"
  "unless"
  "until"
  "while"
]) @indent

[
  (argument_list)
  (array)
  (begin)
  (block)
  (do_block)
  (call)
  (class)
  (case)
  (case_match)
  (if)
  (unless)
  (while)
  (until)
  (for)
  (hash)
  (method)
  (module)
  (singleton_class)
  (singleton_method)
] @indent

[
  ")"
  "}"
  "]"
  "end"
  "when"
  "else"
  "elsif"
  "rescue"
  "ensure"
] @outdent
