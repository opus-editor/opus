# Replace — design notes

## Rules (confirmed)

1. **Replace**: replaces only the occurrence currently marked by
   `current_match_tag`, then advances to the next match.
2. **Replace All**: replaces every occurrence currently marked by
   `search_match_tag`. The user's real cursor/selection stays at its own
   logical position (shifted by whatever length delta lands before it),
   not moved to any of the replaced ranges. All replacements count as one
   history entry (one Ctrl+Z undoes all of Replace All).

## Point 1 — how Replace/Replace All apply edits (resolved)

`SearchController` only holds `SearchBar`/`EditorView` today — it has no
path to `Document.cursors`/`Document.history` (owned by
`EditorController`/`CursorController`). Neither `GtkSource.SearchContext`'s
own native `replace()`/`replace_all()` fits: they mutate the buffer
directly, which would surface through `EditorView.untracked_edit` →
`CursorController.on_untracked_edit`, and that path today pushes
`before_cursors == after_cursors` (no delta repositioning at all) and
would push **one history entry per replacement** for Replace All, not one.

Plan:
- New `EditorController.apply_external_edits (TextEdit[] edits)`: builds
  the edits itself (from the tracked match ranges + replacement text),
  applies them via the existing `EditorView.apply_edits()` (one GTK
  transaction), repositions cursors, and pushes **one**
  `EditHistory` entry (`EditKind.OTHER`).
- New `CursorCollection.shift_for_external_edits (TextEdit[] edits)`:
  none of these edits are "produced" by any live cursor, so every cursor
  just shifts by the combined length delta of edits landing before it —
  same math `apply_edit_results()`'s own "else" branch already does for
  an edit a cursor didn't produce itself.

Checked against VS Code's real `ReplaceAllCommand`
(`src/vs/editor/contrib/find/browser/replaceAllCommand.ts`): it batches
every match into one command and uses `builder.trackSelection()` to let
the (mutable, decoration-tracking) text model carry the selection through
the edit automatically, reading it back afterward — same *shape* (one
batch, one undo step, selection lands wherever the edits leave it) as the
plan above. The mechanism differs because Opus's `Cursor` is a plain
Gtk-free int-offset Model type (`src/models/CLAUDE.md` — no native
range-tracking available at that layer), so `shift_for_external_edits()`
is doing by hand what VS Code's own text model does for free via
`trackSelection`.

Also confirmed: VS Code's single `replace()` uses the *real* editor
selection as the range to replace (`ReplaceCommand(selection, ...)`) —
it actually selects the current match while Find is open. Opus already
decided differently on purpose (Find never touches the real selection
until the bar closes — see `current_match_tag`/`select_last_match()`), so
our own single "Replace" reads its range from `current_match_start_mark`/
`end_mark` instead, not the real selection.

## Point 4 — undo granularity for single Replace (confirmed)

`EditKind.OTHER`, same as Enter/select-all-occurrences — never coalesces,
so each "Replace" click is its own undo step (Ctrl+Z undoes one
replacement at a time), never grouped with any other. User confirmed.

## Q2 — regex backreferences in the replacement text (resolved: full parity)

Full parity with VS Code's real `parseReplaceString`
(`src/vs/editor/contrib/find/browser/replacePattern.ts`) — only active
when Regex mode is on; with it off, the Replace field is always literal,
no parsing at all. The mini-DSL, confirmed to descend from Perl's own
regex-substitution syntax (the source's own comment: "patterned after
Boost" — Boost.Regex modeled its own case-modifier escapes on Perl's;
Sublime Text and the JetBrains IDEs support the same `\u\U\l\L` set in
their own Find & Replace):

- `$$` → literal `$`
- `$&` / `$0` → the whole match
- `$1`–`$99` → capture group N
- `\n` `\t` `\\` → newline, tab, literal backslash
- `\u` / `\l` → upper/lower-case just the **next one** character of
  whatever immediately follows (consumes itself, one-shot)
- `\U` / `\L` → upper/lower-case **every remaining** character of the
  text that follows, until another case op overrides it (doesn't
  consume itself)
- a case op only ever applies to the *one* `$n` reference immediately
  after it — it resets the moment that reference is emitted, so e.g.
  `\U$1-$2` uppercases `$1` only, `$2` is untouched unless it gets its
  own case op too (`\U$1-\U$2`)

Implementation: parse the Replace field into pieces (static text vs.
`$n` + pending case-ops) the same way `parseReplaceString` does, only
when regex is on; apply capture groups from `GLib.Regex`'s own match
result. Fully covered by the existing D-Bus test surface (SetActiveText
+ trigger the replace + GetActiveText).

## Preserve Case — removed from scope

Was going to port VS Code's real `buildReplaceStringWithCasePreserved`
(whole-match case rules + a kebab-case/snake_case segment-aware layer on
top — see git history of this file for the researched algorithm/example
trace if it comes back later). Descoped for now, per direct instruction:
the `preserve_case_button` toggle and its `format-size-symbolic` icon are
removed from the UI (`_search-bar.blp`/`.vala`,
`io.github.nowaos.Opus.gresource.xml`, `data/icons/`) — not just hidden
from Replace's own logic.

## Implemented

- `ReplacePattern` (`src/models/replace-pattern.vala`) — the Q2 DSL,
  full parity, with its own unit test (`tests/models/
  replace-pattern-test.vala`, 14 cases) covering `$n`/`$&`/`$0`/`$$`,
  `\n\t\\`, `\u\U\l\L` (including the "only attaches to the next `$n`"
  and stacked-ops nuances), two-digit groups, out-of-range groups, and
  the literal-vs-dynamic collapse (a pattern with no real `$`/`\` in it
  reports `has_replacement_patterns == false` even with Regex on — this
  is exactly the bug that first run of the test caught: an earlier
  version always reported `true` once Regex was on, unconditionally).
- `CursorCollection.shift_for_external_edits()` (Point 1).
- `EditorController.apply_external_edits()` (Point 1) — one atomic
  `EditKind.OTHER` history push per call, so Replace All's own edits
  come out as one undo step, and each single "Replace" click is its own
  (Point 4).
- `EditorView.compute_replace_current_match()`/`compute_replace_all()`/
  `land_after_replace()`/`forget_current_match()`, plus `enumerate_
  matches()` (`refresh_search_match_tags()`'s own walk, pulled out so
  Replace All can reuse it) and `capture_groups()` (re-matches an
  already-known match's own text with GLib.Regex, since SearchContext's
  forward()/backward() never hand back submatches themselves).
- `SearchBar`: `replace_button`/`replace_all_button`/`replace_entry`
  wired to `replace_requested`/`replace_all_requested` (Enter in the
  Replace field also fires `replace_requested`).
- `SearchController.on_replace_requested()`/`on_replace_all_requested()`
  tie it all together.

Build clean, all 18 tests pass (17 existing + the new replace-pattern
suite).
