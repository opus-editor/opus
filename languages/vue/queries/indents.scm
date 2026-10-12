; Written for Opus: Helix's Vue indent query, with `</script>`/`</style>` not outdenting.
; tools/port-helix-language.py never overwrites a file starting this way.

; Vue single-file components are HTML-like: indent the contents of <template>
; and of nested elements, and pull the end tag — and the close of a multi-line
; start / self-closing tag — back to the element's column. Mirrors the html/jsx
; rules.
;
; <script> and <style> bodies are deliberately *not* indented: Vue convention
; (and Prettier's default) keeps them at column 0, and their embedded JS/CSS is
; indented by the injected language's own indent query.
[
  (element)
  (template_element)
] @indent

; Only the tags whose insides go in: a `</script>` closes a block whose
; lines sit flush, so it has nothing to come out of.
(element (end_tag) @outdent)
(template_element (end_tag) @outdent)
(start_tag ">" @outdent)
(self_closing_tag "/>" @outdent)
