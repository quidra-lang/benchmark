fn main() {
    let boards = [["XXX", "OO.", "O.X"], ["X.O", ".X.", "O.."], ["XO.", ".OX", "XO."], ["XOX", "XOO",
        "OXX"], ["X.O", "XO.", "O.X"], ["XOX", "OXO", "OXX"]];
    let lines = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4,
        6]];
    for (k, b) in boards.iter().enumerate() {
        let cells: Vec<u8> = b.iter().flat_map(|r| r.bytes()).collect();
        let mut winner = None;
        for[a, b, c] in lines {
            if cells[a] != b'.' && cells[a] == cells[b] && cells[b] == cells[c] {
                winner = Some(cells[a] as char);
            }
        }
        let result = if let Some(c) = winner {
            format!("{} wins", c)
        } else if cells.contains(&b'.') {
            "in progress".to_string()
        } else {
            "draw".to_string()
        };
        println!("board {}: {}", k + 1, result);
    }
}
