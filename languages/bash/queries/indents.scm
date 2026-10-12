; Written for Opus: Helix's Bash indent query, plus the array whose
; items sit on lines of their own — `LOCALES=(` … `)`.
; tools/port-helix-language.py never overwrites a file starting this way.

(array) @indent

")" @outdent

[
  (function_definition)
  (if_statement)
  (for_statement)
  (while_statement)
  (case_statement)
  (case_item)
  (pipeline)
] @indent

[
  "}"
  "fi"
  "elif"
  "else"
  "done"
  "esac"
] @outdent
