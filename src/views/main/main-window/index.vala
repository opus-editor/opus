/**
 * The application's main window — composition root for the whole app: owns
 * EditorView.EditorPane (always) and EditorView.FindBar/EditorView.FindInFilesBar
 * (always) directly, and EditorView.ExplorerPane once a folder is linked. Absorbs the real
 * MainController (the ExplorerPane<->EditorPane glue) and SearchController
 * (the FindBar<->EditorPane glue) entirely. What's left for main.vala:
 * reading argv/GLib.Settings/DevServer and constructing one of these per
 * window.
 *
 * Loads the window and its named slots straight from the compiled
 * Blueprint via {@link Gtk.Builder} — the same way {@link
 * CodeEditor} loads its widget tree, no composite-template
 * subclass needed.
 */
public class MainWindow : Object {
  private Adw.ApplicationWindow window;
  private Adw.OverlaySplitView split_view;
  private Adw.Bin sidebar_bin;
  private Gtk.Box sidebar_resize_handle;
  private Adw.Bin content_bin;
  private Adw.Bin search_bar_bin;
  private GLib.Settings settings;

  private EditorView.FindBar find_bar;
  private EditorView.FindInFilesBar find_in_files_bar;
  private EditorView.ExplorerPane? explorer_pane = null;

  // The plugin-decoration plumbing for whichever folder is currently
  // linked — owned here, not by ExplorerPane, since it must outlive a
  // single linked folder the day a second consumer (e.g. tab tinting)
  // wants it too; ExplorerPane itself is torn down and rebuilt on every
  // link_folder()/unlink_folder() (see GIT_STATUS_PLUGIN_PLAN.md's own
  // "Host wiring" section for the full reasoning). All three recreated
  // together in link_folder(), all three torn down together in
  // teardown_workspace_extensions().
  private WorkspaceContext? workspace_context = null;
  private FileDecoration.Registry? decorations = null;
  private Opus.Plugins.WorkspaceExtensions? decoration_providers = null;

  // Same lifecycle as the decoration trio above, for the git-diff gutter's
  // own extension point — no registry needed here (unlike
  // FileDecoration.Registry's N-provider aggregation): exactly one plugin
  // will ever register GitDiff.IBaseProvider, so the last one to register
  // simply wins.
  private Opus.Plugins.WorkspaceExtensions? diff_base_providers = null;
  private GitDiff.IBaseProvider? diff_base_provider = null;

  /** Whichever of find_bar/find_in_files_bar is currently open — Ctrl+F/Ctrl+H and Ctrl+Shift+F are mutually exclusive, see set_active_bottom_panel(). Null when neither is open. */
  private IGlobalPanel? active_bottom_panel = null;

  /** The window's own EditorPane, exposed directly — Opus.Dev.DevServer's own way to add/remove this window from its per-window list (App wires this at construction/close), same reasoning as EditorPane's own public `code_editor`. */
  public EditorView.EditorPane editor_pane { get; private set; }

  // search_position_changed's own (position, count) doesn't say whether
  // count == 0 means "no search text" or "search text with zero
  // matches" — find_bar.set_match_info() needs that distinction, so
  // it's tracked here from find_bar's own search_changed directly
  // instead (the real SearchController's own field).
  private bool has_search_text = false;

  /** Every IGlobalPanel registered via register_global_panel() — see its own doc comment, and IGlobalPanel's, for what this drives. */
  private GenericArray<IGlobalPanel> global_panels = new GenericArray<IGlobalPanel> ();

  // Gates Ctrl+F/Ctrl+H — kept in sync by on_has_open_tabs_changed()
  // rather than queried from editor_pane itself, since this is the one
  // piece of that state MainWindow's own key handling needs directly.
  private bool has_open_tabs = false;
  private Gtk.MenuButton menu_button;
  private Gtk.ToggleButton sidebar_toggle_button;
  private Gtk.Widget close_folder_item;

  // Ctrl+P. The registry/router/popover live for the window; the file
  // provider, its recent-files list and the plugin-contributed
  // providers come and go with the linked folder, same lifecycle as
  // the decoration trio above (see link_folder()/
  // teardown_workspace_extensions()).
  private Gtk.Stack title_stack;
  private Adw.ViewSwitcher view_switcher;
  private Adw.Bin command_bar_bin;
  private CommandBar.Registry command_registry = new CommandBar.Registry ();
  private CommandBar.Router command_router;
  private CommandBarPopover command_bar;
  private CommandBar.RecentFiles? recent_files = null;
  private CommandBar.FileProvider? file_provider = null;
  // Whatever held keyboard focus right before Ctrl+P — title_stack
  // switching its page back away from the entry on close otherwise
  // leaves GTK to pick its own fallback (the view switcher button).
  private Gtk.Widget? focus_before_command_bar = null;
  private Opus.Plugins.WorkspaceExtensions? command_providers = null;

  // The Find menu's own three items — kept live via update_find_menu(),
  // same push-on-change pattern as the primary menu's Save/Save as…
  // group (save_item/save_as_item above) rather than rebuilt lazily on
  // open.
  private Gtk.MenuButton find_menu_button;
  private Gtk.Widget find_item;
  private Gtk.Widget replace_item;
  private Gtk.Widget find_in_files_item;

  // The first theme-selector button becomes the group's own leader
  // (Gtk.CheckButton.group has no getter, so this is the only way to
  // point every later button at the same group) — see
  // build_theme_selector().
  private Gtk.CheckButton? theme_selector_group_leader = null;

  // Whether "Open Folder…" has ever linked a folder into this window —
  // the sidebar-reveal button and the primary menu's "Close Folder"
  // (see update_folder_dependent_ui) both stay hidden without one:
  // there'd be nothing in the sidebar to reveal, and nothing linked to
  // close.
  private bool has_linked_folder = false;

  // The primary menu's Save/Save as… group — kept live (not rebuilt on
  // each open) via set_active_state(), the same push-on-change pattern
  // EditorView.TabBarPill.set_modified()/mark_preview() already use elsewhere, rather
  // than querying EditorPane state at popover-open time (which
  // Gtk.MenuButton has no signal for anyway).
  private Gtk.Widget save_group_separator;
  private Gtk.Widget save_item;
  private Gtk.Widget save_as_item;
  private bool has_active_tab = false;
  private bool active_is_dirty = false;

  // Live for exactly as long as settings.json's own tab is open —
  // armed on EditorPane's tab_opened, disarmed on tab_closed, not tied
  // to which tab is active: a background tab still open keeps this
  // armed too, matching a real editor's own live-reload scope rather
  // than only-while-focused.
  private FileMonitor? settings_monitor = null;

