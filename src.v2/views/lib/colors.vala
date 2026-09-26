/**
 * Small color utilities shared by more than one editor sub-component
 * (TextEditorCursors' own selection color, TextEditorSearch's own match
 * colors) — nothing about them is specific to either, so they live here
 * rather than in one and imported by the other. Needs `Adw`
 * (accent_color()), so views/lib/ — not models/ or a Gdk-only src/lib/ —
 * is where this belongs; see the conversation this came out of for the
 * back-and-forth that landed here.
 */
namespace Colors {
    /** The current system accent color — `Adw.AccentColor.to_rgba()`, not the nullable `Adw.StyleManager.get_accent_color_rgba()` convenience method: the two are documented as equivalent, but this one never needs a fallback value for a case that doesn't actually happen. */
    public Gdk.RGBA accent_color () {
        return Adw.StyleManager.get_default ().get_accent_color ().to_rgba ();
    }

    /**
     * HSL-desaturates `color` toward grayscale by `amount` (0 = unchanged,
     * 1 = fully desaturated), preserving its lightness and alpha — the
     * same operation as Sass's `desaturate($color, amount * 100%)`.
     * `amount`'s default of 1.0 makes this the exact same full
     * desaturation GTK's own real default theme uses for its backdrop
     * (window-inactive) selection color; TextEditorSearch's own match
     * highlight instead uses a small `amount` — just enough to keep it
     * visually distinct from the accent-colored selection, without
     * draining the color away entirely.
     */
    public Gdk.RGBA desaturate (Gdk.RGBA color, float amount = 1.0f) {
        float lightness = (float.max (float.max (color.red, color.green), color.blue)
            + float.min (float.min (color.red, color.green), color.blue)) / 2.0f;
        return Gdk.RGBA () {
            red = color.red + (lightness - color.red) * amount,
            green = color.green + (lightness - color.green) * amount,
            blue = color.blue + (lightness - color.blue) * amount,
            alpha = color.alpha,
        };
    }
}
