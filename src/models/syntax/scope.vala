namespace Syntax {
  /**
   * What the syntax says about one place in a text: the innermost
   * language there (an embedded style sheet's, inside `<style>`) and
   * the highlight captures that contain the place — `string`,
   * `comment.block` — the names a pair's `not-in` is matched against.
   */
  public class Scope : Object {
    public LanguagePackage package { get; private set; }
    public string[] captures { get; private set; }

    public Scope (LanguagePackage package, string[] captures) {
      this.package = package;
      this.captures = captures;
    }
  }
}
