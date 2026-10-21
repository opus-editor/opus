/**
 * One file's diff, inline, in the Git view's main area: a
 * GitDiff.Request's two sides read in a thread, diffed by git
 * (GitDiff.FileDiff), shown in a read-only CodeEditor in diff mode
 * (CodeEditor.show_diff()) — or, when a side has no text to show
 * (binary, too large, not UTF-8, a symlink or submodule, missing), an
 * Adw.StatusPage saying which. A request with only one side (a new or
 * a deleted file) shows that side as plain text, no markers — all-added
 * or all-removed says nothing a reader doesn't know. reload() re-reads
 * the same request; a
 * live one (a side in the working tree or index) is reloaded by
 * GitView.Content whenever the repository moves under it.
 */
namespace GitView {
  public class DiffPane : Object {
    private Gtk.Stack stack = new Gtk.Stack ();
    private Adw.StatusPage placeholder = new Adw.StatusPage ();
    private CodeEditor code_editor;
    private GitDiff.Request? request = null;
    private FileSettings.Registry? file_settings = null;
    /** "diff", "plain" or "placeholder" — what the stack shows, for the debug D-Bus surface. */
    public string mode { get; private set; default = "diff"; }
    // A load still in flight when a newer one starts lands on nothing.
    private int generation = 0;

    /** Re-emitted from the editor — the FindBar's "N of M" while this diff is what it searches. */
    public signal void search_position_changed (int position, int count);

    /** `search_settings` is the window's one Find query, shared with the editor pane's tabs. */
    public DiffPane (UserSettings user_settings, GtkSource.SearchSettings search_settings) {
      code_editor = new CodeEditor (user_settings, search_settings);
      code_editor.search_position_changed.connect ((position, count) => search_position_changed (position, count));
      stack.add_named (code_editor.widget, "diff");
      stack.add_named (placeholder, "placeholder");
    }

    public Gtk.Widget widget { get { return stack; } }

    /** What is showing, null before the first show(). */
    public GitDiff.Request? shown_request { get { return request; } }

    /** The editor the FindBar acts on — null while a placeholder shows. Searchable, never replaceable: a diff is read-only. */
    public CodeEditor? search_editor { get { return mode == "placeholder" ? null : code_editor; } }

    /** The folder's per-file settings — the diff's indent guides follow the file's own indentation, the same as its tab would. */
    public void set_file_settings (FileSettings.Registry? registry) {
      file_settings = registry;
    }

    public void show (GitDiff.Request request) {
      this.request = request;
      reload ();
    }

    public void reload () {
      if (request != null) {
        load.begin ();
      }
    }

    public void close () {
      generation++;
      code_editor.close ();
    }

    private async void load () {
      int my_generation = ++generation;
      var current = request;
      GitDiff.BlobResult? left_blob = null;
      GitDiff.BlobResult? right_blob = null;
      GitDiff.FileDiff? diff = null;
      string? failure = null;
      try {
        yield GitScope.Command.in_thread (() => {
          left_blob = GitDiff.Blob.read (current.root_path, current.left);
          right_blob = GitDiff.Blob.read (current.root_path, current.right);
          if (left_blob.status == GitDiff.BlobStatus.OK && right_blob.status == GitDiff.BlobStatus.OK) {
            diff = GitDiff.FileDiff.compute (left_blob.text, right_blob.text);
          }
        });
      } catch (GitScope.CommandError e) {
        failure = e.message;
      }
      if (my_generation != generation) {
        return;
      }
      if (failure != null) {
        show_placeholder (_("Couldn’t compute the diff"), failure);
        return;
      }
      var blocked = left_blob.status != GitDiff.BlobStatus.OK ? left_blob : right_blob;
      if (blocked.status != GitDiff.BlobStatus.OK) {
        show_placeholder (reason_title (blocked.status), reason_body (blocked.status));
        return;
      }
      apply_indent (current.path);
      if (current.left.kind == GitDiff.SideKind.EMPTY || current.right.kind == GitDiff.SideKind.EMPTY) {
        code_editor.show_plain_text (current.left.kind == GitDiff.SideKind.EMPTY ? right_blob.text : left_blob.text, current.path);
        mode = "plain";
      } else {
        code_editor.show_diff (diff, current.path);
        mode = "diff";
      }
      stack.visible_child_name = "diff";
    }

    private void apply_indent (string path) {
      var settings = file_settings?.settings_for (path) ?? new FileSettings.Values ();
      int indent_size = settings.indent_size ?? FileSettings.Values.DEFAULT_INDENT_SIZE;
      code_editor.set_indent (indent_size, settings.insert_spaces ?? FileSettings.Values.DEFAULT_INSERT_SPACES, settings.tab_width ?? indent_size);
    }

    private void show_placeholder (string title, string body) {
      placeholder.title = title;
      placeholder.description = body;
      stack.visible_child_name = "placeholder";
      mode = "placeholder";
    }

    private static string reason_title (GitDiff.BlobStatus status) {
      switch (status) {
        case GitDiff.BlobStatus.BINARY: return _("Binary file");
        case GitDiff.BlobStatus.TOO_LARGE: return _("File too large");
        case GitDiff.BlobStatus.NOT_UTF8: return _("Not UTF-8 text");
        case GitDiff.BlobStatus.UNSUPPORTED: return _("Nothing to compare");
        default: return _("File not found");
      }
    }

    private static string reason_body (GitDiff.BlobStatus status) {
      switch (status) {
        case GitDiff.BlobStatus.BINARY: return _("A binary file has no text to diff.");
        case GitDiff.BlobStatus.TOO_LARGE: return _("Files over %d MB aren’t diffed.").printf ((int) (GitDiff.Blob.MAX_BYTES / (1024 * 1024)));
        case GitDiff.BlobStatus.NOT_UTF8: return _("Only UTF-8 text can be shown here.");
        case GitDiff.BlobStatus.UNSUPPORTED: return _("Symlinks and submodules aren’t diffed.");
        default: return _("One side of this diff couldn’t be read.");
      }
    }

    /** The lines as shown, "<old>|<new>|<marker>|<text>" — the debug D-Bus surface; a plain file lists "n|n| |text", a placeholder nothing. */
    public string[] describe_lines () {
      if (mode == "placeholder") {
        return {};
      }
      if (mode == "plain") {
        string[] out = {};
        var lines = code_editor.get_text ().split ("\n");
        int count = code_editor.get_text ().has_suffix ("\n") ? lines.length - 1 : lines.length;
        for (int i = 0; i < count; i++) {
          out += "%d|%d| |%s".printf (i + 1, i + 1, lines[i]);
        }
        return out;
      }
      return code_editor.describe_diff_lines ();
    }

    /** The placeholder's title, "" while the diff itself shows. */
    public string placeholder_title {
      owned get { return stack.visible_child_name == "placeholder" ? placeholder.title : ""; }
    }
  }
}
