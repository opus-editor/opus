/**
 * A single tab in the {@link EditorView.TabBar}'s row: a title showing the
 * file name and, smaller and italic, its parent folder name; a close button
 * that's always clickable; and italic styling for the whole label while
 * the tab is a preview. Selection and double-click are reported via
 * signals; this widget knows nothing about `EditorView.TabBar` — that class
 * translates its signals into its own, keyed by path.
 */
namespace EditorView.EditorPane {
  public class TabBarPill : Object {
    private Gtk.Box box;
    private Gtk.Label title_label;
    private Gtk.Button close_button;

    public Gtk.Widget widget { get { return box; } }

    /** Single click — makes this tab active. */
    public signal void selected ();

    /** Double click — promotes a preview tab to permanent. */
    public signal void double_clicked ();

    /** The close button was clicked. Always emitted; the button is never disabled. */
    public signal void close_requested ();

    /** Right click — open this tab's context menu at `(x, y)`, in this pill's own widget coordinates. */
    public signal void context_menu_requested (double x, double y);

    // Read-only outside this class — exposed so a ghost copy (see
    // _ghost.vala) can be built with the same label/state without this
    // pill needing to know dragging is even happening. Named is_preview/
    // is_modified, not preview/modified: those would collide with the
    // set_preview()/set_modified() methods below.
    public string file_name { get; private set; default = ""; }
    public string folder_name { get; private set; default = ""; }
    public bool is_preview { get; private set; default = false; }
    public bool is_modified { get; private set; default = false; }
    public bool is_deleted { get; private set; default = false; }
    public bool is_unsynchronized { get; private set; default = false; }

    /** This tab's own clean, user-facing name (a real file's real path, or a synthetic tab's plain display name) — TabBar's tooltip source, remembered here so mark_deleted()/mark_unsynchronized() can recompute it later without needing it passed in again. Plain get/set: unlike file_name/folder_name/is_deleted/etc., storing this has no rendering side effect of its own for set_label()-style wrapping to trigger. */
    public string tooltip_path { get; set; default = ""; }

    /** Whether this tab is backed by a real on-disk path right now — a synthetic tab (Untitled-N, Find Results) has nothing for "Copy Path"/"Reveal in Sidebar" to point at, so its context menu leaves them out. Same plain get/set reasoning as tooltip_path. */
    public bool has_pathname { get; set; default = false; }

    public TabBarPill () {
      var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/editor-view/editor-pane/tab-bar/_pill.ui");
      box = (Gtk.Box) builder.get_object ("pill");
      title_label = (Gtk.Label) builder.get_object ("title_label");
      close_button = (Gtk.Button) builder.get_object ("close_button");

      var click = new Gtk.GestureClick ();
      click.pressed.connect ((n_press, x, y) => {
        if (n_press == 1) {
          selected ();
        } else if (n_press == 2) {
          double_clicked ();
        }
      });
      box.add_controller (click);

      var right_click = new Gtk.GestureClick ();
      right_click.set_button (Gdk.BUTTON_SECONDARY);
      right_click.pressed.connect ((n_press, x, y) => context_menu_requested (x, y));
      box.add_controller (right_click);

      close_button.clicked.connect (() => close_requested ());
    }

    /** `folder_name` is the file's immediate parent directory name, or "" if it has none. */
    public void set_label (string file_name, string folder_name) {
      this.file_name = file_name;
      this.folder_name = folder_name;
      refresh_label ();
    }

    public void set_active (bool active) {
      if (active) {
        box.add_css_class ("active");
      } else {
        box.remove_css_class ("active");
      }
    }

    public void set_preview (bool preview) {
      is_preview = preview;
      refresh_label ();
    }

    public void set_modified (bool modified) {
      is_modified = modified;
      refresh_label ();
    }

    /** The file this tab was opened from was deleted (or moved away) outside Opus. */
    public void set_deleted (bool deleted) {
      is_deleted = deleted;
      refresh_label ();
    }

    /** The file this tab was opened from changed on disk while the "File Has Changed on Disk" banner's own choice is still unresolved — stays true whether or not the banner itself is currently showing. */
    public void set_unsynchronized (bool unsynchronized) {
      is_unsynchronized = unsynchronized;
      refresh_label ();
    }

    /** A plugin's own decoration for this tab's file (git status, a future linter badge, …), or null with nothing to show — tints the label text itself, not appended text like is_modified/is_deleted above. Same shared `git-*` CSS vocabulary and toggle-by-switch technique as ExplorerPaneTreeRow.update_decoration(). */
    public void set_decoration (FileDecoration.State? decoration) {
      title_label.remove_css_class ("tone-accent");
      title_label.remove_css_class ("git-added");
      title_label.remove_css_class ("git-modified");
      title_label.remove_css_class ("git-conflict");
      title_label.remove_css_class ("git-removed");

      if (decoration == null) {
        return;
      }

      switch (decoration.tone) {
        case FileDecoration.Tone.ACCENT:
          title_label.add_css_class ("tone-accent");
          break;
        case FileDecoration.Tone.SUCCESS:
          title_label.add_css_class ("git-added");
          break;
        case FileDecoration.Tone.WARNING:
          title_label.add_css_class ("git-modified");
          break;
        case FileDecoration.Tone.ALERT:
          title_label.add_css_class ("git-conflict");
          break;
        case FileDecoration.Tone.ERROR:
          title_label.add_css_class ("git-removed");
          break;
        default:
          break;
      }
    }

    private void refresh_label () {
      var file_part = Markup.escape_text (file_name);
      // The same dot already used for "unsaved changes" — an
      // unsynchronized tab needs attention exactly the same way a
      // dirty one does, so it reuses that same marker rather than
      // adding a second, differently-colored one next to it.
      if (is_modified || is_unsynchronized) {
        file_part = "%s •".printf (file_part);
      }
      if (is_preview) {
        file_part = "<i>%s</i>".printf (file_part);
      }
      if (is_deleted) {
        file_part = "<s>%s</s>".printf (file_part);
      }

      var text = file_part;
      if (folder_name != "") {
        text += " <span style=\"italic\" size=\"smaller\" alpha=\"50%%\">%s</span>".printf (Markup.escape_text (folder_name));
      }

      title_label.label = text;
    }
  }
}
