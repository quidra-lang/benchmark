words <- strsplit("we planted beans and carrots in the garden behind our old house", " ", fixed = TRUE)[[1]]
lengths <- nchar(words)
average <- sum(lengths) / length(words)
cat(sprintf("words: %d\nlongest: %s\nshortest: %s\naverage length: %.2f\n",
    length(words), words[which.max(lengths)], words[which.min(lengths)], floor(average * 100 + 0.5) / 100))
