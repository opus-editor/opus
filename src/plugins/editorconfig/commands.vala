namespace Opus.Plugins.EditorConfig {
  /** The plugin's rows in the `>` list: "EditorConfig / Generate .editorconfig", VS Code's own command, from a fixed template for now. */
  public class Commands : Object, IWorkspaceExtension, CommandBar.ICommandSource {
    public const string GENERATE = "generate";
    public const string TEMPLATE = """root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true
""";

    public WorkspaceContext context { get; set; }

    public Commands (WorkspaceContext context) {
      Object (context: context);
    }

    public void activate () {}
    public void deactivate () {}

    public string name {
      owned get { return "EditorConfig"; }
    }

    public CommandBar.Command[] commands () {
      return { new CommandBar.Command (GENERATE, _("Generate .editorconfig")) };
    }

    /** Writes the template at the folder's root and opens it — never over one already there. */
    public void run (string id) throws Error {
      if (id != GENERATE) {
        return;
      }
      var path = Path.build_filename (context.root_path, ConfigFile.NAME);
      if (FileUtils.test (path, FileTest.EXISTS)) {
        throw new IOError.EXISTS (_("There is a .editorconfig at the root of this folder already"));
      }
      FileUtils.set_contents (path, TEMPLATE);
      open_file_requested (path);
    }
  }
}