  // The user-dragged sidebar width, in pixels — kept in sync with
  // split_view's own min/max-sidebar-width (see setup_sidebar_resize()),
  // pinned equal to each other so the fraction-based layout
  // AdwOverlaySplitView actually does internally always resolves to
  // exactly this value regardless of window width. Saved to
  // GLib.Settings alongside window-width/window-height, restored the
  // same way.
  private const double MIN_SIDEBAR_WIDTH = 180;
  private const double MAX_SIDEBAR_WIDTH = 600;
  private double sidebar_width;
  private double sidebar_drag_start_width;
  private double sidebar_drag_start_surface_x;

  /** Ctrl+Shift+N, or the primary menu's own "New Window" — reopening a window as either blank/file/folder is a decision only whoever manages the app's own window list can make. */
  public signal void new_window_requested ();

  /** The window was actually destroyed (not just requested to close, which can be cancelled) — main.vala uses this to release this window. */
  public signal void closed ();

  public MainWindow (Gtk.Application app, GLib.Settings settings, string root_path) {
    this.settings = settings;

    var builder = new Gtk.Builder.from_resource ("/io/github/nowaos/Opus/main/main-window/index.ui");
    window = (Adw.ApplicationWindow) builder.get_object ("window");
    split_view = (Adw.OverlaySplitView) builder.get_object ("split_view");
    sidebar_bin = (Adw.Bin) builder.get_object ("sidebar_bin");
    sidebar_resize_handle = (Gtk.Box) builder.get_object ("sidebar_resize_handle");
    content_bin = (Adw.Bin) builder.get_object ("content_bin");
    search_bar_bin = (Adw.Bin) builder.get_object ("search_bar_bin");
    menu_button = (Gtk.MenuButton) builder.get_object ("menu_button");
    find_menu_button = (Gtk.MenuButton) builder.get_object ("find_menu_button");
    sidebar_toggle_button = (Gtk.ToggleButton) builder.get_object ("sidebar_toggle_button");
    title_stack = (Gtk.Stack) builder.get_object ("title_stack");
    view_switcher = (Adw.ViewSwitcher) builder.get_object ("view_switcher");
    command_bar_bin = (Adw.Bin) builder.get_object ("command_bar_bin");

    editor_pane = new EditorView.EditorPane (root_path);
    // Set once — editor_pane.widget's own child already toggles itself
    // between its real content and its own empty state as tabs open/close.
    content_bin.child = editor_pane.widget;
    editor_pane.has_open_tabs_changed.connect (on_has_open_tabs_changed);
    editor_pane.active_state_changed.connect ((path, dirty) => set_active_state (path != null, dirty));
    editor_pane.reveal_in_sidebar_requested.connect (on_reveal_in_sidebar_requested);
    editor_pane.tab_opened.connect (on_settings_tab_opened);
    editor_pane.tab_closed.connect (on_settings_tab_closed);
    // active_document_path, not the signal's own `path`: that one is the
    // tab's URI, and only a real on-disk file belongs in recent files.
    editor_pane.active_state_changed.connect (() => {
      var path = editor_pane.active_document_path;
      if (path != null && recent_files != null) {
        recent_files.push (path);
      }
    });

    command_bar = new CommandBarPopover (new IconTheme.symbols ());
    command_bar_bin.child = command_bar.widget;
    register_global_panel (command_bar);
    command_bar.closed.connect (() => command_router.close ());
    command_router = new CommandBar.Router (command_registry);
    command_router.opened.connect (on_command_bar_opened);
    command_router.closed.connect (on_command_bar_closed);

    find_bar = new EditorView.FindBar ();
    register_global_panel (find_bar);
    find_bar.search_changed.connect (on_search_changed);
    find_bar.search_options_changed.connect (on_search_options_changed);
    find_bar.search_next_requested.connect (() => editor_pane.search_next ());
    find_bar.search_previous_requested.connect (() => editor_pane.search_previous ());
    find_bar.select_all_requested.connect (on_select_all_requested);
    find_bar.replace_requested.connect (on_replace_requested);
    find_bar.replace_all_requested.connect (on_replace_all_requested);
    find_bar.closed.connect (on_search_bar_closed);
    editor_pane.search_position_changed.connect (on_search_position_changed);

    find_in_files_bar = new EditorView.FindInFilesBar ();
    register_global_panel (find_in_files_bar);
    find_in_files_bar.closed.connect (on_find_in_files_bar_closed);
    find_in_files_bar.search_next_requested.connect (on_find_in_files_search_requested);
    find_in_files_bar.add_folder_requested.connect (() => on_add_folder_requested.begin ());

    // search_bar_bin is a single-child slot (Adw.ToolbarView's own
    // [bottom] bar) — find_bar/find_in_files_bar take turns occupying
    // it, reparented in by set_active_bottom_panel() rather than both
    // sitting permanently mounted side by side: each is a real
    // Gtk.SearchBar with its own internal collapse/reveal revealer (see
    // FindBar's own doc comment), and two of those animating at once in
    // a shared Gtk.Box would show both partially expanded mid-switch —
    // reparenting keeps only the active one in the tree at all, so only
    // its own reveal animation ever plays. find_bar starts mounted here,
    // collapsed by default, so nothing shows until show_find()/
    // show_replace() actually opens it.
    search_bar_bin.child = find_bar.widget;

    // Restores whatever size the last window that closed was left at —
    // saved back on close_request below. Deliberately session-wide, not
    // per-window: with several windows open, whichever one closes
    // last is what the next launch restores, matching most GNOME
    // apps' own single-shared-size behavior rather than remembering
    // one size per window.
    window.set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
    window.close_request.connect (() => {
      settings.set_int ("window-width", window.get_width ());
      settings.set_int ("window-height", window.get_height ());
      settings.set_int ("sidebar-width", (int) sidebar_width);
      return false;
    });

    setup_sidebar_resize ();

    // Gtk.Window has its own plain destroy() method (calls
    // gtk_window_destroy()), which shadows Gtk.Widget's own `destroy`
    // signal for a Gtk.Window-typed reference — same issue, same fix,
    // as add_controller()'s own cast below.
    ((Gtk.Widget) window).destroy.connect (() => {
      if (explorer_pane != null) {
        explorer_pane.close ();
      }
      teardown_workspace_extensions ();
      command_bar.destroy ();
      editor_pane.close ();
      settings_monitor?.cancel ();
      closed ();
    });
    // build_find_menu() first: build_primary_menu() ends by calling
    // update_folder_dependent_ui(), which (see its own doc comment) also
    // updates find_in_files_item — needs to already exist by then.
    build_find_menu ();
    build_primary_menu ();

    install_css ();

    var style_manager = Adw.StyleManager.get_default ();
    style_manager.notify["dark"].connect (() => update_theme_class (style_manager.dark));
    update_theme_class (style_manager.dark);

    window.application = app;
    // No folder is linked at construction — the sidebar has nothing
    // to show until link_folder() gives it one ("Open Folder…", or
    // main.vala linking one right after construction when launched
    // with a folder argument).
    split_view.show_sidebar = false;

    // The button itself just mirrors/drives show-sidebar — the split
    // view already reveals/hides accordingly, animation and all, and
    // (per its own source) already dismisses on an outside click
    // while collapsed, with no extra code needed for that part.
    split_view.bind_property (
      "show-sidebar", sidebar_toggle_button, "active", BindingFlags.BIDIRECTIONAL | BindingFlags.SYNC_CREATE
    );
    split_view.notify["collapsed"].connect (update_folder_dependent_ui);

    // On the window itself, not a specific widget: these need to fire
    // no matter where focus currently is (sidebar, tab bar, or the
    // editor's own GtkSourceView, none of which bind Ctrl+W/Ctrl+S/
    // Ctrl+Shift+S to anything of their own, so nothing here competes
    // with a more specific handler for the same keys).
    var key_controller = new Gtk.EventControllerKey ();
    key_controller.key_pressed.connect (on_key_pressed);
    // Adw.ApplicationWindow implements Gtk.ShortcutManager, whose own
    // add_controller (Gtk.ShortcutController) shadows Gtk.Widget's —
    // the cast picks the one that actually takes an EventControllerKey.
    ((Gtk.Widget) window).add_controller (key_controller);

    // Escape closes whichever registered IGlobalPanel is open, from
    // anywhere in the window — not just while focus already happens
    // to be inside it (see IGlobalPanel's own doc comment for why
    // that's genuinely generic, not specific to EditorView.FindBar). A
    // *separate*, CAPTURE-phase controller, not folded into
    // on_key_pressed above (BUBBLE, and only reacts to a Ctrl
    // combination in the first place): CAPTURE resolves outer-to-
    // inner, ancestor before descendant, so this needs to run before
    // CodeEditorCursors' own plain-Escape handling — otherwise, with a
    // selection in the editor (Ctrl+F's own "seed from the current
    // selection" leaves exactly that), that would already claim the
    // keystroke to collapse it before this ever got a turn, and an
    // open panel would only close on a *second* Escape.
    var escape_controller = new Gtk.EventControllerKey ();
    escape_controller.set_propagation_phase (Gtk.PropagationPhase.CAPTURE);
    escape_controller.key_pressed.connect ((keyval, keycode, state) => {
      if (keyval != Gdk.Key.Escape) {
        return false;
      }
      for (uint i = 0; i < global_panels.length; i++) {
        if (global_panels[i].is_open) {
          global_panels[i].close ();
          return true;
        }
      }
      return false;
    });
    ((Gtk.Widget) window).add_controller (escape_controller);
  }

