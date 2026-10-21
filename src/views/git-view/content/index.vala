/**
 * The Git activity's main area: a breadcrumb bar over a stack holding
 * the history tree (GitView.TreePane's widget, owned by MainWindow) or a
 * file's diff (GitView.DiffPane, owned here). "History" alone while the
 * tree shows; "History / <commit or WIP> / <file>" while a diff does,
 * "History" being the way back, chevrons between the crumbs, and at
 * the right end an "Open File" button for the file as it is on disk.
 * MainWindow decides what to show and when a live diff must be
 * re-read; this only lays it out.
 */
namespace GitView {
  public class Content : Object {
    private Gtk.Box root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
    private Gtk.Box breadcrumb = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
    private Gtk.Stack stack = new Gtk.Stack ();
    private DiffPane diff_pane;
    private string middle_crumb = "";
    private string file_crumb = "";
    private string shown_path = "";

    /** The "Open File" button: the diff's file (absolute, the right-hand name), to open in the editor. */
    public signal void open_file_requested (string path);

    /** Re-emitted from the diff — see DiffPane.search_position_changed. */
    public signal void search_position_changed (int position, int count);

    /** `search_editor` may be another now: the tree or a diff took the main area, or a diff became a placeholder (or back). */
    public signal void search_editor_changed ();

    /** The diff's editor while a diff shows, else null — see DiffPane.search_editor. */
    public CodeEditor? search_editor { get { return showing == "diff" ? diff_pane.search_editor : null; } }

    /** `search_settings` is the window's one Find query, shared with the editor pane's tabs. */
    public Content (Gtk.Widget tree_widget, UserSettings user_settings, GtkSource.SearchSettings search_settings) {
      diff_pane = new DiffPane (user_settings, search_settings);
      diff_pane.search_position_changed.connect ((position, count) => search_position_changed (position, count));
      diff_pane.notify["mode"].connect (() => search_editor_changed ());
      breadcrumb.add_css_class ("git-breadcrumb");
      stack.add_named (tree_widget, "tree");
      stack.add_named (diff_pane.widget, "diff");
      root.append (breadcrumb);
      root.append (stack);
      rebuild_breadcrumb ();
      GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/git-content.css");
    }

    public Gtk.Widget widget { get { return root; } }

    /** "tree" or "diff" — the debug D-Bus surface. */
    public string showing { owned get { return stack.visible_child_name; } }

    /** "History", or "History / <middle> / <file>" — the debug D-Bus surface. */
    public string breadcrumb_text {
      owned get { return showing == "tree" ? _("History") : "%s / %s / %s".printf (_("History"), middle_crumb, file_crumb); }
    }

    public void show_tree () {
      stack.visible_child_name = "tree";
      rebuild_breadcrumb ();
      search_editor_changed ();
    }

    /** `middle` is the commit's short hash, or "WIP" for the working tree. */
    public void show_diff (GitDiff.Request request, string middle) {
      middle_crumb = middle;
      file_crumb = request.relative_path;
      shown_path = request.path;
      diff_pane.show (request);
      stack.visible_child_name = "diff";
      rebuild_breadcrumb ();
      search_editor_changed ();
    }

    /** See DiffPane.set_file_settings. */
    public void set_file_settings (FileSettings.Registry? registry) {
      diff_pane.set_file_settings (registry);
    }

    /** Re-reads the diff on screen if a side of it is the working tree or the index. */
    public void reload_live_diff () {
      var request = diff_pane.shown_request;
      if (showing == "diff" && request != null && request.is_live) {
        diff_pane.reload ();
      }
    }

    public string[] describe_diff_lines () {
      return diff_pane.describe_lines ();
    }

    /** "diff", "plain" or "placeholder". */
    public string diff_mode {
      owned get { return diff_pane.mode; }
    }

    public string diff_placeholder_title {
      owned get { return diff_pane.placeholder_title; }
    }

    public void close () {
      diff_pane.close ();
    }

    private void rebuild_breadcrumb () {
      Gtk.Widget? child;
      while ((child = breadcrumb.get_first_child ()) != null) {
        breadcrumb.remove (child);
      }
      if (showing == "tree") {
        breadcrumb.append (crumb_label (_("History"), true));
        return;
      }
      var back = new Gtk.Button.with_label (_("History")) { has_frame = false, valign = Gtk.Align.CENTER };
      back.add_css_class ("crumb");
      back.add_css_class ("dimmed");
      back.clicked.connect (show_tree);
      breadcrumb.append (back);
      breadcrumb.append (separator ());
      breadcrumb.append (crumb_label (middle_crumb, false));
      breadcrumb.append (separator ());
      breadcrumb.append (crumb_label (file_crumb, true));
      breadcrumb.append (open_button ());
    }

    /** Flat, pushed to the right end; insensitive when the file is not on disk (deleted, or only in a commit). */
    private Gtk.Widget open_button () {
      var button = new Gtk.Button.from_icon_name ("opus-file-open-symbolic") { has_frame = false, halign = Gtk.Align.END, hexpand = true, valign = Gtk.Align.CENTER };
      button.add_css_class ("crumb-action");
      button.tooltip_text = _("Open File");
      button.sensitive = FileUtils.test (shown_path, FileTest.IS_REGULAR);
      button.clicked.connect (() => open_file_requested (shown_path));
      return button;
    }

    /** A crumb that is not a way anywhere: the same shape as the clickable ones, in the regular weight; dimmed unless it is where we are. */
    private static Gtk.Widget crumb_label (string text, bool current) {
      var label = new Gtk.Label (text) { ellipsize = Pango.EllipsizeMode.MIDDLE, valign = Gtk.Align.CENTER };
      label.add_css_class ("crumb");
      if (!current) {
        label.add_css_class ("dimmed");
      }
      return label;
    }

    private static Gtk.Widget separator () {
      var chevron = new Gtk.Image.from_icon_name ("opus-chevron-right-symbolic");
      chevron.add_css_class ("faint");
      chevron.add_css_class ("crumb-separator");
      return chevron;
    }
  }
}
