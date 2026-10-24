var values = [27,64,13,88,41,5,72,36], swaps = 0
for p in 1...7 {
    var changed = false
    for j in 0...(7 - p) where values[j] > values[j + 1] {
        values.swapAt(j, j + 1)
        changed = true
        swaps += 1
    }
    print("pass \(p): \(values.map(String.init).joined(separator: " "))")
    if !changed { break }
}
print("swaps: \(swaps)")