  /**
   * Links `path` into this window — "Open Folder…", whether this window
   * had none yet or is replacing one it already had. The open tab bar/
   * editor stay exactly as they are (switching folders doesn't imply
   * discarding whatever's already open); only what ExplorerPane shows
   * and what EditorPane resolves relative paths against change.
   * Constructing the new ExplorerPane happens *before* anything about
   * the old one (or EditorPane's own root path) is touched, so a
   * failure here — the folder itself just became unreadable, say —
   * leaves this window exactly as it was.
   */
  public void link_folder (string path) throws Error {
    // Built into locals first, not the real fields — ExplorerPane's own
    // constructor is what can actually throw (an unreadable path), and
    // this class's own doc comment above promises a failure here leaves
    // the window exactly as it was. Nothing below this point touches the
    // old workspace_context/decorations/decoration_providers/
    // explorer_pane until the new ExplorerPane has already been built
    // successfully.
    var new_workspace_context = new WorkspaceContext (path);
    var new_decorations = new FileDecoration.Registry (path);
    var new_decoration_providers = new Opus.Plugins.WorkspaceExtensions (typeof (FileDecoration.IProvider), new_workspace_context);
    new_decoration_providers.added.connect ((e) => new_decorations.add_provider ((FileDecoration.IProvider) e));
    new_decoration_providers.removed.connect ((e) => new_decorations.remove_provider ((FileDecoration.IProvider) e));

    var new_diff_base_providers = new Opus.Plugins.WorkspaceExtensions (typeof (GitDiff.IBaseProvider), new_workspace_context);
    new_diff_base_providers.added.connect ((e) => {
      diff_base_provider = (GitDiff.IBaseProvider) e;
      editor_pane.set_diff_base_provider (diff_base_provider);
    });
    new_diff_base_providers.removed.connect ((e) => {
      if (diff_base_provider == e) {
        diff_base_provider = null;
        editor_pane.set_diff_base_provider (null);
      }
    });

    EditorView.ExplorerPane new_explorer_pane;
    try {
      new_explorer_pane = new EditorView.ExplorerPane (path, new_workspace_context, new_decorations);
    } catch (Error e) {
      new_decoration_providers.close ();
      new_diff_base_providers.close ();
      throw e;
    }
    wire_explorer_pane (new_explorer_pane);

    teardown_workspace_extensions ();
    workspace_context = new_workspace_context;
    decorations = new_decorations;
    decoration_providers = new_decoration_providers;
    diff_base_providers = new_diff_base_providers;
    editor_pane.set_decorations (new_decorations);

    recent_files = new CommandBar.RecentFiles ();
    file_provider = new CommandBar.FileProvider (new_workspace_context, recent_files);
    file_provider.activate ();
    command_registry.add (file_provider);
    command_providers = new Opus.Plugins.WorkspaceExtensions (typeof (CommandBar.IProvider), new_workspace_context);
    command_providers.added.connect ((e) => command_registry.add ((CommandBar.IProvider) e));
    command_providers.removed.connect ((e) => command_registry.remove ((CommandBar.IProvider) e));

    if (explorer_pane != null) {
      explorer_pane.close ();
    }
    explorer_pane = new_explorer_pane;
    editor_pane.set_root_path (path);

    sidebar_bin.child = explorer_pane.widget;
    has_linked_folder = true;
    split_view.show_sidebar = true;
    update_folder_dependent_ui ();
  }

  /** "Close Folder" — the opposite of link_folder(): the sidebar goes back to not existing at all, same as a window that never had one linked. Open tabs stay exactly as they are; only the sidebar (and what "Copy Relative Path" resolves against) are affected. */
  public void unlink_folder () {
    if (explorer_pane == null) {
      return;
    }

    explorer_pane.close ();
    explorer_pane = null;
    teardown_workspace_extensions ();
    sidebar_bin.child = null;
    has_linked_folder = false;
    split_view.show_sidebar = false;
    editor_pane.set_root_path (Environment.get_current_dir ());
    update_folder_dependent_ui ();
  }

