; Written for Opus: Helix's own file puts @definition on the name node
; by itself, with no @name, so Opus would list nothing from it.

(recipe
  name: (identifier) @name) @definition.function

(alias
  alias_name: (identifier) @name) @definition.function

(assignment
  name: (identifier) @name) @definition.constant

(mod
  name: (identifier) @name) @definition.module
