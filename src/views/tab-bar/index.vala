/** What the user chose when asked about a tab with unsaved changes. */
public enum DiscardChoice {
    SAVE,
    DISCARD,
    CANCEL,
}

/**
 * Real Gtk-backed facade for the row of open-file tabs above the editor
 * pane: a horizontal, scrollable row of {@link TabPill}s, one per open file,
 * keyed by path.
 */
public class TabBarView : Object {
    // Pixels scrolled per wheel notch (a discrete GtkEventControllerScroll
    // delta is usually ±1; trackpads report fractional deltas, scaling
    // proportionally with the same constant).
    private const double SCROLL_STEP_PX = 40;

    private Gtk.Overlay overlay;
    private Gtk.Box box;
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.Widget fade_start;
    private Gtk.Widget fade_end;
    private HashTable<string, TabPill> pills = new HashTable<string, TabPill> (str_hash, str_equal);
    private TabPill? active_pill = null;
    private string? preview_path = null;

    // The floating "held" copy of whichever pill is currently being
    // dragged — see begin_drag_ghost() and TabGhost. Rendered by whoever
    // owns the window (see the drag_ghost_* signals below), not by this
    // view itself: a copy confined to this row's own bounds can't follow
    // the pointer once it leaves the tab bar, the same way a real file
    // manager's drag icon does.
    private TabGhost? drag_ghost = null;

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

    /** A tab was double-clicked (promotes a preview tab to permanent). */
    public signal void tab_double_clicked (string path);

    /** The preview tab was dragged (or displaced) away from the last position, so it's now permanent. */
    public signal void preview_demoted (string path);

    /** A tab started being dragged: show `ghost` floating at `(x, y, width, height)`, in the window's own coordinates. */
    public signal void drag_ghost_shown (Gtk.Widget ghost, int x, int y, int width, int height);

    /** The dragged tab's ghost should move to `(x, y)`, in the window's own coordinates. */
    public signal void drag_ghost_moved (int x, int y);

    /** The drag ended (or was cancelled); remove the ghost. */
    public signal void drag_ghost_hidden ();

    /** Double-click on the tab bar's own empty area (not on any pill) — same as "New File" (Ctrl+N / the primary menu's own item). */
    public signal void new_file_requested ();

    static construct {
        install_css ();
    }

    public TabBarView () {
        box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

        scrolled_window = new Gtk.ScrolledWindow ();
        // EXTERNAL, not NEVER: per GtkPolicyType's own docs, NEVER means
        // "the content determines the size" — no clipping at all, so the
        // window would keep growing as tabs are added. EXTERNAL keeps the
        // row's width independent of its content (clipped, never drawing a
        // scrollbar, not even an auto-hiding overlay one) — but per its own
        // docs ("this can be used to make multiple scrolled windows share a
        // scrollbar"), it also opts the row out of GtkScrolledWindow's own
        // built-in wheel handling and undershoot-fade indicators, on the
        // assumption something external drives the adjustment (and draws
        // its own edge indicators) instead. The EventControllerScroll and
        // fade_start/fade_end below are that something.
        //
        // `AUTOMATIC` was tried instead, to get the wheel handling and the
        // undershoot fade for free — but it also brings back
        // GtkScrolledWindow's own click-and-drag-to-pan handling on the
        // content, which fights the reorder gesture below the same way the
        // window's own drag-to-move once did (see the [top]-bar history in
        // main-window/index.blp) — reordering a tab ends up panning the
        // row instead. EXTERNAL avoids that entirely, at the cost of having
        // to reimplement the wheel and fade ourselves.
        scrolled_window.set_policy (Gtk.PolicyType.EXTERNAL, Gtk.PolicyType.NEVER);
        scrolled_window.set_child (box);

        var scroll_controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.BOTH_AXES);
        scroll_controller.scroll.connect ((dx, dy) => {
            var adjustment = scrolled_window.get_hadjustment ();
            adjustment.set_value (adjustment.get_value () + (dx != 0 ? dx : dy) * SCROLL_STEP_PX);
            return true;
        });
        scrolled_window.add_controller (scroll_controller);

        fade_start = new_fade_indicator ("start", Gtk.Align.START);
        fade_end = new_fade_indicator ("end", Gtk.Align.END);

        overlay = new Gtk.Overlay ();
        // A row with zero tabs has no content to size itself against, so it
        // collapses to 0px and the content-divider below it rides up next
        // to the header. 31px is a real tab pill's own natural height
        // (measured from a live render, not guessed) — pinning the row to
        // it keeps the divider in place whether there are any tabs or not.
        overlay.add_css_class ("tab-bar");
        overlay.set_child (scrolled_window);
        overlay.add_overlay (fade_start);
        overlay.add_overlay (fade_end);

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

