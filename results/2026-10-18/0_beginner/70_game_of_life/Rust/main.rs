fn main() {
    let initial = [
        ".#......", "..#.....", "###.....", "........", "........", "........", ".....###",
        "........",
    ];
    let mut board = [[b'.'; 8]; 8];
    for r in 0..8 {
        board[r].copy_from_slice(initial[r].as_bytes());
    }
    for g in 0..=4 {
        println!("generation {}", g);
        for row in board {
            println!("{}", std::str::from_utf8(&row).unwrap());
        }
        if g == 4 {
            break;
        }
        let mut next = [[b'.'; 8]; 8];
        for r in 0..8 {
            for c in 0..8 {
                let mut neighbors = 0;
                for dr in -1..=1 {
                    for dc in -1..=1 {
                        let rr = r as i32 + dr;
                        let cc = c as i32 + dc;
                        if (dr != 0 || dc != 0)
                            && (0..8).contains(&rr)
                            && (0..8).contains(&cc)
                            && board[rr as usize][cc as usize] == b'#'
                        {
                            neighbors += 1;
                        }
                    }
                }
                if neighbors == 3 || (board[r][c] == b'#' && neighbors == 2) {
                    next[r][c] = b'#';
                }
            }
        }
        board = next;
    }
    let alive = board.iter().flatten().filter(|&&c| c == b'#').count();
    println!("alive: {}", alive);
}
