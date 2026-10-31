encode <- function(source) {
  runs <- rle(strsplit(source, "", fixed = TRUE)[[1]])
  paste(paste0(runs$lengths, runs$values), collapse = "")
}

decode <- function(encoded) {
  runs <- regmatches(encoded, gregexpr("[0-9]+[A-Z]", encoded))[[1]]
  paste(strrep(sub("[0-9]+", "", runs), as.integer(sub("[A-Z]", "", runs))), collapse = "")
}

sources <- c(
  "AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",
  "XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ"
)
for (source in sources) {
  encoded <- encode(source)
  cat(sprintf("%s -> %s -> %s\n", source, encoded, decode(encoded)))
}
