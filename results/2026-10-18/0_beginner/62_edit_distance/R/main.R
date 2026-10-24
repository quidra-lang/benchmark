edit_distance <- function(a,b) {
    a <- utf8ToInt(a)
    b <- utf8ToInt(b)
    table <- matrix(0L,length(a)+1,length(b)+1)
    table[,1] <- 0:length(a)
    table[1,] <- 0:length(b)
    for (i in seq_along(a)) {
        for (j in seq_along(b)) {
            cost <- as.integer(a[i] != b[j])
            table[i+1,j+1] <- min(table[i,j+1]+1L,table[i+1,j]+1L,table[i,j]+cost)
        }
    }
    table[nrow(table),ncol(table)]
}
for (pair in list(c("kitten","sitting"),c("flaw","lawn"),c("listen","silent"),c("intention","execution"),c("algorithm","altruistic"))) {
    cat(sprintf("%s -> %s: %d\n",pair[1],pair[2],edit_distance(pair[1],pair[2])))
}
