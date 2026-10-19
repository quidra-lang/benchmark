use std::collections::{BTreeMap, VecDeque};
use std::io::{self, Read};

const CATEGORIES: [&str; 13] = [
    "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
    "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE",
];
const POWERS: [usize; 6] = [1, 6, 36, 216, 1296, 7776];
const FACTORIAL: [i64; 6] = [1, 1, 2, 6, 24, 120];
const CODES: usize = 46656;
type CommandResult<T = ()> = Result<T, String>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Strategy { Kind, Straight, High, Upper }

impl Strategy {
    fn parse(word: &str) -> CommandResult<Self> {
        match word {
            "KIND" => Ok(Self::Kind),
            "STRAIGHT" => Ok(Self::Straight),
            "HIGH" => Ok(Self::High),
            "UPPER" => Ok(Self::Upper),
            _ => Err(format!("bad strategy {word}")),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Kind => "KIND", Self::Straight => "STRAIGHT",
            Self::High => "HIGH", Self::Upper => "UPPER",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum JokerRule { Forced, Free, Off }

#[derive(Clone, Copy)]
struct Rules { rolls: usize, joker: JokerRule }

fn positive(word: &str, maximum: i64) -> CommandResult<i64> {
    if !matches!(word.as_bytes()[0], b'1'..=b'9') || !word.bytes().all(|b| b.is_ascii_digit()) {
        return Err(format!("bad value {word}"));
    }
    let value = word.parse::<i64>().unwrap();
    if value > maximum { Err(format!("bad value {word}")) } else { Ok(value) }
}

fn valid_name(word: &str) -> CommandResult {
    if word.len() > 8 || !word.bytes().all(|b| b.is_ascii_uppercase()) {
        Err(format!("bad name {word}"))
    } else { Ok(()) }
}

fn parse_pattern(word: &str) -> CommandResult<u8> {
    if word.len() != 5 || !word.bytes().all(|b| b == b'0' || b == b'1') {
        return Err(format!("bad pattern {word}"));
    }
    Ok(word.bytes().fold(0, |mask, b| mask * 2 + b - b'0'))
}

fn fraction(mut numerator: i64, mut denominator: i64) -> String {
    let (mut a, mut b) = (numerator, denominator);
    while b != 0 { (a, b) = (b, a % b); }
    numerator /= a;
    denominator /= a;
    if denominator == 1 { numerator.to_string() } else { format!("{numerator}/{denominator}") }
}

fn average(sum: i64, count: usize) -> String {
    let value = if count == 0 { 0 } else { 100 * sum / count as i64 };
    format!("{}.{:02}", value / 100, value % 100)
}

fn held(mask: u8, die: usize) -> bool { mask & (1 << (4 - die)) != 0 }

fn pattern_text(mask: u8) -> String { format!("{mask:05b}") }

fn face_text(faces: &[usize; 5], mask: u8) -> String {
    let selected: Vec<_> = faces.iter().enumerate()
        .filter(|(i, _)| held(mask, *i)).map(|(_, face)| face.to_string()).collect();
    if selected.is_empty() { "-".into() } else { selected.join(" ") }
}

fn face_counts(faces: &[usize; 5]) -> [usize; 6] {
    let mut counts = [0; 6];
    for &face in faces { counts[face - 1] += 1; }
    counts
}

fn decode(mut code: usize) -> [usize; 6] {
    std::array::from_fn(|_| { let count = code % 6; code /= 6; count })
}

fn held_code(faces: &[usize; 5], mask: u8) -> usize {
    faces.iter().enumerate().filter(|(i, _)| held(mask, *i))
        .map(|(_, face)| POWERS[face - 1]).sum()
}

fn frequent(counts: &[usize; 6]) -> usize {
    (0..6).max_by_key(|&i| (counts[i], i)).unwrap()
}

fn normal_score(category: usize, counts: &[usize; 6]) -> i32 {
    if category < 6 { return ((category + 1) * counts[category]) as i32; }
    let sum = counts.iter().enumerate().map(|(i, n)| (i + 1) * n).sum::<usize>() as i32;
    let maximum = *counts.iter().max().unwrap();
    let bits = (0..6).filter(|&i| counts[i] != 0).fold(0, |mask, i| mask | (1 << i));
    match category {
        6 => if maximum >= 3 { sum } else { 0 },
        7 => if maximum >= 4 { sum } else { 0 },
        8 => if counts.contains(&2) && counts.contains(&3) { 25 } else { 0 },
        9 => if bits & 15 == 15 || bits & 30 == 30 || bits & 60 == 60 { 30 } else { 0 },
        10 => if bits == 31 || bits == 62 { 40 } else { 0 },
        11 => if maximum == 5 { 50 } else { 0 },
        _ => sum,
    }
}

struct Player {
    name: String,
    strategy: Strategy,
    scores: [Option<i32>; 13],
    yahtzee_bonus: i32,
}

impl Player {
    fn new(name: &str) -> Self {
        Self { name: name.into(), strategy: Strategy::Kind, scores: [None; 13], yahtzee_bonus: 0 }
    }

    fn upper(&self) -> i32 { self.scores[..6].iter().flatten().sum() }
    fn upper_bonus(&self) -> i32 { if self.upper() >= 63 { 35 } else { 0 } }
    fn total(&self) -> i32 { self.scores.iter().flatten().sum::<i32>() + self.upper_bonus() + self.yahtzee_bonus }
    fn round(&self) -> usize { self.scores.iter().filter(|s| s.is_some()).count() + 1 }
}

struct Candidates {
    points: [Option<i32>; 13],
    allowed: u16,
    best: usize,
    yahtzee_face: Option<usize>,
    joker: bool,
}

fn evaluate(player: &Player, counts: &[usize; 6], rule: JokerRule) -> Candidates {
    let yahtzee_face = counts.iter().position(|&n| n == 5);
    let joker = rule != JokerRule::Off && yahtzee_face.is_some() && player.scores[11].is_some();
    let mut allowed = (0..13).filter(|&c| player.scores[c].is_none()).fold(0, |mask, c| mask | (1 << c));
    if joker && rule == JokerRule::Forced {
        let upper = 1 << yahtzee_face.unwrap();
        if allowed & upper != 0 { allowed = upper; }
        else if allowed & 0x1fc0 != 0 { allowed &= 0x1fc0; }
    }
    let mut result = Candidates { points: [None; 13], allowed, best: 0, yahtzee_face, joker };
    let mut best_score = -1;
    for c in 0..13 {
        if player.scores[c].is_some() { continue; }
        let points = if allowed & (1 << c) == 0 { 0 }
            else if joker && (8..=10).contains(&c) { [25, 30, 40][c - 8] }
            else { normal_score(c, counts) };
        result.points[c] = Some(points);
        if points > best_score { best_score = points; result.best = c; }
    }
    result
}

#[derive(Clone, Copy)]
struct Outcome { code: usize, weight: i64 }

fn make_outcomes() -> [Vec<Outcome>; 6] {
    fn fill(out: &mut Vec<Outcome>, size: usize, face: usize, left: usize, code: usize, divisor: i64) {
        if face == 6 {
            if left == 0 { out.push(Outcome { code, weight: FACTORIAL[size] / divisor }); }
            return;
        }
        for n in 0..=left { fill(out, size, face + 1, left - n, code + n * POWERS[face], divisor * FACTORIAL[n]); }
    }
    std::array::from_fn(|size| {
        let mut out = Vec::new();
        fill(&mut out, size, 0, size, 0, 1);
        out
    })
}

#[derive(Clone, Copy, Default)]
struct Turn { seat: usize, rolls: usize, faces: [usize; 5], hold: u8 }

#[derive(Clone, Copy)]
struct ScoreEntry { before: Turn, category: usize, points: i32, bonus: i32, joker: bool }

struct RedoEntry { after: Option<Turn>, entry: ScoreEntry }

struct Game {
    players: Vec<Player>,
    rules: Rules,
    random_state: i64,
    face_counts: [i64; 6],
    loaded: VecDeque<usize>,
    entries: Vec<ScoreEntry>,
    redo: Vec<RedoEntry>,
    turn: Option<Turn>,
    verbose: bool,
}

impl Game {
    fn new(seed: i64, names: &[&str], rules: Rules, verbose: bool) -> Self {
        Self {
            players: names.iter().map(|name| Player::new(name)).collect(), rules,
            random_state: seed, face_counts: [0; 6], loaded: VecDeque::new(),
            entries: Vec::new(), redo: Vec::new(), turn: Some(Turn::default()), verbose,
        }
    }

    fn check_turn(&self) -> CommandResult<Turn> { self.turn.ok_or_else(|| "game over".into()) }

    fn rolled(&self) -> CommandResult<Turn> {
        let turn = self.check_turn()?;
        if turn.rolls == 0 { Err("not rolled".into()) } else { Ok(turn) }
    }

    fn rolls_left(&self) -> CommandResult<Turn> {
        let turn = self.rolled()?;
        if turn.rolls == self.rules.rolls { Err("no rolls left".into()) } else { Ok(turn) }
    }

    fn roll(&mut self) -> CommandResult {
        let mut turn = self.check_turn()?;
        if turn.rolls == self.rules.rolls { return Err("no rolls left".into()); }
        if turn.hold == 31 { return Err("all dice held".into()); }
        self.redo.clear();
        for i in 0..5 {
            if turn.rolls != 0 && held(turn.hold, i) { continue; }
            turn.faces[i] = if let Some(face) = self.loaded.pop_front() { face } else {
                self.random_state = 48271 * self.random_state % 2147483647;
                (self.random_state % 6 + 1) as usize
            };
            self.face_counts[turn.faces[i] - 1] += 1;
        }
        turn.rolls += 1;
        self.turn = Some(turn);
        if self.verbose { println!("{} roll {}: {}", self.players[turn.seat].name, turn.rolls, face_text(&turn.faces, 31)); }
        Ok(())
    }

    fn hold(&mut self, mask: u8) -> CommandResult {
        let mut turn = self.rolls_left()?;
        self.redo.clear();
        turn.hold = mask;
        self.turn = Some(turn);
        if self.verbose { println!("{} holds {}: {}", self.players[turn.seat].name, pattern_text(mask), face_text(&turn.faces, mask)); }
        Ok(())
    }

    fn keep(&mut self, values: &[usize]) -> CommandResult {
        let turn = self.rolls_left()?;
        let mut mask = 0;
        for &value in values {
            let die = (0..5).find(|&i| !held(mask, i) && turn.faces[i] == value)
                .ok_or_else(|| format!("not showing {value}"))?;
            mask |= 1 << (4 - die);
        }
        self.hold(mask)
    }

    fn score(&mut self, category: usize, preview: bool) -> CommandResult {
        let turn = self.rolled()?;
        let player = &self.players[turn.seat];
        if player.scores[category].is_some() { return Err(format!("{} already used", CATEGORIES[category])); }
        let candidates = evaluate(player, &face_counts(&turn.faces), self.rules.joker);
        if candidates.allowed & (1 << category) == 0 {
            let face = candidates.yahtzee_face.unwrap();
            return Err(format!("joker requires {}", if player.scores[face].is_none() { CATEGORIES[face] } else { "lower box" }));
        }
        let points = candidates.points[category].unwrap();
        let bonus = if candidates.yahtzee_face.is_some() && player.scores[11] == Some(50) { 100 } else { 0 };
        let upper = player.upper();
        let gained_upper = if category < 6 && upper < 63 && upper + points >= 63 { 35 } else { 0 };
        if self.verbose {
            print!("{} {} {} in {}", player.name, if preview { "would score" } else { "scores" }, points, CATEGORIES[category]);
            if candidates.joker { print!(" joker"); }
            if bonus != 0 { print!(" ybonus 100"); }
            if gained_upper != 0 { print!(" ubonus 35"); }
            println!(" total {}", player.total() + points + bonus + gained_upper);
        }
        if preview { return Ok(()); }
        self.redo.clear();
        self.entries.push(ScoreEntry { before: turn, category, points, bonus, joker: candidates.joker });
        self.players[turn.seat].scores[category] = Some(points);
        self.players[turn.seat].yahtzee_bonus += bonus;
        self.turn = if self.entries.len() == 13 * self.players.len() { None }
            else { Some(Turn { seat: (turn.seat + 1) % self.players.len(), ..Turn::default() }) };
        if self.verbose {
            if let Some(next) = self.turn { println!("turn {} {}", self.players[next.seat].round(), self.players[next.seat].name); }
            else { println!("game over"); }
        }
        Ok(())
    }

    fn undo(&mut self) -> CommandResult {
        let entry = self.entries.pop().ok_or_else(|| "nothing to undo".to_string())?;
        self.redo.push(RedoEntry { after: self.turn, entry });
        let player = &mut self.players[entry.before.seat];
        player.scores[entry.category] = None;
        player.yahtzee_bonus -= entry.bonus;
        self.turn = Some(entry.before);
        println!("undo {} {} {}", player.name, CATEGORIES[entry.category], entry.points);
        Ok(())
    }

    fn redo(&mut self) -> CommandResult {
        let saved = self.redo.pop().ok_or_else(|| "nothing to redo".to_string())?;
        let entry = saved.entry;
        let player = &mut self.players[entry.before.seat];
        player.scores[entry.category] = Some(entry.points);
        player.yahtzee_bonus += entry.bonus;
        self.entries.push(entry);
        self.turn = saved.after;
        println!("redo {} {} {}", player.name, CATEGORIES[entry.category], entry.points);
        Ok(())
    }

    fn bot_hold(&self, strategy: Strategy) -> u8 {
        let faces = self.turn.unwrap().faces;
        let counts = face_counts(&faces);
        let favorite = frequent(&counts) + 1;
        let mut mask = 0;
        if strategy == Strategy::Straight {
            let (mut best_start, mut best_length) = (0, 0);
            for start in 0..6 {
                let mut end = start;
                while end < 6 && counts[end] != 0 { end += 1; }
                if end - start >= best_length { best_start = start; best_length = end - start; }
            }
            if best_length >= 3 {
                for face in best_start + 1..=best_start + best_length {
                    let die = faces.iter().position(|&value| value == face).unwrap();
                    mask |= 1 << (4 - die);
                }
                return mask;
            }
        }
        for (i, &face) in faces.iter().enumerate() {
            if if strategy == Strategy::High { face >= 5 } else { face == favorite } { mask |= 1 << (4 - i); }
        }
        mask
    }

    fn bot_turn(&mut self) {
        let strategy = self.players[self.turn.unwrap().seat].strategy;
        if self.turn.unwrap().rolls == 0 { self.roll().unwrap(); }
        while self.turn.unwrap().rolls < self.rules.rolls {
            let mask = self.bot_hold(strategy);
            if mask == 31 { break; }
            self.hold(mask).unwrap();
            self.roll().unwrap();
        }
        let turn = self.turn.unwrap();
        let counts = face_counts(&turn.faces);
        let candidates = evaluate(&self.players[turn.seat], &counts, self.rules.joker);
        let favorite = frequent(&counts);
        let category = if strategy == Strategy::Upper && counts[favorite] >= 3 && candidates.allowed & (1 << favorite) != 0 {
            favorite
        } else { candidates.best };
        self.score(category, false).unwrap();
    }

    fn ranking(&self) -> Vec<usize> {
        let mut order: Vec<_> = (0..self.players.len()).collect();
        order.sort_by_key(|&i| (-self.players[i].total(), i));
        order
    }

    fn odds(&self, mask: u8, outcomes: &[Vec<Outcome>; 6]) -> CommandResult {
        let turn = self.rolls_left()?;
        let player = &self.players[turn.seat];
        let code = held_code(&turn.faces, mask);
        let rerolled = 5 - mask.count_ones() as usize;
        let (mut sums, mut chances, mut best) = ([0; 13], [0; 13], 0);
        for outcome in &outcomes[rerolled] {
            let candidates = evaluate(player, &decode(code + outcome.code), self.rules.joker);
            for c in 0..13 {
                if let Some(points) = candidates.points[c] {
                    sums[c] += outcome.weight * i64::from(points);
                    if points > 0 { chances[c] += outcome.weight; }
                }
            }
            best += outcome.weight * i64::from(candidates.points[candidates.best].unwrap());
        }
        let denominator = POWERS[rerolled] as i64;
        println!("odds {} outcomes {}", pattern_text(mask), denominator);
        for c in 0..13 {
            if player.scores[c].is_none() {
                println!("{} expect {} chance {}", CATEGORIES[c], fraction(sums[c], denominator), fraction(chances[c], denominator));
            }
        }
        println!("best expect {}", fraction(best, denominator));
        Ok(())
    }

    fn advise(&self, outcomes: &[Vec<Outcome>; 6]) -> CommandResult {
        let turn = self.rolls_left()?;
        let depth = self.rules.rolls - turn.rolls;
        let mut adviser = Adviser {
            player: &self.players[turn.seat], joker: self.rules.joker, outcomes,
            values: vec![vec![-1; CODES]; depth + 1], expectations: vec![vec![-1; CODES]; depth + 1],
        };
        let (mut best, mut chosen) = (-1, 0);
        for mask in 0..32 {
            let value = adviser.expected(held_code(&turn.faces, mask), depth);
            if value > best { best = value; chosen = mask; }
        }
        println!("advise {}: {} expect {}", pattern_text(chosen), face_text(&turn.faces, chosen), fraction(best, 7776_i64.pow(depth as u32)));
        Ok(())
    }

    fn card_row(&self, heading: &str, cells: impl Iterator<Item = String>) {
        print!("{heading:<9}");
        for (player, cell) in self.players.iter().zip(cells) {
            print!(" {cell:>width$}", width = player.name.len().max(4));
        }
        println!();
    }

    fn report(&self, command: &str) {
        match command {
            "STATUS" => if let Some(turn) = self.turn {
                let player = &self.players[turn.seat];
                println!("status round {} player {} rolls {} dice {} holds {}", player.round(), player.name, turn.rolls,
                    face_text(&turn.faces, if turn.rolls == 0 { 0 } else { 31 }), pattern_text(turn.hold));
            } else { println!("status game over"); },
            "CARD" => {
                self.card_row("CATEGORY", self.players.iter().map(|p| p.name.clone()));
                for c in 0..13 {
                    self.card_row(CATEGORIES[c], self.players.iter().map(|p| p.scores[c].map_or_else(|| "-".into(), |n| n.to_string())));
                }
                self.card_row("UPPER", self.players.iter().map(|p| p.upper().to_string()));
                self.card_row("BONUS", self.players.iter().map(|p| p.upper_bonus().to_string()));
                self.card_row("YBONUS", self.players.iter().map(|p| p.yahtzee_bonus.to_string()));
                self.card_row("TOTAL", self.players.iter().map(|p| p.total().to_string()));
            }
            "BONUS" => for player in &self.players {
                let upper = player.upper();
                let maximum = upper + (0..6).filter(|&c| player.scores[c].is_none()).map(|c| 5 * (c + 1) as i32).sum::<i32>();
                println!("bonus {} upper {} need {} max {} {}", player.name, upper, (63 - upper).max(0), maximum,
                    if upper >= 63 { "made" } else if maximum < 63 { "lost" } else { "open" });
            },
            "STATS" => for (i, player) in self.players.iter().enumerate() {
                let entries: Vec<_> = self.entries.iter().filter(|e| e.before.seat == i).collect();
                let rolls: usize = entries.iter().map(|e| e.before.rolls).sum();
                let zeros = entries.iter().filter(|e| e.points == 0).count();
                let yahtzees = entries.iter().filter(|e| e.before.faces.iter().all(|f| *f == e.before.faces[0])).count();
                let sum = entries.iter().map(|e| i64::from(e.points)).sum();
                println!("stats {} turns {} rolls {} zeros {} yahtzees {} average {}", player.name, entries.len(), rolls, zeros, yahtzees, average(sum, entries.len()));
            },
            "LOG" => {
                for (i, entry) in self.entries.iter().enumerate() {
                    print!("log {} {} {} {} {}", i + 1, self.players[entry.before.seat].name,
                        face_text(&entry.before.faces, 31), CATEGORIES[entry.category], entry.points);
                    if entry.joker { print!(" joker"); }
                    if entry.bonus != 0 { print!(" ybonus 100"); }
                    println!();
                }
                if self.entries.is_empty() { println!("no scores"); }
            }
            "FACES" => {
                let total: i64 = self.face_counts.iter().sum();
                let squares: i64 = self.face_counts.iter().map(|n| n * n).sum();
                print!("faces");
                for count in self.face_counts { print!(" {count}"); }
                println!(" total {} chi2 {}", total, fraction(6 * squares - total * total, total.max(1)));
            }
            "STANDINGS" => {
                let order = self.ranking();
                let leader = self.players[order[0]].total();
                for (rank, i) in order.into_iter().enumerate() {
                    let player = &self.players[i];
                    println!("standing {} {} {} behind {}", rank + 1, player.name, player.total(), leader - player.total());
                }
            }
            _ => unreachable!(),
        }
    }
}

struct Adviser<'a> {
    player: &'a Player,
    joker: JokerRule,
    outcomes: &'a [Vec<Outcome>; 6],
    // At depth j every stored value is scaled by 7776^j.
    values: Vec<Vec<i64>>,
    expectations: Vec<Vec<i64>>,
}

impl Adviser<'_> {
    fn value(&mut self, code: usize, depth: usize) -> i64 {
        if self.values[depth][code] >= 0 { return self.values[depth][code]; }
        let counts = decode(code);
        let value = if depth == 0 {
            let candidates = evaluate(self.player, &counts, self.joker);
            i64::from(candidates.points[candidates.best].unwrap())
        } else { self.search_holds(&counts, 0, 0, depth) };
        self.values[depth][code] = value;
        value
    }

    fn search_holds(&mut self, counts: &[usize; 6], face: usize, code: usize, depth: usize) -> i64 {
        if face == 6 { return self.expected(code, depth); }
        let mut best = -1_i64;
        for n in 0..=counts[face] { best = best.max(self.search_holds(counts, face + 1, code + n * POWERS[face], depth)); }
        best
    }

    fn expected(&mut self, code: usize, depth: usize) -> i64 {
        if self.expectations[depth][code] >= 0 { return self.expectations[depth][code]; }
        let kept: usize = decode(code).iter().sum();
        let mut sum = 0;
        for i in 0..self.outcomes[5 - kept].len() {
            let outcome = self.outcomes[5 - kept][i];
            sum += outcome.weight * self.value(code + outcome.code, depth - 1);
        }
        let value = sum * POWERS[kept] as i64;
        self.expectations[depth][code] = value;
        value
    }
}

#[derive(Default)]
struct Record { games: usize, wins: usize, best: i32, sum: i64 }

struct Table { game: Option<Game>, rules: Rules, records: BTreeMap<String, Record> }

impl Table {
    fn game(&self) -> CommandResult<&Game> { self.game.as_ref().ok_or_else(|| "no game".into()) }
    fn game_mut(&mut self) -> CommandResult<&mut Game> { self.game.as_mut().ok_or_else(|| "no game".into()) }

