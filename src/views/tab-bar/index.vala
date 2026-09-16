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

    public Gtk.Widget widget { get { return overlay; } }

    /** A tab was clicked (single-click — makes it active). */
    public signal void tab_selected (string path);

    /** A tab's close control was clicked. */
    public signal void tab_close_requested (string path);

    /** A tab was double-clicked (promotes a preview tab to permanent). */
    public signal void tab_double_clicked (string path);

    /** The preview tab was dragged (or displaced) away from the last position, so it's now permanent. */
    public signal void preview_demoted (string path);

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
        overlay.set_child (scrolled_window);
        overlay.add_overlay (fade_start);
        overlay.add_overlay (fade_end);

        var hadjustment = scrolled_window.get_hadjustment ();
        hadjustment.value_changed.connect (update_fade_visibility);
        hadjustment.notify["upper"].connect (update_fade_visibility);
        hadjustment.notify["page-size"].connect (update_fade_visibility);
        update_fade_visibility ();
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
            .tab-bar-fade {
                min-width: 48px;
            }

            .tab-bar-fade.start {
                background: linear-gradient(to right, var(--view-bg-color), transparent);
            }

            .tab-bar-fade.end {
                background: linear-gradient(to left, var(--view-bg-color), transparent);
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
        double start_x = 0;
        double start_y = 0;
        var dragging = false;

        var drag = new Gtk.GestureDrag ();
        drag.set_button (Gdk.BUTTON_PRIMARY);
        drag.drag_begin.connect ((gesture, x, y) => {
            start_x = x;
            start_y = y;
            dragging = false;
        });
        drag.drag_update.connect ((gesture, offset_x, offset_y) => {
            if (!dragging) {
                if (!Gtk.drag_check_threshold (pill.widget, 0, 0, (int) offset_x, (int) offset_y)) {
                    return;
                }
                dragging = true;
            }

            // Only claim once movement past GTK's drag threshold is
            // confirmed, same as AdwTabBox: claiming unconditionally on
            // every press would swallow plain clicks meant for selection.
            gesture.set_state (Gtk.EventSequenceState.CLAIMED);

            var point = Graphene.Point () { x = (float) (start_x + offset_x), y = (float) (start_y + offset_y) };
            Graphene.Point box_point;
            if (pill.widget.compute_point (box, point, out box_point)) {
                reorder_towards (path, box_point.x, box_point.y);
            }
        });
        pill.widget.add_controller (drag);
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
