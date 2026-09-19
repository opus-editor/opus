/** Which kind of edit produced an {@link EditHistoryEntry} — decides whether the next edit coalesces into it or starts a fresh undo step. See {@link EditHistory.push}. */
public enum EditKind {
    TYPING_OTHER,
    TYPING_FIRST_SPACE,
    TYPING_CONSECUTIVE_SPACE,
    DELETING_LEFT,
    DELETING_RIGHT,
    OTHER
}

/**
 * One coalesced keystroke's worth of edits within an
 * {@link EditHistoryEntry}: `edits` (forward, replayed for redo) and
 * `inverse_edits` (already rebased — see {@link TextEdit.invert_batch} —
 * replayed for undo). Kept as its own unit rather than flattened
 * together with its sibling pushes, because both are only self-consistent
 * relative to the buffer state at the exact moment *this* push landed —
 * see {@link EditHistory.push}'s own comment for why that matters once a
 * single push can touch more than one simultaneous cursor.
 */
public class EditHistoryPush : Object {
    public TextEdit[] edits;
    public TextEdit[] inverse_edits;
}

/**
 * One undo step: the coalesced keystrokes it applied (`pushes`, oldest
 * first), and the full multi-cursor selection state immediately before
 * and after it — snapshots, not live cursors (see
 * {@link CursorCollection.snapshot}), so a later edit can't
 * retroactively change what an old entry restores.
 */
public class EditHistoryEntry : Object {
    public GenericArray<EditHistoryPush> pushes;
    public Cursor[] before_cursors;
    public Cursor[] after_cursors;
    public EditKind kind { get; set; }
}
