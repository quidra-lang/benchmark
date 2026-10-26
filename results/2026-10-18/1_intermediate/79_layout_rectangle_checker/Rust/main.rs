use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};
type Answer = Result<Vec<String>, String>;

fn error(s: impl Into<String>) -> String {
    format!("error: {}", s.into())
}

fn names(mut values: Vec<String>) -> String {
    values.sort();
    if values.is_empty() {
        "none".into()
    } else {
        values.join(" ")
    }
}

fn decimal(n: i64, d: i64) -> String {
    let v = n * 100 / d;
    format!("{}.{:02}", v / 100, v % 100)
}

#[derive(Clone)]
struct Rect {
    name: String,
    layer: String,
    x1: i64,
    y1: i64,
    x2: i64,
    y2: i64,
}

impl Rect {
    fn shape(x1: i64, y1: i64, x2: i64, y2: i64) -> Self {
        Self {
            name: String::new(),
            layer: String::new(),
            x1,
            y1,
            x2,
            y2,
        }
    }

    fn width(&self) -> i64 {
        self.x2 - self.x1
    }

    fn height(&self) -> i64 {
        self.y2 - self.y1
    }

    fn area(&self) -> i64 {
        self.width() * self.height()
    }

    fn text(&self) -> String {
        format!("({},{})-({},{})", self.x1, self.y1, self.x2, self.y2)
    }

    fn contains(&self, b: &Rect) -> bool {
        self.x1 <= b.x1 && self.y1 <= b.y1 && self.x2 >= b.x2 && self.y2 >= b.y2
    }

    fn margins(&self, b: &Rect) -> [i64; 4] {
        [
            b.x1 - self.x1,
            b.y1 - self.y1,
            self.x2 - b.x2,
            self.y2 - b.y2,
        ]
    }

    fn moved(&self, dx: i64, dy: i64) -> Self {
        let mut r = self.clone();
        r.x1 += dx;
        r.x2 += dx;
        r.y1 += dy;
        r.y2 += dy;
        r
    }

    fn check_bounds(&self) -> Result<(), String> {
        if [self.x1, self.y1, self.x2, self.y2]
            .iter()
            .any(|v| v.abs() > 10000)
        {
            Err(error("out of bounds"))
        } else {
            Ok(())
        }
    }
}

struct Relation {
    common: Rect,
    ox: i64,
    oy: i64,
    kind: usize,
    gap: i64,
}

impl Relation {
    fn direction(&self) -> &str {
        if self.kind == 2 {
            "corner"
        } else if self.ox < 0 && self.oy < 0 {
            "diagonal"
        } else if self.ox < 0 {
            "x"
        } else {
            "y"
        }
    }
}

fn relation(a: &Rect, b: &Rect) -> Relation {
    let common = Rect::shape(
        a.x1.max(b.x1),
        a.y1.max(b.y1),
        a.x2.min(b.x2),
        a.y2.min(b.y2),
    );
    let ox = common.width();
    let oy = common.height();
    let kind = if ox > 0 && oy > 0 {
        0
    } else if ox >= 0 && oy >= 0 && ox + oy > 0 {
        1
    } else if ox == 0 && oy == 0 {
        2
    } else {
        3
    };
    Relation {
        common,
        ox,
        oy,
        kind,
        gap: 0.max(-ox).max(-oy),
    }
}

fn connected(a: &Rect, b: &Rect) -> bool {
    relation(a, b).kind <= 1
}

fn bbox(rs: &[Rect]) -> Rect {
    Rect::shape(
        rs.iter().map(|r| r.x1).min().unwrap(),
        rs.iter().map(|r| r.y1).min().unwrap(),
        rs.iter().map(|r| r.x2).max().unwrap(),
        rs.iter().map(|r| r.y2).max().unwrap(),
    )
}

struct Grid {
    xs: Vec<i64>,
    ys: Vec<i64>,
    count: Vec<Vec<usize>>,
}

