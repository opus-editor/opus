/** What the user chose when asked about a tab with unsaved changes. */
public enum DiscardChoice {
  SAVE,
  DISCARD,
  CANCEL,
}

/**
 * Real Gtk-backed facade for the row of open-file tabs above the editor
 * pane: a horizontal, scrollable row of {@link TabBarPill}s, one per open file,
 * keyed by path.
 */
namespace EditorView.EditorPane_ {
  public class TabBar : Object {
    // Pixels scrolled per wheel notch (a discrete GtkEventControllerScroll
    // delta is usually ±1; trackpads report fractional deltas, scaling
    // proportionally with the same constant).
    private const double SCROLL_STEP_PX = 40;

    private Gtk.Overlay overlay;
    private Gtk.Box box;
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.Widget fade_start;
    private Gtk.Widget fade_end;
    private HashTable<string, TabBarPill> pills = new HashTable<string, TabBarPill> (str_hash, str_equal);
    private TabBarPill? active_pill = null;
    private string? preview_path = null;

    public Gtk.Widget widget { get { return overlay; } }

    /** A tab was clicked (single-click — makes it active). */
    public signal void tab_selected (string path);

    /** A tab's close control was clicked. */
    public signal void tab_close_requested (string path);

    /** "Close Others" from a tab's context menu — `path` is the one to keep open. */
    public signal void close_others_requested (string path);

    /** "Close All" from a tab's context menu. */
    public signal void close_all_requested ();

    public signal void copy_path_requested (string path);
    public signal void copy_relative_path_requested (string path);

    /** "Reveal in Sidebar" from a tab's context menu — expands/selects `path` in the sidebar and briefly flashes it, if a sidebar is even linked for this window (whoever wires this up decides that; TabBar has no idea). */
    public signal void reveal_in_sidebar_requested (string path);

    /** A tab was double-clicked (promotes a preview tab to permanent). */
    public signal void tab_double_clicked (string path);

    /** The preview tab was dragged (or displaced) away from the last position, so it's now permanent. */
    public signal void preview_demoted (string path);

    /** Double-click on the tab bar's own empty area (not on any pill) — same as "New File" (Ctrl+N / the primary menu's own item). */
    public signal void new_file_requested ();

    public TabBar () {
      var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor-view/editor-pane/tab-bar/index.ui");
      overlay = (Gtk.Overlay) builder.get_object ("overlay");
      box = (Gtk.Box) builder.get_object ("box");
      scrolled_window = (Gtk.ScrolledWindow) builder.get_object ("scrolled_window");
      fade_start = (Gtk.Widget) builder.get_object ("fade_start");
      fade_end = (Gtk.Widget) builder.get_object ("fade_end");

      install_css ();

      var scroll_controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
      scroll_controller.scroll.connect ((dx, dy) => {
        var adjustment = scrolled_window.get_hadjustment ();
        adjustment.set_value (adjustment.get_value () + (dx != 0 ? dx : dy) * SCROLL_STEP_PX);
        return true;
      });
      scrolled_window.add_controller (scroll_controller);

      var hadjustment = scrolled_window.get_hadjustment ();
      hadjustment.value_changed.connect (update_fade_visibility);
      hadjustment.notify["upper"].connect (update_fade_visibility);
      hadjustment.notify["page-size"].connect (update_fade_visibility);
      update_fade_visibility ();

      // Double-clicking the empty stretch of the row (past the last
      // tab, or the whole row with none open) is a quick "New File" —
      // on the outermost widget, not `box` itself, since a Gtk.Box with
      // no hexpand only sizes to its own children and wouldn't cover
      // the empty space to their right at all.
      var new_file_click = new Gtk.GestureClick ();
      new_file_click.set_button (Gdk.BUTTON_PRIMARY);
      new_file_click.pressed.connect ((n_press, x, y) => {
        if (n_press == 2 && click_is_on_empty_area (x, y)) {
          new_file_requested ();
        }
      });
      overlay.add_controller (new_file_click);

      setup_reorder_drop_target ();
    }

