/**
* The reusable code editor: a Gtk.ScrolledWindow holding one
* CodeEditorSourceView, composed of sub-components the same way a Vue SFC
* composes child components — cursor state and editing transactions live
* in CodeEditorCursors (_cursors.vala), keys/mouse/context menu in
* CodeEditorInput, the clipboard in CodeEditorClipboard, Find/Replace in
* CodeEditorSearch, the git change bars in CodeEditorChangeGutter,
* syntax highlighting in CodeEditorSyntaxHighlighter. Plural "Cursors": it's
* the manager for however many cursors exist, not one instance per
* cursor — see its own doc comment for why (checked against VS Code's
* real ViewCursors/ViewCursor split).
*
* Knows nothing about files, tabs, or disk: the "File Has Changed on
* Disk" banner and the Save As dialog belong to EditorView.EditorPane.TabDocument, which is what
* lets this same component also show Find Results. What it can't work
* out on its own comes in as "props": which cursor set/undo stack to
* work on, indent settings, git hunks — see bind()/set_indent()/
* set_hunks().
*
* Theming is split the same way VS Code's own real ViewCursors does it
* (checked its source: registerThemingParticipant lives right in
* viewCursors.ts, styling only what that file itself owns) — each
* sub-component reacts to Adw.StyleManager on its own, for its own tags'
* colors, rather than one central "theme" object reaching into siblings
* it doesn't otherwise know about. What's left here is only what's
* genuinely CodeEditor's own: the drop-feedback CSS, the editor font, and
* the buffer's style scheme (EditorTheme's).
*
* set_text() routes its actual buffer write through
* cursors.load_text() rather than text_view.buffer directly — only
* CodeEditorCursors holds the updating_programmatically guard that keeps
* on_insert_text_native()/on_delete_range_native() from misreading a
* freshly-loaded document as an untracked user edit.
*/
public class CodeEditor : Object {
  private Gtk.ScrolledWindow scrolled_window;
  // Wraps scrolled_window so a floating toolbar (CodeEditorConflicts') can sit over the editor in widget coordinates.
  private Gtk.Overlay overlay = new Gtk.Overlay ();
  private CodeEditorSourceView text_view;
  private UserSettings settings;
  private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
  private CodeEditorCursors cursors;
  private CodeEditorClipboard clipboard;
  private CodeEditorInput input;
  private CodeEditorSearch search;
  private CodeEditorChangeGutter change_gutter;
  private CodeEditorScrollbar scrollbar;
  // Only in diff mode (show_diff()): the old/new/marker gutter and the row backgrounds.
  private CodeEditorDiffGutter? diff_gutter = null;
  private bool diff_gutter_attached = false;
  private GitDiff.FileDiff? shown_diff = null;
  private CodeEditorSyntaxHighlighter syntax_highlighter;
  private CodeEditorLinePreview line_preview;
  private CodeEditorConflicts conflicts;
  /** What set_text() last showed — "" for none. Kept so the language can be worked out again when the packages change. */
  private string language_path = "";
  /** The language package named by hand for what is showing, over whatever `language_path` says — null for none. */
  private string? language_override = null;

  // How many passes scroll_to_top_line() gives the layout to settle — see reveal_settled().
  private const int SCROLL_SETTLE_PASSES = 3;

  /** A scroll_to_top_line() already queued, not yet run — same reasoning as pending_reveal_id. 0 means none pending. */
  private uint pending_scroll_id = 0;

  /** A reveal_offset() already queued, not yet run — see that method's own doc comment. 0 means none pending. */
  private uint pending_reveal_id = 0;

  public Gtk.Widget widget { get { return overlay; } }

  /** The real buffer, for a consumer's own tags/highlighting and for reads — never for writing content: only set_text() carries the guard that keeps a load from being recorded as an edit (see CodeEditorCursors.load_text()). */
  public GtkSource.Buffer buffer { get { return source_buffer; } }

  /**
   * Whether this editor refuses every edit — typing, Cut/Paste, Undo/
   * Redo, drag-to-move, Replace — while still navigating, selecting
   * (multi-cursor included), and copying. A property of this view, not
   * of whatever is bound to it: the same content could be shown
   * editable in one place and read-only in another (Monaco's own
   * EditorOption.readOnly, likewise not on its text model). Plain sugar
   * over GtkTextView's `editable`: that one flag is both what
   * CodeEditorCursors' own transactions check and what makes GTK refuse
   * its own native writes (IM composition, middle-click paste, unclaimed
   * bindings), which never go through those transactions at all.
   */
  public bool read_only {
    get { return !text_view.editable; }
    set { text_view.editable = !value; }
  }

