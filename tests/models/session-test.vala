int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/models/session/insert_mode/starts_disabled", () => {
        var session = new Session ();

        assert_false (session.insert_mode);
    });

    Test.add_func ("/models/session/insert_mode/setting_it_notifies_listeners", () => {
        var session = new Session ();
        int notify_count = 0;
        session.notify["insert-mode"].connect (() => notify_count++);

        session.insert_mode = true;

        assert_cmpint (notify_count, CompareOperator.EQ, 1);
    });

    Test.add_func ("/models/session/get_default/returns_the_same_instance_every_time", () => {
        var a = Session.get_default ();
        var b = Session.get_default ();

        assert_true (a == b);
    });

    return Test.run ();
}
