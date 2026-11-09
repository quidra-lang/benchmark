import Foundation
func validName(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 32 && text.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
    }
}
func number(_ text: String, _ low: Int, _ high: Int) -> Int? {
    guard !text.isEmpty, !(text.count > 1 && text.first == "0"), text.utf8.allSatisfy({
        (48...57).contains($0)
    }), let value = Int(text), low <= value, value <= high else {
        return nil
    }
    return value
}
func threshold(_ text: String) -> (Int, Int)? {
    let a = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard a.count == 2, let p = number(a[0], 0, 99), let q = number(a[1], 1, 99), p <= q else {
        return nil
    }
    return (p, q)
}
func fraction(_ p: Int, _ q: Int) -> String {
    var a = p, b = q;
    while b != 0 {
        let r = a % b;
        a = b;
        b = r
    };
    return "\(p / a)/\(q / a)"
}
func list(_ values: [Int], _ separator: String = ",") -> String {
    values.map(String.init).joined(separator: separator)
}
func compare(_ a: (Int, Int), _ b: (Int, Int)) -> Int {
    let x = a.0 * b.1, y = b.0 * a.1;
    return x < y ? -1 : x == y ? 0 : 1
}
func analyze(_ text: String, _ elements: Elements) throws -> Molecule {
    let molecule = try SmilesParser.parse(text, elements).molecule
    RingsAromatic.detect(molecule)
    for i in molecule.bonds.indices where molecule.bonds[i].kind == 0 {
        let b = molecule.bonds[i]
        molecule.bonds[i].kind = molecule.atoms[b.a].aromatic && molecule.atoms[b.b].aromatic && b.ring ? 4 : 1
    }
    try RingsAromatic.kekulize(molecule, elements)
    for i in molecule.atoms.indices {
        let atom = molecule.atoms[i]
        if atom.bracket {
            if molecule.multiplicity(i) + atom.hydrogens > elements[atom.element]!.valences.last! + abs(atom.charge) {
                throw MoleculeError("bad valence", atom.column)
            }
        } else {
            guard let hydrogen = molecule.organicHydrogens(i, elements) else {
                throw MoleculeError("bad valence", atom.column)
            }
            molecule.atoms[i].hydrogens = hydrogen
        }
    }
    return molecule
}
func scaffold(_ molecule: Molecule, _ elements: Elements) -> String? {
    if molecule.rings.isEmpty {
        return nil
    }
    let ringAtoms = Set(molecule.rings.flatMap {
        $0
    })
    var remaining = Set(molecule.atoms.indices)
    while let removed = remaining.sorted().first(where: {
        i in !ringAtoms.contains(i) && molecule.neighbors[i].filter {
            remaining.contains($0.0)
        }.count == 1
    }) {
        remaining.remove(removed)
    }
    let core = remaining
    for bond in molecule.bonds where bond.kind == 2 {
        if core.contains(bond.a) {
            remaining.insert(bond.b)
        }
        if core.contains(bond.b) {
            remaining.insert(bond.a)
        }
    }
    let graph = Molecule()
    var index: [Int: Int] = [:]
    for i in remaining.sorted() {
        index[i] = graph.atoms.count
        var atom = molecule.atoms[i]
        atom.hydrogens += molecule.neighbors[i].filter {
            !remaining.contains($0.0)
        }.reduce(0) {
            $0 + molecule.bonds[$1.1].multiplicity
        }
        graph.atoms.append(atom)
    }
    for bond in molecule.bonds where remaining.contains(bond.a) && remaining.contains(bond.b) {
        var bond = bond
        bond.a = index[bond.a]!;
        bond.b = index[bond.b]!
        graph.bonds.append(bond)
    }
    graph.rebuild()
    return Canonical.smiles(graph, elements).0
}
struct Analysis {
    let name: String, graph: Molecule, smiles: String, classes: Int, formula: String, weight: Int
    let heavy: Int, rotatable: Int, donors: Int, acceptors: Int, lipinski: String, charge: Int
    let scaffold: String?, fingerprint: Fingerprint
}
func properties(_ name: String, _ molecule: Molecule, _ elements: Elements) -> Analysis {
    var counts: [String: Int] = [:], weight = 0, hydrogens = 0
    for atom in molecule.atoms {
        counts[atom.element, default: 0] += 1;
        hydrogens += atom.hydrogens
        weight += atom.mass == 0 ? elements[atom.element]!.mass : atom.mass * 1000
    }
    counts["H", default: 0] += hydrogens
    weight += hydrogens * elements["H"]!.mass
    counts = counts.filter {
        $0.value > 0
    }
    var order: [String] = []
    if counts["C"] != nil {
        order.append("C");
        if counts["H"] != nil {
            order.append("H")
        }
    }
    order += counts.keys.filter {
        !order.contains($0)
    }.sorted()
    let formula = order.map {
        $0 + (counts[$0]! > 1 ? String(counts[$0]!) : "")
    }.joined()
    let heavy = molecule.atoms.filter {
        $0.element != "H"
    }.count
    let heavyDegree = molecule.neighbors.map {
        $0.filter {
            molecule.atoms[$0.0].element != "H"
        }.count
    }
    let triple = molecule.neighbors.map {
        $0.contains {
            molecule.bonds[$0.1].multiplicity == 3
        }
    }
    let rotatable = molecule.bonds.filter {
        $0.multiplicity == 1 && !$0.ring && heavyDegree[$0.a] >= 2 && heavyDegree[$0.b] >= 2 && !triple[$0.a] && !triple[$0.b]
    }.count
    let acceptors = molecule.atoms.filter {
        $0.element == "N" || $0.element == "O"
    }.count
    let donors = molecule.atoms.indices.filter {
        i in let a = molecule.atoms[i];
        return (a.element == "N" || a.element == "O") && (a.hydrogens > 0 || molecule.neighbors[i].contains {
            molecule.atoms[$0.0].element == "H"
        })
    }.count
    let lipinski = (weight > 500000 ? 1 : 0) + (donors > 5 ? 1 : 0) + (acceptors > 10 ? 1 : 0) <= 1 ? "pass" : "fail"
    let charge = molecule.atoms.reduce(0) {
        $0 + $1.charge
    }, (smiles, classes) = Canonical.smiles(molecule, elements)
    return Analysis(name: name, graph: molecule, smiles: smiles, classes: classes, formula: formula, weight: weight, heavy: heavy, rotatable: rotatable, donors: donors, acceptors: acceptors, lipinski: lipinski, charge: charge, scaffold: scaffold(molecule, elements), fingerprint: Search.fingerprint(molecule, elements))
}
func ringSystems(_ molecule: Molecule) -> [([Int], String, Int)] {
    var remaining = Set(molecule.rings.indices), result: [([Int], String, Int)] = []
    while let start = remaining.min() {
        var group: Set<Int> = [], stack = [start]
        remaining.remove(start)
        while let i = stack.popLast() {
            group.insert(i)
            let neighbors = remaining.filter {
                j in molecule.rings[i].contains {
                    molecule.rings[j].contains($0)
                }
            }.sorted()
            for j in neighbors {
                remaining.remove(j);
                stack.append(j)
            }
        }
        let rings = group.sorted(), atoms = Set(rings.flatMap {
            molecule.rings[$0]
        })
        var kind = "isolated"
        if rings.count > 1 {
            kind = "spiro"
            for x in rings.indices {
                for y in (x + 1)..<rings.count {
                    let common = molecule.rings[rings[x]].filter {
                        molecule.rings[rings[y]].contains($0)
                    }
                    if common.count >= 2 {
                        if common.count == 2 && molecule.bond(common[0], common[1]) != nil {
                            if kind != "bridged" {
                                kind = "fused"
                            }
                        }
                        else {
                            kind = "bridged"
                        }
                    }
                }
            }
        }
        result.append((rings, kind, atoms.count))
    }
    return result
}
func paragraph(_ output: inout [String], _ lines: [String]) {
    if !output.isEmpty {
        output.append("")
    };
    output += lines
}
func canonicalReport(_ molecules: [Analysis]) -> [String] {
    var result: [String] = [], lines = ["CANONICAL molecules=\(molecules.count) unique=\(Set(molecules.map(\.smiles)).count)"]
    for molecule in molecules {
        lines.append("\(molecule.name) \(molecule.smiles) classes=\(molecule.classes) charge=\(molecule.charge > 0 ? "+" : "")\(molecule.charge)")
    }
    paragraph(&result, lines)
    var duplicates: [String: [Int]] = [:], formulas: [String: [Int]] = [:], scaffolds: [String: [Int]] = [:]
    for (i, molecule) in molecules.enumerated() {
        duplicates[molecule.smiles, default: []].append(i);
        formulas[molecule.formula, default: []].append(i)
        if let scaffold = molecule.scaffold {
            scaffolds[scaffold, default: []].append(i)
        }
    }
    func names(_ ids: [Int]) -> String {
        ids.map {
            molecules[$0].name
        }.joined(separator: ",")
    }
    let groups = duplicates.filter {
        $0.value.count >= 2
    }.sorted {
        $0.value[0] < $1.value[0]
    }
    lines = ["DUPLICATES groups=\(groups.count) molecules=\(groups.reduce(0) { $0 + $1.value.count })"]
    for (i, group) in groups.enumerated() {
        lines.append("group \(i + 1) \(group.key) members=\(names(group.value))")
    }
    paragraph(&result, lines)
    let isomers = formulas.map {
        ($0.key, $0.value, Set($0.value.map {
            molecules[$0].smiles
        }).count)
    }.filter {
        $0.2 >= 2
    }.sorted {
        $0.1[0] < $1.1[0]
    }
    lines = ["ISOMERS groups=\(isomers.count)"]
    for (i, group) in isomers.enumerated() {
        lines.append("isomer \(i + 1) \(group.0) forms=\(group.2) members=\(names(group.1))")
    }
    paragraph(&result, lines)
    let scaffoldGroups = scaffolds.sorted {
        $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
    }
    lines = ["SCAFFOLDS distinct=\(scaffoldGroups.count) acyclic=\(molecules.filter { $0.scaffold == nil }.count)"]
    for (i, group) in scaffoldGroups.enumerated() {
        lines.append("scaffold \(i + 1) \(group.key) count=\(group.value.count) members=\(names(group.value))")
    }
    paragraph(&result, lines)
    return result
}
func ringsReport(_ molecules: [Analysis]) -> [String] {
    var result: [String] = [], total = 0, aromatic = 0, cyclic = 0, sizes: [Int: Int] = [:], kinds = [0, 0, 0, 0]
    for molecule in molecules where !molecule.graph.rings.isEmpty {
        let graph = molecule.graph, aromaticCount = graph.rings.filter {
            $0.allSatisfy {
                graph.atoms[$0].aromatic
            }
        }.count, systems = ringSystems(graph)
        cyclic += 1;
        total += graph.rings.count;
        aromatic += aromaticCount
        var lines = ["MOLECULE \(molecule.name) atoms=\(graph.atoms.count) bonds=\(graph.bonds.count) rings=\(graph.rings.count) aromatic=\(aromaticCount) systems=\(systems.count) ring_atoms=\(Set(graph.rings.flatMap { $0 }).count) ring_bonds=\(graph.bonds.filter(\.ring).count)"]
        for (i, ring) in graph.rings.enumerated() {
            sizes[ring.count, default: 0] += 1
            let a = ring.allSatisfy {
                graph.atoms[$0].aromatic
            }, hetero = ring.filter {
                graph.atoms[$0].element != "C"
            }.count
            lines.append("ring \(i + 1) size=\(ring.count) aromatic=\(a ? "yes" : "no") hetero=\(hetero) atoms=\(list(ring.map { $0 + 1 }, "-"))")
        }
        for (i, system) in systems.enumerated() {
            kinds[["isolated", "fused", "spiro", "bridged"].firstIndex(of: system.1)!] += 1
            lines.append("system \(i + 1) kind=\(system.1) rings=\(list(system.0.map { $0 + 1 })) atoms=\(system.2)")
        }
        let double = graph.bonds.filter {
            $0.kind == 4 && $0.multiplicity == 2
        }.map {
            "\($0.a + 1)=\($0.b + 1)"
        }
        lines.append("kekule " + (double.isEmpty ? "-" : double.joined(separator: " ")))
        paragraph(&result, lines)
    }
    let sizeText = sizes.isEmpty ? "-" : sizes.keys.sorted().map {
        "\($0)=\(sizes[$0]!)"
    }.joined(separator: " ")
    paragraph(&result, ["SUMMARY molecules=\(molecules.count) cyclic=\(cyclic) rings=\(total) aromatic=\(aromatic)", "sizes \(sizeText)", "systems isolated=\(kinds[0]) fused=\(kinds[1]) spiro=\(kinds[2]) bridged=\(kinds[3])"])
    return result
}
struct QueryError: Error {
    let reason: String;
    init(_ reason: String) {
        self.reason = reason
    }
}
struct Query {
    let kind: String, id: String, args: [String]
    var indices: [Int] = [], pattern: Pattern?, count = 0, threshold = (0, 1)
}
func query(_ a: [String], _ names: [String: Int], _ elements: Elements) throws -> Query {
    let kind = a[0], args = Array(a.dropFirst(2)), length = args.count
    let valid = kind == "MATCH" || kind == "CLUSTER" ? length == 1 : kind == "MATRIX" ? (2...12).contains(length) : length == 2
    if !valid {
        throw QueryError("bad arguments")
    }
    var query = Query(kind: kind, id: a[1], args: args)
    func index(_ name: String) throws -> Int {
        guard let i = names[name] else {
            throw QueryError("unknown molecule \(name)")
        };
        return i
    }
    switch kind {
        case "MATCH":
        do {
            query.pattern = try Pattern.parse(args[0], elements)
        }
        catch let error as MoleculeError {
            throw QueryError("bad pattern \(error.reason) at column \(error.column)")
        }
        case "CLUSTER": guard let t = threshold(args[0]) else {
            throw QueryError("bad threshold")
        };
        query.threshold = t
        case "NEAREST", "WITHIN":
        query.indices.append(try index(args[0]))
        if kind == "NEAREST" {
            guard let n = number(args[1], 1, 99) else {
                throw QueryError("bad count")
            };
            query.count = n
        }
        else {
            guard let t = threshold(args[1]) else {
                throw QueryError("bad threshold")
            };
            query.threshold = t
        }
        default:
        for name in args {
            query.indices.append(try index(name))
        }
        if Set(query.indices).count != query.indices.count {
            throw QueryError("repeated molecule")
        }
    }
    return query
}
func process(_ q: Query, _ molecules: [Analysis], _ sub: inout [String], _ similarity: inout [String], _ counts: inout [Int]) {
    func sim(_ a: Int, _ b: Int) -> (Int, Int) {
        Search.similarity(molecules[a].fingerprint, molecules[b].fingerprint)
    }
    switch q.kind {
        case "MATCH":
        counts[0] += 1
        let pattern = q.pattern!, matches = molecules.enumerated().map {
            ($0.offset, Search.embeddings(pattern, $0.element.graph))
        }.filter {
            $0.1.count > 0
        }
        counts[1] += matches.count
        var lines = ["MATCH \(q.id) \(q.args[0]) atoms=\(pattern.graph.atoms.count) bonds=\(pattern.graph.bonds.count) hits=\(matches.count) embeddings=\(matches.reduce(0) { $0 + $1.1.count })"]
        for (i, match) in matches {
            lines.append("\(molecules[i].name) count=\(match.count) unique=\(match.unique) map=\(list(match.first))")
        }
        if let top = matches.min(by: {
            $0.1.count == $1.1.count ? $0.0 < $1.0 : $0.1.count > $1.1.count
        }) {
            lines.append("top \(molecules[top.0].name) count=\(top.1.count)")
        }
        paragraph(&sub, lines)
        case "CONTAINS":
        counts[2] += 1
        let a = q.indices[0], b = q.indices[1], matches = Search.embeddings(.molecule(molecules[a].graph), molecules[b].graph)
        let result: String
        if matches.count > 0 {
            counts[3] += 1;
            result = "yes count=\(matches.count) unique=\(matches.unique) map=\(list(matches.first))"
        }
        else {
            result = "no"
        }
        paragraph(&sub, ["CONTAINS \(q.id) \(q.args[0]) \(q.args[1]) result=\(result)"])
        case "MATRIX":
        var lines = ["MATRIX \(q.id) size=\(q.indices.count)"]
        for a in q.indices {
            lines.append("row \(molecules[a].name) " + q.indices.map {
                let s = sim(a, $0);
                return fraction(s.0, s.1)
            }.joined(separator: " "))
        }
        var best = (0, 1, sim(q.indices[0], q.indices[1]))
        for a in q.indices.indices {
            for b in (a + 1)..<q.indices.count {
                let s = sim(q.indices[a], q.indices[b]);
                if compare(s, best.2) > 0 {
                    best = (a, b, s)
                }
            }
        }
        lines.append("best \(q.args[best.0]) \(q.args[best.1]) \(fraction(best.2.0, best.2.1))")
        paragraph(&similarity, lines)
        case "NEAREST", "WITHIN":
        let x = q.indices[0]
        var results = molecules.indices.filter {
            $0 != x
        }.map {
            ($0, sim(x, $0))
        }.sorted {
            let order = compare($0.1, $1.1);
            return order == 0 ? $0.0 < $1.0 : order > 0
        }
        if q.kind == "NEAREST" {
            results = Array(results.prefix(q.count))
        }
        else {
            results = results.filter {
                compare($0.1, q.threshold) >= 0
            }
        }
        let first = q.kind == "NEAREST" ? "NEAREST \(q.id) \(q.args[0]) count=\(results.count)" : "WITHIN \(q.id) \(q.args[0]) threshold=\(fraction(q.threshold.0, q.threshold.1)) count=\(results.count)"
        var lines = [first]
        for (k, result) in results.enumerated() {
            lines.append("\(k + 1) \(molecules[result.0].name) \(fraction(result.1.0, result.1.1)) common=\(result.1.0)")
        }
        paragraph(&similarity, lines)
        case "COMPARE":
        let a = q.indices[0], b = q.indices[1], s = sim(a, b)
        paragraph(&similarity, ["COMPARE \(q.id) \(q.args[0]) \(q.args[1]) bits=\(molecules[a].fingerprint.bits.count),\(molecules[b].fingerprint.bits.count) common=\(s.0) union=\(s.1) tanimoto=\(fraction(s.0, s.1)) identical=\(molecules[a].smiles == molecules[b].smiles ? "yes" : "no")"])
        default:
        let n = molecules.count, neighbors = molecules.indices.map {
            i in molecules.indices.filter {
                $0 != i && compare(sim(i, $0), q.threshold) >= 0
            }
        }
        let order = (0..<n).sorted {
            neighbors[$0].count == neighbors[$1].count ? $0 < $1 : neighbors[$0].count > neighbors[$1].count
        }
        var used: Set<Int> = [], clusters: [[Int]] = []
        for i in order where used.insert(i).inserted {
            var members = [i]
            for j in neighbors[i] where used.insert(j).inserted {
                members.append(j)
            }
            clusters.append(members)
        }
        let singletons = clusters.filter {
            $0.count == 1
        }.count
        var lines = ["CLUSTER \(q.id) threshold=\(fraction(q.threshold.0, q.threshold.1)) clusters=\(clusters.count) singletons=\(singletons)"]
        for (k, cluster) in clusters.filter({
            $0.count > 1
        }).enumerated() {
            lines.append("cluster \(k + 1) centroid=\(molecules[cluster[0]].name) size=\(cluster.count) members=\(cluster.map { molecules[$0].name }.joined(separator: ","))")
        }
        paragraph(&similarity, lines)
    }
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func runProgram() {
    let elements = readElements()
    var molecules: [Analysis] = [], seen: Set<String> = [], moleculeErrors: [String] = [], causes: [String: Int] = [:], moleculeLines = 0
    let moleculeText = try! String(contentsOfFile: "input/molecules.smi", encoding: .ascii)
    for (i, line) in moleculeText.components(separatedBy: "\n").enumerated() where !line.isEmpty && line.first != "#" {
        moleculeLines += 1
        let a = line.components(separatedBy: " "), error: (String, String)?
        if a.count != 2 || a[0].isEmpty || !validName(a[1]) {
            error = ("line \(i + 1): bad line", "bad line")
        }
        else if !seen.insert(a[1]).inserted {
            error = ("line \(i + 1) \(a[1]): duplicate name", "duplicate name")
        }
        else {
            do {
                molecules.append(properties(a[1], try analyze(a[0], elements), elements));
                error = nil
            }
            catch let cause as MoleculeError {
                error = ("line \(i + 1) \(a[1]): \(cause.reason) at column \(cause.column)", cause.reason)
            }
            catch {
                preconditionFailure()
            }
        }
        if let (line, cause) = error {
            moleculeErrors.append(line);
            causes[cause, default: 0] += 1
        }
    }
    let names = Dictionary(uniqueKeysWithValues: molecules.enumerated().map {
        ($0.element.name, $0.offset)
    })
    var propertyLines = ["name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"]
    for m in molecules {
        let remainder = String(m.weight % 1000), weight = "\(m.weight / 1000)." + String(repeating: "0", count: 3 - remainder.count) + remainder
        propertyLines.append("\(m.name),\(m.formula),\(weight),\(m.heavy),\(m.graph.rings.count),\(m.rotatable),\(m.donors),\(m.acceptors),\(m.lipinski)")
    }
    var substructure: [String] = [], similarity = ["FINGERPRINTS molecules=\(molecules.count) size=1024 depth=5"]
    similarity += molecules.map {
        "\($0.name) bits=\($0.fingerprint.bits.count) paths=\($0.fingerprint.paths)"
    }
    var identifiers: Set<String> = [], queryErrors: [String] = [], queryLines = 0, queryValid = 0, counts = [0, 0, 0, 0]
    let queryText = try! String(contentsOfFile: "input/queries.txt", encoding: .ascii)
    for (i, line) in queryText.components(separatedBy: "\n").enumerated() where !line.isEmpty && line.first != "#" {
        queryLines += 1
        let a = line.components(separatedBy: " "), error: (String, String)?
        if !["MATCH", "CONTAINS", "MATRIX", "NEAREST", "WITHIN", "COMPARE", "CLUSTER"].contains(a[0]) {
            error = ("line \(i + 1): unknown query", "unknown query")
        }
        else if a.count == 1 || !validName(a[1]) {
            error = ("line \(i + 1) \(a[0]): bad id", "bad id")
        }
        else {
            do {
                if !identifiers.insert(a[1]).inserted {
                    throw QueryError("duplicate id")
                }
                let q = try query(a, names, elements)
                queryValid += 1;
                process(q, molecules, &substructure, &similarity, &counts);
                error = nil
            } catch let reason as QueryError {
                let cause = reason.reason.hasPrefix("bad pattern ") ? "bad pattern" : reason.reason.hasPrefix("unknown molecule ") ? "unknown molecule" : reason.reason
                error = ("line \(i + 1) \(a[0]) \(a[1]): \(reason.reason)", cause)
            } catch {
                preconditionFailure()
            }
        }
        if let (line, cause) = error {
            queryErrors.append(line);
            causes[cause, default: 0] += 1
        }
    }
    paragraph(&substructure, ["SUMMARY patterns=\(counts[0]) hits=\(counts[1]) contains=\(counts[2]) found=\(counts[3])"])
    var errors: [String] = []
    paragraph(&errors, ["MOLECULES lines=\(moleculeLines) valid=\(molecules.count) errors=\(moleculeErrors.count)"] + moleculeErrors)
    paragraph(&errors, ["QUERIES lines=\(queryLines) valid=\(queryValid) errors=\(queryErrors.count)"] + queryErrors)
    let sortedCauses = causes.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }
    paragraph(&errors, ["CAUSES kinds=\(causes.count)"] + sortedCauses.map {
        "\($0.key)=\($0.value)"
    })
    write("properties.csv", propertyLines);
    write("canonical.txt", canonicalReport(molecules));
    write("rings.txt", ringsReport(molecules))
    write("substructure.txt", substructure);
    write("similarity.txt", similarity);
    write("errors.txt", errors)
}
runProgram()
