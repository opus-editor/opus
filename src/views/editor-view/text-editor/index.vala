/**
* Architecture prototype, not wired into the real app. .blp = template,
* .vala = "ViewModel": owns lifecycle + logic, composed of sub-components
* the same way a Vue SFC composes child components — cursor movement/
* rendering lives in TextEditorCursors (_cursors.vala) now, not here, once
* it started accumulating unrelated concerns. Plural: it's the manager for
* however many cursors exist, not one instance per cursor — see its own
* doc comment for why (checked against VS Code's real ViewCursors/
* ViewCursor split).
*
* set_active_document()/set_change_banner_visible() stay public: which
* document is active, and whether its file changed on disk, are the only
* two things this component can't work out on its own (tab-selection
* state and a filesystem watch, both owned elsewhere) — the SFC "props".
* set_active_document() is pure pass-through to the cursor sub-component,
* same as a parent forwarding a prop straight to a child.
*
* Theming is split the same way VS Code's own real ViewCursors does it
* (checked its source: registerThemingParticipant lives right in
* viewCursors.ts, styling only what that file itself owns) — each
* sub-component reacts to Adw.StyleManager on its own, for its own tags'
* colors, rather than one central "theme" object reaching into siblings
* it doesn't otherwise know about. What's left here is only what's
* genuinely TextEditor's own: the change-banner/drop-feedback CSS, and
* the buffer's style scheme (GtkSource.StyleSchemeManager) — neither
* belongs to cursors or search specifically.
*
* set_text()/set_placeholder() route their actual buffer write through
* cursors.load_text() rather than text_view.buffer directly — only
* TextEditorCursors holds the updating_programmatically guard that keeps
* on_insert_text_native()/on_delete_range_native() from misreading a
* freshly-loaded document as an untracked user edit.
*
* Everything CursorController/EditorController/SearchController's real
* jobs covered is ported except the right-click context menu (needs
* actual menu-building code — see TextEditorCursors' own doc comment).
* See the real src/views/editor-view/text-editor/index.vala for that.
*/
namespace EditorView {
  public class TextEditor : Object {
    private Gtk.Box root;
    private Gtk.Revealer change_banner_revealer;
    private Gtk.ScrolledWindow scrolled_window;
    private TextEditorSourceView text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
    private TextEditorCursors cursors;
    private TextEditorSearch search;

    public Gtk.Widget widget { get { return root; } }

    /** Whether the real text view currently holds keyboard focus — MainWindow's own "was the user actually in the editor when they pressed Ctrl+F" check, read before FindBar.show_find() steals focus into the Find entry. */
    public bool has_focus { get { return text_view.has_focus; } }

    /**
     * The real primary selection's own text, "" if it's empty/collapsed.
     * Reads the native insert/selection_bound marks directly rather than
     * going through TextEditorCursors' own CursorCollection: they always
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

    /** "Discard Changes and Reload" clicked — still an emit, not a direct Model call: reloading is file I/O plus tab bookkeeping this component doesn't own. */
    public signal void reload_requested ();

    /** The buffer's full content changed — re-emitted from the cursors sub-component, which is what actually mutates the buffer now. Something outside this whole component still needs this to mark the document dirty/enable Save. */
    public signal void text_changed (string new_text);

    /** Re-emitted from the search sub-component — see FindBar's own "N of M" counter, wired to this wherever both are composed (see TextEditorSearch's own doc comment). */
    public signal void search_position_changed (int position, int count);

    public TextEditor () {
      var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor-view/text-editor/index.ui");
      root = (Gtk.Box) builder.get_object ("root");
      change_banner_revealer = (Gtk.Revealer) builder.get_object ("change_banner_revealer");
      scrolled_window = (Gtk.ScrolledWindow) builder.get_object ("scrolled_window");

      text_view = new TextEditorSourceView () {
        monospace = true,
        top_margin = 8,
        bottom_margin = 8,
        left_margin = 8,
        right_margin = 8,
        show_line_numbers = true,
        cursor_visible = false, // every caret is hand-drawn by TextEditorSourceView instead — see its own doc comment
      };
      scrolled_window.set_child (text_view);

      cursors = new TextEditorCursors (text_view);
      cursors.text_changed.connect ((text) => text_changed (text));

      search = new TextEditorSearch (text_view);
      search.search_position_changed.connect ((position, count) => search_position_changed (position, count));

      var discard_button = (Gtk.Button) builder.get_object ("change_banner_discard_button");
      discard_button.clicked.connect (() => reload_requested ());

      install_css ();

      // GtkSource.Buffer paints with a StyleScheme's own fixed colors
      // instead of following the app's GTK theme, so it stays put through
      // a light/dark switch unless told otherwise.
      var style_manager = Adw.StyleManager.get_default ();
      style_manager.notify["dark"].connect (() => apply_style_scheme (style_manager.dark));
      apply_style_scheme (style_manager.dark);
    }

