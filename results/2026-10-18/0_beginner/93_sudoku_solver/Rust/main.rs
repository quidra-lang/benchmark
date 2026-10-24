fn solve(board: &mut [[u8; 9]; 9], placements: &mut u64) -> bool {
    let empty = (0..81).find(|&i| board[i / 9][i % 9] == 0);
    let Some(index) = empty else {
        return true;
    };
    let (row, col) = (index / 9, index % 9);
    for d in 1..=9 {
        let safe = (0..9).all(|k| board[row][k] != d && board[k][col] != d)
            && (row / 3 * 3..row / 3 * 3 + 3).all(|r|
                (col / 3 * 3..col / 3 * 3 + 3).all(|c| board[r][c] != d));
        if safe {
            board[row][col] = d;
            *placements += 1;
            if solve(board, placements) {
                return true;
            }
            board[row][col] = 0;
        }
    }
    false
}

fn main() {
    let rows = ["800025000", "070080005", "260400070", "000001900", "010000040", "600200000", "900010000",
        "700000004", "020000036"];
    let mut board = [[0; 9]; 9];
    for r in 0..9 {
        for c in 0..9 {
            board[r][c] = rows[r].as_bytes()[c] - b'0';
        }
    }
    let mut placements = 0;
    solve(&mut board, &mut placements);
    for row in board {
        for (c, d) in row.iter().enumerate() {
            if c > 0 {
                print!(" ");
            }
            print!("{}", d);
        }
        println!();
    }
    println!("placements: {}", placements);
}
