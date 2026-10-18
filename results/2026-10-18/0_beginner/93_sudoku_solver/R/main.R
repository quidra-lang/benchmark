puzzle <- c("800025000","070080005","260400070","000001900","010000040","600200000","900010000","700000004","020000036")
board <- do.call(rbind,lapply(puzzle,function(row) utf8ToInt(row)-48L))
placements <- 0
solve <- function() {
    for (row in 1:9) {
        for (column in 1:9) {
            if (board[row,column] == 0) {
                for (digit in 1:9) {
                    if (digit %in% board[row,] || digit %in% board[,column]) next
                    block_row <- 3*((row-1) %/% 3)+1
                    block_column <- 3*((column-1) %/% 3)+1
                    if (digit %in% board[block_row:(block_row+2),block_column:(block_column+2)]) next
                    board[row,column] <<- digit
                    placements <<- placements+1
                    if (solve()) return(TRUE)
                    board[row,column] <<- 0L
                }
                return(FALSE)
            }
        }
    }
    TRUE
}
invisible(solve())
for (row in 1:9) cat(paste(board[row,],collapse=" "),"\n",sep="")
cat(sprintf("placements: %d\n",placements))
