import Foundation

struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

func integer(_ word: String, _ range: ClosedRange<Int>) throws -> Int {
    let bytes = Array(word.utf8)
    guard !bytes.isEmpty, bytes.count <= 10,
          bytes.count == 1 || bytes[0] != 48,
          bytes.allSatisfy({ (48...57).contains($0) }),
          let value = Int64(word), value >= Int64(range.lowerBound), value <= Int64(range.upperBound)
    else { throw CommandError("bad value \(word)") }
    return Int(value)
}

func signed(_ value: Int) -> String { (value >= 0 ? "+" : "") + String(value) }
func onOff(_ value: Bool) -> String { value ? "ON" : "OFF" }

func switchValue(_ word: String) throws -> Bool {
    guard word == "ON" || word == "OFF" else { throw CommandError("bad value \(word)") }
    return word == "ON"
}

struct Card {
    static let ranks = Array("A23456789TJQK")
    static let suits = Array("CDHS")
    let code: Int
    var rank: Int { code % 13 }
    var suit: Int { code / 13 }
    var points: Int { min(rank + 1, 10) }
    var isBlack: Bool { suit == 0 || suit == 3 }
    var text: String { String(Card.ranks[rank]) + String(Card.suits[suit]) }
}

func total(_ cards: [Card]) -> (value: Int, soft: Bool) {
    let sum = cards.reduce(0) { $0 + $1.points }
    let soft = cards.contains(where: { $0.rank == 0 }) && sum + 10 <= 21
    return (sum + (soft ? 10 : 0), soft)
}

func blackjack(_ cards: [Card], split: Bool = false) -> Bool {
    !split && cards.count == 2 && total(cards).value == 21
}

func handText(_ cards: [Card], split: Bool = false) -> String {
    let t = total(cards)
    let status: String
    if blackjack(cards, split: split) { status = "blackjack" }
    else if t.value > 21 { status = "bust \(t.value)" }
    else if t.soft { status = "soft \(t.value)" }
    else { status = String(t.value) }
    return cards.map(\.text).joined(separator: " ") + " (\(status))"
}

enum Phase: String { case idle, insurance, play }
enum Finish: String { case bust, surrender, charlie }
enum Outcome: String { case blackjack, win, charlie, push, lose, bust, surrender }
enum DealerRule: String { case s17 = "S17", h17 = "H17" }
enum Payout: String { case threeToTwo = "3:2", sixToFive = "6:5" }
enum DoubleRule: String { case any = "ANY", hard9 = "9-11", hard10 = "10-11" }
enum Action: String {
    case hit = "HIT", stand = "STAND", double = "DOUBLE", split = "SPLIT", surrender = "SURRENDER"
}

struct Rules {
    var dealer = DealerRule.s17
    var penetration = 75
    var minimum = 10
    var maximum = 500
    var payout = Payout.threeToTwo
    var doubleAfterSplit = true
    var doubling = DoubleRule.any
    var hands = 4
    var resplitAces = false
    var surrender = true
    var charlie = 0
    var sideMaximum = 25

    func changed(_ name: String, to word: String) throws -> Rules {
        var next = self
        switch name {
        case "DEALER":
            guard let value = DealerRule(rawValue: word) else { throw CommandError("bad value \(word)") }
            next.dealer = value
        case "PEN": next.penetration = try integer(word, 50...90)
        case "MIN": next.minimum = try integer(word, 1...10000)
        case "MAX": next.maximum = try integer(word, 1...10000)
        case "BJ":
            guard let value = Payout(rawValue: word) else { throw CommandError("bad value \(word)") }
            next.payout = value
        case "DAS": next.doubleAfterSplit = try switchValue(word)
        case "DOUBLE":
            guard let value = DoubleRule(rawValue: word) else { throw CommandError("bad value \(word)") }
            next.doubling = value
        case "HANDS": next.hands = try integer(word, 1...4)
        case "RSA": next.resplitAces = try switchValue(word)
        case "SURRENDER": next.surrender = try switchValue(word)
        case "CHARLIE":
            guard ["0", "5", "6", "7"].contains(word) else { throw CommandError("bad value \(word)") }
            next.charlie = Int(word)!
        case "SIDEMAX": next.sideMaximum = try integer(word, 0...1000)
        default: throw CommandError("unknown rule \(name)")
        }
        return next
    }

