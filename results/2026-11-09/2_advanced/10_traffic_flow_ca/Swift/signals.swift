struct Phase {
    let duration: Int
    let token: String
    let greens: Set<String>
    init(_ text: String) {
        let fields = text.split(separator: ":").map(String.init)
        duration = Int(fields[0])!; token = fields[1]; greens = fields[1] == "-" ? [] : Set(fields[1].split(separator: ",").map(String.init))
    }
}
final class Junction {
    let node: String
    let offset: Int
    let phases: [Phase]
    let cycle: Int
    init(_ node: String, _ offset: Int, _ tokens: [String]) { let plan = tokens.map(Phase.init); self.node = node; self.offset = offset; phases = plan; cycle = plan.reduce(0) { $0 + $1.duration } }
    func green(_ segment: String, _ step: Int) -> Bool {
        if phases.isEmpty { return true }
        var time = (step - 1 + offset) % cycle
        for phase in phases { if time < phase.duration { return phase.greens.contains(segment) }; time -= phase.duration }
        return false
    }
    func planLines() -> [String] {
        if phases.isEmpty { return ["JUNCTION \(node) unsignalized"] }
        var lines = ["JUNCTION \(node) signal cycle \(cycle) offset \(offset)"]
        var start = 0
        for (index, phase) in phases.enumerated() { lines.append("  PHASE \(index + 1) \(start)-\(start + phase.duration - 1) \(phase.token)"); start += phase.duration }
        return lines
    }
}
