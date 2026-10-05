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
    locals.scm
    indents.scm
```

Only `language.json` and `highlights.scm` are required.

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

**`queries/locals.scm`** says which names are local variables, so
`highlights.scm` can tell a use of one from anything else spelled the
same way — in a language where a bare name may be a variable or a
call, that is the only way to know:

```scheme
[(function_declaration) (lambda_literal)] @local.scope

(parameter (simple_identifier) @local.definition.variable.parameter)

(simple_identifier) @local.reference
```

| Capture | Meaning |
|---|---|
| `@local.scope` | A definition is visible inside the scope it was made in, and in the scopes nested there. `(#set! local.scope-inherits false)` makes a scope see nothing from outside it. |
| `@local.definition.<class>` | Introduces a name. |
| `@local.reference` | A name that may refer to a definition. It does when a visible definition, made earlier in the file, has the same text. |
| anything else | Written after the reference pattern, cancels the reference on that node. |

In `highlights.scm`, `(#is-not? local)` then keeps a pattern off names
that turned out to be locals, and `(#is? local)` restricts it to them.

Unlike Helix, Opus does not recolor a reference as its definition's
`<class>`: a parameter is colored where it is declared, and its uses
keep whatever `highlights.scm` gives them. The class is accepted so
Helix's files work unchanged.

**`queries/indents.scm`** says where the indentation goes in and out,
so Enter after a line that opens a block starts one level in, and
typing what closes a block pulls that line back out:

```scheme
[(function_body) (class_body) (value_arguments)] @indent

["}" ")" "]"] @outdent
```

| Capture | Meaning |
|---|---|
| `@indent` | Every line the node holds after its own first line is one level in. Nodes that start on the same line count once. |
| `@outdent` | The line this node starts on is one level out — a closing token, or a keyword like `else`. |
| `@indent.always`, `@outdent.always` | The same, but each one counts even when several start on one line. |
| `(#set! "scope" "header")` | On an `@indent`: the level starts at the parent node's first line. For a body with no braces around it. |

A node captured as both `@indent` and `@outdent` counts as neither.
Opus only ever moves a line by the difference between two lines the
query describes, so a file indented its own way keeps its style.

Helix's `@align`, `@anchor`, `@extend` and `@opaque` are accepted and
ignored: their effects (aligning arguments under a parenthesis,
Python's dedent after `return`) don't happen in Opus. What `@opaque`
protects is covered another way: a line broken inside anything
`highlights.scm` captures as `@string…` or `@comment…` just keeps its
indentation.

Supported predicates: `#eq?`, `#match?`, `#any-of?` and their `#not-`
forms; `#is? local` and `#is-not? local`; and, for indent queries,
`#kind-eq?`, `#same-line?`, `#one-line?` and their `#not-` forms. Any
other predicate is an error.

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
