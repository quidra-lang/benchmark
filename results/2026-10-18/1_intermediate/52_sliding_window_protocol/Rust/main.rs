use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};

const KEYS: [&str; 22] = ["PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY", "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"];
fn fixed(numerator: i64, denominator: i64, digits: usize) -> String {
    let scale = if digits == 2 { 100 } else { 10 };
    let value = if denominator == 0 { 0 } else { numerator * scale / denominator };
    format!("{}.{:0width$}", value / scale, value % scale, width = digits)
}
fn stamp(tick: i32) -> String { if tick < 0 { "-".into() } else { tick.to_string() } }
struct Config {
    name: String,
    protocol: String,
    trace: String,
    n: usize,
    w: i32,
    k: i32,
    timeout: i32,
    delay: i32,
    interval: i32,
    limit: i32,
    dupack: i32,
    nak: bool,
    backoff: bool,
    congestion: bool,
    unsafe_window: bool,
    random: Option<(i64, i32, i32)>,
    lost_data: BTreeSet<i32>,
    lost_control: BTreeSet<i32>,
    corrupt_data: BTreeSet<i32>,
    corrupt_control: BTreeSet<i32>,
    delay_data: BTreeMap<i32, i32>,
    delay_control: BTreeMap<i32, i32>,
    snapshots: BTreeSet<i32>,
}
fn validate(name: &str, lines: &[Vec<&str>]) -> Result<Config, String> {
    let mut values = BTreeMap::<&str, Vec<&str>>::new();
    for line in lines {
        let key = line[0];
        let Some(index) = KEYS.iter().position(|k| *k == key) else { return Err(format!("unknown key {key}")); };
        if values.contains_key(key) { return Err(format!("duplicate key {key}")); }
        let count = line.len() - 1;
        if if key == "RANDOM" { count != 3 } else if index >= 15 { count == 0 } else { count != 1 } {
            return Err(format!("wrong number of values for {key}"));
        }
        values.insert(key, line[1..].to_vec());
    }
    for key in &KEYS[..6] { if !values.contains_key(key) { return Err(format!("missing key {key}")); } }
    for (index, key) in KEYS.iter().enumerate() {
        let Some(v) = values.get(key) else { continue; };
        let valid = match index {
            0 => ["SW", "GBN", "SR"].contains(&v[0]),
            9..=12 => ["ON", "OFF"].contains(&v[0]),
            13 => ["ALL", "SENDER", "RECEIVER", "NONE"].contains(&v[0]),
            14 => {
                let seed: i64 = v[0].parse().unwrap();
                let loss: i64 = v[1].parse().unwrap(); let corruption: i64 = v[2].parse().unwrap();
                (1..=2147483646).contains(&seed) && loss >= 0 && corruption >= 0 && loss + corruption <= 100
            }
            15..=21 => {
                let mut seen = BTreeSet::new();
                let mut valid = true;
                for value in v {
                    let parts: Vec<&str> = value.split(':').collect();
                    let number: i32 = parts[0].parse().unwrap();
                    let (low, high) = if index == 21 { (0, 2000) } else { (1, 9999) };
                    if !(low..=high).contains(&number) || !seen.insert(number) { valid = false; }
                    if index == 19 || index == 20 {
                        let extra: i32 = parts[1].parse().unwrap(); if !(1..=50).contains(&extra) { valid = false; }
                    }
                }
                valid
            }
            _ => {
                let number: i32 = v[0].parse().unwrap();
                let low = if index == 6 { 0 } else { 1 };
                let high = match index { 1 => 60, 2 => 32, 3 => 6, 4 => 50, 7 => 2000, _ => 10 };
                (low..=high).contains(&number)
            }
        };
        if !valid { return Err(format!("bad value for {key}")); }
    }
    let get = |key: &str, fallback: &str| values.get(key).map_or(fallback, |v| v[0]).to_string();
    let number = |key, fallback| get(key, fallback).parse::<i32>().unwrap();
    let protocol = get("PROTOCOL", "").to_string();
    let w = number("WINDOW", "0"); let k = number("SEQBITS", "0");
    let unsafe_window = get("UNSAFE", "OFF") == "ON";
    if protocol == "SR" && values.contains_key("DUPACK") { return Err("DUPACK not supported for SR".into()); }
    let limit = if protocol == "SW" { 1 } else if protocol == "GBN" { (1 << k) - 1 } else { 1 << (k - 1) };
    if w > limit && !(unsafe_window && protocol != "SW") { return Err(format!("window {w} exceeds limit {limit} for {protocol}")); }
    let set = |key| values.get(key).map_or_else(BTreeSet::new, |v| v.iter().map(|s| s.parse().unwrap()).collect());
    let delays = |key| values.get(key).map_or_else(BTreeMap::new, |v| v.iter().map(|s| {
        let (a, b) = s.split_once(':').unwrap(); (a.parse().unwrap(), b.parse().unwrap())
    }).collect());
    let lost_data: BTreeSet<i32> = set("LOSEDATA"); let lost_control: BTreeSet<i32> = set("LOSECTRL");
    let corrupt_data: BTreeSet<i32> = set("CORRUPTDATA"); let corrupt_control: BTreeSet<i32> = set("CORRUPTCTRL");
    if let Some(i) = lost_data.intersection(&corrupt_data).next() { return Err(format!("data #{i} both lost and corrupted")); }
    if let Some(i) = lost_control.intersection(&corrupt_control).next() { return Err(format!("control #{i} both lost and corrupted")); }
    Ok(Config {
        name: name.into(), protocol, trace: get("TRACE", "ALL").into(), n: number("FRAMES", "0") as usize, w, k,
        timeout: number("TIMEOUT", "0"), delay: number("DELAY", "0"), interval: number("INTERVAL", "0"),
        limit: number("MAXTICKS", "1000"), dupack: number("DUPACK", "0"), nak: get("NAK", "OFF") == "ON",
        backoff: get("BACKOFF", "OFF") == "ON", congestion: get("CONGESTION", "OFF") == "ON", unsafe_window,
        random: values.get("RANDOM").map(|v| (v[0].parse().unwrap(), v[1].parse().unwrap(), v[2].parse().unwrap())),
        lost_data, lost_control, corrupt_data, corrupt_control, delay_data: delays("DELAYDATA"), delay_control: delays("DELAYCTRL"), snapshots: set("SNAPSHOT"),
    })
}
#[derive(Clone)]
struct Event {
    arrival: i32,
    number: i32,
    value: i32,
    outcome: i32,
    nak: bool,
}
struct Summary {
    name: String,
    protocol: String,
    status: &'static str,
    delivered: i64,
    data: i64,
    completion: i64,
    order: usize,
}
struct Simulation<'a> {
    c: &'a Config,
    output: Vec<String>,
    data_events: Vec<Event>,
    control_events: Vec<Event>,
    queue: VecDeque<usize>,
    buffer: BTreeMap<i32, i32>,
    acknowledged: Vec<bool>,
    timers: Vec<i32>,
    tx: Vec<i32>,
    first: Vec<i32>,
    delivered_at: Vec<i32>,
    acked_at: Vec<i32>,
    tick: i32,
    base: usize,
    high: usize,
    next: usize,
    duration: i32,
    timer: i32,
    duplicates: i32,
    receiver: i32,
    cwnd: i32,
    threshold: i32,
    credit: i32,
    random: i64,
    nak_sent: bool,
    data: i32,
    control: i32,
    resent: i32,
    naks: i32,
    timeouts: i32,
    fast: i32,
    lost_data: i32,
    lost_control: i32,
    corrupt_data: i32,
    corrupt_control: i32,
    delivered: i32,
    errors: i32,
    discarded: i32,
    max_buffer: usize,
    latency: i32,
}
impl<'a> Simulation<'a> {
    fn new(c: &'a Config) -> Self {
        Self { c, output: Vec::new(), data_events: Vec::new(), control_events: Vec::new(), queue: VecDeque::new(), buffer: BTreeMap::new(),
            acknowledged: vec![false; c.n], timers: vec![-1; c.n], tx: vec![0; c.n], first: vec![-1; c.n], delivered_at: vec![-1; c.n], acked_at: vec![-1; c.n],
            tick: 0, base: 0, high: 0, next: 0, duration: c.timeout, timer: -1, duplicates: 0, receiver: 0, cwnd: 1, threshold: c.w, credit: 0,
            random: c.random.map_or(0, |v| v.0), nak_sent: false, data: 0, control: 0, resent: 0, naks: 0, timeouts: 0, fast: 0,
            lost_data: 0, lost_control: 0, corrupt_data: 0, corrupt_control: 0, delivered: 0, errors: 0, discarded: 0, max_buffer: 0, latency: 0 }
    }
    fn sr(&self) -> bool { self.c.protocol == "SR" }
    fn modulus(&self) -> i32 { 1 << self.c.k }
    fn effective(&self) -> usize { (if self.c.congestion { self.c.w.min(self.cwnd) } else { self.c.w }) as usize }
    fn log(&mut self, side: &str, text: String) {
        if self.c.trace == "ALL" || self.c.trace == side || side == "ALWAYS" { self.output.push(format!("{} {text}", self.tick)); }
    }
    fn outcome(&mut self, data: bool, number: i32) -> i32 {
        let mut outcome = 0;
        if let Some((_, loss, corruption)) = self.c.random {
            self.random = self.random * 48271 % 2147483647;
            let value = (self.random % 100) as i32;
            outcome = if value < loss { 1 } else if value < loss + corruption { 2 } else { 0 };
        }
        if (if data { &self.c.lost_data } else { &self.c.lost_control }).contains(&number) { outcome = 1; }
        if (if data { &self.c.corrupt_data } else { &self.c.corrupt_control }).contains(&number) { outcome = 2; }
        outcome
    }
    fn send_control(&mut self, nak: bool, value: i32) {
        self.control += 1; if nak { self.naks += 1; }
        self.log("RECEIVER", format!("{} a={value} #{}", if nak { "NAK" } else { "ACK" }, self.control));
        let outcome = self.outcome(false, self.control);
        self.control_events.push(Event { arrival: self.tick + self.c.delay + self.c.delay_control.get(&self.control).copied().unwrap_or(0), number: self.control, value, outcome, nak });
    }
    fn deliver(&mut self, payload: i32) {
        if payload == self.receiver {
            self.log("RECEIVER", format!("DELIVER f={}", self.receiver)); self.delivered += 1;
            let frame = payload as usize;
            if self.delivered_at[frame] < 0 { self.delivered_at[frame] = self.tick; }
            self.latency += self.tick - self.first[frame];
        } else {
            self.log("RECEIVER", format!("DELIVER f={} wrong={payload}", self.receiver)); self.errors += 1;
        }
        self.receiver += 1; self.nak_sent = false;
    }
    fn discard(&mut self, sequence: i32) { self.discarded += 1; self.log("RECEIVER", format!("DISCARD seq={sequence}")); }
    fn receive(&mut self, e: Event) {
        if e.outcome != 0 {
            if e.outcome == 1 { self.lost_data += 1; } else { self.corrupt_data += 1; }
            self.log("RECEIVER", format!("{} data #{}", if e.outcome == 1 { "LOST" } else { "CORRUPT" }, e.number)); return;
        }
        let sequence = e.value % self.modulus();
        self.log("RECEIVER", format!("RECV seq={sequence} #{}", e.number));
        if !self.sr() {
            if sequence == self.receiver % self.modulus() { self.deliver(e.value); self.send_control(false, sequence); }
            else {
                self.discard(sequence);
                if self.c.nak && !self.nak_sent { self.send_control(true, self.receiver % self.modulus()); self.nak_sent = true; }
                else if self.receiver > 0 { self.send_control(false, (self.receiver - 1) % self.modulus()); }
            }
            return;
        }
        let offset = (sequence - self.receiver).rem_euclid(self.modulus());
        let position = self.receiver + offset;
        if offset < self.c.w {
            if self.buffer.contains_key(&position) { self.discard(sequence); self.send_control(false, sequence); }
            else if offset == 0 {
                self.deliver(e.value);
                while let Some(payload) = self.buffer.remove(&self.receiver) { self.deliver(payload); }
                self.send_control(false, sequence);
            } else {
                self.buffer.insert(position, e.value); self.max_buffer = self.max_buffer.max(self.buffer.len());
                self.log("RECEIVER", format!("BUFFER f={position}")); self.send_control(false, sequence);
                if self.c.nak && !self.nak_sent { self.send_control(true, self.receiver % self.modulus()); self.nak_sent = true; }
            }
        } else {
            self.discard(sequence);
            if (self.receiver - sequence).rem_euclid(self.modulus()) <= self.c.w { self.send_control(false, sequence); }
        }
    }
    fn go_back(&mut self) { self.next = self.base; self.timer = -1; self.duplicates = 0; }
    fn increase(&mut self, count: usize) {
        if !self.c.congestion { return; }
        for _ in 0..count {
            if self.cwnd >= self.c.w { break; }
            if self.cwnd < self.threshold { self.cwnd += 1; }
            else { self.credit += 1; if self.credit == self.cwnd { self.cwnd += 1; self.credit = 0; } }
        }
    }
    fn decrease(&mut self, timeout: bool) {
        if self.c.congestion { self.threshold = (self.cwnd / 2).max(1); self.cwnd = if timeout { 1 } else { self.threshold }; self.credit = 0; }
    }
    fn cwnd_line(&mut self, old: (i32, i32)) {
        if self.c.congestion && old != (self.cwnd, self.threshold) { self.log("SENDER", format!("CWND {} ssthresh={}", self.cwnd, self.threshold)); }
    }
    fn control(&mut self, e: Event) {
        let kind = if e.nak { "NAK" } else { "ACK" };
        if e.outcome != 0 {
            if e.outcome == 1 { self.lost_control += 1; } else { self.corrupt_control += 1; }
            self.log("SENDER", format!("{} {} #{}", if e.outcome == 1 { "LOST" } else { "CORRUPT" }, kind.to_lowercase(), e.number)); return;
        }
        let old = (self.cwnd, self.threshold); let old_base = self.base;
        let frame = self.base + (e.value - self.base as i32).rem_euclid(self.modulus()) as usize;
        let accepted = if self.sr() { frame < self.high && !self.acknowledged[frame] } else if e.nak { frame <= self.high } else { frame < self.high };
        if accepted {
            if self.sr() {
                self.timers[frame] = -1;
                if e.nak { if !self.queue.contains(&frame) { self.queue.push_back(frame); } }
                else {
                    self.acknowledged[frame] = true; self.queue.retain(|f| *f != frame);
                    if self.acked_at[frame] < 0 { self.acked_at[frame] = self.tick; }
                    while self.base < self.high && self.acknowledged[self.base] { self.base += 1; }
                    self.increase(1);
                }
            } else {
                self.base = frame + usize::from(!e.nak); self.increase(self.base - old_base);
                for f in old_base..self.base { if self.acked_at[f] < 0 { self.acked_at[f] = self.tick; } }
            }
            if self.base > old_base { self.duration = self.c.timeout; self.duplicates = 0; }
            if !self.sr() {
                if e.nak { self.go_back(); } else { self.next = self.next.max(self.base); self.timer = if self.base == self.next { -1 } else { self.tick + self.duration }; }
            }
            if e.nak { self.decrease(false); }
            self.log("SENDER", format!("GOT{kind} a={} #{} base={}", e.value, e.number, self.base));
        } else {
            self.log("SENDER", format!("OLD{kind} a={} #{}", e.value, e.number));
            if !self.sr() && !e.nak && self.c.dupack > 0 && self.base >= 1 && e.value == (self.base as i32 - 1) % self.modulus() {
                self.duplicates += 1;
                if self.duplicates == self.c.dupack { self.fast += 1; self.log("SENDER", format!("FASTRETX f={}", self.base)); self.go_back(); self.decrease(false); }
            }
        }
        self.cwnd_line(old);
    }
    fn timeout(&mut self, frame: usize) {
        let old = (self.cwnd, self.threshold);
        self.timeouts += 1; self.log("SENDER", format!("TIMEOUT f={frame}"));
        if self.sr() { self.timers[frame] = -1; if !self.queue.contains(&frame) { self.queue.push_back(frame); } } else { self.go_back(); }
        if self.c.backoff { self.duration = (self.duration * 2).min(self.c.timeout * 8); }
        self.decrease(true); self.cwnd_line(old);
    }
    fn send(&mut self, frame: usize) {
        self.data += 1; let retry = self.tx[frame] > 0;
        if retry { self.resent += 1; } else { self.first[frame] = self.tick; }
        self.tx[frame] += 1;
        self.log("SENDER", format!("{} f={frame} seq={} #{}", if retry { "RESEND" } else { "SEND" }, frame as i32 % self.modulus(), self.data));
        let outcome = self.outcome(true, self.data);
        self.data_events.push(Event { arrival: self.tick + self.c.delay + self.c.delay_data.get(&self.data).copied().unwrap_or(0), number: self.data, value: frame as i32, outcome, nak: false });
        if self.sr() { self.timers[frame] = self.tick + self.duration; } else if self.timer < 0 { self.timer = self.tick + self.duration; }
    }
    fn snapshot(&mut self) {
        let mut sender = String::new(); let mut receiver = String::new();
        for f in 0..self.c.n {
            sender.push(if if self.sr() { self.acknowledged[f] } else { f < self.base } { 'A' }
                else if if self.sr() { self.queue.contains(&f) } else { self.next <= f && f < self.high } { 'R' }
                else if if self.sr() { f < self.high } else { f < self.next } { 'O' }
                else if f < self.base + self.effective() { 'W' } else { '.' });
            receiver.push(if (f as i32) < self.receiver { 'D' } else if self.sr() && self.buffer.contains_key(&(f as i32)) { 'B' }
                else if if self.sr() { (f as i32) < self.receiver + self.c.w } else { f as i32 == self.receiver } { 'W' } else { '.' });
        }
        self.log("ALWAYS", format!("SNAPSHOT sender={sender} receiver={receiver}"));
    }
    fn run(mut self, order: usize) -> (Summary, Vec<String>) {
        let c = self.c;
        self.output.push(format!("config: {} n={} w={} k={} T={} d={}", c.protocol, c.n, c.w, c.k, c.timeout, c.delay));
        let on = |v| if v { "on" } else { "off" };
        let random = c.random.map_or("off".into(), |(s, p, r)| format!("{s}/{p}/{r}"));
        self.output.push(format!("options: interval={} limit={} dupack={} nak={} backoff={} congestion={} unsafe={} trace={} random={random}", c.interval, c.limit,
            if c.dupack == 0 { "off".into() } else { c.dupack.to_string() }, on(c.nak), on(c.backoff), on(c.congestion), on(c.unsafe_window), c.trace.to_lowercase()));
        let mut complete = false;
        for tick in 0..=c.limit {
            self.tick = tick;
            let events: Vec<Event> = self.data_events.iter().filter(|e| e.arrival == tick).cloned().collect();
            for e in events { self.receive(e); }
            let events: Vec<Event> = self.control_events.iter().filter(|e| e.arrival == tick).cloned().collect();
            for e in events { self.control(e); }
            complete = self.base == c.n;
            if !complete {
                if self.sr() { for frame in self.base..self.high { if self.timers[frame] == tick { self.timeout(frame); } } }
                else if self.timer == tick { self.timeout(self.base); }
                if self.sr() {
                    if let Some(frame) = self.queue.pop_front() { self.send(frame); }
                    else if self.high < c.n && self.high < self.base + self.effective() && self.high as i32 * c.interval <= tick {
                        let frame = self.high; self.high += 1; self.send(frame);
                    }
                } else if self.next < c.n && self.next < self.base + self.effective() && (self.next < self.high || self.next as i32 * c.interval <= tick) {
                    let frame = self.next; self.next += 1; self.high = self.high.max(self.next); self.send(frame);
                }
            }
            if c.snapshots.contains(&tick) { self.snapshot(); }
            if complete || tick == c.limit { self.log("ALWAYS", if complete { "DONE".into() } else { "ABORT".into() }); break; }
        }
        for f in 0..c.n { self.output.push(format!("frame {f}: seq={} tx={} first={} delivered={} acked={}", f as i32 % self.modulus(), self.tx[f], stamp(self.first[f]), stamp(self.delivered_at[f]), stamp(self.acked_at[f]))); }
        self.output.push(format!("totals: data={} resent={} control={} nak={} timeouts={} fastretx={}", self.data, self.resent, self.control, self.naks, self.timeouts, self.fast));
        self.output.push(format!("channel: lost_data={} lost_ctrl={} corrupt_data={} corrupt_ctrl={}", self.lost_data, self.lost_control, self.corrupt_data, self.corrupt_control));
        self.output.push(format!("receiver: delivered={} errors={} discarded={} max_buffer={}", self.delivered, self.errors, self.discarded, self.max_buffer));
        self.output.push(format!("result: completion={} goodput={} efficiency={}% utilization={}% latency={}",
            if complete { self.tick.to_string() } else { "-".into() }, if complete { fixed(self.delivered as i64, self.tick as i64, 2) } else { "-".into() },
            fixed(self.delivered as i64 * 100, self.data as i64, 1), fixed(self.data as i64 * 100, self.tick as i64 + 1, 1),
            if self.delivered == 0 { "-".into() } else { fixed(self.latency as i64, self.delivered as i64, 2) }));
        (Summary { name: c.name.clone(), protocol: c.protocol.clone(), status: if complete { "complete" } else { "aborted" }, delivered: self.delivered as i64, data: self.data as i64, completion: self.tick as i64, order }, self.output)
    }
}
fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines(); let count: usize = lines.next().unwrap().parse().unwrap();
    let mut output = Vec::new(); let mut results = Vec::new();
    for order in 0..count {
        let name = lines.next().unwrap().split_whitespace().nth(1).unwrap();
        let mut settings = Vec::new();
        for line in lines.by_ref() { if line == "END" { break; } settings.push(line.split_whitespace().collect()); }
        output.push(format!("== {name} =="));
        match validate(name, &settings) {
            Ok(config) => { let (summary, timeline) = Simulation::new(&config).run(order); results.push(summary); output.extend(timeline); }
            Err(message) => {
                output.push(format!("error: {message}"));
                results.push(Summary { name: name.into(), protocol: String::new(), status: "invalid", delivered: 0, data: 0, completion: 0, order });
            }
        }
    }
    output.push("== ranking ==".into());
    let mut completed: Vec<&Summary> = results.iter().filter(|r| r.status == "complete").collect();
    completed.sort_by(|a, b| (b.delivered * a.completion).cmp(&(a.delivered * b.completion))
        .then_with(|| (b.delivered * a.data).cmp(&(a.delivered * b.data))).then(a.order.cmp(&b.order)));
    for (rank, r) in completed.iter().enumerate() { output.push(format!("{}. {} {} goodput={} efficiency={}%", rank + 1, r.name, r.protocol, fixed(r.delivered, r.completion, 2), fixed(r.delivered * 100, r.data, 1))); }
    for r in &results { if r.status != "complete" { output.push(format!("- {} {}", r.name, r.status)); } }
    output.push("== protocols ==".into());
    for protocol in ["SW", "GBN", "SR"] {
        let runs: Vec<&&Summary> = completed.iter().filter(|r| r.protocol == protocol).collect();
        if runs.is_empty() { continue; }
        let delivered: i64 = runs.iter().map(|r| r.delivered).sum();
        let ticks: i64 = runs.iter().map(|r| r.completion).sum(); let data: i64 = runs.iter().map(|r| r.data).sum();
        output.push(format!("{protocol}: runs={} goodput={} efficiency={}%", runs.len(), fixed(delivered, ticks, 2), fixed(delivered * 100, data, 1)));
    }
    println!("{}", output.join("\n"));
}
