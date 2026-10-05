import { useState } from "react";

const locales = [
  { code: "en", name: "English" },
  { code: "pt-BR", name: "Português" },
];

function LocaleItem({ locale, active, onPick }) {
  return (
    <li className={active ? "locale is-active" : "locale"} onClick={() => onPick(locale.code)}>
      {locale.name} <small>({locale.code})</small>
    </li>
  );
}

export default function LocalePicker({ initial = "en" }) {
  const [current, setCurrent] = useState(initial);

  return (
    <ul className="locale-list">
      {locales.map((locale) => (
        <LocaleItem key={locale.code} locale={locale} active={locale.code === current} onPick={setCurrent} />
      ))}
    </ul>
  );
}