  /** Deactivates and drops every plugin extension for whichever folder was linked, if any — a no-op with none (a plain "no folder yet" window). Called before constructing a fresh trio in link_folder() too, not just on unlink/close, so a folder-switch never leaves the previous one's plugins running alongside the new one's. */
  private void teardown_workspace_extensions () {
    command_router.close ();
    if (command_providers != null) {
      command_providers.close ();
    }
    command_providers = null;
    if (file_provider != null) {
      command_registry.remove (file_provider);
      file_provider.deactivate ();
    }
    file_provider = null;
    recent_files = null;

    if (decoration_providers != null) {
      decoration_providers.close ();
    }
    decoration_providers = null;
    decorations = null;

    if (diff_base_providers != null) {
      diff_base_providers.close ();
    }
    diff_base_providers = null;
    diff_base_provider = null;

    workspace_context = null;
    editor_pane.set_decorations (null);
    editor_pane.set_diff_base_provider (null);
  }

  /** Opens `path` as a permanent tab right at startup (`opus <file>`) — failures are reported through this same window's own show_error() rather than left for main.vala to handle, since main.vala no longer holds a reference to anything that could report one itself. */
  public void open_initial_file (string path) {
    try {
      editor_pane.open (path, true);
    } catch (Error e) {
      show_error (_("Couldn’t open “%s”: %s").printf (path, e.message));
    }
  }

  /** The primary menu's own "Settings" — creates settings.json with its defaults on first use, then opens it as a permanent tab, same as any other file. */
  private void open_settings () {
    try {
      var path = UserSettings.ensure_exists (Environment.get_user_config_dir ());
      editor_pane.open (path, true);
    } catch (Error e) {
      show_error (_("Couldn’t open settings: %s").printf (e.message));
    }
  }

  /** Alt+W — flips editor.wordWrap in settings.json and re-applies it right away, same as editing the file by hand and the live-reload watch picking it up (see on_settings_tab_opened()'s own doc comment), just without needing that tab open at all. */
  private void toggle_word_wrap () {
    try {
      UserSettings.toggle_word_wrap (Environment.get_user_config_dir ());
      editor_pane.code_editor.reload_settings ();
    } catch (Error e) {
      show_error (_("Couldn’t update settings: %s").printf (e.message));
    }
  }

  /**
   * Arms a live-reload watch on settings.json for exactly as long as
   * its own tab stays open — every open tab's font re-renders on each
   * change (the font CSS is display-wide, see CodeEditor's own
   * font_css()), not just whichever tab happens to be active.
   */
  private void on_settings_tab_opened (string uri) {
    var settings_path = UserSettings.path (Environment.get_user_config_dir ());
    if (uri != Document.uri_for_path (settings_path) || settings_monitor != null) {
      return;
    }

    try {
      settings_monitor = File.new_for_path (settings_path).monitor_file (FileMonitorFlags.NONE, null);
      settings_monitor.changed.connect (() => editor_pane.code_editor.reload_settings ());
    } catch (Error e) {
      Logger.warn ("failed to watch settings.json for live-reload: %s".printf (e.message));
    }
  }

  private void on_settings_tab_closed (string uri) {
    if (uri != Document.uri_for_path (UserSettings.path (Environment.get_user_config_dir ())) || settings_monitor == null) {
      return;
    }
    settings_monitor.cancel ();
    settings_monitor = null;
  }

  /**
   * Wires an EditorView.ExplorerPane's file activations, creations,
   * deletions and moves into editor_pane — the real MainController's
   * entire job, absorbed here since this class is what composes both.
   */
  private void wire_explorer_pane (EditorView.ExplorerPane pane) {
    pane.file_activated.connect ((path, open_permanent) => open_from_explorer (path, open_permanent));
    // A New File is opened as a permanent tab right away, same as a
    // double-click — there's no reason to make the user go find and
    // click the file they just named.
    pane.file_created.connect ((path) => open_from_explorer (path, true));
    pane.delete_entry_requested.connect ((path) => on_delete_requested.begin (pane, path));
    pane.file_moved.connect ((old_path, new_path) => {
      editor_pane.file_moved (old_path, new_path);
      if (recent_files != null && recent_files.contains (old_path)) {
        recent_files.remove (old_path);
        recent_files.push (new_path);
      }
    });
  }

  /** Ctrl+P — or, while the bar is already open, "next result" (VS Code's own Ctrl+P-again). Public for Opus.Dev.DevServer's own OpenCommandBar, same as the three below. */
  public void open_command_bar () {
    if (command_router.is_open) {
      command_router.picker.move_active (1);
      return;
    }
    focus_before_command_bar = window.get_focus ();
    title_stack.visible_child_name = "command-bar";
    command_router.open ();
    if (!command_router.is_open) {
      title_stack.visible_child_name = "switcher";
      return;
    }
    command_bar.open ();
  }

  public void command_bar_set_text (string text) {
    command_bar.set_text (text);
  }

  public void command_bar_accept () {
    command_bar.accept ();
  }

  public string[] command_bar_item_ids () {
    string[] ids = {};
    if (!command_router.is_open) {
      return ids;
    }
    var items = command_router.picker.items;
    for (uint i = 0; i < items.length; i++) {
      ids += items[i].id;
    }
    return ids;
  }

  private void on_command_bar_opened (CommandBar.Picker picker) {
    command_bar.bind (picker);
    picker.accepted.connect (on_command_bar_item_accepted);
  }

  /** Without this, the view switcher button underneath the entry's own title_stack page picks up focus on its own once that page becomes visible again. Restores focus_before_command_bar (set in open_command_bar()) rather than always the editor — Ctrl+P isn't only ever pressed from there. */
  private void on_command_bar_closed () {
    command_bar.close ();
    title_stack.visible_child_name = "switcher";
    if (focus_before_command_bar != null && focus_before_command_bar.get_mapped ()) {
      focus_before_command_bar.grab_focus ();
    } else if (editor_pane.active_document_path != null) {
      editor_pane.grab_focus ();
    }
    focus_before_command_bar = null;
  }

  /** Only the file provider's items are understood here (`id` is a path); a future `>` provider's own accept behaviour belongs to that provider. */
  private void on_command_bar_item_accepted (CommandBar.Item item) {
    var is_file = command_router.provider == file_provider;
    command_router.close ();
    if (!is_file) {
      return;
    }
    try {
      editor_pane.open (item.id, true);
    } catch (Error e) {
      show_error (_("Couldn’t open “%s”: %s").printf (item.id, e.message));
    }
  }

  private void open_from_explorer (string path, bool open_permanent) {
    try {
      editor_pane.open (path, open_permanent);
    } catch (Error e) {
      warning ("failed to open %s: %s", path, e.message);
    }
  }

  /**
   * A folder, or a file with no dirty open tab, deletes immediately —
   * same as before. A file with unsaved changes open asks first (same
   * shape VS Code uses); declining leaves it untouched, on disk and in
   * its tab. Either way, once actually deleted, whatever tab was open
   * for it closes outright — nothing left on disk to save it back to.
   */
  private async void on_delete_requested (EditorView.ExplorerPane pane, string path) {
    if (editor_pane.is_dirty (path)) {
      var confirmed = yield pane.confirm_delete_with_unsaved_changes (Path.get_basename (path));
      if (!confirmed) {
        return;
      }
    }

    pane.delete_entry (path);
    editor_pane.discard_tab (path);
    recent_files?.remove (path);
  }

