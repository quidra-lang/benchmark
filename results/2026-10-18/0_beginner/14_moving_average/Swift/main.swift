import Foundation

let sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176]
for i in 2..<sales.count {
    let average = Double(sales[i - 2] + sales[i - 1] + sales[i]) / 3
    print(String(format: "day %d: %.2f", locale: Locale(identifier: "en_US_POSIX"), i + 1, average))
}
