namespace Syntax {
  private class LanguageGlob : Object {
    public string text;
    public Regex pattern;
    public LanguagePackage package;
  }

  /**
   * Every language package found on disk, and the three ways one gets
   * picked: by name, by the file being opened, by the name an injection
   * asks for.
   */
  public class LanguageRegistry : Object {
    // Helix's own shebang pattern: skips the interpreter's directory and
    // an `env` (flags included), and stops before a version suffix, so
    // `#!/usr/bin/env -S python3.12` yields `python`.
    private const string SHEBANG_PATTERN = "^#!\\s*(?:\\S*[/\\\\](?:env\\s+(?:\\-\\S+\\s+)*)?)?([^\\s\\.\\d]+)";

    // In loading order, so a later package wins a file type both claim.
    private GenericArray<LanguagePackage> packages = new GenericArray<LanguagePackage> ();
    private HashTable<string, LanguagePackage> packages_by_name = new HashTable<string, LanguagePackage> (str_hash, str_equal);
    private HashTable<string, LanguagePackage> packages_by_extension = new HashTable<string, LanguagePackage> (str_hash, str_equal);
    private HashTable<string, LanguagePackage> packages_by_shebang = new HashTable<string, LanguagePackage> (str_hash, str_equal);
    private GenericArray<LanguageGlob> globs = new GenericArray<LanguageGlob> ();
    private Regex shebang_regex;

    /**
     * Loads every package directly under each of `directories`, given
     * in rising precedence: a package replaces a same-named one from an
     * earlier directory outright, queries included. A directory that
     * doesn't exist is skipped; a package that doesn't load is logged
     * and skipped, never fatal — one broken package must not cost the
     * editor every other language.
     */
    public LanguageRegistry (string[] directories) {
      try {
        shebang_regex = new Regex (SHEBANG_PATTERN);
      } catch (RegexError e) {
        error ("unreachable: the shebang pattern failed to compile: %s", e.message);
      }

      foreach (unowned string directory in directories) {
        load_directory (directory);
      }
      foreach (var package in packages) {
        index (package);
      }
    }

    public LanguagePackage? by_name (string name) {
      return packages_by_name[name];
    }

    /** Every package, in no particular order. */
    public GenericArray<LanguagePackage> all () {
      return packages.copy ((package) => package);
    }

    /**
     * The language for the file at `path`: the longest matching glob
     * first, then the extension, then `first_line`'s shebang.
     */
    public LanguagePackage? detect (string path, string? first_line = null) {
      var package = by_glob (path) ?? by_extension (path);
      if (package == null && first_line != null) {
        package = by_shebang (first_line);
      }
      return package;
    }

    /**
     * The language an injection naming `name` means: a package of that
     * exact name, else the one whose `injection-regex` matches the most
     * of it.
     */
    public LanguagePackage? for_injection (string name) {
      var exact = packages_by_name[name];
      if (exact != null) {
        return exact;
      }

      LanguagePackage? best = null;
      int best_length = 0;
      foreach (var package in packages) {
        int length = injection_match_length (package, name);
        if (length > best_length) {
          best = package;
          best_length = length;
        }
      }
      return best;
    }

    private void load_directory (string directory) {
      foreach (var name in sorted_children (directory)) {
        var package_directory = Path.build_filename (directory, name);
        if (!FileUtils.test (Path.build_filename (package_directory, LanguagePackage.MANIFEST), FileTest.IS_REGULAR)) {
          continue;
        }
        try {
          add (LanguagePackage.load (package_directory));
        } catch (PackageError e) {
          Logger.warn ("skipping language package %s: %s".printf (package_directory, e.message));
        }
      }
    }

    /** Sorted, so two packages of one directory claiming the same file type resolve the same way on every machine. */
    private static GenericArray<string> sorted_children (string directory) {
      var names = new GenericArray<string> ();
      try {
        var dir = Dir.open (directory);
        string? name;
        while ((name = dir.read_name ()) != null) {
          names.add (name);
        }
      } catch (FileError e) {
        return names;
      }
      names.sort (strcmp);
      return names;
    }

    private void add (LanguagePackage package) {
      var replaced = packages_by_name[package.name];
      if (replaced != null) {
        packages.remove (replaced);
      }
      packages.add (package);
      packages_by_name[package.name] = package;
    }

    private void index (LanguagePackage package) {
      foreach (unowned string extension in package.extensions) {
        packages_by_extension[extension] = package;
      }
      foreach (unowned string shebang in package.shebangs) {
        packages_by_shebang[shebang] = package;
      }
      foreach (unowned string glob in package.globs) {
        index_glob (package, glob);
      }
    }

    private void index_glob (LanguagePackage package, string glob) {
      try {
        globs.add (new LanguageGlob () {
          text = glob,
          pattern = Glob.compile (anywhere (glob)),
          package = package,
        });
      } catch (RegexError e) {
        Logger.warn ("language package %s: ignoring glob \"%s\": %s".printf (package.name, glob, e.message));
      }
    }

    /**
     * A glob is matched against the whole path of the file, so one
     * naming a directory (`conf.d` followed by `*.conf`) has to be let
     * match under any parent — {@link Glob.compile} only does that by
     * itself for a pattern with no `/` at all.
     */
    private static string anywhere (string glob) {
      if (!glob.contains ("/") || glob.has_prefix ("/") || glob.has_prefix ("*")) {
        return glob;
      }
      return "**/" + glob;
    }

    private LanguagePackage? by_glob (string path) {
      LanguageGlob? best = null;
      foreach (var glob in globs) {
        // `>=`: on a tie the later package — the one with precedence — wins.
        if (glob.pattern.match (path) && (best == null || glob.text.length >= best.text.length)) {
          best = glob;
        }
      }
      return best == null ? null : best.package;
    }

    /** Longest extension first, so a package claiming `js.map` gets `app.js.map` ahead of one claiming `map`. */
    private LanguagePackage? by_extension (string path) {
      var basename = Path.get_basename (path);
      // From 1: a leading dot names a hidden file, not an extension.
      int dot = basename.index_of_char ('.', 1);
      while (dot >= 0) {
        var package = packages_by_extension[basename.substring (dot + 1)];
        if (package != null) {
          return package;
        }
        dot = basename.index_of_char ('.', dot + 1);
      }
      return null;
    }

    private LanguagePackage? by_shebang (string first_line) {
      MatchInfo info;
      if (!shebang_regex.match (first_line, 0, out info)) {
        return null;
      }
      return packages_by_shebang[info.fetch (1)];
    }

    private static int injection_match_length (LanguagePackage package, string name) {
      if (package.injection_regex == null) {
        return 0;
      }
      MatchInfo info;
      if (!package.injection_regex.match (name, 0, out info)) {
        return 0;
      }
      int start;
      int end;
      info.fetch_pos (0, out start, out end);
      return end - start;
    }
  }
}
