/**
 * A flat Gtk.ListView over a ChangeStore — HistoryPane's own list of a
 * commit's files, identical in visual design to ExplorerPaneTree's own
 * (same "navigation-sidebar"/"data-table" CSS classes, so row height,
 * hover and the lack of margin between rows all match exactly).
 * Gtk.MultiSelection gives plain/Ctrl/Shift-click selection straight
 * from GTK's own native list bindings — nothing hand-rolled.
 */
namespace GitView {
  public class ChangeList : Object {
    private Gtk.ListView list_view;
    private ChangeStore changes = new ChangeStore ();
    private Gtk.MultiSelection selection;
    private IconTheme icon_theme = new IconTheme.symbols ();
    // Every GitScope.Change.path is absolute — on_bind() strips this
    // back off for the row's own relative-path display.
    private string root_path = "";

    public Gtk.Widget widget { get { return list_view; } }

    /** The set of selected rows changed — HistoryPane opens a diff when exactly one row is selected. */
    public signal void selection_changed ();

    /** A row was double-clicked, or Enter pressed on it — carries just that row's own Change. */
    public signal void item_activated (GitScope.Change change);

    public ChangeList () {
      var factory = new Gtk.SignalListItemFactory ();
      factory.setup.connect (on_setup);
      factory.bind.connect (on_bind);

      selection = new Gtk.MultiSelection (changes.store);
      selection.selection_changed.connect (() => selection_changed ());
      list_view = new Gtk.ListView (selection, factory);
      list_view.activate.connect ((position) => item_activated (changes.at (position)));
      // Same two classes ExplorerPaneTree's own list_view carries — see
      // its own doc comment for what each one does.
      list_view.add_css_class ("navigation-sidebar");
      list_view.add_css_class ("data-table");

      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/explorer-pane.css");
    }

    /** Every row's own Change, in list order, selected or not. */
    public GenericArray<GitScope.Change> all_changes () {
      return changes.all_changes ();
    }

    /** Every currently-selected row's own Change, in list order — empty with nothing selected. */
    public GenericArray<GitScope.Change> selected_changes () {
      var result = new GenericArray<GitScope.Change> ();
      var bitset = selection.get_selection ();
      var iter = Gtk.BitsetIter ();
      uint position;
      if (iter.init_first (bitset, out position)) {
        do {
          result.add (changes.at (position));
        } while (iter.next (out position));
      }
      return result;
    }

    /** See ChangeStore.set_changes(). */
    public void set_changes (GenericArray<GitScope.Change> list, string root_path) {
      this.root_path = root_path;
      changes.set_changes (list, root_path);
    }

    /** See ChangeStore.set_sort_key(). */
    public void set_sort_key (string key) {
      changes.set_sort_key (key);
    }

    private void on_setup (Object item) {
      var list_item = (Gtk.ListItem) item;
      var row = new ChangeRow (icon_theme);
      row.widget.set_data ("row", row);
      list_item.child = row.widget;
    }

    private void on_bind (Object item) {
      var list_item = (Gtk.ListItem) item;
      var change = (GitScope.Change) list_item.item;
      list_item.child.get_data<ChangeRow> ("row").bind (change, root_path);
    }
  }
}
