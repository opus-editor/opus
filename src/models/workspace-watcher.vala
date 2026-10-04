/**
 * Every filesystem watch a linked workspace holds. In a git repository
 * that is every directory git doesn't ignore, from the moment the folder
 * is linked — a change is reported whether or not the explorer ever
 * showed the directory it happened in. An ignored directory (a
 * `node_modules/`, a build dir) costs one kernel watch per subdirectory
 * for changes nobody acts on, so it is only watched while something
 * asks for it by name (request()); outside a repository there is no
 * ignore list to tell the two apart, and every directory is on request.
 */
public class WorkspaceWatcher : Object {
  // Long enough for a burst (a checkout, an unpacked archive) to end up
  // as one rescan.
  private const uint RESCAN_DEBOUNCE_MS = 400;
  // A burst (a build, a checkout) is reported as one batch per window
  // rather than once per event — every report makes a consumer re-read a
  // directory. Opened by the first event and never extended, so a steady
  // stream still gets through.
  private const uint EVENT_LATENCY_MS = 100;
  private const string GIT_DIRECTORY = ".git";
  private const string IGNORE_FILE = ".gitignore";

  private string root_path;
  private HashTable<string, FileMonitor> monitors = new HashTable<string, FileMonitor> (str_hash, str_equal);
  private GenericSet<string> unignored = new GenericSet<string> (str_hash, str_equal);
  private GenericSet<string> requested = new GenericSet<string> (str_hash, str_equal);

  private GenericSet<string> changed_directories = new GenericSet<string> (str_hash, str_equal);
  private GenericSet<string> changed_contents = new GenericSet<string> (str_hash, str_equal);
  private uint pending_flush_id = 0;

  private uint pending_rescan_id = 0;
  private bool rescan_running = false;
  private bool rescan_pending_again = false;
  private bool scanned_once = false;
  private bool closed = false;

  /** `path`'s own immediate children changed (create/delete/rename/move). Also fired for a directory that only just became watched: whatever happened inside it before that went unseen. */
  public signal void directory_changed (string path);

  /** The file at `path`, directly inside a watched directory, had its contents written. */
  public signal void content_changed (string path);

  /** The set of unignored directories was just recomputed from disk, and the watches now match it. */
  public signal void rescanned ();

  public WorkspaceWatcher (string root_path) {
    this.root_path = root_path;
    request (root_path);
    run_rescan.begin ();
  }

  /** Watches `path` no matter what git says about it, until release(). */
  public void request (string path) {
    requested.add (path);
    ensure_monitor (path);
  }

  /** Undoes request(). An unignored directory stays watched regardless. */
  public void release (string path) {
    requested.remove (path);
    if (!unignored.contains (path)) {
      drop_monitor (path);
    }
  }

  /** Cancels every watch, pending report and pending rescan — call before discarding this object: an active Gio.FileMonitor keeps firing into its handler's closure, which holds this object alive. */
  public void close () {
    closed = true;
    if (pending_flush_id != 0) {
      Source.remove (pending_flush_id);
      pending_flush_id = 0;
    }
    if (pending_rescan_id != 0) {
      Source.remove (pending_rescan_id);
      pending_rescan_id = 0;
    }
    foreach (var monitor in monitors.get_values ()) {
      monitor.cancel ();
    }
    monitors.remove_all ();
  }

  private void ensure_monitor (string path) {
    if (monitors.contains (path)) {
      return;
    }
    try {
      var monitor = File.new_for_path (path).monitor_directory (FileMonitorFlags.WATCH_MOVES, null);
      monitor.changed.connect ((file, other_file, event_type) => on_event (path, file, other_file, event_type));
      monitors[path] = monitor;
    } catch (Error e) {
      warning ("failed to watch %s: %s", path, e.message);
    }
  }

  private void drop_monitor (string path) {
    var monitor = monitors[path];
    if (monitor == null) {
      return;
    }
    monitor.cancel ();
    monitors.remove (path);
  }

  private void on_event (string directory, File file, File? other_file, FileMonitorEvent event_type) {
    switch (event_type) {
      case FileMonitorEvent.CREATED:
      case FileMonitorEvent.DELETED:
      case FileMonitorEvent.RENAMED:
      case FileMonitorEvent.MOVED_IN:
      case FileMonitorEvent.MOVED_OUT:
        if (changes_unignored_set (file) || (other_file != null && changes_unignored_set (other_file))) {
          schedule_rescan ();
        }
        changed_directories.add (directory);
        schedule_flush ();
        break;
      case FileMonitorEvent.CHANGED:
        if (file.get_basename () == IGNORE_FILE) {
          schedule_rescan ();
        }
        changed_contents.add (file.get_path ());
        schedule_flush ();
        break;
      default:
        break;
    }
  }

  private void schedule_flush () {
    if (pending_flush_id != 0) {
      return;
    }
    pending_flush_id = Timeout.add (EVENT_LATENCY_MS, () => {
      pending_flush_id = 0;
      flush ();
      return Source.REMOVE;
    });
  }

  private void flush () {
    // Taken before emitting: a handler can cause changes of its own.
    var directories = changed_directories;
    var contents = changed_contents;
    changed_directories = new GenericSet<string> (str_hash, str_equal);
    changed_contents = new GenericSet<string> (str_hash, str_equal);

    foreach (var path in directories.get_values ()) {
      directory_changed (path);
    }
    foreach (var path in contents.get_values ()) {
      content_changed (path);
    }
  }