  /** GtkSourceView's own line-number gutter — off for content that carries its own line numbers inline (Find Results). */
  public bool show_line_numbers {
    get { return text_view.show_line_numbers; }
    set { text_view.show_line_numbers = value; }
  }

  /** The VS Code-style indent guides — off for content whose leading whitespace isn't indentation (Find Results' own "  N: " prefixes would otherwise make every line look indented). */
  public bool show_indent_guides {
    get { return text_view.show_indent_guides; }
    set { text_view.show_indent_guides = value; }
  }

  /** Whether the real text view currently holds keyboard focus — MainWindow's own "was the user actually in the editor when they pressed Ctrl+F" check, read before FindBar.show_find() steals focus into the Find entry. */
  public bool has_focus { get { return text_view.has_focus; } }

  /**
   * The real primary selection's own text, "" if it's empty/collapsed.
   * Reads the native insert/selection_bound marks directly rather than
   * going through CodeEditorCursors' own CursorCollection: they always
   * mirror the primary cursor's own selection 1:1 (see render_cursors()'s
   * own doc comment) — MainWindow's own Ctrl+F prefill has no other
   * reason to reach past this View at all.
   */
  public string primary_selection_text {
    owned get {
      Gtk.TextIter start;
      Gtk.TextIter end;
      if (!source_buffer.get_selection_bounds (out start, out end)) {
        return "";
      }
      return source_buffer.get_text (start, end, false);
    }
  }

  /** The buffer's full content changed — re-emitted from the cursors sub-component, which is what actually mutates the buffer. Something outside this whole component still needs this to mark the document dirty/enable Save. */
  public signal void text_changed (string new_text);

  /** Re-emitted from the search sub-component — see FindBar's own "N of M" counter, wired to this wherever both are composed (see CodeEditorSearch's own doc comment). */
  public signal void search_position_changed (int position, int count);

  /** Re-emitted from the input sub-component — a Ctrl+click or a plain double-click released on the line it was pressed on, on any view (see CodeEditorInput's own on_pressed() comment). This component knows nothing about what that should *do*; that's entirely up to whoever's listening (Find Results' own filename/line hyperlinks). */
  public signal void link_click (int offset);

  // The handlers on things that outlive this editor, for close() to undo.
  private ulong settings_handler;
  private ulong languages_handler;
  private ulong theme_handler;

  /** `search_settings`, when given, is shared with other editors: one Find query for every tab of a pane. */
  public CodeEditor (UserSettings settings, GtkSource.SearchSettings? search_settings = null) {
    this.settings = settings;
    settings_handler = settings.changed.connect (apply_settings);
    text_view = new CodeEditorSourceView () {
      monospace = true,
      top_margin = 8,
      bottom_margin = 8,
      left_margin = 8,
      right_margin = 8,
      show_line_numbers = true,
      cursor_visible = false, // every caret is hand-drawn by CodeEditorSourceView instead — see its own doc comment
    };
    text_view.add_css_class ("code-editor");

    scrolled_window = new Gtk.ScrolledWindow () {
      vexpand = true,
      hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
      // The vertical bar is CodeEditorScrollbar's, over the view, with the git changes marked along it.
      vscrollbar_policy = Gtk.PolicyType.EXTERNAL,
      child = text_view,
    };

    cursors = new CodeEditorCursors (text_view);
    cursors.text_changed.connect ((text) => text_changed (text));
    conflicts = new CodeEditorConflicts (this, text_view);
    cursors.text_changed.connect (() => conflicts.schedule_scan ());
    overlay.child = scrolled_window;
    scrollbar = new CodeEditorScrollbar (text_view, scrolled_window.vadjustment);
    overlay.add_overlay (scrollbar);
    overlay.add_overlay (conflicts.widget);
    clipboard = new CodeEditorClipboard (text_view, cursors);
    input = new CodeEditorInput (text_view, cursors, clipboard);
    input.link_click.connect ((offset) => link_click (offset));

    search = new CodeEditorSearch (text_view, search_settings);
    search.search_position_changed.connect ((position, count) => search_position_changed (position, count));

    change_gutter = new CodeEditorChangeGutter ();
    text_view.get_gutter (Gtk.TextWindowType.LEFT).insert (change_gutter, 0);

    syntax_highlighter = new CodeEditorSyntaxHighlighter (text_view, scrolled_window.vadjustment);
    line_preview = new CodeEditorLinePreview (text_view, scrolled_window.vadjustment);
    languages_handler = Syntax.Languages.instance.changed.connect (apply_language);
    // The two don't know each other: this is what owns both.
    cursors.set_indentation (
      (offset) => syntax_highlighter.new_line_indent_change (offset),
      (offset, reference_offset, out levels) => syntax_highlighter.outdent_change (offset, reference_offset, out levels)
    );

    install_css ();
    apply_settings ();

    // GtkSource.Buffer paints with a StyleScheme's own fixed colors
    // instead of following the app's GTK theme, so it stays put through
    // a light/dark switch unless told otherwise.
    theme_handler = EditorTheme.instance.changed.connect (apply_style_scheme);
    apply_style_scheme ();
  }

