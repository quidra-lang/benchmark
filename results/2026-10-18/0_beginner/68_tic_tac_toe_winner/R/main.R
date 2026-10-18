outcome <- function(board) {
    values <- do.call(rbind,strsplit(board,"",fixed=TRUE))
    lines <- c(lapply(1:3,function(i) values[i,]),lapply(1:3,function(i) values[,i]),list(diag(values),values[cbind(1:3,3:1)]))
    for (line in lines) {
        if (line[1] != "." && all(line == line[1])) return(paste(line[1],"wins"))
    }
    if (any(values == ".")) "in progress" else "draw"
}
boards <- list(c("XXX","OO.","O.X"),c("X.O",".X.","O.."),c("XO.",".OX","XO."),c("XOX","XOO","OXX"),c("X.O","XO.","O.X"),c("XOX","OXO","OXX"))
for (i in seq_along(boards)) cat(sprintf("board %d: %s\n",i,outcome(boards[[i]])))