    /**
     * A thin, click-through strip fading to the window's own background
     * color — GTK's own undershoot indicators do the same (a gradient
     * overlay at the edge, not an actual mask on the clipped content), but
     * aren't available here (see the constructor). `edge` drives both the
     * CSS gradient direction and which end of the row this sits at.
     */
    private Gtk.Widget new_fade_indicator (string edge, Gtk.Align align) {
        var indicator = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        indicator.add_css_class ("tab-bar-fade");
        indicator.add_css_class (edge);
        indicator.halign = align;
        indicator.valign = Gtk.Align.FILL;
        indicator.vexpand = true;
        // Let clicks (selecting/reordering a tab underneath) pass through.
        indicator.can_target = false;
        return indicator;
    }

    /** Shows each fade indicator only while its side actually has tabs scrolled out of view. */
    private void update_fade_visibility () {
        var adjustment = scrolled_window.get_hadjustment ();
        fade_start.visible = adjustment.get_value () > 0.5;
        fade_end.visible = adjustment.get_value () < adjustment.get_upper () - adjustment.get_page_size () - 0.5;
    }

    private static void install_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            .tab-bar {
                min-height: 31px;
            }

            .tab-bar-fade {
                min-width: 48px;
            }

            .tab-bar-fade.start {
                background: linear-gradient(to right, var(--view-bg-color), transparent);
            }

            .tab-bar-fade.end {
                background: linear-gradient(to left, var(--view-bg-color), transparent);
            }

            .tab-drag-ghost {
                border-radius: 6px;
            }

            .tab-drag-ghost-light {
                background-color: #ebebeb;
            }

            .tab-drag-ghost-dark {
                background-color: #333336;
            }

