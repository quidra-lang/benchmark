import Foundation


for n in [84,9973,15625,1001,123456,48000,999958,999999] {
    var remaining = n, d = 2, factors = [String]()
    while d * d <= remaining {
        var exponent = 0
        while remaining % d == 0 { remaining /= d; exponent += 1 }
        if exponent > 0 { factors.append("\(d)" + (exponent > 1 ? "^\(exponent)" : "")) }
        d += 1
    }
    if remaining > 1 { factors.append(String(remaining)) }
    print("\(n) = \(factors.joined(separator: " * "))")
}
