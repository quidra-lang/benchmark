row <- 1
for (n in 0:11) {
    cat(paste(row, collapse = " "), "\n", sep = "")
    next_row <- rep(1, length(row)+1)
    if (length(row) > 1) for (k in 2:length(row)) next_row[k] <- row[k-1] + row[k]
    row <- next_row
}
