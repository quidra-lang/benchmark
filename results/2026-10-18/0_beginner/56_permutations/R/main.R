characters <- strsplit("ABCD","",fixed=TRUE)[[1]]
visit <- function(prefix,used,counter) {
    if (nchar(prefix) == 4) {
        counter <- counter+1
        cat(sprintf("%d: %s\n",counter,prefix))
        return(counter)
    }
    for (i in seq_along(characters)) if (!used[i]) {
        next_used <- used; next_used[i] <- TRUE
        counter <- visit(paste0(prefix,characters[i]),next_used,counter)
    }
    counter
}
invisible(visit("",rep(FALSE,4),0))
