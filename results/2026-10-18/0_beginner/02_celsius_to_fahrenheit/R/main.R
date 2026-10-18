for (celsius in c(-40, -15, -3, 0, 22, 37, 100)) {
    fahrenheit <- celsius * 9 / 5 + 32
    rounded <- sign(fahrenheit) * floor(abs(fahrenheit) * 10 + 0.5) / 10
    cat(sprintf("%d C = %.1f F\n", celsius, rounded))
}
