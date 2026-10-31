use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

type Answer = Result<Vec<String>, String>;

fn error(s: impl Into<String>) -> String {
    format!("error: {}", s.into())
}

fn time(s: &str) -> i64 {
    s[..2].parse::<i64>().unwrap() * 60 + s[3..].parse::<i64>().unwrap()
}

fn time_text(t: i64) -> String {
    format!("{:02}:{:02}", t / 60, t % 60)
}

fn name(n: usize) -> String {
    if n == 0 { "D".into() } else { n.to_string() }
}

fn notation(p: &[usize]) -> String {
    let mut words = vec!["D".into()];
    words.extend(p.iter().map(usize::to_string));
    words.push("D".into());
    words.join("-")
}
#[derive(Clone)]
struct Stop {
    x: i64,
    y: i64,
    demand: i64,
    service: i64,
    window: Option<(i64, i64)>,
}
#[derive(Clone)]
struct Plan {
    capacity: i64,
    routes: Vec<Vec<usize>>,
}

struct Run {
    lines: Vec<String>,
    returned: i64,
    violations: i64,
    lateness: i64,
}

struct TourMove {
    path: Vec<usize>,
    text: String,
}

struct PlanMove {
    routes: Vec<Vec<usize>>,
    text: String,
}

struct Workbench {
    depot: Option<(i64, i64)>,
    start: i64,
    stops: BTreeMap<usize, Stop>,
    tour: Option<Vec<usize>>,
    plan: Option<Plan>,
}