  /** "Reveal in Sidebar" — a pure View<->View navigation, no Model involved. A no-op with no folder linked (explorer_pane null). */
  private void on_reveal_in_sidebar_requested (string path) {
    if (explorer_pane == null) {
      return;
    }
    reveal_sidebar ();
    explorer_pane.reveal_path (path);
  }

  /**
   * Ctrl+F — already gated on there being an open tab at all (see
   * on_key_pressed). Seeds the Find entry from the editor's own current
   * (primary) selection first, same as most editors' own real Ctrl+F,
   * but only when the editor genuinely had focus at the moment it was
   * pressed — read into `selected` before find_bar.show_find() below
   * moves focus into the entry itself, so a second Ctrl+F while the bar
   * is already open (focus already in its entry, mid-typing a query)
   * leaves that query alone instead of clobbering it with whatever the
   * editor's own primary selection happens to be.
   *
   * find_bar.set_find_text() itself still has to run *after*
   * show_find(), not before — see its own doc comment.
   */
  private void open_find () {
    bool has_selection_in_focus = editor_pane.has_focus;
    string selected = has_selection_in_focus ? editor_pane.primary_selection_text : "";

    set_active_bottom_panel (find_bar);
    find_bar.show_find ();

    if (selected != "") {
      find_bar.set_find_text (selected);
    }
  }

  /**
   * Ctrl+Shift+F — mutually exclusive with Ctrl+F/Ctrl+H, see
   * set_active_bottom_panel(). Restores the search behind the "Find
   * Results" tab if that's the active tab right now (as if reopening
   * the bar to redo/tweak it), or starts blank otherwise — see
   * EditorPane.current_find_in_files_query's own doc comment for why
   * that's exactly the condition it already encodes.
   */
  private void open_find_in_files () {
    set_active_bottom_panel (find_in_files_bar);
    find_in_files_bar.show_find ();
    find_in_files_bar.set_query (editor_pane.current_find_in_files_query);
  }

  /** Enter in FindInFilesBar's own entry, or its Search button — searches the whole linked workspace folder and opens/refreshes the "Find Results" tab. Fire-and-forget: EditorPane.search_in_files() itself guards against a second search superseding a still-running one. */
  private void on_find_in_files_search_requested () {
    var query = new FindInFilesQuery () {
      text = find_in_files_bar.search_text,
      regex_enabled = find_in_files_bar.regex_enabled,
      case_sensitive_enabled = find_in_files_bar.case_sensitive_enabled,
      whole_word_enabled = find_in_files_bar.whole_word_enabled,
      gitignore_enabled = find_in_files_bar.gitignore_enabled,
      where_text = find_in_files_bar.where_text,
    };
    editor_pane.search_in_files.begin (query);
    // Unlike plain Find (FindBar stays open to step through live
    // matches), Find in Files has nothing left for the bar itself to do
    // once a search is launched — the Find Results tab is where the
    // action moves to next.
    find_in_files_bar.close ();
  }

  /**
   * "Add Folder…" — FindInFilesBar itself has no root_path to validate
   * against (only EditorPane does), so this is where the real folder
   * chooser and the "must be inside the linked folder" check both live.
   * All-or-nothing across a multi-selection: the very first folder that
   * isn't inside root_path aborts the whole thing with one error and
   * appends nothing at all, rather than adding the folders picked
   * before it and silently dropping the rest.
   */
  private async void on_add_folder_requested () {
    ListModel? folders;
    try {
      var dialog = new Gtk.FileDialog ();
      folders = yield dialog.select_multiple_folders (window, null);
    } catch (Error e) {
      return; // cancelled, or the portal itself failed — nothing to do either way
    }
    if (folders == null) {
      return;
    }
    // The folder dialog is async and Ctrl+F/Escape/etc. can swap
    // search_bar_bin's own single slot to a different IGlobalPanel while
    // it was still open (set_active_bottom_panel() unparents
    // find_in_files_bar entirely in that case) — nothing left to append
    // into, or to sensibly show an error for, once that's happened.
    if (!find_in_files_bar.is_open) {
      return;
    }

    var root_path = editor_pane.linked_folder_path;
    var prefix = root_path + "/";
    string[] patterns = {};
    for (uint i = 0; i < folders.get_n_items (); i++) {
      var path = ((File) folders.get_item (i)).get_path ();
      // !has_prefix (prefix) alone already rejects path == root_path too
      // — a string can never have a strictly longer string as its own
      // prefix — so this is really one check, not two: "must be
      // strictly inside root_path," which is exactly what rules out the
      // otherwise-meaningless pattern "//" a bare root_path would give.
      if (path == null || !path.has_prefix (prefix)) {
        show_error (_("Every folder has to be inside the project folder."));
        return;
      }
      // "/<relative path>/" — anchored to the root, directory-only —
      // see FindInFilesScope's own doc comment for why both matter here.
      patterns += "/" + path.substring (prefix.length) + "/";
    }

    find_in_files_bar.append_where_patterns (patterns);
  }

  /** "Replace" — replaces only the current match, then advances to the next one. A no-op if there's no current match right now. */
  private void on_replace_requested () {
    var edit = editor_pane.compute_replace_current_match (find_bar.replace_text);
    if (edit == null) {
      return;
    }

    editor_pane.apply_external_edits ({ edit });
    editor_pane.land_after_replace (edit.start_offset + edit.new_text.char_count ());
  }

  /** "Replace All" — replaces every live match as one undo step; the user's own cursor/selection just shifts to stay at its own logical position. A no-op with no matches. */
  private void on_replace_all_requested () {
    var edits = editor_pane.compute_replace_all (find_bar.replace_text);
    if (edits.length == 0) {
      return;
    }

    editor_pane.apply_external_edits (edits);
    editor_pane.forget_current_match ();
  }

  private void on_search_changed (string text) {
    has_search_text = text != "";
    editor_pane.set_search_text (text);
  }

  private void on_search_options_changed () {
    editor_pane.set_search_options (
      find_bar.regex_enabled, find_bar.case_sensitive_enabled, find_bar.whole_word_enabled
    );
  }

  private void on_search_position_changed (int position, int count) {
    find_bar.set_match_info (position, count, has_search_text);
  }

