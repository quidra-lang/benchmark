for (celsius in c(-40, -15, -3, 0, 22, 37, 100)) {
  fahrenheit <- celsius * 9 / 5 + 32
  cat(sprintf("%d C = %.1f F\n", celsius, fahrenheit))
}