  /**
   * Takes this editor out of the app for good: off every singleton it
   * listens to, every pending idle and timer gone. An editor lives as
   * long as its tab; without this, a closed tab would keep repainting
   * on every theme or settings change, unseen.
   */
  public void close () {
    settings.disconnect (settings_handler);
    Syntax.Languages.instance.disconnect (languages_handler);
    EditorTheme.instance.disconnect (theme_handler);
    if (pending_scroll_id != 0) {
      Source.remove (pending_scroll_id);
      pending_scroll_id = 0;
    }
    if (pending_reveal_id != 0) {
      Source.remove (pending_reveal_id);
      pending_reveal_id = 0;
    }
    conflicts.close ();
    scrollbar.close ();
    cursors.close ();
    search.close ();
    syntax_highlighter.close ();
    line_preview.close ();
    change_gutter.close ();
    text_view.close ();
  }

  /** Rules themselves live in styles/code-editor.css, not here — see GlobalCss.install_from_resource()'s own doc comment for why. */
  private void install_css () {
    GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/code-editor.css");
  }

  private void apply_style_scheme () {
    source_buffer.style_scheme = EditorTheme.instance.scheme;
    apply_diff_colors ();
    conflicts.reload_colors ();
  }

  /**
   * Turns this editor into an inline diff of `diff`: read-only, the
   * native line numbers (and the change gutter) swapped for
   * CodeEditorDiffGutter's old/new/marker columns, the text being every
   * line of the diff in order — so `path`'s own language colors it —
   * with added and removed rows tinted edge to edge
   * (CodeEditorSourceView's row bands). Call again with a new diff to
   * refresh in place, or show_plain_text() for a file with only one
   * side; the change gutter never comes back, a diff view is one.
   */
  public void show_diff (GitDiff.FileDiff diff, string path) {
    read_only = true;
    show_line_numbers = false;
    var gutter = text_view.get_gutter (Gtk.TextWindowType.LEFT);
    if (diff_gutter == null) {
      gutter.remove (change_gutter);
      diff_gutter = new CodeEditorDiffGutter (text_view);
    }
    if (!diff_gutter_attached) {
      diff_gutter.attach (gutter);
      diff_gutter_attached = true;
    }
    shown_diff = diff;
    diff_gutter.set_diff (diff);
    var text = new StringBuilder ();
    for (uint i = 0; i < diff.lines.length; i++) {
      if (i > 0) {
        text.append_c ('\n');
      }
      text.append (diff.lines[i].text);
    }
    set_text (text.str, path);
    diff_gutter.apply_word_tags ();
    paint_diff_rows ();
  }

  /** Each diff line with words marked, as "<line index>|<start>-<end>,<start>-<end>" in character offsets — for the debug D-Bus surface; empty when not in diff mode. */
  public string[] describe_diff_word_changes () {
    string[] out = {};
    if (shown_diff == null) {
      return out;
    }
    for (uint i = 0; i < shown_diff.lines.length; i++) {
      var line = shown_diff.lines[i];
      if (line.word_changes.length == 0) {
        continue;
      }
      string[] ranges = {};
      foreach (var range in line.word_changes) {
        ranges += "%d-%d".printf (range.start, range.end);
      }
      out += "%u|%s".printf (i, string.joinv (",", ranges));
    }
    return out;
  }

