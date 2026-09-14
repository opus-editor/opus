int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/scaffold/trivial", () => {
        assert (1 + 1 == 2);
    });
    return Test.run ();
}
