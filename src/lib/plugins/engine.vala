/**
 * Owns the single, process-wide libpeas engine — discovers and loads every
 * built-in plugin at startup. `App.startup()` constructs the one instance
 * and sets it as `instance` before any window (and therefore any
 * WorkspaceExtensions) can be built.
 *
 * v1 only ever loads embedded plugins (compiled straight into this same
 * binary, discovered via a GResource `.plugin` manifest — see
 * GIT_STATUS_PLUGIN_PLAN.md) — every plugin is builtin, so there's no
 * enable/disable UI or on-disk plugin directory yet.
 */
namespace Opus.Plugins {
  public class Engine : Object {
    public Peas.Engine peas { get; private set; }

    /** Set once by App.startup(), read by whichever View constructs the first Opus.Plugins.WorkspaceExtensions (currently MainWindow). */
    public static Engine? instance { get; private set; }

    public Engine () {
      peas = Peas.Engine.get_default ();
      peas.add_search_path ("resource:///io/github/nowaos/Opus/plugins", null);
      peas.rescan_plugins ();

      for (uint i = 0; i < peas.get_n_items (); i++) {
        Object item = peas.get_item (i);
        var info = (Peas.PluginInfo) item;
        if (info.is_builtin ()) {
          peas.load_plugin (info);
          Logger.info ("loaded plugin: %s".printf (info.get_module_name ()));
        }
      }

      Engine.instance = this;
    }
  }
}
