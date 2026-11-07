use std::fmt::{self, Write};
use std::io::{self, Read, Write as IoWrite};

const SHIP_NAMES: [&str; 5] = ["CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"];
const LENGTHS: [usize; 5] = [5, 4, 3, 3, 2];
const SYMBOLS: [char; 5] = ['C', 'B', 'R', 'S', 'D'];
const STRATEGIES: [Strategy; 3] = [Strategy::Hunt, Strategy::Prob, Strategy::Random];

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase { Setup, Battle, Over }

impl Phase {
    fn name(self) -> &'static str {
        match self { Self::Setup => "SETUP", Self::Battle => "BATTLE", Self::Over => "OVER" }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Strategy { Hunt, Prob, Random }

impl Strategy {
    fn parse(text: &str) -> Self {
        match text {
            "HUNT" => Self::Hunt,
            "PROB" => Self::Prob,
            "RANDOM" => Self::Random,
            _ => unreachable!(),
        }
    }

    fn name(self) -> &'static str {
        match self { Self::Hunt => "HUNT", Self::Prob => "PROB", Self::Random => "RANDOM" }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CellView { Reef, Unknown, Miss, Hit, Sunk }

impl CellView {
    fn symbol(self) -> char {
        match self { Self::Reef => '~', Self::Unknown => '.', Self::Miss => 'o', Self::Hit => 'x', Self::Sunk => '#' }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Shot { Already, Miss, Hit, Sunk(usize) }

impl Shot {
    fn is_hit(self) -> bool { matches!(self, Self::Hit | Self::Sunk(_)) }
}

impl fmt::Display for Shot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Already => f.write_str("ALREADY"),
            Self::Miss => f.write_str("MISS"),
            Self::Hit => f.write_str("HIT"),
            Self::Sunk(s) => write!(f, "SUNK {}", SHIP_NAMES[*s]),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Output { Normal, SinksOnly, Quiet }

#[derive(Clone, Copy)]
struct Ship { start: usize, step: usize }

impl Ship {
    fn cells(self, length: usize) -> impl Iterator<Item = usize> {
        (0..length).map(move |i| self.start + i * self.step)
    }

    fn in_bounds(self, length: usize) -> bool {
        if self.step == 1 { self.start % 10 + length <= 10 }
        else { self.start / 10 + length <= 10 }
    }

    fn range(self, length: usize) -> String {
        format!("{}-{}", cell_name(self.start), cell_name(self.start + (length - 1) * self.step))
    }

    fn touches(self, length: usize, other: Self, other_length: usize) -> bool {
        self.cells(length).any(|a| other.cells(other_length).any(|b| adjacent(a, b)))
    }
}

#[derive(Default)]
struct Stats {
    shots: i64,
    hits: i64,
    sunk: i64,
    turns: i64,
    streak: i64,
    longest: i64,
    wins: i64,
}

impl Stats {
    fn record(&mut self, shot: Shot) {
        self.shots += 1;
        if shot.is_hit() {
            self.hits += 1;
            self.streak += 1;
            self.longest = self.longest.max(self.streak);
        } else { self.streak = 0; }
        if matches!(shot, Shot::Sunk(_)) { self.sunk += 1; }
    }
}

struct Player {
    fleet: [Option<Ship>; 5],
    board: [Option<usize>; 100],
    attacked: [bool; 100],
    candidates: Vec<usize>,
    random: i64,
    controller: Option<Strategy>,
    torpedo_used: bool,
    sonar_used: bool,
    stats: Stats,
}

impl Player {
    fn new(number: usize) -> Self {
        Self {
            fleet: [None; 5], board: [None; 100], attacked: [false; 100], candidates: Vec::new(),
            random: number as i64 + 1, controller: None, torpedo_used: false, sonar_used: false,
            stats: Stats::default(),
        }
    }

    fn clear_fleet(&mut self) { self.fleet = [None; 5]; self.board = [None; 100]; }

    fn put_ship(&mut self, s: usize, ship: Ship) {
        self.fleet[s] = Some(ship);
        for c in ship.cells(LENGTHS[s]) { self.board[c] = Some(s); }
    }

    fn attacked_count(&self, s: usize) -> usize {
        self.fleet[s].map_or(0, |ship| ship.cells(LENGTHS[s]).filter(|&c| self.attacked[c]).count())
    }

    fn sunk(&self, s: usize) -> bool { self.fleet[s].is_some() && self.attacked_count(s) == LENGTHS[s] }
    fn placed(&self) -> usize { self.fleet.iter().filter(|ship| ship.is_some()).count() }
    fn afloat(&self) -> usize { (0..5).filter(|&s| self.fleet[s].is_some() && !self.sunk(s)).count() }
}

struct View {
    cells: [CellView; 100],
    excluded: [bool; 100],
    remaining: [bool; 5],
}

impl View {
    fn candidate(&self, c: usize) -> bool { self.cells[c] == CellView::Unknown && !self.excluded[c] }

    fn density(&self) -> [usize; 100] {
        let mut scores = [0; 100];
        for (s, &length) in LENGTHS.iter().enumerate() {
            if !self.remaining[s] { continue; }
            for start in 0..100 {
                for step in [1, 10] {
                    let ship = Ship { start, step };
                    if !ship.in_bounds(length) { continue; }
                    if !ship.cells(length).all(|c| !self.excluded[c] && matches!(self.cells[c], CellView::Unknown | CellView::Hit)) {
                        continue;
                    }
                    let hits = ship.cells(length).filter(|&c| self.cells[c] == CellView::Hit).count();
                    for c in ship.cells(length) { scores[c] += 1 + 10 * hits; }
                }
            }
        }
        scores
    }

    fn best(&self, scores: &[usize; 100]) -> usize {
        let mut best = None;
        for c in 0..100 {
            if self.cells[c] == CellView::Unknown && best.is_none_or(|b| scores[c] > scores[b]) { best = Some(c); }
        }
        best.unwrap()
    }
}

enum ChoiceInfo { Step(&'static str), Number(usize) }

impl fmt::Display for ChoiceInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self { Self::Step(step) => f.write_str(step), Self::Number(value) => write!(f, "{value}") }
    }
}

struct Choice { cell: usize, info: ChoiceInfo, next_random: i64 }
struct Match { winner: usize, shots: [i64; 2], hits: [i64; 2] }

struct Game {
    players: [Player; 2],
    reefs: [bool; 100],
    salvo: bool,
    chain: bool,
    touch: bool,
    phase: Phase,
    current: usize,
    winner: Option<usize>,
}

fn advance(state: i64) -> i64 { state * 48271 % 2147483647 }
fn cell_number(text: &str) -> usize { (text.as_bytes()[0] - b'A') as usize * 10 + text[1..].parse::<usize>().unwrap() - 1 }
fn cell_name(cell: usize) -> String { format!("{}{}", (b'A' + (cell / 10) as u8) as char, cell % 10 + 1) }
fn ship_number(text: &str) -> usize { SHIP_NAMES.iter().position(|&name| name == text).unwrap() }
fn switch(enabled: bool) -> &'static str { if enabled { "ON" } else { "OFF" } }
fn adjacent(a: usize, b: usize) -> bool { (a / 10).abs_diff(b / 10) <= 1 && (a % 10).abs_diff(b % 10) <= 1 }

fn neighbour(cell: usize, dr: isize, dc: isize) -> Option<usize> {
    let row = (cell / 10) as isize + dr;
    let col = (cell % 10) as isize + dc;
    if (0..10).contains(&row) && (0..10).contains(&col) { Some((row * 10 + col) as usize) } else { None }
}

impl Game {
    fn new() -> Self {
        Self {
            players: std::array::from_fn(Player::new), reefs: [false; 100], salvo: false, chain: false,
            touch: false, phase: Phase::Setup, current: 0, winner: None,
        }
    }

    fn allowance(&self, p: usize) -> usize { if self.salvo { self.players[p].afloat() } else { 1 } }

    fn placement_error(&self, p: &Player, s: usize, ship: Ship) -> Option<String> {
        if !ship.in_bounds(LENGTHS[s]) { return Some("out of bounds".into()); }
        if ship.cells(LENGTHS[s]).any(|c| self.reefs[c]) { return Some("on reef".into()); }
        for (other, name) in SHIP_NAMES.iter().enumerate() {
            if ship.cells(LENGTHS[s]).any(|c| p.board[c] == Some(other)) { return Some(format!("overlaps {name}")); }
        }
        if !self.touch {
            for (other, placed) in p.fleet.iter().enumerate() {
                if placed.is_some_and(|other_ship| ship.touches(LENGTHS[s], other_ship, LENGTHS[other])) {
                    return Some(format!("touches {}", SHIP_NAMES[other]));
                }
            }
        }
        None
    }

    fn print_placed(&self, p: usize, s: usize, out: &mut String) {
        writeln!(out, "PLACED {} {} {}", p + 1, SHIP_NAMES[s], self.players[p].fleet[s].unwrap().range(LENGTHS[s])).unwrap();
    }

    fn autoplace(&mut self, p: usize, seed: i64) -> i64 {
        self.players[p].clear_fleet();
        self.players[p].random = seed;
        let mut attempts = 0;
        for (s, &length) in LENGTHS.iter().enumerate() {
            loop {
                attempts += 1;
                self.players[p].random = advance(self.players[p].random);
                let step = if self.players[p].random % 2 == 0 { 1 } else { 10 };
                self.players[p].random = advance(self.players[p].random);
                let k = self.players[p].random as usize % (10 * (11 - length));
                let start = if step == 1 { k / (11 - length) * 10 + k % (11 - length) } else { k };
                let ship = Ship { start, step };
                if self.placement_error(&self.players[p], s, ship).is_none() {
                    self.players[p].put_ship(s, ship);
                    break;
                }
            }
        }
        attempts
    }

    fn parse_layout(&self, layout: &str) -> Result<[Ship; 5], String> {
        let mut fleet = [Ship { start: 0, step: 1 }; 5];
        let bytes = layout.as_bytes();
        for s in 0..5 {
            let cells: Vec<_> = (0..100).filter(|&c| bytes[c / 10 * 11 + c % 10] == SYMBOLS[s] as u8).collect();
            if cells.len() != LENGTHS[s] { return Err(format!("{} has {} cells", SHIP_NAMES[s], cells.len())); }
            let ship = Ship { start: cells[0], step: cells[1] - cells[0] };
            if !matches!(ship.step, 1 | 10) || !ship.in_bounds(LENGTHS[s]) || !ship.cells(LENGTHS[s]).eq(cells.iter().copied()) {
                return Err(format!("{} not straight", SHIP_NAMES[s]));
            }
            if cells.iter().any(|&c| self.reefs[c]) { return Err(format!("{} on reef", SHIP_NAMES[s])); }
            fleet[s] = ship;
        }
        if !self.touch {
            for a in 0..5 {
                for b in a + 1..5 {
                    if fleet[a].touches(LENGTHS[a], fleet[b], LENGTHS[b]) {
                        return Err(format!("{} touches {}", SHIP_NAMES[a], SHIP_NAMES[b]));
                    }
                }
            }
        }
        Ok(fleet)
    }

    fn view(&self, p: usize) -> View {
        let opponent = &self.players[1 - p];
        let remaining = std::array::from_fn(|s| !opponent.sunk(s));
        let cells = std::array::from_fn(|c| {
            if self.reefs[c] { CellView::Reef }
            else if !opponent.attacked[c] { CellView::Unknown }
            else {
                match opponent.board[c] {
                    None => CellView::Miss,
                    Some(s) if remaining[s] => CellView::Hit,
                    Some(_) => CellView::Sunk,
                }
            }
        });
        let mut excluded = [false; 100];
        if !self.touch {
            for (c, &state) in cells.iter().enumerate() {
                if state != CellView::Sunk { continue; }
                for dr in -1..=1 {
                    for dc in -1..=1 {
                        if dr == 0 && dc == 0 { continue; }
                        if let Some(other) = neighbour(c, dr, dc) { excluded[other] = true; }
                    }
                }
            }
        }
        View { cells, excluded, remaining }
    }

    fn choose(&self, p: usize, strategy: Strategy) -> Choice {
        let view = self.view(p);
        let player = &self.players[p];
        if strategy == Strategy::Prob {
            let scores = view.density();
            let cell = view.best(&scores);
            return Choice { cell, info: ChoiceInfo::Number(scores[cell]), next_random: player.random };
        }
        if strategy == Strategy::Random {
            let cells: Vec<_> = (0..100).filter(|&c| view.candidate(c)).collect();
            let next_random = advance(player.random);
            return Choice { cell: cells[next_random as usize % cells.len()], info: ChoiceInfo::Number(cells.len()), next_random };
        }
        for h in 0..100 {
            if view.cells[h] != CellView::Hit { continue; }
            for (dr, dc) in [(0, 1), (1, 0)] {
                let mut front = neighbour(h, dr, dc);
                if !front.is_some_and(|c| view.cells[c] == CellView::Hit) { continue; }
                while front.is_some_and(|c| view.cells[c] == CellView::Hit) { front = neighbour(front.unwrap(), dr, dc); }
                for cell in [front, neighbour(h, -dr, -dc)].iter().copied().flatten() {
                    if view.candidate(cell) { return Choice { cell, info: ChoiceInfo::Step("LINE"), next_random: player.random }; }
                }
            }
        }
        for &cell in player.candidates.iter().rev() {
            if view.candidate(cell) { return Choice { cell, info: ChoiceInfo::Step("STACK"), next_random: player.random }; }
        }
        let shortest = (0..5).filter(|&s| view.remaining[s]).map(|s| LENGTHS[s]).min().unwrap();
        let cell = (0..100).find(|&c| view.candidate(c) && (c / 10 + c % 10) % shortest == 0).unwrap();
        Choice { cell, info: ChoiceInfo::Step("PARITY"), next_random: player.random }
    }

    fn shoot(&mut self, p: usize, cell: usize) -> Shot {
        let opponent = &mut self.players[1 - p];
        let shot = if opponent.attacked[cell] { Shot::Already } else {
            opponent.attacked[cell] = true;
            match opponent.board[cell] {
                None => Shot::Miss,
                Some(s) if opponent.sunk(s) => Shot::Sunk(s),
                Some(_) => Shot::Hit,
            }
        };
        let player = &mut self.players[p];
        if shot == Shot::Hit {
            for (dr, dc) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                if let Some(c) = neighbour(cell, dr, dc) { player.candidates.push(c); }
            }
        }
        player.stats.record(shot);
        shot
    }

    fn emit_shot(&self, p: usize, cell: usize, shot: Shot, output: Output, out: &mut String) {
        if output == Output::Normal { writeln!(out, "SHOT {} {} {shot}", p + 1, cell_name(cell)).unwrap(); }
        else if output == Output::SinksOnly {
            if let Shot::Sunk(s) = shot { writeln!(out, "SINK {} {} {}", p + 1, SHIP_NAMES[s], self.players[p].stats.shots).unwrap(); }
        }
    }

    fn finish_turn(&mut self, p: usize, hit: bool, output: Output, out: &mut String) {
        self.players[p].stats.turns += 1;
        if self.players[1 - p].afloat() == 0 {
            self.phase = Phase::Over;
            self.winner = Some(p);
            self.players[p].stats.wins += 1;
            if output == Output::Normal { writeln!(out, "WINNER {}", p + 1).unwrap(); }
        } else { self.current = if self.chain && hit { p } else { 1 - p }; }
    }

    fn ai_turn(&mut self, p: usize, strategy: Strategy, output: Output, out: &mut String) {
        let allowance = self.allowance(p);
        let mut hit = false;
        for _ in 0..allowance {
            let choice = self.choose(p, strategy);
            self.players[p].random = choice.next_random;
            let shot = self.shoot(p, choice.cell);
            self.emit_shot(p, choice.cell, shot, output, out);
            hit |= shot.is_hit();
            if self.players[1 - p].afloat() == 0 { break; }
        }
        self.finish_turn(p, hit, output, out);
    }

    fn automatic_control(&mut self, out: &mut String) {
        while self.phase == Phase::Battle {
            let p = self.current;
            let Some(strategy) = self.players[p].controller else { break; };
            self.ai_turn(p, strategy, Output::Normal, out);
        }
    }

    fn turn(&mut self, words: &[&str], out: &mut String) -> Result<(), String> {
        let cmd = words[0];
        let p = words[1].parse::<usize>().unwrap() - 1;
        if self.phase == Phase::Over { return Err("game over".into()); }
        if self.phase == Phase::Setup && self.players.iter().any(|player| player.placed() != 5) {
            return Err("fleets not ready".into());
        }
        if self.current != p { return Err("not your turn".into()); }
        if cmd == "FIRE" {
            let expected = self.allowance(p);
            if words.len() - 2 != expected { return Err(format!("expected {expected} shots")); }
            for &text in &words[2..] {
                if self.reefs[cell_number(text)] { return Err(format!("reef at {text}")); }
            }
        } else if cmd == "TORPEDO" && self.players[p].torpedo_used { return Err("torpedo used".into()); }
        else if cmd == "SONAR" && self.players[p].sonar_used { return Err("sonar used".into()); }
        self.phase = Phase::Battle;
        if cmd == "AI" { self.ai_turn(p, Strategy::parse(words[2]), Output::Normal, out); return Ok(()); }
        let mut hit = false;
        match cmd {
            "FIRE" => {
                for &text in &words[2..] {
                    let cell = cell_number(text);
                    let shot = self.shoot(p, cell);
                    self.emit_shot(p, cell, shot, Output::Normal, out);
                    hit |= shot.is_hit();
                    if self.players[1 - p].afloat() == 0 { break; }
                }
            }
            "SONAR" => {
                self.players[p].sonar_used = true;
                let centre = cell_number(words[2]);
                let opponent = &self.players[1 - p];
                let count = (0..100).filter(|&c| adjacent(c, centre) && opponent.board[c].is_some() && !opponent.attacked[c]).count();
                writeln!(out, "SONAR {} {} {count}", p + 1, words[2]).unwrap();
            }
            "TORPEDO" => {
                self.players[p].torpedo_used = true;
                let mut result = "MISS".to_owned();
                let mut stopped_at_ship = false;
                for i in 0..10 {
                    let cell = (words[2].as_bytes()[0] - b'A') as usize * 10 + if words[3] == "W" { i } else { 9 - i };
                    if self.reefs[cell] { result = format!("REEF {}", cell_name(cell)); break; }
                    if self.players[1 - p].board[cell].is_some() {
                        let shot = self.shoot(p, cell);
                        hit = shot.is_hit();
                        result = format!("{shot} {}", cell_name(cell));
                        stopped_at_ship = true;
                        break;
                    }
                    self.players[1 - p].attacked[cell] = true;
                }
                if !stopped_at_ship { self.players[p].stats.record(Shot::Miss); }
                writeln!(out, "TORPEDO {} {} {} {result}", p + 1, words[2], words[3]).unwrap();
            }
            _ => unreachable!(),
        }
        self.finish_turn(p, hit, Output::Normal, out);
        Ok(())
    }

    fn play_match(&self, seed1: i64, seed2: i64, strategies: [Strategy; 2], output: Output, out: &mut String) -> Match {
        let mut game = Self::new();
        game.salvo = self.salvo;
        game.chain = self.chain;
        game.touch = self.touch;
        game.reefs = self.reefs;
        game.autoplace(0, seed1);
        game.autoplace(1, seed2);
        game.phase = Phase::Battle;
        while game.phase == Phase::Battle {
            let p = game.current;
            game.ai_turn(p, strategies[p], output, out);
        }
        Match {
            winner: game.winner.unwrap(), shots: std::array::from_fn(|p| game.players[p].stats.shots),
            hits: std::array::from_fn(|p| game.players[p].stats.hits),
        }
    }

    fn show_board(&self, p: usize, radar: bool, out: &mut String) {
        writeln!(out, "{} {}\n  1 2 3 4 5 6 7 8 9 10", if radar { "RADAR" } else { "BOARD" }, p + 1).unwrap();
        let view = self.view(p);
        let player = &self.players[p];
        for row in 0..10 {
            out.push((b'A' + row as u8) as char);
            for col in 0..10 {
                let c = row * 10 + col;
                let mark = if radar { view.cells[c].symbol() }
                else if self.reefs[c] { '~' }
                else if let Some(s) = player.board[c] {
                    if player.attacked[c] { SYMBOLS[s].to_ascii_lowercase() } else { SYMBOLS[s] }
                } else if player.attacked[c] { 'o' } else { '.' };
                write!(out, " {mark}").unwrap();
            }
            out.push('\n');
        }
    }

    fn execute(&mut self, w: &[&str], out: &mut String) -> Result<(), String> {
        let cmd = w[0];
        if matches!(cmd, "PLACE" | "REMOVE" | "AUTOPLACE" | "LAYOUT" | "REEF" | "SALVO" | "CHAIN" | "TOUCH") && self.phase != Phase::Setup {
            return Err("setup closed".into());
        }
        match cmd {
            "NEW" => {
                let wins = [self.players[0].stats.wins, self.players[1].stats.wins];
                *self = Self::new();
                for (p, win_count) in wins.iter().copied().enumerate() { self.players[p].stats.wins = win_count; }
                writeln!(out, "NEW").unwrap();
            }
            "SEED" | "CONTROL" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                if cmd == "SEED" {
                    self.players[p].random = w[2].parse().unwrap();
                    writeln!(out, "SEED {} {}", p + 1, self.players[p].random).unwrap();
                } else {
                    self.players[p].controller = if w[2] == "HUMAN" { None } else { Some(Strategy::parse(w[2])) };
                    writeln!(out, "CONTROL {} {}", p + 1, w[2]).unwrap();
                }
            }
            "SALVO" | "CHAIN" | "TOUCH" => {
                let enabled = w[1] == "ON";
                match cmd { "SALVO" => self.salvo = enabled, "CHAIN" => self.chain = enabled, _ => self.touch = enabled }
                writeln!(out, "{cmd} {}", w[1]).unwrap();
            }
            "PLACE" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                let s = ship_number(w[2]);
                if self.players[p].fleet[s].is_some() { return Err(format!("{} already placed", SHIP_NAMES[s])); }
                let ship = Ship { start: cell_number(w[3]), step: if w[4] == "H" { 1 } else { 10 } };
                if let Some(error) = self.placement_error(&self.players[p], s, ship) { return Err(error); }
                self.players[p].put_ship(s, ship);
                self.print_placed(p, s, out);
            }
            "REMOVE" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                let s = ship_number(w[2]);
                let ship = self.players[p].fleet[s].ok_or_else(|| format!("{} not placed", SHIP_NAMES[s]))?;
                for c in ship.cells(LENGTHS[s]) { self.players[p].board[c] = None; }
                self.players[p].fleet[s] = None;
                writeln!(out, "REMOVED {} {}", p + 1, SHIP_NAMES[s]).unwrap();
            }
            "AUTOPLACE" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                let attempts = self.autoplace(p, w[2].parse().unwrap());
                writeln!(out, "AUTOPLACE {} attempts {attempts}", p + 1).unwrap();
                for s in 0..5 { self.print_placed(p, s, out); }
            }
            "LAYOUT" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                let fleet = self.parse_layout(w[2])?;
                self.players[p].clear_fleet();
                for (s, ship) in fleet.iter().copied().enumerate() { self.players[p].put_ship(s, ship); }
                writeln!(out, "LAYOUT {}", p + 1).unwrap();
                for s in 0..5 { self.print_placed(p, s, out); }
            }
            "REEF" => {
                let c = cell_number(w[1]);
                if self.reefs[c] { return Err(format!("reef exists at {}", w[1])); }
                for (p, player) in self.players.iter().enumerate() {
                    if let Some(s) = player.board[c] { return Err(format!("{} occupied by {} {}", w[1], p + 1, SHIP_NAMES[s])); }
                }
                self.reefs[c] = true;
                writeln!(out, "REEF {}", w[1]).unwrap();
            }
            "FIRE" | "AI" | "TORPEDO" | "SONAR" => { self.turn(w, out)?; self.automatic_control(out); }
            "RESIGN" => {
                if self.phase != Phase::Battle { return Err("not in battle".into()); }
                let p = w[1].parse::<usize>().unwrap() - 1;
                self.phase = Phase::Over;
                self.winner = Some(1 - p);
                self.players[1 - p].stats.wins += 1;
                writeln!(out, "RESIGN {}\nWINNER {}", p + 1, 2 - p).unwrap();
            }
            "HINT" | "DENSITY" => {
                if self.phase == Phase::Over { return Err("game over".into()); }
                let p = w[1].parse::<usize>().unwrap() - 1;
                if cmd == "HINT" {
                    let choice = self.choose(p, Strategy::parse(w[2]));
                    writeln!(out, "HINT {} {} {} {}", p + 1, w[2], cell_name(choice.cell), choice.info).unwrap();
                } else {
                    let view = self.view(p);
                    let scores = view.density();
                    writeln!(out, "DENSITY {}", p + 1).unwrap();
                    out.push(' ');
                    for col in 1..=10 { write!(out, "{col:>5}").unwrap(); }
                    out.push('\n');
                    for row in 0..10 {
                        out.push((b'A' + row as u8) as char);
                        for col in 0..10 {
                            let c = row * 10 + col;
                            if view.cells[c] == CellView::Unknown { write!(out, "{:>5}", scores[c]).unwrap(); }
                            else { write!(out, "{:>5}", if view.cells[c] == CellView::Reef { "~" } else { "-" }).unwrap(); }
                        }
                        out.push('\n');
                    }
                    let best = view.best(&scores);
                    writeln!(out, "BEST {} {}", cell_name(best), scores[best]).unwrap();
                }
            }
            "SHOW" | "RADAR" => self.show_board(w[1].parse::<usize>().unwrap() - 1, cmd == "RADAR", out),
            "EXPORT" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                let rows: Vec<String> = self.players[p].board.chunks(10).map(|row| row.iter().map(|s| s.map_or('.', |s| SYMBOLS[s])).collect()).collect();
                writeln!(out, "EXPORT {} {}", p + 1, rows.join("/")).unwrap();
            }
            "FLEET" => {
                let p = w[1].parse::<usize>().unwrap() - 1;
                let player = &self.players[p];
                writeln!(out, "FLEET {} afloat {}", p + 1, player.afloat()).unwrap();
                for s in 0..5 {
                    if let Some(ship) = player.fleet[s] {
                        writeln!(out, "{} {} {}/{} {}", SHIP_NAMES[s], ship.range(LENGTHS[s]), player.attacked_count(s), LENGTHS[s], if player.sunk(s) { "SUNK" } else { "AFLOAT" }).unwrap();
                    } else { writeln!(out, "{} unplaced", SHIP_NAMES[s]).unwrap(); }
                }
            }
            "STATUS" => {
                write!(out, "STATUS {} salvo {} chain {} touch {} reefs {}", self.phase.name(), switch(self.salvo), switch(self.chain), switch(self.touch), self.reefs.iter().filter(|&&reef| reef).count()).unwrap();
                match self.phase {
                    Phase::Setup => writeln!(out, " placed {} {}", self.players[0].placed(), self.players[1].placed()).unwrap(),
                    Phase::Battle => writeln!(out, " turn {} shots {} afloat {} {}", self.current + 1, self.allowance(self.current), self.players[0].afloat(), self.players[1].afloat()).unwrap(),
                    Phase::Over => writeln!(out, " winner {} afloat {} {}", self.winner.unwrap() + 1, self.players[0].afloat(), self.players[1].afloat()).unwrap(),
                }
            }
            "STATS" => {
                for (p, player) in self.players.iter().enumerate() {
                    let s = &player.stats;
                    let accuracy = if s.shots == 0 { "-".to_owned() } else { format!("{}%", s.hits * 100 / s.shots) };
                    writeln!(out, "STATS {} shots {} hits {} sunk {} turns {} streak {} accuracy {accuracy} wins {}", p + 1, s.shots, s.hits, s.sunk, s.turns, s.longest, s.wins).unwrap();
                }
            }
            "MATCH" => {
                let strategies = [Strategy::parse(w[3]), Strategy::parse(w[4])];
                writeln!(out, "MATCH 1 {} 2 {}", w[3], w[4]).unwrap();
                let result = self.play_match(w[1].parse().unwrap(), w[2].parse().unwrap(), strategies, Output::SinksOnly, out);
                writeln!(out, "RESULT winner {} shots {} {} hits {} {}", result.winner + 1, result.shots[0], result.shots[1], result.hits[0], result.hits[1]).unwrap();
            }
            "SERIES" => {
                let count: usize = w[1].parse().unwrap();
                let mut random = w[2].parse().unwrap();
                let strategies = [Strategy::parse(w[3]), Strategy::parse(w[4])];
                let mut wins = [0i64; 2];
                let mut shots = [0i64; 2];
                let mut fastest: [Option<i64>; 2] = [None; 2];
                for _ in 0..count {
                    random = advance(random);
                    let seed1 = random;
                    random = advance(random);
                    let result = self.play_match(seed1, random, strategies, Output::Quiet, out);
                    let winner = result.winner;
                    wins[winner] += 1;
                    for p in 0..2 { shots[p] += result.shots[p]; }
                    if fastest[winner].is_none_or(|best| result.shots[winner] < best) { fastest[winner] = Some(result.shots[winner]); }
                }
                let fastest = fastest.map(|value| value.map_or_else(|| "-".to_owned(), |value| value.to_string()));
                writeln!(out, "SERIES {count} wins {} {} shots {} {} fastest {} {}", wins[0], wins[1], shots[0], shots[1], fastest[0], fastest[1]).unwrap();
            }
            "TOURNEY" => {
                let count: usize = w[1].parse().unwrap();
                let mut random = w[2].parse().unwrap();
                let mut wins = [0i64; 3];
                let mut shots = [0i64; 3];
                for (a, &first) in STRATEGIES.iter().enumerate() {
                    for (b, &second) in STRATEGIES.iter().enumerate() {
                        if a == b { continue; }
                        for _ in 0..count {
                            random = advance(random);
                            let seed1 = random;
                            random = advance(random);
                            let result = self.play_match(seed1, random, [first, second], Output::Quiet, out);
                            wins[if result.winner == 0 { a } else { b }] += 1;
                            shots[a] += result.shots[0];
                            shots[b] += result.shots[1];
                        }
                    }
                }
                let mut order = [0, 1, 2];
                order.sort_by_key(|&s| (-wins[s], shots[s], s));
                writeln!(out, "TOURNEY {count}").unwrap();
                for (rank, s) in order.iter().copied().enumerate() {
                    writeln!(out, "{} {} wins {} shots {}", rank + 1, STRATEGIES[s].name(), wins[s], shots[s]).unwrap();
                }
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut game = Game::new();
    let mut output = String::new();
    for line in lines.take(count) {
        let words: Vec<_> = line.split_whitespace().collect();
        if let Err(error) = game.execute(&words, &mut output) { writeln!(output, "ERROR {error}").unwrap(); }
    }
    io::BufWriter::new(io::stdout().lock()).write_all(output.as_bytes()).unwrap();
}
