/**
 * Aggregates every registered FileDecoration.IProvider's own decorations
 * into one resolved picture per path — the generic "given N providers,
 * pick a winner, bubble it up folders" logic VS Code keeps as a
 * provider-agnostic core service (DecorationsService), not something any
 * one provider (git or otherwise) should reimplement. One instance per
 * linked workspace.
 */
namespace FileDecoration {
  public class Registry : Object {
    private string root_path;
    private GenericArray<IProvider> providers = new GenericArray<IProvider> ();

    // Rebuilt from scratch on every recompute() — cheap at realistic
    // provider/change-set sizes, and simpler than trying to incrementally
    // patch two maps whose contents depend on every provider at once.
    private HashTable<string, State> direct = new HashTable<string, State> (str_hash, str_equal);
    private HashTable<string, State> bubbled = new HashTable<string, State> (str_hash, str_equal);

    /** The resolved picture changed somewhere — whole-snapshot; the caller diffs against what it last rendered. */
    public signal void changed ();

    public Registry (string root_path) {
      this.root_path = root_path;
    }

    /** A no-op if `provider` is already registered — guards against a duplicate add_provider() ever double-connecting decorations_changed and double-counting that provider's own entries in merge_direct(). */
    public void add_provider (IProvider provider) {
      uint existing_index;
      if (providers.find (provider, out existing_index)) {
        return;
      }
      providers.add (provider);
      provider.decorations_changed.connect (recompute);
      recompute ();
    }

    public void remove_provider (IProvider provider) {
      providers.remove (provider);
      provider.decorations_changed.disconnect (recompute);
      recompute ();
    }

    /** Resolved decoration for a row, or null when there's nothing to show. Cheap: one or two HashTable lookups. */
    public State? decoration_for (string path, bool is_directory) {
      if (!is_directory) {
        return direct[path];
      }

      var own = direct[path];
      var inherited = bubbled[path];
      if (own == null) {
        return inherited;
      }
      if (inherited == null || (int) own.tone >= (int) inherited.tone) {
        return own; // direct wins ties
      }
      return inherited;
    }

    private void recompute () {
      var new_direct = new HashTable<string, State> (str_hash, str_equal);
      var new_bubbled = new HashTable<string, State> (str_hash, str_equal);

      foreach (var provider in providers) {
        var entries = provider.current_decorations ();
        foreach (var path in entries.get_keys ()) {
          var state = entries[path];
          merge_direct (new_direct, path, state);
          if (state.propagate) {
            bubble (new_bubbled, path, state);
          }
        }
      }

      direct = new_direct;
      bubbled = new_bubbled;
      changed ();
    }

    /**
     * Highest tone wins across providers; a strict tie merges tooltips
     * (distinct, non-null ones joined with " • " — the same rule VS
     * Code's own DecorationStyles.asDecoration uses) rather than
     * silently dropping one.
     */
    private static void merge_direct (HashTable<string, State> table, string path, State incoming) {
      var existing = table[path];
      if (existing == null || (int) incoming.tone > (int) existing.tone) {
        table[path] = incoming;
        return;
      }
      if ((int) incoming.tone == (int) existing.tone && incoming.tooltip != null && incoming.tooltip != existing.tooltip) {
        var joined_tooltip = existing.tooltip == null ? incoming.tooltip : "%s • %s".printf (existing.tooltip, incoming.tooltip);
        table[path] = new State (existing.tone, joined_tooltip, existing.bubble_tooltip, existing.propagate);
      }
    }

    /** Walks every ancestor of `path`'s own directory up to (and including) root_path, keeping the highest tone seen at each level — same algorithm GIT_STATUS_PLAN.md's original GitStatus model used for its own dir_status, moved here since it's generic across every provider, not just git. */
    private void bubble (HashTable<string, State> table, string path, State state) {
      var dir = Path.get_dirname (path);
      while (dir.length >= root_path.length && dir.has_prefix (root_path)) {
        var existing = table[dir];
        if (existing == null || (int) state.tone > (int) existing.tone) {
          table[dir] = state;
        }
        if (dir == root_path) {
          break;
        }
        dir = Path.get_dirname (dir);
      }
    }
  }
}
