import Foundation

enum Destination { case process(Int), sender }
enum Action { case local(String), send(Destination, String), transfer(Destination, Int), broadcast(String), snapshot(String) }
struct ScheduledAction { let start: Int; let period: Int?; let action: Action }
struct Reaction { let tag: String; let action: Action }
struct Script { let initial: Int; let scheduled: [ScheduledAction]; let reactions: [Reaction] }
func parseAction(_ words: [String], _ indices: [String: Int]) -> Action {
    func destination(_ name: String) -> Destination { name == "SENDER" ? .sender : .process(indices[name]!) }
    switch words[0] {
    case "LOCAL": return .local(words[1])
    case "SEND": return .send(destination(words[1]), words[2])
    case "TRANSFER": return .transfer(destination(words[1]), Int(words[2])!)
    case "BROADCAST": return .broadcast(words[1])
    default: return .snapshot(words[1])
    }
}
func readScripts(_ names: [String]) throws -> [Script] {
    let indices = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) }), lines = try String(contentsOfFile: "input/programs.txt", encoding: .ascii).split(separator: "\n")
    var scripts: [Script] = [], initial = 0, scheduled: [ScheduledAction] = [], reactions: [Reaction] = []
    for line in lines {
        let words = line.components(separatedBy: " ")
        switch words[0] {
        case "PROCESS": initial = Int(words[3])!; scheduled = []; reactions = []
        case "END": scripts.append(Script(initial: initial, scheduled: scheduled, reactions: reactions))
        case "AT":
            let repeated = words[2] == "EVERY", action = parseAction(Array(words.dropFirst(repeated ? 4 : 2)), indices)
            scheduled.append(ScheduledAction(start: Int(words[1])!, period: repeated ? Int(words[3])! : nil, action: action))
        default: reactions.append(Reaction(tag: words[1], action: parseAction(Array(words.dropFirst(2)), indices)))
        }
    }
    return scripts
}
final class ProcessState {
    let initial: Int
    let script: Script
    var balance: Int
    var lamport = 0
    var vector: [Int]
    var broadcast: [Int]
    var events: [Int] = []
    var nextSequence: [Int]
    var reorder: [[Int: Packet]]
    var holdback: [Int] = []
    var delivered: [Int] = []
    var maximumHeld = 0
    var incoming = 0
    var outgoing = 0
    var refused = 0
    var minimumBalance: Int
    var types = Array(repeating: 0, count: 5)
    init(_ script: Script, _ count: Int) { self.script = script; initial = script.initial; balance = script.initial; minimumBalance = script.initial; vector = Array(repeating: 0, count: count); broadcast = Array(repeating: 0, count: count); nextSequence = Array(repeating: 1, count: count); reorder = Array(repeating: [:], count: count) }
    var heldCount: Int { reorder.reduce(0) { $0 + $1.count } + holdback.count }
    func balanceAtCut(_ count: Int, _ events: [Event]) -> Int { count == 0 ? initial : events[self.events[count - 1]].balance }
}
struct TimedAction { let time: Int; let process: Int; let action: Action }
func scheduledActions(_ scripts: [Script], _ limit: Int) -> [TimedAction] {
    var result: [TimedAction] = []
    for (p, script) in scripts.enumerated() {
        for line in script.scheduled where line.start <= limit {
            if let period = line.period { for time in stride(from: line.start, through: limit, by: period) { result.append(TimedAction(time: time, process: p, action: line.action)) } }
            else { result.append(TimedAction(time: line.start, process: p, action: line.action)) }
        }
    }
    return result
}
