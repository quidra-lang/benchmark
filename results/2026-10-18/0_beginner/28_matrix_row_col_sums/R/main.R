matrix_values <- matrix(c(125,340,78,912,456,603,27,819,150,384,0,765,231,498,62,947,113,586,39,720), nrow = 4, byrow = TRUE)
for (i in 1:4) {
    cat(paste(sprintf("%6d", c(matrix_values[i, ], sum(matrix_values[i, ]))), collapse = ""), "\n", sep = "")
}
cat(paste(sprintf("%6d", c(colSums(matrix_values), sum(matrix_values))), collapse = ""), "\n", sep = "")
