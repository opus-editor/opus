namespace FileSettings {
  /** Every registered provider's word on a file, field by field: the last provider registered that has one wins. One per linked workspace. */
  public class Registry : Object {
    private GenericArray<IProvider> providers = new GenericArray<IProvider> ();

    /** Some provider's answers changed: whoever applied settings_for() once should ask again. */
    public signal void changed ();

    public void add_provider (IProvider provider) {
      uint existing_index;
      if (providers.find (provider, out existing_index)) {
        return;
      }
      providers.add (provider);
      provider.changed.connect (on_provider_changed);
    }

    public void remove_provider (IProvider provider) {
      if (providers.remove (provider)) {
        provider.changed.disconnect (on_provider_changed);
      }
    }

    private void on_provider_changed () {
      changed ();
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