    /** Rules themselves live in styles/text-editor.css, not here — see GlobalCss.install_from_resource()'s own doc comment for why. */
    private void install_css () {
      GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/text-editor.css");
    }

    private void apply_style_scheme (bool dark) {
      var scheme_id = dark ? "Adwaita-dark" : "Adwaita";
      source_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (scheme_id);
    }

    /**
    * Cascades to both sub-components' own close() — the same "parent
    * tears down its children" shape Vue's onUnmounted has. Nothing of
    * TextEditor's own needs unregistering: its one signal connection
    * closes over `this` (g_signal_connect_object — see the conversation
    * this came out of), so it disconnects itself once this object dies.
    */
    public void close () {
      cursors.close ();
      search.close ();
    }

    /** Shows `text`, highlighted as whichever language `path`'s name/extension matches (none, if it matches none). */
    public void set_text (string text, string path) {
      text_view.editable = true;
      source_buffer.language = GtkSource.LanguageManager.get_default ().guess_language (path, null);
      cursors.load_text (text);
    }

    public string get_text () {
      return text_view.buffer.text;
    }

    /** language = null, not left as whatever set_text() last guessed: without this, a placeholder message shown right after a real file would still highlight as that file's own language. */
    public void set_placeholder (string message) {
      text_view.editable = false;
      source_buffer.language = null;
      cursors.load_text (message);
    }

    public void clear_placeholder () {
      text_view.editable = true;
    }

    /**
     * Fires Gtk.TextView's own native "select-all" signal directly — no
     * UI caller today, only Opus.Dev.DevServer's own SelectAll, for the
     * system-test DSL. Not a workaround or a copy of what GTK does:
     * `select_all` is declared as a `signal` on Gtk.TextView (confirmed
     * in gtk4.vapi), so this call already is a real g_signal_emit,
     * running GTK's own default handler exactly as a genuine Ctrl+A
     * would — quirks included (the caret landing at the start, not the
     * end; see TextEditorCursors.on_mark_set()).
     */
    public void select_all () {
      text_view.select_all (true);
    }

    /** See TextEditorCursors.key_pressed()'s own doc comment. `modifier_state` is a raw Gdk.ModifierType bitmask, taken as a plain `uint` so a caller that doesn't import Gdk itself (Opus.Dev.DevServer) can pass one straight through. */
    public bool key_pressed (uint keyval, uint modifier_state) {
      return cursors.key_pressed (keyval, (Gdk.ModifierType) modifier_state);
    }

    public void set_active_document (Document? document) {
      cursors.set_active_document (document);
    }

    /** Columns per indent level, and whether Tab inserts spaces — pass-through to the cursors sub-component, same "prop forwarded to a child" shape as set_active_document(). */
    public void set_indent_config (int indent_size, bool insert_spaces) {
      cursors.set_indent_config (indent_size, insert_spaces);
    }

    /** Renders `cursor_set` onto the real buffer's own selection/carets — pass-through to the cursors sub-component. EditorPane's own SetActiveCursors (Opus.Dev.DevServer) mutates a document's own CursorCollection directly, then calls this to make it visible. */
    public void render_cursors (Cursor[] cursor_set) {
      cursors.render_cursors (cursor_set);
    }

    public void set_change_banner_visible (bool visible) {
      change_banner_revealer.reveal_child = visible;
    }

    /** How many columns one indent level is, for the indent guides — a different need than set_indent_config()'s own Tab/Backspace behavior, so both are set independently. */
    public void set_indent_size (int size) {
      text_view.set_indent_size (size);
    }

    /** Moves keyboard focus into the text view — used when opening a tab is meant to start editing right away, not just show it. */
    public void grab_focus () {
      text_view.grab_focus ();
    }

    /** Applies a Replace/Replace All result — not produced by any live cursor, so it goes through the cursors sub-component's own external-edit path rather than a cursor command. */
    public void apply_external_edits (TextEdit[] edits) {
      cursors.apply_external_edit (edits);
    }

    /** Shows the system's own Save-As file chooser, pre-filled with `suggested_name` in `current_folder`. Returns the chosen path, or null if cancelled or the dialog/portal itself failed. */
    public async string? choose_save_as_path (string suggested_name, string current_folder) {
      var dialog = new Gtk.FileDialog ();
      dialog.initial_name = suggested_name;
      dialog.initial_folder = File.new_for_path (current_folder);

      try {
        var file = yield dialog.save (widget.get_root () as Gtk.Window, null);
        return file != null ? file.get_path () : null;
      } catch (Error e) {
        return null;
      }
    }

    // ---- Search pass-through — same shape as set_active_document(): TextEditor doesn't own any of this logic, it just forwards to the sub-component that does. ----

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
  }
}