    var text: String {
        "rules DEALER \(dealer.rawValue) PEN \(penetration) MIN \(minimum) MAX \(maximum)"
            + " BJ \(payout.rawValue) DAS \(onOff(doubleAfterSplit)) DOUBLE \(doubling.rawValue)"
            + " HANDS \(hands) RSA \(onOff(resplitAces)) SURRENDER \(onOff(surrender))"
            + " CHARLIE \(charlie) SIDEMAX \(sideMaximum)"
    }
}

final class Hand {
    var cards: [Card]
    var bet: Int
    let split: Bool
    let splitAces: Bool
    var finished: Bool
    var reason: Finish?

    init(_ cards: [Card], bet: Int, split: Bool = false, splitAces: Bool = false) {
        self.cards = cards
        self.bet = bet
        self.split = split
        self.splitAces = splitAces
        finished = blackjack(cards, split: split)
    }

    var natural: Bool { blackjack(cards, split: split) }
    var text: String { handText(cards, split: split) }
}

struct Statistics {
    var rounds = 0, hands = 0, wins = 0, losses = 0, pushes = 0
    var blackjacks = 0, busts = 0, surrenders = 0, doubles = 0, splits = 0

    var text: String {
        "rounds \(rounds) hands \(hands) wins \(wins) losses \(losses) pushes \(pushes)"
            + " blackjacks \(blackjacks) busts \(busts) surrenders \(surrenders)"
            + " doubles \(doubles) splits \(splits)"
    }
}

final class Player {
    let name: String
    let seat: Int
    var bankroll: Int
    var bet = 0, side = 0, insurance = 0, net = 0
    var stats = Statistics()
    var hands: [Hand] = []

    init(name: String, seat: Int, bankroll: Int) {
        self.name = name
        self.seat = seat
        self.bankroll = bankroll
    }

    func handName(_ index: Int) -> String { "\(name)[\(index + 1)]" }
}

final class Table {
    static let commands: Set<String> = [
        "SHOE", "RULE", "RULES", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL", "INSURANCE",
        "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER", "HINT", "AUTO", "STATUS", "COUNT", "STATS"
    ]
    var rules = Rules()
    var seats: [Player?] = Array(repeating: nil, count: 7)
    var participants: [Player] = []
    var phase = Phase.idle
    var round = 0, dealerBlackjacks = 0, dealerBusts = 0
    var decks = 0, drawn = 0, running = 0
    var random: Int64 = 1
    var shoe: [Card] = []
    var dealer: [Card] = []
    var holeRevealed = false
    var insuranceTurn = 0
    var output: [String] = []

    var players: [Player] { seats.compactMap { $0 } }
    var cut: Int { shoe.count * rules.penetration / 100 }
    func emit(_ line: String) { output.append(line) }

    func player(named name: String) throws -> Player {
        guard let player = players.first(where: { $0.name == name }) else {
            throw CommandError("unknown player \(name)")
        }
        return player
    }

    func shuffle() {
        shoe = (0..<(52 * decks)).map { Card(code: $0 % 52) }
        for i in stride(from: shoe.count - 1, through: 1, by: -1) {
            random = random * 48271 % 2147483647
            shoe.swapAt(i, Int(random % Int64(i + 1)))
        }
        drawn = 0
        running = 0
    }

    func countCard(_ card: Card) {
        if (2...6).contains(card.points) { running += 1 }
        else if card.points == 1 || card.points == 10 { running -= 1 }
    }

    func draw(faceUp: Bool = true) -> Card {
        let card = shoe[drawn]
        drawn += 1
        if faceUp { countCard(card) }
        return card
    }

    func revealDealer() {
        if !holeRevealed {
            countCard(dealer[1])
            holeRevealed = true
        }
        emit("dealer: \(handText(dealer))")
    }

    func current() -> (player: Player, index: Int, hand: Hand)? {
        for player in participants {
            if let index = player.hands.firstIndex(where: { !$0.finished }) {
                return (player, index, player.hands[index])
            }
        }
        return nil
    }

