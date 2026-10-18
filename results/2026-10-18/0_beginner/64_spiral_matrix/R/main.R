values <- matrix(0L,5,6)
directions <- list(c(0,1),c(1,0),c(0,-1),c(-1,0))
row <- 1
column <- 1
direction <- 1
for (value in 1:30) {
    values[row,column] <- value
    if (value == 30) break
    dr <- directions[[direction]][1]
    dc <- directions[[direction]][2]
    next_row <- row+dr
    next_column <- column+dc
    if (next_row < 1 || next_row > 5 || next_column < 1 || next_column > 6 || values[next_row,next_column] != 0) {
        direction <- direction %% 4+1
        dr <- directions[[direction]][1]
        dc <- directions[[direction]][2]
    }
    row <- row+dr
    column <- column+dc
}
for (row in 1:5) cat(paste(sprintf("%3d",values[row,]),collapse=""),"\n",sep="")
