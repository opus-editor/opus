/**
 * A directory's live-tracking state: an active `Gio.FileMonitor` once
 * actually watching, and/or a pending debounce timeout about to start or
 * stop one — see FileTreeController.on_directory_expanded_changed() for
 * why both exist and are never both meaningful at once (a directory is
 * either mid-transition or settled, never both).
 */
private class DirectoryWatch : Object {
    public FileMonitor? monitor = null;
    public uint pending_timeout_id = 0;
}

/**
 * Builds the {@link FileTree} for a workspace root and drives an
 * {@link FileTreeView} from it — including the sidebar's context menu:
 * creating, renaming, deleting, moving and copying files/folders on disk
 * (keeping {@link FileTree} in sync), launching the system file
 * manager/terminal, copying paths to the clipboard, and live-tracking
 * external changes (another app creating/deleting/renaming something)
 * for whichever directories are actually expanded.
 *
 * Re-emits the view's `file_activated`/`delete_entry_requested` signals as
 * its own, so callers (`MainController`) never need to depend on
 * `FileTreeView` directly.
 */
public class FileTreeController : Object {
    // Tried in this order for "Open in Terminal"; the first one actually
    // installed wins. Spawned with its working directory set directly
    // (see open_in_terminal()) rather than passed a
    // `--working-directory`-style flag, since those differ per terminal
    // and a process's own cwd doesn't.
    private const string[] TERMINAL_COMMANDS = { "gnome-terminal", "kgx", "konsole", "xfce4-terminal", "xterm" };

    // Long enough to absorb someone rapidly toggling a row open/closed
    // (thinking out loud, or just clicking around) without ever actually
    // touching the filesystem for it; short enough that deliberately
    // opening a folder to look at it still starts tracking it almost
    // immediately. See on_directory_expanded_changed()'s own comment for
    // the full reasoning.
    private const uint WATCH_DEBOUNCE_MS = 400;

    private FileTreeView view;
    private FileTree tree;
    private string root_path;

    // One entry per directory that's ever been expanded (or is mid-way
    // through becoming watched/unwatched) — never the whole tree at once;
    // see the class doc comment. Root's own entry starts watching
    // immediately at construction (its children are always visible, no
    // "expand" ever needed for it) rather than through this debounce path.
    private HashTable<string, DirectoryWatch> watches = new HashTable<string, DirectoryWatch> (str_hash, str_equal);

    public signal void file_activated (string path, bool open_permanent);

    /** A New File was just created on disk (not a New Folder — nothing to open for those) — meant to be opened as a permanent tab right away. */
    public signal void file_created (string path);

    /**
     * "Delete" was chosen for `path` — re-emitted, not handled here
     * directly: whether this needs an unsaved-changes confirmation first
     * (a file with a dirty open tab) is MainController's call, since only
     * it can see EditorController's state too. delete_entry() below does
     * the actual deletion, once MainController decides it's safe to.
     */
    public signal void delete_entry_requested (string path);

    public FileTreeController (FileTreeView view, string root_path) throws Error {
        this.view = view;
        this.root_path = root_path;

        tree = new FileTree (root_path);
        view.populate (tree.root);

        view.file_activated.connect ((path, open_permanent) => {
            file_activated (path, open_permanent);
        });
        view.create_entry_requested.connect (on_create_entry_requested);
        view.rename_entry_requested.connect (on_rename_entry_requested);
        view.delete_entry_requested.connect ((path) => delete_entry_requested (path));
        view.paste_requested.connect (on_paste_requested);
        view.open_in_files_requested.connect (open_in_files);
        view.open_in_terminal_requested.connect (open_in_terminal);
        view.copy_path_requested.connect ((path) => view.copy_to_clipboard (path));
        view.copy_relative_path_requested.connect ((path) => view.copy_to_clipboard (relative_path (path)));
        view.directory_expanded_changed.connect (on_directory_expanded_changed);

        var root_watch = new DirectoryWatch ();
        watches[root_path] = root_watch;
        start_watching (root_path, root_watch);
    }

