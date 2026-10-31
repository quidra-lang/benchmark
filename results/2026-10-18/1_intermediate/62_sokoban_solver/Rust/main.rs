use std::collections::{HashMap, HashSet};
use std::io::{self, Read};
const DIRS: &[u8] = b"udlr";
const LEVEL: &[u8] = b"#-.$*@+";

fn text(bytes: &[u8]) -> String {
    String::from_utf8(bytes.to_vec()).unwrap()
}

fn pushes(letters: &[u8]) -> usize {
    letters.iter().filter(|c| c.is_ascii_uppercase()).count()
}

fn count(flags: &[bool]) -> usize {
    flags.iter().filter(|&&v| v).count()
}

fn moved(boxes: &[i32], from: i32, to: i32) -> Vec<i32> {
    let mut result: Vec<i32> = boxes.iter().map(|&b| if b == from {
        to
    } else {
        b
    }).collect();
    result.sort_unstable();
    result
}

fn decode(word: &str, allowed: &[u8]) -> Option<Vec<u8>> {
    let bytes = word.as_bytes();
    let mut result = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let start = i;
        let mut n = 0;
        while i < bytes.len() && bytes[i].is_ascii_digit() {
            if i - start < 2 {
                n = n * 10 + (bytes[i] - b'0') as usize;
            }
            i += 1;
        }
        if i - start > 2 || (i > start && bytes[start] == b'0') || i == bytes.len() || !allowed.contains(&bytes[i]) {
            return None;
        }
        result.extend(std::iter::repeat_n(bytes[i], if i == start {
            1
        } else {
            n
        }));
        i += 1;
    }
    Some(result)
}

fn encode(row: &str) -> String {
    let bytes = row.as_bytes();
    let mut result = String::new();
    let mut i = 0;
    while i < bytes.len() {
        let mut j = i + 1;
        while j < bytes.len() && bytes[j] == bytes[i] {
            j += 1;
        }
        if j - i > 1 {
            result.push_str(&(j - i).to_string());
        }
        result.push(bytes[i] as char);
        i = j;
    }
    result
}

fn turns(kind: &str) -> Option<&'static [u8; 4]> {
    match kind {
        "ROT90" => Some(b"rlud"),
        "ROT180" => Some(b"durl"),
        "ROT270" => Some(b"lrdu"),
        "FLIPH" => Some(b"udrl"),
        "FLIPV" => Some(b"dulr"),
        _ => None
    }
}

fn turn(letters: &[u8], kind: &str) -> Vec<u8> {
    letters.iter().map(|c| {
        let d = DIRS.iter().position(|&d| d == c.to_ascii_lowercase()).unwrap();
        let next = turns(kind).unwrap()[d];
        if c.is_ascii_uppercase() {
            next.to_ascii_uppercase()
        } else {
            next
        }
    }).collect()
}

fn kinds(command: &str) -> Option<&'static str> {
    match command {
        "IMPORT" => Some("t"),
        "MOVE" | "CHECK" => Some("s"),
        "PUSH" => Some("nnd"),
        "BRING" => Some("nnnn"),
        "PATH" => Some("nn"),
        "UNDO" | "REDO" | "SOLVE" | "HINT" => Some("n"),
        "SAVE" | "RESTORE" => Some("a"),
        "TRANSFORM" => Some("f"),
        "VALID" | "INFO" | "SHOW" | "EXPORT" | "RESET" | "STATUS" | "HISTORY"
        | "BOXES" | "REACH" | "DEADSQUARES" | "DEADLOCK" | "BOUND" | "PLAY" => Some(""),
        _ => None,
    }
}

fn argument(kind: u8, word: &str) -> bool {
    let b = word.as_bytes();
    match kind {
        b'n' => !b.is_empty() && b.len() <= 6 && b.iter().all(u8::is_ascii_digit) && (b.len() == 1 || b[0] != b'0'),
        b's' => decode(word, b"udlrUDLR").is_some(),
        b'd' => b.len() == 1 && DIRS.contains(&b[0]),
        b'a' => !b.is_empty() && b.len() <= 8 && b.iter().all(u8::is_ascii_lowercase),
        b'f' => turns(word).is_some(),
        _ => true,
    }
}

