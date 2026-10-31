use std::collections::{HashMap, HashSet};
use std::io::{self, Read};

const COLS: &str = "ABCDEFGHJKLMNOPQRST";

fn opponent(color: u8) -> u8 {
    if color == b'B' { b'W' } else { b'B' }
}

fn color_index(color: u8) -> usize {
    if color == b'B' { 0 } else { 1 }
}

fn half(v: i32) -> String {
    format!(
        "{}{}.{}",
        if v < 0 { "-" } else { "" },
        v.abs() / 2,
        if v.abs() % 2 == 1 { 5 } else { 0 }
    )
}

fn komi(s: &str) -> Option<i32> {
    let negative = s.starts_with('-');
    let digits = if negative { &s[1..] } else { s };
    let parts: Vec<_> = digits.split('.').collect();
    if parts.len() > 2 {
        return None;
    }
    let whole = parts[0];
    if whole.is_empty()
        || (whole.len() > 1 && whole.starts_with('0'))
        || !whole.bytes().all(|x| x.is_ascii_digit())
    {
        return None;
    }
    let whole: i32 = whole.parse().ok()?;
    if whole > 100 {
        return None;
    }
    let fraction = if parts.len() == 1 {
        0
    } else if parts[1] == "0" {
        0
    } else if parts[1] == "5" {
        1
    } else {
        return None;
    };
    let result = 2 * whole + fraction;
    if negative && result == 0 {
        return None;
    }
    Some(if negative { -result } else { result })
}

fn handicap_names(size: usize) -> &'static [&'static str] {
    match size {
        9 => &["C3", "G7", "C7", "G3", "C5", "G5", "E3", "E7", "E5"],
        13 => &["D4", "K10", "D10", "K4", "D7", "K7", "G4", "G10", "G7"],
        _ => &["D4", "Q16", "D16", "Q4", "D10", "Q10", "K4", "K16", "K10"],
    }
}

fn point_name(p: usize, size: usize) -> String {
    format!("{}{}", COLS.as_bytes()[p % size] as char, p / size + 1)
}

fn point_number(text: &str, size: usize) -> Option<usize> {
    let bytes = text.as_bytes();
    if bytes.len() < 2 || bytes.len() > 3 {
        return None;
    }
    let c = COLS.as_bytes().iter().position(|&x| x == bytes[0])?;
    if c >= size || bytes[1] == b'0' || !bytes[1..].iter().all(|x| x.is_ascii_digit()) {
        return None;
    }
    let row: usize = text[1..].parse().ok()?;
    if row == 0 || row > size {
        return None;
    }
    Some((row - 1) * size + c)
}

fn sgf(p: usize, size: usize) -> String {
    format!(
        "{}{}",
        (b'a' + (p % size) as u8) as char,
        (b'a' + (size - 1 - p / size) as u8) as char
    )
}

fn adjacent(p: usize, n: usize, diagonal: bool) -> Vec<usize> {
    let (row, col) = (p / n, p % n);
    let deltas: &[(i32, i32)] = if diagonal {
        &[(-1, -1), (-1, 1), (1, -1), (1, 1)]
    } else {
        &[(-1, 0), (1, 0), (0, -1), (0, 1)]
    };
    deltas
        .iter()
        .filter_map(|&(dr, dc)| {
            let r = row as i32 + dr;
            let c = col as i32 + dc;
            if r >= 0 && c >= 0 && r < n as i32 && c < n as i32 {
                Some(r as usize * n + c as usize)
            } else {
                None
            }
        })
        .collect()
}

fn flood(board: &[u8], size: usize, p: usize, allowed: &[u8]) -> Vec<usize> {
    let mut seen = vec![false; board.len()];
    let mut todo = vec![p];
    seen[p] = true;
    let mut next = 0;
    while next < todo.len() {
        let point = todo[next];
        next += 1;
        for q in adjacent(point, size, false) {
            if !seen[q] && allowed.contains(&board[q]) {
                seen[q] = true;
                todo.push(q);
            }
        }
    }
    todo.sort_unstable();
    todo
}

