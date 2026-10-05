namespace Syntax {
  public errordomain PackageError {
    UNREADABLE,
    INVALID,
  }

  /** Where a package's grammar comes from: one pinned commit of a git repository. */
  public class GrammarSource : Object {
    /** Names the compiled library and, through {@link symbol}, the function it exports. */
    public string name { get; private set; }
    public string repository { get; private set; }
    public string rev { get; private set; }
    /** The grammar's own directory inside the repository — "" for its root. */
    public string path { get; private set; }

    public GrammarSource (string name, string repository, string rev, string path) {
      this.name = name;
      this.repository = repository;
      this.rev = rev;
      this.path = path;
    }

    /** The function every grammar library exports: C can't spell `-` or `.` in a name, so grammars swap them for `_`. */
    public string symbol {
      owned get { return "tree_sitter_" + name.replace ("-", "_").replace (".", "_"); }
    }
  }

  /**
   * One language as a directory: a `language.json` manifest plus a
   * `queries` folder of `.scm` files. Built-in languages and the user's own share this
   * exact shape — that sameness is what makes a language a package
   * rather than code.
   *
   * The manifest's keys are Helix's `languages.toml` ones, so porting a
   * language from there is a mechanical translation.
   */
  public class LanguagePackage : Object {
    public const string MANIFEST = "language.json";

    public string directory { get; private set; }
    public string name { get; private set; }
    /** How the language is written for a person to read ("C++", where `name` is "cpp") — `name` itself when the manifest gives none. */
    public string title { get; private set; }
    /** File extensions, without the dot. */
    public string[] extensions { get; private set; }
    /** See {@link Glob.compile} for the syntax. */
    public string[] globs { get; private set; }
    /** Interpreter names a `#!` line may carry. */
    public string[] shebangs { get; private set; }
    /** Matched against the language name an injection asks for. */
    public Regex? injection_regex { get; private set; }
    /** Null for a package that only lends its queries to others through `; inherits:`. */
    public GrammarSource? grammar { get; private set; }

    private LanguagePackage () {}

    public static LanguagePackage load (string directory) throws PackageError {
      var manifest_path = Path.build_filename (directory, MANIFEST);
      string manifest;
      try {
        FileUtils.get_contents (manifest_path, out manifest);
      } catch (FileError e) {
        throw new PackageError.UNREADABLE ("%s: %s", manifest_path, e.message);
      }
      return parse (directory, manifest);
    }

    /** Split out from {@link load} so a manifest can be tested as plain text. */
    public static LanguagePackage parse (string directory, string manifest) throws PackageError {
      var root = parse_root (manifest);

      var package = new LanguagePackage ();
      package.directory = directory;
      package.name = required_string (root, "name");
      package.title = optional_string (root, "title") ?? package.name;
      package.shebangs = string_array (root, "shebangs");
      package.injection_regex = injection_regex_of (root);
      package.grammar = grammar_of (root, package.name);
      package.read_file_types (root);
      return package;
    }

    /** Whether a file can be this language: it has a grammar to parse with and claims some kind of file. The rest only exist inside other languages (`markdown.inline`, `comment`) or lend them queries (`ecma`). */
    public bool opens_files {
      get { return grammar != null && (extensions.length > 0 || globs.length > 0 || shebangs.length > 0); }
    }

    /** Null when this package has no `queries/<query_name>.scm`. */
    public string? query_path (string query_name) {
      var path = Path.build_filename (directory, "queries", query_name + ".scm");
      return FileUtils.test (path, FileTest.IS_REGULAR) ? path : null;
    }

    private static Json.Object parse_root (string manifest) throws PackageError {
      var parser = new Json.Parser ();
      try {
        parser.load_from_data (manifest);
      } catch (Error e) {
        throw new PackageError.INVALID ("not valid JSON: %s", e.message);
      }
      var root = parser.get_root ();
      if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
        throw new PackageError.INVALID ("the manifest must be a JSON object");
      }
      return root.get_object ();
    }

    /** `file-types` mixes two shapes, as Helix's does: a bare string is an extension, `{ "glob": … }` a path pattern. */
    private void read_file_types (Json.Object root) throws PackageError {
      string[] found_extensions = {};
      string[] found_globs = {};

      foreach (var node in array_member (root, "file-types")) {
        if (is_string (node)) {
          found_extensions += node.get_string ();
          continue;
        }
        if (node.get_node_type () != Json.NodeType.OBJECT) {
          throw new PackageError.INVALID ("\"file-types\" entries must be a string or { \"glob\": … }");
        }
        found_globs += required_string (node.get_object (), "glob");
      }

      extensions = found_extensions;
      globs = found_globs;
    }

    private static Regex? injection_regex_of (Json.Object root) throws PackageError {
      var pattern = optional_string (root, "injection-regex");
      if (pattern == null) {
        return null;
      }
      try {
        return new Regex (pattern);
      } catch (RegexError e) {
        throw new PackageError.INVALID ("\"injection-regex\": %s", e.message);
      }
    }

    private static GrammarSource? grammar_of (Json.Object root, string language_name) throws PackageError {
      if (!root.has_member ("grammar")) {
        return null;
      }
      var node = root.get_member ("grammar");
      if (node.get_node_type () != Json.NodeType.OBJECT) {
        throw new PackageError.INVALID ("\"grammar\" must be an object");
      }
      var grammar = node.get_object ();
      return new GrammarSource (
        optional_string (grammar, "name") ?? language_name,
        required_string (grammar, "repository"),
        required_string (grammar, "rev"),
        optional_string (grammar, "path") ?? ""
      );
    }

    private static string required_string (Json.Object object, string key) throws PackageError {
      var value = optional_string (object, key);
      if (value == null || value == "") {
        throw new PackageError.INVALID ("\"%s\" is required", key);
      }
      return value;
    }

    private static string? optional_string (Json.Object object, string key) throws PackageError {
      if (!object.has_member (key)) {
        return null;
      }
      var node = object.get_member (key);
      if (!is_string (node)) {
        throw new PackageError.INVALID ("\"%s\" must be a string", key);
      }
      return node.get_string ();
    }

    private static string[] string_array (Json.Object object, string key) throws PackageError {
      string[] values = {};
      foreach (var node in array_member (object, key)) {
        if (!is_string (node)) {
          throw new PackageError.INVALID ("\"%s\" must hold strings only", key);
        }
        values += node.get_string ();
      }
      return values;
    }

    /** Empty when `key` is absent. */
    private static List<unowned Json.Node> array_member (Json.Object object, string key) throws PackageError {
      if (!object.has_member (key)) {
        return new List<unowned Json.Node> ();
      }
      var node = object.get_member (key);
      if (node.get_node_type () != Json.NodeType.ARRAY) {
        throw new PackageError.INVALID ("\"%s\" must be an array", key);
      }
      return node.get_array ().get_elements ();
    }

    private static bool is_string (Json.Node node) {
      return node.get_node_type () == Json.NodeType.VALUE && node.get_value_type () == typeof (string);
    }
  }
}
