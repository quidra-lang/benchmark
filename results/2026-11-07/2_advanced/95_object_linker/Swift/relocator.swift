enum Relocator {
    static let types = ["ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24"]
    static func width(_ kind: String) -> Int {
        kind == "ABS32" || kind == "REL32" ? 4 : kind == "CALL24" ? 3 : 2
    }
    static func value(_ kind: String, _ symbol: Int, _ addend: Int, _ position: Int, _ gp: Int) -> Int {
        symbol + addend - (["REL32", "CALL24"].contains(kind) ? position : kind == "GPREL16" ? gp : 0)
    }
    static func fits(_ kind: String, _ value: Int) -> Bool {
        let low: Int, high: Int
        switch kind {
            case "ABS32", "HI16": low = -2147483648;
            high = 4294967296;
            case "REL32": low = -2147483648;
            high = 2147483648;
            case "ABS16": low = -32768;
            high = 65536;
            case "GPREL16": low = -32768;
            high = 32768;
            case "CALL24": low = -33554432;
            high = 33554432;
            default: return true
        };
        return value >= low && value < high
    }
    static func field(_ kind: String, _ value: Int) -> Int {
        switch kind {
            case "HI16": return mod((mod(value, 4294967296) + 32768) / 65536, 65536);
            case "CALL24": return mod((value - mod(value, 4)) / 4, 16777216);
            case "ABS32", "REL32": return mod(value, 4294967296);
            default: return mod(value, 65536)
        }
    }
    static func unpaired(_ relocations: [Relocation], _ index: Int) -> Bool {
        let current = relocations[index];
        if current.kind != "HI16" {
            return false
        };
        if index + 1 == relocations.count {
            return true
        };
        let next = relocations[index + 1];
        return next.kind != "LO16" || next.symbol != current.symbol || next.addend != current.addend
    }
    static func little(_ value: Int, _ width: Int) -> [Int] {
        (0..<width).map {
            (value >> (8 * $0)) & 255
        }
    }
}
