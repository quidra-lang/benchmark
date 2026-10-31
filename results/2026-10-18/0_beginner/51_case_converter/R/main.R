capitalize <- function(word) paste0(toupper(substr(word, 1, 1)), substr(word, 2, nchar(word)))

identifiers <- c(
  "user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time",
  "isEmailAddressValid"
)
for (identifier in identifiers) {
  separated <- gsub("([A-Z])", " \\1", identifier)
  words <- strsplit(tolower(gsub("[_-]", " ", separated)), " +")[[1]]
  words <- words[nzchar(words)]
  capitals <- capitalize(words)
  camel <- paste0(words[1], paste(capitals[-1], collapse = ""))
  cat(sprintf(
    "%s: snake=%s, camel=%s, pascal=%s, kebab=%s\n",
    identifier, paste(words, collapse = "_"), camel, paste(capitals, collapse = ""),
    paste(words, collapse = "-")
  ))
}