  /** Each diff line as "<old>|<new>|<marker>|<text>" — for the debug D-Bus surface; empty when not in diff mode. */
  public string[] describe_diff_lines () {
    string[] out = {};
    if (shown_diff == null) {
      return out;
    }
    for (uint i = 0; i < shown_diff.lines.length; i++) {
      var line = shown_diff.lines[i];
      var marker = line.kind == GitDiff.LineKind.ADDED ? "+" : line.kind == GitDiff.LineKind.REMOVED ? "-" : " ";
      out += "%d|%d|%s|%s".printf (line.old_number, line.new_number, marker, line.text);
    }
    return out;
  }

  /** A file with only one side (new, or deleted) is no diff: the text as it is, read-only, with the native line numbers — the way VS Code opens an untracked file plainly rather than as all-added. */
  public void show_plain_text (string text, string path) {
    read_only = true;
    if (diff_gutter_attached) {
      diff_gutter.detach (text_view.get_gutter (Gtk.TextWindowType.LEFT));
      diff_gutter_attached = false;
    }
    shown_diff = null;
    text_view.set_row_bands ("diff", new GenericArray<CodeEditorSourceView.RowBand> ());
    scrollbar.set_hunks ({});
    show_line_numbers = true;
    set_text (text, path);
  }

  /** A theme change: the bands read their swatches when painted, so a repaint is all it takes; the word tags cache theirs. */
  private void apply_diff_colors () {
    if (diff_gutter != null) {
      diff_gutter.refresh_colors ();
    }
    text_view.queue_draw ();
  }

  /** One band per run of added or removed lines, painted from CodeEditorDiffGutter's swatches — and the same runs as hunks for the scrollbar's bars, which nothing else feeds in diff mode. */
  private void paint_diff_rows () {
    var bands = new GenericArray<CodeEditorSourceView.RowBand> ();
    GitDiff.Hunk[] hunks = {};
    int run_start = -1;
    GitDiff.LineKind run_kind = GitDiff.LineKind.CONTEXT;
    for (uint i = 0; i <= shown_diff.lines.length; i++) {
      var kind = i < shown_diff.lines.length ? shown_diff.lines[i].kind : GitDiff.LineKind.CONTEXT;
      if (kind == run_kind) {
        continue;
      }
      if (run_kind != GitDiff.LineKind.CONTEXT) {
        bands.add (new CodeEditorSourceView.RowBand (run_start, (int) i - 1, run_kind == GitDiff.LineKind.ADDED ? diff_gutter.added_swatch : diff_gutter.removed_swatch));
        hunks += new GitDiff.Hunk (run_start, (int) i - run_start, run_kind == GitDiff.LineKind.ADDED ? GitDiff.HunkKind.ADDED : GitDiff.HunkKind.REMOVED, true);
      }
      run_start = (int) i;
      run_kind = kind;
    }
    text_view.set_row_bands ("diff", bands);
    scrollbar.set_hunks (hunks);
  }

  /**
   * A transient adjustment on top of settings.json's own
   * editor.font_size — Ctrl+Plus/Minus/0, never written to disk. Ported
   * from VS Code's own real EditorZoom (checked editorZoom.ts): a
   * plain in-memory value, gone on restart. Static, not per-instance:
   * this app has no per-window zoom concept, one shared level applies
   * everywhere at once — matches the font CSS itself already being
   * display-wide (see apply_settings()), so any one instance
   * recomputing it after a change is enough to re-render every open
   * window's text.
   */
  private static int zoom_level = 0;

  /** Static for the same reason zoom_level is: the provider it holds is display-wide, so with several CodeEditors alive at once (the file editor plus Find Results) the previous one has to be uninstalled no matter which instance reloads. */
  private static Gtk.CssProvider? font_provider = null;
  private static string? installed_font_css = null;

  /** Ctrl+Plus — same "+1" semantics as font_css()'s own `settings.font_size`, not VS Code's real 10%-per-level multiplier (checked fontInfo.ts): this app's own editor.font_size is already a plain point size, so a flat step matches it more directly than a percentage would. */
  public void zoom_in () {
    zoom_level += 1;
    apply_settings ();
  }

  /** Ctrl+Minus — see zoom_in()'s own doc comment. */
  public void zoom_out () {
    zoom_level -= 1;
    apply_settings ();
  }

