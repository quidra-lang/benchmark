use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const SIDES: [&str; 4] = ["top", "right", "bottom", "left"];

fn defaults() -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    for (p, v) in [
        ("display", "block"), ("position", "static"), ("box-sizing", "content-box"),
        ("width", "auto"), ("height", "auto"), ("min-width", "0"), ("min-height", "0"),
        ("max-width", "none"), ("max-height", "none"), ("flex-direction", "row"),
        ("flex-wrap", "nowrap"), ("justify-content", "start"), ("align-items", "stretch"),
        ("align-self", "auto"), ("row-gap", "0"), ("column-gap", "0"), ("order", "0"),
        ("flex-grow", "0"), ("flex-shrink", "1"), ("flex-basis", "auto"),
        ("grid-template-columns", "none"), ("grid-template-rows", "none"),
        ("grid-column", "auto"), ("grid-row", "auto"),
    ].iter().copied() {
        values.insert(p.to_string(), v.to_string());
    }
    for side in SIDES.iter().copied() {
        values.insert(side.to_string(), "auto".to_string());
        for kind in ["margin", "padding", "border"].iter().copied() {
            values.insert(format!("{}-{}", kind, side), "0".to_string());
        }
    }
    values
}

fn natural(s: &str) -> bool {
    (1..=3).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_digit())
}

fn positive(s: &str) -> bool {
    natural(s) && s.parse::<usize>().unwrap() > 0
}

fn signed(s: &str) -> bool {
    natural(s.strip_prefix('-').unwrap_or(s))
}

fn percent(s: &str) -> bool {
    s.strip_suffix('%').map_or(false, natural)
}

fn fraction(s: &str) -> bool {
    s.strip_suffix("fr").map_or(false, positive)
}

fn grid_value(t: &[&str]) -> bool {
    match t {
        ["auto"] => true,
        [a] => positive(a),
        ["span", n] => positive(n),
        [a, "/", b] => positive(a) && positive(b) && a.parse::<usize>().unwrap() < b.parse::<usize>().unwrap(),
        [a, "/", "span", n] => positive(a) && positive(n),
        _ => false,
    }
}

fn valid(p: &str, t: &[&str]) -> bool {
    if p.starts_with("grid-template-") {
        return t == ["none"] || t.iter().all(|v| *v == "auto" || natural(v) || fraction(v));
    }
    if p == "grid-column" || p == "grid-row" {
        return grid_value(t);
    }
    if t.len() != 1 {
        return false;
    }
    let v = t[0];
    match p {
        "display" => ["block", "flex", "grid", "none"].contains(&v),
        "position" => ["static", "relative", "absolute"].contains(&v),
        "box-sizing" => ["content-box", "border-box"].contains(&v),
        "width" | "height" | "flex-basis" => v == "auto" || natural(v) || percent(v),
        "min-width" | "min-height" => natural(v) || percent(v),
        "max-width" | "max-height" => v == "none" || natural(v) || percent(v),
        "top" | "right" | "bottom" | "left" => v == "auto" || signed(v),
        "order" => signed(v),
        "flex-direction" => ["row", "row-reverse", "column", "column-reverse"].contains(&v),
        "flex-wrap" => ["nowrap", "wrap"].contains(&v),
        "justify-content" => ["start", "end", "center", "space-between", "space-around", "space-evenly"].contains(&v),
        "align-items" => ["stretch", "start", "end", "center"].contains(&v),
        "align-self" => ["auto", "stretch", "start", "end", "center"].contains(&v),
        _ => if p.starts_with("border-") {
            v == "0" || v == "1"
        } else {
            natural(v)
        },
    }
}

fn shorthand(p: &str) -> bool {
    ["margin", "padding", "border", "gap"].contains(&p)
}

fn declaration(p: &str, value: &str) -> Option<Vec<(String, String)>> {
    let t: Vec<&str> = value.split(' ').collect();
    if defaults().contains_key(p) {
        return if valid(p, &t) {
            Some(vec![(p.to_string(), value.to_string())])
        } else {
            None
        };
    }
    if p == "gap" {
        if !(1..=2).contains(&t.len()) || !t.iter().all(|v| natural(v)) {
            return None;
        }
        return Some(vec![("row-gap".to_string(), t[0].to_string()), ("column-gap".to_string(), t[t.len() - 1].to_string())]);
    }
    if shorthand(p) && (1..=4).contains(&t.len()) && t.iter().all(|v| valid(&format!("{}-top", p), &[*v])) {
        let pick = match t.len() {
            1 => [0, 0, 0, 0], 2 => [0, 1, 0, 1], 3 => [0, 1, 2, 1], _ => [0, 1, 2, 3]
        };
        return Some((0..4).map(|i| (format!("{}-{}", p, SIDES[i]), t[pick[i]].to_string())).collect());
    }
    None
}

struct Rule {
    selectors: Vec<String>,
    values: Vec<(String, String)>
}
#[derive(Clone, Copy, PartialEq, Eq)]
struct Rect {
    x: i64,
    y: i64,
    w: i64,
    h: i64
}

