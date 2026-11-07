import Foundation

let posix = Locale(identifier: "en_US_POSIX")
let points = [
    (12, -7), (-33, 25), (41, 18), (-8, -44), (27, 39), (-46, -12), (5, 14), (36, -29), (-19, 47),
    (-2, 3),
]
var minimum = Int.max, maximum = -1, minI = 0, minJ = 0, maxI = 0, maxJ = 0
for i in points.indices {
    for j in (i + 1)..<points.count {
        let dx = points[i].0 - points[j].0, dy = points[i].1 - points[j].1
        let distance = dx * dx + dy * dy
        if distance < minimum {
            minimum = distance
            minI = i
            minJ = j
        }
        if distance > maximum {
            maximum = distance
            maxI = i
            maxJ = j
        }
    }
}
print(String(format: "closest: P%d P%d %.4f", locale: posix, minI, minJ, sqrt(Double(minimum))))
print(String(format: "farthest: P%d P%d %.4f", locale: posix, maxI, maxJ, sqrt(Double(maximum))))
