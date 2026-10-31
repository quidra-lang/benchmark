numbers <- c(52, 17, 38, 9, 61, 38, 24, 45)
total <- 0
for (i in 2:8) {
  value <- numbers[i]
  j <- i - 1
  shifts <- 0
  while (j >= 1 && numbers[j] > value) {
    numbers[j + 1] <- numbers[j]
    shifts <- shifts + 1
    j <- j - 1
  }
  numbers[j + 1] <- value
  total <- total + shifts
  cat(sprintf("i=%d shifts=%d: %s\n", i - 1, shifts, paste(numbers, collapse = " ")))
}
cat(sprintf("total shifts: %d\n", total))
