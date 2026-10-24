cache <- character(0)
hits <- 0
misses <- 0
for (key in c("B","A","C","B","D","A","B","E","A","D","D","C","A","E","B")) {
    index <- match(key,cache)
    if (!is.na(index)) {
        hits <- hits+1
        cache <- cache[-index]
        result <- "hit"
    } else {
        misses <- misses+1
        if (length(cache) == 3) {
            result <- paste("miss, evict",tail(cache,1))
            cache <- head(cache,-1)
        } else result <- "miss"
    }
    cache <- c(key,cache)
    cat(sprintf("%s: %s [%s]\n",key,result,paste(cache,collapse=" ")))
}
cat(sprintf("hits: %d misses: %d\n",hits,misses))
