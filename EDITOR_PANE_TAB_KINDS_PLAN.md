# Editor pane: split by tab kind — implementation plan

`EditorView.EditorPaneWidget` (`src/views/editor-view/editor-pane/index.vala`,
1186 lines) grew up as "the pane that edits one file", and every feature since
(Find Results, the git gutter, `.editorconfig`, the change banner) was bolted
onto it. The split below gives each *tab kind* its own component, leaves the
pane as the coordinator of tab chrome and routing only, and replaces the
by-name `is_find_results_active ()` special-casing in `MainWindow` with a
contract each tab kind implements.

This revision folds in the owner's review decisions (§6 is the one-line log;
§5 holds only what is still open). It is meant to be executed in stages —
each stage in §4 lands and ships on its own.

Paths below are relative to the repo root. Line numbers refer to the tree at
`f7ad0af`.

## 1. Target structure

```
src/views/editor-view/editor-pane/
  index.vala                        EditorView.EditorPaneWidget — pane coordinator (unchanged name)
  _i-tab-kind.vala                  EditorView.EditorPane.ITabKind + EditorView.EditorPane.TabCapability (new)
  tab-bar/                          EditorView.EditorPane.TabBar / TabBarPill / TabBarGhost — one small chrome addition (§1.1)
  tab-document/
    index.vala                      EditorView.EditorPane.TabDocument (new; extracted from editor-pane/index.vala)
    _change-banner.vala             EditorView.EditorPane.TabDocumentChangeBanner (moved from editor-pane/_change-banner.vala)
    _change-banner.blp              moved as-is
    _file-watcher.vala              EditorView.EditorPane.TabDocumentFileWatcher (moved from editor-pane/_file-watcher.vala)
  tab-find-results/
    index.vala                      EditorView.EditorPane.TabFindResults (renamed from find-results/ FindResults)
    index.blp                       moved as-is
    _language-highlighter.vala      EditorView.EditorPane.TabFindResultsLanguageHighlighter
```

Naming follows `src/views/CLAUDE.md` § Naming to the letter:

- A nested view keeps its own name and moves into the namespace named after
  its owner's directory: `EditorView.EditorPane.TabDocument`,
  `EditorView.EditorPane.TabFindResults` — exactly as `TabBar` already does.
- A flat `_sub.vala` sub-widget's class is prefixed with its *owning view's*
  name. The banner and watcher stop being `EditorPaneChangeBanner`/
  `EditorPaneFileWatcher` (owned by the pane, namespace `EditorView`) and
  become `TabDocumentChangeBanner`/`TabDocumentFileWatcher` (owned by
  `TabDocument`, namespace `EditorView.EditorPane`). Same for
  `FindResultsLanguageHighlighter` → `TabFindResultsLanguageHighlighter`.
- `EditorPaneWidget` keeps its `Widget` suffix: it still owns nested
  sub-components, so it still collides with the `EditorPane` namespace.
- The interface sits as a flat `_i-tab-kind.vala` next to `index.vala`, the
  same placement `src/views/main/_i-global-panel.vala` and
  `src/lib/dev-server/_i-dev-server.vala` use. Interfaces don't carry the
  owner prefix in this codebase (`IGlobalPanel`, `IDevServer`,
  `GitDiff.IBaseProvider`), so it's `ITabKind`, namespaced
  `EditorView.EditorPane` because it lives inside `editor-pane/`. The
  `TabCapability` enum is declared in the same file and stays inside
  `EditorPane` (decided: no hoisting, no boolean properties on the pane);
  `MainWindow` spells `EditorView.EditorPane.TabCapability` out in full.
- Everything outside `EditorView.EditorPane` spells the namespace out in full
  — no `using`.

### 1.1 File-by-file move map

| Today | Target | Kind of change |
|---|---|---|
| `editor-pane/find-results/index.vala` (`FindResults`) | `editor-pane/tab-find-results/index.vala` (`TabFindResults`) | `git mv` + class rename + implements `ITabKind` + absorbs `search_in_files` (§1.3) |
| `editor-pane/find-results/index.blp` | `editor-pane/tab-find-results/index.blp` | `git mv`; resource path `/io/github/nowaos/Opus/editor-view/editor-pane/tab-find-results/index.ui` |
| `editor-pane/find-results/_language-highlighter.vala` | `editor-pane/tab-find-results/_language-highlighter.vala` (`TabFindResultsLanguageHighlighter`) | `git mv` + class rename |
| `src/styles/find-results.css` | `src/styles/tab-find-results.css` | rename file only; CSS class names (`.find-results-header`, `.find-results-replace-row`) stay |
| `editor-pane/_change-banner.vala` (`EditorPaneChangeBanner`) | `editor-pane/tab-document/_change-banner.vala` (`TabDocumentChangeBanner`) | `git mv` + class/namespace rename |
| `editor-pane/_change-banner.blp` | `editor-pane/tab-document/_change-banner.blp` | `git mv`; resource path `.../editor-pane/tab-document/_change-banner.ui` |
| `editor-pane/_file-watcher.vala` (`EditorPaneFileWatcher`) | `editor-pane/tab-document/_file-watcher.vala` (`TabDocumentFileWatcher`) | `git mv` + class/namespace rename |
| `src/styles/editor-pane.css` | `src/styles/tab-document.css` | rename; its only rules are `.change-banner*`, loaded from the banner's constructor (`_change-banner.vala:24`) |
| `editor-pane/index.vala` (document-tab logic, §1.2) | `editor-pane/tab-document/index.vala` (`TabDocument`) | extraction, the one real refactor |
| — | `editor-pane/_i-tab-kind.vala` | new |
| `editor-pane/tab-bar/index.vala`, `_pill.vala` | same files | (a) `TabBar.confirm_unsaved_close ()` (lines 463-465) is deleted — its one caller moves into `TabDocument`, which calls `Dialogs.confirm_discard (widget, name)` directly, same as the method itself did. (b) `add_tab`/`rename_tab` gain a trailing `bool has_pathname`, stored on the pill as a plain public field next to `tooltip_path`; `show_context_menu` (lines 312-323) appends "Reveal in Sidebar" and the separator + "Copy Path" + "Copy Relative Path" group only when `pill.has_pathname`. Decided: the whole block is *omitted* for Untitled-N/Find Results, not pointed at the uri or the title — "Reveal in Sidebar" gets the same treatment as the Copy group, not left as a separate open question. |
| `src/models/document.vala` | same file | `internal_tab ()` (lines 148-154), `is_internal` (35), `is_saveable` (34) and the two guards that read it (170-171, 182-183) are removed; `tests/models/document-test.vala` loses the `internal_tab` cases (255-290) and their registration (330). Decided — see §1.3 for why nothing needs them any more. |

