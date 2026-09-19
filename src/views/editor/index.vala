/**
 * Real Gtk-backed facade for the editor pane: a single {@link GtkSource.View}
 * whose content swaps per active tab. An unreadable file is shown by
 * replacing the buffer with a placeholder message and making the view
 * non-editable, rather than by swapping in a different widget.
 *
 * Syntax highlighting and its colors are never hardcoded here: which
 * language a file highlights as comes from {@link GtkSource.LanguageManager},
 * and the colors from a {@link GtkSource.StyleScheme} — both loaded from
 * `.lang`/`.xml` files GtkSourceView already discovers on disk (including
 * under the user's own `~/.local/share/gtksourceview-5/`), so a new language
 * or a recolored one is a file dropped there, not a code change.
 */
public class EditorView : Object {
    private const string SECONDARY_SELECTION_TAG_NAME = "secondary-selection";

    private Gtk.Box root;
    private Gtk.Revealer change_banner_revealer;
    private Gtk.ScrolledWindow scrolled_window;
    private OpusSourceView text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
    private Gtk.TextTag secondary_selection_tag;

    /** Suppresses `text_changed` while a set_text/set_placeholder call is itself writing the buffer. */
    private bool updating_programmatically = false;

    /** Suppresses `native_cursor_moved` while render_cursors() is itself setting the insert/selection_bound marks. */
    private bool setting_cursors_programmatically = false;

    /**
     * Whether the marks' current relative order was set by the user
     * actually dragging (a plain single click, or the drag-select that
     * can follow it) — the only case with a real "direction" worth
     * preserving as-is. Every other unclaimed native action that can
     * move the marks — a double/triple-click's word/line-select,
     * Ctrl+A's select-all, or any other native keybinding GTK adds in
     * the future — has no such direction (nothing was dragged anywhere),
     * so on_mark_set() normalizes those instead of trusting whichever of
     * GTK's own `insert`/`selection_bound` its internal implementation
     * happens to place where — verified for both of the two cases above
     * against GTK's real source, both landing the caret at the *start*,
     * opposite of VS Code's own convention (the caret at the end).
     * Tracking "was this a drag" rather than naming each such action
     * keeps this correct without having to predict every one of them.
     */
    private bool preserve_native_direction = false;

    public Gtk.Widget widget { get { return root; } }

    /** The user edited the text; `new_text` is the buffer's full content. */
    public signal void text_changed (string new_text);

    /** The active tab's file changed on disk and the user chose to discard in-memory content in its favor — see the "Discard Changes and Reload" button on the change banner. */
    public signal void reload_requested ();

    /**
     * A key was pressed in the text view — raw keyval/modifiers, no
     * interpretation of what it means (that depends on live cursor
     * state, which belongs to CursorController, not this View). Return
     * `true` from a handler to claim it (stop it reaching GtkSourceView's
     * own default key handling); `false` lets it fall through natively —
     * see CursorController for exactly which keys are claimed and why
     * the rest deliberately aren't yet.
     */
    public signal bool key_pressed_raw (uint keyval, Gdk.ModifierType state);

    /** A mouse button was pressed in the text view, already resolved from pixels to the buffer offset underneath it. */
    public signal void click_raw (int offset, int n_press, uint button, Gdk.ModifierType state);

    /** The pointer moved during a click-drag in the text view, already resolved to the buffer offset currently under it. */
    public signal void drag_extended_raw (int offset, Gdk.ModifierType state);

    /**
     * The real `insert`/`selection_bound` marks moved for a reason this
     * View didn't itself initiate — a native click GestureClick/Drag
     * left unclaimed (e.g. a double/triple-click's native word/line
     * select), or a key CursorController didn't claim. Also fires
     * (harmlessly, to the same values) right after render_cursors() sets
     * those same marks itself. CursorController listens to keep the
     * primary cursor it tracks from drifting out of sync with what's
     * actually on screen.
     */
    public signal void native_cursor_moved (int anchor_offset, int position_offset);

