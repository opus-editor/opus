// Every test here has `git`/`sh` on the local PATH — true on a dev
// machine and inside the Sdk's build sandbox alike — so they exercise
// the local pass-through; the flatpak-spawn side only exists where a
// program is missing locally, checked by hand on a Flatpak build.

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/host-command/a-local-program-argv-is-the-command-itself", () => {
        string[] command = { "git", "-C", "/tmp", "status" };

        var argv = HostCommand.argv (command);

        assert_cmpint (argv.length, CompareOperator.EQ, 4);
        assert_cmpstr (argv[0], CompareOperator.EQ, "git");
        assert_cmpstr (argv[3], CompareOperator.EQ, "status");
    });

    Test.add_func ("/host-command/finds-a-program-on-the-path", () => {
        assert_true (HostCommand.has_program ("sh"));
    });

    Test.add_func ("/host-command/does-not-find-a-program-that-is-not-there", () => {
        assert_false (HostCommand.has_program ("opus-no-such-program-4f1c"));
    });

    Test.add_func ("/host-command/shared-tmp-dir-for-a-local-program-is-the-tmp-dir", () => {
        var dir = HostCommand.shared_tmp_dir ("sh");

        assert_cmpstr (dir, CompareOperator.EQ, Environment.get_tmp_dir ());
        assert_cmpint (Posix.access (dir, Posix.W_OK), CompareOperator.EQ, 0);
    });

    return Test.run ();
}
