/**
 * A Find in Files search request: the query text plus the same three
 * options FindBar's own single-file search already exposes (Regular
 * Expressions/Case Sensitive/Match Whole Word Only). Collapsing these
 * into one object here, rather than four separate parameters, is what
 * keeps FindInFilesSearch.run()/EditorPaneWidget.search_in_files()/
 * EditorView.EditorPane.FindResults.show_results() from each growing a
 * parallel parameter list — and gives Replace/Where (later parts of
 * this same feature) a natural place to grow into instead of more.
 */
public class FindInFilesQuery : Object {
  public string text { get; set; default = ""; }
  public bool regex_enabled { get; set; default = false; }
  public bool case_sensitive_enabled { get; set; default = false; }
  public bool whole_word_enabled { get; set; default = false; }

  /** Restricts the walk to whatever `git ls-files` itself would show (tracked files, plus untracked ones .gitignore/.git/info/exclude/the user's own global excludesFile don't hide) — see FindInFilesSearch's own doc comment for why that's a real `git` invocation, not a hand-rolled .gitignore parser. A no-op outside a git repo (or without git installed at all): the search just runs unfiltered, same as this being off. */
  public bool gitignore_enabled { get; set; default = false; }

  /** The "Where" field's own raw text — comma-separated .gitignore-style patterns, parsed by FindInFilesScope (see its own doc comment for the exact grammar and, importantly, why its include/exclude polarity is the opposite of a real .gitignore's). "" (the default) means no scope restriction at all. */
  public string where_text { get; set; default = ""; }
}