            /* The real pill being dragged — stays in place, invisible,
             * showing just its empty slot ("hole") while the ghost above
             * follows the pointer instead. */
            .tab-pill.dragging {
                opacity: 0;
            }
        """);

        // See views/tab-bar/_pill.vala for why add_provider_for_display
        // despite the GTK 4.10 deprecation with no replacement.
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    public void add_tab (string path, string file_name, string folder_name, bool preview) {
        var pill = new TabPill ();
        pill.set_label (file_name, folder_name);
        pill.set_preview (preview);
        pill.selected.connect (() => tab_selected (path));
        pill.double_clicked.connect (() => tab_double_clicked (path));
        pill.close_requested.connect (() => tab_close_requested (path));
        pill.context_menu_requested.connect ((x, y) => show_context_menu (path, pill, x, y));

        pills[path] = pill;
        box.append (pill.widget);
        if (preview) {
            preview_path = path;
        }

        setup_reorder_gesture (path, pill);
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

    /** Re-keys the tab currently shown for `old_path` to `new_path` (e.g. after Save As) and updates its label — the same pill and position, not a new one. */
    public void rename_tab (string old_path, string new_path, string file_name, string folder_name) {
        var pill = pills[old_path];
        if (pill == null) {
            return;
        }

        pills.remove (old_path);
        pills[new_path] = pill;
        pill.set_label (file_name, folder_name);

        if (preview_path == old_path) {
            preview_path = new_path;
        }
    }

    public void copy_to_clipboard (string text) {
        widget.get_clipboard ().set_text (text);
    }

    /**
     * `path`'s own right-click menu. Save/Save as… used to live here too,
     * but only ever applied to the active tab regardless of which tab's
     * menu triggered them — now that they're global (the primary menu,
     * Ctrl+S/Ctrl+Shift+S), keeping a second copy here would just offer
     * the same not-necessarily-this-tab action from a place that implies
     * it's about *this* tab specifically.
     *
     * The "Close" accelerator hint is built via `Gtk.accelerator_get_label`,
     * from the exact same keyval/modifier constants
     * MainWindowView.on_key_pressed matches on — not typed out as literal
     * text, which drifted from the actual keys the first time around and
     * would drift again silently.
     */
    private void show_context_menu (string path, TabPill pill, double x, double y) {
        var popover = ContextMenu.create (pill.widget, x, y);
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        box.append (ContextMenu.item (_("Close"), () => tab_close_requested (path), popover, Gtk.accelerator_get_label (Gdk.Key.w, Gdk.ModifierType.CONTROL_MASK)));
        box.append (ContextMenu.item (_("Close Others"), () => close_others_requested (path), popover));
        box.append (ContextMenu.item (_("Close All"), () => close_all_requested (), popover));
        box.append (ContextMenu.separator ());
        box.append (ContextMenu.item (_("Copy Path"), () => copy_path_requested (path), popover));
        box.append (ContextMenu.item (_("Copy Relative Path"), () => copy_relative_path_requested (path), popover));

        popover.child = box;
        popover.popup ();
    }

    /**
     * Lets `pill` be reordered within the row by dragging it. Tracked with a
     * plain {@link Gtk.GestureDrag} rather than real GDK drag-and-drop
     * ({@link Gtk.DragSource}/{@link Gtk.DropTarget}): a real drag session
     * gets offered to every other drop-capable widget the pointer passes
     * over — including the editor's GtkTextView, which happily accepts and
     * pastes it — and starting one is subject to GTK's DND source/target
     * negotiation, which proved unreliable here. A gesture never leaves this
     * row, so neither problem can happen. Same technique libadwaita's own
     * AdwTabBar uses for in-bar reordering (see AdwTabBox's drag_gesture).
     */
    private void setup_reorder_gesture (string path, TabPill pill) {
        // Where within `pill.widget` the press landed — fixed for the
        // whole drag, so the ghost keeps that same point glued under the
        // pointer regardless of the pill's current size or position.
        double press_x = 0;
        double press_y = 0;
        var dragging = false;

        var drag = new Gtk.GestureDrag ();
        drag.set_button (Gdk.BUTTON_PRIMARY);
        drag.drag_begin.connect ((gesture, x, y) => {
            press_x = x;
            press_y = y;
            dragging = false;
        });
        drag.drag_update.connect ((gesture, offset_x, offset_y) => {
            if (!dragging) {
                if (!Gtk.drag_check_threshold (pill.widget, 0, 0, (int) offset_x, (int) offset_y)) {
                    return;
                }
                dragging = true;
                begin_drag_ghost (pill);
            }

            // Only claim once movement past GTK's drag threshold is
            // confirmed, same as AdwTabBox: claiming unconditionally on
            // every press would swallow plain clicks meant for selection.
            gesture.set_state (Gtk.EventSequenceState.CLAIMED);

            // Not `offset_x`/`offset_y`: GtkGestureDrag reports those
            // relative to `pill.widget`'s OWN current position, which
            // reorder_towards changes mid-drag (moving it to a new
            // sibling slot) — the reference point shifts under it,
            // producing a visible jump. The pointer's raw surface
            // position is unaffected by that, so it's what both the
            // ghost and the reorder target are computed from instead.
            double root_x, root_y;
            if (!get_pointer_root_position (gesture, pill.widget, out root_x, out root_y)) {
                return;
            }

            update_drag_ghost_position (root_x - press_x, root_y - press_y);

            var root = pill.widget.get_root ();
            if (root != null) {
                var point = Graphene.Point () { x = (float) root_x, y = (float) root_y };
                Graphene.Point box_point;
                if (((Gtk.Widget) root).compute_point (box, point, out box_point)) {
                    reorder_towards (path, box_point.x, box_point.y);
                }
            }
        });
        drag.drag_end.connect ((gesture, offset_x, offset_y) => end_drag_ghost (pill));
        drag.cancel.connect ((gesture, sequence) => end_drag_ghost (pill));
        pill.widget.add_controller (drag);
    }

    /** `widget`'s (thus `gesture`'s) root, in the widget tree's own coordinates — from the current event's raw surface position, corrected for the surface's own offset from that root (window decoration shadows, etc). */
    private bool get_pointer_root_position (Gtk.Gesture gesture, Gtk.Widget widget, out double x, out double y) {
        x = 0;
        y = 0;

        var event = gesture.get_current_event ();
        if (event == null) {
            return false;
        }

        double surface_x, surface_y;
        if (!event.get_position (out surface_x, out surface_y)) {
            return false;
        }

        var native = widget.get_native ();
        if (native == null) {
            return false;
        }

        double transform_x, transform_y;
        native.get_surface_transform (out transform_x, out transform_y);
        x = surface_x - transform_x;
        y = surface_y - transform_y;
        return true;
    }

    /**
     * Builds a {@link TabGhost} from `pill`'s current label/state and emits
     * drag_ghost_shown so whoever owns the window shows it floating under
     * the pointer for the rest of the drag: the real pill still swaps
     * position in the row as the pointer crosses a neighbor (see
     * reorder_towards), which alone reads as an abrupt jump rather than a
     * drag — this copy is what makes it feel "held" instead.
     */
    private void begin_drag_ghost (TabPill pill) {
        var root = pill.widget.get_root ();
        if (root == null) {
            return;
        }

        Graphene.Rect bounds;
        if (!pill.widget.compute_bounds ((Gtk.Widget) root, out bounds)) {
            return;
        }

        var ghost = new TabGhost (pill.file_name, pill.folder_name, pill.is_preview, pill.is_modified);
        drag_ghost = ghost;

        // `pill.widget` itself stays right where it is — still in `box`,
        // still swapping position as reorder_towards runs below — just
        // invisible, so the row shows an empty "hole" moving between tabs
        // instead of doubling up with the ghost floating above it.
        pill.widget.add_css_class ("dragging");

        drag_ghost_shown (ghost.widget, (int) bounds.origin.x, (int) bounds.origin.y, (int) bounds.get_width (), (int) bounds.get_height ());
    }

    private void update_drag_ghost_position (double x, double y) {
        if (drag_ghost == null) {
            return;
        }

        drag_ghost_moved ((int) x, (int) y);
    }

    private void end_drag_ghost (TabPill pill) {
        if (drag_ghost == null) {
            return;
        }

        pill.widget.remove_css_class ("dragging");

        drag_ghost = null;
        drag_ghost_hidden ();
    }

    /** Moves `dragged_path`'s pill next to whichever pill is under `(box_x, box_y)`, before or after it. */
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
        // default at medium sizes (its own doc comment on
        // prefer-wide-layout: "By default it will prefer to stack buttons
        // vertically") — side-by-side, like GNOME Text Editor's own
        // unsaved-changes dialog, needs this opted into explicitly.
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
}
