/**
 * Small `Gdk.RGBA` color utilities that don't belong to any one widget —
 * kept alongside {@link EditorView}, the only place using them today,
 * rather than in `src/models/` (a plain color transform needs `Gdk`, and
 * models/ stays Gtk/Adw-free on purpose).
 */
namespace EditorColors {
    /**
     * HSL-desaturates `color` toward grayscale by `amount` (0 = unchanged,
     * 1 = fully desaturated), preserving its lightness and alpha —
     * the same operation as Sass's `desaturate($color, amount * 100%)`.
     * `amount`'s default of 1.0 makes this the exact same full
     * desaturation GTK's own real default theme uses for its backdrop
     * (window-inactive) selection color (see `gtk/theme/Default/
     * _colors.scss`: `$backdrop_selected_bg_color: transparentize(
     * desaturate($selected_bg_color, 100%), 0.5)`); EditorView's own
     * search-match highlight instead uses a small `amount` — just enough
     * to keep it visually distinct from the accent-colored selection,
     * without draining the color away entirely.
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
