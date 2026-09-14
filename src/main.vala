[GtkTemplate (ui = "/io/github/alxmagro/Codi/ui/window.ui")]
public class CodiWindow : Adw.ApplicationWindow {
    public CodiWindow (Gtk.Application app) {
        Object (application: app);
    }
}

int main (string[] args) {
    var app = new Adw.Application ("io.github.alxmagro.Codi", ApplicationFlags.DEFAULT_FLAGS);
    app.activate.connect (() => {
        var window = new CodiWindow (app);
        window.present ();
    });
    return app.run (args);
}
