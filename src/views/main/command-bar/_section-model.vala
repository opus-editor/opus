/**
 * The popover's list model: the picker's flat items, plus the section
 * boundaries Gtk.ListView needs to draw each group's caption as its own
 * header widget — outside any row, so selecting a group's first item
 * never highlights the caption with it. A section starts at every item
 * carrying a `separator_label` and runs to the next one; the cursor
 * itself stays a plain index over items, headers aren't items.
 */
public class CommandBarPopoverSections : Object, ListModel, Gtk.SectionModel {
  private GenericArray<CommandBar.Item> items = new GenericArray<CommandBar.Item> ();

  public Type get_item_type () {
    return typeof (CommandBar.Item);
  }

  public uint get_n_items () {
    return items.length;
  }

  public Object? get_item (uint position) {
    return position < items.length ? items[position] : null;
  }

  public void get_section (uint position, out uint out_start, out uint out_end) {
    if (position >= items.length) {
      out_start = items.length;
      out_end = uint.MAX;
      return;
    }
    uint start = position;
    while (start > 0 && items[start].separator_label == null) {
      start--;
    }
    uint end = position + 1;
    while (end < items.length && items[end].separator_label == null) {
      end++;
    }
    out_start = start;
    out_end = end;
  }

  public void replace_all (GenericArray<CommandBar.Item> new_items) {
    uint removed = items.length;
    items = new GenericArray<CommandBar.Item> ();
    for (uint i = 0; i < new_items.length; i++) {
      items.add (new_items[i]);
    }
    items_changed (0, removed, items.length);
  }
}
