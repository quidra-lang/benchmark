use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};
use std::ops::{Add, Sub, Mul, Div, Neg};
use std::cmp::Ordering;
type Answer = Result<Vec<String>, String>;

#[derive(Clone, Copy, Eq, PartialEq)]
struct Q {
    p: i64,
    q: i64
}

impl Q {
    fn new(p: i64, q: i64) -> Self {
        let (mut a, mut b) = (p.abs(), q.abs());
        while b != 0 {
            let r = a % b;
            a = b;
            b = r;
        }
        Self {
            p: if q < 0 {
                -p / a
            } else {
                p / a
            },
            q: q.abs() / a
        }
    }

    fn integer(n: i64) -> Self {
        Self {
            p: n,
            q: 1
        }
    }

    fn text(self) -> String {
        if self.q == 1 {
            self.p.to_string()
        } else {
            format!("{}/{}", self.p, self.q)
        }
    }

    fn value(self) -> String {
        let h = self.p.abs() * 1000000 / self.q;
        format!("{} ({}{}.{:06})", self.text(), if self.p < 0 {
            "-"
        } else {
            ""
        }, h / 1000000, h % 1000000)
    }
}
const ZERO: Q = Q {
    p: 0,
    q: 1
};
const ONE: Q = Q {
    p: 1,
    q: 1
};

impl Add for Q {
    type Output = Self;

    fn add(self, b: Self) -> Self {
        Self::new(self.p * b.q + b.p * self.q, self.q * b.q)
    }
}

impl Sub for Q {
    type Output = Self;

    fn sub(self, b: Self) -> Self {
        Self::new(self.p * b.q - b.p * self.q, self.q * b.q)
    }
}

impl Mul for Q {
    type Output = Self;

    fn mul(self, b: Self) -> Self {
        Self::new(self.p * b.p, self.q * b.q)
    }
}

impl Div for Q {
    type Output = Self;

    fn div(self, b: Self) -> Self {
        Self::new(self.p * b.q, self.q * b.p)
    }
}

impl Neg for Q {
    type Output = Self;

    fn neg(self) -> Self {
        Self {
            p: -self.p,
            q: self.q
        }
    }
}

impl Ord for Q {
    fn cmp(&self, b: &Self) -> Ordering {
        (self.p * b.q).cmp(&(b.p * self.q))
    }
}

impl PartialOrd for Q {
    fn partial_cmp(&self, b: &Self) -> Option<Ordering> {
        Some(self.cmp(b))
    }
}

fn digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())
}

fn number(raw: &str) -> Result<Q, String> {
    let mut s = raw;
    let mut factor = ONE;
    for (suffix, multiplier) in [("meg", Q::integer(1000000)), ("k", Q::integer(1000)), ("m", Q::new(1, 1000)), ("u", Q::new(1, 1000000))].iter().copied() {
        if let Some(prefix) = s.strip_suffix(suffix) {
            s = prefix;
            factor = multiplier;
            break;
        }
    }
    if let Some(prefix) = s.strip_prefix('-') {
        s = prefix;
        factor = -factor;
    }
    let value = if digits(s) {
        Some(Q::integer(s.parse().unwrap()))
    } else if let Some((a, b)) = s.split_once('.') {
        if digits(a) && digits(b) {
            Some(Q::new(format!("{}{}", a, b).parse().unwrap(), 10i64.pow(b.len() as u32)))
        } else {
            None
        }
    } else if let Some((a, b)) = s.split_once('/') {
        if digits(a) && digits(b) && b.parse::<i64>().unwrap() != 0 {
            Some(Q::new(a.parse().unwrap(), b.parse().unwrap()))
        } else {
            None
        }
    } else {
        None
    };
    value.map(|v| v * factor).ok_or_else(|| format!("invalid value {}", raw))
}

