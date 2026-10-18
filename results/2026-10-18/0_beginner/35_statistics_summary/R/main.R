numbers <- c(72,85,64,90,85,58,77,85,69,93,71)
average <- sum(numbers) / length(numbers)
squares <- 0
for (value in numbers) {
    difference <- value - average
    squares <- squares + difference * difference
}
deviation <- sqrt(squares / length(numbers))
ordered <- sort(numbers)
frequencies <- table(numbers)
cat(sprintf("mean: %.3f\nmedian: %d\nmode: %d\nrange: %d\nstdev: %.3f\n",
    average, ordered[6], as.integer(names(frequencies)[which.max(frequencies)]),
    ordered[length(ordered)]-ordered[1], deviation))
