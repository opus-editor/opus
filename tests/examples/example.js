const locales = [
  { code: "en", name: "English" },
  { code: "pt-BR", name: "Português" },
];

function findLocale(code) {
  return locales.find((locale) => locale.code.toLowerCase() === code.toLowerCase());
}

function requestedLocale(acceptLanguage) {
  const tags = acceptLanguage.split(",").map((tag) => tag.split(";")[0].trim());

  for (const tag of tags) {
    const match = findLocale(tag) ?? findLocale(tag.split("-")[0]);
    if (match) return match;
  }

  return null;
}

const match = requestedLocale("pt-BR,pt;q=0.9,en;q=0.8");
console.log(match ? match.name : "no match");
