#[derive(Clone,Copy)] pub struct Tile {
    pub kind: usize,
    pub red: bool
}
pub fn parse(source: &str, empty: bool) -> Option<Vec<Tile>> {
    if source == "-" && empty {
        return Some(Vec::new());
    }
    if source.is_empty() {
        return None;
    }
    let mut digits = Vec::new();
    let mut tiles = Vec::new();
    for byte in source.bytes() {
        if byte.is_ascii_digit() {
            digits.push(byte-b'0');
            continue;
        }
        let suit = b"mpsz".iter().position(|&s| s == byte)?;
        if digits.is_empty() {
            return None;
        }
        for digit in digits.drain(..) {
            if suit == 3 {
                if !(1..=7).contains(&digit) {
                    return None;
                }
                tiles.push(Tile {
                    kind: 27+digit as usize-1,
                    red: false
                });
            } else {
                let red = digit == 0;
                let number = if red {
                    5
                } else {
                    digit as usize
                };
                tiles.push(Tile {
                    kind: 9*suit+number-1,
                    red
                });
            }
        }
    }
    if !digits.is_empty() || tiles.is_empty() {
        None
    } else {
        Some(tiles)
    }
}
pub fn name(kind: usize) -> String {
    if kind < 27 {
        format!("{}{}",kind%9+1,b"mps"[kind/9] as char)
    } else {
        format!("{}z",kind-26)
    }
}
pub fn block(kinds: &[usize]) -> String {
    let mut kinds = kinds.to_vec();
    kinds.sort_unstable();
    let mut text: String = kinds.iter().map(|&k| (b'0'+if k < 27 {
        (k%9+1) as u8
    } else {
        (k-26) as u8
    }) as char).collect();
    text.push(if kinds[0] < 27 {
        b"mps"[kinds[0]/9] as char
    } else {
        'z'
    });
    text
}
pub fn counts(tiles: &[Tile]) -> [u8;34] {
    let mut counts = [0;34];
    for tile in tiles {
        counts[tile.kind] += 1;
    }
    counts
}
pub fn terminal(kind: usize) -> bool {
    kind < 27 && (kind%9 == 0 || kind%9 == 8)
}
pub fn yaochuu(kind: usize) -> bool {
    kind >= 27 || terminal(kind)
}
pub fn green(kind: usize) -> bool {
    [19,20,21,23,25,32].contains(&kind)
}
pub fn next(kind: usize) -> usize {
    if kind < 27 {
        kind/9*9+(kind%9+1)%9
    } else if kind < 31 {
        27+(kind-27+1)%4
    } else {
        31+(kind-31+1)%3
    }
}
