/**
 * One IWorkspaceExtension instance per loaded plugin providing
 * `extension_type`, for one workspace — a thin owner of a
 * Peas.ExtensionSet that also runs activate()/deactivate() for it. Keeps
 * `Peas` out of the View layer entirely: MainWindow only ever sees
 * `added`/`removed` handing it plain IWorkspaceExtension objects.
 */
namespace Opus.Plugins {
  public class WorkspaceExtensions : Object {
    private Peas.ExtensionSet extension_set;
    private bool closed = false;

    /** A plugin providing `extension_type` was just instantiated for this workspace — already activate()d by the time this fires. */
    public signal void added (IWorkspaceExtension extension);

    /** A plugin's own extension for this workspace is about to go away — not yet deactivate()d; the handler is expected to do nothing further, deactivate() already ran. */
    public signal void removed (IWorkspaceExtension extension);

    public WorkspaceExtensions (GLib.Type extension_type, WorkspaceContext context) {
      extension_set = new Peas.ExtensionSet.with_properties (
        Engine.instance.peas, extension_type, { "context" }, { context }
      );
      extension_set.extension_added.connect (on_extension_added);
      extension_set.extension_removed.connect (on_extension_removed);

      // Peas.ExtensionSet.with_properties() itself already instantiates
      // (and internally fires its own extension_added for) every plugin
      // providing extension_type that's already loaded by this exact
      // point — before the two connect() calls just above can ever see
      // it. activate() still happens here, right away; announcing them
      // via this class's own added() is deferred one main-loop turn
      // (Idle.add()) instead of firing inline — a constructor can't
      // usefully fire a signal its own caller has had no chance to
      // connect to yet, and by the time this Idle callback actually
      // runs, any real caller (constructs this, then connects
      // added()/removed() synchronously right after, same statement
      // block) already has. `closed` guards against this same callback
      // firing into a meanwhile-torn-down instance.
      for (uint i = 0; i < extension_set.get_n_items (); i++) {
        Object item = extension_set.get_item (i);
        ((IWorkspaceExtension) item).activate ();
      }

      Idle.add (() => {
        if (closed) {
          return Source.REMOVE;
        }
        for (uint i = 0; i < extension_set.get_n_items (); i++) {
          Object item = extension_set.get_item (i);
          added ((IWorkspaceExtension) item);
        }
        return Source.REMOVE;
      });
    }

    private void on_extension_added (Peas.PluginInfo info, Object extension_object) {
      var extension = (IWorkspaceExtension) extension_object;
      extension.activate ();
      added (extension);
    }

    private void on_extension_removed (Peas.PluginInfo info, Object extension_object) {
      var extension = (IWorkspaceExtension) extension_object;
      removed (extension);
      extension.deactivate ();
    }

    /**
     * Announces (removed()) then deactivates every extension this set
     * currently holds, then drops the set itself. Call before discarding
     * this object. Disconnects extension_set's own signals first so
     * libpeas emitting extension-removed while this set is being
     * disposed can't re-enter on_extension_removed() and deactivate()
     * the same extension twice.
     */
    public void close () {
      closed = true;
      extension_set.extension_added.disconnect (on_extension_added);
      extension_set.extension_removed.disconnect (on_extension_removed);

      for (uint i = 0; i < extension_set.get_n_items (); i++) {
        Object item = extension_set.get_item (i);
        var extension = (IWorkspaceExtension) item;
        removed (extension);
        extension.deactivate ();
      }
    }
  }
}
