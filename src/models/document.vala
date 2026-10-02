/**
 * Plain state for a single file open in the editor: its identity, its
 * content, whether it has unsaved changes, and whether it's shown as a
 * preview tab.
 *
 * `uri` is a scheme-prefixed identifier — `file:///abs/path`,
 * `untitled://1` — unique per open tab and safe to use as a map key
 * regardless of what kind of document this is.
 * `pathname`, separate from it, is the real OS filesystem path, set only
 * for a `load()`ed document; `name` is its short display name. Neither
 * is ever assigned directly from outside this class — {@link load},
 * {@link move_to}, and {@link save_as} are the only places any of
 * `uri`/`pathname`/`name` ever change, always together, as one atomic
 * state change.
 *
 * A Document is created through {@link load} (an existing file on disk —
 * also detects files that aren't valid UTF-8 and marks them `readable =
 * false` instead of throwing, shown as a placeholder by the editor and
 * never edited or saved) or {@link untitled} (a brand-new tab, `is_untitled =
 * true`, no `pathname` until it's actually saved somewhere).
 */
public class Document : Object {
  public string uri { get; private set; }
  public string? pathname { get; private set; default = null; }
  /** This document's own short display name — a real file's basename, or a synthetic tab's plain name ("Untitled-1", "Find Results"). Set once at creation and kept in sync with `pathname`/`uri` by move_to()/save_as(); never derived from `uri` itself, which is a machine key only and never guaranteed to look presentable. */
  public string name { get; private set; }
  public string content { get; set; default = ""; }
  public bool is_preview { get; set; default = false; }
  public bool readable { get; private set; default = true; }
  public bool is_untitled { get; private set; default = false; }

  /** A clean, user-facing identity string for this document — the real full path for a file, `name` otherwise. Used wherever a value needs to stay unambiguous between two documents that could share the same `name` (Opus.Dev.DevServer's own ListOpenTabs/GetActiveTab, and the tab tooltip); the tab label itself reads `name` directly instead, since a full path is too long for that. */
  public string title {
    owned get { return pathname ?? name; }
  }

  /**
   * The file this document was loaded from was deleted (or moved away)
   * outside Opus, while still open — set by the Document tab's own file
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
   * the Document tab's own file watcher. Cleared only by {@link reload}
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

  private Document (string uri) {
    this.uri = uri;
    cursors = new CursorCollection ();
    history = new EditHistory ();
  }

  /** `"file://" + path` — the one place this prefix is built; EditorView.EditorPane.TabDocument reuses it at its own boundary instead of re-deriving it. */
  public static string uri_for_path (string path) {
    return "file://" + path;
  }

  public static Document load (string path) throws Error {
    var document = new Document (uri_for_path (path));
    document.pathname = path;
    document.name = Path.get_basename (path);
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
    FileUtils.get_contents (pathname, out contents, out length);

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

  /**
   * A brand-new tab with nothing on disk yet — a synthetic `untitled://`
   * uri stands in for a real one until save_as() gives it one. Starts
   * clean, same as any freshly-loaded file: it only becomes dirty once
   * actually edited. `uri_path`/`name` are independent on purpose:
   * `uri_path` is a stable identity slug (a plain counter, e.g. "1") that
   * must never move just because the display text does — "Untitled-N" is
   * exactly the kind of string that gets reworded/localized later, and
   * the uri can't follow it when it does.
   */
  public static Document untitled (string uri_path, string name) {
    var document = new Document ("untitled://" + uri_path);
    document.name = name;
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
    uri = uri_for_path (new_path);
    pathname = new_path;
    name = Path.get_basename (new_path);
  }

  /** Only ever valid for a document that already has a real path — an untitled one always goes through save_as() instead. A no-op on an unreadable document: there's no real content to write back. */
  public void save () throws Error {
    if (!readable) {
      return;
    }

    FileUtils.set_contents (pathname, content);
    original_content = content;
    is_deleted = false;
    is_externally_modified = false;
  }

  /** Writes the current content to `new_path` instead, and this document now tracks that path from here on (a "Save As", or an untitled document's first real save). A no-op on an unreadable document, same as save(). */
  public void save_as (string new_path) throws Error {
    if (!readable) {
      return;
    }

    FileUtils.set_contents (new_path, content);
    uri = uri_for_path (new_path);
    pathname = new_path;
    name = Path.get_basename (new_path);
    original_content = content;
    is_untitled = false;
    is_deleted = false;
    is_externally_modified = false;
  }
}
