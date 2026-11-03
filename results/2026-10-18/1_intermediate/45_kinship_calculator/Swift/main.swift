import Foundation

struct CommandError: Error {
    let reason: String
}

struct Fraction: CustomStringConvertible {
    let numerator: Int64
    let denominator: Int64

    init(_ numerator: Int64, _ denominator: Int64 = 1) {
        var a = numerator
        var b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        self.numerator = numerator / a
        self.denominator = denominator / a
    }

    static func + (a: Fraction, b: Fraction) -> Fraction {
        let denominator = max(a.denominator, b.denominator)
        return Fraction(a.numerator * (denominator / a.denominator) + b.numerator * (denominator / b.denominator), denominator)
    }

    var half: Fraction { Fraction(numerator, denominator * 2) }
    var description: String { "\(numerator)/\(denominator)" }
}

struct Person {
    let sex: String
    let birth: Int
    let name: String
    var death: Int?
    var parents: Set<String> = []

    var life: String { "\(birth)-" + (death.map(String.init) ?? "") }
}

struct Marriage {
    let first: String
    let second: String
    let start: Int
    var end: Int?
    var status = "current"
    var died: String?

    func contains(_ id: String) -> Bool { first == id || second == id }
    func other(_ id: String) -> String { first == id ? second : first }
}

struct FamilyState {
    var people: [String: Person] = [:]
    var marriages: [Marriage] = []
}

struct UndoRecord {
    let command: String
    let state: FamilyState
}

struct PersonPair: Hashable {
    let first: String
    let second: String
    init(_ a: String, _ b: String) {
        first = min(a, b)
        second = max(a, b)
    }
}

struct Apex {
    let id: String
    let da: Int
    let db: Int
    let shares: Int
}

func gender(_ sex: String, _ male: String, _ female: String, _ neutral: String) -> String {
    sex == "M" ? male : sex == "F" ? female : neutral
}

func grandPrefix(_ generation: Int) -> String {
    if generation == 1 { return "" }
    return String(repeating: "great-", count: generation - 2) + "grand"
}

func ordinal(_ number: Int) -> String {
    let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
    if number <= 10 { return words[number - 1] }
    let suffix: String
    if (11...13).contains(number % 100) { suffix = "th" }
    else { suffix = [1: "st", 2: "nd", 3: "rd"][number % 10] ?? "th" }
    return "\(number)" + suffix
}

func term(_ da: Int, _ db: Int, _ sex: String) -> String {
    if da == 0 && db == 0 { return "self" }
    if da == 0 { return grandPrefix(db) + gender(sex, "father", "mother", "parent") }
    if db == 0 { return grandPrefix(da) + gender(sex, "son", "daughter", "child") }
    if da == 1 && db == 1 { return gender(sex, "brother", "sister", "sibling") }
    if da == 1 { return grandPrefix(db - 1) + gender(sex, "uncle", "aunt", "pibling") }
    if db == 1 { return grandPrefix(da - 1) + gender(sex, "nephew", "niece", "nibling") }
    let removed = abs(da - db)
    let ending: String
    switch removed {
    case 0: ending = ""
    case 1: ending = " once removed"
    case 2: ending = " twice removed"
    default: ending = " \(removed) times removed"
    }
    return ordinal(min(da, db) - 1) + " cousin" + ending
}

final class Family {
    var state = FamilyState()
    var history: [UndoRecord] = []
    var ancestorCache: [String: [String: Int]] = [:]
    var kinshipCache: [PersonPair: Fraction] = [:]
    var lastMarriages: [PersonPair: Int] = [:]
    var spouses: [String: String] = [:]
    var partnerCache: [String: Set<String>] = [:]

    func prepareQueries() {
        ancestorCache.removeAll(keepingCapacity: true)
        kinshipCache.removeAll(keepingCapacity: true)
        partnerCache.removeAll(keepingCapacity: true)
        lastMarriages.removeAll(keepingCapacity: true)
        spouses.removeAll(keepingCapacity: true)
        for (i, marriage) in state.marriages.enumerated() {
            lastMarriages[PersonPair(marriage.first, marriage.second)] = i
            if marriage.status == "current" {
                spouses[marriage.first] = marriage.second
                spouses[marriage.second] = marriage.first
            }
        }
    }

