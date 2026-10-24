use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const POLICIES: [&str; 10] = ["FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT"];
fn hex(x: usize) -> String { format!("0x{:X}", x) }
fn number(s: &str) -> usize { s.parse().unwrap() }
fn address(s: &str) -> usize { usize::from_str_radix(&s[2..], 16).unwrap() }
fn decimal(x: u64) -> String { format!("{}.{:02}", x / 100, x % 100) }
fn ratio(x: usize, y: usize) -> String { decimal(if y == 0 { 0 } else { (10000 * x / y) as u64 }) + "%" }
#[derive(Clone)]
struct Config {
    page: usize, frames: usize, tlb: usize, sets: usize, policy: String,
    local: bool, asid: bool, tick: usize, tau: usize, seed: u64,
}
impl Default for Config {
    fn default() -> Self {
        Self { page: 256, frames: 4, tlb: 4, sets: 1, policy: "FIFO".into(), local: false, asid: false, tick: 0, tau: 8, seed: 1 }
    }
}
impl Config {
    fn scope(&self) -> &str { if self.local { "LOCAL" } else { "GLOBAL" } }
    fn description(&self) -> String {
        format!("SYSTEM page={} frames={} tlb={} sets={} policy={} scope={} asid={} tick={} tau={} seed={}",
            self.page, self.frames, self.tlb, self.sets, self.policy, self.scope(), if self.asid { "ON" } else { "OFF" }, self.tick, self.tau, self.seed)
    }
}
fn settings(tokens: &[String]) -> Result<Config, String> {
    let mut c = Config::default();
    let keys = ["page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed"];
    let mut seen = BTreeSet::new();
    for token in &tokens[1..] {
        let (key, value) = token.split_once('=').unwrap();
        if !keys.contains(&key) { return Err(format!("unknown key {}", key)); }
        if !seen.insert(key) { return Err(format!("duplicate key {}", key)); }
        let valid = match key {
            "policy" => { c.policy = value.into(); POLICIES.contains(&value) }
            "scope" => { c.local = value == "LOCAL"; ["GLOBAL", "LOCAL"].contains(&value) }
            "asid" => { c.asid = value == "ON"; ["ON", "OFF"].contains(&value) }
            _ => {
                let n: u64 = value.parse().unwrap();
                let valid = match key {
                    "page" => (16..=4096).contains(&n) && n.is_power_of_two(),
                    "frames" => (1..=16).contains(&n),
                    "tlb" | "sets" => (1..=8).contains(&n),
                    "tick" => n <= 1000,
                    "tau" => (1..=1000).contains(&n),
                    _ => (1..=2147483646).contains(&n),
                };
                if valid {
                    match key {
                        "page" => c.page = n as usize,
                        "frames" => c.frames = n as usize,
                        "tlb" => c.tlb = n as usize,
                        "sets" => c.sets = n as usize,
                        "tick" => c.tick = n as usize,
                        "tau" => c.tau = n as usize,
                        _ => c.seed = n,
                    }
                }
                valid
            }
        };
        if !valid { return Err(format!("invalid {}", key)); }
    }
    if c.tlb % c.sets != 0 { return Err("invalid sets".into()); }
    Ok(c)
}
#[derive(Clone, Copy, PartialEq, Eq)]
struct Key { pid: usize, page: usize }
impl Key { fn label(self) -> String { format!("P{}:{}", self.pid, self.page) } }
#[derive(Default)]
struct Page {
    frame: Option<usize>, slot: Option<usize>, r: usize, m: usize,
    load: usize, last: usize, uses: usize, age: usize, references: usize,
    ro: bool, locked: bool, ever: bool,
}
struct Process {
    pages: Vec<Page>, history: Vec<usize>, accesses: usize, faults: usize,
    writebacks: usize, segfaults: usize, protfaults: usize, peak: usize, hand: usize, exited: bool,
}
impl Process {
    fn new(count: usize) -> Self {
        Self { pages: (0..count).map(|_| Page::default()).collect(), history: Vec::new(), accesses: 0, faults: 0,
            writebacks: 0, segfaults: 0, protfaults: 0, peak: 0, hand: 0, exited: false }
    }
    fn resident(&self) -> usize { self.pages.iter().filter(|p| p.frame.is_some()).count() }
}
#[derive(Clone, Copy)]
struct Access { pid: usize, op: char, address: usize }
#[derive(Clone, Copy)]
enum Event { Access(Access), Exit(usize), Clean, Lock(usize, usize, usize, bool) }
struct Simulation {
    c: Config, processes: BTreeMap<usize, Process>, frames: Vec<Option<Key>>,
    tlb: Vec<Vec<Key>>, swap: BTreeMap<usize, Key>, future: Vec<Access>, cursor: usize,
    time: usize, faults: usize, zero: usize, swapin: usize, tlbhits: usize, writebacks: usize, switches: usize,
    previous: Option<usize>, hand: usize, random: u64, fixed: bool, trace: bool, silent: bool,
    fault_history: Vec<bool>, log: Vec<Event>,
}
impl Simulation {
    fn new(c: Config, future: Vec<Access>, silent: bool) -> Self {
        let frames = vec![None; c.frames];
        let tlb = vec![Vec::new(); c.sets];
        let random = c.seed;
        Self { c, processes: BTreeMap::new(), frames, tlb, swap: BTreeMap::new(), future, cursor: 0,
            time: 0, faults: 0, zero: 0, swapin: 0, tlbhits: 0, writebacks: 0, switches: 0,
            previous: None, hand: 0, random, fixed: false, trace: false, silent, fault_history: Vec::new(), log: Vec::new() }
    }
    fn emit(&self, text: String) { if !self.silent { println!("{}", text); } }
    fn process(&self, pid: usize) -> Result<&Process, String> {
        let p = self.processes.get(&pid).ok_or_else(|| format!("unknown process {}", pid))?;
        if p.exited { return Err(format!("process {} exited", pid)); }
        Ok(p)
    }
    fn page(&self, key: Key) -> &Page { &self.processes[&key.pid].pages[key.page] }
    fn page_mut(&mut self, key: Key) -> &mut Page { &mut self.processes.get_mut(&key.pid).unwrap().pages[key.page] }
    fn quota(&self, pid: usize) -> usize {
        let rank = self.processes.keys().position(|&p| p == pid).unwrap();
        self.c.frames / self.processes.len() + usize::from(rank < self.c.frames % self.processes.len())
    }
    fn declare(&mut self, pid: usize, count: usize) -> Result<(), String> {
        if self.fixed { return Err("processes are fixed".into()); }
        if self.processes.contains_key(&pid) { return Err(format!("duplicate process {}", pid)); }
        if !(1..=256).contains(&count) { return Err("invalid page count".into()); }
        if self.processes.len() >= 8 || self.c.local && self.processes.len() == self.c.frames { return Err("too many processes".into()); }
        self.processes.insert(pid, Process::new(count));
        Ok(())
    }
    fn invalidate(&mut self, key: Key) { for set in &mut self.tlb { set.retain(|&p| p != key); } }
    fn write(&mut self, key: Key) {
        self.writebacks += 1;
        self.processes.get_mut(&key.pid).unwrap().writebacks += 1;
        self.page_mut(key).m = 0;
        if self.page(key).slot.is_none() {
            let mut slot = 0;
            while self.swap.contains_key(&slot) { slot += 1; }
            self.swap.insert(slot, key); self.page_mut(key).slot = Some(slot);
        }
    }
    fn next_use(&self, key: Key) -> usize {
        self.future.iter().enumerate().skip(self.cursor)
            .find(|(_, a)| a.pid == key.pid && a.address / self.c.page == key.page)
            .map_or(usize::MAX, |(i, _)| i)
    }
    fn choose(&mut self, mut candidates: Vec<usize>, pid: usize) -> usize {
        let unlocked: Vec<usize> = candidates.iter().copied().filter(|&f| !self.page(self.frames[f].unwrap()).locked).collect();
        if !unlocked.is_empty() { candidates = unlocked; }
        if ["FIFO", "LRU", "LFU", "NRU", "AGING", "OPT"].contains(&self.c.policy.as_str()) {
            candidates.sort_by(|&a, &b| {
                let x = self.page(self.frames[a].unwrap());
                let y = self.page(self.frames[b].unwrap());
                match self.c.policy.as_str() {
                    "FIFO" => x.load.cmp(&y.load),
                    "LRU" => x.last.cmp(&y.last),
                    "LFU" => (x.uses, x.load).cmp(&(y.uses, y.load)),
                    "NRU" => (2*x.r + x.m, a).cmp(&(2*y.r + y.m, b)),
                    "AGING" => (x.age, x.load).cmp(&(y.age, y.load)),
                    _ => self.next_use(self.frames[b].unwrap()).cmp(&self.next_use(self.frames[a].unwrap())).then(a.cmp(&b)),
                }
            });
            return candidates[0];
        }
        if self.c.policy == "RANDOM" {
            self.random = self.random * 48271 % 2147483647;
            return candidates[(self.random % candidates.len() as u64) as usize];
        }
        let h = if self.c.local { self.processes[&pid].hand } else { self.hand };
        candidates.sort_by_key(|&f| (f + self.c.frames - h) % self.c.frames);
        let mut chosen = None;
        if self.c.policy == "CLOCK" {
            while chosen.is_none() {
                for &f in &candidates {
                    let key = self.frames[f].unwrap();
                    if self.page(key).r == 0 { chosen = Some(f); break; }
                    self.page_mut(key).r = 0;
                }
            }
        } else if self.c.policy == "ECLOCK" {
            while chosen.is_none() {
                for &f in &candidates {
                    let p = self.page(self.frames[f].unwrap());
                    if p.r == 0 && p.m == 0 { chosen = Some(f); break; }
                }
                if chosen.is_some() { break; }
                for &f in &candidates {
                    let key = self.frames[f].unwrap();
                    if self.page(key).r == 0 && self.page(key).m == 1 { chosen = Some(f); break; }
                    self.page_mut(key).r = 0;
                }
            }
        } else {
            for &f in &candidates {
                let key = self.frames[f].unwrap();
                if self.page(key).r == 1 {
                    let time = self.time;
                    let p = self.page_mut(key); p.r = 0; p.last = time;
                } else if self.time - self.page(key).last > self.c.tau {
                    if self.page(key).m == 0 { chosen = Some(f); break; }
                    self.write(key);
                }
            }
            if chosen.is_none() {
                chosen = Some(candidates.iter().copied().find(|&f| self.page(self.frames[f].unwrap()).m == 0).unwrap_or(candidates[0]));
            }
        }
        let result = chosen.unwrap();
        let next = (result + 1) % self.c.frames;
        if self.c.local { self.processes.get_mut(&pid).unwrap().hand = next; } else { self.hand = next; }
        result
    }
    fn access(&mut self, a: Access) -> Result<(), String> {
        self.fixed = true; self.cursor += 1;
        let owner = self.process(a.pid)?;
        if a.address >= owner.pages.len() * self.c.page {
            self.processes.get_mut(&a.pid).unwrap().segfaults += 1;
            self.emit(format!("SEGFAULT P{} {}", a.pid, hex(a.address))); return Ok(());
        }
        let key = Key { pid: a.pid, page: a.address / self.c.page };
        if a.op == 'W' && self.page(key).ro {
            self.processes.get_mut(&a.pid).unwrap().protfaults += 1;
            self.emit(format!("PROTFAULT P{} {}", a.pid, hex(a.address))); return Ok(());
        }
        self.time += 1; self.processes.get_mut(&a.pid).unwrap().accesses += 1;
        let switched = self.previous.is_some_and(|pid| pid != a.pid);
        if switched {
            self.switches += 1;
            if !self.c.asid { for set in &mut self.tlb { set.clear(); } }
        }
        self.previous = Some(a.pid);
        let set = key.page % self.c.sets;
        let hit = self.tlb[set].iter().position(|&p| p == key);
        let mut fault = false;
        let mut result;
        if let Some(index) = hit {
            self.tlb[set].remove(index); self.tlbhits += 1; result = "TLBHIT".to_string();
        } else if self.page(key).frame.is_some() { result = "HIT".to_string(); }
        else {
            fault = true; self.faults += 1; self.processes.get_mut(&a.pid).unwrap().faults += 1;
            if self.page(key).slot.is_some() { self.swapin += 1; result = "FAULT SWAPIN".to_string(); }
            else { self.zero += 1; result = "FAULT ZERO".to_string(); }
            let mut frame = None;
            if !self.c.local || self.processes[&a.pid].resident() < self.quota(a.pid) {
                frame = self.frames.iter().position(Option::is_none);
            }
            if frame.is_none() {
                let candidates = self.frames.iter().enumerate().filter_map(|(f, key)| {
                    match key {
                        Some(p) if !self.c.local || p.pid == a.pid => Some(f),
                        _ => None,
                    }
                }).collect();
                let f = self.choose(candidates, a.pid); frame = Some(f);
                let victim = self.frames[f].unwrap();
                result += &format!(" evict={}", victim.label());
                self.invalidate(victim);
                if self.page(victim).m == 1 { self.write(victim); result += " writeback"; }
                self.page_mut(victim).frame = None;
            }
            let f = frame.unwrap(); self.frames[f] = Some(key);
            let time = self.time;
            let p = self.page_mut(key);
            p.frame = Some(f); p.load = time; p.uses = 0; p.m = 0; p.age = 0;
            let owner = self.processes.get_mut(&a.pid).unwrap();
            owner.peak = owner.peak.max(owner.resident());
        }
        if self.tlb[set].len() == self.c.tlb / self.c.sets { self.tlb[set].remove(0); }
        self.tlb[set].push(key);
        let time = self.time;
        let p = self.page_mut(key);
        p.r = 1; if a.op == 'W' { p.m = 1; }
        p.last = time; p.uses += 1; p.ever = true; p.references += 1;
        self.processes.get_mut(&a.pid).unwrap().history.push(key.page);
        self.fault_history.push(fault); self.log.push(Event::Access(a));
        let interrupt = self.c.tick > 0 && self.time % self.c.tick == 0;
        if interrupt {
            for key in self.frames.clone().into_iter().flatten() {
                let p = self.page_mut(key); p.age = p.age / 2 + 128 * p.r; p.r = 0;
            }
        }
        if self.trace {
            let f = self.page(key).frame.unwrap();
            self.emit(format!("t={} P{} {} {} page={} frame={} phys={} {}{}", self.time, a.pid, a.op, hex(a.address), key.page, f,
                hex(f * self.c.page + a.address % self.c.page), result, if switched { " switch" } else { "" }));
            if interrupt { self.emit(format!("t={} tick", self.time)); }
        }
        Ok(())
    }
    fn exit(&mut self, pid: usize) -> Result<(), String> {
        let count = self.process(pid)?.pages.len();
        let (mut freed, mut slots) = (0, 0);
        for page in 0..count {
            let key = Key { pid, page };
            if let Some(f) = self.page(key).frame {
                self.frames[f] = None; self.page_mut(key).frame = None; freed += 1;
            }
            self.invalidate(key);
            if let Some(slot) = self.page(key).slot {
                self.swap.remove(&slot); self.page_mut(key).slot = None; slots += 1;
            }
        }
        self.processes.get_mut(&pid).unwrap().exited = true; self.log.push(Event::Exit(pid));
        self.emit(format!("EXIT P{} freed={} slots={}", pid, freed, slots));
        Ok(())
    }
    fn attributes(&mut self, cmd: &str, pid: usize, first: usize, last: usize, ro: bool) -> Result<(), String> {
        let p = self.process(pid)?;
        if first > last || last >= p.pages.len() { return Err("invalid page range".into()); }
        for page in first..=last {
            let p = self.page_mut(Key { pid, page });
            if cmd == "PROTECT" { p.ro = ro; } else { p.locked = cmd == "LOCK"; }
        }
        if cmd != "PROTECT" { self.log.push(Event::Lock(pid, first, last, cmd == "LOCK")); }
        Ok(())
    }
    fn clean(&mut self) {
        let mut count = 0;
        for key in self.frames.clone().into_iter().flatten() {
            if self.page(key).m == 1 { self.write(key); count += 1; }
        }
        self.log.push(Event::Clean); self.emit(format!("CLEAN written={}", count));
    }
    fn rerun(&self, policy: &str, count: usize) -> Result<Self, String> {
        let mut c = self.c.clone(); c.policy = policy.into(); c.frames = count;
        let future = self.log.iter().filter_map(|e| if let Event::Access(a) = e { Some(*a) } else { None }).collect();
        let mut r = Self::new(c, future, true);
        for (&pid, p) in &self.processes { r.declare(pid, p.pages.len())?; }
        for event in &self.log {
            match *event {
                Event::Access(a) => r.access(a)?,
                Event::Exit(pid) => r.exit(pid)?,
                Event::Clean => r.clean(),
                Event::Lock(pid, first, last, locked) => r.attributes(if locked { "LOCK" } else { "UNLOCK" }, pid, first, last, false)?,
            }
        }
        Ok(r)
    }
    fn summary(&self) {
        self.emit(format!("SUMMARY policy={} scope={} time={}", self.c.policy, self.c.scope(), self.time));
        let seg: usize = self.processes.values().map(|p| p.segfaults).sum();
        let prot: usize = self.processes.values().map(|p| p.protfaults).sum();
        self.emit(format!("total faults={} zero={} swapin={} faultrate={} tlbhits={} tlbrate={} writebacks={} switches={} segfaults={} protfaults={}",
            self.faults, self.zero, self.swapin, ratio(self.faults, self.time), self.tlbhits, ratio(self.tlbhits, self.time), self.writebacks, self.switches, seg, prot));
        for (&pid, p) in &self.processes {
            self.emit(format!("P{} accesses={} faults={} writebacks={} segfaults={} protfaults={} resident={} peak={}{}{}", pid, p.accesses, p.faults,
                p.writebacks, p.segfaults, p.protfaults, p.resident(), p.peak,
                if self.c.local { format!(" quota={}", self.quota(pid)) } else { String::new() }, if p.exited { " exited" } else { "" }));
        }
    }
    fn frame_dump(&self) {
        self.emit(format!("FRAMES used={}/{}", self.frames.iter().flatten().count(), self.c.frames));
        for (f, key) in self.frames.iter().enumerate() {
            if let Some(key) = key {
                let p = self.page(*key);
                self.emit(format!("{} {} R={} M={} load={} last={} uses={} age={}{}", f, key.label(), p.r, p.m, p.load, p.last, p.uses, p.age, if p.locked { " locked" } else { "" }));
            } else { self.emit(format!("{} free", f)); }
        }
        if ["CLOCK", "ECLOCK", "WSCLOCK"].contains(&self.c.policy.as_str()) {
            if !self.c.local { self.emit(format!("hand={}", self.hand)); }
            else {
                let mut text = "hand".to_string();
                for (&pid, p) in &self.processes { text += &format!(" P{}={}", pid, p.hand); }
                self.emit(text);
            }
        }
    }
    fn page_table(&self, pid: usize) -> Result<(), String> {
        let p = self.process(pid)?;
        self.emit(format!("PAGETABLE P{} pages={} resident={}", pid, p.pages.len(), p.resident()));
        for (number, p) in p.pages.iter().enumerate().filter(|(_, p)| p.ever) {
            let info = if let Some(f) = p.frame { format!("frame={} R={} M={}", f, p.r, p.m) }
                else if let Some(slot) = p.slot { format!("swap={}", slot) } else { "zero".into() };
            self.emit(format!("{} {}{}{}", number, info, if p.ro { " RO" } else { "" }, if p.locked { " locked" } else { "" }));
        }
        Ok(())
    }
    fn compare(&self) -> Result<(), String> {
        self.emit(format!("COMPARE accesses={} frames={}", self.time, self.c.frames));
        let mut results = Vec::new();
        for (i, policy) in POLICIES.iter().enumerate() {
            let r = self.rerun(policy, self.c.frames)?;
            self.emit(format!("{} faults={} writebacks={} tlbhits={}", policy, r.faults, r.writebacks, r.tlbhits));
            results.push((r.faults, r.writebacks, i));
        }
        results.sort();
        self.emit("ranking ".to_string() + &results.iter().map(|x| POLICIES[x.2]).collect::<Vec<_>>().join(" "));
        Ok(())
    }
    fn execute(&mut self, t: &[String]) -> Result<(), String> {
        let cmd = t[0].as_str();
        if cmd.as_bytes()[0].is_ascii_digit() { return self.access(Access { pid: number(cmd), op: t[1].chars().next().unwrap(), address: address(&t[2]) }); }
        match cmd {
            "PROCESS" => self.declare(number(&t[1]), number(&t[2]))?,
            "EXIT" => self.exit(number(&t[1]))?,
            "PROTECT" | "LOCK" | "UNLOCK" => self.attributes(cmd, number(&t[1]), number(&t[2]), number(&t[3]), t.get(4).is_some_and(|s| s == "RO"))?,
            "TRACE" => self.trace = t[1] == "ON",
            "SUMMARY" => self.summary(),
            "FRAMES" => self.frame_dump(),
            "PAGETABLE" => self.page_table(number(&t[1]))?,
            "TLB" => {
                self.emit(format!("TLB used={}/{} sets={}", self.tlb.iter().map(Vec::len).sum::<usize>(), self.c.tlb, self.c.sets));
                for (i, set) in self.tlb.iter().enumerate() {
                    let mut text = format!("set {}:", i);
                    for &key in set.iter().rev() { text += &format!(" {}->{}", key.label(), self.page(key).frame.unwrap()); }
                    self.emit(text);
                }
            }
            "SWAP" => {
                self.emit(format!("SWAP used={}", self.swap.len()));
                for (&slot, &key) in &self.swap { self.emit(format!("{} {}", slot, key.label())); }
            }
            "CLEAN" => self.clean(),
            "COMPARE" => self.compare()?,
            "CURVE" => {
                let policy = t[1].as_str(); let lo = number(&t[2]); let hi = number(&t[3]);
                if !POLICIES.contains(&policy) { return Err("unknown policy".into()); }
                if lo < 1 || lo > hi || hi > 16 || self.c.local && lo < self.processes.len() { return Err("invalid frame range".into()); }
                self.emit(format!("CURVE {} frames={}..{}", policy, lo, hi));
                let mut previous = usize::MAX;
                for f in lo..=hi {
                    let value = self.rerun(policy, f)?.faults;
                    self.emit(format!("F={} faults={}{}", f, value, if value > previous { " ANOMALY" } else { "" })); previous = value;
                }
            }
            "EAT" => {
                let total = number(&t[1]) as u64 * self.time as u64 + number(&t[2]) as u64 * (2 * self.time - self.tlbhits) as u64
                    + number(&t[3]) as u64 * (self.swapin + self.writebacks) as u64;
                self.emit(if self.time == 0 { "EAT accesses=0".into() }
                    else { format!("EAT accesses={} total={} average={}", self.time, total, decimal(100 * total / self.time as u64)) });
            }
            "TIMELINE" => {
                let w = number(&t[1]);
                if w < 1 { return Err("invalid window".into()); }
                let mut text = format!("TIMELINE window={}", w);
                for chunk in self.fault_history.chunks(w) { text += &format!(" {}", chunk.iter().filter(|&&v| v).count()); }
                self.emit(text);
            }
            "WSET" => {
                let pid = number(&t[1]); let p = self.process(pid)?; let w = number(&t[2]);
                if w < 1 { return Err("invalid window".into()); }
                let pages: BTreeSet<usize> = p.history.iter().rev().take(w).copied().collect();
                let mut text = format!("WSET P{} window={} size={}", pid, w, pages.len());
                for page in pages { text += &format!(" {}", page); }
                self.emit(text);
            }
            "HOT" => {
                let pid = number(&t[1]); let p = self.process(pid)?; let k = number(&t[2]);
                if k < 1 { return Err("invalid count".into()); }
                let mut pages: Vec<_> = p.pages.iter().enumerate().filter(|(_, p)| p.references > 0).collect();
                pages.sort_by(|(a, x), (b, y)| y.references.cmp(&x.references).then(a.cmp(b)));
                let mut text = format!("HOT P{}", pid);
                for (number, p) in pages.into_iter().take(k) { text += &format!(" {}:{}", number, p.references); }
                self.emit(text);
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}
fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines(); let n = number(lines.next().unwrap());
    let mut commands: Vec<Vec<String>> = Vec::new();
    for _ in 0..n {
        let t: Vec<String> = lines.next().unwrap().split(' ').map(str::to_string).collect();
        if t[0] == "LOOP" {
            let start = address(&t[3]); let interval = number(&t[4]); let length = number(&t[5]); let repeats = number(&t[6]);
            for _ in 0..repeats {
                for j in 0..length { commands.push(vec![t[1].clone(), t[2].clone(), hex(start + j * interval)]); }
            }
        } else if t[0] == "RAND" {
            let lo = address(&t[2]); let hi = address(&t[3]); let count = number(&t[4]); let rate = number(&t[6]) as u64;
            let mut x: u64 = t[5].parse().unwrap();
            for _ in 0..count {
                x = x * 48271 % 2147483647; let a = lo + (x % (hi - lo) as u64) as usize;
                x = x * 48271 % 2147483647;
                commands.push(vec![t[1].clone(), if x % 100 < rate { "W".into() } else { "R".into() }, hex(a)]);
            }
        } else { commands.push(t); }
    }
    let mut simulation: Option<Simulation> = None;
    for (i, t) in commands.iter().enumerate() {
        let result = if t[0] == "SYSTEM" {
            simulation = None;
            match settings(t) {
                Err(error) => Err(error),
                Ok(c) => {
                    let future = commands[i + 1..].iter().take_while(|t| t[0] != "SYSTEM")
                        .filter(|t| t[0].as_bytes()[0].is_ascii_digit())
                        .map(|t| Access { pid: number(&t[0]), op: t[1].chars().next().unwrap(), address: address(&t[2]) }).collect();
                    println!("{}", c.description()); simulation = Some(Simulation::new(c, future, false)); Ok(())
                }
            }
        } else if let Some(s) = &mut simulation { s.execute(t) }
        else { Err("no system".into()) };
        if let Err(error) = result { println!("ERROR {}", error); }
    }
}
