/**
 * One Gtk.TextTag per syntax style of the current EditorTheme, on one
 * buffer. Rebuilt whenever the theme changes — a different theme
 * defines different styles, not just different colors for the same
 * ones — so whoever painted with the old tags has to paint again on
 * {@link restyled}.
 */
public class SyntaxTags : Object {
  private Gtk.TextBuffer buffer;
  private HashTable<string, Gtk.TextTag> tags = new HashTable<string, Gtk.TextTag> (str_hash, str_equal);

  /** Every tag handed out before is gone from the buffer, and what it painted with it. */
  public signal void restyled ();

  public SyntaxTags (Gtk.TextBuffer buffer) {
    this.buffer = buffer;
    EditorTheme.instance.changed.connect (() => {
      rebuild ();
      restyled ();
    });
    rebuild ();
  }

  /** Null for a style the current theme doesn't define. */
  public Gtk.TextTag? tag_for (string style_key) {
    return tags[style_key];
  }

  /** The style key painted at `iter`, or null where nothing is. */
  public string? style_key_at (Gtk.TextIter iter) {
    foreach (unowned string key in tags.get_keys ()) {
      if (iter.has_tag (tags[key])) {
        return key;
      }
    }
    return null;
  }

  /** Unpaints `start` to `end`, leaving every tag that isn't a syntax one alone. */
  public void clear (Gtk.TextIter start, Gtk.TextIter end) {
    foreach (var tag in tags.get_values ()) {
      buffer.remove_tag (tag, start, end);
    }
  }

  private void rebuild () {
    foreach (var tag in tags.get_values ()) {
      buffer.tag_table.remove (tag);
    }
    tags.remove_all ();

    var theme = EditorTheme.instance.theme;
    foreach (unowned string key in theme.style_keys ()) {
      var tag = new Gtk.TextTag (null);
      apply (theme.style (key), tag);
      buffer.tag_table.add (tag);
      // Below every tag another part of the editor adds, whenever it
      // adds it: a selection, a search match or a link has to show
      // through whatever the code under it is colored.
      tag.set_priority (0);
      tags[key] = tag;
    }
  }

  private static void apply (ThemeStyle style, Gtk.TextTag tag) {
    if (style.foreground != null) {
      tag.foreground = style.foreground;
    }
    if (style.background != null) {
      tag.background = style.background;
    }
    if (style.bold) {
      tag.weight = Pango.Weight.BOLD;
    }
    if (style.italic) {
      tag.style = Pango.Style.ITALIC;
    }
    if (style.underline) {
      tag.underline = Pango.Underline.SINGLE;
    }
    if (style.strikethrough) {
      tag.strikethrough = true;
    }
  }
}
