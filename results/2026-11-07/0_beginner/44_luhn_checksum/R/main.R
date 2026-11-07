numbers <- c(
  "688126340316", "0128469655154", "92181914514156", "177332430060552", "7982377590420309",
  "9884593615513906"
)
for (number in numbers) {
  digits <- rev(utf8ToInt(number) - 48L)
  even <- seq(2, length(digits), by = 2)
  digits[even] <- 2L * digits[even]
  digits[digits > 9] <- digits[digits > 9] - 9L
  total <- sum(digits)
  if (total %% 10 == 0) {
    cat(sprintf("%s: valid\n", number))
  } else {
    expected <- (-(total - digits[1])) %% 10
    cat(sprintf("%s: invalid (expected check digit %d)\n", number, expected))
  }
}
