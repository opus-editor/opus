/*
 * Hand-written binding for the tree-sitter C runtime (subprojects/
 * tree-sitter.wrap pins the version) — only what Opus calls, not the
 * whole API.
 */
[CCode (cheader_filename = "tree_sitter/api.h")]
namespace TreeSitter {
  [CCode (cname = "TREE_SITTER_LANGUAGE_VERSION")]
  public const uint32 LANGUAGE_VERSION;

  [CCode (cname = "TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION")]
  public const uint32 MIN_COMPATIBLE_LANGUAGE_VERSION;

  /** Static data owned by the grammar's own shared library — never freed. */
  [CCode (cname = "TSLanguage", free_function = "", has_type_id = false)]
  [Compact]
  public class Language {
    [CCode (cname = "ts_language_abi_version")]
    public uint32 abi_version ();
  }

  [CCode (cname = "TSPoint", has_type_id = false)]
  [SimpleType]
  public struct Point {
    public uint32 row;
    public uint32 column;
  }

  [CCode (cname = "TSRange", has_type_id = false)]
  public struct Range {
    public Point start_point;
    public Point end_point;
    public uint32 start_byte;
    public uint32 end_byte;
  }

  [CCode (cname = "TSInputEncoding", has_type_id = false)]
  public enum InputEncoding {
    [CCode (cname = "TSInputEncodingUTF8")]
    UTF8,
  }

  /** C's own `bool`, one byte: what tree-sitter's callbacks return, where Vala's `bool` is GLib's int-sized one. */
  [CCode (cname = "bool", has_type_id = false)]
  [BooleanType]
  public struct CBool {
  }

  /** Hands the parser the text from `byte_index` on, as much of it as is convenient; zero `bytes_read` ends the input. */
  [CCode (has_target = false, has_typedef = false)]
  public delegate unowned string InputReadFunc (void* payload, uint32 byte_index, Point position, out uint32 bytes_read);

  [CCode (cname = "TSInput", has_type_id = false)]
  [SimpleType]
  public struct Input {
    public void* payload;
    public InputReadFunc read;
    public InputEncoding encoding;
    public void* decode;
  }

  [CCode (cname = "TSParseState", has_type_id = false)]
  public struct ParseState {
    public void* payload;
    public uint32 current_byte_offset;
    public bool has_error;
  }

  /** Called every so often during a parse; returning true halts it. */
  [CCode (has_target = false, has_typedef = false)]
  public delegate CBool ParseProgressFunc (ParseState* state);

  [CCode (cname = "TSParseOptions", has_type_id = false)]
  [SimpleType]
  public struct ParseOptions {
    public void* payload;
    public ParseProgressFunc progress_callback;
  }

  [CCode (cname = "TSInputEdit", has_type_id = false)]
  public struct InputEdit {
    public uint32 start_byte;
    public uint32 old_end_byte;
    public uint32 new_end_byte;
    public Point start_point;
    public Point old_end_point;
    public Point new_end_point;
  }

  [CCode (cname = "TSNode", has_type_id = false)]
  [SimpleType]
  public struct Node {
    [CCode (cname = "ts_node_type")]
    public unowned string type ();

    [CCode (cname = "ts_node_start_byte")]
    public uint32 start_byte ();

    [CCode (cname = "ts_node_end_byte")]
    public uint32 end_byte ();

    [CCode (cname = "ts_node_start_point")]
    public Point start_point ();

    [CCode (cname = "ts_node_end_point")]
    public Point end_point ();

    [CCode (cname = "ts_node_is_named")]
    public bool is_named ();

    [CCode (cname = "ts_node_child_count")]
    public uint32 child_count ();

    [CCode (cname = "ts_node_child")]
    public Node child (uint32 index);
  }

  [CCode (cname = "TSTree", free_function = "ts_tree_delete", has_type_id = false)]
  [Compact]
  public class Tree {
    [CCode (cname = "ts_tree_root_node")]
    public Node root_node ();

    /** The ranges the tree was parsed over — one covering everything, unless the parser was given others. */
    [CCode (cname = "ts_tree_included_ranges", array_length_type = "uint32_t")]
    public Range[] included_ranges ();

    /** Shifts the tree to match an edit of the text, so the next parse can reuse what the edit left alone. */
    [CCode (cname = "ts_tree_edit")]
    public void edit (InputEdit edit);
  }

  [CCode (cname = "TSParser", free_function = "ts_parser_delete", has_type_id = false)]
  [Compact]
  public class Parser {
    [CCode (cname = "ts_parser_new")]
    public Parser ();

