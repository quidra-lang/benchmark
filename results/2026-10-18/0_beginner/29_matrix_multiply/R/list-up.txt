a <- matrix(c(3, -2, 5, 1, -4, 7, 0, 6, 2, 9, -8, -3), nrow = 3, byrow = TRUE)
b <- matrix(c(1, 4, -5, 2, 6, -1, 0, 7), nrow = 4, byrow = TRUE)
product <- a %*% b
for (i in 1:3) cat(paste(sprintf("%5d", product[i, ]), collapse = ""), "\n", sep = "")
