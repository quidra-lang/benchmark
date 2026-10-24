using Printf
matrix = [125 340 78 912 456; 603 27 819 150 384; 0 765 231 498 62; 947 113 586 39 720]
for row in eachrow(matrix)
    for value in vcat(row, sum(row))
        @printf("%6d", value)
    end
    println()
end
for value in vcat(vec(sum(matrix; dims=1)), sum(matrix))
    @printf("%6d", value)
end
println()
