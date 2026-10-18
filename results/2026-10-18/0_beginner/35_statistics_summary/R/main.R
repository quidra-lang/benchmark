numbers <- c(72,85,64,90,85,58,77,85,69,93,71)
average <- sum(numbers) / length(numbers)
squares <- 0
for (value in numbers) {
    difference <- value - average
    squares <- squares + difference * difference
}
deviation <- sqrt(squares / length(numbers))
ordered <- sort(numbers)
candidates <- unique(ordered)
frequencies <- vapply(candidates, function(value) sum(numbers == value), numeric(1))
cat(sprintf("mean: %.3f\nmedian: %d\nmode: %d\nrange: %d\nstdev: %.3f\n",
    floor(average*1000+0.5)/1000, ordered[6], candidates[which.max(frequencies)],
    ordered[length(ordered)]-ordered[1], floor(deviation*1000+0.5)/1000))
