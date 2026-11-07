import Foundation

struct PetriNet {
    let places: [String]
    let transitions: [String]
    let arcs: Set<NamePair>
    let initial: Int
    let finalPlace: Int
    let inputs: [String: [Int]]
    let outputs: [String: [Int]]
    let routes: [[String]]
    let initialMarking: [Int]
    let finalMarking: [Int]
    init(_ places: [String], _ transitions: [String], _ arcs: Set<NamePair>, _ initial: String, _ finalName: String) {
        let sorted = transitions.sorted(), initialIndex = places.firstIndex(of: initial)!, finalIndex = places.firstIndex(of: finalName)!
        self.places = places; self.transitions = sorted; self.arcs = arcs; self.initial = initialIndex; finalPlace = finalIndex
        inputs = Dictionary(uniqueKeysWithValues: sorted.map { transition in (transition, places.indices.filter { arcs.contains(NamePair(places[$0], transition)) }) }); outputs = Dictionary(uniqueKeysWithValues: sorted.map { transition in (transition, places.indices.filter { arcs.contains(NamePair(transition, places[$0])) }) }); routes = places.map { place in sorted.filter { arcs.contains(NamePair(place, $0)) } }; initialMarking = places.indices.map { $0 == initialIndex ? 1 : 0 }; finalMarking = places.indices.map { $0 == finalIndex ? 1 : 0 }
    }
    func enabled(_ marking: [Int], _ transition: String) -> Bool { inputs[transition]!.allSatisfy { marking[$0] >= 1 } }
    func enabledTransitions(_ marking: [Int]) -> [String] { transitions.filter { enabled(marking, $0) } }
    func fire(_ marking: [Int], _ transition: String) -> [Int] { var result = marking; for place in inputs[transition]! { result[place] -= 1 }; for place in outputs[transition]! { result[place] += 1 }; return result }
}
func readModel() throws -> PetriNet { var places: [String] = [], transitions: [String] = [], arcs: Set<NamePair> = [], initial = "", finalName = ""; for line in try inputLines("model.txt") { let fields = line.split(separator: " ").map(String.init); switch fields[0] { case "PLACE": places.append(fields[1]); case "TRANSITION": transitions.append(fields[1]); case "ARC": arcs.insert(NamePair(fields[1], fields[2])); case "INITIAL": initial = fields[1]; default: finalName = fields[1] } }; return PetriNet(places, transitions, arcs, initial, finalName) }
struct ReplayTotals {
    var missing = 0
    var remaining = 0
    var consumed = 0
    var produced = 0
    var skipped = 0
    var placeMissing: [Int]
    var placeRemaining: [Int]
    var deviating: [Int]
    var waiting: [[Int]]
    var routes: [[String: Int]]
    init(_ count: Int) { placeMissing = Array(repeating: 0, count: count); placeRemaining = placeMissing; deviating = placeMissing; waiting = Array(repeating: [], count: count); routes = Array(repeating: [:], count: count) }
    func fitness() -> Rational { Rational(1, 2) * (Rational(1) - Rational(missing, consumed)) + Rational(1, 2) * (Rational(1) - Rational(remaining, produced)) }
}
