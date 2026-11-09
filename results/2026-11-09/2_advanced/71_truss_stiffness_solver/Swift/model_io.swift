import Foundation

struct Node { let identifier: Int; let x: Int; let y: Int }
struct Member { let identifier: Int; let start: Int; let end: Int; let section: Int; let material: Int; let group: String }
struct Section { let name: String; let area: Double; let inertia: Double }
struct Material { let name: String; let young: Double; let yieldStress: Double; let density: Double; let expansion: Double }
struct Support { let node: Int; let fixed: [Bool]; let prescribed: [Double] }
enum Load { case force(Int, Double, Double), temperature(Int, Double), selfWeight, settlement }
struct LoadCase { let name: String; let lines: [Load] }
struct CombinationTerm { let name: String; let factor: Double }
struct Combination { let name: String; let terms: [CombinationTerm] }
struct Axle { let offset: Int; let load: Double }
struct Drawing { let name: String; let magnification: Int; let horizontal: Int; let vertical: Int }
struct Settings {
    var deck: [Int] = [], influence: [Int] = []
    var vehicleStep = 0
    var axles: [Axle] = []
    var ratingName = "", deflectionName = "", vibrationName = "", removalName = ""
    var deadFactor = 0.0, vehicleFactor = 0.0
    var slenderness: [Double] = []
    var deflectionRatio = 0, modeCount = 0, iterations = 0
    var drawings: [Drawing] = []
    var mapHorizontal = 0, mapVertical = 0
}
struct Model { let nodes: [Node]; let members: [Member]; let sections: [Section]; let materials: [Material]; let supports: [Support]; let cases: [LoadCase]; let combinations: [Combination]; let settings: Settings }
func inputLines(_ name: String) throws -> [String] { try String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init) }
func csvRows(_ name: String) throws -> [[String]] { try inputLines(name + ".csv").dropFirst().map { $0.split(separator: ",").map(String.init) } }
func readModel() throws -> Model {
    let nodes = try csvRows("nodes").map { Node(identifier: Int($0[0])!, x: Int($0[1])!, y: Int($0[2])!) }
    let sections = try csvRows("sections").map { Section(name: $0[0], area: Double($0[1])!, inertia: Double($0[2])!) }
    let materials = try csvRows("materials").map { Material(name: $0[0], young: Double($0[1])!, yieldStress: Double($0[2])!, density: Double($0[3])!, expansion: Double($0[4])!) }
    let nodeIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.identifier, $0.offset) })
    let sectionIndex = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($0.element.name, $0.offset) })
    let materialIndex = Dictionary(uniqueKeysWithValues: materials.enumerated().map { ($0.element.name, $0.offset) })
    let members = try csvRows("members").map { Member(identifier: Int($0[0])!, start: nodeIndex[Int($0[1])!]!, end: nodeIndex[Int($0[2])!]!, section: sectionIndex[$0[3]]!, material: materialIndex[$0[4]]!, group: $0[5]) }
    let memberIndex = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($0.element.identifier, $0.offset) })
    let supports = try csvRows("supports").map { Support(node: nodeIndex[Int($0[0])!]!, fixed: [$0[1] == "1", $0[2] == "1"], prescribed: [Double($0[3])!, Double($0[4])!]) }
    var cases: [LoadCase] = [], combinations: [Combination] = [], name = "", loads: [Load] = [], settings = Settings()
    for line in try inputLines("loads.txt") {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "LOADCASE": name = fields[1]; loads = []
        case "END": cases.append(LoadCase(name: name, lines: loads))
        case "COMBINATION": combinations.append(Combination(name: fields[1], terms: stride(from: 2, to: fields.count, by: 2).map { CombinationTerm(name: fields[$0], factor: Double(fields[$0 + 1])!) }))
        case "FORCE": loads.append(.force(nodeIndex[Int(fields[1])!]!, Double(fields[2])!, Double(fields[3])!))
        case "TEMPERATURE": loads.append(.temperature(memberIndex[Int(fields[1])!]!, Double(fields[2])!))
        case "SELFWEIGHT": loads.append(.selfWeight)
        default: loads.append(.settlement)
        }
    }
    for line in try inputLines("params.txt") {
        let fields = line.split(separator: " ").map(String.init)
        switch fields[0] {
        case "deck": settings.deck = fields.dropFirst().map { nodeIndex[Int($0)!]! }
        case "influence": settings.influence.append(memberIndex[Int(fields[1])!]!)
        case "vehicle": settings.vehicleStep = Int(fields[1])!; settings.axles = stride(from: 2, to: fields.count, by: 2).map { Axle(offset: Int(fields[$0])!, load: Double(fields[$0 + 1])!) }
        case "rating": settings.ratingName = fields[1]; settings.deadFactor = Double(fields[2])!; settings.vehicleFactor = Double(fields[3])!
        case "slenderness": settings.slenderness = fields.dropFirst().map { Double($0)! }
        case "deflection": settings.deflectionName = fields[1]; settings.deflectionRatio = Int(fields[2])!
        case "vibration": settings.vibrationName = fields[1]; settings.modeCount = Int(fields[2])!; settings.iterations = Int(fields[3])!
        case "removal": settings.removalName = fields[1]
        case "drawing": settings.drawings.append(Drawing(name: fields[1], magnification: Int(fields[2])!, horizontal: Int(fields[3])!, vertical: Int(fields[4])!))
        default: settings.mapHorizontal = Int(fields[1])!; settings.mapVertical = Int(fields[2])!
        }
    }
    return Model(nodes: nodes, members: members, sections: sections, materials: materials, supports: supports, cases: cases, combinations: combinations, settings: settings)
}