#[derive(Clone, PartialEq, Eq)]
struct Position {
    player: i32,
    boxes: Vec<i32>
}

#[derive(Clone)]
struct Level {
    h: usize,
    w: usize,
    walls: Vec<bool>,
    goals: Vec<bool>,
    inside: Vec<bool>,
    dead: Vec<bool>,
    goal_cells: Vec<i32>,
    distances: Vec<Vec<i32>>,
    reason: Option<String>,
}

impl Level {
    fn size(&self) -> usize {
        self.h * self.w
    }

    fn offsets(&self) -> [i32; 4] {
        [-(self.w as i32), self.w as i32, -1, 1]
    }

    fn offset(&self, direction: u8) -> i32 {
        self.offsets()[DIRS.iter().position(|&d| d == direction.to_ascii_lowercase()).unwrap()]
    }

    fn interior(&self, cell: i32) -> bool {
        cell >= 0 && self.inside.get(cell as usize).copied().unwrap_or(false)
    }

    fn cell(&self, cell: i32) -> String {
        format!("{} {}", cell as usize / self.w + 1, cell as usize % self.w + 1)
    }

    fn build(rows: &[String]) -> (Self, Position) {
        let h = rows.len();
        let w = rows[0].len();
        let bytes: Vec<u8> = rows.iter().flat_map(|r| r.bytes()).collect();
        let walls: Vec<bool> = bytes.iter().map(|&c| c == b'#').collect();
        let goals: Vec<bool> = bytes.iter().map(|c| b".*+".contains(c)).collect();
        let players: Vec<i32> = (0..bytes.len()).filter(|&i| b"@+".contains(&bytes[i])).map(|i| i as i32).collect();
        let boxes: Vec<i32> = (0..bytes.len()).filter(|&i| b"$*".contains(&bytes[i])).map(|i| i as i32).collect();
        let goal_cells = (0..bytes.len()).filter(|&i| goals[i]).map(|i| i as i32).collect();
        let mut level = Self {
            h,
            w,
            walls,
            goals,
            inside: vec![false; h * w],
            dead: vec![false; h * w],
            goal_cells,
            distances: Vec::new(),
            reason: None
        };
        if players.len() == 1 {
            let mut queue = vec![players[0] as usize];
            level.inside[queue[0]] = true;
            let mut head = 0;
            while head < queue.len() {
                let cell = queue[head];
                head += 1;
                let r = cell / w;
                let c = cell % w;
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nr = r as i32 + dr;
                    let nc = c as i32 + dc;
                    if nr >= 0 && nr < h as i32 && nc >= 0 && nc < w as i32 {
                        let p = nr as usize * w + nc as usize;
                        if !level.walls[p] && !level.inside[p] {
                            level.inside[p] = true;
                            queue.push(p);
                        }
                    }
                }
            }
        }
        level.reason = if players.len() != 1 {
            Some(format!("players {}", players.len()))
        } else if boxes.is_empty() {
            Some("no boxes".into())
        } else if boxes.len() != level.goal_cells.len() {
            Some(format!("boxes {} goals {}", boxes.len(), level.goal_cells.len()))
        } else if let Some(p) = (0..h * w).find(|&p| level.inside[p] && (p / w == 0 || p / w == h - 1 || p % w == 0 || p % w == w - 1)) {
            Some(format!("open {}", level.cell(p as i32)))
        } else if let Some(p) = (0..h * w).find(|&p| (level.goals[p] || boxes.contains(&(p as i32))) && !level.inside[p]) {
            Some(format!("outside {}", level.cell(p as i32)))
        } else {
            None
        };
        if level.reason.is_none() {
            level.analyze();
        }
        (level, Position {
            player: players.first().copied().unwrap_or(0),
            boxes
        })
    }

    fn analyze(&mut self) {
        self.goal_cells = (0..self.size()).filter(|&p| self.goals[p]).map(|p| p as i32).collect();
        self.distances = self.goal_cells.iter().map(|&goal| {
            let mut dist = vec![-1; self.size()];
            dist[goal as usize] = 0;
            let mut queue = vec![goal];
            let mut head = 0;
            while head < queue.len() {
                let q = queue[head];
                head += 1;
                for delta in self.offsets() {
                    let b = q - delta;
                    if self.interior(b) && self.interior(b - delta) && dist[b as usize] < 0 {
                        dist[b as usize] = dist[q as usize] + 1;
                        queue.push(b);
                    }
                }
            }
            dist
        }).collect();
        self.dead = (0..self.size()).map(|p| self.inside[p] && self.distances.iter().all(|d| d[p] < 0)).collect();
    }

    fn reach(&self, player: i32, boxes: &[i32]) -> Vec<bool> {
        let mut seen = vec![false; self.size()];
        seen[player as usize] = true;
        let mut queue = vec![player];
        let mut head = 0;
        while head < queue.len() {
            let q = queue[head];
            head += 1;
            for delta in self.offsets() {
                let p = q + delta;
                if self.interior(p) && !seen[p as usize] && !boxes.contains(&p) {
                    seen[p as usize] = true;
                    queue.push(p);
                }
            }
        }
        seen
    }

    fn representative(&self, player: i32, boxes: &[i32]) -> i32 {
        self.reach(player, boxes).iter().position(|&v| v).unwrap() as i32
    }

    fn path(&self, player: i32, target: i32, boxes: &[i32]) -> Vec<u8> {
        let mut from = vec![None; self.size()];
        let mut queue = vec![player];
        let mut head = 0;
        while head < queue.len() {
            let q = queue[head];
            head += 1;
            for (d, delta) in self.offsets().iter().enumerate() {
                let p = q + delta;
                if self.interior(p) && p != player && !boxes.contains(&p) && from[p as usize].is_none() {
                    from[p as usize] = Some((q, DIRS[d]));
                    queue.push(p);
                }
            }
        }
        let mut result = Vec::new();
        let mut p = target;
        while p != player {
            let (q, d) = from[p as usize].unwrap();
            result.push(d);
            p = q;
        }
        result.reverse();
        result
    }

    fn step(&self, position: &Position, direction: u8) -> Result<(Position, u8), &'static str> {
        let d = direction.to_ascii_lowercase();
        let delta = self.offset(d);
        let p = position.player + delta;
        if self.walls[p as usize] {
            return Err("wall");
        }
        let mut next = Position {
            player: p,
            boxes: position.boxes.clone()
        };
        if position.boxes.contains(&p) {
            let dest = p + delta;
            if self.walls[dest as usize] || position.boxes.contains(&dest) {
                return Err("blocked");
            }
            next.boxes = moved(&next.boxes, p, dest);
            Ok((next, d.to_ascii_uppercase()))
        } else {
            Ok((next, d))
        }
    }

    fn pushable(&self, b: i32, d: usize, boxes: &[i32], reach: &[bool]) -> bool {
        let delta = self.offsets()[d];
        reach[(b - delta) as usize] && self.interior(b + delta) && !boxes.contains(&(b + delta))
    }

    fn frozen(&self, b: i32, boxes: &[i32], assumed: &[i32]) -> bool {
        let axis = |sides: [i32;2]| {
            if sides.iter().any(|&p| self.walls[p as usize] || assumed.contains(&p)) || sides.iter().all(|&p| self.dead[p as usize]) {
                return true;
            }
            let mut extended = assumed.to_vec();
            extended.push(b);
            sides.iter().any(|&p| boxes.contains(&p) && self.frozen(p, boxes, &extended))
        };
        axis([b - 1, b + 1]) && axis([b - self.w as i32, b + self.w as i32])
    }

    fn on_goals(&self, boxes: &[i32]) -> usize {
        boxes.iter().filter(|&&b| self.goals[b as usize]).count()
    }

    fn solved(&self, boxes: &[i32]) -> bool {
        self.on_goals(boxes) == boxes.len()
    }

    fn render(&self, pos: &Position, dead_map: bool) -> Vec<String> {
        let cells: Vec<u8> = (0..self.size()).map(|p| {
            if self.walls[p] {
                b'#'
            } else if dead_map {
                if self.goals[p] {
                    b'.'
                } else if self.dead[p] {
                    b'x'
                } else {
                    b'-'
                }
            } else if pos.player == p as i32 {
                if self.goals[p] {
                    b'+'
                } else {
                    b'@'
                }
            } else if pos.boxes.contains(&(p as i32)) {
                if self.goals[p] {
                    b'*'
                } else {
                    b'$'
                }
            } else if self.goals[p] {
                b'.'
            } else {
                b'-'
            }
        }).collect();
        cells.chunks(self.w).map(text).collect()
    }

    fn map_cell(&self, p: i32, kind: &str) -> i32 {
        let r = p as usize / self.w;
        let c = p as usize % self.w;
        (match kind {
            "ROT90" => c * self.h + self.h - 1 - r,
            "ROT180" => (self.h - 1 - r) * self.w + self.w - 1 - c,
            "ROT270" => (self.w - 1 - c) * self.h + r,
            "FLIPH" => r * self.w + self.w - 1 - c,
            _ => (self.h - 1 - r) * self.w + c
        }) as i32
    }

    fn map_position(&self, p: &Position, kind: &str) -> Position {
        let mut boxes: Vec<i32> = p.boxes.iter().map(|&b| self.map_cell(b, kind)).collect();
        boxes.sort_unstable();
        Position {
            player: self.map_cell(p.player, kind),
            boxes
        }
    }

    fn transformed(&self, kind: &str) -> Self {
        let mut result = self.clone();
        if kind == "ROT90" || kind == "ROT270" {
            result.h = self.w;
            result.w = self.h;
        }
        for p in 0..self.size() {
            let q = self.map_cell(p as i32, kind) as usize;
            result.walls[q] = self.walls[p];
            result.goals[q] = self.goals[p];
            result.inside[q] = self.inside[p];
        }
        result.analyze();
        result
    }
}

