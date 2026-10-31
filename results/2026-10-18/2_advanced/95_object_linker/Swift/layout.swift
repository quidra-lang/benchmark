struct MergedPosition {
    let reference: Reference, offset: Int, merged: Int
}
struct MergedData {
    let sections: Int, strings: Int, unique: Int, saved: Int, positions: [MergedPosition]
}
enum ComponentKind {
    case input(Reference), merged(MergedData), common(String), veneer(String)
}
final class Component {
    let kind: ComponentKind, size: Int, alignment: Int;
    var address = 0, data: [Int]
    init(_ kind: ComponentKind, _ size: Int, _ alignment: Int, _ data: [Int] = []) {
        self.kind = kind;
        self.size = size;
        self.alignment = alignment;
        self.data = data
    }
}
final class OutputSection {
    let name: String;
    var components: [Component] = [], address = 0, size = 0, alignment = 1
    init(_ name: String) {
        self.name = name
    }
}
final class Segment {
    let name: String, base: Int, length: Int, fill: Int, outputs: [Int]
    var memsz = 0, filesz = 0, paddr = 0, used = 0, image: [Int] = []
    init(_ name: String, _ base: Int, _ length: Int, _ fill: Int, _ outputs: [Int]) {
        self.name = name;
        self.base = base;
        self.length = length;
        self.fill = fill;
        self.outputs = outputs
    }
}
func mod(_ x: Int, _ n: Int) -> Int {
    let r = x % n;
    return r < 0 ? r + n : r
}
func align(_ x: Int, _ n: Int) -> Int {
    x + mod(n - mod(x, n), n)
}
enum Layout {
    static func output(_ name: String, _ outputs: [OutputSection]) -> Int? {
        outputs.firstIndex {
            belongs(name, $0.name)
        }
    }
    static func assign(_ segment: Segment, _ outputs: [OutputSection]) {
        var cursor = segment.base;
        segment.filesz = 0
        for i in segment.outputs {
            let output = outputs[i];
            output.alignment = output.components.map(\.alignment).max() ?? 1;
            cursor = align(cursor, output.alignment);
            output.address = cursor
            for component in output.components {
                cursor = align(cursor, component.alignment);
                component.address = cursor;
                cursor += component.size
            }
            output.size = cursor - output.address;
            if !nobits(output.name) {
                segment.filesz = cursor - segment.base
            }
        };
        segment.memsz = cursor - segment.base;
        segment.paddr = segment.base;
        segment.used = segment.memsz
    }
}
