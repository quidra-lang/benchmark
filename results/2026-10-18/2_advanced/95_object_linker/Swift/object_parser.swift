import Foundation
struct Reference: Hashable {
    let object: Int, index: Int
}
final class Section {
    let name: String, alignment: Int, size: Int
    var data: [Int] = [], discard: String?, output: Int?, live = false, address = 0, strings: [Int: Int] = [:]
    init(_ name: String, _ alignment: Int, _ size: Int) {
        self.name = name;
        self.alignment = alignment;
        self.size = size
    }
}
enum Definition {
    case section(Int, Int), undefined, common(Int, Int)
}
final class Symbol {
    var name: String, definition: Definition;
    let binding: String
    init(_ name: String, _ binding: String, _ definition: Definition) {
        self.name = name;
        self.binding = binding;
        self.definition = definition
    }
}
struct Relocation {
    let section: Int, offset: Int, kind: String, symbol: Int, addend: Int
}
final class Object {
    let name: String;
    var sections: [Section] = [], groups: [(String, [Int])] = [], symbols: [Symbol] = [], relocations: [Relocation] = []
    init(_ name: String) {
        self.name = name
    }
}
func belongs(_ name: String, _ output: String) -> Bool {
    name == output || name.hasPrefix(output + ".")
}
func nobits(_ name: String) -> Bool {
    belongs(name, ".bss")
}
func stringSection(_ name: String) -> Bool {
    belongs(name, ".rodata.str")
}
enum ObjectParser {
    static func lines(_ name: String) -> [String] {
        try! String(contentsOfFile: "input/" + name, encoding: .ascii).split(separator: "\n").map(String.init)
    }
    static func parse(_ name: String, _ lines: [String]) -> Object {
        let object = Object(name)
        for line in lines {
            let fields = line.split(separator: " ").map(String.init)
            switch fields[0] {
                case "section": object.sections.append(Section(fields[1], Int(fields[2])!, Int(fields[3])!))
                case "data": let bytes = Array(fields[1].utf8);
                for i in stride(from: 0, to: bytes.count, by: 2) {
                    object.sections.last!.data.append(Int(String(decoding: bytes[i..<(i + 2)], as: UTF8.self), radix: 16)!)
                }
                case "comdat": object.groups.append((fields[1], fields.dropFirst(2).map {
                    name in object.sections.firstIndex {
                        $0.name == name
                    }!
                }))
                case "symbol":
                let definition: Definition
                if fields[3] == "undef" {
                    definition = .undefined
                }
                else if fields[3] == "common" {
                    definition = .common(Int(fields[4])!, Int(fields[5])!)
                }
                else {
                    definition = .section(object.sections.firstIndex {
                        $0.name == fields[3]
                    }!, Int(fields[4])!)
                }
                object.symbols.append(Symbol(fields[1], fields[2], definition))
                case "reloc": object.relocations.append(Relocation(section: object.sections.firstIndex {
                    $0.name == fields[1]
                }!, offset: Int(fields[2])!, kind: fields[3], symbol: object.symbols.firstIndex {
                    $0.name == fields[4]
                }!, addend: Int(fields[5])!))
                default: break
            }
        };
        return object
    }
}
