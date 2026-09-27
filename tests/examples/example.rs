struct Locale {
  code: &'static str,
  name: &'static str,
}

fn find_locale(locales: &[Locale], code: &str) -> Option<&Locale> {
  locales.iter().find(|locale| locale.code.eq_ignore_ascii_case(code))
}

fn requested_locale(locales: &[Locale], accept_language: &str) -> Option<&Locale> {
  for tag in accept_language.split(',').map(|t| t.split(';').next().unwrap().trim()) {
    if let Some(locale) = find_locale(locales, tag) {
      return Some(locale);
    }
    if let Some(prefix) = tag.split('-').next() {
      if let Some(locale) = find_locale(locales, prefix) {
        return Some(locale);
      }
    }
  }
  None
}

fn main() {
  let locales = [
    Locale { code: "en", name: "English" },
    Locale { code: "pt-BR", name: "Português" },
  ];

  match requested_locale(&locales, "pt-BR,pt;q=0.9,en;q=0.8") {
    Some(locale) => println!("{}", locale.name),
    None => println!("no match"),
  }
}
