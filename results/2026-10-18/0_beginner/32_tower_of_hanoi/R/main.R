hanoi <- function(n, source, target, auxiliary) {
    if (n == 0) return(0)
    moves <- hanoi(n-1, source, auxiliary, target)
    cat(sprintf("move disk %d from %s to %s\n", n, source, target))
    moves + 1 + hanoi(n-1, auxiliary, target, source)
}
moves <- hanoi(4, "A", "C", "B")
cat(sprintf("total moves: %d\n", moves))
