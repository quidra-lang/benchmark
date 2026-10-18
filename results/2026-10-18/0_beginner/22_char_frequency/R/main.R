codes <- utf8ToInt(tolower("Peter Piper picked a peck of pickled peppers!"))
counts <- tabulate(codes - 96, nbins = 26)
present <- which(counts > 0)
cat(sprintf("%s: %d\n", letters[present], counts[present]), sep = "")