    fn simulate(&self, seed: i64, count: usize, bots: &[Strategy]) {
        let (mut wins, mut sums, mut best, mut bonus, mut yahtzee) = ([0; 6], [0_i64; 6], [0_i32; 6], [0; 6], [0; 6]);
        let names = ["A", "B", "C", "D", "E", "F"];
        let mut state = seed;
        for _ in 0..count {
            let mut game = Game::new(state, &names[..bots.len()], self.rules, false);
            for (player, &strategy) in game.players.iter_mut().zip(bots) { player.strategy = strategy; }
            while game.turn.is_some() { game.bot_turn(); }
            state = game.random_state;
            wins[game.ranking()[0]] += 1;
            for (i, player) in game.players.iter().enumerate() {
                let total = player.total();
                sums[i] += i64::from(total);
                best[i] = best[i].max(total);
                bonus[i] += usize::from(player.upper_bonus() == 35);
                yahtzee[i] += usize::from(player.scores[11] == Some(50));
            }
        }
        println!("sim seed {} games {} players {}", seed, count, bots.len());
        for (i, strategy) in bots.iter().enumerate() {
            println!("seat {} {} wins {} average {} best {} bonus {} yahtzee {}", i + 1, strategy.name(), wins[i], average(sums[i], count), best[i], bonus[i], yahtzee[i]);
        }
    }

