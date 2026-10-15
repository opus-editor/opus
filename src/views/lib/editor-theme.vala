/**
 * The theme the editor is wearing right now: the one settings.json
 * names for the app's current light or dark mode, reloaded when either
 * changes. Every CodeEditor reads its colors from here, so they all
 * switch together.
 *
 * A theme only carries syntax styles (SyntaxTags paints them). The
 * editor's own surfaces — background, text color, line numbers — stay
 * Adwaita's, through the GtkSource.StyleScheme handed out as
 * {@link scheme}.
 */
public class EditorTheme : Object {
  /** Set once by App.startup(), before any window exists. */
  public static EditorTheme? instance { get; set; }

  public Theme theme { get; private set; }

  /** Adwaita's own scheme for the current mode. */
  public GtkSource.StyleScheme? scheme { get; private set; }

  /** `theme` and `scheme` are different now, Syntax.Languages already resolves captures against the new theme, and `styled_captures_changed` says whether painted text is still right. */
  public signal void changed ();

  private UserSettings settings;
  private string[] theme_directories;

  /** Whether the last change moved a capture between styled and unstyled (see Syntax.Languages.set_style_keys) — what tells SyntaxTags that restyling in place isn't enough. */
  public bool styled_captures_changed { get; private set; }

  // What the last reload loaded — a mode as well as a name, since
  // nothing stops settings.json naming one theme for both modes.
  private string? loaded_name;
  private bool loaded_dark;

  /** `theme_directories` in rising precedence (see Theme.load()). */
  public EditorTheme (UserSettings settings, string[] theme_directories) {
    this.settings = settings;
    this.theme_directories = theme_directories;

    settings.changed.connect (reload);
    Adw.StyleManager.get_default ().notify["dark"].connect (reload);
    reload ();
  }

  private void reload () {
    bool dark = Adw.StyleManager.get_default ().dark;
    var name = settings.theme_syntax;
    // settings.changed fires for every key; only a different theme is news here.
    if (name == loaded_name && dark == loaded_dark) {
      return;
    }
    loaded_name = name;
    loaded_dark = dark;

    theme = load (name, dark);
    apply_editor_foreground ();
    scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "Adwaita-dark" : "Adwaita");
    styled_captures_changed = Syntax.Languages.instance.set_style_keys (theme.style_keys ());
    changed ();
  }

  private Gtk.CssProvider? foreground_provider = null;

  /** The theme's own text color for every CodeEditor, as one stylesheet over the window's text color — gone again for a theme that leaves it to the window. */
  private void apply_editor_foreground () {
    if (foreground_provider != null) {
      GlobalCss.uninstall (foreground_provider);
      foreground_provider = null;
    }
    if (theme.editor_foreground != null) {
      // One priority above the app's stylesheets: among providers of the
      // same priority GTK lets the one installed last win, whatever the
      // selectors say, and this one is installed at startup, before the
      // window installs common.css — the theme's color only showed up
      // once a theme switch reinstalled this after it.
      foreground_provider = GlobalCss.install_from_string ("textview.code-editor { color: %s; }".printf (theme.editor_foreground), Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    }
  }

  /** The named theme, else the bundled one for this mode, else none at all — a typo in settings.json must not cost the editor its colors. */
  private Theme load (string name, bool dark) {
    string[] candidates = { name, UserSettings.DEFAULT_THEME_SYNTAX };
    foreach (unowned string candidate in candidates) {
      try {
        return Theme.load (theme_directories, candidate, dark);
      } catch (ThemeError e) {
        Logger.warn ("theme \"%s\": %s".printf (candidate, e.message));
      }
    }
    return new Theme.empty ();
  }
}
