namespace GitTree {
  /** One line drawn through a row: from `top_lane` at the row's top edge to `bottom_lane` at its bottom edge. NODE on either side means it starts or ends at the row's own commit dot. */
  public class Segment : Object {
    public const int NODE = -1;
    public int top_lane { get; construct; }
    public int bottom_lane { get; construct; }
    public int color { get; construct; }

    public Segment (int top_lane, int bottom_lane, int color) {
      Object (top_lane: top_lane, bottom_lane: bottom_lane, color: color);
    }
  }

  /** A lane still open at the bottom of a row: waiting for `hash` to show up further down. */
  public class Lane : Object {
    public string hash { get; construct; }
    public int color { get; construct; }

    public Lane (string hash, int color) {
      Object (hash: hash, color: color);
    }
  }

  /** One commit, laid out: where its dot sits and every line crossing its row. `lane_count` is the widest the row gets, top or bottom. */
  public class Row : Object {
    public Commit commit { get; construct; }
    public int node_lane { get; construct; }
    public int node_color { get; construct; }
    public GenericArray<Segment> segments { get; construct; }
    public int lane_count { get; construct; }
    /** The lanes still open below this row — what the next row (or the next page) starts from. */
    public GenericArray<Lane> open_lanes { get; construct; }
    /** Set when this row is a stash rather than a commit: `commit` then stands in for it (hash, message as subject), and the row is drawn dashed. */
    public Stash? stash { get; construct; default = null; }

    public Row (Commit commit, int node_lane, int node_color, GenericArray<Segment> segments, int lane_count, GenericArray<Lane> open_lanes, Stash? stash = null) {
      Object (commit: commit, node_lane: node_lane, node_color: node_color, segments: segments, lane_count: lane_count, open_lanes: open_lanes, stash: stash);
    }
  }

  /**
   * Lays `git log --topo-order` commits out into lanes, one pass, newest
   * first — the same swimlane model VS Code's own SCM graph uses
   * (toISCMHistoryItemViewModelArray/renderSCMHistoryItemGraph in
   * scmHistory.ts). Each row starts from the lanes the row above left
   * open, each waiting for a commit hash. The commit's dot goes in the
   * first lane waiting for it (a new lane at the right if none is), its
   * line from above ending at the dot; that lane goes on waiting for the
   * first parent; every other lane waiting for this same commit ends
   * here too, curving into the dot; every further
   * parent opens one more lane at the right, drawn from the dot. A lane
   * is never deduplicated on open: two lanes may wait for one parent, and
   * they merge in that parent's row — that is what a fork looks like
   * read bottom-up.
   */
  public class Graph : Object {
    /** How many colors there are to cycle through — the view's own lane palette has this many entries. */
    public const int COLOR_COUNT = 8;

    private Graph () {}

