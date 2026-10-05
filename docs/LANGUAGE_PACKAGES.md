# Language packages

Opus learns a language from a package: a folder holding a manifest and
a few Tree-sitter query files. The languages Opus ships with are
packages of exactly this shape (see `languages/`), so anything a
built-in language does, yours can do too.

```
kotlin/
  language.json
  queries/
    highlights.scm
    injections.scm
```

## Installing a package

```sh
opus --install-language path/to/kotlin
opus --install-language https://example.org/someone/opus-kotlin.git
```

Either form copies the manifest and the queries into your own languages
folder, compiles the grammar, and checks the result. A repository has
to hold `language.json` at its root.

Installing a package under a name that is already installed replaces
it. A package named like a built-in language replaces that language.

| What | Where |
|---|---|
| Your packages | `~/.local/share/opus/languages/<name>/` |
| Their compiled grammars | `~/.cache/opus/grammars/` |
| Fetched grammar sources | `~/.cache/opus/grammar-sources/` |

Under Flatpak the same folders live in
`~/.var/app/io.github.opus_editor.Opus/`, as `data/opus/` and
`cache/opus/`.

Compiling a grammar needs `git` and a C compiler (`cc`) on your
machine. A grammar is ordinary native code that runs inside Opus, so
only install packages you trust.

## Writing a package

### 1. The manifest

`language.json`:

```json
{
  "name": "kotlin",
  "file-types": ["kt", "kts", { "glob": "build.gradle.kts" }],
  "shebangs": ["kotlin"],
  "injection-regex": "kotlin|kt",
  "grammar": {
    "repository": "https://github.com/fwcd/tree-sitter-kotlin",
    "rev": "f66d2908542e93c0204c6c241f794afe4e9cd5d1"
  }
}
```

| Key | Meaning |
|---|---|
| `name` | Required. What other packages call this language, and its folder name once installed. |
| `file-types` | Which files are this language. A string is an extension (`kt`, or `html.erb`); `{ "glob": … }` is matched against the whole path, for files told apart by name (`Dockerfile`, `*.tfstate.backup`). |
| `shebangs` | Interpreter names: a file starting with `#!/usr/bin/env kotlin` is this language whatever it is called. |
| `injection-regex` | Matched against the name another language asks for when it embeds code — the `kt` of a Markdown fence. |
| `grammar.repository` | Anything `git fetch` accepts, a local path included. |
| `grammar.rev` | The full commit to build. Always a commit, never a branch: the queries are written against one exact grammar. |
| `grammar.path` | The grammar's folder inside the repository, when it isn't the root. |
| `grammar.name` | The grammar's own name, when it differs from the language's. It names the function the grammar exports: `tree_sitter_<name>`, with `-` and `.` turned into `_`. |

When two languages claim a file, a glob beats an extension, the longer
glob or extension beats the shorter, and your packages beat built-in
ones.

A package with no `grammar` is never used on a file by itself; it
exists to lend its queries to others (see *Sharing queries* below).

### 2. The queries

Queries are written in Tree-sitter's
[query language](https://tree-sitter.github.io/tree-sitter/using-parsers/queries/index.html),
with the conventions of the Helix editor — most of Helix's
`runtime/queries/<language>/` files work unchanged.

**`queries/highlights.scm`** says what each piece of syntax is:

```scheme
(comment) @comment
(string_literal) @string

["fun" "val" "var"] @keyword

(function_declaration
  (simple_identifier) @function)

((simple_identifier) @constant
  (#match? @constant "^[A-Z][A-Z0-9_]*$"))
```

The names after `@` are what the theme colors. They are dotted and can
be as specific as you like: a theme that defines `keyword` but not
`keyword.control.return` paints the latter as `keyword`. The names
bundled themes define are listed in `themes/github-light.json`.

When several patterns capture the same text, the innermost one wins,
and between two patterns on the very same node, the one written
**later** in the file.

**`queries/injections.scm`** says where another language is embedded:

```scheme
; A fixed language
((comment) @injection.content
  (#set! injection.language "comment"))

; A language named by the text itself
(fenced_code_block
  (info_string (language) @injection.language)
  (code_fence_content) @injection.content)
```

| Property | Effect |
|---|---|
| `(#set! injection.language "x")` | The embedded language, by name or by its `injection-regex`. |
| `(#set! injection.combined)` | Every match of the pattern is parsed as one document — a template's scattered code. |
| `(#set! injection.include-children)` | Include the content node's children. They are left out by default. |

Supported predicates: `#eq?`, `#match?`, `#any-of?` and their `#not-`
forms. `#is? local` and `#is-not? local` are recognized, but Opus does
not track local variables yet, so a pattern using either never applies.
Any other predicate is an error.

### 3. Sharing queries

A query can start from another language's:

```scheme
; inherits: ecma,_typescript

(type_annotation) @type
```

The line is replaced by the same-named query of each language listed.
What you write after it overrides what it brought in.

### 4. Checking your work

```sh
opus --check-language path/to/kotlin
```

Builds the grammar if needed and reports every problem with the file
and line it is in:

```
queries/highlights.scm: line 12: the grammar has no such node type
```

While you work on a package inside your languages folder, Opus reloads
it whenever you save the manifest or a query: open files of that
language repaint right away. A rebuilt grammar is the exception — it
takes effect the next time Opus starts.

## Adding a built-in language

For a language to ship with Opus itself:

```sh
tools/port-helix-language.py path/to/helix <language>   # from a Helix clone
tools/sync-grammars.py                                  # regenerate build files
meson setup --reconfigure out/native
just test
```

`sync-grammars.py` turns every `languages/*/language.json` into the
Meson wraps and Flatpak sources that fetch and compile its grammar at
build time. The `bundled-languages` test compiles each bundled query
against its grammar, so a query using something Opus doesn't support
fails there.