impl Grid {
    fn new(rs: &[Rect]) -> Self {
        let xs: Vec<i64> = rs
            .iter()
            .flat_map(|r| [r.x1, r.x2])
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let ys: Vec<i64> = rs
            .iter()
            .flat_map(|r| [r.y1, r.y2])
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let count = (0..ys.len() - 1)
            .map(|y| {
                (0..xs.len() - 1)
                    .map(|x| {
                        rs.iter()
                            .filter(|r| {
                                r.x1 <= xs[x] && r.x2 > xs[x] && r.y1 <= ys[y] && r.y2 > ys[y]
                            })
                            .count()
                    })
                    .collect()
            })
            .collect();
        Self { xs, ys, count }
    }

    fn nx(&self) -> usize {
        self.xs.len() - 1
    }

    fn ny(&self) -> usize {
        self.ys.len() - 1
    }

    fn area(&self, k: usize, window: Option<&Rect>) -> i64 {
        let mut sum = 0;
        for y in 0..self.ny() {
            for x in 0..self.nx() {
                if self.count[y][x] >= k {
                    let x1 = self.xs[x].max(window.map_or(self.xs[x], |r| r.x1));
                    let x2 = self.xs[x + 1].min(window.map_or(self.xs[x + 1], |r| r.x2));
                    let y1 = self.ys[y].max(window.map_or(self.ys[y], |r| r.y1));
                    let y2 = self.ys[y + 1].min(window.map_or(self.ys[y + 1], |r| r.y2));
                    sum += (x2 - x1).max(0) * (y2 - y1).max(0);
                }
            }
        }
        sum
    }

    fn perimeter(&self) -> i64 {
        let mut sum = 0;
        for y in 0..self.ny() {
            for x in 0..self.nx() {
                if self.count[y][x] > 0 {
                    if x == 0 || self.count[y][x - 1] == 0 {
                        sum += self.ys[y + 1] - self.ys[y];
                    }
                    if x + 1 == self.nx() || self.count[y][x + 1] == 0 {
                        sum += self.ys[y + 1] - self.ys[y];
                    }
                    if y == 0 || self.count[y - 1][x] == 0 {
                        sum += self.xs[x + 1] - self.xs[x];
                    }
                    if y + 1 == self.ny() || self.count[y + 1][x] == 0 {
                        sum += self.xs[x + 1] - self.xs[x];
                    }
                }
            }
        }
        sum
    }

    fn empty(&self) -> Option<Rect> {
        let mut best: Option<Rect> = None;
        for bottom in 0..self.ny() {
            let mut free = vec![true; self.nx()];
            for top in bottom..self.ny() {
                for x in 0..self.nx() {
                    free[x] &= self.count[top][x] == 0;
                }
                let mut x = 0;
                while x < self.nx() {
                    if !free[x] {
                        x += 1;
                        continue;
                    }
                    let start = x;
                    while x < self.nx() && free[x] {
                        x += 1;
                    }
                    let r = Rect::shape(
                        self.xs[start],
                        self.ys[bottom],
                        self.xs[x],
                        self.ys[top + 1],
                    );
                    if best.as_ref().is_none_or(|old| {
                        (-r.area(), r.x1, r.y1, r.width())
                            < (-old.area(), old.x1, old.y1, old.width())
                    }) {
                        best = Some(r);
                    }
                }
            }
        }
        best
    }