    public EditorView () {
        var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/editor/index.ui");
        root = (Gtk.Box) builder.get_object ("root");
        change_banner_revealer = (Gtk.Revealer) builder.get_object ("change_banner_revealer");
        scrolled_window = (Gtk.ScrolledWindow) builder.get_object ("scrolled_window");

        text_view = new OpusSourceView ();
        text_view.monospace = true;
        text_view.top_margin = 8;
        text_view.bottom_margin = 8;
        text_view.left_margin = 8;
        text_view.right_margin = 8;
        text_view.show_line_numbers = true;
        // The native caret is never painted — every cursor, primary
        // included, is hand-drawn by OpusSourceView itself so all of
        // them are guaranteed pixel- and blink-identical (see its own
        // doc comment for why). The real insert/selection_bound marks
        // still move normally; only their visual caret line is
        // suppressed, so IM composition, bracket-matching, accessibility,
        // and scroll-to-cursor are all unaffected.
        text_view.cursor_visible = false;
        scrolled_window.set_child (text_view);
        text_view.buffer.changed.connect (on_buffer_changed);
        text_view.buffer.mark_set.connect (on_mark_set);

        // CAPTURE, not the default BUBBLE phase: this has to see a key
        // before GtkTextView's own built-in bindings do, so returning
        // true from a handler actually stops those from also running.
        var key_controller = new Gtk.EventControllerKey ();
        key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
        key_controller.key_pressed.connect ((keyval, keycode, state) => handle_key_pressed (keyval, state));
        text_view.add_controller (key_controller);

        // CAPTURE, so we get first refusal on every press before
        // GtkTextView's own internal click gesture (always BUBBLE phase,
        // set in its own gtk_text_view_init() — not overridable, not
        // exposed to us at all).
        //
        // Verified directly against GTK 4.18's real source
        // (gtk/gtkmain.c's gtk_propagate_event_internal, gtk/gtkgesture.c):
        // claiming a sequence during the CAPTURE pass makes that pass
        // return TRUE, which skips the *entire* "propagate back up"
        // pass outright — gtk_widget_event(), the function that runs
        // GTK_PHASE_TARGET/GTK_PHASE_BUBBLE, is never even called for
        // that event. It's not "the native gesture sees the click and
        // backs off" — it never receives the click at all. Its own
        // multi-click counter (GtkGestureClick's private n_presses,
        // incremented only inside its own begin() vfunc, which only
        // runs when handle_event is actually invoked on it) then starts
        // one physical click late for that whole streak — this is
        // exactly what caused an earlier version of this code (which
        // claimed on *every* n_press == 1, denying n_press >= 2) to need
        // 3 physical clicks for a native double-click and 4 for a
        // triple-click.
        //
        // The fix, confirmed by GTK's own internal precedent
        // (gtk_text_view_click_gesture_pressed claims its own separate
        // drag gesture only for one specific case — never broadly):
        // claim precisely, only for the exact presses that are actually
        // ours — Alt+Click (add a cursor) and Alt+Shift+drag (box
        // select) — and leave every other press at its default NONE
        // state. An unclaimed gesture's handle_event returns FALSE,
        // which does *not* short-circuit propagation, so GtkTextView's
        // native click-to-place, Shift+click-extend, double/triple-click
        // word/line-select, and click-drag-select all keep working
        // completely untouched — native_cursor_moved (below) already
        // picks up whatever the native path lands on.
        //
        // Drag continuation (for Alt+Shift box-select only) rides
        // Gtk.Gesture's own inherited `update` signal rather than a
        // second Gesture or an EventControllerMotion: two Gestures
        // claiming the same sequence deny *each other* (confirmed by
        // trying it — it broke drag-select entirely), and claiming also
        // starves sibling *non-Gesture* controllers' motion delivery too
        // (confirmed the same way — a separate EventControllerMotion
        // received zero events for the whole held-button period). Only
        // this same, already-claimed gesture's own `update` signal
        // reliably keeps receiving position updates while it holds the
        // sequence.
        bool dragging = false;

        var click_gesture = new Gtk.GestureClick ();
        click_gesture.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
        click_gesture.pressed.connect ((n_press, x, y) => {
            var state = click_gesture.get_current_event_state ();
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;

            // CAPTURE fires before GtkTextView's own native handling (see
            // above), so this is set before whatever the native click
            // handling is about to do — on_mark_set() reads it once that
            // lands. Only a plain, single-press click (n_press == 1) has
            // a direction worth preserving: what follows is either just
            // that click, or the drag-select that can follow it.
            preserve_native_direction = n_press == 1;

            if (n_press == 1 && alt) {
                click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
                dragging = shift; // only the box-select case continues via drag right now
            }
            // else: leave the sequence at NONE — no claim, no deny —
            // so it flows to GtkTextView's native handling untouched.

            click_raw (offset_at_widget_position (x, y), n_press, click_gesture.get_current_button (), state);
        });
        click_gesture.released.connect ((n_press, x, y) => {
            dragging = false;
        });
        click_gesture.update.connect ((sequence) => {
            if (!dragging) {
                return;
            }
            double x;
            double y;
            if (click_gesture.get_point (sequence, out x, out y)) {
                drag_extended_raw (offset_at_widget_position (x, y), click_gesture.get_current_event_state ());
            }
        });
        text_view.add_controller (click_gesture);

        // One shared tag applied over every secondary cursor's selection
        // range (if any) — cleared and reapplied fresh on every
        // render_cursors() call, rather than a distinct tag per cursor:
        // they're all styled identically, so a single tag applied to N
        // disjoint ranges is just as correct and simpler to manage.
        secondary_selection_tag = new Gtk.TextTag (SECONDARY_SELECTION_TAG_NAME);
        secondary_selection_tag.background_set = true;
        source_buffer.tag_table.add (secondary_selection_tag);

        var discard_button = (Gtk.Button) builder.get_object ("change_banner_discard_button");
        discard_button.clicked.connect (() => reload_requested ());

        install_css ();

        // GtkSource.Buffer paints with a StyleScheme's own fixed colors
        // instead of following the app's GTK theme, so it stays put through
        // a light/dark switch unless told otherwise — pick the scheme, and
        // the multi-cursor colors that need to track the accent color too,
        // ourselves each time Adwaita's does.
        var style_manager = Adw.StyleManager.get_default ();
        style_manager.notify["dark"].connect (() => apply_theme_colors (style_manager.dark));
        apply_theme_colors (style_manager.dark);
    }

