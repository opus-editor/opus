/**
 * The undo/redo stack for one document: a sequence of
 * {@link EditHistoryEntry} units, each capturing enough to replay or
 * reverse a whole multi-cursor edit — text and cursor state together —
 * as one atomic step.
 *
 * Consecutive compatible edits (plain typing, or a run of the same kind
 * of delete) merge into the still-open top entry instead of each getting
 * their own undo step, so "type hello, undo once" removes the whole
 * word — see {@link push} for exactly which kinds coalesce.
 */
public class EditHistory : Object {
  private GenericArray<EditHistoryEntry> undo_stack;
  private GenericArray<EditHistoryEntry> redo_stack;
  private bool top_is_open = false;

  public EditHistory () {
    undo_stack = new GenericArray<EditHistoryEntry> ();
    redo_stack = new GenericArray<EditHistoryEntry> ();
  }

  public bool can_undo { get { return undo_stack.length > 0; } }
  public bool can_redo { get { return redo_stack.length > 0; } }

  /**
   * Records one edit batch (one keystroke — possibly touching several
   * simultaneous cursors at once). Coalesces into the currently-open
   * entry when `kind` is compatible with it (see {@link can_coalesce});
   * otherwise closes that entry and starts a new one. Always clears
   * the redo stack — any new edit invalidates whatever was available
   * to redo, coalesced or not.
   *
   * Each keystroke's edits are kept as their own
   * {@link EditHistoryPush} within the entry rather than flattened
   * together with earlier ones in the same entry. They can't safely be
   * flattened: a keystroke's own edits (and their rebased inverse) are
   * only valid relative to the buffer exactly as it stood the moment
   * *that* keystroke landed. A single-cursor typing run happens to stay
   * valid if flattened anyway (each character is only ever inserted
   * after everything before it), which is why this looked safe at
   * first — but a second cursor positioned *before* a first one shifts
   * that first cursor's own already-recorded position the moment the
   * second cursor also types something, and flattening bakes in the
   * *old* (now-wrong) position. Replaying each push separately, in
   * order, sidesteps the whole problem: every push is exactly as valid
   * on replay as it was the instant it actually happened.
   *
   * `before_cursors`/`after_cursors` must already be independent
   * snapshots (e.g. from {@link CursorCollection.snapshot}), not the
   * live, still-mutating cursor collection.
   */
  public void push (TextEdit[] edits, Cursor[] before_cursors, Cursor[] after_cursors, EditKind kind) {
    redo_stack = new GenericArray<EditHistoryEntry> ();

    var new_push = new EditHistoryPush ();
    new_push.edits = edits;
    new_push.inverse_edits = TextEdit.invert_batch (edits);

    if (top_is_open) {
      var open_entry = undo_stack[undo_stack.length - 1];
      if (can_coalesce (open_entry.kind, kind)) {
        open_entry.pushes.add (new_push);
        open_entry.after_cursors = after_cursors;
        open_entry.kind = kind;
        return;
      }
      top_is_open = false;
    }

    var entry = new EditHistoryEntry ();
    entry.pushes = new GenericArray<EditHistoryPush> ();
    entry.pushes.add (new_push);
    entry.before_cursors = before_cursors;
    entry.after_cursors = after_cursors;
    entry.kind = kind;
    undo_stack.add (entry);
    top_is_open = (kind != EditKind.OTHER);
  }

  /** Explicit undo-stop boundary — the next push can never coalesce into whatever's currently open, even if its kind would otherwise allow it. Call on focus loss, Escape, or any non-edit action. */
  public void close_current_entry () {
    top_is_open = false;
  }

  /** Pops the most recent undo entry onto the redo stack and returns it, or null if there's nothing to undo. The caller replays `entry.pushes`' `inverse_edits`, one push at a time, **newest first** (each is only valid against the buffer state left by undoing everything after it), then restores `entry.before_cursors`. */
  public EditHistoryEntry? undo () {
    if (undo_stack.length == 0) {
      return null;
    }

    top_is_open = false;
    var entry = undo_stack[undo_stack.length - 1];
    undo_stack.remove_index (undo_stack.length - 1);
    redo_stack.add (entry);
    return entry;
  }

  /** Pops the most recent redo entry back onto the undo stack and returns it, or null if there's nothing to redo. The caller replays `entry.pushes`' `edits`, one push at a time, **oldest first** (same order they originally happened in), then restores `entry.after_cursors`. */
  public EditHistoryEntry? redo () {
    if (redo_stack.length == 0) {
      return null;
    }

    var entry = redo_stack[redo_stack.length - 1];
    redo_stack.remove_index (redo_stack.length - 1);
    undo_stack.add (entry);
    top_is_open = false;
    return entry;
  }

  private static bool is_typing_kind (EditKind kind) {
    return kind == EditKind.TYPING_OTHER || kind == EditKind.TYPING_FIRST_SPACE || kind == EditKind.TYPING_CONSECUTIVE_SPACE;
  }

  // Buckets TYPING_FIRST_SPACE and TYPING_CONSECUTIVE_SPACE together
  // for the plain equality check in can_coalesce() below — every
  // other kind compares only against itself.
  private static EditKind normalize_kind (EditKind kind) {
    return (kind == EditKind.TYPING_FIRST_SPACE || kind == EditKind.TYPING_CONSECUTIVE_SPACE) ? EditKind.TYPING_FIRST_SPACE : kind;
  }

  /**
   * Whether an edit of `incoming` kind can extend an already-open
   * entry of `open` kind, instead of starting its own undo step.
   * Ported directly from VS Code's own shouldPushStackElementBetween()
   * (src/vs/editor/common/cursor/cursorTypeEditOperations.ts, verified
   * against the real source, not just its visible behavior — an
   * earlier version of this method got it wrong from memory alone).
   *
   * The one non-obvious rule: the boundary lands *before* a space, not
   * after it. Typing "abc " closes "abc" off into its own step the
   * moment the space itself is typed — but typing right after that
   * single space never opens a boundary in turn ("abc |d": no stop),
   * so the space re-attaches itself to whatever comes *next* instead
   * of staying with what came before. That asymmetry is what makes
   * plain prose typing land one undo step per word: every space
   * closes the word behind it, and only a second consecutive space
   * (TYPING_CONSECUTIVE_SPACE) counts as "more of the same" rather
   * than re-triggering that exception.
   */
  private static bool can_coalesce (EditKind open, EditKind incoming) {
    bool open_is_typing = is_typing_kind (open);
    bool incoming_is_typing = is_typing_kind (incoming);

    if (open_is_typing && !incoming_is_typing) {
      return false; // always close before a non-typing operation
    }
    if (open == EditKind.TYPING_FIRST_SPACE) {
      return true; // "abc |d": never close right after a single space
    }
    return normalize_kind (open) == normalize_kind (incoming);
  }
}
