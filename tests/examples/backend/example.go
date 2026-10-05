package main

import (
  "fmt"
  "strings"
)

type Locale struct {
  Code string
  Name string
}

func findLocale(locales []Locale, code string) (Locale, bool) {
  for _, locale := range locales {
    if strings.EqualFold(locale.Code, code) {
      return locale, true
    }
  }
  return Locale{}, false
}

func requestedLocale(locales []Locale, acceptLanguage string) (Locale, bool) {
  tags := strings.Split(acceptLanguage, ",")
  for _, raw := range tags {
    tag := strings.TrimSpace(strings.Split(raw, ";")[0])
    if locale, ok := findLocale(locales, tag); ok {
      return locale, true
    }
  }
  return Locale{}, false
}

func main() {
  locales := []Locale{
    {Code: "en", Name: "English"},
    {Code: "pt-BR", Name: "Português"},
  }

  if match, ok := requestedLocale(locales, "pt-BR,pt;q=0.9,en;q=0.8"); ok {
    fmt.Println(match.Name)
  } else {
    fmt.Println("no match")
  }
}
