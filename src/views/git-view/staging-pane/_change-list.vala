/**
 * A flat Gtk.ListView over a GenericArray<GitScope.Change> — Unstaged/
 * Staged Changes' own shared list, identical in visual design to
 * ExplorerPaneTree's own (same "navigation-sidebar"/"data-table" CSS
 * classes, so row height, hover and the lack of margin between rows all
 * match exactly) — just flat, no Gtk.TreeListModel, since a change list
 * has no folders to expand. Gtk.MultiSelection (not Gtk.SingleSelection,
 * unlike ExplorerPaneTree) gives plain/Ctrl/Shift-click selection and
 * multi-selection for free, straight from GTK's own native list
 * bindings — nothing hand-rolled. all_changes()/has_items are what
 * StagingPane's own Stage All/Unstage All buttons act on and gate their
 * own sensitivity against — not selected_changes()/has_selection, which
 * are instead what a double-click or Enter act on (see item_activated/
 * selection_activated below for why those are two different signals
 * now, not one).
 *
 * Gtk.ListView's own native `activate` signal (position-based) fires
 * identically for a double-click *and* an Enter press — both ultimately
 * call the same `list.activate-item` action (confirmed in GTK's own
 * source, gtklistview.c) — so there's no telling them apart from it
 * alone, even though StagingPane wants different scopes for each
 * (double-click: just the row clicked; Enter: the whole current
 * selection). key_controller below intercepts Return/KP_Enter in the
 * CAPTURE phase, ahead of that native binding, so item_activated ends
 * up firing only for a real double-click — see its own doc comment.
 *
 * set_sort_key() ports VS Code's own three SCM sort orders
 * (`scm.defaultViewSortKey`, List mode — see scmViewPane.ts's own
 * SCMTreeSorter.compare()): "name" (bare file name), "status" (by
 * GitScope.Change.label, falling back to "path" order for two changes
 * with the same label — same tie-break VS Code's own comparator falls
 * through to), and "path" (default — every path segment compared in
 * turn; within a shared prefix, whichever path ends first, i.e. is
 * shallower, sorts first).
 */
namespace GitView {
  public class ChangeList : Object {
    private Gtk.ListView list_view;
    private ListStore store = new ListStore (typeof (GitScope.Change));
    private Gtk.MultiSelection selection;
    private IconTheme icon_theme = new IconTheme.symbols ();
    // Every GitScope.Change.path is absolute — on_bind() strips this
    // back off for the row's own relative-path display, and
    // compare_changes() strips it the same way to sort by relative path.
    private string root_path = "";
    private string sort_key = "path";

    public Gtk.Widget widget { get { return list_view; } }

    /** The set of selected rows changed — StagingPane opens a preview diff when exactly one row is selected. */
    public signal void selection_changed ();

    /** A row was double-clicked — carries just that row's own Change, regardless of whatever else might currently be selected (see this class's own doc comment for why Enter doesn't also fire this). */
    public signal void item_activated (GitScope.Change change);

    /** Enter pressed with focus in this list — StagingPane acts on selected_changes() itself; a no-op (never fired) with nothing selected. */
    public signal void selection_activated ();

    /** A right-click on the list — `change` is the row under the pointer, null over the empty space below the rows. */
    public signal void context_menu_requested (GitScope.Change? change, double x, double y);

    /** Whether anything is currently selected — what gates the Unstaged "…" menu's own "Discard changes on selected files" item. */
    public bool has_selection { get { return selection.get_selection ().get_size () > 0; } }

    /** Whether the list holds any change at all, selected or not — StagingPane's own Commit button stays insensitive without this in Staged Changes' own list. */
    public bool has_items { get { return store.get_n_items () > 0; } }

    public ChangeList () {
      var factory = new Gtk.SignalListItemFactory ();
      factory.setup.connect (on_setup);
      factory.bind.connect (on_bind);

      selection = new Gtk.MultiSelection (store);
      selection.selection_changed.connect (() => selection_changed ());
      list_view = new Gtk.ListView (selection, factory);
      list_view.activate.connect ((position) => item_activated ((GitScope.Change) store.get_item (position)));
      var secondary_click = new Gtk.GestureClick ();
      secondary_click.set_button (Gdk.BUTTON_SECONDARY);
      secondary_click.pressed.connect ((n_press, x, y) => context_menu_requested (change_at (x, y), x, y));
      list_view.add_controller (secondary_click);
      // Same two classes ExplorerPaneTree's own list_view carries — see
      // its own doc comment for what each one does.
      list_view.add_css_class ("navigation-sidebar");
      list_view.add_css_class ("data-table");

      // CAPTURE, not the BUBBLE default: has to see Return/KP_Enter
      // before list_view's own internal list.activate-item binding
      // does, so it can swallow the keypress outright (returning true)
      // and keep that binding from also firing list_view's own
      // `activate` signal for whatever row happens to hold keyboard
      // focus — see this class's own doc comment.
      var key_controller = new Gtk.EventControllerKey ();
      key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
      key_controller.key_pressed.connect ((keyval, keycode, state) => {
        if (keyval != Gdk.Key.Return && keyval != Gdk.Key.KP_Enter) {
          return false;
        }
        if (has_selection) {
          selection_activated ();
        }
        return true;
      });
      list_view.add_controller (key_controller);

      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/explorer-pane.css");
    }

