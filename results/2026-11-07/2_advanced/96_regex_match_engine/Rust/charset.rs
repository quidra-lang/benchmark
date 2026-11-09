use std::collections::BTreeSet;
use crate::Flags;
pub type Set = BTreeSet<u8>;
pub fn word(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_'
}
pub fn swap(c: u8) -> u8 {
    if c.is_ascii_lowercase() {
        c.to_ascii_uppercase()
    } else if c.is_ascii_uppercase() {
        c.to_ascii_lowercase()
    } else {
        c
    }
}
pub fn equal(a: u8, b: u8, flags: Flags) -> bool {
    a == b || (flags.i && a.is_ascii_alphabetic() && swap(a) == b)
}
pub fn base(c: u8) -> Set {
    let lower = c.to_ascii_lowercase();
    let mut set: Set = (0..128).filter(|&c| match lower {
        b'd' => c >= b'0' && c <= b'9',
        b'w' => word(c),
        _ => [9, 10, 11, 12, 13, 32].contains(&c)
    }).collect();
    if c.is_ascii_uppercase() {
        set = (0..128).filter(|c| !set.contains(c)).collect();
    }
    set
}
pub fn class(c: u8, set: &Set, negated: bool, flags: Flags) -> bool {
    (set.contains(&c) || (flags.i && c.is_ascii_alphabetic() && set.contains(&swap(c)))) != negated
}
pub fn assertion(kind: &str, subject: &[u8], q: usize, flags: Flags) -> bool {
    match kind {
        "BOL" => q == 0 || (flags.m && subject[q - 1] == 10),
        "EOL" => q == subject.len() || (flags.m && subject[q] == 10),
        _ => {
            let left = q > 0 && word(subject[q - 1]);
            let right = q < subject.len() && word(subject[q]);
            (left != right) == (kind == "WORD")
        }
    }
}
