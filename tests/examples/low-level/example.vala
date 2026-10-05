public class Locale : Object {
  public string code { get; construct; }
  public string name { get; construct; }

  public Locale (string code, string name) {
    Object (code: code, name: name);
  }
}

public class LocaleMatcher : Object {
  private GenericArray<Locale> locales = new GenericArray<Locale> ();

  public void add (Locale locale) {
    locales.add (locale);
  }

  /** The first tag of `accept_language` that names a known locale, or its base language. */
  public Locale? requested (string accept_language) {
    foreach (unowned string part in accept_language.split (",")) {
      var tag = part.split (";")[0].strip ();
      var match = find (tag) ?? find (tag.split ("-")[0]);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  private Locale? find (string code) {
    foreach (var locale in locales) {
      if (locale.code.ascii_casecmp (code) == 0) {
        return locale;
      }
    }
    return null;
  }
}

int main (string[] args) {
  var matcher = new LocaleMatcher ();
  matcher.add (new Locale ("en", "English"));
  matcher.add (new Locale ("pt-BR", "Português"));

  var match = matcher.requested ("pt-BR,pt;q=0.9,en;q=0.8");
  print ("%s\n", match != null ? match.name : "no match");
  return 0;
}