    /** Every row's own Change, in list order, selected or not — StagingPane's own "Discard all changes" acts on this, not selected_changes(). */
    public GenericArray<GitScope.Change> all_changes () {
      var result = new GenericArray<GitScope.Change> ();
      for (uint i = 0; i < store.get_n_items (); i++) {
        result.add ((GitScope.Change) store.get_item (i));
      }
      return result;
    }

    /** Every currently-selected row's own Change, in list order — empty with nothing selected. */
    public GenericArray<GitScope.Change> selected_changes () {
      var result = new GenericArray<GitScope.Change> ();
      var bitset = selection.get_selection ();
      var iter = Gtk.BitsetIter ();
      uint position;
      if (iter.init_first (bitset, out position)) {
        do {
          result.add ((GitScope.Change) store.get_item (position));
        } while (iter.next (out position));
      }
      return result;
    }

    /** Selects just the row for `path` (absolute); false when there is none. */
    public bool select_path (string path) {
      for (uint i = 0; i < store.get_n_items (); i++) {
        if (((GitScope.Change) store.get_item (i)).path == path) {
          selection.select_item (i, true);
          return true;
        }
      }
      return false;
    }

    /**
     * Brings the list in line with `changes` — StagingPane calls this each
     * time a fresh GitScope.WorkingTree comes back. A merge of two sorted
     * lists, not a clear-and-refill: only rows that actually came or
     * went touch the store, so Gtk.MultiSelection's own position bitset
     * (and the keyboard focus, and the scroll) stay put on everything
     * else — a refresh that changes nothing changes nothing. Switching
     * folders is the one case the old rows mean nothing any more.
     */
    public void set_changes (GenericArray<GitScope.Change> changes, string root_path) {
      if (this.root_path != root_path) {
        this.root_path = root_path;
        store.remove_all ();
      }
      var sorted = copy_sorted (changes);

      uint i = 0;
      uint j = 0;
      while (j < sorted.length) {
        if (i >= store.get_n_items ()) {
          store.append (sorted[j++]);
          i++;
          continue;
        }
        var current = (GitScope.Change) store.get_item (i);
        var incoming = sorted[j];
        int order = compare_changes (current, incoming);
        if (order == 0 && current.kind == incoming.kind) {
          i++;
          j++;
        } else if (order <= 0) {
          store.remove (i);
        } else {
          store.insert (i++, incoming);
          j++;
        }
      }
      while (i < store.get_n_items ()) {
        store.remove (i);
      }
    }

    private GenericArray<GitScope.Change> copy_sorted (GenericArray<GitScope.Change> changes) {
      var sorted = new GenericArray<GitScope.Change> ();
      for (uint i = 0; i < changes.length; i++) {
        sorted.add (changes[i]);
      }
      sorted.sort_with_data ((a, b) => compare_changes (a, b));
      return sorted;
    }

    /** "name"/"path"/"status" — UserSettings.changes_sort's own values. Anything else behaves as "path". Re-sorts the list already shown, same as VS Code's own live "Sort Changes by…" menu. */
    public void set_sort_key (string key) {
      if (sort_key == key) {
        return;
      }
      sort_key = key;
      store.sort (compare_changes);
    }

    private int compare_changes (Object a_object, Object b_object) {
      var a = (GitScope.Change) a_object;
      var b = (GitScope.Change) b_object;

      if (sort_key == "name") {
        return compare_names (Path.get_basename (a.path), Path.get_basename (b.path));
      }
      if (sort_key == "status" && a.label != b.label) {
        return a.label < b.label ? -1 : 1;
      }
      return compare_paths (relative_path (a.path), relative_path (b.path));
    }

    private string relative_path (string absolute_path) {
      return root_path == "" ? absolute_path : absolute_path.substring (root_path.length + 1);
    }

    /** Segment-by-segment, same as VS Code's own comparePaths(): within a shared prefix, whichever path has no more segments left (ends first) sorts before one that keeps going. */
    private static int compare_paths (string a, string b) {
      var a_parts = a.split ("/");
      var b_parts = b.split ("/");
      int last_a = a_parts.length - 1;
      int last_b = b_parts.length - 1;

      for (int i = 0; ; i++) {
        bool end_a = i == last_a;
        bool end_b = i == last_b;
        if (end_a && end_b) {
          return compare_names (a_parts[i], b_parts[i]);
        } else if (end_a) {
          return -1;
        } else if (end_b) {
          return 1;
        }

        int result = compare_names (a_parts[i], b_parts[i]);
        if (result != 0) {
          return result;
        }
      }
    }

    /** Locale-aware, with VS Code's own "numeric" disambiguation (`file2` before `file10`) — GLib's own collation key for exactly this job. */
    private static int compare_names (string a, string b) {
      var a_key = a.collate_key_for_filename ();
      var b_key = b.collate_key_for_filename ();
      if (a_key == b_key) {
        return 0;
      }
      return a_key < b_key ? -1 : 1;
    }

    /** The Change bound to the row under `(x, y)`, or null over the list's empty background — same pick-and-climb as ExplorerPaneTree.row_widget_at(). */
    private GitScope.Change? change_at (double x, double y) {
      Gtk.Widget? widget = list_view.pick (x, y, Gtk.PickFlags.DEFAULT);
      while (widget != null && widget != list_view) {
        var row = widget.get_data<ChangeRow?> ("row");
        if (row != null) {
          return row.bound_change;
        }
        widget = widget.get_parent ();
      }
      return null;
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