  /** Ctrl+0 — back to settings.json's own editor.font_size exactly, same as VS Code's real EditorFontZoomReset. */
  public void reset_zoom () {
    zoom_level = 0;
    apply_settings ();
  }

  /**
   * Applies UserSettings' `editor.*` values that aren't their own
   * dedicated "prop" (indent, hunks, …): turns the font ones into a real
   * stylesheet targeting `.code-editor` (text_view's own class, set
   * above), and sets `wrap_mode` directly (not a CSS concern) from
   * `editor.word_wrap`. Run once at construction, again on every
   * UserSettings.changed, and again on every zoom_in()/zoom_out()/
   * reset_zoom() (wrap_mode is unaffected by zoom, re-set anyway).
   * Uninstalls the previous font provider first — a property the last
   * reload set and this one omits (e.g. editor.font_family going back to
   * null) needs the old rule gone, not just left uncontested by a new
   * one that doesn't mention it.
   *
   * `word_wrap_override`, when set, wins over the setting: Alt+W's own
   * state for this one document, VS Code's transient wordWrapOverride
   * (toggleWordWrap.ts) — gone with the tab, never written to settings.
   *
   * `wrap_mode`, not VS Code's full `wordWrap` enum: GTK's own wrap is
   * always tied to the real widget width (`Gtk.WrapMode` has no
   * "wrap at a fixed column" option at all — checked gtkenums.h), so
   * there's no native equivalent of `wordWrapColumn`/`bounded` to wire
   * up here; this app's own `editor.word_wrap` is `on`/`off` only.
   * `Gtk.WrapMode.WORD_CHAR` is the same mapping GNOME Text Editor's own
   * "Wrap Text" preference uses (checked editor-utils.c's
   * `_editor_gboolean_to_wrap_mode`): word boundaries first, falling
   * back to a mid-word break only when a single word can't fit at all.
   */
  private void apply_settings () {
    var css = font_css ();
    // Every live editor runs this on the same change; the display-wide provider only needs one of them to.
    if (css != installed_font_css) {
      if (font_provider != null) {
        GlobalCss.uninstall (font_provider);
      }
      font_provider = GlobalCss.install_from_string (css);
      installed_font_css = css;
    }
    apply_word_wrap ();
  }

  /** Synchronous, so a tab never paints a frame in the wrong mode: set_text() and set_language_override() run it before the main loop gets to draw. The rulers go with it: the same per-language lookup. */
  private void apply_word_wrap () {
    text_view.wrap_mode = word_wrap ? Gtk.WrapMode.WORD_CHAR : Gtk.WrapMode.NONE;
    text_view.set_rulers (rulers ());
  }

  private int max_line_length = 0;

  /** The project's `max_line_length` for this file from its .editorconfig, 0 with none — the ruler when `editorconfig.max_line_length` is on. */
  public void set_max_line_length (int columns) {
    max_line_length = columns;
    apply_word_wrap ();
  }

  private int[] rulers () {
    if (max_line_length > 0 && settings.editorconfig_max_line_length_for (language_name)) {
      return { max_line_length };
    }
    return settings.rulers_for (language_name);
  }

  private bool has_word_wrap_override = false;
  private bool word_wrap_override = false;

  /** Whether lines wrap right now: the document's own override when Alt+W set one, else `editor.word_wrap` for its language (UserSettings.word_wrap_for). */
  public bool word_wrap {
    get { return has_word_wrap_override ? word_wrap_override : settings.word_wrap_for (language_name); }
  }

  /** Alt+W: flips wrapping for this document only, as an override that lives as long as the tab does. */
  public void toggle_word_wrap () {
    word_wrap_override = !word_wrap;
    has_word_wrap_override = true;
    apply_word_wrap ();
  }

