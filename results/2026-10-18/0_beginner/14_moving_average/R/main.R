sales <- c(120, 135, 98, 143, 160, 152, 171, 149, 188, 176)
for (day in 3:length(sales)) {
    average <- sum(sales[(day-2):day]) / 3
    rounded <- floor(average * 100 + 0.5) / 100
    cat(sprintf("day %d: %.2f\n", day, rounded))
}
