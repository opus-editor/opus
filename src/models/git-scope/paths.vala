/**
 * `GitScope`: the editor's own dealings with a repository through git
 * itself. Reading — `StatusQuery` narrowed to one path, the scope a
 * batch of changes is local to (a directory, or one file), and
 * `WorkingTree` over the whole repository at once — and writing:
 * `Stage`, `Discard`, `Resolve`, `Operation`, every spawn through
 * `Command`. `Paths` is the scope arithmetic the readers share.
 */
namespace GitScope {
  public class Paths : Object {
    public static bool is_at_or_under (string path, string scope) {
      return path == scope || path.has_prefix (scope + "/");
    }

    /** The deepest path that holds both — what two pending scopes widen to. */
    public static string common_ancestor (string a, string b) {
      var ancestor = a;
      while (!is_at_or_under (b, ancestor)) {
        var parent = Path.get_dirname (ancestor);
        if (parent == ancestor) {
          break; // the filesystem root holds everything
        }
        ancestor = parent;
      }
      return ancestor;
    }
  }
}