Build-system touch points for the moves: `src/meson.build`
`opus_gtk_view_sources` (lines listing `editor-pane/_change-banner.vala`,
`_file-watcher.vala`, `find-results/*`), `data/meson.build` `blueprints`
input list (`_change-banner.blp`, `find-results/index.blp`),
`data/io.github.nowaos.Opus.gresource.xml` (the two `.ui` entries and the two
`styles/*.css` entries). `meson setup --reconfigure builddir` after each.

### 1.2 What leaves `editor-pane/index.vala` for `tab-document/index.vala`

Everything that reads or writes a `Document`, the shared `CodeEditor`'s
content, or disk. By today's line ranges:

| Member (today) | Lines | Goes to |
|---|---|---|
| `DEFAULT_INDENT_SIZE`, `DEFAULT_INSERT_SPACES`, `editor_config`, `EditorConfig.load` in ctor/`set_root_path` | 34-39, 58, 123, 178 | `TabDocument` |
| `change_banner`, `file_watcher` fields + wiring (`discard_clicked`, `file_changed`) | 55-56, 127-128, 169, 171 | `TabDocument` |
| `code_editor` construction, `text_changed`, `search_position_changed` re-emit | 126, 153, 170 | `TabDocument` (re-emits `search_position_changed` as an `ITabKind` signal; the pane re-exposes `code_editor` — §2.4) |
| `documents` map, `untitled_counter` | 60, 62 | `TabDocument` (its own tabs only) |
| `decorations`, `diff_tracker`, `diff_base_provider`, `set_decorations`, `set_diff_base_provider`, `refresh_tab_decorations`, `stamp_tab_decoration` | 69-77, 182-215 | `TabDocument` (pane keeps one-line forwarders for the two setters — §2.4) |
| `open`, `open_at`, `char_offset_of_line_column`, `new_untitled` | 222-314 | `TabDocument` (pane forwards `open`/`new_untitled`; `open_at` is wired from `TabFindResults.navigate_requested`) |
| `save_active`, `save_as_active` | 384-395 | pane-level routing (§2 item 9) over `TabDocument.save_uri`/`save_as_uri` |
| `is_dirty`, `save_path`, `save_uri`, `save_as_path`, `choose_save_as_path`, `save_document` | 405-408, 988-1010, 1081-1178 | `TabDocument` (`save_path` is DevServer-only and is reached through `document_tab` — §2.4) |
| `active_content`, `set_active_content`, `set_active_cursors`, `get_active_cursors` | 457-530 | `TabDocument`, **not re-forwarded** by the pane: DevServer-only members (their own doc comments say so), reached as `editor_pane.document_tab.*` — §2.4 |
| `apply_external_edits`, `has_focus`, `primary_selection_text`, `grab_focus`, `set_search_text` … `select_all_occurrences` (the CodeEditor search surface) | 533-599 | deleted as forwarders. They are all `CodeEditor` methods; `MainWindow`/`DevServer` reach them through the pane's new `search_editor` property — §2.4 |
| `discard_tab`, `file_moved` | 606-641 | `TabDocument` (pane forwards both; `MainWindow` uses them) |
| `open_preview`, `open_permanent`, `on_file_changed`, `mark_externally_modified`, `on_reload_requested`, `reload_document`, `mark_file_deleted`, `folder_name_of`, `find_preview`, `find_by_title` | 652-836 | `TabDocument` |
| the document half of `show_in_editor` | 877-899 | `TabDocument.show (uri)` |
| the Find-Results half of `show_in_editor` and the no-tab-left reset in `finish_close` | 859-875, 1028-1033 | `TabDocument.hide ()` — one method, two call sites collapse into it |
| `promote`, `on_preview_demoted`, `on_text_changed`, `on_tab_double_clicked`, `close_tab` | 902-975 | `TabDocument` (`promote (uri)` is the `ITabKind` entry point for both double-click and demotion) |
| `relative_path` | 1181-1184 | both: `TabDocument` needs it for `.editorconfig` lookups; the pane keeps a copy for "Copy Relative Path" |

### 1.3 What leaves `editor-pane/index.vala` for `tab-find-results/index.vala`

| Member (today) | Lines | Goes to |
|---|---|---|
| `FIND_RESULTS_TAB_URI`, `DEFAULT_FIND_IN_FILES_CONTEXT_LINES`, `last_find_in_files_query`, `search_generation` | 83-96 | `TabFindResults` private state |
| `search_in_files` body, `open_or_focus_find_results_tab` | 327-381 | `TabFindResults.search (string root_path, FindInFilesQuery query)` — emits `tab_added` on first run, `activate_requested` on every run |
| `current_find_in_files_query` | 421-423 | `TabFindResults.active_query` (non-null only while `show ()`n, i.e. while its tab is the active one — the same condition, now known locally) |
| `is_find_results_active`, `open_internal_replace`, `is_find_results_tab` | 434-445, 854-856 | deleted; replaced by `ITabKind.capabilities`/`open_replace ()` (§3) |
| `close ()`'s `search_generation++` | 649 | `TabFindResults.close ()` |
| `Document.internal_tab (...)` for the results tab | 372 | gone. The tab only had a `Document` so it could sit in the pane's one `documents` map; once the pane keys tabs by `ITabKind` instead, nothing reads it. `is_internal` was never read outside its own test; `is_saveable` gated `save_uri`/`save_as_path`, which is now expressed by `TabDocument` being the only kind with a save path at all. Removed with their tests (§1.1, last row). |

## 2. What stays in `editor-pane/index.vala`, and why

After the split the pane is the composer of `TabBar` + N tab kinds, and
nothing else. Its remaining responsibilities, all genuinely pane-level:

1. **The widget shell** — `container`/`content`/`empty_state`/
   `editor_area_bin` (lines 46-53, 130-151). `editor_area_bin.child` becomes
   `active_kind.widget`; the empty-state swap stays as is.
2. **The tab registry** — replaces the `documents` map with
   `HashTable<string, OpenTab> tabs` where `OpenTab { ITabKind kind; string
   title; }`, plus `string? active_uri` and `ITabKind? active_kind`. `title`
   is what `open_paths ()`/`active_document_path` (DevServer's
   `ListOpenTabs`/`GetActiveTab`) read today via `documents[uri].title`, and
   what the Copy Path/Reveal handlers resolve to (for a tab with a pathname,
   `title == pathname`); the kind hands it over in `tab_added`, so the pane
   never needs the `Document` back.
