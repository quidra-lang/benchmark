import Foundation

for (a,b,c) in [(1,-3,-10),(-2,5,4),(3,1,-2),(4,-12,9),(1,2,5),(-2,3,-4)] {
    let d = b * b - 4 * a * c, prefix = "\(a) \(b) \(c): "
    if d > 0 {
        let first = (Double(-b) + sqrt(Double(d))) / Double(2 * a)
        let second = (Double(-b) - sqrt(Double(d))) / Double(2 * a)
        print(String(format: prefix + "x1 = %.4f, x2 = %.4f", locale: Locale(identifier: "en_US_POSIX"), max(first, second), min(first, second)))
    } else if d == 0 { print(String(format: prefix + "x = %.4f", locale: Locale(identifier: "en_US_POSIX"), Double(-b) / Double(2 * a))) }
    else {
        let p = Double(-b) / Double(2 * a), q = sqrt(Double(-d)) / Double(2 * abs(a))
        print(String(format: prefix + "x = %.4f + %.4fi, %.4f - %.4fi", locale: Locale(identifier: "en_US_POSIX"), p, q, p, q))
    }
}
