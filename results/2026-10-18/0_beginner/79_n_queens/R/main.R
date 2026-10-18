solve_queens <- function(n) {
    columns <- rep(-1L,n)
    first_solution <- integer(0)
    solutions <- 0
    place <- function(row) {
        if (row == n) {
            solutions <<- solutions+1
            if (length(first_solution) == 0) first_solution <<- columns
            return(invisible(NULL))
        }
        for (column in 0:(n-1)) {
            valid <- TRUE
            if (row > 0) {
                for (previous in 0:(row-1)) {
                    if (columns[previous+1] == column || abs(columns[previous+1]-column) == row-previous) {
                        valid <- FALSE
                        break
                    }
                }
            }
            if (valid) {
                columns[row+1] <<- column
                place(row+1)
            }
        }
    }
    place(0)
    list(count=solutions,first=first_solution)
}
for (n in 4:8) {
    result <- solve_queens(n)
    cat(sprintf("N=%d: %d solutions\n",n,result$count))
}
for (column in result$first) cat(strrep(".",column),"Q",strrep(".",7-column),"\n",sep="")
