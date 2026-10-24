using Printf
a = [3 -2 5 1; -4 7 0 6; 2 9 -8 -3]
b = [1 4; -5 2; 6 -1; 0 7]
product = a * b
for row in eachrow(product)
    for value in row
        @printf("%5d", value)
    end
    println()
end
