/**
 * The sidebar's own content — reacts to the *same* "Editor"/"Git"
 * activity main-window/index.blp's own `view_stack` already drives for
 * the main content area, rather than owning a second, independent
 * switcher of its own: MainWindow listens for `view_stack`'s own
 * `visible-child-name` to change and calls show() here with whichever
 * name it changed to, so both halves of the window always agree on
 * which activity is active.
 *
 * Built entirely in code (a plain Adw.Bin, nothing to template).
 */
public class Sidebar : Object {
  private Adw.Bin bin = new Adw.Bin ();
  private ISidebarPane? editor_pane = null;
  private ISidebarPane? git_pane = null;
  private string active_name = "editor";

  public Gtk.Widget widget { get { return bin; } }

  /** `editor_pane` (null once unlinked) — MainWindow calls this in lockstep with link_folder()/unlink_folder(), same as it did for sidebar_bin directly before this existed. */
  public void set_editor_pane (ISidebarPane? editor_pane) {
    this.editor_pane = editor_pane;
    update ();
  }

  /** `git_pane` — set once, at construction, unlike editor_pane: GitView.StagingPane itself doesn't need tearing down between folders (see its own doc comment). */
  public void set_git_pane (ISidebarPane? git_pane) {
    this.git_pane = git_pane;
    update ();
  }

  /** `name` is one of view_stack's own page names ("editor", "git") — MainWindow calls this once at construction (the stack's initial page) and again on every `notify::visible-child-name`. */
  public void show (string name) {
    active_name = name;
    update ();
  }

  private void update () {
    bin.child = active_name == "editor" ? editor_pane?.widget : git_pane?.widget;
  }
}
