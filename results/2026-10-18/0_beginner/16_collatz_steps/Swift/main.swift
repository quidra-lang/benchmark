for start in [1, 6, 27, 97, 871] {
    var n = start, maximum = n, steps = 0
    while n != 1 {
        n = n % 2 == 0 ? n / 2 : 3 * n + 1
        steps += 1
        maximum = max(maximum, n)
    }
    print("\(start): steps=\(steps) max=\(maximum)")
}
