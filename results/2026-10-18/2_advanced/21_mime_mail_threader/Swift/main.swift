import Foundation

let checkedFields = ["From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"]
typealias MailLine = (Int, String)
func readLines(_ path: String) throws -> [String] {
    var lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}
func readMailbox(_ lines: [String]) -> [[MailLine]] {
    var messages: [[MailLine]] = []
    for (number, line) in lines.enumerated() {
        if line.hasPrefix("From ") { messages.append([]) }
        else if !messages.isEmpty {
            let unquoted = line.drop(while: { $0 == ">" })
            let text = unquoted.count < line.count && unquoted.hasPrefix("From ") ? String(line.dropFirst()) : line
            messages[messages.count - 1].append((number + 1, text))
        }
    }
    for index in messages.indices where messages[index].last?.1 == "" { messages[index].removeLast() }
    return messages
}
func splitSections(_ lines: [MailLine]) -> ([MailLine], [MailLine]) {
    if let index = lines.firstIndex(where: { $0.1.isEmpty }) { return (Array(lines[..<index]), Array(lines[(index + 1)...])) }
    return (lines, [])
}
func isMessageID(_ text: String) -> Bool {
    if text.utf8.count < 3 || !text.hasPrefix("<") || !text.hasSuffix(">") { return false }
    let inside = text.dropFirst().dropLast()
    return inside.utf8.filter { $0 == 64 }.count == 1 && inside.first != "@" && inside.last != "@" && inside.utf8.allSatisfy { 33...126 ~= $0 && !"<>()\"\\".utf8.contains($0) }
}
func extractIDs(_ value: String) -> [String] {
    let data = Array(value.utf8)
    var result: [String] = []
    var position = 0
    while position < data.count {
        guard let start = data[position...].firstIndex(of: 60), let end = data[(start + 1)...].firstIndex(of: 62) else { break }
        let id = String(decoding: data[start...end], as: UTF8.self)
        if isMessageID(id) { result.append(id) }
        position = end + 1
    }
    return result
}
func dateNotation(_ seconds: Int?) -> String { seconds.map(formatUTC) ?? "invalid" }
func subjectNotation(_ subject: String) -> String { subject.isEmpty ? "(no subject)" : subject }
func asciiLess(_ first: String, _ second: String) -> Bool { first.utf8.lexicographicallyPrecedes(second.utf8) }
final class Entity {
    let number: String
    var mainType = "text"
    var subtype = "plain"
    var parameters: [String: String] = [:]
    var disposition: String?
    var filename = ""
    var children: [Entity]?
    var content = ""
    init(_ number: String) { self.number = number }
    func parameter(_ name: String) -> String { parameters[name] ?? "" }
}
final class Message {
    let number: Int
    var problems: [String] = []
    var sender: Mailbox?
    var to: [String] = []
    var cc: [String] = []
    var subject = ""
    var baseSubject = ""
    var reply = false
    var date: Int?
    var id = ""
    var references: [String] = []
    var body = Entity("1")
    var thread = 0
    var depth = 0
    var parent: Message?
    var sortKey: (Int, Int, String, Int) { (date == nil ? 1 : 0, date ?? 0, id, number) }
    init(_ number: Int) { self.number = number }
    func process(_ lines: [MailLine], _ knownIDs: inout [String: Int]) {
        let (headerLines, bodyLines) = splitSections(lines)
        let header = parseFields(headerLines)
        for number in header.invalidLines { problems.append("bad header line \(number)") }
        for name in checkedFields where header.count(name) > 1 { problems.append("duplicate " + name) }
        readSender(header.value("From"))
        to = readRecipients(header.value("To"), "To")
        cc = readRecipients(header.value("Cc"), "Cc")
        let (subject, error) = decodeUnstructured(header.value("Subject") ?? "")
        self.subject = subject
        if error { problems.append("bad encoded word in Subject") }
        var base = subject
        while base.prefix(3).lowercased() == "re:" { base = String(base.dropFirst(3).drop(while: { $0 == " " })); reply = true }
        baseSubject = base
        if let value = header.value("Date") {
            do { date = try parseDate(value) }
            catch let error as DateProblem { problems.append(error.rawValue) }
            catch { preconditionFailure() }
        } else { problems.append("missing Date") }
        if let value = header.value("Message-ID") {
            if !isMessageID(value) { problems.append("bad Message-ID") }
            else if let number = knownIDs[value] { problems.append("Message-ID already used by message \(number)") }
            else { id = value; knownIDs[value] = number }
        } else { problems.append("missing Message-ID") }
        references = extractIDs(header.value("References") ?? "")
        if let first = extractIDs(header.value("In-Reply-To") ?? "").first, references.last != first { references.append(first) }
        var enabled = false
        if let value = header.value("MIME-Version") {
            if let text = removeComments(value), text.filter({ $0 != " " && $0 != "\t" }) == "1.0" { enabled = true }
            else { problems.append("bad MIME-Version") }
        }
        body = parseEntity("1", header, bodyLines, enabled)
    }
    func readSender(_ value: String?) {
        guard let value else { problems.append("missing From"); return }
        if let (addresses, error) = parseAddressList(value), addresses.count == 1, case .mailbox(let mailbox) = addresses[0] {
            sender = mailbox
            if error { problems.append("bad encoded word in From") }
        } else { problems.append("bad From") }
    }
    func readRecipients(_ value: String?, _ name: String) -> [String] {
        guard let value else { return [] }
        guard let (addresses, error) = parseAddressList(value) else { problems.append("bad " + name); return [] }
        var recipients: [String] = []
        for address in addresses {
            switch address { case .mailbox(let mailbox): recipients.append(mailbox.address); case .group(let mailboxes): recipients += mailboxes.map(\.address) }
        }
        if error { problems.append("bad encoded word in " + name) }
        return recipients
    }
    func parseEntity(_ number: String, _ header: Header, _ lines: [MailLine], _ enabled: Bool) -> Entity {
        let entity = Entity(number)
        if enabled {
            if let value = header.value("Content-Type") {
                if let parsed = parseParameters(value, true) { entity.mainType = parsed.mainType; entity.subtype = parsed.subtype; entity.parameters = parsed.values }
                else { problems.append("bad Content-Type in part " + number) }
            }
            if let value = header.value("Content-Disposition") {
                if let parsed = parseParameters(value, false) { entity.disposition = parsed.mainType; entity.filename = parsed.values["filename"] ?? "" }
                else { problems.append("bad Content-Disposition in part " + number) }
            }
        }
        if entity.filename.isEmpty { entity.filename = entity.parameter("name") }
        if entity.mainType == "text", let charset = entity.parameters["charset"], charset.lowercased() != "us-ascii" { problems.append("unsupported charset \"\(charset.lowercased())\" in part \(number)") }
        if enabled && entity.mainType == "multipart" {
            let boundary = entity.parameter("boundary")
            if !boundary.isEmpty { splitMultipart(entity, lines, boundary); return entity }
            problems.append("missing boundary in part " + number)
        }
        let original = lines.map { $0.1 }.joined(separator: "\n")
        let encoding = enabled ? (header.value("Content-Transfer-Encoding") ?? "7bit").lowercased() : "7bit"
        switch encoding {
        case "base64":
            if let content = decodeBase64Body(original) { entity.content = content }
            else { problems.append("bad base64 in part " + number) }
        case "quoted-printable":
            let (content, error) = decodeQuotedPrintable(original)
            entity.content = content
            if error { problems.append("bad quoted-printable in part " + number) }
        default:
            entity.content = original
            if !["7bit", "8bit", "binary"].contains(encoding) { problems.append("unknown encoding \"\(encoding)\" in part \(number)") }
        }
        return entity
    }
    func splitMultipart(_ entity: Entity, _ lines: [MailLine], _ boundary: String) {
        var parts: [[MailLine]] = []
        var closed = false
        for line in lines {
            let text = stripTrailing(line.1)
            if text == "--" + boundary + "--" { closed = true; break }
            if text == "--" + boundary { parts.append([]) }
            else if !parts.isEmpty { parts[parts.count - 1].append(line) }
        }
        if parts.isEmpty { problems.append("no parts in part " + entity.number) }
        else if !closed { problems.append("unterminated multipart in part " + entity.number) }
        var children: [Entity] = []
        for (index, part) in parts.enumerated() {
            let (headerLines, bodyLines) = splitSections(part)
            let header = parseFields(headerLines)
            for number in header.invalidLines { problems.append("bad header line \(number)") }
            children.append(parseEntity("\(entity.number).\(index + 1)", header, bodyLines, true))
        }
        entity.children = children
    }
}
func collectTextParts(_ entity: Entity, _ allowHTML: Bool) -> [Entity] {
    guard let children = entity.children else {
        if entity.disposition == "attachment" || entity.mainType != "text" { return [] }
        return entity.subtype == "plain" || entity.subtype == "html" && allowHTML ? [entity] : []
    }
    if entity.subtype == "alternative" {
        for pass in [false, true] { for child in children { let parts = collectTextParts(child, pass); if !parts.isEmpty { return parts } } }
        return []
    }
    return children.flatMap { collectTextParts($0, allowHTML) }
}
func quotePrefix(_ depth: Int) -> String { depth == 0 ? "" : String(repeating: ">", count: depth) + " " }
func wrap(_ text: String, _ prefix: String) -> [String] {
    var lines: [String] = []
    var current = ""
    for word in splitWords(text) {
        if !current.isEmpty && current.utf8.count + 1 + word.utf8.count > 72 { lines.append(prefix + current); current = word }
        else { if !current.isEmpty { current += " " }; current += word }
    }
    lines.append(prefix + current)
    return lines
}
struct LogicalLine { let depth: Int; var text: String; var flowing = false }
func flowedLines(_ content: String, _ deleteSpace: Bool) -> [String] {
    if content.isEmpty { return [] }
    var logical: [LogicalLine] = []
    for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let remainder = line.drop(while: { $0 == ">" })
        let depth = line.count - remainder.count
        let text = remainder.hasPrefix(" ") ? String(remainder.dropFirst()) : String(remainder)
        let flowing = text.hasSuffix(" ") && text != "-- "
        if let previous = logical.last, previous.flowing && previous.depth == depth {
            let last = logical.count - 1
            if deleteSpace { logical[last].text.removeLast() }
            logical[last].text += text; logical[last].flowing = flowing
        } else { logical.append(LogicalLine(depth: depth, text: text, flowing: flowing)) }
    }
    return logical.flatMap { wrap($0.text, quotePrefix($0.depth)) }
}
func referenceValue(_ name: String) -> String? {
    let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "]
    if let value = named[name] { return value }
    let digits = name.dropFirst()
    if name.hasPrefix("#") && (1...3).contains(digits.count) && digits.utf8.allSatisfy({ 48...57 ~= $0 }), let value = UInt8(digits), 32...126 ~= value { return String(UnicodeScalar(value)) }
    return nil
}
func replaceReferences(_ text: String) -> String {
    let data = Array(text.utf8)
    var result = ""
    var position = 0
    while position < data.count {
        if data[position] == 38, let end = data[(position + 1)...].firstIndex(of: 59), let value = referenceValue(String(decoding: data[(position + 1)..<end], as: UTF8.self)) { result += value; position = end + 1; continue }
        result += String(UnicodeScalar(data[position])); position += 1
    }
    return result
}
func htmlBlocks(_ content: String) -> [LogicalLine] {
    let data = Array(content.utf8)
    var blocks: [LogicalLine] = []
    var depth = 0
    var position = 0
    var text = ""
    var hide: String?
    while position < data.count {
        let close = data[position] == 60 ? data[(position + 1)...].firstIndex(of: 62) : nil
        guard let close else {
            if hide == nil { text += String(UnicodeScalar(data[position])) }
            position += 1; continue
        }
        let inside = Array(data[(position + 1)..<close])
        position = close + 1
        let endTag = inside.first == 47
        let start = endTag ? Array(inside.dropFirst()) : inside
        let name = String(decoding: start.prefix(while: { 65...90 ~= $0 || 97...122 ~= $0 || 48...57 ~= $0 }), as: UTF8.self).lowercased()
        if let hidden = hide { if endTag && name == hidden { hide = nil } }
        else if !endTag && ["head", "style", "script"].contains(name) { hide = name }
        else if name == "br" || name == "li" && !endTag {
            blocks.append(LogicalLine(depth: depth, text: text)); text = name == "li" ? "* " : ""
        } else if ["p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"].contains(name) {
            blocks.append(LogicalLine(depth: depth, text: text)); blocks.append(LogicalLine(depth: depth, text: "")); text = ""
            if name == "blockquote" { depth = endTag ? max(0, depth - 1) : depth + 1 }
        }
    }
    blocks.append(LogicalLine(depth: depth, text: text))
    return blocks
}
func htmlLines(_ content: String) -> [String] {
    var lines: [String] = []
    for block in htmlBlocks(content) {
        let normalized = collapseWhitespace(block.text.replacingOccurrences(of: "\n", with: " "))
        let text = replaceReferences(normalized).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        if !text.isEmpty { lines += wrap(text, quotePrefix(block.depth)) }
        else if let last = lines.last, !last.isEmpty { lines.append("") }
    }
    while lines.last == "" { lines.removeLast() }
    return lines
}
func displayLines(_ entity: Entity) -> (String, [String]) {
    if entity.subtype == "html" { return ("html", htmlLines(entity.content)) }
    if entity.parameter("format").lowercased() == "flowed" { return ("flowed", flowedLines(entity.content, entity.parameter("delsp").lowercased() == "yes")) }
    return ("plain", entity.content.isEmpty ? [] : entity.content.components(separatedBy: "\n"))
}
func lineCounts(_ lines: [String]) -> (Int, Int) {
    var quoted = 0
    var signature = 0
    for (index, line) in lines.enumerated() {
        let text = stripTrailing(line)
        if text.hasPrefix(">") { quoted += 1 }
        if text == "--" { signature = lines.count - index - 1 }
    }
    return (quoted, signature)
}
func walkContainer(_ container: Container, _ prefix: String, _ stem: String, _ depth: Int) -> [(Container, String, Int)] {
    var entries = [(container, prefix, depth)]
    for (index, child) in container.children.enumerated() {
        let last = index + 1 == container.children.count
        entries += walkContainer(child, stem + (last ? "`- " : "+- "), stem + (last ? "   " : "|  "), depth + 1)
    }
    return entries
}
struct MailThread {
    let number: Int
    let root: Container
    let entries: [(Container, String, Int)]
    init(_ number: Int, _ root: Container) { self.number = number; self.root = root; entries = walkContainer(root, "", "", 0) }
    func placeMessages() {
        for (container, _, depth) in entries {
            if let message = container.message { message.thread = number; message.depth = depth; message.parent = container.parent?.message }
        }
    }
    func report() -> [String] {
        let messages = entries.compactMap { $0.0.message }
        let depth = entries.map { $0.2 }.max()!
        let senders = Set(messages.compactMap { $0.sender?.address })
        let dates = messages.compactMap(\.date)
        var lines = ["thread \(number) messages \(messages.count) depth \(depth) senders \(senders.count)"]
        if let first = dates.min(), let last = dates.max() { lines.append("span \(formatUTC(first)) .. \(formatUTC(last))") }
        else { lines.append("span -") }
        lines.append("subject " + subjectNotation(root.subject ?? rootSubject(root)))
        for (container, prefix, _) in entries {
            let notation: String
            if let message = container.message { notation = "[\(message.number)] \(dateNotation(message.date)) \(message.sender?.address ?? "-") \(subjectNotation(message.subject))" }
            else if let subject = container.subject { notation = "[subject] " + subject }
            else { notation = "[missing] " + container.id }
            lines.append(prefix + notation)
        }
        return lines
    }
}
func senderNotation(_ sender: Mailbox?) -> String {
    guard let sender else { return "-" }
    return sender.name.isEmpty ? sender.address : "\(sender.name) <\(sender.address)>"
}
func entityLines(_ entity: Entity) -> [String] {
    var line = "part \(entity.number) \(entity.mainType)/\(entity.subtype)"
    if let children = entity.children { return [line] + children.flatMap(entityLines) }
    line += " \(entity.content.utf8.count)"
    if let disposition = entity.disposition { line += " " + disposition }
    if !entity.filename.isEmpty { line += " \"\(entity.filename)\"" }
    return [line]
}
func messageReport(_ message: Message) -> [String] {
    let parent = message.parent.map { String($0.number) } ?? "-"
    return ["message \(message.number)", "id \(message.id.isEmpty ? "-" : message.id)", "date " + dateNotation(message.date), "from " + senderNotation(message.sender),
        "to \(message.to.isEmpty ? "-" : message.to.joined(separator: ", "))", "cc \(message.cc.isEmpty ? "-" : message.cc.joined(separator: ", "))", "subject " + subjectNotation(message.subject),
        "refs \(message.references.isEmpty ? "-" : message.references.joined(separator: " "))", "thread \(message.thread) depth \(message.depth) parent \(parent)"] + entityLines(message.body)
}
func bodyReport(_ request: String, _ lookup: [String: Message]) -> [String] {
    var lines = ["request " + request]
    guard let message = lookup[request] else { return lines + ["not found"] }
    let parts = collectTextParts(message.body, true)
    lines.append("message \(message.number) text parts \(parts.count)")
    for part in parts {
        let (format, display) = displayLines(part)
        let (quoted, signature) = lineCounts(display)
        lines.append("part \(part.number) \(format) lines \(display.count) quoted \(quoted) signature \(signature)")
        lines += display.map { let text = stripTrailing($0); return text.isEmpty ? "|" : "| " + text }
    }
    return lines
}
struct SenderStats {
    let address: String
    var count = 0
    var threads: Set<Int> = []
    var first: Int?
    var last: Int?
    var name = ""
    mutating func add(_ message: Message) {
        count += 1; threads.insert(message.thread)
        if let date = message.date { first = min(first ?? date, date); last = max(last ?? date, date) }
        if let sender = message.sender, !sender.name.isEmpty { name = sender.name }
    }
}
func csvField(_ text: String) -> String {
    text.contains(",") || text.contains("\"") ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
}
func sendersReport(_ messages: [Message]) -> [String] {
    var stats: [String: SenderStats] = [:]
    for message in messages {
        guard let sender = message.sender else { continue }
        var entry = stats[sender.address] ?? SenderStats(address: sender.address)
        entry.add(message); stats[sender.address] = entry
    }
    let entries = stats.values.sorted { $0.count == $1.count ? asciiLess($0.address, $1.address) : $0.count > $1.count }
    return ["address,name,messages,threads,first,last"] + entries.map { "\($0.address),\(csvField($0.name)),\($0.count),\($0.threads.count),\($0.first.map(formatUTC) ?? "-"),\($0.last.map(formatUTC) ?? "-")" }
}
func malformedReport(_ messages: [Message]) -> [String] {
    let flagged = messages.filter { !$0.problems.isEmpty }.count
    let total = messages.reduce(0) { $0 + $1.problems.count }
    return ["messages \(messages.count) malformed \(flagged) problems \(total)"] + messages.flatMap { message in message.problems.map { "message \(message.number): \($0)" } }
}
func joinBlocks(_ blocks: [[String]]) -> [String] {
    var lines: [String] = []
    for block in blocks { if !lines.isEmpty { lines.append("") }; lines += block }
    return lines
}

var messages: [Message] = []
var knownIDs: [String: Int] = [:]
for (index, lines) in readMailbox(try readLines("input/mailbox.mbox")).enumerated() {
    let message = Message(index + 1); message.process(lines, &knownIDs); messages.append(message)
}
let roots = buildThreads(messages)
let threads = roots.enumerated().map { MailThread($0.offset + 1, $0.element) }
for thread in threads { thread.placeMessages() }
for message in messages {
    if let parent = message.parent, let date = message.date, let parentDate = parent.date, date < parentDate { message.problems.append("dated before parent message \(parent.number)") }
}
let lookup = Dictionary(uniqueKeysWithValues: messages.filter { !$0.id.isEmpty }.map { ($0.id, $0) })
let requests = try readLines("input/requests.txt")
let files = [("threads.txt", joinBlocks(threads.map { $0.report() })), ("messages.txt", joinBlocks(messages.map(messageReport))),
    ("bodies.txt", joinBlocks(requests.map { bodyReport($0, lookup) })), ("senders.csv", sendersReport(messages)), ("malformed.txt", malformedReport(messages))]
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in files { try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8) }
