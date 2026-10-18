import Foundation


for sides in [[3,8,5],[6,6,6],[5,8,5],[13,5,12],[2,9,4],[7,4,7],[8,6,7],[4,9,6]] {
    let prefix = sides.map(String.init).joined(separator: " ") + ": ", sorted = sides.sorted()
    let a = sorted[0], b = sorted[1], c = sorted[2]
    if a + b <= c { print(prefix + "not a triangle"); continue }
    let side = a == c ? "equilateral" : a == b || b == c ? "isosceles" : "scalene"
    let difference = c * c - a * a - b * b
    let angle = difference < 0 ? "acute" : difference == 0 ? "right" : "obtuse"
    print(prefix + side + " " + angle)
}
