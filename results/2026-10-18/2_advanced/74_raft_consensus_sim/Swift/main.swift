import Foundation

func nodeSet<S: Sequence>(_ values: S) -> String where S.Element == Int { let nodes = Set(values).sorted(); return nodes.isEmpty ? "-" : nodes.map { "n\($0)" }.joined(separator: ",") }
struct ElectionRecord { let time: Int; let node: Int; let term: Int; let trigger: String; var votes: Set<Int>; var won: Int? = nil }
final class LeaderRecord {
    let node: Int, elected: Int
    let votes: Set<Int>
    var appended = 1
    var ended: Int?, reason: String?, commit: Int?
    init(_ node: Int, _ elected: Int, _ votes: Set<Int>) { self.node = node; self.elected = elected; self.votes = votes }
}
final class Simulator {
    let settings: Settings
    let nodes: [RaftNode]
    let network: Network
    let random: Minstd
    let checker = Checker()
    let controls: [Int: [ControlEvent]]
    let requests: [Request]
    var time = 0
    var trace: [String] = []
    var elections: [ElectionRecord] = []
    var leaders: [Int: LeaderRecord] = [:]
    var timelines: [String] = []
    var leaderTicks = 0, multiTicks = 0
    var gaps: [(first: Int, last: Int)] = []
    var gapStart: Int?
    var maximumTerm = 0, committedCount = 0
    var referenceStates: [Int: [String: Int]] = [0: [:]], referenceState: [String: Int] = [:]
    var statusCounts: [RequestStatus: Int] = [:]
    var latencies: [Int] = []
    var keyRequests: [String: Int] = [:], keyCommitted: [String: Int] = [:]
    init(_ settings: Settings, _ script: (controls: [Control], requests: [Request]), _ network: Network) {
        self.settings = settings; nodes = (1...settings.nodes).map { RaftNode($0) }; self.network = network; random = Minstd(settings.seed); requests = script.requests
        var controls: [Int: [ControlEvent]] = [:]
        for control in script.controls { controls[control.time, default: []].append(control.event) }
        self.controls = controls
    }
    func node(_ number: Int) -> RaftNode { nodes[number - 1] }
    func majority(_ count: Int) -> Bool { 2 * count > settings.nodes }
    func writeTrace(_ content: String) { trace.append("\(time) \(content)") }
    func setElectionTimer(_ node: RaftNode) { node.electionDeadline = time + random.between(settings.electionMin, settings.electionMax) }
    func send(_ node: RaftNode, _ destination: Int, _ payload: Payload) { network.send(time, node.number, destination, node.term, payload) }
    func sendAppend(_ node: RaftNode, _ destination: Int) {
        let previous = node.next[destination]! - 1, end = min(previous + settings.batch, node.lastIndex), entries = Array(node.log[previous..<end])
        send(node, destination, .appendRequest(previous, node.termAt(previous), entries, node.commit))
    }
    func broadcastAppend(_ node: RaftNode) { for other in nodes where other.number != node.number { sendAppend(node, other.number) } }
    func endLeadership(_ node: RaftNode, _ reason: String) { let record = leaders[node.term]!; record.ended = time; record.reason = reason; record.commit = node.commit; node.cancelTransfer() }
    func control(_ event: ControlEvent) {
        switch event {
        case let .crash(number):
            let node = self.node(number)
            writeTrace("CRASH n\(number) \(node.role.rawValue) term \(node.term)")
            if node.role == .leader { endLeadership(node, "CRASH") }; node.crash()
        case let .restart(number):
            let node = self.node(number); node.up = true; setElectionTimer(node)
            writeTrace("RESTART n\(number) term \(node.term) length \(node.lastIndex) deadline \(node.electionDeadline!)")
        case let .partition(groups): network.partition(groups); writeTrace("PARTITION " + groups.map { nodeSet($0) }.joined(separator: " "))
        case .heal: network.heal(); writeTrace("HEAL")
        case let .transfer(first, second): startTransfer(node(first), second)
        }
    }
    func attempt(_ request: Request) {
        request.attempts += 1
        var destination = request.destination, redirected = 0, reason = "", rejecting = destination
        while true {
            let node = self.node(destination); rejecting = node.number
            if !node.up { reason = "down"; break }
            if node.role == .leader {
                if node.transferTarget != nil { reason = "transfer"; break }
                node.log.append(Entry(term: node.term, command: request.command, request: request.number)); leaders[node.term]!.appended += 1
                request.accepted = AcceptedEntry(index: node.lastIndex, term: node.term); request.scheduled = nil
                writeTrace("ACCEPT r\(request.number) n\(node.number) index \(node.lastIndex) term \(node.term)"); return
            }
            if node.knownLeader == nil || redirected >= settings.nodes - 1 { reason = "noleader"; break }
            destination = node.knownLeader!
            writeTrace("REDIRECT r\(request.number) n\(node.number) n\(destination)")
            redirected += 1; request.redirects += 1
        }
        let prefix = "REJECT r\(request.number) n\(rejecting) \(reason)"
        if request.attempts < settings.attempts {
            request.destination = rejecting % settings.nodes + 1; request.scheduled = time + settings.retry
            writeTrace("\(prefix) retry n\(request.destination) at \(request.scheduled!)")
        } else { request.abandoned = true; request.scheduled = nil; writeTrace(prefix + " giveup") }
    }
    func startElection(_ node: RaftNode, _ trigger: String) {
        node.term += 1; node.role = .candidate; node.votedFor = node.number; node.votes = [node.number]; node.knownLeader = nil
        setElectionTimer(node); node.stats.elections += 1; node.electionIndex = elections.count
        elections.append(ElectionRecord(time: time, node: node.number, term: node.term, trigger: trigger, votes: node.votes))
        writeTrace("ELECTION n\(node.number) term \(node.term) last \(node.lastIndex)/\(node.lastTerm) deadline \(node.electionDeadline!)")
        for other in nodes where other.number != node.number { send(node, other.number, .voteRequest(node.lastIndex, node.lastTerm)) }
    }
    func voteRequest(_ node: RaftNode, _ message: Message, _ index: Int, _ term: Int) {
        var reason: String?
        if message.term < node.term { reason = "term" }
        else if let voted = node.votedFor, voted != message.source { reason = "voted" }
        else if !node.acceptsLog(index, term) { reason = "log" }
        if let reason { writeTrace("DENY n\(node.number) n\(message.source) term \(node.term) \(reason)") }
        else {
            node.votedFor = message.source; node.stats.votesGranted += 1; setElectionTimer(node)
            writeTrace("VOTE n\(node.number) n\(message.source) term \(node.term) deadline \(node.electionDeadline!)")
        }
        send(node, message.source, .voteResponse(reason == nil))
    }
    func voteResponse(_ node: RaftNode, _ message: Message, _ granted: Bool) {
        if node.role != .candidate || message.term != node.term || !granted { return }
        node.votes.insert(message.source); elections[node.electionIndex!].votes = node.votes
        if majority(node.votes.count) { becomeLeader(node) }
    }
    func becomeLeader(_ node: RaftNode) {
        node.role = .leader; node.knownLeader = node.number
        for other in nodes where other.number != node.number { node.next[other.number] = node.lastIndex + 1; node.match[other.number] = 0 }
        node.log.append(Entry(term: node.term, command: .noop, request: 0)); node.stats.leaderTerms += 1; elections[node.electionIndex!].won = time
        checker.leader(node); leaders[node.term] = LeaderRecord(node.number, time, node.votes)
        writeTrace("LEADER n\(node.number) term \(node.term) votes \(nodeSet(node.votes)) noop \(node.lastIndex)")
        broadcastAppend(node); node.heartbeatDeadline = time + settings.heartbeat; node.quorumDeadline = time + settings.quorum; node.heard = []
    }
    func truncate(_ node: RaftNode, _ first: Int) {
        let removed = Array(node.log[(first - 1)...])
        node.log.removeSubrange((first - 1)..<node.log.count); node.stats.truncated += removed.count; checker.truncate(first, removed)
        writeTrace("TRUNCATE n\(node.number) from \(first) removed \(removed.count)")
    }
    func appendRequest(_ node: RaftNode, _ message: Message, _ previous: Int, _ previousTerm: Int, _ entries: [Entry], _ commit: Int) {
        if message.term < node.term { send(node, message.source, .appendResponse(false, 0)); return }
        if node.role == .candidate { node.role = .follower; writeTrace("YIELD n\(node.number) term \(node.term) n\(message.source)") }
        node.knownLeader = message.source; setElectionTimer(node)
        if previous > node.lastIndex || node.termAt(previous) != previousTerm {
            node.stats.aeFail += 1; let hint = previous > node.lastIndex ? node.lastIndex : previous - 1
            send(node, message.source, .appendResponse(false, hint)); return
        }
        node.stats.aeOK += 1
        for (offset, entry) in entries.enumerated() {
            let index = previous + offset + 1
            if index <= node.lastIndex && node.termAt(index) != entry.term { truncate(node, index) }
            if index > node.lastIndex { node.log.append(entry); node.stats.appended += 1 }
        }
        let confirmed = previous + entries.count, committed = min(commit, confirmed)
        if committed > node.commit { advanceCommit(node, committed) }
        send(node, message.source, .appendResponse(true, confirmed))
    }
    func appendResponse(_ node: RaftNode, _ message: Message, _ success: Bool, _ confirmed: Int) {
        if node.role != .leader || message.term != node.term { return }
        let source = message.source
        node.heard.insert(source)
        if success {
            node.match[source] = max(node.match[source]!, confirmed); node.next[source] = max(node.next[source]!, confirmed + 1); checkCommit(node)
            if source == node.transferTarget && !node.transferSent && node.match[source] == node.lastIndex { sendTimeoutNow(node) }
            else if node.next[source]! <= node.lastIndex { sendAppend(node, source) }
        } else {
            node.next[source] = max(node.match[source]! + 1, min(node.next[source]! - 1, confirmed + 1))
            writeTrace("BACKTRACK n\(node.number) n\(source) next \(node.next[source]!)"); sendAppend(node, source)
        }
    }
    func checkCommit(_ node: RaftNode) {
        if node.lastIndex <= node.commit { return }
        for index in stride(from: node.lastIndex, through: node.commit + 1, by: -1) {
            if node.termAt(index) != node.term { return }
            if majority(1 + node.match.values.filter { $0 >= index }.count) {
                writeTrace("COMMIT n\(node.number) \(node.commit + 1)-\(index) term \(node.term)"); advanceCommit(node, index); return
            }
        }
    }
    func advanceCommit(_ node: RaftNode, _ index: Int) {
        for position in (node.commit + 1)...index { checker.commit(position, node.termAt(position), time) }
        node.commit = index
        let first = node.applied + 1
        for position in first...index {
            let entry = node.log[position - 1], result = applyCommand(&node.store, entry.command)
            node.stats.applies += 1; checker.apply(position, entry, result)
        }
        node.applied = index; writeTrace("APPLY n\(node.number) \(first)-\(index)")
    }
    func receive(_ message: Message) {
        let node = self.node(message.destination)
        if message.term > node.term {
            let role = node.role
            writeTrace("TERM n\(node.number) \(node.term)->\(message.term) \(message.kind.rawValue) n\(message.source) \(role.rawValue)")
            if role == .leader { endLeadership(node, "STEPDOWN") }
            node.term = message.term; node.votedFor = nil; node.knownLeader = nil; node.role = .follower
            if role == .leader { setElectionTimer(node) }
        }
        switch message.payload {
        case let .voteRequest(index, term): voteRequest(node, message, index, term)
        case let .voteResponse(granted): voteResponse(node, message, granted)
        case let .appendRequest(previous, term, entries, commit): appendRequest(node, message, previous, term, entries, commit)
        case let .appendResponse(success, confirmed): appendResponse(node, message, success, confirmed)
        case .timeoutNow:
            if message.term != node.term || node.role != .follower { writeTrace("IGNORE n\(node.number) TN n\(message.source) term \(message.term)") }
            else { startElection(node, "transfer") }
        }
    }
    func startTransfer(_ node: RaftNode, _ destination: Int) {
        let prefix = "TRANSFER n\(node.number) n\(destination)"
        if !node.up || node.role != .leader || node.transferTarget != nil || node.number == destination { writeTrace(prefix + " ignored"); return }
        writeTrace("\(prefix) start match \(node.match[destination]!)/\(node.lastIndex)")
        node.transferTarget = destination; node.transferSent = false; node.transferDeadline = time + settings.electionMin
        if node.match[destination] == node.lastIndex { sendTimeoutNow(node) } else { sendAppend(node, destination) }
    }
    func sendTimeoutNow(_ node: RaftNode) {
        let target = node.transferTarget!
        writeTrace("TIMEOUTNOW n\(node.number) n\(target) term \(node.term) index \(node.lastIndex)")
        node.transferSent = true; send(node, target, .timeoutNow)
    }
    func timers(_ node: RaftNode) {
        if node.role == .leader {
            if node.quorumDeadline == time {
                if !majority(1 + node.heard.count) {
                    writeTrace("STEPDOWN n\(node.number) term \(node.term) heard \(nodeSet(node.heard))"); endLeadership(node, "QUORUM")
                    node.role = .follower; node.knownLeader = nil; setElectionTimer(node); return
                }
                node.heard = []; node.quorumDeadline = time + settings.quorum
            }
            if node.transferTarget != nil && node.transferDeadline == time { writeTrace("TRANSFER n\(node.number) n\(node.transferTarget!) abort"); node.cancelTransfer() }
            if node.heartbeatDeadline == time { broadcastAppend(node); node.heartbeatDeadline = time + settings.heartbeat }
        } else if node.electionDeadline == time { startElection(node, "timeout") }
    }
    func endOfTick() {
        checker.checkLogs(nodes)
        let leaders = nodes.filter { $0.up && $0.role == .leader }
        for node in leaders { node.stats.leaderTicks += 1 }
        if !leaders.isEmpty {
            leaderTicks += 1; multiTicks += leaders.count >= 2 ? 1 : 0
            if let gapStart { gaps.append((gapStart, time - 1)); self.gapStart = nil }
        } else if gapStart == nil { gapStart = time }
        if time % settings.sample == 0 { timelines.append("TIMELINE \(time) " + nodes.map { ($0.up ? String($0.role.rawValue.prefix(1)) : "D") + String($0.term) }.joined(separator: " ")) }
    }
    func run() {
        for node in nodes { setElectionTimer(node); writeTrace("START n\(node.number) deadline \(node.electionDeadline!)") }
        for current in 0...settings.end {
            time = current
            for event in controls[time] ?? [] { control(event) }
            for request in requests where request.scheduled == time { attempt(request) }
            for message in network.arrivals(time) { if network.deliver(message, node(message.destination).up) { receive(message) } }
            for node in nodes where node.up { timers(node) }
            endOfTick()
        }
        if let gapStart { gaps.append((gapStart, settings.end)) }
        finishStatistics()
    }
}
func statisticsText(_ statistics: MessageStatistics) -> String { MessageField.allCases.map { "\($0.name) \(statistics[$0])" }.joined(separator: " ") }
extension Simulator {
    func finishStatistics() {
        maximumTerm = nodes.map { $0.term }.max()!; committedCount = checker.committed.count
        let needed = Set(nodes.map { $0.applied })
        for index in 1..<(committedCount + 1) {
            _ = applyCommand(&referenceState, checker.applied[index]!.entry.command)
            if needed.contains(index) { referenceStates[index] = referenceState }
        }
        for request in requests {
            let key = request.command.key!
            keyRequests[key, default: 0] += 1
            if let accepted = request.accepted {
                if let committed = checker.committed[accepted.index], committed.term == accepted.term {
                    request.status = .committed; request.latency = committed.time - request.time; request.result = checker.applied[accepted.index]!.result
                    latencies.append(request.latency!); keyCommitted[key, default: 0] += 1
                } else if nodes.contains(where: { $0.lastIndex >= accepted.index && $0.termAt(accepted.index) == accepted.term }) { request.status = .uncommitted }
                else { request.status = .lost }
            } else { request.status = request.abandoned ? .failed : .waiting }
            statusCounts[request.status, default: 0] += 1
        }
    }
    func leaderLines() -> [String] {
        var lines: [String] = []
        for record in elections {
            let outcome = record.won.map { "WON \($0)" } ?? "LOST"
            lines.append("ELECTION \(record.time) n\(record.node) term \(record.term) trigger \(record.trigger) votes \(record.votes.count) \(outcome)")
        }
        for term in 1..<(maximumTerm + 1) {
            let elections = self.elections.filter { $0.term == term }, candidates = nodeSet(elections.map { $0.node })
            guard let record = leaders[term] else { lines.append("TERM \(term) NONE candidates \(candidates)"); continue }
            let end = record.ended.map(String.init) ?? "-", reason = record.reason ?? "ACTIVE", commit = record.commit ?? node(record.node).commit, start = elections[0].time
            lines.append("TERM \(term) LEADER n\(record.node) elected \(record.elected) votes \(nodeSet(record.votes)) ended \(end) \(reason) appended \(record.appended) commit \(commit) candidates \(candidates) started \(start) wait \(record.elected - start)")
        }
        for node in nodes { let stats = node.stats; lines.append("NODE n\(node.number) elections \(stats.elections) leader_terms \(stats.leaderTerms) leader_ticks \(stats.leaderTicks) votes_granted \(stats.votesGranted)") }
        lines += timelines
        for gap in gaps { lines.append("GAP \(gap.first)-\(gap.last) length \(gap.last - gap.first + 1)") }
        let longest = gaps.map { $0.last - $0.first + 1 }.max() ?? 0
        lines.append("SUMMARY terms \(maximumTerm) leaders \(leaders.count) elections \(elections.count) leader_ticks \(leaderTicks) multi_ticks \(multiTicks) ticks \(settings.end + 1) gaps \(gaps.count) longest \(longest)")
        return lines
    }
    func logLines() -> [String] {
        var lines: [String] = []
        for node in nodes {
            let status = node.up ? node.role.rawValue : "DOWN", voted = node.votedFor.map { "n\($0)" } ?? "-"
            lines.append("NODE n\(node.number) \(status) term \(node.term) voted \(voted) commit \(node.commit) applied \(node.applied) length \(node.lastIndex)")
            for (index, entry) in node.log.enumerated() { lines.append("\(index + 1) \(entry.term) \(entry.command.text)" + (entry.request == 0 ? "" : " r\(entry.request)")) }
        }
        var prefix = 0
        for index in 0..<nodes.map({ $0.lastIndex }).min()! { if !nodes.dropFirst().allSatisfy({ $0.log[index] == nodes[0].log[index] }) { break }; prefix += 1 }
        lines.append("AGREE prefix \(prefix) committed \(committedCount)")
        for node in nodes {
            var common = 0
            for index in 1..<(min(node.lastIndex, committedCount) + 1) { if node.termAt(index) != checker.committed[index]!.term { break }; common = index }
            let stats = node.stats
            lines.append("DIFF n\(node.number) common \(common) behind \(committedCount - common) extra \(node.lastIndex - common) ae_ok \(stats.aeOK) ae_fail \(stats.aeFail) appended \(stats.appended) truncated \(stats.truncated) applies \(stats.applies)")
        }
        return lines
    }
    func requestLine(_ request: Request) -> String {
        var line = "REQUEST r\(request.number) at \(request.time) n\(request.initialDestination) \(request.command.text) attempts \(request.attempts) redirects \(request.redirects) "
        if let accepted = request.accepted {
            line += "\(request.status.rawValue) index \(accepted.index) term \(accepted.term)"
            if request.status == .committed { line += " latency \(request.latency!) result \(request.result!)" }
        } else if request.status == .failed { line += "FAILED" } else { line += "WAITING next \(request.scheduled!)" }
        return line
    }
    func stateLines() -> [String] {
        var lines: [String] = []
        for node in nodes {
            let replay = node.store == referenceStates[node.applied]! ? "match" : "mismatch"
            lines.append("NODE n\(node.number) \(node.up ? "UP" : "DOWN") applied \(node.applied) keys \(node.store.count) replay \(replay)")
            for key in node.store.keys.sorted() { lines.append("\(key) \(node.store[key]!)") }
        }
        lines += requests.map(requestLine)
        for key in keyRequests.keys.sorted() { let value = referenceState[key].map(String.init) ?? "missing"; lines.append("KEY \(key) requests \(keyRequests[key]!) committed \(keyCommitted[key, default: 0]) final \(value)") }
        let statuses = RequestStatus.allCases.map { "\($0.rawValue.lowercased()) \(statusCounts[$0, default: 0])" }.joined(separator: " ")
        lines.append("REQUESTS total \(requests.count) \(statuses)")
        lines.append("LATENCY count \(latencies.count) total \(latencies.reduce(0, +)) min \(latencies.min() ?? 0) max \(latencies.max() ?? 0)")
        return lines
    }
    func safetyLines() -> [String] {
        var lines = checker.lines(maximumTerm)
        lines.append("MESSAGES " + statisticsText(network.total))
        for kind in MessageType.allCases { lines.append("TYPE \(kind.rawValue) " + statisticsText(network.byType[kind] ?? MessageStatistics())) }
        for source in 1...settings.nodes { for destination in 1...settings.nodes where source != destination {
            let link = network.links[LinkKey(source: source, destination: destination)]!, dropped = [MessageField.partition, .rule, .loss, .down].map { link.stats[$0] }.reduce(0, +)
            lines.append("LINK n\(source)->n\(destination) delay \(link.delay) loss \(link.loss) sent \(link.stats[.sent]) delivered \(link.stats[.delivered]) dropped \(dropped)")
        } }
        lines.append("DRAWS \(random.draws)"); lines.append(checker.violations.values.contains { $0 != 0 } ? "RESULT UNSAFE" : "RESULT SAFE")
        return lines
    }
    func writeOutputs() throws {
        let outputs = [("trace.txt", trace), ("leaders.txt", leaderLines()), ("logs.txt", logLines()), ("state.txt", stateLines()), ("safety.txt", safetyLines())]
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        for (name, lines) in outputs { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
    }
}
let settings = try readSettings(), script = try readScript(), network = try Network(settings.nodes), simulation = Simulator(settings, script, network)
simulation.run()
try simulation.writeOutputs()
