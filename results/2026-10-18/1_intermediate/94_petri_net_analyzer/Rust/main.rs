use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{self, Read};
type Mark = Vec<i64>;
fn yes(b: bool) -> &'static str {
    if b { "yes" } else { "no" }
}
fn mark(m: &[i64]) -> String {
    format!(
        "({})",
        m.iter()
            .map(|v| if *v < 0 { "w".into() } else { v.to_string() })
            .collect::<Vec<_>>()
            .join(",")
    )
}
fn listed(a: &[String]) -> String {
    if a.is_empty() {
        "none".into()
    } else {
        a.join(" ")
    }
}
fn number(s: &str, lo: i64, hi: i64) -> Option<i64> {
    if s.is_empty()
        || s.len() > 10
        || s.len() > 1 && s.starts_with('0')
        || !s.bytes().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    s.parse::<i64>().ok().filter(|v| *v >= lo && *v <= hi)
}
fn visit(adj: &[Vec<usize>], start: usize) -> Vec<bool> {
    let mut seen = vec![false; adj.len()];
    let mut queue = VecDeque::from([start]);
    seen[start] = true;
    while let Some(u) = queue.pop_front() {
        for &v in &adj[u] {
            if !seen[v] {
                seen[v] = true;
                queue.push_back(v);
            }
        }
    }
    seen
}
fn gcd(mut a: i64, mut b: i64) -> i64 {
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a.abs()
}
fn flows(a: Vec<Mark>) -> Vec<Mark> {
    let (n, m) = (a.len(), a[0].len());
    let mut rows: Vec<Mark> = a
        .into_iter()
        .enumerate()
        .map(|(i, mut r)| {
            r.extend((0..n).map(|j| i64::from(i == j)));
            r
        })
        .collect();
    for j in 0..m {
        let mut unique: HashSet<Mark> = rows.iter().filter(|r| r[j] == 0).cloned().collect();
        for r in rows.iter().filter(|r| r[j] > 0) {
            for s in rows.iter().filter(|r| r[j] < 0) {
                let mut v: Mark = (0..m + n).map(|k| -s[j] * r[k] + r[j] * s[k]).collect();
                let d = v.iter().fold(0, |g, &x| gcd(g, x));
                for x in &mut v {
                    *x /= d;
                }
                unique.insert(v);
            }
        }
        let candidates: Vec<Mark> = unique.into_iter().collect();
        let supports: Vec<u32> = candidates
            .iter()
            .map(|r| (0..n).filter(|&i| r[m + i] > 0).fold(0, |s, i| s | 1 << i))
            .collect();
        rows = candidates
            .into_iter()
            .enumerate()
            .filter(|(i, _)| {
                !supports
                    .iter()
                    .any(|&s| s != supports[*i] && s & supports[*i] == s)
            })
            .map(|(_, r)| r)
            .collect();
    }
    let mut result: Vec<Mark> = rows.into_iter().map(|r| r[m..].to_vec()).collect();
    result.sort_by(|a, b| b.cmp(a));
    result
}
struct Graph {
    states: Vec<Mark>,
    parent: Vec<Option<usize>>,
    via: Vec<usize>,
    edges: Vec<Vec<(usize, usize)>>,
    found: Option<usize>,
    aborted: bool,
}
impl Graph {
    fn new(start: Mark) -> Self {
        Self {
            states: vec![start],
            parent: vec![None],
            via: vec![0],
            edges: vec![vec![]],
            found: None,
            aborted: false,
        }
    }
    fn add(&mut self, m: Mark, p: usize, t: usize) {
        self.states.push(m);
        self.parent.push(Some(p));
        self.via.push(t);
        self.edges.push(vec![]);
    }
}
struct Net {
    name: String,
    p: Vec<String>,
    t: Vec<String>,
    initial: Mark,
    capacity: Mark,
    priority: Mark,
    current: Mark,
    history: Vec<Mark>,
    pre: [[i64; 16]; 16],
    post: [[i64; 16]; 16],
    inhibitor: [[i64; 16]; 16],
    arcs: usize,
    inhibitors: usize,
}
impl Net {
    fn new(name: &str) -> Self {
        Self {
            name: name.into(),
            p: vec![],
            t: vec![],
            initial: vec![],
            capacity: vec![],
            priority: vec![],
            current: vec![],
            history: vec![],
            pre: [[0; 16]; 16],
            post: [[0; 16]; 16],
            inhibitor: [[0; 16]; 16],
            arcs: 0,
            inhibitors: 0,
        }
    }
    fn place(&self, s: &str) -> Option<usize> {
        self.p.iter().position(|v| v == s)
    }
    fn transition(&self, s: &str) -> Option<usize> {
        self.t.iter().position(|v| v == s)
    }
    fn define(&mut self, w: &[&str]) -> Result<(), String> {
        let (cmd, n) = (w[0], w.len() - 1);
        if !["place", "transition", "arc", "inhibit"].contains(&cmd) {
            return Err(format!("unknown definition {cmd}"));
        }
        if !match cmd {
            "place" => n == 2 || n == 3,
            "transition" => n == 1 || n == 2,
            _ => n == 3,
        } {
            return Err("wrong number of arguments".into());
        }
        let a = w[1];
        match cmd {
            "place" | "transition" => {
                if self.place(a).is_some() || self.transition(a).is_some() {
                    return Err(format!("duplicate name {a}"));
                }
                if cmd == "place" {
                    let tokens: i64 = w[2].parse().unwrap();
                    let capacity = if n == 3 { w[3].parse().unwrap() } else { 0 };
                    if n == 3 && tokens > capacity {
                        return Err(format!("tokens exceed capacity of {a}"));
                    }
                    self.p.push(a.into());
                    self.initial.push(tokens);
                    self.capacity.push(capacity);
                } else {
                    self.t.push(a.into());
                    self.priority
                        .push(if n == 2 { w[2].parse().unwrap() } else { 0 });
                }
            }
            "arc" => {
                let b = w[2];
                for x in [a, b] {
                    if self.place(x).is_none() && self.transition(x).is_none() {
                        return Err(format!("unknown node {x}"));
                    }
                }
                let (pa, pb) = (self.place(a), self.place(b));
                if pa.is_some() == pb.is_some() {
                    return Err("arc must connect a place and a transition".into());
                }
                let p = pa.or(pb).unwrap();
                let t = self.transition(if pa.is_some() { b } else { a }).unwrap();
                let matrix = if pa.is_some() {
                    &mut self.pre
                } else {
                    &mut self.post
                };
                if matrix[p][t] != 0 {
                    return Err(format!("duplicate arc {a} {b}"));
                }
                matrix[p][t] = w[3].parse().unwrap();
                self.arcs += 1;
            }
            _ => {
                let p = self.place(a).ok_or_else(|| format!("unknown place {a}"))?;
                let t = self
                    .transition(w[2])
                    .ok_or_else(|| format!("unknown transition {}", w[2]))?;
                if self.inhibitor[p][t] != 0 {
                    return Err(format!("duplicate inhibitor {a} {}", w[2]));
                }
                self.inhibitor[p][t] = w[3].parse().unwrap();
                self.inhibitors += 1;
            }
        }
        Ok(())
    }
    fn reason(&self, m: &[i64], t: usize) -> Option<String> {
        for p in 0..self.p.len() {
            if m[p] >= 0 && m[p] < self.pre[p][t] {
                return Some(format!("insufficient tokens in {}", self.p[p]));
            }
        }
        for p in 0..self.p.len() {
            if self.inhibitor[p][t] > 0 && (m[p] < 0 || m[p] >= self.inhibitor[p][t]) {
                return Some(format!("inhibited by {}", self.p[p]));
            }
        }
        for p in 0..self.p.len() {
            if self.capacity[p] > 0
                && (m[p] < 0 || m[p] - self.pre[p][t] + self.post[p][t] > self.capacity[p])
            {
                return Some(format!("capacity of {} exceeded", self.p[p]));
            }
        }
        None
    }
    fn enabled(&self, m: &[i64]) -> Vec<usize> {
        (0..self.t.len())
            .filter(|&t| self.reason(m, t).is_none())
            .collect()
    }
    fn fire(&self, m: &[i64], t: usize) -> Mark {
        m.iter()
            .enumerate()
            .map(|(p, &v)| {
                if v < 0 {
                    -1
                } else {
                    v - self.pre[p][t] + self.post[p][t]
                }
            })
            .collect()
    }
    fn commit(&mut self, t: usize) {
        let next = self.fire(&self.current, t);
        self.history
            .push(std::mem::replace(&mut self.current, next));
    }
    fn names(&self, ts: &[usize]) -> Vec<String> {
        ts.iter().map(|&t| self.t[t].clone()).collect()
    }
    fn graph(&self, start: &[i64], limit: usize, target: Option<&[(i64, i64)]>) -> Graph {
        let mut g = Graph::new(start.to_vec());
        let mut index = HashMap::from([(start.to_vec(), 0)]);
        let matches = |m: &[i64]| {
            target.is_some_and(|a| {
                m.iter()
                    .enumerate()
                    .all(|(p, &v)| v >= a[p].0 && (a[p].1 < 0 || v == a[p].1))
            })
        };
        if matches(start) {
            g.found = Some(0);
            return g;
        }
        let mut q = 0;
        while q < g.states.len() {
            for t in self.enabled(&g.states[q]) {
                let m = self.fire(&g.states[q], t);
                let k = if let Some(&k) = index.get(&m) {
                    k
                } else {
                    if g.states.len() == limit {
                        g.aborted = true;
                        return g;
                    }
                    let k = g.states.len();
                    index.insert(m.clone(), k);
                    let found = matches(&m);
                    g.add(m, q, t);
                    if found {
                        g.found = Some(k);
                        return g;
                    }
                    k
                };
                g.edges[q].push((t, k));
            }
            q += 1;
        }
        g
    }
    fn path(&self, g: &Graph, mut k: usize) -> Vec<usize> {
        let mut a = vec![];
        while let Some(p) = g.parent[k] {
            a.push(g.via[k]);
            k = p;
        }
        a.reverse();
        a
    }
    fn reach(&self, limit: usize, display: bool) {
        let g = self.graph(&self.current, limit, None);
        if g.aborted {
            println!("reachability graph limit {limit} exceeded");
            return;
        }
        let n = g.states.len();
        if display {
            for (i, m) in g.states.iter().enumerate() {
                let a: Vec<_> = g.edges[i]
                    .iter()
                    .map(|&(t, k)| format!("{}->M{k}", self.t[t]))
                    .collect();
                println!(
                    "M{i} {}: {}",
                    mark(m),
                    if a.is_empty() {
                        "dead".into()
                    } else {
                        a.join(" ")
                    }
                );
            }
            return;
        }
        let adj: Vec<Vec<_>> = g
            .edges
            .iter()
            .map(|e| e.iter().map(|x| x.1).collect())
            .collect();
        let closure: Vec<_> = (0..n).map(|i| visit(&adj, i)).collect();
        let mut comp = vec![usize::MAX; n];
        let mut components = 0;
        for i in 0..n {
            if comp[i] != usize::MAX {
                continue;
            }
            for j in i..n {
                if closure[i][j] && closure[j][i] {
                    comp[j] = components;
                }
            }
            components += 1;
        }
        let mut terminal = vec![true; components];
        let mut home = vec![true; n];
        let mut maximum = vec![0; self.p.len()];
        let mut dead = vec![];
        let mut edges = 0;
        let mut persistent = true;
        for i in 0..n {
            if g.edges[i].is_empty() {
                dead.push(i);
            }
            edges += g.edges[i].len();
            for p in 0..maximum.len() {
                maximum[p] = maximum[p].max(g.states[i][p]);
            }
            for j in 0..n {
                home[j] &= closure[i][j];
            }
            for &(t, k) in &g.edges[i] {
                if comp[i] != comp[k] {
                    terminal[comp[i]] = false;
                }
                for &(u, _) in &g.edges[i] {
                    if t != u && self.reason(&g.states[k], u).is_some() {
                        persistent = false;
                    }
                }
            }
        }
        println!(
            "reachable markings: {n}\nedges: {edges}\ncomponents: {components} (terminal {})\ndead markings: {}",
            terminal.iter().filter(|&&v| v).count(),
            dead.len()
        );
        for i in dead {
            let a = self.names(&self.path(&g, i));
            println!(
                "  M{i} {} path {}",
                mark(&g.states[i]),
                if a.is_empty() {
                    "empty".into()
                } else {
                    a.join(" ")
                }
            );
        }
        let bound = *maximum.iter().max().unwrap();
        println!(
            "max tokens: {}\nbound: {bound}\nsafe: {}\nhome markings: {}\nreversible: {}\npersistent: {}",
            mark(&maximum),
            yes(bound <= 1),
            home.iter().filter(|&&v| v).count(),
            yes(home[0]),
            yes(persistent)
        );
        let mut levels = vec![];
        for t in 0..self.t.len() {
            let mut present = vec![false; components];
            let (mut used, mut cycle) = (false, false);
            for i in 0..n {
                for &(u, k) in &g.edges[i] {
                    if u == t {
                        used = true;
                        present[comp[i]] = true;
                        cycle |= comp[i] == comp[k];
                    }
                }
            }
            let live = (0..components).all(|c| !terminal[c] || present[c]);
            levels.push(format!(
                "{}={}",
                self.t[t],
                if live {
                    "L4"
                } else if cycle {
                    "L3"
                } else if used {
                    "L1"
                } else {
                    "L0"
                }
            ));
        }
        println!("liveness: {}", levels.join(" "));
    }
    fn cover(&self, limit: usize) {
        let mut g = Graph::new(self.current.clone());
        let (mut old, mut dead) = (vec![false], vec![false]);
        let mut seen = HashSet::from([self.current.clone()]);
        let rank = |v: i64| if v < 0 { i64::MAX } else { v };
        let mut q = 0;
        while q < g.states.len() {
            if !old[q] {
                let es = self.enabled(&g.states[q]);
                dead[q] = es.is_empty();
                let mut ancestors = vec![q];
                let mut a = q;
                while let Some(p) = g.parent[a] {
                    ancestors.push(p);
                    a = p;
                }
                ancestors.reverse();
                for t in es {
                    let mut m = self.fire(&g.states[q], t);
                    for &a in &ancestors {
                        if (0..m.len()).all(|p| rank(m[p]) >= rank(g.states[a][p]))
                            && (0..m.len()).any(|p| rank(m[p]) > rank(g.states[a][p]))
                        {
                            for p in 0..m.len() {
                                if self.capacity[p] == 0 && rank(m[p]) > rank(g.states[a][p]) {
                                    m[p] = -1;
                                }
                            }
                        }
                    }
                    if g.states.len() == limit {
                        println!("coverability tree limit {limit} exceeded");
                        return;
                    }
                    old.push(!seen.insert(m.clone()));
                    dead.push(false);
                    g.add(m, q, t);
                }
            }
            q += 1;
        }
        println!("coverability tree nodes: {}", g.states.len());
        let mut maximum = vec![0; self.p.len()];
        for (i, m) in g.states.iter().enumerate() {
            let prefix = if let Some(p) = g.parent[i] {
                format!("<- {p} {}", self.t[g.via[i]])
            } else {
                "root".into()
            };
            println!(
                "  {i} {} {prefix}{}{}",
                mark(m),
                if old[i] { " old" } else { "" },
                if dead[i] { " dead" } else { "" }
            );
            for p in 0..m.len() {
                if rank(m[p]) > rank(maximum[p]) {
                    maximum[p] = m[p];
                }
            }
        }
        let unbounded: Vec<_> = (0..maximum.len())
            .filter(|&p| maximum[p] < 0)
            .map(|p| self.p[p].clone())
            .collect();
        println!(
            "bounds: {}\nunbounded: {}",
            mark(&maximum),
            listed(&unbounded)
        );
    }
    fn bits(&self, mask: u32) -> Vec<usize> {
        (0..self.p.len())
            .filter(|&p| mask & (1 << p) != 0)
            .collect()
    }
    fn sets(&self, trap: bool) -> Vec<u32> {
        let found: Vec<u32> = (1..1 << self.p.len())
            .filter(|&mask| {
                (0..self.t.len()).all(|t| {
                    let ps = self.bits(mask);
                    let input = ps.iter().any(|&p| self.post[p][t] > 0);
                    let output = ps.iter().any(|&p| self.pre[p][t] > 0);
                    if trap {
                        !output || input
                    } else {
                        !input || output
                    }
                })
            })
            .collect();
        let mut result: Vec<_> = found
            .iter()
            .copied()
            .filter(|&m| !found.iter().any(|&s| s != m && s & m == s))
            .collect();
        result.sort_by(|a, b| {
            a.count_ones()
                .cmp(&b.count_ones())
                .then_with(|| self.bits(*a).cmp(&self.bits(*b)))
        });
        result
    }
    fn set_text(&self, mask: u32) -> String {
        format!(
            "{{{}}}",
            self.bits(mask)
                .iter()
                .map(|&p| self.p[p].clone())
                .collect::<Vec<_>>()
                .join(",")
        )
    }
    fn realize(&self, counts: &[i64]) -> Option<Vec<usize>> {
        let mut used = vec![0; counts.len()];
        let mut stack = vec![self.current.clone()];
        let mut choices = vec![0];
        let mut path: Vec<usize> = vec![];
        let mut seen = HashSet::new();
        let total: i64 = counts.iter().sum();
        while !stack.is_empty() {
            let d = path.len();
            if d as i64 == total {
                return Some(path);
            }
            let mut chosen = None;
            for t in choices[d]..counts.len() {
                choices[d] = t + 1;
                if used[t] >= counts[t] || self.reason(&stack[d], t).is_some() {
                    continue;
                }
                used[t] += 1;
                let fresh = seen.insert(used.clone());
                used[t] -= 1;
                if fresh {
                    chosen = Some(t);
                    break;
                }
            }
            if let Some(t) = chosen {
                used[t] += 1;
                path.push(t);
                stack.push(self.fire(&stack[d], t));
                choices.push(0);
            } else {
                stack.pop();
                choices.pop();
                if let Some(t) = path.pop() {
                    used[t] -= 1;
                }
            }
        }
        None
    }
    fn invariants(&self, transpose: bool) {
        let a = if transpose {
            (0..self.t.len())
                .map(|t| {
                    (0..self.p.len())
                        .map(|p| self.post[p][t] - self.pre[p][t])
                        .collect()
                })
                .collect()
        } else {
            (0..self.p.len())
                .map(|p| {
                    (0..self.t.len())
                        .map(|t| self.post[p][t] - self.pre[p][t])
                        .collect()
                })
                .collect()
        };
        let f = flows(a);
        let ns = if transpose { &self.t } else { &self.p };
        let mut covered = vec![false; ns.len()];
        let mut bounds = vec![-1; ns.len()];
        println!(
            "{}-semiflows: {}",
            if transpose { "T" } else { "P" },
            f.len()
        );
        for c in f {
            let mut terms = vec![];
            let mut value = 0;
            for i in 0..c.len() {
                if c[i] > 0 {
                    covered[i] = true;
                    terms.push(format!(
                        "{}{}",
                        if c[i] == 1 {
                            String::new()
                        } else {
                            format!("{}*", c[i])
                        },
                        ns[i]
                    ));
                    if !transpose {
                        value += c[i] * self.current[i];
                    }
                }
            }
            let text = terms.join(" + ");
            if transpose {
                let result = self.realize(&c).map_or("not realizable".into(), |p| {
                    format!("realizable {}", self.names(&p).join(" "))
                });
                println!("  {text}: {result}");
            } else {
                println!("  {text} = {value}");
                for p in 0..c.len() {
                    if c[p] > 0 {
                        bounds[p] = if bounds[p] < 0 {
                            value / c[p]
                        } else {
                            bounds[p].min(value / c[p])
                        };
                    }
                }
            }
        }
        if !transpose {
            println!(
                "bounds: ({})",
                bounds
                    .iter()
                    .map(|b| if *b < 0 { "-".into() } else { b.to_string() })
                    .collect::<Vec<_>>()
                    .join(",")
            );
        }
        println!(
            "{}: {}",
            if transpose {
                "consistent"
            } else {
                "conservative"
            },
            yes(covered.iter().all(|v| *v))
        );
    }
    fn classify(&self) {
        let inputs: Vec<Vec<_>> = (0..self.t.len())
            .map(|t| (0..self.p.len()).filter(|&p| self.pre[p][t] > 0).collect())
            .collect();
        let outputs: Vec<Vec<_>> = (0..self.p.len())
            .map(|p| (0..self.t.len()).filter(|&t| self.pre[p][t] > 0).collect())
            .collect();
        let ordinary = (0..self.p.len())
            .all(|p| (0..self.t.len()).all(|t| self.pre[p][t] <= 1 && self.post[p][t] <= 1));
        let pure = (0..self.p.len())
            .all(|p| (0..self.t.len()).all(|t| self.pre[p][t] == 0 || self.post[p][t] == 0));
        let sm = ordinary
            && (0..self.t.len()).all(|t| {
                inputs[t].len() == 1
                    && (0..self.p.len()).filter(|&p| self.post[p][t] > 0).count() == 1
            });
        let mg = ordinary
            && (0..self.p.len()).all(|p| {
                outputs[p].len() == 1
                    && (0..self.t.len()).filter(|&t| self.post[p][t] > 0).count() == 1
            });
        let fc = ordinary
            && outputs
                .iter()
                .all(|a| a.iter().all(|&t| a.len() == 1 || inputs[t].len() == 1));
        let efc = ordinary
            && outputs.iter().all(|a| {
                outputs
                    .iter()
                    .all(|b| !a.iter().any(|t| b.contains(t)) || a == b)
            });
        for (label, v) in [
            ("ordinary", ordinary),
            ("pure", pure),
            ("state machine", sm),
            ("marked graph", mg),
            ("free choice", fc),
            ("extended free choice", efc),
        ] {
            println!("{label}: {}", yes(v));
        }
        let mut verdict = if !fc {
            "not applicable"
        } else if self.p.len() > 12 {
            "too many places"
        } else {
            "holds"
        }
        .to_string();
        if fc && self.p.len() <= 12 {
            let traps = self.sets(true);
            for s in self.sets(false) {
                if !traps
                    .iter()
                    .any(|&q| s & q == q && self.bits(q).iter().any(|&p| self.current[p] > 0))
                {
                    verdict = format!("fails at {}", self.set_text(s));
                    break;
                }
            }
        }
        println!("commoner: {verdict}");
    }
    fn workflow(&self, limit: usize) {
        let (pn, tn) = (self.p.len(), self.t.len());
        let sources: Vec<_> = (0..pn)
            .filter(|&p| (0..tn).all(|t| self.post[p][t] == 0))
            .collect();
        let sinks: Vec<_> = (0..pn)
            .filter(|&p| (0..tn).all(|t| self.pre[p][t] == 0))
            .collect();
        if sources.len() != 1 {
            println!("workflow: no ({} source places)", sources.len());
            return;
        }
        if sinks.len() != 1 {
            println!("workflow: no ({} sink places)", sinks.len());
            return;
        }
        let (i, o) = (sources[0], sinks[0]);
        let mut adj = vec![vec![]; pn + tn];
        let mut rev = adj.clone();
        for p in 0..pn {
            for t in 0..tn {
                if self.pre[p][t] > 0 {
                    adj[p].push(pn + t);
                    rev[pn + t].push(p);
                }
                if self.post[p][t] > 0 {
                    adj[pn + t].push(p);
                    rev[p].push(pn + t);
                }
            }
        }
        let (f, b) = (visit(&adj, i), visit(&rev, o));
        for (v, name) in self.p.iter().chain(&self.t).enumerate() {
            if !f[v] || !b[v] {
                println!(
                    "workflow: no ({name} is not on a path from {} to {})",
                    self.p[i], self.p[o]
                );
                return;
            }
        }
        println!("workflow: source {} sink {}", self.p[i], self.p[o]);
        let (mut start, mut goal) = (vec![0; pn], vec![0; pn]);
        start[i] = 1;
        goal[o] = 1;
        let g = self.graph(&start, limit, None);
        if g.aborted {
            println!("reachability graph limit {limit} exceeded");
            return;
        }
        let finish = g.states.iter().position(|m| *m == goal);
        let mut rev = vec![vec![]; g.states.len()];
        let mut used = vec![false; tn];
        for (u, e) in g.edges.iter().enumerate() {
            for &(t, v) in e {
                rev[v].push(u);
                used[t] = true;
            }
        }
        let option = finish.is_some_and(|v| visit(&rev, v).iter().all(|v| *v));
        let proper = g.states.iter().all(|m| m[o] < 1 || *m == goal);
        let live = used.iter().all(|v| *v);
        println!(
            "option to complete: {}\nproper completion: {}\nno dead transitions: {}\nsound: {}",
            yes(option),
            yes(proper),
            yes(live),
            yes(option && proper && live)
        );
    }
    fn execute(&mut self, w: &[&str]) -> Result<(), String> {
        let cmd = w[0];
        let expected = match cmd {
            "SET" | "PATH" => 2,
            "SIMULATE" => 3,
            "FIRE" => -1,
            "UNDO" | "REACH" | "GRAPH" | "COVER" | "WORKFLOW" => 1,
            "MARKING" | "RESET" | "ENABLED" | "CONFLICTS" | "INCIDENCE" | "PINV" | "TINV"
            | "SIPHONS" | "TRAPS" | "CLASSIFY" | "SHOW" => 0,
            _ => return Err(format!("unknown command {cmd}")),
        };
        if if expected < 0 {
            w.len() < 2
        } else {
            w.len() != expected as usize + 1
        } {
            return Err("wrong number of arguments".into());
        }
        let limit = if ["REACH", "GRAPH", "COVER", "PATH", "WORKFLOW"].contains(&cmd) {
            number(w[1], 1, 2000).ok_or_else(|| format!("invalid limit {}", w[1]))? as usize
        } else {
            0
        };
        match cmd {
            "MARKING" | "RESET" => {
                if cmd == "RESET" {
                    self.current = self.initial.clone();
                    self.history.clear();
                }
                println!("marking {}", mark(&self.current));
            }
            "SET" => {
                let p = self
                    .place(w[1])
                    .ok_or_else(|| format!("unknown place {}", w[1]))?;
                let v = number(w[2], 0, 999).ok_or_else(|| format!("invalid tokens {}", w[2]))?;
                if self.capacity[p] > 0 && v > self.capacity[p] {
                    return Err(format!("tokens exceed capacity of {}", w[1]));
                }
                self.current[p] = v;
                self.history.clear();
                println!("marking {}", mark(&self.current));
            }
            "ENABLED" => println!(
                "enabled: {}",
                listed(&self.names(&self.enabled(&self.current)))
            ),
            "FIRE" => {
                let ts: Vec<_> = w[1..]
                    .iter()
                    .map(|s| {
                        self.transition(s)
                            .ok_or_else(|| format!("unknown transition {s}"))
                    })
                    .collect::<Result<_, _>>()?;
                for (i, &t) in ts.iter().enumerate() {
                    if let Some(r) = self.reason(&self.current, t) {
                        println!(
                            "step {}: {} not enabled ({r}) at {}",
                            i + 1,
                            self.t[t],
                            mark(&self.current)
                        );
                        return Ok(());
                    }
                    self.commit(t);
                }
                println!("fired {} -> {}", ts.len(), mark(&self.current));
            }
            "UNDO" => {
                let k = number(w[1], 1, 1000).ok_or_else(|| format!("invalid count {}", w[1]))?
                    as usize;
                let h = self.history.len();
                if k > h {
                    return Err(format!("cannot undo {k}: history size {h}"));
                }
                self.current = self.history[h - k].clone();
                self.history.truncate(h - k);
                println!("marking {}", mark(&self.current));
            }
            "SIMULATE" => {
                let steps =
                    number(w[1], 1, 1000).ok_or_else(|| format!("invalid steps {}", w[1]))?;
                let mut x =
                    number(w[2], 1, 2147483646).ok_or_else(|| format!("invalid seed {}", w[2]))?;
                if w[3] != "PRIORITY" && w[3] != "RANDOM" {
                    return Err(format!("invalid mode {}", w[3]));
                }
                let mut counts = vec![0; self.t.len()];
                let mut done = 0;
                while done < steps {
                    let es = self.enabled(&self.current);
                    if es.is_empty() {
                        println!("dead (steps={done})");
                        break;
                    }
                    let mut t = es[0];
                    if w[3] == "RANDOM" {
                        x = x * 48271 % 2147483647;
                        t = es[(x % es.len() as i64) as usize];
                    } else {
                        for u in es {
                            if self.priority[u] > self.priority[t] {
                                t = u;
                            }
                        }
                    }
                    self.commit(t);
                    counts[t] += 1;
                    done += 1;
                    println!("step {done}: {} -> {}", self.t[t], mark(&self.current));
                }
                if done == steps {
                    println!("completed (steps={steps})");
                }
                println!(
                    "counts: {}",
                    self.t
                        .iter()
                        .enumerate()
                        .map(|(t, n)| format!("{n}={}", counts[t]))
                        .collect::<Vec<_>>()
                        .join(" ")
                );
            }
            "CONFLICTS" => {
                let (mut s, mut e) = (vec![], vec![]);
                for u in 0..self.t.len() {
                    for v in u + 1..self.t.len() {
                        let pair = format!("{}/{}", self.t[u], self.t[v]);
                        if (0..self.p.len()).any(|p| self.pre[p][u] > 0 && self.pre[p][v] > 0) {
                            s.push(pair.clone());
                        }
                        if self.reason(&self.current, u).is_none()
                            && self.reason(&self.current, v).is_none()
                            && (self.reason(&self.fire(&self.current, u), v).is_some()
                                || self.reason(&self.fire(&self.current, v), u).is_some())
                        {
                            e.push(pair);
                        }
                    }
                }
                println!("structural: {}\neffective: {}", listed(&s), listed(&e));
            }
            "REACH" | "GRAPH" => self.reach(limit, cmd == "GRAPH"),
            "COVER" => self.cover(limit),
            "PATH" => {
                let entries: Vec<_> = w[2].split(',').collect();
                if entries.len() != self.p.len() {
                    return Err(format!("target needs {} entries", self.p.len()));
                }
                let mut target = vec![];
                for s in entries {
                    if s == "*" {
                        target.push((0, -1));
                        continue;
                    }
                    let plus = s.ends_with('+');
                    let v = number(if plus { &s[..s.len() - 1] } else { s }, 0, 9999999999)
                        .ok_or_else(|| format!("invalid target entry {s}"))?;
                    target.push((v, if plus { -1 } else { v }));
                }
                let g = self.graph(&self.current, limit, Some(&target));
                if let Some(k) = g.found {
                    let a = self.names(&self.path(&g, k));
                    println!(
                        "reached {} length={}{}",
                        mark(&g.states[k]),
                        a.len(),
                        if a.is_empty() {
                            String::new()
                        } else {
                            format!(": {}", a.join(" "))
                        }
                    );
                } else if g.aborted {
                    println!("search limit {limit} exceeded");
                } else {
                    println!("unreachable (markings explored: {})", g.states.len());
                }
            }
            "INCIDENCE" => {
                let mut header = vec![String::new()];
                header.extend(self.t.clone());
                let mut rows = vec![header];
                for p in 0..self.p.len() {
                    let mut r = vec![self.p[p].clone()];
                    r.extend(
                        (0..self.t.len()).map(|t| (self.post[p][t] - self.pre[p][t]).to_string()),
                    );
                    rows.push(r);
                }
                let widths: Vec<_> = (0..self.t.len() + 1)
                    .map(|i| rows.iter().map(|r| r[i].len()).max().unwrap())
                    .collect();
                for r in rows {
                    let a: Vec<_> = r
                        .iter()
                        .enumerate()
                        .map(|(i, s)| {
                            if i == 0 {
                                format!("{s:<width$}", width = widths[i])
                            } else {
                                format!("{s:>width$}", width = widths[i])
                            }
                        })
                        .collect();
                    println!("{}", a.join("  ").trim_end());
                }
            }
            "PINV" | "TINV" => self.invariants(cmd == "TINV"),
            "SIPHONS" | "TRAPS" => {
                if self.p.len() > 12 {
                    return Err("more than 12 places".into());
                }
                let ss = self.sets(cmd == "TRAPS");
                println!(
                    "minimal {}: {}",
                    if cmd == "TRAPS" { "traps" } else { "siphons" },
                    ss.len()
                );
                for s in ss {
                    let tokens: i64 = self.bits(s).iter().map(|&p| self.current[p]).sum();
                    println!("  {} tokens={tokens}", self.set_text(s));
                }
            }
            "CLASSIFY" => self.classify(),
            "WORKFLOW" => self.workflow(limit),
            "SHOW" => {
                for p in 0..self.p.len() {
                    println!(
                        "place {} tokens={} capacity={}",
                        self.p[p],
                        self.initial[p],
                        if self.capacity[p] == 0 {
                            "none".into()
                        } else {
                            self.capacity[p].to_string()
                        }
                    );
                }
                for t in 0..self.t.len() {
                    let list = |m: &[[i64; 16]; 16]| {
                        let a: Vec<_> = (0..self.p.len())
                            .filter(|&p| m[p][t] > 0)
                            .map(|p| format!("{}:{}", self.p[p], m[p][t]))
                            .collect();
                        if a.is_empty() {
                            "-".into()
                        } else {
                            a.join(",")
                        }
                    };
                    println!(
                        "transition {} priority={} pre={} post={} inhibit={}",
                        self.t[t],
                        self.priority[t],
                        list(&self.pre),
                        list(&self.post),
                        list(&self.inhibitor)
                    );
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
    let blocks: usize = lines.next().unwrap().parse().unwrap();
    for _ in 0..blocks {
        let name = lines.next().unwrap().split(' ').nth(1).unwrap();
        let mut net = Net::new(name);
        loop {
            let line = lines.next().unwrap();
            if line == "END NET" {
                break;
            }
            if let Err(e) = net.define(&line.split(' ').collect::<Vec<_>>()) {
                println!("error: {e}");
            }
        }
        net.current = net.initial.clone();
        println!(
            "net {}: places={} transitions={} arcs={} inhibitors={}",
            net.name,
            net.p.len(),
            net.t.len(),
            net.arcs,
            net.inhibitors
        );
        let n: usize = lines.next().unwrap().parse().unwrap();
        for _ in 0..n {
            if let Err(e) = net.execute(&lines.next().unwrap().split(' ').collect::<Vec<_>>()) {
                println!("error: {e}");
            }
        }
    }
}
