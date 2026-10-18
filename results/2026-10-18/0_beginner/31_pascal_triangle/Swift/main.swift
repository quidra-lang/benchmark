import Foundation


var row = [1]
for _ in 0..<12 {
    print(row.map(String.init).joined(separator: " "))
    var next = [Int](repeating: 1, count: row.count + 1)
    if row.count > 1 { for k in 1..<row.count { next[k] = row[k - 1] + row[k] } }
    row = next
}
