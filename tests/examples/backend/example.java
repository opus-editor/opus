import java.util.List;
import java.util.Optional;

public class LocaleResolver {
  record Locale(String code, String name) {}

  static Optional<Locale> findLocale(List<Locale> locales, String code) {
    return locales.stream()
      .filter(locale -> locale.code().equalsIgnoreCase(code))
      .findFirst();
  }

  public static void main(String[] args) {
    var locales = List.of(
      new Locale("en", "English"),
      new Locale("pt-BR", "Português")
    );

    Optional<Locale> match = findLocale(locales, "pt-BR");
    System.out.println(match.map(Locale::name).orElse("no match"));
  }
}
