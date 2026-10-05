import { useState } from "react";

interface Locale {
  code: string;
  name: string;
}

interface LocaleItemProps {
  locale: Locale;
  active: boolean;
  onPick: (code: string) => void;
}

const locales: Locale[] = [
  { code: "en", name: "English" },
  { code: "pt-BR", name: "Português" },
];

function LocaleItem({ locale, active, onPick }: LocaleItemProps) {
  return (
    <li className={active ? "locale is-active" : "locale"} onClick={() => onPick(locale.code)}>
      {locale.name} <small>({locale.code})</small>
    </li>
  );
}

export default function LocalePicker({ initial = "en" }: { initial?: string }) {
  const [current, setCurrent] = useState<string>(initial);

  return (
    <ul className="locale-list">
      {locales.map((locale) => (
        <LocaleItem key={locale.code} locale={locale} active={locale.code === current} onPick={setCurrent} />
      ))}
    </ul>
  );
}
