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
        foreach (var edit in edits_of (segment, output[i])) {
          edits += edit;
        }
      }
      return edits;
    }

    /**
     * The smallest edits that turn `segment` into `output`: one per
     * changed line while both have the same number of lines (a trim, a
     * reindent), else the one span between the common head and tail.
     * Small edits keep the cursors, the scroll and the undo step where
     * the change really is, instead of swapping the whole text.
     */
    private TextEdit[] edits_of (LuaSandbox.Segment segment, string output) {
      var old_lines = segment.text.split ("\n");
      var new_lines = output.split ("\n");
      if (old_lines.length != new_lines.length) {
        return { span_edit (segment, output) };
      }
      TextEdit[] edits = {};
      int offset = segment.start;
      for (int i = 0; i < old_lines.length; i++) {
        int length = old_lines[i].char_count ();
        if (old_lines[i] != new_lines[i]) {
          edits += new TextEdit () { start_offset = offset, end_offset = offset + length, old_text = old_lines[i], new_text = new_lines[i] };
        }
        offset += length + 1;
      }
      return edits;
    }

    private TextEdit span_edit (LuaSandbox.Segment segment, string output) {
      int old_length = segment.text.char_count ();
      int new_length = output.char_count ();
      int head = 0;
      while (head < old_length && head < new_length && segment.text.get_char (segment.text.index_of_nth_char (head)) == output.get_char (output.index_of_nth_char (head))) {
        head++;
      }
      int tail = 0;
      while (tail < old_length - head && tail < new_length - head
             && segment.text.get_char (segment.text.index_of_nth_char (old_length - 1 - tail)) == output.get_char (output.index_of_nth_char (new_length - 1 - tail))) {
        tail++;
      }
      int old_from = segment.text.index_of_nth_char (head);
      int old_to = segment.text.index_of_nth_char (old_length - tail);
      int new_from = output.index_of_nth_char (head);
      int new_to = output.index_of_nth_char (new_length - tail);
      return new TextEdit () {
        start_offset = segment.start + head, end_offset = segment.start + old_length - tail,
        old_text = segment.text.substring (old_from, old_to - old_from), new_text = output.substring (new_from, new_to - new_from),
      };
    }
  }
}