    fn holes(&self) -> Vec<(i64, Rect)> {
        let mut seen = vec![vec![false; self.nx()]; self.ny()];
        let mut result = Vec::new();
        for y in 0..self.ny() {
            for x in 0..self.nx() {
                if self.count[y][x] > 0 || seen[y][x] {
                    continue;
                }
                let mut queue = VecDeque::from(vec![(x, y)]);
                seen[y][x] = true;
                let mut boundary = false;
                let mut area = 0;
                let mut r = Rect::shape(self.xs[x], self.ys[y], self.xs[x + 1], self.ys[y + 1]);
                let mut anchor = (self.ys[y], self.xs[x]);
                while let Some((cx, cy)) = queue.pop_front() {
                    boundary |= cx == 0 || cy == 0 || cx + 1 == self.nx() || cy + 1 == self.ny();
                    area += (self.xs[cx + 1] - self.xs[cx]) * (self.ys[cy + 1] - self.ys[cy]);
                    r.x1 = r.x1.min(self.xs[cx]);
                    r.y1 = r.y1.min(self.ys[cy]);
                    r.x2 = r.x2.max(self.xs[cx + 1]);
                    r.y2 = r.y2.max(self.ys[cy + 1]);
                    anchor = anchor.min((self.ys[cy], self.xs[cx]));
                    for (dx, dy) in [(-1isize, 0isize), (1, 0), (0, -1), (0, 1)].iter().copied() {
                        let xx = cx as isize + dx;
                        let yy = cy as isize + dy;
                        if xx >= 0
                            && yy >= 0
                            && (xx as usize) < self.nx()
                            && (yy as usize) < self.ny()
                        {
                            let (xx, yy) = (xx as usize, yy as usize);
                            if !seen[yy][xx] && self.count[yy][xx] == 0 {
                                seen[yy][xx] = true;
                                queue.push_back((xx, yy));
                            }
                        }
                    }
                }
                if !boundary {
                    result.push((anchor, area, r));
                }
            }
        }
        result.sort_by_key(|r| r.0);
        result.into_iter().map(|(_, area, r)| (area, r)).collect()
    }

    fn pieces(&self) -> Vec<Rect> {
        let mut active: BTreeMap<(i64, i64), Rect> = BTreeMap::new();
        let mut result = Vec::new();
        for y in 0..self.ny() {
            let mut next = BTreeMap::new();
            let mut x = 0;
            while x < self.nx() {
                if self.count[y][x] == 0 {
                    x += 1;
                    continue;
                }
                let start = x;
                while x < self.nx() && self.count[y][x] > 0 {
                    x += 1;
                }
                let key = (self.xs[start], self.xs[x]);
                let mut r = active
                    .remove(&key)
                    .unwrap_or_else(|| Rect::shape(key.0, self.ys[y], key.1, self.ys[y + 1]));
                r.y2 = self.ys[y + 1];
                next.insert(key, r);
            }
            result.extend(active.into_values());
            active = next;
        }
        result.extend(active.into_values());
        result.sort_by_key(|r| (r.y1, r.x1));
        result
    }
}

fn spacing(rs: &[Rect], s: i64) -> Vec<(String, String, i64, String)> {
    let mut found = Vec::new();
    for i in 0..rs.len() {
        for j in i + 1..rs.len() {
            let r = relation(&rs[i], &rs[j]);
            if r.kind == 2 || r.kind == 3 && r.gap < s {
                found.push((
                    rs[i].name.clone(),
                    rs[j].name.clone(),
                    r.gap,
                    r.direction().into(),
                ));
            }
        }
    }
    found.sort_by(|a, b| (a.2, &a.0, &a.1).cmp(&(b.2, &b.0, &b.1)));
    found
}

fn violation(v: &(String, String, i64, String)) -> String {
    format!("{} {} gap {} {}", v.0, v.1, v.2, v.3)
}

fn nets(rs: &[Rect]) -> Vec<Vec<Rect>> {
    let mut seen = BTreeSet::new();
    let mut groups = Vec::new();
    for r in rs {
        if !seen.insert(r.name.clone()) {
            continue;
        }
        let mut queue = vec![r.clone()];
        let mut at = 0;
        while at < queue.len() {
            let a = queue[at].clone();
            at += 1;
            for b in rs {
                if !seen.contains(&b.name) && connected(&a, b) {
                    seen.insert(b.name.clone());
                    queue.push(b.clone());
                }
            }
        }
        queue.sort_by(|a, b| a.name.cmp(&b.name));
        groups.push(queue);
    }
    groups
}

struct Layout {
    rectangles: BTreeMap<String, Rect>,
    history: Vec<(BTreeMap<String, Rect>, String)>,
    rules: BTreeMap<(String, String, String), i64>,
}