    /**
     * Debounces a directory's expand/collapse into starting or stopping a
     * `Gio.FileMonitor` for it — at most one pending timeout per
     * directory, always reflecting the *latest* toggle: expanding cancels
     * any pending "stop watching" (and, if nothing's watching yet, starts
     * a fresh "start watching" timer); collapsing does the reverse.
     * Toggling back and forth fast enough never lets either timer fire at
     * all, so a real watch/unwatch only ever happens once the state's
     * actually settled — a deliberate, preventive design (not something
     * observed breaking live): without it, rapidly clicking a row
     * open/closed (or just idly fidgeting with one) would start and stop
     * real `Gio.FileMonitor`s — each one a kernel inotify watch, a
     * genuinely limited resource — many times over for nothing.
     */
    private void on_directory_expanded_changed (string path, bool expanded) {
        var watch = watches[path];
        if (watch == null) {
            watch = new DirectoryWatch ();
            watches[path] = watch;
        }

        if (watch.pending_timeout_id != 0) {
            Source.remove (watch.pending_timeout_id);
            watch.pending_timeout_id = 0;
        }

        if (expanded) {
            if (watch.monitor != null) {
                return; // already watching — re-expanded before its own "stop" debounce fired
            }
            watch.pending_timeout_id = Timeout.add (WATCH_DEBOUNCE_MS, () => {
                watch.pending_timeout_id = 0;
                start_watching (path, watch);
                return Source.REMOVE;
            });
        } else {
            if (watch.monitor == null) {
                return; // never actually started — collapsed before its own "start" debounce fired
            }
            watch.pending_timeout_id = Timeout.add (WATCH_DEBOUNCE_MS, () => {
                watch.pending_timeout_id = 0;
                stop_watching (watch);
                return Source.REMOVE;
            });
        }
    }

    private void start_watching (string path, DirectoryWatch watch) {
        var node = tree.find (path);
        if (node == null) {
            return; // gone (deleted/renamed away) before the debounce fired
        }

        try {
            watch.monitor = File.new_for_path (path).monitor_directory (FileMonitorFlags.WATCH_MOVES, null);
            watch.monitor.changed.connect ((file, other_file, event_type) => on_directory_changed (path, event_type));
        } catch (Error e) {
            warning ("failed to watch %s: %s", path, e.message);
        }
    }

    private void stop_watching (DirectoryWatch watch) {
        if (watch.monitor == null) {
            return;
        }
        watch.monitor.cancel ();
        watch.monitor = null;
    }

    /**
     * An external change to a watched directory's own immediate children
     * (something this tree didn't do itself — those already update the
     * view directly, e.g. on_create_entry_requested()). Only structural
     * events actually change what that directory's children list looks
     * like; a plain CHANGED (a file's contents being written) doesn't.
     */
    private void on_directory_changed (string path, FileMonitorEvent event_type) {
        switch (event_type) {
            case FileMonitorEvent.CREATED:
            case FileMonitorEvent.DELETED:
            case FileMonitorEvent.RENAMED:
            case FileMonitorEvent.MOVED_IN:
            case FileMonitorEvent.MOVED_OUT:
                break;
            default:
                return;
        }

        var node = tree.find (path);
        if (node == null) {
            return;
        }

        try {
            tree.rescan_children (node);
        } catch (Error e) {
            return; // the directory itself was likely just deleted/renamed away
        }

        view.refresh_children (path, node.children);
    }

    /** Cancels every pending debounce timer and active filesystem watch — call before discarding this controller (e.g. "Close Folder", or replacing it with a freshly-opened one), so nothing keeps firing — or keeping this object alive via a scheduled GLib.Timeout closure — after it's no longer wanted. */
    public void close () {
        foreach (var watch in watches.get_values ()) {
            if (watch.pending_timeout_id != 0) {
                Source.remove (watch.pending_timeout_id);
            }
            if (watch.monitor != null) {
                watch.monitor.cancel ();
            }
        }
        watches.remove_all ();
    }

