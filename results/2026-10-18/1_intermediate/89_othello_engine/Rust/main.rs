use std::collections::HashMap;
use std::io::{self, Read};

type Board = [u8; 64];

const WEIGHTS: [i32; 64] = [
    100, -20, 10, 5, 5, 10, -20, 100,
    -20, -50, -2, -2, -2, -2, -50, -20,
    10, -2, -1, -1, -1, -1, -2, 10,
    5, -2, -1, -1, -1, -1, -2, 5,
    5, -2, -1, -1, -1, -1, -2, 5,
    10, -2, -1, -1, -1, -1, -2, 10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10, 5, 5, 10, -20, 100,
];

fn opponent(side: u8) -> u8 {
    if side == b'B' { b'W' } else { b'B' }
}

fn initial() -> Board {
    let mut board = [b'.'; 64];
    board[27] = b'W';
    board[36] = b'W';
    board[28] = b'B';
    board[35] = b'B';
    board
}

fn name(p: usize) -> String {
    format!("{}{}", (b'a' + (p % 8) as u8) as char, p / 8 + 1)
}

fn square(s: &str) -> usize {
    (s.as_bytes()[1] - b'1') as usize * 8 + (s.as_bytes()[0] - b'a') as usize
}

fn inside(row: i32, col: i32) -> bool {
    (0..8).contains(&row) && (0..8).contains(&col)
}

fn flips(board: &Board, side: u8, p: usize) -> Vec<usize> {
    let mut result = Vec::new();
    if board[p] != b'.' {
        return result;
    }
    let row = (p / 8) as i32;
    let col = (p % 8) as i32;
    for dr in -1..=1 {
        for dc in -1..=1 {
            if dr == 0 && dc == 0 {
                continue;
            }
            let mut r = row + dr;
            let mut c = col + dc;
            let mut path = Vec::new();
            while inside(r, c) && board[(r * 8 + c) as usize] == opponent(side) {
                path.push((r * 8 + c) as usize);
                r += dr;
                c += dc;
            }
            if !path.is_empty() && inside(r, c) && board[(r * 8 + c) as usize] == side {
                result.extend(path);
            }
        }
    }
    result.sort_unstable();
    result
}

fn legal(board: &Board, side: u8) -> Vec<usize> {
    (0..64).filter(|&p| board[p] == b'.' && !flips(board, side, p).is_empty()).collect()
}

fn place(board: &Board, side: u8, p: usize) -> Board {
    let mut next = *board;
    for q in flips(board, side, p) {
        next[q] = side;
    }
    next[p] = side;
    next
}

fn count(board: &Board, piece: u8) -> usize {
    board.iter().filter(|&&x| x == piece).count()
}

fn terminal(board: &Board) -> bool {
    legal(board, b'B').is_empty() && legal(board, b'W').is_empty()
}

fn game_over(board: &Board) -> String {
    let black = count(board, b'B');
    let white = count(board, b'W');
    let winner = if black > white {
        "winner B"
    } else if black < white {
        "winner W"
    } else {
        "draw"
    };
    format!("game over B {black} W {white} {winner}")
}

fn evaluate(board: &Board, side: u8) -> [i32; 4] {
    let mut weights = 0;
    for p in 0..64 {
        if board[p] == side {
            weights += WEIGHTS[p];
        } else if board[p] == opponent(side) {
            weights -= WEIGHTS[p];
        }
    }
    let own = legal(board, side).len() as i32;
    let other = legal(board, opponent(side)).len() as i32;
    [weights + 10 * (own - other), weights, own, other]
}

#[derive(Default)]
struct Solver {
    search_cache: HashMap<(Board, u8, i32), i32>,
    perft_cache: HashMap<(Board, u8, u32), u64>,
}

impl Solver {
    fn search(&mut self, board: &Board, side: u8, depth: i32) -> i32 {
        let key = (*board, side, depth);
        if let Some(&value) = self.search_cache.get(&key) {
            return value;
        }
        let moves = legal(board, side);
        let other = opponent(side);
        let value = if moves.is_empty() && legal(board, other).is_empty() {
            let factor = if depth < 0 { 1 } else { 1000 };
            factor * (count(board, side) as i32 - count(board, other) as i32)
        } else if depth == 0 {
            evaluate(board, side)[0]
        } else if moves.is_empty() {
            -self.search(board, other, if depth < 0 { -1 } else { depth - 1 })
        } else {
            moves.into_iter()
                .map(|p| -self.search(&place(board, side, p), other, if depth < 0 { -1 } else { depth - 1 }))
                .max()
                .unwrap()
        };
        if self.search_cache.len() > 300_000 {
            self.search_cache.clear();
        }
        self.search_cache.insert(key, value);
        value
    }

