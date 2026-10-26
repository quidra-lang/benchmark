using Printf

sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
for day = 3:length(sales)
    average = sum(sales[(day-2):day]) / 3
    @printf("day %d: %.2f\n", day, average)
end