    /**
     * Copied straight from GTK's own real `infobar.warning > revealer >
     * box` / `infobar .close` rules (found in libgtk-4.so's compiled CSS,
     * not guessed) — same `var(--…)` tokens GtkInfoBar itself resolves
     * against, so this tracks light/dark and the accent color exactly the
     * same way it does, with no hardcoded color of our own. The 30% mix
     * with the window background (not a flat `--warning-bg-color`) is
     * what actually gives GtkInfoBar its pale, non-saturated look.
     */
    private void install_css () {
        var css_provider = new Gtk.CssProvider ();
        css_provider.load_from_string ("""
            .change-banner {
                background-color: color-mix(in srgb, var(--warning-bg-color) 30%, var(--window-bg-color));
                color: var(--window-fg-color);
                padding: 6px 6px 7px 6px;
                box-shadow: inset 0 -1px var(--shade-color);
            }

            .change-banner-title {
                font-weight: bold;
            }
        """);
        // See views/tab-bar/_pill.vala for why add_provider_for_display
        // despite the GTK 4.10 deprecation with no replacement.
        Gtk.StyleContext.add_provider_for_display (
            Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }

    /** Shows `text`, highlighted as whichever language `path`'s name/extension matches (none, if it matches none). */
    public void set_text (string text, string path) {
        text_view.editable = true;
        source_buffer.language = GtkSource.LanguageManager.get_default ().guess_language (path, null);
        set_buffer_text (text);
    }

    public string get_text () {
        return text_view.buffer.text;
    }

    /**
     * The real EventControllerKey callback's own body, factored out so
     * a simulated keystroke (below) runs the exact same code a genuine
     * one does — including resetting preserve_native_direction — rather
     * than a second copy that could quietly drift from it.
     */
    private bool handle_key_pressed (uint keyval, Gdk.ModifierType state) {
        preserve_native_direction = false;
        return key_pressed_raw (keyval, state);
    }

    /**
     * Fires `key_pressed_raw` exactly as the real EventControllerKey
     * handler would for a genuine keystroke — driving the same
     * CursorController dispatch, without needing a real GTK event.
     * Opus.Dev.DevServer's own KeyPress (via EditorController), for the
     * system-test DSL to simulate typing/commands. `modifier_state` is
     * the raw `Gdk.ModifierType` bitmask, taken as a plain `uint` here so
     * EditorController — which never imports Gdk itself — can pass one
     * straight through from its own D-Bus-facing method.
     */
    public bool simulate_key_press (uint keyval, uint modifier_state) {
        return handle_key_pressed (keyval, (Gdk.ModifierType) modifier_state);
    }

    /**
     * Fires GtkTextView's own "select-all" keybinding-action signal
     * directly — Opus.Dev.DevServer's own SelectAll (via
     * EditorController), for the system-test DSL to exercise Ctrl+A's
     * real native handling. First routes a Ctrl+A through
     * handle_key_pressed() itself, same as a real keypress would (and
     * unclaimed there, same as a real one) — this is what actually
     * resets preserve_native_direction, not a hand-set precondition
     * that would hide a break in that same mechanism. "select-all"
     * itself doesn't need a real GTK event to reach GtkTextView's own
     * internal binding, unlike an ordinary keystroke (see
     * simulate_key_press()): it's a G_SIGNAL_ACTION signal — GTK's own
     * class handler runs the same way whether the emission came from
     * its keybinding table or, like here, straight from application
     * code.
     */
    public void simulate_select_all () {
        handle_key_pressed (Gdk.Key.a, Gdk.ModifierType.CONTROL_MASK);
        text_view.select_all (true);
    }

    public void set_placeholder (string message) {
        text_view.editable = false;
        source_buffer.language = null;
        set_buffer_text (message);
    }

    public void clear_placeholder () {
        text_view.editable = true;
    }

    /** Moves keyboard focus into the text view — used when opening a tab is meant to start editing right away, not just show it. */
    public void grab_focus () {
        text_view.grab_focus ();
    }

    /**
     * Shows every cursor in `cursors` (must be non-empty) for the
     * currently displayed document: the primary's selection still uses
     * the real native selection_bound/insert range (so it keeps
     * following the system's own selection-color convention), every
     * other cursor's selection uses the shared secondary-selection
     * Gtk.TextTag — but every cursor's *caret*, primary included, is
     * hand-drawn by OpusSourceView (see its own doc comment for why: the
     * native caret is never painted at all, only its marks are still
     * moved). Purely a rendering call — it doesn't read or change the
     * buffer's text.
     */
    public void render_cursors (Cursor[] cursors) {
        assert (cursors.length > 0);

        // select_range() below moves the real insert/selection_bound
        // marks, which fires mark_set — suppressed here so it doesn't
        // turn straight back around into native_cursor_moved and resync
        // CursorController's tracked cursors from what's now only the
        // *primary* mark, collapsing any secondary cursors this same
        // call is trying to render.
        setting_cursors_programmatically = true;
        var primary = cursors[0];
        Gtk.TextIter primary_position;
        Gtk.TextIter primary_anchor;
        source_buffer.get_iter_at_offset (out primary_position, primary.position_offset);
        source_buffer.get_iter_at_offset (out primary_anchor, primary.anchor_offset);
        source_buffer.select_range (primary_position, primary_anchor);
        setting_cursors_programmatically = false;

        Gtk.TextIter buffer_start;
        Gtk.TextIter buffer_end;
        source_buffer.get_start_iter (out buffer_start);
        source_buffer.get_end_iter (out buffer_end);
        source_buffer.remove_tag_by_name (SECONDARY_SELECTION_TAG_NAME, buffer_start, buffer_end);

        var caret_offsets = new int[cursors.length];
        for (int i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            caret_offsets[i] = cursor.position_offset;

            if (i > 0 && !cursor.is_empty) {
                Gtk.TextIter selection_start;
                Gtk.TextIter selection_end;
                source_buffer.get_iter_at_offset (out selection_start, cursor.selection_start);
                source_buffer.get_iter_at_offset (out selection_end, cursor.selection_end);
                source_buffer.apply_tag_by_name (SECONDARY_SELECTION_TAG_NAME, selection_start, selection_end);
            }
        }

        text_view.set_carets (caret_offsets);

        // Restarts every caret's blink phase so they're all solid right
        // after a cursor-visible change (typing, movement, click,
        // undo/redo — anything that calls render_cursors()) instead of
        // blinking on their own unsynchronized cycle; also covers the
        // redraw set_carets() itself needs.
        text_view.reset_blink ();
    }

    /**
     * Mechanically replaces every `[start_offset, end_offset)` in `edits`
     * with its `new_text` — applied in descending `start_offset` order
     * regardless of what order they arrive in, so an edit's own range is
     * never invalidated by one applied after it, and grouped as one
     * `begin_user_action()`/`end_user_action()` pair. No interpretation
     * of what the edits mean — purely mechanical; CursorCollection/
     * EditHistory already decided all of that.
     */
    public void apply_edits (TextEdit[] edits) {
        if (edits.length == 0) {
            return;
        }

        var sorted = new TextEdit[edits.length];
        for (int i = 0; i < edits.length; i++) {
            sorted[i] = edits[i];
        }
        stable_sort_edits_descending (sorted);

        source_buffer.begin_user_action ();
        updating_programmatically = true;
        foreach (var edit in sorted) {
            Gtk.TextIter start_iter;
            Gtk.TextIter end_iter;
            source_buffer.get_iter_at_offset (out start_iter, edit.start_offset);
            source_buffer.get_iter_at_offset (out end_iter, edit.end_offset);
            source_buffer.delete (ref start_iter, ref end_iter);
            source_buffer.insert (ref start_iter, edit.new_text, -1);
        }
        updating_programmatically = false;
        source_buffer.end_user_action ();

        text_changed (get_text ());
    }

    /** Switches GtkSourceView's own native undo manager on/off — off once CursorController's own EditHistory-backed pipeline takes over, so the two never compete for the same Ctrl+Z. */
    public void set_undo_enabled (bool enabled) {
        source_buffer.enable_undo = enabled;
    }

    /** Shows or hides the "File Has Changed on Disk" banner — for whichever document is currently shown, tracked by EditorController, not by EditorView itself. */
    public void set_change_banner_visible (bool visible) {
        change_banner_revealer.reveal_child = visible;
    }

    /**
     * Shows the system's own Save-As file chooser (Gtk.FileDialog — a
     * portal dialog, the desktop's own file manager UI when a portal is
     * available, e.g. GNOME's Nautilus-flavored one), pre-filled with
     * `suggested_name` in `current_folder`. Returns the chosen path, or
     * null if the user cancelled or the dialog/portal itself failed.
     */
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

    private void on_buffer_changed () {
        if (updating_programmatically) {
            return;
        }

        text_changed (get_text ());
    }

    private void on_mark_set (Gtk.TextIter location, Gtk.TextMark mark) {
        if (setting_cursors_programmatically) {
            return;
        }
        if (mark.name != "insert" && mark.name != "selection_bound") {
            return;
        }

        int anchor = get_anchor_offset ();
        int position = get_position_offset ();

        if (preserve_native_direction) {
            native_cursor_moved (anchor, position);
        } else {
            // Not a drag — whatever unclaimed native action just moved
            // the marks (a double/triple-click's word/line-select, a
            // Ctrl+A select-all, or anything else GTK's own default
            // keybindings do) has no real "direction" to preserve, so
            // this normalizes to VS Code's own convention instead: the
            // caret (position) always the larger offset, the anchor
            // always the smaller one — regardless of which of GTK's own
            // `insert`/`selection_bound` its internal implementation
            // happens to place where (verified for both cases named
            // above against GTK's real source; both currently land
            // `insert` at the smaller offset, but this doesn't assume
            // that stays true).
            native_cursor_moved (int.min (anchor, position), int.max (anchor, position));
        }
    }

    private void set_buffer_text (string text) {
        updating_programmatically = true;
        text_view.buffer.text = text;
        updating_programmatically = false;
    }

    private int get_position_offset () {
        Gtk.TextIter iter;
        source_buffer.get_iter_at_mark (out iter, source_buffer.get_insert ());
        return iter.get_offset ();
    }

    private int get_anchor_offset () {
        Gtk.TextIter iter;
        source_buffer.get_iter_at_mark (out iter, source_buffer.get_selection_bound ());
        return iter.get_offset ();
    }

    private int offset_at_widget_position (double widget_x, double widget_y) {
        int buffer_x;
        int buffer_y;
        text_view.window_to_buffer_coords (Gtk.TextWindowType.WIDGET, (int) widget_x, (int) widget_y, out buffer_x, out buffer_y);

        Gtk.TextIter iter;
        text_view.get_iter_at_location (out iter, buffer_x, buffer_y);
        return iter.get_offset ();
    }

    private static void stable_sort_edits_descending (TextEdit[] edits) {
        for (int i = 1; i < edits.length; i++) {
            var key = edits[i];
            int j = i - 1;
            while (j >= 0 && edits[j].start_offset < key.start_offset) {
                edits[j + 1] = edits[j];
                j--;
            }
            edits[j + 1] = key;
        }
    }

    private void apply_style_scheme (bool dark) {
        var scheme_id = dark ? "Adwaita-dark" : "Adwaita";
        source_buffer.style_scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (scheme_id);
    }

    private void apply_theme_colors (bool dark) {
        apply_style_scheme (dark);

        var accent = Adw.StyleManager.get_default ().get_accent_color_rgba () ?? Gdk.RGBA () { red = 0.2f, green = 0.4f, blue = 0.85f, alpha = 1.0f };

        var selection_background = accent;
        selection_background.alpha = 0.35f;
        secondary_selection_tag.background_rgba = selection_background;

        // Every caret's own color (OpusSourceView.snapshot_layer) reads
        // the widget's resolved foreground color directly at paint time
        // instead of being told it here — see that class's own comment
        // for why (a theme-change callback isn't a reliable place to
        // read freshly-resolved CSS from).
    }
}