#[derive(Clone, Hash, PartialEq, Eq)]
struct State {
    boxes: Vec<i32>,
    representative: i32
}

struct Node {
    state: State,
    parent: Option<usize>,
    push: (i32, usize)
}

struct Search {
    outcome: &'static str,
    expanded: usize,
    states: usize,
    notation: Vec<u8>
}

fn search(level: &Level, start: &Position, fixed: &[i32], target: Option<i32>, pruning: bool, limit: Option<usize>) -> Search {
    let first = State {
        boxes: start.boxes.clone(),
        representative: level.representative(start.player, &start.boxes)
    };
    let mut known = HashSet::from([first.clone()]);
    let mut nodes = vec![Node {
        state: first,
        parent: None,
        push: (0, 0)
    }];
    let mut expanded = 0;
    while expanded < nodes.len() {
        if Some(expanded) == limit {
            return Search {
                outcome: "limit",
                expanded,
                states: nodes.len(),
                notation: Vec::new()
            };
        }
        let parent = expanded;
        let state = nodes[parent].state.clone();
        expanded += 1;
        let reach = level.reach(state.representative, &state.boxes);
        for &b in &state.boxes {
            if fixed.contains(&b) {
                continue;
            }
            for d in 0..4 {
                if !level.pushable(b, d, &state.boxes, &reach) {
                    continue;
                }
                let dest = b + level.offsets()[d];
                let boxes = moved(&state.boxes, b, dest);
                if pruning && (level.dead[dest as usize] || boxes.iter().any(|&p| !level.goals[p as usize] && level.frozen(p, &boxes, &[]))) {
                    continue;
                }
                let next = State {
                    representative: level.representative(b, &boxes),
                    boxes
                };
                if !known.insert(next.clone()) {
                    continue;
                }
                let found = match target {
                    Some(t) => dest == t,
                    None => level.solved(&next.boxes)
                };
                nodes.push(Node {
                    state: next,
                    parent: Some(parent),
                    push: (b, d)
                });
                if found {
                    let mut steps = Vec::new();
                    let mut i = nodes.len() - 1;
                    while let Some(p) = nodes[i].parent {
                        steps.push(nodes[i].push);
                        i = p;
                    }
                    steps.reverse();
                    let mut position = start.clone();
                    let mut notation = Vec::new();
                    for (b, d) in steps {
                        let delta = level.offsets()[d];
                        notation.extend(level.path(position.player, b - delta, &position.boxes));
                        notation.push(DIRS[d].to_ascii_uppercase());
                        position = Position {
                            player: b,
                            boxes: moved(&position.boxes, b, b + delta)
                        };
                    }
                    return Search {
                        outcome: "found",
                        expanded,
                        states: nodes.len(),
                        notation
                    };
                }
            }
        }
    }
    Search {
        outcome: "no solution",
        expanded,
        states: nodes.len(),
        notation: Vec::new()
    }
}

