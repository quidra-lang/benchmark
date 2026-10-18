for (n in 1:30) {
    if (n %% 15 == 0) {
        cat("FizzBuzz\n")
    } else if (n %% 3 == 0) {
        cat("Fizz\n")
    } else if (n %% 5 == 0) {
        cat("Buzz\n")
    } else {
        cat(sprintf("%d\n", n))
    }
}
