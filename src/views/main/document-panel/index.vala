/**
 * The header's "Document Properties" pane, to the content's right —
 * GNOME Text Editor's own panel (editor-properties-panel.ui): what the
 * active document is and how it is written out, then how it indents.
 * MainWindow hands it the Document (show()) and it reads everything
 * off that, following its changes; what the user picks here goes back
 * out as signals, for MainWindow to put on the active tab — the pane
 * never writes to the document itself.
 */
public class DocumentPanel : Object {
  private Adw.PreferencesPage page;
  private Adw.ActionRow name_row;
  private Adw.ActionRow location_row;
  private Adw.ActionRow language_row;
  private Adw.SwitchRow word_wrap_row;
  private Adw.ComboRow encoding_row;
  private Adw.ComboRow line_ending_row;
  private Adw.SwitchRow auto_indent_row;
  private Adw.ComboRow indent_style_row;
  private Adw.ActionRow indent_size_row;
  private Adw.ActionRow tab_width_row;

  private UserSettings settings;
  private Document? document = null;
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
  /** The indentation rows, each for this tab only — see Indentation.resolve. */
  public signal void auto_indent_chosen (bool on);
  public signal void insert_spaces_chosen (bool spaces);
  /** The "Indent Size" and "Tab Width" rows: the user wants to pick a number. */
  public signal void indent_size_change_requested ();
  public signal void tab_width_change_requested ();

  public DocumentPanel (UserSettings settings) {
    this.settings = settings;
    // A document without a word wrap of its own follows `editor.word_wrap` when settings.json is rewritten.
    settings.changed.connect (refresh);
    var builder = new Gtk.Builder.from_resource ("/io/github/opus_editor/Opus/main/document-panel/index.ui");
    page = (Adw.PreferencesPage) builder.get_object ("page");
    name_row = (Adw.ActionRow) builder.get_object ("name_row");
    location_row = (Adw.ActionRow) builder.get_object ("location_row");
    language_row = (Adw.ActionRow) builder.get_object ("language_row");
    word_wrap_row = (Adw.SwitchRow) builder.get_object ("word_wrap_row");
    encoding_row = (Adw.ComboRow) builder.get_object ("encoding_row");
    line_ending_row = (Adw.ComboRow) builder.get_object ("line_ending_row");
    auto_indent_row = (Adw.SwitchRow) builder.get_object ("auto_indent_row");
    indent_style_row = (Adw.ComboRow) builder.get_object ("indent_style_row");
    indent_size_row = (Adw.ActionRow) builder.get_object ("indent_size_row");
    tab_width_row = (Adw.ActionRow) builder.get_object ("tab_width_row");

    // In Document.Charset's and Document.LineEnding's own order: the selected index is the enum value.
    encoding_row.model = string_list ({ "UTF-8", _("UTF-8 with BOM"), _("Western (ISO-8859-1)"), "UTF-16 BE", "UTF-16 LE" });
    line_ending_row.model = string_list ({ _("Unix/Linux (LF)"), _("Windows (CR+LF)") });
    encoding_row.list_factory = popup_factory (encoding_row);
    line_ending_row.list_factory = popup_factory (line_ending_row);
    indent_style_row.model = string_list ({ _("Space"), _("Tab") });
    indent_style_row.list_factory = popup_factory (indent_style_row);

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
    auto_indent_row.notify["active"].connect (() => {
      if (!refreshing && document != null) {
        auto_indent_chosen (auto_indent_row.active);
      }
    });
    indent_style_row.notify["selected"].connect (() => {
      if (!refreshing && document != null) {
        insert_spaces_chosen (indent_style_row.selected == 0);
      }
    });
    indent_size_row.activated.connect (() => indent_size_change_requested ());
    tab_width_row.activated.connect (() => tab_width_change_requested ());
    refresh ();
  }

  /** `document` is the active tab's, null with none (or with a tab that isn't a document). */
  public void show (Document? document) {
    if (this.document != document) {
      follow (document);
    }
    refresh ();
  }

  /** Name, path and language change on a "Save As"; line ending and charset on a save that applies the folder's .editorconfig; language and word wrap when picked by hand; the indentation whenever its tab resolves it again. */
  private void follow (Document? next) {
    foreach (var handler in document_handlers) {
      document.disconnect (handler);
    }
    document_handlers = {};
    document = next;
    if (next == null) {
      return;
    }
    foreach (var property in new string[] { "name", "pathname", "language", "word-wrap-override", "indentation", "line-ending", "charset", "readable" }) {
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

  /** The width, and where it came from when nothing set it apart. */
  private static string tab_width_subtitle (Indentation? indentation) {
    if (indentation == null) {
      return "";
    }
    if (indentation.tab_width_from_size) {
      return _("Same as Indent Size");
    }
    return indentation.tab_width.to_string ();
  }

  private string? language_title () {
    return document.language == null ? null : Syntax.Languages.instance.title_of (document.language);
  }

  /** The document's own override, else `editor.word_wrap` for its language — what its editor shows. */
  private bool word_wrap () {
    if (document.word_wrap_override == Document.Override.NONE) {
      return settings.word_wrap_for (document.language);
    }
    return document.word_wrap_override == Document.Override.ON;
  }

  private void refresh () {
    refreshing = true;
    page.sensitive = document != null;
    name_row.subtitle = document == null ? "" : document.name;
    string? folder = document == null || document.pathname == null ? null : Path.get_dirname (document.pathname);
    location_row.subtitle = folder ?? "";
    location_row.sensitive = folder != null;
    language_row.subtitle = document == null ? "" : language_title () ?? _("Plain Text");
    word_wrap_row.active = document != null && word_wrap ();
    bool writable = document != null && document.readable;
    encoding_row.sensitive = writable;
    line_ending_row.sensitive = writable;
    encoding_row.selected = document == null ? 0 : document.charset;
    line_ending_row.selected = document == null ? 0 : document.line_ending;
    var indentation = document == null ? null : document.indentation;
    auto_indent_row.active = indentation != null && indentation.auto_indent;
    indent_style_row.selected = indentation == null || indentation.insert_spaces ? 0 : 1;
    indent_size_row.subtitle = indentation == null ? "" : indentation.size.to_string ();
    tab_width_row.subtitle = tab_width_subtitle (indentation);
    refreshing = false;
  }
}
