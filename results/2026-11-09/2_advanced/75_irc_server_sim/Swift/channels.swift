import Foundation

final class Member {
    unowned let client: Client
    var isOperator: Bool
    var voice = false

    init(_ client: Client, isOperator: Bool) {
        self.client = client
        self.isOperator = isOperator
    }

    var status: String { isOperator ? "@" : voice ? "+" : "" }
    var display: String { status + client.nickname! }
}

struct Ban {
    let mask: String
    let setter: String
    let time: Int
}

final class Channel {
    let name: String
    let created: Int
    var members: [Member] = []
    var topic = ""
    var topicSetter = ""
    var topicTime = 0
    var bans: [Ban] = []
    var flags: Set<Character> = ["n", "t"]
    var key = ""
    var limit = 0
    var peak = 0
    var messages = 0

    init(_ name: String, time: Int) {
        self.name = name
        created = time
    }

    func member(_ client: Client) -> Member? {
        members.first { $0.client === client }
    }

    func add(_ client: Client, isOperator: Bool) {
        members.append(Member(client, isOperator: isOperator))
        client.channels.append(self)
        peak = max(peak, members.count)
    }

    func remove(_ client: Client) {
        members.removeAll { $0.client === client }
        client.channels.removeAll { $0 === self }
    }

    func nameList(_ viewer: Client) -> String {
        let inside = member(viewer) != nil
        return members.filter { inside || !$0.client.invisible }.map(\.display).joined(separator: " ")
    }

    func banned(_ client: Client) -> Bool {
        bans.contains { maskMatches($0.mask, client.prefix) }
    }

    func canSpeak(_ client: Client) -> Bool {
        let member = member(client)
        let privileged = member.map { $0.isOperator || $0.voice } ?? false
        return (member != nil || !flags.contains("n"))
            && (!flags.contains("m") || privileged) && (privileged || !banned(client))
    }

    func modeDisplay(includeKey: Bool = true) -> String {
        var mode = "+"
        for character in "iklmnt" {
            let present = character == "k" ? !key.isEmpty : character == "l" ? limit != 0
                : flags.contains(character)
            if present { mode.append(character) }
        }
        if includeKey && !key.isEmpty { mode += " " + key }
        if limit != 0 { mode += " \(limit)" }
        return mode
    }
}
