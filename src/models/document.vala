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

    private string original_content = "";

    public bool dirty {
        get { return readable && content != original_content; }
    }

    private Document (string path) {
        this.path = path;
    }

    public static Document load (string path) throws Error {
        var document = new Document (path);

        string contents;
        size_t length;
        FileUtils.get_contents (path, out contents, out length);

        if (((string) contents).validate ((ssize_t) length)) {
            document.content = contents;
            document.original_content = contents;
            document.readable = true;
        } else {
            document.content = "";
            document.original_content = "";
            document.readable = false;
        }

        return document;
    }

    /** A brand-new tab with nothing on disk yet — `display_name` (e.g. "Untitled-1") stands in for `path` as this document's unique key until save_as() gives it a real one. Starts clean, same as any freshly-loaded file: it only becomes dirty once actually edited. */
    public static Document untitled (string display_name) {
        var document = new Document (display_name);
        document.is_untitled = true;
        return document;
    }

    /** Only ever valid for a document that already has a real path — an untitled one always goes through save_as() instead (see EditorController). */
    public void save () throws Error {
        if (!readable) {
            return;
        }

        FileUtils.set_contents (path, content);
        original_content = content;
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
    }
}