  /**
   * select_last_match() only moves focus back into the editor when a
   * match was actually live-highlighted — a no-op close (bar opened,
   * nothing searched/found, then dismissed) left focus stuck wherever it
   * was, typically still the bar's own entry. Grabbing it here too
   * covers that case as well, harmlessly redundant with
   * select_last_match()'s own grab in the case it already handled.
   * Gated on there still being an active tab: close() is also called
   * directly when the last open tab closes while the bar is still open
   * (see on_has_open_tabs_changed()) — nothing to focus then.
   */
  private void on_search_bar_closed () {
    clear_active_bottom_panel (find_bar);
    editor_pane.select_last_match ();
    if (editor_pane.active_document_path != null) {
      editor_pane.grab_focus ();
    }
  }

  /** find_in_files_bar's own closed — see on_search_bar_closed()'s doc comment for why active_bottom_panel needs clearing here too. */
  private void on_find_in_files_bar_closed () {
    clear_active_bottom_panel (find_in_files_bar);
  }

  /**
   * Alt+Return in the Find entry — matches VS Code's own "Select All
   * Occurrences of Find Match" (no toolbar button there either, see
   * EditorView.FindBar's own doc comment on select_all_requested).
   * select_last_match() first, same as a plain Escape close would do:
   * select_all_occurrences() reads its needle off the real primary
   * selection, not off the find bar's own live (visual-only) match —
   * without this, it would select occurrences of whatever the editor's
   * selection happened to be *before* Ctrl+F was pressed. close()
   * re-triggers on_search_bar_closed()'s own select_last_match() call,
   * a safe no-op by then (it clears its own marks the first time it
   * actually finds something to hand off).
   */
  private void on_select_all_requested () {
    editor_pane.select_last_match ();
    editor_pane.select_all_occurrences ();
    find_bar.close ();
  }

  // editor_pane.widget already swaps its own content for its own empty
  // state internally — nothing left to do here besides tracking the
  // flag Ctrl+F/Ctrl+H gate on, and closing the search bar once there's
  // nothing left for it to search.
  private void on_has_open_tabs_changed (bool has_tabs) {
    has_open_tabs = has_tabs;
    if (!has_tabs) {
      find_bar.close ();
    }
    update_find_menu ();
  }

  /** Registers `panel` for the window-wide "Escape closes it, even without focus" behavior — see IGlobalPanel's own doc comment. */
  private void register_global_panel (IGlobalPanel panel) {
    global_panels.add (panel);
  }

  /**
   * Makes `panel` the one occupying search_bar_bin's single slot —
   * Ctrl+F/Ctrl+H and Ctrl+Shift+F are mutually exclusive. Reparents
   * `panel.widget` into the bin (unmounting whichever one was there
   * before, if any) rather than leaving both permanently mounted side
   * by side: each panel is a real Gtk.SearchBar with its own internal
   * reveal/collapse revealer (see FindBar's own doc comment), and two
   * of those animating at once in a shared container showed both
   * partially expanded mid-switch instead of one clean transition.
   * close() still runs on the old one first, for its side effects
   * (clearing its entry, emitting closed) — its own collapse animation
   * just never gets to play since unparenting cuts it short right
   * after, which is what "closing and opening at the same time" comes
   * down to here: the caller's own show_find()/show_replace() on
   * `panel` right after this runs without waiting on the old one.
   */
  private void set_active_bottom_panel (IGlobalPanel panel) {
    if (active_bottom_panel == panel) {
      return;
    }
    active_bottom_panel?.close ();
    search_bar_bin.child = panel.widget;
    active_bottom_panel = panel;
  }

  /** Clears active_bottom_panel once `panel` closes on its own (Escape, its own close button, or nothing left to search) — a no-op if `panel` wasn't the active one, e.g. set_active_bottom_panel() already closed it to switch to the other. */
  private void clear_active_bottom_panel (IGlobalPanel panel) {
    if (active_bottom_panel == panel) {
      active_bottom_panel = null;
    }
  }

  /** Shows the sidebar if it's currently collapsed/hidden behind the toggle button — "Reveal in Sidebar" needs it actually visible, not just linked, same as clicking sidebar_toggle_button by hand would. A no-op with no folder linked at all: nothing to reveal. */
  private void reveal_sidebar () {
    if (has_linked_folder) {
      split_view.show_sidebar = true;
    }
  }

  /** Toggles the "dark" class the opus-header/opus-sidebar/opus-main CSS (see main-window.css) keys its colors off of. */
  private void update_theme_class (bool dark) {
    if (dark) {
      window.add_css_class ("dark");
    } else {
      window.remove_css_class ("dark");
    }
  }

  private void install_css () {
    GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/main-window.css");
    GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/context-menu.css");
    GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/dialogs.css");
    GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/common.css");
    GlobalCss.install_from_resource ("/io/github/nowaos/Opus/styles/command-bar.css");
  }

  /**
   * Drag-to-resize for the sidebar (see the Blueprint's own
   * sidebar_resize_handle comment for why this is hand-rolled rather
   * than something AdwOverlaySplitView already provides). Pins
   * min-sidebar-width and max-sidebar-width to the same value — the
   * only way to make the fraction-based layout AdwOverlaySplitView
   * actually does internally resolve to one exact pixel width instead
   * of a width that also depends on how wide the window itself is.
   *
   * Deliberately NOT driven by Gtk.GestureDrag's own offset_x/offset_y
   * (widget-local coordinates, relative to sidebar_resize_handle
   * itself): every drag-update here resizes the very box that handle
   * sits in, which shifts the handle's own on-screen position — GTK
   * then resolves the *next* event's "local" coordinates against that
   * already-shifted allocation, so the reported offset no longer means
   * "distance from where the drag started." That fed back into itself
   * (every update nudging the widget it was being measured against)
   * and showed up live as the sidebar width oscillating between two
   * values many times a second. Surface coordinates
   * (Gdk.Event.get_position(), relative to the whole window, not any
   * single widget inside it) don't move just because an inner box got
   * wider, so the same math stays correct for the whole drag.
   */
  private void setup_sidebar_resize () {
    sidebar_width = ((double) settings.get_int ("sidebar-width")).clamp (MIN_SIDEBAR_WIDTH, MAX_SIDEBAR_WIDTH);
    split_view.min_sidebar_width = sidebar_width;
    split_view.max_sidebar_width = sidebar_width;

    sidebar_resize_handle.set_cursor (new Gdk.Cursor.from_name ("col-resize", null));

    var drag = new Gtk.GestureDrag ();
    drag.drag_begin.connect ((start_x, start_y) => {
      var event = drag.get_current_event ();
      if (event == null) {
        return;
      }
      sidebar_drag_start_width = sidebar_width;
      double surface_y;
      event.get_position (out sidebar_drag_start_surface_x, out surface_y);
    });
    drag.drag_update.connect ((offset_x, offset_y) => {
      var event = drag.get_current_event ();
      if (event == null) {
        return;
      }
      double surface_x, surface_y;
      event.get_position (out surface_x, out surface_y);
      sidebar_width = (sidebar_drag_start_width + (surface_x - sidebar_drag_start_surface_x)).clamp (MIN_SIDEBAR_WIDTH, MAX_SIDEBAR_WIDTH);
      split_view.min_sidebar_width = sidebar_width;
      split_view.max_sidebar_width = sidebar_width;
    });
    sidebar_resize_handle.add_controller (drag);

    // Double-click resets to "optimal" width — VS Code's own real
    // behavior. A no-op with no folder linked: nothing to measure.
    var click = new Gtk.GestureClick ();
    click.pressed.connect ((n_press, x, y) => {
      if (n_press == 2 && explorer_pane != null) {
        set_sidebar_width (explorer_pane.get_optimal_width ());
      }
    });
    sidebar_resize_handle.add_controller (click);
  }

