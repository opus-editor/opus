; Written for Opus: Helix's Svelte indent query, with the else clauses out of @indent.
; tools/port-helix-language.py never overwrites a file starting this way.

; `{:else}` and its kin only go out: what follows them goes back in
; through the block they sit in. Helix lists them under @indent too,
; which Opus reads as "neither".
[
  (element)
  (if_block)
  (each_block)
  (key_block)
  (snippet_block)
  (await_block)
  (expression)
] @indent

[
  (end_tag)
  (block_end)
  (else_if_clause)
  (else_clause)
  (await_branch)
] @outdent
