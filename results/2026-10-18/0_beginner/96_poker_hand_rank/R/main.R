describe_hand <- function(original) {
    cards <- strsplit(original," ",fixed=TRUE)[[1]]
    alphabet <- strsplit("23456789TJQKA","",fixed=TRUE)[[1]]
    ranks <- match(substr(cards,1,1),alphabet)+1
    frequencies <- tabulate(ranks,nbins=14)
    distinct <- which(frequencies > 0)
    wheel <- identical(distinct,c(2L,3L,4L,5L,14L))
    straight <- length(distinct) == 5 && (max(distinct)-min(distinct) == 4 || wheel)
    flush <- length(unique(substr(cards,2,2))) == 1
    counts <- sort(frequencies[distinct],decreasing=TRUE)
    if (straight && flush) {
        strength <- 9
    } else if (counts[1] == 4) {
        strength <- 8
    } else if (identical(counts,c(3L,2L))) {
        strength <- 7
    } else if (flush) {
        strength <- 6
    } else if (straight) {
        strength <- 5
    } else if (counts[1] == 3) {
        strength <- 4
    } else if (identical(counts,c(2L,2L,1L))) {
        strength <- 3
    } else if (counts[1] == 2) {
        strength <- 2
    } else {
        strength <- 1
    }
    sequence <- if (wheel && straight) c(5,4,3,2,1) else distinct[order(-frequencies[distinct],-distinct)]
    categories <- c("high card","one pair","two pair","three of a kind","straight","flush","full house","four of a kind","straight flush")
    list(original=original,strength=strength,sequence=c(sequence,rep(0,5-length(sequence))),category=categories[strength])
}
hands <- lapply(c("9C 9D 5H QH 2C","4D AH 3C 5S 2H","KS 8S 2S JS 6S","7H 7D KC 7S KD","3H 6C 4S 2D 5C","JD TC 4H 8C AS","QC 6D QS 3S 6H","9H KH 9S 8H 3D"),describe_hand)
strengths <- vapply(hands,function(hand) hand$strength,numeric(1))
ties <- do.call(rbind,lapply(hands,function(hand) hand$sequence))
ordered <- order(-strengths,-ties[,1],-ties[,2],-ties[,3],-ties[,4],-ties[,5])
for (position in seq_along(ordered)) {
    hand <- hands[[ordered[position]]]
    cat(sprintf("%d. %s: %s\n",position,hand$original,hand$category))
}