  /**
   * `font-family` only goes in when the user actually set one — left
   * out entirely otherwise, so `monospace = true` above keeps
   * resolving fontconfig's own "monospace" alias untouched, same as
   * before settings.json existed. `font-size` defaults to the point
   * size straight out of `font_size` plus the current zoom_level
   * (floored at 1pt) — `font_size` itself is whatever UserSettings
   * already resolved from the user's real system default rather than
   * a number this app invented, this CSS never has to know that.
   * `font-size` in `pt`, not `px`, and `line-height` as a bare
   * multiplier (never `px`, unlike VS Code's own editor.lineHeight) —
   * both checked against GNOME Text Editor's real font CSS for the
   * same GtkSourceView-based widget (editor-utils.c's
   * _editor_font_description_to_css(), editor-source-view.c's own
   * "line-height" property).
   */
  private string font_css () {
    var css = new StringBuilder ("textview.code-editor {\n");
    if (settings.font_family != null) {
      css.append ("  font-family: \"%s\";\n".printf (settings.font_family.replace ("\"", "'")));
    }
    if (settings.font_size > 0) {
      int effective_size = int.max (1, settings.font_size + zoom_level);
      css.append ("  font-size: %dpt;\n".printf (effective_size));
    }
    css.append ("  font-weight: %s;\n".printf (settings.font_weight));
    css.append ("  font-feature-settings: %s;\n".printf (settings.font_ligatures ? "\"liga\" 1, \"calt\" 1" : "\"liga\" 0, \"calt\" 0"));
    css.append ("  letter-spacing: %gpx;\n".printf (settings.letter_spacing));
    css.append ("  line-height: %g;\n".printf (settings.line_height));
    css.append ("}\n");
    return css.str;
  }

  /**
   * Shows `text`, highlighted as the language package named
   * `language_override` when one is given, and otherwise as whichever
   * claims `path` — by its name, or failing that by `text`'s own first
   * line (a shebang). None if no package does, or if `path` is "".
   */
  public void set_text (string text, string path, string? language_override = null) {
    if (pending_reveal_id != 0) {
      Source.remove (pending_reveal_id);
      pending_reveal_id = 0;
    }
    language_path = path;
    this.language_override = language_override;
    syntax_highlighter.set_language (language_for (text));
    apply_word_wrap ();
    cursors.load_text (text);
    conflicts.schedule_scan ();
  }

  /** How many merge-conflict blocks the text holds right now (see CodeEditorConflicts). */
  public int conflict_count { get { return conflicts.count; } }

  /** Resolves conflict block `index` with "current", "incoming", "both" or "both-incoming-first" — the links' own action, for the debug D-Bus surface. */
  public void accept_conflict (int index, string side) throws Error {
    conflicts.accept (index, side);
  }

  /** Changes the language of the text already showing: a package's name, or null to go back to the one its path says. */
  public void set_language_override (string? language_override) {
    this.language_override = language_override;
    apply_language ();
    apply_word_wrap ();
  }

  /** A package was installed, edited or finished building while this text was showing — or the language was just set by hand. */
  private void apply_language () {
    syntax_highlighter.set_language (language_for (text_view.buffer.text));
  }

  /** A language named by hand that no longer exists (its package was removed) leaves the text plain rather than falling back to a guess the user already overruled. */
  private Syntax.LoadedLanguage? language_for (string text) {
    if (language_override != null) {
      return Syntax.Languages.instance.by_name (language_override);
    }
    return language_path == "" ? null : Syntax.Languages.instance.detect (language_path, first_line_of (text));
  }

  private static string first_line_of (string text) {
    int line_end = text.index_of_char ('\n');
    return line_end < 0 ? text : text.substring (0, line_end);
  }

  /** The syntax style key painted at `offset`, or "" where nothing is — no UI caller, only Opus.Dev.DevServer's own SyntaxStyleAt, for the system-test DSL. */
  public string syntax_style_at (int offset) {
    return syntax_highlighter.style_key_at (offset);
  }

  public string get_text () {
    return text_view.buffer.text;
  }

  /**
   * Fires Gtk.TextView's own native "select-all" signal directly — no
   * UI caller today, only Opus.Dev.DevServer's own SelectAll, for the
   * system-test DSL. Not a workaround or a copy of what GTK does:
   * `select_all` is declared as a `signal` on Gtk.TextView (confirmed
   * in gtk4.vapi), so this call already is a real g_signal_emit,
   * running GTK's own default handler exactly as a genuine Ctrl+A
   * would — quirks included (the caret landing at the start, not the
   * end; see CodeEditorCursors.on_mark_set()).
   */
  public void select_all () {
    text_view.select_all (true);
  }

  /** See CodeEditorInput.key_pressed()'s own doc comment. `modifier_state` is a raw Gdk.ModifierType bitmask, taken as a plain `uint` so a caller that doesn't import Gdk itself (Opus.Dev.DevServer) can pass one straight through. */
  public bool key_pressed (uint keyval, uint modifier_state) {
    return input.key_pressed (keyval, (Gdk.ModifierType) modifier_state);
  }

