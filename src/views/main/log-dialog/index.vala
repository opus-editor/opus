/**
 * A modal showing the raw output of something that failed — the "View
 * Log" behind MainWindow's own error toasts. A read-only CodeEditor
 * under a flat header, the whole sheet painted in the editor's own
 * background so the header reads as part of the text area rather than
 * a bar above it (see styles/log-dialog.css). Zed opens the same
 * output in a tab; a dialog keeps the user on whatever view they were
 * in. Same static shape as Dialogs: each call builds, shows and
 * forgets its own Adw.Dialog, with the editor released once it closes.
 *
 * A first line starting with `$ ` is the command that ran
 * (GitScope.Command's own log format) and is painted in the theme's
 * `string` style, the way Find Results paints its own filenames — the
 * output below it stays plain. Not the bash highlighter over the whole
 * text: git's own stderr isn't shell, and would come out as noise.
 */
public class LogDialog : Object {
  private const string COMMAND_PREFIX = "$ ";
  private const string COMMAND_CAPTURE = "string";

  private LogDialog () {}

  public static void show (Gtk.Widget parent, UserSettings user_settings, string title, string text) {
    var editor = new CodeEditor (user_settings) {
      read_only = true,
      show_line_numbers = false,
      show_indent_guides = false,
    };
    editor.set_text (text, "");

    var syntax_tags = new SyntaxTags (editor.buffer);
    paint_command_line (editor.buffer, syntax_tags);

    var toolbar_view = new Adw.ToolbarView () {
      top_bar_style = Adw.ToolbarStyle.FLAT,
      content = editor.widget,
    };
    toolbar_view.add_top_bar (new Adw.HeaderBar ());

    var dialog = new Adw.Dialog () {
      title = title,
      child = toolbar_view,
      content_width = 720,
      content_height = 420,
      presentation_mode = Adw.DialogPresentationMode.FLOATING,
    };
    dialog.add_css_class ("log-dialog");
    dialog.closed.connect (() => {
      syntax_tags.close ();
      editor.close ();
    });

    GlobalCss.install_from_resource ("/io/github/opus_editor/Opus/styles/log-dialog.css");
    dialog.present (parent);
  }

  private static void paint_command_line (Gtk.TextBuffer buffer, SyntaxTags syntax_tags) {
    Gtk.TextIter start;
    buffer.get_start_iter (out start);
    var end = start;
    end.forward_to_line_end ();
    if (!buffer.get_text (start, end, false).has_prefix (COMMAND_PREFIX)) {
      return;
    }
    buffer.apply_tag (syntax_tags.tag_for (COMMAND_CAPTURE), start, end);
  }
}