#[derive(Clone)]
struct Snapshot {
    position: Position,
    history: Vec<u8>
}

#[derive(Clone)]
struct Solution {
    position: Position,
    notation: Vec<u8>
}

struct Game {
    level: Level,
    initial: Position,
    current: Position,
    history: Vec<u8>,
    redo: Vec<u8>,
    snapshots: HashMap<String, Snapshot>,
    solution: Option<Solution>,
    output: Vec<String>
}

impl Game {
    fn new(rows: &[String]) -> Self {
        let (level, initial) = Level::build(rows);
        Self {
            level,
            current: initial.clone(),
            initial,
            history: Vec::new(),
            redo: Vec::new(),
            snapshots: HashMap::new(),
            solution: None,
            output: Vec::new()
        }
    }

    fn load(&mut self, rows: &[String]) {
        let (level, position) = Level::build(rows);
        self.level = level;
        self.initial = position.clone();
        self.current = position;
        self.history.clear();
        self.redo.clear();
        self.snapshots.clear();
        self.solution = None;
    }

    fn emit(&mut self, line: String) {
        self.output.push(line);
    }

    fn progress(&self, boxes: &[i32]) -> String {
        let n = self.level.on_goals(boxes);
        format!("goals {}/{}{}", n, boxes.len(), if n == boxes.len() {
            " solved"
        } else {
            ""
        })
    }

