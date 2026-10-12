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

  /** The active document's state, for the function rows — false with no document open at all. */
  public delegate bool DocumentStateSource (out string? language, out bool has_selection);

  /**
   * The `>` provider — VS Code's own Command Palette: a list of things
   * the app can do, narrowed by what is typed after the `>`. Two
   * groups: the commands it was built with, then the functions
   * (src/models/functions/) listed for the active document's language —
   * while something is selected every `Selection > Name` first, being
   * the special case, then every `File > Name`, each by name — read
   * from the registry when the list opens, which is also when the
   * registry is first scanned. It lists and nothing
   * more: an accepted row carries an id, and whoever built the
   * provider is who runs it (a Model can't toggle a setting on a window
   * or rewrite a tab's text).
   *
   * Not a workspace thing: registered once per window, `context` stays
   * unset — see GoToLineProvider for why IWorkspaceExtension is here
   * at all.
   */
  public class CommandProvider : Object, IWorkspaceExtension, IProvider {
    public const string FUNCTION_ON_SELECTION = "function:selection:";
    public const string FUNCTION_ON_DOCUMENT = "function:document:";

    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ">"; }
    }

    public string placeholder {
      owned get { return _("Type a command"); }
    }

    private GenericArray<Item> commands = new GenericArray<Item> ();
    private GenericArray<Item> rows = new GenericArray<Item> ();
    private Functions.Registry? registry;
    private DocumentStateSource? document_state;
    private Picker? picker = null;

    /** `commands` are listed in the order given, until something is typed; the functions follow them, by name. */
    public CommandProvider (Command[] commands, Functions.Registry? registry = null, owned DocumentStateSource? document_state = null) {
      foreach (var command in commands) {
        this.commands.add (new Item (command.id, command.label));
      }
      this.registry = registry;
      this.document_state = (owned) document_state;
    }

    /** Whether `id` is a function row's, and which way it was picked. */
    public static bool decode_function (string id, out string function_id, out bool on_selection) {
      function_id = "";
      on_selection = id.has_prefix (FUNCTION_ON_SELECTION);
      if (on_selection) {
        function_id = id.substring (FUNCTION_ON_SELECTION.length);
        return true;
      }
      if (id.has_prefix (FUNCTION_ON_DOCUMENT)) {
        function_id = id.substring (FUNCTION_ON_DOCUMENT.length);
        return true;
      }
      return false;
    }

    public void activate () {}

    public void deactivate () {
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      picker.empty_message = _("No matching commands");
      rows = new GenericArray<Item> ();
      foreach (var command in commands) {
        rows.add (command);
      }
      foreach (var row in function_rows ()) {
        rows.add (row);
      }
      picker.filter_changed.connect (update);
      picker.closed.connect (detach_picker);
      update ();
    }

    private GenericArray<Item> function_rows () {
      var found = new GenericArray<Item> ();
      if (registry == null || document_state == null) {
        return found;
      }
      string? language;
      bool has_selection;
      if (!document_state (out language, out has_selection)) {
        return found;
      }
      if (!registry.loaded) {
        registry.reload ();
      }
      var functions = registry.for_language (language);
      if (has_selection) {
        foreach (var function in functions) {
          if (function.input != Functions.Scope.DOCUMENT) {
            found.add (new Item (FUNCTION_ON_SELECTION + function.id, _("Selection > %s").printf (function.name)) { description = description_of (function) });
          }
        }
      }
      foreach (var function in functions) {
        if (function.input != Functions.Scope.SELECTION) {
          found.add (new Item (FUNCTION_ON_DOCUMENT + function.id, _("File > %s").printf (function.name)) { description = description_of (function) });
        }
      }
      return found;
    }

    private static string? description_of (Functions.Function function) {
      return function.description == "" ? null : function.description;
    }

    /** The narrowed rows, each group captioned at its first row — only when both groups show, the way the file list captions "recently opened" and "files". */
    private void update () {
      var narrowed = ItemFilter.narrow (rows, picker.filter);
      Item? first_command = null;
      Item? first_function = null;
      foreach (var item in narrowed) {
        item.separator_label = null;
        if (item.id.has_prefix ("function:")) {
          first_function = first_function ?? item;
        } else {
          first_command = first_command ?? item;
        }
      }
      if (first_command != null && first_function != null) {
        first_command.separator_label = _("commands");
        first_function.separator_label = _("functions");
      }
      picker.set_items (narrowed);
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
