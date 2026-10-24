initial <- c(".#......","..#.....","###.....","........","........","........",".....###","........")
board <- do.call(rbind,strsplit(initial,"",fixed=TRUE)) == "#"
for (generation in 0:4) {
    cat(sprintf("generation %d\n",generation))
    for (row in 1:8) cat(paste(ifelse(board[row,],"#","."),collapse=""),"\n",sep="")
    if (generation == 4) break
    following <- matrix(FALSE,8,8)
    for (row in 1:8) {
        for (column in 1:8) {
            neighbors <- 0
            for (dr in -1:1) {
                for (dc in -1:1) {
                    if (dr == 0 && dc == 0) next
                    r <- row+dr
                    c_value <- column+dc
                    if (r >= 1 && r <= 8 && c_value >= 1 && c_value <= 8) neighbors <- neighbors+board[r,c_value]
                }
            }
            following[row,column] <- neighbors == 3 || (board[row,column] && neighbors == 2)
        }
    }
    board <- following
}
cat(sprintf("alive: %d\n",sum(board)))
