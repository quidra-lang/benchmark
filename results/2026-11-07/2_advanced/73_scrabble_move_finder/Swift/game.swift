import Foundation

let tileOrder: [UInt8] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ?".utf8)
final class Minstd { private var state: Int64; init(_ seed: Int64) { state = seed }; func next() -> Int64 { state = state * 48271 % 2147483647; return state } }
func shuffle(_ bag: inout [UInt8], _ random: Minstd) { if bag.count > 1 { for position in stride(from: bag.count - 1, through: 1, by: -1) { let other = Int(random.next() % Int64(position + 1)); bag.swapAt(position, other) } } }
func makeBag(_ counts: [Int], _ random: Minstd) -> [UInt8] { var bag = tileOrder.indices.flatMap { Array(repeating: tileOrder[$0], count: counts[$0]) }; shuffle(&bag, random); return bag }
func draw(_ bag: inout [UInt8], _ count: Int) -> [UInt8] { var drawn: [UInt8] = []; for _ in 0..<min(count, bag.count) { drawn.append(bag.removeLast()) }; return drawn }
func exchange(_ bag: inout [UInt8], _ returned: [UInt8], _ random: Minstd) -> [UInt8] { let drawn = draw(&bag, returned.count); bag += returned.sorted(); shuffle(&bag, random); return drawn }
func points(_ collection: [UInt8], _ values: [Int]) -> Int { collection.map { values[$0 == 63 ? 26 : Int($0 - 65)] }.reduce(0, +) }