  /** The cursor set and undo stack this editor works on from now on — EditorView.EditorPane.TabDocument hands over its Document's own pair (Document.cursors/history) once, when it builds its editor; a consumer with nothing to keep (Find Results) never calls this and stays on the pair the constructor made. */
  public void bind (CursorCollection cursor_collection, EditHistory history) {
    cursors.bind (cursor_collection, history);
  }

  /** Back to a fresh, throwaway cursor set and undo stack — for when nothing is showing. */
  public void unbind () {
    cursors.unbind ();
  }

  /** Columns per indent level — the indent guides, how wide a literal tab renders, and what Tab/Backspace/Enter do — plus whether Tab inserts spaces. Resolved by EditorView.EditorPane.TabDocument from the linked folder's .editorconfig, per file. */
  /** `tab_width` is how wide a literal tab renders, the indent size unless the folder says otherwise. */
  public void set_indent (int size, bool insert_spaces, int tab_width = -1) {
    indent_size = size;
    this.insert_spaces = insert_spaces;
    text_view.set_indent_size (size);
    text_view.tab_width = (uint) (tab_width > 0 ? tab_width : size);
    cursors.set_indent_config (size, insert_spaces);
  }

  /** The theme's colors for what the view paints itself — what a sibling painting alongside (find results, a line preview) matches. */
  public CodeEditorPalette palette {
    get { return text_view.palette; }
  }

  /** As last given to set_indent() — what a function that rewrites indentation follows. */
  public int indent_size { get; private set; default = 2; }
  public bool insert_spaces { get; private set; default = true; }

  /** The package name of the language the text is highlighted as, null for plain text. */
  public string? language_name {
    owned get {
      var language = language_for (text_view.buffer.text);
      return language == null ? null : language.package.name;
    }
  }

  /** Renders `cursor_set` onto the real buffer's own selection/carets — pass-through to the cursors sub-component. EditorView.EditorPane.TabDocument's own SetActiveCursors (Opus.Dev.DevServer) mutates a document's own CursorCollection directly, then calls this to make it visible. */
  public void render_cursors (Cursor[] cursor_set) {
    cursors.render_cursors (cursor_set);
  }

  /** Pass-through to the change-bar gutter renderer, same "prop forwarded to a child" shape as set_hunks()'s siblings above. */
  public void set_hunks (GitDiff.Hunk[] hunks) {
    change_gutter.set_hunks (hunks);
    scrollbar.set_hunks (hunks);
  }

  /** Moves keyboard focus into the text view — used when opening a tab is meant to start editing right away, not just show it. */
  public void grab_focus () {
    text_view.grab_focus ();
  }

  /**
   * Scrolls `offset` into view (centered, only if not already visible),
   * without moving any cursor itself — pairs with render_cursors() when a
   * consumer (EditorView.EditorPane.TabDocument's own open_at()) needs the *target* of a
   * jump-to-another-file visible, not just marked.
   *
   * Deferred to the default idle priority, not called synchronously:
   * showing Find Results' own target tab re-parents this component's
   * `scrolled_window` out of wherever it was (`gtk_widget_unparent`
   * resets the widget's own size to 0×0), and the new parent only
   * allocates it a real size during the frame's own layout phase
   * (`Gdk.PRIORITY_REDRAW`) — a reveal computed before that would read
   * against a zero-height view and silently do nothing. The default
   * idle priority runs after both that layout pass and GTK's own
   * incremental line-height validation (which keeps re-running at a
   * slightly higher priority until the whole buffer is valid), so by the
   * time this actually calls reveal_iter(), a far target's position is
   * exact — not just "whatever's known so far". `CodeEditorCursors.
   * reveal_cursors()`'s own doc comment covers the sibling, much
   * tighter-tolerance case (an edit/move on an already-visible,
   * already-allocated view), which is why that one runs one priority
   * earlier instead.
   *
   * `reveal_iter()`, not `Gtk.TextView.scroll_to_iter()`/
   * `scroll_to_mark()`: see that method's own doc comment
   * (CodeEditorSourceView) for the three concrete bugs those caused here
   * (a visible glide, a spurious horizontal scroll, and this exact
   * re-parent race landing on an unvalidated zero-height view).
   */
  /** The first line showing, 1-based. */
  public int top_line {
    get {
      Gdk.Rectangle visible;
      text_view.get_visible_rect (out visible);
      Gtk.TextIter top;
      int top_y;
      text_view.get_line_at_y (out top, visible.y, out top_y);
      return top.get_line () + 1;
    }
  }

