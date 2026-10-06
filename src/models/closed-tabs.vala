/** A file tab that was closed: where it was, and where its cursor was. */
public class ClosedTab : Object {
  public string path { get; private set; }
  /** 1-based line and 0-based column of the primary cursor, the pair EditorPane.open_at() takes. */
  public int line { get; private set; }
  public int column { get; private set; }

  public ClosedTab (string path, int line, int column) {
    this.path = path;
    this.line = line;
    this.column = column;
  }
}

/**
 * The file tabs closed in a window, latest first — what Ctrl+Shift+T
 * walks back through, like a browser or VS Code (whose cap of 20 this
 * takes). Only tabs with a file behind them: an untitled one has
 * nothing left to reopen from. Lives with the window and dies with it.
 */
public class ClosedTabs : Object {
  public const int CAPACITY = 20;

  private GenericArray<ClosedTab> entries = new GenericArray<ClosedTab> ();

  public bool is_empty {
    get { return entries.length == 0; }
  }

  /** Puts `path` on top. A path already recorded moves up rather than appearing twice; the oldest goes when there are more than CAPACITY. */
  public void record (string path, int line, int column) {
    forget (path);
    entries.add (new ClosedTab (path, line, column));
    if (entries.length > CAPACITY) {
      entries.remove_index (0);
    }
  }

  /** Takes the latest closed tab off the top — null when none is left. */
  public ClosedTab? take () {
    if (entries.length == 0) {
      return null;
    }
    var latest = entries[entries.length - 1];
    entries.remove_index (entries.length - 1);
    return latest;
  }

  /** Drops `path` wherever it is — for a file that no longer exists. */
  public void forget (string path) {
    for (int i = (int) entries.length - 1; i >= 0; i--) {
      if (entries[i].path == path) {
        entries.remove_index (i);
      }
    }
  }
}
