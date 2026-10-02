/**
 * The Command Bar's own widgets: a frameless text entry meant to stand
 * in the header's title slot (where the view switcher normally sits —
 * MainWindow does the swap) and a popover below it listing a
 * {@link CommandBar.Picker}'s items. Mirrors the picker it's bound to
 * and drives it from keys; it decides nothing about what the rows are
 * or what accepting one does.
 *
 * Keyboard focus stays in the entry the whole time — the list is a
 * cursor (`Picker.active_index`) the entry moves, rows aren't focusable,
 * and the popover doesn't autohide (which would take focus). Losing the
 * entry's focus for any other reason is what dismisses the bar.
 */
public class CommandBarPopover : Object, IGlobalPanel {
  private const int PAGE_ROWS = 10;

  private Adw.Clamp clamp;
  private Gtk.Box entry_box;
  private Gtk.Text entry;
  private Gtk.Spinner spinner;
  private Gtk.Popover results_popover;
  private Gtk.Stack content_stack;
  private Gtk.Label empty_label;
  private Gtk.ListView list_view;
  private ListStore store = new ListStore (typeof (CommandBar.Item));
  private Gtk.SingleSelection selection;
  private IconTheme icon_theme;

  private CommandBar.Picker? picker = null;
  private bool shown = false;

  // Keeps the popover's content exactly as wide as the entry for as
  // long as the bar is shown — re-checked every frame, since there's
  // no allocation signal to hook and the entry's width changes with
  // the window's. Zero while not running.
  private uint popover_width_tick_id = 0;
  private int synced_entry_width = -1;

  // Set while this class itself writes entry.text (mirroring a picker),
  // so the entry's own `changed` doesn't echo that straight back.
  private bool syncing_text = false;

  public Gtk.Widget widget { get { return clamp; } }

  public bool is_open { get { return shown; } }

  /** The bar stopped being shown — Escape, focus leaving the entry, or close() from outside. Whoever owns the Router closes it on this. */
  public signal void closed ();

  public CommandBarPopover (IconTheme icon_theme) {
    this.icon_theme = icon_theme;

    var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/main/command-bar/index.ui");
    clamp = (Adw.Clamp) builder.get_object ("clamp");
    entry_box = (Gtk.Box) builder.get_object ("entry_box");
    entry = (Gtk.Text) builder.get_object ("entry");
    spinner = (Gtk.Spinner) builder.get_object ("spinner");
    results_popover = (Gtk.Popover) builder.get_object ("results_popover");
    content_stack = (Gtk.Stack) builder.get_object ("content_stack");
    empty_label = (Gtk.Label) builder.get_object ("empty_label");
    list_view = (Gtk.ListView) builder.get_object ("list_view");

    results_popover.set_parent (entry_box);

    selection = new Gtk.SingleSelection (store) {
      autoselect = false,
      can_unselect = true,
    };
    selection.notify["selected"].connect (on_selection_changed);
    list_view.model = selection;

    var factory = new Gtk.SignalListItemFactory ();
    factory.setup.connect (on_setup);
    factory.bind.connect (on_bind);
    factory.unbind.connect (on_unbind);
    list_view.factory = factory;

    entry.changed.connect (() => {
      if (!syncing_text && picker != null) {
        picker.text = entry.text;
      }
    });
    entry.activate.connect (() => picker?.accept ());

    // CAPTURE: runs before Gtk.Text's own bindings get a say, so Up/
    // Down/Tab never reach them at all.
    var key_controller = new Gtk.EventControllerKey ();
    key_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
    key_controller.key_pressed.connect (on_key_pressed);
    entry.add_controller (key_controller);

    var focus_controller = new Gtk.EventControllerFocus ();
    focus_controller.leave.connect (() => close ());
    entry.add_controller (focus_controller);
  }

  /** Mirrors `picker` from now on — called for every picker a Router opens, including a replacement when the provider switches mid-typing. */
  public void bind (CommandBar.Picker picker) {
    unbind ();
    this.picker = picker;

    syncing_text = true;
    entry.text = picker.text;
    syncing_text = false;
    entry.placeholder_text = picker.placeholder;

    picker.items_changed.connect (on_items_changed);
    picker.active_changed.connect (on_active_changed);
    picker.notify["busy"].connect (on_busy_changed);
    on_items_changed ();
    on_busy_changed ();
  }

  private void unbind () {
    if (picker == null) {
      return;
    }
    picker.items_changed.disconnect (on_items_changed);
    picker.active_changed.disconnect (on_active_changed);
    picker.notify["busy"].disconnect (on_busy_changed);
    picker = null;
  }