    func check(_ ids: String...) throws {
        for id in ids where state.people[id] == nil { throw CommandError(reason: "UNKNOWN PERSON " + id) }
    }

    func remember(_ line: String) { history.append(UndoRecord(command: line, state: state)) }

    func ageBefore(_ a: String, _ b: String) -> Bool {
        let x = state.people[a]!.birth
        let y = state.people[b]!.birth
        return x != y ? x < y : a < b
    }

    func personList<S: Sequence>(_ ids: S) -> String where S.Element == String {
        let sorted = ids.sorted(by: ageBefore)
        return sorted.isEmpty ? "-" : sorted.joined(separator: " ")
    }

    func children(_ id: String) -> [String] {
        state.people.keys.filter { state.people[$0]!.parents.contains(id) }
    }

    func siblings(_ a: String, _ b: String) -> Bool {
        a != b && !state.people[a]!.parents.isDisjoint(with: state.people[b]!.parents)
    }

    func ancestors(_ id: String) -> [String: Int] {
        if let cached = ancestorCache[id] { return cached }
        var distances = [id: 0]
        var queue = [id]
        var cursor = 0
        while cursor < queue.count {
            let person = queue[cursor]
            cursor += 1
            let distance = distances[person]! + 1
            for parent in state.people[person]!.parents where distances[parent] == nil {
                distances[parent] = distance
                queue.append(parent)
            }
        }
        ancestorCache[id] = distances
        return distances
    }

    func descendants(_ id: String) -> [String: Int] {
        var result: [String: Int] = [:]
        for person in state.people.keys where person != id {
            if let distance = ancestors(person)[id] { result[person] = distance }
        }
        return result
    }

    func apex(_ a: String, _ b: String) -> Apex? {
        let aa = ancestors(a)
        let ab = ancestors(b)
        if let db = ab[a] { return Apex(id: a, da: 0, db: db, shares: 0) }
        if let da = aa[b] { return Apex(id: b, da: da, db: 0, shares: 0) }
        let common = aa.keys.filter { ab[$0] != nil }
        guard let best = common.min(by: {
            let leftSum = aa[$0]! + ab[$0]!
            let rightSum = aa[$1]! + ab[$1]!
            if leftSum != rightSum { return leftSum < rightSum }
            if aa[$0]! != aa[$1]! { return aa[$0]! < aa[$1]! }
            return $0 < $1
        }) else { return nil }
        let da = aa[best]!
        let db = ab[best]!
        let shares = common.filter { aa[$0] == da && ab[$0] == db }.count
        return Apex(id: best, da: da, db: db, shares: shares)
    }

    func bloodTerm(_ a: String, _ b: String, sex: String? = nil) -> String? {
        guard a != b, let apex = apex(a, b) else { return nil }
        let prefix = apex.shares == 1 ? "half-" : apex.shares >= 4 ? "double " : ""
        return prefix + term(apex.da, apex.db, sex ?? state.people[a]!.sex)
    }

    func partners(_ id: String) -> Set<String> {
        if let cached = partnerCache[id] { return cached }
        var result: Set<String> = []
        for (pair, i) in lastMarriages where pair.first == id || pair.second == id {
            let marriage = state.marriages[i]
            if marriage.status != "divorced" { result.insert(marriage.other(id)) }
        }
        partnerCache[id] = result
        return result
    }

