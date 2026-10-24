/**
 * The header's "Document Properties" pane, to the content's right —
 * GNOME Text Editor's own panel (editor-properties-panel.ui), its first
 * group: what the active document is, and how it is written out.
 * MainWindow hands it the document (show()) and it reads the rest off
 * that; what the user picks here goes back out as signals, for
 * MainWindow to put on the active tab — the pane never writes to the
 * document itself.
 */
public class DocumentPanel : Object {
  private Adw.PreferencesPage page;
  private Adw.ActionRow name_row;
  private Adw.ActionRow location_row;
  private Adw.ActionRow language_row;
  private Adw.SwitchRow word_wrap_row;
  private Adw.ComboRow encoding_row;
  private Adw.ComboRow line_ending_row;

  private Document? document = null;
  private string? language_title = null;
  private bool word_wrap = false;
  private ulong[] document_handlers = {};
  // The combos are set from the document too; only the user's own picks go back out.
  private bool refreshing = false;

  public Gtk.Widget widget { get { return page; } }

  /** The "Document Type" row: the user wants to pick the language. */
  public signal void language_change_requested ();
  /** The "Word Wrap" switch: for this tab only, the way Alt+W is. */
  public signal void word_wrap_chosen (bool wrap);
  public signal void line_ending_chosen (Document.LineEnding line_ending);
  public signal void charset_chosen (Document.Charset charset);
  /** The "Location" row: the file at `path` is to be shown in its folder. */
  public signal void location_activated (string path);

  public DocumentPanel () {
    var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/main/document-panel/index.ui");
    page = (Adw.PreferencesPage) builder.get_object ("page");
    name_row = (Adw.ActionRow) builder.get_object ("name_row");
    location_row = (Adw.ActionRow) builder.get_object ("location_row");
    language_row = (Adw.ActionRow) builder.get_object ("language_row");
    word_wrap_row = (Adw.SwitchRow) builder.get_object ("word_wrap_row");
    encoding_row = (Adw.ComboRow) builder.get_object ("encoding_row");
    line_ending_row = (Adw.ComboRow) builder.get_object ("line_ending_row");

    // In Document.Charset's and Document.LineEnding's own order: the selected index is the enum value.
    encoding_row.model = string_list ({ "UTF-8", _("UTF-8 with BOM"), _("Western (ISO-8859-1)"), "UTF-16 BE", "UTF-16 LE" });
    line_ending_row.model = string_list ({ _("Unix/Linux (LF)"), _("Windows (CR+LF)") });
    encoding_row.list_factory = popup_factory (encoding_row);
    line_ending_row.list_factory = popup_factory (line_ending_row);

    location_row.activated.connect (() => {
      if (document != null && document.pathname != null) {
        location_activated (document.pathname);
      }
    });
    language_row.activated.connect (() => language_change_requested ());
    word_wrap_row.notify["active"].connect (() => {
      if (!refreshing && document != null) {
        word_wrap_chosen (word_wrap_row.active);
      }
    });
    encoding_row.notify["selected"].connect (() => {
      if (!refreshing && document != null) {
        charset_chosen ((Document.Charset) encoding_row.selected);
      }
    });
    line_ending_row.notify["selected"].connect (() => {
      if (!refreshing && document != null) {
        line_ending_chosen ((Document.LineEnding) line_ending_row.selected);
      }
    });
    refresh ();
  }

  /**
   * `document` is the active tab's, null with none (or with a tab that
   * isn't a document). `language_title` is what it is highlighted as,
   * null for plain text, and `word_wrap` whether its lines wrap right
   * now — both resolved by the caller, since they live on the tab's
   * editor: the language depends on the file's name and first line
   * without an override, and the wrap on `editor.word_wrap` without one.
   */
  public void show (Document? document, string? language_title, bool word_wrap) {
    if (this.document != document) {
      follow (document);
    }
    this.language_title = language_title;
    this.word_wrap = word_wrap;
    refresh ();
  }

  /** Name and path change on a "Save As"; line ending and charset on a save that applies the folder's .editorconfig. */
  private void follow (Document? next) {
    foreach (var handler in document_handlers) {
      document.disconnect (handler);
    }
    document_handlers = {};
    document = next;
    if (next == null) {
      return;
    }
    foreach (var property in new string[] { "name", "pathname", "line-ending", "charset", "readable" }) {
      document_handlers += next.notify[property].connect (() => refresh ());
    }
  }

  /** Appended one by one: the vapi's own Gtk.StringList constructor takes a `string[]` the C header types `const char* const*`, which gcc warns about. */
  private static Gtk.StringList string_list (string[] items) {
    var list = new Gtk.StringList (null);
    foreach (var item in items) {
      list.append (item);
    }
    return list;
  }

  /**
   * The popup's own rows: libadwaita's default (adw-combo-row.c,
   * setup_item) puts the check right after the text, which lines them up
   * unevenly; this one keeps the text and the check at the row's two
   * ends. Only the popup: the closed row keeps the default factory,
   * which already hides the check outside the popover.
   */
  private static Gtk.SignalListItemFactory popup_factory (Adw.ComboRow row) {
    var factory = new Gtk.SignalListItemFactory ();
    factory.setup.connect ((object) => {
      var item = (Gtk.ListItem) object;
      var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
      box.append (new Gtk.Label (null) { xalign = 0, hexpand = true });
      box.append (new Gtk.Image.from_icon_name ("object-select-symbolic"));
      item.child = box;
    });
    factory.bind.connect ((object) => {
      var item = (Gtk.ListItem) object;
      var box = (Gtk.Box) item.child;
      ((Gtk.Label) box.get_first_child ()).label = ((Gtk.StringObject) item.item).string;
      var check = box.get_last_child ();
      check.opacity = row.selected_item == item.item ? 1 : 0;
      item.set_data<ulong> ("selected-handler", row.notify["selected-item"].connect (() => {
        check.opacity = row.selected_item == item.item ? 1 : 0;
      }));
    });
    factory.unbind.connect ((object) => {
      var item = (Gtk.ListItem) object;
      row.disconnect (item.get_data<ulong> ("selected-handler"));
    });
    return factory;
  }

  private void refresh () {
    refreshing = true;
    page.sensitive = document != null;
    name_row.subtitle = document == null ? "" : document.name;
    string? folder = document == null || document.pathname == null ? null : Path.get_dirname (document.pathname);
    location_row.subtitle = folder ?? "";
    location_row.sensitive = folder != null;
    language_row.subtitle = document == null ? "" : language_title ?? _("Plain Text");
    word_wrap_row.active = document != null && word_wrap;
    bool writable = document != null && document.readable;
    encoding_row.sensitive = writable;
    line_ending_row.sensitive = writable;
    encoding_row.selected = document == null ? 0 : document.charset;
    line_ending_row.selected = document == null ? 0 : document.line_ending;
    refreshing = false;
  }
}
