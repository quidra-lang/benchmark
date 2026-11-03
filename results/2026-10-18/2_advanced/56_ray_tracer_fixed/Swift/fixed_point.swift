import Foundation

let scale = 4096
func floorDivide(_ a: Int, _ b: Int) -> Int { let q = a / b, remainder = a % b; return q - (remainder != 0 && ((a < 0) != (b < 0)) ? 1 : 0) }
func multiply(_ a: Int, _ b: Int) -> Int { floorDivide(a * b, scale) }
func integerSquareRoot(_ n: Int) -> Int { if n < 2 { return n }; var x = n, y = (n + 1) / 2; while y < x { x = y; y = (x + n / x) / 2 }; return x }