    func finishCheck(_ hand: Hand, player: Player) {
        let value = total(hand.cards).value
        if value > 21 {
            hand.reason = .bust
            hand.finished = true
        } else if rules.charlie != 0 && hand.cards.count == rules.charlie {
            hand.reason = .charlie
            hand.finished = true
        } else if value == 21 {
            hand.finished = true
        } else if hand.splitAces && hand.cards.count == 2 {
            hand.finished = !(hand.cards.allSatisfy { $0.rank == 0 }
                && rules.resplitAces && player.hands.count < rules.hands)
        }
    }

    func settle(dealerNatural: Bool = false) {
        let dealerTotal = total(dealer).value
        for player in participants {
            for (index, hand) in player.hands.enumerated() {
                let result: Outcome
                if dealerNatural { result = hand.natural ? .push : .lose }
                else if hand.natural { result = .blackjack }
                else if let reason = hand.reason { result = Outcome(rawValue: reason.rawValue)! }
                else {
                    let value = total(hand.cards).value
                    result = dealerTotal > 21 || value > dealerTotal ? .win : value == dealerTotal ? .push : .lose
                }
                let profit: Int
                switch result {
                case .blackjack: profit = rules.payout == .threeToTwo ? hand.bet * 3 / 2 : hand.bet * 6 / 5
                case .win, .charlie: profit = hand.bet
                case .push: profit = 0
                case .surrender: profit = hand.bet / 2 - hand.bet
                case .lose, .bust: profit = -hand.bet
                }
                player.bankroll += hand.bet + profit
                player.net += profit
                player.stats.hands += 1
                if result == .blackjack || result == .win || result == .charlie { player.stats.wins += 1 }
                else if result == .push { player.stats.pushes += 1 }
                else { player.stats.losses += 1 }
                if result == .blackjack { player.stats.blackjacks += 1 }
                if result == .bust { player.stats.busts += 1 }
                if result == .surrender { player.stats.surrenders += 1 }
                emit("\(player.handName(index)) \(result.rawValue) \(signed(profit))")
            }
            emit("\(player.name) bankroll \(player.bankroll)")
        }
        for player in players {
            player.bet = 0
            player.side = 0
        }
        phase = .idle
    }

    func dealerTurn() {
        revealDealer()
        let mustPlay = participants.contains { player in
            player.hands.contains { $0.reason == nil && !$0.natural }
        }
        var drew = false
        if mustPlay {
            while true {
                let t = total(dealer)
                if !(t.value <= 16 || t.value == 17 && t.soft && rules.dealer == .h17) { break }
                let card = draw()
                dealer.append(card)
                drew = true
                emit("dealer hits: \(handText(dealer))")
            }
        }
        if drew && total(dealer).value > 21 { dealerBusts += 1 }
        settle()
    }

    func advance() {
        while let turn = current() {
            if turn.hand.cards.count != 1 { return }
            let card = draw()
            turn.hand.cards.append(card)
            emit("\(turn.player.handName(turn.index)): \(turn.hand.text)")
            finishCheck(turn.hand, player: turn.player)
            if !turn.hand.finished { return }
        }
        dealerTurn()
    }

    func peek() {
        let natural = blackjack(dealer)
        emit("dealer peeks: \(natural ? "blackjack" : "no blackjack")")
        for player in participants where player.insurance != 0 {
            let profit = player.insurance * (natural ? 2 : -1)
            player.bankroll += player.insurance + profit
            player.net += profit
            emit("\(player.name) insurance \(signed(profit))")
        }
        if natural {
            dealerBlackjacks += 1
            revealDealer()
            settle(dealerNatural: true)
        } else {
            phase = .play
            advance()
        }
    }