    private void install_css () {
      GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/tab-bar.css");
    }

    /** Whether `(x, y)` (in `overlay`'s own coordinates) lands outside every pill — walks up from whatever's actually under the point looking for one whose direct parent is `box` (a pill's own root widget); reaching `box` itself first means the background was hit instead. */
    private bool click_is_on_empty_area (double x, double y) {
      Gtk.Widget? picked = overlay.pick (x, y, Gtk.PickFlags.DEFAULT);
      while (picked != null && picked != box) {
        if (picked.get_parent () == box) {
          return false;
        }
        picked = picked.get_parent ();
      }
      return true;
    }

    /** Shows each fade indicator only while its side actually has tabs scrolled out of view. */
    private void update_fade_visibility () {
      var adjustment = scrolled_window.get_hadjustment ();
      fade_start.visible = adjustment.get_value () > 0.5;
      fade_end.visible = adjustment.get_value () < adjustment.get_upper () - adjustment.get_page_size () - 0.5;
    }

    /** `tooltip_path` is the tab's own clean, user-facing name — a real file's real path, or a synthetic tab's plain display name — never `path` itself, which is just this tab's own internal identity key and, for a synthetic tab, not something to ever show the user. */
    public void add_tab (string path, string file_name, string folder_name, bool preview, string tooltip_path) {
      var pill = new TabBarPill ();
      pill.set_label (file_name, folder_name);
      pill.set_preview (preview);
      pill.tooltip_path = tooltip_path;
      // A plain Gtk.Widget property — no need for a TabBarPill method of
      // its own just to proxy it.
      pill.widget.tooltip_text = display_path (tooltip_path);
      pill.selected.connect (() => tab_selected (path));
      pill.double_clicked.connect (() => tab_double_clicked (path));
      pill.close_requested.connect (() => tab_close_requested (path));
      pill.context_menu_requested.connect ((x, y) => show_context_menu (path, pill, x, y));

      pills[path] = pill;
      box.append (pill.widget);
      if (preview) {
        preview_path = path;
      }

      setup_drag_source (pill);
      // A newly-appended permanent tab may have just pushed an existing
      // preview tab out of the last position.
      enforce_preview_is_last ();
    }

    public void remove_tab (string path) {
      var pill = pills[path];
      if (pill == null) {
        return;
      }

      box.remove (pill.widget);
      pills.remove (path);
      if (active_pill == pill) {
        active_pill = null;
      }
      if (preview_path == path) {
        preview_path = null;
      }
    }

    /**
     * The rightmost open tab's path, or null if none are open — `pills`
     * is a plain HashTable with no ordering of its own, so this walks
     * `box`'s real widget children instead, the actual visual left-to-
     * right order (drag-reordering included). Lets a caller closing the
     * active tab fall back to some other one without tracking order
     * itself.
     */
    public string? last_tab_path () {
      var last_child = box.get_last_child ();
      if (last_child == null) {
        return null;
      }

      foreach (var path in pills.get_keys ()) {
        if (pills[path].widget == last_child) {
          return path;
        }
      }
      return null;
    }

    public void set_active (string path) {
      if (active_pill != null) {
        active_pill.set_active (false);
      }

      active_pill = pills[path];
      if (active_pill != null) {
        active_pill.set_active (true);
        scroll_into_view (active_pill.widget);
      }
    }

