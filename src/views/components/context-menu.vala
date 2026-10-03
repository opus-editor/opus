/** See ContextMenu.item(). */
public delegate void MenuAction ();

/** See ContextMenu.popup_at(). */
public delegate void MenuBuilder (Gtk.Popover popover, Gtk.Box box);

/**
 * A small shared builder for the flat-button right-click menus used by
 * EditorView.FileTree, EditorView.TabBar, and CodeEditor — a plain
 * Gtk.Popover containing a vertical Gtk.Box of flat Gtk.Buttons and
 * Gtk.Separators, not Gtk.PopoverMenu/GLib.Menu+Gio.SimpleAction: nothing
 * else in this codebase uses that pattern, every interactive row/pill
 * here is plain widgets wired to signals, and a menu isn't reason enough
 * to introduce a whole new action-group convention just for itself.
 *
 * A real Gtk.Popover subclass — so it belongs in views/components/ (a
 * real, reusable widget) rather than views/lib/. popup_at() instantiates
 * one per call and throws it away once closed, hidden inside the static
 * method so every call site keeps one-call ergonomics (no `var menu`
 * needed).
 */
public class ContextMenu : Gtk.Popover {
  // A menu with only one or two short-word items (CodeEditor's own)
  // shrinks to fit its widest label and reads as oddly narrow; every
  // menu gets this same floor rather than each call site guessing its
  // own.
  private const int MIN_WIDTH = 124;

  private Gtk.Box box;

  public ContextMenu () {
    has_arrow = false;
    box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { width_request = MIN_WIDTH };
    child = box;
    closed.connect (() => unparent ());
  }

  /**
   * Builds a menu parented on `parent`, pointing at `(x, y)` (in
   * `parent`'s own coordinates), and shows it — `builder` fills in
   * `box` with whatever `item()`/`separator()` calls that particular
   * menu needs; the popover/box scaffolding itself is the same for
   * every menu, so only the actual item list varies per call site.
   */
  public static void popup_at (Gtk.Widget parent, double x, double y, owned MenuBuilder builder) {
    var menu = new ContextMenu ();
    menu.set_parent (parent);
    menu.set_pointing_to (Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 });

    builder (menu, menu.box);

    menu.popup ();
  }

  // 6px, matching AdwTabView's own dividers/spacing conventions elsewhere
  // in this codebase — a bare separator with no margin reads as glued to
  // its neighbors.
  public static Gtk.Widget separator () {
    var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
    separator.margin_top = 6;
    separator.margin_bottom = 6;
    return separator;
  }

  /**
   * A flat button styled as a menu row; `action` runs once `popover`
   * has popped down. `accel`, if given (build it with
   * `Gtk.accelerator_get_label (keyval, mods)`, not typed out by hand),
   * is shown as a dimmed hint on the right. `sensitive` false renders
   * it disabled and unclickable — for a menu item whose action doesn't
   * apply right now.
   */
  public static Gtk.Widget item (string label_text, owned MenuAction action, Gtk.Popover popover, string? accel = null, bool sensitive = true) {
    var button = new Gtk.Button () { sensitive = sensitive };
    // libadwaita's own button { font-weight: bold; } applies
    // unconditionally, .flat included — real popover menu items use a
    // different widget entirely (a legacy `modelbutton`, styled
    // separately) that never had this problem to begin with;
    // styles/context-menu.css undoes it for a plain Gtk.Button used the
    // same way.
    button.add_css_class ("flat");
    button.add_css_class ("opus-context-menu-item");

    var label = new Gtk.Label (label_text) { xalign = 0, hexpand = true };
    // Always a box, even with no accel: newer GTK gives a button whose
    // direct child is a label the `text-button` class, and its wider
    // padding would push that item out of line with the others.
    var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
    box.append (label);
    if (accel != null) {
      var accel_label = new Gtk.Label (accel) { xalign = 1 };
      accel_label.add_css_class ("dim-label");
      box.append (accel_label);
    }
    button.child = box;

    button.clicked.connect (() => {
      popover.popdown ();
      action ();
    });
    return button;
  }
}
