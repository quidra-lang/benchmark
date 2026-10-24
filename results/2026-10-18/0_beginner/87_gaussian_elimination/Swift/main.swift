import Foundation

let systems: [[[Double]]] = [[[2,-1,3,7],[4,1,-2,3],[-3,5,1,-4]],
    [[1,3,-2,4,6],[5,-2,1,3,-7],[-2,4,6,-1,9],[3,1,-4,2,5]]]
for (system,original) in systems.enumerated() {
    var a = original
    let n = a.count
    for k in 0..<n {
        let pivot = (k..<n).max { abs(a[$0][k]) < abs(a[$1][k]) }!
        a.swapAt(k,pivot)
        for i in (k + 1)..<n {
            let factor = a[i][k] / a[k][k]
            for j in k...n { a[i][j] = a[i][j] - factor * a[k][j] }
        }
    }
    var x = [Double](repeating: 0, count: n)
    for i in stride(from: n - 1, through: 0, by: -1) {
        var sum = a[i][n]
        for j in (i + 1)..<n { sum = sum - a[i][j] * x[j] }
        x[i] = sum / a[i][i]
    }
    print("system \(system + 1):")
    for i in 0..<n {
        print(String(format: "x%d = %.4f", locale: Locale(identifier: "en_US_POSIX"), i + 1, x[i]))
    }
}
