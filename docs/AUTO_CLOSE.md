# Auto-close Brackets/Quotes

Typing `(` gives `(|)`. That one sentence hides eight abilities, each
of which exists because the sentence alone gets in the way somewhere.
This document names them, says what each one does, and which setting,
if any, controls it. `|` marks the cursor.

Settings live in `settings.json` under `editor.`, and every one of them
accepts a `"language.<name>": { … }` override, like `editor.word_wrap`
does today.

| Setting | Type | Default |
|---|---|---|
| `editor.auto_close.brackets` | bool | true |
| `editor.auto_close.quotes` | bool | true |
| `editor.auto_close.surround_selection` | bool | true |
| `editor.auto_close.track_inserted_pairs` | bool | true |

## 1. Pairs

What a pair is comes from the language, not the editor. A language
package declares its pairs in `language.json`:

```json
"pairs": [
  { "open": "{", "close": "}" },
  { "open": "[", "close": "]" },
  { "open": "(", "close": ")" },
  { "open": "\"", "close": "\"", "not-in": ["string"] },
  { "open": "'", "close": "'", "not-in": ["string", "comment"] },
  { "open": "<", "close": ">", "auto-close": false },
  { "open": "/*", "close": " */", "not-in": ["string", "comment"] }
],
"auto-close-before": ";:.,=}])>"
```

| Key | Meaning |
|---|---|
| `open`, `close` | The pair. Any length: `/*`, `<!--`, `${` are pairs too. |
| `not-in` | Highlight captures (`string`, `comment`, …) inside which this pair is inert. Matched by prefix: `string` covers `string.special`. |
| `auto-close` | `false` keeps the pair for surround only. Default `true`. |
| `surround` | `false` keeps the pair for auto-close only. Default `true`. |
| `auto-close-before` | Characters a closer may be inserted in front of, besides whitespace and end of line. Default shown above. |

A **quote** is a pair whose `open` equals its `close`. Everything else is
a **bracket**, block-comment delimiters included.

A language with no `pairs` gets `() [] {} "" ''`. A file with no
language gets the same.

## 2. Auto-close

Typing the last character of a pair's `open` inserts `close` after the
cursor: `(` gives `(|)`, `/*` gives `/*| */`.

Controlled by `editor.auto_close.brackets` for brackets and
`editor.auto_close.quotes` for quotes. Quotes get their own switch
because they are the ones that guess wrong (see 3).

A closer is inserted only when all of these hold:

- the pair is enabled at the cursor: `not-in` doesn't match the syntax
  there, or the file has no syntax. The syntax at the cursor is every
  highlight capture that contains it, from every language layered over
  that place; a caret is inside a capture strictly between its ends,
  except a comment's, whose end still counts: after `// text|` what
  comes next is still comment, after `"abc"|` it is code;
- the character after the cursor is whitespace, end of line, a closer
  of some pair, or one of `auto-close-before`. So `(` before `value`
  gives `(|value`, not `(|)value`;
- the typed text is a single character (one keystroke), never a paste
  or a composition commit.

## 3. Quote guard

Quotes are symmetric, so the editor has to guess whether `"` opens or
closes. Two extra rules apply to quotes only:

- **after a word**: `don|` + `'` gives `don'|`, never `don''`. A quote
  typed right after a letter, digit or `_` is a plain character;
- **odd count**: `"hello|` + `"` gives `"hello"|`. If the line before
  the cursor holds an odd number of this quote, counting only the ones
  where the pair is enabled, this one closes a string.

No setting. Turning `editor.auto_close.quotes` off turns the guard off
with it.

## 4. Inserted-pair memory

The editor remembers each closer it inserted, per cursor: the closer
itself and the span from its `open` to it. The memory is what lets 5
and 6 tell `)` that Opus typed from `)` that was already in the file.

A remembered pair is a span of the text, not a cursor's: it is kept
while some cursor sits between its open and its close, and forgotten
once none does, when the span stops being one line, or when the text
under either end changes. Undo restores nothing: a pair brought back by
undo is plain text.

Controlled by `editor.auto_close.track_inserted_pairs`. With it off
the editor keeps no memory, and 5 and 6 act on any pair at the cursor
whatever put it there, the way Helix does.

## 5. Overtype

With `(foo|)` remembered, typing `)` moves the cursor past the existing
`)` instead of inserting a second one: `(foo)|`. Typing by habit stays
correct.

Single-character closers only: `/*| */` + Space inserts a space, as
in VS Code and Zed. A quote right after `\` is never overtyped: `"a\|"`
+ `"` gives `"a\"|"`.

Acts on a remembered closer (4), or on any closer when
`editor.auto_close.track_inserted_pairs` is off. Off when the
corresponding auto-close switch is off.

## 6. Pair delete

With `(|)` remembered, Backspace removes both characters, leaving `|`.
Opening a pair and changing your mind costs one keystroke, not two.

Only when `open` sits right before the cursor and `close` right after,
with nothing between them. Governed like 5. Delete (forward) never
pairs.

## 7. Auto-surround

With text selected, typing a pair's `open` wraps the selection instead
of replacing it: `foo` + `(` gives `(foo)`, with the selection kept on
`foo`. Typing the `close` does the same.

Controlled by `editor.auto_close.surround_selection`. Independent from auto-close: a
pair with `auto-close: false` (the `<` of Rust) still surrounds, and a
pair with `surround: false` still auto-closes. Only single-character
`open`s surround; `/*` does not. Quotes surround too, without the
guard from 3.

## 8. Cursors, undo, modes

- **Many cursors**: each decides on its own context (2, 3, 4), so one
  `(` may close at one cursor and not at another. Two cursors whose
  edits collide drop one, through the `cursors_to_remove` contract
  `CursorCollection.compute_edits` already reserves.
- **Undo**: the typed `open` and the inserted `close` are one history
  step. An overtype (5) is a cursor move, nothing to undo: `foo(a)`
  typed with auto-close undoes exactly like `foo(a)` typed without. A
  pair delete (6) is one step.
- **Insert-key overtype mode**: auto-close, overtype and pair delete
  are off while the session is in overtype mode; typing replaces the
  character under the cursor as usual. Surround still works.
- **Indentation**: typing a closer that auto-outdents (`}` on its own
  line) keeps doing so whether it was overtyped or inserted.
- **Input method**: what is still being composed (a dead key's `~`, a
  CJK candidate) shows at every cursor as marked text, outside the
  history; what it commits is typed like any key, so `"` from a dead
  key closes and wraps the same as `"` from a plain one.

## Out of scope

Named here so they are not rediscovered as gaps.

- **Tags**: `<div>` + `>` giving `<div>|</div>`. Different trigger,
  needs the syntax tree to know what an opening tag is. Its own
  feature, "Auto-close Tags".
- **Enter between a pair**: `{|}` + Enter opening three lines with the
  cursor indented in the middle. Belongs to indentation
  (`indents.scm`), not to pairs.
- **Space padding**: `(|)` + Space giving `( | )` and Backspace undoing
  both (Helix). Low value, surprising; not planned.
- **Separate switch for block comments** (VS Code's
  `autoClosingComments`): `/*` is a bracket here. A language that
  doesn't want it closed leaves it out of `pairs`.
- **Enum strategies** (`always` / `beforeWhitespace` / `languageDefined`):
  `auto-close-before` per language plus a boolean per kind covers what
  people actually change.
