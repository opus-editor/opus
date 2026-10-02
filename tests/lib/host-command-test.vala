// Runs natively (no /.flatpak-info), so every test here exercises the
// pass-through side; the flatpak-spawn side is only reachable inside a
// real sandbox, checked by hand on a Flatpak build.

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/host-command/outside-a-sandbox-argv-is-the-command-itself", () => {
        string[] command = { "git", "-C", "/tmp", "status" };

        var argv = HostCommand.argv (command);

        assert_cmpint (argv.length, CompareOperator.EQ, 4);
        assert_cmpstr (argv[0], CompareOperator.EQ, "git");
        assert_cmpstr (argv[3], CompareOperator.EQ, "status");
    });

    Test.add_func ("/host-command/outside-a-sandbox-reports-not-sandboxed", () => {
        assert_false (HostCommand.in_sandbox ());
    });

    Test.add_func ("/host-command/finds-a-program-on-the-path", () => {
        assert_true (HostCommand.has_program ("sh"));
    });

    Test.add_func ("/host-command/does-not-find-a-program-that-is-not-there", () => {
        assert_false (HostCommand.has_program ("opus-no-such-program-4f1c"));
    });

    Test.add_func ("/host-command/shared-tmp-dir-is-a-writable-directory", () => {
        var dir = HostCommand.shared_tmp_dir ();

        assert_true (FileUtils.test (dir, FileTest.IS_DIR));
        assert_cmpint (Posix.access (dir, Posix.W_OK), CompareOperator.EQ, 0);
    });

    return Test.run ();
}
