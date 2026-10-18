import Foundation


let a = [[3,-2,5,1],[-4,7,0,6],[2,9,-8,-3]], b = [[1,4],[-5,2],[6,-1],[0,7]]
for i in 0..<3 {
    var row = [Int]()
    for j in 0..<2 {
        var sum = 0
        for k in 0..<4 { sum += a[i][k] * b[k][j] }
        row.append(sum)
    }
    print(row.map { String(repeating: " ", count: 5 - String($0).count) + String($0) }.joined())
}