impl Rect {
    fn text(self) -> String {
        format!("{} {} {} {}", self.x, self.y, self.w, self.h)
    }
    fn contains(self, x: i64, y: i64) -> bool {
        x >= self.x && x < self.x + self.w && y >= self.y && y < self.y + self.h
    }
    fn encloses(self, r: Rect) -> bool {
        r.x >= self.x && r.y >= self.y && r.x + r.w <= self.x + self.w && r.y + r.h <= self.y + self.h
    }
}

struct Element {
    kind: String,
    id: String,
    classes: BTreeSet<String>,
    text: Option<String>,
    parent: Option<usize>,
    depth: usize,
    children: Vec<usize>,
    overrides: BTreeMap<String, String>,
    style: BTreeMap<String, String>,
    displayed: bool,
    cw: i64,
    ch: i64,
    rx: i64,
    ry: i64,
    x: i64,
    y: i64,
    lines: Vec<String>,
}

impl Element {
    fn s(&self, p: &str) -> &str {
        &self.style[p]
    }
    fn n(&self, p: &str) -> i64 {
        self.s(p).parse().unwrap()
    }
    fn edge(&self, kind: &str, i: usize) -> i64 {
        self.n(&format!("{}-{}", kind, SIDES[i]))
    }
    fn frame(&self, h: bool) -> i64 {
        let (a, b) = if h {
            (1, 3)
        } else {
            (0, 2)
        };
        self.edge("padding", a) + self.edge("padding", b) + self.edge("border", a) + self.edge("border", b)
    }
    fn margin(&self, h: bool) -> i64 {
        let (a, b) = if h {
            (1, 3)
        } else {
            (0, 2)
        };
        self.edge("margin", a) + self.edge("margin", b)
    }
    fn border_width(&self) -> i64 {
        self.cw + self.frame(true)
    }
    fn border_height(&self) -> i64 {
        self.ch + self.frame(false)
    }
    fn border(&self) -> Rect {
        Rect {
            x: self.x, y: self.y, w: self.border_width(), h: self.border_height()
        }
    }
    fn content(&self) -> Rect {
        Rect {
            x: self.x + self.edge("border", 3) + self.edge("padding", 3), y: self.y + self.edge("border", 0) + self.edge("padding", 0), w: self.cw, h: self.ch
        }
    }
    fn padding(&self) -> Rect {
        Rect {
            x: self.x + self.edge("border", 3), y: self.y + self.edge("border", 0), w: self.cw + self.edge("padding", 1) + self.edge("padding", 3), h: self.ch + self.edge("padding", 0) + self.edge("padding", 2)
        }
    }
    fn margin_box(&self) -> Rect {
        Rect {
            x: self.x - self.edge("margin", 3), y: self.y - self.edge("margin", 0), w: self.border_width() + self.margin(true), h: self.border_height() + self.margin(false)
        }
    }
    fn resolve(&self, prop: &str, reference: Option<i64>, h: bool) -> Option<i64> {
        let v = self.s(prop);
        if v == "auto" || v == "none" {
            return None;
        }
        let r = if let Some(p) = v.strip_suffix('%') {
            reference? * p.parse::<i64>().unwrap() / 100
        } else {
            v.parse().unwrap()
        };
        Some(if self.s("box-sizing") == "border-box" {
            (r - self.frame(h)).max(0)
        } else {
            r
        })
    }
    fn clamp(&self, v: i64, reference: Option<i64>, h: bool) -> i64 {
        let axis = if h {
            "width"
        } else {
            "height"
        };
        let lo = self.resolve(&format!("min-{}", axis), reference, h).unwrap_or(0);
        let hi = self.resolve(&format!("max-{}", axis), reference, h);
        hi.map_or(v, |upper| v.min(upper)).max(lo)
    }
}
#[derive(Clone)]
struct Area {
    row: usize,
    col: usize,
    rows: usize,
    cols: usize
}

struct Grid {
    items: Vec<usize>,
    areas: Vec<Area>,
    columns: Vec<String>,
    rows: Vec<String>,
    nc: usize,
    nr: usize
}

fn distribution(total: i64, weights: &[i64]) -> Vec<i64> {
    let sum: i64 = weights.iter().sum();
    if sum == 0 {
        return vec![0; weights.len()];
    }
    let mut out: Vec<i64> = weights.iter().map(|w| total * w / sum).collect();
    let mut rest = total - out.iter().sum::<i64>();
    for i in 0..weights.len() {
        if rest > 0 && weights[i] > 0 {
            out[i] += 1;
            rest -= 1;
        }
    }
    out
}

fn placement(v: &str) -> (usize, usize) {
    let t: Vec<&str> = v.split(' ').collect();
    match t.as_slice() {
        ["auto"] => (0, 1), ["span", n] => (0, n.parse().unwrap()), [a] => (a.parse().unwrap(), 1),
        [a, "/", b] => {
            let start: usize = a.parse().unwrap();
            (start, b.parse::<usize>().unwrap() - start)
        },
        [a, "/", "span", n] => (a.parse().unwrap(), n.parse().unwrap()), _ => unreachable!(),
    }
}

fn overlaps(a: &Area, r: usize, c: usize, occupied: &BTreeSet<(usize, usize)>) -> bool {
    (r..r + a.rows).any(|row| (c..c + a.cols).any(|col| occupied.contains(&(row, col))))
}

