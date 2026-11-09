import Foundation

enum DecodeError: String, Error { case marker, code, index, sync }
struct BitWriter {
    var data: [Int] = []
    var buffer = 0
    var pending = 0
    var paddingBits = 0
    var stuffedBytes = 0
    mutating func write(_ value: Int, _ width: Int) { if width > 0 { for shift in stride(from: width - 1, through: 0, by: -1) { buffer = 2 * buffer + ((value >> shift) & 1); pending += 1; if pending == 8 { data.append(buffer); if buffer == 255 { data.append(0); stuffedBytes += 1 }; buffer = 0; pending = 0 } } } }
    mutating func pad() { if pending > 0 { let width = 8 - pending; paddingBits += width; write((1 << width) - 1, width) } }
    mutating func restart(_ number: Int) { pad(); data += [255, 208 + number % 8] }
}
final class BitReader {
    let data: [Int]
    var position: Int
    var buffer = 0
    var remaining = 0
    init(_ data: [Int], _ position: Int) { self.data = data; self.position = position }
    func bit() throws -> Int { if remaining == 0 { let value = data[position]; if value == 255 { if data[position + 1] != 0 { throw DecodeError.marker }; position += 2 } else { position += 1 }; buffer = value; remaining = 8 }; remaining -= 1; return (buffer >> remaining) & 1 }
    func read(_ width: Int) throws -> Int { var value = 0; for _ in 0..<width { value = 2 * value + (try bit()) }; return value }
    func discard() { buffer = 0; remaining = 0 }
}
func findResync(_ data: [Int], _ position: Int) -> Int { (position..<(data.count - 1)).first { data[$0] == 255 && ((208...215).contains(data[$0 + 1]) || data[$0 + 1] == 217) }! }
