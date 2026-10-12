namespace Functions {
  /**
   * Runs a function off the main thread and turns what it returns into
   * the edits that put it in the text: one per segment, the unchanged
   * ones left out. Whoever applies them checks that the text is still
   * the one the input was taken from.
   */
  namespace Executor {
    public async TextEdit[] run_async (Function function, Input input) throws FunctionError {
      SourceFunc callback = run_async.callback;
      FunctionError? failure = null;
      string[] output = {};

      new Thread<void> ("function", () => {
        try {
          output = function.runner.run (input);
        } catch (FunctionError e) {
          failure = e;
        }
        Idle.add ((owned) callback);
      });

      yield;
      if (failure != null) {
        throw failure;
      }
      return edits_for (input, output);
    }

    public TextEdit[] edits_for (Input input, string[] output) throws FunctionError {
      if (output.length != input.segments.length) {
        throw new FunctionError.BAD_OUTPUT ("the function returned %d strings for %d segments", output.length, input.segments.length);
      }
      TextEdit[] edits = {};
      for (int i = 0; i < output.length; i++) {
        var segment = input.segments[i];
        if (output[i] == segment.text) {
          continue;
        }
        edits += new TextEdit () {
          start_offset = segment.start, end_offset = segment.end, old_text = segment.text, new_text = output[i],
        };
      }
      return edits;
    }
  }
}
