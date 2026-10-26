func hanoi(_ n: Int, _ source: String, _ target: String, _ auxiliary: String) -> Int {
    if n == 0 { return 0 }
    let count = hanoi(n - 1, source, auxiliary, target)
    print("move disk \(n) from \(source) to \(target)")
    return count + 1 + hanoi(n - 1, auxiliary, target, source)
}

print("total moves: \(hanoi(4, "A", "C", "B"))")
