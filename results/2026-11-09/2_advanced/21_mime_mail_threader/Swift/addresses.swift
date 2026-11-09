struct Mailbox { let name: String; let address: String }
enum Address { case mailbox(Mailbox), group([Mailbox]) }
private final class AddressParser {
    let tokens: [Token]
    var position = 0
    var error = false
    init(_ tokens: [Token]) { self.tokens = tokens }
    var peek: TokenKind? { position < tokens.count ? tokens[position].kind : nil }
    func expect(_ kind: TokenKind) -> Bool {
        if peek != kind { return false }
        position += 1; return true
    }
    func run(_ quoted: Bool) -> Range<Int> {
        let start = position
        while peek == .word || peek == .special(46) || quoted && peek == .quoted { position += 1 }
        return start..<position
    }
    func displayName(_ range: Range<Int>) -> String {
        var result = ""
        var previous = false
        for (index, token) in tokens[range].enumerated() {
            let (text, decoded, failed) = token.kind == .word ? decodeWord(token.text) : (token.text, false, false)
            error = error || failed
            if index > 0 && token.spaced && !(decoded && previous) { result += " " }
            result += text; previous = decoded
        }
        return collapseWhitespace(result)
    }
    func atom(_ range: Range<Int>) -> String? {
        if range.count % 2 == 0 { return nil }
        for (index, token) in tokens[range].enumerated() {
            if token.kind != (index % 2 == 0 ? .word : .special(46)) { return nil }
        }
        return tokens[range].map(\.text).joined()
    }
    func address(_ inGroup: Bool) -> Address? {
        let phrase = run(true)
        if peek == .special(60) {
            position += 1
            let local = run(false)
            if !expect(.special(64)) { return nil }
            let domain = run(false)
            guard expect(.special(62)), let first = atom(local), let second = atom(domain) else { return nil }
            return .mailbox(Mailbox(name: displayName(phrase), address: (first + "@" + second).lowercased()))
        }
        if peek == .special(64) {
            position += 1
            let domain = run(false)
            guard let first = atom(phrase), let second = atom(domain) else { return nil }
            return .mailbox(Mailbox(name: "", address: (first + "@" + second).lowercased()))
        }
        if peek == .special(58) && !phrase.isEmpty && !inGroup {
            position += 1
            var mailboxes: [Mailbox] = []
            if peek != .special(59) {
                while true {
                    guard let entry = address(true), case .mailbox(let mailbox) = entry else { return nil }
                    mailboxes.append(mailbox)
                    if peek != .special(44) { break }
                    position += 1
                }
            }
            if !expect(.special(59)) { return nil }
            return .group(mailboxes)
        }
        return nil
    }
}
func parseAddressList(_ value: String) -> ([Address], Bool)? {
    guard let tokens = tokenize(value, true) else { return nil }
    let parser = AddressParser(tokens)
    guard let first = parser.address(false) else { return nil }
    var addresses = [first]
    while parser.peek == .special(44) {
        parser.position += 1
        guard let next = parser.address(false) else { return nil }
        addresses.append(next)
    }
    return parser.position == tokens.count ? (addresses, parser.error) : nil
}