    func deal() {
        if drawn >= cut {
            shuffle()
            emit("shuffle")
        }
        round += 1
        emit("round \(round)")
        participants = players.filter { $0.bet != 0 }
        for player in participants {
            player.bankroll -= player.bet + player.side
            player.insurance = 0
            player.stats.rounds += 1
            player.hands = [Hand([draw()], bet: player.bet)]
        }
        dealer = [draw()]
        for player in participants {
            let hand = player.hands[0]
            let card = draw()
            hand.cards.append(card)
            hand.finished = hand.natural
        }
        let hole = draw(faceUp: false)
        dealer.append(hole)
        holeRevealed = false
        for player in participants { emit("\(player.handName(0)): \(player.hands[0].text)") }
        emit("dealer: \(dealer[0].text) ??")
        for player in participants where player.side != 0 {
            let cards = player.hands[0].cards
            let a = cards[0], b = cards[1]
            let result: String, multiplier: Int
            if a.rank != b.rank { result = "lose"; multiplier = -1 }
            else if a.suit == b.suit { result = "perfect"; multiplier = 25 }
            else if a.isBlack == b.isBlack { result = "colored"; multiplier = 12 }
            else { result = "mixed"; multiplier = 6 }
            let profit = player.side * multiplier
            player.bankroll += player.side + profit
            player.net += profit
            emit("\(player.name) side \(result) \(signed(profit))")
        }
        if dealer[0].points == 1 {
            phase = .insurance
            insuranceTurn = 0
            emit("insurance offered")
        } else if dealer[0].points == 10 { peek() }
        else {
            phase = .play
            advance()
        }
    }

    func actionError(_ action: Action, player: Player, hand: Hand) -> String? {
        switch action {
        case .hit:
            if hand.splitAces { return "split aces" }
        case .double:
            if hand.splitAces { return "split aces" }
            if hand.cards.count != 2 { return "two cards only" }
            let t = total(hand.cards)
            if rules.doubling != .any && (t.soft || t.value < (rules.doubling == .hard9 ? 9 : 10) || t.value > 11)
                || !rules.doubleAfterSplit && hand.split { return "double not allowed" }
            if player.bankroll < hand.bet { return "insufficient funds" }
        case .split:
            if hand.cards.count != 2 { return "two cards only" }
            if hand.cards[0].points != hand.cards[1].points { return "not a pair" }
            if player.hands.count >= rules.hands { return "hand limit" }
            if player.bankroll < hand.bet { return "insufficient funds" }
        case .surrender:
            if !rules.surrender || hand.split { return "surrender not allowed" }
            if hand.cards.count != 2 { return "two cards only" }
        case .stand: break
        }
        return nil
    }

    func perform(_ action: Action) {
        let turn = current()!
        let player = turn.player, hand = turn.hand
        let name = player.handName(turn.index)
        switch action {
        case .split:
            let first = hand.cards[0], second = hand.cards[1]
            let aces = hand.splitAces || first.points == 1
            player.bankroll -= hand.bet
            player.stats.splits += 1
            emit("\(name) splits \(first.text) \(second.text)")
            let replacement = Hand([first], bet: hand.bet, split: true, splitAces: aces)
            player.hands[turn.index] = replacement
            player.hands.insert(Hand([second], bet: hand.bet, split: true, splitAces: aces), at: turn.index + 1)
            let card = draw()
            replacement.cards.append(card)
            emit("\(name): \(replacement.text)")
            finishCheck(replacement, player: player)
        case .stand, .surrender:
            hand.finished = true
            if action == .surrender { hand.reason = .surrender }
            emit("\(name) \(action == .stand ? "stands" : "surrenders"): \(hand.text)")
        case .hit, .double:
            if action == .double {
                player.bankroll -= hand.bet
                hand.bet *= 2
                player.stats.doubles += 1
            }
            let card = draw()
            hand.cards.append(card)
            emit("\(name) \(action == .double ? "doubles" : "hits"): \(hand.text)")
            finishCheck(hand, player: player)
            if action == .double { hand.finished = true }
        }
        advance()
    }

