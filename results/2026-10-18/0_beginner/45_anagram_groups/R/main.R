words <- c("listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones")
signatures <- vapply(words, function(word) paste(sort(strsplit(word,"",fixed=TRUE)[[1]],method="radix"),collapse=""), character(1))
groups <- split(words, factor(signatures, levels=unique(signatures)))
for (group in groups) cat(paste(group,collapse=" "),"\n",sep="")
