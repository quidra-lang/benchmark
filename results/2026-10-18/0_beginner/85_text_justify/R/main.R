paragraph <- "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week."
lines <- list()
current <- character(0)
letters <- 0
for (word in strsplit(paragraph, " ", fixed = TRUE)[[1]]) {
  if (length(current) > 0 && letters + length(current) + nchar(word) > 30) {
    lines[[length(lines) + 1]] <- current
    current <- character(0)
    letters <- 0
  }
  current <- c(current, word)
  letters <- letters + nchar(word)
}
lines[[length(lines) + 1]] <- current
for (number in seq_along(lines)) {
  words <- lines[[number]]
  if (number == length(lines) || length(words) == 1) {
    line <- sprintf("%-30s", paste(words, collapse = " "))
  } else {
    spaces <- 30 - sum(nchar(words))
    gaps <- length(words) - 1
    base <- spaces %/% gaps
    extra <- spaces %% gaps
    padding <- strrep(" ", c(base + (seq_len(gaps) <= extra), 0))
    line <- paste0(words, padding, collapse = "")
  }
  cat("|", line, "|\n", sep = "")
}
