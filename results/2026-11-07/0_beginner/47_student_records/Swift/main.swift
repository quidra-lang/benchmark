import Foundation

let posix = Locale(identifier: "en_US_POSIX")
let names = ["Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori"]
let scores = [[78, 85, 94], [88, 74, 82], [65, 90, 71], [80, 79, 85], [92, 88, 95], [70, 62, 78]]
let students = zip(names, scores).map { (name: $0.0, total: $0.1.reduce(0, +)) }
let order = students.sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
var rank = 0, previous = -1
for (position, student) in order.enumerated() {
    if student.total != previous { rank = position + 1 }
    previous = student.total
    let average = String(format: "%.2f", locale: posix, Double(student.total) / 3)
    print("\(rank). \(student.name) total=\(student.total) average=\(average)")
}
