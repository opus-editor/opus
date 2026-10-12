namespace CommandBar {
  /**
   * Commands a plugin adds to the `>` list — a list of what it offers,
   * which the CommandProvider lays after the app's own, each row read
   * "<name> / <label>". VS Code's contributes.commands and
   * registerCommand in one: the same object lists and runs. Nothing of
   * the Picker reaches a source; it hands out ids and gets one back.
   */
  public interface ICommandSource : Object, IWorkspaceExtension {
    /** What the rows start with: the plugin's own name, "EditorConfig". */
    public abstract string name { owned get; }

    /** The commands, in the order they are listed; ids unique within this source. */
    public abstract Command[] commands ();

    /** Runs the command picked. A failure is an Error whose message the host shows. */
    public abstract void run (string id) throws Error;

    /** A command wants `path` shown in a tab — the host opens it; a source never touches a View. */
    public signal void open_file_requested (string path);
  }
}
