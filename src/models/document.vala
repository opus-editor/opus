/**
 * Plain state for a single file open in the editor: its path, its content,
 * whether it has unsaved changes, and whether it's shown as a preview tab.
 *
 * A Document is created either through {@link load} (an existing file on
 * disk — also detects files that aren't valid UTF-8 and marks them
 * `readable = false` instead of throwing, shown as a placeholder by the
 * editor and never edited or saved) or {@link untitled} (a brand-new tab,
 * `is_untitled = true`, whose `path` is a synthetic display name rather
 * than a real filesystem path until it's actually saved somewhere).
 */
public class Document : Object {
  public string path { get; private set; }
  public string content { get; set; default = ""; }
  public bool is_preview { get; set; default = false; }
  public bool readable { get; private set; default = true; }
  public bool is_untitled { get; private set; default = false; }

  /**
   * The file this document was loaded from was deleted (or moved away)
   * outside Opus, while still open — set by EditorController's own file
   * watcher, and only ever for a tab that was already dirty at that
   * moment (a clean one just closes outright instead — nothing of
   * value to keep showing "deleted"). Doesn't factor into `dirty`
   * itself: it's only ever set on an already-dirty document, so dirty's
   * own plain `content != original_content` already covers it.
   */
  public bool is_deleted { get; set; default = false; }

  /**
   * The file this document was loaded from was changed on disk by
   * something other than Opus itself, while still open — set by
   * EditorController's own file watcher. Cleared only by {@link reload}
   * (the user explicitly discarding in-memory content in favor of what's
   * on disk); like `is_deleted`, purely a display/tracking flag that
   * doesn't factor into `dirty` on its own.
   */
  public bool is_externally_modified { get; set; default = false; }

  private string original_content = "";

  public bool dirty {
    get { return readable && content != original_content; }
  }

  /** This document's own multi-cursor state — separate from any other open document's. */
  public CursorCollection cursors { get; private set; }

  /** This document's own undo/redo stack — separate from any other open document's. */
  public EditHistory history { get; private set; }

  private Document (string path) {
    this.path = path;
    cursors = new CursorCollection ();
    history = new EditHistory ();
  }

  public static Document load (string path) throws Error {
    var document = new Document (path);
    document.read_from_disk ();
    return document;
  }

  /**
   * Discards in-memory content and re-reads `path` from disk — "Discard
   * Changes and Reload", after an external change was detected. Always
   * wins over whatever was in the buffer, dirty or not: the banner that
   * leads here already is the user's confirmation, same as GNOME Text
   * Editor's own equivalent action.
   */
  public void reload () throws Error {
    read_from_disk ();
    is_externally_modified = false;
    is_deleted = false;
  }

  private void read_from_disk () throws Error {
    string contents;
    size_t length;
    FileUtils.get_contents (path, out contents, out length);

    if (((string) contents).validate ((ssize_t) length)) {
      content = contents;
      original_content = contents;
      readable = true;
    } else {
      content = "";
      original_content = "";
      readable = false;
    }
  }

  /** A brand-new tab with nothing on disk yet — `display_name` (e.g. "Untitled-1") stands in for `path` as this document's unique key until save_as() gives it a real one. Starts clean, same as any freshly-loaded file: it only becomes dirty once actually edited. */
  public static Document untitled (string display_name) {
    var document = new Document (display_name);
    document.is_untitled = true;
    return document;
  }

  /**
   * The file this document tracks moved on disk without Opus itself
   * writing anything there — a sidebar Rename, or a Cut+Paste (menu or
   * drag) actually moving it. Unlike save_as(), nothing was written:
   * content/dirty/is_untitled are all untouched, this only relabels
   * which path the document is for.
   */
  public void move_to (string new_path) {
    path = new_path;
  }

  /** Only ever valid for a document that already has a real path — an untitled one always goes through save_as() instead (see EditorController). */
  public void save () throws Error {
    if (!readable) {
      return;
    }

    FileUtils.set_contents (path, content);
    original_content = content;
    is_deleted = false;
    is_externally_modified = false;
  }

  /** Writes the current content to `new_path` instead, and this document now tracks that path from here on (a "Save As", or an untitled document's first real save). */
  public void save_as (string new_path) throws Error {
    if (!readable) {
      return;
    }

    FileUtils.set_contents (new_path, content);
    path = new_path;
    original_content = content;
    is_untitled = false;
    is_deleted = false;
    is_externally_modified = false;
  }
}