    /**
     * Scrolls the row so `child` is fully visible. Deferred to an idle
     * callback because a just-appended pill has no valid allocation yet —
     * layout only happens on the next main-loop iteration.
     */
    private void scroll_into_view (Gtk.Widget child) {
      Idle.add (() => {
        Graphene.Rect bounds;
        if (!child.compute_bounds (box, out bounds)) {
          return false;
        }

        var adjustment = scrolled_window.get_hadjustment ();
        var child_start = bounds.origin.x;
        var child_end = child_start + bounds.get_width ();
        var page_start = adjustment.value;
        var page_end = page_start + adjustment.page_size;

        if (child_start < page_start) {
          adjustment.value = child_start;
        } else if (child_end > page_end) {
          adjustment.value = child_end - adjustment.page_size;
        }

        return false;
      });
    }

    public void mark_preview (string path, bool preview) {
      var pill = pills[path];
      if (pill == null) {
        return;
      }

      pill.set_preview (preview);
      if (preview) {
        preview_path = path;
      } else if (preview_path == path) {
        preview_path = null;
      }
    }

    public void mark_modified (string path, bool modified) {
      var pill = pills[path];
      if (pill != null) {
        pill.set_modified (modified);
      }
    }

    /** The file behind `path` was deleted (or moved away) outside Opus, or came back — strikes through the tab's own label and updates its tooltip to say so. */
    public void mark_deleted (string path, bool deleted) {
      var pill = pills[path];
      if (pill == null) {
        return;
      }

      pill.set_deleted (deleted);
      pill.widget.tooltip_text = deleted
        ? _("%s · Deleted").printf (display_path (pill.tooltip_path))
        : display_path (pill.tooltip_path);
    }

    /** The file behind `path` changed on disk while unresolved — stays true whether or not the "File Has Changed on Disk" banner itself is currently showing. */
    public void mark_unsynchronized (string path, bool unsynchronized) {
      var pill = pills[path];
      if (pill == null) {
        return;
      }

      pill.set_unsynchronized (unsynchronized);
      pill.widget.tooltip_text = unsynchronized
        ? _("%s · Unsynchronized").printf (display_path (pill.tooltip_path))
        : display_path (pill.tooltip_path);
    }

    /** A plugin's own decoration for the file behind `path` (git status, a future linter badge, …), or null with nothing to show. Same "just overwrite tooltip_text" simplification mark_deleted()/mark_unsynchronized() above already make — doesn't try to compose with either of their own tooltip suffixes if more than one happens to apply at once. */
    public void mark_decoration (string path, FileDecoration.State? decoration) {
      var pill = pills[path];
      if (pill == null) {
        return;
      }

      pill.set_decoration (decoration);
      pill.widget.tooltip_text = decoration?.tooltip != null
        ? "%s · %s".printf (display_path (pill.tooltip_path), decoration.tooltip)
        : display_path (pill.tooltip_path);
    }

    /** Re-keys the tab currently shown for `old_path` to `new_path` (e.g. after Save As) and updates its label — the same pill and position, not a new one. `tooltip_path` — see add_tab()'s own doc comment. */
    public void rename_tab (string old_path, string new_path, string file_name, string folder_name, string tooltip_path) {
      var pill = pills[old_path];
      if (pill == null) {
        return;
      }

      pills.remove (old_path);
      pills[new_path] = pill;
      pill.set_label (file_name, folder_name);
      pill.tooltip_path = tooltip_path;
      pill.widget.tooltip_text = display_path (tooltip_path);

      if (preview_path == old_path) {
        preview_path = new_path;
      }
    }

    public void copy_to_clipboard (string text) {
      widget.get_clipboard ().set_text (text);
    }

