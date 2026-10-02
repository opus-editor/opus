/**
 * A single row in the file tree list: an icon, a name label, and (via the
 * {@link Gtk.TreeExpander} wrapping them) the chevron used to expand or
 * collapse a directory. Recycled by the list view's factory.
 *
 * While {@link FileNode.is_editing_name} is set — a New File/Folder still being
 * named (blank), or an existing node being renamed (pre-filled and fully
 * selected) — the label is replaced with an editable {@link Gtk.Text}, focused immediately;
 * {@link edit_committed}/{@link edit_cancelled} report how that ended —
 * this row doesn't know or care which of the two is in progress, that's
 * for whoever set the flag to track. Otherwise purely a display widget —
 * click handling lives in ExplorerPaneTree's `Gtk.ListView.activate` handler,
 * not a gesture of this row's own.
 */
namespace EditorView {
  public class ExplorerPaneTreeRow : Object {
    private Gtk.Box box;
    private Gtk.TreeExpander expander;
    private Gtk.Image icon;
    private Gtk.Label label;
    private Gtk.Text edit_entry;
    private Gtk.Widget decoration_dot;
    private IconTheme icon_theme;

    /** Whether the current bind()'s edit has already fired edit_committed/edit_cancelled — a focus-leave following either must not re-fire it. */
    private bool resolved = false;

    public Gtk.Widget widget { get { return box; } }

    /** The node this row currently displays, or null between bind() calls (row recycling). */
    public FileNode? bound_node { get; private set; }

    /** The list row currently bound — lets ExplorerPaneTree expand/collapse a directory under the pointer (e.g. drag-hover auto-expand) without a separate, position-searching lookup for a row it's already looking straight at. */
    public Gtk.TreeListRow? bound_row { get; private set; }

    /** The inline edit's name was confirmed non-empty (Enter, or focus lost with text present). */
    public signal void edit_committed (string name);

    /** The inline edit was cancelled (Escape, or focus lost with no text). */
    public signal void edit_cancelled ();

    public ExplorerPaneTreeRow (IconTheme icon_theme) {
      this.icon_theme = icon_theme;

      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/editor-view/explorer-pane/_tree-row.ui");
      box = (Gtk.Box) builder.get_object ("row");
      expander = (Gtk.TreeExpander) builder.get_object ("expander");
      icon = (Gtk.Image) builder.get_object ("icon");
      label = (Gtk.Label) builder.get_object ("label");
      edit_entry = (Gtk.Text) builder.get_object ("edit_entry");
      decoration_dot = (Gtk.Widget) builder.get_object ("decoration_dot");

      // Connected once here, not per bind(): edit_entry is the same
      // recycled widget instance across every bind()/unbind() this row
      // goes through, so reconnecting each time would stack duplicate
      // handlers instead of replacing them.
      edit_entry.activate.connect (commit_or_cancel);

      var focus_controller = new Gtk.EventControllerFocus ();
      focus_controller.leave.connect (on_edit_focus_leave);
      edit_entry.add_controller (focus_controller);

      var key_controller = new Gtk.EventControllerKey ();
      key_controller.key_pressed.connect (on_edit_key_pressed);
      edit_entry.add_controller (key_controller);
    }

    /** Binds this row to `list_row`/`node`, recycled from a previous use. */
    public void bind (Gtk.TreeListRow list_row, FileNode node) {
      expander.list_row = list_row;
      bound_row = list_row;
      bound_node = node;
      resolved = false;

      update_decoration (node.decoration);

      // Dims the whole row while this node sits on the tree's internal
      // Cut clipboard, awaiting a Paste — same idea as a dimmed row in
      // Nautilus/VS Code after Cut, just drawn with plain opacity instead
      // of a dedicated CSS class.
      box.opacity = node.is_cut ? 0.5 : 1.0;

      icon.visible = true;
      icon.set_from_resource (node.is_directory ? icon_theme.icon_path_for_folder (node.name) : icon_theme.icon_path_for_file (node.name));

      if (node.is_editing_name) {
        label.visible = false;
        edit_entry.visible = true;
        edit_entry.text = node.name; // "" for a new placeholder, current name for a rename
        start_editing (node);
        return;
      }

      label.visible = true;
      edit_entry.visible = false;
      label.label = node.name;
    }

