struct Failure: Error { let rows: [String] }
func fail(_ message: String) throws -> Never {
    throw Failure(rows: [message])
}
func fail(_ rows: [String]) throws -> Never {
    throw Failure(rows: rows)
}
func words(_ line: String) -> [String] {
    line.split(separator: " ").map(String.init)
}
func normalized(_ line: String) -> [String] {
    words(line.lowercased()).filter { !["the", "a", "an"].contains($0) }
}
enum Direction: String, CaseIterable, Hashable {
    case north, south, east, west, up, down
    static func parse(_ word: String) -> Direction? {
        allCases
            .first { $0.rawValue == word || String($0.rawValue.prefix(1)) == word }
    }
    var opposite: Direction {
        Self.allCases[Self.allCases.firstIndex(of: self)! ^ 1]
    }
}
enum Verb: String, Hashable {
    case go, look, examine, take, drop, put, inventory, openContainer = "open", closeContainer = "close"
    case unlock, lock, use, light, extinguish, wait, score, save, restore, verbose, brief
}
let verbWords: [String: Verb] = Dictionary(uniqueKeysWithValues: [
    (Verb.go, "go walk run"), (.look, "look l"), (.examine, "examine x inspect read"), (.take, "take get grab"),
    (.drop, "drop discard"), (.put, "put insert place"), (.inventory, "inventory inv i"), (.openContainer, "open"),
    (.closeContainer, "close shut"), (.unlock, "unlock"), (.lock, "lock"), (.use, "use apply"), (
        .light,
        "light ignite"
    ),
    (.extinguish, "extinguish douse snuff"), (.wait, "wait z"), (.score, "score"), (.save, "save"),
    (.restore, "restore load"), (.verbose, "verbose"), (.brief, "brief")
].flatMap { verb, synonyms in words(synonyms).map { ($0, verb) } })
let noObjects: Set<Verb> = [.look, .inventory, .wait, .score, .save, .restore, .verbose, .brief]
let actions: Set<Verb> = [
    .go,
    .take,
    .drop,
    .put,
    .openContainer,
    .closeContainer,
    .unlock,
    .lock,
    .use,
    .light,
    .extinguish,
    .wait
]

enum Place: Hashable { case room(String), player, inside(String), nowhere }
enum ContainerState: String { case open, closed, locked }
enum EndState { case none, won, dead }
struct Room { let name: String
    let dark: Bool
    var description = [String]()
}
struct Item {
    let id: String
    let weight: Int
    var name = ""
    var points = 0
    var light = false
    var fixed = false
    var capacity: Int?
    var key: String?
    var nouns: Set<String>
    var adjectives = Set<String>()
    var details = [String]()
}
struct ItemState { var place: Place
    var container = ContainerState.open
    var lit = false
    var fuel = 0
}
struct Exit { let destination: String
    let key: String?
    var locked: Bool
}
enum Effect {
    case message(String), openExit(String, Direction, String), removeItem(String), addItem(String, String)
    case setFlag(String, Bool), addPoints(Int)
}
struct Condition { let flag: String
    let on: Bool
}
struct Rule { let first, second: String
    let condition: Condition?
    let effect: Effect
}
struct GameState {
    var room = ""
    var items = [String: ItemState]()
    var exits = [String: [Direction: Exit]]()
    var flags = Set<String>()
    var visited = Set<String>()
    var bonus = 0
    var moves = 0
    var darkness = 0
    var ended = EndState.none
}
struct Score { var stored = 0
    var treasures = 0
    var points = 0
    var total = 0
}

final class Adventure {
    private var rooms = [String: Room]()
    private var items = [String: Item]()
    private var ids = [String]()
    private var rules = [Rule](), enterRules = [Rule]()
    private var vocabulary = Set<String>()
    private var trophy = "", maxWeight = 0
    private var state = GameState()
    private var saved: GameState?
    private var pronoun: String?, previous: String?
    private var verbose = false