    fn execute(&mut self, words: &[&str], outcomes: &[Vec<Outcome>; 6]) -> CommandResult {
        match words[0] {
            "RULE" => {
                let mut rules = self.rules;
                match words[1] {
                    "ROLLS" => rules.rolls = positive(words[2], 4)? as usize,
                    "JOKER" => rules.joker = match words[2] {
                        "FORCED" => JokerRule::Forced, "FREE" => JokerRule::Free, "OFF" => JokerRule::Off,
                        word => return Err(format!("bad value {word}")),
                    },
                    word => return Err(format!("unknown rule {word}")),
                }
                if self.game.is_some() { return Err("game in progress".into()); }
                self.rules = rules;
                println!("rule {} {}", words[1], words[2]);
            }
            "GAME" => {
                let seed = positive(words[1], 2147483646)?;
                let names = &words[2..];
                for name in names { valid_name(name)?; }
                if names.len() > 6 { return Err("too many players".into()); }
                if self.game.is_some() { return Err("game in progress".into()); }
                for (i, name) in names.iter().enumerate() {
                    if names[..i].contains(name) { return Err(format!("duplicate name {name}")); }
                }
                self.game = Some(Game::new(seed, names, self.rules, true));
                println!("game seed {} players {}\nturn 1 {}", seed, names.join(" "), names[0]);
            }
            "BOT" => {
                valid_name(words[1])?;
                let strategy = Strategy::parse(words[2])?;
                let game = self.game_mut()?;
                let player = game.players.iter_mut().find(|p| p.name == words[1]).ok_or_else(|| format!("no player {}", words[1]))?;
                player.strategy = strategy;
                println!("bot {} {}", words[1], words[2]);
            }
            "LOAD" | "KEEP" => {
                let values = words[1..].iter().map(|word| positive(word, 6).map(|n| n as usize)).collect::<CommandResult<Vec<_>>>()?;
                let game = self.game_mut()?;
                if words[0] == "KEEP" { game.keep(&values)?; }
                else { game.loaded.extend(values); println!("loaded {}", game.loaded.len()); }
            }
            "ROLL" => self.game_mut()?.roll()?,
            "HOLD" | "ODDS" => {
                let mask = parse_pattern(words[1])?;
                if words[0] == "HOLD" { self.game_mut()?.hold(mask)?; }
                else { self.game()?.odds(mask, outcomes)?; }
            }
            "SCORE" | "WHATIF" => {
                let category = CATEGORIES.iter().position(|&c| c == words[1]).ok_or_else(|| format!("bad category {}", words[1]))?;
                self.game_mut()?.score(category, words[0] == "WHATIF")?;
            }
            "UNDO" => self.game_mut()?.undo()?,
            "REDO" => self.game_mut()?.redo()?,
            "SUGGEST" => {
                let game = self.game()?;
                let turn = game.rolled()?;
                let candidates = evaluate(&game.players[turn.seat], &face_counts(&turn.faces), game.rules.joker);
                print!("suggest");
                for (category, points) in CATEGORIES.iter().zip(candidates.points) {
                    if let Some(points) = points { print!(" {category} {points}"); }
                }
                println!(" best {} {}", CATEGORIES[candidates.best], candidates.points[candidates.best].unwrap());
            }
            "ADVISE" => self.game()?.advise(outcomes)?,
            "AUTO" => {
                let count = positive(words[1], 100)?;
                let game = self.game_mut()?;
                game.check_turn()?;
                game.redo.clear();
                for _ in 0..count { if game.turn.is_none() { break; } game.bot_turn(); }
            }
            "STATUS" | "CARD" | "BONUS" | "STATS" | "LOG" | "FACES" | "STANDINGS" => self.game()?.report(words[0]),
            "END" => {
                let game = self.game.take().ok_or_else(|| "no game".to_string())?;
                println!("end {}", if game.turn.is_none() { "final" } else { "abandoned" });
                for (rank, i) in game.ranking().into_iter().enumerate() {
                    let player = &game.players[i];
                    let total = player.total();
                    println!("rank {} {} {}", rank + 1, player.name, total);
                    if game.turn.is_none() {
                        let record = self.records.entry(player.name.clone()).or_default();
                        record.games += 1;
                        record.wins += usize::from(rank == 0);
                        record.sum += i64::from(total);
                        record.best = record.best.max(total);
                    }
                }
            }
            "RECORDS" => {
                let mut order: Vec<_> = self.records.iter().collect();
                order.sort_by(|(an, a), (bn, b)| b.wins.cmp(&a.wins).then(b.best.cmp(&a.best)).then(an.cmp(bn)));
                for (name, record) in order {
                    println!("record {} games {} wins {} best {} average {}", name, record.games, record.wins, record.best, average(record.sum, record.games));
                }
                if self.records.is_empty() { println!("no records"); }
            }
            "SIM" => {
                let seed = positive(words[1], 2147483646)?;
                let count = positive(words[2], 50)? as usize;
                let bots = words[3..].iter().map(|word| Strategy::parse(word)).collect::<CommandResult<Vec<_>>>()?;
                if bots.len() > 6 { return Err("too many players".into()); }
                self.simulate(seed, count, &bots);
            }
            word => return Err(format!("unknown command {word}")),
        }
        Ok(())
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let outcomes = make_outcomes();
    let mut table = Table { game: None, rules: Rules { rolls: 3, joker: JokerRule::Forced }, records: BTreeMap::new() };
    for line in lines.take(count) {
        let words: Vec<_> = line.split_whitespace().collect();
        if let Err(error) = table.execute(&words, &outcomes) { println!("error: {error}"); }
    }
}
