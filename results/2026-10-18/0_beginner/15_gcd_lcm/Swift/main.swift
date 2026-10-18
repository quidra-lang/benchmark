import Foundation

func gcd(_ a: Int, _ b: Int) -> Int { var x = a, y = b; while y != 0 { let r = x % y; x = y; y = r }; return x }
for (a, b) in [(48,180), (1071,462), (7,91), (13,97), (36288,98280)] {
    let g = gcd(a, b)
    print("gcd(\(a), \(b)) = \(g), lcm(\(a), \(b)) = \(a / g * b)")
}
