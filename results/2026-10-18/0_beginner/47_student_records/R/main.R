names <- c("Tanaka","Suzuki","Yamada","Ito","Kato","Mori")
scores <- matrix(c(78,85,94,88,74,82,65,90,71,80,79,85,92,88,95,70,62,78),nrow=6,byrow=TRUE)
totals <- rowSums(scores)
ordered <- order(-totals,names,method="radix")
rank <- 0; previous <- -1
for (position in seq_along(ordered)) {
    i <- ordered[position]
    if (totals[i] != previous) rank <- position
    average <- totals[i]/3
    cat(sprintf("%d. %s total=%d average=%.2f\n",rank,names[i],totals[i],floor(average*100+0.5)/100))
    previous <- totals[i]
}
