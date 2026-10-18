solve_system <- function(values) {
    n <- nrow(values)
    for (k in seq_len(n)) {
        pivot <- k
        if (k < n) {
            for (i in (k+1):n) {
                if (abs(values[i,k]) > abs(values[pivot,k])) pivot <- i
            }
        }
        if (pivot != k) values[c(k,pivot),] <- values[c(pivot,k),]
        if (k < n) {
            for (i in (k+1):n) {
                factor <- values[i,k]/values[k,k]
                for (j in k:(n+1)) {
                    values[i,j] <- values[i,j]-factor*values[k,j]
                }
            }
        }
    }
    solution <- numeric(n)
    for (i in n:1) {
        subtotal <- values[i,n+1]
        if (i < n) {
            for (j in (i+1):n) {
                subtotal <- subtotal-values[i,j]*solution[j]
            }
        }
        solution[i] <- subtotal/values[i,i]
    }
    solution
}
systems <- list(matrix(c(2,-1,3,7,4,1,-2,3,-3,5,1,-4),nrow=3,byrow=TRUE),matrix(c(1,3,-2,4,6,5,-2,1,3,-7,-2,4,6,-1,9,3,1,-4,2,5),nrow=4,byrow=TRUE))
for (number in seq_along(systems)) {
    cat(sprintf("system %d:\n",number))
    solution <- solve_system(systems[[number]])
    for (i in seq_along(solution)) {
        value <- solution[i]
        rounded <- sign(value)*floor(abs(value)*10000+0.5)/10000
        cat(sprintf("x%d = %.4f\n",i,rounded))
    }
}