    fn simulate(&self, directions: &[u8]) -> (Position, Vec<u8>, Option<String>) {
        let mut position = self.current.clone();
        let mut letters = Vec::new();
        for &d in directions {
            match self.level.step(&position, d) {
                Ok((next, c)) => {
                    position = next;
                    letters.push(c);
                },
                Err(reason) => {
                    let error = format!("step {} {}", letters.len() + 1, reason);
                    return (position, letters, Some(error));
                }
            }
        }
        (position, letters, None)
    }

    fn take(&mut self, directions: &[u8]) -> (Vec<u8>, Option<String>) {
        let (position, letters, failure) = self.simulate(directions);
        self.current = position;
        self.history.extend(&letters);
        if !letters.is_empty() {
            self.redo.clear();
        }
        (letters, failure)
    }

    fn cell_argument(&self, a: &[&str], i: usize) -> i32 {
        (a[i].parse::<i32>().unwrap() - 1) * self.level.w as i32 + a[i + 1].parse::<i32>().unwrap() - 1
    }

    fn execute(&mut self, words: &[&str], rows: &[String]) -> Result<(), String> {
        let name = words[0];
        let a = &words[1..];
        if name == "LOAD" {
            let w = a[1].parse::<usize>().unwrap();
            if let Some(i) = rows.iter().position(|r| r.len() != w || !r.bytes().all(|c| LEVEL.contains(&c))) {
                return Err(format!("bad row {}", i + 1));
            }
            self.load(rows);
            self.emit(format!("loaded {}x{}", rows.len(), w));
            return Ok(());
        }
        let schema = kinds(name).ok_or_else(|| format!("unknown command {}", name))?;
        if a.len() != schema.len() || !schema.bytes().zip(a.iter()).all(|(k, w)| argument(k, w)) {
            return Err("bad arguments".into());
        }
        if name == "IMPORT" {
            let rows: Option<Vec<Vec<u8>>> = a[0].split('|').map(|s| decode(s, LEVEL)).collect();
            let rows = rows.ok_or("bad level")?;
            if rows.len() > 10 || rows[0].is_empty() || rows[0].len() > 10 || rows.iter().any(|r| r.len() != rows[0].len()) {
                return Err("bad level".into());
            }
            let rows: Vec<String> = rows.iter().map(|r| text(r)).collect();
            self.load(&rows);
            self.emit(format!("loaded {}x{}", self.level.h, self.level.w));
            return Ok(());
        }
        if name == "VALID" {
            self.emit(self.level.reason.as_ref().map_or("valid".into(), |r| format!("invalid {}", r)));
            return Ok(());
        }
        if self.level.reason.is_some() {
            return Err("invalid level".into());
        }
        let cells = match name {
            "PATH" | "PUSH" => 1,
            "BRING" => 2,
            _ => 0
        };
        for i in 0..cells {
            let r = a[2 * i].parse::<usize>().unwrap();
            let c = a[2 * i + 1].parse::<usize>().unwrap();
            if r < 1 || r > self.level.h || c < 1 || c > self.level.w {
                return Err("bad value".into());
            }
        }
        if matches!(name, "UNDO" | "REDO" | "SOLVE" | "HINT") {
            let n = a[0].parse::<usize>().unwrap();
            if n < 1 || (matches!(name, "SOLVE" | "HINT") && n > 100000) {
                return Err("bad value".into());
            }
        }
        match name {
            "INFO" => self.emit(format!(
                "size {}x{} walls {} cells {} boxes {} dead {}",
                self.level.h, self.level.w, count(&self.level.walls), count(&self.level.inside), self.current.boxes.len(), count(&self.level.dead))),
            "SHOW" => {
                self.output.extend(self.level.render(&self.current, false));
            },
            "EXPORT" => self.emit(format!(
                "level {}",
                self.level.render(&self.current, false).iter().map(|r| encode(r)).collect::<Vec<_>>().join("|"))),
            "MOVE" => {
                let steps = decode(a[0], b"udlrUDLR").unwrap();
                let (letters, failure) = self.take(&steps);
                if !letters.is_empty() {
                    self.emit(format!("moved {}", text(&letters)));
                }
                if let Some(error) = failure {
                    return Err(error);
                }
            },
            "PUSH" => {
                let b = self.cell_argument(a, 0);
                let d = a[2].as_bytes()[0];
                let delta = self.level.offset(d);
                if !self.current.boxes.contains(&b) {
                    return Err("no box".into());
                }
                if !self.level.interior(b + delta) || self.current.boxes.contains(&(b + delta)) {
                    return Err("blocked".into());
                }
                if !self.level.reach(self.current.player, &self.current.boxes)[(b - delta) as usize] {
                    return Err("unreachable".into());
                }
                let mut path = self.level.path(self.current.player, b - delta, &self.current.boxes);
                path.push(d);
                let (letters, _) = self.take(&path);
                self.emit(format!("pushed {}", text(&letters)));
            },
            "BRING" => {
                let b = self.cell_argument(a, 0);
                let target = self.cell_argument(a, 2);
                if !self.current.boxes.contains(&b) {
                    return Err("no box".into());
                }
                if b == target {
                    self.emit("brought 0".into());
                } else {
                    let fixed: Vec<i32> = self.current.boxes.iter().copied().filter(|&p| p != b).collect();
                    let result = search(&self.level, &self.current, &fixed, Some(target), false, None);
                    if result.outcome != "found" {
                        return Err("no route".into());
                    }
                    self.take(&result.notation);
                    self.emit(format!("brought {} {}", pushes(&result.notation), text(&result.notation)));
                }
            },
            "PATH" => {
                let target = self.cell_argument(a, 0);
                if !self.level.reach(self.current.player, &self.current.boxes)[target as usize] {
                    return Err("unreachable".into());
                }
                let path = self.level.path(self.current.player, target, &self.current.boxes);
                let (letters, _) = self.take(&path);
                self.emit(if letters.is_empty() {
                    "path 0".into()
                } else {
                    format!("path {} {}", letters.len(), text(&letters))
                });
            },
            "UNDO" => {
                if self.history.is_empty() {
                    return Err("nothing to undo".into());
                }
                let n = a[0].parse::<usize>().unwrap().min(self.history.len());
                for _ in 0..n {
                    let letter = self.history.pop().unwrap();
                    let d = letter.to_ascii_lowercase();
                    let delta = self.level.offset(d);
                    let p = self.current.player;
                    if letter.is_ascii_uppercase() {
                        self.current.boxes = moved(&self.current.boxes, p + delta, p);
                    }
                    self.current.player = p - delta;
                    self.redo.push(d);
                }
                self.emit(format!("undone {}", n));
            },
            "REDO" => {
                if self.redo.is_empty() {
                    return Err("nothing to redo".into());
                }
                let n = a[0].parse::<usize>().unwrap().min(self.redo.len());
                for _ in 0..n {
                    let d = self.redo.pop().unwrap();
                    let (p, c) = self.level.step(&self.current, d).unwrap();
                    self.current = p;
                    self.history.push(c);
                }
                self.emit(format!("redone {}", n));
            },
            "RESET" => {
                self.current = self.initial.clone();
                self.history.clear();
                self.redo.clear();
                self.emit("reset".into());
            },
            "STATUS" => self.emit(format!("moves {} pushes {} {}", self.history.len(), pushes(&self.history), self.progress(&self.current.boxes))),
            "HISTORY" => self.emit(if self.history.is_empty() {
                "history 0".into()
            } else {
                format!("history {} {}", self.history.len(), text(&self.history))
            }),
            "BOXES" => {
                self.emit(format!("boxes {}", self.current.boxes.len()));
                let reach = self.level.reach(self.current.player, &self.current.boxes);
                for b in self.current.boxes.clone() {
                    let distance = self.level.distances.iter().map(|d| d[b as usize]).filter(|&d| d >= 0).min().map_or("dead".into(), |d| d.to_string());
                    let dirs: Vec<u8> = (0..4).filter(|&d| self.level.pushable(b, d, &self.current.boxes, &reach)).map(|d| DIRS[d]).collect();
                    self.emit(format!("box {} {} {}", self.level.cell(b), distance, if dirs.is_empty() {
                        "-".into()
                    } else {
                        text(&dirs)
                    }));
                }
            },
            "REACH" => {
                let reach = self.level.reach(self.current.player, &self.current.boxes);
                self.emit(format!("reach {} first {}", count(&reach), self.level.cell(reach.iter().position(|&v| v).unwrap() as i32)));
            },
            "DEADSQUARES" => {
                self.emit(format!("dead {}", count(&self.level.dead)));
                self.output.extend(self.level.render(&self.current, true));
            },
            "DEADLOCK" => {
                let dead = self.current.boxes.iter().copied().find(|&b| self.level.dead[b as usize]);
                let frozen = self.current.boxes.iter().copied().find(|&b| !self.level.goals[b as usize] && self.level.frozen(b, &self.current.boxes, &[]));
                self.emit(if let Some(b) = dead {
                    format!("deadlock dead {}", self.level.cell(b))
                } else if let Some(b) = frozen {
                    format!("deadlock frozen {}", self.level.cell(b))
                } else {
                    "no deadlock".into()
                });
            },
            "BOUND" => {
                let mut best = None;
                self.assignment(&mut Vec::new(), 0, 0, &mut best);
                if let Some((total, order)) = best {
                    self.emit(format!("bound {}", total));
                    for (i, g) in order.iter().enumerate() {
                        let b = self.current.boxes[i];
                        self.emit(format!("box {} goal {} pushes {}", self.level.cell(b), self.level.cell(self.level.goal_cells[*g]), self.level.distances[*g][b as usize]));
                    }
                } else {
                    self.emit("bound none".into());
                }
            },
            "SAVE" => {
                self.snapshots.insert(a[0].into(), Snapshot {
                    position: self.current.clone(),
                    history: self.history.clone()
                });
                self.emit(format!("saved {} moves {}", a[0], self.history.len()));
            },
            "RESTORE" => {
                let snapshot = self.snapshots.get(a[0]).ok_or_else(|| format!("no snapshot {}", a[0]))?.clone();
                self.current = snapshot.position;
                self.history = snapshot.history;
                self.redo.clear();
                self.emit(format!("restored {} moves {}", a[0], self.history.len()));
            },
            "CHECK" => {
                let (p, letters, failure) = self.simulate(&decode(a[0], b"udlrUDLR").unwrap());
                self.emit(if let Some(error) = failure {
                    format!("check fail {}", error)
                } else {
                    format!("check ok moves {} pushes {} {}", letters.len(), pushes(&letters), self.progress(&p.boxes))
                });
            },
            "SOLVE" | "HINT" => {
                let (summary, notation) = self.search_solution(a[0].parse().unwrap());
                if name == "SOLVE" {
                    self.solution = notation.as_ref().map(|n| Solution {
                        position: self.current.clone(),
                        notation: n.clone()
                    });
                    self.emit(summary);
                    if let Some(n) = notation {
                        self.emit(text(&n));
                    }
                } else if let Some(n) = notation {
                    let end = n.iter().position(u8::is_ascii_uppercase).unwrap() + 1;
                    self.take(&n[..end]);
                    self.emit(format!("hint {}", text(&n[..end])));
                } else {
                    self.emit(summary);
                }
            },
            "PLAY" => {
                let solution = self.solution.as_ref().filter(|s| s.position == self.current).ok_or("no solution")?.clone();
                self.take(&solution.notation);
                self.emit(format!("played pushes {} moves {}", pushes(&solution.notation), solution.notation.len()));
            },
            "TRANSFORM" => {
                let kind = a[0];
                let old = self.level.clone();
                self.level = old.transformed(kind);
                self.initial = old.map_position(&self.initial, kind);
                self.current = old.map_position(&self.current, kind);
                self.history = turn(&self.history, kind);
                self.redo = turn(&self.redo, kind);
                for snapshot in self.snapshots.values_mut() {
                    snapshot.position = old.map_position(&snapshot.position, kind);
                    snapshot.history = turn(&snapshot.history, kind);
                }
                if let Some(s) = &mut self.solution {
                    s.position = old.map_position(&s.position, kind);
                    s.notation = turn(&s.notation, kind);
                }
                self.emit(format!("transformed {}x{}", self.level.h, self.level.w));
            },
            _ => unreachable!(),
        }
        Ok(())
    }

