namespace CommandBar {
  /** Every registered {@link IProvider}, and which one a typed text belongs to: the longest non-empty prefix the text starts with, else the `""` provider. One per window. */
  public class Registry : Object {
    private GenericArray<IProvider> providers = new GenericArray<IProvider> ();

    public signal void changed ();

    /** A no-op if `provider` is already registered — same guard FileDecoration.Registry.add_provider keeps. */
    public void add (IProvider provider) {
      uint existing_index;
      if (providers.find (provider, out existing_index)) {
        return;
      }
      providers.add (provider);
      changed ();
    }

    public void remove (IProvider provider) {
      if (providers.remove (provider)) {
        changed ();
      }
    }

    public IProvider? resolve (string text) {
      IProvider? best = null;
      IProvider? fallback = null;
      for (uint i = 0; i < providers.length; i++) {
        var provider = providers[i];
        if (provider.prefix == "") {
          fallback = provider;
          continue;
        }
        if (text.has_prefix (provider.prefix) && (best == null || provider.prefix.length > best.prefix.length)) {
          best = provider;
        }
      }
      return best ?? fallback;
    }

    public GenericArray<IProvider> all () {
      var copy = new GenericArray<IProvider> ();
      for (uint i = 0; i < providers.length; i++) {
        copy.add (providers[i]);
      }
      return copy;
    }
  }
}
