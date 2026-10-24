import Foundation

let radii = [3, 7, 12, 25, 41]
let pi = 3.141592653589793
for radius in radii {
    let r = Double(radius)
    let area = pi * r * r
    let circumference = 2 * pi * r
    print(String(format: "r=%d area=%.3f circumference=%.3f", locale: Locale(identifier: "en_US_POSIX"), radius, area, circumference))
}
