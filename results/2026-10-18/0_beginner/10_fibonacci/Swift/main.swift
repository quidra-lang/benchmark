import Foundation


var a = 1, b = 1, sum = 0
var terms = [Int]()
for _ in 0..<30 {
    terms.append(a); sum += a
    let next = a + b; a = b; b = next
}
print(terms.map(String.init).joined(separator: " "))
print("sum: \(sum)")
