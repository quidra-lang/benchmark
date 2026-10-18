import Foundation


let denominations = [10000,5000,1000,500,100,50,10,5,1]
for amount in [3780,15420,99999,506,48263] {
    var remaining = amount, total = 0, parts = [String]()
    for face in denominations {
        let count = remaining / face; remaining %= face; total += count
        if count > 0 { parts.append("\(face)x\(count)") }
    }
    print("\(amount) yen: \(parts.joined(separator: " ")) (\(total) pieces)")
}
