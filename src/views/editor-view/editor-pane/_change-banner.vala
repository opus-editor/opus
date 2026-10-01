namespace EditorView {
  /**
   * The "File Has Changed on Disk" banner shown above the editor while
   * the active document is unsynchronized with disk — EditorPaneWidget's own
   * sub-widget, not CodeEditor's: whether a file changed on disk is
   * something only the tab/file bookkeeping here knows about, and a
   * consumer embedding CodeEditor for non-file content (Find Results)
   * has nothing to show here at all.
   */
  public class EditorPaneChangeBanner : Object {
    private Gtk.Revealer revealer;

    public Gtk.Widget widget { get { return revealer; } }

    /** "Discard Changes and Reload" clicked — reloading is file I/O plus tab bookkeeping this widget doesn't own. */
    public signal void discard_clicked ();

    public EditorPaneChangeBanner () {
      var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor-view/editor-pane/_change-banner.ui");
      revealer = (Gtk.Revealer) builder.get_object ("revealer");
      var discard_button = (Gtk.Button) builder.get_object ("discard_button");
      discard_button.clicked.connect (() => discard_clicked ());

      GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/editor-pane.css");
    }

    public void set_visible (bool visible) {
      revealer.reveal_child = visible;
    }
  }
}
