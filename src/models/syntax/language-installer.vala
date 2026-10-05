namespace Syntax {
  public errordomain InstallError {
    INVALID_PACKAGE,
    FAILED,
  }

  /**
   * Puts a language package into the user's own languages directory:
   * the manifest and the queries, under a folder named after the
   * language. Only those — a package's source may be a whole git
   * repository, and none of the rest is the package.
   */
  public class LanguageInstaller : Object {
    private string languages_directory;

    public LanguageInstaller (string languages_directory) {
      this.languages_directory = languages_directory;
    }

    /**
     * Installs the package at `source_directory`, replacing an
     * installed one of the same name outright — queries the new
     * version dropped must not linger. Returns it as installed.
     */
    public LanguagePackage install (string source_directory) throws InstallError {
      LanguagePackage source;
      try {
        source = LanguagePackage.load (source_directory);
      } catch (PackageError e) {
        throw new InstallError.INVALID_PACKAGE ("%s", e.message);
      }

      var target = Path.build_filename (languages_directory, source.name);
      try {
        remove_package (target);
        copy_file (source_directory, target, LanguagePackage.MANIFEST);
        copy_queries (Path.build_filename (source_directory, "queries"), Path.build_filename (target, "queries"));
        return LanguagePackage.load (target);
      } catch (Error e) {
        throw new InstallError.FAILED ("%s", e.message);
      }
    }

    /**
     * {@link install} for a package kept in a git repository: `url`
     * is anything `git clone` takes, with the manifest at its root.
     * The clone is temporary — what stays is the installed copy.
     */
    public LanguagePackage install_from_repository (string url) throws InstallError {
      if (!HostCommand.has_program ("git")) {
        throw new InstallError.FAILED ("installing from a repository needs `git`, which isn't installed");
      }
      var clone = Path.build_filename (HostCommand.shared_tmp_dir ("git"), "opus-language-%u".printf (Random.next_int ()));
      try {
        clone_repository (url, clone);
        return install (clone);
      } finally {
        remove_recursively (clone);
      }
    }

    private static void clone_repository (string url, string directory) throws InstallError {
      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
      string? errors;
      try {
        // The same spawnv() argv wart as every other one in this codebase.
        var process = launcher.spawnv (HostCommand.argv ({ "git", "clone", "--quiet", "--depth", "1", url, directory }));
        process.communicate_utf8 (null, null, null, out errors);
        if (process.get_successful ()) {
          return;
        }
      } catch (Error e) {
        throw new InstallError.FAILED ("git: %s", e.message);
      }
      throw new InstallError.FAILED ("git clone failed: %s", (errors ?? "").strip ());
    }

    private static void remove_recursively (string path) {
      if (FileUtils.test (path, FileTest.IS_DIR) && !FileUtils.test (path, FileTest.IS_SYMLINK)) {
        try {
          var dir = Dir.open (path);
          string? name;
          while ((name = dir.read_name ()) != null) {
            remove_recursively (Path.build_filename (path, name));
          }
        } catch (FileError e) {
          return;
        }
        DirUtils.remove (path);
        return;
      }
      FileUtils.remove (path);
    }

    /** Only what {@link install} itself writes: a manifest and `queries/*.scm`. Anything else found there is left, and the directory with it. */
    private static void remove_package (string directory) throws Error {
      var queries = Path.build_filename (directory, "queries");
      foreach (var name in query_files (queries)) {
        FileUtils.remove (Path.build_filename (queries, name));
      }
      FileUtils.remove (Path.build_filename (directory, LanguagePackage.MANIFEST));
    }

    private static void copy_queries (string source, string target) throws Error {
      foreach (var name in query_files (source)) {
        copy_file (source, target, name);
      }
    }

    private static GenericArray<string> query_files (string directory) {
      var names = new GenericArray<string> ();
      try {
        var dir = Dir.open (directory);
        string? name;
        while ((name = dir.read_name ()) != null) {
          if (name.has_suffix (".scm")) {
            names.add (name);
          }
        }
      } catch (FileError e) {
        return names;
      }
      return names;
    }

    private static void copy_file (string source_directory, string target_directory, string name) throws Error {
      DirUtils.create_with_parents (target_directory, 0755);
      File.new_for_path (Path.build_filename (source_directory, name)).copy (
        File.new_for_path (Path.build_filename (target_directory, name)),
        FileCopyFlags.OVERWRITE
      );
    }
  }
}
