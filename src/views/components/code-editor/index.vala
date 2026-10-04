/**
* The reusable code editor: a Gtk.ScrolledWindow holding one
* CodeEditorSourceView, composed of sub-components the same way a Vue SFC
* composes child components — cursor state and editing transactions live
* in CodeEditorCursors (_cursors.vala), keys/mouse/context menu in
* CodeEditorInput, the clipboard in CodeEditorClipboard, Find/Replace in
* CodeEditorSearch, the git change bars in CodeEditorChangeGutter. Plural "Cursors": it's
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
* the buffer's style scheme (GtkSource.StyleSchemeManager).
*
* set_text() routes its actual buffer write through
* cursors.load_text() rather than text_view.buffer directly — only
* CodeEditorCursors holds the updating_programmatically guard that keeps
* on_insert_text_native()/on_delete_range_native() from misreading a
* freshly-loaded document as an untracked user edit.
*/
public class CodeEditor : Object {
  private Gtk.ScrolledWindow scrolled_window;
  private CodeEditorSourceView text_view;
  private UserSettings settings;
  private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
  private CodeEditorCursors cursors;
  private CodeEditorClipboard clipboard;
  private CodeEditorInput input;
  private CodeEditorSearch search;
  private CodeEditorChangeGutter change_gutter;

  /** A reveal_offset() already queued, not yet run — see that method's own doc comment. 0 means none pending. */
  private uint pending_reveal_id = 0;

  public Gtk.Widget widget { get { return scrolled_window; } }

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

  public CodeEditor (UserSettings settings) {
    this.settings = settings;
    settings.changed.connect (apply_settings);
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
      vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
      child = text_view,
    };

    cursors = new CodeEditorCursors (text_view);
    cursors.text_changed.connect ((text) => text_changed (text));
    clipboard = new CodeEditorClipboard (text_view, cursors);
    input = new CodeEditorInput (text_view, cursors, clipboard);
    input.link_click.connect ((offset) => link_click (offset));

    search = new CodeEditorSearch (text_view);
    search.search_position_changed.connect ((position, count) => search_position_changed (position, count));

    change_gutter = new CodeEditorChangeGutter ();
    text_view.get_gutter (Gtk.TextWindowType.LEFT).insert (change_gutter, 0);

    install_css ();
    apply_settings ();

    // GtkSource.Buffer paints with a StyleScheme's own fixed colors
    // instead of following the app's GTK theme, so it stays put through
    // a light/dark switch unless told otherwise.
    var style_manager = Adw.StyleManager.get_default ();
    style_manager.notify["dark"].connect (() => apply_style_scheme (style_manager.dark));
    apply_style_scheme (style_manager.dark);
  }

  /** Rules themselves live in styles/code-editor.css, not here — see GlobalCss.install_from_resource()'s own doc comment for why. */
  private void install_css () {
    GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/code-editor.css");
  }

  private void apply_style_scheme (bool dark) {
    var scheme_id = dark ? "Adwaita-dark" : "Adwaita";
    source_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (scheme_id);
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
    if (font_provider != null) {
      GlobalCss.uninstall (font_provider);
    }
    font_provider = GlobalCss.install_from_string (font_css ());
    text_view.wrap_mode = settings.word_wrap ? Gtk.WrapMode.WORD_CHAR : Gtk.WrapMode.NONE;
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
   * Shows `text`, highlighted as whichever language `path`'s name/
   * extension matches (none, if it matches none, or if `path` is "" —
   * guess_language() itself asserts on an empty filename with no
   * content_type either, checked gtksourcelanguage-manager.c).
   */
  public void set_text (string text, string path) {
    if (pending_reveal_id != 0) {
      Source.remove (pending_reveal_id);
      pending_reveal_id = 0;
    }
    source_buffer.language = path == "" ? null : GtkSource.LanguageManager.get_default ().guess_language (path, null);
    cursors.load_text (text);
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

  /** The cursor set and undo stack this editor works on from now on — EditorView.EditorPane.TabDocument hands over each tab's own pair (Document.cursors/history) on a tab switch; a consumer with nothing per-tab to keep (Find Results) never calls this and stays on the pair the constructor made. */
  public void bind (CursorCollection cursor_collection, EditHistory history) {
    cursors.bind (cursor_collection, history);
  }

  /** Back to a fresh, throwaway cursor set and undo stack — for when nothing is showing. */
  public void unbind () {
    cursors.unbind ();
  }

  /** Columns per indent level — the indent guides, how wide a literal tab renders, and what Tab/Backspace/Enter do — plus whether Tab inserts spaces. Resolved by EditorView.EditorPane.TabDocument from the linked folder's .editorconfig, per file. */
  public void set_indent (int size, bool insert_spaces) {
    text_view.set_indent_size (size);
    cursors.set_indent_config (size, insert_spaces);
  }

  /** Renders `cursor_set` onto the real buffer's own selection/carets — pass-through to the cursors sub-component. EditorView.EditorPane.TabDocument's own SetActiveCursors (Opus.Dev.DevServer) mutates a document's own CursorCollection directly, then calls this to make it visible. */
  public void render_cursors (Cursor[] cursor_set) {
    cursors.render_cursors (cursor_set);
  }

  /** Pass-through to the change-bar gutter renderer, same "prop forwarded to a child" shape as set_hunks()'s siblings above. */
  public void set_hunks (GitDiff.Hunk[] hunks) {
    change_gutter.set_hunks (hunks);
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
