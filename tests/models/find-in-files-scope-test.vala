// Pure logic, no filesystem involved — FindInFilesScope only ever
// matches against relative path strings the caller already computed.

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/find-in-files-scope/empty-text-includes-everything", () => {
        try {
            var scope = new FindInFilesScope ("");
            assert (scope.is_path_included ("anything.txt"));
            assert (scope.is_path_included ("deep/nested/path.vala"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/leading-slash-anchors-a-folder-to-the-root", () => {
        try {
            var scope = new FindInFilesScope ("/src");
            assert (scope.is_path_included ("src/foo.txt"));
            assert (scope.is_path_included ("src/nested/foo.txt"));
            assert (!scope.is_path_included ("lib/foo.txt"));
            // Anchored — a *nested* "src" doesn't count, only the one at the root.
            assert (!scope.is_path_included ("other/src/foo.txt"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/bare-file-glob-matches-at-any-depth", () => {
        try {
            var scope = new FindInFilesScope ("*.vala");
            assert (scope.is_path_included ("foo.vala"));
            assert (scope.is_path_included ("src/foo.vala"));
            assert (scope.is_path_included ("src/nested/foo.vala"));
            assert (!scope.is_path_included ("foo.c"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/negated-folder-excludes-it-everything-else-stays", () => {
        try {
            var scope = new FindInFilesScope ("!/build");
            assert (!scope.is_path_included ("build/output.txt"));
            assert (!scope.is_path_included ("build/nested/output.txt"));
            assert (scope.is_path_included ("src/foo.vala"));
            // Same anchoring rule as a plain inclusion — a *nested*
            // "build" isn't the one this excludes.
            assert (scope.is_path_included ("other/build/output.txt"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/negated-file-glob-excludes-it-everywhere", () => {
        try {
            var scope = new FindInFilesScope ("!*.c");
            assert (!scope.is_path_included ("foo.c"));
            assert (!scope.is_path_included ("src/foo.c"));
            assert (scope.is_path_included ("foo.vala"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/combines-an-inclusion-and-an-exclusion", () => {
        try {
            var scope = new FindInFilesScope ("/src, !/src/vendor");
            assert (scope.is_path_included ("src/foo.vala"));
            assert (!scope.is_path_included ("src/vendor/foo.vala"));
            assert (!scope.is_path_included ("lib/foo.vala")); // outside /src entirely
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/exclusion-always-wins-over-a-matching-inclusion", () => {
        try {
            // Same file matches both an inclusion and an exclusion —
            // exclusion must win regardless of pattern order.
            var scope = new FindInFilesScope ("*.vala, !*.vala");
            assert (!scope.is_path_included ("foo.vala"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/double-star-matches-any-number-of-directories", () => {
        try {
            var scope = new FindInFilesScope ("/src/**/*.vala");
            assert (scope.is_path_included ("src/foo.vala"));
            assert (scope.is_path_included ("src/a/foo.vala"));
            assert (scope.is_path_included ("src/a/b/foo.vala"));
            assert (!scope.is_path_included ("lib/foo.vala"));
        } catch (Error e) {
            error (e.message);
        }
    });

    Test.add_func ("/find-in-files-scope/trailing-slash-matches-only-inside-that-directory", () => {
        try {
            var scope = new FindInFilesScope ("!/build/");
            assert (!scope.is_path_included ("build/output.txt"));
            // Not a prefix match — a differently-named directory that
            // merely starts with "build" must stay included.
            assert (scope.is_path_included ("buildx/output.txt"));
        } catch (Error e) {
            error (e.message);
        }
    });

    return Test.run ();
}