#[derive(Clone)]
struct Group {
    color: u8,
    first: usize,
    stones: Vec<usize>,
    liberties: Vec<usize>,
}

fn group(board: &[u8], size: usize, p: usize) -> Group {
    let stones = flood(board, size, p, &[board[p]]);
    let mut liberties: Vec<usize> = stones
        .iter()
        .flat_map(|&q| adjacent(q, size, false))
        .filter(|&q| board[q] == b'.')
        .collect();
    liberties.sort_unstable();
    liberties.dedup();
    Group {
        color: board[p],
        first: stones[0],
        stones,
        liberties,
    }
}

fn groups(board: &[u8], size: usize, color: Option<u8>) -> Vec<Group> {
    let mut visited = vec![false; board.len()];
    let mut result = Vec::new();
    for p in 0..board.len() {
        if visited[p] || board[p] == b'.' || color.is_some_and(|c| board[p] != c) {
            continue;
        }
        let found = group(board, size, p);
        for &q in &found.stones {
            visited[q] = true;
        }
        result.push(found);
    }
    result
}

struct Attempt {
    board: Vec<u8>,
    captured: usize,
    reason: Option<&'static str>,
}

fn placement(board: &[u8], n: usize, color: u8, p: usize) -> Attempt {
    if board[p] != b'.' {
        return Attempt {
            board: board.to_vec(),
            captured: 0,
            reason: Some("occupied"),
        };
    }
    let mut next = board.to_vec();
    next[p] = color;
    let mut captured = 0;
    let mut seen = vec![false; board.len()];
    for q in adjacent(p, n, false) {
        if next[q] == opponent(color) && !seen[q] {
            let enemy = group(&next, n, q);
            for &stone in &enemy.stones {
                seen[stone] = true;
            }
            if enemy.liberties.is_empty() {
                for &stone in &enemy.stones {
                    next[stone] = b'.';
                    captured += 1;
                }
            }
        }
    }
    let reason = if group(&next, n, p).liberties.is_empty() {
        Some("suicide")
    } else {
        None
    };
    Attempt {
        board: next,
        captured,
        reason,
    }
}

struct Region {
    first: usize,
    points: Vec<usize>,
    owner: Option<u8>,
}

fn regions(board: &[u8], size: usize) -> Vec<Region> {
    let mut visited = vec![false; board.len()];
    let mut result = Vec::new();
    for p in 0..board.len() {
        if board[p] != b'.' || visited[p] {
            continue;
        }
        let points = flood(board, size, p, b".");
        let mut border = HashSet::new();
        for &point in &points {
            visited[point] = true;
            for q in adjacent(point, size, false) {
                if board[q] != b'.' {
                    border.insert(board[q]);
                }
            }
        }
        result.push(Region {
            first: p,
            points,
            owner: if border.len() == 1 {
                border.iter().copied().next()
            } else {
                None
            },
        });
    }
    result
}

