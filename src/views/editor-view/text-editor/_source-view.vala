/**
 * The real GTK-backed text widget {@link EditorView.TextEditor} wraps: a
 * `GtkSource.View` subclass that hand-draws every cursor's caret itself —
 * primary included — instead of splitting the work between GTK's native
 * caret and custom-drawn secondary ones.
 *
 * That split existed early on and looked inconsistent: the native caret
 * blinks on GTK's own internal timer with GTK's own color, while a
 * hand-drawn secondary caret had to be reimplemented from scratch — two
 * independent systems that couldn't be kept pixel- and timing-identical.
 * `EditorView.TextEditor` now sets `cursor_visible = false` on this view, which
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
 * Every cursor's *selection*, primary included, is painted the same way
 * too: through a plain `Gtk.TextTag` applied by `EditorView.TextEditor.
 * render_cursors()`. The real, native `selection_bound`↔`insert` range
 * still moves normally for the primary cursor (copy/cut/drag/IM and
 * every native selection keybinding all still depend on it) — only its
 * *painting* is suppressed, via a CSS rule on GtkTextView's own
 * `selection` node (see `EditorView.TextEditor.install_css()`), the same kind of
 * paint-only suppression `cursor_visible = false` already does for the
 * caret above.
 */
namespace EditorView {
    public class TextEditorSourceView : GtkSource.View {
        // Matches VS Code's own default (ViewCursors.BLINK_INTERVAL in
        // src/vs/editor/browser/viewParts/viewCursors/viewCursors.ts) — a
        // plain on/off toggle, not the smooth/phase/expand fade styles VS
        // Code also offers as alternatives to its "blink" default.
        private const uint BLINK_INTERVAL_MS = 500;

        // How far past the visible range indent guides look for
        // interpolation context (see draw_indent_guides()) — a blank run
        // of lines taller than this just loses its guide past the edge,
        // same as IndentGuides already treats the real top/bottom of a file.
        private const int INDENT_GUIDE_CONTEXT_LINES = 300;
        private const float INDENT_GUIDE_ALPHA = 0.075f;
        private const float ACTIVE_INDENT_GUIDE_ALPHA = 0.15f;

        // How many characters to measure at once for the per-character
        // guide width (see draw_indent_guides()) — long enough that
        // Pango's own integer-pixel rounding of the sample's total width
        // is a negligible fraction of one column, unlike measuring a
        // single character.
        // VS Code measures the same way for the same reason (its own
        // charWidthReader.ts repeats a character 256 times, reads the
        // rendered width, and divides by 256).
        private const int CHAR_WIDTH_SAMPLE_LENGTH = 256;

