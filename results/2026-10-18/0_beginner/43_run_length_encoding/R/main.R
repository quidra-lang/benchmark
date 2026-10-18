encode <- function(source) {
    runs <- rle(strsplit(source,"",fixed=TRUE)[[1]])
    paste(paste0(runs$lengths,runs$values),collapse="")
}
decode <- function(encoded) {
    runs <- regmatches(encoded,gregexpr("[0-9]+[A-Z]",encoded))[[1]]
    paste(vapply(runs,function(run) {
        size <- nchar(run)
        strrep(substr(run,size,size),as.integer(substr(run,1,size-1)))
    },character(1)),collapse="")
}
for (source in c("AAABBBCCCD","WWWWWWWWWWWWBWWWWWWWWWWWWBBB","ALGORITHM","MISSISSIPPI","XXXXXXXXXXYYYYYYYYYYYYYYYYYYYYYZ")) {
    encoded <- encode(source)
    cat(sprintf("%s -> %s -> %s\n",source,encoded,decode(encoded)))
}
