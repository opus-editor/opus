# Functions

A function is something Opus can do to your text. `Ctrl+P`, then `>`
lists them after the commands: `Selection > Name` runs one over what
is selected, `File > Name` over the whole document. Opus ships a few
(Uppercase, Lowercase, Kebab Case, Pascal Case and Snake Case over a
selection; Reindent over the file — redone from the syntax, so it refuses a
file with a syntax error, and languages where indentation is the
syntax: Python, YAML, Markdown, Just);
yours are folders in your own functions directory, each a manifest and
a Lua script.

| What | Where |
|---|---|
| Your functions | `~/.local/share/opus/functions/<name>/` |
| Under Flatpak | `~/.var/app/io.github.opus_editor.Opus/data/opus/functions/<name>/` |

Opus reads the directory the first time the `>` list opens. After
adding or changing a function, `Ctrl+P`, `>`, *Functions / Reload
functions*.

## Writing a function

```
functions/
  shout/
    function.json
    main.lua
  lua/                 a language group: only listed in Lua files
    sort-requires/
      function.json
      main.lua
```

A folder holding `function.json` is a function; a folder without one
is a language group, named after a language package (`lua`, `ruby`,
`markdown`…), whose functions are listed for that language only. A
function named like a bundled one replaces it.

### 1. The manifest

```json
{
  "name": "Shout",
  "description": "Every letter in capitals, with a bang",
  "entry": "main.lua",
  "type": "transform",
  "input": "both",
  "languages": ["lua", "ruby"]
}
```

| Key | Meaning |
|---|---|
| `name` | Required. What the list shows. The folder's name is the function's id. |
| `description` | Shown under the name. |
| `entry` | The script. Defaults to `main.lua`. |
| `type` | Only `transform` for now: text in, text out. |
| `input` | `document` (listed as `File > …` only), `selection` (`Selection > …` only, so only while something is selected), or `both` (the default). |
| `languages` | Package names of the languages it is listed for. Added to the group's, if the folder is in one. Leave it out to list it everywhere. |

### 2. The script

The script defines `transform`, which gets one table and returns a
table of strings — one for each segment it was given, in order:

```lua
function transform (input)
  local out = {}
  for i, segment in ipairs (input.segments) do
    out[i] = opus.upper (segment.text) .. "!"
  end
  return out
end
```

`input`:

| Field | Meaning |
|---|---|
| `kind` | `"selection"` or `"document"`. |
| `segments` | `{ text = …, start = …, ["end"] = … }` each — the selections, or the whole text as one. Offsets count characters from the start of the document. |
| `text` | The whole document, whatever the segments are. |
| `cursors` | `{ anchor = …, position = … }` each. |
| `language` | The document's language package name, `""` with none. |
| `path` | The file's path, `""` for an unsaved one. |

Each returned string replaces its segment, all of them as one undo
step. Returning the segment's own text leaves it alone.

### 3. What a script can use

Lua 5.4 with `string`, `table`, `utf8` and `math`. Nothing that reaches
outside the process: no `os`, `io`, `require`, `load` or `package`. A
function that runs too long is stopped.

Lua's own `string.upper` only knows ASCII, so Opus adds `opus`:

| Function | Result |
|---|---|
| `opus.upper (s)`, `opus.lower (s)` | Every letter up or down, accents included. |
| `opus.capitalize (s)` | The first letter up, the rest down. |
| `opus.words (s)` | The words of an identifier or a sentence: `fooBar HTTPServer a-b_c` → `foo`, `Bar`, `HTTP`, `Server`, `a`, `b`, `c`. |

A script's error shows as a notification with the file and line.