impl Layout {
    fn get(&self, name: &str) -> Result<Rect, String> {
        self.rectangles
            .get(name)
            .cloned()
            .ok_or_else(|| error(format!("unknown rectangle {}", name)))
    }

    fn layer(&self, name: &str) -> Vec<Rect> {
        self.rectangles
            .values()
            .filter(|r| r.layer == name)
            .cloned()
            .collect()
    }

    fn checked_layer(&self, name: &str) -> Result<Vec<Rect>, String> {
        let rs = self.layer(name);
        if rs.is_empty() {
            Err(error(format!("no rectangles on {}", name)))
        } else {
            Ok(rs)
        }
    }

    fn command(&mut self, line: &str) -> Answer {
        let w: Vec<&str> = line.split(' ').collect();
        let c = w[0];
        let n = |i: usize| w[i].parse::<i64>().unwrap();
        let mut out = Vec::new();
        if ["ADD", "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE"].contains(&c) {
            let mut next = self.rectangles.clone();
            let name = w[1];
            match c {
                "ADD" => {
                    if self.rectangles.contains_key(name) {
                        return Err(error(format!("duplicate rectangle {}", name)));
                    }
                    let mut r = Rect::shape(n(3), n(4), n(5), n(6));
                    r.name = name.into();
                    r.layer = w[2].into();
                    if r.width() <= 0 || r.height() <= 0 {
                        return Err(error("invalid rectangle"));
                    }
                    r.check_bounds()?;
                    out.push(format!("added {} {} {}", name, r.layer, r.text()));
                    next.insert(name.into(), r);
                }
                "COPY" => {
                    let old = self.get(name)?;
                    if self.rectangles.contains_key(w[2]) {
                        return Err(error(format!("duplicate rectangle {}", w[2])));
                    }
                    let mut r = old.moved(n(3), n(4));
                    r.name = w[2].into();
                    r.check_bounds()?;
                    out.push(format!("copied {} to {} {}", name, r.name, r.text()));
                    next.insert(r.name.clone(), r);
                }
                "MOVE" => {
                    let r = self.get(name)?.moved(n(2), n(3));
                    r.check_bounds()?;
                    out.push(format!("moved {} to {}", name, r.text()));
                    next.insert(name.into(), r);
                }
                "RESIZE" => {
                    let mut r = self.get(name)?;
                    if n(2) <= 0 || n(3) <= 0 {
                        return Err(error("invalid size"));
                    }
                    r.x2 = r.x1 + n(2);
                    r.y2 = r.y1 + n(3);
                    r.check_bounds()?;
                    out.push(format!("resized {} to {}", name, r.text()));
                    next.insert(name.into(), r);
                }
                "SPLIT" => {
                    let old = self.get(name)?;
                    if self.rectangles.contains_key(w[4]) {
                        return Err(error(format!("duplicate rectangle {}", w[4])));
                    }
                    let p = n(3);
                    let x = w[2] == "x";
                    if p <= (if x { old.x1 } else { old.y1 })
                        || p >= (if x { old.x2 } else { old.y2 })
                    {
                        return Err(error(format!("cut outside {}", name)));
                    }
                    let mut a = old.clone();
                    let mut b = old;
                    b.name = w[4].into();
                    if x {
                        a.x2 = p;
                        b.x1 = p;
                    } else {
                        a.y2 = p;
                        b.y1 = p;
                    }
                    out.push(format!(
                        "split {} at {}={}: {} {}, {} {}",
                        name,
                        w[2],
                        p,
                        name,
                        a.text(),
                        b.name,
                        b.text()
                    ));
                    next.insert(name.into(), a);
                    next.insert(b.name.clone(), b);
                }
                "LAYER" => {
                    let mut r = self.get(name)?;
                    if r.layer == w[2] {
                        return Err(error(format!("already on {}", w[2])));
                    }
                    out.push(format!("layer {} {} -> {}", name, r.layer, w[2]));
                    r.layer = w[2].into();
                    next.insert(name.into(), r);
                }
                _ => {
                    self.get(name)?;
                    next.remove(name);
                    out.push(format!("deleted {}", name));
                }
            }
            self.history
                .push((std::mem::replace(&mut self.rectangles, next), line.into()));
            return Ok(out);
        }
        match c {
            "UNDO" => {
                let (old, text) = self.history.pop().ok_or_else(|| error("nothing to undo"))?;
                self.rectangles = old;
                return Ok(vec![format!("undo: {}", text)]);
            }
            "LIST" => {
                out.push(format!("rectangles: {}", self.rectangles.len()));
                out.extend(self.rectangles.values().map(|r| {
                    format!(
                        "{} {} {} {}x{}",
                        r.name,
                        r.layer,
                        r.text(),
                        r.width(),
                        r.height()
                    )
                }));
                return Ok(out);
            }
            "INFO" => {
                let a = self.get(w[1])?;
                let others: Vec<&Rect> = self
                    .rectangles
                    .values()
                    .filter(|r| r.name != a.name)
                    .collect();
                out.push(format!(
                    "{} {} {} {}x{} area {}",
                    a.name,
                    a.layer,
                    a.text(),
                    a.width(),
                    a.height(),
                    a.area()
                ));
                for (label, kind) in [("overlaps", 0), ("touches", 1), ("corners", 2)]
                    .iter()
                    .copied()
                {
                    out.push(format!(
                        "{}: {}",
                        label,
                        names(
                            others
                                .iter()
                                .filter(|r| r.layer == a.layer && relation(&a, r).kind == kind)
                                .map(|r| r.name.clone())
                                .collect()
                        )
                    ));
                }
                out.push(format!(
                    "encloses: {}",
                    names(
                        others
                            .iter()
                            .filter(|r| a.contains(r))
                            .map(|r| r.name.clone())
                            .collect()
                    )
                ));
                out.push(format!(
                    "enclosed by: {}",
                    names(
                        others
                            .iter()
                            .filter(|r| r.contains(&a))
                            .map(|r| r.name.clone())
                            .collect()
                    )
                ));
                return Ok(out);
            }
            "LAYERS" => {
                let layers = self
                    .rectangles
                    .values()
                    .map(|r| r.layer.clone())
                    .collect::<BTreeSet<_>>();
                out.push(format!("layers: {}", layers.len()));
                for l in layers {
                    let rs = self.layer(&l);
                    out.push(format!(
                        "{}: {} rectangles, area {}, nets {}",
                        l,
                        rs.len(),
                        Grid::new(&rs).area(1, None),
                        nets(&rs).len()
                    ));
                }
                return Ok(out);
            }
            "INTERSECT" | "ADJACENT" | "ENCLOSE" | "PATH" => {
                let a = self.get(w[1])?;
                let b = self.get(w[2])?;
                if a.name == b.name {
                    return Err(error(format!("same rectangle {}", a.name)));
                }
                let r = relation(&a, &b);
                let q = &r.common;
                if c == "INTERSECT" {
                    return Ok(vec![format!(
                        "intersect {} {}: {}",
                        a.name,
                        b.name,
                        match r.kind {
                            0 => format!("{} area {}", q.text(), q.area()),
                            1 => format!("segment {} length {}", q.text(), r.ox + r.oy),
                            2 => format!("point ({},{})", q.x1, q.y1),
                            _ => format!("none, gap {}", r.gap),
                        }
                    )]);
                }
                if c == "ADJACENT" {
                    let d = if r.ox == 0 {
                        if a.x2 == q.x1 { "west" } else { "east" }
                    } else if a.y2 == q.y1 {
                        "south"
                    } else {
                        "north"
                    };
                    return Ok(vec![format!(
                        "adjacent {} {}: {}",
                        a.name,
                        b.name,
                        match r.kind {
                            0 => "overlapping".into(),
                            1 => format!(
                                "{} is {} of {}, edge {}, length {}",
                                a.name,
                                d,
                                b.name,
                                q.text(),
                                r.ox + r.oy
                            ),
                            2 => format!("corner only at ({},{})", q.x1, q.y1),
                            _ => "not adjacent".into(),
                        }
                    )]);
                }
                if c == "ENCLOSE" {
                    let m = a.margins(&b);
                    return Ok(vec![format!(
                        "enclose {} {}: {}, margins left {} bottom {} right {} top {}{}",
                        a.name,
                        b.name,
                        if a.contains(&b) { "yes" } else { "no" },
                        m[0],
                        m[1],
                        m[2],
                        m[3],
                        if a.contains(&b) {
                            format!(", min {}", m.iter().min().unwrap())
                        } else {
                            String::new()
                        }
                    )]);
                }
                if a.layer != b.layer {
                    return Err(error("different layers"));
                }
                let rs = self.layer(&a.layer);
                let mut seen = BTreeSet::from([a.name.clone()]);
                let mut previous = BTreeMap::new();
                let mut queue = VecDeque::from(vec![a.clone()]);
                while let Some(p) = queue.pop_front() {
                    for q in &rs {
                        if !seen.contains(&q.name) && connected(&p, q) {
                            seen.insert(q.name.clone());
                            previous.insert(q.name.clone(), p.name.clone());
                            queue.push_back(q.clone());
                        }
                    }
                }
                if !seen.contains(&b.name) {
                    return Ok(vec![format!("path {} {}: none", a.name, b.name)]);
                }
                let mut path = vec![b.name.clone()];
                while path.last().unwrap() != &a.name {
                    path.push(previous[path.last().unwrap()].clone());
                }
                path.reverse();
                return Ok(vec![format!(
                    "path {} {}: {} ({} steps)",
                    a.name,
                    b.name,
                    path.join(" -> "),
                    path.len() - 1
                )]);
            }
            "AT" => {
                let (x, y) = (n(1), n(2));
                let found: Vec<String> = self
                    .rectangles
                    .values()
                    .filter(|r| r.x1 <= x && x <= r.x2 && r.y1 <= y && y <= r.y2)
                    .map(|r| {
                        let xx = x == r.x1 || x == r.x2;
                        let yy = y == r.y1 || y == r.y2;
                        format!(
                            "{} {} {}",
                            r.name,
                            r.layer,
                            if xx && yy {
                                "corner"
                            } else if xx || yy {
                                "edge"
                            } else {
                                "inside"
                            }
                        )
                    })
                    .collect();
                return Ok(vec![format!(
                    "at ({},{}): {}",
                    x,
                    y,
                    if found.is_empty() {
                        "none".into()
                    } else {
                        found.join(", ")
                    }
                )]);
            }
            "NEAREST" => {
                let a = self.get(w[1])?;
                let rs = self.layer(&a.layer);
                let b = rs
                    .iter()
                    .filter(|r| r.name != a.name)
                    .min_by_key(|r| (relation(&a, r).gap, r.name.clone()));
                return Ok(vec![format!(
                    "nearest {}: {}",
                    a.name,
                    b.map_or("none".into(), |r| format!(
                        "{} gap {}",
                        r.name,
                        relation(&a, r).gap
                    ))
                )]);
            }
            "OVERLAPS" => {
                let rs = if w.len() == 2 {
                    self.checked_layer(w[1])?
                } else {
                    self.rectangles.values().cloned().collect()
                };
                let mut found = Vec::new();
                for i in 0..rs.len() {
                    for j in i + 1..rs.len() {
                        if rs[i].layer == rs[j].layer {
                            let r = relation(&rs[i], &rs[j]);
                            if r.kind == 0 {
                                found.push((&rs[i], &rs[j], r.common));
                            }
                        }
                    }
                }
                found.sort_by(|a, b| {
                    (&a.0.layer, &a.0.name, &a.1.name).cmp(&(&b.0.layer, &b.0.name, &b.1.name))
                });
                out.push(format!(
                    "overlaps {}: {}",
                    if w.len() == 1 { "all layers" } else { w[1] },
                    found.len()
                ));
                for (a, b, r) in found {
                    out.push(format!(
                        "{}{} {} {} area {}",
                        if w.len() == 1 {
                            format!("{} ", a.layer)
                        } else {
                            String::new()
                        },
                        a.name,
                        b.name,
                        r.text(),
                        r.area()
                    ));
                }
                return Ok(out);
            }
            "RULE" => {
                let kind = w[1].to_lowercase();
                if kind == "enclose" && w[2] == w[3] {
                    return Err(error(format!("same layer {}", w[2])));
                }
                let outer = if kind == "enclose" { w[3] } else { "" };
                let v = n(if kind == "enclose" { 4 } else { 3 });
                self.rules
                    .insert((kind.clone(), w[2].into(), outer.into()), v);
                return Ok(vec![format!(
                    "rule {} {}{} {}",
                    kind,
                    w[2],
                    if outer.is_empty() {
                        String::new()
                    } else {
                        format!(" {}", outer)
                    },
                    v
                )]);
            }
            "CHECK" => {
                if self.rules.is_empty() {
                    return Err(error("no rules"));
                }
                let mut total = 0;
                for ((kind, inner, outer), &v) in &self.rules {
                    let rs = self.layer(inner);
                    let found: Vec<String> = match kind.as_str() {
                        "spacing" => spacing(&rs, v).iter().map(violation).collect(),
                        "width" => rs
                            .iter()
                            .filter(|r| r.width().min(r.height()) < v)
                            .map(|r| format!("{} width {}", r.name, r.width().min(r.height())))
                            .collect(),
                        _ => {
                            let outer = self.layer(outer);
                            rs.iter()
                                .filter_map(|r| {
                                    let best = outer
                                        .iter()
                                        .map(|a| *a.margins(r).iter().min().unwrap())
                                        .max();
                                    if best.is_none_or(|b| b < v) {
                                        Some(format!(
                                            "{} best margin {}",
                                            r.name,
                                            best.map_or("none".into(), |b| b.to_string())
                                        ))
                                    } else {
                                        None
                                    }
                                })
                                .collect()
                        }
                    };
                    total += found.len();
                    out.push(format!(
                        "{} {}{} {}: {} violations",
                        kind,
                        inner,
                        if kind == "enclose" {
                            format!(" {}", outer)
                        } else {
                            String::new()
                        },
                        v,
                        found.len()
                    ));
                    out.extend(found);
                }
                out.push(format!(
                    "check: {} violations in {} rules",
                    total,
                    self.rules.len()
                ));
                return Ok(out);
            }
            _ => {}
        }
        let rs = self.checked_layer(if c == "COVER" { w[2] } else { w[1] })?;
        let l = &rs[0].layer;
        let g = Grid::new(&rs);
        let b = bbox(&rs);
        match c {
            "AREA" => Ok(vec![format!("area {}: {}", l, g.area(1, None))]),
            "COVER" => Ok(vec![format!(
                "cover {} >= {}: {}",
                l,
                w[1],
                g.area(n(1) as usize, None)
            )]),
            "PERIMETER" => Ok(vec![format!("perimeter {}: {}", l, g.perimeter())]),
            "NETS" => {
                let groups = nets(&rs);
                out.push(format!("nets {}: {}", l, groups.len()));
                for (i, group) in groups.iter().enumerate() {
                    out.push(format!(
                        "net {}: {} area {}",
                        i + 1,
                        names(group.iter().map(|r| r.name.clone()).collect()),
                        Grid::new(group).area(1, None)
                    ));
                }
                Ok(out)
            }
            "DRC" => {
                let violations = spacing(&rs, n(2));
                out.push(format!(
                    "drc {} spacing {}: {} violations",
                    l,
                    w[2],
                    violations.len()
                ));
                out.extend(violations.iter().map(violation));
                Ok(out)
            }
            "BBOX" => Ok(vec![format!(
                "bbox {}: {} {}x{}, {} rectangles, density {}%",
                l,
                b.text(),
                b.width(),
                b.height(),
                rs.len(),
                decimal(100 * g.area(1, None), b.area())
            )]),
            "DENSITY" => {
                let size = n(2);
                let cols = (b.width() + size - 1) / size;
                let rows = (b.height() + size - 1) / size;
                if cols > 20 || rows > 20 {
                    return Err(error("too many windows"));
                }
                let values: Vec<Vec<i64>> = (0..rows)
                    .map(|y| {
                        (0..cols)
                            .map(|x| {
                                let xx = b.x1 + x * size;
                                let yy = b.y1 + y * size;
                                g.area(1, Some(&Rect::shape(xx, yy, xx + size, yy + size)))
                            })
                            .collect()
                    })
                    .collect();
                let denominator = size * size;
                out.push(format!("density {} window {}: {}x{}", l, size, cols, rows));
                for row in values.iter().rev() {
                    out.push(
                        row.iter()
                            .map(|v| (100 * v / denominator).to_string())
                            .collect::<Vec<_>>()
                            .join(" "),
                    );
                }
                let (mut min_x, mut min_y, mut max_x, mut max_y) = (0, 0, 0, 0);
                for y in 0..rows as usize {
                    for x in 0..cols as usize {
                        if values[y][x] < values[min_y][min_x] {
                            min_x = x;
                            min_y = y;
                        }
                        if values[y][x] > values[max_y][max_x] {
                            max_x = x;
                            max_y = y;
                        }
                    }
                }
                out.push(format!(
                    "min {}% at ({},{})",
                    decimal(100 * values[min_y][min_x], denominator),
                    b.x1 + min_x as i64 * size,
                    b.y1 + min_y as i64 * size
                ));
                out.push(format!(
                    "max {}% at ({},{})",
                    decimal(100 * values[max_y][max_x], denominator),
                    b.x1 + max_x as i64 * size,
                    b.y1 + max_y as i64 * size
                ));
                Ok(out)
            }
            "RENDER" => {
                let r = Rect::shape(n(2), n(3), n(4), n(5));
                if r.width() <= 0 || r.height() <= 0 {
                    return Err(error("invalid window"));
                }
                if r.width() > 60 || r.height() > 40 {
                    return Err(error("window too large"));
                }
                out.push(format!("render {} {}", l, r.text()));
                for y in (r.y1..r.y2).rev() {
                    out.push(
                        (r.x1..r.x2)
                            .map(|x| {
                                let count = rs
                                    .iter()
                                    .filter(|a| a.x1 <= x && x < a.x2 && a.y1 <= y && y < a.y2)
                                    .count();
                                if count == 0 {
                                    '.'
                                } else if count >= 10 {
                                    '*'
                                } else {
                                    (b'0' + count as u8) as char
                                }
                            })
                            .collect(),
                    );
                }
                Ok(out)
            }
            "EMPTY" => Ok(vec![format!(
                "empty {}: {}",
                l,
                g.empty()
                    .map_or("none".into(), |r| format!("{} area {}", r.text(), r.area()))
            )]),
            "HOLES" => {
                let holes = g.holes();
                out.push(format!("holes {}: {}", l, holes.len()));
                out.extend(holes.iter().enumerate().map(|(i, (area, r))| {
                    format!("hole {}: area {}, bbox {}", i + 1, area, r.text())
                }));
                Ok(out)
            }
            "MERGE" => {
                let pieces = g.pieces();
                out.push(format!("merge {}: {} pieces", l, pieces.len()));
                out.extend(pieces.iter().map(Rect::text));
                Ok(out)
            }
            _ => unreachable!(),
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut layout = Layout {
        rectangles: BTreeMap::new(),
        history: Vec::new(),
        rules: BTreeMap::new(),
    };
    for line in lines.take(count) {
        match layout.command(line) {
            Ok(lines) => {
                for line in lines {
                    println!("{}", line);
                }
            }
            Err(e) => println!("{}", e),
        }
    }
}
