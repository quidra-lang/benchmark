n = 5
for i in vcat(1:n, n-1:-1:1)
    println(repeat(" ", n-i), repeat("*", 2*i-1))
end
