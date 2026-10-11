namespace GitView {
  /** The Commit Message column's cell: the subject, then a dimmed notes icon (Material's `notes`, bundled) whose tooltip is the whole message and the author; or "// WIP" plus a green "+N" for the working-tree row. */
  public class TreePaneMessageCell : Object {
    private Gtk.Box box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
    private Gtk.Label label = new Gtk.Label ("") { use_markup = true, xalign = 0, ellipsize = Pango.EllipsizeMode.END };
    private Gtk.Image body_icon = new Gtk.Image.from_icon_name ("notes-symbolic") { visible = false, opacity = 0.5 };
    private Gtk.Label count = new Gtk.Label ("") { visible = false };

    public Gtk.Widget widget { get { return box; } }

    public TreePaneMessageCell () {
      box.margin_start = 8;
      box.margin_end = 8;
      count.add_css_class ("wip-count");
      box.append (label);
      box.append (body_icon);
      box.append (count);
    }

    public void bind (TreePaneItem item) {
      body_icon.visible = false;
      label.hexpand = true;
      if (item.working != null) {
        label.label = "<span alpha=\"60%%\">// WIP</span>";
        label.hexpand = false; // the count sits right after the text, not at the far end
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
      label.label = Markup.escape_text (commit.subject);
      label.tooltip_text = null;
      label.hexpand = false;
      var body = commit.body != "" ? "\n\n" + Markup.escape_text (commit.body) : "";
      body_icon.tooltip_markup = "<b>%s</b>%s\n\n<span alpha=\"60%%\">%s</span>".printf (Markup.escape_text (commit.subject), body, Markup.escape_text (commit.author));
      body_icon.visible = true;
      count.visible = false;
    }
  }
}
