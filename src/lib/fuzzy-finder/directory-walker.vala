namespace Opus.FuzzyFinder {
  /**
   * Lists every regular file under a root, recursively, on its own
   * thread, handing back root-relative "/"-separated paths in batches
   * on the main loop — so whoever owns an {@link Index} can start
   * searching the first directories while deeper ones are still being
   * read (Helix's own picker streams its walk the same way).
   *
   * Directories named in `excluded_names` are pruned before descending,
   * never listed: the only way `.git`/`node_modules`-sized trees stay
   * out of both memory and every later search. Symlinks are skipped
   * (no cycle-following — the same v1 rule FindInFilesSearch keeps).
   */
  public class DirectoryWalker : Object {
    public string[] excluded_names { get; set; }
    public uint batch_size { get; set; default = 256; }

    private string root_path;
    private bool started = false;

    /** The next `batch_size` paths found, root-relative. Emitted on the main loop, in walk order. */
    public signal void batch (string[] relative_paths);

    /** The walk ended — every path was reported, or `cancelled` cut it short. Emitted on the main loop, exactly once per start(). */
    public signal void finished (bool cancelled);

    public DirectoryWalker (string root_path) {
      this.root_path = root_path;
      excluded_names = { ".git" };
    }

    /** Spawns the walking thread. A second call is ignored — construct another walker for another walk. */
    public void start (Cancellable cancellable) {
      if (started) {
        return;
      }
      started = true;

      var excluded = excluded_names;
      var size = batch_size;
      new Thread<void> ("fuzzy-finder-walk", () => {
        var pending = new GenericArray<string> ();
        walk (root_path, "", excluded, size, cancellable, pending);
        if (pending.length > 0 && !cancellable.is_cancelled ()) {
          emit_batch (pending);
        }
        bool was_cancelled = cancellable.is_cancelled ();
        Idle.add (() => {
          finished (was_cancelled);
          return Source.REMOVE;
        });
      });
    }

    private void walk (string dir_path, string relative_prefix, string[] excluded, uint size, Cancellable cancellable, GenericArray<string> pending) {
      if (cancellable.is_cancelled ()) {
        return;
      }

      Dir dir;
      try {
        dir = Dir.open (dir_path);
      } catch (Error e) {
        return; // unreadable (permissions, vanished mid-walk) — skip, not fatal
      }

      var entry_names = new GenericArray<string> ();
      string? entry_name;
      while ((entry_name = dir.read_name ()) != null) {
        if (!is_excluded (entry_name, excluded)) {
          entry_names.add (entry_name);
        }
      }
      entry_names.sort (strcmp);

      for (uint i = 0; i < entry_names.length; i++) {
        if (cancellable.is_cancelled ()) {
          return;
        }
        var name = entry_names[i];
        var entry_path = Path.build_filename (dir_path, name);
        var relative_path = relative_prefix == "" ? name : relative_prefix + "/" + name;

        if (FileUtils.test (entry_path, FileTest.IS_SYMLINK)) {
          continue;
        }
        if (FileUtils.test (entry_path, FileTest.IS_DIR)) {
          walk (entry_path, relative_path, excluded, size, cancellable, pending);
          continue;
        }
        if (!FileUtils.test (entry_path, FileTest.IS_REGULAR)) {
          continue;
        }

        pending.add (relative_path);
        if (pending.length >= size) {
          emit_batch (pending);
          pending.remove_range (0, pending.length);
        }
      }
    }

    private static bool is_excluded (string name, string[] excluded) {
      foreach (var excluded_name in excluded) {
        if (name == excluded_name) {
          return true;
        }
      }
      return false;
    }

    private void emit_batch (GenericArray<string> pending) {
      var paths = new string[pending.length];
      for (uint i = 0; i < pending.length; i++) {
        paths[i] = pending[i];
      }
      Idle.add (() => {
        batch (paths);
        return Source.REMOVE;
      });
    }
  }
}