  /** Shows the bar and puts the caret after the prefix with the rest selected, so typing replaces the query but keeps the mode. */
  public void open () {
    if (shown) {
      return;
    }
    shown = true;
    results_popover.popup ();
    synced_entry_width = -1;
    popover_width_tick_id = entry_box.add_tick_callback (() => {
      sync_popover_width ();
      return Source.CONTINUE;
    });
    entry.grab_focus_without_selecting ();
    int prefix_length = picker != null ? picker.prefix.char_count () : 0;
    entry.select_region (prefix_length, -1);
  }

  public void close () {
    if (!shown) {
      return;
    }
    shown = false;
    stop_syncing_popover_width ();
    results_popover.popdown ();
    unbind ();
    closed ();
  }

  /** Replaces the entry's text as typing would — Opus.Dev.DevServer's way in; exercises the same `changed` path a real keystroke does. */
  public void set_text (string text) {
    entry.text = text;
  }

  /** What Return does — Opus.Dev.DevServer's way in. */
  public void accept () {
    picker?.accept ();
  }

  /** Unparents the popover — the one child here GTK won't tear down with the window on its own. Called from MainWindow's destroy handler. */
  public void destroy () {
    stop_syncing_popover_width ();
    results_popover.unparent ();
  }

  /** The popover window itself is wider than what it shows (its shadow margins live inside its allocation), so the width that must match the entry is its content's, not the popover's. */
  private void sync_popover_width () {
    int width = entry_box.get_width ();
    if (width <= 0 || width == synced_entry_width) {
      return;
    }
    synced_entry_width = width;
    content_stack.width_request = width;
  }

  private void stop_syncing_popover_width () {
    if (popover_width_tick_id != 0) {
      entry_box.remove_tick_callback (popover_width_tick_id);
      popover_width_tick_id = 0;
    }
  }

  private void on_items_changed () {
    store.remove_all ();
    for (uint i = 0; i < picker.items.length; i++) {
      store.append (picker.items[i]);
    }
    if (store.get_n_items () == 0) {
      empty_label.label = picker.filter == "" ? _("Type to search files") : _("No matching files");
      content_stack.visible_child_name = "empty";
    } else {
      content_stack.visible_child_name = "list";
    }
    on_active_changed (picker.active_index);
  }

  private void on_active_changed (int index) {
    if (index < 0 || index >= store.get_n_items ()) {
      selection.selected = Gtk.INVALID_LIST_POSITION;
      return;
    }
    selection.selected = index;
    list_view.scroll_to (index, Gtk.ListScrollFlags.NONE, null);
  }

  private void on_selection_changed () {
    if (picker != null && selection.selected != Gtk.INVALID_LIST_POSITION) {
      picker.set_active ((int) selection.selected);
    }
  }

  private void on_busy_changed () {
    spinner.visible = picker != null && picker.busy;
  }

  private void on_setup (Object item) {
    var list_item = (Gtk.ListItem) item;
    var row = new CommandBarPopoverRow (icon_theme);
    row.widget.set_data ("row", row);
    row.activated.connect (on_row_activated);
    list_item.focusable = false;
    list_item.child = row.widget;
  }

  private void on_bind (Object item) {
    var list_item = (Gtk.ListItem) item;
    list_item.child.get_data<CommandBarPopoverRow> ("row").bind ((CommandBar.Item) list_item.item, list_item.position);
  }

  private void on_unbind (Object item) {
    var list_item = (Gtk.ListItem) item;
    list_item.child.get_data<CommandBarPopoverRow> ("row").unbind ();
  }

  private void on_row_activated (uint position) {
    if (picker == null) {
      return;
    }
    picker.set_active ((int) position);
    picker.accept ();
  }

  private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
    if (picker == null) {
      return false;
    }
    bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
    switch (keyval) {
      case Gdk.Key.Down:
      case Gdk.Key.KP_Down:
        picker.move_active (1);
        return true;
      case Gdk.Key.Up:
      case Gdk.Key.KP_Up:
        picker.move_active (-1);
        return true;
      case Gdk.Key.Page_Down:
      case Gdk.Key.KP_Page_Down:
        picker.move_active_by_page (PAGE_ROWS, 1);
        return true;
      case Gdk.Key.Page_Up:
      case Gdk.Key.KP_Page_Up:
        picker.move_active_by_page (PAGE_ROWS, -1);
        return true;
      case Gdk.Key.Home:
      case Gdk.Key.KP_Home:
        if (ctrl) {
          picker.move_active_to_first ();
          return true;
        }
        return false;
      case Gdk.Key.End:
      case Gdk.Key.KP_End:
        if (ctrl) {
          picker.move_active_to_last ();
          return true;
        }
        return false;
      case Gdk.Key.Tab:
      case Gdk.Key.ISO_Left_Tab:
        return true;
      default:
        break;
    }

    if (ctrl) {
      var lower = Gdk.keyval_to_lower (keyval);
      if (lower == Gdk.Key.n || lower == Gdk.Key.p) {
        picker.move_active (1);
        return true;
      }
    }
    return false;
  }
}
