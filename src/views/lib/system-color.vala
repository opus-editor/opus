/**
 * A small, chainable color builder shared by more than one editor
 * sub-component (TextEditorCursors' own selection color,
 * TextEditorSearch's own match colors) — nothing about it is specific to
 * either, so it lives here rather than in one and imported by the other.
 * Needs `Adw` (from_accent()), so views/lib/ — not models/ or a
 * Gdk-only src/lib/ — is where this belongs.
 *
 * `desaturate()` returns a new instance (safe to branch off the same
 * base color into several independent variants); `transparentize()`
 * mutates in place and returns `this` instead, since it's always the
 * last step of a chain right before `to_rgba()` — nothing is ever
 * branched off *after* it, so there's nothing for in-place mutation to
 * accidentally corrupt.
 */
public class SystemColor : Object {
  private Gdk.RGBA rgba;

  private SystemColor (Gdk.RGBA rgba) {
    this.rgba = rgba;
  }

  /** The current system accent color — `Adw.AccentColor.to_rgba()`, not the nullable `Adw.StyleManager.get_accent_color_rgba()` convenience method: the two are documented as equivalent, but this one never needs a fallback value for a case that doesn't actually happen. */
  public static SystemColor from_accent () {
    return new SystemColor (Adw.StyleManager.get_default ().get_accent_color ().to_rgba ());
  }

  /**
   * HSL-desaturates this color toward grayscale by `amount` (0 =
   * unchanged, 1 = fully desaturated), preserving its lightness and
   * alpha — the same operation as Sass's `desaturate($color, amount *
   * 100%)`. `amount`'s default of 1.0 makes this the exact same full
   * desaturation GTK's own real default theme uses for its backdrop
   * (window-inactive) selection color; TextEditorSearch's own match
   * highlight instead uses a small `amount` — just enough to keep it
   * visually distinct from the accent-colored selection, without
   * draining the color away entirely.
   */
  public SystemColor desaturate (float amount = 1.0f) {
    float lightness = (float.max (float.max (rgba.red, rgba.green), rgba.blue)
      + float.min (float.min (rgba.red, rgba.green), rgba.blue)) / 2.0f;
    return new SystemColor (Gdk.RGBA () {
      red = rgba.red + (lightness - rgba.red) * amount,
      green = rgba.green + (lightness - rgba.green) * amount,
      blue = rgba.blue + (lightness - rgba.blue) * amount,
      alpha = rgba.alpha,
    });
  }

  /** Sets this color's own alpha and returns `this`, so it chains straight into a call site's own `to_rgba()` with no extra local variable. */
  public SystemColor transparentize (float alpha) {
    rgba.alpha = alpha;
    return this;
  }

  public Gdk.RGBA to_rgba () {
    return rgba;
  }
}
