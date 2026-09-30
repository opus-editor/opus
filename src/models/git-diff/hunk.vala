namespace GitDiff {
  public enum HunkKind { ADDED, CHANGED, REMOVED }

  /**
   * One contiguous line-range difference against a base — current-buffer
   * coordinates only. A REMOVED hunk (current_count == 0) has no real
   * current-buffer range to span: current_start is the boundary line
   * where the removed lines used to be. The renderer draws a small
   * triangle notch there instead of a full-height bar (see
   * CodeEditorChangeGutter.draw_removed_marker()).
   */
  public class Hunk : Object {
    public int current_start { get; construct; }
    public int current_count { get; construct; }
    public HunkKind kind { get; construct; }
    /** True if this hunk's range also differs from the index (still has unstaged work on top); false if it's fully captured by what's staged. */
    public bool solid { get; construct; }

    public Hunk (int current_start, int current_count, HunkKind kind, bool solid) {
      Object (current_start: current_start, current_count: current_count, kind: kind, solid: solid);
    }
  }
}