    /**
     * `path`'s own right-click menu. Save/Save as… don't live here:
     * they only ever apply to the active tab regardless of which tab's
     * menu triggered them, so they're global (the primary menu, Ctrl+S/
     * Ctrl+Shift+S) instead of a second, misleadingly tab-scoped copy.
     *
     * The "Close" accelerator hint is built via `Gtk.accelerator_get_label`,
     * from the exact same keyval/modifier constants MainWindow.
     * on_key_pressed matches on — not typed out as literal text, which
     * would silently drift from the actual keys.
     */
    private void show_context_menu (string path, TabBarPill pill, double x, double y) {
      ContextMenu.popup_at (pill.widget, x, y, (popover, box) => {
        box.append (ContextMenu.item (_("Close"), () => tab_close_requested (path), popover, Gtk.accelerator_get_label (Gdk.Key.w, Gdk.ModifierType.CONTROL_MASK)));
        box.append (ContextMenu.item (_("Close Others"), () => close_others_requested (path), popover));
        box.append (ContextMenu.item (_("Close All"), () => close_all_requested (), popover));
        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Reveal in Sidebar"), () => reveal_in_sidebar_requested (path), popover));
        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Copy Path"), () => copy_path_requested (path), popover));
        box.append (ContextMenu.item (_("Copy Relative Path"), () => copy_relative_path_requested (path), popover));
      });
    }

    /**
     * Lets `pill` be dragged to reorder it within the row, or onto
     * EditorView.FileTree's own sidebar (see FileDrag.make_source()'s own
     * comment). Real Gtk.DragSource, not a hand-rolled gesture: the
     * payload carries its own distinct GType (FileDragPayload) instead
     * of plain text, so nothing else in GTK declares interest in it and
     * it's never offered anywhere it shouldn't be. Reordering within
     * this row is just this row's own Gtk.DropTarget (see
     * setup_reorder_drop_target() below) accepting the very same
     * payload a plain pill drag produces.
     */
    private void setup_drag_source (TabBarPill pill) {
      var source = FileDrag.make_source (pill.widget, (x, y) => {
        var path = path_of (pill);
        if (path == null) {
          return null;
        }

        // A live Gtk.WidgetPaintable of `pill.widget` itself would
        // carry over whatever it's currently rendering (e.g. an
        // inactive tab's dimmed look) into the drag icon, with no
        // clean way to override that on the paintable copy — a fresh,
        // throwaway pill, always shown as if active, is what GTK's
        // own native tab drag (and libadwaita's own AdwTabBox) uses
        // instead, so this does too.
        var ghost = new TabBarGhost (pill.file_name, pill.folder_name, pill.is_preview, pill.is_modified);
        // A freshly-built widget has never been through a real
        // measure/allocate pass — Gtk.DragIcon showing it before one
        // ever happens logs "Trying to snapshot GtkGizmo without a
        // current allocation". AdwTabBox's own drag icon explicitly
        // sizes its equivalent throwaway tab the same way, matching
        // the real pill's own current size.
        ghost.widget.set_size_request (pill.widget.get_width (), pill.widget.get_height ());
        return new FileDragCandidate (path, pill.widget, ghost.widget);
      });

      // The real pill stays right where it is — still in `box`, still
      // swapping position as reorder_towards runs below — just
      // invisible, so the row shows an empty "hole" moving between tabs
      // instead of doubling up with the drag icon floating above it.
      source.drag_begin.connect ((drag) => pill.widget.add_css_class ("dragging"));
      source.drag_end.connect ((drag, delete_data) => pill.widget.remove_css_class ("dragging"));
      source.drag_cancel.connect ((drag, reason) => {
        pill.widget.remove_css_class ("dragging");
        return false; // let GTK play its own default "snap back" animation
      });
    }

    /** `pill`'s current path — looked up by identity rather than captured at add_tab() time: rename_tab() never re-points at a tab's new path after a rename, a real pre-existing gap out of scope to fix here, but not one to add a new instance of for a drag specifically. */
    private string? path_of (TabBarPill pill) {
      foreach (var path in pills.get_keys ()) {
        if (pills[path] == pill) {
          return path;
        }
      }
      return null;
    }