    /**
     * Grabs focus and selects the whole name (a no-op on a new placeholder's
     * blank text) once this row is actually on screen. Calling
     * `grab_focus()` directly from bind() itself was silently a no-op: GTK
     * doesn't consider a just-inserted row's widget mapped yet at that
     * exact point, and `grab_focus()` on an unmapped widget does nothing —
     * found by testing (typing didn't reach the entry at all until
     * manually clicking it first), not assumed. Deferring one main-loop
     * iteration gives layout a chance to actually place the row before
     * asking for focus.
     */
    private void start_editing (FileNode node) {
      Idle.add (() => {
        if (bound_node != node) {
          return Source.REMOVE; // recycled for something else before this ran
        }

        edit_entry.grab_focus ();
        edit_entry.select_region (0, -1);
        return Source.REMOVE;
      });
    }

    /** Releases the row's data ahead of being recycled for another node. */
    public void unbind () {
      expander.list_row = null;
      bound_row = null;
      bound_node = null;
    }

    /** Toggles the dot's visibility and swaps its tone CSS class — a plain `switch`, so no CSS vocabulary leaks into a Model (FileDecoration.Tone). SUCCESS/WARNING/ALERT/ERROR map to the shared `git-*` classes common.css defines once for every git-status surface (also the tab label tint, also the editor gutter) — ACCENT has no git-status meaning, so it keeps its own `tone-accent` class. No `unbind()` counterpart needed: a fresh bind() always fully re-sets this, same as icon/label. */
    private void update_decoration (FileDecoration.State? decoration) {
      decoration_dot.visible = decoration != null;
      decoration_dot.remove_css_class ("tone-accent");
      decoration_dot.remove_css_class ("git-added");
      decoration_dot.remove_css_class ("git-modified");
      decoration_dot.remove_css_class ("git-conflict");
      decoration_dot.remove_css_class ("git-removed");
      decoration_dot.tooltip_text = decoration?.tooltip ?? "";

      if (decoration == null) {
        return;
      }

      switch (decoration.tone) {
        case FileDecoration.Tone.ACCENT:
          decoration_dot.add_css_class ("tone-accent");
          break;
        case FileDecoration.Tone.SUCCESS:
          decoration_dot.add_css_class ("git-added");
          break;
        case FileDecoration.Tone.WARNING:
          decoration_dot.add_css_class ("git-modified");
          break;
        case FileDecoration.Tone.ALERT:
          decoration_dot.add_css_class ("git-conflict");
          break;
        case FileDecoration.Tone.ERROR:
          decoration_dot.add_css_class ("git-removed");
          break;
        default:
          break;
      }
    }

    private bool on_edit_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
      if (keyval != Gdk.Key.Escape) {
        return false;
      }

      resolve (null);
      return true;
    }

    /** Focus can leave for reasons other than the user finishing the edit (e.g. this very row getting recycled once resolve() below already fired) — resolve() itself is idempotent per bind() via `resolved`, so a redundant call here is harmless. */
    private void on_edit_focus_leave () {
      if (bound_node != null && bound_node.is_editing_name) {
        commit_or_cancel ();
      }
    }

    private void commit_or_cancel () {
      resolve (edit_entry.text.strip ());
    }

    /** `name` null or empty cancels; anything else commits. Fires at most once per bind() — Enter, Escape, and focus-leave can all reach here for the same edit. */
    private void resolve (string? name) {
      if (resolved) {
        return;
      }
      resolved = true;

      if (name == null || name == "") {
        edit_cancelled ();
      } else {
        edit_committed (name);
      }
    }
  }
}
