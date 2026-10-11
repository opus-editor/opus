; Written for Opus: Helix's Lua indent query, plus the block whose
; closer hasn't been typed yet — the grammar leaves its opening keyword
; inside an error rather than making a block of it, and an error
; holding one is a block being opened.
; tools/port-helix-language.py never overwrites a file starting this way.

(ERROR [
  "function"
  "then"
  "do"
  "repeat"
  "else"
  "elseif"
]) @indent

[
  (function_definition)
  (function_declaration)
  (method_index_expression)
  (field)
  (if_statement)
  (for_statement)
  (repeat_statement)
  (while_statement)
  (table_constructor)
  (arguments)
  (do_statement)
] @indent

[
  "end"
  "until"
  "else"
  "elseif"
  "}"
  ")"
] @outdent
