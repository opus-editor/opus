/** Cursor/selection DSL — set_cursors/set_selections/assert_cursors. Composed into SystemTestSession the same way CodeEditorCursors composes into CodeEditor. Takes `editor_text` too (not just the shared proxy): resolving a {line, column} pair against the buffer's current text needs active_text(), already implemented on SystemTestEditorText — reused directly rather than duplicated here. */
public class SystemTestCursors : Object {
    private DBusProxy proxy;
    private SystemTestEditorText editor_text;

    public SystemTestCursors (DBusProxy proxy, SystemTestEditorText editor_text) {
        this.proxy = proxy;
        this.editor_text = editor_text;
    }

    /** `pairs[i] = { line, column }` (both 0-based) — one collapsed cursor per pair, resolved against the buffer's current text. */
    public void set_cursors (int[,] pairs) throws Error {
        var lines = editor_text.active_text ().split ("\n");

        var anchors = new VariantBuilder (new VariantType ("ai"));
        var positions = new VariantBuilder (new VariantType ("ai"));
        for (int i = 0; i < pairs.length[0]; i++) {
            int offset = offset_for_line_column (lines, pairs[i, 0], pairs[i, 1]);
            anchors.add ("i", offset);
            positions.add ("i", offset);
        }

        call ("SetActiveCursors", new Variant ("(@ai@ai)", anchors.end (), positions.end ()));
    }

    /** `triples[i] = { line, start_column, end_column }` (0-based) — one cursor per triple, selecting `[start_column, end_column)` on that line, anchored at the start (position/caret lands at the end, matching a left-to-right drag-select). Resolved against the buffer's current text. */
    public void set_selections (int[,] triples) throws Error {
        var lines = editor_text.active_text ().split ("\n");

        var anchors = new VariantBuilder (new VariantType ("ai"));
        var positions = new VariantBuilder (new VariantType ("ai"));
        for (int i = 0; i < triples.length[0]; i++) {
            anchors.add ("i", offset_for_line_column (lines, triples[i, 0], triples[i, 1]));
            positions.add ("i", offset_for_line_column (lines, triples[i, 0], triples[i, 2]));
        }

        call ("SetActiveCursors", new Variant ("(@ai@ai)", anchors.end (), positions.end ()));
    }

    /** The current cursor set as raw buffer offsets — anchors[i]/positions[i] pair up into one cursor each (equal when collapsed). */
    public void active_cursors (out int[] anchors, out int[] positions) throws Error {
        var result = call ("GetActiveCursors");
        anchors = variant_to_int_array (result.get_child_value (0));
        positions = variant_to_int_array (result.get_child_value (1));
    }

    /** Asserts the current cursor set matches exactly: expected[i] = { anchor_offset, position_offset } (equal when collapsed) — raw buffer offsets, since a selection's anchor and position can't both be expressed as one line/column pair the way set_cursors()'s collapsed cursors can. */
    public void assert_cursors (int[,] expected) throws Error {
        int[] anchors;
        int[] positions;
        active_cursors (out anchors, out positions);

        assert_cmpint (anchors.length, CompareOperator.EQ, expected.length[0]);
        for (int i = 0; i < expected.length[0]; i++) {
            assert_cmpint (anchors[i], CompareOperator.EQ, expected[i, 0]);
            assert_cmpint (positions[i], CompareOperator.EQ, expected[i, 1]);
        }
    }

    private static int[] variant_to_int_array (Variant array_variant) {
        var result = new int[array_variant.n_children ()];
        for (size_t i = 0; i < array_variant.n_children (); i++) {
            result[i] = array_variant.get_child_value (i).get_int32 ();
        }
        return result;
    }

    private static int offset_for_line_column (string[] lines, int line, int column) {
        int offset = 0;
        for (int i = 0; i < line; i++) {
            offset += lines[i].char_count () + 1; // +1 for the newline split() consumed
        }
        return offset + column;
    }

    private Variant call (string method_name, Variant? parameters = null) throws Error {
        return proxy.call_sync (method_name, parameters, DBusCallFlags.NONE, -1);
    }
}
