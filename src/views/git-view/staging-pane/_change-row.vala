/**
 * A single row in a ChangeList: an icon, the file's own name followed by
 * its dimmed containing directory (same markup idiom as TabBar.Pill's
 * own title_label — a Pango span, not a second label, so ellipsize
 * still runs over the whole thing as one unit), a tooltip with the
 * file's full relative path followed by its status word
 * (GitScope.Change.label — "src/a.vala · Modified"), and the status
 * letters: one (A/M/D/R/C/T/U) colored by GitScope.ChangeKind, or for
 * a conflict git's own two-letter code (Change.conflict_code — UU, DU,
 * …) with each letter in the color of what it means — the same four
 * tone classes ExplorerPaneTreeRow's own update_decoration() groups
 * into, reused directly rather than reinvented, just as text color
 * instead of a dot's background (see staging-pane.css's own
 * .change-decoration-letter rules, and StagingPane's own
 * apply_decoration_font() for why it's a Gtk.Label, not a plain
 * Gtk.Box, in the first place). Recycled by the list view's factory,
 * same as ExplorerPaneTreeRow.
 */
namespace GitView {
  public class ChangeRow : Object {
    private Gtk.Box box;
    private Gtk.Image icon;
    private Gtk.Label label;
    private Gtk.Label decoration_letter;
    private Gtk.Label decoration_letter_2;
    private IconTheme icon_theme;

    public Gtk.Widget widget { get { return box; } }

    /** What bind() last showed — ChangeList's own right-click hit test reads it back off the row under the pointer. */
    public GitScope.Change? bound_change { get; private set; default = null; }

    public ChangeRow (IconTheme icon_theme) {
      this.icon_theme = icon_theme;

      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/git-view/staging-pane/_change-row.ui");
      box = (Gtk.Box) builder.get_object ("row");
      icon = (Gtk.Image) builder.get_object ("icon");
      label = (Gtk.Label) builder.get_object ("label");
      decoration_letter = (Gtk.Label) builder.get_object ("decoration_letter");
      decoration_letter_2 = (Gtk.Label) builder.get_object ("decoration_letter_2");
    }

    /** `root_path` strips down to the relative path the tooltip and the dimmed directory part both show — change.path itself stays absolute (GitScope.Change's own doc comment). */
    public void bind (GitScope.Change change, string root_path) {
      bound_change = change;
      var relative_path = change.path.substring (root_path.length + 1);
      var name = Path.get_basename (relative_path);
      var directory = Path.get_dirname (relative_path);

      icon.set_from_resource (icon_theme.icon_path_for_file (name));
      // tooltip_text is plain text, not Pango markup — "·" (U+00B7) is
      // the real character, not the "&middot;" entity it'd take to
      // write this in markup.
      box.tooltip_text = "%s · %s".printf (relative_path, change.label);

      var text = Markup.escape_text (name);
      if (directory != ".") {
        text += " <span style=\"italic\" size=\"smaller\" alpha=\"50%%\">%s</span>".printf (Markup.escape_text (directory));
      }
      label.label = text;

      if (change.kind.is_conflict ()) {
        show_conflict_code (change.conflict_code);
      } else {
        update_decoration (change.kind);
      }
    }

    /** `code` is git's own XY pair — U reads as a conflict, D as a removal, A as an addition, each letter on its own. */
    private void show_conflict_code (string code) {
      decoration_letter_2.visible = true;
      set_letter (decoration_letter, code[0]);
      set_letter (decoration_letter_2, code[1]);
    }

    private static void set_letter (Gtk.Label label, char letter) {
      clear_tone (label);
      label.label = letter.to_string ();
      switch (letter) {
        case 'D': label.add_css_class ("git-removed"); break;
        case 'A': label.add_css_class ("git-added"); break;
        default: label.add_css_class ("git-conflict"); break;
      }
    }

    private static void clear_tone (Gtk.Label label) {
      label.remove_css_class ("git-added");
      label.remove_css_class ("git-modified");
      label.remove_css_class ("git-conflict");
      label.remove_css_class ("git-removed");
    }

    private void update_decoration (GitScope.ChangeKind kind) {
      decoration_letter_2.visible = false;
      clear_tone (decoration_letter);
      decoration_letter.label = kind.code ();

      switch (kind) {
        case GitScope.ChangeKind.ADDED:
        case GitScope.ChangeKind.UNTRACKED:
          decoration_letter.add_css_class ("git-added");
          break;
        case GitScope.ChangeKind.DELETED:
          decoration_letter.add_css_class ("git-removed");
          break;
        default: // MODIFIED, RENAMED, COPIED, TYPE_CHANGED
          decoration_letter.add_css_class ("git-modified");
          break;
      }
    }
  }
}
