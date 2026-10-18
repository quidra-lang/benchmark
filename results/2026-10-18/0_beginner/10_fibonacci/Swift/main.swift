var a = 1, b = 1
var terms = [Int]()
for _ in 0..<30 {
    terms.append(a)
    (a, b) = (b, a + b)
}
print(terms.map(String.init).joined(separator: " "))
print("sum: \(terms.reduce(0, +))")
