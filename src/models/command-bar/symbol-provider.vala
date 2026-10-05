namespace CommandBar {
  /** What the host knows of the active document's symbols when the bar opens. */
  public class DocumentSymbols : Object {
    public Syntax.Symbol[] symbols;
    /** False for a language that has no way to list symbols — not the same as a file with none. */
    public bool listable;
    /** False while the document is still being read: its symbols aren't known yet. */
    public bool ready;
    /** The 1-based line the caret is on. */
    public int caret_line;

    public DocumentSymbols (Syntax.Symbol[] symbols, bool listable, bool ready, int caret_line) {
      this.symbols = symbols;
      this.listable = listable;
      this.ready = ready;
      this.caret_line = caret_line;
    }
  }

  /** The host's own answer, read when the bar opens. Null when there is no document to list the symbols of. */
  public delegate DocumentSymbols? SymbolSource ();

  /**
   * The `#` provider — VS Code's own "Go to Symbol in Editor" (its
   * `@`): the active document's definitions in the order they appear,
   * narrowed by what is typed. A row's `id` is where its name is, in
   * GoToLineProvider's own format; MainWindow turns it into the jump,
   * and into a preview of the row under the cursor. Registered once
   * per window, like GoToLineProvider.
   */
  public class SymbolProvider : Object, IWorkspaceExtension, IProvider {
    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return "#"; }
    }

    public string placeholder {
      owned get { return _("Type the name of a symbol"); }
    }

    private SymbolSource source;
    private Picker? picker = null;
    private GenericArray<Item> rows = new GenericArray<Item> ();
    // The row to start on with nothing typed: the symbol the caret is in.
    private int caret_row = 0;

    public SymbolProvider (owned SymbolSource source) {
      this.source = (owned) source;
    }

    public void activate () {}

    public void deactivate () {
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      read_symbols ();
      picker.filter_changed.connect (on_filter_changed);
      picker.closed.connect (detach_picker);
      update ();
    }

    /** The 1-based line and 0-based column an accepted row's `id` stands for — the same convention EditorPane.go_to_line() takes. */
    public static void decode (string id, out int line, out int column) {
      GoToLineProvider.decode (id, out line, out column);
    }

    private void read_symbols () {
      rows = new GenericArray<Item> ();
      caret_row = 0;
      var document = source ();
      if (document == null) {
        picker.empty_message = _("Open a file to go to a symbol");
        return;
      }
      if (!document.listable) {
        picker.empty_message = _("No symbols for this language");
        return;
      }
      if (!document.ready) {
        picker.empty_message = _("Still reading this file");
        return;
      }

      foreach (var symbol in document.symbols) {
        // The last one holding the caret is the innermost: they come in document order.
        if (symbol.first_line <= document.caret_line && document.caret_line <= symbol.last_line) {
          caret_row = (int) rows.length;
        }
        rows.add (row_for (symbol));
      }
      picker.empty_message = rows.length == 0 ? _("No symbols in this file") : _("No matching symbols");
    }

    private static Item row_for (Syntax.Symbol symbol) {
      var row = new Item ("%d:%d".printf (symbol.line, symbol.column), symbol.name);
      row.description = symbol.container == "" ? symbol.kind : "%s · %s".printf (symbol.kind, symbol.container);
      return row;
    }

    private void on_filter_changed () {
      update ();
    }

    private void update () {
      if (picker.filter == "") {
        picker.set_items (rows, caret_row);
        return;
      }
      picker.set_items (ItemFilter.narrow (rows, picker.filter));
    }

    private void detach_picker () {
      if (picker == null) {
        return;
      }
      picker.filter_changed.disconnect (on_filter_changed);
      picker.closed.disconnect (detach_picker);
      picker = null;
    }
  }
}