  /**
   * Puts the 1-based `line` at the top of the view, with no animation,
   * once the view has settled — the same deferral as reveal_offset(),
   * and the same settling passes as CodeEditorSourceView.reveal_settled():
   * a line's y is only right once the lines above it are laid out.
   */
  public void scroll_to_top_line (int line) {
    if (pending_scroll_id != 0) {
      Source.remove (pending_scroll_id);
    }
    pending_scroll_id = Idle.add (() => {
      pending_scroll_id = 0;
      Gtk.TextIter iter;
      source_buffer.get_iter_at_line (out iter, line - 1);
      var vadjustment = scrolled_window.vadjustment;
      for (int pass = 0; pass < SCROLL_SETTLE_PASSES; pass++) {
        int y, height;
        text_view.get_line_yrange (iter, out y, out height);
        // get_line_yrange() leaves the top margin out; the visible rect doesn't.
        double wanted = y + text_view.top_margin;
        double target = wanted.clamp (vadjustment.lower, double.max (vadjustment.lower, vadjustment.upper - vadjustment.page_size));
        if (vadjustment.value == target) {
          break;
        }
        vadjustment.value = target;
      }
      return Source.REMOVE;
    });
  }

  public void reveal_offset (int offset) {
    if (pending_reveal_id != 0) {
      Source.remove (pending_reveal_id);
    }
    pending_reveal_id = Idle.add (() => {
      pending_reveal_id = 0;
      Gtk.TextIter iter;
      source_buffer.get_iter_at_offset (out iter, offset);
      text_view.reveal_settled (iter, RevealMode.CENTER_IF_OUTSIDE);
      return Source.REMOVE;
    });
  }

  /** Whether the shown text's language can list symbols — see CodeEditorSyntaxHighlighter. */
  public bool lists_symbols {
    get { return syntax_highlighter.lists_symbols; }
  }

  /** The definitions in the shown text; false while they aren't known yet — see CodeEditorSyntaxHighlighter.symbols(). */
  public bool symbols (out Syntax.Symbol[] symbols) {
    return syntax_highlighter.symbols (out symbols);
  }

  /** Shows the 1-based `line` without moving a cursor — see CodeEditorLinePreview. */
  public void preview_line (int line) {
    line_preview.show (line);
  }

  public void end_line_preview (bool restore_scroll) {
    line_preview.end (restore_scroll);
  }

  /** The 1-based line under preview, 0 when none is — for Opus.Dev.DevServer. */
  public int previewed_line {
    get { return line_preview.line; }
  }

  /** Re-announces search_position_changed as things stand — see CodeEditorSearch.announce_position(). */
  public void announce_search_position () {
    search.announce_position ();
  }

  /** Applies a Replace/Replace All result — not produced by any live cursor, so it goes through the cursors sub-component's own external-edit path rather than a cursor command. */
  public void apply_external_edits (TextEdit[] edits) {
    cursors.apply_external_edit (edits);
  }

  // ---- Search pass-through — same shape as set_hunks(): CodeEditor doesn't own any of this logic, it just forwards to the sub-component that does. ----

  public void set_search_text (string text) {
    search.set_search_text (text);
  }

  public void set_search_options (bool regex, bool case_sensitive, bool whole_word) {
    search.set_search_options (regex, case_sensitive, whole_word);
  }

  public void search_next () {
    search.search_next ();
  }

  public void search_previous () {
    search.search_previous ();
  }

  public TextEdit? compute_replace_current_match (string replacement) {
    return search.compute_replace_current_match (replacement);
  }

  public TextEdit[] compute_replace_all (string replacement) {
    return search.compute_replace_all (replacement);
  }

  public void land_after_replace (int replaced_end_offset) {
    search.land_after_replace (replaced_end_offset);
  }

  public void forget_current_match () {
    search.forget_current_match ();
  }

  public void select_last_match () {
    search.select_last_match ();
  }

  /** See CodeEditorCursors.select_all_occurrences()'s own doc comment. */
  public void select_all_occurrences () {
    cursors.select_all_occurrences ();
  }
}
