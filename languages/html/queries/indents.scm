; Written for Opus: Helix's HTML indent query, minus the void elements.
; tools/port-helix-language.py never overwrites a file starting this way.

; Indent the contents of an element; pull the end tag — and the close of a
; multi-line start/self-closing tag — back to the element's column. Mirrors the
; jsx rules. Void elements (`<br>`, `<img …>`) are single-line `element`s, so the
; tail-scoped indent is a no-op for them.
; A void element (`<meta>`, `<br>`…) has no end tag, and the grammar
; runs its node on to the next tag: nothing is ever inside it.
((element
  (start_tag (tag_name) @_tag)) @indent
  (#not-any-of? @_tag "area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "param" "source" "track" "wbr"))

[
  (script_element)
  (style_element)
] @indent
(end_tag) @outdent
(start_tag ">" @outdent)
(self_closing_tag "/>" @outdent)

; <script>/<style> bodies are embedded JS/CSS, handled by injection-aware indent
; (the engine indents them with the JS/CSS query). No @opaque needed.
