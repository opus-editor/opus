locales <- list(
  list(code = "en", name = "English"),
  list(code = "pt-BR", name = "Português")
)

find_locale <- function(code) {
  for (locale in locales) {
    if (tolower(locale$code) == tolower(code)) {
      return(locale)
    }
  }
  return(NULL)
}

requested_locale <- function(accept_language) {
  tags <- trimws(sapply(strsplit(accept_language, ",")[[1]], function(t) strsplit(t, ";")[[1]][1]))

  for (tag in tags) {
    match <- find_locale(tag)
    if (is.null(match)) {
      match <- find_locale(strsplit(tag, "-")[[1]][1])
    }
    if (!is.null(match)) {
      return(match)
    }
  }
  return(NULL)
}

match <- requested_locale("pt-BR,pt;q=0.9,en;q=0.8")
if (!is.null(match)) {
  cat(match$name, "\n")
} else {
  cat("no match\n")
}
