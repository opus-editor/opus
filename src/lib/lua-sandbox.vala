public errordomain LuaError {
  /** The script can't be read, doesn't compile, or defines no `transform`. */
  LOAD,
  /** `transform` raised an error — the message carries `file:line`. */
  RUN,
  /** The instruction limit was reached: a loop that never ends. */
  TIMEOUT,
  /** `transform` returned something other than a table of strings. */
  BAD_RESULT,
}

/**
 * One Lua 5.4 state to run a transform script in, with the standard
 * libraries a text transformation needs and nothing that reaches
 * outside the process: `os`, `io`, `package`, `debug`, `require`,
 * `dofile`, `loadfile` and `load` are gone. The host adds an `opus`
 * table because Lua's own `string.upper` is ASCII-only: `opus.upper`,
 * `opus.lower` and `opus.capitalize` go through GLib, and `opus.words`
 * splits an identifier or a sentence into words — what Kebab, Pascal
 * and Snake share. Generic infrastructure: it knows strings and
 * offsets, never a Document or a Cursor.
 *
 * A count hook stops a script after `instruction_limit` VM
 * instructions; the callbacks are plain C functions (the binding's
 * delegates carry no target), so nothing here holds state they need.
 */
public class LuaSandbox : Object {
  public struct Segment {
    public string text;
    /** Character offsets into the whole text. */
    public int start;
    public int end;
  }

  public struct Caret {
    public int anchor;
    public int position;
  }

  public struct TransformInput {
    /** "document" or "selection". */
    public string kind;
    public Segment[] segments;
    /** The whole text, whatever the segments are. */
    public string text;
    public Caret[] cursors;
    public string language;
    public string path;
  }

  private const string LIMIT_MESSAGE = "the function ran for too long";
  private const string[] REMOVED_GLOBALS = { "os", "io", "package", "debug", "require", "dofile", "loadfile", "load" };

  private Lua.LuaVM vm = new Lua.LuaVM ();

  public LuaSandbox (int instruction_limit = 100000000) {
    vm.open_libs ();
    foreach (var name in REMOVED_GLOBALS) {
      vm.push_nil ();
      vm.set_global (name);
    }
    install_opus_table ();
    vm.set_hook (on_instruction_limit, Lua.EventMask.COUNT, instruction_limit);
  }

  /** Runs `script_path`'s `transform (input)` and returns its table of strings, one per segment. */
  public string[] run_transform (string script_path, TransformInput input) throws LuaError {
    string source;
    try {
      FileUtils.get_contents (script_path, out source);
    } catch (Error e) {
      throw new LuaError.LOAD ("%s", e.message);
    }
    // "@name" makes Lua report positions as "name:line", a file's way.
    if (vm.load_buffer (source.to_utf8 (), "@" + Path.get_basename (script_path)) != 0) {
      throw new LuaError.LOAD ("%s", vm.to_string (-1));
    }
    if (vm.pcall (0, 0, 0) != 0) {
      throw failure (vm.to_string (-1));
    }
    vm.get_global ("transform");
    if (!vm.is_function (-1)) {
      throw new LuaError.LOAD ("%s defines no transform function", Path.get_basename (script_path));
    }
    push_input (input);
    if (vm.pcall (1, 1, 0) != 0) {
      throw failure (vm.to_string (-1));
    }
    return read_strings ();
  }

  private static LuaError failure (string message) {
    if (message.contains (LIMIT_MESSAGE)) {
      return new LuaError.TIMEOUT ("%s", LIMIT_MESSAGE);
    }
    return new LuaError.RUN ("%s", message);
  }

  private void push_input (TransformInput input) {
    vm.new_table ();
    push_field ("kind", input.kind);
    push_field ("text", input.text);
    push_field ("language", input.language);
    push_field ("path", input.path);

    vm.new_table ();
    for (int i = 0; i < input.segments.length; i++) {
      vm.new_table ();
      push_field ("text", input.segments[i].text);
      vm.push_integer (input.segments[i].start);
      vm.set_field (-2, "start");
      vm.push_integer (input.segments[i].end);
      vm.set_field (-2, "end");
      vm.raw_seti (-2, i + 1);
    }
    vm.set_field (-2, "segments");

    vm.new_table ();
    for (int i = 0; i < input.cursors.length; i++) {
      vm.new_table ();
      vm.push_integer (input.cursors[i].anchor);
      vm.set_field (-2, "anchor");
      vm.push_integer (input.cursors[i].position);
      vm.set_field (-2, "position");
      vm.raw_seti (-2, i + 1);
    }
    vm.set_field (-2, "cursors");
  }

