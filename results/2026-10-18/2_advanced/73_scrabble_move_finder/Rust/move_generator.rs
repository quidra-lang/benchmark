use crate::board::{self,Board,SIZE};
use crate::dictionary_trie::Trie;
#[derive(Clone)] pub struct Move {
    pub row: usize,
    pub column: usize,
    pub down: bool,
    pub word: Vec<u8>
}
pub fn anchors(board: &Board) -> [[bool;SIZE];SIZE] {
    let mut anchors = [[false;SIZE];SIZE];
    if board::tiles(board).is_empty() {
        anchors[7][7] = true;
    } else {
        for r in 0..SIZE {
            for c in 0..SIZE {
                anchors[r][c] = board[r][c] == b'.' && board::neighbors(r,c).iter().any(|&(a,b)| board[a][b] != b'.');
            }
        }
    }
    anchors
}
pub fn checks(board: &Board, trie: &Trie) -> ([[u32;SIZE];SIZE],[usize;3]) {
    let mut checks = [[0u32;SIZE];SIZE];
    let mut statistics = [0;3];
    for r in 0..SIZE {
        for c in 0..SIZE {
            if board[r][c] != b'.' {
                continue;
            }
            let mut first = r;
            while first > 0 && board[first-1][c] != b'.' {
                first -= 1;
            }
            let mut last = r;
            while last+1 < SIZE && board[last+1][c] != b'.' {
                last += 1;
            }
            if first == last {
                checks[r][c] = (1<<26)-1;
                continue;
            }
            statistics[0] += 1;
            for letter in b'A'..=b'Z' {
                let word: Vec<_> = (first..=last).map(|row| if row == r {
                    letter
                } else {
                    board[row][c].to_ascii_uppercase()
                }).collect();
                if trie.contains(&word) {
                    checks[r][c] |= 1<<(letter-b'A');
                }
            }
            statistics[1] += usize::from(checks[r][c] == 0);
            statistics[2] += checks[r][c].count_ones() as usize;
        }
    }
    (checks,statistics)
}
struct Generator<'a> {
    board: &'a Board,
    trie: &'a Trie,
    anchors: [[bool;SIZE];SIZE],
    checks: [[u32;SIZE];SIZE],
    row: usize,
    anchor: usize,
    result: Vec<Move>
}
impl<'a> Generator<'a> {
    fn extend(&mut self, column: usize, start: usize, node: usize, word: &mut Vec<u8>, counts: &mut [usize;27], placed: usize) {
        if column > self.anchor && placed > 0 && word.len() >= 2 && self.trie.nodes[node].terminal && (column == SIZE || self.board[self.row][column] == b'.') {
            self.result.push(Move {
                row: self.row,
                column: start,
                down: false,
                word: word.clone()
            });
        }
        if column == SIZE {
            return;
        }
        let existing = self.board[self.row][column];
        if existing != b'.' {
            if let Some(next) = self.trie.nodes[node].children[(existing.to_ascii_uppercase()-b'A') as usize] {
                word.push(existing);
                self.extend(column+1,start,next,word,counts,placed);
                word.pop();
            }
        } else {
            for letter in 0..26 {
                if self.checks[self.row][column]&(1<<letter) == 0 {
                    continue;
                }
                if let Some(next) = self.trie.nodes[node].children[letter] {
                    for tile in [letter,26].iter().copied() {
                        if counts[tile] > 0 {
                            counts[tile] -= 1;
                            word.push(if tile == 26 {
                                b'a'+letter as u8
                            } else {
                                b'A'+letter as u8
                            });
                            self.extend(column+1,start,next,word,counts,placed+1);
                            word.pop();
                            counts[tile] += 1;
                        }
                    }
                }
            }
        }
    }
    fn left(&mut self, limit: usize, node: usize, word: &mut Vec<u8>, counts: &mut [usize;27]) {
        let length = word.len();
        self.extend(self.anchor,self.anchor-length,node,word,counts,length);
        if word.len() == limit {
            return;
        }
        for letter in 0..26 {
            if let Some(next) = self.trie.nodes[node].children[letter] {
                for tile in [letter,26].iter().copied() {
                    if counts[tile] > 0 {
                        counts[tile] -= 1;
                        word.push(if tile == 26 {
                            b'a'+letter as u8
                        } else {
                            b'A'+letter as u8
                        });
                        self.left(limit,next,word,counts);
                        word.pop();
                        counts[tile] += 1;
                    }
                }
            }
        }
    }
    fn generate(mut self, rack: &[u8]) -> Vec<Move> {
        let mut counts = [0;27];
        for &tile in rack {
            counts[if tile == b'?' {
                26
            } else {
                (tile-b'A') as usize
            }] += 1;
        }
        for r in 0..SIZE {
            for c in 0..SIZE {
                if !self.anchors[r][c] {
                    continue;
                }
                self.row = r;
                self.anchor = c;
                if c > 0 && self.board[r][c-1] != b'.' {
                    let mut first = c-1;
                    while first > 0 && self.board[r][first-1] != b'.' {
                        first -= 1;
                    }
                    let mut prefix = self.board[r][first..c].to_vec();
                    if let Some(node) = self.trie.prefix(&prefix) {
                        self.extend(c,first,node,&mut prefix,&mut counts,0);
                    }
                } else {
                    let mut limit = 0;
                    while c > limit && self.board[r][c-limit-1] == b'.' && !self.anchors[r][c-limit-1] {
                        limit += 1;
                    }
                    self.left(limit,0,&mut Vec::new(),&mut counts);
                }
            }
        }
        self.result
    }
}
pub fn generate(board: &Board, rack: &[u8], trie: &Trie) -> Vec<Move> {
    fn across(board: &Board, rack: &[u8], trie: &Trie) -> Vec<Move> {
        let (checks,_) = checks(board,trie);
        Generator {
            board,
            trie,
            anchors: anchors(board),
            checks,
            row: 0,
            anchor: 0,
            result: Vec::new()
        }.generate(rack)
    }
    let mut result = across(board,rack,trie);
    let transposed = board::transpose(board);
    for mut movement in across(&transposed,rack,trie) {
        std::mem::swap(&mut movement.row,&mut movement.column);
        movement.down = true;
        let new: Vec<_> = movement.word.iter().enumerate().filter(|(i,_)| board[movement.row+*i][movement.column] == b'.').map(|(i,_)| (movement.row+i,movement.column)).collect();
        if new.len() == 1 {
            let (r,c) = new[0];
            if (c > 0 && board[r][c-1] != b'.') || (c+1 < SIZE && board[r][c+1] != b'.') {
                continue;
            }
        }
        result.push(movement);
    }
    result
}
