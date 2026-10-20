use std::collections::HashSet;
use std::io::{self, Read};

type Position = [[i32; 26]; 2];
type Move = (usize, usize);
#[derive(Clone)]
struct State {
    pos: Position,
    side: usize,
    cube: i32,
    owner: Option<usize>,
    pending: bool,
    over: bool,
    score: [i32; 2],
}
impl State {
    fn initial(score: [i32; 2]) -> Self {
        let mut pos = [[0; 26]; 2];
        for own in &mut pos {
            own[24] = 2;
            own[13] = 5;
            own[8] = 3;
            own[6] = 5;
        }
        Self { pos, side: 0, cube: 1, owner: None, pending: false, over: false, score }
    }
}
#[derive(Clone)]
struct Play {
    pos: Position,
    key: Vec<Move>,
    text: String,
    count: usize,
    first_die: i32,
}
struct Plays {
    all: Vec<Play>,
    legal: Vec<Play>,
    maximum: usize,
}
#[derive(Clone)]
struct Entry {
    record: String,
    before: State,
    after: State,
}
struct Outcome {
    winner: usize,
    kind: &'static str,
    points: i32,
}
struct Simulation {
    outcome: Outcome,
    turns: usize,
    first: usize,
}
struct RandomStream(i64);
impl RandomStream {
    fn next(&mut self) -> i64 {
        self.0 = self.0 * 48271 % 2147483647;
        self.0
    }
    fn die(&mut self) -> i32 { (self.next() % 6) as i32 + 1 }
}
fn color(side: usize) -> &'static str { if side == 0 { "W" } else { "B" } }
fn require(valid: bool, message: &str) -> Result<(), String> {
    if valid { Ok(()) } else { Err(message.to_owned()) }
}
fn notation(moves: &[Move], hits: u32) -> (Vec<Move>, String) {
    let mut key = moves.to_vec();
    key.sort_by(|a, b| b.cmp(a));
    loop {
        let mut pair = None;
        for (i, &(_, t)) in key.iter().enumerate() {
            if t == 0 || hits & (1u32 << t) != 0 { continue; }
            if let Some(j) = key.iter().position(|&(s, _)| s == t) {
                pair = Some((i, j));
                break;
            }
        }
        let Some((ai, bi)) = pair else { break; };
        let merged = (key[ai].0, key[bi].1);
        key.remove(ai.max(bi));
        key.remove(ai.min(bi));
        key.push(merged);
        key.sort_by(|a, b| b.cmp(a));
    }
    let mut parts = Vec::new();
    let mut marked = 0u32;
    let mut i = 0;
    while i < key.len() {
        let (s, t) = key[i];
        let mut j = i + 1;
        while j < key.len() && key[j] == key[i] { j += 1; }
        let from = if s == 25 { "bar".to_owned() } else { s.to_string() };
        let to = if t == 0 { "off".to_owned() } else { t.to_string() };
        let mut text = format!("{from}/{to}");
        if hits & (1u32 << t) != 0 && marked & (1u32 << t) == 0 {
            text.push('*');
            marked |= 1u32 << t;
        }
        if j - i > 1 { text.push_str(&format!("({})", j - i)); }
        parts.push(text);
        i = j;
    }
    let text = if parts.is_empty() { "none".to_owned() } else { parts.join(" ") };
    (key, text)
}
fn visit(pos: Position, side: usize, dice: &[i32], moves: &mut Vec<Move>, hits: u32,
         first_die: i32, all: &mut Vec<Play>) {
    let (key, text) = notation(moves, hits);
    all.push(Play { pos, key, text, count: moves.len(), first_die });
    let mut tried = [false; 7];
    for (di, &die) in dice.iter().enumerate() {
        if tried[die as usize] { continue; }
        tried[die as usize] = true;
        for s in 1..=25 {
            if pos[side][s] == 0 || (pos[side][25] > 0 && s != 25) { continue; }
            let t = (s as i32 - die).max(0) as usize;
            if t > 0 {
                if pos[1 - side][25 - t] >= 2 { continue; }
            } else {
                if pos[side][25] > 0 || (7..=24).any(|p| pos[side][p] > 0) { continue; }
                if (s as i32) < die && (s + 1..=6).any(|p| pos[side][p] > 0) { continue; }
            }
            let mut next = pos;
            next[side][s] -= 1;
            next[side][t] += 1;
            let mut next_hits = hits;
            if t > 0 && pos[1 - side][25 - t] == 1 {
                next[1 - side][25 - t] = 0;
                next[1 - side][25] += 1;
                next_hits |= 1u32 << t;
            }
            let mut rest = dice.to_vec();
            rest.remove(di);
            let first = if moves.is_empty() { die } else { first_die };
            moves.push((s, t));
            visit(next, side, &rest, moves, next_hits, first, all);
            moves.pop();
        }
    }
}
fn enumerate(pos: Position, side: usize, d1: i32, d2: i32) -> Plays {
    let dice = if d1 == d2 { vec![d1; 4] } else { vec![d1, d2] };
    let mut all = Vec::new();
    visit(pos, side, &dice, &mut Vec::new(), 0, 0, &mut all);
    let maximum = all.iter().map(|p| p.count).max().unwrap();
    let larger = maximum == 1 && d1 != d2 && all.iter().any(|p| p.count == 1 && p.first_die == d1.max(d2));
    let mut seen = HashSet::new();
    let mut legal: Vec<Play> = all.iter().filter(|p| p.count == maximum && (!larger || p.first_die == d1.max(d2)))
        .filter(|p| seen.insert(p.pos)).cloned().collect();
    legal.sort_by(|a, b| b.key.cmp(&a.key));
    Plays { all, legal, maximum }
}
fn pips(own: &[i32; 26]) -> i32 {
    (1..=25).map(|p| p as i32 * own[p]).sum()
}
fn evaluation(pos: Position, side: usize) -> [i32; 7] {
    let own = pos[side];
    let opponent = pos[1 - side];
    let p = pips(&opponent) - pips(&own);
    let (mut s, mut home, mut prime, mut anchors, mut run) = (0i32, 0i32, 0i32, 0i32, 0i32);
    for point in 1..=24 {
        if own[point] == 1 {
            let mut distances = [false; 25];
            for q in 0..point {
                if opponent[25 - q] > 0 { distances[point - q] = true; }
            }
            for a in 1..=6 {
                for b in 1..=6 {
                    if distances[a] || distances[b] || distances[a + b] || (a == b && (distances[3 * a] || distances[4 * a])) {
                        s += 1;
                    }
                }
            }
        }
        if own[point] >= 2 {
            if point <= 6 { home += 1; }
            if point >= 19 { anchors += 1; }
            run += 1;
            prime = prime.max(run);
        } else { run = 0; }
    }
    let bar = opponent[25] - own[25];
    [2 * p - s + 4 * home + 3 * prime + 3 * anchors + 6 * bar, p, s, home, prime, anchors, bar]
}
fn keith(own: &[i32; 26]) -> i32 {
    pips(own) + 2 * (own[1] - 1).max(0) + (own[2] - 1).max(0) + (own[3] - 3).max(0)
        + (4..=6).filter(|&p| own[p] == 0).count() as i32
}
fn contact(pos: Position) -> bool {
    let w = if pos[0][25] > 0 { 25 } else { (1..=24).filter(|&p| pos[0][p] > 0).max().unwrap_or(0) };
    let b = if pos[1][25] > 0 { 0 } else { 25 - (1..=24).filter(|&p| pos[1][p] > 0).max().unwrap_or(0) };
    w > b
}
fn cube_decision(state: &State, forbidden: bool) -> &'static str {
    let x = state.side;
    if state.owner == Some(1 - x) || state.cube == 64 || forbidden { return "unavailable"; }
    if contact(state.pos) {
        let value = evaluation(state.pos, x)[0];
        if value < 60 { return "no double"; }
        return if value <= 100 { "double take" } else { "double drop" };
    }
    let value = 8 * keith(&state.pos[x]) - 7 * keith(&state.pos[1 - x]);
    let limit = if state.owner.is_none() { 28 } else { 21 };
    if value > limit { return "no double"; }
    if value >= 14 { "double take" } else { "double drop" }
}
fn end_game(state: &mut State, winner: usize, kind: Option<&'static str>) -> Outcome {
    let kind = kind.unwrap_or_else(|| {
        let opponent = state.pos[1 - winner];
        if opponent[0] > 0 { "single" }
        else if opponent[25] > 0 || (19..=24).any(|p| opponent[p] > 0) { "backgammon" }
        else { "gammon" }
    });
    let multiplier = match kind { "gammon" => 2, "backgammon" => 3, _ => 1 };
    let points = state.cube * multiplier;
    state.over = true;
    state.pending = false;
    state.score[winner] += points;
    Outcome { winner, kind, points }
}
fn apply_play(state: &mut State, play: &Play) -> Option<Outcome> {
    state.pos = play.pos;
    if state.pos[state.side][0] == 15 {
        let winner = state.side;
        return Some(end_game(state, winner, None));
    }
    state.side = 1 - state.side;
    None
}
fn ranked(legal: &[Play], side: usize) -> Vec<(i32, usize)> {
    let mut values: Vec<_> = legal.iter().enumerate().map(|(i, p)| (evaluation(p.pos, side)[0], i)).collect();
    values.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    values
}
fn parse_point(word: &str, first: bool) -> Result<usize, String> {
    if first && word == "bar" { return Ok(25); }
    if !first && word == "off" { return Ok(0); }
    let word = if !first { word.strip_suffix('*').unwrap_or(word) } else { word };
    let point = word.parse::<usize>().ok();
    require(!word.is_empty() && !word.starts_with('0') && word.bytes().all(|b| b.is_ascii_digit()) && point.is_some_and(|n| (1..=24).contains(&n)), "ILLEGAL syntax")?;
    Ok(point.unwrap())
}
fn parse_play(tokens: &[&str]) -> Result<Vec<Move>, String> {
    if tokens == ["none"] { return Ok(Vec::new()); }
    let mut moves = Vec::new();
    for &token in tokens {
        let (path, repeat) = if token.ends_with(')') {
            let bytes = token.as_bytes();
            require(bytes.len() >= 3 && bytes[bytes.len() - 3] == b'(' && (b'2'..=b'4').contains(&bytes[bytes.len() - 2]), "ILLEGAL syntax")?;
            (&token[..token.len() - 3], (bytes[bytes.len() - 2] - b'0') as usize)
        } else { (token, 1) };
        let fields: Vec<_> = path.split('/').collect();
        require(fields.len() >= 2, "ILLEGAL syntax")?;
        let mut previous = parse_point(fields[0], true)?;
        for word in &fields[1..] {
            let point = parse_point(word, false)?;
            require(previous > point, "ILLEGAL syntax")?;
            for _ in 0..repeat { moves.push((previous, point)); }
            previous = point;
        }
    }
    Ok(moves)
}
fn choose_play(state: &State, tokens: &[&str], plays: &Plays) -> Result<Play, String> {
    let moves = parse_play(tokens)?;
    let side = state.side;
    let mut final_pos = state.pos;
    let mut destinations = [false; 25];
    for &(s, t) in &moves {
        final_pos[side][s] -= 1;
        final_pos[side][t] += 1;
        if t > 0 { destinations[t] = true; }
    }
    for t in 1..=24 {
        if destinations[t] && state.pos[1 - side][25 - t] == 1 {
            final_pos[1 - side][25 - t] = 0;
            final_pos[1 - side][25] += 1;
        }
    }
    require((1..=25).all(|p| final_pos[side][p] >= 0), "ILLEGAL no checker")?;
    require(final_pos[side][25] == 0 || moves.iter().all(|&(s, _)| s == 25), "ILLEGAL bar")?;
    require((1..=24).all(|t| !destinations[t] || state.pos[1 - side][25 - t] < 2), "ILLEGAL blocked")?;
    if moves.iter().any(|&(_, t)| t == 0) {
        require(final_pos[side][25] == 0 && (7..=24).all(|p| final_pos[side][p] == 0), "ILLEGAL bear-off")?;
    }
    if let Some(play) = plays.legal.iter().find(|p| p.pos == final_pos) { return Ok(play.clone()); }
    let possible: Vec<_> = plays.all.iter().filter(|p| p.pos == final_pos).collect();
    require(!possible.is_empty(), "ILLEGAL impossible")?;
    let message = if possible.iter().any(|p| p.count < plays.maximum) { "ILLEGAL too few dice" } else { "ILLEGAL larger die required" };
    Err(message.to_owned())
}
fn result_line(result: &Outcome) -> String {
    format!("result {} {} {}", color(result.winner), result.kind, result.points)
}
fn simulate(mut state: State, rng: &mut RandomStream, strategies: [&str; 2], opening: bool,
            target: i32, scores: [i32; 2], crawford: bool, verbose: bool) -> Simulation {
    let (mut d1, mut d2) = (0, 0);
    if opening {
        loop {
            d1 = rng.die(); d2 = rng.die();
            if d1 != d2 { break; }
        }
        state.side = if d1 > d2 { 0 } else { 1 };
    }
    let first = state.side;
    let mut plays = 0;
    for turn in 1.. {
        let x = state.side;
        if !opening || turn != 1 {
            let forbidden = target > 0 && (crawford || scores[x] + state.cube >= target);
            let decision = cube_decision(&state, forbidden);
            if decision.starts_with("double") {
                if verbose { println!("{turn} {} doubles {}", color(x), state.cube * 2); }
                if decision == "double drop" {
                    if verbose { println!("{turn} {} drops", color(1 - x)); }
                    return Simulation { outcome: end_game(&mut state, x, Some("drop")), turns: plays, first };
                }
                if verbose { println!("{turn} {} takes", color(1 - x)); }
                state.cube *= 2;
                state.owner = Some(1 - x);
            }
            d1 = rng.die(); d2 = rng.die();
        }
        let legal = enumerate(state.pos, x, d1, d2).legal;
        let index = match strategies[x] {
            "FIRST" => 0,
            "RANDOM" => (rng.next() % legal.len() as i64) as usize,
            _ => ranked(&legal, x)[0].1,
        };
        let play = &legal[index];
        if verbose { println!("{turn} {} {d1}-{d2} {}", color(x), play.text); }
        let outcome = apply_play(&mut state, play);
        plays += 1;
        if let Some(outcome) = outcome { return Simulation { outcome, turns: plays, first }; }
    }
    unreachable!()
}
fn numeric(word: Option<&&str>, low: i64, high: i64) -> bool {
    word.is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()) && s.parse::<i64>().is_ok_and(|n| n >= low && n <= high))
}
fn parse_position(args: &[&str]) -> Option<Position> {
    if args.len() != 4 || !numeric(args.get(1), 0, 15) || !numeric(args.get(2), 0, 15) || !["W", "B"].contains(&args[3]) { return None; }
    let points: Option<Vec<i32>> = args[0].split(',').map(|s| s.parse().ok()).collect();
    let points = points?;
    if points.len() != 24 { return None; }
    let mut pos = [[0; 26]; 2];
    for (i, &n) in points.iter().enumerate() {
        if !(-15..=15).contains(&n) { return None; }
        if n > 0 { pos[0][i + 1] = n; } else { pos[1][24 - i] = -n; }
    }
    pos[0][25] = args[1].parse().ok()?;
    pos[1][25] = args[2].parse().ok()?;
    for own in &mut pos {
        own[0] = 15 - own.iter().sum::<i32>();
        if !(0..=14).contains(&own[0]) { return None; }
    }
    Some(pos)
}
const NO_ARGUMENTS: &[&str] = &["NEW", "SHOW", "BOARD", "PIPS", "RACE", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "SCORE", "HISTORY"];
const OTHER: &[&str] = &["POS", "MOVES", "PLAY", "AUTO", "HINT", "RESIGN", "UNDO", "REDO", "GAME", "MATCH", "STATS"];
const LIMITED: &[&str] = &["RACE", "MOVES", "PLAY", "AUTO", "HINT", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "RESIGN", "GAME"];
const PENDING_LIMITED: &[&str] = &["PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME"];
fn arguments_valid(command: &str, a: &[&str]) -> bool {
    if NO_ARGUMENTS.contains(&command) { return a.is_empty(); }
    match command {
        "POS" => parse_position(a).is_some(),
        "MOVES" | "PLAY" | "AUTO" | "HINT" => {
            numeric(a.first(), 1, 6) && numeric(a.get(1), 1, 6) && match command {
                "PLAY" => a.len() >= 3,
                "HINT" => a.len() == 3 && numeric(a.get(2), 1, 1000),
                _ => a.len() == 2,
            }
        }
        "RESIGN" => a.len() == 1 && ["single", "gammon", "backgammon"].contains(&a[0]),
        "UNDO" | "REDO" => a.len() == 1 && numeric(a.first(), 1, 1000),
        "GAME" => a.len() == 3 && numeric(a.first(), 1, 2147483646) && a[1..].iter().all(|s| ["BEST", "FIRST", "RANDOM"].contains(s)),
        "MATCH" | "STATS" => a.len() == 2 && numeric(a.first(), 1, if command == "MATCH" { 15 } else { 50 }) && numeric(a.get(1), 1, 2147483646),
        _ => false,
    }
}
fn board_line(pos: Position, top: bool, row: i32) {
    let mut line = String::new();
    for i in 1..=12 {
        let p = if top { i + 12 } else { 13 - i };
        let value = if row == 0 { p.to_string() } else {
            let (w, b) = (pos[0][p], pos[1][25 - p]);
            let n = w.max(b);
            if row == 5 && n > 5 { n.to_string() }
            else if n >= row { (if w > 0 { "W" } else { "B" }).to_owned() }
            else { ".".to_owned() }
        };
        line.push_str(&format!("{value:>3}"));
        if i == 6 { line.push_str(" |"); }
    }
    println!("{line}");
}
struct Engine { state: State, history: Vec<Entry>, redo: Vec<Entry> }
impl Engine {
    fn run(&mut self, line: &str) -> Result<(), String> {
        let words: Vec<_> = line.split_whitespace().collect();
        let command = words[0];
        let a = &words[1..];
        require(NO_ARGUMENTS.contains(&command) || OTHER.contains(&command), "ERROR unknown command")?;
        require(arguments_valid(command, a), if command == "POS" { "ERROR bad position" } else { "ERROR bad arguments" })?;
        require(!self.state.over || !LIMITED.contains(&command), "ERROR game over")?;
        require(!self.state.pending || !PENDING_LIMITED.contains(&command), "ERROR double pending")?;
        let side = self.state.side;
        match command {
            "NEW" | "POS" => {
                self.state = State::initial(self.state.score);
                if command == "POS" {
                    self.state.pos = parse_position(a).unwrap();
                    self.state.side = if a[3] == "W" { 0 } else { 1 };
                }
                self.history.clear(); self.redo.clear(); println!("OK");
            }
            "SHOW" => {
                let points: Vec<_> = (1..=24).map(|p| (self.state.pos[0][p] - self.state.pos[1][25 - p]).to_string()).collect();
                println!("POS {} {} {} {}", points.join(","), self.state.pos[0][25], self.state.pos[1][25], color(side));
            }
            "BOARD" => {
                board_line(self.state.pos, true, 0);
                for row in 1..=5 { board_line(self.state.pos, true, row); }
                let owner = self.state.owner.map(color).unwrap_or("center");
                let status = if self.state.over { "game over".to_owned() } else { format!("{} {}", color(side), if self.state.pending { "doubles" } else { "to move" }) };
                println!("bar W{} B{} | off W{} B{} | cube {} {} | {}", self.state.pos[0][25], self.state.pos[1][25], self.state.pos[0][0], self.state.pos[1][0], self.state.cube, owner, status);
                for row in (1..=5).rev() { board_line(self.state.pos, false, row); }
                board_line(self.state.pos, false, 0);
            }
            "PIPS" => println!("pips W {} B {}", pips(&self.state.pos[0]), pips(&self.state.pos[1])),
            "RACE" => {
                if contact(self.state.pos) { println!("contact"); }
                else { println!("race W {} B {}", keith(&self.state.pos[0]), keith(&self.state.pos[1])); }
            }
            "EVAL" => {
                let values = evaluation(self.state.pos, side);
                let labels = ["eval", "pips", "blots", "home", "prime", "anchors", "bar"];
                println!("{}", labels.iter().zip(values).map(|(s, v)| format!("{s} {v}")).collect::<Vec<_>>().join(" "));
            }
            "MOVES" | "PLAY" | "AUTO" | "HINT" => {
                let d1 = a[0].parse().unwrap(); let d2 = a[1].parse().unwrap();
                let plays = enumerate(self.state.pos, side, d1, d2);
                if command == "MOVES" {
                    for play in &plays.legal { println!("{}", play.text); }
                    println!("total {}", plays.legal.len());
                } else if command == "HINT" {
                    let count = a[2].parse::<usize>().unwrap();
                    for (value, index) in ranked(&plays.legal, side).into_iter().take(count) { println!("{value} {}", plays.legal[index].text); }
                } else {
                    let play = if command == "AUTO" { plays.legal[ranked(&plays.legal, side)[0].1].clone() } else { choose_play(&self.state, &a[2..], &plays)? };
                    let value = evaluation(play.pos, side)[0];
                    let before = self.state.clone();
                    let result = apply_play(&mut self.state, &play);
                    let suffix = if command == "AUTO" { format!(" eval {value}") } else { String::new() };
                    println!("OK {}{suffix}", play.text);
                    if let Some(result) = result { println!("{}", result_line(&result)); }
                    self.history.push(Entry { record: format!("{} {d1}-{d2} {}", color(side), play.text), before, after: self.state.clone() });
                    self.redo.clear();
                }
            }
            "SHOTS" => {
                let blots: Vec<_> = (1..=24).rev().filter(|&p| self.state.pos[side][p] == 1).collect();
                let mut counts = [0; 25];
                let mut total = 0;
                let mut rolls = Vec::new();
                for d1 in (1..=6).rev() {
                    for d2 in (1..=d1).rev() {
                        let legal = enumerate(self.state.pos, 1 - side, d1, d2).legal;
                        let hit: Vec<_> = blots.iter().copied().filter(|&p| legal.iter().any(|play| play.pos[side][p] == 0)).collect();
                        if !hit.is_empty() {
                            let weight = if d1 == d2 { 1 } else { 2 };
                            total += weight;
                            rolls.push(format!("{d1}-{d2}"));
                            for p in hit { counts[p] += weight; }
                        }
                    }
                }
                let suffix = if rolls.is_empty() { String::new() } else { format!(" {}", rolls.join(" ")) };
                println!("shots {total}/36{suffix}");
                for p in blots { println!("blot {p} {}/36", counts[p]); }
            }
            "CUBE" => println!("cube {}", cube_decision(&self.state, false)),
            "DOUBLE" => {
                require(self.state.owner != Some(1 - side) && self.state.cube != 64, "ERROR cube unavailable")?;
                self.state.pending = true;
                self.redo.clear();
                println!("OK double {}", self.state.cube * 2);
            }
            "TAKE" | "DROP" => {
                require(self.state.pending, "ERROR no double")?;
                self.state.pending = false;
                self.redo.clear();
                if command == "TAKE" {
                    self.state.cube *= 2; self.state.owner = Some(1 - side);
                    println!("OK take {} {}", self.state.cube, color(1 - side));
                } else {
                    println!("OK drop");
                    let result = end_game(&mut self.state, side, Some("drop"));
                    println!("{}", result_line(&result));
                }
            }
            "RESIGN" => {
                let kind = match a[0] { "single" => "single", "gammon" => "gammon", _ => "backgammon" };
                self.redo.clear(); println!("OK resign");
                let result = end_game(&mut self.state, 1 - side, Some(kind));
                println!("{}", result_line(&result));
            }
            "SCORE" => println!("score W {} B {}", self.state.score[0], self.state.score[1]),
            "HISTORY" => {
                println!("history {}", self.history.len());
                for (i, entry) in self.history.iter().enumerate() { println!("{} {}", i + 1, entry.record); }
            }
            "UNDO" | "REDO" => {
                let count = a[0].parse::<usize>().unwrap();
                if command == "UNDO" {
                    require(count <= self.history.len(), "ERROR cannot undo")?;
                    let entries = self.history.split_off(self.history.len() - count);
                    self.state = entries[0].before.clone();
                    self.redo.splice(0..0, entries);
                } else {
                    require(count <= self.redo.len(), "ERROR cannot redo")?;
                    let entries: Vec<_> = self.redo.drain(..count).collect();
                    self.state = entries[count - 1].after.clone();
                    self.history.extend(entries);
                }
                println!("OK");
            }
            "GAME" => {
                let mut rng = RandomStream(a[0].parse().unwrap());
                let result = simulate(self.state.clone(), &mut rng, [a[1], a[2]], false, 0, [0, 0], false, true);
                println!("{}", result_line(&result.outcome));
            }
            "MATCH" | "STATS" => {
                let n = a[0].parse::<i32>().unwrap();
                let mut rng = RandomStream(a[1].parse().unwrap());
                let mut points = [0i32, 0i32];
                let (mut turns, mut game, mut crawford_used) = (0, 0, false);
                let kinds = ["single", "gammon", "backgammon", "drop"];
                let mut outcomes = [[0; 2]; 4];
                while if command == "STATS" { game < n } else { points[0].max(points[1]) < n } {
                    game += 1;
                    let crawford = command == "MATCH" && !crawford_used && points[0].max(points[1]) == n - 1;
                    crawford_used |= crawford;
                    let result = simulate(State::initial([0, 0]), &mut rng, ["BEST", "BEST"], true, if command == "MATCH" { n } else { 0 }, points, crawford, false);
                    points[result.outcome.winner] += result.outcome.points;
                    let kind = kinds.iter().position(|&k| k == result.outcome.kind).unwrap();
                    outcomes[kind][result.outcome.winner] += 1;
                    turns += result.turns;
                    if command == "MATCH" {
                        println!("game {game}{} start {} turns {} {} score {}-{}", if crawford { " crawford" } else { "" }, color(result.first), result.turns, result_line(&result.outcome), points[0], points[1]);
                    }
                }
                if command == "MATCH" {
                    println!("match {} {}-{}", color(if points[0] >= n { 0 } else { 1 }), points[0], points[1]);
                } else {
                    for (i, kind) in kinds.iter().enumerate() { println!("{kind} W {} B {}", outcomes[i][0], outcomes[i][1]); }
                    println!("points W {} B {}", points[0], points[1]);
                    println!("turns {turns}");
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
    let count = lines.next().unwrap().parse::<usize>().unwrap();
    let mut engine = Engine { state: State::initial([0, 0]), history: Vec::new(), redo: Vec::new() };
    for line in lines.take(count) {
        if let Err(message) = engine.run(line) { println!("{message}"); }
    }
}
