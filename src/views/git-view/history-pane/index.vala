/**
 * The Git activity's sidebar while a commit (or stash) is selected in
 * the tree: the same shape as StagingPane — header, one list —
 * read-only. "Commit: <short hash>" and the author with the date up
 * top, the subject as a heading (with a "Read more" link while there is
 * a body), and the files the commit changed (GitTree.CommitFiles) as a
 * ChangeList. The close
 * button, and selecting the WIP row, go back to StagingPane
 * (back_requested, handled by MainWindow). Selecting a file row shows
 * that file's diff in the commit (open_diff_requested), the same single
 * click the staging lists use.
 */
namespace GitView {
  public class HistoryPane : Object, ISidebarPane {
    private Gtk.Box root_box;
    private Gtk.Label commit_label;
    private Gtk.Label author_label;
    private Gtk.Label subject_label;
    private Gtk.Label read_more_label;
    private ChangeList files = new ChangeList ();
    private string? root_path = null;
    // Same guard as TreePane.generation: the files of a commit selected earlier must not land over a later one.
    private int generation = 0;

    /** The close button: the user wants the working tree back. */
    public signal void back_requested ();

    /** A file selected (a single click is enough, as in the staging lists) or double-clicked: its diff in this commit — MainWindow shows it in the Git view. */
    public signal void open_diff_requested (GitDiff.Request request);

    private GitTree.Commit? shown_commit = null;
    private UserSettings user_settings;

    public HistoryPane (UserSettings user_settings) {
      this.user_settings = user_settings;
      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/git-view/history-pane/index.ui");
      root_box = (Gtk.Box) builder.get_object ("root_box");
      commit_label = (Gtk.Label) builder.get_object ("commit_label");
      author_label = (Gtk.Label) builder.get_object ("author_label");
      subject_label = (Gtk.Label) builder.get_object ("subject_label");
      read_more_label = (Gtk.Label) builder.get_object ("read_more_label");
      read_more_label.activate_link.connect (show_message);
      ((Gtk.Button) builder.get_object ("close_button")).clicked.connect (() => back_requested ());
      ((Gtk.ScrolledWindow) builder.get_object ("files_scrolled")).child = files.widget;
      files.item_activated.connect (request_diff);
      files.selection_changed.connect (() => {
        var selected = files.selected_changes ();
        if (selected.length == 1) {
          request_diff (selected[0]);
        }
      });
      files.set_sort_key (user_settings.changes_sort);
      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/staging-pane.css");
    }

    public Gtk.Widget widget { get { return root_box; } }

    /** Shows `row`'s commit or stash — header, message, and its files once git answers. */
    public void show_row (string root_path, GitTree.Row row) {
      this.root_path = root_path;
      var commit = row.commit;
      shown_commit = commit;
      if (row.stash != null) {
        commit_label.label = _("Stash: %s").printf (row.stash.name);
        commit_label.tooltip_text = commit.hash;
        author_label.label = row.stash.branch != "" ? _("on %s · %s").printf (row.stash.branch, commit.date_label) : commit.date_label;
      } else {
        commit_label.label = _("Commit: %s").printf (commit.short_hash);
        commit_label.tooltip_text = commit.hash;
        author_label.label = "%s · %s".printf (commit.author, commit.date_label);
      }
      subject_label.label = commit.subject;
      read_more_label.visible = commit.body != "";
      load_files.begin (root_path, commit);
    }

    public void close () {
      generation++;
    }

    /** "Read more": the whole message, subject and body, in the same read-only sheet the error toasts' "View Log" opens. Handled here, so GTK never tries to open the link's href as a URI. */
    private bool show_message () {
      if (shown_commit != null) {
        LogDialog.show (root_box, user_settings, commit_label.label, shown_commit.message);
      }
      return true;
    }

    /** One file picked (a click, or a double-click): its diff in this commit, under the breadcrumb. */
    private void request_diff (GitScope.Change change) {
      if (shown_commit == null || root_path == null) {
        return;
      }
      var parent = shown_commit.parents.length > 0 ? shown_commit.parents[0] : null;
      open_diff_requested (GitDiff.Request.for_commit_change (root_path, change, shown_commit.hash, parent));
    }

    /** A double-click on `path`'s file row — the debug D-Bus surface. */
    public void activate_file (string path) throws Error {
      var changes = files.all_changes ();
      for (uint i = 0; i < changes.length; i++) {
        if (changes[i].path == Path.build_filename (root_path, path)) {
          files.item_activated (changes[i]);
          return;
        }
      }
      throw new IOError.NOT_FOUND ("No “%s” file in the commit".printf (path));
    }

    /** The header's first line — the debug D-Bus surface reads it. */
    public string header_text {
      owned get { return commit_label.label; }
    }

    /** Each file as "<code> <relative path>", in list order. */
    public string[] list_files () {
      string[] rows = {};
      var changes = files.all_changes ();
      for (uint i = 0; i < changes.length; i++) {
        rows += "%s %s".printf (changes[i].kind.code (), changes[i].path.substring (root_path.length + 1));
      }
      return rows;
    }

    private async void load_files (string root_path, GitTree.Commit commit) {
      int my_generation = ++generation;
      files.set_changes (new GenericArray<GitScope.Change> (), root_path);
      var changes = yield GitTree.CommitFiles.run_async (root_path, commit);
      if (my_generation != generation) {
        return;
      }
      files.set_changes (changes ?? new GenericArray<GitScope.Change> (), root_path);
    }
  }
}
