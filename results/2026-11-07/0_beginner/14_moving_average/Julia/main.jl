using Printf

sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
window = 3
for day = window:length(sales)
    average = sum(sales[(day-window+1):day]) / window
    @printf("day %d: %.2f\n", day, average)
end
