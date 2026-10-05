; Written for Opus: Helix has no indent query for Vala.
; tools/port-helix-language.py never overwrites a file starting this way.

[
  (block)
  (class_declaration)
  (interface_declaration)
  (struct_declaration)
  (enum_declaration)
  (namespace_declaration)
  (switch_statement)
  (switch_section)
  (initializer)
  (object_initializers)
] @indent

[
  "}"
  ")"
  "]"
] @outdent