fn valid_node(s: &str) -> bool {
    s == "0" || !s.is_empty() && s.len() <= 8 && s.as_bytes()[0].is_ascii_lowercase() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

#[derive(Clone)]
struct Element {
    name: String,
    nodes: Vec<String>,
    reference: String,
    value: Q
}

impl Element {
    fn kind(&self) -> u8 {
        self.name.as_bytes()[0]
    }

    fn a(&self) -> &str {
        &self.nodes[0]
    }

    fn b(&self) -> &str {
        &self.nodes[1]
    }

    fn voltage(&self) -> bool {
        b"VEH".contains(&self.kind())
    }

    fn independent(&self) -> bool {
        b"VI".contains(&self.kind())
    }
}

struct Union {
    parent: BTreeMap<String, String>
}

impl Union {
    fn new(nodes: Vec<String>) -> Self {
        Self {
            parent: nodes.into_iter().map(|n| (n.clone(), n)).collect()
        }
    }

    fn root(&self, x: &str) -> String {
        let mut p = x;
        while self.parent[p] != p {
            p = &self.parent[p];
        }
        p.into()
    }

    fn join(&mut self, a: &str, b: &str) {
        let x = self.root(a);
        let y = self.root(b);
        if x < y {
            self.parent.insert(y, x);
        } else {
            self.parent.insert(x, y);
        }
    }
}

fn reach(start: &str, edges: &[(String, String)]) -> BTreeSet<String> {
    let mut found = BTreeSet::from([start.to_string()]);
    let mut queue = VecDeque::from(vec![start.to_string()]);
    while let Some(a) = queue.pop_front() {
        for (u, v) in edges {
            let b = if &a == u {
                v
            } else if &a == v {
                u
            } else {
                continue;
            };
            if found.insert(b.clone()) {
                queue.push_back(b.clone());
            }
        }
    }
    found
}

fn solve(a: &[Vec<Q>], b: &[Q]) -> Option<Vec<Q>> {
    let n = b.len();
    let mut m: Vec<Vec<Q>> = a.iter().zip(b).map(|(row, &v)| {
        let mut r = row.clone();
        r.push(v);
        r
    }).collect();
    for k in 0..n {
        let r = (k..n).find(|&i| m[i][k].p != 0)?;
        m.swap(k, r);
        let pivot = m[k][k];
        for j in 0..=n {
            m[k][j] = m[k][j] / pivot;
        }
        for i in 0..n {
            if i != k && m[i][k].p != 0 {
                let f = m[i][k];
                for j in 0..=n {
                    m[i][j] = m[i][j] - f * m[k][j];
                }
            }
        }
    }
    Some(m.iter().map(|r| r[n]).collect())
}

struct Equations {
    nodes: Vec<String>,
    sources: Vec<Element>,
    labels: Vec<String>,
    index: BTreeMap<String, usize>,
    a: Vec<Vec<Q>>,
    b: Vec<Q>
}

impl Equations {
    fn new(elements: &[Element]) -> Self {
        let nodes: Vec<String> = elements.iter().flat_map(|e| e.nodes.iter().cloned()).filter(|n| n != "0").collect::<BTreeSet<_>>().into_iter().collect();
        let sources: Vec<Element> = elements.iter().filter(|e| e.voltage()).cloned().collect();
        let mut labels = nodes.clone();
        labels.extend(sources.iter().map(|e| e.name.clone()));
        let index = labels.iter().cloned().enumerate().map(|(i, n)| (n, i)).collect();
        let mut eq = Self {
            a: vec![vec![ZERO; labels.len()]; labels.len()],
            b: vec![ZERO; labels.len()],
            nodes,
            sources,
            labels,
            index
        };
        for e in elements {
            let (a, b, w) = (e.a(), e.b(), e.value);
            match e.kind() {
                b'R' => {
                    let g = ONE / w;
                    eq.add(a, a, g);
                    eq.add(b, b, g);
                    eq.add(a, b, -g);
                    eq.add(b, a, -g);
                }
                b'I' => {
                    eq.rhs(a, -w);
                    eq.rhs(b, w);
                }
                b'G' => {
                    eq.add(a, &e.nodes[2], w);
                    eq.add(b, &e.nodes[3], w);
                    eq.add(a, &e.nodes[3], -w);
                    eq.add(b, &e.nodes[2], -w);
                }
                b'F' => {
                    eq.add(a, &e.reference, w);
                    eq.add(b, &e.reference, -w);
                }
                _ => {
                    eq.add(a, &e.name, ONE);
                    eq.add(&e.name, a, ONE);
                    eq.add(b, &e.name, -ONE);
                    eq.add(&e.name, b, -ONE);
                    match e.kind() {
                        b'V' => eq.rhs(&e.name, w),
                        b'E' => {
                            eq.add(&e.name, &e.nodes[2], -w);
                            eq.add(&e.name, &e.nodes[3], w);
                        },
                        b'H' => eq.add(&e.name, &e.reference, -w),
                        _ => unreachable!()
                    }
                }
            }
        }
        eq
    }

    fn add(&mut self, row: &str, column: &str, value: Q) {
        if row != "0" && column != "0" {
            let i = self.index[row];
            let j = self.index[column];
            self.a[i][j] = self.a[i][j] + value;
        }
    }

    fn add_rhs(&self, rhs: &mut [Q], row: &str, value: Q) {
        if row != "0" {
            let i = self.index[row];
            rhs[i] = rhs[i] + value;
        }
    }

    fn rhs(&mut self, row: &str, value: Q) {
        if row != "0" {
            let i = self.index[row];
            self.b[i] = self.b[i] + value;
        }
    }

    fn v(&self, y: &[Q], node: &str) -> Q {
        if node == "0" {
            ZERO
        } else {
            y[self.index[node]]
        }
    }

    fn injection(&self, a: &str, b: &str) -> Vec<Q> {
        let mut rhs = vec![ZERO; self.labels.len()];
        self.add_rhs(&mut rhs, a, ONE);
        self.add_rhs(&mut rhs, b, -ONE);
        solve(&self.a, &rhs).unwrap()
    }

    fn alone(&self, e: &Element, unit: bool) -> Vec<Q> {
        let mut rhs = vec![ZERO; self.labels.len()];
        let w = if unit {
            ONE
        } else {
            e.value
        };
        if e.kind() == b'V' {
            self.add_rhs(&mut rhs, &e.name, w);
        } else {
            self.add_rhs(&mut rhs, e.a(), -w);
            self.add_rhs(&mut rhs, e.b(), w);
        }
        solve(&self.a, &rhs).unwrap()
    }

    fn current(&self, e: &Element, y: &[Q]) -> Q {
        match e.kind() {
            b'R' => (self.v(y, e.a()) - self.v(y, e.b())) / e.value,
            b'I' => e.value,
            b'G' => e.value * (self.v(y, &e.nodes[2]) - self.v(y, &e.nodes[3])),
            b'F' => e.value * y[self.index[&e.reference]],
            _ => y[self.index[&e.name]]
        }
    }
}

#[derive(Clone)]
struct Resistor {
    name: String,
    a: String,
    b: String,
    value: Q
}

struct Circuit {
    elements: Vec<Element>
}

impl Circuit {
    fn nodes(&self) -> Vec<String> {
        self.elements.iter().flat_map(|e| e.nodes.iter().cloned()).filter(|n| n != "0").collect::<BTreeSet<_>>().into_iter().collect()
    }

    fn get(&self, name: &str) -> Result<usize, String> {
        self.elements.iter().position(|e| e.name == name).ok_or_else(|| format!("unknown element {}", name))
    }

    fn node(&self, name: &str) -> Result<(), String> {
        if name == "0" || self.nodes().iter().any(|n| n == name) {
            Ok(())
        } else {
            Err(format!("unknown node {}", name))
        }
    }

    fn floating(&self) -> Vec<String> {
        let reached = reach("0", &self.elements.iter().filter(|e| b"RVEH".contains(&e.kind())).map(|e| (e.a().into(), e.b().into())).collect::<Vec<_>>());
        self.nodes().into_iter().filter(|n| !reached.contains(n)).collect()
    }

    fn loops(&self) -> Vec<String> {
        let mut ns = self.nodes();
        ns.push("0".into());
        let mut u = Union::new(ns);
        let mut result = Vec::new();
        for e in self.elements.iter().filter(|e| e.voltage()) {
            if u.root(e.a()) == u.root(e.b()) {
                result.push(e.name.clone());
            }
            u.join(e.a(), e.b());
        }
        result
    }

    fn structure(&self) -> Result<(), String> {
        if self.nodes().is_empty() {
            return Err("no nodes".into());
        }
        if let Some(n) = self.floating().first() {
            return Err(format!("floating node {}", n));
        }
        if let Some(n) = self.loops().first() {
            return Err(format!("voltage source loop at {}", n));
        }
        Ok(())
    }

    fn add(&mut self, w: &[&str]) -> Result<(), String> {
        let name = w[0];
        let kind = name.as_bytes()[0];
        if !b"RVIEGFH".contains(&kind) {
            return Err(format!("unknown element type {}", name));
        }
        let count = if b"RVI".contains(&kind) {
            4
        } else if b"EG".contains(&kind) {
            6
        } else {
            5
        };
        if w.len() != count {
            return Err(format!("wrong field count for {}", name));
        }
        if self.elements.iter().any(|e| e.name == name) {
            return Err(format!("duplicate element {}", name));
        }
        let nodes = &w[1..if b"EG".contains(&kind) {
            5
        } else {
            3
        }];
        for &n in nodes {
            if !valid_node(n) {
                return Err(format!("invalid node {}", n));
            }
        }
        let reference = if b"FH".contains(&kind) {
            w[3]
        } else {
            ""
        };
        if b"FH".contains(&kind) && !self.elements.iter().any(|e| e.name == reference && e.kind() == b'V') {
            return Err(format!("unknown voltage source {}", reference));
        }
        let value = number(w[w.len() - 1])?;
        if kind == b'R' && value <= ZERO {
            return Err(format!("nonpositive resistance {}", name));
        }
        self.elements.push(Element {
            name: name.into(),
            nodes: nodes.iter().map(|s| s.to_string()).collect(),
            reference: reference.into(),
            value
        });
        Ok(())
    }

    fn resistance(&self, a: &str, b: &str) -> Vec<String> {
        let mut ns = self.nodes();
        ns.push("0".into());
        let mut u = Union::new(ns);
        for e in &self.elements {
            if e.kind() == b'V' {
                u.join(e.a(), e.b());
            }
        }
        let x = u.root(a);
        let y = u.root(b);
        if x == y {
            return vec![format!("Req = {}", ZERO.value())];
        }
        let edges: Vec<&Element> = self.elements.iter().filter(|e| e.kind() == b'R' && u.root(e.a()) != u.root(e.b())).collect();
        let connected = reach(&x, &edges.iter().map(|e| (u.root(e.a()), u.root(e.b()))).collect::<Vec<_>>());
        if !connected.contains(&y) {
            return vec!["Req = INFINITE".into()];
        }
        let groups: Vec<String> = connected.iter().filter(|n| *n != &y).cloned().collect();
        let index: BTreeMap<String, usize> = groups.iter().cloned().enumerate().map(|(i, n)| (n, i)).collect();
        let mut matrix = vec![vec![ZERO; groups.len()]; groups.len()];
        let mut rhs = vec![ZERO; groups.len()];
        for e in edges {
            let p = u.root(e.a());
            let q = u.root(e.b());
            if !connected.contains(&p) {
                continue;
            }
            let g = ONE / e.value;
            for (r, c, v) in [(&p, &p, g), (&q, &q, g), (&p, &q, -g), (&q, &p, -g)].iter().copied() {
                if r != &y && c != &y {
                    let i = index[r];
                    let j = index[c];
                    matrix[i][j] = matrix[i][j] + v;
                }
            }
        }
        rhs[index[&x]] = ONE;
        vec![format!("Req = {}", solve(&matrix, &rhs).unwrap()[index[&x]].value())]
    }

    fn reduce(&self, a: &str, b: &str) -> Vec<String> {
        if a == b {
            return vec![format!("Req = {}", ZERO.value())];
        }
        let mut list: Vec<Resistor> = self.elements.iter().filter(|e| e.kind() == b'R').map(|e| Resistor {
            name: e.name.clone(),
            a: e.a().into(),
            b: e.b().into(),
            value: e.value
        }).collect();
        let connected = reach(a, &list.iter().map(|r| (r.a.clone(), r.b.clone())).collect::<Vec<_>>());
        if !connected.contains(b) {
            return vec!["Req = INFINITE".into()];
        }
        list.retain(|r| connected.contains(&r.a));
        let mut out = Vec::new();
        let mut created = 0;
        loop {
            if let Some(i) = list.iter().position(|r| r.a == r.b) {
                out.push(format!("remove {}", list.remove(i).name));
                continue;
            }
            let mut degree = BTreeMap::new();
            for r in &list {
                *degree.entry(r.a.clone()).or_insert(0) += 1;
                *degree.entry(r.b.clone()).or_insert(0) += 1;
            }
            if let Some((p, _)) = degree.iter().find(|(n, d)| n.as_str() != a && n.as_str() != b && **d == 1) {
                let i = list.iter().position(|r| &r.a == p || &r.b == p).unwrap();
                out.push(format!("remove {}", list.remove(i).name));
                continue;
            }
            let mut pair = None;
            'pairs: for i in 0..list.len() {
                for j in i + 1..list.len() {
                    let x = &list[i];
                    let y = &list[j];
                    if x.a == y.a && x.b == y.b || x.a == y.b && x.b == y.a {
                        pair = Some((i, j));
                        break 'pairs;
                    }
                }
            }
            let parallel = pair.is_some();
            let node = if parallel {
                None
            } else {
                degree.iter().find(|(n, d)| n.as_str() != a && n.as_str() != b && **d == 2).map(|(n, _)| n.clone())
            };
            if let Some(p) = &node {
                let indices: Vec<usize> = list.iter().enumerate().filter(|(_, r)| &r.a == p || &r.b == p).map(|(i, _)| i).collect();
                pair = Some((indices[0], indices[1]));
            }
            let Some((i, j)) = pair else {
                break;
            };
            let x = list[i].clone();
            let y = list[j].clone();
            let value = if parallel {
                x.value * y.value / (x.value + y.value)
            } else {
                x.value + y.value
            };
            created += 1;
            let r = Resistor {
                name: format!("#{}", created),
                a: if parallel || x.a != *node.as_ref().unwrap() {
                    x.a.clone()
                } else {
                    x.b.clone()
                },
                b: if parallel {
                    x.b.clone()
                } else if y.a != *node.as_ref().unwrap() {
                    y.a.clone()
                } else {
                    y.b.clone()
                },
                value
            };
            out.push(format!("{} = {} {} {} = {}", r.name, x.name, if parallel {
                "||"
            } else {
                "+"
            }, y.name, value.value()));
            list.remove(j);
            list.remove(i);
            list.push(r);
        }
        out.push(if list.len() == 1 {
            format!("Req = {}", list[0].value.value())
        } else {
            format!("not series-parallel: {} resistors remain", list.len())
        });
        out
    }

    fn command(&mut self, w: &[&str]) -> Answer {
        let c = w[0];
        let count = match c {
            ".OP" | ".POWER" | ".MATRIX" | ".CHECK" | ".CLEAR" | ".NODES" | ".PRINT" => 0,
            ".CURRENT" | ".KCL" | ".SENS" | ".SUPERPOSITION" | ".DELETE" => 1,
            ".VOLTAGE" | ".THEVENIN" | ".NORTON" | ".MAXPOWER" | ".TF" | ".REQ" | ".REDUCE" | ".ALTER" => 2,
            ".ZPARAM" => 4,
            ".SWEEP" => 5,
            _ => return Err(format!("unknown command {}", c))
        };
        if w.len() != count + 1 {
            return Err(format!("wrong argument count for {}", c));
        }
        match c {
            ".CLEAR" => {
                let n = self.elements.len();
                self.elements.clear();
                return Ok(vec![format!("cleared {} elements", n)]);
            }
            ".PRINT" => return Ok(if self.elements.is_empty() {
                vec!["empty netlist".into()]
            } else {
                self.elements.iter().map(|e| {
                    let mut fields = vec![e.name.clone()];
                    fields.extend(e.nodes.clone());
                    if !e.reference.is_empty() {
                        fields.push(e.reference.clone());
                    }
                    fields.push(e.value.text());
                    fields.join(" ")
                }).collect()
            }),
            ".NODES" => {
                let ns = self.elements.iter().flat_map(|e| e.nodes.iter().cloned()).collect::<BTreeSet<_>>();
                return Ok(if ns.is_empty() {
                    vec!["no nodes".into()]
                } else {
                    ns.into_iter().map(|n| format!("{}: {}", n, self.elements.iter().filter(|e| e.nodes.contains(&n)).map(|e| e.name.as_str()).collect::<Vec<_>>().join(" "))).collect()
                });
            }
            ".DELETE" => {
                let i = self.get(w[1])?;
                if let Some(e) = self.elements.iter().find(|e| b"FH".contains(&e.kind()) && e.reference == w[1]) {
                    return Err(format!("{} is referenced by {}", w[1], e.name));
                }
                self.elements.remove(i);
                return Ok(vec![format!("deleted {}", w[1])]);
            }
            ".ALTER" => {
                let i = self.get(w[1])?;
                let v = number(w[2])?;
                if self.elements[i].kind() == b'R' && v <= ZERO {
                    return Err(format!("nonpositive resistance {}", w[1]));
                }
                let old = self.elements[i].value;
                self.elements[i].value = v;
                return Ok(vec![format!("altered {}: {} -> {}", w[1], old.text(), v.text())]);
            }
            ".CHECK" => {
                let ns = self.nodes();
                if ns.is_empty() {
                    return Ok(vec!["no nodes".into()]);
                }
                let mut out = Vec::new();
                for n in ns {
                    if self.elements.iter().map(|e| usize::from(e.a() == n) + usize::from(e.b() == n)).sum::<usize>() < 2 {
                        out.push(format!("dangling node {}", n));
                    }
                }
                out.extend(self.floating().iter().map(|n| format!("floating node {}", n)));
                out.extend(self.loops().iter().map(|n| format!("voltage source loop at {}", n)));
                if out.is_empty() {
                    let eq = Equations::new(&self.elements);
                    if solve(&eq.a, &eq.b).is_none() {
                        out.push("singular matrix".into());
                    }
                }
                if out.is_empty() {
                    out.push("ok".into());
                }
                return Ok(out);
            }
            ".REQ" | ".REDUCE" => {
                self.node(w[1])?;
                self.node(w[2])?;
                return Ok(if c == ".REQ" {
                    self.resistance(w[1], w[2])
                } else {
                    self.reduce(w[1], w[2])
                });
            }
            ".SWEEP" => {
                let i = self.get(w[1])?;
                let from = number(w[2])?;
                let to = number(w[3])?;
                let step = number(w[4])?;
                self.node(w[5])?;
                if step <= ZERO {
                    return Err("invalid sweep step".into());
                }
                if from > to {
                    return Err("invalid sweep range".into());
                }
                let ratio = (to - from) / step;
                let k = ratio.p / ratio.q + 1;
                if k > 20 {
                    return Err("too many sweep points".into());
                }
                if self.elements[i].kind() == b'R' && from <= ZERO {
                    return Err(format!("nonpositive resistance {}", w[1]));
                }
                self.structure()?;
                let mut out = Vec::new();
                for j in 0..k {
                    let x = from + Q::integer(j) * step;
                    let mut elements = self.elements.clone();
                    elements[i].value = x;
                    let eq = Equations::new(&elements);
                    out.push(format!("{} = {}: {}", w[1], x.text(), solve(&eq.a, &eq.b).map_or("singular matrix".into(), |y| format!("V({}) = {}", w[5], eq.v(&y, w[5]).value()))));
                }
                return Ok(out);
            }
            _ => ()
        }
        match c {
            ".CURRENT" => {
                self.get(w[1])?;
            }
            ".VOLTAGE" | ".THEVENIN" | ".NORTON" | ".MAXPOWER" => {
                self.node(w[1])?;
                self.node(w[2])?;
            }
            ".KCL" | ".SENS" | ".SUPERPOSITION" => self.node(w[1])?,
            ".ZPARAM" => for n in &w[1..] {
                self.node(n)?;
            },
            ".TF" => {
                self.node(w[1])?;
                let e = &self.elements[self.get(w[2])?];
                if !e.independent() {
                    return Err(format!("not an independent source {}", e.name));
                }
            }
            _ => ()
        }
        self.structure()?;
        let eq = Equations::new(&self.elements);
        if c == ".MATRIX" {
            let unknowns: Vec<String> = eq.nodes.iter().map(|n| format!("V({})", n)).chain(eq.sources.iter().map(|e| format!("I({})", e.name))).collect();
            let mut out = vec![format!("unknowns: {}", unknowns.join(" "))];
            for i in 0..eq.labels.len() {
                out.push(format!("{}: {} | {}", eq.labels[i], eq.a[i].iter().map(|q| q.text()).collect::<Vec<_>>().join(" "), eq.b[i].text()));
            }
            return Ok(out);
        }
        let y = solve(&eq.a, &eq.b).ok_or("singular matrix")?;
        let v = |n: &str| eq.v(&y, n);
        let mut out = Vec::new();
        match c {
            ".OP" => {
                out.extend(eq.nodes.iter().map(|n| format!("V({}) = {}", n, v(n).value())));
                out.extend(eq.sources.iter().map(|e| format!("I({}) = {}", e.name, eq.current(e, &y).value())));
            }
            ".CURRENT" => out.push(format!("I({}) = {}", w[1], eq.current(&self.elements[self.get(w[1])?], &y).value())),
            ".VOLTAGE" => out.push(format!("V({},{}) = {}", w[1], w[2], (v(w[1]) - v(w[2])).value())),
            ".POWER" => {
                let (mut absorbed, mut delivered, mut total) = (ZERO, ZERO, ZERO);
                for e in &self.elements {
                    let p = (v(e.a()) - v(e.b())) * eq.current(e, &y);
                    out.push(format!("P({}) = {}", e.name, p.value()));
                    if p > ZERO {
                        absorbed = absorbed + p;
                    }
                    if p < ZERO {
                        delivered = delivered - p;
                    }
                    total = total + p;
                }
                out.push(format!("absorbed = {}", absorbed.value()));
                out.push(format!("delivered = {}", delivered.value()));
                out.push(format!("total = {}", total.value()));
            }
            ".KCL" => {
                let mut sum = ZERO;
                for e in &self.elements {
                    if e.a() == w[1] || e.b() == w[1] {
                        let i = if e.a() == w[1] && e.b() == w[1] {
                            ZERO
                        } else if e.a() == w[1] {
                            eq.current(e, &y)
                        } else {
                            -eq.current(e, &y)
                        };
                        sum = sum + i;
                        out.push(format!("I({}) leaving {} = {}", e.name, w[1], i.value()));
                    }
                }
                out.push(format!("sum = {}", sum.value()));
            }
            ".THEVENIN" | ".NORTON" | ".MAXPOWER" => {
                let z = eq.injection(w[1], w[2]);
                let voltage = v(w[1]) - v(w[2]);
                let resistance = eq.v(&z, w[1]) - eq.v(&z, w[2]);
                if c == ".NORTON" && resistance.p == 0 {
                    return Err("zero thevenin resistance".into());
                }
                if c == ".MAXPOWER" && resistance <= ZERO {
                    return Err("nonpositive thevenin resistance".into());
                }
                match c {
                    ".THEVENIN" => {
                        out.push(format!("Vth = {}", voltage.value()));
                        out.push(format!("Rth = {}", resistance.value()));
                    },
                    ".NORTON" => {
                        out.push(format!("In = {}", (voltage / resistance).value()));
                        out.push(format!("Rn = {}", resistance.value()));
                    },
                    _ => {
                        out.push(format!("RL = {}", resistance.value()));
                        out.push(format!("Pmax = {}", (voltage * voltage / (Q::integer(4) * resistance)).value()));
                    }
                }
            }
            ".TF" => {
                let e = &self.elements[self.get(w[2])?];
                let z = eq.alone(e, true);
                out.push(format!("gain = {}", eq.v(&z, w[1]).value()));
                if e.kind() == b'V' {
                    let i = z[eq.index[&e.name]];
                    out.push(format!("input resistance = {}", if i.p == 0 {
                        "INFINITE".into()
                    } else {
                        (-ONE / i).value()
                    }));
                } else {
                    out.push(format!("input resistance = {}", (eq.v(&z, e.b()) - eq.v(&z, e.a())).value()));
                }
                out.push(format!("output resistance = {}", eq.v(&eq.injection(w[1], "0"), w[1]).value()));
            }
            ".SENS" => for e in &self.elements {
                let mut d = vec![ZERO; eq.labels.len()];
                match e.kind() {
                    b'R' => {
                        let t = eq.current(e, &y) / e.value;
                        eq.add_rhs(&mut d, e.a(), t);
                        eq.add_rhs(&mut d, e.b(), -t);
                    },
                    b'I' => {
                        eq.add_rhs(&mut d, e.a(), -ONE);
                        eq.add_rhs(&mut d, e.b(), ONE);
                    },
                    b'G' | b'F' => {
                        let t = if e.kind() == b'G' {
                            v(&e.nodes[2]) - v(&e.nodes[3])
                        } else {
                            y[eq.index[&e.reference]]
                        };
                        eq.add_rhs(&mut d, e.a(), -t);
                        eq.add_rhs(&mut d, e.b(), t);
                    },
                    b'V' => eq.add_rhs(&mut d, &e.name, ONE),
                    b'E' => eq.add_rhs(&mut d, &e.name, v(&e.nodes[2]) - v(&e.nodes[3])),
                    b'H' => eq.add_rhs(&mut d, &e.name, y[eq.index[&e.reference]]),
                    _ => unreachable!()
                }
                out.push(format!("dV({})/d{} = {}", w[1], e.name, eq.v(&solve(&eq.a, &d).unwrap(), w[1]).value()));
            },
            ".ZPARAM" => {
                let z1 = eq.injection(w[1], w[2]);
                let z2 = eq.injection(w[3], w[4]);
                for (name, z, a, b) in [("z11", &z1, w[1], w[2]), ("z12", &z2, w[1], w[2]), ("z21", &z1, w[3], w[4]), ("z22", &z2, w[3], w[4])].iter().copied() {
                    out.push(format!("{} = {}", name, (eq.v(z, a) - eq.v(z, b)).value()));
                }
            }
            ".SUPERPOSITION" => {
                let mut total = ZERO;
                for e in self.elements.iter().filter(|e| e.independent()) {
                    let value = eq.v(&eq.alone(e, false), w[1]);
                    total = total + value;
                    out.push(format!("{}: V({}) = {}", e.name, w[1], value.value()));
                }
                out.push(format!("total: V({}) = {}", w[1], total.value()));
            }
            _ => unreachable!()
        }
        Ok(out)
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut circuit = Circuit {
        elements: Vec::new()
    };
    for (i, line) in input.lines().enumerate() {
        if line == ".END" {
            break;
        }
        if line.starts_with('*') {
            continue;
        }
        let words: Vec<&str> = line.split(' ').collect();
        let result = if line.starts_with('.') {
            circuit.command(&words)
        } else {
            circuit.add(&words).map(|_| Vec::new())
        };
        match result {
            Ok(lines) => for line in lines {
                println!("{}", line);
            },
            Err(reason) => println!("error: line {}: {}", i + 1, reason)
        }
    }
}
