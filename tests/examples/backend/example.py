from dataclasses import dataclass


@dataclass
class Locale:
  code: str
  name: str


def requested_locale(available: list[Locale], accept_language: str) -> Locale | None:
  """Picks the best matching locale from the Accept-Language header."""
  tags = [tag.split(";")[0].strip().lower() for tag in accept_language.split(",")]
  by_code = {locale.code.lower(): locale for locale in available}

  for tag in tags:
    if tag in by_code:
      return by_code[tag]
    prefix = tag.split("-")[0]
    if prefix in by_code:
      return by_code[prefix]

  return None


if __name__ == "__main__":
  locales = [Locale("en", "English"), Locale("pt-BR", "Português")]
  match = requested_locale(locales, "pt-BR,pt;q=0.9,en;q=0.8")
  print(match.name if match else "no match")
