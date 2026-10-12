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
  /** How a file's lines end on disk. The buffer itself is always "\n"; this is reapplied when saving. */
  public enum LineEnding {
    LF,
    CRLF;

    public string text () {
      return this == CRLF ? "\r\n" : "\n";
    }
  }

  /** How a file's bytes encode its text. The buffer is always UTF-8; this is what the bytes are read and written as. */
  public enum Charset {
    UTF8,
    UTF8_BOM,
    LATIN1,
    UTF16BE,
    UTF16LE;

    /** EditorConfig's own names: utf-8, utf-8-bom, latin1, utf-16be, utf-16le; null for anything else. */
    public static Charset? parse (string name) {
      switch (name) {
        case "utf-8": return UTF8;
        case "utf-8-bom": return UTF8_BOM;
        case "latin1": return LATIN1;
        case "utf-16be": return UTF16BE;
        case "utf-16le": return UTF16LE;
        default: return null;
      }
    }

    public string iconv_name () {
      switch (this) {
        case LATIN1: return "ISO-8859-1";
        case UTF16BE: return "UTF-16BE";
        case UTF16LE: return "UTF-16LE";
        default: return "UTF-8";
      }
    }

    /** The byte order mark this charset is written with; none for plain UTF-8 and latin1. */
    public uint8[] bom () {
      switch (this) {
        case UTF8_BOM: return { 0xEF, 0xBB, 0xBF };
        case UTF16BE: return { 0xFE, 0xFF };
        case UTF16LE: return { 0xFF, 0xFE };
        default: return {};
      }
    }

    /** The charset a leading byte order mark names, null without one. */
    public static Charset? of_bom (uint8[] bytes) {
      if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        return UTF8_BOM;
      }
      if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return UTF16BE;
      }
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return UTF16LE;
      }
      return null;
    }
  }

  public string uri { get; private set; }
  public string? pathname { get; private set; default = null; }
  /** This document's own short display name — a real file's basename, or a synthetic tab's plain name ("Untitled-1", "Find Results"). Set once at creation and kept in sync with `pathname`/`uri` by move_to()/save_as(); never derived from `uri` itself, which is a machine key only and never guaranteed to look presentable. */
  public string name { get; private set; }
  public string content { get; set; default = ""; }
  /**
   * The line ending the file is written with: what it had when loaded
   * (CRLF when more than half its line ends were), LF for a new one,
   * or what the folder's .editorconfig says. Never present in `content`.
   */
  public LineEnding line_ending { get; set; default = LineEnding.LF; }
  /**
   * The charset the file is read and written as: what its byte order
   * mark said, else what the folder's settings said when it was opened,
   * else UTF-8. A file that can't be decoded as it is `readable = false`.
   */
  public Charset charset { get; set; default = Charset.UTF8; }
  /**
   * The name of the language package this document was set to by
   * hand, over whatever its own name would make it — null while it
   * hasn't been. Lives and dies with the document: kept through a
   * rename or a "Save As", gone once it is closed.
   */
  public string? language_override { get; set; default = null; }
  public bool is_preview { get; set; default = false; }
  /** The first line showing while this document was last on screen, 1-based — where the editor scrolls back to when it comes back. */
  public int top_line { get; set; default = 1; }
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

  /** `charset`, when given, is what the folder says the file is; a byte order mark in the file itself wins over it. */
  public static Document load (string path, Charset? charset = null) throws Error {
    var document = new Document (uri_for_path (path));
    document.pathname = path;
    document.name = Path.get_basename (path);
    if (charset != null) {
      document.charset = charset;
    }
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
    uint8[] bytes;
    FileUtils.get_data (pathname, out bytes);

    var decoded = decode (bytes);
    if (decoded != null) {
      line_ending = detect_line_ending (decoded);
      content = decoded.replace ("\r\n", "\n");
      original_content = content;
      readable = true;
    } else {
      content = "";
      original_content = "";
      readable = false;
    }
  }

  /** `bytes` as UTF-8 text in `charset` (a BOM naming another one wins, and is dropped), null when they aren't valid in it. */
  private string? decode (uint8[] bytes) {
    var marked = Charset.of_bom (bytes);
    if (marked != null) {
      charset = marked;
    }
    int skip = charset.bom ().length;
    unowned uint8[] body = bytes[skip:bytes.length];
    if (charset == Charset.UTF8 || charset == Charset.UTF8_BOM) {
      return ((string) body).validate ((ssize_t) body.length) ? ((string) body).substring (0, body.length) : null;
    }
    try {
      return GLib.convert ((string) body, body.length, "UTF-8", charset.iconv_name ());
    } catch (ConvertError e) {
      return null;
    }
  }

  /** `content` as the bytes that go to disk: the buffer's "\n" as `line_ending`, in `charset`, behind its BOM. Throws for text the charset can't hold (a "ç" outside latin1's reach is not the case, an emoji is). */
  private uint8[] encoded () throws Error {
    var text = serialized ();
    uint8[] body;
    if (charset == Charset.UTF8 || charset == Charset.UTF8_BOM) {
      body = text.data;
    } else {
      size_t written;
      var converted = GLib.convert (text, text.length, charset.iconv_name (), "UTF-8", null, out written);
      body = new uint8[written];
      Memory.copy (body, (uint8*) converted, written);
    }
    var bytes = new ByteArray ();
    bytes.append (charset.bom ());
    bytes.append (body);
    return bytes.steal ();
  }

  /** VS Code's rule (pieceTreeTextBufferBuilder): CRLF when more than half the line ends are; a lone "\r" counts as nothing. */
  private static LineEnding detect_line_ending (string text) {
    int lf = 0, crlf = 0;
    for (int i = 0; i < text.length; i++) {
      if (text[i] != '\n') {
        continue;
      }
      lf++;
      if (i > 0 && text[i - 1] == '\r') {
        crlf++;
      }
    }
    return crlf * 2 > lf ? LineEnding.CRLF : LineEnding.LF;
  }

  /** `content` as it goes to disk: the buffer's "\n" as `line_ending`. */
  private string serialized () {
    return line_ending == LineEnding.CRLF ? content.replace ("\n", "\r\n") : content;
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

    FileUtils.set_data (pathname, encoded ());
    original_content = content;
    is_deleted = false;
    is_externally_modified = false;
  }

  /** Writes the current content to `new_path` instead, and this document now tracks that path from here on (a "Save As", or an untitled document's first real save). A no-op on an unreadable document, same as save(). */
  public void save_as (string new_path) throws Error {
    if (!readable) {
      return;
    }

    FileUtils.set_data (new_path, encoded ());
    uri = uri_for_path (new_path);
    pathname = new_path;
    name = Path.get_basename (new_path);
    original_content = content;
    is_untitled = false;
    is_deleted = false;
    is_externally_modified = false;
  }
}
