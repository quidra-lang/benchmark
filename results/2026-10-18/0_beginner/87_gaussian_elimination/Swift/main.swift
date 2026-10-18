import Foundation

func fixed(_ value: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((abs(value) * Double(scale)).rounded(.toNearestOrAwayFromZero))
    let fraction = String(scaled % scale)
    return "\(value < 0 ? "-" : "")\(scaled / scale).\(String(repeating: "0", count: places - fraction.count))\(fraction)"
}
let systems: [[[Double]]] = [[[2,-1,3,7],[4,1,-2,3],[-3,5,1,-4]],
    [[1,3,-2,4,6],[5,-2,1,3,-7],[-2,4,6,-1,9],[3,1,-4,2,5]]]
for (system,original) in systems.enumerated() {
    var a = original
    let n = a.count
    for k in 0..<n {
        var pivot = k
        for i in (k + 1)..<n where abs(a[i][k]) > abs(a[pivot][k]) { pivot = i }
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
    for i in 0..<n { print("x\(i + 1) = \(fixed(x[i],4))") }
}
