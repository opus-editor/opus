namespace CommandBar {
  /**
   * The provider of the empty prefix while no folder is open: there
   * are no files to search, so it lists nothing — it is there for the
   * bar to open at all, and so reach the lists a prefix leads to,
   * none of which need a folder. MainWindow swaps it for FileProvider
   * while a folder is linked.
   */
  public class NoFolderProvider : Object, IWorkspaceExtension, IProvider {
    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ""; }
    }

    public string placeholder {
      owned get { return _("Search files by name"); }
    }

    public void activate () {}

    public void deactivate () {}

    public void provide (Picker picker, Cancellable cancellable) {
      picker.empty_message = PrefixHint.text (_("Open a folder to search files"));
      picker.set_items (new GenericArray<Item> ());
    }
  }
}