3. **Chrome routing, kind → `TabBar`** — one `wire_kind (ITabKind kind)`
   helper connects the kind's `tab_added`/`tab_removed`/`tab_renamed`/
   `tab_marks_changed`/`tab_preview_changed`/`tab_decoration_changed`/
   `activate_requested`/`search_position_changed` to the matching
   `tab_bar.*` call (or re-emission) plus the registry bookkeeping. This is
   also where the four copies of `if (documents.size () == 1)
   has_open_tabs_changed (true)` (lines 309, 376, 668, 682) and the
   `tab_opened`/`tab_closed` emissions collapse into one place each. Adding
   a kind = construct it + `wire_kind (it)`.
4. **Gesture routing, `TabBar` → kind** — `tab_selected` → `activate (uri)`;
   `tab_close_requested` → `kind_of (uri).close_tab.begin (uri)`;
   `tab_double_clicked`/`preview_demoted` → `kind_of (uri).promote (uri)`;
   `close_others`/`close_all` iterate the registry and call each owning
   kind's `close_tab` one at a time (today's `close_paths`, lines 1066-1070,
   unchanged in spirit — the serial-prompt guarantee is pane-level since it
   spans kinds). `copy_path`/`copy_relative_path`/`reveal_in_sidebar` use
   `tabs[uri].title` — and with `has_pathname` gating the Copy group in
   `TabBar` (§1.1), the two copy handlers only ever fire for a tab whose
   title *is* its path.
5. **Activation** — `activate (uri)`: hide the previous kind if it differs,
   swap `editor_area_bin.child`, `tab_bar.set_active`, `kind.show (uri)`,
   emit `active_state_changed (uri, kind.is_dirty (uri))`. Fallback on close
   via `tab_bar.last_tab_path ()` (line 1024) stays here; with nothing left,
   `active_kind.hide ()` and `active_state_changed (null, false)`.
6. **The keyboard-dispatch surface** (§3): `zoom_in`/`zoom_out`/
   `reset_zoom`/`open_replace` forward to `active_kind`;
   `active_tab_supports (TabCapability)` answers for it.
