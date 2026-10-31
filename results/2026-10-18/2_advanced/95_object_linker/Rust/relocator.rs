use crate::object_parser::Relocation;
pub const TYPES: [&str;
7] = ["ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24"];
pub fn width(kind: &str) -> usize {
    match kind {
        "ABS32" | "REL32" => 4,
        "CALL24" => 3,
        _ => 2
    }
}
pub fn value(kind: &str, symbol: i64, addend: i64, position: i64, gp: i64) -> i64 {
    symbol + addend - match kind {
        "REL32" | "CALL24" => position,
        "GPREL16" => gp,
        _ => 0
    }
}
pub fn fits(kind: &str, value: i64) -> bool {
    let (low, high) = match kind {
        "ABS32" | "HI16" => (-2147483648, 4294967296),
        "REL32" => (-2147483648, 2147483648),
        "ABS16" => (-32768, 65536),
        "GPREL16" => (-32768, 32768),
        "CALL24" => (-33554432, 33554432),
        _ => return true
    };
    value >= low && value < high
}
pub fn field(kind: &str, value: i64) -> i64 {
    match kind {
        "HI16" => ((value.rem_euclid(4294967296) + 32768) / 65536).rem_euclid(65536),
        "CALL24" => value.div_euclid(4).rem_euclid(16777216),
        "ABS32" | "REL32" => value.rem_euclid(4294967296),
        _ => value.rem_euclid(65536)
    }
}
pub fn unpaired(relocations: &[Relocation], index: usize) -> bool {
    let current = &relocations[index];
    current.kind == "HI16" && !relocations.get(index + 1).map_or(false, |next| next.kind == "LO16" && next.symbol == current.symbol && next.addend == current.addend)
}
pub fn little(value: i64, width: usize) -> Vec<u8> {
    (0..width).map(|n| ((value >> (8 * n)) & 255) as u8).collect()
}