    func relationship(_ a: String, _ b: String, sex: String? = nil) -> [String] {
        if a == b { return ["self"] }
        let s = sex ?? state.people[a]!.sex
        let parentsA = state.people[a]!.parents
        let parentsB = state.people[b]!.parents
        let partnersA = partners(a)
        let partnersB = partners(b)
        let aa = ancestors(a)
        let ab = ancestors(b)
        var terms: [String] = []
        if let blood = bloodTerm(a, b, sex: s) { terms.append(blood) }
        if let i = lastMarriages[PersonPair(a, b)] {
            let marriage = state.marriages[i]
            switch marriage.status {
            case "current": terms.append(gender(s, "husband", "wife", "spouse"))
            case "widowed":
                terms.append(marriage.died == a ? gender(s, "late husband", "late wife", "late spouse") : gender(s, "widower", "widow", "surviving spouse"))
            default: terms.append(gender(s, "ex-husband", "ex-wife", "ex-spouse"))
            }
        } else if children(a).contains(where: { state.people[$0]!.parents.contains(b) }) {
            terms.append("co-parent")
        }
        if !parentsB.contains(a) && parentsB.contains(where: { partners($0).contains(a) }) {
            terms.append(gender(s, "stepfather", "stepmother", "stepparent"))
        }
        if !parentsA.contains(b) && parentsA.contains(where: { partners($0).contains(b) }) {
            terms.append(gender(s, "stepson", "stepdaughter", "stepchild"))
        }
        if parentsA.isDisjoint(with: parentsB) && parentsA.contains(where: { !partners($0).isDisjoint(with: parentsB) }) {
            terms.append(gender(s, "stepbrother", "stepsister", "stepsibling"))
        }
        if ab[a] == nil && ab.contains(where: { $0.value == 2 && partners($0.key).contains(a) }) {
            terms.append(gender(s, "stepgrandfather", "stepgrandmother", "stepgrandparent"))
        }
        if aa[b] == nil && aa.contains(where: { $0.value == 2 && partners($0.key).contains(b) }) {
            terms.append(gender(s, "stepgrandson", "stepgranddaughter", "stepgrandchild"))
        }
        if partnersB.contains(where: { state.people[$0]!.parents.contains(a) }) {
            terms.append(gender(s, "father-in-law", "mother-in-law", "parent-in-law"))
        }
        if partnersA.contains(where: { state.people[$0]!.parents.contains(b) }) {
            terms.append(gender(s, "son-in-law", "daughter-in-law", "child-in-law"))
        }
        if partnersB.contains(where: { siblings(a, $0) }) || partnersA.contains(where: { siblings($0, b) }) {
            terms.append(gender(s, "brother-in-law", "sister-in-law", "sibling-in-law"))
        }
        return terms
    }

    func relationshipString(_ a: String, _ b: String) -> String {
        let terms = relationship(a, b)
        return terms.isEmpty ? "no relation" : terms.joined(separator: ", ")
    }

    func phi(_ a: String, _ b: String) -> Fraction {
        let pair = PersonPair(a, b)
        if let value = kinshipCache[pair] { return value }
        let value: Fraction
        if a == b {
            let parents = Array(state.people[a]!.parents)
            value = parents.count == 2 ? (Fraction(1) + phi(parents[0], parents[1])).half : Fraction(1, 2)
        } else {
            let x = state.people[a]!.birth >= state.people[b]!.birth ? a : b
            let y = x == a ? b : a
            var sum = Fraction(0)
            for parent in state.people[x]!.parents { sum = sum + phi(parent, y) }
            value = sum.half
        }
        kinshipCache[pair] = value
        return value
    }

    func inbreeding(_ id: String) -> Fraction {
        let parents = Array(state.people[id]!.parents)
        return parents.count == 2 ? phi(parents[0], parents[1]) : Fraction(0)
    }

    func upwardPath(_ from: String, to apex: String) -> [String] {
        var result = [from]
        var current = from
        while current != apex {
            let targetDistance = ancestors(current)[apex]! - 1
            current = state.people[current]!.parents.sorted().first { ancestors($0)[apex] == targetDistance }!
            result.append(current)
        }
        return result
    }

