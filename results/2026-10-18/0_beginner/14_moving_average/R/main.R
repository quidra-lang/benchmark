sales <- c(120, 135, 98, 143, 160, 152, 171, 149, 188, 176)
for (day in 3:length(sales)) {
    average <- mean(sales[(day-2):day])
    cat(sprintf("day %d: %.2f\n", day, average))
}
