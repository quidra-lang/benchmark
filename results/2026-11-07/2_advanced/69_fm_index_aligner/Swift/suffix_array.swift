import Foundation

let symbols: [UInt8] = Array("$#ACGT".utf8)
let bases: [UInt8] = Array("ACGT".utf8)
func symbolNumber(_ symbol: UInt8) -> Int { switch symbol { case 36: return 0; case 35: return 1; case 65: return 2; case 67: return 3; case 71: return 4; default: return 5 } }
func countingSort(_ positions: [Int], _ keys: [Int], _ keyCount: Int) -> [Int] { var counts = Array(repeating: 0, count: keyCount), offset = 0, result = Array(repeating: 0, count: positions.count); for position in positions { counts[keys[position]] += 1 }; for key in counts.indices { let count = counts[key]; counts[key] = offset; offset += count }; for position in positions { let key = keys[position]; result[counts[key]] = position; counts[key] += 1 }; return result }
struct SuffixArray { let order: [Int]; let classes: [Int] }
func buildSuffixArray(_ sequence: [UInt8]) -> SuffixArray {
    let size = sequence.count, positions = Array(0..<size), codes = sequence.map(symbolNumber)
    var order = countingSort(positions, codes, symbols.count), ranks = Array(repeating: 0, count: size), count = 0, previous = -1
    for position in order { if codes[position] != previous { count += 1; previous = codes[position] }; ranks[position] = count - 1 }
    var classes = [count], width = 1
    while count < size { let second = positions.map { $0 + width < size ? ranks[$0 + width] + 1 : 0 }; order = countingSort(countingSort(positions, second, count + 1), ranks, count); var updated = Array(repeating: 0, count: size), priorFirst = -1, priorSecond = -1; count = 0; for position in order { if ranks[position] != priorFirst || second[position] != priorSecond { count += 1; priorFirst = ranks[position]; priorSecond = second[position] }; updated[position] = count - 1 }; ranks = updated; classes.append(count); width *= 2 }
    return SuffixArray(order: order, classes: classes)
}
func directSort(_ sequence: [UInt8]) -> [Int] { sequence.indices.sorted { sequence[$0...].lexicographicallyPrecedes(sequence[$1...]) } }
struct AdjacentCheck { let ordered: Int; let sum: Int; let maximum: Int; let row: Int }
func adjacentCheck(_ sequence: [UInt8], _ suffixes: [Int]) -> AdjacentCheck { var ordered = 0, sum = 0, maximum = -1, longest = 1; for row in 1..<suffixes.count { let left = suffixes[row - 1], right = suffixes[row]; var common = 0; while sequence[left + common] == sequence[right + common] { common += 1 }; if symbolNumber(sequence[left + common]) < symbolNumber(sequence[right + common]) { ordered += 1 }; sum += common; if common > maximum { maximum = common; longest = row } }; return AdjacentCheck(ordered: ordered, sum: sum, maximum: maximum, row: longest) }