impl Workbench {
    fn point(&self, n: usize) -> (i64, i64) {
        if n == 0 {
            self.depot.unwrap()
        } else {
            let s = &self.stops[&n];
            (s.x, s.y)
        }
    }
    fn d(&self, a: usize, b: usize) -> i64 {
        let x = self.point(a);
        let y = self.point(b);
        (x.0 - y.0).abs() + (x.1 - y.1).abs()
    }
    fn length(&self, p: &[usize]) -> i64 {
        let mut at = 0;
        let mut sum = 0;
        for &n in p {
            sum += self.d(at, n);
            at = n;
        }
        sum + self.d(at, 0)
    }
    fn load(&self, p: &[usize]) -> i64 {
        p.iter().map(|n| self.stops[n].demand).sum()
    }
    fn normalize(mut routes: Vec<Vec<usize>>) -> Vec<Vec<usize>> {
        routes.retain(|r| !r.is_empty());
        for r in &mut routes {
            if r.first() > r.last() {
                r.reverse();
            }
        }
        routes.sort_by_key(|r| *r.iter().min().unwrap());
        routes
    }
    fn total(&self, p: &Plan) -> i64 {
        p.routes.iter().map(|r| self.length(r)).sum()
    }
    fn route_lines(&self, p: &Plan) -> Vec<String> {
        p.routes
            .iter()
            .enumerate()
            .map(|(i, r)| {
                format!(
                    "route {}: {} load {} length {}",
                    i + 1,
                    notation(r),
                    self.load(r),
                    self.length(r)
                )
            })
            .collect()
    }
    fn construction(&self) -> Result<(), String> {
        if self.depot.is_none() {
            return Err(error("no depot"));
        }
        if self.stops.is_empty() {
            return Err(error("no stops"));
        }
        Ok(())
    }
    fn tour(&self) -> Result<Vec<usize>, String> {
        self.tour.clone().ok_or_else(|| error("no tour"))
    }
    fn plan(&self) -> Result<Plan, String> {
        self.plan.clone().ok_or_else(|| error("no plan"))
    }
    fn capacity(&self, q: i64) -> Result<(), String> {
        for (n, s) in &self.stops {
            if s.demand > q {
                return Err(error(format!(
                    "stop {} demand {} exceeds capacity {}",
                    n, s.demand, q
                )));
            }
        }
        Ok(())
    }
    fn run(&self, p: &[usize]) -> Run {
        let mut at = 0;
        let mut t = self.start;
        let mut wait = 0;
        let mut service = 0;
        let mut violations = 0;
        let mut late = 0;
        let mut out = Vec::new();
        for &n in p {
            let s = &self.stops[&n];
            let arrival = t + self.d(at, n);
            let w = (s.window.map_or(arrival, |w| w.0) - arrival).max(0);
            let begin = arrival + w;
            let e = (arrival - s.window.map_or(arrival, |w| w.1)).max(0);
            t = begin + s.service;
            wait += w;
            service += s.service;
            if e > 0 {
                violations += 1;
            }
            late += e;
            out.push(format!(
                "{} arrive {} wait {} begin {} leave {} {}",
                n,
                time_text(arrival),
                w,
                time_text(begin),
                time_text(t),
                if e > 0 {
                    format!("late {}", e)
                } else {
                    "ok".into()
                }
            ));
            at = n;
        }
        t += self.d(at, 0);
        out.push(format!(
            "return {}, travel {}, wait {}, service {}, violations {}, lateness {}",
            time_text(t),
            self.length(p),
            wait,
            service,
            violations,
            late
        ));
        Run {
            lines: out,
            returned: t,
            violations,
            lateness: late,
        }
    }
    fn first_tour_move(&self, p: &[usize], kind: &str) -> Option<TourMove> {
        let before = self.length(p);
        let n = p.len();
        if kind == "OROPT" {
            for size in 1..=3 {
                if size > n {
                    continue;
                }
                for i in 0..=n - size {
                    let segment = &p[i..i + size];
                    let rest = p[..i]
                        .iter()
                        .chain(&p[i + size..])
                        .copied()
                        .collect::<Vec<_>>();
                    for j in 0..=rest.len() {
                        if j == i {
                            continue;
                        }
                        let next = rest[..j]
                            .iter()
                            .chain(segment)
                            .chain(&rest[j..])
                            .copied()
                            .collect::<Vec<_>>();
                        let gain = before - self.length(&next);
                        if gain > 0 {
                            return Some(TourMove {
                                path: next,
                                text: format!(
                                    "move {} after {} gain {}",
                                    segment
                                        .iter()
                                        .map(usize::to_string)
                                        .collect::<Vec<_>>()
                                        .join("-"),
                                    name(if j == 0 { 0 } else { rest[j - 1] }),
                                    gain
                                ),
                            });
                        }
                    }
                }
            }
        } else {
            for i in 0..n.saturating_sub(1) {
                for j in i + 1..n {
                    let mut next = p.to_vec();
                    if kind == "TWOOPT" {
                        next[i..=j].reverse();
                    } else {
                        next.swap(i, j);
                    }
                    let gain = before - self.length(&next);
                    if gain > 0 {
                        return Some(TourMove {
                            path: next,
                            text: if kind == "TWOOPT" {
                                format!("reverse {}..{} gain {}", p[i], p[j], gain)
                            } else {
                                format!("swap {} and {} gain {}", p[i], p[j], gain)
                            },
                        });
                    }
                }
            }
        }
        None
    }
    fn first_plan_move(&self, p: &Plan, kind: &str) -> Option<PlanMove> {
        let rs = &p.routes;
        let k = rs.len();
        let replaced = |r: usize, a: Vec<usize>, t: usize, b: Vec<usize>| {
            let mut next = rs.clone();
            next[r] = a;
            next[t] = b;
            next
        };
        if kind == "RELOCATE" {
            for r in 0..k {
                for pos in 0..rs[r].len() {
                    for t in 0..k {
                        if t == r {
                            continue;
                        }
                        let c = rs[r][pos];
                        if self.load(&rs[t]) + self.stops[&c].demand > p.capacity {
                            continue;
                        }
                        for j in 0..=rs[t].len() {
                            let mut a = rs[r].clone();
                            a.remove(pos);
                            let mut b = rs[t].clone();
                            b.insert(j, c);
                            let gain = self.length(&rs[r]) + self.length(&rs[t])
                                - self.length(&a)
                                - self.length(&b);
                            if gain > 0 {
                                return Some(PlanMove {
                                    routes: replaced(r, a, t, b),
                                    text: format!(
                                        "relocate {} from route {} to route {} after {} gain {}",
                                        c,
                                        r + 1,
                                        t + 1,
                                        name(if j == 0 { 0 } else { rs[t][j - 1] }),
                                        gain
                                    ),
                                });
                            }
                        }
                    }
                }
            }
        } else {
            for r in 0..k {
                for t in r + 1..k {
                    if kind == "EXCHANGE" {
                        for pos in 0..rs[r].len() {
                            for j in 0..rs[t].len() {
                                let c = rs[r][pos];
                                let e = rs[t][j];
                                let mut a = rs[r].clone();
                                let mut b = rs[t].clone();
                                a[pos] = e;
                                b[j] = c;
                                if self.load(&a) > p.capacity || self.load(&b) > p.capacity {
                                    continue;
                                }
                                let gain = self.length(&rs[r]) + self.length(&rs[t])
                                    - self.length(&a)
                                    - self.length(&b);
                                if gain > 0 {
                                    return Some(PlanMove {
                                        routes: replaced(r, a, t, b),
                                        text: format!(
                                            "exchange {} (route {}) with {} (route {}) gain {}",
                                            c,
                                            r + 1,
                                            e,
                                            t + 1,
                                            gain
                                        ),
                                    });
                                }
                            }
                        }
                    } else {
                        for i in 0..=rs[r].len() {
                            for j in 0..=rs[t].len() {
                                let a = rs[r][..i]
                                    .iter()
                                    .chain(&rs[t][j..])
                                    .copied()
                                    .collect::<Vec<_>>();
                                let b = rs[t][..j]
                                    .iter()
                                    .chain(&rs[r][i..])
                                    .copied()
                                    .collect::<Vec<_>>();
                                if self.load(&a) > p.capacity || self.load(&b) > p.capacity {
                                    continue;
                                }
                                let gain = self.length(&rs[r]) + self.length(&rs[t])
                                    - self.length(&a)
                                    - self.length(&b);
                                if gain > 0 {
                                    return Some(PlanMove {
                                        routes: replaced(r, a, t, b),
                                        text: format!(
                                            "cross route {} after {} with route {} after {} gain {}",
                                            r + 1,
                                            name(if i == 0 { 0 } else { rs[r][i - 1] }),
                                            t + 1,
                                            name(if j == 0 { 0 } else { rs[t][j - 1] }),
                                            gain
                                        ),
                                    });
                                }
                            }
                        }
                    }
                }
            }
        }
        None
    }
    fn mst(&self, initial: usize, vertices: &[usize]) -> (i64, Vec<String>) {
        let mut entered = vec![initial];
        let mut left = vertices.iter().copied().collect::<BTreeSet<_>>();
        left.remove(&initial);
        let mut sum = 0;
        let mut edges = Vec::new();
        while !left.is_empty() {
            let mut best = None;
            for &c in &left {
                for (i, &p) in entered.iter().enumerate() {
                    let candidate = (self.d(p, c), c, i);
                    if best.is_none_or(|old| candidate < old) {
                        best = Some(candidate);
                    }
                }
            }
            let (weight, c, i) = best.unwrap();
            let p = entered[i];
            entered.push(c);
            left.remove(&c);
            sum += weight;
            edges.push(format!("{}-{}", name(p), c));
        }
        (sum, edges)
    }
    fn exact_cost(
        &self,
        ids: &[usize],
        mask: usize,
        at: usize,
        memo: &mut BTreeMap<(usize, usize), i64>,
    ) -> i64 {
        if mask == (1 << ids.len()) - 1 {
            return self.d(at, 0);
        }
        if let Some(&value) = memo.get(&(mask, at)) {
            return value;
        }
        let mut best = i64::MAX;
        for (i, &n) in ids.iter().enumerate() {
            if mask & (1 << i) == 0 {
                best = best.min(self.d(at, n) + self.exact_cost(ids, mask | (1 << i), n, memo));
            }
        }
        memo.insert((mask, at), best);
        best
    }
    fn command(&mut self, w: &[&str]) -> Answer {
        let c = w[0];
        let a = &w[1..];
        let n = |i: usize| a[i].parse::<i64>().unwrap();
        let id = |i: usize| a[i].parse::<usize>().unwrap();
        let mut out = Vec::new();
        match c {
            "DEPOT" => {
                self.depot = Some((n(0), n(1)));
                return Ok(vec![format!("depot at ({},{})", a[0], a[1])]);
            }
            "START" => {
                self.start = time(a[0]);
                return Ok(vec![format!("start {}", time_text(self.start))]);
            }
            "STOP" => {
                let number = id(0);
                if self.stops.contains_key(&number) {
                    return Err(error(format!("stop {} already exists", number)));
                }
                let window = if a.len() == 7 {
                    Some((time(a[5]), time(a[6])))
                } else {
                    None
                };
                if window.is_some_and(|(a, b)| a > b) {
                    return Err(error("invalid window"));
                }
                self.stops.insert(
                    number,
                    Stop {
                        x: n(1),
                        y: n(2),
                        demand: n(3),
                        service: n(4),
                        window,
                    },
                );
                self.tour = None;
                self.plan = None;
                return Ok(vec![format!("stop {} added", number)]);
            }
            "REMOVE" => {
                let number = id(0);
                if self.stops.remove(&number).is_none() {
                    return Err(error(format!("unknown stop {}", number)));
                }
                if self.stops.is_empty() {
                    self.tour = None;
                    self.plan = None;
                } else {
                    if let Some(p) = &mut self.tour {
                        p.retain(|&n| n != number);
                    }
                    if let Some(p) = &mut self.plan {
                        for r in &mut p.routes {
                            r.retain(|&n| n != number);
                        }
                        p.routes = Self::normalize(std::mem::take(&mut p.routes));
                    }
                }
                return Ok(vec![format!("stop {} removed", number)]);
            }
            "LIST" => {
                out.push(
                    self.depot
                        .map_or("depot none".into(), |(x, y)| format!("depot ({},{})", x, y)),
                );
                out.push(format!("start {}", time_text(self.start)));
                out.push(format!("stops {}", self.stops.len()));
                for (n, s) in &self.stops {
                    out.push(format!(
                        "{} at ({},{}) demand {} service {} window {}",
                        n,
                        s.x,
                        s.y,
                        s.demand,
                        s.service,
                        s.window.map_or("none".into(), |(a, b)| format!(
                            "{}-{}",
                            time_text(a),
                            time_text(b)
                        ))
                    ));
                }
                return Ok(out);
            }
            "MATRIX" => {
                if self.depot.is_none() {
                    return Err(error("no depot"));
                }
                let mut ids = vec![0];
                ids.extend(self.stops.keys().copied());
                let mut header = vec![String::new()];
                header.extend(ids.iter().map(|&n| name(n)));
                let mut rows = vec![header];
                for &x in &ids {
                    let mut row = vec![name(x)];
                    row.extend(ids.iter().map(|&y| self.d(x, y).to_string()));
                    rows.push(row);
                }
                let width = rows.iter().flatten().map(String::len).max().unwrap();
                return Ok(rows
                    .iter()
                    .map(|r| {
                        r.iter()
                            .map(|s| format!("{:>width$}", s))
                            .collect::<Vec<_>>()
                            .join(" ")
                    })
                    .collect());
            }
            "TOUR" => {
                let p = self.tour()?;
                return Ok(vec![format!(
                    "tour: {} length {}",
                    notation(&p),
                    self.length(&p)
                )]);
            }
            "TIMECHECK" => {
                let p = if a.is_empty() {
                    let p = self.tour()?;
                    out.push(format!("timecheck tour depart {}", time_text(self.start)));
                    p
                } else {
                    let p = self.plan()?;
                    let r = id(0);
                    if r > p.routes.len() {
                        return Err(error(format!("no route {}", r)));
                    }
                    out.push(format!(
                        "timecheck route {} depart {}",
                        r,
                        time_text(self.start)
                    ));
                    p.routes[r - 1].clone()
                };
                out.extend(self.run(&p).lines);
                return Ok(out);
            }
            "TWOOPT" | "OROPT" | "SWAP" => {
                let mut p = self.tour()?;
                let before = self.length(&p);
                let mut count = 0;
                while let Some(m) = self.first_tour_move(&p, c) {
                    out.push(m.text);
                    p = m.path;
                    count += 1;
                }
                out.push(format!(
                    "{}: moves {}, length {} -> {}",
                    c.to_lowercase(),
                    count,
                    before,
                    self.length(&p)
                ));
                self.tour = Some(p);
                return Ok(out);
            }
            "ROUTES" => {
                let p = self.plan()?;
                out.push(format!(
                    "plan: capacity {}, routes {}, length {}",
                    p.capacity,
                    p.routes.len(),
                    self.total(&p)
                ));
                out.extend(self.route_lines(&p));
                return Ok(out);
            }
            "RELOCATE" | "EXCHANGE" | "CROSS" => {
                let mut p = self.plan()?;
                let before = self.total(&p);
                let old_count = p.routes.len();
                let mut count = 0;
                while let Some(m) = self.first_plan_move(&p, c) {
                    out.push(m.text);
                    p.routes = Self::normalize(m.routes);
                    count += 1;
                }
                let route_part = if c == "EXCHANGE" {
                    String::new()
                } else {
                    format!("routes {} -> {}, ", old_count, p.routes.len())
                };
                out.push(format!(
                    "{}: moves {}, {}length {} -> {}",
                    c.to_lowercase(),
                    count,
                    route_part,
                    before,
                    self.total(&p)
                ));
                self.plan = Some(p);
                return Ok(out);
            }
            "ROUTEOPT" => {
                let mut p = self.plan()?;
                let before = self.total(&p);
                for (i, route) in p.routes.iter_mut().enumerate() {
                    let old = self.length(route);
                    let mut count = 0;
                    while let Some(m) = self.first_tour_move(route, "TWOOPT") {
                        *route = m.path;
                        count += 1;
                    }
                    out.push(format!(
                        "route {}: moves {}, length {} -> {}",
                        i + 1,
                        count,
                        old,
                        self.length(route)
                    ));
                }
                p.routes = Self::normalize(p.routes);
                out.push(format!("routeopt: length {} -> {}", before, self.total(&p)));
                self.plan = Some(p);
                return Ok(out);
            }
            "REPORT" => {
                let demand: i64 = self.stops.values().map(|s| s.demand).sum();
                out.push(format!(
                    "report: stops {}, demand {}, service {}, windows {}",
                    self.stops.len(),
                    demand,
                    self.stops.values().map(|s| s.service).sum::<i64>(),
                    self.stops.values().filter(|s| s.window.is_some()).count()
                ));
                if let Some(p) = &self.tour {
                    let r = self.run(p);
                    out.push(format!(
                        "tour: length {}, return {}, violations {}, lateness {}",
                        self.length(p),
                        time_text(r.returned),
                        r.violations,
                        r.lateness
                    ));
                } else {
                    out.push("tour: none".into());
                }
                if let Some(p) = &self.plan {
                    let runs = p.routes.iter().map(|r| self.run(r)).collect::<Vec<_>>();
                    let capacity = p.routes.len() as i64 * p.capacity;
                    let u = (2000 * demand + capacity) / (2 * capacity);
                    out.push(format!("plan: capacity {}, routes {}, length {}, utilization {}.{}%, return {}, violations {}, lateness {}",p.capacity,p.routes.len(),self.total(p),u/10,u%10,time_text(runs.iter().map(|r|r.returned).max().unwrap()),runs.iter().map(|r|r.violations).sum::<i64>(),runs.iter().map(|r|r.lateness).sum::<i64>()));
                } else {
                    out.push("plan: none".into());
                }
                return Ok(out);
            }
            "SPLIT" => {
                let p = self.tour()?;
                let q = n(0);
                self.capacity(q)?;
                let mut values = vec![i64::MAX; p.len() + 1];
                let mut previous = vec![0; p.len() + 1];
                values[0] = 0;
                for j in 1..=p.len() {
                    for i in 0..j {
                        let part = &p[i..j];
                        if self.load(part) <= q {
                            let candidate = values[i] + self.length(part);
                            if candidate < values[j] {
                                values[j] = candidate;
                                previous[j] = i;
                            }
                        }
                    }
                }
                let mut routes = Vec::new();
                let mut j = p.len();
                while j > 0 {
                    let i = previous[j];
                    routes.push(p[i..j].to_vec());
                    j = i;
                }
                let p = Plan {
                    capacity: q,
                    routes: Self::normalize(routes),
                };
                out.push(format!(
                    "split: capacity {}, routes {}, length {}",
                    q,
                    p.routes.len(),
                    self.total(&p)
                ));
                out.extend(self.route_lines(&p));
                self.plan = Some(p);
                return Ok(out);
            }
            _ => {}
        }
        self.construction()?;
        match c {
            "ORDER" => {
                let ids = a
                    .iter()
                    .map(|s| s.parse::<usize>().unwrap())
                    .collect::<Vec<_>>();
                for n in &ids {
                    if !self.stops.contains_key(n) {
                        return Err(error(format!("unknown stop {}", n)));
                    }
                }
                let mut seen = BTreeSet::new();
                for &n in &ids {
                    if !seen.insert(n) {
                        return Err(error(format!("duplicate stop {}", n)));
                    }
                }
                if ids.len() != self.stops.len() {
                    return Err(error(format!(
                        "order has {} stops, expected {}",
                        ids.len(),
                        self.stops.len()
                    )));
                }
                self.tour = Some(ids);
            }
            "NEAREST" => {
                let mut left = self.stops.keys().copied().collect::<BTreeSet<_>>();
                let mut p = Vec::new();
                let mut at = 0;
                while !left.is_empty() {
                    let next = *left.iter().min_by_key(|&&n| (self.d(at, n), n)).unwrap();
                    p.push(next);
                    left.remove(&next);
                    at = next;
                }
                self.tour = Some(p);
            }
            "INSERTION" => {
                let mut p = Vec::new();
                while p.len() < self.stops.len() {
                    let mut best = None;
                    for &n in self.stops.keys() {
                        if p.contains(&n) {
                            continue;
                        }
                        for j in 0..=p.len() {
                            let left = if j == 0 { 0 } else { p[j - 1] };
                            let right = if j == p.len() { 0 } else { p[j] };
                            let candidate = (
                                self.d(left, n) + self.d(n, right) - self.d(left, right),
                                n,
                                j,
                            );
                            if best.is_none_or(|old| candidate < old) {
                                best = Some(candidate);
                            }
                        }
                    }
                    let (_, n, j) = best.unwrap();
                    p.insert(j, n);
                }
                self.tour = Some(p);
            }
            "EXACT" => {
                if self.stops.len() > 10 {
                    return Err(error(format!(
                        "too many stops for exact ({})",
                        self.stops.len()
                    )));
                }
                let ids = self.stops.keys().copied().collect::<Vec<_>>();
                let full = (1 << ids.len()) - 1;
                let mut memo = BTreeMap::new();
                let mut mask = 0;
                let mut at = 0;
                let mut p = Vec::new();
                while mask != full {
                    let target = self.exact_cost(&ids, mask, at, &mut memo);
                    let i = (0..ids.len())
                        .find(|&i| {
                            mask & (1 << i) == 0
                                && self.d(at, ids[i])
                                    + self.exact_cost(&ids, mask | (1 << i), ids[i], &mut memo)
                                    == target
                        })
                        .unwrap();
                    at = ids[i];
                    p.push(at);
                    mask |= 1 << i;
                }
                self.tour = Some(p);
            }
            "BOUND" => {
                let ids = self.stops.keys().copied().collect::<Vec<_>>();
                let (m, edges) = self.mst(0, &ids);
                let tree = if ids.len() == 1 {
                    2 * self.d(0, ids[0])
                } else {
                    let mut distances = ids.iter().map(|&n| self.d(0, n)).collect::<Vec<_>>();
                    distances.sort();
                    self.mst(ids[0], &ids).0 + distances[0] + distances[1]
                };
                let bound = m.max(tree);
                out.push(format!("mst: {} (length {})", edges.join(" "), m));
                out.push(format!(
                    "bound: mst {}, one-tree {}, best {}",
                    m, tree, bound
                ));
                if let Some(p) = &self.tour {
                    let l = self.length(p);
                    let u = if bound == 0 {
                        0
                    } else {
                        (2000 * (l - bound) + bound) / (2 * bound)
                    };
                    out.push(format!("gap: tour {}, {}.{}%", l, u / 10, u % 10));
                } else {
                    out.push("gap: no tour".into());
                }
                return Ok(out);
            }
            "VRP" | "SWEEP" => {
                let q = n(0);
                self.capacity(q)?;
                let limit = if a.len() == 2 { Some(n(1)) } else { None };
                if let Some(limit) = limit {
                    for &n in self.stops.keys() {
                        if 2 * self.d(0, n) > limit {
                            return Err(error(format!("stop {} too far for limit {}", n, limit)));
                        }
                    }
                }
                let mut routes = Vec::new();
                let mut merges = 0;
                if c == "VRP" {
                    let ids = self.stops.keys().copied().collect::<Vec<_>>();
                    routes.extend(ids.iter().map(|&n| vec![n]));
                    let mut savings = Vec::new();
                    for (i, &x) in ids.iter().enumerate() {
                        for &y in &ids[i + 1..] {
                            let saving = self.d(0, x) + self.d(0, y) - self.d(x, y);
                            if saving > 0 {
                                savings.push((-saving, x, y));
                            }
                        }
                    }
                    savings.sort();
                    for (_, x, y) in savings {
                        let ia = routes.iter().position(|r| r.contains(&x)).unwrap();
                        let ib = routes.iter().position(|r| r.contains(&y)).unwrap();
                        if ia == ib {
                            continue;
                        }
                        let mut left = routes[ia].clone();
                        let mut right = routes[ib].clone();
                        if (!left.first().is_some_and(|n| *n == x)
                            && !left.last().is_some_and(|n| *n == x))
                            || (!right.first().is_some_and(|n| *n == y)
                                && !right.last().is_some_and(|n| *n == y))
                        {
                            continue;
                        }
                        if self.load(&left) + self.load(&right) > q {
                            continue;
                        }
                        if left.last() != Some(&x) {
                            left.reverse();
                        }
                        if right.first() != Some(&y) {
                            right.reverse();
                        }
                        left.extend(right);
                        if limit.is_some_and(|lim| self.length(&left) > lim) {
                            continue;
                        }
                        routes[ia] = left;
                        routes.remove(ib);
                        merges += 1;
                    }
                } else {
                    let center = self.depot.unwrap();
                    let mut ids = self.stops.keys().copied().collect::<Vec<_>>();
                    ids.sort_by(|&x, &y| {
                        let a = self.point(x);
                        let b = self.point(y);
                        let (ax, ay) = (a.0 - center.0, a.1 - center.1);
                        let (bx, by) = (b.0 - center.0, b.1 - center.1);
                        let az = ax == 0 && ay == 0;
                        let bz = bx == 0 && by == 0;
                        if az || bz {
                            return if az != bz { bz.cmp(&az) } else { x.cmp(&y) };
                        }
                        let ah = if ay > 0 || (ay == 0 && ax > 0) { 0 } else { 1 };
                        let bh = if by > 0 || (by == 0 && bx > 0) { 0 } else { 1 };
                        let cross = ax * by - ay * bx;
                        ah.cmp(&bh)
                            .then_with(|| 0.cmp(&cross))
                            .then_with(|| self.d(0, x).cmp(&self.d(0, y)))
                            .then_with(|| x.cmp(&y))
                    });
                    let mut route = Vec::new();
                    let mut load = 0;
                    for n in ids {
                        let demand = self.stops[&n].demand;
                        if load + demand > q {
                            routes.push(route);
                            route = Vec::new();
                            load = 0;
                        }
                        route.push(n);
                        load += demand;
                    }
                    routes.push(route);
                }
                let p = Plan {
                    capacity: q,
                    routes: Self::normalize(routes),
                };
                out.push(if c == "VRP" {
                    format!(
                        "vrp: capacity {}, merges {}, routes {}, length {}",
                        q,
                        merges,
                        p.routes.len(),
                        self.total(&p)
                    )
                } else {
                    format!(
                        "sweep: capacity {}, routes {}, length {}",
                        q,
                        p.routes.len(),
                        self.total(&p)
                    )
                });
                out.extend(self.route_lines(&p));
                self.plan = Some(p);
                return Ok(out);
            }
            _ => unreachable!(),
        }
        let p = self.tour.as_ref().unwrap();
        Ok(vec![format!(
            "{}: {} length {}",
            c.to_lowercase(),
            notation(p),
            self.length(p)
        )])
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut workbench = Workbench {
        depot: None,
        start: 480,
        stops: BTreeMap::new(),
        tour: None,
        plan: None,
    };
    for line in lines.take(count) {
        let w = line.split(' ').collect::<Vec<_>>();
        match workbench.command(&w) {
            Ok(out) => {
                for line in out {
                    println!("{}", line);
                }
            }
            Err(problem) => println!("{}", problem),
        }
    }
}
