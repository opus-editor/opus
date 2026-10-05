#include <stdio.h>
#include <string.h>

typedef struct {
  const char *code;
  const char *name;
} Locale;

static const Locale *find_locale(const Locale *locales, int count, const char *code) {
  for (int i = 0; i < count; i++) {
    if (strcmp(locales[i].code, code) == 0) {
      return &locales[i];
    }
  }
  return NULL;
}

int main(void) {
  Locale locales[] = {
    {"en", "English"},
    {"pt-BR", "Portugues"},
  };
  int count = sizeof(locales) / sizeof(locales[0]);

  const Locale *match = find_locale(locales, count, "pt-BR");
  if (match != NULL) {
    printf("matched: %s\n", match->name);
  } else {
    printf("no match\n");
  }

  return 0;
}
