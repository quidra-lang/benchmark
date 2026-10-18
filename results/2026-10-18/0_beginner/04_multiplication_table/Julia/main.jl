using Printf

for i in 1:9
    for j in 1:9
        @printf("%3d", i * j)
    end
    println()
end
