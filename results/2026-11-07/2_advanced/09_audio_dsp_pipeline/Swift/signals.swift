import Foundation

final class AudioSignal {
    let name: String
    let rate: Int
    let samples: [Int]
    let origin: String
    let ingredients: [AudioSignal]
    init(_ name: String, _ rate: Int, _ samples: [Int], _ origin: String = "input", _ ingredients: [AudioSignal] = []) { self.name = name; self.rate = rate; self.samples = samples; self.origin = origin; self.ingredients = ingredients }
}
struct ClipResult { let samples: [Int]; let clipped: Int }
final class ClipCounter {
    var count = 0
    func saturate(_ value: Int) -> Int { let limited = max(-32768, min(32767, value)); if limited != value { count += 1 }; return limited }
}
func floorDivide(_ numerator: Int, _ denominator: Int) -> Int {
    let quotient = numerator / denominator
    let remainder = numerator % denominator
    return remainder != 0 && (remainder < 0) != (denominator < 0) ? quotient - 1 : quotient
}
func rdiv(_ numerator: Int, _ denominator: Int) -> Int { floorDivide(2 * numerator + denominator, 2 * denominator) }
func peak(_ samples: [Int]) -> Int { samples.map { abs($0) }.max()! }
func readSignals() throws -> [AudioSignal] {
    let lines = try String(contentsOfFile: "input/signals.txt", encoding: .utf8).split(separator: "\n").map(String.init)
    var result: [AudioSignal] = []
    var index = 0
    while index < lines.count {
        let header = lines[index].split(separator: " ").map(String.init)
        index += 1
        let count = Int(header[3])!
        var samples: [Int] = []
        while samples.count < count { samples += lines[index].split(separator: " ").map { Int($0)! }; index += 1 }
        result.append(AudioSignal(header[1], Int(header[2])!, samples))
    }
    return result
}
func formatSignal(_ signal: AudioSignal) -> [String] { ["SIGNAL \(signal.name) \(signal.rate) \(signal.samples.count)"] + stride(from: 0, to: signal.samples.count, by: 16).map { signal.samples[$0..<min($0 + 16, signal.samples.count)].map(String.init).joined(separator: " ") } }
func impulse(_ count: Int, _ position: Int, _ amplitude: Int) -> [Int] { (0..<count).map { $0 == position ? amplitude : 0 } }
func step(_ count: Int, _ position: Int, _ amplitude: Int) -> [Int] { (0..<count).map { $0 >= position ? amplitude : 0 } }
func noise(_ count: Int, _ seed: Int) -> [Int] { var state = seed; return (0..<count).map { _ in state = 48271 * state % 2147483647; return state % 65536 - 32768 } }