    private void on_create_entry_requested (string parent_path, string name, bool is_directory) {
        var parent = tree.find (parent_path);
        if (parent == null) {
            view.discard_pending_entry ();
            return;
        }

        FileNode node;
        try {
            node = tree.create_child (parent, name, is_directory);
        } catch (Error e) {
            view.discard_pending_entry ();
            view.show_error (_("Couldn’t create “%s”: %s").printf (name, e.message));
            return;
        }

        view.refresh_children (parent_path, parent.children);
        if (!is_directory) {
            file_created (node.path);
        }
    }

    private void on_rename_entry_requested (string path, string new_name) {
        var node = tree.find (path);
        var parent = node == null ? null : tree.find (Path.get_dirname (path));
        if (node == null || parent == null) {
            view.cancel_rename ();
            return;
        }

        try {
            tree.rename_child (parent, node, new_name);
        } catch (Error e) {
            view.cancel_rename ();
            view.show_error (_("Couldn’t rename “%s”: %s").printf (node.name, e.message));
            return;
        }

        view.refresh_children (parent.path, parent.children);
    }

    /** Actually deletes `path` — called by MainController once it's decided it's safe to (a folder, or a file with no dirty open tab, or one whose unsaved changes the user explicitly confirmed losing). */
    public void delete_entry (string path) {
        var node = tree.find (path);
        var parent = node == null ? null : tree.find (Path.get_dirname (path));
        if (node == null || parent == null) {
            return;
        }

        try {
            tree.delete_child (parent, node);
        } catch (Error e) {
            view.show_error (_("Couldn’t delete “%s”: %s").printf (node.name, e.message));
            return;
        }

        view.refresh_children (parent.path, parent.children);
    }

    /** The system's own confirmation for deleting `filename` while it has unsaved changes open — Cancel, or lose them and delete anyway. */
    public async bool confirm_delete_with_unsaved_changes (string filename) {
        return yield view.confirm_delete_with_unsaved_changes (filename);
    }

    private void on_paste_requested (string source_path, bool is_cut, string target_path) {
        var source = tree.find (source_path);
        var source_parent = source == null ? null : tree.find (Path.get_dirname (source_path));
        var target = tree.find (target_path);
        if (source == null || source_parent == null || target == null) {
            return;
        }

        try {
            if (is_cut) {
                tree.move_child (source_parent, source, target);
            } else {
                tree.copy_child (source, target);
            }
        } catch (Error e) {
            view.show_error (_("Couldn’t paste “%s”: %s").printf (source.name, e.message));
            return;
        }

        view.refresh_children (target.path, target.children);
        if (is_cut) {
            view.refresh_children (source_parent.path, source_parent.children);
        }
        view.clipboard_pasted (is_cut);
    }

    private void open_in_files (string path) {
        try {
            AppInfo.launch_default_for_uri (File.new_for_path (path).get_uri (), null);
        } catch (Error e) {
            view.show_error (_("Couldn’t open “%s” in the file manager: %s").printf (path, e.message));
        }
    }

    private void open_in_terminal (string path) {
        foreach (var command in TERMINAL_COMMANDS) {
            if (Environment.find_program_in_path (command) == null) {
                continue;
            }

            var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
            launcher.set_cwd (path);
            string[] argv = { command };
            // spawnv() takes a `const gchar * const *`; valac always
            // marshals a string[] as a plain, non-const `gchar**`, which C
            // never implicitly converts to that (a structural wart around
            // double-pointer const-ness, not a vapi bug here specifically).
            // Normally a plain -Wno-incompatible-pointer-types would cover
            // this, but valac itself emits `#pragma GCC diagnostic warning
            // "-Wincompatible-pointer-types"` at the top of every generated
            // .c file, which overrides any command-line -Wno- for it —
            // so, same as the Gtk.StyleContext deprecation warnings
            // elsewhere in this project, this one stays until upstream
            // changes something, not because a build flag wasn't tried.
            try {
                launcher.spawnv (argv);
            } catch (Error e) {
                view.show_error (_("Couldn’t launch %s: %s").printf (command, e.message));
            }
            return;
        }

        view.show_error (_("No terminal emulator was found on this system."));
    }

    /** `path`, relative to the workspace root — `path` itself if it's somehow outside it. */
    private string relative_path (string path) {
        var prefix = root_path + "/";
        return path.has_prefix (prefix) ? path.substring (prefix.length) : path;
    }
}
