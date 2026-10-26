import Foundation

let posix = Locale(identifier: "en_US_POSIX")
let matrix = [
    [125, 340, 78, 912, 456],
    [603, 27, 819, 150, 384],
    [0, 765, 231, 498, 62],
    [947, 113, 586, 39, 720],
]
var columns = [Int](repeating: 0, count: 5)
for row in matrix {
    for j in row.indices { columns[j] += row[j] }
    let sum = row.reduce(0, +)
    print((row + [sum]).map { String(format: "%6d", locale: posix, $0) }.joined())
}
print((columns + [columns.reduce(0, +)]).map { String(format: "%6d", locale: posix, $0) }.joined())