    fn ranked(&mut self, board: &Board, side: u8, depth: i32) -> Vec<(i32, usize)> {
        let mut results: Vec<_> = legal(board, side).into_iter()
            .map(|p| (-self.search(&place(board, side, p), opponent(side), if depth < 0 { -1 } else { depth - 1 }), p))
            .collect();
        results.sort_by_key(|&(value, p)| (-value, p));
        results
    }

    fn variation(&mut self, mut board: Board, mut side: u8, mut depth: i32) -> (Vec<String>, Board) {
        let mut steps = Vec::new();
        while depth != 0 && !terminal(&board) {
            let moves = self.ranked(&board, side, depth);
            if let Some(&(_, p)) = moves.first() {
                steps.push(name(p));
                board = place(&board, side, p);
            } else {
                steps.push("pass".to_string());
            }
            side = opponent(side);
            if depth > 0 {
                depth -= 1;
            }
        }
        (steps, board)
    }

    fn perft(&mut self, board: &Board, side: u8, depth: u32) -> u64 {
        if depth == 0 {
            return 1;
        }
        let key = (*board, side, depth);
        if let Some(&result) = self.perft_cache.get(&key) {
            return result;
        }
        let moves = legal(board, side);
        let other = opponent(side);
        let result = if moves.is_empty() {
            if legal(board, other).is_empty() { 1 } else { self.perft(board, other, depth - 1) }
        } else {
            moves.into_iter().map(|p| self.perft(&place(board, side, p), other, depth - 1)).sum()
        };
        if self.perft_cache.len() > 200_000 {
            self.perft_cache.clear();
        }
        self.perft_cache.insert(key, result);
        result
    }
}

fn stable(board: &Board) -> (usize, usize) {
    let mut set = [false; 64];
    let axes = [(0, 1), (1, 0), (1, 1), (1, -1)];
    loop {
        let mut added = Vec::new();
        for p in 0..64 {
            if board[p] == b'.' || set[p] {
                continue;
            }
            let mut valid = true;
            for (dr, dc) in axes {
                let mut full = true;
                let mut anchor = false;
                for sign in [-1, 1] {
                    let mut r = p as i32 / 8 + dr * sign;
                    let mut c = p as i32 % 8 + dc * sign;
                    if !inside(r, c) || (set[(r * 8 + c) as usize] && board[(r * 8 + c) as usize] == board[p]) {
                        anchor = true;
                    }
                    while inside(r, c) {
                        if board[(r * 8 + c) as usize] == b'.' {
                            full = false;
                        }
                        r += dr * sign;
                        c += dc * sign;
                    }
                }
                if !full && !anchor {
                    valid = false;
                    break;
                }
            }
            if valid {
                added.push(p);
            }
        }
        if added.is_empty() {
            break;
        }
        for p in added {
            set[p] = true;
        }
    }
    let black = (0..64).filter(|&p| set[p] && board[p] == b'B').count();
    let white = (0..64).filter(|&p| set[p] && board[p] == b'W').count();
    (black, white)
}

fn transformed_square(p: usize, operation: &str) -> usize {
    let r = p / 8;
    let c = p % 8;
    match operation {
        "rot90" => 8 * c + 7 - r,
        "rot180" => 63 - p,
        "rot270" => 8 * (7 - c) + r,
        "mirror" => 8 * r + 7 - c,
        "flip" => 8 * (7 - r) + c,
        "diag" => 8 * c + r,
        _ => 8 * (7 - c) + 7 - r,
    }
}

fn transformed_board(board: &Board, operation: &str) -> Board {
    let mut result = [b'.'; 64];
    for p in 0..64 {
        result[transformed_square(p, operation)] = board[p];
    }
    result
}

struct Random {
    state: u64,
}

impl Random {
    fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    fn draw(&mut self) -> u64 {
        self.state = self.state * 48271 % 2147483647;
        self.state
    }
}

fn random_game(mut board: Board, mut side: u8, random: &mut Random) -> Board {
    loop {
        let moves = legal(&board, side);
        if !moves.is_empty() {
            let p = moves[(random.draw() as usize) % moves.len()];
            board = place(&board, side, p);
        } else if legal(&board, opponent(side)).is_empty() {
            return board;
        }
        side = opponent(side);
    }
}

