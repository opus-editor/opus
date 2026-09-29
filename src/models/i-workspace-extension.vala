/**
 * Anything a plugin instantiates once per linked workspace — created by
 * the host (Peas.ExtensionSet.with_properties, via
 * Opus.Plugins.WorkspaceExtensions) with a "context" property set during
 * construction, activated right after, deactivated before teardown.
 * Modeled on gedit's own WindowActivatable pattern.
 *
 * `context` is plain `{ get; set; }`, not `{ get; construct; }`: libpeas
 * validates property names against this interface before ever touching a
 * concrete class, so the property must stay declared here — but a class
 * overriding a `{ get; construct; }` interface property can hit a valac
 * codegen bug (see docs/decisions.md). Plain `{ get; set; }` sidesteps it
 * and still works fine with construction-time property assignment.
 */
public interface IWorkspaceExtension : Object {
  public abstract WorkspaceContext context { get; set; }
  public abstract void activate ();
  public abstract void deactivate ();
}
