let values = [7, 98000, 4096, 50301, 2718281, 123456789]
for value in values {
    var remaining = value
    var digits = 0
    var sum = 0
    var reversed = 0
    while remaining > 0 {
        let digit = remaining % 10
        digits += 1
        sum += digit
        reversed = reversed * 10 + digit
        remaining /= 10
    }
    print("\(value): digits=\(digits) sum=\(sum) reversed=\(reversed)")
}