    /** False when the language's ABI is one this runtime can't run. */
    [CCode (cname = "ts_parser_set_language")]
    public bool set_language (Language language);

    /** Restricts the next parses to `ranges` (ascending, not overlapping) of the text: how one language is parsed out of the middle of another. Null goes back to the whole text. */
    [CCode (cname = "ts_parser_set_included_ranges")]
    public bool set_included_ranges ([CCode (array_length_type = "uint32_t")] Range[]? ranges);

    /** `length` in bytes. `old_tree`, already {@link Tree.edit}ed, makes the parse incremental. */
    [CCode (cname = "ts_parser_parse_string")]
    public Tree? parse_string (Tree? old_tree, string text, uint32 length);

    /**
     * A parse that `options`' progress callback can halt: it then
     * returns null, and the same call over again picks up where it
     * stopped. {@link reset} instead makes the next parse start over.
     */
    [CCode (cname = "ts_parser_parse_with_options")]
    public Tree? parse_with_options (Tree? old_tree, Input input, ParseOptions options);

    [CCode (cname = "ts_parser_reset")]
    public void reset ();
  }

  [CCode (cname = "TSQueryError", has_type_id = false)]
  public enum QueryError {
    [CCode (cname = "TSQueryErrorNone")]
    NONE,
    [CCode (cname = "TSQueryErrorSyntax")]
    SYNTAX,
    [CCode (cname = "TSQueryErrorNodeType")]
    NODE_TYPE,
    [CCode (cname = "TSQueryErrorField")]
    FIELD,
    [CCode (cname = "TSQueryErrorCapture")]
    CAPTURE,
    [CCode (cname = "TSQueryErrorStructure")]
    STRUCTURE,
    [CCode (cname = "TSQueryErrorLanguage")]
    LANGUAGE,
  }

  [CCode (cname = "TSQueryPredicateStepType", has_type_id = false)]
  public enum QueryPredicateStepType {
    [CCode (cname = "TSQueryPredicateStepTypeDone")]
    DONE,
    [CCode (cname = "TSQueryPredicateStepTypeCapture")]
    CAPTURE,
    [CCode (cname = "TSQueryPredicateStepTypeString")]
    STRING,
  }

  [CCode (cname = "TSQueryPredicateStep", has_type_id = false)]
  public struct QueryPredicateStep {
    public QueryPredicateStepType type;
    /** A capture id or a string id, by `type`. */
    public uint32 value_id;
  }

  [CCode (cname = "TSQueryCapture", has_type_id = false)]
  public struct QueryCapture {
    public Node node;
    public uint32 index;
  }

  [CCode (cname = "TSQueryMatch", has_type_id = false)]
  public struct QueryMatch {
    public uint32 id;
    public uint16 pattern_index;
    [CCode (array_length_cname = "capture_count", array_length_type = "uint16_t")]
    public unowned QueryCapture[] captures;
  }

  [CCode (cname = "TSQuery", free_function = "ts_query_delete", has_type_id = false)]
  [Compact]
  public class Query {
    /** Null on a query that doesn't compile — `error_offset` (bytes) and `error_type` say where and why. */
    [CCode (cname = "ts_query_new")]
    public static Query? create (Language language, string source, uint32 source_length, out uint32 error_offset, out QueryError error_type);

    [CCode (cname = "ts_query_pattern_count")]
    public uint32 pattern_count ();

    [CCode (cname = "ts_query_capture_count")]
    public uint32 capture_count ();

    [CCode (cname = "ts_query_capture_name_for_id")]
    public unowned string capture_name_for_id (uint32 index, out uint32 length);

    [CCode (cname = "ts_query_string_value_for_id")]
    public unowned string string_value_for_id (uint32 index, out uint32 length);

    /** Every predicate of one pattern, flattened: each one's steps end in a DONE step. */
    [CCode (cname = "ts_query_predicates_for_pattern", array_length_type = "uint32_t")]
    public unowned QueryPredicateStep[] predicates_for_pattern (uint32 pattern_index);
  }

  [CCode (cname = "TSQueryCursor", free_function = "ts_query_cursor_delete", has_type_id = false)]
  [Compact]
  public class QueryCursor {
    [CCode (cname = "ts_query_cursor_new")]
    public QueryCursor ();

    [CCode (cname = "ts_query_cursor_exec")]
    public void exec (Query query, Node node);

    /** Limits the next {@link exec} to matches that intersect the range. */
    [CCode (cname = "ts_query_cursor_set_point_range")]
    public bool set_point_range (Point start, Point end);

    [CCode (cname = "ts_query_cursor_next_match")]
    public bool next_match (out QueryMatch match);
  }
}