fn safe(board: &[u8], size: usize, color: u8) -> Vec<Group> {
    let own = groups(board, size, Some(color));
    let mut visited = vec![false; board.len()];
    let mut areas = Vec::new();
    for p in 0..board.len() {
        if board[p] == color || visited[p] {
            continue;
        }
        let points = flood(board, size, p, &[b'.', opponent(color)]);
        for &q in &points {
            visited[q] = true;
        }
        let touching: Vec<usize> = own
            .iter()
            .enumerate()
            .filter_map(|(i, g)| {
                if points.iter().any(|&q| {
                    adjacent(q, size, false)
                        .iter()
                        .any(|s| g.stones.contains(s))
                }) {
                    Some(i)
                } else {
                    None
                }
            })
            .collect();
        let vital: Vec<usize> = own
            .iter()
            .enumerate()
            .filter_map(|(i, g)| {
                if points
                    .iter()
                    .filter(|&&q| board[q] == b'.')
                    .all(|q| g.liberties.contains(q))
                {
                    Some(i)
                } else {
                    None
                }
            })
            .collect();
        areas.push((touching, vital));
    }
    let mut good_groups = vec![true; own.len()];
    let mut good_areas = vec![true; areas.len()];
    loop {
        let mut changed = false;
        for i in 0..own.len() {
            if good_groups[i] {
                let count = areas
                    .iter()
                    .enumerate()
                    .filter(|(j, (_, v))| good_areas[*j] && v.contains(&i))
                    .count();
                if count < 2 {
                    good_groups[i] = false;
                    changed = true;
                }
            }
        }
        for (j, (touches, _)) in areas.iter().enumerate() {
            if good_areas[j] && touches.iter().any(|&i| !good_groups[i]) {
                good_areas[j] = false;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    own.into_iter()
        .enumerate()
        .filter_map(|(i, g)| if good_groups[i] { Some(g) } else { None })
        .collect()
}

#[derive(Clone, Copy)]
struct Reading {
    success: bool,
    chosen: Option<usize>,
}

fn defend(
    board: &[u8],
    size: usize,
    p: usize,
    depth: usize,
    memo: &mut HashMap<(Vec<u8>, usize, bool), Reading>,
) -> Reading {
    if depth >= 40 {
        return Reading {
            success: true,
            chosen: None,
        };
    }
    let key = (board.to_vec(), depth, true);
    if let Some(result) = memo.get(&key) {
        return *result;
    }
    let defender = board[p];
    let attacker = opponent(defender);
    let g = group(board, size, p);
    let mut choices = g.liberties.clone();
    let mut visited = vec![false; board.len()];
    for stone in g.stones {
        for q in adjacent(stone, size, false) {
            if board[q] == attacker && !visited[q] {
                let enemy = group(board, size, q);
                for &s in &enemy.stones {
                    visited[s] = true;
                }
                if enemy.liberties.len() == 1 {
                    choices.push(enemy.liberties[0]);
                }
            }
        }
    }
    choices.sort_unstable();
    choices.dedup();
    for q in choices {
        let move_ = placement(board, size, defender, q);
        if move_.reason.is_some() {
            continue;
        }
        let m = group(&move_.board, size, p).liberties.len();
        if m >= 3 || (m == 2 && !attack(&move_.board, size, p, depth + 1, memo).success) {
            let result = Reading {
                success: true,
                chosen: Some(q),
            };
            memo.insert(key, result);
            return result;
        }
    }
    let result = Reading {
        success: false,
        chosen: None,
    };
    memo.insert(key, result);
    result
}

fn attack(
    board: &[u8],
    size: usize,
    p: usize,
    depth: usize,
    memo: &mut HashMap<(Vec<u8>, usize, bool), Reading>,
) -> Reading {
    if depth >= 40 {
        return Reading {
            success: false,
            chosen: None,
        };
    }
    let key = (board.to_vec(), depth, false);
    if let Some(result) = memo.get(&key) {
        return *result;
    }
    let defender = board[p];
    for q in group(board, size, p).liberties {
        let move_ = placement(board, size, opponent(defender), q);
        if move_.reason.is_none() && !defend(&move_.board, size, p, depth + 1, memo).success {
            let result = Reading {
                success: true,
                chosen: Some(q),
            };
            memo.insert(key, result);
            return result;
        }
    }
    let result = Reading {
        success: false,
        chosen: None,
    };
    memo.insert(key, result);
    result
}

fn ladder(board: &[u8], size: usize, p: usize) -> (String, Option<usize>) {
    let liberties = group(board, size, p).liberties.len();
    if liberties >= 3 {
        return ("safe".to_string(), None);
    }
    let mut memo = HashMap::new();
    if liberties == 1 {
        let result = defend(board, size, p, 0, &mut memo);
        (
            if result.success {
                "escapes"
            } else {
                "captured"
            }
            .to_string(),
            if result.success { result.chosen } else { None },
        )
    } else {
        let result = attack(board, size, p, 0, &mut memo);
        (
            if result.success {
                "captured"
            } else {
                "escapes"
            }
            .to_string(),
            if result.success { result.chosen } else { None },
        )
    }
}

#[derive(Clone)]
struct Position {
    board: Vec<u8>,
    turn: u8,
    captures: [usize; 2],
    passes: usize,
    over: bool,
}

#[derive(Clone)]
struct Move {
    color: u8,
    point: Option<usize>,
    captured: usize,
    before: Position,
}

#[derive(Clone, Copy)]
struct ReplayRecord {
    color: u8,
    point: Option<usize>,
}

fn parse_records(s: &str, size: usize) -> Option<Vec<ReplayRecord>> {
    let bytes = s.as_bytes();
    let mut records = Vec::new();
    let mut p = 0;
    while p < bytes.len() {
        if p + 3 >= bytes.len()
            || bytes[p] != b';'
            || ![b'B', b'W'].contains(&bytes[p + 1])
            || bytes[p + 2] != b'['
        {
            return None;
        }
        let color = bytes[p + 1];
        p += 3;
        let point = if bytes[p] == b']' {
            None
        } else {
            if p + 2 >= bytes.len()
                || !(b'a'..b'a' + size as u8).contains(&bytes[p])
                || !(b'a'..b'a' + size as u8).contains(&bytes[p + 1])
            {
                return None;
            }
            let col = (bytes[p] - b'a') as usize;
            let row = size - 1 - (bytes[p + 1] - b'a') as usize;
            p += 2;
            Some(row * size + col)
        };
        if p >= bytes.len() || bytes[p] != b']' {
            return None;
        }
        p += 1;
        records.push(ReplayRecord { color, point });
    }
    if records.is_empty() {
        None
    } else {
        Some(records)
    }
}

struct Game {
    size: usize,
    komi: i32,
    superko: bool,
    position: Position,
    handicap: Vec<usize>,
    history: Vec<Move>,
    positions: Vec<Vec<u8>>,
    dead: HashSet<usize>,
}

impl Game {
    fn new() -> Self {
        let mut game = Self {
            size: 19,
            komi: 13,
            superko: false,
            position: Position {
                board: Vec::new(),
                turn: b'B',
                captures: [0, 0],
                passes: 0,
                over: false,
            },
            handicap: Vec::new(),
            history: Vec::new(),
            positions: Vec::new(),
            dead: HashSet::new(),
        };
        game.reset(19, 13);
        game
    }

    fn reset(&mut self, size: usize, komi: i32) {
        self.size = size;
        self.komi = komi;
        self.position = Position {
            board: vec![b'.'; size * size],
            turn: b'B',
            captures: [0, 0],
            passes: 0,
            over: false,
        };
        self.handicap.clear();
        self.history.clear();
        self.positions = vec![self.position.board.clone()];
        self.dead.clear();
    }

    fn point(&self, text: &str) -> Option<usize> {
        point_number(text, self.size)
    }

    fn name(&self, p: usize) -> String {
        point_name(p, self.size)
    }

    fn check(&self, color: u8, point: usize) -> Attempt {
        let mut result = placement(&self.position.board, self.size, color, point);
        if result.reason.is_none()
            && self.positions.len() >= 2
            && result.board == self.positions[self.positions.len() - 2]
        {
            result.reason = Some("ko");
        }
        if result.reason.is_none() && self.superko && self.positions.contains(&result.board) {
            result.reason = Some("superko");
        }
        result
    }

    fn play(&mut self, color: u8, point: Option<usize>, supplied: Option<Attempt>) -> usize {
        let before = self.position.clone();
        let mut captured = 0;
        if let Some(p) = point {
            let attempt = supplied.unwrap_or_else(|| self.check(color, p));
            self.position.board = attempt.board;
            captured = attempt.captured;
            self.position.captures[color_index(color)] += captured;
            self.position.passes = 0;
        } else {
            self.position.passes += 1;
            if self.position.passes == 2 {
                self.position.over = true;
            }
        }
        self.position.turn = opponent(color);
        self.history.push(Move {
            color,
            point,
            captured,
            before,
        });
        self.positions.push(self.position.board.clone());
        self.dead.clear();
        captured
    }

    fn clean(&self) -> Vec<u8> {
        let mut board = self.position.board.clone();
        for &p in &self.dead {
            board[p] = b'.';
        }
        board
    }

    fn show(&self, output: &mut Vec<String>, map: bool) {
        let board = if map {
            self.clean()
        } else {
            self.position.board.clone()
        };
        let mut glyphs = board.clone();
        let star_names = handicap_names(self.size);
        let mut stars = HashSet::new();
        for (i, name) in star_names.iter().enumerate() {
            if self.size == 19 || i < 4 || i == 8 {
                stars.insert(self.point(name).unwrap());
            }
        }
        if map {
            for area in regions(&board, self.size) {
                for p in area.points {
                    glyphs[p] = match area.owner {
                        Some(b'B') => b'x',
                        Some(b'W') => b'o',
                        _ => b'.',
                    };
                }
            }
        }
        for p in 0..board.len() {
            if board[p] == b'B' {
                glyphs[p] = if !map && self.dead.contains(&p) {
                    b'x'
                } else {
                    b'X'
                };
            } else if board[p] == b'W' {
                glyphs[p] = if !map && self.dead.contains(&p) {
                    b'o'
                } else {
                    b'O'
                };
            } else if !map {
                glyphs[p] = if stars.contains(&p) { b'+' } else { b'.' };
            }
        }
        let header = format!(
            "   {}",
            COLS[..self.size]
                .chars()
                .map(|x| x.to_string())
                .collect::<Vec<_>>()
                .join(" ")
        );
        output.push(header.clone());
        for row in (1..=self.size).rev() {
            let items: Vec<_> = glyphs[(row - 1) * self.size..row * self.size]
                .iter()
                .map(|&c| (c as char).to_string())
                .collect();
            output.push(format!("{:>2} {} {}", row, items.join(" "), row));
        }
        output.push(header);
    }

    fn score(&self, method: &str, output: &mut Vec<String>) {
        let board = self.clean();
        let mut territory = [0usize; 2];
        for area in regions(&board, self.size) {
            if let Some(color) = area.owner {
                territory[color_index(color)] += area.points.len();
            }
        }
        let mut totals = [0i32; 2];
        for color in [b'B', b'W'] {
            let index = color_index(color);
            let label = color as char;
            if method == "AREA" {
                let stones = board.iter().filter(|&&x| x == color).count();
                totals[index] = 2 * (stones + territory[index]) as i32
                    + if color == b'W' { self.komi } else { 0 };
                output.push(if color == b'W' {
                    format!(
                        "{label} stones {stones} territory {} komi {} total {}",
                        territory[index],
                        half(self.komi),
                        half(totals[index])
                    )
                } else {
                    format!(
                        "{label} stones {stones} territory {} total {}",
                        territory[index],
                        half(totals[index])
                    )
                });
            } else {
                let prisoners = self.position.captures[index]
                    + self
                        .dead
                        .iter()
                        .filter(|&&p| self.position.board[p] == opponent(color))
                        .count();
                totals[index] = 2 * (territory[index] + prisoners) as i32
                    + if color == b'W' { self.komi } else { 0 };
                output.push(if color == b'W' {
                    format!(
                        "{label} territory {} prisoners {prisoners} komi {} total {}",
                        territory[index],
                        half(self.komi),
                        half(totals[index])
                    )
                } else {
                    format!(
                        "{label} territory {} prisoners {prisoners} total {}",
                        territory[index],
                        half(totals[index])
                    )
                });
            }
        }
        let delta = totals[0] - totals[1];
        output.push(if delta == 0 {
            "result Draw".to_string()
        } else if delta > 0 {
            format!("result B+{}", half(delta))
        } else {
            format!("result W+{}", half(-delta))
        });
    }

    fn execute(&mut self, line: &str, output: &mut Vec<String>) {
        let words: Vec<_> = line.split(' ').collect();
        let (command, args) = (words[0], &words[1..]);
        let two = ["BOARD", "PLAY"];
        let one = [
            "KOMI", "SUPERKO", "HANDICAP", "PASS", "REPLAY", "GROUP", "LEGAL", "EYES", "SAFE",
            "LADDER", "DEAD", "SCORE",
        ];
        let zero = [
            "UNDO", "SHOW", "MAP", "STATUS", "CAPTURES", "HISTORY", "MOVES", "GROUPS", "ATARI",
            "REGIONS",
        ];
        if !two.contains(&command) && !one.contains(&command) && !zero.contains(&command) {
            output.push("ERROR unknown command".to_string());
            return;
        }
        let expected = if two.contains(&command) {
            2
        } else if one.contains(&command) {
            1
        } else {
            0
        };
        if args.len() != expected {
            output.push("ERROR bad arguments".to_string());
            return;
        }
        let mut new_size = self.size;
        let mut new_komi = self.komi;
        let valid = match command {
            "BOARD" => {
                if !["9", "13", "19"].contains(&args[0]) {
                    false
                } else if let Some(amount) = komi(args[1]) {
                    new_size = args[0].parse().unwrap();
                    new_komi = amount;
                    true
                } else {
                    false
                }
            }
            "KOMI" => {
                if let Some(amount) = komi(args[0]) {
                    new_komi = amount;
                    true
                } else {
                    false
                }
            }
            "SUPERKO" => ["ON", "OFF"].contains(&args[0]),
            "HANDICAP" => args[0].len() == 1 && (b'2'..=b'9').contains(&args[0].as_bytes()[0]),
            "PLAY" | "PASS" | "LEGAL" | "EYES" | "SAFE" => ["B", "W"].contains(&args[0]),
            "SCORE" => ["AREA", "TERRITORY"].contains(&args[0]),
            _ => true,
        };
        if !valid {
            output.push("ERROR bad arguments".to_string());
            return;
        }
        let point = if ["PLAY", "GROUP", "LADDER", "DEAD"].contains(&command) {
            self.point(if command == "PLAY" { args[1] } else { args[0] })
        } else {
            None
        };
        if ["PLAY", "GROUP", "LADDER", "DEAD"].contains(&command) && point.is_none() {
            output.push("ERROR bad point".to_string());
            return;
        }
        let sequence = if command == "REPLAY" {
            match parse_records(args[0], self.size) {
                Some(records) => records,
                None => {
                    output.push("ERROR bad sequence".to_string());
                    return;
                }
            }
        } else {
            Vec::new()
        };
        if self.position.over && ["PLAY", "PASS", "REPLAY"].contains(&command) {
            output.push("ERROR game over".to_string());
            return;
        }
        match command {
            "BOARD" => {
                self.reset(new_size, new_komi);
                output.push(format!("board {new_size} komi {}", half(new_komi)));
            }
            "KOMI" => {
                self.komi = new_komi;
                output.push(format!("komi {}", half(new_komi)));
            }
            "SUPERKO" => {
                self.superko = args[0] == "ON";
                output.push(format!(
                    "superko {}",
                    if self.superko { "on" } else { "off" }
                ));
            }
            "HANDICAP" => {
                if !self.history.is_empty() || self.position.board.iter().any(|&c| c != b'.') {
                    output.push("ERROR handicap not allowed".to_string());
                    return;
                }
                let k: usize = args[0].parse().unwrap();
                let indexes: Vec<_> = if k == 5 {
                    vec![0, 1, 2, 3, 8]
                } else if k == 7 {
                    vec![0, 1, 2, 3, 4, 5, 8]
                } else {
                    (0..k).collect()
                };
                let names = handicap_names(self.size);
                let mut text = format!("handicap {k}");
                for i in indexes {
                    let p = self.point(names[i]).unwrap();
                    self.handicap.push(p);
                    self.position.board[p] = b'B';
                    text.push_str(&format!(" {}", names[i]));
                }
                self.position.turn = b'W';
                self.positions = vec![self.position.board.clone()];
                self.dead.clear();
                output.push(text);
            }
            "PLAY" => {
                let color = args[0].as_bytes()[0];
                let p = point.unwrap();
                let attempt = self.check(color, p);
                let why = if color != self.position.turn {
                    Some("turn")
                } else {
                    attempt.reason
                };
                if let Some(reason) = why {
                    output.push(format!("ILLEGAL {} {} {}", color as char, args[1], reason));
                } else {
                    let captured = self.play(color, Some(p), Some(attempt));
                    output.push(format!(
                        "{} {}{}",
                        color as char,
                        args[1],
                        if captured > 0 {
                            format!(" captures {captured}")
                        } else {
                            String::new()
                        }
                    ));
                }
            }
            "PASS" => {
                let color = args[0].as_bytes()[0];
                if color != self.position.turn {
                    output.push(format!("ILLEGAL {} pass turn", color as char));
                } else {
                    self.play(color, None, None);
                    output.push(format!("{} pass", color as char));
                    if self.position.over {
                        output.push("game over".to_string());
                    }
                }
            }
            "REPLAY" => {
                let mut count = 0;
                let mut stopped = String::new();
                for record in sequence {
                    let why = if self.position.over {
                        Some("game over")
                    } else if record.color != self.position.turn {
                        Some("turn")
                    } else {
                        record
                            .point
                            .and_then(|p| self.check(record.color, p).reason)
                    };
                    if let Some(reason) = why {
                        stopped = format!(
                            " stopped {} {} {reason}",
                            record.color as char,
                            record.point.map_or("pass".to_string(), |p| self.name(p))
                        );
                        break;
                    }
                    self.play(record.color, record.point, None);
                    count += 1;
                }
                output.push(format!("replay {count} moves{stopped}"));
                if self.position.over {
                    output.push("game over".to_string());
                }
            }
            "UNDO" => {
                if let Some(last) = self.history.pop() {
                    self.position = last.before;
                    self.positions.pop();
                    self.dead.clear();
                    output.push(format!(
                        "undo {} {}",
                        last.color as char,
                        last.point.map_or("pass".to_string(), |p| self.name(p))
                    ));
                } else {
                    output.push("ERROR nothing to undo".to_string());
                }
            }
            "SHOW" => self.show(output, false),
            "MAP" => self.show(output, true),
            "STATUS" => {
                output.push(format!(
                    "size {} komi {} handicap {} superko {}",
                    self.size,
                    half(self.komi),
                    self.handicap.len(),
                    if self.superko { "on" } else { "off" }
                ));
                output.push(if self.position.over {
                    format!("moves {} game over", self.history.len())
                } else {
                    format!(
                        "moves {} next {} passes {}",
                        self.history.len(),
                        self.position.turn as char,
                        self.position.passes
                    )
                });
            }
            "CAPTURES" => output.push(format!(
                "captures B {} W {}",
                self.position.captures[0], self.position.captures[1]
            )),
            "HISTORY" => {
                output.push(format!("history {}", self.history.len()));
                for (i, entry) in self.history.iter().enumerate() {
                    let square = entry.point.map_or("pass".to_string(), |p| self.name(p));
                    output.push(format!(
                        "{} {} {}{}",
                        i + 1,
                        entry.color as char,
                        square,
                        if entry.captured == 0 {
                            String::new()
                        } else {
                            format!(" captures {}", entry.captured)
                        }
                    ));
                }
            }
            "MOVES" => {
                let mut text = format!("(;GM[1]FF[4]SZ[{}]KM[{}]", self.size, half(self.komi));
                if !self.handicap.is_empty() {
                    text.push_str(&format!("HA[{}]AB", self.handicap.len()));
                    for &p in &self.handicap {
                        text.push_str(&format!("[{}]", sgf(p, self.size)));
                    }
                }
                for entry in &self.history {
                    text.push_str(&format!(
                        ";{}[{}]",
                        entry.color as char,
                        entry.point.map_or(String::new(), |p| sgf(p, self.size))
                    ));
                }
                text.push(')');
                output.push(text);
            }
            "GROUP" | "DEAD" | "LADDER" => {
                let p = point.unwrap();
                if self.position.board[p] == b'.' {
                    output.push("ERROR no stone".to_string());
                    return;
                }
                let g = group(&self.position.board, self.size, p);
                if command == "GROUP" {
                    output.push(format!(
                        "group {} {} size {} liberties {}",
                        g.color as char,
                        self.name(g.first),
                        g.stones.len(),
                        g.liberties.len()
                    ));
                    output.push(format!(
                        "stones{}",
                        g.stones
                            .iter()
                            .map(|&q| format!(" {}", self.name(q)))
                            .collect::<Vec<_>>()
                            .join("")
                    ));
                    output.push(format!(
                        "liberties{}",
                        g.liberties
                            .iter()
                            .map(|&q| format!(" {}", self.name(q)))
                            .collect::<Vec<_>>()
                            .join("")
                    ));
                } else if command == "DEAD" {
                    let was_dead = self.dead.contains(&p);
                    for q in &g.stones {
                        if was_dead {
                            self.dead.remove(q);
                        } else {
                            self.dead.insert(*q);
                        }
                    }
                    output.push(format!(
                        "{} {} {} size {}",
                        if was_dead { "alive" } else { "dead" },
                        g.color as char,
                        self.name(g.first),
                        g.stones.len()
                    ));
                } else {
                    let (status, move_) = ladder(&self.position.board, self.size, p);
                    output.push(format!(
                        "ladder {} {status}{}",
                        args[0],
                        move_.map_or(String::new(), |q| format!(" {}", self.name(q)))
                    ));
                }
            }
            "GROUPS" => {
                let all = groups(&self.position.board, self.size, None);
                output.push(format!("groups {}", all.len()));
                for g in all {
                    output.push(format!(
                        "{} {} size {} liberties {}{}",
                        g.color as char,
                        self.name(g.first),
                        g.stones.len(),
                        g.liberties.len(),
                        if self.dead.contains(&g.first) {
                            " dead"
                        } else {
                            ""
                        }
                    ));
                }
            }
            "ATARI" => {
                let all: Vec<_> = groups(&self.position.board, self.size, None)
                    .into_iter()
                    .filter(|g| g.liberties.len() == 1)
                    .collect();
                if all.is_empty() {
                    output.push("atari none".to_string());
                }
                for g in all {
                    output.push(format!(
                        "atari {} {} size {} at {}",
                        g.color as char,
                        self.name(g.first),
                        g.stones.len(),
                        self.name(g.liberties[0])
                    ));
                }
            }
            "LEGAL" => {
                let color = args[0].as_bytes()[0];
                let mut legal_count = 0;
                let mut invalid = Vec::new();
                for p in 0..self.position.board.len() {
                    if self.position.board[p] != b'.' {
                        continue;
                    }
                    if let Some(why) = self.check(color, p).reason {
                        invalid.push(format!("{} {why}", self.name(p)));
                    } else {
                        legal_count += 1;
                    }
                }
                output.push(format!("legal {} {legal_count}", color as char));
                output.extend(invalid);
            }
            "EYES" => {
                let color = args[0].as_bytes()[0];
                let mut found = Vec::new();
                for p in 0..self.position.board.len() {
                    if self.position.board[p] != b'.' {
                        continue;
                    }
                    let neighbors = adjacent(p, self.size, false);
                    if neighbors.iter().all(|&q| self.position.board[q] == color) {
                        let count = adjacent(p, self.size, true)
                            .into_iter()
                            .filter(|&q| self.position.board[q] == opponent(color))
                            .count();
                        let allowed = if neighbors.len() == 4 { 1 } else { 0 };
                        found.push(format!(
                            "{} {}",
                            self.name(p),
                            if count <= allowed { "real" } else { "false" }
                        ));
                    }
                }
                output.push(format!("eyes {} {}", color as char, found.len()));
                output.extend(found);
            }
            "SAFE" => {
                let color = args[0].as_bytes()[0];
                let all = safe(&self.position.board, self.size, color);
                output.push(format!("safe {} {}", color as char, all.len()));
                for g in all {
                    output.push(format!("{} size {}", self.name(g.first), g.stones.len()));
                }
            }
            "REGIONS" => {
                let all = regions(&self.clean(), self.size);
                output.push(format!("regions {}", all.len()));
                for area in all {
                    output.push(format!(
                        "{} size {} {}",
                        self.name(area.first),
                        area.points.len(),
                        area.owner
                            .map_or("neutral", |c| if c == b'B' { "B" } else { "W" })
                    ));
                }
            }
            "SCORE" => self.score(args[0], output),
            _ => {}
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let commands = lines.next().unwrap().parse::<usize>().unwrap();
    let mut game = Game::new();
    let mut output = Vec::new();
    for line in lines.take(commands) {
        game.execute(line, &mut output);
    }
    println!("{}", output.join("\n"));
}
