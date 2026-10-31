struct Message {
    let serial: Int, sender: Int, receiver: Int, link: Int, prefix: Prefix, content: Attribute?, arrival: Int
    static func before(_ a: Self, _ b: Self) -> Bool { if a.arrival != b.arrival { return a.arrival < b.arrival }; if a.receiver != b.receiver { return a.receiver < b.receiver }; if a.sender != b.sender { return a.sender < b.sender }; return a.serial < b.serial }
}
final class MessageQueue {
    var messages: [Message] = [], serial = 0
    func send(_ time: Int, _ delay: Int, _ sender: Int, _ receiver: Int, _ link: Int, _ prefix: Prefix, _ content: Attribute?) -> Message {
        serial += 1; let message = Message(serial: serial, sender: sender, receiver: receiver, link: link, prefix: prefix, content: content, arrival: time + delay); messages.append(message); return message
    }
    func deliveries(_ time: Int) -> [Message] { let result = messages.filter { $0.arrival == time }.sorted(by: Message.before); messages.removeAll { $0.arrival == time }; return result }
    func remove(_ link: Int) -> [Message] { let result = messages.filter { $0.link == link }.sorted(by: Message.before); messages.removeAll { $0.link == link }; return result }
}
struct Event {
    let time: Int, text: String, fields: [String], kind: String
    static func read() -> [Self] { [Self(time: 0, text: "INITIAL", fields: ["INITIAL"], kind: "INITIAL")] + words("events.txt").map { w in let fields = Array(w.dropFirst()); return Self(time: Int(w[0])!, text: fields.joined(separator: " "), fields: fields, kind: ["LINK", "POLICY"].contains(fields[0]) ? fields[0] + "_" + fields[1] : fields[0]) } }
}
struct Parameters {
    let defaults: [Int], stepcap: Int, traces: [(Int, String, Int)]
    init() { let lines = words("params.txt"); defaults = lines[0].dropFirst().map { Int($0)! }; stepcap = Int(lines[1][1])!; traces = lines.dropFirst(2).map { (Int($0[1])!, $0[2], parseAddress($0[2])) } }
}
