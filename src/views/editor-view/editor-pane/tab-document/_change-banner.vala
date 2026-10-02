namespace EditorView.EditorPane {
  /**
   * The "File Has Changed on Disk" banner shown above the editor while
   * the active document is unsynchronized with disk — a Document tab's
   * own sub-widget, not CodeEditor's: whether a file changed on disk is
   * something only the tab/file bookkeeping knows about, and a consumer
   * embedding CodeEditor for non-file content (Find Results) has nothing
   * to show here at all.
   */
  public class TabDocumentChangeBanner : Object {
    private Gtk.Revealer revealer;

    public Gtk.Widget widget { get { return revealer; } }

    /** "Discard Changes and Reload" clicked — reloading is file I/O plus tab bookkeeping this widget doesn't own. */
    public signal void discard_clicked ();

    public TabDocumentChangeBanner () {
      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/editor-view/editor-pane/tab-document/_change-banner.ui");
      revealer = (Gtk.Revealer) builder.get_object ("revealer");
      var discard_button = (Gtk.Button) builder.get_object ("discard_button");
      discard_button.clicked.connect (() => discard_clicked ());

      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/tab-document.css");
    }

    public void set_visible (bool visible) {
      revealer.reveal_child = visible;
    }
  }
}
