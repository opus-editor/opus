/**
 * A sorted ListStore of GitScope.Change, brought in line with each fresh
 * GitScope.WorkingTree by set_changes(): a merge of two sorted lists, not
 * a clear-and-refill, so only rows that actually came or went touch the
 * store, and a list's selection, keyboard focus and scroll stay put on
 * everything else — a refresh that changes nothing changes nothing.
 * Switching folders is the one case the old rows mean nothing any more.
 *
 * set_sort_key() ports VS Code's own three SCM sort orders
 * (`scm.defaultViewSortKey`, List mode — see scmViewPane.ts's own
 * SCMTreeSorter.compare()): "name" (bare file name), "status" (by
 * GitScope.Change.label, falling back to "path" order for two changes
 * with the same label — same tie-break VS Code's own comparator falls
 * through to), and "path" (default — every path segment compared in
 * turn; within a shared prefix, whichever path ends first, i.e. is
 * shallower, sorts first).
 */
namespace GitView {
  public class ChangeStore : Object {
    public ListStore store { get; private set; default = new ListStore (typeof (GitScope.Change)); }
    // Every GitScope.Change.path is absolute — compare_changes() strips
    // this back off to sort by relative path.
    private string root_path = "";
    private string sort_key = "path";

    public bool has_items { get { return store.get_n_items () > 0; } }

    public GitScope.Change at (uint position) {
      return (GitScope.Change) store.get_item (position);
    }

    /** Every row's own Change, in list order. */
    public GenericArray<GitScope.Change> all_changes () {
      var result = new GenericArray<GitScope.Change> ();
      for (uint i = 0; i < store.get_n_items (); i++) {
        result.add (at (i));
      }
      return result;
    }

    /** The row for `path` (absolute), -1 with none. */
    public int index_of (string path) {
      for (uint i = 0; i < store.get_n_items (); i++) {
        if (at (i).path == path) {
          return (int) i;
        }
      }
      return -1;
    }

    public void set_changes (GenericArray<GitScope.Change> changes, string root_path) {
      if (this.root_path != root_path) {
        this.root_path = root_path;
        store.remove_all ();
      }
      var sorted = copy_sorted (changes);

      uint i = 0;
      uint j = 0;
      while (j < sorted.length) {
        if (i >= store.get_n_items ()) {
          store.append (sorted[j++]);
          i++;
          continue;
        }
        var current = at (i);
        var incoming = sorted[j];
        int order = compare_changes (current, incoming);
        if (order == 0 && current.kind == incoming.kind) {
          i++;
          j++;
        } else if (order <= 0) {
          store.remove (i);
        } else {
          store.insert (i++, incoming);
          j++;
        }
      }
      while (i < store.get_n_items ()) {
        store.remove (i);
      }
    }

    private GenericArray<GitScope.Change> copy_sorted (GenericArray<GitScope.Change> changes) {
      var sorted = new GenericArray<GitScope.Change> ();
      for (uint i = 0; i < changes.length; i++) {
        sorted.add (changes[i]);
      }
      sorted.sort_with_data ((a, b) => compare_changes (a, b));
      return sorted;
    }

    /** "name"/"path"/"status" — UserSettings.changes_sort's own values. Anything else behaves as "path". Re-sorts the rows already there, same as VS Code's own live "Sort Changes by…" menu. */
    public void set_sort_key (string key) {
      if (sort_key == key) {
        return;
      }
      sort_key = key;
      store.sort (compare_changes);
    }

    private int compare_changes (Object a_object, Object b_object) {
      var a = (GitScope.Change) a_object;
      var b = (GitScope.Change) b_object;

      if (sort_key == "name") {
        return compare_names (Path.get_basename (a.path), Path.get_basename (b.path));
      }
      if (sort_key == "status" && a.label != b.label) {
        return a.label < b.label ? -1 : 1;
      }
      return compare_paths (relative_path (a.path), relative_path (b.path));
    }

    private string relative_path (string absolute_path) {
      return root_path == "" ? absolute_path : absolute_path.substring (root_path.length + 1);
    }

    /** Segment-by-segment, same as VS Code's own comparePaths(): within a shared prefix, whichever path has no more segments left (ends first) sorts before one that keeps going. */
    private static int compare_paths (string a, string b) {
      var a_parts = a.split ("/");
      var b_parts = b.split ("/");
      int last_a = a_parts.length - 1;
      int last_b = b_parts.length - 1;

      for (int i = 0; ; i++) {
        bool end_a = i == last_a;
        bool end_b = i == last_b;
        if (end_a && end_b) {
          return compare_names (a_parts[i], b_parts[i]);
        } else if (end_a) {
          return -1;
        } else if (end_b) {
          return 1;
        }

        int result = compare_names (a_parts[i], b_parts[i]);
        if (result != 0) {
          return result;
        }
      }
    }

    /** Locale-aware, with VS Code's own "numeric" disambiguation (`file2` before `file10`) — GLib's own collation key for exactly this job. */
    private static int compare_names (string a, string b) {
      var a_key = a.collate_key_for_filename ();
      var b_key = b.collate_key_for_filename ();
      if (a_key == b_key) {
        return 0;
      }
      return a_key < b_key ? -1 : 1;
    }
  }
}
