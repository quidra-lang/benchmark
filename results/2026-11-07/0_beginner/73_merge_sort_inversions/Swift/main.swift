func mergeSort(_ values: inout [Int], _ l: Int, _ r: Int, _ inversions: inout Int) {
    if l == r { return }
    let m = (l + r) / 2
    mergeSort(&values, l, m, &inversions)
    mergeSort(&values, m + 1, r, &inversions)
    var merged = [Int](), i = l, j = m + 1
    while i <= m && j <= r {
        if values[i] < values[j] {
            merged.append(values[i])
            i += 1
        } else {
            merged.append(values[j])
            j += 1
            inversions += m - i + 1
        }
    }
    while i <= m {
        merged.append(values[i])
        i += 1
    }
    while j <= r {
        merged.append(values[j])
        j += 1
    }
    values.replaceSubrange(l...r, with: merged)
    print("merge [\(l)..\(r)]: \(merged.map(String.init).joined(separator: " "))")
}

var values = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14]
var inversions = 0
mergeSort(&values, 0, values.count - 1, &inversions)
print("sorted: \(values.map(String.init).joined(separator: " "))")
print("inversions: \(inversions)")
