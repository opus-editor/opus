/**
 * Small `Gdk.RGBA` color utilities that don't belong to any one widget —
 * kept alongside {@link EditorView}, the only place using them today,
 * rather than in `src/models/` (a plain color transform needs `Gdk`, and
 * models/ stays Gtk/Adw-free on purpose).
 */
namespace EditorColors {
    /**
     * HSL-desaturates `color` to grayscale (0 saturation) while
     * preserving its lightness and alpha — the same operation as Sass's
     * `desaturate($color, 100%)`, which GTK's own real default theme
     * uses for its backdrop (window-inactive) selection color (see
     * `gtk/theme/Default/_colors.scss`: `$backdrop_selected_bg_color:
     * transparentize(desaturate($selected_bg_color, 100%), 0.5)`).
     */
    public Gdk.RGBA desaturate (Gdk.RGBA color) {
        float lightness = (float.max (float.max (color.red, color.green), color.blue)
            + float.min (float.min (color.red, color.green), color.blue)) / 2.0f;
        return Gdk.RGBA () { red = lightness, green = lightness, blue = lightness, alpha = color.alpha };
    }
}
