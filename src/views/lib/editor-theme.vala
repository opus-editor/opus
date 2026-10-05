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

  /** `theme` and `scheme` are different now, and Syntax.Languages already resolves captures against the new theme. */
  public signal void changed ();

  private UserSettings settings;
  private string[] theme_directories;
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
    var name = dark ? settings.theme_dark : settings.theme_light;
    // settings.changed fires for every key; only a different theme is news here.
    if (name == loaded_name && dark == loaded_dark) {
      return;
    }
    loaded_name = name;
    loaded_dark = dark;

    theme = load (name, dark);
    scheme = GtkSource.StyleSchemeManager.get_default ().get_scheme (dark ? "Adwaita-dark" : "Adwaita");
    Syntax.Languages.instance.set_style_keys (theme.style_keys ());
    changed ();
  }

  /** The named theme, else the bundled one for this mode, else none at all — a typo in settings.json must not cost the editor its colors. */
  private Theme load (string name, bool dark) {
    string[] candidates = { name, dark ? UserSettings.DEFAULT_THEME_DARK : UserSettings.DEFAULT_THEME_LIGHT };
    foreach (unowned string candidate in candidates) {
      try {
        return Theme.load (theme_directories, candidate);
      } catch (ThemeError e) {
        Logger.warn ("theme \"%s\": %s".printf (candidate, e.message));
      }
    }
    return new Theme.empty ();
  }
}