  /** Pins the sidebar to exactly `width` px, clamped to the same range dragging allows — see setup_sidebar_resize(). */
  private void set_sidebar_width (double width) {
    sidebar_width = width.clamp (MIN_SIDEBAR_WIDTH, MAX_SIDEBAR_WIDTH);
    split_view.min_sidebar_width = sidebar_width;
    split_view.max_sidebar_width = sidebar_width;
  }

  private void update_folder_dependent_ui () {
    sidebar_toggle_button.visible = has_linked_folder && split_view.collapsed;
    close_folder_item.visible = has_linked_folder;
    update_find_menu ();
  }

  public void show_error (string message) {
    Dialogs.show_error (window, message);
  }

  private bool on_key_pressed (uint keyval, uint keycode, Gdk.ModifierType state) {
    // Alt+W, not folded into the Ctrl switch below: it's its own
    // modifier entirely, not another Ctrl combination.
    if ((state & Gdk.ModifierType.ALT_MASK) != 0 && (state & Gdk.ModifierType.CONTROL_MASK) == 0
        && Gdk.keyval_to_lower (keyval) == Gdk.Key.w) {
      toggle_word_wrap ();
      return true;
    }

    if ((state & Gdk.ModifierType.CONTROL_MASK) == 0) {
      return false;
    }

    // Shift already changes the keyval itself (lowercase 's' becomes
    // uppercase 'S'), on top of setting SHIFT_MASK — comparing the raw
    // keyval against Gdk.Key.s below would never match with Shift
    // held, silently missing Ctrl+Shift+S. Normalizing here lets the
    // switch below check letters only, leaving Shift entirely to the
    // flag above.
    keyval = Gdk.keyval_to_lower (keyval);

    var shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
    switch (keyval) {
      case Gdk.Key.w:
        editor_pane.close_active ();
        return true;
      case Gdk.Key.s:
        if (shift) {
          editor_pane.save_as_active.begin ();
        } else {
          editor_pane.save_active.begin ();
        }
        return true;
      case Gdk.Key.n:
        if (shift) {
          new_window_requested ();
        } else {
          editor_pane.new_untitled ();
        }
        return true;
      case Gdk.Key.o:
        if (shift) {
          on_open_folder_requested.begin ();
        } else {
          on_open_file_requested.begin ();
        }
        return true;
      case Gdk.Key.comma:
        open_settings ();
        return true;
      case Gdk.Key.p:
        // Same gate as Ctrl+Shift+F: no folder linked means nothing to
        // search.
        if (has_linked_folder) {
          open_command_bar ();
        }
        return true;
      case Gdk.Key.plus:
      case Gdk.Key.equal:
      case Gdk.Key.KP_Add:
        editor_pane.code_editor.zoom_in ();
        return true;
      case Gdk.Key.minus:
      case Gdk.Key.KP_Subtract:
        editor_pane.code_editor.zoom_out ();
        return true;
      case Gdk.Key.@0:
        editor_pane.code_editor.reset_zoom ();
        return true;
      case Gdk.Key.f:
        if (shift) {
          // Gated the same reasoning as plain Ctrl+F below: no folder
          // linked means nothing to search — root_path would otherwise
          // silently default to the process's own cwd instead of
          // something the user actually chose.
          if (has_linked_folder) {
            open_find_in_files ();
          }
        } else if (has_open_tabs) {
          // Gated here, not inside open_find(): no open tab means
          // nothing to search, so there's nothing to show for it either
          // — same guard on_has_open_tabs_changed() itself uses to
          // close the bar once the last one closes.
          open_find ();
        }
        return true;
      case Gdk.Key.h:
        // Same reasoning as plain Ctrl+F above, just into Replace mode —
        // except on the Find Results tab, which has no single-file
        // buffer for FindBar to act on: opens that tab's own inline
        // Find/Replace row instead, falling back to the regular FindBar
        // for every other tab.
        if (has_open_tabs) {
          if (editor_pane.is_find_results_active ()) {
            editor_pane.open_internal_replace ();
          } else {
            set_active_bottom_panel (find_bar);
            find_bar.show_replace ();
          }
        }
        return true;
      default:
        return false;
    }
  }

  /** The system's own file chooser (a portal dialog) — for "Open File…". */
  private async void on_open_file_requested () {
    var path = yield choose_file ();
    if (path == null) {
      return;
    }

    try {
      editor_pane.open (path, true);
    } catch (Error e) {
      show_error (_("Couldn’t open “%s”: %s").printf (path, e.message));
    }
  }

  /** The system's own folder chooser (a portal dialog) — for "Open Folder…". */
  private async void on_open_folder_requested () {
    var path = yield choose_folder ();
    if (path == null) {
      return;
    }

    try {
      link_folder (path);
    } catch (Error e) {
      show_error (_("Couldn’t open “%s”: %s").printf (path, e.message));
    }
  }

  /** The system's own file chooser (a portal dialog). Returns the chosen path, or null if cancelled/failed. */
  private async string? choose_file () {
    var dialog = new Gtk.FileDialog ();
    try {
      var file = yield dialog.open (window, null);
      return file != null ? file.get_path () : null;
    } catch (Error e) {
      return null;
    }
  }

  /** The system's own folder chooser (a portal dialog). Returns the chosen path, or null if cancelled/failed. */
  private async string? choose_folder () {
    var dialog = new Gtk.FileDialog ();
    try {
      var folder = yield dialog.select_folder (window, null);
      return folder != null ? folder.get_path () : null;
    } catch (Error e) {
      return null;
    }
  }