        private int[] caret_offsets = {};
        private bool blink_visible = true;
        private uint blink_timeout_id = 0;
        private int? drop_indicator_offset = null;
        private int indent_size = 4; // matches EditorController.DEFAULT_INDENT_SIZE, overwritten by set_indent_size() once a document's actually loaded

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
        public TextEditorSourceView () {
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

        /** Columns per indent level, for indent guides — resolved by EditorController from the linked folder's .editorconfig, per file. */
        public void set_indent_size (int size) {
            indent_size = size;
            queue_draw ();
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

            if (layer == Gtk.TextViewLayer.BELOW_TEXT) {
                draw_indent_guides (snapshot);
                return;
            }

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
         * Where EditorView.TextEditor's own reimplemented drag-and-drop (see its own
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
         * Vertical indent-guide lines, painted behind the text (BELOW_TEXT
         * layer) so glyphs draw over them, same as VS Code. Only ever
         * analyzes a bounded window of buffer text around what's actually
         * visible — INDENT_GUIDE_CONTEXT_LINES of slack each side, not the
         * whole buffer — since this runs on every repaint (scroll, cursor
         * blink, edits) and re-parsing an entire large file that often
         * would be wasteful.
         *
         * Column-to-pixel math is done by hand (line-start x from
         * get_iter_location(), plus `level * indent_size` character
         * widths) rather than looking up a real Gtk.TextIter at that
         * column: a blank line has no character there for
         * get_iter_at_line_offset() to find — it would just clamp back to
         * column 0 — but a guide still needs to draw through it at its
         * interpolated depth.
         */
        private void draw_indent_guides (Gtk.Snapshot snapshot) {
            Gdk.Rectangle visible_rect;
            get_visible_rect (out visible_rect);

            Gtk.TextIter top_iter;
            int top_y;
            get_line_at_y (out top_iter, visible_rect.y, out top_y);
            Gtk.TextIter bottom_iter;
            int bottom_y;
            get_line_at_y (out bottom_iter, visible_rect.y + visible_rect.height, out bottom_y);

            int line_count = buffer.get_line_count ();
            int visible_first_line = top_iter.get_line ().clamp (0, line_count - 1);
            int visible_last_line = bottom_iter.get_line ().clamp (0, line_count - 1);
            int window_start_line = int.max (0, visible_first_line - INDENT_GUIDE_CONTEXT_LINES);
            int window_end_line = int.min (line_count - 1, visible_last_line + INDENT_GUIDE_CONTEXT_LINES);

            Gtk.TextIter window_start_iter;
            buffer.get_iter_at_line (out window_start_iter, window_start_line);
            Gtk.TextIter window_end_iter;
            buffer.get_iter_at_line (out window_end_iter, window_end_line);
            window_end_iter.forward_to_line_end ();

            var guides = new IndentGuides (buffer.get_text (window_start_iter, window_end_iter, true), indent_size);

            int active_start_line = -1;
            int active_end_line = -1;
            int active_level = 0;
            if (caret_offsets.length > 0) {
                Gtk.TextIter cursor_iter;
                buffer.get_iter_at_offset (out cursor_iter, caret_offsets[0]);

                int local_start;
                int local_end;
                int level;
                guides.active_guide (cursor_iter.get_line () - window_start_line, out local_start, out local_end, out level);
                if (level > 0) {
                    active_start_line = local_start + window_start_line;
                    active_end_line = local_end + window_start_line;
                    active_level = level;
                }
            }

            // The view is monospace, so one glyph's width stands in for
            // every character's — the same metric VS Code itself calls
            // spaceWidth for this exact purpose. Measured over a long
            // sample and averaged, not from a single character: confirmed
            // directly (temporary Logger.warn instrumentation, since
            // reverted) that a single-space Pango layout reports a width
            // measurably wider than this font's real per-character
            // advance (9px vs. an actual ~7.56px, measured here over 34
            // characters) — a fixed per-glyph error that `(level - 1) *
            // indent_size * char_width` then multiplies by `level`, so
            // guides drifted further off with every deeper level instead
            // of by a constant amount.
            var layout = create_pango_layout (string.nfill (CHAR_WIDTH_SAMPLE_LENGTH, '0'));
            int sample_width;
            int sample_height;
            layout.get_pixel_size (out sample_width, out sample_height);
            float char_width = sample_width / (float) CHAR_WIDTH_SAMPLE_LENGTH;

            var guide_color = get_color ();
            guide_color.alpha = INDENT_GUIDE_ALPHA;
            var active_color = get_color ();
            active_color.alpha = ACTIVE_INDENT_GUIDE_ALPHA;

            var levels = guides.levels_for_lines (visible_first_line - window_start_line, visible_last_line - window_start_line);

            for (int line = visible_first_line; line <= visible_last_line; line++) {
                int level_count = levels[line - visible_first_line];
                if (level_count == 0) {
                    continue;
                }

                Gtk.TextIter line_start_iter;
                buffer.get_iter_at_line (out line_start_iter, line);
                Gdk.Rectangle line_rect;
                get_iter_location (line_start_iter, out line_rect);

                for (int level = 1; level <= level_count; level++) {
                    float x = line_rect.x + (level - 1) * indent_size * char_width;
                    bool is_active = level == active_level && line >= active_start_line && line <= active_end_line;

                    var rect = Graphene.Rect ();
                    rect.init (x, line_rect.y, 1, line_rect.height);
                    snapshot.append_color (is_active ? active_color : guide_color, rect);
                }
            }
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
}
