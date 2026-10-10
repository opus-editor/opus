namespace GitView {
  /** The Commit Message column's cell: the subject, then the body's first line dimmed, as one ellipsized label — or "// WIP" plus a green "+N" for the working-tree row. */
  public class TreePaneMessageCell : Object {
    private Gtk.Box box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
    private Gtk.Label label = new Gtk.Label ("") { use_markup = true, xalign = 0, ellipsize = Pango.EllipsizeMode.END, hexpand = true };
    private Gtk.Label count = new Gtk.Label ("") { visible = false };

    public Gtk.Widget widget { get { return box; } }

    public TreePaneMessageCell () {
      box.margin_start = 8;
      box.margin_end = 8;
      count.add_css_class ("wip-count");
      box.append (label);
      box.append (count);
    }

    public void bind (TreePaneItem item) {
      if (item.working != null) {
        label.label = "<span alpha=\"60%%\">// WIP</span>";
        label.tooltip_text = null;
        count.label = "+%d".printf (item.working.change_count);
        count.visible = true;
        return;
      }
      var commit = item.row.commit;
      if (item.row.stash != null) {
        var stash = item.row.stash;
        label.label = "<span alpha=\"80%%\">%s</span>".printf (Markup.escape_text (stash.message));
        label.tooltip_text = stash.branch != "" ? "%s · on %s".printf (stash.name, stash.branch) : stash.name;
        count.visible = false;
        return;
      }
      var text = Markup.escape_text (commit.subject);
      if (commit.body_first_line != "") {
        text += "  <span alpha=\"50%%\">%s</span>".printf (Markup.escape_text (commit.body_first_line));
      }
      label.label = text;
      label.tooltip_text = "%s · %s".printf (commit.short_hash, commit.author);
      count.visible = false;
    }
  }
}