  /**
   * Builds the primary (hamburger) menu once, at construction — its
   * Save/Save as… group is kept in sync afterwards via set_active_state()
   * rather than being rebuilt lazily on open (see the fields' own
   * comment).
   */
  private void build_primary_menu () {
    var popover = new Gtk.Popover ();
    var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

    box.append (build_theme_selector ());
    box.append (ContextMenu.separator ());

    box.append (ContextMenu.item (_("New File"), () => editor_pane.new_untitled (), popover, Gtk.accelerator_get_label (Gdk.Key.n, Gdk.ModifierType.CONTROL_MASK)));
    box.append (ContextMenu.item (_("New Window"), () => new_window_requested (), popover, Gtk.accelerator_get_label (Gdk.Key.n, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)));
    box.append (ContextMenu.separator ());
    box.append (ContextMenu.item (_("Open File…"), () => on_open_file_requested.begin (), popover, Gtk.accelerator_get_label (Gdk.Key.o, Gdk.ModifierType.CONTROL_MASK)));
    box.append (ContextMenu.item (_("Open Folder…"), () => on_open_folder_requested.begin (), popover, Gtk.accelerator_get_label (Gdk.Key.o, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)));
    close_folder_item = ContextMenu.item (_("Close Folder"), () => unlink_folder (), popover);
    box.append (close_folder_item);

    save_group_separator = ContextMenu.separator ();
    box.append (save_group_separator);
    save_item = ContextMenu.item (_("Save"), () => editor_pane.save_active.begin (), popover, Gtk.accelerator_get_label (Gdk.Key.s, Gdk.ModifierType.CONTROL_MASK));
    box.append (save_item);
    save_as_item = ContextMenu.item (_("Save as…"), () => editor_pane.save_as_active.begin (), popover, Gtk.accelerator_get_label (Gdk.Key.s, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK));
    box.append (save_as_item);

    box.append (ContextMenu.separator ());
    box.append (ContextMenu.item (_("Settings"), () => open_settings (), popover, Gtk.accelerator_get_label (Gdk.Key.comma, Gdk.ModifierType.CONTROL_MASK)));

    popover.child = box;
    // Not the `popover` property: the vapi types it as Gtk.Popover,
    // but the real C setter (gtk_menu_button_set_popover) takes a
    // plain GtkWidget* — the property assignment generates a call
    // that mismatches the real header (-Wincompatible-pointer-types,
    // same vapi/C-header mismatch class as this project's other
    // already-documented warnings). The plain set_popover() method is
    // typed Gtk.Widget? in the vapi, matching the real signature.
    menu_button.set_popover (popover);

    update_save_group ();
    // close_folder_item defaults to visible (a plain Gtk.Button's own
    // default) — this is what actually hides it until a folder is
    // linked; sidebar_toggle_button already starts hidden via the
    // Blueprint's own `visible: false;`, so it doesn't strictly need
    // this call too, but sharing one update function for everything
    // has_linked_folder affects is simpler than two.
    update_folder_dependent_ui ();
  }

  /**
   * Builds the Find menu once, at construction — kept in sync afterwards
   * via update_find_menu() the same way build_primary_menu()'s own
   * Save/Save as… group is, rather than rebuilt lazily on open.
   */
  private void build_find_menu () {
    var popover = new Gtk.Popover ();
    var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

    find_item = ContextMenu.item (_("Find…"), () => open_find (), popover, Gtk.accelerator_get_label (Gdk.Key.f, Gdk.ModifierType.CONTROL_MASK));
    box.append (find_item);
    replace_item = ContextMenu.item (_("Replace…"), () => {
      set_active_bottom_panel (find_bar);
      find_bar.show_replace ();
    }, popover, Gtk.accelerator_get_label (Gdk.Key.h, Gdk.ModifierType.CONTROL_MASK));
    box.append (replace_item);

    box.append (ContextMenu.separator ());
    find_in_files_item = ContextMenu.item (_("Find in Files"), () => open_find_in_files (), popover, Gtk.accelerator_get_label (Gdk.Key.f, Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK));
    box.append (find_in_files_item);

    popover.child = box;
    find_menu_button.set_popover (popover);

    update_find_menu ();
  }

  /**
   * Find…/Replace… only make sense against a real, editable text tab —
   * disabled (not hidden, same sensitive-not-visible split as Save's own
   * "nothing to save yet") while there's no open tab, or the active one
   * is Find Results itself, which has no single-file buffer to search.
   * Find in Files only ever makes sense with something to search across,
   * so it's hidden entirely without a linked folder, not just disabled.
   */
  private void update_find_menu () {
    bool can_find_in_active_tab = has_open_tabs && !editor_pane.is_find_results_active ();
    find_item.sensitive = can_find_in_active_tab;
    replace_item.sensitive = can_find_in_active_tab;
    find_in_files_item.visible = has_linked_folder;
  }

  /**
   * The primary menu's own light/dark/follow-system radio row — three
   * grouped Gtk.CheckButtons, each wired straight to the "style-variant"
   * GLib.Settings key via its own action-name/action-target, with no
   * manual read/write/sync code of our own: GLib.Settings.create_action()
   * already returns a real Gio.Action whose state mirrors the setting
   * both ways. Ported from GNOME Text Editor's own real EditorThemeSelector.
   * The "settings" action-group prefix is inserted on the window itself
   * — a popover attached to a descendant Gtk.MenuButton still resolves
   * action-names up through its attachment widget's own ancestry.
   */
  private Gtk.Widget build_theme_selector () {
    var action = settings.create_action ("style-variant");
    var action_group = new SimpleActionGroup ();
    action_group.add_action (action);
    ((Gtk.Widget) window).insert_action_group ("settings", action_group);

    var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) {
      margin_start = 6, margin_end = 6, margin_top = 6, margin_bottom = 6, hexpand = true,
    };
    box.append (theme_selector_button ("follow", _("Follow System Style")));
    box.append (theme_selector_button ("light", _("Light Style")));
    box.append (theme_selector_button ("dark", _("Dark Style")));
    return box;
  }

  private Gtk.Widget theme_selector_button (string variant, string tooltip_text) {
    var button = new Gtk.CheckButton () {
      hexpand = true,
      halign = Gtk.Align.CENTER,
      focus_on_click = false,
      action_name = "settings.style-variant",
      action_target = new Variant.string (variant),
      tooltip_text = tooltip_text,
    };
    button.add_css_class ("theme-selector");
    button.add_css_class (variant);
    if (theme_selector_group_leader == null) {
      theme_selector_group_leader = button;
    } else {
      button.group = theme_selector_group_leader;
    }
    return button;
  }

  /** Whether the active tab exists/is dirty — drives the primary menu's Save/Save as… group: hidden entirely with no active tab, "Save" itself disabled while it's clean. */
  private void set_active_state (bool has_active_tab, bool dirty) {
    this.has_active_tab = has_active_tab;
    this.active_is_dirty = dirty;
    update_save_group ();
    // Switching tabs (e.g. onto/off of Find Results) changes whether
    // Find…/Replace… apply, even when has_open_tabs itself doesn't.
    update_find_menu ();
  }

  private void update_save_group () {
    save_group_separator.visible = has_active_tab;
    save_item.visible = has_active_tab;
    save_as_item.visible = has_active_tab;
    save_item.sensitive = active_is_dirty;
  }

  /** Shows the window. */
  public void present () {
    window.present ();
  }
}
