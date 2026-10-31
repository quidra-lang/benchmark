import Foundation

let posix = Locale(identifier: "en_US_POSIX")
let names = ["Tanaka", "Suzuki", "Yamada", "Ito", "Kato", "Mori"]
let scores = [[78, 85, 94], [88, 74, 82], [65, 90, 71], [80, 79, 85], [92, 88, 95], [70, 62, 78]]
let totals = scores.map { $0.reduce(0, +) }
let order = names.indices.sorted { totals[$0] == totals[$1] ? names[$0] < names[$1] : totals[$0] > totals[$1] }
var rank = 0, previous = -1
for (position, i) in order.enumerated() {
    if totals[i] != previous { rank = position + 1 }
    previous = totals[i]
    let average = String(format: "%.2f", locale: posix, Double(totals[i]) / 3)
    print("\(rank). \(names[i]) total=\(totals[i]) average=\(average)")
}
