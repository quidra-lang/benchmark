import Foundation
struct HeapObject {
    var size: Int,
    fields: [Int?],
    address = 0,
    marked = false,
    moves = 0,
    age = 0,
    count = 0,
    present = true
    init(_ p: Int, _ d: Int) {
        size = 1+p+d;
        fields = Array(repeating: nil, count: p)
    }
}
struct Pair {
    var count = 0,
    words = 0
    mutating func add(_ o: HeapObject) {
        count += 1;
        words += o.size
    }
    mutating func merge(_ p: Pair) {
        count += p.count;
        words += p.words
    }
    var text: String {
        "\(count) \(words)"
    }
}
struct Record {
    let line: Int,
    request: Int,
    kind: String;
    var live = Pair(),
    freed = Pair(),
    moved = Pair(),
    promoted = Pair(),
    stack = 0,
    work = 0,
    before: (Int, Int),
    after = (0, 0)
    init(_ line: Int, _ request: Int, _ kind: String, _ blocks: [(Int, Int)]) {
        self.line = line;
        self.request = request;
        self.kind = kind;
        before = freeAmount(blocks)
    }
}
final class Memory {
    let algorithm: String,
    size: Int,
    young: Int,
    promotionAge: Int;
    var objects = [HeapObject](),
    base = 0,
    top = 0,
    remembered = Set<Int>(),
    barriers = 0,
    remembers = 0,
    records = [Record]()
    init(_ entry: Collector, _ size: Int) {
        algorithm = entry.algorithm;
        self.size = size;
        young = entry.young;
        promotionAge = entry.age
    }
    var ids: [Int] {
        objects.indices.filter {
            objects[$0].present
        }
    }
    var oldBlocks: [(Int, Int)] {
        freeBlocks(objects, young, size)
    }
    var freeList: [(Int, Int)] {
        switch algorithm {
            case "MARK_SWEEP", "REFCOUNT": return freeBlocks(objects, 0, size);
            case "MARK_COMPACT": return top<size ? [(top, size-top)] : [];
            default: let half = algorithm == "COPYING" ? size/2 : young/2;
            var out = top<base+half ? [(top, base+half-top)] : [];
            if algorithm == "GENERATIONAL" {
                out += oldBlocks
            };
            return out
        }
    }
    var inactive: (Int, Int) {
        let half = algorithm == "COPYING" ? size/2 : algorithm == "GENERATIONAL" ? young/2 : 0;
        return(half-base, 2*half-base)
    }
    func pair(_ ids: [Int]) -> Pair {
        var p = Pair();
        for i in ids {
            p.add(objects[i])
        };
        return p
    }
    func ordered(_ ids: [Int]) -> [Int] {
        ids.sorted {
            objects[$0].address<objects[$1].address
        }
    }
}
func freeBlocks(_ objects: [HeapObject], _ start: Int, _ end: Int) -> [(Int, Int)] {
    let list = objects.filter {
        $0.present && $0.address >= start && $0.address<end
    }.sorted {
        $0.address<$1.address
    };
    var position = start, out = [(Int, Int)]();
    for o in list {
        if o.address>position {
            out.append((position, o.address-position))
        };
        position = o.address+o.size
    };
    if position<end {
        out.append((position, end-position))
    };
    return out
}
func firstFit(_ blocks: [(Int, Int)], _ size: Int) -> Int? {
    blocks.first {
        $0.1 >= size
    }?.0
}
func freeAmount(_ blocks: [(Int, Int)]) -> (Int, Int) {
    (blocks.reduce(0) {
        $0+$1.1
    }, blocks.map {
        $0.1
    }.max() ?? 0)
}
func dec2(_ a: Int, _ b: Int) -> String {
    let z = (200*a+b)/(2*b);
    return "\(z/100)."+String(format: "%02d", z%100)
}
func pct(_ a: Int, _ b: Int) -> String {
    b == 0 ? "-" : dec2(100*a, b)
}
func classTable(_ values: [Int]) -> String {
    var counts = Array(repeating: 0, count: 5);
    for v in values {
        let k = [1, 3, 7, 15].firstIndex {
            $0 >= v
        } ?? 4;
        counts[k] += 1
    };
    return zip(["1", "2-3", "4-7", "8-15", "16+"], counts).map {
        "\($0.0):\($0.1)"
    }.joined(separator: " ")
}
func heapMap(_ m: Memory, _ reached: Set<Int>) -> String {
    var cells = Array(repeating: UInt8(46), count: m.size);
    let(lo, hi) = m.inactive;
    for a in lo..<hi {
        cells[a] = 45
    };
    for i in m.ids {
        let o = m.objects[i], live = reached.contains(i);
        cells[o.address] = live ? UInt8(65+i%26) : 35;
        for a in (o.address+1)..<(o.address+o.size) {
            cells[a] = live ? UInt8(97+i%26) : 61
        }
    };
    return String(bytes: cells, encoding: .utf8)!
}