  /** Whether an entry appearing or disappearing at `file` can add or remove an unignored directory: a directory itself (a known one that is gone now, or one on disk now), or the ignore rules. */
  private bool changes_unignored_set (File file) {
    var path = file.get_path ();
    return file.get_basename () == IGNORE_FILE || unignored.contains (path) || is_real_directory (path);
  }

  private void schedule_rescan () {
    if (pending_rescan_id != 0) {
      Source.remove (pending_rescan_id);
    }
    pending_rescan_id = Timeout.add (RESCAN_DEBOUNCE_MS, () => {
      pending_rescan_id = 0;
      run_rescan.begin ();
      return Source.REMOVE;
    });
  }

  /** Guards against overlapping runs: a trigger arriving mid-rescan schedules exactly one more afterward, never dropped. */
  private async void run_rescan () {
    if (rescan_running) {
      rescan_pending_again = true;
      return;
    }
    rescan_running = true;
    var found = yield list_unignored_directories_async (root_path);
    rescan_running = false;

    if (closed) {
      return;
    }

    apply_unignored (found);
    scanned_once = true;
    rescanned ();

    if (rescan_pending_again) {
      rescan_pending_again = false;
      schedule_rescan ();
    }
  }

  private void apply_unignored (GenericSet<string> found) {
    foreach (var path in unignored.get_values ()) {
      if (!found.contains (path) && !requested.contains (path)) {
        drop_monitor (path);
      }
    }

    var newly_watched = new GenericArray<string> ();
    foreach (var path in found.get_values ()) {
      if (!monitors.contains (path)) {
        ensure_monitor (path);
        newly_watched.add (path);
      }
    }
    unignored = found;

    if (!scanned_once) {
      return; // the first scan reads the workspace as it is being opened — nothing was missed yet
    }
    foreach (var path in newly_watched) {
      directory_changed (path);
    }
  }

  /** Thread + Idle.add, same shape as FindInFilesSearch.run_async. */
  private static async GenericSet<string> list_unignored_directories_async (string root_path) {
    SourceFunc callback = list_unignored_directories_async.callback;
    GenericSet<string>? result = null;

    new Thread<void> ("workspace-watcher", () => {
      result = list_unignored_directories (root_path);
      Idle.add ((owned) callback);
    });

    yield;
    return result;
  }

  /** Empty whenever there is no ignore list to go by: `root_path` isn't a repository root, or git couldn't answer. */
  private static GenericSet<string> list_unignored_directories (string root_path) {
    var directories = new GenericSet<string> (str_hash, str_equal);
    if (!GitFileList.is_repository_root (root_path)) {
      return directories;
    }
    var ignored = list_ignored_directories (root_path);
    if (ignored == null) {
      return directories;
    }
    collect_directories (root_path, ignored, directories);
    return directories;
  }

  private static void collect_directories (string path, GenericSet<string> ignored, GenericSet<string> into) {
    into.add (path);

    Dir dir;
    try {
      dir = Dir.open (path);
    } catch (Error e) {
      return;
    }
    string? name;
    while ((name = dir.read_name ()) != null) {
      if (name == GIT_DIRECTORY) {
        continue;
      }
      var child = Path.build_filename (path, name);
      if (ignored.contains (child) || !is_real_directory (child)) {
        continue;
      }
      // A nested repository has ignore rules of its own that the outer
      // one never reports.
      if (GitFileList.is_repository_root (child)) {
        continue;
      }
      collect_directories (child, ignored, into);
    }
  }

  /** A single lstat: never a symlink to a directory — following one can leave the workspace, or loop. */
  private static bool is_real_directory (string path) {
    Posix.Stat info;
    if (Posix.lstat (path, out info) != 0) {
      return false;
    }
    return Posix.S_ISDIR (info.st_mode);
  }

  /**
   * Absolute paths of every directory git ignores as a whole, or null
   * when git couldn't answer. `--ignored=matching` reports a directory
   * matched by an ignore pattern as one `!! dir/` entry and never
   * descends into it; a directory that merely holds ignored files isn't
   * reported, and stays watched. `-z`: paths verbatim, NUL-terminated.
   * `--no-optional-locks`: never holds `index.lock` against the user's
   * own git.
   */
  private static GenericSet<string>? list_ignored_directories (string root_path) {
    if (!HostCommand.has_program ("git")) {
      return null;
    }

    var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
    string[] argv = HostCommand.argv ({
      "git", "--no-optional-locks", "-C", root_path,
      "status", "--porcelain", "-z", "--untracked-files=all", "--ignored=matching",
    });

    Subprocess process;
    Bytes? stdout_buf;
    try {
      process = launcher.spawnv (argv);
      process.communicate (null, null, out stdout_buf, null);
    } catch (Error e) {
      return null;
    }
    if (!process.get_successful () || stdout_buf == null) {
      return null;
    }

    var ignored = new GenericSet<string> (str_hash, str_equal);
    unowned uint8[] data = stdout_buf.get_data ();
    int start = 0;
    for (int i = 0; i < data.length; i++) {
      if (data[i] != 0) {
        continue;
      }
      unowned string entry = (string) data[start:i];
      start = i + 1;
      if (entry.has_prefix ("!! ") && entry.has_suffix ("/")) {
        ignored.add (Path.build_filename (root_path, entry.substring (3, entry.length - 4)));
      }
    }
    return ignored;
  }
}
