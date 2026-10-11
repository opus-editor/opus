namespace GitView {
  /**
   * The Graph column's cell: the row's lines and dot, drawn with Gsk
   * paths straight from GitTree.Row's segments — a straight line when a
   * segment stays in its lane, an S-curve between lanes, each in its
   * lane's color (TreePanePalette). Lines run edge to edge vertically,
   * so consecutive rows join seamlessly. The working-tree row draws in
   * HEAD's lane color, its node a square with the theme's
   * view-more icon; a commit row crossed by its line down to
   * HEAD draws that stretch too (TreePaneItem.working_lane). A stash row (GitTree.Row.stash)
   * gets a square with an inbox glyph in place of the dot; its lines are
   * solid like any other. Recycled by the column's factory.
   */
  public class TreePaneGraphCell : Gtk.Widget {
    public const int LANE_WIDTH = 20;
    /** Breathing room at both sides: a lane-wide box on the first lane would otherwise lose half its stroke past the cell's left edge. */
    public const int SIDE_PADDING = 4;
    private const float LINE_WIDTH = 2.0f;
    private const float DOT_RADIUS = 4.0f;
    private const float STASH_SIZE = 20.0f;
    private const int ICON_SIZE = 12;
    private const float OVERDRAW = 1.0f;

    /** How a line crosses from one lane to another — kept switchable while the two are being compared by eye. */
    private enum CurveStyle {
      /** One cubic S from edge to edge, vertical at both ends. */
      S_CURVE,
      /** Straight runs with a rounded right angle at each turn: horizontal out of (or into) the dot, vertical along the lane. */
      ELBOW,
    }
    private const CurveStyle CURVE_STYLE = CurveStyle.ELBOW;
    private const float ELBOW_RADIUS = 8.0f;

    private TreePanePalette palette;
    private TreePaneItem? item = null;

    public TreePaneGraphCell (TreePanePalette palette) {
      this.palette = palette;
      hexpand = false;
      valign = Gtk.Align.FILL;
    }

    public void bind (TreePaneItem item) {
      this.item = item;
      if (item.row != null && item.row.stash != null) {
        tooltip_text = "%s · %s".printf (_("Stash"), item.row.stash.name);
      } else if (item.working != null) {
        tooltip_text = _("Working tree");
      } else {
        tooltip_text = null;
      }
      queue_draw ();
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
      minimum_baseline = -1;
      natural_baseline = -1;
      if (orientation == Gtk.Orientation.HORIZONTAL) {
        int lanes = item != null ? item.lane_count : 1;
        minimum = natural = lanes * LANE_WIDTH + 2 * SIDE_PADDING;
      } else {
        minimum = natural = 0;
      }
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
      if (item == null) {
        return;
      }
      float height = (float) get_height ();
      float middle = height / 2;
      if (item.working != null) {
        draw_working (snapshot, item.working, height, middle);
        return;
      }
      var row = item.row;
      for (uint i = 0; i < row.segments.length; i++) {
        var segment = row.segments[i];
        draw_segment (snapshot, segment.top_lane, segment.bottom_lane, row.node_lane, height, middle, palette.color (segment.color));
      }
      if (item.working_lane >= 0) {
        draw_segment (snapshot, item.working_lane, item.working_lane, -1, height, middle, working_color ());
      }
      if (item.working_into_node) {
        draw_segment (snapshot, row.node_lane, GitTree.Segment.NODE, row.node_lane, height, middle, working_color ());
      }
      if (row.stash != null) {
        draw_stash (snapshot, row.node_lane, middle, palette.color (row.node_color));
      } else {
        draw_dot (snapshot, row.node_lane, middle, palette.color (row.node_color));
      }
    }

    /** A square, the lane's width, with an inbox tray and a down arrow inside, in the lane color — the glyph is drawn here, not an icon, so it scales and tints with the lane like everything else in the cell. Filled with the view background first, so the lane line doesn't run through the glyph. */
    private void draw_stash (Gtk.Snapshot snapshot, int lane, float middle, Gdk.RGBA lane_color) {
      var color = lane_color;
      float cx = x_of (lane);
      draw_box (snapshot, lane, middle, color);

      // 12px glyph: arrow from the top into a tray at the bottom.
      var glyph = new Gsk.PathBuilder ();
      glyph.move_to (cx, middle - 5.5f);
      glyph.line_to (cx, middle + 1.5f);
      glyph.move_to (cx - 3.2f, middle - 1.5f);
      glyph.line_to (cx, middle + 1.5f);
      glyph.line_to (cx + 3.2f, middle - 1.5f);
      glyph.move_to (cx - 5.5f, middle + 1.5f);
      glyph.line_to (cx - 5.5f, middle + 5.5f);
      glyph.line_to (cx + 5.5f, middle + 5.5f);
      glyph.line_to (cx + 5.5f, middle + 1.5f);
      glyph.move_to (cx - 5.5f, middle + 1.5f);
      glyph.line_to (cx - 3.0f, middle + 1.5f);
      glyph.move_to (cx + 3.0f, middle + 1.5f);
      glyph.line_to (cx + 5.5f, middle + 1.5f);
      var glyph_stroke = new Gsk.Stroke (1.4f);
      glyph_stroke.set_line_cap (Gsk.LineCap.ROUND);
      glyph_stroke.set_line_join (Gsk.LineJoin.ROUND);
      snapshot.append_stroke (glyph.to_path (), glyph_stroke, color);
    }

    private void draw_working (Gtk.Snapshot snapshot, GitTree.WorkingRow working, float height, float middle) {
      var color = working_color ();
      draw_segment (snapshot, GitTree.Segment.NODE, working.head_lane, working.head_lane, height, middle, color);
      draw_box (snapshot, working.head_lane, middle, color);
      draw_icon (snapshot, "view-more-symbolic", x_of (working.head_lane), middle, color);
    }

    /** A square the lane's width, filled with the view background (so no lane line runs through what goes inside) and framed in `color`. */
    private void draw_box (Gtk.Snapshot snapshot, int lane, float middle, Gdk.RGBA color) {
      float cx = x_of (lane);
      float half = STASH_SIZE / 2;
      var rect = Graphene.Rect () { origin = { cx - half, middle - half }, size = { STASH_SIZE, STASH_SIZE } };
      var frame = new Gsk.PathBuilder ();
      frame.add_rounded_rect (Gsk.RoundedRect ().init_from_rect (rect, 3.0f));
      var frame_path = frame.to_path (); // to_path() empties the builder: one path, used twice
      snapshot.append_fill (frame_path, Gsk.FillRule.WINDING, palette.background ());
      snapshot.append_stroke (frame_path, new Gsk.Stroke (1.2f), color);
    }

    /** A symbolic icon from the icon theme, centered on (cx, cy), painted in `color` — the way Gtk.Image would paint it, minus the widget. */
    private void draw_icon (Gtk.Snapshot snapshot, string icon_name, float cx, float cy, Gdk.RGBA color) {
      var theme = Gtk.IconTheme.get_for_display (get_display ());
      var icon = theme.lookup_icon (icon_name, null, ICON_SIZE, scale_factor, get_direction (), 0);
      snapshot.save ();
      snapshot.translate (Graphene.Point () { x = cx - ICON_SIZE / 2.0f, y = cy - ICON_SIZE / 2.0f });
      icon.snapshot_symbolic (snapshot, ICON_SIZE, ICON_SIZE, { color });
      snapshot.restore ();
    }

    /** The WIP line and square are HEAD's own lane color. */
    private Gdk.RGBA working_color () {
      return palette.color (item.row != null ? item.row.node_color : item.working.head_color);
    }

    private static float x_of (int lane) {
      return SIDE_PADDING + LANE_WIDTH / 2.0f + lane * LANE_WIDTH;
    }

    private void draw_segment (Gtk.Snapshot snapshot, int top_lane, int bottom_lane, int node_lane, float height, float middle, Gdk.RGBA color) {
      bool from_node = top_lane == GitTree.Segment.NODE;
      bool to_node = bottom_lane == GitTree.Segment.NODE;
      float x_start = x_of (from_node ? node_lane : top_lane);
      // Past the edges by a hair: two rows' lines meet without a seam
      // from subpixel rounding (overflow is visible on a plain widget).
      float y_start = from_node ? middle : -OVERDRAW;
      float x_end = x_of (to_node ? node_lane : bottom_lane);
      float y_end = to_node ? middle : height + OVERDRAW;

      var builder = new Gsk.PathBuilder ();
      builder.move_to (x_start, y_start);
      if (x_start == x_end) {
        builder.line_to (x_end, y_end);
      } else if (CURVE_STYLE == CurveStyle.S_CURVE) {
        // An S-curve: vertical tangents at both ends, so it meets the
        // straight lines above and below without a kink.
        float y_mid = (y_start + y_end) / 2;
        builder.cubic_to (x_start, y_mid, x_end, y_mid, x_end, y_end);
      } else {
        elbow (builder, x_start, y_start, x_end, y_end, from_node, to_node, middle);
      }
      snapshot.append_stroke (builder.to_path (), new Gsk.Stroke (LINE_WIDTH), color);
    }

    /**
     * The horizontal leg sits at the row's middle, level with the dot:
     * out of the dot sideways then down (from_node), down then sideways
     * into the dot (to_node), or down-sideways-down for a lane that
     * shifts without touching the dot. Each corner is a quarter arc of
     * ELBOW_RADIUS, shrunk if the legs are too short for it.
     */
    private static void elbow (Gsk.PathBuilder builder, float x_start, float y_start, float x_end, float y_end, bool from_node, bool to_node, float middle) {
      float dx = x_end > x_start ? 1 : -1;
      float r = float.min (ELBOW_RADIUS, (x_end - x_start).abs () / 2);
      if (from_node) {
        // sideways from the dot, then a corner turning down the lane
        float ry = float.min (r, (y_end - middle).abs ());
        builder.line_to (x_end - dx * r, middle);
        builder.arc_to (x_end, middle, x_end, middle + ry);
        builder.line_to (x_end, y_end);
        return;
      }
      if (to_node) {
        // down the lane, then a corner turning sideways into the dot
        float ry = float.min (r, (middle - y_start).abs ());
        builder.line_to (x_start, middle - ry);
        builder.arc_to (x_start, middle, x_start + dx * r, middle);
        builder.line_to (x_end, middle);
        return;
      }
      float ry = float.min (r, (middle - y_start).abs ());
      builder.line_to (x_start, middle - ry);
      builder.arc_to (x_start, middle, x_start + dx * r, middle);
      builder.line_to (x_end - dx * r, middle);
      builder.arc_to (x_end, middle, x_end, middle + ry);
      builder.line_to (x_end, y_end);
    }

    private void draw_dot (Gtk.Snapshot snapshot, int lane, float middle, Gdk.RGBA color) {
      var builder = new Gsk.PathBuilder ();
      builder.add_circle (Graphene.Point () { x = x_of (lane), y = middle }, DOT_RADIUS);
      snapshot.append_fill (builder.to_path (), Gsk.FillRule.WINDING, color);
    }
  }
}