    func recommend() -> Action {
        let turn = current()!
        let player = turn.player, hand = turn.hand
        func possible(_ action: Action) -> Bool { actionError(action, player: player, hand: hand) == nil }
        let u = dealer[0].points == 1 ? 11 : dealer[0].points
        if hand.splitAces { return possible(.split) ? .split : .stand }
        if hand.cards.count == 2 && hand.cards[0].points == hand.cards[1].points && possible(.split) {
            let v = hand.cards[0].points
            if v == 1 || v == 8 || v == 9 && ![7, 10, 11].contains(u)
                || [2, 3, 7].contains(v) && u <= 7 || v == 6 && u <= 6 || v == 4 && (u == 5 || u == 6) {
                return .split
            }
        }
        let t = total(hand.cards)
        enum Symbol { case h, s, d, ds, r }
        var symbol = Symbol.h
        if t.soft {
            if t.value >= 19 { symbol = .s }
            else if t.value == 18 { symbol = (3...6).contains(u) ? .ds : [2, 7, 8].contains(u) ? .s : .h }
            else if t.value == 17 && (3...6).contains(u)
                || [15, 16].contains(t.value) && (4...6).contains(u)
                || [13, 14].contains(t.value) && [5, 6].contains(u) { symbol = .d }
        } else {
            if t.value >= 17 { symbol = .s }
            else if t.value >= 13 {
                symbol = u <= 6 ? .s : t.value == 16 && u >= 9 || t.value == 15 && u == 10 ? .r : .h
            } else if t.value == 12 { symbol = (4...6).contains(u) ? .s : .h }
            else if t.value == 11 && u <= 10 || t.value == 10 && u <= 9 || t.value == 9 && (3...6).contains(u) {
                symbol = .d
            }
        }
        switch symbol {
        case .s: return .stand
        case .h: return .hit
        case .d: return possible(.double) ? .double : .hit
        case .ds: return possible(.double) ? .double : .stand
        case .r: return possible(.surrender) ? .surrender : .hit
        }
    }

    func status() {
        var line = "table \(phase.rawValue) round \(round)"
        if phase == .insurance { line += " next \(participants[insuranceTurn].name)" }
        else if phase == .play {
            let turn = current()!
            line += " turn \(turn.player.handName(turn.index))"
        }
        emit(line)
        if phase != .idle { emit("dealer: \(dealer[0].text) ??") }
        for player in players {
            emit("seat \(player.seat) \(player.name) bankroll \(player.bankroll) bet \(player.bet) side \(player.side)")
            if phase != .idle && participants.contains(where: { $0 === player }) {
                for (index, hand) in player.hands.enumerated() {
                    emit("\(player.handName(index)): \(hand.text) bet \(hand.bet)")
                }
            }
        }
    }

