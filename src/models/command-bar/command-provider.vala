namespace CommandBar {
  /** One thing the `>` list offers: the words it is listed under, and the id handed back when it is picked. */
  public class Command : Object {
    public string id { get; private set; }
    public string label { get; private set; }

    public Command (string id, string label) {
      this.id = id;
      this.label = label;
    }
  }

  /**
   * The `>` provider — VS Code's own Command Palette: a list of things
   * the app can do, narrowed by what is typed after the `>`. It lists
   * and nothing more: an accepted row carries a command's `id`, and
   * whoever built the provider with those commands is who runs them (a
   * Model can't toggle a setting on a window or open a tab).
   *
   * Not a workspace thing: registered once per window, `context` stays
   * unset — see GoToLineProvider for why IWorkspaceExtension is here
   * at all.
   */
  public class CommandProvider : Object, IWorkspaceExtension, IProvider {
    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ">"; }
    }

    public string placeholder {
      owned get { return _("Type a command"); }
    }

    private GenericArray<Item> rows = new GenericArray<Item> ();
    private Picker? picker = null;

    /** `commands` are listed in the order given, until something is typed. */
    public CommandProvider (Command[] commands) {
      foreach (var command in commands) {
        rows.add (new Item (command.id, command.label));
      }
    }

    public void activate () {}

    public void deactivate () {
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      picker.empty_message = _("No matching commands");
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
