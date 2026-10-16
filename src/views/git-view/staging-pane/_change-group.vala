/**
 * One of ChangeTree's sections — "staged"/"conflicts"/"unstaged", the
 * words its own row shows, and the changes under it. The root rows of
 * the tree's Gtk.TreeListModel; a GitScope.Change is a child row.
 */
namespace GitView {
  public class ChangeGroup : Object {
    public string section { get; private set; }
    public string title { get; private set; }
    public ChangeStore changes { get; private set; default = new ChangeStore (); }

    public ChangeGroup (string section, string title) {
      this.section = section;
      this.title = title;
    }
  }
}
