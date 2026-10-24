fn search(board: &[&str], word: &str) -> Option<(i32, i32, usize)> {
    let directions = [(0, 1), (1, 1), (1, 0), (1, -1),
                      (0, -1), (-1, -1), (-1, 0), (-1, 1)];
    for r in 0..10_i32 {
        for c in 0..10_i32 {
            for (d, (dr, dc)) in directions.iter().enumerate() {
                if word.bytes().enumerate().all(|(k, ch)| {
                    let rr = r + dr * k as i32;
                    let cc = c + dc * k as i32;
                    (0..10).contains(&rr) && (0..10).contains(&cc)
                        && board[rr as usize].as_bytes()[cc as usize] == ch
                }) {
                    return Some((r, c, d));
                }
            }
        }
    }
    None
}

fn main() {
    let board = ["MMONKENBIR", "PMTIGERJPL", "TGREJEDUZI", "SPYUTEJDEC", "WKAPSIDLBN",
                 "KUVNGSBPRO", "RIBSDACBAM", "YWVAUAPKAH", "KYCGTHHESR", "OCCALAOKKR"];
    let names = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"];
    for word in ["TIGER", "ZEBRA", "MONKEY", "PANDA", "KOALA", "RABBIT"] {
        if let Some((r, c, d)) = search(&board, word) {
            println!("{}: ({}, {}) {}", word, r, c, names[d]);
        } else {
            println!("{}: not found", word);
        }
    }
}