    func command(_ line: String) throws {
        let words = line.split(separator: " ").map(String.init)
        let command = words[0]
        guard Table.commands.contains(command) else { throw CommandError("unknown command \(command)") }
        let first = words.count > 1 ? words[1] : ""
        let second = words.count > 2 ? words[2] : ""
        let action = Action(rawValue: command)
        var target: Player?
        var value = 0
        var seed: Int64 = 1
        var proposedRules: Rules?

        // Validate arguments in their written order before inspecting the phase.
        if command == "SHOE" {
            value = try integer(first, 1...8)
            seed = Int64(try integer(second, 1...2147483646))
        } else if command == "RULE" { proposedRules = try rules.changed(first, to: second) }
        else if command == "PLAYER" {
            let bytes = Array(first.utf8)
            guard (1...8).contains(bytes.count), bytes.allSatisfy({ (65...90).contains($0) }) else {
                throw CommandError("bad name \(first)")
            }
            value = try integer(second, 1...1000000)
        } else if action != nil || ["LEAVE", "REBUY", "BET", "SIDE", "INSURANCE", "AUTO"].contains(command) {
            target = try player(named: first)
            if ["REBUY", "BET", "SIDE", "INSURANCE"].contains(command) {
                value = try integer(second, (command == "REBUY" ? 1 : 0)...1000000)
            }
        }
        if ["SHOE", "RULE", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL"].contains(command) {
            guard phase == .idle else { throw CommandError("round in progress") }
        } else if command == "INSURANCE" {
            guard phase == .insurance else { throw CommandError("no insurance") }
        } else if action != nil || command == "AUTO" || command == "HINT" {
            if phase == .idle { throw CommandError("no round") }
            if phase == .insurance { throw CommandError("insurance pending") }
        }

        if action != nil || command == "AUTO" {
            let turn = current()!, player = target!
            guard turn.player === player else { throw CommandError("waiting for \(turn.player.handName(turn.index))") }
            if let action {
                if let error = actionError(action, player: player, hand: turn.hand) { throw CommandError(error) }
                perform(action)
            } else {
                while phase == .play && current()!.player === player { perform(recommend()) }
            }
            return
        }
        switch command {
        case "SHOE":
            decks = value
            random = seed
            shuffle()
            emit("shoe \(decks) decks \(shoe.count) cards cut \(cut)")
        case "RULE":
            let next = proposedRules!
            guard next.minimum <= next.maximum else { throw CommandError("min above max") }
            rules = next
            emit("rule \(first) \(second)")
        case "RULES": emit(rules.text)
        case "PLAYER":
            if players.contains(where: { $0.name == first }) { throw CommandError("player exists") }
            guard let seat = seats.firstIndex(where: { $0 == nil }) else { throw CommandError("table full") }
            seats[seat] = Player(name: first, seat: seat + 1, bankroll: value)
            emit("\(first) sits at seat \(seat + 1) with \(value)")
        case "LEAVE":
            let player = target!
            emit("\(player.name) leaves with \(player.bankroll) net \(signed(player.net))")
            seats[player.seat - 1] = nil
        case "REBUY":
            let player = target!
            player.bankroll += value
            emit("\(player.name) rebuys \(value) bankroll \(player.bankroll)")
        case "BET":
            let player = target!
            if value != 0 {
                guard (rules.minimum...rules.maximum).contains(value) else { throw CommandError("bet out of limits") }
                guard value + player.side <= player.bankroll else { throw CommandError("insufficient funds") }
            }
            player.bet = value
            if value == 0 { player.side = 0 }
            emit(value == 0 ? "\(player.name) bet cleared" : "\(player.name) bets \(value)")
        case "SIDE":
            let player = target!
            if value != 0 {
                if player.bet == 0 { throw CommandError("no bet") }
                if value > rules.sideMaximum { throw CommandError("side out of limits") }
                if player.bet + value > player.bankroll { throw CommandError("insufficient funds") }
            }
            player.side = value
            emit(value == 0 ? "\(player.name) side cleared" : "\(player.name) side \(value)")
        case "DEAL":
            if decks == 0 { throw CommandError("no shoe") }
            guard players.contains(where: { $0.bet != 0 }) else { throw CommandError("no bets") }
            deal()
        case "INSURANCE":
            let player = target!
            guard participants[insuranceTurn] === player else {
                throw CommandError("waiting for \(participants[insuranceTurn].name)")
            }
            if value > player.bet / 2 { throw CommandError("insurance out of limits") }
            if value > player.bankroll { throw CommandError("insufficient funds") }
            player.bankroll -= value
            player.insurance = value
            emit(value == 0 ? "\(player.name) declines insurance" : "\(player.name) insures \(value)")
            insuranceTurn += 1
            if insuranceTurn == participants.count { peek() }
        case "HINT":
            let turn = current()!
            emit("hint \(turn.player.handName(turn.index)): \(recommend().rawValue.lowercased())")
        case "STATUS": status()
        case "COUNT":
            if decks == 0 { throw CommandError("no shoe") }
            let remaining = shoe.count - drawn
            let hundredths = abs(running) * 5200 / remaining
            let fraction = String(hundredths % 100)
            let count = (running < 0 ? "-" : "") + String(hundredths / 100)
                + "." + (fraction.count == 1 ? "0" : "") + fraction
            emit("count running \(running) true \(count) remaining \(remaining)")
        case "STATS":
            if players.isEmpty { throw CommandError("no players") }
            for player in players { emit("stats \(player.name) \(player.stats.text) net \(signed(player.net))") }
            emit("stats dealer rounds \(round) blackjacks \(dealerBlackjacks) busts \(dealerBusts)")
        default: break
        }
    }
}

let commandCount = Int(readLine()!)!
let table = Table()
for _ in 0..<commandCount {
    do {
        try table.command(readLine()!)
    } catch let error as CommandError {
        table.emit("error: \(error.message)")
    } catch {
        fatalError("Unexpected error: \(error)")
    }
}
FileHandle.standardOutput.write(Data((table.output.joined(separator: "\n") + "\n").utf8))
