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
    private const string SELECTION_TAG_NAME = "cursor-selection";

    private Gtk.Box root;
    private Gtk.Revealer change_banner_revealer;
    private Gtk.ScrolledWindow scrolled_window;
    private OpusSourceView text_view;
    private GtkSource.Buffer source_buffer { get { return (GtkSource.Buffer) text_view.buffer; } }
    private Gtk.TextTag selection_tag;
    private Gdk.RGBA focused_selection_background;
    private Gdk.RGBA backdrop_selection_background;

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

    /**
     * The real buffer's text was structurally edited (inserted into or
     * deleted from) by some native GTK path this View didn't itself
     * drive through apply_edits() — a defense-in-depth net for whatever
     * that turns out to be (e.g. an external app's text dropped into the
     * editor, still handled by GtkTextView's own native drop-target
     * logic — only its native drag-*start* is preempted, by our own
     * DragSource below, not its target side). Captured directly from
     * Gtk.TextBuffer's own insert-text/delete-range signal parameters,
     * before the mutation lands, so it's exact — not a before/after diff
     * reconstructed after the fact. CursorController pushes each one as
     * its own EditHistory entry.
     */
    public signal void untracked_edit (TextEdit edit);

    /**
     * The primary selection's own drag-to-move (our own reimplementation
     * — see the DragSource/DropTarget setup below for why GTK's native
     * one can't be used at all) landed. `source_start`/`source_end` are
     * that selection's original bounds, `drop_offset` is where it was
     * released — all offsets against the buffer as it stood *before*
     * this drop, mirroring TextEdit's own convention. `text` is the
     * moved selection's own content, captured once at drag-start so
     * CursorController never needs to re-derive a substring for this.
     * Purely mechanical, same shape as click_raw/drag_extended_raw — no
     * interpretation of "is this actually a no-op" here (e.g. dropping
     * back inside the original range); CursorController decides that.
     */
    public signal void selection_dropped (string text, int source_start, int source_end, int drop_offset);

    /**
     * A right-click landed on the text (widget-relative `x`/`y`) — this
     * View doesn't decide the context menu's own item states itself:
     * whether Cut/Copy/Delete or Undo/Redo make sense right now depends
     * on the live CursorCollection/EditHistory, which live in the Model,
     * not here. CursorController answers with show_context_menu() once
     * it's worked that out.
     */
    public signal void context_menu_requested (double x, double y);

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
        // Plain .connect() (not _after) runs before GtkTextBuffer's own
        // default handler actually applies the mutation, so `pos`/`start`/
        // `end` still describe what's *about to* happen — exact structured
        // data, not something reconstructed afterward.
        text_view.buffer.insert_text.connect (on_insert_text);
        text_view.buffer.delete_range.connect (on_delete_range);

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
        // Drag continuation (for both Alt-drag cases — plain Alt extends
        // the just-added cursor into a selection, Alt+Shift box-selects)
        // rides Gtk.Gesture's own inherited `update` signal rather than a
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

        // Our own reimplementation of "drag a selection to move it" —
        // GTK's native one (a private GtkGestureDrag + a GdkDrag created
        // inside a static function, both confirmed unreachable from
        // application code by reading gtk/gtktextview.c directly) can't
        // be used at all: its own drop-position indicator gates its
        // visibility on cursor_visible(text_view), a private function
        // returning `use_caret || priv->cursor_visible` — permanently
        // false in Opus's own configuration (cursor_visible = false, to
        // suppress the native caret entirely — see OpusSourceView's own
        // doc comment), so the indicator could never be made to appear
        // without either reintroducing a duplicate native caret or
        // mutating a desktop-wide accessibility setting shared by every
        // GTK app on the system. Both rejected.
        //
        // Built on top of click_gesture below rather than a separate
        // Gtk.DragSource: DragSource's own gesture recognition only
        // calls its `prepare` signal once a real drag threshold is
        // crossed on a *later* motion event — but GTK's own native
        // precedent (gtk_text_view_click_gesture_pressed) claims its
        // internal drag gesture immediately on the *press* itself (if
        // inside the selection), and once that claim lands, GTK's own
        // cross-gesture arbitration denies every other ungrouped gesture
        // watching that same sequence — including a DragSource — before
        // it ever gets to recognize its own, later threshold crossing
        // (confirmed live: a DragSource attached this way never once
        // fired `prepare`). So this claims on press, exactly like Alt+
        // Click already does below, and drives the rest by hand:
        // `possible_selection_drag` tracks a claimed press that might
        // still turn out to be just a click (see the `released` handler
        // for why that fallback is needed, and start_selection_drag()
        // for where the drag actually starts once threshold is crossed).
        bool possible_selection_drag = false;
        double drag_press_x = 0;
        double drag_press_y = 0;

        var click_gesture = new Gtk.GestureClick ();
        click_gesture.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
        // GTK's own native click_gesture (gtk_text_view_init) listens for
        // *any* button (button = 0), not just the primary one — its own
        // pressed handler is where the native context-menu-on-right-click
        // check happens (gdk_event_triggers_context_menu(), confirmed
        // directly in gtktextview.c), ahead of its primary-button branch.
        // Widening this gesture the same way is what lets it claim a
        // right-click too — same CAPTURE-preemption this already relies
        // on for Alt+Click and the selection-drag start below.
        click_gesture.button = 0;
        click_gesture.pressed.connect ((n_press, x, y) => {
            var state = click_gesture.get_current_event_state ();
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            uint button = click_gesture.get_current_button ();

            // CAPTURE fires before GtkTextView's own native handling (see
            // above), so this is set before whatever the native click
            // handling is about to do — on_mark_set() reads it once that
            // lands. Only a plain, single-press primary click (n_press ==
            // 1) has a direction worth preserving: what follows is either
            // just that click, or the drag-select that can follow it.
            preserve_native_direction = n_press == 1 && button == Gdk.BUTTON_PRIMARY;

            if (button == Gdk.BUTTON_SECONDARY && n_press == 1) {
                // Claim outright, same as Alt+Click below — this is what
                // stops gtk_text_view_do_popup() from ever running (its
                // own native Cut/Copy/Paste/Delete menu items call
                // GtkTextBuffer's clipboard methods directly, the exact
                // primary-selection-only, non-EditHistory path Cut/Copy/
                // Paste were already claimed away from at the keyboard
                // level — see CursorController's own Ctrl+X/C/V handling).
                // No cursor/selection change of our own here either: GTK's
                // real gtk_text_view_do_popup() doesn't reposition the
                // cursor on a right-click, so this doesn't need to.
                click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
                context_menu_requested (x, y);
            } else if (button == Gdk.BUTTON_PRIMARY && n_press <= 3 && alt) {
                // Also claims Alt+Double/Triple-click now (not just
                // Alt+Click): CursorController.on_click expands the
                // just-added cursor to its word/line for those, same as
                // native double/triple-click does for a single cursor —
                // leaving this unclaimed would let native handling run
                // right after and replace the whole multi-cursor set
                // with its own single selection.
                click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
                // Only a plain single Alt+click continues via drag —
                // either the added cursor extending into a selection, or
                // Alt+Shift box-select (CursorController.on_drag_extended
                // tells them apart by shift's own state). Alt+Double/
                // Triple-click's own word/line expansion is a deliberate
                // one-shot action, not drag-extending further — see
                // CursorCollection.expand_last_added_cursor_to_word/
                // line()'s own doc comments for that trade-off.
                dragging = n_press == 1;
            } else if (button == Gdk.BUTTON_PRIMARY && n_press == 1 && !alt && !shift && is_inside_selection (x, y)) {
                click_gesture.set_state (Gtk.EventSequenceState.CLAIMED);
                possible_selection_drag = true;
                drag_press_x = x;
                drag_press_y = y;
            }
            // else: leave the sequence at NONE — no claim, no deny —
            // so it flows to GtkTextView's native handling untouched.

            click_raw (offset_at_widget_position (x, y), n_press, click_gesture.get_current_button (), state);
        });
        click_gesture.released.connect ((n_press, x, y) => {
            dragging = false;
            if (possible_selection_drag) {
                // Claiming the press to *maybe* start a drag means
                // nothing else will reposition the cursor if it turns
                // out to just be a click with no real movement — native
                // GTK needs the exact same fallback, for the exact same
                // reason (gtk_text_view_click_gesture_released).
                possible_selection_drag = false;
                Gtk.TextIter iter;
                source_buffer.get_iter_at_offset (out iter, offset_at_widget_position (x, y));
                source_buffer.place_cursor (iter);
            }
        });
        click_gesture.update.connect ((sequence) => {
            if (possible_selection_drag) {
                double x;
                double y;
                if (click_gesture.get_point (sequence, out x, out y) &&
                    Gtk.drag_check_threshold (text_view, (int) drag_press_x, (int) drag_press_y, (int) x, (int) y)) {
                    possible_selection_drag = false;
                    start_selection_drag (click_gesture.get_current_event ());
                }
                return;
            }
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

        // GtkTextView's own native *drop target* side is untouched by
        // any of the above — only its native drag-*start* competes with
        // click_gesture's own claim, never its target side — so this
        // stays a plain Gtk.DropTarget, reacting to the GDK drag-and-
        // drop protocol the same way regardless of whether the Gdk.Drag
        // was started by a Gtk.DragSource or, as above, by hand.
        var drop_target = new Gtk.DropTarget (typeof (EditorDragPayload), Gdk.DragAction.MOVE);
        drop_target.motion.connect (on_drop_motion);
        drop_target.leave.connect (on_drop_leave);
        drop_target.drop.connect (on_drop);
        text_view.add_controller (drop_target);

        // One shared tag applied over every cursor's selection range (if
        // any), primary included — cleared and reapplied fresh on every
        // render_cursors() call, rather than a distinct tag per cursor:
        // they're all styled identically, so a single tag applied to N
        // disjoint ranges is just as correct and simpler to manage. The
        // real native selection_bound/insert range (moved below) still
        // drives which text counts as selected for copy/cut/drag/IM
        // purposes — this tag only controls how that range is *painted*
        // (see install_css()'s own `selection` node rule for why the
        // native painting itself is suppressed).
        selection_tag = new Gtk.TextTag (SELECTION_TAG_NAME);
        selection_tag.background_set = true;
        source_buffer.tag_table.add (selection_tag);

        // GTK's own native selection (gtktextview.c: gtk_text_view_
        // state_flags_changed) grays its selection out whenever the
        // window is inactive, by giving its "selection" CSS node the
        // widget's full current state flags — BACKDROP included — and
        // theming that state separately (gtk's own Default theme:
        // `textview > text > selection { background-color: $backdrop_
        // selected_bg_color; &:focus-within { ...$selected_text_bg_color; } }`,
        // where `$backdrop_selected_bg_color` is the selection color
        // fully desaturated). Reusing that same real BACKDROP flag here
        // (state_flags_changed already fires on text_view itself: state
        // flags like BACKDROP propagate down from the toplevel window to
        // every descendant) reproduces that behavior for our own tag.
        text_view.state_flags_changed.connect ((previous_state) => update_selection_background ());

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

            /* libadwaita's own default for any widget currently holding
             * an "active" drop target (base.css: `:drop(active)`) is a
             * 1px accent-colored inset border — same fix as TabBarView's
             * own `.tab-row:drop(active)` and FileTreeView's own
             * `listview.data-table:drop(active)`, for the same reason:
             * text_view carries our own drag-move Gtk.DropTarget
             * directly, so libadwaita's descendant-selector suppression
             * for other lists doesn't catch it. The drop indicator
             * (OpusSourceView's own hand-drawn one) is this editor's
             * real feedback for a drop target; this outer border is
             * redundant on top of it either way. GtkTextView's own real
             * internal CSS node tree (libadwaita's _views.scss, checked
             * directly: `textview { > text { ... } > border { ... } }`)
             * has the actual content painted on child nodes, not
             * `textview` itself — covering all three since it's unclear
             * which one(s) libadwaita's own generic `:not(window):
             * drop(active)` wildcard rule (_common.scss) actually
             * matches here. */
            textview:drop(active),
            textview > text:drop(active),
            textview > border:drop(active) {
                box-shadow: none;
            }

            /* GtkTextView paints its native selection highlight from a
             * distinct "selection" CSS node, a child of "text" (confirmed
             * directly in gtktextview.c: gtk_css_node_set_name (priv->
             * selection_node, "selection"), parented under text_window->
             * css_node) — it's drawn straight from the real buffer
             * selection (gtk_text_buffer_get_selection_bounds()) any time
             * one exists, with no property or flag to gate it off from
             * application code (unlike the caret's own cursor_visible).
             * Both background-color and color are set transparent here —
             * gtktextlayout.c only overrides glyph color when this node's
             * own color is non-transparent, so leaving color alone would
             * still recolor the primary selection's text even with an
             * invisible background. The real selection_bound/insert
             * range keeps moving and keeps driving copy/cut/drag/IM
             * exactly as before; only its native *painting* is disabled,
             * in favor of the same Gtk.TextTag every cursor's selection
             * now renders through (see EditorView.render_cursors()). */
            textview > text > selection {
                background-color: transparent;
                color: transparent;
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

    /**
     * Writes `text` to the system clipboard — Copy/Cut's own write half.
     * Not GTK's native copy-to-clipboard action: that only ever copies
     * the real (primary-only) native selection, which is exactly what
     * left multi-cursor Cut/Paste silently dropping every cursor but the
     * primary's — CursorController computes the real joined, every-
     * cursor text itself and writes it here instead.
     */
    public void write_clipboard_text (string text) {
        text_view.get_clipboard ().set_text (text);
    }

    /** The clipboard's current text, or null if it has none (or isn't text at all) — Paste's own read half; the caller inserts it through its own apply_edit(), same reasoning as copy_selection_to_clipboard() above. */
    public async string? read_clipboard_text () {
        try {
            return yield text_view.get_clipboard ().read_text_async (null);
        } catch (Error e) {
            return null;
        }
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
     * currently displayed document: every cursor's selection, primary
     * included, is painted through the same shared Gtk.TextTag (native
     * selection painting is suppressed entirely — see install_css()'s
     * own `selection` node rule), and every cursor's *caret*, primary
     * included, is hand-drawn by OpusSourceView (see its own doc comment
     * for why: the native caret is never painted at all, only its marks
     * are still moved). The real native selection_bound/insert range is
     * still moved for the primary cursor — copy/cut/drag/IM all read it
     * directly, and native keybindings (arrows, double/triple-click,
     * Ctrl+A) still drive it — this only changes how that range is
     * painted. Purely a rendering call — it doesn't read or change the
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
        source_buffer.remove_tag_by_name (SELECTION_TAG_NAME, buffer_start, buffer_end);

        var caret_offsets = new int[cursors.length];
        for (int i = 0; i < cursors.length; i++) {
            var cursor = cursors[i];
            caret_offsets[i] = cursor.position_offset;

            if (!cursor.is_empty) {
                Gtk.TextIter selection_start;
                Gtk.TextIter selection_end;
                source_buffer.get_iter_at_offset (out selection_start, cursor.selection_start);
                source_buffer.get_iter_at_offset (out selection_end, cursor.selection_end);
                source_buffer.apply_tag_by_name (SELECTION_TAG_NAME, selection_start, selection_end);
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

    // insert-text/delete-range fire for *every* buffer mutation, this
    // View's own apply_edits() included — updating_programmatically is
    // already true for that whole call (see apply_edits()'s own body),
    // the same guard on_buffer_changed() itself already relies on to
    // tell "our own pipeline" apart from anything else.
    private void on_insert_text (ref Gtk.TextIter pos, string new_text, int new_text_length) {
        if (updating_programmatically || new_text == "") {
            return;
        }

        Logger.warn ("on_insert_text (untracked/native path) fired: %s".printf (new_text));
        int offset = pos.get_offset ();
        untracked_edit (new TextEdit () {
            start_offset = offset, end_offset = offset, old_text = "", new_text = new_text
        });
    }

    private void on_delete_range (Gtk.TextIter start, Gtk.TextIter end) {
        if (updating_programmatically) {
            return;
        }

        Logger.warn ("on_delete_range (untracked/native path) fired");
        untracked_edit (new TextEdit () {
            start_offset = start.get_offset (), end_offset = end.get_offset (),
            old_text = source_buffer.get_text (start, end, false), new_text = ""
        });
    }

    /**
     * Opus's own replacement for GtkTextView's native right-click menu —
     * every item just simulates the equivalent keystroke via
     * handle_key_pressed(), the exact same call simulate_select_all()
     * and simulate_key_press() already use to run a real keystroke's own
     * code path without a real GTK event, so each item is guaranteed to
     * behave identically to actually pressing that key (no separate,
     * driftable copy of Cut/Copy/Paste/Delete/Undo/Redo's own logic).
     * Uses the same ContextMenu/popover-menu.vala builder FileTreeView
     * and TabBarView already share for their own right-click menus.
     *
     * `can_cut_copy_delete`/`can_undo`/`can_redo` come from
     * CursorController — see context_menu_requested's own doc comment
     * for why this View can't work them out by itself. Paste has no
     * such check: it would need an async clipboard read before the menu
     * could even be built, and clicking it with nothing useful to paste
     * already just no-ops (paste_from_clipboard's own empty-text guard).
     */
    public void show_context_menu (double x, double y, bool can_cut_copy_delete, bool can_undo, bool can_redo) {
        ContextMenu.show (text_view, x, y, (popover, box) => {
            box.append (ContextMenu.item (_("Cut"), () => { handle_key_pressed (Gdk.Key.x, Gdk.ModifierType.CONTROL_MASK); }, popover, null, can_cut_copy_delete));
            box.append (ContextMenu.item (_("Copy"), () => { handle_key_pressed (Gdk.Key.c, Gdk.ModifierType.CONTROL_MASK); }, popover, null, can_cut_copy_delete));
            box.append (ContextMenu.item (_("Paste"), () => { handle_key_pressed (Gdk.Key.v, Gdk.ModifierType.CONTROL_MASK); }, popover));
            box.append (ContextMenu.item (_("Delete"), () => { handle_key_pressed (Gdk.Key.Delete, 0); }, popover, null, can_cut_copy_delete));
            box.append (ContextMenu.separator ());
            box.append (ContextMenu.item (_("Undo"), () => { handle_key_pressed (Gdk.Key.z, Gdk.ModifierType.CONTROL_MASK); }, popover, null, can_undo));
            box.append (ContextMenu.item (_("Redo"), () => { handle_key_pressed (Gdk.Key.y, Gdk.ModifierType.CONTROL_MASK); }, popover, null, can_redo));
        });
    }

    /**
     * Whether a press at widget-relative (x, y) landed inside the
     * *real* native selection (source_buffer.get_selection_bounds), not
     * CursorCollection: this View has no reference to the Model, and
     * doesn't need one here — render_cursors() already mirrors the
     * primary cursor's own selection onto these same marks, so they're
     * always in sync with it. This also means only the primary selection
     * is ever draggable — matches Cut/Paste's own precedent (see
     * cursor-controller.vala's Ctrl+X/Ctrl+V comment): a drag has exactly
     * one pointer, with no natural mapping onto several secondary-cursor
     * destinations. Also false for a non-editable buffer (an unreadable
     * file's placeholder text shouldn't be draggable — see
     * set_placeholder()).
     */
    private bool is_inside_selection (double x, double y) {
        if (!text_view.editable) {
            return false;
        }

        Gtk.TextIter sel_start;
        Gtk.TextIter sel_end;
        if (!source_buffer.get_selection_bounds (out sel_start, out sel_end)) {
            return false;
        }
        int offset = offset_at_widget_position (x, y);
        return offset >= sel_start.get_offset () && offset < sel_end.get_offset ();
    }

    /** Actually starts the drag, once click_gesture's own threshold check (see its own comment) says a claimed press has turned into a real drag. */
    private void start_selection_drag (Gdk.Event? event) {
        if (event == null) {
            return;
        }
        var surface = event.get_surface ();
        var device = event.get_device ();
        if (surface == null || device == null) {
            return;
        }

        Gtk.TextIter sel_start;
        Gtk.TextIter sel_end;
        if (!source_buffer.get_selection_bounds (out sel_start, out sel_end)) {
            return;
        }

        var payload = new EditorDragPayload (
            source_buffer.get_text (sel_start, sel_end, false),
            sel_start.get_offset (), sel_end.get_offset ()
        );
        var value = Value (typeof (EditorDragPayload));
        value.set_object (payload);
        var content = new Gdk.ContentProvider.for_value (value);

        // dx/dy are surface-relative (what the event's own get_position()
        // reports), not the widget-relative x/y click_gesture's signals
        // carry.
        double sx;
        double sy;
        event.get_position (out sx, out sy);
        var drag = Gdk.Drag.begin (surface, device, content, Gdk.DragAction.MOVE, sx, sy);

        // Without an explicit icon, Gtk.DragIcon falls back to
        // Gtk.DragIcon.create_widget_for_value()'s own default rendering
        // for whatever GType the content holds — EditorDragPayload isn't
        // a type it knows how to render meaningfully, so this replaces
        // that default (a plain bordered box) with the moved text
        // itself, styled as a plain label — no border, no background.
        if (drag != null) {
            ((Gtk.DragIcon) Gtk.DragIcon.get_for_drag (drag)).child = new Gtk.Label (payload.text);
        }
    }

    private Gdk.DragAction on_drop_motion (double x, double y) {
        text_view.set_drop_indicator (offset_at_widget_position (x, y));
        return Gdk.DragAction.MOVE;
    }

    private void on_drop_leave () {
        text_view.set_drop_indicator (null);
    }

    private bool on_drop (Value value, double x, double y) {
        text_view.set_drop_indicator (null); // drop completing isn't guaranteed to also fire leave()
        var payload = value.get_object () as EditorDragPayload;
        if (payload == null) {
            Logger.warn ("on_drop: dropped content wasn't an EditorDragPayload — should be unreachable, DropTarget is typed to only accept that");
            return false;
        }

        Logger.warn ("on_drop: moving selection [%d, %d) to %d".printf (payload.source_start, payload.source_end, offset_at_widget_position (x, y)));
        selection_dropped (payload.text, payload.source_start, payload.source_end, offset_at_widget_position (x, y));
        return true;
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

        focused_selection_background = accent;
        focused_selection_background.alpha = 0.35f;

        // Mirrors GTK's own ratio between its default (backdrop) and
        // `:focus-within` selection colors: an opaque, fully desaturated
        // color at half the alpha of the focused one ($backdrop_selected_
        // bg_color: transparentize(desaturate($selected_bg_color, 100%), 0.5),
        // against an otherwise-opaque focused color) — see gtk/theme/
        // Default/_colors.scss in GTK's own real source.
        backdrop_selection_background = EditorColors.desaturate (accent);
        backdrop_selection_background.alpha = focused_selection_background.alpha * 0.5f;

        update_selection_background ();

        // Every caret's own color (OpusSourceView.snapshot_layer) reads
        // the widget's resolved foreground color directly at paint time
        // instead of being told it here — see that class's own comment
        // for why (a theme-change callback isn't a reliable place to
        // read freshly-resolved CSS from).
    }

    private void update_selection_background () {
        bool backdrop = (text_view.get_state_flags () & Gtk.StateFlags.BACKDROP) != 0;
        selection_tag.background_rgba = backdrop ? backdrop_selection_background : focused_selection_background;
    }
}
