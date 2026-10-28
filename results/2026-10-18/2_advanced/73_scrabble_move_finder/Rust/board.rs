use std::collections::VecDeque;
pub const SIZE: usize = 15;
pub const CENTER: (usize,usize) = (7,7);
pub type Board = [[u8;SIZE];SIZE];
pub const PREMIUM: [&str;SIZE] = ["#..+...#...+..#",".*...^...^...*.","..*...+.+...*..","+..*...+...*..+","....*.....*....",".^...^...^...^.","..+...+.+...+..","#..+...*...+..#","..+...+.+...+..",".^...^...^...^.","....*.....*....","+..*...+...*..+","..*...+.+...*..",".*...^...^...*.","#..+...#...+..#"];
#[derive(Clone)] pub struct Word {
    pub row: usize,
    pub column: usize,
    pub down: bool,
    pub text: Vec<u8>
}
pub fn empty() -> Board {
    [[b'.';SIZE];SIZE]
}
pub fn square(row: usize, column: usize) -> String {
    format!("{}{}",(b'A'+column as u8) as char,row+1)
}
pub fn position(row: usize, column: usize, down: bool) -> String {
    if down {
        square(row,column)
    } else {
        format!("{}{}",row+1,(b'A'+column as u8) as char)
    }
}
pub fn number(text: &str, low: i64, high: i64) -> Option<i64> {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) || (text.len() > 1 && text.starts_with('0')) {
        return None;
    }
    text.parse::<i64>().ok().filter(|&v| low <= v && v <= high)
}
pub fn parse_position(text: &str) -> Option<(usize,usize,bool)> {
    let bytes = text.as_bytes();
    if bytes.len() < 2 {
        return None;
    }
    if (b'A'..=b'O').contains(&bytes[0]) {
        number(&text[1..],1,15).map(|r| (r as usize-1,(bytes[0]-b'A') as usize,true))
    } else {
        let letter = *bytes.last().unwrap();
        if !(b'A'..=b'O').contains(&letter) {
            None
        } else {
            number(&text[..text.len()-1],1,15).map(|r| (r as usize-1,(letter-b'A') as usize,false))
        }
    }
}
pub fn transpose(board: &Board) -> Board {
    let mut result = empty();
    for r in 0..SIZE {
        for c in 0..SIZE {
            result[r][c] = board[c][r];
        }
    }
    result
}
pub fn tiles(board: &Board) -> Vec<(usize,usize,u8)> {
    let mut result = Vec::new();
    for r in 0..SIZE {
        for c in 0..SIZE {
            if board[r][c] != b'.' {
                result.push((r,c,board[r][c]));
            }
        }
    }
    result
}
pub fn neighbors(row: usize, column: usize) -> Vec<(usize,usize)> {
    let mut result = Vec::new();
    for (dr,dc) in [(-1,0),(1,0),(0,-1),(0,1)].iter().copied() {
        let r = row as i32+dr;
        let c = column as i32+dc;
        if r >= 0 && c >= 0 && r < SIZE as i32 && c < SIZE as i32 {
            result.push((r as usize,c as usize));
        }
    }
    result
}
pub fn connected(board: &Board) -> bool {
    let occupied = tiles(board);
    let Some(&(r,c,_)) = occupied.first() else {
        return true;
    };
    let mut seen = [[false;SIZE];SIZE];
    seen[r][c] = true;
    let mut queue = VecDeque::from([(r,c)]);
    let mut count = 0;
    while let Some((r,c)) = queue.pop_front() {
        count += 1;
        for (a,b) in neighbors(r,c) {
            if board[a][b] != b'.' && !seen[a][b] {
                seen[a][b] = true;
                queue.push_back((a,b));
            }
        }
    }
    count == occupied.len()
}
pub fn words(board: &Board) -> Vec<Word> {
    let mut result = Vec::new();
    for down in [false,true].iter().copied() {
        for outer in 0..SIZE {
            let mut inner = 0;
            while inner < SIZE {
                let (r,c) = if down {
                    (inner,outer)
                } else {
                    (outer,inner)
                };
                if board[r][c] == b'.' {
                    inner += 1;
                    continue;
                }
                let start = inner;
                let mut text = Vec::new();
                while inner < SIZE {
                    let (r,c) = if down {
                        (inner,outer)
                    } else {
                        (outer,inner)
                    };
                    if board[r][c] == b'.' {
                        break;
                    }
                    text.push(board[r][c]);
                    inner += 1;
                }
                if text.len() >= 2 {
                    let (row,column) = if down {
                        (start,outer)
                    } else {
                        (outer,start)
                    };
                    result.push(Word {
                        row,
                        column,
                        down,
                        text
                    });
                }
            }
        }
    }
    result
}
pub fn display(board: &Board) -> Vec<String> {
    let mut lines = vec![format!("   {}",(b'A'..=b'O').map(|b| (b as char).to_string()).collect::<Vec<_>>().join(" "))];
    for r in 0..SIZE {
        let cells = (0..SIZE).map(|c| (if board[r][c] == b'.' {
            PREMIUM[r].as_bytes()[c]
        } else {
            board[r][c]
        }
        as char).to_string()).collect::<Vec<_>>().join(" ");
        lines.push(format!("{:>2} {}",r+1,cells));
    }
    lines
}
