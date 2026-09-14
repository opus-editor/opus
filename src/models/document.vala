/**
 * Plain state for a single file open in the editor: its path, its content,
 * whether it has unsaved changes, and whether it's shown as a preview tab.
 *
 * A Document is only ever created through {@link load}, which also detects
 * files that aren't valid UTF-8 and marks them `readable = false` instead of
 * throwing — those are shown as a placeholder by the editor and never edited
 * or saved.
 */
public class Document : Object {
    public string path { get; private set; }
    public string content { get; set; default = ""; }
    public bool is_preview { get; set; default = false; }
    public bool readable { get; private set; default = true; }

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

    public void save () throws Error {
        if (!readable) {
            return;
        }

        FileUtils.set_contents (path, content);
        original_content = content;
    }
}
