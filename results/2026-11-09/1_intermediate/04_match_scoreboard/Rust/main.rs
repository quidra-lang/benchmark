use std::collections::{BTreeMap, HashSet};
use std::io::{self, BufRead, Write};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Sport {
    Tennis,
    TableTennis,
    Badminton,
    Volleyball,
    Bowling,
    Darts,
}
#[derive(Clone, Copy, Default)]
struct Segment {
    a: i32,
    b: i32,
    kind: usize,
    loser: i32,
}
#[derive(Clone, Copy, Default)]
struct Rally {
    points: [i32; 2],
    games: [i32; 2],
    sets: [i32; 2],
    substitutions: [i32; 2],
    timeouts: [i32; 2],
    stats: [[i32; 10]; 2],
    lineup: [[i32; 6]; 2],
    segments: [Segment; 7],
    segment_count: usize,
    server: usize,
    winner: Option<usize>,
}
#[derive(Clone, Copy, Default)]
struct BowlingState {
    rolls: [i32; 21],
    count: usize,
}
#[derive(Clone, Copy, Default)]
struct DartsState {
    remaining: [i32; 2],
    legs: [i32; 2],
    sets: [i32; 2],
    stats: [[i32; 8]; 2],
    segments: [[i32; 2]; 9],
    turn: [usize; 3],
    segment_count: usize,
    server: usize,
    turn_start: i32,
    turn_count: usize,
    turn_score: i32,
    leg_number: usize,
    winner: Option<usize>,
}
#[derive(Clone, Copy)]
enum State {
    Rally(Rally),
    Bowling(BowlingState),
    Darts(DartsState),
}
#[derive(Clone, Copy)]
struct Config {
    sport: Sport,
    first: usize,
    sets: i32,
    games: i32,
    final_rule: usize,
    start: i32,
    legs: i32,
    no_ad: bool,
    initial_lineup: [[i32; 6]; 2],
}
struct Match {
    id: String,
    names: [String; 2],
    config: Config,
    state: State,
    history: Vec<State>,
}
#[derive(Default)]
struct BowlingInfo {
    start: [usize; 10],
    count: [usize; 10],
    score: [i32; 10],
    closed: [bool; 10],
    final_score: [bool; 10],
    marks: [u8; 21],
    standing: i32,
    frame: usize,
    fresh: bool,
    finished: bool,
}
struct Dart {
    name: String,
    value: i32,
    double: bool,
}

