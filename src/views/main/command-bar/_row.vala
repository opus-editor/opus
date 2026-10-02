/**
 * One result row in the Command Bar's list: file icon, name with the
 * matched characters emphasized, dim directory. Group captions are the
 * list's own section headers (CommandBarPopoverSections), not part of
 * any row. Recycled by the list view's factory, same as
 * ExplorerPaneTreeRow. A click reports its position; the cursor/accept
 * decision is CommandBarPopover's.
 */
public class CommandBarPopoverRow : Object {
  private Gtk.Box box;
  private Gtk.Image icon;
  private Gtk.Label label;
  private Gtk.Label description;
  private IconTheme icon_theme;
  private uint position = 0;

  public Gtk.Widget widget { get { return box; } }

  /** Clicked — `position` is the list index this row was last bound to. */
  public signal void activated (uint position);

  public CommandBarPopoverRow (IconTheme icon_theme) {
    this.icon_theme = icon_theme;

    var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/main/command-bar/_row.ui");
    box = (Gtk.Box) builder.get_object ("row");
    icon = (Gtk.Image) builder.get_object ("icon");
    label = (Gtk.Label) builder.get_object ("label");
    description = (Gtk.Label) builder.get_object ("description");

    var click = new Gtk.GestureClick ();
    click.released.connect (() => activated (position));
    box.add_controller (click);
  }

  public void bind (CommandBar.Item item, uint position) {
    this.position = position;

    if (item.icon_name != null) {
      icon.set_from_resource (icon_theme.icon_path_for_file (item.icon_name));
      icon.visible = true;
    } else {
      icon.visible = false;
    }

    label.label = item.label;
    label.attributes = highlight_attributes (item.label, item.label_highlights);

    description.label = item.description ?? "";
    description.visible = item.description != null;
    description.attributes = highlight_attributes (item.description ?? "", item.description_highlights);
  }

  public void unbind () {
    label.attributes = null;
    description.attributes = null;
  }

  /** Bold + accent over each [start, end) character range — converted to the byte offsets Pango attributes actually index by. */
  private static Pango.AttrList? highlight_attributes (string text, int[] ranges) {
    if (ranges.length < 2) {
      return null;
    }
    var accent = Adw.StyleManager.get_default ().get_accent_color_rgba ();
    var attributes = new Pango.AttrList ();
    for (int i = 0; i + 1 < ranges.length; i += 2) {
      uint start = (uint) text.index_of_nth_char (ranges[i]);
      uint end = (uint) text.index_of_nth_char (ranges[i + 1]);

      var weight = Pango.attr_weight_new (Pango.Weight.BOLD);
      weight.start_index = start;
      weight.end_index = end;
      attributes.insert ((owned) weight);

      var color = Pango.attr_foreground_new ((uint16) (accent.red * 65535), (uint16) (accent.green * 65535), (uint16) (accent.blue * 65535));
      color.start_index = start;
      color.end_index = end;
      attributes.insert ((owned) color);
    }
    return attributes;
  }
}
