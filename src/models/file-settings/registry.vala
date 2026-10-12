namespace FileSettings {
  /** Every registered provider's word on a file, field by field: the last provider registered that has one wins. One per linked workspace. */
  public class Registry : Object {
    private GenericArray<IProvider> providers = new GenericArray<IProvider> ();

    public void add_provider (IProvider provider) {
      uint existing_index;
      if (providers.find (provider, out existing_index)) {
        return;
      }
      providers.add (provider);
    }

    public void remove_provider (IProvider provider) {
      providers.remove (provider);
    }

    public Values settings_for (string path) {
      var values = new Values ();
      foreach (var provider in providers) {
        values.take (provider.settings_for (path));
      }
      return values;
    }
  }
}
