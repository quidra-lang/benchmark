use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};
const KINDS: &[u8; 7] = b"IOTSZJL";
const STATES: [&str; 4] = ["0", "R", "2", "L"];
const OPS: [&str; 11] = ["L", "R", "LL", "RR", "SD", "DD", "CW", "CCW", "HD", "LOCK", "HOLD"];
const CLEAR: [&str; 11] = ["SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"];
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Position {
    s: usize, x: i32, y: i32
}
type Well = [u16; 22];
fn spawn(k: usize) -> Position {
    Position {
        s: 0, x: if k == 1 {
            5
        } else {
            4
        }, y: 22
    }
}
fn cells(k: usize, p: Position) -> Vec<(i32, i32)> {
    let shapes: [&[(i32, i32)]; 7] = [&[(0, 1), (1, 1), (2, 1), (3, 1)], &[(0, 0), (1, 0), (0, 1), (1, 1)], &[(1, 0), (0, 1), (1, 1), (2, 1)], &[(1, 0), (2, 0), (0, 1), (1, 1)], &[(0, 0), (1, 0), (1, 1), (2, 1)], &[(0, 0), (0, 1), (1, 1), (2, 1)], &[(2, 0), (0, 1), (1, 1), (2, 1)]];
    let n = if k == 0 {
        4
    } else if k == 1 {
        2
    } else {
        3
    };
    shapes[k].iter().map(|&(mut x, mut y)| {
        for _ in 0..p.s {
            (x, y) = (n-1-y, x)
        }(p.x+x, p.y-y)
    }).collect()
}
fn blocked(w: &Well, x: i32, y: i32) -> bool {
    !(1..= 10).contains(&x) || !(1..= 22).contains(&y) || w[(y-1)as usize]&(1<<(x-1)) != 0
}
fn fits(w: &Well, k: usize, p: Position) -> bool {
    cells(k, p).iter().all(|&(x, y)|!blocked(w, x, y))
}
fn movement(w: &Well, k: usize, p: Position, op: usize) -> Option<(Position, usize)> {
    if op<6 {
        let (dx, dy) = if op == 0 || op == 2 {
            (-1, 0)
        } else if op == 1 || op == 3 {
            (1, 0)
        } else {
            (0, -1)
        };
        let mut q = p;
        loop {
            let t = Position {
                s: q.s, x: q.x+dx, y: q.y+dy
            };
            if !fits(w, k, t) {
                break
            }
            q = t;
            if op == 0 || op == 1 || op == 4 {
                break
            }
        }
        if q == p {
            None
        } else {
            Some((q, 0))
        }
    } else {
        let b = (p.s+if op == 6 {
            1
        } else {
            3
        })%4;
        let kicks = if k == 1 {
            vec![(0, 0)]
        } else if k == 0 {
            match (p.s, b) {
                (0, 1)|(3, 2) => vec![(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)], (1, 0)|(2, 3) => vec![(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)], (1, 2)|(0, 3) => vec![(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)], _ => vec![(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)]
            }
        } else {
            match (p.s, b) {
                (0, 1)|(2, 1) => vec![(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)], (1, 0)|(1, 2) => vec![(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)], (2, 3)|(0, 3) => vec![(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)], _ => vec![(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)]
            }
        };
        for (i, (dx, dy)) in  kicks.into_iter().enumerate() {
            let q = Position {
                s: b, x: p.x+dx, y: p.y+dy
            };
            if fits(w, k, q) {
                return Some((q, i+1))
            }
        }
        None
    }
}
fn landing(w: &Well, k: usize, p: Position) -> Position {
    movement(w, k, p, 5).map_or(p, |x|x.0)
}
fn place(w: &mut Well, k: usize, p: Position) -> usize {
    for (x, y) in  cells(k, p) {
        w[(y-1)as usize] |= 1<<(x-1)
    }
    let mut j = 0;
    for i in 0..22 {
        if w[i] != 1023 {
            w[j] = w[i];
            j += 1
        }
    }
    let n = 22-j;
    for r in &mut w[j..] {
        *r = 0
    }
    n
}
fn analysis(w: &Well, n: usize) -> ([i32; 10], i32, i32, i32) {
    let mut h = [0; 10];
    let mut holes = 0;
    for c in 0..10 {
        h[c] = (0..22).rev().find(|&r|w[r]&(1<<c) != 0).map_or(0, |r|r as i32+1);
        holes += (0..h[c] as usize).filter(|&r|w[r]&(1<<c) == 0).count()as i32
    }
    let bump = (0..9).map(|c|(h[c]-h[c+1]).abs()).sum::<i32>();
    let v = 76*n as i32-51*h.iter().sum::<i32>()-36*holes-18*bump;
    (h, holes, bump, v)
}
fn explore(w: &Well, k: usize, start: Position) -> Vec<(Position, Vec<usize>)> {
    if !fits(w, k, start) {
        return Vec::new()
    }
    let mut seen = BTreeSet::from([start]);
    let mut queue = VecDeque::from([(start, Vec::new())]);
    let mut result = Vec::new();
    while let Some((p, path)) = queue.pop_front() {
        result.push((p, path.clone()));
        for op in 0..8 {
            if let Some((q, _)) = movement(w, k, p, op) {
                if seen.insert(q) {
                    let mut next = path.clone();
                    next.push(op);
                    queue.push_back((q, next))
                }
            }
        }
    }
    result
}
fn spin(w: &Well, p: Position, test: usize) -> usize {
    let corners = [blocked(w, p.x, p.y), blocked(w, p.x+2, p.y), blocked(w, p.x+2, p.y-2), blocked(w, p.x, p.y-2)];
    if corners.iter().filter(| && x|x).count()<3 {
        0
    } else if (corners[p.s] && corners[(p.s+1)%4]) || test == 5 {
        2
    } else {
        1
    }
}
fn clear_type(spin: usize, n: usize) -> Option<(usize, i64, i64)> {
    match (spin, n) {
        (0, 1) => Some((0, 100, 0)), (0, 2) => Some((1, 300, 1)), (0, 3) => Some((2, 500, 2)), (0, 4) => Some((3, 800, 4)), (1, 0) => Some((4, 100, 0)), (1, 1) => Some((5, 200, 0)), (1, 2) => Some((6, 400, 1)), (2, 0) => Some((7, 400, 0)), (2, 1) => Some((8, 800, 2)), (2, 2) => Some((9, 1200, 4)), (2, 3) => Some((10, 1600, 6)), _ => None
    }
}
#[derive(Clone, Default)]
struct Stats {
    drops: i64, holds: i64, operations: i64, faults: i64, perfect: i64, sent: i64, cancelled: i64, received: i64, combo: i64, chain: i64, kinds: [i64; 7], clears: [i64; 11]
}
#[derive(Clone)]
struct State {
    well: Well, random: u64, queue: VecDeque<usize>, hold: Option<usize>, used: bool, kind: usize, p: Position, motion: usize, test: usize, operations: i64, drop: i64, fall: i64, ground: i64, resets: i64, lowest: i32, start_level: i64, level: i64, score: i64, lines: i64, pieces: i64, streak: i64, chain: i64, pending: VecDeque<i64>, stats: Stats, ended: bool
}
#[derive(Clone)]
struct Snapshot {
    state: State, history: Vec<State>, start: State
}
struct Game {
    serial: usize, s: State, history: Vec<State>, start: State, saves: BTreeMap<String, Snapshot>
}
fn ratio(a: i64, b: i64) -> String {
    let q = if b == 0 {
        0
    } else {
        100*a/b
    };
    format!("{}.{:02}", q/100, q%100)
}
fn operation_string(ops: &[usize]) -> String {
    if ops.is_empty() {
        "none".into()
    } else {
        ops.iter().map(|&i|OPS[i]).collect::<Vec<_>>().join(" ")
    }
}
#[derive(Clone)]
struct Candidate {
    value: i32, kind: usize, ops: Vec<usize>
}
impl State {
    fn random(&mut self) -> u64 {
        self.random = self.random*48271%2147483647;
        self.random
    }
    fn bag(&mut self) {
        let mut bag = [0, 1, 2, 3, 4, 5, 6];
        for i in (1..7).rev() {
            let j = (self.random()%(i+1)as u64)as usize;
            bag.swap(i, j)
        }
        self.queue.extend(bag)
    }
    fn next(&mut self) -> usize {
        let k = self.queue.pop_front().unwrap();
        if self.queue.len()<5 {
            self.bag()
        }
        k
    }
    fn update(&mut self, p: Position, motion: usize, test: usize) {
        self.p = p;
        self.motion = motion;
        self.test = test;
        let low = cells(self.kind, p).iter().map(|&(_, y)|y).min().unwrap();
        if low<self.lowest {
            self.lowest = low;
            self.resets = 0
        }
    }
    fn pending(&self) -> i64 {
        self.pending.iter().sum()
    }
    fn candidates_for(&self, k: usize, start: Position, prefix: &[usize]) -> Vec<Candidate> {
        let mut result = Vec::new();
        let mut seen = BTreeSet::new();
        for rotations in [vec![], vec![6], vec![6, 6], vec![7]] {
            let mut p = start;
            let mut valid = true;
            for &op in &rotations {
                if let Some((q, _)) = movement(&self.well, k, p, op) {
                    p = q
                } else {
                    valid = false;
                    break
                }
            }
            if !valid {
                continue
            }
            let mut shifts = vec![(p, Vec::new())];
            for op in 0..2 {
                let mut q = p;
                let mut path = Vec::new();
                while let Some((t, _)) = movement(&self.well, k, q, op) {
                    q = t;
                    path.push(op);
                    shifts.push((q, path.clone()))
                }
            }
            for (q, path) in  shifts {
                let target = landing(&self.well, k, q);
                let mut blocks = cells(k, target);
                blocks.sort();
                if !seen.insert(blocks) {
                    continue
                }
                let mut well = self.well;
                let n = place(&mut well, k, target);
                let value = analysis(&well, n).3;
                let mut ops = prefix.to_vec();
                ops.extend(rotations.clone());
                ops.extend(path);
                ops.push(8);
                result.push(Candidate {
                    value, kind: k, ops
                })
            }
        }
        result
    }
    fn candidates(&self) -> Vec<Candidate> {
        let mut result = self.candidates_for(self.kind, self.p, &[]);
        if !self.used {
            let k = self.hold.unwrap_or(self.queue[0]);
            if fits(&self.well, k, spawn(k)) {
                result.extend(self.candidates_for(k, spawn(k), &[10]))
            }
        }
        result.sort_by(|a, b|b.value.cmp(&a.value));
        result
    }
}
impl Game {
    fn new(serial: usize, seed: u64, level: i64) -> Self {
        let mut s = State {
            well: [0; 22], random: seed, queue: VecDeque::new(), hold: None, used: false, kind: 0, p: spawn(0), motion: 0, test: 0, operations: 0, drop: 0, fall: 0, ground: 0, resets: 0, lowest: 21, start_level: level, level, score: 0, lines: 0, pieces: 0, streak: 0, chain: 0, pending: VecDeque::new(), stats: Stats::default(), ended: false
        };
        s.bag();
        s.kind = s.next();
        s.p = spawn(s.kind);
        s.lowest = cells(s.kind, s.p).iter().map(|&(_, y)|y).min().unwrap();
        Self {
            serial, start: s.clone(), s, history: Vec::new(), saves: BTreeMap::new()
        }
    }
    fn summary(&self, out: &mut Vec<String>) {
        let s = &self.s;
        let t = &s.stats;
        out.push(format!("summary game {} score {} level {} lines {} pieces {}", self.serial, s.score, s.level, s.lines, s.pieces));
        out.push(format!("clears single {} double {} triple {} tetris {} perfect {}", t.clears[0], t.clears[1], t.clears[2], t.clears[3], t.perfect));
        out.push(format!("tspins mini {} mini_single {} mini_double {} zero {} single {} double {} triple {}", t.clears[4], t.clears[5], t.clears[6], t.clears[7], t.clears[8], t.clears[9], t.clears[10]));
        out.push(format!("pieces {}", KINDS.iter().enumerate().map(|(i, &k)|format!("{} {}", k as char, t.kinds[i])).collect::<Vec<_>>().join(" ")));
        out.push(format!("best combo {} chain {} holds {} drops {} faults {}", t.combo, t.chain, t.holds, t.drops, t.faults));
        out.push(format!("garbage sent {} cancelled {} received {}", t.sent, t.cancelled, t.received));
        out.push(format!("rates app {} apl {} kpp {}", ratio(t.sent, s.pieces), ratio(t.sent, s.lines), ratio(t.operations, s.pieces)));
    }
    fn over(&mut self, reason: &str, out: &mut Vec<String>) {
        out.push(format!("game over {}", reason));
        self.summary(out);
        self.s.ended = true
    }
    fn spawn(&mut self, k: usize, out: &mut Vec<String>) {
        let s = &mut self.s;
        s.kind = k;
        s.p = spawn(k);
        s.motion = 0;
        s.test = 0;
        s.operations = 0;
        s.drop = 0;
        s.fall = 0;
        s.ground = 0;
        s.resets = 0;
        s.lowest = cells(k, s.p).iter().map(|&(_, y)|y).min().unwrap();
        if !fits(&s.well, k, s.p) {
            self.over("block out", out)
        }
    }
    fn garbage(&mut self, n: usize, h: usize, out: &mut Vec<String>) -> bool {
        if self.s.well[22-n..].iter().any(|&r|r != 0) {
            self.over("top out", out);
            return false
        }
        for r in (n..22).rev() {
            self.s.well[r] = self.s.well[r-n]
        }
        for r in &mut self.s.well[..n] {
            *r = 1023^(1<<(h-1))
        }
        true
    }
    fn drop_points(&mut self, n: i64) {
        self.s.score += n;
        self.s.drop += n;
        self.s.stats.drops += n
    }
    fn lock(&mut self, out: &mut Vec<String>) {
        let k = self.s.kind;
        let p = self.s.p;
        let shortest = explore(&self.s.well, k, spawn(k)).into_iter().find(|(q, _)|landing(&self.s.well, k, *q) == p).map(|(_, path)|path);
        let tspin = if k == 2 && self.s.motion == 2 {
            spin(&self.s.well, p, self.s.test)
        } else {
            0
        };
        let lockout = cells(k, p).iter().all(|&(_, y)|y >= 21);
        let n = place(&mut self.s.well, k, p);
        self.history.push(self.start.clone());
        let s = &mut self.s;
        s.pieces += 1;
        s.stats.kinds[k] += 1;
        s.stats.operations += s.operations;
        let clear = clear_type(tspin, n);
        let mut points = clear.map_or(0, |(_, p, _)|p*s.level);
        let mut sent = clear.map_or(0, |(_, _, q)|q);
        let mut b2b = false;
        if n>0 {
            s.streak += 1;
            if n == 4 || tspin != 0 {
                s.chain += 1;
                b2b = s.chain >= 2
            } else {
                s.chain = 0
            }
        } else {
            s.streak = 0
        }
        if b2b {
            points = points*3/2;
            sent += 1
        }
        let combo = s.streak-1;
        let combo_points = if combo >= 1 {
            50*combo*s.level
        } else {
            0
        };
        if combo >= 0 {
            sent += [0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5][(combo as usize).min(10)]
        }
        let perfect = n>0 && s.well.iter().all(|&r|r == 0);
        let perfect_points = if perfect {
            sent += 10;
            s.stats.perfect += 1;
            if n == 4 && b2b {
                3200*s.level
            } else {
                [0, 800, 1200, 1800, 2000][n]*s.level
            }
        } else {
            0
        };
        let gained = points+combo_points+perfect_points;
        s.score += gained;
        s.lines += n as i64;
        s.stats.sent += sent;
        s.stats.combo = s.stats.combo.max(combo);
        s.stats.chain = s.stats.chain.max(s.chain);
        out.push(format!("lock {} {} {} {} {} keys {} {} drop {} lines {} sent {} +{} total {}", s.pieces, KINDS[k]as char, STATES[p.s], p.x, p.y, s.operations, shortest.as_ref().map_or("-".into(), |v|v.len().to_string()), s.drop, n, sent, gained, s.score));
        if let Some(path) = shortest {
            if s.operations>path.len()as i64 {
                s.stats.faults += 1;
                out.push(format!("finesse {}", operation_string(&path)))
            }
        }
        if let Some((i, _, _)) = clear {
            s.stats.clears[i] += 1;
            let mut line = format!("clear {} {}", CLEAR[i], points);
            if b2b {
                line.push_str(" b2b")
            }
            if combo >= 1 {
                line.push_str(&format!(" combo {} {}", combo, combo_points))
            }
            if perfect {
                line.push_str(&format!(" perfect {}", perfect_points))
            }
            out.push(line)
        }
        let level = s.start_level+s.lines/10;
        if level>s.level {
            s.level = level;
            out.push(format!("level {}", level))
        }
        if lockout {
            self.over("lock out", out);
            return
        }
        let cancel = sent.min(self.s.pending());
        if cancel>0 {
            let mut remaining = cancel;
            while remaining>0 {
                let amount = remaining.min(self.s.pending[0]);
                remaining -= amount;
                self.s.pending[0] -= amount;
                if self.s.pending[0] == 0 {
                    self.s.pending.pop_front();
                }
            }
            self.s.stats.cancelled += cancel;
            out.push(format!("cancel {} pending {}", cancel, self.s.pending()))
        }
        if n == 0 {
            let mut risen = 0;
            while !self.s.pending.is_empty() && risen<8 {
                let m = self.s.pending[0].min(8-risen);
                let h = (self.s.random()%10+1)as usize;
                if !self.garbage(m as usize, h, out) {
                    return
                }
                risen += m;
                self.s.stats.received += m;
                self.s.pending[0] -= m;
                if self.s.pending[0] == 0 {
                    self.s.pending.pop_front();
                }
                out.push(format!("rise {} hole {} pending {}", m, h, self.s.pending()));
            }
        }
        self.s.used = false;
        let k = self.s.next();
        self.spawn(k, out);
        if !self.s.ended {
            self.start = self.s.clone()
        }
    }
    fn operate(&mut self, op: usize, out: &mut Vec<String>) {
        let success = if op<8 {
            self.s.operations += 1;
            if let Some((q, test)) = movement(&self.s.well, self.s.kind, self.s.p, op) {
                if op == 4 || op == 5 {
                    self.drop_points((self.s.p.y-q.y)as i64);
                    self.s.update(q, 1, 0);
                    self.s.fall = 0;
                    self.s.ground = 0
                } else {
                    self.s.update(q, if op >= 6 {
                        2
                    } else {
                        1
                    }, test);
                    if self.s.ground>0 && self.s.resets<15 {
                        self.s.ground = 0;
                        self.s.resets += 1
                    }
                }
                true
            } else {
                false
            }
        } else if op == 8 {
            let q = landing(&self.s.well, self.s.kind, self.s.p);
            let n = self.s.p.y-q.y;
            self.drop_points(2*n as i64);
            if n>0 {
                self.s.update(q, 1, 0)
            }
            self.lock(out);
            true
        } else if op == 9 {
            if movement(&self.s.well, self.s.kind, self.s.p, 4).is_none() {
                self.lock(out);
                true
            } else {
                false
            }
        } else if self.s.used {
            false
        } else {
            self.s.used = true;
            self.s.stats.holds += 1;
            let k = if let Some(k) = self.s.hold {
                k
            } else {
                self.s.next()
            };
            self.s.hold = Some(self.s.kind);
            self.spawn(k, out);
            true
        };
        if !success {
            out.push(format!("fail {}", OPS[op]))
        }
    }
    fn command(&mut self, c: &str, a: &[&str], out: &mut Vec<String>) {
        match c {
            "PRINT" => {
                let current = if self.s.ended {
                    Vec::new()
                } else {
                    cells(self.s.kind, self.s.p)
                };
                let ghost = if self.s.ended {
                    Vec::new()
                } else {
                    cells(self.s.kind, landing(&self.s.well, self.s.kind, self.s.p))
                };
                for r in (1..= 22).rev() {
                    let row: String = (1..= 10).map(|x|if self.s.well[r-1]&(1<<(x-1)) != 0 {
                        '#'
                    } else if current.contains(&(x as i32, r as i32)) {
                        '@'
                    } else if ghost.contains(&(x as i32, r as i32)) {
                        '+'
                    } else {
                        '.'
                    }).collect();
                    out.push(format!("{:2} {}", r, row))
                }
            }, "NEXT" => out.push(format!("hold {} next {}", self.s.hold.map_or('-'.to_string(), |k|(KINDS[k]as char).to_string()), self.s.queue.iter().take(5).map(|&k|KINDS[k]as char).collect::<String>())), "PREVIEW" => {
                let n = a[0].parse::<usize>().unwrap();
                let mut s = self.s.clone();
                while s.queue.len()<n {
                    s.bag()
                }
                out.push(format!("preview {}", s.queue.iter().take(n).map(|&k|KINDS[k]as char).collect::<String>()))
            }, "STATUS" => {
                let s = &self.s;
                out.push(format!("score {} level {} lines {} pieces {}", s.score, s.level, s.lines, s.pieces));
                out.push(format!("piece {} streak {} chain {} pending {}", if s.ended {
                    "-".into()
                } else {
                    format!("{} {} {} {}", KINDS[s.kind]as char, STATES[s.p.s], s.p.x, s.p.y)
                }, s.streak, s.chain, s.pending()))
            }, "ANALYZE" => {
                let (h, holes, bump, v) = analysis(&self.s.well, 0);
                out.push(format!("heights {}", h.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
                out.push(format!("holes {} bumpiness {} value {}", holes, bump, v))
            }, "ROW" => {
                let r = a[0].parse::<usize>().unwrap();
                let mut row = 0;
                for (i, c) in  a[1].bytes().enumerate() {
                    if c == b'#' {
                        row |= 1<<i
                    }
                }
                if cells(self.s.kind, self.s.p).iter().any(|&(x, y)|y == r as i32 && row&(1<<(x-1)) != 0) {
                    out.push("ERROR overlap".into())
                } else {
                    self.s.well[r-1] = row;
                    out.push("OK".into())
                }
            }, "GARBAGE" => {
                let n = a[0].parse::<usize>().unwrap();
                let h = a[1].parse().unwrap();
                if self.garbage(n, h, out) {
                    let p = self.s.p;
                    if let Some(q) = (0..= n).map(|j|Position {
                        y: p.y+j as i32, ..p
                    }).find(|&q|fits(&self.s.well, self.s.kind, q)) {
                        self.s.p = q;
                        out.push("OK".into())
                    } else {
                        self.over("top out", out)
                    }
                }
            }, "ATTACK" => {
                self.s.pending.push_back(a[0].parse().unwrap());
                out.push(format!("pending {}", self.s.pending()))
            }, "TICK" => {
                let n = a[0].parse::<usize>().unwrap();
                for _ in 0..n {
                    if self.s.ended {
                        break
                    }
                    if let Some((q, _)) = movement(&self.s.well, self.s.kind, self.s.p, 4) {
                        self.s.ground = 0;
                        self.s.fall += 1;
                        let g = if self.s.level <= 12 {
                            [60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2][self.s.level as usize-1]
                        } else {
                            1
                        };
                        if self.s.fall >= g {
                            self.s.update(q, 1, 0);
                            self.s.fall = 0
                        }
                    } else {
                        self.s.ground += 1;
                        if self.s.ground >= 30 {
                            self.lock(out)
                        }
                    }
                }
            }, "UNDO" => {
                if let Some(s) = self.history.pop() {
                    self.s = s.clone();
                    self.start = s;
                    out.push(format!("undo {} {}", self.s.pieces, KINDS[self.s.kind]as char))
                } else {
                    out.push("ERROR nothing to undo".into())
                }
            }, "SAVE" => {
                self.saves.insert(a[0].into(), Snapshot {
                    state: self.s.clone(), history: self.history.clone(), start: self.start.clone()
                });
                out.push("OK".into())
            }, "LOAD" => {
                if let Some(save) = self.saves.get(a[0]) {
                    self.s = save.state.clone();
                    self.history = save.history.clone();
                    self.start = save.start.clone();
                    out.push(format!("load {} {}", self.s.pieces, KINDS[self.s.kind]as char))
                } else {
                    out.push("ERROR unknown save".into())
                }
            }, "SPINS" => {
                let mut spins: BTreeMap<(i32, i32, usize), usize> = BTreeMap::new();
                if self.s.kind == 2 {
                    for (p, _) in  explore(&self.s.well, 2, self.s.p) {
                        for op in 6..8 {
                            if let Some((q, test)) = movement(&self.s.well, 2, p, op) {
                                if movement(&self.s.well, 2, q, 4).is_some() {
                                    continue
                                }
                                let ty = spin(&self.s.well, q, test);
                                if ty>0 {
                                    let key = (q.y, q.x, q.s);
                                    let old = spins.entry(key).or_insert(0);
                                    *old = (*old).max(ty)
                                }
                            }
                        }
                    }
                }
                for (&(y, x, s), &ty) in  &spins {
                    let p = Position {
                        s, x, y
                    };
                    let mut w = self.s.well;
                    let n = place(&mut w, 2, p);
                    let i = clear_type(ty, n).unwrap().0;
                    out.push(format!("spin {} {} {} {}", STATES[s], x, y, CLEAR[i]))
                }
                out.push(format!("spins {}", spins.len()))
            }, "HINT" => {
                let n = a[0].parse::<usize>().unwrap();
                for (i, c) in  self.s.candidates().iter().take(n).enumerate() {
                    out.push(format!("hint {} {} {} value {}", i+1, KINDS[c.kind]as char, operation_string(&c.ops), c.value))
                }
            }, "AUTO" => {
                let n = a[0].parse::<usize>().unwrap();
                for _ in 0..n {
                    if self.s.ended {
                        break
                    }
                    let candidates = self.s.candidates();
                    if let Some(c) = candidates.first() {
                        out.push(format!("auto {} {}", KINDS[c.kind]as char, operation_string(&c.ops)));
                        for &op in &c.ops {
                            if self.s.ended {
                                break
                            }
                            self.operate(op, out)
                        }
                    }
                }
            }, _ => {
            }
        }
    }
}
fn number(s: &str, lo: u64, hi: u64) -> bool {
    !s.is_empty() && s.bytes().all(|c|c.is_ascii_digit()) && (s.len() == 1 || !s.starts_with('0')) && s.parse::<u64>().is_ok_and(|n|n >= lo && n <= hi)
}
fn arguments(c: &str, a: &[&str]) -> bool {
    let one = |lo, hi|a.len() == 1 && number(a[0], lo, hi);
    match c {
        "NEW" => a.len() == 2 && number(a[0], 1, 2147483646) && number(a[1], 1, 15), "PREVIEW" => one(1, 14), "HINT" => one(1, 10), "AUTO" => one(1, 50), "ATTACK" => one(1, 20), "TICK" => one(1, 1000), "GARBAGE" => a.len() == 2 && number(a[0], 1, 10) && number(a[1], 1, 10), "ROW" => a.len() == 2 && number(a[0], 1, 22) && a[1].len() == 10 && a[1].bytes().all(|c|b"#.".contains(&c)) && a[1].contains('.'), "SAVE"|"LOAD" => a.len() == 1 && !a[0].is_empty() && a[0].len() <= 8 && a[0].bytes().all(|c|c.is_ascii_lowercase()), _ => a.is_empty()
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let commands = ["NEW", "PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "ROW", "GARBAGE", "ATTACK", "TICK", "UNDO", "SAVE", "LOAD", "SPINS", "HINT", "AUTO"];
    let mut game: Option<Game> = None;
    let mut serial = 0;
    let mut out = Vec::new();
    for line in input.lines().skip(1) {
        let w: Vec<_> = line.split_whitespace().collect();
        if w.is_empty() {
            continue
        }
        let c = w[0];
        let a = &w[1..];
        if commands.contains(&c) {
            if !arguments(c, a) {
                out.push("ERROR bad arguments".into());
                continue
            }
            if c == "NEW" {
                if let Some(g) = &game {
                    if !g.s.ended {
                        out.push("game stopped".into());
                        g.summary(&mut out)
                    }
                }
                serial += 1;
                let seed = a[0].parse().unwrap();
                let level = a[1].parse().unwrap();
                out.push(format!("game {} seed {} level {}", serial, seed, level));
                game = Some(Game::new(serial, seed, level));
                continue
            }
            let Some(g) = game.as_mut()else {
                out.push("ERROR no game".into());
                continue
            };
            if g.s.ended && !["PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD"].contains(&c) {
                out.push("ERROR game over".into());
                continue
            }
            g.command(c, a, &mut out);
        } else {
            if let Some(s) = w.iter().find(|s|!OPS.contains(s)) {
                out.push(format!("ERROR unknown {}", s));
                continue
            }
            let Some(g) = game.as_mut()else {
                out.push("ERROR no game".into());
                continue
            };
            if g.s.ended {
                out.push("ERROR game over".into());
                continue
            }
            for s in w {
                if g.s.ended {
                    break
                }
                g.operate(OPS.iter().position(|&op|op == s).unwrap(), &mut out)
            }
        }
    }
    if let Some(g) = &game {
        if !g.s.ended {
            out.push("game stopped".into());
            g.summary(&mut out)
        }
    }
    for line in out {
        println!("{}", line)
    }
}
