import Foundation


let grades = ["A", "B", "C", "D", "F"]
var counts = [Int](repeating: 0, count: 5)
for score in [78, 90, 100, 59, 80, 85, 89, 70, 45, 93] {
    let index = score >= 90 ? 0 : score >= 80 ? 1 : score >= 70 ? 2 : score >= 60 ? 3 : 4
    counts[index] += 1
    print("\(score): \(grades[index])")
}
for i in grades.indices { print("\(grades[i]): \(counts[i])") }