    init(_ definitions: [String]) {
        for line in definitions {
            define(line)
        }
        state.visited.insert(state.room)
        ids = items.keys.sorted()
        for item in items.values {
            vocabulary.formUnion(item.nouns)
            vocabulary.formUnion(item.adjectives)
        }
    }
    private func setExit(_ room: String, _ direction: Direction, _ destination: String, key: String? = nil) {
        state.exits[room, default: [:]][direction] = Exit(destination: destination, key: key, locked: key != nil)
    }
    private func define(_ line: String) {
        let parts = words(line), kind = parts[0], id = parts[1]
        func text(_ index: Int) -> String {
            parts[index...].joined(separator: " ")
        }
        switch kind {
        case "ROOM":
            let dark = parts[2] == "DARK"
            rooms[id] = Room(name: text(dark ? 3 : 2), dark: dark)
        case "DESC":
            rooms[id]!.description.append(text(2))
        case "EXIT":
            setExit(id, Direction.parse(parts[2])!, parts[3], key: parts.count > 4 ? parts[5] : nil)
        case "ITEM":
            var item = Item(id: id, weight: Int(parts[3])!, nouns: [id])
            var value =
                ItemState(place: parts[2] == "PLAYER" ? .player : parts[2] == "NOWHERE" ? .nowhere : .room(parts[2]))
            var index = 4
            if parts[index] == "TREASURE" {
                item.points = Int(parts[index + 1])!
                index += 2
            }
            if parts[index] == "LIGHT" {
                item.light = true
                value.fuel = Int(parts[index + 1])!
                index += 2
            }
            if parts[index] == "CONTAINER" {
                item.capacity = Int(parts[index + 1])!
                index += 2
                if parts[index] == "CLOSED" {
                    value.container = .closed
                    index += 1
                }
                if parts[index] == "LOCKED" {
                    item.key = parts[index + 1]
                    value.container = .locked
                    index += 2
                }
            }
            if parts[index] == "FIXED" {
                item.fixed = true
                index += 1
            }
            item.name = text(index)
            item.adjectives = Set(parts[index...])
            items[id] = item
            state.items[id] = value
        case "INSIDE":
            state.items[id]!.place = .inside(parts[2])
        case "ALIAS":
            items[id]!.nouns.insert(parts[2])
        case "DETAIL":
            items[id]!.details.append(text(2))
        case "RULE", "ENTER":
            var index = kind == "RULE" ? 3 : 2
            var condition: Condition?
            if parts[index] == "IF" || parts[index] == "UNLESS" {
                condition = Condition(flag: parts[index + 1], on: parts[index] == "IF")
                index += 2
            }
            let name = parts[index]
            index += 1
            let effect: Effect
            switch name {
            case "MESSAGE":
                effect = .message(text(index))
            case "OPEN":
                effect = .openExit(parts[index], Direction.parse(parts[index + 1])!, parts[index + 2])
            case "REMOVE":
                effect = .removeItem(parts[index])
            case "ADD":
                effect = .addItem(parts[index], parts[index + 1])
            case "SET", "CLEAR":
                effect = .setFlag(parts[index], name == "SET")
            default:
                effect = .addPoints(Int(parts[index])!)
            }
            let rule = Rule(first: id, second: kind == "RULE" ? parts[2] : "", condition: condition, effect: effect)
            if kind == "RULE" {
                rules.append(rule)
            } else {
                enterRules.append(rule)
            }
        case "TROPHY":
            trophy = id
        case "START":
            state.room = id
        case "MAXWEIGHT":
            maxWeight = Int(id)!
        default:
            break
        }
    }
    private func contents(_ place: Place) -> [String] {
        ids.filter { state.items[$0]!.place == place }
    }
    private func children() -> [Place: [String]] {
        var result = [Place: [String]]()
        for id in ids {
            result[state.items[id]!.place, default: []].append(id)
        }
        return result
    }
    private func isOpen(_ id: String) -> Bool {
        items[id]!.capacity != nil && state.items[id]!.container == .open
    }
    private func reachable(_ place: Place) -> Set<String> {
        let grouped = children()
        var result = Set<String>()
        func visit(_ place: Place) {
            for id in grouped[place, default: []] {
                result.insert(id)
                if isOpen(id) {
                    visit(.inside(id))
                }
            }
        }
        visit(place)
        return result
    }
    private func carried() -> Set<String> {
        reachable(.player)
    }
    private func roomItems() -> Set<String> {
        reachable(.room(state.room))
    }
    private func isLit() -> Bool {
        !rooms[state.room]!.dark || carried().union(roomItems())
            .contains { state.items[$0]!.lit }
    }
    private func visible() -> Set<String> {
        isLit() ? carried().union(roomItems()) : carried()
    }
    private func weights() -> [String: Int] {
        let grouped = children()
        var result = [String: Int]()
        func total(_ id: String) -> Int {
            if let weight = result[id] {
                return weight
            }
            let weight = items[id]!.weight + grouped[.inside(id), default: []].reduce(0) { $0 + total($1) }
            result[id] = weight
            return weight
        }
        for id in ids {
            _ = total(id)
        }
        return result
    }
    private func totalWeight(_ id: String) -> Int {
        weights()[id]!
    }
    private func contentWeight(_ id: String) -> Int {
        totalWeight(id) - items[id]!.weight
    }
    private func carriedWeight() -> Int {
        let totals = weights()
        return contents(.player).reduce(0) { $0 + totals[$1]! }
    }
    private func nestedIn(_ id: String, _ ancestor: String) -> Bool {
        var place = state.items[id]!.place
        while case .inside(let parent) = place {
            if parent == ancestor {
                return true
            }
            place = state.items[parent]!.place
        }
        return false
    }
    private func score() -> Score {
        var result = Score()
        for id in ids where items[id]!.points > 0 {
            result.treasures += 1
            var place = state.items[id]!.place
            while case .inside(let parent) = place {
                place = state.items[parent]!.place
            }
            if place == .room(trophy) {
                result.stored += 1
                result.points += items[id]!.points
            }
        }
        result.total = result.points + state.bonus
        return result
    }
    private func display(_ id: String) -> String {
        let item = items[id]!, value = state.items[id]!
        var annotations = [String]()
        if item.capacity != nil {
            annotations.append(value.container.rawValue)
        }
        if item.light && value.lit {
            annotations.append("lit")
        }
        return item.name + (annotations.isEmpty ? "" : " (" + annotations.joined(separator: ", ") + ")")
    }
    private func tree(_ place: Place) -> [String] {
        let grouped = children()
        var rows = [String]()
        func visit(_ place: Place, depth: Int) {
            for id in grouped[place, default: []] {
                rows.append(String(repeating: "  ", count: depth) + display(id))
                if isOpen(id) {
                    visit(.inside(id), depth: depth + 1)
                }
            }
        }
        visit(place, depth: 1)
        return rows
    }
    func describe(full: Bool = true) -> [String] {
        guard isLit() else {
            return ["It is pitch dark."]
        }
        let room = rooms[state.room]!, exits = state.exits[state.room, default: [:]]
        let names = Direction.allCases.compactMap { direction -> String? in
            guard let exit = exits[direction] else {
                return nil
            }
            return direction.rawValue + (exit.locked ? " (locked)" : "")
        }
        var rows = [room.name] + (full ? room.description : [])
        rows.append("Exits: " + (names.isEmpty ? "none" : names.joined(separator: ", ")))
        if !contents(.room(state.room)).isEmpty {
            rows += ["You see:"] + tree(.room(state.room))
        }
        return rows
    }
    private func resolve(_ phrase: [String]) throws -> String {
        let available = visible()
        if phrase == ["it"] {
            guard let pronoun else {
                try fail("I don't know what \"it\" refers to.")
            }
            guard available.contains(pronoun) else {
                try fail("You can't see any such thing.")
            }
            return pronoun
        }
        for word in phrase where !vocabulary.contains(word) {
            try fail("I don't know the word \"\(word)\".")
        }
        let matches = ids.filter { id in
            let item = items[id]!
            return available.contains(id) && item.nouns.contains(phrase.last!) && phrase.dropLast()
                .allSatisfy { item.adjectives.contains($0) }
        }
        guard !matches.isEmpty else {
            try fail("You can't see any such thing.")
        }
        guard matches.count == 1
        else {
            try fail("Which do you mean: " + matches.map { items[$0]!.name }.joined(separator: ", ") + "?")
        }
        pronoun = matches[0]
        return matches[0]
    }
    private func runRules(_ rules: [Rule], first: String, second: String = "") -> (rows: [String], executed: Int) {
        var rows = [String](), executed = 0
        for rule in rules where rule.first == first && rule.second == second {
            if let condition = rule.condition, state.flags.contains(condition.flag) != condition.on {
                continue
            }
            executed += 1
            switch rule.effect {
            case .message(let text):
                rows.append(text)
            case .openExit(let room, let direction, let destination):
                setExit(room, direction, destination)
            case .removeItem(let id):
                state.items[id]!.place = .nowhere
            case .addItem(let id, let room):
                state.items[id]!.place = .room(room)
            case .setFlag(let id, let on):
                if on { state.flags.insert(id) } else { state.flags.remove(id) }
            case .addPoints(let amount):
                state.bonus += amount
            }
        }
        return (rows, executed)
    }
    private func requireContainer(_ id: String) throws {
        guard items[id]!.capacity != nil else {
            try fail("The \(items[id]!.name) is not a container.")
        }
        guard isOpen(id) else {
            try fail("The \(items[id]!.name) is closed.")
        }
    }
    private func take(_ first: [String], _ second: [String]?) throws -> [String] {
        guard isLit() else {
            try fail("It is pitch dark.")
        }
        var container: String?, source = Place.room(state.room)
        if let second {
            let target = try resolve(second)
            try requireContainer(target)
            container = target
            source = .inside(target)
        }
        if first == ["all"] {
            let candidates = contents(source).filter { !items[$0]!.fixed }
            guard !candidates.isEmpty else {
                try fail(container == nil ? "There is nothing here to take." :
                    "There is nothing in the \(items[container!]!.name) to take.")
            }
            var rows = [String](), taken = false
            for id in candidates {
                var outcome = "You can't carry any more."
                if carried().contains(id) || carriedWeight() + totalWeight(id) <= maxWeight {
                    state.items[id]!.place = .player
                    outcome = "Taken."
                    taken = true
                }
                rows.append("\(items[id]!.name): \(outcome)")
            }
            guard taken else {
                try fail(rows)
            }
            return rows
        }
        let id = try resolve(first), item = items[id]!, value = state.items[id]!
        if let container,
           value.place != source
        {
            try fail("The \(item.name) is not in the \(items[container]!.name).")
        }
        guard value.place != .player else {
            try fail("You already have the \(item.name).")
        }
        guard !item.fixed else {
            try fail("The \(item.name) is fixed in place.")
        }
        guard carried().contains(id) || carriedWeight() + totalWeight(id) <= maxWeight
        else {
            try fail("You can't carry any more.")
        }
        state.items[id]!.place = .player
        return ["Taken."]
    }
    private func drop(_ phrase: [String]) throws -> [String] {
        if phrase == ["all"] {
            let candidates = contents(.player)
            guard !candidates.isEmpty else {
                try fail("You are empty-handed.")
            }
            return candidates.map { id in
                state.items[id]!.place = .room(state.room)
                return "\(items[id]!.name): Dropped."
            }
        }
        let id = try resolve(phrase)
        guard carried().contains(id) else {
            try fail("You aren't carrying the \(items[id]!.name).")
        }
        state.items[id]!.place = .room(state.room)
        return ["Dropped."]
    }
    private func putItem(_ id: String, _ container: String) -> String? {
        let item = items[id]!, target = items[container]!
        if nestedIn(container, id) {
            return "The \(target.name) is inside the \(item.name)."
        }
        if state.items[id]!.place == .inside(container) {
            return "The \(item.name) is already in the \(target.name)."
        }
        let weight = contentWeight(container) + (nestedIn(id, container) ? 0 : totalWeight(id))
        if weight > target.capacity! {
            return "The \(item.name) doesn't fit in the \(target.name)."
        }
        state.items[id]!.place = .inside(container)
        return nil
    }
    private func put(_ first: [String], _ second: [String]) throws -> [String] {
        if first == ["all"] {
            let target = try resolve(second)
            try requireContainer(target)
            let candidates = contents(.player).filter { $0 != target }
            guard !candidates.isEmpty else {
                try fail("You have nothing to put in the \(items[target]!.name).")
            }
            var rows = [String](), succeeded = false
            for id in candidates {
                let reason = putItem(id, target)
                if reason == nil {
                    succeeded = true
                }
                rows.append("\(items[id]!.name): \(reason ?? "Done.")")
            }
            guard succeeded else {
                try fail(rows)
            }
            return rows
        }
        let id = try resolve(first)
        let target = try resolve(second), item = items[id]!
        guard carried().contains(id) else {
            try fail("You aren't carrying the \(item.name).")
        }
        guard id != target else {
            try fail("You can't put the \(item.name) inside itself.")
        }
        try requireContainer(target)
        if let reason = putItem(id, target) {
            try fail(reason)
        }
        return ["You put the \(item.name) in the \(items[target]!.name)."]
    }
    private func keyCheck(_ key: String, _ phrase: [String]?) throws -> [String] {
        if let phrase {
            let id = try resolve(phrase), name = items[id]!.name
            guard carried().contains(id) else {
                try fail("You aren't carrying the \(name).")
            }
            guard id == key else {
                try fail("The \(name) doesn't fit.")
            }
            return []
        }
        guard carried().contains(key) else {
            try fail("You don't have the right key.")
        }
        return ["(with the \(items[key]!.name))"]
    }
    private func lock(_ first: [String], _ second: [String]?, locking: Bool) throws -> [String] {
        if first.count == 1, let direction = Direction.parse(first[0]) {
            let room = state.room, name = direction.rawValue
            guard var exit = state.exits[room]?[direction] else {
                try fail("There is no exit \(name).")
            }
            guard let key = exit.key else {
                try fail("The way \(name) has no lock.")
            }
            guard exit.locked != locking
            else {
                try fail("The way \(name) is \(locking ? "already locked" : "not locked").")
            }
            let rows = try keyCheck(key, second)
            exit.locked = locking
            state.exits[room]![direction] = exit
            if var back = state.exits[exit.destination]?[direction.opposite], back.destination == room,
               back.key == key
            {
                back.locked = locking
                state.exits[exit.destination]![direction.opposite] = back
            }
            return rows + [locking ? "Locked." : "Unlocked."]
        }
        let id = try resolve(first), item = items[id]!, value = state.items[id]!
        guard item.capacity != nil, let key = item.key else {
            try fail("The \(item.name) has no lock.")
        }
        guard (value.container == .locked) != locking
        else {
            try fail("The \(item.name) is \(locking ? "already locked" : "not locked").")
        }
        guard !locking || value.container != .open else {
            try fail("You must close the \(item.name) first.")
        }
        let rows = try keyCheck(key, second)
        state.items[id]!.container = locking ? .locked : .closed
        return rows + [locking ? "Locked." : "Unlocked."]
    }
    private func execute(_ verb: Verb, _ first: [String], _ second: [String]?) throws -> [String] {
        switch verb {
        case .look:
            return describe()
        case .inventory:
            if contents(.player).isEmpty {
                return ["You are empty-handed."]
            }
            return ["You are carrying:"] + tree(.player) + ["Total weight: \(carriedWeight())/\(maxWeight)"]
        case .wait:
            return ["Time passes."]
        case .score:
            let value = score()
            return [
                "You have scored \(value.total) points (treasure \(value.points), bonus \(state.bonus)) in \(state.moves) moves.",
                "Treasures stored: \(value.stored) of \(value.treasures)."
            ]
        case .save:
            saved = state
            return ["Game saved."]
        case .restore:
            guard let saved else {
                try fail("There is no saved game.")
            }
            state = saved
            return ["Game restored."] + describe()
        case .verbose:
            verbose = true
            return ["Verbose mode."]
        case .brief:
            verbose = false
            return ["Brief mode."]
        case .take:
            return try take(first, second)
        case .drop:
            return try drop(first)
        case .put:
            return try put(first, second!)
        case .unlock, .lock:
            return try lock(first, second, locking: verb == .lock)
        case .use:
            let id = try resolve(first)
            let target = try resolve(second!)
            guard carried().contains(id) else {
                try fail("You aren't carrying the \(items[id]!.name).")
            }
            let result = runRules(rules, first: id, second: target)
            guard result.executed > 0 else {
                try fail("Nothing happens.")
            }
            return result.rows.isEmpty ? ["Done."] : result.rows
        default:
            break
        }
        let id = try resolve(first), item = items[id]!, value = state.items[id]!
        switch verb {
        case .examine:
            var rows = item.details.isEmpty ? ["You see nothing special about the \(item.name)."] : item.details
            if item.light {
                rows.append("It is \(value.lit ? "lit" : "unlit") (fuel \(value.fuel)).")
            }
            if item.capacity != nil {
                if value.container != .open {
                    rows.append("It is \(value.container.rawValue).")
                } else if !contents(.inside(id)).isEmpty {
                    rows += ["It contains:"] + tree(.inside(id))
                } else {
                    rows.append("It is empty.")
                }
            }
            if item.points > 0 {
                rows.append("It is a treasure worth \(item.points) points.")
            }
            rows.append("It weighs \(totalWeight(id)).")
            return rows
        case .openContainer:
            guard item.capacity != nil else {
                try fail("You can't open the \(item.name).")
            }
            guard value.container != .open else {
                try fail("The \(item.name) is already open.")
            }
            guard value.container != .locked else {
                try fail("The \(item.name) is locked.")
            }
            state.items[id]!.container = .open
            let names = contents(.inside(id)).map { items[$0]!.name }
            return names
                .isEmpty ? ["Opened."] : ["Opening the \(item.name) reveals " + names.joined(separator: ", ") + "."]
        case .closeContainer:
            guard item.capacity != nil else {
                try fail("You can't close the \(item.name).")
            }
            guard value.container == .open else {
                try fail("The \(item.name) is already closed.")
            }
            state.items[id]!.container = .closed
            return ["Closed."]
        case .light:
            guard item.light else {
                try fail("You can't light the \(item.name).")
            }
            guard !value.lit else {
                try fail("The \(item.name) is already lit.")
            }
            guard value.fuel > 0 else {
                try fail("The \(item.name) has no fuel.")
            }
            state.items[id]!.lit = true
            return ["The \(item.name) is now lit."]
        case .extinguish:
            guard item.light else {
                try fail("You can't extinguish the \(item.name).")
            }
            guard value.lit else {
                try fail("The \(item.name) is not lit.")
            }
            state.items[id]!.lit = false
            return ["The \(item.name) is now out."]
        default:
            return []
        }
    }
    private func endTurn(_ baseline: Bool) -> [String] {
        state.moves += 1
        let nearby = carried().union(roomItems())
        var rows = [String]()
        for id in ids where state.items[id]!.lit {
            state.items[id]!.fuel -= 1
            if state.items[id]!.fuel == 0 {
                state.items[id]!.lit = false
                if nearby.contains(id) {
                    rows.append("The \(items[id]!.name) goes out.")
                }
            }
        }
        let lit = isLit()
        if baseline && !lit {
            rows.append("It is now pitch dark.")
        } else if !baseline && lit {
            rows += describe()
        }
        state.darkness = lit ? 0 : state.darkness + 1
        if state.darkness == 2 {
            rows.append("You hear something moving in the dark.")
        }
        if state.darkness == 3 {
            state.ended = .dead
        }
        let value = score()
        if state.ended == .none && value.treasures > 0 && value.stored == value.treasures {
            state.ended = .won
        }
        if state.ended != .none {
            rows.append(state.ended == .dead ? "*** You have died ***" : "*** You have won ***")
            rows.append("You scored \(value.total) points in \(state.moves) moves.")
        }
        return rows
    }
    private func interpret(_ line: String) throws -> [String] {
        var parts = normalized(line)
        guard !parts.isEmpty else {
            try fail("I beg your pardon?")
        }
        if Direction.parse(parts[0]) != nil {
            parts.insert("go", at: 0)
        }
        guard var verb = verbWords[parts[0]] else {
            try fail("I don't know the verb \"\(parts[0])\".")
        }
        var rest = Array(parts.dropFirst())
        guard state.ended == .none || verb == .restore else {
            try fail("The game is over.")
        }
        if verb == .look && !rest.isEmpty {
            guard rest[0] == "at" else {
                try fail("I don't understand that.")
            }
            verb = .examine
            rest.removeFirst()
        }
        var first = rest
        var second: [String]?
        if noObjects.contains(verb) {
            guard rest.isEmpty else {
                try fail("I don't understand that.")
            }
        } else {
            guard !rest.isEmpty
            else {
                try fail(verb == .go ? "Which way do you want to go?" : "What do you want to \(verb.rawValue)?")
            }
            if verb == .go {
                guard rest.count == 1, Direction.parse(rest[0]) != nil else {
                    try fail("I don't understand that.")
                }
            } else {
                var prepositions = Set<String>()
                if verb == .put {
                    prepositions = ["in", "into"]
                } else if verb == .use {
                    prepositions = ["on", "with"]
                } else if (verb == .unlock || verb == .lock) && rest.contains("with") {
                    prepositions = ["with"]
                } else if verb == .take && rest.contains("from") {
                    prepositions = ["from"]
                }
                if !prepositions.isEmpty {
                    guard let index = rest.firstIndex(where: { prepositions.contains($0) }), index > 0,
                          index + 1 < rest.count
                    else {
                        try fail("I don't understand that.")
                    }
                    first = Array(rest[..<index])
                    second = Array(rest[(index + 1)...])
                }
            }
        }
        var baseline = isLit()
        var rows: [String]
        if verb == .go {
            let direction = Direction.parse(rest[0])!
            guard let exit = state.exits[state.room]?[direction] else {
                try fail("You can't go that way.")
            }
            guard !exit.locked else {
                try fail("The way \(direction.rawValue) is locked.")
            }
            state.room = exit.destination
            baseline = isLit()
            rows = describe(full: verbose || !state.visited.contains(state.room))
            state.visited.insert(state.room)
            rows += runRules(enterRules, first: state.room).rows
        } else {
            rows = try execute(verb, first, second)
        }
        if actions.contains(verb) {
            rows += endTurn(baseline)
        }
        return rows
    }
    func command(_ line: String) throws -> [String] {
        do {
            let parts = normalized(line)
            if let first = parts.first, first == "again" || first == "g" {
                guard parts.count == 1 else {
                    try fail("I don't understand that.")
                }
                guard let previous else {
                    try fail("There is nothing to repeat.")
                }
                return try interpret(previous)
            }
            previous = line
            return try interpret(line)
        } catch let error as Failure { return error.rows }
    }
    func finalScore() -> String {
        "Final score: \(score().total) points in \(state.moves) moves."
    }
}

var definitions = [String]()
while let line = readLine(), line != "BEGIN" {
    definitions.append(line)
}
let adventure = Adventure(definitions)
for row in adventure.describe() {
    print(row)
}
while let line = readLine() {
    if line == "QUIT" {
        print(adventure.finalScore())
        break
    }
    print("> " + line)
    for row in try adventure.command(line) {
        print(row)
    }
}