    func command(_ line: String) throws -> [String] {
        prepareQueries()
        let words = line.components(separatedBy: " ")
        let command = words[0]
        switch command {
        case "PERSON":
            let id = words[1]
            guard state.people[id] == nil else { throw CommandError(reason: "DUPLICATE PERSON " + id) }
            remember(line)
            state.people[id] = Person(sex: words[2], birth: Int(words[3])!, name: words[4])
            return ["ADDED \(id) \(words[4]) \(words[2]) \(words[3])"]
        case "DEATH":
            let id = words[1]
            let year = Int(words[2])!
            try check(id)
            let person = state.people[id]!
            guard person.death == nil else { throw CommandError(reason: "ALREADY DECEASED " + id) }
            if year < person.birth || state.marriages.contains(where: { $0.contains(id) && ($0.start > year || ($0.end != nil && $0.end! > year)) }) {
                throw CommandError(reason: "BAD YEAR " + id)
            }
            if let child = children(id).sorted().first(where: { state.people[$0]!.birth > year + 1 }) {
                throw CommandError(reason: "AFTER DEATH \(child) \(id)")
            }
            remember(line)
            state.people[id]!.death = year
            if let spouse = spouses[id] {
                let i = lastMarriages[PersonPair(id, spouse)]!
                state.marriages[i].end = year
                state.marriages[i].status = "widowed"
                state.marriages[i].died = id
                return ["DIED \(id) \(year) spouse=\(spouse)"]
            }
            return ["DIED \(id) \(year)"]
        case "REMOVE":
            let id = words[1]
            try check(id)
            remember(line)
            let ids = Array(state.people.keys)
            for person in ids { state.people[person]!.parents.remove(id) }
            state.people.removeValue(forKey: id)
            state.marriages.removeAll { $0.contains(id) }
            return ["REMOVED " + id]
        case "PARENT":
            let child = words[1]
            let parent = words[2]
            try check(child, parent)
            guard child != parent else { throw CommandError(reason: "SAME PERSON " + child) }
            guard !state.people[child]!.parents.contains(parent) else { throw CommandError(reason: "ALREADY PARENT \(child) \(parent)") }
            guard state.people[child]!.parents.count < 2 else { throw CommandError(reason: "TOO MANY PARENTS " + child) }
            guard ancestors(parent)[child] == nil else { throw CommandError(reason: "CYCLE \(child) \(parent)") }
            guard state.people[parent]!.birth + 12 <= state.people[child]!.birth else { throw CommandError(reason: "AGE GAP \(child) \(parent)") }
            if let death = state.people[parent]!.death, death + 1 < state.people[child]!.birth {
                throw CommandError(reason: "AFTER DEATH \(child) \(parent)")
            }
            remember(line)
            state.people[child]!.parents.insert(parent)
            return ["LINKED \(child) \(parent) " + gender(state.people[parent]!.sex, "father", "mother", "parent")]
        case "UNPARENT":
            let child = words[1]
            let parent = words[2]
            try check(child, parent)
            guard state.people[child]!.parents.contains(parent) else { throw CommandError(reason: "NOT PARENT \(child) \(parent)") }
            remember(line)
            state.people[child]!.parents.remove(parent)
            return ["UNLINKED \(child) \(parent)"]
        case "SPOUSE":
            let a = words[1]
            let b = words[2]
            let year = Int(words[3])!
            try check(a, b)
            guard a != b else { throw CommandError(reason: "SAME PERSON " + a) }
            for id in [a, b] where state.people[id]!.death != nil { throw CommandError(reason: "DECEASED " + id) }
            for id in [a, b] where spouses[id] != nil { throw CommandError(reason: "ALREADY MARRIED " + id) }
            if ancestors(a)[b] != nil || ancestors(b)[a] != nil || siblings(a, b) { throw CommandError(reason: "CLOSE KIN \(a) \(b)") }
            for id in [a, b] where year < state.people[id]!.birth + 16 { throw CommandError(reason: "TOO YOUNG " + id) }
            for id in [a, b] {
                if state.marriages.contains(where: { $0.contains(id) && $0.end != nil && $0.end! >= year }) {
                    throw CommandError(reason: "BAD YEAR " + id)
                }
            }
            remember(line)
            state.marriages.append(Marriage(first: a, second: b, start: year))
            return ["MARRIED \(a) \(b) \(year)"]
        case "DIVORCE":
            let a = words[1]
            let b = words[2]
            let year = Int(words[3])!
            try check(a, b)
            guard spouses[a] == b else { throw CommandError(reason: "NOT MARRIED \(a) \(b)") }
            let i = lastMarriages[PersonPair(a, b)]!
            guard year > state.marriages[i].start else { throw CommandError(reason: "BAD YEAR " + a) }
            remember(line)
            state.marriages[i].end = year
            state.marriages[i].status = "divorced"
            return ["DIVORCED \(a) \(b) \(year)"]
        case "UNDO":
            guard let previous = history.popLast() else { throw CommandError(reason: "NOTHING TO UNDO") }
            state = previous.state
            return ["UNDONE " + previous.command]
        case "INFO":
            let id = words[1]
            try check(id)
            let person = state.people[id]!
            var lines = ["INFO \(id) \(person.name) \(person.sex) \(person.life)", "  parents: " + personList(person.parents)]
            for marriage in state.marriages where marriage.contains(id) {
                lines.append("  marriage: \(marriage.other(id)) \(marriage.start)-\(marriage.end.map(String.init) ?? "") \(marriage.status)")
            }
            lines.append("  children: " + personList(children(id)))
            lines.append("  siblings: " + personList(state.people.keys.filter { siblings($0, id) }))
            lines.append("  inbreeding: \(inbreeding(id))")
            return lines
        case "RELATION":
            let a = words[1]
            let b = words[2]
            try check(a, b)
            return ["RELATION \(a) \(b): " + relationshipString(a, b)]
        case "RELATIVES", "WHO":
            let id = words[1]
            try check(id)
            let query = words.dropFirst(2).joined(separator: " ")
            var lines: [String] = []
            for person in state.people.keys.sorted() where person != id {
                let terms = relationship(person, id)
                if command == "RELATIVES" {
                    if !terms.isEmpty { lines.append("  \(person): " + terms.joined(separator: ", ")) }
                } else {
                    let neutral = relationship(person, id, sex: "X")
                    if let index = terms.indices.first(where: { terms[$0] == query || neutral[$0] == query }) {
                        lines.append("  \(person): " + terms[index])
                    }
                }
            }
            let title = command == "WHO" ? "WHO \(id) \(query)" : "RELATIVES \(id)"
            return [title + " \(lines.count)"] + lines
        case "PATH":
            let a = words[1]
            let b = words[2]
            try check(a, b)
            guard let apex = apex(a, b) else { return ["PATH \(a) \(b) none"] }
            let path = upwardPath(a, to: apex.id) + Array(upwardPath(b, to: apex.id).dropLast().reversed())
            return ["PATH \(a) \(b) \(apex.da + apex.db): " + path.joined(separator: " ")]
        case "COMMON":
            let a = words[1]
            let b = words[2]
            try check(a, b)
            let aa = ancestors(a)
            let ab = ancestors(b)
            let common = Set(aa.keys.filter { ab[$0] != nil })
            let nearest = common.filter { Set(children($0)).isDisjoint(with: common) }.sorted {
                let left = aa[$0]! + ab[$0]!
                let right = aa[$1]! + ab[$1]!
                return left != right ? left < right : $0 < $1
            }
            return ["COMMON \(a) \(b) \(nearest.count)"] + nearest.map { "  \($0) \(aa[$0]!) \(ab[$0]!)" }
        case "ANCESTORS", "DESCENDANTS":
            let id = words[1]
            try check(id)
            var distances = command == "ANCESTORS" ? ancestors(id) : descendants(id)
            distances.removeValue(forKey: id)
            let sorted = distances.keys.sorted {
                distances[$0]! != distances[$1]! ? distances[$0]! < distances[$1]! : $0 < $1
            }
            return ["\(command) \(id) \(sorted.count)"] + sorted.map { person in
                let generation = distances[person]!
                let title = command == "ANCESTORS" ? term(0, generation, state.people[person]!.sex) : term(generation, 0, state.people[person]!.sex)
                return "  \(generation) \(person) \(title)"
            }
        case "COUSINS":
            let id = words[1]
            let degree = Int(words[2])!
            try check(id)
            var matches: [(String, Apex)] = []
            for person in state.people.keys where person != id {
                if let apex = apex(person, id), apex.da >= 2, apex.db >= 2, min(apex.da, apex.db) - 1 == degree {
                    matches.append((person, apex))
                }
            }
            matches.sort {
                let left = abs($0.1.da - $0.1.db)
                let right = abs($1.1.da - $1.1.db)
                return left != right ? left < right : $0.0 < $1.0
            }
            return ["COUSINS \(id) \(degree) \(matches.count)"] + matches.map { "  \($0.0) \(bloodTerm($0.0, id)!)" }
        case "SIBLINGS":
            let id = words[1]
            try check(id)
            let parents = state.people[id]!.parents
            var matches: [(String, String)] = []
            var order = 1
            for person in state.people.keys where person != id {
                let otherParents = state.people[person]!.parents
                let count = parents.intersection(otherParents).count
                let kind: String
                if count == 2 { kind = "full" }
                else if count == 1 { kind = "half" }
                else if parents.contains(where: { !partners($0).isDisjoint(with: otherParents) }) { kind = "step" }
                else { continue }
                matches.append((person, kind))
                if count > 0 && ageBefore(person, id) { order += 1 }
            }
            matches.sort { ageBefore($0.0, $1.0) }
            return ["SIBLINGS \(id) \(matches.count) order=\(order)"] + matches.map { "  \($0.0) \($0.1) \(state.people[$0.0]!.birth)" }
        case "GENERATIONS":
            let id = words[1]
            try check(id)
            var groups: [Int: [String]] = [:]
            for (person, generation) in descendants(id) { groups[generation, default: []].append(person) }
            return ["GENERATIONS \(id) \(groups.count)"] + groups.keys.sorted().map { generation in
                let people = groups[generation]!.map { state.people[$0]! }
                let years = people.map(\.birth)
                return "  \(generation) \(people.count) \(people.filter { $0.death == nil }.count) \(years.min()!)-\(years.max()!)"
            }
        case "TREE":
            let id = words[1]
            try check(id)
            var lines = ["TREE \(id) \(descendants(id).count)"]
            var visited: Set<String> = []
            func visit(_ person: String, depth: Int) {
                let indent = String(repeating: " ", count: 2 * (depth + 1))
                if !visited.insert(person).inserted { lines.append(indent + person + " (see above)"); return }
                let value = state.people[person]!
                let spouse = spouses[person].map { " = " + $0 } ?? ""
                lines.append(indent + "\(person) \(value.name) \(value.life)" + spouse)
                for child in children(person).sorted(by: ageBefore) { visit(child, depth: depth + 1) }
            }
            visit(id, depth: 0)
            return lines
        case "PEDIGREE":
            let id = words[1]
            let depth = Int(words[2])!
            try check(id)
            var lines: [String] = []
            var entered: Set<String> = []
            let sexOrder = ["M": 0, "F": 1, "X": 2]
            func enter(_ person: String, number: Int, generation: Int) {
                entered.insert(person)
                let value = state.people[person]!
                lines.append(String(repeating: " ", count: 2 * (generation + 1)) + "\(number) \(person) \(value.name) \(value.life)")
                if generation < depth {
                    let parents = value.parents.sorted {
                        let left = sexOrder[state.people[$0]!.sex]!
                        let right = sexOrder[state.people[$1]!.sex]!
                        return left != right ? left < right : $0 < $1
                    }
                    for (i, parent) in parents.enumerated() { enter(parent, number: 2 * number + i, generation: generation + 1) }
                }
            }
            enter(id, number: 1, generation: 0)
            return ["PEDIGREE \(id) \(depth) entries=\(lines.count) distinct=\(entered.count)"] + lines
        case "TIMELINE":
            let id = words[1]
            try check(id)
            let person = state.people[id]!
            var events: [(year: Int, rank: Int, other: String, text: String)] = [(person.birth, 0, "", "born")]
            for marriage in state.marriages where marriage.contains(id) {
                let other = marriage.other(id)
                events.append((marriage.start, 1, other, "married " + other))
                if marriage.status == "divorced" { events.append((marriage.end!, 3, other, "divorced " + other)) }
                if marriage.status == "widowed" && marriage.died == other { events.append((marriage.end!, 4, other, "widowed " + other)) }
            }
            let kids = children(id)
            for child in kids { events.append((state.people[child]!.birth, 2, child, "child " + child)) }
            for (relatives, label) in [(Array(person.parents), "parent"), (kids, "child")] {
                for other in relatives {
                    if let death = state.people[other]!.death, death >= person.birth, person.death == nil || death <= person.death! {
                        events.append((death, 5, other, "lost \(label) \(other)"))
                    }
                }
            }
            if let death = person.death { events.append((death, 6, "", "died")) }
            events.sort {
                if $0.year != $1.year { return $0.year < $1.year }
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.other < $1.other
            }
            return ["TIMELINE \(id) \(events.count)"] + events.map { "  \($0.year) \($0.text)" }
        case "CENSUS":
            let year = Int(words[1])!
            let residents = state.people.keys.filter {
                let person = state.people[$0]!
                return person.birth <= year && (person.death == nil || person.death! > year)
            }.sorted(by: ageBefore)
            var lines = ["CENSUS \(year) \(residents.count)"]
            for id in residents {
                var status = "single"
                if let marriage = state.marriages.last(where: { $0.contains(id) && $0.start <= year }) {
                    status = marriage.end == nil || marriage.end! > year ? "married " + marriage.other(id) : marriage.status
                }
                lines.append("  \(id) \(year - state.people[id]!.birth) \(status)")
            }
            return lines
        case "KINSHIP":
            let a = words[1]
            let b = words[2]
            try check(a, b)
            return ["KINSHIP \(a) \(b) \(phi(a, b))"]
        case "FIND":
            let id = words[1]
            let route = words[2]
            try check(id)
            var found: Set<String> = [id]
            for step in route.components(separatedBy: ".") {
                var next: Set<String> = []
                let requiredSex = ["father", "son", "brother", "husband"].contains(step) ? "M" : ["mother", "daughter", "sister", "wife"].contains(step) ? "F" : nil
                for person in found {
                    let candidates: [String]
                    switch step {
                    case "parent", "father", "mother": candidates = Array(state.people[person]!.parents)
                    case "child", "son", "daughter": candidates = children(person)
                    case "sibling", "brother", "sister": candidates = state.people.keys.filter { siblings(person, $0) }
                    default: candidates = spouses[person].map { [$0] } ?? []
                    }
                    for candidate in candidates where requiredSex == nil || state.people[candidate]!.sex == requiredSex! { next.insert(candidate) }
                }
                found = next
            }
            found.remove(id)
            return ["FIND \(id) \(route) \(found.count)"] + found.sorted().map { "  \($0): " + relationshipString($0, id) }
        case "TERM":
            let da = Int(words[1])!
            let db = Int(words[2])!
            return ["TERM \(da) \(db) \(words[3]) " + term(da, db, words[3])]
        case "STATS":
            var lengths: [String: Int] = [:]
            func length(_ id: String) -> Int {
                if let cached = lengths[id] { return cached }
                let value = 1 + (state.people[id]!.parents.map { length($0) }.max() ?? 0)
                lengths[id] = value
                return value
            }
            let generations = state.people.keys.map { length($0) }.max() ?? 0
            let people = Array(state.people.values)
            return ["STATS persons=\(people.count) living=\(people.filter { $0.death == nil }.count) links=\(people.reduce(0) { $0 + $1.parents.count }) couples=\(state.marriages.filter { $0.status == "current" }.count) founders=\(people.filter { $0.parents.isEmpty }.count) generations=\(generations)"]
        case "AUDIT":
            var lines: [String] = []
            for marriage in state.marriages {
                if let blood = bloodTerm(marriage.first, marriage.second) { lines.append("  marriage \(marriage.first) \(marriage.second) \(blood)") }
            }
            for id in state.people.keys.sorted() {
                let coefficient = inbreeding(id)
                if coefficient.numerator != 0 { lines.append("  inbred \(id) \(coefficient)") }
            }
            return ["AUDIT \(lines.count)"] + lines
        default: return []
        }
    }
}

let family = Family()
if let line = readLine(), let count = Int(line) {
    var output: [String] = []
    for _ in 0..<count {
        guard let line = readLine() else { break }
        do { output += try family.command(line) }
        catch let error as CommandError { output.append("ERROR " + error.reason) }
        catch { fatalError("Unexpected error: \(error)") }
    }
    if !output.isEmpty { print(output.joined(separator: "\n")) }
}
