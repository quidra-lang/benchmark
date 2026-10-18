import Foundation


let matrix = [[125,340,78,912,456],[603,27,819,150,384],[0,765,231,498,62],[947,113,586,39,720]]
var columns = [Int](repeating: 0, count: 5), total = 0
for row in matrix {
    for j in row.indices { columns[j] += row[j] }
    let sum = row.reduce(0,+); total += sum
    print((row + [sum]).map { String(repeating: " ", count: 6 - String($0).count) + String($0) }.joined())
}
print((columns + [total]).map { String(repeating: " ", count: 6 - String($0).count) + String($0) }.joined())
