/**
 * The real GTK-backed text widget {@link EditorView} wraps: a
 * `GtkSource.View` subclass that hand-draws every cursor's caret itself —
 * primary included — instead of splitting the work between GTK's native
 * caret and custom-drawn secondary ones.
 *
 * That split existed early on and looked inconsistent: the native caret
 * blinks on GTK's own internal timer with GTK's own color, while a
 * hand-drawn secondary caret had to be reimplemented from scratch — two
 * independent systems that couldn't be kept pixel- and timing-identical.
 * `EditorView` now sets `cursor_visible = false` on this view, which
 * suppresses only the native caret's *painting* — the real `insert`/
 * `selection_bound` marks it wraps still move normally, so IM
 * composition, bracket-matching, accessibility, and scroll-to-cursor all
 * keep working unaffected. Every caret users actually see, including the
 * primary one, is painted here through the same code path, with the
 * same color and the same blink timer, so they're guaranteed identical —
 * matching VS Code's own default multi-cursor appearance (`editorMultiCursor.
 * primary.foreground`/`.secondary.foreground` both default to the same
 * `editorCursor.foreground`) rather than trying to approximate it from
 * two different rendering systems.
 *
 * Secondary *selections* are still left to GTK, painted with a plain
 * `Gtk.TextTag` by `EditorView.render_cursors()` (and the primary's own
 * selection still renders through the real, native `selection_bound`↔
 * `insert` range, `cursor_visible` doesn't affect that) — only the caret
 * itself has no native equivalent for more than one cursor.
 */
public class OpusSourceView : GtkSource.View {
    // Matches VS Code's own default (ViewCursors.BLINK_INTERVAL in
    // src/vs/editor/browser/viewParts/viewCursors/viewCursors.ts) — a
    // plain on/off toggle, not the smooth/phase/expand fade styles VS
    // Code also offers as alternatives to its "blink" default.
    private const uint BLINK_INTERVAL_MS = 500;

    private int[] caret_offsets = {};
    private bool blink_visible = true;
    private uint blink_timeout_id = 0;
    private int? drop_indicator_offset = null;

    /**
     * A caret means "typing lands here" — showing one while this view
     * doesn't actually hold keyboard focus would be misleading (e.g.
     * opening a file with a single click in the sidebar: EditorController.
     * open() deliberately leaves focus in the file tree so arrow keys
     * keep navigating it, but the active document's cursor still exists
     * and gets rendered into caret_offsets same as ever). Gate painting
     * on has_focus rather than have CursorController suppress the
     * render itself — it never imports Gtk, so it has no notion of focus
     * at all, and the cursor state it computes is correct regardless.
     */
    public OpusSourceView () {
        notify["has-focus"].connect (() => {
            if (has_focus) {
                reset_blink (); // solid immediately, not mid-blink from whenever focus happened to return
            } else {
                queue_draw ();
            }
        });
    }

    /** The codepoint offsets to paint a caret at on the next draw — one per cursor, primary included. Call whenever the cursor set changes, then `reset_blink()`. */
    public void set_carets (int[] offsets) {
        caret_offsets = offsets;
    }

    /**
     * Restarts the blink cycle so every caret is solid right after a
     * cursor-affecting change, then resumes blinking on the interval
     * above — the hand-drawn equivalent of `Gtk.TextView.
     * reset_cursor_blink()`, which stops being meaningful once the
     * native caret is never painted at all. Respects the desktop's own
     * "reduce motion"/no-blink accessibility preference
     * (`Gtk.Settings.gtk-cursor-blink`) by simply not starting the timer
     * when it's off — carets stay solid instead.
     */
    public void reset_blink () {
        blink_visible = true;
        stop_blinking ();

        if (Gtk.Settings.get_default ().gtk_cursor_blink) {
            blink_timeout_id = Timeout.add (BLINK_INTERVAL_MS, on_blink_tick);
        }

        queue_draw ();
    }

    private bool on_blink_tick () {
        blink_visible = !blink_visible;
        queue_draw ();
        return true;
    }

    private void stop_blinking () {
        if (blink_timeout_id != 0) {
            Source.remove (blink_timeout_id);
            blink_timeout_id = 0;
        }
    }

    public override void snapshot_layer (Gtk.TextViewLayer layer, Gtk.Snapshot snapshot) {
        base.snapshot_layer (layer, snapshot);

        if (layer != Gtk.TextViewLayer.ABOVE_TEXT) {
            return;
        }

        draw_drop_indicator (snapshot);

        if (!blink_visible || !has_focus) {
            return;
        }

        // Read the theme's resolved foreground color fresh on every
        // paint rather than caching it from a theme-change callback —
        // CSS re-cascading on a light/dark switch isn't guaranteed to
        // have already settled by the time such a callback runs, but it
        // always has by the time an actual draw happens.
        var color = get_color ();

        foreach (var offset in caret_offsets) {
            Gtk.TextIter iter;
            buffer.get_iter_at_offset (out iter, offset);

            Gdk.Rectangle strong;
            Gdk.Rectangle weak;
            get_cursor_locations (iter, out strong, out weak);

            var rect = Graphene.Rect ();
            rect.init (strong.x, strong.y, 2, strong.height);
            snapshot.append_color (color, rect);
        }
    }

    /**
     * Where EditorView's own reimplemented drag-and-drop (see its own
     * DragSource/DropTarget setup) currently wants the drop indicator
     * shown, or null to hide it — driven entirely by real motion/leave/
     * drop events on our own DropTarget. GTK's native drag-and-drop
     * indicator can't be used at all: it gates its own visibility on
     * `cursor_visible(text_view)`, a private function returning
     * `use_caret || priv->cursor_visible` — unconditionally false in
     * Opus's configuration (`cursor_visible = false`, to suppress the
     * native caret entirely — see this class's own doc comment), so it
     * could never be made to appear without reintroducing a duplicate
     * native caret or mutating a desktop-wide accessibility setting
     * shared by every GTK app on the system. Both rejected — this is why
     * Opus reimplements the whole drag-and-drop interaction itself
     * rather than only its rendering.
     */
    public void set_drop_indicator (int? offset) {
        drop_indicator_offset = offset;
        queue_draw ();
    }

    /**
     * Painted the same way as a real caret (same shape) but never
     * blinking and in the theme's accent color, so it reads as "this is
     * where it lands," not as one more actual cursor.
     */
    private void draw_drop_indicator (Gtk.Snapshot snapshot) {
        if (drop_indicator_offset == null) {
            return;
        }

        Gtk.TextIter iter;
        buffer.get_iter_at_offset (out iter, drop_indicator_offset);

        Gdk.Rectangle strong;
        Gdk.Rectangle weak;
        get_cursor_locations (iter, out strong, out weak);

        var rect = Graphene.Rect ();
        rect.init (strong.x, strong.y, 2, strong.height);
        // Null only if the platform doesn't support accent colors at
        // all (get_system_supports_accent_colors()) — the normal caret
        // color is a reasonable fallback rather than skipping the
        // indicator entirely. Deliberately the *method* form, not the
        // `accent_color_rgba` *property* — the property form is broken
        // against this system's installed libadwaita 1.7.6 headers (a
        // real vapi/header mismatch: "too many arguments to function
        // `adw_style_manager_get_accent_color_rgba`" at the C level).
        var accent = Adw.StyleManager.get_default ().get_accent_color_rgba ();
        snapshot.append_color (accent ?? get_color (), rect);
    }
}
