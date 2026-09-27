using System;
using System.Collections.Generic;
using System.Linq;

record Locale(string Code, string Name);

class LocaleResolver
{
  static Locale? FindLocale(List<Locale> locales, string code) =>
    locales.FirstOrDefault(locale => locale.Code.Equals(code, StringComparison.OrdinalIgnoreCase));

  static void Main()
  {
    var locales = new List<Locale>
    {
      new("en", "English"),
      new("pt-BR", "Português"),
    };

    var match = FindLocale(locales, "pt-BR");
    Console.WriteLine(match?.Name ?? "no match");
  }
}