    /** `next_color` carries the palette position across pages (0 to start); `open_lanes` is the last row's own of the page before, null for the first page. Each of `stashes` is laid out right above its base commit, when that commit is in `commits`; `working_tree_dirty` says a WIP row will sit above HEAD, which counts as HEAD's lane continuing upward (see add_stash_rows). */
    public static GenericArray<Row> layout (GenericArray<Commit> commits, ref int next_color, GenericArray<Lane>? open_lanes = null, GenericArray<Stash>? stashes = null, bool working_tree_dirty = false) {
      var rows = new GenericArray<Row> ();
      var input = open_lanes ?? new GenericArray<Lane> ();

      for (uint i = 0; i < commits.length; i++) {
        var commit = commits[i];
        bool stash_dropped_in = stashes != null && add_stash_rows (rows, stashes, commit, input, next_color, working_tree_dirty);
        var segments = new GenericArray<Segment> ();
        var output = new GenericArray<Lane> ();
        int node_lane = -1;
        int node_color = -1;

        // Lanes coming in from above: the first one waiting for this
        // commit is where the dot goes, the others end at the dot.
        for (uint j = 0; j < input.length; j++) {
          var lane = input[j];
          if (lane.hash == commit.hash) {
            // The line from the row above always reaches the dot; the
            // first such lane carries on below it, the others end here.
            segments.add (new Segment ((int) j, Segment.NODE, lane.color));
            if (node_lane == -1) {
              node_lane = (int) j;
              node_color = lane.color;
              if (commit.parents.length > 0) {
                output.add (new Lane (commit.parents[0], lane.color));
                segments.add (new Segment (Segment.NODE, (int) output.length - 1, lane.color));
              }
            }
            continue;
          }
          output.add (lane);
          segments.add (new Segment ((int) j, (int) output.length - 1, lane.color));
        }

        // Nothing was waiting for it: a tip, or a root of its own.
        int first_parent = 0;
        if (node_lane == -1) {
          node_lane = (int) input.length;
          node_color = next_color;
          next_color = (next_color + 1) % COLOR_COUNT;
          if (stash_dropped_in) {
            segments.add (new Segment (node_lane, Segment.NODE, node_color)); // the stash's line above lands on the dot
          }
          if (commit.parents.length > 0) {
            output.add (new Lane (commit.parents[0], node_color));
            segments.add (new Segment (Segment.NODE, (int) output.length - 1, node_color));
            first_parent = 1;
          }
        } else {
          first_parent = 1;
        }

        // Every further parent: a merge, one new lane each.
        for (int p = first_parent; p < commit.parents.length; p++) {
          var color = next_color;
          next_color = (next_color + 1) % COLOR_COUNT;
          output.add (new Lane (commit.parents[p], color));
          segments.add (new Segment (Segment.NODE, (int) output.length - 1, color));
        }

        int lane_count = int.max ((int) input.length, (int) output.length);
        lane_count = int.max (lane_count, node_lane + 1);
        rows.add (new Row (commit, node_lane, node_color, segments, lane_count, output));
        input = output;
      }
      return rows;
    }

    /**
     * A stash row sits just above its base. Where nothing continues
     * above the base — a tip, with no lane waiting for it and no WIP row
     * about to hang off it — the stash takes the column the base is
     * about to open, straight above it, one line dropping from the stash
     * to the dot. Otherwise (mid-branch, or HEAD with a dirty working
     * tree) the stash moves to the first free column at the right and
     * curves down into the base's column: on the line itself it would
     * read as what's above having come out of the stash (GitKraken draws
     * every case this way). Every open lane passes straight through; a
     * stash opens nothing. True when a line was dropped into a column the
     * base will open itself — the base row then has to draw that line's
     * last stretch down to its dot.
     */
    private static bool add_stash_rows (GenericArray<Row> rows, GenericArray<Stash> stashes, Commit base_commit, GenericArray<Lane> input, int next_color, bool working_tree_dirty) {
      bool dropped_into_new_column = false;
      for (uint s = 0; s < stashes.length; s++) {
        var stash = stashes[s];
        if (stash.base_hash != base_commit.hash) {
          continue;
        }
        int base_lane = (int) input.length;
        int base_color = next_color;
        for (uint j = 0; j < input.length; j++) {
          if (input[j].hash == base_commit.hash) {
            base_lane = (int) j;
            base_color = input[j].color;
            break;
          }
        }
        bool base_is_tip = base_lane == input.length;
        bool straight_above = base_is_tip && !(base_commit.is_head && working_tree_dirty);
        int node_lane = straight_above ? base_lane : base_lane + 1 > (int) input.length ? base_lane + 1 : (int) input.length;
        var segments = new GenericArray<Segment> ();
        for (uint j = 0; j < input.length; j++) {
          segments.add (new Segment ((int) j, (int) j, input[j].color));
        }
        segments.add (new Segment (Segment.NODE, base_lane, base_color));
        dropped_into_new_column |= base_is_tip;

        var stand_in = new Commit (stash.hash, { stash.base_hash }, "", "", stash.timestamp, stash.message, "", new GenericArray<Ref> (), false);
        rows.add (new Row (stand_in, node_lane, base_color, segments, node_lane + 1, input, stash));
      }
      return dropped_into_new_column;
    }
  }
}
