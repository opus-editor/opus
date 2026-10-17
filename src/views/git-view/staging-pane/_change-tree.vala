/**
 * StagingPane's one list: Staged, Conflicts and Unstaged as the root
 * rows of a Gtk.TreeListModel (ChangeGroup), each collapsing the changes
 * under it the way ExplorerPaneTree's folders do — same list CSS, so
 * rows match the explorer's. Conflicts is only in the tree while it
 * has any; every group starts expanded. A click on a group's row
 * toggles it; its own chevron is left to Gtk.TreeExpander.
 *
 * Gtk.MultiSelection gives plain/Ctrl/Shift-click selection straight
 * from GTK's own list bindings, across groups. The row last clicked
 * (or, failing that, the first selected one) keeps its inline actions
 * showing — last_selected, ChangeRow.set_actions_shown(). Gtk.ListView's native
 * `activate` fires identically for a double-click and an Enter press
 * (both call `list.activate-item`), while StagingPane wants different
 * scopes for each (double-click: the row; Enter: the selection), so
 * key_controller takes Return/KP_Enter in the CAPTURE phase, ahead of
 * that binding — item_activated is then only ever a real double-click.
 */
namespace GitView {
  public class ChangeTree : Object {
    private Gtk.ListView list_view;
    private ListStore root = new ListStore (typeof (ChangeGroup));
    private Gtk.TreeListModel tree_model;
    private Gtk.MultiSelection selection;
    private IconTheme icon_theme = new IconTheme.symbols ();
    private string root_path = "";
    private GitScope.Change? last_selected = null;
    private ChangeGroup staged = new ChangeGroup ("staged", _("Staged"));
    private ChangeGroup conflicts = new ChangeGroup ("conflicts", _("Conflicts"));
    private ChangeGroup unstaged = new ChangeGroup ("unstaged", _("Unstaged"));

    public Gtk.Widget widget { get { return list_view; } }

    /** The set of selected rows changed — StagingPane opens a preview when exactly one change is selected. */
    public signal void selection_changed ();

    /** A change's row was double-clicked — just that row, in `section`, whatever else is selected. */
    public signal void item_activated (GitScope.Change change, string section);

    /** Enter pressed with at least one change selected — StagingPane acts on selected_changes() itself. */
    public signal void selection_activated ();

    /** A right-click on the list, at `(x, y)` in widget's coordinates — a change's row not yet selected is selected alone first, so the menu StagingPane builds from selected_changes() is for what was clicked too. */
    public signal void context_menu_requested (double x, double y);

    /** A group row's own action — "stage-all", "unstage-all" or "discard-all" — for every change under `section`. */
    public signal void group_action_requested (string action, string section);

    /** A row's own inline action — "stage", "unstage" or "discard" — for `changes`, in `section`: every selected row of that section when the clicked row is among them, just the clicked row otherwise. */
    public signal void action_requested (string action, GenericArray<GitScope.Change> changes, string section);

    public ChangeTree () {
      root.append (staged);
      root.append (unstaged);
      tree_model = tree_list_model_new_raw (root, false, true, on_create_model_raw, (void*) this, null);

      var factory = new Gtk.SignalListItemFactory ();
      factory.setup.connect (on_setup);
      factory.bind.connect (on_bind);
      factory.unbind.connect (on_unbind);

      selection = new Gtk.MultiSelection (tree_model);
      selection.selection_changed.connect (on_selection_changed);
      list_view = new Gtk.ListView (selection, factory);
      list_view.activate.connect (on_activate);
      // Same two classes ExplorerPaneTree's own list_view carries — see
      // its own doc comment for what each one does.
      list_view.add_css_class ("navigation-sidebar");
      list_view.add_css_class ("data-table");

      var primary_click = new Gtk.GestureClick ();
      primary_click.set_button (Gdk.BUTTON_PRIMARY);
      primary_click.pressed.connect (on_primary_pressed);
      list_view.add_controller (primary_click);

      var secondary_click = new Gtk.GestureClick ();
      secondary_click.set_button (Gdk.BUTTON_SECONDARY);
      secondary_click.pressed.connect ((n_press, x, y) => {
        var row = list_row_at (x, y);
        var change = row?.item as GitScope.Change;
        if (change != null && !is_selected (change)) {
          selection.select_item (row.get_position (), true);
        }
        context_menu_requested (x, y);
      });
      list_view.add_controller (secondary_click);

      var key_controller = new Gtk.EventControllerKey ();
      key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
      key_controller.key_pressed.connect ((keyval, keycode, state) => {
        if (keyval != Gdk.Key.Return && keyval != Gdk.Key.KP_Enter) {
          return false;
        }
        if (has_selected_change ()) {
          selection_activated ();
        }
        return true;
      });
      list_view.add_controller (key_controller);

      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/explorer-pane.css");
    }