    fn assignment(&self, order: &mut Vec<usize>, used: u32, total: i32, best: &mut Option<(i32, Vec<usize>)>) {
        let i = order.len();
        if i == self.current.boxes.len() {
            if best.as_ref().is_none_or(|(cost, _)|total < *cost) {
                *best = Some((total, order.clone()));
            }
            return;
        }
        for g in 0..self.level.goal_cells.len() {
            let d = self.level.distances[g][self.current.boxes[i] as usize];
            if used & (1 << g) == 0 && d >= 0 {
                order.push(g);
                self.assignment(order, used | (1 << g), total + d, best);
                order.pop();
            }
        }
    }

    fn search_solution(&self, limit: usize) -> (String, Option<Vec<u8>>) {
        if self.level.solved(&self.current.boxes) {
            return ("already solved".into(), None);
        }
        let result = search(&self.level, &self.current, &[], None, true, Some(limit));
        let counts = format!("expanded {} states {}", result.expanded, result.states);
        if result.outcome != "found" {
            return (format!("{} {}", result.outcome, counts), None);
        }
        (format!("solution pushes {} moves {} {}", pushes(&result.notation), result.notation.len(), counts), Some(result.notation))
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let h = lines.next().unwrap().split(' ').next().unwrap().parse::<usize>().unwrap();
    let rows: Vec<String> = (0..h).map(|_| lines.next().unwrap().to_owned()).collect();
    let mut game = Game::new(&rows);
    let n = lines.next().unwrap().parse::<usize>().unwrap();
    for _ in 0..n {
        let words: Vec<&str> = lines.next().unwrap().split(' ').collect();
        let rows = if words[0] == "LOAD" {
            (0..words[1].parse::<usize>().unwrap()).map(|_| lines.next().unwrap().to_owned()).collect()
        } else {
            Vec::new()
        };
        if let Err(error) = game.execute(&words, &rows) {
            game.emit(format!("error: {}", error));
        }
    }
    println!("{}", game.output.join("\n"));
}
