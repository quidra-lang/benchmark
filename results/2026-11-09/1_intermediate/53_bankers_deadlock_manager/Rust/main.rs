use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, BufRead};

type Vector = Vec<i32>;
#[derive(Clone)]
struct Process { max: Vector, allocation: Vector, created: usize }
#[derive(Clone)]
struct Waiting { id: i32, vector: Vector, since: usize }
#[derive(Clone)]
struct Event { time: usize, kind: usize, id: i32, vector: Vector, wait: usize }
#[derive(Clone, Default)]
struct State {
    total: Vector,
    available: Vector,
    processes: BTreeMap<i32, Process>,
    queue: Vec<Waiting>,
    history: Vec<Event>,
}
const KINDS: [&str; 7] = ["granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"];
fn vector(v: &[i32]) -> String { format!("({})", v.iter().map(i32::to_string).collect::<Vec<_>>().join(",")) }
fn list(ids: &[i32]) -> String { ids.iter().map(|id| format!("P{id}")).collect::<Vec<_>>().join(" ") }
fn le(a: &[i32], b: &[i32]) -> bool { a.iter().zip(b).all(|(x, y)| x <= y) }
fn add(a: &[i32], b: &[i32]) -> Vector { a.iter().zip(b).map(|(x, y)| x + y).collect() }
fn sub(a: &[i32], b: &[i32]) -> Vector { a.iter().zip(b).map(|(x, y)| x - y).collect() }
fn need(p: &Process) -> Vector { sub(&p.max, &p.allocation) }
fn check(s: &State, detect: bool, trace: bool) -> (Vec<i32>, Vec<i32>) {
    let mut work = s.available.clone();
    let idle: Vec<i32> = s.processes.iter().filter(|(_, p)| detect && p.allocation.iter().all(|x| *x == 0)).map(|(id, _)| *id).collect();
    let mut left: Vec<i32> = s.processes.keys().filter(|id| !idle.contains(id)).copied().collect();
    let mut sequence = Vec::new();
    let tag = if detect { "[detect]" } else { "[safety]" };
    if trace {
        print!("{tag} start work={}", vector(&work));
        if !idle.is_empty() { print!(" idle {}", list(&idle)); }
        println!();
    }
    loop {
        let next = left.iter().position(|id| {
            let request = if detect { s.queue.iter().find(|q| q.id == *id).map(|q| q.vector.clone()).unwrap_or(vec![0; work.len()]) } else { need(&s.processes[id]) };
            le(&request, &work)
        });
        let Some(index) = next else { break };
        let id = left.remove(index);
        work = add(&work, &s.processes[&id].allocation);
        sequence.push(id);
        if trace { println!("{tag} P{id} can finish, work={}", vector(&work)); }
    }
    if trace && !left.is_empty() { println!("{tag} stuck work={} remaining {}", vector(&work), list(&left)); }
    (sequence, left)
}
struct Manager {
    state: State,
    snapshots: BTreeMap<String, State>,
    mode: String,
    policy: String,
    trace: bool,
    auto: bool,
    time: usize,
}
impl Manager {
    fn blocked(&self, id: i32) -> Option<usize> { self.state.queue.iter().position(|q| q.id == id) }
    fn reject(&self, id: i32, v: &[i32]) -> Option<String> {
        if self.blocked(id).is_some() { return Some(format!("process P{id} is blocked")); }
        if v.iter().all(|x| *x == 0) { return Some("zero vector".into()); }
        let p = &self.state.processes[&id];
        if !le(v, &need(p)) { return Some("request exceeds need".into()); }
        if self.mode == "ORDER" {
            if let Some(last) = p.allocation.iter().rposition(|x| *x > 0) {
                if v[..=last].iter().any(|x| *x > 0) { return Some("resource order violation".into()); }
            }
        }
        None
    }
    fn decision(&self, id: i32, v: &[i32], trace: bool) -> (Option<&'static str>, Vec<i32>) {
        if !le(v, &self.state.available) { return (Some("insufficient resources"), vec![]); }
        if self.mode != "AVOID" { return (None, vec![]); }
        let mut candidate = self.state.clone();
        candidate.available = sub(&candidate.available, v);
        let p = candidate.processes.get_mut(&id).unwrap();
        p.allocation = add(&p.allocation, v);
        let (sequence, left) = check(&candidate, false, trace);
        (if left.is_empty() { None } else { Some("unsafe state") }, sequence)
    }
    fn record(&mut self, kind: usize, id: i32, v: Vector, wait: usize) {
        self.state.history.push(Event { time: self.time, kind, id, vector: v, wait });
    }
    fn allocate(&mut self, id: i32, v: &[i32]) {
        self.state.available = sub(&self.state.available, v);
        let p = self.state.processes.get_mut(&id).unwrap();
        p.allocation = add(&p.allocation, v);
    }
    fn retry(&mut self) {
        let mut index = 0;
        while index < self.state.queue.len() {
            let q = self.state.queue[index].clone();
            if self.decision(q.id, &q.vector, self.trace).0.is_some() { index += 1; continue; }
            self.allocate(q.id, &q.vector);
            self.state.queue.remove(index);
            println!("unblocked P{} {}", q.id, vector(&q.vector));
            self.record(2, q.id, q.vector, self.time - q.since);
        }
    }
    fn terminate(&mut self, id: i32, kind: usize, retry: bool) {
        let p = self.state.processes.remove(&id).unwrap();
        self.state.available = add(&self.state.available, &p.allocation);
        self.state.queue.retain(|q| q.id != id);
        println!("{} P{id} released {}", KINDS[kind], vector(&p.allocation));
        self.record(kind, id, p.allocation, 0);
        if retry { self.retry(); }
    }
    fn sequences(&self, limit: usize) {
        if self.state.processes.is_empty() { println!("safe sequences: no processes"); return; }
        fn visit(s: &State, path: &mut Vec<i32>, left: Vec<i32>, work: Vector, limit: usize, count: &mut usize, rows: &mut Vec<String>) {
            if left.is_empty() {
                *count += 1;
                if rows.len() < limit { rows.push(list(path)); }
                return;
            }
            for id in &left {
                if !le(&need(&s.processes[id]), &work) { continue; }
                path.push(*id);
                visit(s, path, left.iter().filter(|x| *x != id).copied().collect(), add(&work, &s.processes[id].allocation), limit, count, rows);
                path.pop();
            }
        }
        let mut count = 0;
        let mut rows = vec![];
        visit(&self.state, &mut vec![], self.state.processes.keys().copied().collect(), self.state.available.clone(), limit, &mut count, &mut rows);
        println!("safe sequences: {count}");
        for row in rows { println!("{row}"); }
    }
    fn victims(&self) {
        let dead = check(&self.state, true, false).1;
        if dead.is_empty() { println!("no deadlock"); return; }
        let mut sets: Vec<Vec<i32>> = (1..(1usize << dead.len())).map(|mask| dead.iter().enumerate().filter(|(i, _)| mask & (1 << i) != 0).map(|(_, id)| *id).collect()).collect();
        sets.sort_by_key(|ids| (ids.len(), ids.iter().map(|id| self.state.processes[id].allocation.iter().sum::<i32>()).sum::<i32>(), ids.clone()));
        for ids in sets {
            let mut candidate = self.state.clone();
            for id in &ids {
                let p = candidate.processes.remove(id).unwrap();
                candidate.available = add(&candidate.available, &p.allocation);
                candidate.queue.retain(|q| q.id != *id);
            }
            if check(&candidate, true, false).1.is_empty() { println!("victims: {}", list(&ids)); break; }
        }
    }
    fn graph(&self, resource: bool) {
        let s = &self.state;
        if resource && s.total.iter().any(|x| *x != 1) { println!("error: not single-instance"); return; }
        let mut edges: BTreeMap<i32, Vec<(usize, i32)>> = s.processes.keys().map(|id| (*id, vec![])).collect();
        if resource {
            for j in 0..s.total.len() {
                for (id, p) in &s.processes {
                    if p.allocation[j] > 0 { println!("assign {} -> P{id}", (b'A' + j as u8) as char); }
                }
            }
            for id in s.processes.keys() {
                if let Some(q) = s.queue.iter().find(|q| q.id == *id) {
                    for j in 0..s.total.len() {
                        if q.vector[j] == 0 { continue; }
                        println!("request P{id} -> {}", (b'A' + j as u8) as char);
                        for (other, p) in &s.processes {
                            if p.allocation[j] > 0 { edges.get_mut(id).unwrap().push((j, *other)); }
                        }
                    }
                }
            }
            for (id, p) in &s.processes {
                let q = s.queue.iter().find(|q| q.id == *id);
                for (j, n) in need(p).iter().enumerate() {
                    if *n > 0 && q.map_or(true, |q| q.vector[j] == 0) { println!("claim P{id} -> {}", (b'A' + j as u8) as char); }
                }
            }
        } else {
            let mut count = 0;
            for id in s.processes.keys() {
                let Some(q) = s.queue.iter().find(|q| q.id == *id) else { continue };
                for (other, p) in &s.processes {
                    if other == id { continue; }
                    let labels: Vec<String> = (0..s.total.len()).filter(|j| q.vector[*j] > s.available[*j] && p.allocation[*j] > 0).map(|j| ((b'A' + j as u8) as char).to_string()).collect();
                    if labels.is_empty() { continue; }
                    count += 1;
                    println!("P{id} -> P{other} on {}", labels.join(","));
                    edges.get_mut(id).unwrap().push((0, *other));
                }
            }
            if count == 0 { println!("no wait edges"); }
        }
        fn visit(start: i32, at: i32, edges: &BTreeMap<i32, Vec<(usize, i32)>>, resource: bool, seen: &mut BTreeSet<i32>, path: Vec<String>, any: &mut bool) {
            for (kind, next) in &edges[&at] {
                let mut text = path.clone();
                if resource { text.push(((b'A' + *kind as u8) as char).to_string()); }
                text.push(format!("P{next}"));
                if *next == start && (resource || seen.len() >= 2) { println!("cycle: {}", text.join(" -> ")); *any = true; }
                else if *next > start && !seen.contains(next) {
                    seen.insert(*next);
                    visit(start, *next, edges, resource, seen, text, any);
                    seen.remove(next);
                }
            }
        }
        let mut any = false;
        for id in s.processes.keys() { visit(*id, *id, &edges, resource, &mut BTreeSet::from([*id]), vec![format!("P{id}")], &mut any); }
        if !any { println!("no cycles"); }
    }
    fn table(&self) {
        let s = &self.state;
        let widths: Vec<usize> = s.total.iter().map(|x| x.to_string().len()).collect();
        let names = widths.iter().enumerate().map(|(j, w)| format!("{:>width$}", (b'A' + j as u8) as char, width = *w)).collect::<Vec<_>>().join(" ");
        let columns: Vec<usize> = [10, 3, 4, 7].iter().map(|w| (*w).max(names.len())).collect();
        let form = |v: &[i32]| v.iter().enumerate().map(|(j, x)| format!("{x:>width$}", width = widths[j])).collect::<Vec<_>>().join(" ");
        let row = |head: &str, cells: &[String]| {
            let mut text = format!("{head:<9}");
            for i in 0..4 { text.push_str(&format!("  {:<width$}", cells.get(i).map_or("", |x| x.as_str()), width = columns[i])); }
            println!("{}", text.trim_end());
        };
        row("Process", &["Allocation".into(), "Max".into(), "Need".into(), "Request".into()]);
        row("", &vec![names; 4]);
        for (id, p) in &s.processes {
            let request = s.queue.iter().find(|q| q.id == *id).map(|q| q.vector.clone()).unwrap_or(vec![0; s.total.len()]);
            row(&format!("P{id}"), &[form(&p.allocation), form(&p.max), form(&need(p)), form(&request)]);
        }
        row("Available", &[form(&s.available)]);
        row("Total", &[form(&s.total)]);
        println!("blocked queue: {}", if s.queue.is_empty() { "empty".into() } else { s.queue.iter().map(|q| format!("P{} {} since t={}", q.id, vector(&q.vector), q.since)).collect::<Vec<_>>().join(", ") });
    }
    fn execute(&mut self, a: &[&str]) -> Result<(), String> {
        let cmd = a[0];
        match cmd {
            "RESOURCES" => {
                let v: Vector = a[1..].iter().map(|x| x.parse().unwrap()).collect();
                self.state = State { total: v.clone(), available: v.clone(), ..State::default() };
                println!("resources {}", vector(&v));
            }
            "MODE" | "POLICY" | "TRACE" | "AUTODETECT" => {
                match cmd { "MODE" => self.mode = a[1].into(), "POLICY" => self.policy = a[1].into(), "TRACE" => self.trace = a[1] == "ON", _ => self.auto = a[1] == "ON" }
                println!("{} {}", cmd.to_lowercase(), a[1]);
            }
            "SNAPSHOT" => { self.snapshots.insert(a[1].into(), self.state.clone()); println!("saved {}", a[1]); }
            "RESTORE" => {
                self.state = self.snapshots.get(a[1]).ok_or_else(|| format!("unknown snapshot {}", a[1]))?.clone();
                println!("restored {}", a[1]);
            }
            "STATE" => self.table(),
            "GRAPH" | "WAITGRAPH" => self.graph(cmd == "GRAPH"),
            "VICTIMS" => self.victims(),
            "SEQUENCES" => self.sequences(a[1].parse().unwrap()),
            "SAFE" => {
                if self.state.processes.is_empty() { println!("safe: no processes"); }
                else {
                    let (seq, left) = check(&self.state, false, self.trace);
                    if left.is_empty() { println!("safe: {}", list(&seq)); } else { println!("unsafe: {} cannot finish", list(&left)); }
                }
            }
            "DETECT" => {
                let left = check(&self.state, true, self.trace).1;
                if left.is_empty() { println!("no deadlock"); } else { println!("deadlocked: {}", list(&left)); }
            }
            "RECOVER" => {
                let mut count = 0;
                loop {
                    let dead = check(&self.state, true, self.trace).1;
                    if dead.is_empty() { break; }
                    if a.len() > 1 {
                        count += dead.len();
                        for id in dead { self.terminate(id, 5, false); }
                        self.retry();
                        break;
                    }
                    let id = *dead.iter().max_by_key(|id| {
                        let p = &self.state.processes[*id];
                        let rank = match self.policy.as_str() { "ALLOC" => -p.allocation.iter().sum::<i32>(), "NEED" => need(p).iter().sum::<i32>(), _ => p.created as i32 };
                        (rank, **id)
                    }).unwrap();
                    self.terminate(id, 5, true);
                    count += 1;
                }
                if count == 0 { println!("no deadlock"); } else { println!("recovered: {count} aborted"); }
            }
            "DEFICIT" => {
                let mut values = vec![];
                for j in 0..self.state.total.len() {
                    let bound: i32 = self.state.processes.values().map(|p| need(p)[j]).sum();
                    let mut value = "-".to_string();
                    for x in 0..=bound {
                        let mut candidate = self.state.clone(); candidate.available[j] += x;
                        if check(&candidate, false, false).1.is_empty() { value = x.to_string(); break; }
                    }
                    values.push(value);
                }
                println!("deficit: ({})", values.join(","));
            }
            "HISTORY" => {
                let events: Vec<&Event> = self.state.history.iter().filter(|e| a.len() == 1 || a[1] == KINDS[e.kind] || a[1] == e.id.to_string()).collect();
                if events.is_empty() { println!("no events"); }
                for e in events {
                    print!("t={} {} P{} {}", e.time, KINDS[e.kind], e.id, vector(&e.vector));
                    if e.kind == 2 { print!(" waited {}", e.wait); }
                    println!();
                }
            }
            "STATS" => {
                for j in 0..self.state.total.len() {
                    let total = self.state.total[j];
                    let used = total - self.state.available[j];
                    let percent = used * 1000 / total;
                    let requested: i32 = self.state.queue.iter().map(|q| q.vector[j]).sum();
                    println!("{}: allocated {used}/{total} ({}.{}%), requested {requested}", (b'A' + j as u8) as char, percent / 10, percent % 10);
                }
                let counts: Vec<usize> = (0..7).map(|k| self.state.history.iter().filter(|e| e.kind == k).count()).collect();
                println!("events: {}", (0..7).map(|k| format!("{} {}", KINDS[k], counts[k])).collect::<Vec<_>>().join(", "));
                let total: usize = self.state.history.iter().filter(|e| e.kind == 2).map(|e| e.wait).sum();
                if counts[2] == 0 { println!("waits: none"); }
                else { let average = total * 100 / counts[2]; println!("waits: {} unblocked, total {total}, average {}.{:02}", counts[2], average / 100, average % 100); }
            }
            _ => self.process_command(a)?,
        }
        Ok(())
    }
    fn process_command(&mut self, a: &[&str]) -> Result<(), String> {
        let cmd = a[0];
        let resource = cmd == "ADD" || cmd == "REMOVE";
        let has_vector = resource || matches!(cmd, "PROCESS" | "CLAIM" | "REQUEST" | "WHATIF" | "RELEASE");
        let id: i32 = if resource { 0 } else { a[1].parse().unwrap() };
        let v: Vector = if has_vector { a[if resource { 1 } else { 2 }..].iter().map(|x| x.parse().unwrap()).collect() } else { vec![0; self.state.total.len()] };
        if has_vector && v.len() != self.state.total.len() { return Err("wrong vector length".into()); }
        if !resource && cmd != "PROCESS" && !self.state.processes.contains_key(&id) { return Err(format!("unknown process P{id}")); }
        if cmd == "PROCESS" {
            if self.state.processes.contains_key(&id) { return Err(format!("duplicate process P{id}")); }
            if !le(&v, &self.state.total) { return Err("max exceeds total".into()); }
            self.state.processes.insert(id, Process { max: v.clone(), allocation: vec![0; v.len()], created: self.time });
            println!("process P{id} max {}", vector(&v));
            return Ok(());
        }
        if cmd == "REQUEST" || cmd == "WHATIF" {
            if let Some(reason) = self.reject(id, &v) {
                if cmd == "REQUEST" { return Err(reason); }
                println!("whatif P{id} {}: rejected ({reason})", vector(&v));
                return Ok(());
            }
            let (reason, seq) = self.decision(id, &v, self.trace);
            if cmd == "WHATIF" {
                match reason {
                    Some(r) => println!("whatif P{id} {}: blocked ({r})", vector(&v)),
                    None => println!("whatif P{id} {}: granted{}", vector(&v), if self.mode == "AVOID" { format!(", safe sequence {}", list(&seq)) } else { String::new() }),
                }
            } else if let Some(reason) = reason {
                self.state.queue.push(Waiting { id, vector: v.clone(), since: self.time });
                println!("blocked P{id} {}: {reason}", vector(&v));
                self.record(1, id, v, 0);
                if self.auto {
                    let dead = check(&self.state, true, self.trace).1;
                    if !dead.is_empty() { println!("deadlock detected: {}", list(&dead)); }
                }
            } else {
                self.allocate(id, &v);
                println!("granted P{id} {}", vector(&v)); self.record(0, id, v, 0);
            }
            return Ok(());
        }
        if !resource && cmd != "ABORT" && cmd != "CANCEL" && self.blocked(id).is_some() { return Err(format!("process P{id} is blocked")); }
        match cmd {
            "FINISH" | "ABORT" => self.terminate(id, if cmd == "FINISH" { 4 } else { 5 }, true),
            "CANCEL" => {
                let index = self.blocked(id).ok_or_else(|| format!("process P{id} is not blocked"))?;
                let q = self.state.queue.remove(index);
                println!("cancelled P{id} {}", vector(&q.vector)); self.record(6, id, q.vector, 0);
            }
            "MAXGRANT" => {
                let mut answer = vec![0; self.state.total.len()];
                for j in 0..answer.len() {
                    for x in (1..=need(&self.state.processes[&id])[j]).rev() {
                        let mut request = vec![0; answer.len()]; request[j] = x;
                        if self.reject(id, &request).is_none() && self.decision(id, &request, false).0.is_none() { answer[j] = x; break; }
                    }
                }
                println!("maxgrant P{id}: {}", vector(&answer));
            }
            "CLAIM" => {
                if !le(&self.state.processes[&id].allocation, &v) { return Err("claim below allocation".into()); }
                if !le(&v, &self.state.total) { return Err("max exceeds total".into()); }
                let mut candidate = self.state.clone(); candidate.processes.get_mut(&id).unwrap().max = v.clone();
                if self.mode == "AVOID" && !check(&candidate, false, self.trace).1.is_empty() { return Err("claim makes state unsafe".into()); }
                self.state.processes.get_mut(&id).unwrap().max = v.clone();
                println!("claim P{id} max {}", vector(&v)); self.retry();
            }
            _ => {
                if v.iter().all(|x| *x == 0) { return Err("zero vector".into()); }
                if cmd == "RELEASE" {
                    let p = self.state.processes.get_mut(&id).unwrap();
                    if !le(&v, &p.allocation) { return Err("release exceeds allocation".into()); }
                    p.allocation = sub(&p.allocation, &v);
                    self.state.available = add(&self.state.available, &v);
                    println!("released P{id} {}", vector(&v)); self.record(3, id, v, 0); self.retry();
                } else if cmd == "ADD" {
                    self.state.total = add(&self.state.total, &v); self.state.available = add(&self.state.available, &v);
                    println!("added {} total {}", vector(&v), vector(&self.state.total)); self.retry();
                } else {
                    if !le(&v, &self.state.available) { return Err("remove exceeds available".into()); }
                    let total = sub(&self.state.total, &v);
                    if total.contains(&0) { return Err("total must stay positive".into()); }
                    if self.state.processes.values().any(|p| !le(&p.max, &total)) { return Err("max exceeds total".into()); }
                    let mut candidate = self.state.clone(); candidate.available = sub(&candidate.available, &v);
                    if self.mode == "AVOID" && !check(&candidate, false, self.trace).1.is_empty() { return Err("removal makes state unsafe".into()); }
                    self.state.total = total; self.state.available = candidate.available;
                    println!("removed {} total {}", vector(&v), vector(&self.state.total));
                }
            }
        }
        Ok(())
    }
}
fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let n: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let mut manager = Manager { state: State::default(), snapshots: BTreeMap::new(), mode: "AVOID".into(), policy: "ALLOC".into(), trace: false, auto: false, time: 0 };
    for time in 1..=n {
        manager.time = time;
        let line = lines.next().unwrap().unwrap();
        let words: Vec<&str> = line.split(' ').collect();
        if let Err(message) = manager.execute(&words) { println!("error: {message}"); }
    }
}
