words <- strsplit("we planted beans and carrots in the garden behind our old house", " ", fixed = TRUE)[[1]]
lengths <- nchar(words)
cat(sprintf(
  "words: %d\nlongest: %s\nshortest: %s\naverage length: %.2f\n",
  length(words), words[which.max(lengths)], words[which.min(lengths)], mean(lengths)
))
