import Foundation
func number(_ text: String) -> Int {
    text.hasPrefix("0x") ? Int(text.dropFirst(2), radix: 16)! : Int(text)!
}
func hex(_ value: Int, _ width: Int = 8, _ uppercase: Bool = false) -> String {
    let text = String(value, radix: 16, uppercase: uppercase);
    return String(repeating: "0", count: max(0, width - text.count)) + text
}
struct VeneerPair: Hashable {
    let output: Int, name: String
}
enum LiveUnit {
    case section(Reference), common(String)
}
struct Comdat {
    let signature: String, keeper: String;
    var discarded: [String] = []
}
final class Linker {
    var entry = "", gc = true, segments: [Segment] = [], outputs: [OutputSection] = [], loads: [(String, String)] = [], keeps: Set<String> = [], sorts: Set<String> = [], wraps: Set<String> = [], defines: [(String, String)] = [], checksum: (String, String)?, inputs: [[String]] = []
    var objects: [Object] = [], archives: [String: Archive] = [:], entries: [String: [Reference]] = [:], names: [String: Resolution] = [:], comdats: [Comdat] = [], extractions: [(String, String, String)] = [], veneers: Set<VeneerPair> = []
    init() {
        for line in ObjectParser.lines("link.txt") {
            let f = line.split(separator: " ").map(String.init)
            switch f[0] {
                case "entry": entry = f[1]
                case "gc": gc = f[1] == "on"
                case "segment": var indices: [Int] = [];
                for name in f.dropFirst(5) {
                    indices.append(outputs.count);
                    outputs.append(OutputSection(name))
                };
                segments.append(Segment(f[1], number(f[2]), number(f[3]), number(f[4]), indices))
                case "load": loads.append((f[1], f[2]))
                case "keep": keeps.insert(f[1])
                case "sort": sorts.insert(f[1])
                case "wrap": wraps.insert(f[1])
                case "define": let parts = line.components(separatedBy: " = ");
                defines.append((String(parts[0].dropFirst(7)), parts[1]))
                case "checksum": checksum = (f[1], f[2])
                default: inputs.append(f)
            }
        }
    }
    func undefined(_ name: String) -> Bool {
        if defines.contains(where: {
            $0.0 == name
        }) {
            return false
        }
        let references = entries[name] ?? []
        if references.contains(where: {
            if case .undefined = objects[$0.object].symbols[$0.index].definition {
                return false
            };
            return true
        }) {
            return false
        }
        return name == entry || references.contains {
            objects[$0.object].symbols[$0.index].binding == "global"
        }
    }
    func load(_ object: Object) {
        for (signature, sections) in object.groups {
            if let i = comdats.firstIndex(where: {
                $0.signature == signature
            }) {
                for s in sections {
                    object.sections[s].discard = "comdat"
                };
                comdats[i].discarded.append(object.name)
            }
            else {
                comdats.append(Comdat(signature: signature, keeper: object.name))
            }
        }
        for symbol in object.symbols {
            if symbol.binding != "local", case .section(let s, _) = symbol.definition, object.sections[s].discard == "comdat" {
                symbol.definition = .undefined
            }
            if case .undefined = symbol.definition {
                if wraps.contains(symbol.name) {
                    symbol.name = "__wrap_" + symbol.name
                }
                else if symbol.name.hasPrefix("__real_"), wraps.contains(String(symbol.name.dropFirst(7))) {
                    symbol.name = String(symbol.name.dropFirst(7))
                }
            }
        }
        let o = objects.count
        for (i, symbol) in object.symbols.enumerated() where symbol.binding != "local" {
            entries[symbol.name, default: []].append(Reference(object: o, index: i))
        };
        objects.append(object)
    }
    func scan(_ name: String) -> Bool {
        if archives[name] == nil {
            archives[name] = Archive(name)
        };
        let archive = archives[name]!
        return archive.scan {
            member in
            guard let reason = member.exports.first(where: self.undefined) else {
                return false
            }
            let referrer = (self.entries[reason] ?? []).first {
                reference in let symbol = self.objects[reference.object].symbols[reference.index];
                if case .undefined = symbol.definition {
                    return symbol.binding == "global"
                };
                return false
            }.map {
                self.objects[$0.object].name
            } ?? "*entry*"
            self.extractions.append((member.object.name, referrer, reason));
            self.load(member.object);
            return true
        }
    }
    func loadInputs() {
        for f in inputs {
            if f[0] == "object" {
                load(ObjectParser.parse(f[1], ObjectParser.lines(f[1])))
            }
            else if f[0] == "library" {
                _ = scan(f[1])
            }
            else {
                while true {
                    var changed = false;
                    for name in f.dropFirst() {
                        if scan(name) {
                            changed = true
                        }
                    };
                    if !changed {
                        break
                    }
                }
            }
        }
        let scripts = Set(defines.map {
            $0.0
        })
        for name in Set(entries.keys).union(scripts).sorted() {
            names[name] = Resolver.resolve(objects, entries[name] ?? [], scripts.contains(name))
        }
        for object in objects {
            for section in object.sections where section.discard == nil {
                section.output = Layout.output(section.name, outputs);
                if section.output == nil {
                    section.discard = "orphan"
                }
            }
        }
    }
    func definitionUnit(_ resolution: Resolution) -> LiveUnit? {
        if resolution.kind == "common", let name = names.first(where: {
            $0.value === resolution
        })?.key {
            return .common(name)
        }
        if let reference = resolution.definition, case .section(let section, _) = objects[reference.object].symbols[reference.index].definition {
            return .section(Reference(object: reference.object, index: section))
        };
        return nil
    }
    func target(_ object: Int, _ relocation: Relocation) -> LiveUnit? {
        let symbol = objects[object].symbols[relocation.symbol]
        if symbol.binding == "local", case .section(let section, _) = symbol.definition {
            return .section(Reference(object: object, index: section))
        }
        if symbol.binding != "local" {
            let resolution = names[symbol.name]!;
            if resolution.kind == "common" {
                return .common(symbol.name)
            };
            return definitionUnit(resolution)
        };
        return nil
    }
    func collect() {
        var pending: [LiveUnit] = []
        for (o, object) in objects.enumerated() {
            for (s, section) in object.sections.enumerated() where section.discard == nil && (!gc || keeps.contains(outputs[section.output!].name)) {
                pending.append(.section(Reference(object: o, index: s)))
            }
        }
        if !gc {
            for name in names.keys.sorted() where names[name]!.kind == "common" {
                pending.append(.common(name))
            }
        }
        if let resolution = names[entry], let unit = definitionUnit(resolution) {
            pending.append(unit)
        }
        var i = 0
        while i < pending.count {
            let unit = pending[i];
            i += 1
            switch unit {
                case .common(let name): names[name]!.live = true
                case .section(let reference):
                let object = objects[reference.object], section = object.sections[reference.index]
                if section.live || section.discard != nil {
                    continue
                };
                section.live = true
                for relocation in object.relocations where relocation.section == reference.index {
                    if let unit = target(reference.object, relocation) {
                        pending.append(unit)
                    }
                }
            }
        }
        for object in objects {
            for section in object.sections where section.discard == nil && !section.live {
                section.discard = "gc"
            }
        }
        for resolution in names.values {
            if let reference = resolution.definition, case .section(let section, _) = objects[reference.object].symbols[reference.index].definition {
                resolution.live = objects[reference.object].sections[section].live
            }
        }
    }
    func merged(_ sections: [Reference]) -> Component {
        var unique: [[Int]: Int] = [:], data: [Int] = [], positions: [MergedPosition] = [], strings = 0, total = 0
        for reference in sections {
            let section = objects[reference.object].sections[reference.index];
            total += section.size;
            var start = 0
            for end in section.data.indices where section.data[end] == 0 {
                let string = Array(section.data[start...end]), offset: Int
                if let old = unique[string] {
                    offset = old
                } else {
                    offset = data.count;
                    unique[string] = offset;
                    data += string
                }
                positions.append(MergedPosition(reference: reference, offset: start, merged: offset));
                strings += 1;
                start = end + 1
            }
        };
        return Component(.merged(MergedData(sections: sections.count, strings: strings, unique: unique.count, saved: total - data.count, positions: positions)), data.count, 1, data)
    }
    func layout() {
        for (index, output) in outputs.enumerated() {
            var sections: [Reference] = []
            for (o, object) in objects.enumerated() {
                for (s, section) in object.sections.enumerated() where section.live && section.output == index {
                    sections.append(Reference(object: o, index: s))
                }
            }
            if sorts.contains(output.name) {
                func priority(_ reference: Reference) -> Int {
                    let name = objects[reference.object].sections[reference.index].name;
                    return name == output.name ? 65536 : Int(name.dropFirst(output.name.count + 1))!
                }
                sections = sections.enumerated().sorted {
                    let a = priority($0.element), b = priority($1.element);
                    return a == b ? $0.offset < $1.offset : a < b
                }.map(\.element)
            }
            let strings = sections.filter {
                stringSection(objects[$0.object].sections[$0.index].name)
            };
            var emitted = false, components: [Component] = []
            for reference in sections {
                let section = objects[reference.object].sections[reference.index]
                if stringSection(section.name) {
                    if !emitted {
                        components.append(merged(strings));
                        emitted = true
                    }
                }
                else {
                    components.append(Component(.input(reference), section.size, section.alignment, section.data))
                }
            }
            if output.name == ".bss" {
                let commons = names.keys.filter {
                    names[$0]!.kind == "common" && names[$0]!.live
                }.sorted {
                    names[$0]!.alignment == names[$1]!.alignment ? $0 < $1 : names[$0]!.alignment > names[$1]!.alignment
                }
                for name in commons {
                    let resolution = names[name]!;
                    components.append(Component(.common(name), resolution.size, resolution.alignment))
                }
            }
            for pair in veneers.filter({
                $0.output == index
            }).sorted(by: {
                $0.name < $1.name
            }) {
                components.append(Component(.veneer(pair.name), 8, 4))
            };
            output.components = components
        }
        for segment in segments {
            Layout.assign(segment, outputs)
        }
        for output in outputs {
            for component in output.components {
                switch component.kind {
                    case .input(let reference): objects[reference.object].sections[reference.index].address = component.address
                    case .merged(let data): for position in data.positions {
                        objects[position.reference.object].sections[position.reference.index].strings[position.offset] = component.address + position.merged
                    }
                    case .common(let name): names[name]!.address = component.address
                    default: break
                }
            }
        }
        for resolution in names.values {
            if let reference = resolution.definition, case .section(let sectionIndex, let offset) = objects[reference.object].symbols[reference.index].definition {
                let section = objects[reference.object].sections[sectionIndex];
                resolution.address = stringSection(section.name) && section.live ? section.strings[offset]! : section.address + offset
            }
        }
    }
    func isFar(_ object: Int, _ relocation: Relocation) -> Bool {
        let section = objects[object].sections[relocation.section], symbol = objects[object].symbols[relocation.symbol]
        guard section.live, relocation.kind == "CALL24", symbol.binding != "local", let resolution = names[symbol.name], ["global", "weak"].contains(resolution.kind) else {
            return false
        }
        return !Relocator.fits("CALL24", resolution.address + relocation.addend - section.address - relocation.offset)
    }
    func farPairs() -> Set<VeneerPair> {
        var pairs: Set<VeneerPair> = []
        for (o, object) in objects.enumerated() {
            for relocation in object.relocations where isFar(o, relocation) {
                pairs.insert(VeneerPair(output: object.sections[relocation.section].output!, name: object.symbols[relocation.symbol].name))
            }
        };
        return pairs
    }
    func finishLayout() {
        while true {
            layout();
            let far = farPairs();
            if far.isSubset(of: veneers) {
                break
            };
            veneers.formUnion(far)
        }
        var storage = segments.map {
            $0.base + $0.memsz
        }
        for (a, b) in loads {
            let first = segments.firstIndex {
                $0.name == a
            }!, second = segments.firstIndex {
                $0.name == b
            }!;
            segments[first].paddr = align(storage[second], 4);
            storage[second] = segments[first].paddr + segments[first].filesz
        }
        for (i, segment) in segments.enumerated() {
            segment.used = storage[i] - segment.base
        }
        var values: [String: Int] = [:]
        for (name, expression) in defines {
            let value = ScriptParser(expression, values, outputs, segments).expression();
            values[name] = value;
            names[name]!.address = value
        }
    }
    func symbolValue(_ object: Int, _ index: Int) -> Int? {
        let symbol = objects[object].symbols[index]
        if symbol.binding == "local", case .section(let s, let offset) = symbol.definition {
            let section = objects[object].sections[s];
            return stringSection(section.name) ? section.strings[offset]! : section.address + offset
        }
        let resolution = names[symbol.name]!;
        return resolution.kind == "undefined" ? nil : resolution.address
    }
    func diagnostics() -> [String] {
        var lines: [String] = [], orphans: [String: Int] = [:]
        for object in objects {
            for section in object.sections where section.discard == "orphan" {
                orphans[section.name, default: 0] += 1
            }
        }
        for name in orphans.keys.sorted() {
            lines.append("warning: orphan section \(name) discarded from \(orphans[name]!) object(s)")
        }
        for name in names.keys.sorted() {
            let resolution = names[name]!, definers = (resolution.kind == "script" ? ["*script*"] : []) + resolution.strong.map {
                objects[$0].name
            }
            if definers.count >= 2 {
                lines.append("error: multiple definition of \(name): " + definers.joined(separator: " "))
            }
            if !resolution.common.isEmpty && ["global", "script"].contains(resolution.kind) {
                lines.append("warning: common symbol \(name) overridden by \(resolution.definer)")
            }
            if resolution.kind == "common" && Set(resolution.common).count >= 2 {
                lines.append("warning: common symbol \(name) merged to size \(resolution.size) align \(resolution.alignment)")
            }
        }
        if names[entry] == nil || ["undefined", "weakundef"].contains(names[entry]!.kind) {
            lines.append("error: entry symbol \(entry) is undefined")
        }
        for name in names.keys.sorted() where names[name]!.kind == "undefined" {
            let referrers = objects.filter {
                object in object.relocations.contains {
                    r in object.sections[r.section].live && object.symbols[r.symbol].binding != "local" && object.symbols[r.symbol].name == name
                }
            }.map(\.name)
            if !referrers.isEmpty {
                lines.append("error: undefined symbol \(name) referenced by " + referrers.joined(separator: " "))
            }
        }
        for segment in segments where segment.used > segment.length {
            lines.append("error: segment \(segment.name) overflows its length by \(segment.used - segment.length) bytes")
        }
        for (i, a) in segments.enumerated() {
            for b in segments.dropFirst(i + 1) where a.memsz > 0 && b.memsz > 0 && a.base < b.base + b.memsz && b.base < a.base + a.memsz {
                lines.append("error: segments \(a.name) and \(b.name) overlap")
            }
        };
        return lines
    }
    func relocate(_ diagnostics: inout [String]) -> [String] {
        var lines: [String] = [], counts = Dictionary(uniqueKeysWithValues: Relocator.types.map {
            ($0, Array(repeating: 0, count: 4))
        }), addresses: [VeneerPair: Int] = [:], order: [Reference] = []
        for (i, output) in outputs.enumerated() {
            for component in output.components {
                switch component.kind {
                    case .veneer(let name): addresses[VeneerPair(output: i, name: name)] = component.address;
                    case .input(let reference): order.append(reference);
                    default: break
                }
            }
        }
        let gp = names["_gp"]?.address ?? 0
        for reference in order {
            let o = reference.object, s = reference.index, object = objects[o], section = object.sections[s], relocations = object.relocations.filter {
                $0.section == s
            }
            for (index, relocation) in relocations.enumerated() {
                let symbolName = object.symbols[relocation.symbol].name, location = "\(object.name) \(section.name)+\(relocation.offset)", position = section.address + relocation.offset
                if Relocator.unpaired(relocations, index) {
                    diagnostics.append("error: unpaired HI16 at \(location) against \(symbolName)")
                }
                var symbol = symbolValue(o, relocation.symbol), status = "ok"
                if isFar(o, relocation) {
                    symbol = addresses[VeneerPair(output: section.output!, name: symbolName)]!;
                    status = "veneer"
                }
                if let symbol {
                    let value = Relocator.value(relocation.kind, symbol, relocation.addend, position, gp), field = Relocator.field(relocation.kind, value), width = Relocator.width(relocation.kind)
                    if !Relocator.fits(relocation.kind, value) {
                        status = "overflow";
                        diagnostics.append("error: relocation overflow at \(location): \(relocation.kind) value \(value) against \(symbolName)")
                    }
                    for (i, byte) in Relocator.little(field, width).enumerated() {
                        section.data[relocation.offset + i] = byte
                    }
                    lines.append("\(hex(position)) \(object.name) \(section.name)+\(relocation.offset) \(relocation.kind) \(symbolName) \(relocation.addend) \(hex(symbol)) \(value) \(hex(field, width * 2)) \(status)")
                } else {
                    status = "undefined";
                    lines.append("\(hex(position)) \(object.name) \(section.name)+\(relocation.offset) \(relocation.kind) \(symbolName) \(relocation.addend) - - - undefined")
                }
                counts[relocation.kind]![status == "ok" ? 0 : status == "veneer" ? 1 : status == "overflow" ? 2 : 3] += 1
            }
        }
        for kind in Relocator.types {
            let c = counts[kind]!;
            lines.append("summary \(kind) total \(c.reduce(0, +)) ok \(c[0]) veneer \(c[1]) overflow \(c[2]) undefined \(c[3])")
        };
        return lines
    }
    func images() {
        for segment in segments {
            var image = Array(repeating: segment.fill, count: segment.filesz)
            for i in segment.outputs where !nobits(outputs[i].name) {
                for component in outputs[i].components {
                    let data: [Int]
                    switch component.kind {
                        case .input(let reference): data = objects[reference.object].sections[reference.index].data;
                        case .veneer(let name): data = [4, 240, 31, 229] + Relocator.little(names[name]!.address, 4);
                        default: data = component.data
                    }
                    let offset = component.address - segment.base;
                    image.replaceSubrange(offset..<(offset + data.count), with: data)
                }
            };
            segment.image = image
        }
        if let (name, symbol) = checksum {
            let segment = segments.first {
                $0.name == name
            }!, offset = names[symbol]!.address - segment.base
            segment.image.replaceSubrange(offset..<(offset + 4), with: [0, 0, 0, 0]);
            var sum = 0
            for (i, byte) in segment.image.enumerated() {
                sum += byte << (8 * (i % 4))
            };
            segment.image.replaceSubrange(offset..<(offset + 4), with: Relocator.little(mod(-sum, 4294967296), 4))
        }
    }
    func map() -> [String] {
        var lines = extractions.map {
            "member \($0.0) \($0.1) \($0.2)"
        }, symbols: [(Int, String, String, String)] = []
        for group in comdats {
            lines.append("comdat \(group.signature) \(group.keeper) \(group.discarded.isEmpty ? "-" : group.discarded.joined(separator: ","))")
        }
        for segment in segments {
            lines.append("segment \(segment.name) vaddr \(hex(segment.base)) paddr \(hex(segment.paddr)) filesz \(segment.filesz) memsz \(segment.memsz) used \(segment.used) length \(segment.length) \(100 * segment.used / segment.length)%")
            for i in segment.outputs {
                let output = outputs[i];
                lines.append("section \(output.name) \(hex(output.address)) \(output.size) \(output.alignment)")
                for component in output.components {
                    switch component.kind {
                        case .input(let reference): lines.append("input \(hex(component.address)) \(component.size) \(component.alignment) \(objects[reference.object].name) \(objects[reference.object].sections[reference.index].name)")
                        case .merged(let data): lines.append("merged \(hex(component.address)) \(component.size) sections \(data.sections) strings \(data.strings) unique \(data.unique) saved \(data.saved)")
                        case .common(let name): lines.append("common \(hex(component.address)) \(component.size) \(component.alignment) \(names[name]!.definer) \(name)")
                        case .veneer(let name): lines.append("veneer \(hex(component.address)) 8 \(name)");
                        symbols.append((component.address, "__veneer_" + name, "veneer", "*linker*"))
                    }
                }
            }
        }
        for object in objects {
            for section in object.sections {
                if let reason = section.discard {
                    lines.append("discard \(object.name) \(section.name) \(section.size) \(reason)")
                }
            }
        }
        for name in names.keys.sorted() {
            let resolution = names[name]!
            if resolution.kind == "common" && !resolution.live {
                lines.append("discard \(resolution.definer) COMMON(\(name)) \(resolution.size) gc")
            }
            if resolution.live && ["global", "weak", "common", "script"].contains(resolution.kind) {
                symbols.append((resolution.address, name, resolution.kind, resolution.definer))
            }
        }
        for (address, name, kind, definer) in symbols.sorted(by: {
            ($0.0, $0.1) < ($1.0, $1.1)
        }) {
            lines.append("symbol \(hex(address)) \(name) \(kind) \(definer)")
        };
        return lines
    }
    func xref() -> [String] {
        names.keys.sorted().map {
            name in let r = names[name]!, status = ["undefined", "weakundef"].contains(r.kind) ? "-" : r.live ? "kept" : "discarded";
            return "\(name) \(r.kind) \(status) \(r.definer) \(r.referrers.isEmpty ? "-" : r.referrers.map { objects[$0].name }.joined(separator: ","))"
        }
    }
    func output(_ relocations: [String], _ diagnostics: inout [String]) {
        let resolution = names[entry], address = resolution.map {
            ["global", "weak", "common"].contains($0.kind) ? $0.address : 0
        } ?? 0
        var image = ["entry \(hex(address)) \(entry)"]
        for segment in segments {
            image.append("segment \(segment.name) vaddr \(hex(segment.base)) paddr \(hex(segment.paddr)) filesz \(segment.filesz) memsz \(segment.memsz)")
            for k in stride(from: 0, to: segment.image.count, by: 16) {
                image.append(hex(segment.base + k) + " " + segment.image[k..<min(k + 16, segment.image.count)].map {
                    hex($0, 2)
                }.joined(separator: " "))
            }
        }
        var ihex: [String] = [], upper = 0
        let sorted = segments.enumerated().filter {
            $0.element.filesz > 0
        }.sorted {
            $0.element.paddr == $1.element.paddr ? $0.offset < $1.offset : $0.element.paddr < $1.element.paddr
        }.map(\.element)
        for segment in sorted {
            var k = 0
            while k < segment.filesz {
                let a = segment.paddr + k, n = min(16, segment.filesz - k, 65536 - mod(a, 65536))
                if a / 65536 != upper {
                    upper = a / 65536;
                    ihex.append(record(0, 4, [upper / 256, upper % 256]))
                }
                ihex.append(record(mod(a, 65536), 0, Array(segment.image[k..<(k + n)])));
                k += n
            }
        }
        ihex += [record(0, 5, [24, 16, 8, 0].map {
            (address >> $0) & 255
        }), record(0, 1, [])]
        let errors = diagnostics.filter {
            $0.hasPrefix("error")
        }.count, warnings = diagnostics.filter {
            $0.hasPrefix("warning")
        }.count;
        diagnostics.append("errors \(errors) warnings \(warnings)")
        write("image.hex", image);
        write("flash.ihex", ihex);
        write("link.map", map());
        write("xref.txt", xref());
        write("relocations.txt", relocations);
        write("diagnostics.txt", diagnostics)
    }
    func run() {
        loadInputs();
        collect();
        finishLayout();
        var diagnostics = self.diagnostics();
        let relocations = relocate(&diagnostics);
        images();
        output(relocations, &diagnostics)
    }
}
final class ScriptParser {
    let tokens: [String], values: [String: Int], outputs: [OutputSection], segments: [Segment];
    var index = 0
    init(_ expression: String, _ values: [String: Int], _ outputs: [OutputSection], _ segments: [Segment]) {
        let bytes = Array(expression.utf8);
        var tokens: [String] = [], i = 0
        while i < bytes.count {
            if bytes[i] == 32 {
                i += 1;
                continue
            };
            let start = i;
            if Array("(),+-".utf8).contains(bytes[i]) {
                i += 1
            } else {
                while i < bytes.count && bytes[i] != 32 && !Array("(),+-".utf8).contains(bytes[i]) {
                    i += 1
                }
            };
            tokens.append(String(decoding: bytes[start..<i], as: UTF8.self))
        }
        self.tokens = tokens;
        self.values = values;
        self.outputs = outputs;
        self.segments = segments
    }
    var peek: String {
        index < tokens.count ? tokens[index] : ""
    }
    func expression() -> Int {
        var value = term();
        while peek == "+" || peek == "-" {
            let op = peek;
            index += 1;
            let right = term();
            value = op == "+" ? value + right : value - right
        };
        return value
    }
    func term() -> Int {
        let token = tokens[index];
        index += 1
        if token == "(" {
            let value = expression();
            index += 1;
            return value
        }
        if token.utf8.first.map({
            (48...57).contains($0)
        }) ?? false {
            return number(token)
        }
        if peek != "(" {
            return values[token]!
        };
        index += 1
        if token == "align" {
            let value = expression();
            index += 1;
            let alignment = expression();
            index += 1;
            return align(value, alignment)
        }
        let name = tokens[index];
        index += 2;
        let i = outputs.firstIndex {
            $0.name == name
        }!, output = outputs[i]
        switch token {
            case "start": return output.address;
            case "end": return output.address + output.size;
            case "size": return output.size;
            default: let segment = segments.first {
                $0.outputs.contains(i)
            }!;
            return segment.paddr + output.address - segment.base
        }
    }
}
func record(_ address: Int, _ type: Int, _ data: [Int]) -> String {
    var bytes = [data.count, (address >> 8) & 255, address & 255, type] + data;
    bytes.append(mod(-bytes.reduce(0, +), 256));
    return ":" + bytes.map {
        hex($0, 2, true)
    }.joined()
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
Linker().run()
