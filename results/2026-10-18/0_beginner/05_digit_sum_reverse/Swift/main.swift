let values = [7, 98000, 4096, 50301, 2718281, 123456789]
for value in values {
    let digits = String(value)
    let sum = digits.reduce(0) { $0 + $1.wholeNumberValue! }
    let reversed = Int(String(digits.reversed()))!
    print("\(value): digits=\(digits.count) sum=\(sum) reversed=\(reversed)")
}
