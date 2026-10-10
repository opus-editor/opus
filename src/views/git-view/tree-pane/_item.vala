namespace GitView {
  /**
   * One row of the tree list: a laid-out commit (GitTree.Row), or the
   * working tree (GitTree.WorkingRow) sitting above HEAD. `working_lane`
   * is the lane the WIP row's line passes through on its way down to
   * HEAD's own row, -1 when it doesn't cross this row.
   */
  public class TreePaneItem : Object {
    public GitTree.Row? row { get; set; }
    public GitTree.WorkingRow? working { get; set; }
    public int working_lane { get; set; default = -1; }
    /** HEAD's own row while a WIP row exists: the line from above ends at this dot. */
    public bool working_into_node { get; set; default = false; }

    /** The data above was swapped under a bound cell — Gtk.ColumnView keeps a cell bound to an item object it sees again at the same position, so a refresh that reuses this item has to say so itself; every cell rebinds on this. */
    public signal void changed ();

    public TreePaneItem.commit (GitTree.Row row) {
      Object (row: row, working: null);
    }

    public TreePaneItem.working_tree (GitTree.WorkingRow working) {
      Object (row: null, working: working);
    }

    public int lane_count {
      get { return row != null ? row.lane_count : working.head_lane + 1; }
    }

    /** What a refresh matches an old item to a new one by: the commit's (or stash's) hash, or the one working-tree row. */
    public string key {
      owned get { return row != null ? row.commit.hash : "working-tree"; }
    }
  }
}