fn average(flipped: usize, moves: usize) -> String {
    let value = flipped * 100 / moves;
    format!("{}.{:02}", value / 100, value % 100)
}

#[derive(Clone, Copy)]
struct Position {
    board: Board,
    side: u8,
    over: bool,
}

#[derive(Clone)]
struct Move {
    side: u8,
    square: usize,
    count: usize,
    passed: bool,
    before: Position,
    after: Position,
}

struct Othello {
    board: Board,
    side: u8,
    over: bool,
    history: Vec<Move>,
    redo: Vec<Move>,
    solver: Solver,
}

impl Othello {
    fn new() -> Self {
        Self {
            board: initial(),
            side: b'B',
            over: false,
            history: Vec::new(),
            redo: Vec::new(),
            solver: Solver::default(),
        }
    }

    fn reset(&mut self) {
        self.board = initial();
        self.side = b'B';
        self.over = false;
        self.history.clear();
        self.redo.clear();
    }

    fn snapshot(&self) -> Position {
        Position { board: self.board, side: self.side, over: self.over }
    }

    fn restore(&mut self, position: Position) {
        self.board = position.board;
        self.side = position.side;
        self.over = position.over;
    }

    fn status(&self) -> String {
        if self.over {
            game_over(&self.board)
        } else {
            format!("{} to move", self.side as char)
        }
    }

    fn adjust(&mut self, quiet: bool) -> bool {
        if !legal(&self.board, self.side).is_empty() {
            return false;
        }
        if !legal(&self.board, opponent(self.side)).is_empty() {
            if !quiet {
                println!("{} passes", self.side as char);
            }
            self.side = opponent(self.side);
            return true;
        }
        self.over = true;
        if !quiet {
            println!("{}", game_over(&self.board));
        }
        false
    }

    fn play(&mut self, p: usize, quiet: bool, value: Option<i32>) -> bool {
        let before = self.snapshot();
        let side = self.side;
        let flipped = flips(&self.board, side, p).len();
        self.board = place(&self.board, side, p);
        if !quiet {
            if let Some(value) = value {
                println!("{} {} flips {} value {}", side as char, name(p), flipped, value);
            } else {
                println!("{} {} flips {}", side as char, name(p), flipped);
            }
        }
        self.side = opponent(side);
        let passed = self.adjust(quiet);
        let after = self.snapshot();
        self.history.push(Move { side, square: p, count: flipped, passed, before, after });
        self.redo.clear();
        passed
    }

