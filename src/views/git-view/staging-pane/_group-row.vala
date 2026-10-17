/**
 * A ChangeGroup's row in ChangeTree — see _group-row.blp. The count
 * follows the group's own store while bound, so a refresh that adds or
 * drops a change updates it without rebinding the row. Recycled by the
 * list view's factory, same as ChangeRow.
 */
namespace GitView {
  public class ChangeGroupRow : Object {
    private Gtk.Box box;
    private Gtk.TreeExpander expander;
    private Gtk.Label title_label;
    private Gtk.Label count_label;
    private Gtk.Box actions;
    private Gtk.Button stage_all_button;
    private Gtk.Button discard_all_button;
    private Gtk.Button unstage_all_button;
    private ChangeGroup? group = null;
    private ulong items_handler = 0;

    public Gtk.Widget widget { get { return box; } }

    /** One of the whole-group actions was clicked — "stage-all", "unstage-all" or "discard-all" — for `section`. */
    public signal void action_requested (string action, string section);

    public ChangeGroupRow () {
      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/git-view/staging-pane/_group-row.ui");
      box = (Gtk.Box) builder.get_object ("row");
      expander = (Gtk.TreeExpander) builder.get_object ("expander");
      title_label = (Gtk.Label) builder.get_object ("title");
      count_label = (Gtk.Label) builder.get_object ("count");
      actions = (Gtk.Box) builder.get_object ("actions");
      stage_all_button = (Gtk.Button) builder.get_object ("stage_all_button");
      discard_all_button = (Gtk.Button) builder.get_object ("discard_all_button");
      stage_all_button.clicked.connect (() => action_requested ("stage-all", group.section));
      discard_all_button.clicked.connect (() => action_requested ("discard-all", group.section));
      unstage_all_button = (Gtk.Button) builder.get_object ("unstage_all_button");
      unstage_all_button.clicked.connect (() => action_requested ("unstage-all", group.section));
    }

    public void bind (Gtk.TreeListRow list_row, ChangeGroup group) {
      unbind ();
      expander.list_row = list_row;
      this.group = group;
      title_label.label = group.title;
      stage_all_button.visible = group.section == "unstaged";
      discard_all_button.visible = group.section == "unstaged";
      unstage_all_button.visible = group.section == "staged";
      items_handler = group.changes.store.items_changed.connect (update_count);
      update_count ();
    }

    public void unbind () {
      if (group != null) {
        group.changes.store.disconnect (items_handler);
        group = null;
      }
      expander.list_row = null;
    }

    /** The count, and the whole-group actions: nothing to act on in an empty group, so none show. */
    private void update_count () {
      var n_items = group.changes.store.get_n_items ();
      count_label.label = n_items.to_string ();
      actions.visible = n_items > 0;
    }
  }
}
