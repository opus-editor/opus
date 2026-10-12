namespace Functions {
  /** A package's script, run in a fresh LuaSandbox each time: nothing carries over between runs, and a hung one dies alone. */
  public class LuaRunner : Object, IRunner {
    // About two seconds of a tight loop; a real transform of a large file is far below it.
    private const int INSTRUCTION_LIMIT = 200000000;

    public string script_path { get; private set; }

    public LuaRunner (string script_path) {
      this.script_path = script_path;
    }

    public string[] run (Input input) throws FunctionError {
      try {
        return new LuaSandbox (INSTRUCTION_LIMIT).run_transform (script_path, input.to_transform_input ());
      } catch (LuaError e) {
        if (e is LuaError.TIMEOUT) {
          throw new FunctionError.TIMEOUT ("%s", e.message);
        }
        if (e is LuaError.BAD_RESULT) {
          throw new FunctionError.BAD_OUTPUT ("%s", e.message);
        }
        throw new FunctionError.SCRIPT ("%s", e.message);
      }
    }
  }
}