    /** Gtk.TreeListModel decides a row is expandable purely from this returning non-null: a group's own store, nothing for a change. */
    private static ListModel? on_create_model_raw (void* item, void* user_data) {
      var group = ((Object) item) as ChangeGroup;
      return group != null ? group.changes.store : null;
    }

    /** Brings `section`'s group in line with `changes` — see ChangeStore.set_changes(). Conflicts joins the tree with its first change and leaves with its last. */
    public void set_changes (string section, GenericArray<GitScope.Change> changes, string root_path) {
      this.root_path = root_path;
      group_for (section).changes.set_changes (changes, root_path);
      if (section == "conflicts") {
        update_conflicts_row ();
      }
    }

    private void update_conflicts_row () {
      uint position;
      bool shown = root.find (conflicts, out position);
      if (conflicts.changes.has_items && !shown) {
        root.insert (1, conflicts);
      } else if (!conflicts.changes.has_items && shown) {
        root.remove (position);
      }
    }

    public bool has_items (string section) {
      return group_for (section).changes.has_items;
    }

    /** Every change under `section`'s row, in list order, selected or not. */
    public GenericArray<GitScope.Change> all_changes (string section) {
      return group_for (section).changes.all_changes ();
    }

    /** Every selected change under `section`'s row, in list order — group rows never count. */
    public GenericArray<GitScope.Change> selected_changes (string section) {
      var result = new GenericArray<GitScope.Change> ();
      var bitset = selection.get_selection ();
      var iter = Gtk.BitsetIter ();
      uint position;
      if (!iter.init_first (bitset, out position)) {
        return result;
      }
      do {
        var row = tree_model.get_row (position);
        var change = row.item as GitScope.Change;
        if (change != null && section_of (row) == section) {
          result.add (change);
        }
      } while (iter.next (out position));
      return result;
    }

    /** Selects just the row for `path` (absolute) under `section`, expanding the group to reach it; false when there is none. */
    public bool select_path (string section, string path) {
      var group = group_for (section);
      uint group_position;
      if (!root.find (group, out group_position)) {
        return false;
      }
      int index = group.changes.index_of (path);
      if (index < 0) {
        return false;
      }
      var group_row = tree_model.get_child_row (group_position);
      group_row.expanded = true;
      selection.select_item (group_row.get_child_row ((uint) index).get_position (), true);
      return true;
    }

    /** See ChangeStore.set_sort_key() — every group's. */
    public void set_sort_key (string key) {
      staged.changes.set_sort_key (key);
      conflicts.changes.set_sort_key (key);
      unstaged.changes.set_sort_key (key);
    }

    private ChangeGroup group_for (string section) {
      switch (section) {
        case "staged": return staged;
        case "conflicts": return conflicts;
        default: return unstaged;
      }
    }

    private bool has_selected_change () {
      return selected_changes ("staged").length > 0
        || selected_changes ("conflicts").length > 0
        || selected_changes ("unstaged").length > 0;
    }

    /** The section a change's row sits under — its parent row's group. */
    private static string section_of (Gtk.TreeListRow row) {
      return ((ChangeGroup) row.get_parent ().item).section;
    }

    private void on_activate (uint position) {
      var row = tree_model.get_row (position);
      var change = row.item as GitScope.Change;
      if (change != null) {
        item_activated (change, section_of (row));
      }
    }

    /**
     * A group's row toggles on a click anywhere along it, not only on
     * its chevron — deferred to an idle, as ExplorerPaneTree.expand_on_idle()
     * is: toggling `expanded` inside the gesture that selects that same
     * row desyncs Gtk.ListView's item manager from the model.
     */
    private void on_primary_pressed (int n_press, double x, double y) {
      if (n_press != 1 || click_is_on_control (x, y)) {
        return;
      }
      var row = list_row_at (x, y);
      if (row == null) {
        return;
      }
      if (row.item is GitScope.Change) {
        last_selected = (GitScope.Change) row.item;
        refresh_actions_shown ();
        return;
      }
      Idle.add (() => {
        row.expanded = !row.expanded;
        return Source.REMOVE;
      });
    }

    /** The clicked row stays last_selected while it is selected; once it is not, the first selected change takes over, or none. */
    private void on_selection_changed () {
      if (last_selected == null || !is_selected (last_selected)) {
        var selected = selected_changes ("staged");
        if (selected.length == 0) {
          selected = selected_changes ("conflicts");
        }
        if (selected.length == 0) {
          selected = selected_changes ("unstaged");
        }
        last_selected = selected.length > 0 ? selected[0] : null;
        refresh_actions_shown ();
      }
      selection_changed ();
    }

