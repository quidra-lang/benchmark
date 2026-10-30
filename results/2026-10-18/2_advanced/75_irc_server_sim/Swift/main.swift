import Foundation

enum TrafficKind: String {
    case connect, disconnect, messages
}

struct Traffic {
    let time: Int
    let identifier: String
    let kind: TrafficKind
    let body: String
}

final class Server {
    let settings: [String: String]
    let motd: [String]
    let traffic: [Traffic]
    let end: Int
    var time = 0
    var clients: [Client] = []
    var clientByID: [String: Client] = [:]
    var channels: [Channel] = []
    var sent: [String] = []
    var commands: [String: Int] = [:]
    var numerics: [Int: Int] = [:]
    var lineCounts: [TrafficKind: Int] = [:]
    var counts: [String: Int] = [:]
    var disconnects: [String: Int] = [:]
    var gone: [(Int, String, String, String)] = []
    var peakConnections = (0, 0)
    var peakRegistered = (0, 0)

    init() throws {
        var settings: [String: String] = [:], motd: [String] = []
        for line in try String(contentsOfFile: "input/server.txt", encoding: .ascii).split(separator: "\n") {
            let pieces = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pieces[0]), value = String(pieces[1])
            if key == "MOTD" { motd.append(value) } else { settings[key] = value }
        }
        self.settings = settings
        self.motd = motd
        traffic = try String(contentsOfFile: "input/traffic.txt", encoding: .ascii)
            .split(separator: "\n").map { line in
                let pieces = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
                let body = String(pieces[2])
                var kind = TrafficKind.messages
                if body == "DISCONNECT" {
                    kind = .disconnect
                } else if body.hasPrefix("CONNECT ") {
                    let host = body.dropFirst(8)
                    if (1...63).contains(host.count) && host.utf8.allSatisfy({
                        (65...90).contains($0) || (97...122).contains($0)
                            || (48...57).contains($0) || $0 == 46 || $0 == 45
                    }) { kind = .connect }
                }
                return Traffic(time: Int(pieces[0])!, identifier: String(pieces[1]), kind: kind, body: body)
            }
        end = traffic.last!.time
        for record in traffic { lineCounts[record.kind, default: 0] += 1 }
    }

    func integer(_ key: String) -> Int { Int(settings[key]!)! }
    var name: String { settings["NAME"]! }
    var activeClients: [Client] { clients.filter(\.active) }

    func send(_ client: Client, _ line: String) {
        sent.append("\(time) \(client.identifier) \(line)")
        client.sent += 1
    }

    func numeric(_ client: Client, _ number: Int, x: String = "", user: Client? = nil,
                 channel: Channel? = nil, text: String = "") {
        let content: String
        switch number {
        case 1: content = ":Welcome to the Internet Relay Network \(client.prefix)"
        case 2: content = ":Your host is \(name), running version \(settings["VERSION"]!)"
        case 3: content = ":This server was created \(settings["CREATED"]!)"
        case 4: content = "\(name) \(settings["VERSION"]!) i biklmnotv"
        case 5:
            content = "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=\(integer("NICKLEN")) "
                + "CHANNELLEN=\(integer("CHANNELLEN")) TOPICLEN=\(integer("TOPICLEN")) "
                + "CHANLIMIT=#:\(integer("MAXCHANNELS")) CHANMODES=b,k,l,imnt "
                + "PREFIX=(ov)@+ :are supported by this server"
        case 221: content = client.mode
        case 301: content = "\(user!.nickname!) :\(user!.away)"
        case 305: content = ":You are no longer marked as being away"
        case 306: content = ":You have been marked as being away"
        case 311: content = "\(user!.nickname!) \(user!.username!) \(user!.hostname) * :\(user!.realname)"
        case 312: content = "\(user!.nickname!) \(name) :\(settings["DESCRIPTION"]!)"
        case 317:
            content = "\(user!.nickname!) \(time - user!.lastSpeaking) \(user!.registrationTime!) "
                + ":seconds idle, signon time"
        case 318: content = "\(x) :End of /WHOIS list."
        case 319: content = "\(user!.nickname!) :\(joinedChannels(user!, separator: " "))"
        case 324: content = "\(channel!.name) \(channel!.modeDisplay(includeKey: channel!.member(client) != nil))"
        case 329: content = "\(channel!.name) \(channel!.created)"
        case 331: content = "\(channel!.name) :No topic is set"
        case 332: content = "\(channel!.name) :\(channel!.topic)"
        case 333: content = "\(channel!.name) \(channel!.topicSetter) \(channel!.topicTime)"
        case 341: content = "\(user!.nickname!) \(channel!.name)"
        case 353: content = "= \(channel!.name) :\(text)"
        case 366: content = "\(x) :End of /NAMES list."
        case 367: content = "\(channel!.name) \(text)"
        case 368: content = "\(channel!.name) :End of channel ban list"
        case 372: content = ":- \(text)"
        case 375: content = ":- \(name) Message of the day -"
        case 376: content = ":End of /MOTD command."
        case 401: content = "\(x) :No such nick/channel"
        case 403: content = "\(x) :No such channel"
        case 404: content = "\(channel!.name) :Cannot send to channel"
        case 405: content = "\(x) :You have joined too many channels"
        case 409: content = ":No origin specified"
        case 411: content = ":No recipient given (\(x))"
        case 412: content = ":No text to send"
        case 421: content = "\(x) :Unknown command"
        case 431: content = ":No nickname given"
        case 432: content = "\(x) :Erroneous nickname"
        case 433: content = "\(x) :Nickname is already in use"
        case 441: content = "\(user!.nickname!) \(channel!.name) :They aren't on that channel"
        case 442: content = "\(channel!.name) :You're not on that channel"
        case 443: content = "\(user!.nickname!) \(channel!.name) :is already on channel"
        case 451: content = ":You have not registered"
        case 461: content = "\(x) :Not enough parameters"
        case 462: content = ":You may not reregister"
        case 467: content = "\(channel!.name) :Channel key already set"
        case 471: content = "\(channel!.name) :Cannot join channel (+l)"
        case 472: content = "\(x) :is unknown mode char to me for \(channel!.name)"
        case 473: content = "\(channel!.name) :Cannot join channel (+i)"
        case 474: content = "\(channel!.name) :Cannot join channel (+b)"
        case 475: content = "\(channel!.name) :Cannot join channel (+k)"
        case 482: content = "\(channel!.name) :You're not channel operator"
        case 501: content = ":Unknown MODE flag"
        case 502: content = ":Cannot change mode for other users"
        default: preconditionFailure("Unspecified numeric")
        }
        numerics[number, default: 0] += 1
        send(client, ":\(name) \(String(format: "%03d", number)) \(client.addressee) \(content)")
    }

    func broadcast(_ channel: Channel, _ line: String, excluding: Client? = nil) {
        for member in channel.members where member.client !== excluding { send(member.client, line) }
    }

    func sendPeers(_ client: Client, _ line: String) {
        let peers = Set(client.channels.flatMap { $0.members.map { ObjectIdentifier($0.client) } })
        for other in activeClients where other !== client && peers.contains(ObjectIdentifier(other)) {
            send(other, line)
        }
    }

    func findUser(_ nickname: String) -> Client? {
        let folded = ircFold(nickname)
        return activeClients.first { $0.registered && ircFold($0.nickname!) == folded }
    }

    func findChannel(_ name: String) -> Channel? {
        let folded = ircFold(name)
        return channels.first { ircFold($0.name) == folded }
    }

    func joinedChannels(_ client: Client, separator: String) -> String {
        client.channels.map { $0.member(client)!.status + $0.name }.joined(separator: separator)
    }

    func removeMember(_ client: Client, _ channel: Channel) {
        channel.remove(client)
        if channel.members.isEmpty {
            channels.removeAll { $0 === channel }
            for other in activeClients { other.invites.removeAll { $0 === channel } }
        }
    }

    func disconnect(_ client: Client, reason: String, kind: String) {
        if kind != "closed" {
            send(client, "ERROR :Closing Link: \(client.addressee)[\(client.hostname)] (\(reason))")
            counts["errors", default: 0] += 1
        }
        if client.registered { sendPeers(client, ":\(client.prefix) QUIT :\(reason)") }
        for channel in client.channels { removeMember(client, channel) }
        counts["discarded", default: 0] += client.queue.count
        client.queue.removeAll()
        clientByID.removeValue(forKey: client.identifier)
        client.active = false
        gone.append((time, client.identifier, client.addressee, reason))
        disconnects[kind, default: 0] += 1
    }

    func completeRegistration(_ client: Client) {
        guard !client.registered, client.nickname != nil, client.username != nil else { return }
        client.registered = true
        client.registrationTime = time
        client.lastSpeaking = time
        let registered = activeClients.filter(\.registered).count
        if registered > peakRegistered.0 { peakRegistered = (registered, time) }
        for number in [1, 2, 3, 4, 5, 375] { numeric(client, number) }
        for line in motd { numeric(client, 372, text: line) }
        numeric(client, 376)
        if client.invisible { send(client, ":\(client.nickname!) MODE \(client.nickname!) :+i") }
    }

    func useToken(_ client: Client) {
        client.useToken(time: time, capacity: integer("BUCKET"), interval: integer("REFILL"))
    }

    func arrival(_ record: Traffic) {
        if record.kind == .connect {
            let client = Client(record.identifier, hostname: String(record.body.dropFirst(8)),
                                time: time, capacity: integer("BUCKET"))
            clients.append(client)
            clientByID[record.identifier] = client
            if clientByID.count > peakConnections.0 { peakConnections = (clientByID.count, time) }
            return
        }
        guard let client = clientByID[record.identifier] else {
            if record.kind == .messages { counts["dropped", default: 0] += 1 }
            return
        }
        if record.kind == .disconnect {
            disconnect(client, reason: "Remote host closed the connection", kind: "closed")
            return
        }
        client.received += 1
        client.lastReceived = time
        client.pingSent = nil
        if client.queue.isEmpty && client.tokens >= 1 {
            useToken(client)
            process(client, record.body)
        } else if client.queue.count >= integer("QUEUE") {
            counts["discarded", default: 0] += 1
            disconnect(client, reason: "Excess Flood", kind: "flood")
        } else {
            client.queue.append(record.body)
            counts["queued", default: 0] += 1
        }
    }

    func run() {
        var position = 0
        for currentTime in 0...end {
            time = currentTime
            for client in activeClients {
                client.refill(time: time, capacity: integer("BUCKET"), interval: integer("REFILL"))
                while client.active && !client.queue.isEmpty && client.tokens >= 1 {
                    useToken(client)
                    let raw = client.queue.removeFirst()
                    process(client, raw)
                }
            }
            while position < traffic.count && traffic[position].time == time {
                arrival(traffic[position])
                position += 1
            }
            for client in activeClients {
                if let pingTime = client.pingSent {
                    if time - pingTime >= integer("TIMEOUT") {
                        disconnect(client, reason: "Ping timeout: \(time - client.lastReceived) seconds", kind: "timeout")
                    }
                } else if time - client.lastReceived >= integer("PINGFREQ") {
                    send(client, "PING :\(name)")
                    counts["pings", default: 0] += 1
                    client.pingSent = time
                }
            }
        }
    }

    func require(_ client: Client, _ parameters: [String], _ count: Int, _ command: String) -> Bool {
        if parameters.count < count {
            numeric(client, 461, x: command)
            return false
        }
        return true
    }

    func process(_ client: Client, _ raw: String) {
        counts["processed", default: 0] += 1
        let (command, p) = parseMessage(raw)
        if command.isEmpty {
            counts["empty", default: 0] += 1
            return
        }
        commands[command, default: 0] += 1
        if !client.registered && !["NICK", "USER", "PING", "PONG", "QUIT"].contains(command) {
            numeric(client, 451)
            return
        }
        switch command {
        case "NICK": nick(client, p)
        case "USER":
            if client.username != nil { numeric(client, 462); return }
            guard require(client, p, 4, command) else { return }
            client.username = p[0]
            client.realname = p[3]
            client.invisible = digits(p[1]) && p[1].count <= 3 && (Int(p[1])! / 8) % 2 == 1
            completeRegistration(client)
        case "PING":
            if p.isEmpty || p[0].isEmpty { numeric(client, 409) }
            else { send(client, ":\(name) PONG \(name) :\(p[0])") }
        case "PONG": break
        case "QUIT":
            let reason = !p.isEmpty && !p[0].isEmpty ? "Quit: " + p[0] : "Client Quit"
            disconnect(client, reason: reason, kind: "quit")
        case "JOIN": join(client, p)
        case "PART": part(client, p)
        case "PRIVMSG", "NOTICE": message(client, p, command)
        case "TOPIC": topic(client, p)
        case "NAMES":
            if p.isEmpty { numeric(client, 366, x: "*"); return }
            for name in p[0].components(separatedBy: ",") {
                if let channel = findChannel(name) { namesReply(client, channel) }
                else { numeric(client, 366, x: name) }
            }
        case "WHOIS": whois(client, p)
        case "AWAY":
            client.away = p.first ?? ""
            numeric(client, client.away.isEmpty ? 305 : 306)
        case "INVITE": invite(client, p)
        case "KICK": kick(client, p)
        case "MODE":
            guard require(client, p, 1, command) else { return }
            if p[0].hasPrefix("#") { channelMode(client, p) } else { userMode(client, p) }
        default: numeric(client, 421, x: command)
        }
    }

    func nick(_ client: Client, _ p: [String]) {
        guard let first = p.first, !first.isEmpty else { numeric(client, 431); return }
        let nickname = String(first.prefix(integer("NICKLEN")))
        guard validNickname(nickname) else { numeric(client, 432, x: nickname); return }
        if nickname == client.nickname { return }
        let folded = ircFold(nickname)
        if activeClients.contains(where: { $0 !== client && $0.nickname.map { ircFold($0) == folded } == true }) {
            numeric(client, 433, x: nickname)
            return
        }
        if client.registered {
            let line = ":\(client.prefix) NICK :\(nickname)"
            send(client, line)
            sendPeers(client, line)
        }
        client.nickname = nickname
        completeRegistration(client)
    }

    func namesReply(_ client: Client, _ channel: Channel) {
        let names = channel.nameList(client)
        if !names.isEmpty { numeric(client, 353, channel: channel, text: names) }
        numeric(client, 366, x: channel.name)
    }

    func join(_ client: Client, _ p: [String]) {
        guard require(client, p, 1, "JOIN") else { return }
        if p[0] == "0" {
            for channel in client.channels {
                broadcast(channel, ":\(client.prefix) PART \(channel.name)")
                removeMember(client, channel)
            }
            return
        }
        let keys = p.count >= 2 ? p[1].components(separatedBy: ",") : []
        for (index, name) in p[0].components(separatedBy: ",").enumerated() {
            guard validChannel(name, maximum: integer("CHANNELLEN")) else {
                numeric(client, 403, x: name)
                continue
            }
            var channel = findChannel(name)
            if let channel, channel.member(client) != nil { continue }
            if client.channels.count >= integer("MAXCHANNELS") { numeric(client, 405, x: name); continue }
            if channel == nil {
                channel = Channel(name, time: time)
                channels.append(channel!)
            } else {
                let ch = channel!
                let invited = client.invites.contains { $0 === ch }
                let key = index < keys.count ? keys[index] : ""
                let failure: Int? = ch.banned(client) && !invited ? 474
                    : ch.flags.contains("i") && !invited ? 473
                    : !ch.key.isEmpty && key != ch.key ? 475
                    : ch.limit != 0 && ch.members.count >= ch.limit ? 471 : nil
                if let failure { numeric(client, failure, channel: ch); continue }
            }
            let ch = channel!
            client.invites.removeAll { $0 === ch }
            ch.add(client, isOperator: ch.members.isEmpty)
            broadcast(ch, ":\(client.prefix) JOIN \(ch.name)")
            if !ch.topic.isEmpty {
                numeric(client, 332, channel: ch)
                numeric(client, 333, channel: ch)
            }
            namesReply(client, ch)
        }
    }

    func part(_ client: Client, _ p: [String]) {
        guard require(client, p, 1, "PART") else { return }
        let suffix = p.count >= 2 && !p[1].isEmpty ? " :" + p[1] : ""
        for name in p[0].components(separatedBy: ",") {
            guard let ch = findChannel(name) else { numeric(client, 403, x: name); continue }
            guard ch.member(client) != nil else { numeric(client, 442, channel: ch); continue }
            broadcast(ch, ":\(client.prefix) PART \(ch.name)\(suffix)")
            removeMember(client, ch)
        }
    }

    func message(_ client: Client, _ p: [String], _ command: String) {
        let replies = command == "PRIVMSG"
        if replies { client.lastSpeaking = time }
        if p.isEmpty || p[0].isEmpty { if replies { numeric(client, 411, x: command) }; return }
        if p.count < 2 || p[1].isEmpty { if replies { numeric(client, 412) }; return }
        for target in p[0].components(separatedBy: ",") {
            if target.hasPrefix("#") {
                guard let ch = findChannel(target) else {
                    if replies { numeric(client, 401, x: target) }
                    continue
                }
                guard ch.canSpeak(client) else {
                    if replies { numeric(client, 404, channel: ch) }
                    continue
                }
                ch.messages += 1
                broadcast(ch, ":\(client.prefix) \(command) \(ch.name) :\(p[1])", excluding: client)
            } else {
                guard let user = findUser(target) else {
                    if replies { numeric(client, 401, x: target) }
                    continue
                }
                send(user, ":\(client.prefix) \(command) \(user.nickname!) :\(p[1])")
                if replies && !user.away.isEmpty { numeric(client, 301, user: user) }
            }
        }
    }

    func topic(_ client: Client, _ p: [String]) {
        guard require(client, p, 1, "TOPIC") else { return }
        guard let ch = findChannel(p[0]) else { numeric(client, 403, x: p[0]); return }
        guard let member = ch.member(client) else { numeric(client, 442, channel: ch); return }
        if p.count == 1 {
            numeric(client, ch.topic.isEmpty ? 331 : 332, channel: ch)
            if !ch.topic.isEmpty { numeric(client, 333, channel: ch) }
            return
        }
        if ch.flags.contains("t") && !member.isOperator { numeric(client, 482, channel: ch); return }
        ch.topic = String(p[1].prefix(integer("TOPICLEN")))
        ch.topicSetter = client.nickname!
        ch.topicTime = time
        broadcast(ch, ":\(client.prefix) TOPIC \(ch.name) :\(ch.topic)")
    }

    func whois(_ client: Client, _ p: [String]) {
        guard let first = p.first else { numeric(client, 431); return }
        guard let user = findUser(first) else {
            numeric(client, 401, x: first)
            numeric(client, 318, x: first)
            return
        }
        numeric(client, 311, user: user)
        if !user.channels.isEmpty { numeric(client, 319, user: user) }
        numeric(client, 312, user: user)
        if !user.away.isEmpty { numeric(client, 301, user: user) }
        numeric(client, 317, user: user)
        numeric(client, 318, x: user.nickname!)
    }

    func invite(_ client: Client, _ p: [String]) {
        guard require(client, p, 2, "INVITE") else { return }
        guard let user = findUser(p[0]) else { numeric(client, 401, x: p[0]); return }
        guard let ch = findChannel(p[1]) else { numeric(client, 403, x: p[1]); return }
        guard let member = ch.member(client) else { numeric(client, 442, channel: ch); return }
        if ch.member(user) != nil { numeric(client, 443, user: user, channel: ch); return }
        if ch.flags.contains("i") && !member.isOperator { numeric(client, 482, channel: ch); return }
        if !user.invites.contains(where: { $0 === ch }) { user.invites.append(ch) }
        numeric(client, 341, user: user, channel: ch)
        if !user.away.isEmpty { numeric(client, 301, user: user) }
        send(user, ":\(client.prefix) INVITE \(user.nickname!) :\(ch.name)")
    }

    func kick(_ client: Client, _ p: [String]) {
        guard require(client, p, 2, "KICK") else { return }
        guard let ch = findChannel(p[0]) else { numeric(client, 403, x: p[0]); return }
        guard let member = ch.member(client) else { numeric(client, 442, channel: ch); return }
        guard member.isOperator else { numeric(client, 482, channel: ch); return }
        guard let user = findUser(p[1]) else { numeric(client, 401, x: p[1]); return }
        guard ch.member(user) != nil else { numeric(client, 441, user: user, channel: ch); return }
        let reason = p.count >= 3 && !p[2].isEmpty ? p[2] : client.nickname!
        broadcast(ch, ":\(client.prefix) KICK \(ch.name) \(user.nickname!) :\(reason)")
        removeMember(user, ch)
    }

    func userMode(_ client: Client, _ p: [String]) {
        guard let user = findUser(p[0]) else { numeric(client, 401, x: p[0]); return }
        guard user === client else { numeric(client, 502); return }
        if p.count == 1 { numeric(client, 221); return }
        var sign: Character = "+", changes: [ModeItem] = [], unknown = false
        for character in p[1] {
            if character == "+" || character == "-" { sign = character }
            else if character == "i" {
                let desired = sign == "+"
                if client.invisible != desired {
                    client.invisible = desired
                    changes.append(ModeItem(sign: sign, character: character, argument: nil))
                }
            } else { unknown = true }
        }
        if !changes.isEmpty {
            send(client, ":\(client.nickname!) MODE \(client.nickname!) :\(changeString(changes))")
        }
        if unknown { numeric(client, 501) }
    }

    func channelMode(_ client: Client, _ p: [String]) {
        guard let ch = findChannel(p[0]) else { numeric(client, 403, x: p[0]); return }
        if p.count == 1 {
            numeric(client, 324, channel: ch)
            numeric(client, 329, channel: ch)
            return
        }
        let authorized = ch.member(client)?.isOperator ?? false
        var bansSent = false, denialSent = false, changes: [ModeItem] = []
        for item in channelItems(p[1], arguments: Array(p.dropFirst(2))) {
            let c = item.character, a = item.argument
            if !"biklmnotv".contains(c) {
                numeric(client, 472, x: String(c), channel: ch)
                continue
            }
            if c == "b" && a == nil {
                if item.sign == "+" && !bansSent {
                    for ban in ch.bans {
                        numeric(client, 367, channel: ch, text: "\(ban.mask) \(ban.setter) \(ban.time)")
                    }
                    numeric(client, 368, channel: ch)
                    bansSent = true
                }
                continue
            }
            if a == nil && ("ov".contains(c) || (item.sign == "+" && "kl".contains(c))) { continue }
            if !authorized {
                if !denialSent { numeric(client, 482, channel: ch); denialSent = true }
                continue
            }
            if let change = applyMode(client, ch, item) { changes.append(change) }
        }
        if !changes.isEmpty { broadcast(ch, ":\(client.prefix) MODE \(ch.name) \(changeString(changes))") }
    }

    func applyMode(_ client: Client, _ ch: Channel, _ item: ModeItem) -> ModeItem? {
        let c = item.character, adding = item.sign == "+"
        var changed = false, argument: String?
        switch c {
        case "o", "v":
            guard let user = findUser(item.argument!) else { numeric(client, 401, x: item.argument!); return nil }
            guard let member = ch.member(user) else { numeric(client, 441, user: user, channel: ch); return nil }
            if (c == "o" ? member.isOperator : member.voice) != adding {
                if c == "o" { member.isOperator = adding } else { member.voice = adding }
                changed = true
                argument = user.nickname!
            }
        case "b":
            let mask = normalizeMask(item.argument!), folded = ircFold(mask)
            let found = ch.bans.firstIndex { ircFold($0.mask) == folded }
            if adding && found == nil {
                ch.bans.append(Ban(mask: mask, setter: client.nickname!, time: time))
                changed = true
                argument = mask
            } else if !adding, let found {
                argument = ch.bans.remove(at: found).mask
                changed = true
            }
        case "k":
            if adding {
                if !ch.key.isEmpty { numeric(client, 467, channel: ch) }
                else { ch.key = item.argument!; changed = true; argument = item.argument }
            } else if !ch.key.isEmpty { ch.key = ""; changed = true; argument = "*" }
        case "l":
            if adding {
                let limit = Int(item.argument!)!
                if ch.limit != limit { ch.limit = limit; changed = true; argument = String(limit) }
            } else if ch.limit != 0 { ch.limit = 0; changed = true }
        default:
            if adding && !ch.flags.contains(c) { ch.flags.insert(c); changed = true }
            else if !adding && ch.flags.contains(c) { ch.flags.remove(c); changed = true }
        }
        return changed ? ModeItem(sign: item.sign, character: c, argument: argument) : nil
    }

    func channelReport() -> [String] {
        var lines: [String] = []
        for ch in channels {
            lines.append("CHANNEL \(ch.name) created \(ch.created) members \(ch.members.count) "
                + "peak \(ch.peak) messages \(ch.messages) modes \(ch.modeDisplay())")
            lines.append(ch.topic.isEmpty ? "TOPIC none" : "TOPIC \(ch.topicSetter) \(ch.topicTime) \(ch.topic)")
            for ban in ch.bans { lines.append("BAN \(ban.mask) \(ban.setter) \(ban.time)") }
            lines.append("MEMBERS " + ch.members.map(\.display).joined(separator: " "))
        }
        lines.append("TOTAL channels \(channels.count) members \(channels.reduce(0) { $0 + $1.members.count }) "
            + "bans \(channels.reduce(0) { $0 + $1.bans.count })")
        return lines
    }

    func clientReport() -> [String] {
        let clients = activeClients
        var lines: [String] = []
        for client in clients {
            let signon = client.registrationTime.map(String.init) ?? "-"
            let joined = client.channels.isEmpty ? "none" : joinedChannels(client, separator: ",")
            let invites = client.invites.isEmpty ? "none" : client.invites.map(\.name).joined(separator: ",")
            lines.append("CLIENT \(client.identifier) \(client.addressee) \(client.username ?? "*") "
                + "\(client.hostname) \(client.mode) connected \(client.connectionTime) signon \(signon) "
                + "received \(client.received) sent \(client.sent) tokens \(client.tokens) "
                + "queue \(client.queue.count) channels \(joined) invites \(invites)")
            if !client.away.isEmpty { lines.append("AWAY \(client.identifier) \(client.away)") }
        }
        lines.append("TOTAL clients \(clients.count) registered \(clients.filter(\.registered).count) "
            + "invisible \(clients.filter(\.invisible).count) away \(clients.filter { !$0.away.isEmpty }.count)")
        return lines
    }

    func statisticsReport() -> [String] {
        let pending = activeClients.reduce(0) { $0 + $1.queue.count }
        var lines = ["END \(end)",
            "LINES total \(traffic.count) connect \(lineCounts[.connect, default: 0]) "
                + "disconnect \(lineCounts[.disconnect, default: 0]) messages \(lineCounts[.messages, default: 0])",
            "MESSAGES dropped \(counts["dropped", default: 0]) queued \(counts["queued", default: 0]) "
                + "processed \(counts["processed", default: 0]) discarded \(counts["discarded", default: 0]) "
                + "pending \(pending) empty \(counts["empty", default: 0])",
            "SENT lines \(sent.count) numerics \(numerics.values.reduce(0, +)) "
                + "pings \(counts["pings", default: 0]) errors \(counts["errors", default: 0])"]
        for command in commands.keys.sorted() { lines.append("COMMAND \(command) \(commands[command]!)") }
        for number in numerics.keys.sorted() {
            lines.append("NUMERIC \(String(format: "%03d", number)) \(numerics[number]!)")
        }
        lines.append("PEAK connections \(peakConnections.0) at \(peakConnections.1)")
        lines.append("PEAK registered \(peakRegistered.0) at \(peakRegistered.1)")
        lines.append("DISCONNECTS " + ["quit", "closed", "flood", "timeout"].map {
            "\($0) \(disconnects[$0, default: 0])"
        }.joined(separator: " "))
        for (time, id, addressee, reason) in gone { lines.append("GONE \(time) \(id) \(addressee) \(reason)") }
        return lines
    }

    func writeOutputs() throws {
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        let outputs = [("sent.txt", sent), ("channels.txt", channelReport()),
                       ("clients.txt", clientReport()), ("stats.txt", statisticsReport())]
        for (filename, lines) in outputs {
            let text = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
            try text.write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
        }
    }
}

let server = try Server()
server.run()
try server.writeOutputs()
