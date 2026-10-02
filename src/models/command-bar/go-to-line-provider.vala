namespace CommandBar {
  /** Where the caret is right now — the host's own answer, read when the bar opens. `line` is 1-based. Returns false when there is no document to go to. */
  public delegate bool CaretPositionSource (out int line, out int line_count);

  /**
   * The `:` provider — VS Code's own "Go to Line": `:30` goes to line
   * 30, `:30:5` or `:30,5` to column 5 of it. One row, accepted by
   * Enter; MainWindow turns it into an EditorPane jump (a Model can't
   * touch the editor itself), decoding the row's `id` with decode().
   * Not a workspace thing: registered once per window, `context` stays
   * unset — IWorkspaceExtension is only here because IProvider requires
   * it for the plugin-contributed providers' sake.
   */
  public class GoToLineProvider : Object, IWorkspaceExtension, IProvider {
    public WorkspaceContext context { get; set; }

    public string prefix {
      owned get { return ":"; }
    }

    public string placeholder {
      owned get { return _("Type a line number"); }
    }

    private CaretPositionSource caret_position;
    private Regex target_pattern;
    private Picker? picker = null;

    public GoToLineProvider (owned CaretPositionSource caret_position) {
      this.caret_position = (owned) caret_position;
      try {
        target_pattern = new Regex ("^([0-9]+)(?:[:,]([0-9]*))?$");
      } catch (RegexError e) {
        assert_not_reached ();
      }
    }

    public void activate () {}

    public void deactivate () {
      detach_picker ();
    }

    public void provide (Picker picker, Cancellable cancellable) {
      this.picker = picker;
      picker.filter_changed.connect (on_filter_changed);
      picker.closed.connect (detach_picker);
      update ();
    }

    /** The 1-based line and 0-based column an accepted row's `id` stands for — the same convention EditorPane.open_at() takes. */
    public static void decode (string id, out int line, out int column) {
      var parts = id.split (":");
      line = int.parse (parts[0]);
      column = parts.length > 1 ? int.parse (parts[1]) : 0;
    }

    private void on_filter_changed () {
      update ();
    }

    private void update () {
      var items = new GenericArray<Item> ();
      if (picker.filter == "") {
        picker.empty_message = current_position_hint ();
        picker.set_items (items);
        return;
      }

      int line, column;
      if (!parse (picker.filter, out line, out column)) {
        picker.empty_message = _("Type a line number, e.g. 30 or 30:5");
        picker.set_items (items);
        return;
      }

      var label = column > 0
        ? _("Go to line %d, column %d").printf (line, column)
        : _("Go to line %d").printf (line);
      items.add (new Item ("%d:%d".printf (line, int.max (column - 1, 0)), label));
      picker.set_items (items);
    }

    /** `column` is as typed (1-based), 0 when absent. False for anything that isn't a line number of at least 1. */
    private bool parse (string filter, out int line, out int column) {
      line = 0;
      column = 0;
      MatchInfo match;
      if (!target_pattern.match (filter, 0, out match)) {
        return false;
      }
      line = int.parse (match.fetch (1));
      var column_text = match.fetch (2);
      column = column_text == null || column_text == "" ? 0 : int.parse (column_text);
      return line >= 1;
    }

    private string current_position_hint () {
      int line, line_count;
      if (!caret_position (out line, out line_count)) {
        return _("Open a file to go to a line");
      }
      return _("Current line %d of %d — type a line number").printf (line, line_count);
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