  private void push_field (string key, string value) {
    vm.push_string (value);
    vm.set_field (-2, key);
  }

  /** The table at the top of the stack as strings, 1 to the first nil. */
  private string[] read_strings () throws LuaError {
    if (!vm.is_table (-1)) {
      throw new LuaError.BAD_RESULT ("transform must return a table of strings, one per segment");
    }
    string[] strings = {};
    for (int i = 1; ; i++) {
      vm.raw_geti (-1, i);
      if (vm.is_nil (-1)) {
        vm.pop (1);
        break;
      }
      if (!vm.is_string (-1)) {
        throw new LuaError.BAD_RESULT ("transform returned a non-string at position %d", i);
      }
      strings += vm.to_string (-1);
      vm.pop (1);
    }
    return strings;
  }

  private void install_opus_table () {
    vm.new_table ();
    vm.push_cfunction (opus_upper);
    vm.set_field (-2, "upper");
    vm.push_cfunction (opus_lower);
    vm.set_field (-2, "lower");
    vm.push_cfunction (opus_capitalize);
    vm.set_field (-2, "capitalize");
    vm.push_cfunction (opus_words);
    vm.set_field (-2, "words");
    vm.set_global ("opus");
  }

  private static void on_instruction_limit (Lua.LuaVM vm, ref Lua.Debug ar) {
    vm.push_string (LIMIT_MESSAGE);
    vm.error ();
  }

  private static string argument (Lua.LuaVM vm) {
    return vm.is_string (1) ? vm.to_string (1) : "";
  }

  private static int opus_upper (Lua.LuaVM vm) {
    vm.push_string (argument (vm).up ());
    return 1;
  }

  private static int opus_lower (Lua.LuaVM vm) {
    vm.push_string (argument (vm).down ());
    return 1;
  }

  private static int opus_capitalize (Lua.LuaVM vm) {
    vm.push_string (capitalize (argument (vm)));
    return 1;
  }

  private static int opus_words (Lua.LuaVM vm) {
    var words = split_words (argument (vm));
    vm.new_table ();
    for (int i = 0; i < words.length; i++) {
      vm.push_string (words[i]);
      vm.raw_seti (-2, i + 1);
    }
    return 1;
  }

  /** The first character up, the rest down: "ÉCOLE" → "École". */
  public static string capitalize (string text) {
    if (text == "") {
      return text;
    }
    unowned string rest = text.next_char ();
    return text.get_char ().toupper ().to_string () + rest.down ();
  }

  /**
   * Words of an identifier or a sentence: split at anything that is
   * not a letter or a digit, and inside a run at a camelCase boundary
   * — a capital after a small letter or a digit, or the last capital
   * of a run of them before a small one (HTTPServer → HTTP, Server).
   * Digits stay with the letters before them (v2Beta → v2, Beta).
   */
  public static string[] split_words (string text) {
    var words = new GenericArray<string> ();
    var word = new StringBuilder ();
    unichar previous = 0;
    int index = 0;
    unichar current;
    while (text.get_next_char (ref index, out current)) {
      if (!current.isalnum ()) {
        take (word, words);
        previous = 0;
        continue;
      }
      int peek = index;
      unichar next;
      bool next_is_lower = text.get_next_char (ref peek, out next) && next.islower ();
      bool starts_word = current.isupper () && (previous.islower () || previous.isdigit () || (previous.isupper () && next_is_lower));
      if (starts_word) {
        take (word, words);
      }
      word.append_unichar (current);
      previous = current;
    }
    take (word, words);
    string[] result = {};
    foreach (var found in words) {
      result += found;
    }
    return result;
  }

  private static void take (StringBuilder word, GenericArray<string> words) {
    if (word.len > 0) {
      words.add (word.str);
      word.truncate (0);
    }
  }
}
