sentence <- "every program starts with a single line"
characters <- strsplit(sentence, "", fixed = TRUE)[[1]]
words <- strsplit(sentence, " ", fixed = TRUE)[[1]]
cat(paste(rev(characters), collapse = ""), "\n", sep = "")
cat(paste(rev(words), collapse = " "), "\n", sep = "")
