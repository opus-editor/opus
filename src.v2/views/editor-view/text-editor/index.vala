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

    /** "Discard Changes and Reload" clicked — still an emit, not a direct Model call: reloading is file I/O plus tab bookkeeping this component doesn't own. */
    public signal void reload_requested ();

    /** The buffer's full content changed — re-emitted from the cursors sub-component, which is what actually mutates the buffer now. Something outside this whole component still needs this to mark the document dirty/enable Save. */
    public signal void text_changed (string new_text);

    /** Re-emitted from the search sub-component — see FindBar's own "N of M" counter, wired to this wherever both are composed (see TextEditorSearch's own doc comment). */
    public signal void search_position_changed (int position, int count);

    public TextEditor () {
      var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/v2/editor-view/text-editor/index.ui");
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
      GlobalCss.install_from_resource ("/io/github/nowaos/Opus/v2/styles/text-editor.css");
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

    public void set_active_document (Document? document) {
      cursors.set_active_document (document);
    }

    /** Columns per indent level, and whether Tab inserts spaces — pass-through to the cursors sub-component, same "prop forwarded to a child" shape as set_active_document(). */
    public void set_indent_config (int indent_size, bool insert_spaces) {
      cursors.set_indent_config (indent_size, insert_spaces);
    }

    public void set_change_banner_visible (bool visible) {
      change_banner_revealer.reveal_child = visible;
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
