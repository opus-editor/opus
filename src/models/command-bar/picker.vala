namespace CommandBar {
  /**
   * The state of one Command Bar opening — VS Code's own QuickPick split
   * from the widget that draws it: what was typed, which rows show,
   * which one the cursor is on, and the accept/close outcome. Providers
   * fill `items` and listen for `accepted`; the view mirrors it and
   * drives it from keys. Neither side knows the other.
   *
   * `active_index` is a cursor, not keyboard focus: focus never leaves
   * the text entry, the list only shows which row Enter would accept.
   */
  public class Picker : Object {
    public string prefix { get; construct; }
    public string placeholder { get; set; default = ""; }
    /** What the view shows in place of the rows while there are none — the provider's own wording ("Type to search files", "No matching files", …). */
    public string empty_message { get; set; default = ""; }
    public bool busy { get; set; default = false; }
    public int active_index { get; private set; default = -1; }
    public bool is_closed { get; private set; default = false; }

    private GenericArray<Item> _items = new GenericArray<Item> ();
    public GenericArray<Item> items {
      get { return _items; }
    }

    private string _text = "";
    public string text {
      get { return _text; }
      set { apply_text (value); }
    }

    /** `text` minus this picker's own prefix, trimmed — the part a provider actually searches for. */
    public string filter { get; private set; default = ""; }

    public signal void filter_changed (string filter);
    public signal void items_changed ();
    public signal void active_changed (int index);
    public signal void accepted (Item item);
    public signal void closed ();

    public Picker (string prefix) {
      Object (prefix: prefix);
    }

    private void apply_text (string value) {
      if (_text == value) {
        return;
      }
      _text = value;
      var next_filter = (value.has_prefix (prefix) ? value.substring (prefix.length) : value).strip ();
      if (next_filter != filter) {
        filter = next_filter;
        filter_changed (filter);
      }
    }

    /** Replaces every row; `active` is the cursor's new position, clamped (-1 when there are no rows at all). */
    public void set_items (GenericArray<Item> items, int active = 0) {
      _items = items;
      items_changed ();
      set_active (active);
    }

    public void set_active (int index) {
      int clamped = items.length == 0 ? -1 : index.clamp (0, (int) items.length - 1);
      if (clamped == active_index) {
        return;
      }
      active_index = clamped;
      active_changed (active_index);
    }

    /** Moves the cursor by `delta` rows, wrapping around at both ends. */
    public void move_active (int delta) {
      if (items.length == 0) {
        return;
      }
      int count = (int) items.length;
      int next = ((active_index + delta) % count + count) % count;
      set_active (next);
    }

    /** Moves the cursor by a page of `rows` in `direction` (±1), stopping at the ends rather than wrapping. */
    public void move_active_by_page (int rows, int direction) {
      if (items.length == 0) {
        return;
      }
      set_active (active_index + rows * (direction < 0 ? -1 : 1));
    }

    public void move_active_to_first () {
      set_active (0);
    }

    public void move_active_to_last () {
      set_active ((int) items.length - 1);
    }

    /** Emits `accepted` for the row under the cursor — a no-op with no rows. Closing afterwards is the listener's decision. */
    public void accept () {
      if (active_index < 0 || active_index >= items.length) {
        return;
      }
      accepted (items[active_index]);
    }

    public void close () {
      if (is_closed) {
        return;
      }
      is_closed = true;
      closed ();
    }
  }
}
