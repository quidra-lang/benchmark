merge_sort <- function(numbers, lo, hi) {
  if (lo == hi) {
    return(list(numbers = numbers, inversions = 0))
  }
  mid <- (lo + hi) %/% 2
  left_result <- merge_sort(numbers, lo, mid)
  right_result <- merge_sort(left_result$numbers, mid + 1, hi)
  numbers <- right_result$numbers
  inversions <- left_result$inversions + right_result$inversions
  left <- numbers[lo:mid]
  right <- numbers[(mid + 1):hi]
  merged <- numeric(0)
  i <- 1
  j <- 1
  while (i <= length(left) && j <= length(right)) {
    if (left[i] <= right[j]) {
      merged <- c(merged, left[i])
      i <- i + 1
    } else {
      merged <- c(merged, right[j])
      j <- j + 1
      inversions <- inversions + length(left) - i + 1
    }
  }
  if (i <= length(left)) merged <- c(merged, left[i:length(left)])
  if (j <= length(right)) merged <- c(merged, right[j:length(right)])
  numbers[lo:hi] <- merged
  cat(sprintf("merge [%d..%d]: %s\n", lo - 1, hi - 1, paste(merged, collapse = " ")))
  list(numbers = numbers, inversions = inversions)
}

result <- merge_sort(c(47, 12, 85, 33, 6, 71, 29, 58, 90, 14), 1, 10)
cat(sprintf("sorted: %s\ninversions: %d\n", paste(result$numbers, collapse = " "), result$inversions))
