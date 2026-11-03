phrases <- c(
  "Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
  "Step on no pets.", "No lemon, no melon"
)
for (phrase in phrases) {
  clean <- utf8ToInt(tolower(gsub("[^A-Za-z]", "", phrase)))
  cat(sprintf("%s -> %s\n", phrase, if (identical(clean, rev(clean))) "yes" else "no"))
}