fn mark(a: &Area, occupied: &mut BTreeSet<(usize, usize)>) {
    for r in a.row..a.row + a.rows {
        for c in a.col..a.col + a.cols {
            occupied.insert((r, c));
        }
    }
}

fn tracks(g: &Grid, h: bool, available: Option<i64>, gap: i64, contributions: &[i64]) -> Vec<i64> {
    let count = if h {
        g.nc
    } else {
        g.nr
    };
    let explicit = if h {
        &g.columns
    } else {
        &g.rows
    };
    let specs: Vec<&str> = (0..count).map(|i| explicit.get(i).map_or("auto", String::as_str)).collect();
    let mut sizes: Vec<i64> = specs.iter().enumerate().map(|(i, spec)| {
        if natural(spec) {
            spec.parse().unwrap()
        } else if fraction(spec) && available.is_some() {
            0
        } else {
            g.areas.iter().enumerate().filter(|(_, a)| (if h {
                a.col
            } else {
                a.row
            }) == i + 1 && (if h {
                a.cols
            } else {
                a.rows
            }) == 1).map(|(j, _)| contributions[j]).max().unwrap_or(0)
        }
    }).collect();
    if let Some(u) = available {
        let left = u - sizes.iter().sum::<i64>() - gap * count.saturating_sub(1) as i64;
        if left > 0 {
            let has_fr = specs.iter().any(|v| fraction(v));
            let weights: Vec<i64> = specs.iter().map(|v| if has_fr {
                if fraction(v) {
                    v[..v.len() - 2].parse().unwrap()
                } else {
                    0
                }
            } else if *v == "auto" {
                1
            } else {
                0
            }).collect();
            let extra = distribution(left, &weights);
            for i in 0..count {
                sizes[i] += extra[i];
            }
        }
    }
    sizes
}

fn wrap(text: &str, width: i64) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for word in text.split(' ') {
        if lines.last().map_or(true, |s| s.len() as i64 + 1 + word.len() as i64 > width) {
            lines.push(word.to_string());
        } else {
            let line = lines.last_mut().unwrap();
            line.push(' ');
            line.push_str(word);
        }
    }
    lines
}

fn offset(remaining: i64, align: &str) -> i64 {
    if remaining <= 0 {
        0
    } else if align == "end" {
        remaining
    } else if align == "center" {
        remaining / 2
    } else {
        0
    }
}

struct Document {
    width: i64,
    height: i64,
    rules: Vec<Rule>,
    elements: Vec<Element>,
    by_id: BTreeMap<String, usize>
}

