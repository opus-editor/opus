namespace GitTree {
  /**
   * The working tree as the top row of the graph — "// WIP" with how many
   * paths differ, dashed, hanging off HEAD's own lane. Only exists while
   * something differs: a clean tree has no row.
   */
  public class WorkingRow : Object {
    public int change_count { get; construct; }
    /** HEAD's row's own lane and color, so the dashed dot sits right above its dot. */
    public int head_lane { get; construct; }
    public int head_color { get; construct; }

    public WorkingRow (int change_count, int head_lane, int head_color) {
      Object (change_count: change_count, head_lane: head_lane, head_color: head_color);
    }

    /** Null with nothing changed, or with no HEAD row to hang off (an empty repository). */
    public static WorkingRow? create (GitScope.WorkingTree tree, GenericArray<Row> rows) {
      int count = (int) (tree.unstaged.length + tree.staged.length + tree.conflicts.length);
      if (count == 0) {
        return null;
      }
      for (uint i = 0; i < rows.length; i++) {
        if (rows[i].commit.is_head) {
          return new WorkingRow (count, rows[i].node_lane, rows[i].node_color);
        }
      }
      return null;
    }
  }
}