    /**
     * Accepts a FileDragPayload dropped anywhere in the row: motion()
     * moves the dragged pill live as the pointer crosses a neighbor.
     * Only ever accepts a path that's actually one of this row's own
     * open tabs — a drag originating elsewhere (e.g. a sidebar entry)
     * has nothing to reorder here, and is rejected rather than doing
     * something undefined with it.
     *
     * `preload = true`: without it, Gtk.DropTarget doesn't actually
     * fetch the drag's content until the drop itself — get_value()
     * below stays null for the entire hover.
     */
    private void setup_reorder_drop_target () {
      var drop_target = new Gtk.DropTarget (typeof (FileDragPayload), Gdk.DragAction.MOVE);
      drop_target.preload = true;
      drop_target.motion.connect ((x, y) => {
        var raw_value = drop_target.get_value ();
        var payload = raw_value == null ? null : raw_value.get_object () as FileDragPayload;
        if (payload == null || !pills.contains (payload.path)) {
          return 0;
        }

        reorder_towards (payload.path, x, y);
        return Gdk.DragAction.MOVE;
      });
      drop_target.drop.connect ((value, x, y) => {
        var payload = value.get_object () as FileDragPayload;
        return payload != null && pills.contains (payload.path);
      });
      box.add_controller (drop_target);
    }

    /** Moves `dragged_path`'s pill next to whichever pill is under `(box_x, box_y)` (already in `box`'s own coordinates), before or after it. */
    private void reorder_towards (string dragged_path, double box_x, double box_y) {
      var dragged_pill = pills[dragged_path];
      if (dragged_pill == null) {
        return;
      }

      var target = box.pick (box_x, box_y, Gtk.PickFlags.DEFAULT);
      while (target != null && target.get_parent () != box) {
        target = target.get_parent ();
      }
      if (target == null || target == dragged_pill.widget) {
        return;
      }

      var box_point = Graphene.Point () { x = (float) box_x, y = (float) box_y };
      Graphene.Point local_point;
      if (!box.compute_point (target, box_point, out local_point)) {
        return;
      }

      var target_on_right_half = local_point.x > target.get_width () / 2.0;
      var sibling = target_on_right_half ? target : target.get_prev_sibling ();
      if (sibling == dragged_pill.widget) {
        return;
      }

      box.reorder_child_after (dragged_pill.widget, sibling);
      enforce_preview_is_last ();
    }

    /** Demotes the preview tab to permanent if it's no longer the last one in the row. */
    private void enforce_preview_is_last () {
      if (preview_path == null) {
        return;
      }

      var pill = pills[preview_path];
      if (pill == null || box.get_last_child () == pill.widget) {
        return;
      }

      var demoted_path = preview_path;
      preview_path = null;
      pill.set_preview (false);
      preview_demoted (demoted_path);
    }

    public async DiscardChoice confirm_unsaved_close (string filename) {
      var dialog = new Adw.AlertDialog (
        _("Save changes to “%s”?").printf (filename),
        _("Your changes will be lost if you don't save them.")
      );
      dialog.add_response ("cancel", _("Cancel"));
      dialog.add_response ("discard", _("Don't Save"));
      dialog.add_response ("save", _("Save"));
      dialog.set_response_appearance ("discard", Adw.ResponseAppearance.DESTRUCTIVE);
      dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
      dialog.set_default_response ("save");
      dialog.set_close_response ("cancel");
      // Adw.AlertDialog stacks its response buttons vertically by
      // default at medium sizes — side-by-side needs this opted into
      // explicitly.
      dialog.prefer_wide_layout = true;

      var response = yield dialog.choose (widget, null);
      switch (response) {
        case "save":
          return DiscardChoice.SAVE;
        case "discard":
          return DiscardChoice.DISCARD;
        default:
          return DiscardChoice.CANCEL;
      }
    }

    /** `path`, with the user's home directory collapsed to `~` if it's under there — same shorthand every terminal/file manager already uses, for the tab tooltip. */
    private static string display_path (string path) {
      var home = Environment.get_home_dir ();
      if (path.has_prefix (home + "/")) {
        return "~" + path.substring (home.length);
      }
      return path;
    }
  }
}