impl Document {
    fn flow(&self, e: usize) -> Vec<usize> {
        self.elements[e].children.iter().copied().filter(|i| self.elements[*i].displayed && self.elements[*i].s("position") != "absolute").collect()
    }
    fn items(&self, e: usize) -> Vec<usize> {
        let mut items = self.flow(e);
        items.sort_by_key(|i| (self.elements[*i].n("order"), *i));
        items
    }
    fn align(&self, e: usize, child: usize) -> String {
        let s = self.elements[child].s("align-self");
        (if s == "auto" {
            self.elements[e].s("align-items")
        } else {
            s
        }).to_string()
    }
    fn place(&mut self, e: usize, child: usize, x: i64, y: i64) {
        let dx = self.elements[e].edge("border", 3) + self.elements[e].edge("padding", 3);
        let dy = self.elements[e].edge("border", 0) + self.elements[e].edge("padding", 0);
        self.elements[child].rx = x + dx;
        self.elements[child].ry = y + dy;
    }
    fn grid(&self, e: usize) -> Grid {
        let items = self.items(e);
        let columns: Vec<String> = if self.elements[e].s("grid-template-columns") == "none" {
            vec!["auto".to_string()]
        } else {
            self.elements[e].s("grid-template-columns").split(' ').map(str::to_string).collect()
        };
        let rows: Vec<String> = if self.elements[e].s("grid-template-rows") == "none" {
            Vec::new()
        } else {
            self.elements[e].s("grid-template-rows").split(' ').map(str::to_string).collect()
        };
        let mut areas: Vec<Area> = items.iter().map(|i| {
            let (col, cols) = placement(self.elements[*i].s("grid-column"));
            let (row, rows) = placement(self.elements[*i].s("grid-row"));
            Area {
                row, col, rows, cols
            }
        }).collect();
        let nc = columns.len().max(areas.iter().map(|a| if a.col == 0 {
            a.cols
        } else {
            a.col + a.cols - 1
        }).max().unwrap_or(0));
        let mut occupied = BTreeSet::new();
        for a in &areas {
            if a.row != 0 && a.col != 0 {
                mark(a, &mut occupied);
            }
        }
        let (mut cr, mut cc) = (1, 1);
        for a in &mut areas {
            if a.row != 0 && a.col != 0 {
                continue;
            }
            if a.row != 0 {
                a.col = (1..=nc - a.cols + 1).find(|c| !overlaps(a, a.row, *c, &occupied)).unwrap_or(1);
            } else if a.col != 0 {
                if a.col < cc {
                    cr += 1;
                }
                let mut r = cr;
                while overlaps(a, r, a.col, &occupied) {
                    r += 1;
                }
                a.row = r;
                cr = r;
                cc = a.col + a.cols;
            } else {
                let (mut r, mut c) = (cr, cc);
                loop {
                    if c + a.cols - 1 > nc {
                        r += 1;
                        c = 1;
                    } else if overlaps(a, r, c, &occupied) {
                        c += 1;
                    } else {
                        break;
                    }
                }
                a.row = r;
                a.col = c;
                cr = r;
                cc = c + a.cols;
            }
            mark(a, &mut occupied);
        }
        let nr = rows.len().max(areas.iter().map(|a| a.row + a.rows - 1).max().unwrap_or(0));
        Grid {
            items, areas, columns, rows, nc, nr
        }
    }
    fn contribution(&self, e: usize) -> i64 {
        let node = &self.elements[e];
        node.clamp(node.resolve("width", None, true).unwrap_or_else(|| self.max_content(e)), None, true) + node.frame(true) + node.margin(true)
    }
    fn max_content(&self, e: usize) -> i64 {
        let node = &self.elements[e];
        if let Some(text) = &node.text {
            return text.len() as i64;
        }
        let children = self.flow(e);
        if node.s("display") == "flex" && node.s("flex-direction").starts_with("row") {
            children.iter().map(|c| self.contribution(*c)).sum::<i64>() + node.n("column-gap") * children.len().saturating_sub(1) as i64
        } else if node.s("display") == "grid" {
            let g = self.grid(e);
            let p: Vec<i64> = g.items.iter().map(|i| self.contribution(*i)).collect();
            tracks(&g, true, None, node.n("column-gap"), &p).iter().sum::<i64>() + node.n("column-gap") * (g.nc - 1) as i64
        } else {
            children.iter().map(|c| self.contribution(*c)).max().unwrap_or(0)
        }
    }
    fn layout(&mut self, e: usize, cw_ref: i64, ch_ref: Option<i64>, fw: Option<i64>, given_height: Option<i64>) -> i64 {
        let node = &self.elements[e];
        let cw = fw.unwrap_or_else(|| node.clamp(node.resolve("width", Some(cw_ref), true).unwrap_or((cw_ref - node.margin(true) - node.frame(true)).max(0)), Some(cw_ref), true));
        let fh = given_height.or_else(|| node.resolve("height", ch_ref, false).map(|h| node.clamp(h, ch_ref, false)));
        self.elements[e].cw = cw;
        let text = self.elements[e].text.clone();
        let display = self.elements[e].s("display").to_string();
        let a = if let Some(text) = text {
            let lines = wrap(&text, cw);
            let a = lines.len() as i64;
            self.elements[e].lines = lines;
            a
        } else if display == "flex" {
            self.flex(e, fh, ch_ref)
        } else if display == "grid" {
            self.grid_layout(e, fh)
        } else {
            let (mut bottom, mut previous, mut first): (i64, i64, bool) = (0, 0, true);
            for child in self.flow(e) {
                self.layout(child, cw, fh, None, None);
                let top = self.elements[child].edge("margin", 0);
                let y = bottom + if first {
                    top
                } else {
                    previous.max(top)
                };
                self.place(e, child, self.elements[child].edge("margin", 3), y);
                bottom = y + self.elements[child].border_height();
                previous = self.elements[child].edge("margin", 2);
                first = false;
            }
            bottom + previous
        };
        self.elements[e].ch = fh.unwrap_or_else(|| self.elements[e].clamp(a, ch_ref, false));
        a
    }
    fn flex(&mut self, e: usize, k: Option<i64>, height_reference: Option<i64>) -> i64 {
        let items = self.items(e);
        let horizontal = self.elements[e].s("flex-direction").starts_with("row");
        let reverse = self.elements[e].s("flex-direction").ends_with("reverse");
        let gap = self.elements[e].n(if horizontal {
            "column-gap"
        } else {
            "row-gap"
        });
        let line_gap = self.elements[e].n("row-gap");
        let cw = self.elements[e].cw;
        let reference = if horizontal {
            Some(cw)
        } else {
            k
        };
        let mut cross = vec![0; items.len()];
        let mut base = vec![0; items.len()];
        let mut hypothetical = vec![0; items.len()];
        let outer: Vec<i64> = items.iter().map(|i| self.elements[*i].frame(horizontal) + self.elements[*i].margin(horizontal)).collect();
        for (i, child) in items.iter().copied().enumerate() {
            if !horizontal {
                let node = &self.elements[child];
                let r = (cw - node.margin(true) - node.frame(true)).max(0);
                let value = node.resolve("width", Some(cw), true).unwrap_or_else(|| if self.align(e, child) == "stretch" {
                    r
                } else {
                    self.max_content(child).min(r)
                });
                cross[i] = node.clamp(value, Some(cw), true);
            }
            let b = self.elements[child].resolve("flex-basis", reference, horizontal).or_else(|| self.elements[child].resolve(if horizontal {
                "width"
            } else {
                "height"
            }, reference, horizontal));
            base[i] = b.unwrap_or_else(|| if horizontal {
                self.max_content(child)
            } else {
                self.layout(child, cw, k, Some(cross[i]), None)
            });
            hypothetical[i] = self.elements[child].clamp(base[i], reference, horizontal);
        }
        let length = if horizontal {
            cw
        } else {
            k.unwrap_or_else(|| self.elements[e].clamp((0..items.len()).map(|i| hypothetical[i] + outer[i]).sum::<i64>() + gap * items.len().saturating_sub(1) as i64, height_reference, false))
        };
        let mut lines: Vec<Vec<usize>> = Vec::new();
        let mut used = 0;
        for i in 0..items.len() {
            let size = hypothetical[i] + outer[i];
            if lines.is_empty() || (horizontal && self.elements[e].s("flex-wrap") == "wrap" && used + gap + size > length) {
                lines.push(vec![i]);
                used = size;
            } else {
                used += gap + size;
                lines.last_mut().unwrap().push(i);
            }
        }
        let mut line_start = 0;
        for line in &lines {
            let total_gap = gap * (line.len() - 1) as i64;
            let grow = line.iter().map(|i| hypothetical[*i] + outer[*i]).sum::<i64>() + total_gap < length;
            let weights: Vec<i64> = line.iter().map(|i| if grow {
                self.elements[items[*i]].n("flex-grow")
            } else {
                self.elements[items[*i]].n("flex-shrink") * base[*i]
            }).collect();
            let mut target: Vec<i64> = line.iter().map(|i| hypothetical[*i]).collect();
            let mut frozen: Vec<bool> = line.iter().enumerate().map(|(j, i)| weights[j] == 0 || if grow {
                base[*i] > hypothetical[*i]
            } else {
                base[*i] < hypothetical[*i]
            }).collect();
            while frozen.iter().any(|v| !v) {
                let free = length - total_gap - (0..line.len()).map(|j| (if frozen[j] {
                    target[j]
                } else {
                    base[line[j]]
                }) + outer[line[j]]).sum::<i64>();
                let w: Vec<i64> = (0..line.len()).map(|j| if frozen[j] {
                    0
                } else {
                    weights[j]
                }).collect();
                let assigned = distribution((if grow {
                    free
                } else {
                    -free
                }).max(0), &w);
                let mut violations = vec![0; line.len()];
                for j in 0..line.len() {
                    if !frozen[j] {
                        let tentative = base[line[j]] + if grow {
                            assigned[j]
                        } else {
                            -assigned[j]
                        };
                        target[j] = self.elements[items[line[j]]].clamp(tentative, reference, horizontal);
                        violations[j] = target[j] - tentative;
                    }
                }
                let violation: i64 = violations.iter().sum();
                for j in 0..line.len() {
                    if violation == 0 || violation > 0 && violations[j] > 0 || violation < 0 && violations[j] < 0 {
                        frozen[j] = true;
                    }
                }
            }
            if horizontal {
                for j in 0..line.len() {
                    let i = line[j];
                    self.layout(items[i], cw, k, Some(target[j]), None);
                    cross[i] = self.elements[items[i]].ch;
                }
            }
            let mut line_cross = if !horizontal {
                cw
            } else {
                line.iter().map(|i| cross[*i] + self.elements[items[*i]].frame(false) + self.elements[items[*i]].margin(false)).max().unwrap()
            };
            if horizontal && lines.len() == 1 {
                line_cross = k.unwrap_or_else(|| self.elements[e].clamp(line_cross, height_reference, false));
            }
            let remaining = length - (0..line.len()).map(|j| target[j] + outer[line[j]]).sum::<i64>() - total_gap;
            let mut spaces = vec![0; line.len()];
            if remaining > 0 {
                let mode = self.elements[e].s("justify-content");
                if mode == "end" {
                    spaces[0] = remaining;
                } else if mode == "center" {
                    spaces[0] = remaining / 2;
                } else if mode.starts_with("space-") {
                    let weights: Vec<i64> = (0..=line.len()).map(|j| if mode == "space-evenly" {
                        1
                    } else if j == 0 || j == line.len() {
                        if mode == "space-between" {
                            0
                        } else {
                            1
                        }
                    } else if mode == "space-around" {
                        2
                    } else {
                        1
                    }).collect();
                    let assigned = distribution(remaining, &weights);
                    spaces.copy_from_slice(&assigned[..line.len()]);
                }
            }
            let mut cursor = 0;
            for j in 0..line.len() {
                let i = line[j];
                let child = items[i];
                let align = self.align(e, child);
                if horizontal {
                    if align == "stretch" && self.elements[child].s("height") == "auto" {
                        cross[i] = self.elements[child].clamp((line_cross - self.elements[child].margin(false) - self.elements[child].frame(false)).max(0), k, false);
                        self.layout(child, cw, k, Some(target[j]), Some(cross[i]));
                    } else {
                        self.layout(child, cw, k, Some(target[j]), None);
                        cross[i] = self.elements[child].ch;
                    }
                } else {
                    self.layout(child, cw, k, Some(cross[i]), Some(target[j]));
                }
                cursor += spaces[j];
                let main = if reverse {
                    length - cursor - target[j] - outer[i]
                } else {
                    cursor
                };
                let cross_pos = line_start + offset(line_cross - cross[i] - self.elements[child].frame(!horizontal) - self.elements[child].margin(!horizontal), &align);
                let ml = self.elements[child].edge("margin", 3);
                let mt = self.elements[child].edge("margin", 0);
                if horizontal {
                    self.place(e, child, main + ml, cross_pos + mt);
                } else {
                    self.place(e, child, cross_pos + ml, main + mt);
                }
                cursor += target[j] + outer[i] + gap;
            }
            line_start += line_cross + line_gap;
        }
        if horizontal {
            if lines.is_empty() {
                0
            } else {
                line_start - line_gap
            }
        } else {
            length
        }
    }
    fn grid_layout(&mut self, e: usize, k: Option<i64>) -> i64 {
        let g = self.grid(e);
        let col_gap = self.elements[e].n("column-gap");
        let row_gap = self.elements[e].n("row-gap");
        let p: Vec<i64> = g.items.iter().map(|i| self.contribution(*i)).collect();
        let columns = tracks(&g, true, Some(self.elements[e].cw), col_gap, &p);
        let mut widths = vec![0; g.items.len()];
        let mut areas = vec![0; g.items.len()];
        let mut contributions = Vec::new();
        for i in 0..g.items.len() {
            let a = &g.areas[i];
            let child = g.items[i];
            let aw = columns[a.col - 1..a.col - 1 + a.cols].iter().sum::<i64>() + col_gap * (a.cols - 1) as i64;
            areas[i] = aw;
            widths[i] = self.elements[child].clamp(self.elements[child].resolve("width", Some(aw), true).unwrap_or((aw - self.elements[child].margin(true) - self.elements[child].frame(true)).max(0)), Some(aw), true);
            self.layout(child, aw, None, Some(widths[i]), None);
            contributions.push(self.elements[child].border_height() + self.elements[child].margin(false));
        }
        let rows = tracks(&g, false, k, row_gap, &contributions);
        for i in 0..g.items.len() {
            let a = &g.areas[i];
            let child = g.items[i];
            let align = self.align(e, child);
            let ah = rows[a.row - 1..a.row - 1 + a.rows].iter().sum::<i64>() + row_gap * (a.rows - 1) as i64;
            let ax = columns[..a.col - 1].iter().sum::<i64>() + col_gap * (a.col - 1) as i64;
            let ay = rows[..a.row - 1].iter().sum::<i64>() + row_gap * (a.row - 1) as i64;
            let fh = if align == "stretch" && self.elements[child].s("height") == "auto" {
                Some(self.elements[child].clamp((ah - self.elements[child].margin(false) - self.elements[child].frame(false)).max(0), Some(ah), false))
            } else {
                None
            };
            self.layout(child, areas[i], Some(ah), Some(widths[i]), fh);
            let dy = offset(ah - self.elements[child].border_height() - self.elements[child].margin(false), &align);
            self.place(e, child, ax + self.elements[child].edge("margin", 3), ay + dy + self.elements[child].edge("margin", 0));
        }
        rows.iter().sum::<i64>() + row_gap * g.nr.saturating_sub(1) as i64
    }
    fn containing(&self, e: usize) -> Option<usize> {
        let mut p = self.elements[e].parent;
        while let Some(i) = p {
            if self.elements[i].s("position") != "static" {
                return Some(i);
            }
            p = self.elements[i].parent;
        }
        None
    }
    fn reflow(&mut self) {
        for i in 0..self.elements.len() {
            let mut style = defaults();
            let mut specificity: BTreeMap<String, i32> = BTreeMap::new();
            for rule in &self.rules {
                let node = &self.elements[i];
                let best = rule.selectors.iter().filter_map(|s| {
                    if let Some(id) = s.strip_prefix('#') {
                        if id == node.id {
                            Some(2)
                        } else {
                            None
                        }
                    } else if let Some(class) = s.strip_prefix('.') {
                        if node.classes.contains(class) {
                            Some(1)
                        } else {
                            None
                        }
                    } else if s == &node.kind {
                        Some(0)
                    } else {
                        None
                    }
                }).max();
                if let Some(best) = best {
                    for (p, v) in &rule.values {
                        if best >= *specificity.get(p).unwrap_or(&-1) {
                            style.insert(p.clone(), v.clone());
                            specificity.insert(p.clone(), best);
                        }
                    }
                }
            }
            style.extend(self.elements[i].overrides.clone());
            self.elements[i].style = style;
            self.elements[i].displayed = self.elements[i].s("display") != "none" && self.elements[i].parent.map_or(true, |p| self.elements[p].displayed);
        }
        if self.elements[0].displayed && self.elements[0].s("position") != "absolute" {
            self.layout(0, self.width, Some(self.height), None, None);
            self.elements[0].rx = self.elements[0].edge("margin", 3);
            self.elements[0].ry = self.elements[0].edge("margin", 0);
        }
        for i in 0..self.elements.len() {
            if !self.elements[i].displayed || self.elements[i].s("position") != "absolute" {
                continue;
            }
            let block = self.containing(i);
            let cbw = block.map_or(self.width, |b| self.elements[b].cw + self.elements[b].edge("padding", 1) + self.elements[b].edge("padding", 3));
            let cbh = block.map_or(self.height, |b| self.elements[b].ch + self.elements[b].edge("padding", 0) + self.elements[b].edge("padding", 2));
            let side = |s: &str| if self.elements[i].s(s) == "auto" {
                None
            } else {
                Some(self.elements[i].n(s))
            };
            let (left, right, top, bottom) = (side("left"), side("right"), side("top"), side("bottom"));
            let node = &self.elements[i];
            let r = (cbw - left.unwrap_or(0) - right.unwrap_or(0) - node.margin(true) - node.frame(true)).max(0);
            let w = node.resolve("width", Some(cbw), true).unwrap_or_else(|| if left.is_some() && right.is_some() {
                r
            } else {
                self.max_content(i).min(r)
            });
            let fw = node.clamp(w, Some(cbw), true);
            let fh = if node.s("height") == "auto" && top.is_some() && bottom.is_some() {
                Some(node.clamp((cbh - top.unwrap() - bottom.unwrap() - node.margin(false) - node.frame(false)).max(0), Some(cbh), false))
            } else {
                None
            };
            self.layout(i, cbw, Some(cbh), Some(fw), fh);
            let node = &self.elements[i];
            let rx = if let Some(left) = left {
                left + node.edge("margin", 3)
            } else if let Some(right) = right {
                cbw - right - node.edge("margin", 1) - node.border_width()
            } else {
                node.edge("margin", 3)
            };
            let ry = if let Some(top) = top {
                top + node.edge("margin", 0)
            } else if let Some(bottom) = bottom {
                cbh - bottom - node.edge("margin", 2) - node.border_height()
            } else {
                node.edge("margin", 0)
            };
            self.elements[i].rx = rx;
            self.elements[i].ry = ry;
        }
        for i in 0..self.elements.len() {
            if !self.elements[i].displayed {
                continue;
            }
            let absolute = self.elements[i].s("position") == "absolute";
            let reference = if absolute {
                self.containing(i)
            } else {
                self.elements[i].parent
            };
            let bx = reference.map_or(0, |p| self.elements[p].x + if absolute {
                self.elements[p].edge("border", 3)
            } else {
                0
            });
            let by = reference.map_or(0, |p| self.elements[p].y + if absolute {
                self.elements[p].edge("border", 0)
            } else {
                0
            });
            let node = &self.elements[i];
            let (dx, dy) = if node.s("position") == "relative" {
                (if node.s("left") != "auto" {
                    node.n("left")
                } else if node.s("right") != "auto" {
                    -node.n("right")
                } else {
                    0
                }, if node.s("top") != "auto" {
                    node.n("top")
                } else if node.s("bottom") != "auto" {
                    -node.n("bottom")
                } else {
                    0
                })
            } else {
                (0, 0)
            };
            self.elements[i].x = bx + self.elements[i].rx + dx;
            self.elements[i].y = by + self.elements[i].ry + dy;
        }
    }
    fn snapshot(&self) -> Vec<Option<Rect>> {
        self.elements.iter().map(|e| if e.displayed {
            Some(e.border())
        } else {
            None
        }).collect()
    }
    fn changed(&self, old: &[Option<Rect>]) -> String {
        let current = self.snapshot();
        let ids: Vec<&str> = (0..old.len()).filter(|i| old[*i] != current[*i]).map(|i| self.elements[i].id.as_str()).collect();
        if ids.is_empty() {
            "no change".to_string()
        } else {
            ids.join(" ")
        }
    }
    fn render(&self) -> Vec<String> {
        let mut screen = vec![vec![b'.'; self.width as usize]; self.height as usize];
        for e in &self.elements {
            if !e.displayed {
                continue;
            }
            let b = e.border();
            for y in b.y.max(0)..(b.y + b.h).min(self.height) {
                for x in b.x.max(0)..(b.x + b.w).min(self.width) {
                    let horizontal = e.edge("border", 0) == 1 && y == b.y || e.edge("border", 2) == 1 && y == b.y + b.h - 1;
                    let vertical = e.edge("border", 3) == 1 && x == b.x || e.edge("border", 1) == 1 && x == b.x + b.w - 1;
                    screen[y as usize][x as usize] = if horizontal && vertical {
                        b'+'
                    } else if horizontal {
                        b'-'
                    } else if vertical {
                        b'|'
                    } else {
                        b' '
                    };
                }
            }
            if e.text.is_some() {
                let c = e.content();
                for (i, line) in e.lines.iter().enumerate() {
                    for (j, ch) in line.bytes().enumerate() {
                        let x = c.x + j as i64;
                        let y = c.y + i as i64;
                        if x >= 0 && x < self.width && y >= 0 && y < self.height {
                            screen[y as usize][x as usize] = ch;
                        }
                    }
                }
            }
        }
        let frame = "#".repeat(self.width as usize + 2);
        let mut out = vec![format!("render {}x{}", self.width, self.height), frame.clone()];
        for row in screen {
            out.push(format!("#{}#", String::from_utf8(row).unwrap()));
        }
        out.push(frame);
        out
    }
    fn command(&mut self, line: &str) -> Vec<String> {
        let a: Vec<&str> = line.split(' ').collect();
        match a[0] {
            "LAYOUT" => {
                let mut out = vec![format!("layout {}x{}", self.width, self.height)];
                for e in &self.elements {
                    out.push(format!("{}{} {}", "  ".repeat(e.depth), e.id, if e.displayed {
                        e.border().text()
                    } else {
                        "none".to_string()
                    }));
                }
                out
            },
            "BOX" => {
                let e = match self.by_id.get(a[1]) {
                    Some(i) => &self.elements[*i], None => return vec![format!("error: unknown element {}", a[1])]
                };
                if !e.displayed {
                    vec![format!("box {}: none", e.id)]
                } else {
                    vec![format!("box {}", e.id), format!("margin {}", e.margin_box().text()), format!("border {}", e.border().text()), format!("padding {}", e.padding().text()), format!("content {}", e.content().text())]
                }
            },
            "RENDER" => self.render(),
            "HIT" => {
                let x: i64 = a[1].parse().unwrap();
                let y: i64 = a[2].parse().unwrap();
                if x >= self.width || y >= self.height {
                    return vec![format!("error: point {} {} outside viewport", x, y)];
                }
                let mut at = (0..self.elements.len()).rev().find(|i| self.elements[*i].displayed && self.elements[*i].border().contains(x, y));
                let mut path = Vec::new();
                while let Some(i) = at {
                    path.push(self.elements[i].id.clone());
                    at = self.elements[i].parent;
                }
                path.reverse();
                vec![format!("hit {} {}: {}", x, y, if path.is_empty() {
                    "none".to_string()
                } else {
                    path.join(" > ")
                })]
            },
            "SET" => {
                let (id, p) = (a[1], a[2]);
                let value = a[3..].join(" ");
                let i = match self.by_id.get(id) {
                    Some(i) => *i, None => return vec![format!("error: unknown element {}", id)]
                };
                if !defaults().contains_key(p) && !shorthand(p) {
                    return vec![format!("error: unknown property {}", p)];
                }
                let values = match declaration(p, &value) {
                    Some(v) => v, None => return vec![format!("error: invalid value for {}: {}", p, value)]
                };
                let old = self.snapshot();
                self.elements[i].overrides.extend(values);
                self.reflow();
                vec![format!("set {} {} {}: {}", id, p, value, self.changed(&old))]
            },
            "VIEWPORT" => {
                let w: i64 = a[1].parse().unwrap();
                let h: i64 = a[2].parse().unwrap();
                if !(1..=80).contains(&w) || !(1..=40).contains(&h) {
                    return vec![format!("error: invalid viewport {} {}", w, h)];
                }
                let old = self.snapshot();
                self.width = w;
                self.height = h;
                self.reflow();
                vec![format!("viewport {} {}: {}", w, h, self.changed(&old))]
            },
            "OVERFLOW" => {
                let ids: Vec<&str> = (0..self.elements.len()).filter(|i| {
                    let e = &self.elements[*i];
                    e.displayed && if e.text.is_some() {
                        e.lines.iter().any(|s| s.len() as i64 > e.cw) || e.lines.len() as i64 > e.ch
                    } else {
                        self.flow(*i).iter().any(|c| !e.content().encloses(self.elements[*c].margin_box()))
                    }
                }).map(|i| self.elements[i].id.as_str()).collect();
                vec![format!("overflow: {}", if ids.is_empty() {
                    "none".to_string()
                } else {
                    ids.join(" ")
                })]
            },
            name => vec![format!("error: unknown command {}", name)],
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let size: Vec<i64> = lines.next().unwrap().split(' ').map(|s| s.parse().unwrap()).collect();
    let mut rules = Vec::new();
    for line in lines.by_ref() {
        if line == "---" {
            break;
        }
        let at = line.find(" { ").unwrap();
        let selectors = line[..at].split(", ").map(str::to_string).collect();
        let mut values = Vec::new();
        for d in line[at + 3..line.len() - 2].split("; ") {
            let colon = d.find(": ").unwrap();
            if let Some(v) = declaration(&d[..colon], &d[colon + 2..]) {
                values.extend(v);
            }
        }
        rules.push(Rule {
            selectors, values
        });
    }
    let mut elements: Vec<Element> = Vec::new();
    let mut ancestors = Vec::new();
    let mut by_id = BTreeMap::new();
    for line in lines.by_ref() {
        if line == "===" {
            break;
        }
        let spaces = line.bytes().take_while(|b| *b == b' ').count();
        let depth = spaces / 2;
        let body = &line[spaces..];
        let (head, text) = if let Some(at) = body.find(' ') {
            (&body[..at], Some(body[at + 2..body.len() - 1].to_string()))
        } else {
            (body, None)
        };
        let hash = head.find('#').unwrap();
        let parts: Vec<&str> = head[hash + 1..].split('.').collect();
        let index = elements.len();
        let parent = if depth == 0 {
            None
        } else {
            Some(ancestors[depth - 1])
        };
        let e = Element {
            kind: head[..hash].to_string(), id: parts[0].to_string(), classes: parts[1..].iter().map(|s| s.to_string()).collect(), text, parent, depth, children: Vec::new(), overrides: BTreeMap::new(), style: defaults(), displayed: false, cw: 0, ch: 0, rx: 0, ry: 0, x: 0, y: 0, lines: Vec::new()
        };
        by_id.insert(e.id.clone(), index);
        elements.push(e);
        if let Some(p) = parent {
            elements[p].children.push(index);
        }
        ancestors.truncate(depth);
        ancestors.push(index);
    }
    let mut document = Document {
        width: size[0], height: size[1], rules, elements, by_id
    };
    document.reflow();
    let mut output = String::new();
    for line in lines {
        if line == "END" {
            break;
        }
        for result in document.command(line) {
            output.push_str(&result);
            output.push('\n');
        }
    }
    print!("{}", output);
}
