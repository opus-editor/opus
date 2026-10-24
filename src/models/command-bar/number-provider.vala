namespace CommandBar {
  /**
   * A number to pick out of a range — what the Document Properties
   * pane's Indent Size and Tab Width rows put in the Command Bar, the
   * way VS Code's own "Spaces: 4" in the status bar opens a list of 1
   * to 8. One row per value, narrowed by what is typed; an accepted row
   * carries the value, or {@link NONE} for the optional first row that
   * stands for none of them, in whatever words it was given.
   *
   * Never found by a prefix: it is handed to the Router by whoever
   * opens it (Router.open_with()), so it isn't registered.
   */
  public class NumberProvider : Object, IWorkspaceExtension, IProvider {
    /** The id of the "none" row: no number is spelled "". */
    public const string NONE = "";

    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ""; }
    }

    public string placeholder {
      owned get { return hint; }
    }

    private string hint;
    private GenericArray<Item> rows = new GenericArray<Item> ();
    private Picker? picker = null;

    /** `none_label`, when given, puts the NONE row ahead of the numbers, with `none_description` beside it. */
    public NumberProvider (string placeholder, int from, int to, string? none_label = null, string? none_description = null) {
      hint = placeholder;
      if (none_label != null) {
        var none = new Item (NONE, none_label);
        none.description = none_description;
        rows.add (none);
      }
      for (int value = from; value <= to; value++) {
        rows.add (new Item (value.to_string (), value.to_string ()));
      }
    }

    public void activate () {}

    public void deactivate () {
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      picker.empty_message = _("No matching values");
      picker.filter_changed.connect (update);
      picker.closed.connect (detach_picker);
      update ();
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
