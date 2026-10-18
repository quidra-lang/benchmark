text <- "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."
words <- regmatches(tolower(text),gregexpr("[a-z]+",tolower(text)))[[1]]
frequencies <- table(words)
ordered <- order(-as.numeric(frequencies),names(frequencies),method="radix")
for (i in ordered[1:5]) cat(sprintf("%s: %d\n",names(frequencies)[i],frequencies[i]))
cat(sprintf("distinct words: %d\n",length(frequencies)))
