namespace Syntax {
  public errordomain BuildError {
    MISSING_TOOL,
    FAILED,
  }

  /**
   * Compiles a grammar from the commit its package pins: fetches that
   * one commit and builds `parser.c` (and the scanner, when the
   * grammar has one) into a shared library GrammarLoader can open.
   *
   * Uses the user's own `git` and C compiler through HostCommand — a
   * Flatpak sandbox has neither, and the library it loads is the same
   * file wherever it was built.
   */
  public class GrammarBuilder : Object {
    private string sources_directory;
    private string output_directory;

    /** Fetched sources go under `sources_directory`, one checkout per grammar and commit; libraries into `output_directory`, which has to be one GrammarLoader searches. */
    public GrammarBuilder (string sources_directory, string output_directory) {
      this.sources_directory = sources_directory;
      this.output_directory = output_directory;
    }

    /** Where {@link build} puts `grammar`'s library — named for the commit too, so a package pinning another one never loads a stale build. */
    public string library_path (GrammarSource grammar) {
      return Path.build_filename (output_directory, GrammarLoader.library_name (grammar));
    }

    /** Blocks until the library is built; returns its path. A grammar already built is left as it is. */
    public string build (GrammarSource grammar) throws BuildError {
      var library = library_path (grammar);
      if (FileUtils.test (library, FileTest.IS_REGULAR)) {
        return library;
      }
      require ("git");
      var checkout = fetch (grammar);
      compile (grammar, checkout, library);
      return library;
    }

    /** {@link build} off the main thread: compiling a large grammar takes seconds. */
    public async string build_async (GrammarSource grammar) throws BuildError {
      string? library = null;
      BuildError? failure = null;
      new Thread<void*> ("grammar-build", () => {
        try {
          library = build (grammar);
        } catch (BuildError e) {
          failure = e;
        }
        Idle.add (build_async.callback);
        return null;
      });
      yield;

      if (failure != null) {
        throw failure;
      }
      return library;
    }

    private static void require (string program) throws BuildError {
      if (!HostCommand.has_program (program)) {
        throw new BuildError.MISSING_TOOL ("building a grammar needs `%s`, which isn't installed", program);
      }
    }

    /** The checkout of `grammar`'s commit, fetched now unless an earlier build already left it complete. */
    private string fetch (GrammarSource grammar) throws BuildError {
      var checkout = Path.build_filename (sources_directory, "%s-%s".printf (grammar.name, grammar.rev));
      // Written last, so a fetch that was interrupted is never taken for a whole one.
      var complete_marker = Path.build_filename (checkout, ".opus-fetched");
      if (FileUtils.test (complete_marker, FileTest.EXISTS)) {
        return checkout;
      }

      DirUtils.create_with_parents (checkout, 0700);
      run ({ "git", "-C", checkout, "init", "--quiet" });
      run ({ "git", "-C", checkout, "fetch", "--quiet", "--depth", "1", grammar.repository, grammar.rev });
      run ({ "git", "-C", checkout, "checkout", "--quiet", "--force", "FETCH_HEAD" });
      try {
        FileUtils.set_contents (complete_marker, "");
      } catch (FileError e) {
        throw new BuildError.FAILED ("%s", e.message);
      }
      return checkout;
    }

    private void compile (GrammarSource grammar, string checkout, string library) throws BuildError {
      var source = Path.build_filename (checkout, grammar.path, "src");
      var parser = Path.build_filename (source, "parser.c");
      if (!FileUtils.test (parser, FileTest.IS_REGULAR)) {
        throw new BuildError.FAILED ("grammar \"%s\" has no %s", grammar.name, Path.build_filename (grammar.path, "src", "parser.c"));
      }

      DirUtils.create_with_parents (output_directory, 0700);
      // Built under another name and moved into place: a compiler
      // killed halfway must not leave something that looks loadable.
      var unfinished = library + ".part";
      run (compiler_command (source, parser, unfinished));
      if (FileUtils.rename (unfinished, library) != 0) {
        throw new BuildError.FAILED ("couldn't move the built grammar into %s", library);
      }
    }

    /** `-w`: generated parser tables and third-party scanners warn freely, and none of it is the user's to fix. */
    private static string[] compiler_command (string source, string parser, string output) throws BuildError {
      var c_scanner = Path.build_filename (source, "scanner.c");
      var cpp_scanner = Path.build_filename (source, "scanner.cc");
      if (FileUtils.test (cpp_scanner, FileTest.IS_REGULAR)) {
        require ("c++");
        return { "c++", "-shared", "-fPIC", "-O2", "-w", "-I", source, "-xc", parser, "-xc++", cpp_scanner, "-o", output };
      }

      require ("cc");
      string[] command = { "cc", "-shared", "-fPIC", "-O2", "-w", "-std=c11", "-I", source, parser };
      if (FileUtils.test (c_scanner, FileTest.IS_REGULAR)) {
        command += c_scanner;
      }
      command += "-o";
      command += output;
      return command;
    }

    /** Runs `command` to the end; what it wrote to stderr is the error when it fails. */
    private static void run (string[] command) throws BuildError {
      var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
      string? errors;
      try {
        // spawnv() takes a `const gchar * const *`; valac always marshals
        // a string[] as a plain `gchar**` — the same upstream wart as
        // every other spawnv() in this codebase.
        var process = launcher.spawnv (HostCommand.argv (command));
        process.communicate_utf8 (null, null, null, out errors);
        if (process.get_successful ()) {
          return;
        }
      } catch (Error e) {
        throw new BuildError.FAILED ("%s: %s", command[0], e.message);
      }
      throw new BuildError.FAILED ("%s failed: %s", command[0], (errors ?? "").strip ());
    }
  }
}