fn number(s: &str) -> i32 {
    s.parse().unwrap()
}
fn pair_text(p: [i32; 2], first: usize) -> String {
    format!("{}-{}", p[first], p[1 - first])
}
fn initialize_darts() -> Vec<Dart> {
    let mut darts = Vec::new();
    for multiplier in [1, 3, 2] {
        let prefix = if multiplier == 1 {
            'S'
        } else if multiplier == 2 {
            'D'
        } else {
            'T'
        };
        for n in (1..=20).rev() {
            darts.push(Dart {
                name: format!("{prefix}{n}"),
                value: multiplier * n,
                double: multiplier == 2,
            });
        }
    }
    darts.push(Dart {
        name: "25".to_owned(),
        value: 25,
        double: false,
    });
    darts.push(Dart {
        name: "BULL".to_owned(),
        value: 50,
        double: true,
    });
    darts.push(Dart {
        name: "MISS".to_owned(),
        value: 0,
        double: false,
    });
    darts
}
fn double_dart(value: i32) -> Option<usize> {
    if value == 50 {
        Some(61)
    } else if (2..=40).contains(&value) && value % 2 == 0 {
        Some((60 - value / 2) as usize)
    } else {
        None
    }
}
fn checkout(darts: &[Dart], score: i32, maximum: usize) -> Vec<usize> {
    if let Some(last) = double_dart(score) {
        return vec![last];
    }
    if maximum >= 2 {
        for i in 0..62 {
            if let Some(last) = double_dart(score - darts[i].value) {
                return vec![i, last];
            }
        }
    }
    if maximum >= 3 && score <= 170 {
        for i in 0..62 {
            for j in 0..62 {
                if let Some(last) = double_dart(score - darts[i].value - darts[j].value) {
                    return vec![i, j, last];
                }
            }
        }
    }
    Vec::new()
}
fn dart_names(darts: &[Dart], ids: &[usize]) -> String {
    ids.iter()
        .map(|&i| darts[i].name.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}
fn bowling_info(state: &BowlingState) -> BowlingInfo {
    let mut info = BowlingInfo {
        standing: 10,
        fresh: true,
        ..BowlingInfo::default()
    };
    for i in 0..state.count {
        let frame = info.frame;
        let pins = state.rolls[i];
        if info.count[frame] == 0 {
            info.start[frame] = i;
        }
        info.marks[i] = if info.fresh && pins == 10 {
            b'X'
        } else if pins == info.standing {
            b'/'
        } else if pins == 0 {
            b'-'
        } else {
            b'0' + pins as u8
        };
        info.count[frame] += 1;
        info.standing -= pins;
        info.fresh = false;
        let ended = if frame < 9 {
            pins == 10 && info.count[frame] == 1 || info.count[frame] == 2
        } else if info.count[frame] == 2 {
            state.rolls[info.start[frame]] + pins < 10
        } else {
            info.count[frame] == 3
        };
        if ended {
            info.closed[frame] = true;
            if frame == 9 {
                info.finished = true;
            } else {
                info.frame += 1;
            }
            info.standing = 10;
            info.fresh = true;
        } else if frame == 9 && info.standing == 0 {
            info.standing = 10;
            info.fresh = true;
        }
    }
    for frame in 0..10 {
        if info.count[frame] == 0 {
            continue;
        }
        let start = info.start[frame];
        if frame == 9 {
            info.final_score[frame] = info.closed[frame];
            info.score[frame] = state.rolls[start..start + info.count[frame]].iter().sum();
        } else if state.rolls[start] == 10 {
            info.final_score[frame] = state.count >= start + 3;
            if info.final_score[frame] {
                info.score[frame] = 10 + state.rolls[start + 1] + state.rolls[start + 2];
            }
        } else if info.count[frame] >= 2 {
            let total = state.rolls[start] + state.rolls[start + 1];
            info.final_score[frame] = total < 10 || state.count >= start + 3;
            if info.final_score[frame] {
                info.score[frame] = total
                    + if total == 10 {
                        state.rolls[start + 2]
                    } else {
                        0
                    };
            }
        }
    }
    info
}
fn final_set(c: &Config, s: &Rally) -> bool {
    s.sets[0] == c.sets / 2 && s.sets[1] == c.sets / 2
}
fn tennis_kind(c: &Config, s: &Rally) -> usize {
    if final_set(c, s) && c.final_rule == 3 {
        2
    } else if s.games == [6, 6] && !(final_set(c, s) && c.final_rule == 2) {
        1
    } else {
        0
    }
}
fn rally_server(c: &Config, s: &Rally) -> usize {
    if c.sport == Sport::Tennis && tennis_kind(c, s) > 0 {
        s.server ^ (((s.points[0] + s.points[1] + 1) / 2 % 2) as usize)
    } else if c.sport == Sport::TableTennis {
        let first = c.first ^ (s.segment_count % 2);
        let played = s.points[0] + s.points[1];
        first
            ^ ((if played < 20 {
                played / 2 % 2
            } else {
                played % 2
            }) as usize)
    } else {
        s.server
    }
}
fn normal_game(c: &Config, own: i32, other: i32) -> bool {
    own >= 4 && (c.no_ad || own - other >= 2)
}
fn add_rally(c: &Config, s: &mut Rally, side: usize) {
    let other = 1 - side;
    let server = rally_server(c, s);
    s.stats[side][0] += 1;
    s.stats[server][1] += 1;
    if side == server {
        s.stats[side][2] += 1;
    }
    s.stats[side][3] += 1;
    s.stats[other][3] = 0;
    s.stats[side][4] = s.stats[side][4].max(s.stats[side][3]);
    let kind = if c.sport == Sport::Tennis {
        tennis_kind(c, s)
    } else {
        0
    };
    if c.sport == Sport::Tennis && kind == 0 {
        let receiver = 1 - s.server;
        if normal_game(c, s.points[receiver] + 1, s.points[s.server]) {
            s.stats[receiver][8] += 1;
            if side == receiver {
                s.stats[receiver][9] += 1;
            }
        }
    }
    s.points[side] += 1;
    if c.sport == Sport::Tennis {
        let target = if kind == 2 || kind == 1 && final_set(c, s) && c.final_rule == 1 {
            10
        } else {
            7
        };
        let ended = if kind > 0 {
            s.points[side] >= target && s.points[side] - s.points[other] >= 2
        } else {
            normal_game(c, s.points[side], s.points[other])
        };
        if !ended {
            return;
        }
        if kind == 0 {
            s.stats[s.server][5] += 1;
            if side == s.server {
                s.stats[side][6] += 1;
            } else {
                s.stats[side][7] += 1;
            }
        }
        let segment = if kind == 2 {
            Segment {
                a: s.points[0],
                b: s.points[1],
                kind: 2,
                loser: 0,
            }
        } else {
            s.games[side] += 1;
            Segment {
                a: s.games[0],
                b: s.games[1],
                kind,
                loser: if kind > 0 { s.points[other] } else { 0 },
            }
        };
        s.server ^= 1;
        s.points = [0; 2];
        if kind > 0 || s.games[side] >= 6 && s.games[side] - s.games[other] >= 2 {
            s.segments[s.segment_count] = segment;
            s.segment_count += 1;
            s.sets[side] += 1;
            s.games = [0; 2];
            if s.sets[side] == c.sets / 2 + 1 {
                s.winner = Some(side);
            }
        }
        return;
    }
    if c.sport == Sport::Volleyball && side != s.server {
        s.server = side;
        s.lineup[side].rotate_left(1);
    }
    if c.sport == Sport::Badminton {
        s.server = side;
    }
    let target = match c.sport {
        Sport::TableTennis => 11,
        Sport::Badminton => 21,
        _ => {
            if s.segment_count == 4 {
                15
            } else {
                25
            }
        }
    };
    let ended = s.points[side] >= target && s.points[side] - s.points[other] >= 2
        || c.sport == Sport::Badminton && s.points[side] == 30;
    if !ended {
        return;
    }
    s.segments[s.segment_count] = Segment {
        a: s.points[0],
        b: s.points[1],
        kind: 0,
        loser: 0,
    };
    s.segment_count += 1;
    s.sets[side] += 1;
    let needed = match c.sport {
        Sport::TableTennis => c.games / 2 + 1,
        Sport::Badminton => 2,
        _ => 3,
    };
    if s.sets[side] == needed {
        s.winner = Some(side);
    } else {
        s.points = [0; 2];
        if c.sport == Sport::Volleyball {
            s.lineup = c.initial_lineup;
            s.substitutions = [0; 2];
            s.timeouts = [0; 2];
            s.server = c.first ^ (s.segment_count % 2);
        }
    }
}
fn end_darts_turn(s: &mut DartsState) {
    s.server ^= 1;
    s.turn_start = s.remaining[s.server];
    s.turn_count = 0;
    s.turn_score = 0;
}
fn completed_darts_turn(s: &mut DartsState, side: usize) {
    s.stats[side][3] = s.stats[side][3].max(s.turn_score);
    if s.turn_score >= 100 {
        s.stats[side][4] += 1;
    }
    if s.turn_score == 180 {
        s.stats[side][5] += 1;
    }
}
fn add_dart(c: &Config, darts: &[Dart], s: &mut DartsState, id: usize) {
    let side = s.server;
    let remaining = s.remaining[side];
    let dart = &darts[id];
    s.stats[side][0] += 1;
    if remaining == 50 || remaining <= 40 && remaining % 2 == 0 {
        s.stats[side][6] += 1;
    }
    s.turn[s.turn_count] = id;
    s.turn_count += 1;
    s.turn_score += dart.value;
    s.stats[side][1] += dart.value;
    let after = remaining - dart.value;
    if after < 0 || after == 1 || after == 0 && !dart.double {
        s.stats[side][1] -= s.turn_score;
        s.stats[side][2] += 1;
        s.remaining[side] = s.turn_start;
        end_darts_turn(s);
        return;
    }
    s.remaining[side] = after;
    if after == 0 {
        s.stats[side][7] += 1;
        completed_darts_turn(s, side);
        s.legs[side] += 1;
        if s.legs[side] == c.legs {
            s.segments[s.segment_count] = s.legs;
            s.segment_count += 1;
            s.sets[side] += 1;
            if s.sets[side] == c.sets {
                s.winner = Some(side);
                return;
            }
            s.legs = [0; 2];
        }
        s.leg_number += 1;
        s.remaining = [c.start; 2];
        s.server = c.first ^ ((s.leg_number - 1) % 2);
        s.turn_start = c.start;
        s.turn_count = 0;
        s.turn_score = 0;
    } else if s.turn_count == 3 {
        completed_darts_turn(s, side);
        end_darts_turn(s);
    }
}
fn segment_text(s: Segment, first: usize) -> String {
    let mut result = pair_text([s.a, s.b], first);
    if s.kind == 1 {
        result.push_str(&format!("({})", s.loser));
    }
    if s.kind == 2 {
        result = format!("[{result}]");
    }
    result
}
fn situation(c: &Config, s: &Rally, side: usize) -> &'static str {
    let mut next = *s;
    add_rally(c, &mut next, side);
    if next.winner.is_some() {
        "match point"
    } else if next.segment_count != s.segment_count {
        if [Sport::TableTennis, Sport::Badminton].contains(&c.sport) {
            "game point"
        } else {
            "set point"
        }
    } else if c.sport == Sport::Tennis && tennis_kind(c, s) == 0 && next.server != s.server {
        if rally_server(c, s) == side {
            "game point"
        } else {
            "break point"
        }
    } else {
        ""
    }
}
impl Match {
    fn finished(&self) -> bool {
        match self.state {
            State::Bowling(s) => bowling_info(&s).finished,
            State::Darts(s) => s.winner.is_some(),
            State::Rally(s) => s.winner.is_some(),
        }
    }
    fn winner(&self) -> usize {
        match self.state {
            State::Darts(s) => s.winner.unwrap(),
            State::Rally(s) => s.winner.unwrap(),
            _ => unreachable!(),
        }
    }
    fn score(&self, darts: &[Dart]) -> String {
        if let State::Bowling(s) = self.state {
            let info = bowling_info(&s);
            let mut line = format!("{}: {}", self.id, self.names[0]);
            let mut cumulative = 0;
            for frame in 0..10 {
                if info.count[frame] == 0 {
                    continue;
                }
                let start = info.start[frame];
                let marks =
                    std::str::from_utf8(&info.marks[start..start + info.count[frame]]).unwrap();
                line.push_str(&format!(" {marks}"));
                cumulative += info.score[frame];
                if info.final_score[frame] {
                    line.push_str(&format!("({cumulative})"));
                }
            }
            return line;
        }
        let over = self.finished();
        let server = match self.state {
            State::Darts(s) => s.server,
            State::Rally(s) => rally_server(&self.config, &s),
            _ => unreachable!(),
        };
        let mut line = format!(
            "{}: {}{} vs {}{}",
            self.id,
            self.names[0],
            if !over && server == 0 { "*" } else { "" },
            self.names[1],
            if !over && server == 1 { "*" } else { "" }
        );
        match self.state {
            State::Darts(s) => {
                line.push_str(&format!(
                    " sets {} legs {} score {}",
                    pair_text(s.sets, 0),
                    pair_text(s.legs, 0),
                    pair_text(s.remaining, 0)
                ));
                if !over {
                    if s.turn_count > 0 {
                        line.push_str(&format!(
                            " turn {}",
                            dart_names(darts, &s.turn[..s.turn_count])
                        ));
                    }
                    let finish = checkout(darts, s.remaining[s.server], 3 - s.turn_count);
                    if !finish.is_empty() {
                        line.push_str(&format!(" checkout {}", dart_names(darts, &finish)));
                    }
                }
            }
            State::Rally(s) => {
                for segment in &s.segments[..s.segment_count] {
                    line.push_str(&format!(" {}", segment_text(*segment, 0)));
                }
                if !over {
                    if self.config.sport == Sport::Tennis {
                        let kind = tennis_kind(&self.config, &s);
                        if kind == 2 {
                            line.push_str(&format!(" [{}]", pair_text(s.points, 0)));
                        } else {
                            line.push_str(&format!(" {} ", pair_text(s.games, 0)));
                            if kind > 0 {
                                line.push_str(&pair_text(s.points, 0));
                            } else if !self.config.no_ad && s.points[0] >= 3 && s.points[1] >= 3 {
                                line.push_str(if s.points[0] == s.points[1] {
                                    "40-40"
                                } else if s.points[0] > s.points[1] {
                                    "AD-40"
                                } else {
                                    "40-AD"
                                });
                            } else {
                                let labels = ["0", "15", "30", "40"];
                                line.push_str(&format!(
                                    "{}-{}",
                                    labels[s.points[0] as usize], labels[s.points[1] as usize]
                                ));
                            }
                        }
                    } else {
                        line.push_str(&format!(" {}", pair_text(s.points, 0)));
                        if self.config.sport == Sport::Volleyball {
                            line.push_str(&format!(" server {}", s.lineup[s.server][0]));
                        }
                    }
                    for side in 0..2 {
                        let label = situation(&self.config, &s, side);
                        if !label.is_empty() {
                            line.push_str(&format!(" ({label} {})", self.names[side]));
                        }
                    }
                }
            }
            _ => unreachable!(),
        }
        line
    }
    fn statistics(&self) -> Vec<String> {
        if let State::Bowling(mut s) = self.state {
            let mut info = bowling_info(&s);
            let strikes = info.marks[..s.count].iter().filter(|&&c| c == b'X').count();
            let spares = info.marks[..s.count].iter().filter(|&&c| c == b'/').count();
            let mut open = 0;
            for i in 0..10 {
                let start = info.start[i];
                if info.count[i] >= 2
                    && s.rolls[start] != 10
                    && s.rolls[start] + s.rolls[start + 1] < 10
                {
                    open += 1;
                }
            }
            while !info.finished {
                s.rolls[s.count] = info.standing;
                s.count += 1;
                info = bowling_info(&s);
            }
            return vec![format!(
                "{} {}: strikes {strikes} spares {spares} open {open} max {}",
                self.id,
                self.names[0],
                info.score.iter().sum::<i32>()
            )];
        }
        let mut result = Vec::new();
        for side in 0..2 {
            let mut line = format!("{} {}: ", self.id, self.names[side]);
            match self.state {
                State::Darts(state) => {
                    let s = state.stats[side];
                    let average = if s[0] > 0 { s[1] * 300 / s[0] } else { 0 };
                    line.push_str(&format!(
                        "darts {} average {}.{:02} busts {} high {} tons {} 180s {} doubles {}/{}",
                        s[0],
                        average / 100,
                        average % 100,
                        s[2],
                        s[3],
                        s[4],
                        s[5],
                        s[7],
                        s[6]
                    ));
                }
                State::Rally(r) => {
                    let s = r.stats[side];
                    line.push_str(&format!(
                        "points {} serve {}/{} run {}",
                        s[0], s[2], s[1], s[4]
                    ));
                    if self.config.sport == Sport::Tennis {
                        line.push_str(&format!(
                            " holds {}/{} breaks {} break points {}/{}",
                            s[6], s[5], s[7], s[9], s[8]
                        ));
                    }
                    if self.config.sport == Sport::Volleyball {
                        let lineup = r.lineup[side]
                            .iter()
                            .map(i32::to_string)
                            .collect::<Vec<_>>()
                            .join(",");
                        line.push_str(&format!(
                            " subs {} timeouts {} lineup {lineup}",
                            r.substitutions[side], r.timeouts[side]
                        ));
                    }
                }
                _ => unreachable!(),
            }
            result.push(line);
        }
        result
    }
    fn result(&self) -> Result<String, String> {
        if !self.finished() {
            return Err("match not finished".to_owned());
        }
        if let State::Bowling(s) = self.state {
            return Ok(format!(
                "{}: {} {}",
                self.id,
                self.names[0],
                bowling_info(&s).score.iter().sum::<i32>()
            ));
        }
        let first = self.winner();
        let mut line = format!(
            "{}: {} def. {}",
            self.id,
            self.names[first],
            self.names[1 - first]
        );
        match self.state {
            State::Darts(s) => {
                for &segment in &s.segments[..s.segment_count] {
                    line.push_str(&format!(" {}", pair_text(segment, first)));
                }
            }
            State::Rally(s) => {
                for &segment in &s.segments[..s.segment_count] {
                    line.push_str(&format!(" {}", segment_text(segment, first)));
                }
            }
            _ => unreachable!(),
        }
        Ok(line)
    }
}
fn create_match(a: &[&str]) -> Result<Match, String> {
    let sport = match a[2] {
        "TENNIS" => Sport::Tennis,
        "TABLETENNIS" => Sport::TableTennis,
        "BADMINTON" => Sport::Badminton,
        "VOLLEYBALL" => Sport::Volleyball,
        "BOWLING" => Sport::Bowling,
        _ => Sport::Darts,
    };
    let mut c = Config {
        sport,
        first: 0,
        sets: if sport == Sport::Darts { 1 } else { 3 },
        games: 5,
        final_rule: 0,
        start: 501,
        legs: 1,
        no_ad: false,
        initial_lineup: [[0; 6]; 2],
    };
    let option_start = match sport {
        Sport::Bowling => 4,
        Sport::Volleyball => 7,
        _ => 5,
    };
    let mut seen = HashSet::new();
    for option in &a[option_start..] {
        let (key, value) = option.split_once('=').ok_or("invalid option")?;
        let allowed: &[&str] = match (sport, key) {
            (Sport::Tennis, "SETS") => &["3", "5"],
            (Sport::Tennis, "DEUCE") => &["AD", "NOAD"],
            (Sport::Tennis, "FINAL") => &["TB7", "TB10", "ADV", "SUPER"],
            (Sport::TableTennis, "GAMES") => &["5", "7"],
            (Sport::Darts, "START") => &["301", "501", "701"],
            (Sport::Darts, "SETS" | "LEGS") => &["1", "2", "3", "4", "5"],
            (_, "FIRST") if sport != Sport::Bowling => &["A", "B"],
            _ => return Err("invalid option".to_owned()),
        };
        let choice = allowed
            .iter()
            .position(|&s| s == value)
            .ok_or("invalid option")?;
        if !seen.insert(key) {
            return Err("invalid option".to_owned());
        }
        match key {
            "FIRST" => c.first = choice,
            "SETS" => c.sets = number(value),
            "GAMES" => c.games = number(value),
            "START" => c.start = number(value),
            "LEGS" => c.legs = number(value),
            "DEUCE" => c.no_ad = value == "NOAD",
            "FINAL" => c.final_rule = choice,
            _ => unreachable!(),
        }
    }
    let state = match sport {
        Sport::Bowling => State::Bowling(BowlingState::default()),
        Sport::Darts => State::Darts(DartsState {
            remaining: [c.start; 2],
            server: c.first,
            turn_start: c.start,
            leg_number: 1,
            ..DartsState::default()
        }),
        _ => {
            if sport == Sport::Volleyball {
                for side in 0..2 {
                    for (i, s) in a[5 + side].split(',').enumerate() {
                        c.initial_lineup[side][i] = number(s);
                    }
                }
            }
            State::Rally(Rally {
                server: c.first,
                lineup: c.initial_lineup,
                ..Rally::default()
            })
        }
    };
    Ok(Match {
        id: a[1].to_owned(),
        names: [
            a[3].to_owned(),
            if sport == Sport::Bowling {
                String::new()
            } else {
                a[4].to_owned()
            },
        ],
        config: c,
        state,
        history: Vec::new(),
    })
}
fn execute(
    matches: &mut BTreeMap<String, Match>,
    darts: &[Dart],
    a: &[&str],
) -> Result<Vec<String>, String> {
    let command = a[0];
    if command == "MATCH" {
        if matches.contains_key(a[1]) {
            return Err("duplicate match".to_owned());
        }
        let m = create_match(a)?;
        matches.insert(m.id.clone(), m);
        return Ok(Vec::new());
    }
    if command == "CHECKOUT" {
        let finish = checkout(darts, number(a[1]), 3);
        return Ok(vec![format!(
            "checkout {}: {}",
            a[1],
            if finish.is_empty() {
                "none".to_owned()
            } else {
                dart_names(darts, &finish)
            }
        )]);
    }
    if command == "STANDINGS" {
        let mut totals: BTreeMap<&str, [i32; 2]> = BTreeMap::new();
        for m in matches.values() {
            if m.config.sport == Sport::Bowling || !m.finished() {
                continue;
            }
            let first = m.winner();
            for side in 0..2 {
                totals.entry(&m.names[side]).or_default()[usize::from(side != first)] += 1;
            }
        }
        let mut rows: Vec<(&str, [i32; 2])> = totals.into_iter().collect();
        rows.sort_by(|a, b| {
            b.1[0]
                .cmp(&a.1[0])
                .then(a.1[1].cmp(&b.1[1]))
                .then(a.0.cmp(b.0))
        });
        let display = if rows.is_empty() {
            "none".to_owned()
        } else {
            rows.iter()
                .map(|(name, p)| format!("{name} {}", pair_text(*p, 0)))
                .collect::<Vec<_>>()
                .join(", ")
        };
        return Ok(vec![format!("standings: {display}")]);
    }
    let m = matches.get_mut(a[1]).ok_or("unknown match")?;
    match command {
        "SCORE" => return Ok(vec![m.score(darts)]),
        "STATS" => return Ok(m.statistics()),
        "RESULT" => return Ok(vec![m.result()?]),
        "UNDO" => {
            m.state = m.history.pop().ok_or("nothing to undo")?;
            return Ok(Vec::new());
        }
        _ => (),
    }
    let c = m.config;
    let allowed = match command {
        "POINT" => ![Sport::Bowling, Sport::Darts].contains(&c.sport),
        "ROLL" => c.sport == Sport::Bowling,
        "THROW" => c.sport == Sport::Darts,
        _ => c.sport == Sport::Volleyball,
    };
    if !allowed {
        return Err("wrong event".to_owned());
    }
    let count = match command {
        "POINT" => a[2].len(),
        "ROLL" | "THROW" => a.len() - 2,
        _ => 1,
    };
    for i in 0..count {
        if m.finished() {
            return Err("match over".to_owned());
        }
        let (mut value, mut position, mut side) = (0usize, None, 0usize);
        match command {
            "POINT" => value = usize::from(a[2].as_bytes()[i] == b'B'),
            "ROLL" => {
                value = number(a[i + 2]) as usize;
                if let State::Bowling(s) = m.state {
                    if value as i32 > bowling_info(&s).standing {
                        return Err("too many pins".to_owned());
                    }
                }
            }
            "THROW" => {
                value = darts
                    .iter()
                    .position(|d| d.name == a[i + 2])
                    .ok_or("invalid dart")?
            }
            _ => {
                side = usize::from(a[2] == "B");
                if let State::Rally(s) = m.state {
                    if command == "TIMEOUT" {
                        if s.timeouts[side] >= 2 {
                            return Err("no timeouts left".to_owned());
                        }
                    } else {
                        let leaving = number(a[3]);
                        value = number(a[4]) as usize;
                        position = Some(
                            s.lineup[side]
                                .iter()
                                .position(|&n| n == leaving)
                                .ok_or("player not on court")?,
                        );
                        if s.lineup[side].contains(&(value as i32)) {
                            return Err("player already on court".to_owned());
                        }
                        if s.substitutions[side] >= 6 {
                            return Err("no substitutions left".to_owned());
                        }
                    }
                }
            }
        }
        m.history.push(m.state);
        match &mut m.state {
            State::Rally(s) => match command {
                "POINT" => add_rally(&c, s, value),
                "SUB" => {
                    s.lineup[side][position.unwrap()] = value as i32;
                    s.substitutions[side] += 1;
                }
                _ => s.timeouts[side] += 1,
            },
            State::Bowling(s) => {
                s.rolls[s.count] = value as i32;
                s.count += 1;
            }
            State::Darts(s) => add_dart(&c, darts, s, value),
        }
    }
    Ok(Vec::new())
}
fn main() {
    let darts = initialize_darts();
    let mut matches = BTreeMap::new();
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in lines.take(count) {
        let line = line.unwrap();
        let a: Vec<&str> = line.split(' ').collect();
        let result = execute(&mut matches, &darts, &a)
            .unwrap_or_else(|message| vec![format!("ERROR {message}")]);
        for line in result {
            writeln!(output, "{line}").unwrap();
        }
    }
}
