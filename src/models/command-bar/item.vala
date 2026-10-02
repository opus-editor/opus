namespace CommandBar {
  /**
   * One row the Command Bar can show: plain data a provider fills in and
   * the view renders — a GObject so the view's list store can hold it
   * directly. `id` is whatever the provider needs back on accept (a
   * path, a command name); highlight ranges are [start, end) character
   * offsets into the text they belong to.
   */
  public class Item : Object {
    public string id { get; set; }
    public string label { get; set; }
    public string? description { get; set; default = null; }
    public int[] label_highlights;
    public int[] description_highlights;

    /** A file name for icon lookup, or null for no icon. */
    public string? icon_name { get; set; default = null; }

    /** A caption drawn above this row ("recently opened", "files") — set on the first row of a group only. */
    public string? separator_label { get; set; default = null; }

    public Item (string id, string label) {
      this.id = id;
      this.label = label;
      label_highlights = {};
      description_highlights = {};
    }
  }
}
