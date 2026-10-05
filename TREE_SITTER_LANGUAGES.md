# Tree-sitter: out-of-the-box languages

Languages Opus plans to ship by default once syntax highlighting moves
from GtkSourceView to Tree-sitter. Anything outside this list would come
from user-installed language packages.

## Web

| Language | Notes |
|---|---|
| Ruby | |
| ERB | `embedded-template` grammar (also covers EJS); injects Ruby and HTML |
| PHP | Injects HTML |
| Java | |
| Python | |
| Go | |
| JavaScript | Includes JSX |
| TypeScript | Two grammars from the same repository: `typescript` and `tsx` |
| HTML | Injects JavaScript and CSS |
| CSS | |
| SASS/SCSS | SCSS has a usable grammar; indented `.sass` support is much weaker |

## Frontend frameworks

| Framework | Notes |
|---|---|
| React | No grammar of its own: covered by JSX and TSX |
| Vue | Own grammar; injects JS/TS/CSS/SCSS into its blocks |
| Svelte | Own grammar; injects JS/TS/CSS/SCSS into its blocks |
| Angular | Components are plain TypeScript; templates need a separate community grammar |

## Low level

| Language | Notes |
|---|---|
| C | |
| C++ | |
| Rust | |
| Vala | Community grammar, less mature than the others |

## Data and markup

| Language | Notes |
|---|---|
| SQL | Generic grammar; misparses some dialect-specific syntax |
| JSON | |
| YAML | |
| TOML | |
| XML | |
| Markdown | Two grammars (block and inline); code blocks rely on injections |

## Tooling

| Language | Notes |
|---|---|
| Bash | |
| Dockerfile | |
| Diff | |
| Git commit | |
| Meson | |

## Injections come first

ERB, PHP, HTML, Vue, Svelte and Markdown all depend on language
injections, so injection support has to work before most of this list
can ship.
