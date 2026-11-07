import Foundation

struct BTB {
    var entries: [(pc: Int, target: Int)?]
    init(_ count: Int) { entries = Array(repeating: nil, count: count) }
    func lookup(_ pc: Int) -> Int? { guard let entry = entries[(pc / 4) % entries.count], entry.pc == pc else { return nil }; return entry.target }
    mutating func insert(_ pc: Int, _ target: Int) { entries[(pc / 4) % entries.count] = (pc, target) }
}
struct ReturnStack {
    let depth: Int
    var values: [Int] = []
    mutating func push(_ address: Int) { if depth == 0 { return }; if values.count == depth { values.removeFirst() }; values.append(address) }
    mutating func pop() -> Int? { values.popLast() }
}
func updatedCounter(_ value: Int, _ taken: Bool) -> Int { taken ? min(3, value + 1) : max(0, value - 1) }
struct DirectionPredictor {
    let definition: PredictorDefinition
    var history = 0
    var table: [Int] = []
    var local: [Int] = []
    var global: [Int] = []
    var chooser: [Int] = []
    init(_ definition: PredictorDefinition) {
        self.definition = definition
        let params = definition.parameters
        if ["ONEBIT", "TWOBIT", "GSHARE"].contains(definition.scheme) { table = Array(repeating: definition.scheme == "ONEBIT" ? 0 : 1, count: params[0]) }
        else if definition.scheme == "TOURNAMENT" { local = Array(repeating: 1, count: params[0]); global = Array(repeating: 1, count: params[1]); chooser = Array(repeating: 1, count: params[3]) }
    }
    func predict(_ pc: Int, _ target: Int) -> Bool {
        let index = pc / 4
        switch definition.scheme {
        case "STATIC_NT", "PERFECT": return false
        case "BTFN": return target < pc
        case "ONEBIT": return table[index % table.count] == 1
        case "TWOBIT": return table[index % table.count] >= 2
        case "GSHARE": return table[(index ^ history) % table.count] >= 2
        default: return chooser[index % chooser.count] >= 2 ? global[(index ^ history) % global.count] >= 2 : local[index % local.count] >= 2
        }
    }
    mutating func update(_ pc: Int, _ taken: Bool) {
        let scheme = definition.scheme, params = definition.parameters, index = pc / 4, bit = taken ? 1 : 0
        if ["STATIC_NT", "BTFN", "PERFECT"].contains(scheme) { return }
        if scheme == "TOURNAMENT" {
            let l = index % local.count, g = (index ^ history) % global.count, c = index % chooser.count, localPrediction = local[l] >= 2, globalPrediction = global[g] >= 2
            if localPrediction != globalPrediction { chooser[c] = updatedCounter(chooser[c], globalPrediction == taken) }
            local[l] = updatedCounter(local[l], taken); global[g] = updatedCounter(global[g], taken); history = (2 * history + bit) % (1 << params[2])
        } else {
            let slot = (scheme == "GSHARE" ? index ^ history : index) % table.count
            table[slot] = scheme == "ONEBIT" ? bit : updatedCounter(table[slot], taken)
            if scheme == "GSHARE" { history = (2 * history + bit) % (1 << params[1]) }
        }
    }
    var storageBits: Int {
        let params = definition.parameters
        switch definition.scheme {
        case "STATIC_NT", "BTFN", "PERFECT": return 0
        case "ONEBIT": return params[0]
        case "TWOBIT": return 2 * params[0]
        case "GSHARE": return 2 * params[0] + params[1]
        default: return 2 * (params[0] + params[1] + params[3]) + params[2]
        }
    }
}
