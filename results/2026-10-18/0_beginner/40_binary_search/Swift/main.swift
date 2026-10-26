let values = [3, 8, 11, 15, 19, 24, 27, 31, 36, 42, 47, 53, 58, 64, 70, 77]
for target in [42, 3, 77, 31, 50, 1] {
    var lo = 0, hi = 15, found = -1, probes = [Int]()
    while lo <= hi {
        let mid = (lo + hi) / 2
        probes.append(mid)
        if values[mid] == target {
            found = mid
            break
        }
        if values[mid] < target { lo = mid + 1 } else { hi = mid - 1 }
    }
    let result = found >= 0 ? "index \(found)" : "not found"
    print("\(target): probes \(probes.map(String.init).joined(separator: " ")) -> \(result)")
}
