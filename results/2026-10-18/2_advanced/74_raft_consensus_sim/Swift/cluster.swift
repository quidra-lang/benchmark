import Foundation

struct Settings {
    let nodes: Int, electionMin: Int, electionMax: Int, heartbeat: Int, batch: Int, quorum: Int
    let seed: Int64
    let end: Int, retry: Int, attempts: Int, sample: Int
    init(_ values: [[Int]]) {
        nodes = values[0][0]; electionMin = values[1][0]; electionMax = values[1][1]; heartbeat = values[2][0]; batch = values[3][0]; quorum = values[4][0]
        seed = Int64(values[5][0]); end = values[6][0]; retry = values[7][0]; attempts = values[8][0]; sample = values[9][0]
    }
}
enum ControlEvent { case crash(Int), restart(Int), partition([[Int]]), heal, transfer(Int, Int) }
struct Control { let time: Int; let event: ControlEvent }
struct AcceptedEntry { let index: Int; let term: Int }
enum RequestStatus: String, CaseIterable { case committed = "COMMITTED", uncommitted = "UNCOMMITTED", lost = "LOST", failed = "FAILED", waiting = "WAITING" }
final class Request {
    let number: Int, time: Int, initialDestination: Int
    let command: Command
    var scheduled: Int?
    var destination: Int
    var attempts = 0, redirects = 0
    var accepted: AcceptedEntry?
    var abandoned = false
    var status = RequestStatus.waiting
    var latency: Int?
    var result: String?
    init(_ number: Int, _ time: Int, _ destination: Int, _ command: Command) { self.number = number; self.time = time; initialDestination = destination; self.command = command; scheduled = time; self.destination = destination }
}
func inputLines(_ name: String) throws -> [[String]] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map { $0.split(separator: " ").map(String.init) } }
func readSettings() throws -> Settings { Settings(try inputLines("cluster.txt").map { $0.dropFirst().map { Int($0)! } }) }
func readScript() throws -> (controls: [Control], requests: [Request]) {
    var controls: [Control] = [], requests: [Request] = []
    for fields in try inputLines("script.txt") {
        let time = Int(fields[0])!, kind = fields[1]
        if kind == "REQUEST" {
            let command: Command
            switch fields[3] { case "SET": command = .set(fields[4], Int(fields[5])!); case "ADD": command = .add(fields[4], Int(fields[5])!); case "DEL": command = .delete(fields[4]); default: command = .get(fields[4]) }
            requests.append(Request(requests.count + 1, time, Int(fields[2])!, command))
        } else {
            let event: ControlEvent
            switch kind {
            case "CRASH": event = .crash(Int(fields[2])!)
            case "RESTART": event = .restart(Int(fields[2])!)
            case "PARTITION": event = .partition(fields.dropFirst(2).map { $0.split(separator: ",").map { Int($0)! } })
            case "HEAL": event = .heal
            default: event = .transfer(Int(fields[2])!, Int(fields[3])!)
            }
            controls.append(Control(time: time, event: event))
        }
    }
    return (controls, requests)
}
