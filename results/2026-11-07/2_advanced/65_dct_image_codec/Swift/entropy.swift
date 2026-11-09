import Foundation

struct TableKey: Hashable { let kind: Int; let id: Int }
let tableKeys = [TableKey(kind: 0, id: 0), TableKey(kind: 1, id: 0), TableKey(kind: 0, id: 1), TableKey(kind: 1, id: 1)]
let tableNames = ["dc_luma", "ac_luma", "dc_chroma", "ac_chroma"]
struct HuffmanCode: Hashable { let length: Int; let value: Int }
struct HuffmanTable {
    let counts: [Int]
    let symbols: [Int]
    let codes: [Int: HuffmanCode]
    let decoding: [HuffmanCode: Int]
    init(_ counts: [Int], _ symbols: [Int]) { var code = 0, offset = 0, codes: [Int: HuffmanCode] = [:], decoding: [HuffmanCode: Int] = [:]; for length in 1...16 { for symbol in symbols[offset..<(offset + counts[length - 1])] { let entry = HuffmanCode(length: length, value: code); codes[symbol] = entry; decoding[entry] = symbol; code += 1 }; offset += counts[length - 1]; code *= 2 }; self.counts = counts; self.symbols = symbols; self.codes = codes; self.decoding = decoding }
}
func category(_ value: Int) -> Int { var magnitude = abs(value), count = 0; while magnitude != 0 { magnitude >>= 1; count += 1 }; return count }
func extraBits(_ value: Int) -> (value: Int, width: Int) { let width = category(value); return (value >= 0 ? value : value + (1 << width) - 1, width) }
func amplitude(_ bits: Int, _ width: Int) -> Int { if width == 0 { return 0 }; return bits >= (1 << (width - 1)) ? bits : bits - (1 << width) + 1 }
func optimizedTable(_ source: [Int]) -> HuffmanTable {
    var frequencies = source + [1], sizes = Array(repeating: 0, count: 257), others = Array(repeating: -1, count: 257)
    while true { let available = frequencies.indices.filter { frequencies[$0] > 0 }.sorted { frequencies[$0] == frequencies[$1] ? $0 > $1 : frequencies[$0] < frequencies[$1] }; if available.count < 2 { break }; var first = available[0], second = available[1]; frequencies[first] += frequencies[second]; frequencies[second] = 0; sizes[first] += 1; while others[first] != -1 { first = others[first]; sizes[first] += 1 }; others[first] = second; sizes[second] += 1; while others[second] != -1 { second = others[second]; sizes[second] += 1 } }
    var counts = Array(repeating: 0, count: 257)
    for size in sizes where size > 0 { counts[size] += 1 }
    if sizes.max()! >= 17 { for length in stride(from: sizes.max()!, through: 17, by: -1) { while counts[length] > 0 { var shorter = length - 2; while counts[shorter] == 0 { shorter -= 1 }; counts[length] -= 2; counts[length - 1] += 1; counts[shorter + 1] += 2; counts[shorter] -= 1 } } }
    let longest = (1...16).filter { counts[$0] > 0 }.last!
    counts[longest] -= 1
    let symbols = (0..<256).filter { sizes[$0] > 0 }.sorted { sizes[$0] == sizes[$1] ? $0 < $1 : sizes[$0] < sizes[$1] }
    return HuffmanTable(Array(counts[1...16]), symbols)
}
