namespace CommandBar {
  /**
   * The paths opened in this window, most recent first — what the
   * Command Bar shows before anything is typed. In-memory only: it
   * resets with the app (persisting it is a separate, later concern —
   * see COMMAND_BAR_IMPLEMENTATION_PLAN.md §8).
   */
  public class RecentFiles : Object {
    public const uint MAX = 200;

    private GenericArray<string> paths = new GenericArray<string> ();

    public signal void changed ();

    public uint size {
      get { return paths.length; }
    }

    /** Moves `path` to the front, adding it if new; the oldest entry past MAX falls off the end. */
    public void push (string path) {
      remove_quietly (path);
      paths.insert (0, path);
      if (paths.length > MAX) {
        paths.remove_index (paths.length - 1);
      }
      changed ();
    }

    public void remove (string path) {
      if (remove_quietly (path)) {
        changed ();
      }
    }

    public bool contains (string path) {
      uint index;
      return find (path, out index);
    }

    public string[] all () {
      var result = new string[paths.length];
      for (uint i = 0; i < paths.length; i++) {
        result[i] = paths[i];
      }
      return result;
    }

    private bool remove_quietly (string path) {
      uint index;
      if (!find (path, out index)) {
        return false;
      }
      paths.remove_index (index);
      return true;
    }

    private bool find (string path, out uint index) {
      for (uint i = 0; i < paths.length; i++) {
        if (paths[i] == path) {
          index = i;
          return true;
        }
      }
      index = 0;
      return false;
    }
  }
}