7. **`root_path`** — kept for `linked_folder_path` (MainWindow's "Add
   Folder…" check, line 581), "Copy Relative Path", and as the argument to
   `tab_find_results.search (root_path, query)`. `set_root_path` also
   forwards to `tab_document.set_root_path` for its `.editorconfig` reload.
8. **Three exposed sub-facades instead of twenty forwarders** — see §2.4.
   What remains as one-line forwarders to `tab_document` is the set
   `MainWindow`'s real UI calls *and* that is conceptually "the pane opens/
   tracks files": `open`, `new_untitled`, `is_dirty`, `discard_tab`,
   `file_moved`, `set_decorations`, `set_diff_base_provider` — seven. `open`
   has to stay on the pane regardless: it is where a `kind_for_path ()`
   switch goes the day a second kind opens files (§3.4).
9. **`save_active`/`save_as_active`/`close_active`** — pane-level because
   "the active tab" is pane state: `close_active` → `active_kind.close_tab
   .begin (active_uri)`; the two saves call `tab_document.save_uri
   (active_uri)`/`save_as_uri (active_uri)` only when `active_kind ==
   tab_document` (a non-document kind has nothing to save — the same role
   `!is_saveable` played at line 1095, now expressed by which kind is active
   rather than a flag on a `Document`).
10. **`search_in_files`** — stays as the public entry point (MainWindow line
    544, DevServer line 171) but is now two lines: lazily construct and
    `wire_kind` `tab_find_results` (decided: lazy, as today — `kind_of ()`
    tolerates it being null until the first search), then
    `tab_find_results.search.begin (root_path, query)`.
    `current_find_in_files_query` forwards to `tab_find_results?.active_query`.
11. **Re-emitted signals** — `has_open_tabs_changed`, `active_state_changed`,
    `tab_opened`, `tab_closed`, `reveal_in_sidebar_requested` (unchanged
    reasons), `search_position_changed` (re-emitted from whichever kind is
    active, see §2.4).

Expected size: roughly 250-300 lines, down from 1186.

Deliberately *not* done (decided): one `TabDocument` instance per open file.
Today one `CodeEditor` is shared across every file tab by design (the comment
at lines 49-53; `diff_tracker` is explicitly "a single instance, reset on
every tab switch", lines 71-76; `CodeEditor.zoom_level` and `font_provider`
are `static`, `code-editor/index.vala:164-178`). `TabDocument` is therefore
one object per pane that owns *all* document tabs and renders whichever is
active — the same shape `FindResults` already has for its one tab, and the
same shape VS Code uses (one editor per group, `setModel ()` on switch, one
global zoom). Per-tab instances with per-instance zoom (GNOME Text Editor's
shape) is a separate project.

### 2.4 The forwarder question, re-derived

Today's pane re-exports ~20 one-liners onto `code_editor` (lines 457-599)
with the stated reason that `MainWindow` should talk to "the one facade for
the editor" rather than reach into `CodeEditor` (comment at 540-544). After
the split that reason changes meaning: the pane's job becomes *which*
editor is active (routing by kind), while *how* to search a text editor is
already `CodeEditor`'s own, fully public API. Re-typing that API on the pane
would re-create the thing the split removes — a pane that assumes the active
tab is a `CodeEditor`.

Sorting the twenty by who actually calls them (doc comments and
`src/lib/dev-server/index.vala:14-30`, `91-172`; `main-window/index.vala`):

| Group | Members | Real callers |
|---|---|---|
| **A. DevServer-only, document-specific** | `active_content`, `set_active_content`, `set_active_cursors`, `get_active_cursors`, `save_path`, and `code_editor` for `key_press`/`select_all` | `DevServer` only (`GetActiveText`, `SetActiveText`, `SetActiveCursors`, `GetActiveCursors`, `SaveTab`, `KeyPress`, `SelectAll`). Their own doc comments say they exist "only because [DevServer] needed to reach them from outside". |
| **B. The text-search surface** | `has_focus`, `primary_selection_text`, `grab_focus`, `set_search_text`, `set_search_options`, `search_next`, `search_previous`, `compute_replace_current_match`, `compute_replace_all`, `apply_external_edits`, `land_after_replace`, `forget_current_match`, `select_last_match`, `select_all_occurrences`, + the `search_position_changed` signal | `MainWindow`'s FindBar glue (lines 159-165, 508-518, 604-681) for all of them; `DevServer` for four (`SearchSetText`, `SearchSetOptions`, `SearchNext`, `SearchPrevious`) and the signal. Every one is a `CodeEditor` member. |
| **C. Pane-level by nature** | `open_paths`, `active_document_path`, `linked_folder_path`, `search_in_files`, `current_find_in_files_query`, `close_active`, `save_active`, `save_as_active` | both — and they stay on the pane because the registry/active kind is what answers them. Not forwarders. |
| **D. Document entry points `MainWindow` drives** | `open`, `new_untitled`, `is_dirty`, `discard_tab`, `file_moved`, `set_decorations`, `set_diff_base_provider` | `MainWindow` (explorer wiring, settings, folder link/unlink), some also `DevServer`. Kept as one-line forwarders (§2 item 8). |

Design:

- **Group A moves off the pane entirely.** The pane exposes
  `public EditorPane.TabDocument document_tab { get; private set; }` — the
  same "expose the sub-facade DevServer needs" pattern the pane already uses
  for `code_editor` (lines 100-101) and `MainWindow` uses for `editor_pane`
  (line 52). `DevServer` calls `current_editor_pane ().document_tab
  .active_content` and so on. `code_editor` stays on the pane as a `get`
  returning `document_tab.code_editor`: its two `MainWindow` callers
  (`toggle_word_wrap` 409, the settings.json watch 429) are about the
  display-wide font provider, not about any tab, and `DevServer`'s
  `key_press`/`select_all` keep working unchanged. The redundancy with
  `document_tab.code_editor` is accepted for not touching those call sites.
- **Group B collapses into one routed property.** `ITabKind` declares
  `public virtual CodeEditor? search_editor { get { return null; } }` — the
  editor FindBar acts on, non-null exactly for a kind that declares
  `TEXT_SEARCH`. `TabDocument` returns its `code_editor`. The pane exposes
  `public CodeEditor? search_editor { get { return active_kind?.search_editor; } }`.
  `MainWindow`'s FindBar glue becomes `editor_pane.search_editor?.set_search_text
  (text)` etc. — the `?.` form the file already uses (`settings_monitor?.cancel ()`,
  line 212). With FindBar open and a non-searchable tab activated, every
  call no-ops, which is what today's "search the emptied hidden buffer"
  amounted to. `open_find ()` (508-518) reads `search_editor.has_focus`/
  `primary_selection_text` only after the `TEXT_SEARCH` gate, so it is
  non-null there. `search_position_changed` becomes an `ITabKind` signal
  (`TabDocument` re-emits its editor's); `wire_kind` re-emits it from the
  pane only while that kind is active, so `MainWindow` and `DevServer` keep
  connecting to `editor_pane.search_position_changed` as today.
  `DevServer`'s four search methods call `search_editor` the same way; a
  null target there should `throw new DBusError.FAILED ("the active tab has
  no text search")` rather than silently no-op — a body change to existing
  methods, not a new surface (§5 flags the throw-vs-no-op choice).
  This is the one forward-looking seam the plan keeps on purpose: when the
  deferred "Ctrl+F on Find Results" lands (§3.6), `TabFindResults` adds
  `TEXT_SEARCH` and returns its embedded `code_editor` from `search_editor`,
  and nothing in `MainWindow` or the pane changes.
- **Group D stays as seven forwarders**, by the facade rule as it still
  applies: these are the pane's own verbs ("open this path", "this file
  moved", "here are the decorations for the linked folder"), and `open` is
  where kind selection by path will live.

Net: 7 forwarders + 3 exposed sub-facades (`document_tab`, `code_editor`,
`search_editor`), down from ~20 forwarders + 1 (`code_editor`). Exposing a
`CodeEditor` through `ITabKind`/the pane is within the facade rule: it is a
facade object, not a `Gtk.Widget` subclass, and the pane already exposes one.
The comment at 540-544 is deleted with the forwarders it justified.

## 3. Tab-kind dispatch: the `ITabKind` contract

### 3.1 The problem, grounded

`MainWindow.on_key_pressed` (`main-window/index.vala:836-933`):

- Ctrl+Plus/Minus/0 (lines 886-897) call `editor_pane.code_editor.zoom_in ()`
  etc. — "the active tab is a CodeEditor" baked in. It only *happens* to do
  the right thing on Find Results because `zoom_level` is static and the
  font CSS is display-wide, so the hidden editor's zoom also re-renders the
  results' embedded editor. An image-preview tab would get its font zoomed
  instead of its picture.
- Ctrl+H (lines 915-929) branches on `editor_pane.is_find_results_active ()`
  by name. Ctrl+F (line 907) doesn't, so today Ctrl+F on Find Results opens
  FindBar over the deliberately-emptied hidden buffer — while the matching
  menu item is correctly disabled by `update_find_menu` (line 1072), a
  second by-name check.
- `is_find_results_active ()`'s own doc comment (editor-pane/index.vala:425-433)
  points at an `editor-pane-tab-dispatch.md` that was never written (checked
  `git log --all`); its premise — a second internal tab kind — is now the
  roadmap.

### 3.2 Options weighed

| Option | Verdict |
|---|---|
| **A. Keep explicit branches in `MainWindow`** (`is_find_results_active ()`, then `is_image_active ()`, …) | Rejected. O(kinds × shortcuts) in the composition root; `MainWindow` learns every kind by name; the Ctrl+F gap shows it already drifts. |
| **B. Generalized kind queries on the pane** (`active_kind_is (Kind.FIND_RESULTS)`), MainWindow still switches | Rejected for the same reason, one level down — the pane would still have to know what each kind means for each shortcut. |
| **C. Typed per-shortcut methods on an interface each kind implements, pane forwards to the active kind, plus a capability query for the cases where `MainWindow` must choose between a tab-local action and a window-level panel** | **Chosen.** Routing lives in the pane (which already composes the kinds), semantics live in each kind, `MainWindow` stays kind-agnostic. Same shape as `IGlobalPanel`: `MainWindow` asks registered panels `is_open`/`close ()` without knowing what's inside. |
| **D. One `bool handle_shortcut (TabAction action)` enum method** | Not chosen. It's option C with the method names erased: every kind re-switches on the enum, "who implements zoom?" is no longer greppable, and `MainWindow` still needs a separate capability query for the Ctrl+H fallback. Worth revisiting only if a command palette (`COMMAND_BAR_RESEARCH.md`) later wants named commands — at which point the natural target is `Gio.Action` groups inserted by the active kind, not a home-grown enum. Out of scope now: the window's shortcuts are a hand-rolled `Gtk.EventControllerKey` switch, not GActions. |
| **E. Hand each kind the `TabBar`, let kinds handle key events themselves** | Rejected. The window owns the key controller and must keep owning Ctrl+S/N/O/W; and `src/views/CLAUDE.md` says a View that needs a sibling it doesn't own emits a signal — kinds don't get a `TabBar` reference. |

Rules respected, by citation:

- *"No Controller layer: a View that needs a Model calls it directly; a View
  that needs a sibling View it doesn't own emits a signal for whichever View
  composes both."* — `ITabKind` is not a new layer between `MainWindow` and
  the pane; it is the contract between the pane and the sub-components it
  already composes. Nothing new sits between `MainWindow` and
  `EditorPaneWidget`; `MainWindow` keeps calling plain pane methods. Kinds
  talk to `TabBar` only via signals the pane wires (decided: the six chrome
  signals are the right shape — a child emitting to the parent that owns the
  sibling, same as any frontend component tree).
- *"A component composing several subcomponents owns their coordination
  itself: wiring their signals, deciding what each one does next."*
  (`docs/ARCHITECTURE.md`) — the pane decides *which* kind gets a shortcut;
  the kind decides *what it does*.
- *"A View is a facade: owns real widgets internally, exposes plain methods
  + signals — never a `Gtk.Widget` subclass passed around directly."* —
  `ITabKind.widget` is a `Gtk.Widget` *property* on a facade object, the same
  as `IGlobalPanel.widget` and every view's `widget` today; `search_editor`
  is a facade object (§2.4).

Deliberate deviation, stated: `ITabKind` carries signals and non-abstract
(default no-op / default-null) members. Vala interfaces allow both; the
codebase's existing interfaces are abstract-only. The defaults are what keep
"add a shortcut" from forcing every kind to add an empty override.

Set aside, not pursued here: a new `EditorViewWidget` (`editor-view/index.vala`,
which doesn't exist today) composing `editor_pane` + `find_bar` +
`find_in_files_bar`, so that the capability checks and the Ctrl+F/Ctrl+H
routing in §3.6 live in the View that composes both instead of in
`MainWindow`. That is the legitimate end state under `src/views/CLAUDE.md`'s
"a View composing several real sub-components absorbs what a Controller used
to do" rule — `MainWindow` is today's composer only because nothing sits
between it and the three editor-view components. It is a larger-scoped
change than this plan and is explicitly out of scope; §3.6 writes the
routing into `MainWindow`, where the switch already is.

Also deferred to that same future `EditorViewWidget` work, raised during
implementation review, not acted on now: "Reveal in Sidebar" and "Copy
Relative Path" should show a plain OK dialog (`Dialogs.show_error`,
`src/views/lib/dialogs.vala:231`, already exists) instead of silently
doing something meaningless when there's no linked folder at all, or the
open file lives outside the linked one — "Copy Path" is unaffected
(always absolute). Needs `has_linked_folder` (today tracked only on
`MainWindow`) visible to whatever ends up deciding this, which is exactly
the kind of routing `EditorViewWidget` would own. Options stay visible
and behave as today (no guard) until then.

### 3.3 The contract

`src/views/editor-view/editor-pane/_i-tab-kind.vala`:

```vala
namespace EditorView.EditorPane {
  /** What the active tab can do, for the shortcuts/menu items whose fallback is a window-level panel rather than a no-op. */
  [Flags]
  public enum TabCapability {
    /** FindBar applies: Ctrl+F, the Find menu's Find…/Replace… items, and Ctrl+H falling back to FindBar's replace mode. search_editor is non-null. */
    TEXT_SEARCH,
    /** Ctrl+H is handled inside the tab itself (open_replace ()). */
    INLINE_REPLACE,
  }

  /**
   * One object per pane per *kind* of tab (a document, Find Results, …),
   * owning every tab of that kind and rendering whichever one is active.
   * EditorPaneWidget routes TabBar gestures and window shortcuts here and
   * turns the chrome signals below into TabBar calls — a kind never
   * touches TabBar itself.
   */
  public interface ITabKind : Object {
    /** Shown in the pane's editor area while a tab of this kind is active. */
    public abstract Gtk.Widget widget { get; }
    public abstract TabCapability capabilities { get; }
    /** The editor FindBar acts on — non-null exactly when capabilities has TEXT_SEARCH. */
    public virtual CodeEditor? search_editor { get { return null; } }

    public abstract bool owns (string uri);
    public abstract bool is_dirty (string uri);
    /** `uri` just became the active tab — render it. */
    public abstract void show (string uri);
    /** No tab of this kind is active any more (another kind's tab is, or none) — release whatever show () bound. */
    public abstract void hide ();
    /** Same unsaved-changes flow as the tab's own close button; may end up not closing. Emits tab_removed when it does. */
    public abstract async void close_tab (string uri);
    /** Window teardown. */
    public abstract void close ();

    // Shortcut semantics. No-op by default — a kind overrides only what
    // the shortcut means for it.
    public virtual void zoom_in () { }
    public virtual void zoom_out () { }
    public virtual void reset_zoom () { }
    /** Only reached when capabilities has INLINE_REPLACE. */
    public virtual void open_replace () { }
    /** Make `uri` permanent if it was a preview — a no-op for kinds without previews. */
    public virtual void promote (string uri) { }

    // Chrome, for the pane to forward to TabBar (mirrors TabBar.add_tab/
    // remove_tab/rename_tab/mark_*). `title` is the clean user-facing
    // identity (a real path, or a display name) — see TabBar.add_tab's
    // own `tooltip_path` doc comment. `has_pathname` is whether the tab
    // is backed by a real on-disk path right now — false for Untitled-N
    // and Find Results — and gates TabBar's Copy Path group; it can flip
    // to true in tab_renamed (Save As on an untitled tab).
    public signal void tab_added (string uri, string name, string folder_name, bool preview, string title, bool has_pathname);
    public signal void tab_removed (string uri);
    public signal void tab_renamed (string old_uri, string new_uri, string name, string folder_name, string title, bool has_pathname);
    public signal void tab_marks_changed (string uri, bool modified, bool deleted, bool unsynchronized);
    public signal void tab_preview_changed (string uri, bool preview);
    public signal void tab_decoration_changed (string uri, FileDecoration.State? decoration);
    public signal void activate_requested (string uri);
    /** Re-emitted from search_editor; the pane re-emits it only while this kind is active. */
    public signal void search_position_changed (int position, int count);
  }
}
```

Notes on the shape:

- `capabilities` is `{ get; }` only — the `{ get; construct; }` interface
  property bug in `docs/decisions.md` doesn't apply; `IGlobalPanel.is_open`
  is the precedent.
- Zoom has no capability flag: every kind either zooms its own thing or
  ignores it. `TEXT_SEARCH`/`INLINE_REPLACE` exist because for Ctrl+H the
  alternative to "the tab handles it" is "`MainWindow` opens FindBar", and
  only `MainWindow` can do that — the pane can't open a sibling it doesn't
  own.
- `activate_requested` rather than the kind setting `active` itself: which
  tab is active is pane state (`TabBar.set_active`, `editor_area_bin`), so
  a kind asks.
- `promote` on the interface (not just on `TabDocument`) because the
  gesture that triggers it (`TabBar.tab_double_clicked`/`preview_demoted`)
  is keyed by uri and the pane shouldn't have to know which kinds have
  previews.
- `has_pathname` is a boolean, not the pathname itself: `TabBar` only needs
  a yes/no to decide what to build, and the pane already has the path as
  `title` for the handler. `TabBar.add_tab`/`rename_tab` take it as a
  trailing parameter and store it on `TabBarPill` as a public field
  beside `tooltip_path`; `TabBar.show_context_menu` wraps "Reveal in
  Sidebar" *and* the Copy group — the whole block from the separator
  after "Close All" down through "Copy Relative Path" — in one
  `if (pill.has_pathname)`, since both are owner-decided to collapse
  together, not just the Copy items: neither makes sense without a real
  on-disk path.

### 3.4 Implementations

`TabDocument : Object, ITabKind` — `capabilities = TEXT_SEARCH`;
`search_editor` → its `code_editor`; `zoom_in/out/reset` →
`code_editor.zoom_*`; `show (uri)` = the document half of today's
`show_in_editor`; `hide ()` = the Find-Results half (read-only, empty text,
`unbind`, banner off, `diff_tracker.set_document (null, …)`); `close_tab` =
today's `close_tab` with `Dialogs.confirm_discard (widget, document.name)`
inline; `promote` = today's `promote` guarded by `is_preview`. Emits
`tab_added (…, document.pathname != null)` and, from `save_as_path`/
`file_moved`, `tab_renamed (…, true)`.

`TabFindResults : Object, ITabKind` — `capabilities = INLINE_REPLACE`;
`open_replace` = today's `open_replace_row` (`replace_button.active = true`);
`zoom_*` → its own embedded `code_editor.zoom_*` (identical effect to today
because `zoom_level` is static — the override exists so the behavior is
*declared*, not accidental); `owns (uri)` = `uri == FIND_RESULTS_TAB_URI`;
`show`/`hide` flip a private `is_active` that `active_query` reads;
`close_tab` emits `tab_removed` (nothing to confirm); `is_dirty` = false;
`tab_added (…, has_pathname: false)`. `search_editor` stays at the default
null for now (§3.6, Ctrl+F deferral).

A future `TabImagePreview : Object, ITabKind` — `capabilities = 0`,
`zoom_*` scale the picture, `show (uri)` loads it. Ctrl+F/H become no-ops on
it with no `MainWindow` change; Ctrl+Plus zooms the image with no
`MainWindow` change. (Routing `open ("foo.png")` to it is a pane-level
decision for that day — a `kind_for_path ()` in `EditorPaneWidget.open`;
not part of this plan.)

### 3.5 The pane's surface

```vala
public void zoom_in ()    { active_kind?.zoom_in (); }
public void zoom_out ()   { active_kind?.zoom_out (); }
public void reset_zoom () { active_kind?.reset_zoom (); }
public void open_replace () { active_kind?.open_replace (); }
public bool active_tab_supports (EditorPane.TabCapability capability) {
  return active_kind != null && capability in active_kind.capabilities;
}
public CodeEditor? search_editor { get { return active_kind?.search_editor; } }
```

### 3.6 `MainWindow` after

`on_key_pressed`, lines 886-929 become:

```vala
case Gdk.Key.plus:
case Gdk.Key.equal:
case Gdk.Key.KP_Add:
  editor_pane.zoom_in ();
  return true;
case Gdk.Key.minus:
case Gdk.Key.KP_Subtract:
  editor_pane.zoom_out ();
  return true;
case Gdk.Key.@0:
  editor_pane.reset_zoom ();
  return true;
case Gdk.Key.f:
  if (shift) {
    if (has_linked_folder) {
      open_find_in_files ();
    }
  } else if (editor_pane.active_tab_supports (EditorView.EditorPane.TabCapability.TEXT_SEARCH)) {
    open_find ();
  }
  return true;
case Gdk.Key.h:
  on_replace_shortcut ();
  return true;
```

Ctrl+H gets its own private dispatcher — the keybinding is the only caller:

```vala
/** Ctrl+H: the tab's own inline replace if it has one, else FindBar's replace mode for a text tab, else nothing. */
private void on_replace_shortcut () {
  if (editor_pane.active_tab_supports (EditorView.EditorPane.TabCapability.INLINE_REPLACE)) {
    editor_pane.open_replace ();
  } else if (editor_pane.active_tab_supports (EditorView.EditorPane.TabCapability.TEXT_SEARCH)) {
    set_active_bottom_panel (find_bar);
    find_bar.show_replace ();
  }
}
```

The Find menu's "Replace…" item (`build_find_menu`, lines 1047-1050) is
**not** wired to that dispatcher. Decided: its click handler keeps today's
exact body (`set_active_bottom_panel (find_bar); find_bar.show_replace ();`)
and is gated on `TEXT_SEARCH` alone, same as "Find…" — it stays disabled on
Find Results. `update_find_menu` (line 1072):

```vala
bool can_search = editor_pane.active_tab_supports (EditorView.EditorPane.TabCapability.TEXT_SEARCH);
find_item.sensitive = can_search;
replace_item.sensitive = can_search;
find_in_files_item.visible = has_linked_folder;
```

FindBar glue (lines 159-160, 508-518, 604-681) goes through
`editor_pane.search_editor?.…` per §2.4; `on_search_position_changed`
keeps connecting to `editor_pane.search_position_changed`.

`has_open_tabs` (line 67) is no longer needed as a gate for Ctrl+F/H —
`active_tab_supports` is false with no active tab — but stays for
`on_has_open_tabs_changed` closing FindBar when the last tab goes.
`set_active_state` already calls `update_find_menu ()` on every activation
(line 1130), so the menu tracks kind switches with no new signal.

Behavior deltas, all decided:

- Ctrl+F on Find Results becomes an explicit no-op (today it opens FindBar
  over the emptied hidden buffer, while the menu item is disabled). The
  owner agrees this is a real gap — `TabFindResults` already embeds a
  `CodeEditor` that can search — and is explicitly deferring the fix to a
  future sprint. The `search_editor` seam in §2.4 is where it plugs in;
  nothing more is designed here.
- "Replace…" in the Find menu: unchanged behavior, gated on `TEXT_SEARCH`.
- Ctrl+Plus/Minus/0 with no tab open becomes a no-op (today it bumps the
  static zoom level invisibly).

## 4. Migration: six stages, each shippable on its own

The owner's direction: develop this in stages, not one pass. Each stage
below is scoped so it builds warning-free, passes `meson test -C builddir`,
and could be committed and left alone for a week before the next one
starts — no stage leaves a half-moved concept behind that the next stage
must finish. The stages are ordered so the *external* contract
(`MainWindow` ↔ pane) is settled first and the big extraction last.

On verification, plainly: views are untested as units by policy
(`src/views/CLAUDE.md`), and `DevServer`'s D-Bus surface cannot simulate
real UI interaction (clicks, menu items, the change banner, dialogs). That
gap is known and accepted, is worked around with manual validation today,
and is to be solved later by a different tool — **not** by growing
`DevServer` for this plan. So: no new `DevServer` methods, no
`active_tab_supports` over D-Bus. Each stage names what the existing system
suite covers (`tests/system/tabs/close-tab-test.vala`,
`tests/system/find/find-wrap-test.vala`, `tests/support/smoke-test.vala`,
the cursors/editing tests — all driving `open_tab`/`new_file`/
`set_active_text`/`key_press`/`search_*` through today's `DevServer`) and
what is checked by hand. The manual checklist is the verification for the
rest, same as today, not a stopgap to engineer away.

**Manual checklist** (used by every stage that touches the area; ~5 minutes):

1. Open a file; Ctrl+Plus/Minus/0 zoom the text.
2. Ctrl+Shift+F, search; Find Results tab opens and is active; Ctrl+Plus
   zooms its text; Ctrl+H opens its inline replace row; Escape closes it.
3. On Find Results: Find menu → "Find…"/"Replace…" disabled; Ctrl+F does
   nothing (from Stage 2 on).
4. Switch back to the file: Ctrl+H opens FindBar in replace mode; Find menu
   items enabled.
5. Edit the file externally; banner appears; "Discard and Reload" works.
6. New file (Ctrl+N), type, Ctrl+S → Save As dialog; tab re-keys to the
   path; Copy Path group appears in its context menu only after the save
   (from Stage 3 on); Find Results/Untitled context menus have no Copy
   group.
7. Single-click two files in the sidebar: the second preview replaces the
   first; double-click promotes.
8. Close the active tab with others open: the rightmost remaining activates.
9. Close the last tab: empty state; Ctrl+Plus does nothing.

**Stage 0 — rename `find-results/` → `tab-find-results/`.**
`git mv` the three files; `FindResults` → `TabFindResults`,
`FindResultsLanguageHighlighter` → `TabFindResultsLanguageHighlighter`;
resource path in the constructor (`find-results/index.vala:135`);
`styles/find-results.css` → `styles/tab-find-results.css` (constructor line
256); `src/meson.build`, `data/meson.build`, the gresource XML; doc-comment
mentions in `find-in-files-bar/index.vala:7`, `models/find-in-files-query.vala:7`.
No logic change.
*Ships as:* a pure rename commit. *Covered by:* full build + existing suite;
checklist item 2.

**Stage 1 — the dispatch surface, before any extraction.**
Add `zoom_in`/`zoom_out`/`reset_zoom`/`open_replace`/`active_tab_supports`
to `EditorPaneWidget` and the `TabCapability` enum in the new
`_i-tab-kind.vala` (the enum only; the interface comes in Stage 2).
Implement them with the existing `is_find_results_tab (active_path)` branch
for now. Rewrite `MainWindow` per §3.6 (key switch, `on_replace_shortcut`,
`update_find_menu`); delete `is_find_results_active ()` and
`open_internal_replace ()`. The Group B forwarders (§2.4) stay for this
stage — `search_editor` arrives with the interface.
*Ships as:* `MainWindow` no longer names a tab kind; three decided behavior
deltas land here. *Covered by:* `find-wrap-test` (Ctrl+F path on a document
tab); checklist items 1-4, 9.

**Stage 2 — `ITabKind`, with `TabFindResults` as its first implementor, and
the `has_pathname` chrome.**
Finish `_i-tab-kind.vala` (§3.3). `TabFindResults` implements it and absorbs
`search_in_files`'s body, `last_find_in_files_query`, `search_generation`,
`DEFAULT_FIND_IN_FILES_CONTEXT_LINES`, `FIND_RESULTS_TAB_URI` and
`open_or_focus_find_results_tab` (§1.3). `TabBar.add_tab`/`rename_tab` gain
`bool has_pathname`, `TabBarPill` stores it, `show_context_menu` gates the
Copy group on it (§1.1) — the pane passes `document.pathname != null` for
its own documents and the signal carries it for Find Results. In the pane:
add the `tabs` registry and `wire_kind ()`, a `kind_of (uri)` lookup, and
route every `is_find_results_tab` branch (`show_in_editor`, `activate`,
`finish_close`, `close_tab`, `close_others`/`close_all`, `save_uri`)
through `kind_of (uri) != null ? kind : <today's document code>`. Add
`search_editor` to the pane as `kind_of (active_path) != null ? null :
code_editor` for now, and switch `MainWindow`'s FindBar glue and
`DevServer`'s four search methods to it (§2.4); delete the Group B
forwarders. The results tab's `Document.internal_tab` entry leaves
`documents`; delete `Document.internal_tab`/`is_internal`/`is_saveable`, the
two `is_saveable` guards, and the three `document-test.vala` cases.
The Stage 1 dispatch methods now forward to `active_kind` for Find Results
and to `code_editor` otherwise.
*Ships as:* Find Results is a self-contained kind; the pane's registry and
routing exist; the model API is trimmed. *Covered by:* `document-test` (the
removed cases must be gone, the rest green); `find-wrap-test` and the
`search_*` DSL for the `search_editor` route on a document tab; checklist
items 2, 3, 6 (Copy group), 8.
Confirmed, part of this stage (not optional): one harness-side test,
`tests/system/find/find-in-files-tab-test.vala`, calling the **existing**
`DevServer.find_in_files` (`src/lib/dev-server/index.vala:169-172`) through
a thin wrapper added to `tests/support/system-test-session-search.vala` —
same pattern the existing cursor/selection system tests already drive
over D-Bus, nothing new added to `DevServer` itself — then asserting
`get_active_tab () == "Find Results"`, `list_open_tabs ()` contains both
tabs, and that `close_tab ("Find Results")` re-activates the file.

**Stage 3 — move the banner and watcher.**
`git mv` `_change-banner.{vala,blp}` and `_file-watcher.vala` into
`tab-document/`; rename classes to `TabDocumentChangeBanner`/
`TabDocumentFileWatcher`, namespace to `EditorView.EditorPane`; resource
path in the banner's constructor; `styles/editor-pane.css` →
`styles/tab-document.css`; build files and gresource XML. The pane still
constructs and uses them until Stage 4. Pure move.
*Ships as:* a rename commit. *Covered by:* build; checklist item 5.

**Stage 4 — extract `TabDocument`.**
Create `tab-document/index.vala` implementing `ITabKind`; move everything
in §1.2; the pane gets `document_tab` (public) and `code_editor` becomes a
getter over it; `DevServer`'s Group A methods switch to `document_tab.*`;
the pane's remaining `documents`-based branches become `kind.*` calls so it
reads as §2; `search_editor` becomes `active_kind?.search_editor`;
`TabBar.confirm_unsaved_close` goes. Two orderings to get right: (1) in
`open_preview`, load and `tab_added` the new document *before* evicting the
old preview — decided as a fix: `tab_removed (old)` must not arrive while
`old` is still active (it would trigger the pane's fallback activation and
flash an unrelated tab), and today's evict-first order (lines 653-661)
loses the old preview even when `Document.load` throws; (2) `tab_renamed`
→ `tab_removed` in the save-on-close-of-untitled path (lines 960-964), so
the registry is re-keyed before the removal lands.
If the diff is too large to review in one go, split at this seam and ship
both halves:
- *4a* — `TabDocument` owns the editor surface only (`code_editor`,
  banner, watcher object, `editor_config`, `diff_tracker`, `show (Document)`
  / `hide ()`, `on_text_changed`'s diff half), and re-emits
  `text_changed`/`reload_requested`/`file_changed` for the pane, which still
  owns `documents` and the save/open/reload logic.
- *4b* — move `documents` and the I/O into `TabDocument`, turn the
  re-emitted signals back into private handlers, and give the pane its
  final registry-only shape.
*Ships as:* the pane at ~250-300 lines. *Covered by:* the whole system
suite (every test opens/edits/saves/closes document tabs through
`DevServer`, now via `document_tab`); checklist in full.

**Stage 5 — cleanup.**
Doc comments that name moved things (`code-editor/index.vala:304, 314, 320,
338`, `_cursors.vala:91, 99, 574`, `_source-view.vala:77`,
`models/document.vala:44-45, 55, 81, 169`, `models/find-in-files-search.vala:33,
74`, `dev-server/index.vala:17-24`): update the ones that become false, leave
the rest. Add `tab-document/` and `tab-find-results/` to the
`src/views/CLAUDE.md` layout example next to `tab-bar/`. Confirm zero
warnings; `meson test` once more.
*Ships as:* a `chore:` commit.

## 5. Still open

1. **`DevServer` search methods on a non-searchable tab** (§2.4) —
   confirmed: must return *something* observable, not today's silent
   no-op via `?.` (a test driving search on Find Results by mistake
   should not pass silently). Exact shape left open on purpose — throwing
   `DBusError.FAILED` vs. a `bool`/empty-result return the caller can
   check — pick whichever fits the rest of `DevServer`'s own error
   conventions; owner has no preference between the two.

Deferred by decision, recorded so they aren't re-raised: Ctrl+F on Find
Results (future sprint; the `search_editor` seam is where it lands);
`EditorViewWidget` composing pane + find bars (future direction, §3.2);
`kind_for_path ()` for an image-preview kind (the day it exists).

## 6. Decision log

One line each; the body above reflects all of them.

1. Chrome-signal fan-out — confirmed; kinds emit, pane turns into `TabBar` calls (§2 item 3, §3.2).
2. One `TabDocument` per pane — confirmed, matching VS Code/status quo over GNOME Text Editor's per-tab view+zoom (§2, closing paragraph).
3. Lazy `TabFindResults` — confirmed (§2 item 10).
4. Forwarder volume — reopened and re-derived: three exposed sub-facades (`document_tab`, `code_editor`, `search_editor`) + seven real forwarders, split by actual caller (§2.4).
5. Remove `Document.internal_tab`/`is_internal`/`is_saveable` + tests — confirmed (§1.1, §1.3, Stage 2).
6. `TabCapability` stays in `EditorPane`, spelled out at call sites — confirmed; `EditorViewWidget` noted as a future direction only (§1, §3.2).
7. Behavior deltas — Ctrl+F on Find Results stays a no-op with the fix deferred; Find menu "Replace…" unchanged and gated on `TEXT_SEARCH` only, not wired to the Ctrl+H dispatcher; zoom with no tab is a no-op (§3.6).
8. Preview-eviction order — confirmed as a fix (Stage 4).
9. Copy Path/Copy Relative Path *and* Reveal in Sidebar on synthetic tabs — confirmed: omit the whole block together; `has_pathname` threaded through `tab_added`/`tab_renamed` and `TabBar.add_tab`/`rename_tab` (§1.1, §3.3, Stage 2).
10. Testing — no `DevServer` growth; existing suite + manual checklist, named per stage; plan executed in stages (§4).
11. `DevServer` search methods on a non-searchable tab — confirmed: must return something observable, not a silent no-op; exact shape (throw vs. return value) left to implementation taste (§5).
12. Stage 2's harness-side Find Results test — confirmed, included (not optional): same D-Bus-driven pattern the existing cursor/selection system tests already use, nothing added to `DevServer` itself (Stage 2).
