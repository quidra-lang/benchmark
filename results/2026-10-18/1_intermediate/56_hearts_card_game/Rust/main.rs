use std::io::{self, BufRead};

const SEATS: &[u8; 4] = b"NESW";
const SUITS: &[u8; 4] = b"CDSH";
const RANKS: &[u8; 13] = b"23456789TJQKA";
const STRATEGIES: [&str; 5] = ["BASIC", "LOW", "HIGH", "SMART", "MOON"];
fn seat_name(s: usize) -> char {
    SEATS[s] as char
}
fn card_text(c: usize) -> String {
    format!("{}{}", RANKS[c % 13] as char, SUITS[c / 13] as char)
}
fn penalty(c: usize) -> bool {
    c == 36 || c / 13 == 3
}
fn direction(c: u8) -> &'static str {
    match c {
        b'L' => "LEFT",
        b'R' => "RIGHT",
        b'A' => "ACROSS",
        _ => "HOLD",
    }
}
fn pairs<T: std::fmt::Display>(label: &str, values: &[T]) -> String {
    format!(
        "{label} {}",
        values
            .iter()
            .enumerate()
            .map(|(s, v)| format!("{} {v}", seat_name(s)))
            .collect::<Vec<_>>()
            .join(" ")
    )
}
#[derive(Clone, Copy, Default)]
struct Cards(u64);
impl Cards {
    fn contains(self, c: usize) -> bool {
        self.0 & (1 << c) != 0
    }
    fn add(&mut self, c: usize) {
        self.0 |= 1 << c;
    }
    fn remove(&mut self, c: usize) {
        self.0 &= !(1 << c);
    }
    fn values(self) -> Vec<usize> {
        (0..52).filter(|&c| self.contains(c)).collect()
    }
    fn filter(self, f: impl Fn(usize) -> bool) -> Self {
        let mut out = Self::default();
        for c in self.values() {
            if f(c) {
                out.add(c);
            }
        }
        out
    }
    fn len(self) -> usize {
        self.0.count_ones() as usize
    }
    fn is_empty(self) -> bool {
        self.0 == 0
    }
    fn text(self) -> String {
        if self.is_empty() {
            "-".into()
        } else {
            self.values()
                .into_iter()
                .map(card_text)
                .collect::<Vec<_>>()
                .join(" ")
        }
    }
    fn ordered(self, high: bool) -> Vec<usize> {
        let mut cards = self.values();
        cards.sort_by_key(|&c| (if high { 12 - c % 13 } else { c % 13 }, c / 13));
        cards
    }
    fn extreme(self, high: bool) -> usize {
        self.ordered(high)[0]
    }
    fn union(self, other: Self) -> Self {
        Self(self.0 | other.0)
    }
    fn difference(self, other: Self) -> Self {
        Self(self.0 & !other.0)
    }
}
fn parse_seat(s: &str) -> Result<usize, String> {
    if s.len() == 1 {
        if let Some(i) = SEATS.iter().position(|&c| c == s.as_bytes()[0]) {
            return Ok(i);
        }
    }
    Err(format!("bad seat {s}"))
}
fn parse_card(s: &str) -> Result<usize, String> {
    if s.len() == 2 {
        if let (Some(rank), Some(suit)) = (
            RANKS.iter().position(|&c| c == s.as_bytes()[0]),
            SUITS.iter().position(|&c| c == s.as_bytes()[1]),
        ) {
            return Ok(suit * 13 + rank);
        }
    }
    Err(format!("bad card {s}"))
}
fn bounded(s: &str, low: i32, high: i32) -> Result<i32, String> {
    match s.parse::<i32>() {
        Ok(n) if n >= low && n <= high => Ok(n),
        _ => Err(format!("bad value {s}")),
    }
}
fn checked_set(cards: &[usize]) -> Result<Cards, String> {
    let mut set = Cards::default();
    for &c in cards {
        if set.contains(c) {
            return Err(format!("duplicate card {}", card_text(c)));
        }
        set.add(c);
    }
    Ok(set)
}
#[derive(Clone)]
struct Rules {
    target: i32,
    limit: usize,
    moon: String,
    jack: bool,
    qsbreak: bool,
    blood: bool,
    pass: String,
}
impl Default for Rules {
    fn default() -> Self {
        Self {
            target: 100,
            limit: 100,
            moon: "ADD".into(),
            jack: false,
            qsbreak: false,
            blood: false,
            pass: "LRAH".into(),
        }
    }
}
impl Rules {
    fn validate(name: &str, value: &str) -> Result<(), String> {
        let valid = match name {
            "TARGET" => {
                bounded(value, 1, 1000)?;
                true
            }
            "LIMIT" => {
                bounded(value, 1, 100)?;
                true
            }
            "MOON" => ["ADD", "SUB", "AUTO"].contains(&value),
            "JACK" | "QSBREAK" | "BLOOD" => ["ON", "OFF"].contains(&value),
            "PASS" => (1..=8).contains(&value.len()) && value.bytes().all(|c| b"LRAH".contains(&c)),
            _ => return Err(format!("unknown rule {name}")),
        };
        if valid {
            Ok(())
        } else {
            Err(format!("bad value {value}"))
        }
    }
    fn set(&mut self, name: &str, value: &str) {
        match name {
            "TARGET" => self.target = value.parse().unwrap(),
            "LIMIT" => self.limit = value.parse().unwrap(),
            "MOON" => self.moon = value.into(),
            "PASS" => self.pass = value.into(),
            "JACK" => self.jack = value == "ON",
            "QSBREAK" => self.qsbreak = value == "ON",
            "BLOOD" => self.blood = value == "ON",
            _ => (),
        }
    }
    fn text(&self) -> String {
        format!(
            "rules TARGET {} LIMIT {} MOON {} JACK {} QSBREAK {} BLOOD {} PASS {}",
            self.target,
            self.limit,
            self.moon,
            if self.jack { "ON" } else { "OFF" },
            if self.qsbreak { "ON" } else { "OFF" },
            if self.blood { "ON" } else { "OFF" },
            self.pass
        )
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum State {
    None,
    Between,
    Passing,
    Playing,
}
#[derive(Clone, Copy)]
struct Play {
    seat: usize,
    card: usize,
}
#[derive(Clone, Default)]
struct Hand {
    hands: [Cards; 4],
    taken: [Cards; 4],
    tricks: Vec<Vec<Play>>,
    current: Vec<Play>,
    counts: [i32; 4],
    leader: usize,
    broken: bool,
}
#[derive(Clone)]
struct Snapshot {
    hand: Hand,
    log_length: usize,
    seat: usize,
    card: usize,
}
#[derive(Clone)]
struct History {
    number: usize,
    pass: u8,
    points: [i32; 4],
    shooter: Option<usize>,
    begin: usize,
    end: usize,
}
#[derive(Clone)]
struct Game {
    rules: Rules,
    bots: [usize; 4],
    random: i64,
    state: State,
    number: usize,
    scores: [i32; 4],
    stats: [[i32; 4]; 4],
    stacked: [Option<Cards>; 4],
    passes: [Option<Cards>; 4],
    pass: u8,
    hand: Hand,
    undo: Vec<Snapshot>,
    history: Vec<History>,
    log: Vec<(usize, String)>,
    hand_begin: usize,
}
impl Game {
    fn new(rules: Rules, bots: [usize; 4], seed: i64) -> Self {
        Self {
            rules,
            bots,
            random: seed,
            state: State::Between,
            number: 0,
            scores: [0; 4],
            stats: [[0; 4]; 4],
            stacked: [None; 4],
            passes: [None; 4],
            pass: b'L',
            hand: Hand::default(),
            undo: vec![],
            history: vec![],
            log: vec![],
            hand_begin: 0,
        }
    }
    fn point(&self, c: usize) -> i32 {
        if c == 36 {
            13
        } else if c / 13 == 3 {
            1
        } else if c == 22 && self.rules.jack {
            -10
        } else {
            0
        }
    }
    fn points(&self, cards: Cards) -> i32 {
        cards.values().into_iter().map(|c| self.point(c)).sum()
    }
    fn write(&mut self, level: usize, s: String) {
        self.log.push((level, s));
    }
    fn deal(&mut self) {
        self.number += 1;
        self.pass = self.rules.pass.as_bytes()[(self.number - 1) % self.rules.pass.len()];
        self.hand = Hand::default();
        let mut used = Cards::default();
        let mut free = vec![];
        for s in 0..4 {
            if let Some(cards) = self.stacked[s] {
                self.hand.hands[s] = cards;
                used = used.union(cards);
            } else {
                free.push(s);
            }
        }
        let mut deck: Vec<usize> = (0..52).filter(|&c| !used.contains(c)).collect();
        for i in (1..deck.len()).rev() {
            self.random = self.random * 48271 % 2147483647;
            let j = (self.random % (i as i64 + 1)) as usize;
            deck.swap(i, j);
        }
        for (i, c) in deck.into_iter().enumerate() {
            self.hand.hands[free[i % free.len()]].add(c);
        }
        self.stacked = [None; 4];
        self.passes = [None; 4];
        self.undo.clear();
        self.hand_begin = self.log.len();
        self.write(
            1,
            format!("hand {} pass {}", self.number, direction(self.pass)),
        );
        for s in 0..4 {
            self.write(
                2,
                format!("{}: {}", seat_name(s), self.hand.hands[s].text()),
            );
        }
        if self.pass == b'H' {
            self.begin_play();
        } else {
            self.state = State::Passing;
        }
    }
    fn begin_play(&mut self) {
        self.state = State::Playing;
        self.hand.leader = (0..4).find(|&s| self.hand.hands[s].contains(0)).unwrap();
        self.write(2, format!("lead {}", seat_name(self.hand.leader)));
    }
    fn pass_cards(&mut self, seat: usize, cards: Cards) {
        self.hand.hands[seat] = self.hand.hands[seat].difference(cards);
        self.passes[seat] = Some(cards);
        self.write(2, format!("{} passes {}", seat_name(seat), cards.text()));
        if self.passes.iter().all(Option::is_some) {
            let offset = match self.pass {
                b'L' => 1,
                b'R' => 3,
                _ => 2,
            };
            for s in 0..4 {
                let target = (s + offset) % 4;
                self.hand.hands[target] = self.hand.hands[target].union(self.passes[s].unwrap());
            }
            self.begin_play();
        }
    }
    fn actor(&self) -> usize {
        (self.hand.leader + self.hand.current.len()) % 4
    }
    fn legal(&self) -> Cards {
        let hand = self.hand.hands[self.actor()];
        if self.hand.current.is_empty() {
            if self.hand.tricks.is_empty() {
                return Cards(1);
            }
            let safe = hand.filter(|c| c / 13 != 3);
            return if !self.hand.broken && !safe.is_empty() {
                safe
            } else {
                hand
            };
        }
        let suit = self.hand.current[0].card / 13;
        let follow = hand.filter(|c| c / 13 == suit);
        if !follow.is_empty() {
            return follow;
        }
        if self.hand.tricks.is_empty() && !self.rules.blood {
            let safe = hand.filter(|c| !penalty(c));
            if !safe.is_empty() {
                return safe;
            }
        }
        hand
    }
    fn choose_pass(&self, seat: usize) -> Cards {
        let hand = self.hand.hands[seat];
        let strategy = self.bots[seat];
        let low = hand.ordered(false);
        let high = hand.ordered(true);
        let mut order = vec![];
        match strategy {
            1 => order.extend(high.iter().copied()),
            2 => order.extend(low.iter().copied()),
            4 => {
                order.extend(low.iter().copied().filter(|&c| c / 13 != 3));
                order.extend(low.iter().copied().filter(|&c| c / 13 == 3));
            }
            _ => {
                let protect =
                    strategy == 3 && hand.contains(36) && hand.filter(|c| c / 13 == 2).len() >= 5;
                if !protect {
                    order.extend((36..=38).filter(|&c| hand.contains(c)));
                }
                if strategy == 3 {
                    let suit = (0..2)
                        .filter(|&s| !hand.filter(|c| c / 13 == s).is_empty())
                        .min_by_key(|&s| (hand.filter(|c| c / 13 == s).len(), s));
                    if let Some(suit) = suit {
                        order.extend(high.iter().copied().filter(|&c| c / 13 == suit));
                    }
                }
                order.extend(high.iter().copied().filter(|&c| c / 13 == 3));
                order.extend(high.iter().copied());
            }
        }
        let mut out = Cards::default();
        for c in order {
            out.add(c);
            if out.len() == 3 {
                break;
            }
        }
        out
    }
    fn queen_played(&self) -> bool {
        self.hand.taken.iter().any(|h| h.contains(36))
            || self.hand.current.iter().any(|p| p.card == 36)
    }
    fn choose_play(&self) -> usize {
        let seat = self.actor();
        let hand = self.hand.hands[seat];
        let legal = self.legal();
        let mut strategy = self.bots[seat];
        if strategy == 1 || strategy == 2 {
            return legal.extreme(strategy == 2);
        }
        if strategy == 4
            && (0..4).any(|s| s != seat && !self.hand.taken[s].filter(penalty).is_empty())
        {
            strategy = 0;
        }
        if self.hand.current.is_empty() {
            let small_spades = legal.filter(|c| c / 13 == 2 && c % 13 < 10);
            if strategy == 3
                && !self.queen_played()
                && !hand.contains(36)
                && !small_spades.is_empty()
            {
                return small_spades.extreme(false);
            }
            let suit = (0..4)
                .filter(|&s| !legal.filter(|c| c / 13 == s).is_empty())
                .min_by_key(|&s| {
                    let count = legal.filter(|c| c / 13 == s).len() as i32;
                    (if strategy == 4 { -count } else { count }, s)
                })
                .unwrap();
            return legal.filter(|c| c / 13 == suit).extreme(strategy == 4);
        }
        let led = self.hand.current[0].card / 13;
        if !hand.filter(|c| c / 13 == led).is_empty() {
            let winning = self
                .hand
                .current
                .iter()
                .filter(|p| p.card / 13 == led)
                .map(|p| p.card % 13)
                .max()
                .unwrap();
            let lower = legal.filter(|c| c % 13 < winning);
            if strategy == 4 {
                let high = legal.extreme(true);
                return if high % 13 > winning {
                    high
                } else {
                    legal.extreme(false)
                };
            }
            if !lower.is_empty() {
                return lower.extreme(true);
            }
            if strategy == 3 && self.hand.current.len() == 3 {
                let safe = legal.filter(|c| c != 36);
                return if safe.is_empty() {
                    36
                } else {
                    safe.extreme(true)
                };
            }
            return legal.extreme(false);
        }
        if strategy == 4 {
            let safe = legal.filter(|c| !penalty(c));
            return (if safe.is_empty() { legal } else { safe }).extreme(false);
        }
        if legal.contains(36) {
            return 36;
        }
        if strategy == 3 && !self.queen_played() {
            if legal.contains(38) {
                return 38;
            }
            if legal.contains(37) {
                return 37;
            }
        }
        let hearts = legal.filter(|c| c / 13 == 3);
        (if hearts.is_empty() { legal } else { hearts }).extreme(true)
    }
    fn winner(plays: &[Play]) -> usize {
        plays
            .iter()
            .filter(|p| p.card / 13 == plays[0].card / 13)
            .max_by_key(|p| p.card % 13)
            .unwrap()
            .seat
    }
    fn trick_line(&self, plays: &[Play], number: usize) -> String {
        format!(
            "trick {number}: {} -> {} {}",
            plays
                .iter()
                .map(|p| format!("{} {}", seat_name(p.seat), card_text(p.card)))
                .collect::<Vec<_>>()
                .join(" "),
            seat_name(Self::winner(plays)),
            plays.iter().map(|p| self.point(p.card)).sum::<i32>()
        )
    }
    fn play(&mut self, card: usize) {
        let seat = self.actor();
        self.undo.push(Snapshot {
            hand: self.hand.clone(),
            log_length: self.log.len(),
            seat,
            card,
        });
        self.hand.hands[seat].remove(card);
        self.hand.current.push(Play { seat, card });
        if card / 13 == 3 || (card == 36 && self.rules.qsbreak) {
            self.hand.broken = true;
        }
        if self.hand.current.len() == 4 {
            let winner = Self::winner(&self.hand.current);
            for p in &self.hand.current {
                self.hand.taken[winner].add(p.card);
            }
            self.hand.counts[winner] += 1;
            let current = std::mem::take(&mut self.hand.current);
            self.hand.tricks.push(current.clone());
            self.write(2, self.trick_line(&current, self.hand.tricks.len()));
            self.hand.leader = winner;
            if self.hand.tricks.len() == 13 {
                self.finish_hand();
            }
        }
    }
    fn undo(&mut self) -> Play {
        let snapshot = self.undo.pop().unwrap();
        self.hand = snapshot.hand;
        self.log.truncate(snapshot.log_length);
        Play {
            seat: snapshot.seat,
            card: snapshot.card,
        }
    }
    fn claim(&mut self, seat: usize) {
        let all = self
            .hand
            .hands
            .iter()
            .fold(Cards::default(), |a, &b| a.union(b));
        let count = 13 - self.hand.tricks.len();
        self.hand.taken[seat] = self.hand.taken[seat].union(all);
        self.hand.counts[seat] += count as i32;
        self.hand.hands = [Cards::default(); 4];
        self.write(
            2,
            format!(
                "claim {} tricks {count} points {}",
                seat_name(seat),
                self.points(all)
            ),
        );
        self.finish_hand();
    }
    fn ranking(scores: &[i32; 4]) -> Vec<usize> {
        let mut seats: Vec<usize> = (0..4).collect();
        seats.sort_by_key(|&s| (scores[s], s));
        seats
    }
    fn ended(&self, scores: &[i32; 4]) -> bool {
        self.number >= self.rules.limit || scores.iter().any(|&v| v >= self.rules.target)
    }
    fn finish_hand(&mut self) {
        let mut points = [0; 4];
        for (s, p) in points.iter_mut().enumerate() {
            *p = self.points(self.hand.taken[s]);
        }
        let shooter = (0..4).find(|&s| self.hand.taken[s].filter(penalty).len() == 14);
        if let Some(s) = shooter {
            points[s] -= 26;
            let mut method = self.rules.moon.clone();
            if method == "AUTO" {
                let mut add = [0; 4];
                for i in 0..4 {
                    add[i] = self.scores[i] + points[i] + if i == s { 0 } else { 26 };
                }
                method = (if self.ended(&add) && Self::ranking(&add)[0] != s {
                    "SUB"
                } else {
                    "ADD"
                })
                .into();
            }
            if method == "SUB" {
                points[s] -= 26;
            } else {
                for (i, p) in points.iter_mut().enumerate() {
                    if i != s {
                        *p += 26;
                    }
                }
            }
            self.write(1, format!("moon {} {method}", seat_name(s)));
        }
        for s in 0..4 {
            self.scores[s] += points[s];
            self.stats[s][0] += self.hand.counts[s];
            self.stats[s][1] += self.hand.taken[s].filter(|c| c / 13 == 3).len() as i32;
            self.stats[s][2] += i32::from(self.hand.taken[s].contains(36));
            self.stats[s][3] += i32::from(shooter == Some(s));
        }
        self.write(1, pairs("points", &points));
        self.write(1, pairs("scores", &self.scores));
        self.history.push(History {
            number: self.number,
            pass: self.pass,
            points,
            shooter,
            begin: self.hand_begin,
            end: self.log.len(),
        });
        self.state = if self.ended(&self.scores) {
            State::None
        } else {
            State::Between
        };
        if self.state == State::None {
            self.write(0, format!("game over hands {}", self.number));
            for (rank, s) in Self::ranking(&self.scores).into_iter().enumerate() {
                self.write(
                    0,
                    format!("rank {} {} {}", rank + 1, seat_name(s), self.scores[s]),
                );
            }
            for line in self.stats_lines() {
                self.write(0, line);
            }
        }
    }
    fn stats_lines(&self) -> Vec<String> {
        (0..4)
            .map(|s| {
                format!(
                    "stats {} tricks {} hearts {} queens {} moons {}",
                    seat_name(s),
                    self.stats[s][0],
                    self.stats[s][1],
                    self.stats[s][2],
                    self.stats[s][3]
                )
            })
            .collect()
    }
    fn auto_pass(&mut self) {
        for s in 0..4 {
            if self.passes[s].is_none() {
                self.pass_cards(s, self.choose_pass(s));
            }
        }
    }
    fn auto_hand(&mut self) {
        if self.state == State::Passing {
            self.auto_pass();
        }
        while self.state == State::Playing {
            self.play(self.choose_play());
        }
    }
    fn auto_game(&mut self) {
        if self.state == State::Passing || self.state == State::Playing {
            self.auto_hand();
        }
        while self.state != State::None {
            self.deal();
            self.auto_hand();
        }
    }
}
#[derive(Default)]
struct Table {
    rules: Rules,
    bots: [usize; 4],
    game: Option<Game>,
}
impl Table {
    fn active(&self) -> bool {
        self.game.as_ref().is_some_and(|g| g.state != State::None)
    }
    fn simulate(&self, command: &str, seed: i32, count: usize) -> Vec<String> {
        let mut random = seed as i64;
        if command == "GAME" {
            let mut g = Game::new(self.rules.clone(), self.bots, random);
            g.auto_game();
            let mut output = vec![format!("game seed {seed}")];
            output.extend(
                g.log
                    .into_iter()
                    .filter(|(level, _)| *level <= count)
                    .map(|(_, s)| s),
            );
            return output;
        }
        let rounds = if command == "ROTATE" { 4 } else { 1 };
        let games = rounds * count;
        let mut hands = 0;
        let mut places = [[0; 4]; 4];
        let mut totals = [0; 4];
        let mut stats = [[0; 4]; 4];
        for r in 0..rounds {
            let mut bots = [0; 4];
            for s in 0..4 {
                bots[(s + r) % 4] = self.bots[s];
            }
            for _ in 0..count {
                let mut g = Game::new(self.rules.clone(), bots, random);
                g.auto_game();
                random = g.random;
                hands += g.number;
                let ranking = Game::ranking(&g.scores);
                for s in 0..4 {
                    let actual = (s + r) % 4;
                    places[s][ranking.iter().position(|&v| v == actual).unwrap()] += 1;
                    totals[s] += g.scores[actual];
                    for k in 0..4 {
                        stats[s][k] += g.stats[actual][k];
                    }
                }
            }
        }
        let mut output = vec![format!(
            "{} seed {seed} games {games} hands {hands}",
            command.to_lowercase()
        )];
        for s in 0..4 {
            let cents = (100i64 * totals[s] as i64).div_euclid(games as i64);
            let magnitude = cents.abs();
            let average = format!(
                "{}{}.{:02}",
                if cents < 0 { "-" } else { "" },
                magnitude / 100,
                magnitude % 100
            );
            let name = format!(
                "{}{}",
                seat_name(s),
                if command == "ROTATE" {
                    format!(" {}", STRATEGIES[self.bots[s]])
                } else {
                    String::new()
                }
            );
            output.push(format!("{name} places {} total {} average {average} tricks {} hearts {} queens {} moons {}", places[s].iter().map(i32::to_string).collect::<Vec<_>>().join(" "), totals[s], stats[s][0], stats[s][1], stats[s][2], stats[s][3]));
        }
        output
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<&str> = line.split(' ').collect();
        let cmd = words[0];
        let a = &words[1..];
        let known = [
            "RULE", "BOT", "SETTINGS", "GAME", "MATCH", "ROTATE", "NEW", "ABANDON", "STACK",
            "DEAL", "SHOW", "PASS", "PLAY", "AUTO", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "SCORE",
            "TAKEN", "TRICKS", "VOIDS", "UNSEEN", "STATS", "HISTORY", "REPLAY",
        ];
        if !known.contains(&cmd) {
            return Err(format!("unknown command {cmd}"));
        }
        match cmd {
            "RULE" => {
                Rules::validate(a[0], a[1])?;
                if self.active() {
                    return Err("game in progress".into());
                }
                self.rules.set(a[0], a[1]);
                return Ok(vec![format!("rule {} {}", a[0], a[1])]);
            }
            "BOT" => {
                let seat = parse_seat(a[0])?;
                let strategy = STRATEGIES
                    .iter()
                    .position(|&s| s == a[1])
                    .ok_or_else(|| format!("bad value {}", a[1]))?;
                self.bots[seat] = strategy;
                if let Some(g) = &mut self.game {
                    g.bots[seat] = strategy;
                }
                return Ok(vec![format!("bot {} {}", a[0], a[1])]);
            }
            "SETTINGS" => {
                return Ok(vec![
                    self.rules.text(),
                    pairs("bots", &self.bots.map(|i| STRATEGIES[i])),
                ]);
            }
            "GAME" | "MATCH" | "ROTATE" => {
                let seed = bounded(a[0], 1, 2147483646)?;
                let count = bounded(
                    a[1],
                    if cmd == "GAME" { 0 } else { 1 },
                    if cmd == "GAME" {
                        2
                    } else if cmd == "MATCH" {
                        50
                    } else {
                        10
                    },
                )?;
                return Ok(self.simulate(cmd, seed, count as usize));
            }
            "NEW" => {
                let seed = bounded(a[0], 1, 2147483646)?;
                if self.active() {
                    return Err("game in progress".into());
                }
                self.game = Some(Game::new(self.rules.clone(), self.bots, seed as i64));
                return Ok(vec![format!("new game seed {seed}")]);
            }
            "ABANDON" => {
                if !self.active() {
                    return Err("no game".into());
                }
                self.game = None;
                return Ok(vec!["game abandoned".into()]);
            }
            _ => (),
        }
        let seat = if ["STACK", "PASS", "PLAY", "CLAIM"].contains(&cmd) {
            parse_seat(a[0])?
        } else {
            0
        };
        let mut cards = vec![];
        if ["STACK", "PASS", "PLAY"].contains(&cmd) {
            for &s in &a[1..] {
                cards.push(parse_card(s)?);
            }
        }
        if cmd == "STACK" && cards.len() != 13 {
            return Err("need 13 cards".into());
        }
        let mode = if cmd == "AUTO" { a[0] } else { "" };
        if cmd == "AUTO" && !["PASS", "CARD", "TRICK", "HAND", "GAME"].contains(&mode) {
            return Err(format!("bad value {mode}"));
        }
        let state = self.game.as_ref().map(|g| g.state).unwrap_or(State::None);
        let error = if cmd == "STACK" || cmd == "DEAL" {
            if state == State::None {
                Some("no game")
            } else if state != State::Between {
                Some("hand in progress")
            } else {
                None
            }
        } else if cmd == "SHOW" || mode == "HAND" {
            if state != State::Passing && state != State::Playing {
                Some("no hand")
            } else {
                None
            }
        } else if cmd == "PASS" || mode == "PASS" {
            if state != State::Passing {
                Some("not passing")
            } else {
                None
            }
        } else if [
            "PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS", "UNSEEN",
        ]
        .contains(&cmd)
            || mode == "CARD"
            || mode == "TRICK"
        {
            if state != State::Playing {
                Some("not playing")
            } else {
                None
            }
        } else if state == State::None {
            Some("no game")
        } else {
            None
        };
        if let Some(error) = error {
            return Err(error.into());
        }
        let g = self.game.as_mut().unwrap();
        let before = g.log.len();
        let mut output = vec![];
        match cmd {
            "STACK" => {
                let set = checked_set(&cards)?;
                for &c in &cards {
                    for other in 0..4 {
                        if other != seat && g.stacked[other].is_some_and(|h| h.contains(c)) {
                            return Err(format!(
                                "{} stacked for {}",
                                card_text(c),
                                seat_name(other)
                            ));
                        }
                    }
                }
                g.stacked[seat] = Some(set);
                return Ok(vec![format!("stacked {}", seat_name(seat))]);
            }
            "DEAL" => g.deal(),
            "SHOW" => {
                return Ok((0..4)
                    .map(|s| format!("{}: {}", seat_name(s), g.hand.hands[s].text()))
                    .collect());
            }
            "PASS" => {
                if g.passes[seat].is_some() {
                    return Err(format!("{} already passed", seat_name(seat)));
                }
                let set = checked_set(&cards)?;
                for &c in &cards {
                    if !g.hand.hands[seat].contains(c) {
                        return Err(format!(
                            "{} does not hold {}",
                            seat_name(seat),
                            card_text(c)
                        ));
                    }
                }
                g.pass_cards(seat, set);
            }
            "PLAY" => {
                let card = cards[0];
                if seat != g.actor() {
                    return Err(format!("waiting for {}", seat_name(g.actor())));
                }
                if !g.hand.hands[seat].contains(card) {
                    return Err(format!(
                        "{} does not hold {}",
                        seat_name(seat),
                        card_text(card)
                    ));
                }
                if !g.legal().contains(card) {
                    if g.hand.current.is_empty() {
                        return Err(if g.hand.tricks.is_empty() {
                            "must lead 2C"
                        } else {
                            "hearts not broken"
                        }
                        .into());
                    }
                    let led = g.hand.current[0].card / 13;
                    if !g.hand.hands[seat].filter(|c| c / 13 == led).is_empty() {
                        return Err(format!("must follow {}", SUITS[led] as char));
                    }
                    return Err("no points on first trick".into());
                }
                output.push(format!("{} plays {}", seat_name(seat), card_text(card)));
                g.play(card);
            }
            "AUTO" => match mode {
                "PASS" => g.auto_pass(),
                "CARD" => {
                    let seat = g.actor();
                    let card = g.choose_play();
                    output.push(format!("{} plays {}", seat_name(seat), card_text(card)));
                    g.play(card);
                }
                "TRICK" => {
                    let count = g.hand.tricks.len();
                    while g.state == State::Playing && g.hand.tricks.len() == count {
                        g.play(g.choose_play());
                    }
                }
                "HAND" => g.auto_hand(),
                _ => g.auto_game(),
            },
            "UNDO" => {
                if g.undo.is_empty() {
                    return Err("nothing to undo".into());
                }
                let p = g.undo();
                return Ok(vec![format!(
                    "undo {} {}",
                    seat_name(p.seat),
                    card_text(p.card)
                )]);
            }
            "CLAIM" => {
                if seat != g.actor() {
                    return Err(format!("waiting for {}", seat_name(g.actor())));
                }
                if !g.hand.current.is_empty() {
                    return Err("trick in progress".into());
                }
                if g.hand.hands[seat].values().into_iter().any(|c| {
                    (0..4).any(|s| {
                        s != seat
                            && !g.hand.hands[s]
                                .filter(|d| d / 13 == c / 13 && d % 13 > c % 13)
                                .is_empty()
                    })
                }) {
                    return Err("claim rejected".into());
                }
                g.claim(seat);
            }
            "LEGAL" => {
                return Ok(vec![format!(
                    "legal {}: {} bot {}",
                    seat_name(g.actor()),
                    g.legal().text(),
                    card_text(g.choose_play())
                )]);
            }
            "PREVIEW" => {
                for c in g.legal().values() {
                    let mut copy = g.clone();
                    let count = copy.hand.tricks.len();
                    copy.play(c);
                    while copy.state == State::Playing && copy.hand.tricks.len() == count {
                        copy.play(copy.choose_play());
                    }
                    let trick = copy.hand.tricks.last().unwrap();
                    output.push(format!(
                        "preview {} -> {} {}",
                        card_text(c),
                        seat_name(Game::winner(trick)),
                        trick.iter().map(|p| copy.point(p.card)).sum::<i32>()
                    ));
                }
                return Ok(output);
            }
            "SCORE" => {
                output.push(pairs("scores", &g.scores));
                if g.state == State::Playing {
                    output.push(pairs("taken", &g.hand.taken.map(|h| g.points(h))));
                }
                return Ok(output);
            }
            "TAKEN" => {
                return Ok((0..4)
                    .map(|s| {
                        format!(
                            "{}: {}",
                            seat_name(s),
                            g.hand.taken[s].filter(|c| g.point(c) != 0).text()
                        )
                    })
                    .collect());
            }
            "TRICKS" => {
                for (i, t) in g.hand.tricks.iter().enumerate() {
                    output.push(g.trick_line(t, i + 1));
                }
                if !g.hand.current.is_empty() {
                    output.push(format!(
                        "current: {}",
                        g.hand
                            .current
                            .iter()
                            .map(|p| format!("{} {}", seat_name(p.seat), card_text(p.card)))
                            .collect::<Vec<_>>()
                            .join(" ")
                    ));
                }
                if output.is_empty() {
                    output.push("no tricks".into());
                }
                return Ok(output);
            }
            "VOIDS" => {
                let mut missing = [[false; 4]; 4];
                for t in g.hand.tricks.iter().chain(std::iter::once(&g.hand.current)) {
                    if t.is_empty() {
                        continue;
                    }
                    let led = t[0].card / 13;
                    for p in t {
                        if p.card / 13 != led {
                            missing[p.seat][led] = true;
                        }
                    }
                }
                let suits: Vec<String> = missing
                    .iter()
                    .map(|m| {
                        let s: String =
                            (0..4).filter(|&s| m[s]).map(|s| SUITS[s] as char).collect();
                        if s.is_empty() { "-".into() } else { s }
                    })
                    .collect();
                return Ok(vec![pairs("voids", &suits)]);
            }
            "UNSEEN" => {
                let mut seen = g.hand.hands[g.actor()];
                for h in g.hand.taken {
                    seen = seen.union(h);
                }
                for p in &g.hand.current {
                    seen.add(p.card);
                }
                return Ok(vec![format!(
                    "unseen {}: {}",
                    seat_name(g.actor()),
                    Cards((1u64 << 52) - 1).difference(seen).text()
                )]);
            }
            "STATS" => return Ok(g.stats_lines()),
            "HISTORY" => {
                if g.history.is_empty() {
                    return Ok(vec!["no hands".into()]);
                }
                return Ok(g
                    .history
                    .iter()
                    .map(|h| {
                        format!(
                            "hand {} pass {} {}{}",
                            h.number,
                            direction(h.pass),
                            pairs("points", &h.points),
                            h.shooter
                                .map(|s| format!(" moon {}", seat_name(s)))
                                .unwrap_or_default()
                        )
                    })
                    .collect());
            }
            "REPLAY" => {
                let number = bounded(a[0], 1, g.history.len() as i32)? as usize;
                let h = &g.history[number - 1];
                return Ok(g.log[h.begin..h.end]
                    .iter()
                    .map(|(_, s)| s.clone())
                    .collect());
            }
            _ => unreachable!(),
        }
        output.extend(g.log[before..].iter().map(|(_, s)| s.clone()));
        Ok(output)
    }
}
fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let mut table = Table::default();
    for line in lines.take(count) {
        match table.command(&line.unwrap()) {
            Ok(output) => {
                for s in output {
                    println!("{s}");
                }
            }
            Err(reason) => println!("error: {reason}"),
        }
    }
}
