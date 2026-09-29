/**
 * What a per-workspace plugin extension is allowed to know about the
 * linked workspace — deliberately narrow, the analog of `vscode.workspace`,
 * not a general escape hatch back into the app.
 *
 * Re-broadcasts the filesystem signals ExplorerPaneDirWatcher already owns
 * rather than handing plugins their own Gio.FileMonitor — kernel watches
 * are a limited resource (see that class's own doc comment), and a plugin
 * needing a watch the explorer doesn't have (e.g. the git plugin's own
 * `.git/` monitor) uses plain Gio.FileMonitor itself — GLib, not host API.
 */
public class WorkspaceContext : Object {
  public string root_path { get; construct; }

  /** An expanded directory's immediate children changed on disk (create/delete/rename/move) — re-broadcast from the explorer's own watches. */
  public signal void directory_changed (string path);

  /** A file directly inside a watched directory had its contents written. */
  public signal void file_content_changed (string path);

  public WorkspaceContext (string root_path) {
    Object (root_path: root_path);
  }
}
