use crate::board::{self,Board,Word};
use crate::move_generator::Move;
pub const RACK_SIZE: usize = 7;
pub const BINGO: i64 = 50;
pub fn squares(m: &Move) -> Vec<(usize,usize,u8)> {
    m.word.iter().enumerate().map(|(i,&tile)| (m.row+if m.down {
        i
    } else {
        0
    },m.column+if m.down {
        0
    } else {
        i
    },tile)).collect()
}
pub fn placement(board: &Board, m: &Move) -> Vec<(usize,usize,u8)> {
    let mut result: Vec<_> = squares(m).into_iter().filter(|&(r,c,_)| board[r][c] == b'.').collect();
    result.sort();
    result
}
pub fn apply(board: &Board, m: &Move) -> Board {
    let mut result = *board;
    for (r,c,tile) in placement(board,m) {
        result[r][c] = tile;
    }
    result
}
pub fn words(board: &Board, m: &Move) -> Vec<Word> {
    let after = apply(board,m);
    let mut result = vec![Word {
        row: m.row,column: m.column,down: m.down,text: m.word.clone()
    }];
    for (r,c,_) in squares(m) {
        if board[r][c] != b'.' {
            continue;
        }
        let down = !m.down;
        let (mut first_r,mut first_c) = (r,c);
        while if down {
            first_r > 0 && after[first_r-1][first_c] != b'.'
        } else {
            first_c > 0 && after[first_r][first_c-1] != b'.'
        }
        {
            if down {
                first_r -= 1;
            } else {
                first_c -= 1;
            }
        }
        let (mut row,mut column) = (first_r,first_c);
        let mut text = Vec::new();
        while row < 15 && column < 15 && after[row][column] != b'.' {
            text.push(after[row][column]);
            if down {
                row += 1;
            } else {
                column += 1;
            }
        }
        if text.len() >= 2 {
            result.push(Word {
                row: first_r,
                column: first_c,
                down,
                text
            });
        }
    }
    result
}
pub fn word_score(board: &Board, word: &Word, values: &[i64;27]) -> i64 {
    let mut sum = 0;
    let mut multiplier = 1;
    for (i,&tile) in word.text.iter().enumerate() {
        let row = word.row+if word.down {
            i
        } else {
            0
        };
        let column = word.column+if word.down {
            0
        } else {
            i
        };
        let mut value = if tile.is_ascii_lowercase() {
            0
        } else {
            values[(tile-b'A') as usize]
        };
        if board[row][column] == b'.' {
            match board::PREMIUM[row].as_bytes()[column] {
                b'+' => value *= 2,b'^' => value *= 3,b'*' => multiplier *= 2,b'#' => multiplier *= 3,_ => ()
            }
        }
        sum += value;
    }
    sum*multiplier
}
pub fn score(board: &Board, movement: &Move, values: &[i64;27]) -> (i64,usize,String) {
    let tiles = placement(board,movement).len();
    let words = words(board,movement);
    let scores: Vec<_> = words.iter().map(|word| word_score(board,word,values)).collect();
    let mut score: i64 = scores.iter().sum();
    if tiles == RACK_SIZE {
        score += BINGO;
    }
    let notation = words.iter().zip(scores).map(|(w,s)| format!("{}:{}",String::from_utf8(w.text.clone()).unwrap(),s)).collect::<Vec<_>>().join(",");
    (score,tiles,notation)
}
