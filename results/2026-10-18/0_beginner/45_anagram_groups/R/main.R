groups <- list(); signatures <- character(0)
for (word in c("listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones")) {
    signature <- paste(sort(strsplit(word,"",fixed=TRUE)[[1]],method="radix"),collapse="")
    index <- match(signature,signatures)
    if (is.na(index)) { signatures <- c(signatures,signature); index <- length(signatures); groups[[index]] <- character(0) }
    groups[[index]] <- c(groups[[index]],word)
}
for (group in groups) cat(paste(group,collapse=" "),"\n",sep="")
