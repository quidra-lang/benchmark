function hanoi(n, source, target, auxiliary)
    n == 0 && return 0
    moves = hanoi(n-1, source, auxiliary, target)
    println("move disk ", n, " from ", source, " to ", target)
    return moves + 1 + hanoi(n-1, auxiliary, target, source)
end
println("total moves: ", hanoi(4, "A", "C", "B"))
