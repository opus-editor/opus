#include <iostream>
#include <optional>
#include <string>
#include <vector>

struct Locale {
  std::string code;
  std::string name;
};

std::optional<Locale> find_locale(const std::vector<Locale> &locales, const std::string &code) {
  for (const auto &locale : locales) {
    if (locale.code == code) {
      return locale;
    }
  }
  return std::nullopt;
}

int main() {
  std::vector<Locale> locales{
    {"en", "English"},
    {"pt-BR", "Português"},
  };

  if (auto match = find_locale(locales, "pt-BR")) {
    std::cout << "matched: " << match->name << '\n';
  } else {
    std::cout << "no match\n";
  }

  return 0;
}
