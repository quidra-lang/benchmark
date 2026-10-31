fun hanoi(n: Int, source: Char, target: Char, auxiliary: Char): Int {
    if (n == 0) return 0
    val count = hanoi(n - 1, source, auxiliary, target)
    println("move disk $n from $source to $target")
    return count + 1 + hanoi(n - 1, auxiliary, target, source)
}

fun main() {
    println("total moves: ${hanoi(4, 'A', 'C', 'B')}")
}
