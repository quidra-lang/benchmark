use std::collections::{BTreeMap, BTreeSet, BinaryHeap};
use std::cmp::Reverse;
use std::io::{self, Read};
const TYPES: [&str; 10] = ["AND", "OR", "NAND", "NOR", "XOR", "XNOR", "NOT", "BUF", "MUX2", "DFF"];
#[derive(Clone)]
struct Gate {
    name: String, kind: usize, inputs: Vec<String>, out: String, delay: u64
}
#[derive(Clone)]
enum Body {
    Gate(Gate), Instance(String, String, Vec<(String, String)>)
}
#[derive(Clone)]
struct Module {
    name: String, inputs: Vec<String>, outputs: Vec<String>, body: Vec<Body>
}
#[derive(Clone)]
struct Circuit {
    name: String, inputs: Vec<String>, outputs: Vec<String>, gates: Vec<Gate>, signals: Vec<String>, index: BTreeMap<String, usize>
}
fn name(s: &str, upper: bool) -> bool {
    if s.is_empty() || s.len() > 16 { return false; }
    let letter = |c: u8| if upper { c.is_ascii_uppercase() } else { c.is_ascii_lowercase() };
    letter(s.as_bytes()[0]) && s.bytes().all(|c| c.is_ascii_digit() || c == b'_' || letter(c))
}
fn number(s: &str, positive: bool) -> Result<u64, String> {
    if s.is_empty() || s.len()>9 || (s.len()>1 && s.starts_with('0')) || !s.bytes().all(|c|c.is_ascii_digit()) {
        return Err(format!("bad number {}", s))
    }
    let n = s.parse().unwrap();
    if positive && n == 0 {
        Err(format!("bad number {}", s))
    } else {
        Ok(n)
    }
}
fn value(s: &str) -> Result<u8, String> {
    match s {
        "0" => Ok(0), "1" => Ok(1), "X" => Ok(2), _ => Err(format!("bad value {}", s))
    }
}
fn ch(v: u8) -> char {
    b"01X"[v as usize]as char
}
fn eval(kind: usize, v: &[u8]) -> u8 {
    let inv = |x|if x == 2 {
        2
    } else {
        1-x
    };
    match kind {
        0|2 => {
            let x = if v.contains(&0) {
                0
            } else if v.contains(&2) {
                2
            } else {
                1
            };
            if kind == 2 {
                inv(x)
            } else {
                x
            }
        }, 1|3 => {
            let x = if v.contains(&1) {
                1
            } else if v.contains(&2) {
                2
            } else {
                0
            };
            if kind == 3 {
                inv(x)
            } else {
                x
            }
        }, 4|5 => {
            let x = if v.contains(&2) {
                2
            } else {
                v.iter().fold(0, |a, b|a^b)
            };
            if kind == 5 {
                inv(x)
            } else {
                x
            }
        }, 6 => inv(v[0]), 7 => v[0], 8 => if v[0] == 0 {
            v[1]
        } else if v[0] == 1 {
            v[2]
        } else if v[1] == v[2] {
            v[1]
        } else {
            2
        }, _ => 2
    }
}
fn define(lines: &[&str], first: usize, modules: &BTreeMap<String, Module>) -> Result<Module, (usize, String)> {
    let w: Vec<_> = lines[0].split_whitespace().collect();
    let error = |s: String|(first, s);
    if w.len()<5 || w[2] != "IN" || w[3..].iter().filter(| && s|s == "OUT").count() != 1 || w.last() == Some(&"OUT") {
        return Err(error("bad module header".into()))
    }
    if !name(w[1], true) {
        return Err(error(format!("bad module name {}", w[1])))
    }
    if modules.contains_key(w[1]) {
        return Err(error(format!("duplicate module {}", w[1])))
    }
    let split = 3 + w[3..].iter().position(|&s|s == "OUT").unwrap();
    let inputs = w[3..split].iter().map(|s|s.to_string()).collect::<Vec<_>>();
    let outputs = w[split+1..].iter().map(|s|s.to_string()).collect::<Vec<_>>();
    let mut ports = BTreeSet::new();
    for s in inputs.iter().chain(&outputs) {
        if !name(s, false) {
            return Err(error(format!("bad name {}", s)))
        }
        if !ports.insert(s.clone()) {
            return Err(error(format!("duplicate port {}", s)))
        }
    }
    let mut driven: BTreeSet<_> = inputs.iter().cloned().collect();
    let mut used = BTreeSet::new();
    let mut body = Vec::new();
    let mut reads = Vec::new();
    for (i, line) in  lines.iter().enumerate().skip(1) {
        let ln = first+i;
        let w: Vec<_> = line.split_whitespace().collect();
        let err = |s: String|(ln, s);
        if let Some(kind) = TYPES.iter().position(|&s|s == w[0]) {
            if w.len()<5 || w[w.len()-3] != "->" || w.iter().filter(| && s|s == "->").count() != 1 {
                return Err(err("bad gate syntax".into()))
            }
            if !name(w[1], false) {
                return Err(err(format!("bad name {}", w[1])))
            }
            let n = w.len()-5;
            let valid = match kind {
                0..= 5 => (2..= 8).contains(&n), 6|7 => n == 1, 8 => n == 3, _ => n == 2
            };
            if !valid {
                return Err(err(format!("bad input count {} for {}", n, TYPES[kind])))
            }
            for s in w[2..w.len()-3].iter().chain(std::iter::once(&w[w.len()-2])) {
                if !name(s, false) {
                    return Err(err(format!("bad name {}", s)))
                }
            }
            let delay = number(w[w.len()-1], false).ok().filter(|&n|n <= 1000).ok_or_else( || err(format!("bad delay {}", w[w.len()-1])))?;
            if !used.insert(w[1].to_string()) {
                return Err(err(format!("duplicate name {}", w[1])))
            }
            let out = w[w.len()-2];
            if !driven.insert(out.into()) {
                return Err(err(format!("multiple drivers for {}", out)))
            }
            let ins = w[2..w.len()-3].iter().map(|s|s.to_string()).collect::<Vec<_>>();
            for s in &ins {
                reads.push((ln, s.clone()))
            }
            body.push(Body::Gate(Gate {
                name: w[1].into(), kind, inputs: ins, out: out.into(), delay
            }));
        } else if w[0] == "INST" {
            if w.len()<3 {
                return Err(err("bad instance syntax".into()))
            }
            if !name(w[1], false) {
                return Err(err(format!("bad name {}", w[1])))
            }
            let m = modules.get(w[2]).ok_or_else( || err(format!("unknown module {}", w[2])))?;
            let mut connections = Vec::new();
            let mut seen = BTreeSet::new();
            for word in &w[3..] {
                let p: Vec<_> = word.split('=').collect();
                if p.len() != 2 || p[0].is_empty() || p[1].is_empty() {
                    return Err(err(format!("bad connection {}", word)))
                }
                if !m.inputs.iter().chain(&m.outputs).any(|s|s == p[0]) {
                    return Err(err(format!("unknown port {}", p[0])))
                }
                if !seen.insert(p[0]) {
                    return Err(err(format!("duplicate connection {}", p[0])))
                }
                if !name(p[1], false) {
                    return Err(err(format!("bad name {}", p[1])))
                }
                connections.push((p[0].to_string(), p[1].to_string()));
            }
            for s in &m.inputs {
                if !seen.contains(s.as_str()) {
                    return Err(err(format!("unconnected input {}", s)))
                }
            }
            if !used.insert(w[1].to_string()) {
                return Err(err(format!("duplicate name {}", w[1])))
            }
            for (p, s) in  &connections {
                if m.outputs.contains(p) && !driven.insert(s.clone()) {
                    return Err(err(format!("multiple drivers for {}", s)))
                }
            }
            for (p, s) in  &connections {
                if m.inputs.contains(p) {
                    reads.push((ln, s.clone()))
                }
            }
            body.push(Body::Instance(w[1].into(), w[2].into(), connections));
        } else {
            return Err(err(format!("unknown statement {}", w[0])))
        }
    }
    for s in &outputs {
        reads.push((first, s.clone()))
    }
    for (ln, s) in  reads {
        if !driven.contains(&s) {
            return Err((ln, format!("undriven signal {}", s)))
        }
    }
    Ok(Module {
        name: w[1].into(), inputs, outputs, body
    })
}
fn expand(m: &Module, prefix: &str, map: &BTreeMap<String, String>, modules: &BTreeMap<String, Module>, gates: &mut Vec<Gate>) {
    let actual = |s: &String|map.get(s).cloned().unwrap_or_else( || format!("{}{}", prefix, s));
    for b in &m.body {
        match b {
            Body::Gate(g) => gates.push(Gate {
                name: format!("{}{}", prefix, g.name), kind: g.kind, inputs: g.inputs.iter().map(actual).collect(), out: actual(&g.out), delay: g.delay
            }), Body::Instance(i, n, c) => {
                let mapping = c.iter().map(|(p, s)|(p.clone(), actual(s))).collect();
                expand(&modules[n], &format!("{}{}.", prefix, i), &mapping, modules, gates)
            }
        }
    }
}
fn flatten(n: &str, modules: &BTreeMap<String, Module>) -> Result<Circuit, String> {
    let m = modules.get(n).ok_or_else( || format!("unknown module {}", n))?;
    let mut gates = Vec::new();
    expand(m, "", &BTreeMap::new(), modules, &mut gates);
    let signals: Vec<_> = m.inputs.iter().cloned().chain(gates.iter().map(|g|g.out.clone())).collect();
    let index = signals.iter().enumerate().map(|(i, s)|(s.clone(), i)).collect();
    Ok(Circuit {
        name: n.into(), inputs: m.inputs.clone(), outputs: m.outputs.clone(), gates, signals, index
    })
}
impl Circuit {
    fn topological(&self) -> Option<Vec<usize>> {
        let mut available: BTreeSet<_> = self.inputs.iter().cloned().collect();
        for g in &self.gates {
            if g.kind == 9 {
                available.insert(g.out.clone());
            }
        }
        let mut remaining: BTreeSet<_> = self.gates.iter().enumerate().filter(|(_, g)|g.kind != 9).map(|(i, _)|i).collect();
        let mut order = Vec::new();
        while !remaining.is_empty() {
            let i = remaining.iter().copied().find(|&i|self.gates[i].inputs.iter().all(|s|available.contains(s)))?;
            remaining.remove(&i);
            available.insert(self.gates[i].out.clone());
            order.push(i)
        }
        Some(order)
    }
    fn combinational(&self) -> Result<Vec<usize>, String> {
        if self.gates.iter().any(|g|g.kind == 9) {
            return Err(format!("{} is not combinational", self.name))
        }
        let order = self.topological().ok_or_else( || format!("{} has a combinational loop", self.name))?;
        if self.inputs.len()>8 {
            return Err(format!("too many inputs {}", self.inputs.len()))
        }
        Ok(order)
    }
    fn bits(&self, r: usize) -> String {
        (0..self.inputs.len()).map(|i|if r&(1<<(self.inputs.len()-1-i)) == 0 {
            '0'
        } else {
            '1'
        }).collect()
    }
    fn row(&self, r: usize, order: &[usize], fault: Option<(usize, u8)>) -> String {
        let mut v = vec![2;
        self.signals.len()];
        for i in 0..self.inputs.len() {
            v[i] = ((r>>(self.inputs.len()-1-i))&1)as u8
        }
        if let Some((s, x)) = fault {
            v[s] = x
        }
        for &i in order {
            let g = &self.gates[i];
            let s = self.index[&g.out];
            v[s] = if fault.is_some_and(|(f, _)|f == s) {
                fault.unwrap().1
            } else {
                eval(g.kind, &g.inputs.iter().map(|s|v[self.index[s]]).collect::<Vec<_>>())
            }
        }
        self.outputs.iter().map(|s|ch(v[self.index[s]])).collect()
    }
    fn readers(&self, s: &str) -> Vec<usize> {
        self.gates.iter().enumerate().filter(|(_, g)|g.inputs.iter().any(|x|x == s)).map(|(i, _)|i).collect()
    }
}
fn hierarchy(m: &Module, depth: usize, modules: &BTreeMap<String, Module>, out: &mut Vec<String>) {
    for b in &m.body {
        if let Body::Instance(i, n, _) = b {
            out.push(format!("{}{} {}", " ".repeat(depth*2), i, n));
            hierarchy(&modules[n], depth+1, modules, out)
        }
    }
}
fn inspect(cmd: &str, a: &[&str], modules: &BTreeMap<String, Module>, names: &[String]) -> Result<Vec<String>, String> {
    let mut out = Vec::new();
    if cmd == "MODULES" {
        out.push(format!("modules {}", names.len()));
        for n in names {
            let c = flatten(n, modules)?;
            out.push(format!("{} inputs {} outputs {} gates {}", n, c.inputs.len(), c.outputs.len(), c.gates.len()))
        }
        return Ok(out)
    }
    let c = flatten(a[0], modules)?;
    if cmd == "EQUIV" {
        let other = flatten(a[1], modules)?;
        let order = c.combinational()?;
        let oo = other.combinational()?;
        if c.inputs.len() != other.inputs.len() || c.outputs.len() != other.outputs.len() {
            return Err("port mismatch".into())
        }
        for r in 0..1usize<<c.inputs.len() {
            let x = c.row(r, &order, None);
            let y = other.row(r, &oo, None);
            if x != y {
                return Ok(vec![format!("not equivalent at {}: {} vs {}", c.bits(r), x, y)])
            }
        }
        return Ok(vec!["equivalent".into()])
    }
    match cmd {
        "NETLIST" => {
            out.push(format!("netlist {} gates {} signals {}", c.name, c.gates.len(), c.signals.len()));
            for g in &c.gates {
                out.push(format!("{} {} {} -> {} {}", g.name, TYPES[g.kind], g.inputs.join(" "), g.out, g.delay))
            }
        }, "HIERARCHY" => {
            out.push(c.name.clone());
            hierarchy(&modules[a[0]], 1, modules, &mut out)
        }, "STATS" => {
            let order = c.topological();
            let depth = order.map(|o| {
                let mut levels = vec![0usize;
                c.signals.len()];
                for i in o {
                    let g = &c.gates[i];
                    levels[c.index[&g.out]] = g.inputs.iter().map(|s|levels[c.index[s]]).max().unwrap()+1
                }
                levels.into_iter().max().unwrap_or(0).to_string()
            }).unwrap_or("-".into());
            out.push(format!("stats {} gates {} signals {} depth {}", c.name, c.gates.len(), c.signals.len(), depth));
            let mut types = String::from("types");
            for (i, k) in  TYPES.iter().enumerate() {
                let n = c.gates.iter().filter(|g|g.kind == i).count();
                if n>0 {
                    types.push_str(&format!(" {} {}", k, n))
                }
            }
            out.push(types);
            let mut best = 0;
            let mut count = 0;
            for (i, s) in  c.signals.iter().enumerate() {
                let n = c.readers(s).len();
                if n>count {
                    best = i;
                    count = n
                }
            }
            out.push(format!("max fanout {} {}", c.signals[best], count));
        }, "TRUTHTABLE" => {
            let order = c.combinational()?;
            let mut header = c.inputs.clone();
            header.push("|".into());
            header.extend(c.outputs.clone());
            out.push(header.join(" "));
            for r in 0..1usize<<c.inputs.len() {
                let mut row = c.bits(r).chars().map(|c|c.to_string()).collect::<Vec<_>>();
                row.push("|".into());
                row.extend(c.row(r, &order, None).chars().map(|c|c.to_string()));
                out.push(row.join(" "))
            }
        }, "FAULTS" => {
            let order = c.combinational()?;
            let good: Vec<_> = (0..1usize<<c.inputs.len()).map(|r|c.row(r, &order, None)).collect();
            let mut undetected = Vec::new();
            let mut tests = BTreeSet::new();
            let mut detected = 0;
            for (s, n) in  c.signals.iter().enumerate() {
                for v in 0..2 {
                    if let Some(r) = (0..good.len()).find(|&r|c.row(r, &order, Some((s, v))) != good[r]) {
                        detected += 1;
                        tests.insert(r);
                    } else {
                        undetected.push(format!("undetected {}/{}", n, v))
                    }
                }
            }
            out.push(format!("faults {} detected {}", 2*c.signals.len(), detected));
            out.extend(undetected);
            out.push(format!("tests{}", tests.iter().map(|&r|format!(" {}", c.bits(r))).collect::<String>()));
        }, "CRITICAL"|"PERIOD" => {
            let f = c.gates.iter().filter(|g|g.kind == 9).count();
            if cmd == "PERIOD" && f == 0 {
                return Err(format!("{} has no flip-flops", c.name))
            }
            let order = c.topological().ok_or_else( || format!("{} has a combinational loop", c.name))?;
            let mut latest = vec![None::<u64>;
            c.signals.len()];
            let mut earliest = latest.clone();
            let mut previous = vec![None;
            c.signals.len()];
            if cmd == "CRITICAL" {
                for s in &c.inputs {
                    latest[c.index[s]] = Some(0);
                    earliest[c.index[s]] = Some(0)
                }
            } else {
                for g in &c.gates {
                    if g.kind == 9 {
                        latest[c.index[&g.out]] = Some(g.delay);
                        earliest[c.index[&g.out]] = Some(g.delay)
                    }
                }
            }
            for i in order {
                let g = &c.gates[i];
                let s = c.index[&g.out];
                for n in &g.inputs {
                    let j = c.index[n];
                    if let Some(t) = latest[j] {
                        let t = t+g.delay;
                        if latest[s].is_none_or(|old|t>old) {
                            latest[s] = Some(t);
                            previous[s] = Some(j)
                        }
                        let e = earliest[j].unwrap()+g.delay;
                        earliest[s] = Some(earliest[s].map_or(e, |old|old.min(e)));
                    }
                }
            }
            let endpoints: Vec<_> = if cmd == "CRITICAL" {
                c.outputs.clone()
            } else {
                c.gates.iter().filter(|g|g.kind == 9).map(|g|g.inputs[1].clone()).collect()
            };
            let mut best = None;
            for n in endpoints {
                let s = c.index[&n];
                if cmd == "CRITICAL" {
                    out.push(if let Some(t) = latest[s] {
                        format!("{} min {} max {}", n, earliest[s].unwrap(), t)
                    } else {
                        format!("{} unreachable", n)
                    })
                }
                if let Some(t) = latest[s] {
                    if best.is_none_or(|b: usize|t>latest[b].unwrap()) {
                        best = Some(s)
                    }
                }
            }
            let prefix = if cmd == "CRITICAL" {
                "critical".into()
            } else {
                format!("flip-flops {} period", f)
            };
            if let Some(mut s) = best {
                let t = latest[s].unwrap();
                let mut path = vec![c.signals[s].clone()];
                while let Some(p) = previous[s] {
                    s = p;
                    path.push(c.signals[s].clone())
                }
                path.reverse();
                out.push(format!("{} {}: {}", prefix, t, path.join(" -> ")))
            } else {
                out.push(format!("{} none", prefix))
            }
        }, _ => {
        }
    }
    Ok(out)
}
struct Simulation {
    c: Circuit, v: Vec<u8>, time: u64, queue: BinaryHeap<Reverse<(u64, u64, usize, u8)>>, serial: u64, watch: Vec<usize>, history: Vec<Vec<(u64, u8)>>, events: u64, halted: bool
}
impl Simulation {
    fn new(c: Circuit) -> Self {
        let n = c.signals.len();
        Self {
            c, v: vec![2;
            n], time: 0, queue: BinaryHeap::new(), serial: 0, watch: Vec::new(), history: vec![Vec::new();
            n], events: 0, halted: false
        }
    }
    fn schedule(&mut self, t: u64, s: usize, v: u8) {
        self.queue.push(Reverse((t, self.serial, s, v)));
        self.serial += 1
    }
    fn signal(&self, s: &str) -> Result<usize, String> {
        self.c.index.get(s).copied().ok_or_else( || format!("unknown signal {}", s))
    }
    fn input(&self, s: &str) -> Result<usize, String> {
        self.c.inputs.iter().position(|x|x == s).ok_or_else( || format!("not an input {}", s))
    }
    fn time(&self, s: &str) -> Result<u64, String> {
        let t = number(s, false)?;
        if t<self.time {
            Err(format!("time {} is in the past", t))
        } else {
            Ok(t)
        }
    }
    fn command(&mut self, cmd: &str, a: &[&str]) -> Result<Vec<String>, String> {
        let mut out = Vec::new();
        if ["SET", "APPLY", "PULSE", "CLOCK", "RUN"].contains(&cmd) && self.halted {
            return Err("simulation halted".into())
        }
        match cmd {
            "RESET" => {
                let watch = self.watch.clone();
                *self = Self::new(self.c.clone());
                self.watch = watch;
                out.push("reset".into())
            }, "SET" => {
                let t = self.time(a[0])?;
                let s = self.input(a[1])?;
                let v = value(a[2])?;
                self.schedule(t, s, v);
                out.push(format!("set {} {} at {}", a[1], a[2], t))
            }, "APPLY" => {
                let t = self.time(a[0])?;
                let b = a[1].as_bytes();
                if b.len() != self.c.inputs.len() || b.iter().any(|c|!b"01X".contains(c)) {
                    return Err(format!("bad vector {}", a[1]))
                }
                for (i, &v) in  b.iter().enumerate() {
                    self.schedule(t, i, if v == b'X' {
                        2
                    } else {
                        v-b'0'
                    })
                }
                out.push(format!("apply {} at {}", a[1], t))
            }, "PULSE"|"CLOCK" => {
                let s = self.input(a[0])?;
                let t = self.time(a[1])?;
                let half = number(a[2], true)?;
                if cmd == "PULSE" {
                    self.schedule(t, s, 1);
                    self.schedule(t+half, s, 0);
                    out.push(format!("pulse {} {} {}", a[0], t, t+half))
                } else {
                    let count = number(a[3], true)?;
                    for i in 0..count {
                        self.schedule(t+i*half, s, (i%2)as u8)
                    }
                    out.push(format!("clock {} events {} last {}", a[0], count, t+(count-1)*half))
                }
            }, "RUN" => {
                let t = number(a[0], false)?;
                if t <= self.time {
                    return Err(format!("time {} is not after {}", t, self.time))
                }
                let begin = self.events;
                let mut glitches = 0;
                while self.queue.peek().is_some_and(|e|(e.0).0<t) {
                    let tau = (self.queue.peek().unwrap().0).0;
                    let old = self.v.clone();
                    let mut changed = vec![false;
                    old.len()];
                    let mut count = 0;
                    while self.queue.peek().is_some_and(|e|(e.0).0 == tau) {
                        if count == 1000 {
                            self.queue.clear();
                            self.halted = true;
                            self.time = tau;
                            out.push(format!("halted: oscillation at time {}", tau));
                            return Ok(out)
                        }
                        let Reverse((_, _, s, v)) = self.queue.pop().unwrap();
                        count += 1;
                        self.events += 1;
                        let u = self.v[s];
                        if u == v {
                            continue
                        }
                        self.v[s] = v;
                        changed[s] = true;
                        let readers = self.c.readers(&self.c.signals[s]);
                        for i in readers {
                            let g = &self.c.gates[i];
                            let y = if g.kind == 9 {
                                if self.c.index[&g.inputs[0]] != s || u != 0 || v != 1 {
                                    continue
                                }
                                self.v[self.c.index[&g.inputs[1]]]
                            } else {
                                eval(g.kind, &g.inputs.iter().map(|n|self.v[self.c.index[n]]).collect::<Vec<_>>())
                            };
                            let when = tau+g.delay;
                            let output = self.c.index[&g.out];
                            self.schedule(when, output, y)
                        }
                    }
                    for s in 0..old.len() {
                        if old[s] != self.v[s] {
                            self.history[s].push((tau, self.v[s]))
                        } else if changed[s] {
                            glitches += 1
                        }
                    }
                    for &s in &self.watch {
                        if old[s] != self.v[s] {
                            out.push(format!("{} {} {}", tau, self.c.signals[s], ch(self.v[s])))
                        }
                    }
                }
                self.time = t;
                out.push(format!("run {} events {} glitches {} pending {}", t, self.events-begin, glitches, self.queue.len()));
            }, "WATCH"|"UNWATCH" => {
                let mut seen = BTreeSet::new();
                let mut ids = Vec::new();
                for s in a {
                    let i = self.signal(s)?;
                    let present = self.watch.contains(&i);
                    if (cmd == "WATCH" && present) || (cmd == "UNWATCH" && !present) || !seen.insert(i) {
                        return Err(format!("{} {}", if cmd == "WATCH" {
                            "already watched"
                        } else {
                            "not watched"
                        }, s))
                    }
                    ids.push(i)
                }
                if cmd == "WATCH" {
                    self.watch.extend(ids)
                } else {
                    self.watch.retain(|s|!ids.contains(s))
                }
                out.push(format!("watching {}", if self.watch.is_empty() {
                    "nothing".into()
                } else {
                    self.watch.iter().map(|&s|self.c.signals[s].clone()).collect::<Vec<_>>().join(" ")
                }));
            }, "SHOW" => {
                let mut cells = Vec::new();
                if a.is_empty() {
                    for s in &self.c.inputs {
                        cells.push(format!("{}={}", s, ch(self.v[self.c.index[s]])))
                    }
                    cells.push("|".into());
                    for s in &self.c.outputs {
                        cells.push(format!("{}={}", s, ch(self.v[self.c.index[s]])))
                    }
                } else {
                    for s in a {
                        let i = self.signal(s)?;
                        cells.push(format!("{}={}", s, ch(self.v[i])))
                    }
                }
                out.push(cells.join(" "));
            }, "CHECK" => {
                let s = self.signal(a[0])?;
                let v = value(a[1])?;
                out.push(format!("check {}={} {}", a[0], a[1], if self.v[s] == v {
                    "ok".into()
                } else {
                    format!("failed ({})", ch(self.v[s]))
                }));
            }, "PROBE" => {
                let s = self.signal(a[0])?;
                if s<self.c.inputs.len() {
                    out.push(format!("{}={} driven by input", a[0], ch(self.v[s])))
                } else {
                    let g = &self.c.gates[s-self.c.inputs.len()];
                    out.push(format!("{}={} driven by {} {} {} delay {}", a[0], ch(self.v[s]), g.name, TYPES[g.kind], g.inputs.iter().map(|n|format!("{}={}", n, ch(self.v[self.c.index[n]]))).collect::<Vec<_>>().join(" "), g.delay))
                }
                let readers = self.c.readers(a[0]);
                out.push(format!("fanout {}{}", readers.len(), readers.iter().map(|&i|format!(" {}", self.c.gates[i].name)).collect::<String>()));
            }, "HISTORY" => {
                let s = self.signal(a[0])?;
                out.push(format!("history {} changes {}{}", a[0], self.history[s].len(), self.history[s].iter().map(|&(t, v)|format!(" {}:{}", t, ch(v))).collect::<String>()))
            }, "WAVE" => {
                let t0 = number(a[0], false)?;
                let t1 = number(a[1], false)?;
                if !(t0<t1 && t1 <= self.time) {
                    return Err(format!("bad range {} {}", t0, t1))
                }
                if self.watch.is_empty() {
                    return Err("nothing watched".into())
                }
                for &s in &self.watch {
                    let wave: String = (t0..t1).map(|t|ch(self.history[s].iter().rev().find(| && (tau, _)|tau <= t).map_or(2, |&(_, v)|v))).collect();
                    out.push(format!("{} {}", self.c.signals[s], wave))
                }
            }, "ACTIVITY" => {
                let k = number(a[0], true)? as usize;
                let mut ids: Vec<_> = (0..self.v.len()).collect();
                ids.sort_by(|&x, &y|self.history[y].len().cmp(&self.history[x].len()).then_with( || self.c.signals[x].cmp(&self.c.signals[y])));
                for s in ids.into_iter().take(k) {
                    out.push(format!("{} {}", self.c.signals[s], self.history[s].len()))
                }
            }, "STATUS" => {
                out.push(format!("circuit {} time {} pending {} events {} halted {}", self.c.name, self.time, self.queue.len(), self.events, if self.halted {
                    "yes"
                } else {
                    "no"
                }));
                out.push(format!("values 0:{} 1:{} X:{}", self.v.iter().filter(| && v|v == 0).count(), self.v.iter().filter(| && v|v == 1).count(), self.v.iter().filter(| && v|v == 2).count()))
            }, _ => {
            }
        }
        Ok(out)
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<_> = input.lines().collect();
    let mut modules = BTreeMap::new();
    let mut names = Vec::new();
    let mut sim: Option<Simulation> = None;
    let mut i = 0;
    while i<lines.len() {
        let line = i+1;
        let w: Vec<_> = lines[i].split_whitespace().collect();
        if w.len() == 1 && w[0] == "END" {
            break
        }
        if w[0] == "MODULE" {
            let begin = i;
            i += 1;
            while lines[i] != "ENDMODULE" {
                i += 1
            }
            match define(&lines[begin..i], line, &modules) {
                Ok(m) => {
                    println!("defined {} inputs {} outputs {} gates {} instances {}", m.name, m.inputs.len(), m.outputs.len(), m.body.iter().filter(|b|matches!(b, Body::Gate(_))).count(), m.body.iter().filter(|b|matches!(b, Body::Instance(..))).count());
                    names.push(m.name.clone());
                    modules.insert(m.name.clone(), m);
                }, Err((n, e)) => println!("error: line {}: {}", n, e)
            }
            i += 1;
            continue
        }
        i += 1;
        let cmd = w[0];
        let a = &w[1..];
        let count = match cmd {
            "RESET"|"STATUS"|"MODULES" => Some(a.is_empty()), "BUILD"|"RUN"|"PROBE"|"HISTORY"|"ACTIVITY"|"NETLIST"|"HIERARCHY"|"STATS"|"TRUTHTABLE"|"FAULTS"|"CRITICAL"|"PERIOD" => Some(a.len() == 1), "APPLY"|"CHECK"|"WAVE"|"EQUIV" => Some(a.len() == 2), "SET"|"PULSE" => Some(a.len() == 3), "CLOCK" => Some(a.len() == 4), "WATCH"|"UNWATCH" => Some(!a.is_empty()), "SHOW" => Some(true), _ => None
        };
        let result = if count.is_none() {
            Err(format!("unknown command {}", cmd))
        } else if count == Some(false) {
            Err("wrong argument count".into())
        } else if cmd == "BUILD" {
            match flatten(a[0], &modules) {
                Err(e) => Err(e), Ok(c) => {
                    let message = format!("built {} signals {} gates {}", c.name, c.signals.len(), c.gates.len());
                    sim = Some(Simulation::new(c));
                    Ok(vec![message])
                }
            }
        } else if ["MODULES", "NETLIST", "HIERARCHY", "STATS", "TRUTHTABLE", "EQUIV", "FAULTS", "CRITICAL", "PERIOD"].contains(&cmd) {
            inspect(cmd, a, &modules, &names)
        } else if let Some(s) = sim.as_mut() {
            s.command(cmd, a)
        } else {
            Err("no circuit".into())
        };
        match result {
            Ok(out) => for s in out {
                println!("{}", s)
            }, Err(e) => println!("error: line {}: {}", line, e)
        }
    }
}
