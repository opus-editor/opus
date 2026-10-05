namespace CommandBar {
  /**
   * The list of languages a document can be set to — what "Set
   * language..." puts in the Command Bar. One row per language package
   * that can open a file, by title, narrowed by what is typed; an
   * accepted row carries the package's `name`.
   *
   * Never found by a prefix: it is handed to the Router by whoever
   * runs that command (Router.open_with()), so it isn't registered,
   * and its own prefix is empty — everything typed is the filter.
   */
  public class LanguageProvider : Object, IWorkspaceExtension, IProvider {
    /** The id of the "Auto Detect" row: no package has an empty name. */
    public const string AUTO_DETECT = "";

    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ""; }
    }

    public string placeholder {
      owned get { return _("Select language..."); }
    }

    /**
     * Whether to offer "Auto Detect" ahead of the languages: the way
     * back from a language picked by hand to the one the file's own
     * name says. Only worth a row when there is a pick to undo — set
     * before each opening, for the document it is about.
     */
    public bool offers_auto_detect { get; set; default = false; }

    /**
     * Whether there is a document to set the language of. Without
     * one there is nothing to pick for: the list stays empty and says
     * why, the way the `:` list does with no file to go to a line in.
     * Set before each opening, like {@link offers_auto_detect}.
     */
    public bool has_document { get; set; default = true; }

    private Syntax.Languages languages;
    private GenericArray<Item> rows = new GenericArray<Item> ();
    private Picker? picker = null;

    public LanguageProvider (Syntax.Languages languages) {
      this.languages = languages;
    }

    public void activate () {}

    public void deactivate () {
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      // Read now, not once: a package installed since the last opening belongs in the list.
      rows = has_document ? list_rows () : new GenericArray<Item> ();
      picker.empty_message = has_document ? _("No matching languages") : _("Open a file to set its language");
      picker.filter_changed.connect (update);
      picker.closed.connect (detach_picker);
      update ();
    }

    private GenericArray<Item> list_rows () {
      var listed = new GenericArray<Item> ();
      if (offers_auto_detect) {
        listed.add (new Item (AUTO_DETECT, _("Auto Detect")));
      }
      foreach (var package in languages.selectable ()) {
        var row = new Item (package.name, package.title);
        // The name is what a manifest and a Markdown fence call it; not worth repeating when the title already is it.
        row.description = package.title == package.name ? null : package.name;
        listed.add (row);
      }
      return listed;
    }

    private void update () {
      picker.set_items (ItemFilter.narrow (rows, picker.filter));
    }

    private void detach_picker () {
      if (picker == null) {
        return;
      }
      picker.filter_changed.disconnect (update);
      picker.closed.disconnect (detach_picker);
      picker = null;
    }
  }
}