    fn reason(&self, p: usize) -> Option<&'static str> {
        if self.over {
            Some("game over")
        } else if self.board[p] != b'.' {
            Some("occupied")
        } else if flips(&self.board, self.side, p).is_empty() {
            Some("no flips")
        } else {
            None
        }
    }

    fn record(&mut self, text: &str) {
        let mut trial = Othello::new();
        let mut played = Vec::new();
        let mut passes = 0;
        for (i, pair) in text.as_bytes().chunks_exact(2).enumerate() {
            let p = (pair[1] - b'1') as usize * 8 + (pair[0] - b'a') as usize;
            if let Some(reason) = trial.reason(p) {
                println!("ILLEGAL move {} {} {}", i + 1, name(p), reason);
                return;
            }
            played.push(p);
            if trial.play(p, true, None) {
                passes += 1;
            }
        }
        self.restore(trial.snapshot());
        self.history = trial.history;
        self.redo.clear();
        let operation = match name(played[0]).as_str() {
            "e6" => "diag",
            "d3" => "anti",
            "c4" => "rot180",
            _ => "",
        };
        let normalized: String = played.iter().map(|&p| name(if operation.is_empty() { p } else { transformed_square(p, operation) })).collect();
        println!("record {} moves {} passes", played.len(), passes);
        println!("normal {}", normalized);
        println!("{}", self.status());
    }

    fn sheet(&self) {
        let board = self.history.first().map_or(self.board, |m| m.before.board);
        let mut fields: Vec<String> = board.iter().map(|&c| (c as char).to_string()).collect();
        for (i, item) in self.history.iter().enumerate() {
            fields[item.square] = (i + 1).to_string();
        }
        print!(" ");
        for col in b'a'..=b'h' {
            print!("{:>3}", col as char);
        }
        println!();
        for row in 0..8 {
            print!("{}", row + 1);
            for col in 0..8 {
                print!("{:>3}", fields[row * 8 + col]);
            }
            println!();
        }
    }

    fn stats(&self) {
        let total: usize = self.history.iter().map(|m| m.count).sum();
        if self.history.is_empty() {
            println!("moves 0");
        } else {
            let passes = self.history.iter().filter(|m| m.passed).count();
            println!("moves {} flips {} avg {} passes {}", self.history.len(), total, average(total, self.history.len()), passes);
        }
        for side in [b'B', b'W'] {
            let moves: Vec<_> = self.history.iter().filter(|m| m.side == side).collect();
            if moves.is_empty() {
                println!("{} moves 0", side as char);
                continue;
            }
            let sum: usize = moves.iter().map(|m| m.count).sum();
            let maximum = moves.iter().map(|m| m.count).max().unwrap();
            let first = moves.iter().find(|m| m.count == maximum).unwrap();
            let corners = moves.iter().filter(|m| [0, 7, 56, 63].contains(&m.square)).count();
            println!("{} moves {} flips {} avg {} max {} {} corners {}", side as char, moves.len(), sum, average(sum, moves.len()), maximum, name(first.square), corners);
        }
    }

    fn automatic(&mut self, black: i32, white: i32, seed: Option<u64>) {
        let mut random = seed.map(Random::new);
        let mut played = String::new();
        let mut passes = 0;
        let mut moves = 0;
        while !self.over {
            let p = if let Some(ref mut rng) = random {
                let legal_moves = legal(&self.board, self.side);
                legal_moves[(rng.draw() as usize) % legal_moves.len()]
            } else {
                let depth = if self.side == b'B' { black } else { white };
                self.solver.ranked(&self.board, self.side, depth)[0].1
            };
            played.push_str(&name(p));
            if self.play(p, true, None) {
                passes += 1;
            }
            moves += 1;
        }
        println!("{} {} moves {} passes", if seed.is_some() { "random" } else { "autoplay" }, moves, passes);
        println!("moves {}", played);
        println!("{}", game_over(&self.board));
    }

    fn monte_carlo(&self, games: usize, seed: u64) {
        let mut random = Random::new(seed);
        let mut best = None;
        for p in legal(&self.board, self.side) {
            let mut wins = 0;
            let mut draws = 0;
            let mut losses = 0;
            let first = place(&self.board, self.side, p);
            for _ in 0..games {
                let last = random_game(first, opponent(self.side), &mut random);
                let difference = count(&last, self.side) as i32 - count(&last, opponent(self.side)) as i32;
                if difference > 0 {
                    wins += 1;
                } else if difference == 0 {
                    draws += 1;
                } else {
                    losses += 1;
                }
            }
            println!("{} {} {} {}", name(p), wins, draws, losses);
            let points = 2 * wins + draws;
            if best.map_or(true, |(_, value)| points > value) {
                best = Some((p, points));
            }
        }
        if let Some((p, value)) = best {
            println!("best {} {}", name(p), value);
        }
    }

    fn execute(&mut self, line: &str) {
        let mut parts = line.split(' ');
        let command = parts.next().unwrap_or("");
        let args: Vec<&str> = parts.collect();
        let zero = ["NEW", "DUMP", "SHOW", "SCORE", "LEGAL", "HISTORY", "SHEET", "STATS", "EVAL", "STABLE", "SOLVE"];
        let numeric = ["UNDO", "REDO", "HINT", "PV", "AI", "ANALYZE", "RANDOM", "PERFT", "DIVIDE"];
        let active = ["FLIPS", "MOVE", "PLAY", "HINT", "PV", "AI", "SOLVE", "AUTOPLAY", "RANDOM", "MC", "DIVIDE"];
        let known = zero.contains(&command) || numeric.contains(&command) ||
            ["LOAD", "TRANSFORM", "AUTOPLAY", "MC", "FLIPS", "MOVE", "PLAY", "RECORD"].contains(&command);
        if !known {
            println!("ERROR unknown command");
            return;
        }
        let mut error = None;
        if command == "LOAD" {
            if args.len() != 2 || args[0].len() != 64 || !args[0].bytes().all(|c| matches!(c, b'.' | b'B' | b'W')) ||
                !["B", "W"].contains(&args[1]) {
                error = Some("bad board");
            }
        } else if command == "MOVE" || command == "FLIPS" {
            if args.len() != 1 {
                error = Some("bad arguments");
            } else {
                let bytes = args[0].as_bytes();
                if bytes.len() != 2 || !(b'a'..=b'h').contains(&bytes[0]) || !(b'1'..=b'8').contains(&bytes[1]) {
                    error = Some("bad square");
                }
            }
        } else if command == "PLAY" || command == "RECORD" {
            if args.len() != 1 {
                error = Some("bad arguments");
            } else {
                let bytes = args[0].as_bytes();
                if bytes.is_empty() || bytes.len() > 120 || bytes.len() % 2 != 0 ||
                    !bytes.chunks_exact(2).all(|pair| (b'a'..=b'h').contains(&pair[0]) && (b'1'..=b'8').contains(&pair[1])) {
                    error = Some("bad record");
                }
            }
        } else if zero.contains(&command) {
            if !args.is_empty() {
                error = Some("bad arguments");
            }
        } else if command == "TRANSFORM" {
            if args.len() != 1 ||
                !["rot90", "rot180", "rot270", "mirror", "flip", "diag", "anti"].contains(&args[0]) {
                error = Some("bad arguments");
            }
        } else {
            let expected = if command == "MC" || command == "AUTOPLAY" { 2 } else { 1 };
            let valid_numbers = args.len() == expected &&
                args.iter().all(|arg| !arg.is_empty() && arg.bytes().all(|c| c.is_ascii_digit()) && arg.parse::<u64>().is_ok());
            if !valid_numbers {
                error = Some("bad arguments");
            } else {
                let a = args[0].parse::<u64>().unwrap();
                let b = args.get(1).map(|s| s.parse::<u64>().unwrap()).unwrap_or(0);
                let valid = match command {
                    "AUTOPLAY" => (1..=4).contains(&a) && (1..=4).contains(&b),
                    "HINT" | "PV" | "AI" | "ANALYZE" => (1..=4).contains(&a),
                    "PERFT" | "DIVIDE" => (1..=8).contains(&a),
                    "MC" => (1..=100).contains(&a) && (1..=2147483646).contains(&b),
                    "RANDOM" => (1..=2147483646).contains(&a),
                    _ => a >= 1,
                };
                if !valid {
                    error = Some("bad arguments");
                }
            }
        }
        if let Some(message) = error {
            println!("ERROR {}", message);
            return;
        }
        if self.over && active.contains(&command) {
            println!("ERROR game over");
            return;
        }
        let value = args.first().and_then(|s| s.parse::<usize>().ok()).unwrap_or(0);
        match command {
            "NEW" => {
                self.reset();
                println!("OK");
            }
            "LOAD" => {
                self.board.copy_from_slice(args[0].as_bytes());
                self.side = args[1].as_bytes()[0];
                self.over = false;
                self.history.clear();
                self.redo.clear();
                println!("OK");
                self.adjust(false);
            }
            "DUMP" => println!("board {} {}", String::from_utf8_lossy(&self.board), self.side as char),
            "SHOW" => {
                println!("  a b c d e f g h");
                let moves = if self.over { Vec::new() } else { legal(&self.board, self.side) };
                for r in 0..8 {
                    let mut text = (r + 1).to_string();
                    for c in 0..8 {
                        let p = r * 8 + c;
                        text.push(' ');
                        text.push(if moves.contains(&p) { '*' } else { self.board[p] as char });
                    }
                    println!("{}", text);
                }
                println!("{}", self.status());
            }
            "SCORE" => println!("score B {} W {} empty {}", count(&self.board, b'B'), count(&self.board, b'W'), count(&self.board, b'.')),
            "LEGAL" => {
                let moves = if self.over { Vec::new() } else { legal(&self.board, self.side) };
                let mut text = format!("legal {}", moves.len());
                for p in moves {
                    text.push_str(&format!(" {}", name(p)));
                }
                println!("{}", text);
            }
            "MOVE" | "FLIPS" => {
                let p = square(args[0]);
                if let Some(message) = self.reason(p) {
                    println!("ILLEGAL {}", message);
                } else if command == "MOVE" {
                    self.play(p, false, None);
                } else {
                    let flipped = flips(&self.board, self.side, p);
                    let mut line = format!("flips {} {}", args[0], flipped.len());
                    for q in flipped {
                        line.push_str(&format!(" {}", name(q)));
                    }
                    println!("{}", line);
                }
            }
            "PLAY" => {
                for (index, pair) in args[0].as_bytes().chunks_exact(2).enumerate() {
                    let p = (pair[1] - b'1') as usize * 8 + (pair[0] - b'a') as usize;
                    if let Some(message) = self.reason(p) {
                        println!("ILLEGAL move {} {} {}", index + 1, name(p), message);
                        break;
                    }
                    self.play(p, false, None);
                }
            }
            "RECORD" => self.record(args[0]),
            "UNDO" => {
                if value > self.history.len() {
                    println!("ERROR cannot undo");
                } else {
                    let removed = self.history.split_off(self.history.len() - value);
                    self.restore(removed[0].before);
                    let mut redo = removed;
                    redo.append(&mut self.redo);
                    self.redo = redo;
                    println!("{}", self.status());
                }
            }
            "REDO" => {
                if value > self.redo.len() {
                    println!("ERROR cannot redo");
                } else {
                    let tail = self.redo.split_off(value);
                    let added = std::mem::replace(&mut self.redo, tail);
                    self.restore(added.last().unwrap().after);
                    self.history.extend(added);
                    println!("{}", self.status());
                }
            }
            "HISTORY" => {
                println!("history {}", self.history.len());
                for (i, row) in self.history.iter().enumerate() {
                    println!("{} {} {} {}{}", i + 1, row.side as char, name(row.square), row.count, if row.passed { " pass" } else { "" });
                }
            }
            "SHEET" => self.sheet(),
            "STATS" => self.stats(),
            "TRANSFORM" => {
                let operation = args[0];
                self.board = transformed_board(&self.board, operation);
                for row in self.history.iter_mut().chain(self.redo.iter_mut()) {
                    row.square = transformed_square(row.square, operation);
                    row.before.board = transformed_board(&row.before.board, operation);
                    row.after.board = transformed_board(&row.after.board, operation);
                }
                println!("OK");
            }
            "EVAL" => {
                let [value, weights, own, other] = evaluate(&self.board, self.side);
                println!("eval {} weights {} mobility {} {}", value, weights, own, other);
            }
            "STABLE" => {
                let (black, white) = stable(&self.board);
                println!("stable B {} W {}", black, white);
            }
            "HINT" => {
                for (score, p) in self.solver.ranked(&self.board, self.side, value as i32) {
                    println!("{} {}", name(p), score);
                }
            }
            "PV" => {
                let score = self.solver.search(&self.board, self.side, value as i32);
                let (moves, _) = self.solver.variation(self.board, self.side, value as i32);
                println!("pv {} {}", score, moves.join(" "));
            }
            "AI" => {
                let (score, p) = self.solver.ranked(&self.board, self.side, value as i32)[0];
                self.play(p, false, Some(score));
            }
            "ANALYZE" => {
                let mut losses = [0, 0];
                for (i, row) in self.history.iter().enumerate() {
                    let moves = self.solver.ranked(&row.before.board, row.side, value as i32);
                    let (best, best_square) = moves[0];
                    let played = moves.iter().find(|(_, p)| *p == row.square).unwrap().0;
                    losses[if row.side == b'B' { 0 } else { 1 }] += best - played;
                    println!("{} {} {} {} best {} {}", i + 1, row.side as char, name(row.square), played, name(best_square), best);
                }
                println!("loss B {} W {}", losses[0], losses[1]);
            }
            "SOLVE" => {
                if count(&self.board, b'.') >= 9 {
                    println!("ERROR too many empties");
                } else {
                    for (score, p) in self.solver.ranked(&self.board, self.side, -1) {
                        println!("{} {}", name(p), score);
                    }
                    let (moves, board) = self.solver.variation(self.board, self.side, -1);
                    println!("line {}", moves.join(" "));
                    println!("final B {} W {}", count(&board, b'B'), count(&board, b'W'));
                }
            }
            "AUTOPLAY" => self.automatic(value as i32, args[1].parse::<i32>().unwrap(), None),
            "RANDOM" => self.automatic(0, 0, Some(value as u64)),
            "MC" => self.monte_carlo(value, args[1].parse::<u64>().unwrap()),
            "PERFT" => println!("perft {} {}", value, self.solver.perft(&self.board, self.side, value as u32)),
            "DIVIDE" => {
                let mut total = 0;
                for p in legal(&self.board, self.side) {
                    let amount = self.solver.perft(&place(&self.board, self.side, p), opponent(self.side), value as u32 - 1);
                    println!("{} {}", name(p), amount);
                    total += amount;
                }
                println!("total {}", total);
            }
            _ => {}
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count = lines.next().unwrap().parse::<usize>().unwrap();
    let mut engine = Othello::new();
    for line in lines.take(count) {
        engine.execute(line);
    }
}