    /** The selection under `section` when `change` is part of it, else `change` alone. */
    private GenericArray<GitScope.Change> action_targets (GitScope.Change change, string section) {
      var selected = selected_changes (section);
      for (uint i = 0; i < selected.length; i++) {
        if (selected[i] == change) {
          return selected;
        }
      }
      var single = new GenericArray<GitScope.Change> ();
      single.add (change);
      return single;
    }

    private bool is_selected (GitScope.Change change) {
      foreach (var section in new string[] { "staged", "conflicts", "unstaged" }) {
        var selected = selected_changes (section);
        for (uint i = 0; i < selected.length; i++) {
          if (selected[i] == change) {
            return true;
          }
        }
      }
      return false;
    }

    /** Every row widget on screen re-checks whether it is last_selected's — rows are recycled, so bind() does the same for rows coming in. */
    private void refresh_actions_shown () {
      for (var child = list_view.get_first_child (); child != null; child = child.get_next_sibling ()) {
        var holder = child.get_first_child ();
        if (holder == null) {
          continue;
        }
        ChangeRow? change_row = holder.get_data<ChangeRow> ("change-row");
        if (change_row != null) {
          change_row.set_actions_shown (change_row.bound_change == last_selected);
        }
      }
    }

    /** Whether `(x, y)` lands on something in the row that handles the click itself: a group's action button, or its expander icon — Gtk.TreeExpander toggles for that one. */
    private bool click_is_on_control (double x, double y) {
      Gtk.Widget? picked = list_view.pick (x, y, Gtk.PickFlags.DEFAULT);
      if (picked == null) {
        return false;
      }
      if (picked.get_ancestor (typeof (Gtk.Button)) != null) {
        return true;
      }
      var expander = picked.get_ancestor (typeof (Gtk.TreeExpander)) as Gtk.TreeExpander;
      if (expander == null || expander.child == null) {
        return false;
      }
      return picked != expander.child && !picked.is_ancestor (expander.child);
    }

    /** The Gtk.TreeListRow bound to the row under `(x, y)`, or null over the list's empty background — same pick-and-climb as ExplorerPaneTree.row_widget_at(). */
    private Gtk.TreeListRow? list_row_at (double x, double y) {
      Gtk.Widget? widget = list_view.pick (x, y, Gtk.PickFlags.DEFAULT);
      while (widget != null && widget != list_view) {
        var row = widget.get_data<Gtk.TreeListRow?> ("list-row");
        if (row != null) {
          return row;
        }
        widget = widget.get_parent ();
      }
      return null;
    }

    /** One widget per list item that can show either kind of row: a group's own, or a change's — flush with the group's chevron, no indent. bind() shows one and hides the other. */
    private void on_setup (Object item) {
      var list_item = (Gtk.ListItem) item;
      var group_row = new ChangeGroupRow ();
      var change_row = new ChangeRow (icon_theme);
      group_row.widget.vexpand = true;
      change_row.widget.vexpand = true;
      var holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
      group_row.action_requested.connect ((action, section) => group_action_requested (action, section));
      change_row.action_requested.connect ((action, change) => {
        var section = section_of (holder.get_data<Gtk.TreeListRow> ("list-row"));
        action_requested (action, action_targets (change, section), section);
      });
      holder.append (group_row.widget);
      holder.append (change_row.widget);
      holder.set_data ("group-row", group_row);
      holder.set_data ("change-row", change_row);
      list_item.child = holder;
    }

    private void on_bind (Object item) {
      var list_item = (Gtk.ListItem) item;
      var list_row = (Gtk.TreeListRow) list_item.item;
      var holder = list_item.child;
      var group_row = holder.get_data<ChangeGroupRow> ("group-row");
      var change_row = holder.get_data<ChangeRow> ("change-row");
      holder.set_data ("list-row", list_row);

      var group = list_row.item as ChangeGroup;
      if (group != null) {
        group_row.bind (list_row, group);
      } else {
        var change = (GitScope.Change) list_row.item;
        change_row.bind (change, root_path);
        change_row.set_section (section_of (list_row));
        change_row.set_actions_shown (change == last_selected);
      }
      group_row.widget.visible = group != null;
      change_row.widget.visible = group == null;
    }

    private void on_unbind (Object item) {
      var holder = ((Gtk.ListItem) item).child;
      holder.get_data<ChangeGroupRow> ("group-row").unbind ();
      holder.set_data<Gtk.TreeListRow?> ("list-row", null);
    }
  }
}
