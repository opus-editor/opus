<?php

final class Locale
{
  public function __construct(
    public readonly string $code,
    public readonly string $name,
  ) {}
}

function find_locale(array $locales, string $code): ?Locale
{
  foreach ($locales as $locale) {
    if (strcasecmp($locale->code, $code) === 0) {
      return $locale;
    }
  }
  return null;
}

function requested_locale(array $locales, string $acceptLanguage): ?Locale
{
  $tags = array_map(fn ($tag) => trim(explode(';', $tag)[0]), explode(',', $acceptLanguage));

  foreach ($tags as $tag) {
    $match = find_locale($locales, $tag) ?? find_locale($locales, explode('-', $tag)[0]);
    if ($match !== null) {
      return $match;
    }
  }
  return null;
}

$locales = [
  new Locale('en', 'English'),
  new Locale('pt-BR', 'Português'),
];

$match = requested_locale($locales, 'pt-BR,pt;q=0.9,en;q=0.8');
echo $match !== null ? $match->name : 'no match';
echo "\n";
