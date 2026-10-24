use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
const ALGORITHMS: [&str; 9] = ["FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ"];
const KEYS: [&str; 5] = ["cs", "q", "k", "s", "seed"];
const METRICS: [&str; 3] = ["turnaround", "waiting", "response"];
const EVENT_KINDS: [&str; 5] = ["PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE"];
type Params = BTreeMap<String, i64>;
fn check(ok: bool, reason: String) -> Result<(), String> {
    if ok {
        Ok(())
    } else {
        Err(reason)
    }
}
fn allowed(a: &str, k: &str) -> bool {
    k == "cs" || k == "q" && matches!(a, "RR" | "LOTTERY") || k == "k" && a == "PRIORITY" || k == "s" && a == "MLFQ" || k == "seed" && a == "LOTTERY"
}
fn valid(k: &str, v: i64) -> bool {
    match k {
        "cs" => v <= 5,
        "q" => (1..=20).contains(&v),
        "k" => (1..=50).contains(&v),
        "s" => v <= 500,
        "seed" => (1..=2147483646).contains(&v), _ => false
    }
}
fn decimal(n: i64, d: i64) -> String {
    let x = n * 100 / d;
    format!("{}.{:02}", x / 100, x % 100)
}
fn notation(p: &Params, a: Option<&str>) -> String {
    KEYS.iter().filter(|k| a.is_none_or(|a| allowed(a, k))).map(|k| format!("{}={}", k, p[*k])).collect::<Vec<_>>().join(" ")
}
fn row(cells: Vec<String>) -> String {
    cells.iter().enumerate().map(|(i, s)| if i == 0 {
        format!("{:<8}", s)
    } else {
        format!("{:>8}", s)
    }
    ).collect::<Vec<_>>().join(" ")
}
#[derive(Clone)]
struct Process {
    id: String,
    arrival: i64,
    priority: i64,
    deadline: Option<i64>,
    bursts: Vec<i64>,
}
impl Process {
    fn absolute(&self) -> i64 {
        self.arrival + self.deadline.unwrap_or(0)
    }
    fn describe(&self) -> String {
        format!("{} arrival={} priority={} deadline={} bursts={}", self.id, self.arrival, self.priority, self.deadline.map_or("none".into(), |d| d.to_string()), self.bursts.iter().enumerate().map(|(i, n)| format!("{}{}", if i % 2 == 0 {
            "C"
        } else {
            "I"
        }, n)).collect::<Vec<_>>().join(","))
    }
}
struct BurstRecord {
    length: i64,
    ready: i64,
    start: Option<i64>,
    end: i64,
    slices: i64,
}
struct Job {
    process: Process,
    state: &'static str,
    burst: usize,
    left: i64,
    effective: i64,
    wait: i64,
    level: usize,
    usage: i64,
    enqueued: i64,
    start: Option<i64>,
    finish: i64,
    records: Vec<BurstRecord>,
    timeline: String,
}
impl Job {
    fn new(p: Process) -> Self {
        Self {
            left: p.bursts[0], effective: p.priority, process: p, state: "FUTURE", burst: 0, wait: 0, level: 0, usage: 0, enqueued: 0, start: None, finish: 0, records: vec![], timeline: String::new()
        }
    }
    fn metrics(&self) -> [i64; 3] {
        [self.finish - self.process.arrival, self.finish - self.process.arrival - self.process.bursts.iter().sum::<i64>(), self.start.unwrap() - self.process.arrival]
    }
    fn missed(&self) -> bool {
        self.process.deadline.is_some() && self.finish > self.process.absolute()
    }
    fn advance(&mut self) {
        self.burst += 1;
        self.left = self.process.bursts[self.burst];
    }
}
struct Simulation {
    jobs: Vec<Job>,
    algo: String,
    p: Params,
    requested: Option<i64>,
    queues: [Vec<usize>; 3],
    cpu: &'static str,
    current: Option<usize>,
    previous: Option<usize>,
    switch_left: i64,
    run_length: i64,
    time: i64,
    random: i64,
    end: i64,
    switches: i64,
    events: Vec<String>,
    labels: Vec<String>,
    cpu_states: Vec<&'static str>,
    snapshot: Vec<String>,
    queue_lengths: Vec<i64>,
    counts: BTreeMap<String, i64>,
}
impl Simulation {
    fn new(processes: &BTreeMap<String, Process>, algo: &str, p: &Params, requested: Option<i64>) -> Self {
        let mut s = Self {
            jobs: processes.values().cloned().map(Job::new).collect(), algo: algo.into(), p: p.clone(), requested, queues: [vec![], vec![], vec![]], cpu: "IDLE", current: None, previous: None, switch_left: 0, run_length: 0, time: 0, random: p["seed"], end: 0, switches: 0, events: vec![], labels: vec![], cpu_states: vec![], snapshot: vec![], queue_lengths: vec![], counts: BTreeMap::new()
        };
        s.run();
        s
    }
    fn record(&mut self, kind: &str, details: String) {
        self.events.push(format!("{} {}{}", self.time, kind, if details.is_empty() {
            String::new()
        } else {
            " ".to_string() + &details
        }
        ));
        *self.counts.entry(kind.into()).or_default() += 1;
    }
    fn enqueue(&mut self, i: usize) {
        let j = &mut self.jobs[i];
        j.state = "READY";
        j.enqueued = self.time;
        self.queues[j.level].push(i);
    }
    fn release(&mut self) {
        self.cpu = "IDLE";
        self.current = None;
    }
    fn start(&mut self, i: usize) {
        self.cpu = "RUN";
        self.current = Some(i);
        self.run_length = 0;
        let j = &mut self.jobs[i];
        j.state = "RUN";
        j.start.get_or_insert(self.time);
        j.records.last_mut().unwrap().start.get_or_insert(self.time);
    }
    fn preempt(&self, i: usize) -> bool {
        let j = &self.jobs[i];
        match self.algo.as_str() {
            "SRTF" => self.queues[0].iter().any(|&i| self.jobs[i].left < j.left),
            "PRIORITY" => self.queues[0].iter().any(|&i| self.jobs[i].effective < j.effective),
            "EDF" => self.queues[0].iter().any(|&i| {
                let p = &self.jobs[i].process;
                p.deadline.is_some() && (j.process.deadline.is_none() || p.absolute() < j.process.absolute())
            }),
            "MLFQ" => self.queues[..j.level].iter().any(|q| !q.is_empty()), _ => false,
        }
    }
    fn choose(&mut self) -> usize {
        let q = &self.queues[0];
        let mut best = q[0];
        if self.algo == "LOTTERY" {
            self.random = self.random * 48271 % 2147483647;
            let r = self.random % q.iter().map(|&i| 10 - self.jobs[i].process.priority).sum::<i64>();
            let mut sum = 0;
            for &i in q {
                sum += 10 - self.jobs[i].process.priority;
                if sum > r {
                    return i;
                }
            }
        }
        for &i in &q[1..] {
            let j = &self.jobs[i];
            let b = &self.jobs[best];
            let better = match self.algo.as_str() {
                "SJF" | "SRTF" => j.left < b.left,
                "PRIORITY" => j.effective < b.effective,
                "HRRN" => (self.time - j.enqueued + j.left) * b.left > (self.time - b.enqueued + b.left) * j.left,
                "EDF" => j.process.deadline.is_some() && (b.process.deadline.is_none() || j.process.absolute() < b.process.absolute()), _ => false
            };
            if better {
                best = i;
            }
        }
        best
    }
    fn capture(&mut self) {
        let mut lines = vec![if self.cpu == "IDLE" {
            "CPU IDLE".into()
        } else {
            format!("CPU {} {}", self.cpu, self.jobs[self.current.unwrap()].process.id)
        }
        ];
        let text = |q: &[usize]| if q.is_empty() {
            "none".into()
        } else {
            q.iter().map(|&i| self.jobs[i].process.id.clone()).collect::<Vec<_>>().join(" ")
        };
        if self.algo == "MLFQ" {
            for i in 0..3 {
                lines.push(format!("QUEUE{} {}", i, text(&self.queues[i])));
            }
        } else {
            lines.push(format!("QUEUE {}", text(&self.queues[0])));
        }
        for j in &self.jobs {
            let mut line = match j.state {
                "FUTURE" => format!("{} FUTURE at={}", j.process.id, j.process.arrival),
                "DONE" => format!("{} DONE at={}", j.process.id, j.finish), _ => format!("{} {} burst={} left={}", j.process.id, j.state, j.burst + 1, j.left)
            };
            if !matches!(j.state, "FUTURE" | "DONE") {
                if self.algo == "PRIORITY" {
                    line += &format!(" prio={}", j.effective);
                }
                if self.algo == "MLFQ" {
                    line += &format!(" level={} used={}", j.level, j.usage);
                }
            }
            lines.push(line);
        }
        self.snapshot = lines;
    }
    fn run(&mut self) {
        loop {
            if self.algo == "PRIORITY" {
                for i in self.queues[0].clone() {
                    let j = &mut self.jobs[i];
                    j.wait += 1;
                    if j.wait == self.p["k"] {
                        j.wait = 0;
                        if j.effective > 0 {
                            j.effective -= 1;
                            let details = format!("{} {}", j.process.id, j.effective);
                            self.record("AGE", details);
                        }
                    }
                }
            }
            for i in 0..self.jobs.len() {
                if self.jobs[i].state == "IO" && self.jobs[i].left == 0 {
                    let j = &mut self.jobs[i];
                    j.advance();
                    j.records.push(BurstRecord {
                        length: j.left, ready: self.time, start: None, end: 0, slices: 0
                    });
                    self.enqueue(i);
                    self.record("IODONE", self.jobs[i].process.id.clone());
                }
            }
            for i in 0..self.jobs.len() {
                if self.jobs[i].state == "FUTURE" && self.jobs[i].process.arrival == self.time {
                    let j = &mut self.jobs[i];
                    j.records.push(BurstRecord {
                        length: j.left, ready: self.time, start: None, end: 0, slices: 0
                    });
                    self.enqueue(i);
                    self.record("ARRIVE", self.jobs[i].process.id.clone());
                }
            }
            if self.cpu == "SWITCH" && self.switch_left == 0 {
                let i = self.current.unwrap();
                self.start(i);
                self.record("START", self.jobs[i].process.id.clone());
            } else if self.cpu == "RUN" {
                let i = self.current.unwrap();
                let id = self.jobs[i].process.id.clone();
                if self.jobs[i].left == 0 && self.jobs[i].burst + 1 == self.jobs[i].process.bursts.len() {
                    self.jobs[i].state = "DONE";
                    self.jobs[i].finish = self.time;
                    self.record("DONE", id);
                    self.release();
                } else {
                    let j = &self.jobs[i];
                    let demoted = self.algo == "MLFQ" && j.level < 2 && j.usage == if j.level == 0 {
                        4
                    } else {
                        8
                    };
                    if demoted {
                        self.jobs[i].level += 1;
                        self.jobs[i].usage = 0;
                        self.record("DEMOTE", format!("{} {}", id, self.jobs[i].level));
                    }
                    if self.jobs[i].left == 0 {
                        self.jobs[i].advance();
                        self.jobs[i].state = "IO";
                        self.record("IO", format!("{} {}", id, self.jobs[i].left));
                        self.release();
                    } else if demoted {
                        self.enqueue(i);
                        self.release();
                    } else if matches!(self.algo.as_str(), "RR" | "LOTTERY") && self.run_length == self.p["q"] {
                        self.enqueue(i);
                        self.record("EXPIRE", id);
                        self.release();
                    } else if self.preempt(i) {
                        self.enqueue(i);
                        self.record("PREEMPT", id);
                        self.release();
                    }
                }
            }
            if self.jobs.iter().all(|j| j.state == "DONE") {
                break;
            }
            if self.algo == "MLFQ" && self.p["s"] > 0 && self.time > 0 && self.time % self.p["s"] == 0 {
                let merged = self.queues.iter().flatten().copied().collect();
                self.queues = [merged, vec![], vec![]];
                for j in &mut self.jobs {
                    j.level = 0;
                    j.usage = 0;
                }
                self.record("BOOST", String::new());
            }
            if self.cpu == "IDLE" && self.queues.iter().any(|q| !q.is_empty()) {
                let level = if self.algo == "MLFQ" {
                    self.queues.iter().position(|q| !q.is_empty()).unwrap()
                } else {
                    0
                };
                let i = if self.algo == "MLFQ" {
                    self.queues[level][0]
                } else {
                    self.choose()
                };
                self.queues[level].retain(|&j| j != i);
                let j = &mut self.jobs[i];
                j.effective = j.process.priority;
                j.wait = 0;
                j.records.last_mut().unwrap().slices += 1;
                let switched = Some(i) != self.previous;
                if switched {
                    self.switches += 1;
                }
                if switched && self.p["cs"] > 0 {
                    self.cpu = "SWITCH";
                    self.current = Some(i);
                    self.switch_left = self.p["cs"];
                    self.jobs[i].state = "SWITCH";
                    self.record("SWITCH", self.jobs[i].process.id.clone());
                } else {
                    self.start(i);
                    self.record("DISPATCH", self.jobs[i].process.id.clone());
                }
            }
            if Some(self.time) == self.requested {
                self.capture();
            }
            for j in &mut self.jobs {
                j.timeline.push(match j.state {
                    "READY" => '.',
                    "SWITCH" => 's',
                    "RUN" => '#',
                    "IO" => 'i', _ => '-'
                });
            }
            self.queue_lengths.push(self.queues.iter().map(|q| q.len() as i64).sum());
            self.cpu_states.push(self.cpu);
            if self.cpu == "RUN" {
                let i = self.current.unwrap();
                let j = &mut self.jobs[i];
                j.left -= 1;
                j.usage += 1;
                self.run_length += 1;
                self.previous = Some(i);
                self.labels.push(j.process.id.clone());
                if j.left == 0 {
                    j.records.last_mut().unwrap().end = self.time + 1;
                }
            } else if self.cpu == "SWITCH" {
                self.switch_left -= 1;
                self.labels.push("CS".into());
            } else {
                self.labels.push("IDLE".into());
            }
            for j in &mut self.jobs {
                if j.state == "IO" {
                    j.left -= 1;
                }
            }
            self.time += 1;
        }
        self.end = self.time;
        if self.requested.is_some() && self.snapshot.is_empty() {
            self.capture();
        }
    }
    fn totals(&self) -> [i64; 3] {
        std::array::from_fn(|i| self.jobs.iter().map(|j| j.metrics()[i]).sum())
    }
    fn averages(&self) -> Vec<String> {
        self.totals().iter().map(|&n| decimal(n, self.jobs.len() as i64)).collect()
    }
    fn util(&self) -> String {
        decimal(self.cpu_states.iter().filter(|&&s| s == "RUN").count() as i64 * 100, self.end)
    }
    fn missed(&self) -> i64 {
        self.jobs.iter().filter(|j| j.missed()).count() as i64
    }
    fn ticks(&self, a: usize, b: usize) -> (i64, i64, i64) {
        let s = &self.cpu_states[a..b];
        (s.iter().filter(|&&x| x == "RUN").count() as i64, s.iter().filter(|&&x| x == "SWITCH").count() as i64, s.iter().filter(|&&x| x == "IDLE").count() as i64)
    }
}
struct Scheduler {
    registry: BTreeMap<String, Process>,
    output: Vec<String>,
}
impl Scheduler {
    fn prepare(&self, words: &[&str], a: Option<&str>, preset: Option<&str>) -> Result<Params, String> {
        let mut p: Params = [ ("cs", 0), ("q", 4), ("k", 5), ("s", 0), ("seed", 1) ].into_iter().map(|(k, v)| (k.into(), v)).collect();
        let mut seen = BTreeSet::new();
        if let Some(k) = preset {
            seen.insert(k);
        }
        for word in words {
            let (k, v) = word.split_once('=').unwrap();
            let v: i64 = v.parse().unwrap();
            check(KEYS.contains(&k), format!("unknown key {}", k))?;
            check(a.is_none_or(|a| allowed(a, k)), format!("key {} not allowed for {}", k, a.unwrap_or("")))?;
            check(!seen.contains(k), format!("duplicate key {}", k))?;
            check(valid(k, v), format!("invalid {}", k))?;
            seen.insert(k);
            p.insert(k.into(), v);
        }
        check(!self.registry.is_empty(), "no processes".into())?;
        Ok(p)
    }
    fn algorithm(a: &str) -> Result<(), String> {
        check(ALGORITHMS.contains(&a), format!("unknown algorithm {}", a))
    }
    fn command(&mut self, w: &[&str]) -> Result<(), String> {
        let c = w[0];
        let num = |i: usize| w[i].parse::<i64>().unwrap();
        match c {
            "PROC" => {
                let id = w[1];
                check(!self.registry.contains_key(id), format!("duplicate process {}", id))?;
                check(self.registry.len() < 10, "too many processes".into())?;
                check(num(2) <= 200, format!("invalid arrival {}", id))?;
                check(num(3) <= 9, format!("invalid priority {}", id))?;
                let bursts: Vec<i64> = w[4..].iter().map(|s| s[1..].parse().unwrap()).collect();
                let valid_bursts = bursts.len() % 2 == 1
                    && w[4..].iter().enumerate().all(|(i, word)| {
                        let expected = if i % 2 == 0 { b'C' } else { b'I' };
                        word.as_bytes()[0] == expected && (1..=30).contains(&bursts[i])
                    });
                check(valid_bursts, format!("invalid bursts {}", id))?;
                self.output.push(format!("PROC {} cpu={} io={}", id, bursts.iter().step_by(2).sum::<i64>(), bursts.iter().skip(1).step_by(2).sum::<i64>()));
                self.registry.insert(id.into(), Process {
                    id: id.into(), arrival: num(2), priority: num(3), deadline: None, bursts
                });
                return Ok(());
            }
            "GEN" => {
                let ids: Vec<String> = (1..=num(2)).map(|i| format!("{}{}", w[1], i)).collect();
                for id in &ids {
                    check(!self.registry.contains_key(id), format!("duplicate process {}", id))?;
                }
                check(self.registry.len() + ids.len() <= 10, "too many processes".into())?;
                self.output.push(format!("GEN count={}", ids.len()));
                let mut x = num(3);
                let mut draw = |m: i64| {
                    x = x * 48271 % 2147483647;
                    x % m
                };
                for id in ids {
                    let arrival = draw(21);
                    let priority = draw(10);
                    let count = 1 + draw(3);
                    let mut bursts = vec![];
                    for i in 0..count {
                        if i > 0 {
                            bursts.push(1 + draw(8));
                        }
                        bursts.push(1 + draw(9));
                    }
                    let p = Process {
                        id: id.clone(), arrival, priority, deadline: None, bursts
                    };
                    self.output.push(p.describe());
                    self.registry.insert(id, p);
                }
                return Ok(());
            }
            "SETPRIO" | "DEADLINE" | "DROP" => {
                check(self.registry.contains_key(w[1]), format!("unknown process {}", w[1]))?;
                if c == "DROP" {
                    self.registry.remove(w[1]);
                    self.output.push(format!("DROP {}", w[1]));
                } else if c == "SETPRIO" {
                    check(num(2) <= 9, format!("invalid priority {}", w[1]))?;
                    self.registry.get_mut(w[1]).unwrap().priority = num(2);
                    self.output.push(format!("SETPRIO {} priority={}", w[1], num(2)));
                } else {
                    check(num(2) <= 1000, format!("invalid deadline {}", w[1]))?;
                    self.registry.get_mut(w[1]).unwrap().deadline = if num(2) == 0 {
                        None
                    } else {
                        Some(num(2))
                    };
                    self.output.push(format!("DEADLINE {} {}", w[1], if num(2) == 0 {
                        "none".into()
                    } else {
                        num(2).to_string()
                    }
                    ));
                }
                return Ok(());
            }
            "CLEAR" => {
                self.output.push(format!("CLEAR count={}", self.registry.len()));
                self.registry.clear();
                return Ok(());
            }
            "LIST" => {
                self.output.push(format!("LIST count={}", self.registry.len()));
                self.output.extend(self.registry.values().map(Process::describe));
                return Ok(());
            }
            _ => ()
        }
        if matches!(c, "COMPARE" | "RANK" | "DIFF") {
            let offset = if c == "COMPARE" {
                1
            } else if c == "RANK" {
                2
            } else {
                3
            };
            if c == "DIFF" {
                Self::algorithm(w[1])?;
                Self::algorithm(w[2])?;
            }
            if c == "RANK" {
                check(METRICS.contains(&w[1]) || ["end", "switches", "missed"].contains(&w[1]), format!("unknown metric {}", w[1]))?;
            }
            let p = self.prepare(&w[offset..], None, None)?;
            if c == "DIFF" {
                let a = Simulation::new(&self.registry, w[1], &p, None);
                let b = Simulation::new(&self.registry, w[2], &p, None);
                self.output.push(format!("DIFF {} {} {}", w[1], w[2], notation(&p, None)));
                let (mut wins, mut losses) = (0, 0);
                for (j, other) in a.jobs.iter().zip(&b.jobs) {
                    let x = j.metrics();
                    let y = other.metrics();
                    self.output.push(format!("{} {}", j.process.id, METRICS.iter().enumerate().map(|(i, m)| format!("{}={}/{}", m, x[i], y[i])).collect::<Vec<_>>().join(" ")));
                    if x[0] < y[0] {
                        wins += 1;
                    }
                    if x[0] > y[0] {
                        losses += 1;
                    }
                }
                self.output.push(format!("WINS {}={} {}={} ties={}", w[1], wins, w[2], losses, a.jobs.len() - wins - losses));
                return Ok(());
            }
            let sims: Vec<Simulation> = ALGORITHMS.iter().map(|a| Simulation::new(&self.registry, a, &p, None)).collect();
            self.output.push(if c == "COMPARE" {
                format!("COMPARE {}", notation(&p, None))
            } else {
                format!("RANK {} {}", w[1], notation(&p, None))
            });
            if c == "COMPARE" {
                self.output.push(row(["ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS"].iter().map(|s| s.to_string()).collect()));
                for (i, s) in sims.iter().enumerate() {
                    let mut cells = vec![ALGORITHMS[i].into()];
                    cells.extend(s.averages());
                    cells.extend([s.util(), s.end.to_string(), s.switches.to_string(), s.missed().to_string()]);
                    self.output.push(row(cells));
                }
                self.output.push(format!("BEST {}", METRICS.iter().enumerate().map(|(j, m)| {
                    let i = (0..9).min_by_key(|&i| sims[i].totals()[j]).unwrap();
                    format!("{}={}", m, ALGORITHMS[i])
                }
                ).collect::<Vec<_>>().join(" ")));
            } else {
                let metric = METRICS.iter().position(|&m| m == w[1]);
                let value = |i: usize| if let Some(j) = metric {
                    sims[i].totals()[j]
                } else if w[1] == "end" {
                    sims[i].end
                } else if w[1] == "switches" {
                    sims[i].switches
                } else {
                    sims[i].missed()
                };
                let mut order: Vec<usize> = (0..9).collect();
                order.sort_by_key(|&i| (value(i), i));
                for i in order {
                    let rank = 1 + (0..9).filter(|&j| value(j) < value(i)).count();
                    self.output.push(format!("{} {} {}", rank, ALGORITHMS[i], if metric.is_some() {
                        decimal(value(i), self.registry.len() as i64)
                    } else {
                        value(i).to_string()
                    }
                    ));
                }
            }
            return Ok(());
        }
        let a = w[1];
        Self::algorithm(a)?;
        let offset = if matches!(c, "SNAPSHOT" | "WINDOW") {
            3
        } else if c == "SWEEP" {
            5
        } else {
            2
        };
        if c == "WINDOW" {
            check((1..=1000).contains(&num(2)), "invalid window".into())?;
        }
        if c == "SWEEP" {
            check(KEYS.contains(&w[2]), format!("unknown key {}", w[2]))?;
            check(allowed(a, w[2]), format!("key {} not allowed for {}", w[2], a))?;
            check(num(3) <= num(4) && valid(w[2], num(3)) && valid(w[2], num(4)) && num(4) - num(3) <= 20, "invalid range".into())?;
        }
        let mut p = self.prepare(&w[offset..], Some(a), if c == "SWEEP" {
            Some(w[2])
        } else {
            None
        }
        )?;
        if c == "SWEEP" {
            self.output.push(format!("SWEEP {} {} {} {}", a, w[2], num(3), num(4)));
            let (mut best, mut value) = (i64::MAX, num(3));
            for v in num(3)..=num(4) {
                p.insert(w[2].into(), v);
                let s = Simulation::new(&self.registry, a, &p, None);
                let av = s.averages();
                self.output.push(format!("{} turnaround={} waiting={} response={} util={} end={} switches={}", notation(&p, Some(a)), av[0], av[1], av[2], s.util(), s.end, s.switches));
                if s.totals()[1] < best {
                    best = s.totals()[1];
                    value = v;
                }
            }
            self.output.push(format!("BEST {}={}", w[2], value));
            return Ok(());
        }
        let s = Simulation::new(&self.registry, a, &p, if c == "SNAPSHOT" {
            Some(num(2))
        } else {
            None
        });
        if c == "TIMELINE" {
            check(s.end <= 100, format!("too long {}", s.end))?;
        }
        self.output.push(format!("{} {} {}{}", c, a, notation(&p, Some(a)), match c {
            "TIMELINE" => format!(" end={}", s.end),
            "SNAPSHOT" => format!(" t={}", num(2)),
            "WINDOW" => format!(" width={}", num(2)), _ => String::new()
        }
        ));
        match c {
            "TRACE" => {
                self.output.extend(s.events.clone());
                self.output.push(format!("END {}", s.end));
            }
            "SNAPSHOT" => self.output.extend(s.snapshot.clone()),
            "TIMELINE" => {
                for j in &s.jobs {
                    self.output.push(format!("{:<8} {}", j.process.id, j.timeline));
                }
            }
            "BURSTS" => {
                for j in &s.jobs {
                    for (i, r) in j.records.iter().enumerate() {
                        self.output.push(format!("{} #{} len={} ready={} start={} end={} wait={} slices={}", j.process.id, i + 1, r.length, r.ready, r.start.unwrap(), r.end, r.end - r.ready - r.length, r.slices));
                    }
                }
            }
            "WINDOW" => {
                for start in (0..s.end as usize).step_by(num(2) as usize) {
                    let stop = (start + num(2) as usize).min(s.end as usize);
                    let (busy, sw, idle) = s.ticks(start, stop);
                    let mut counts: BTreeMap<&str, usize> = BTreeMap::new();
                    for i in start..stop {
                        if s.cpu_states[i] == "RUN" {
                            *counts.entry(&s.labels[i]).or_default() += 1;
                        }
                    }
                    let top = counts.iter().min_by_key(|(id, n)| (std::cmp::Reverse(**n), **id)).map_or("none", |(&id, _)| id);
                    self.output.push(format!("{}-{} busy={} switch={} idle={} util={} top={}", start, stop, busy, sw, idle, decimal(busy * 100, (stop - start) as i64), top));
                }
            }
            "STATS" => {
                for (i, name) in METRICS.iter().enumerate() {
                    let v: Vec<i64> = s.jobs.iter().map(|j| j.metrics()[i]).collect();
                    let mut sorted = v.clone();
                    sorted.sort();
                    let low = *sorted.first().unwrap();
                    let high = *sorted.last().unwrap();
                    let n = sorted.len();
                    let doubled = if n % 2 == 1 {
                        sorted[n / 2] * 2
                    } else {
                        sorted[n / 2 - 1] + sorted[n / 2]
                    };
                    self.output.push(format!("{} min={} ({}) max={} ({}) median={}.{} total={}", name, low, s.jobs[v.iter().position(|&x| x == low).unwrap()].process.id, high, s.jobs[v.iter().position(|&x| x == high).unwrap()].process.id, doubled / 2, doubled % 2 * 5, v.iter().sum::<i64>()));
                }
            }
            "RUN" => {
                let mut segments = vec![];
                let mut start = 0;
                for t in 1..=s.end as usize {
                    if t == s.end as usize || s.labels[t] != s.labels[start] {
                        segments.push(format!("[{}-{} {}]", start, t, s.labels[start]));
                        start = t;
                    }
                }
                for group in segments.chunks(8) {
                    self.output.push(format!("GANTT {}", group.join("")));
                }
                for j in &s.jobs {
                    let m = j.metrics();
                    let mut line = format!("{} arrival={} done={} turnaround={} waiting={} response={} slices={}", j.process.id, j.process.arrival, j.finish, m[0], m[1], m[2], j.records.iter().map(|r| r.slices).sum::<i64>());
                    if j.process.deadline.is_some() {
                        line += &format!(" deadline={} late={}", j.process.absolute(), (j.finish - j.process.absolute()).max(0));
                    }
                    self.output.push(line);
                }
                let av = s.averages();
                let (busy, sw, idle) = s.ticks(0, s.end as usize);
                self.output.push(format!("AVERAGE turnaround={} waiting={} response={}", av[0], av[1], av[2]));
                self.output.push(format!("CPU end={} busy={} switch={} idle={} switches={} util={}", s.end, busy, sw, idle, s.switches, s.util()));
                self.output.push(format!("QUEUE max={} avg={}", s.queue_lengths.iter().max().unwrap(), decimal(s.queue_lengths.iter().sum(), s.end)));
                self.output.push(format!("EVENTS {}", EVENT_KINDS.iter().map(|k| format!("{}={}", k.to_lowercase(), s.counts.get(*k).unwrap_or(&0))).collect::<Vec<_>>().join(" ")));
                self.output.push(format!("DEADLINE met={} missed={}", s.jobs.iter().filter(|j| j.process.deadline.is_some() && !j.missed()).count(), s.missed()));
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
    let n: usize = lines.next().unwrap().parse().unwrap();
    let mut s = Scheduler {
        registry: BTreeMap::new(), output: vec![]
    };
    for line in lines.take(n) {
        let w: Vec<&str> = line.split(' ').collect();
        if let Err(reason) = s.command(&w) {
            s.output.push(format!("ERROR {}", reason));
        }
    }
    println!("{}", s.output.join("\n"));
}
