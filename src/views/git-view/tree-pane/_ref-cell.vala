namespace GitView {
  /**
   * The Branch / Tag column's cell: one pill per ref, an icon for its
   * kind (local branch, remote, tag) and a check mark on the branch HEAD
   * is on. Only the first shows; the rest fold into a "+N" pill whose tooltip
   * lists them all. Recycled by the column's factory: bind() rebuilds
   * the children each time.
   */
  public class TreePaneRefCell : Object {
    private const int REFS_SHOWN = 1;

    private Gtk.Box box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

    public Gtk.Widget widget { get { return box; } }

    public TreePaneRefCell () {
      box.valign = Gtk.Align.CENTER;
      box.margin_start = 6;
      box.margin_end = 6;
    }

    public void bind (TreePaneItem item) {
      clear ();
      box.tooltip_text = null;
      if (item.row == null) {
        return;
      }
      var refs = item.row.commit.refs;
      uint shown = uint.min (refs.length, REFS_SHOWN);
      for (uint i = 0; i < shown; i++) {
        box.append (pill (refs[i]));
      }
      if (refs.length > shown) {
        box.append (overflow_pill (refs, shown));
      }
    }

    private static Gtk.Widget pill (GitTree.Ref git_ref) {
      var pill = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
      pill.add_css_class ("ref-pill");
      pill.add_css_class (kind_class (git_ref));
      if (git_ref.is_head) {
        pill.add_css_class ("current");
        pill.append (new Gtk.Image.from_icon_name ("object-select-symbolic"));
      }
      pill.append (new Gtk.Label (git_ref.name) { ellipsize = Pango.EllipsizeMode.END, max_width_chars = 18 });
      pill.append (new Gtk.Image.from_icon_name (kind_icon (git_ref)));
      pill.tooltip_text = git_ref.name;
      return pill;
    }

    private static Gtk.Widget overflow_pill (GenericArray<GitTree.Ref> refs, uint from) {
      var pill = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
      pill.add_css_class ("ref-pill");
      pill.add_css_class ("overflow");
      pill.append (new Gtk.Label ("+%u".printf (refs.length - from)));
      var names = new StringBuilder ();
      for (uint i = from; i < refs.length; i++) {
        if (i > from) {
          names.append_c ('\n');
        }
        names.append (refs[i].name);
      }
      pill.tooltip_text = names.str;
      return pill;
    }

    private static string kind_class (GitTree.Ref git_ref) {
      switch (git_ref.kind) {
        case GitTree.RefKind.REMOTE: return "remote";
        case GitTree.RefKind.TAG: return "tag";
        default: return "local";
      }
    }

    private static string kind_icon (GitTree.Ref git_ref) {
      switch (git_ref.kind) {
        case GitTree.RefKind.REMOTE: return "network-server-symbolic";
        case GitTree.RefKind.TAG: return "user-bookmarks-symbolic";
        default: return "computer-symbolic";
      }
    }

    private void clear () {
      Gtk.Widget? child;
      while ((child = box.get_first_child ()) != null) {
        box.remove (child);
      }
    }
  }
}
