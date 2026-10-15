/**
 * One Gtk.TextTag per (language, capture) painted on one buffer,
 * created the first time it is asked for and never removed: a tag's
 * identity is what the text is, the theme only decides how it looks.
 * On a theme change every tag is restyled in place, and
 * {@link repaint_needed} fires only when the theme moved a capture
 * between styled and unstyled, since only then can the spans
 * themselves come out different (see Syntax.Languages.set_style_keys).
 *
 * Removing a tag from the table is the one thing never done here:
 * each removal walks the whole buffer and renumbers every other tag,
 * seconds on a buffer the size of a Find Results listing.
 */
public class SyntaxTags : Object {
  private class Entry : Object {
    public string capture;
    public string? language;
    public Gtk.TextTag tag;
    // The theme key the tag wears right now, null while the theme styles nothing for it.
    public string? style_key;
  }

  private Gtk.TextBuffer buffer;
  private HashTable<string, Entry> by_identity = new HashTable<string, Entry> (str_hash, str_equal);
  private HashTable<Gtk.TextTag, Entry> by_tag = new HashTable<Gtk.TextTag, Entry> (direct_hash, direct_equal);
  private ulong theme_handler;

  /** The theme moved a capture between styled and unstyled, so where spans begin and end may have changed: paint again. Every tag has already been restyled. */
  public signal void repaint_needed ();

  public SyntaxTags (Gtk.TextBuffer buffer) {
    this.buffer = buffer;
    theme_handler = EditorTheme.instance.changed.connect (on_theme_changed);
  }

  /** Stops following the theme — for a buffer on its way out. */
  public void close () {
    EditorTheme.instance.disconnect (theme_handler);
  }

  /** The tag for `capture` as `language` paints it (any language, with none) — made on first request, unstyled while the theme defines nothing for it. */
  public Gtk.TextTag tag_for (string capture, string? language = null) {
    var identity = identity_of (capture, language);
    var entry = by_identity[identity];
    if (entry == null) {
      entry = create (capture, language);
      by_identity[identity] = entry;
      by_tag[entry.tag] = entry;
    }
    return entry.tag;
  }

  /** The theme key painted at `iter`, or null where no syntax tag is, or one the theme leaves unstyled. */
  public string? style_key_at (Gtk.TextIter iter) {
    foreach (unowned Gtk.TextTag tag in iter.get_tags ()) {
      var entry = by_tag[tag];
      if (entry != null) {
        return entry.style_key;
      }
    }
    return null;
  }

  /** Unpaints `start` to `end`, leaving every tag that isn't a syntax one alone. */
  public void clear (Gtk.TextIter start, Gtk.TextIter end) {
    foreach (var entry in by_identity.get_values ()) {
      buffer.remove_tag (entry.tag, start, end);
    }
  }

  // The theme's own `lang:capture` spelling, only because ":" is the one
  // separator neither part can contain (Syntax.CaptureStyles.can_have_styles);
  // a key of this table, never one looked up in the theme.
  private static string identity_of (string capture, string? language) {
    return language == null ? capture : Syntax.CaptureStyles.language_key (language, capture);
  }

  private Entry create (string capture, string? language) {
    var entry = new Entry ();
    entry.capture = capture;
    entry.language = language;
    entry.tag = new Gtk.TextTag (null);
    restyle (entry);
    buffer.tag_table.add (entry.tag);
    // Below every tag another part of the editor adds, whenever it
    // adds it: a selection, a search match or a link has to show
    // through whatever the code under it is colored.
    entry.tag.set_priority (0);
    return entry;
  }

  private void on_theme_changed () {
    foreach (var entry in by_identity.get_values ()) {
      restyle (entry);
    }
    if (EditorTheme.instance.styled_captures_changed) {
      repaint_needed ();
    }
  }

  private static void restyle (Entry entry) {
    entry.style_key = Syntax.Languages.instance.resolve_style (entry.capture, entry.language);
    reset (entry.tag);
    if (entry.style_key != null) {
      apply (EditorTheme.instance.theme.style (entry.style_key), entry.tag);
    }
  }

  // Each property set is a tag-changed emission, and weight/style
  // invalidate the layout under the tag: only unset what is set.
  private static void reset (Gtk.TextTag tag) {
    if (tag.foreground_set) {
      tag.foreground_set = false;
    }
    if (tag.background_set) {
      tag.background_set = false;
    }
    if (tag.weight_set) {
      tag.weight_set = false;
    }
    if (tag.style_set) {
      tag.style_set = false;
    }
    if (tag.underline_set) {
      tag.underline_set = false;
    }
    if (tag.strikethrough_set) {
      tag.strikethrough_set = false;
    }
  }

  private static void apply (ThemeStyle? style, Gtk.TextTag tag) {
    if (style == null) {
      return;
    }
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
