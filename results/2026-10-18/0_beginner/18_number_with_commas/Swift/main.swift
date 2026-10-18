import Foundation


for n in [0,7,999,1000,-456789,3141592,9876543210] {
    let digits = Array(String(abs(n)))
    var formatted = n < 0 ? "-" : ""
    for i in digits.indices {
        if i > 0 && (digits.count - i) % 3 == 0 { formatted += "," }
        formatted.append(digits[i])
    }
    print(formatted)
}
