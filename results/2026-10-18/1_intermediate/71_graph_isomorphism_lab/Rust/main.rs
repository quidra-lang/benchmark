use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};
#[derive(Clone)]
struct Graph {
    adjacent: Vec<u32>,
}
impl Graph {
    fn new(n: usize) -> Self {
        Self {
            adjacent: vec![0; n]
        }
    }
    fn n(&self) -> usize {
        self.adjacent.len()
    }
    fn has(&self, u: usize, v: usize) -> bool {
        self.adjacent[u] & (1 << v) != 0
    }
    fn join(&mut self, u: usize, v: usize) {
        self.adjacent[u] |= 1 << v;
        self.adjacent[v] |= 1 << u;
    }
    fn edges(&self) -> Vec<(usize, usize)> {
        (0..self.n()).flat_map(|u| (u + 1..self.n()).filter_map(move |v| self.has(u, v).then_some((u, v)))).collect()
    }
    fn degrees(&self) -> Vec<usize> {
        self.adjacent.iter().map(|a| a.count_ones() as usize).collect()
    }
    fn refine(&self, mut colors: Vec<usize>) -> (Vec<usize>, usize) {
        let mut rounds = 0;
        loop {
            let signatures: Vec<_> = (0..self.n()).map(|v| {
                let mut neighbors: Vec<_> = (0..self.n()).filter(|&w| self.has(v, w)).map(|w| colors[w]).collect();
                neighbors.sort();
                (colors[v], neighbors)
            }).collect();
            let unique: Vec<_> = signatures.iter().cloned().collect::<BTreeSet<_>>().into_iter().collect();
            if unique.len() == color_count(&colors) {
                return (colors, rounds);
            }
            colors = signatures.iter().map(|s| unique.binary_search(s).unwrap()).collect();
            rounds += 1;
        }
    }
    fn stable(&self) -> (Vec<usize>, usize) {
        let degrees = self.degrees();
        let unique: Vec<_> = degrees.iter().copied().collect::<BTreeSet<_>>().into_iter().collect();
        self.refine(degrees.iter().map(|d| unique.binary_search(d).unwrap()).collect())
    }
    fn leaf_string(&self, colors: &[usize]) -> String {
        let mut inverse = vec![0; self.n()];
        for (v, &c) in colors.iter().enumerate() {
            inverse[c] = v;
        }
        (0..self.n()).flat_map(|i| (i + 1..self.n()).map(move |j| (i, j)))
        .map(|(i, j)| if self.has(inverse[i], inverse[j]) {
            '1'
        } else {
            '0'
        }).collect()
    }
    fn canonical(&self) -> Canonical {
        fn visit(g: &Graph, colors: Vec<usize>, result: &mut Canonical) {
            result.nodes += 1;
            let k = color_count(&colors);
            if k == g.n() {
                result.leaves += 1;
                let text = g.leaf_string(&colors);
                if result.winners.is_empty() || text > result.text {
                    result.text = text;
                    result.label = colors.clone();
                    result.winners.clear();
                    result.winners.push(colors);
                } else if text == result.text {
                    result.winners.push(colors);
                }
                return;
            }
            let cell = (0..k).map(|c| (colors.iter().filter(|&&x| x == c).count(), c))
            .filter(|&(size, _)| size > 1).min().unwrap().1;
            for v in 0..g.n() {
                if colors[v] == cell {
                    visit(g, g.refine(individualize(&colors, v)).0, result);
                }
            }
        }
        let mut result = Canonical {
            nodes: 0, leaves: 0, text: String::new(), label: Vec::new(), winners: Vec::new()
        };
        visit(self, self.stable().0, &mut result);
        result
    }
    fn invariants(&self) -> Invariants {
        let n = self.n();
        let mut sizes = Vec::new();
        let mut seen = vec![false; n];
        let mut eccentricities = Vec::new();
        let mut girth: Option<usize> = None;
        let mut bipartite = true;
        for start in 0..n {
            let mut distance = vec![None; n];
            let mut parent = vec![n; n];
            let mut queue = VecDeque::from([start]);
            distance[start] = Some(0usize);
            while let Some(u) = queue.pop_front() {
                for v in 0..n {
                    if !self.has(u, v) {
                        continue;
                    }
                    if let Some(d) = distance[v] {
                        if d % 2 == distance[u].unwrap() % 2 {
                            bipartite = false;
                        }
                        if parent[u] != v && parent[v] != u {
                            let length = distance[u].unwrap() + d + 1;
                            girth = Some(girth.map_or(length, |old| old.min(length)));
                        }
                    } else {
                        distance[v] = Some(distance[u].unwrap() + 1);
                        parent[v] = u;
                        queue.push_back(v);
                    }
                }
            }
            if !seen[start] {
                sizes.push(distance.iter().filter(|d| d.is_some()).count());
                for v in 0..n {
                    if distance[v].is_some() {
                        seen[v] = true;
                    }
                }
            }
            eccentricities.push(distance.into_iter().flatten().max().unwrap());
        }
        sizes.sort_by(|a, b| b.cmp(a));
        let mut degrees = self.degrees();
        degrees.sort_by(|a, b| b.cmp(a));
        let triangles = (0..n).map(|u| (u + 1..n).map(|v| (v + 1..n)
        .filter(|&w| self.has(u, v) && self.has(v, w) && self.has(u, w)).count()).sum::<usize>()).sum();
        Invariants {
            degrees, triangles, sizes: sizes.clone(), girth,
            diameter: (sizes.len() == 1).then(|| *eccentricities.iter().max().unwrap()),
            radius: (sizes.len() == 1).then(|| *eccentricities.iter().min().unwrap()), bipartite,
        }
    }
    fn clique(&self) -> Vec<usize> {
        let mut best = Vec::new();
        for mask in 1u32..1u32 << self.n() {
            let vertices: Vec<_> = (0..self.n()).filter(|&v| mask & (1 << v) != 0).collect();
            if vertices.len() < best.len() {
                continue;
            }
            if vertices.iter().all(|&v| (mask ^ (1 << v)) & !self.adjacent[v] == 0)
            && (vertices.len() > best.len() || vertices < best) {
                best = vertices;
            }
        }
        best
    }
    fn coloring(&self) -> (usize, Vec<usize>) {
        fn find(g: &Graph, limit: usize, colors: &mut Vec<usize>, used: usize) -> bool {
            let v = colors.len();
            if v == g.n() {
                return true;
            }
            for c in 0..limit.min(used + 1) {
                if (0..v).any(|u| g.has(u, v) && colors[u] == c) {
                    continue;
                }
                colors.push(c);
                if find(g, limit, colors, used.max(c + 1)) {
                    return true;
                }
                colors.pop();
            }
            false
        }
        for limit in 1..=self.n() {
            let mut colors = Vec::new();
            if find(self, limit, &mut colors, 0) {
                return (limit, colors);
            }
        }
        unreachable!()
    }
}
fn color_count(colors: &[usize]) -> usize {
    colors.iter().max().unwrap() + 1
}
fn individualize(colors: &[usize], v: usize) -> Vec<usize> {
    colors.iter().enumerate().map(|(w, &c)| if c < colors[v] || w == v {
        c
    } else {
        c + 1
    }).collect()
}
fn numbers(values: &[usize]) -> String {
    values.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")
}
fn yes(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "no"
    }
}
fn shown(value: Option<usize>, absent: &str) -> String {
    value.map_or(absent.into(), |v| v.to_string())
}
struct Canonical {
    nodes: usize, leaves: usize, text: String, label: Vec<usize>, winners: Vec<Vec<usize>>
}
struct Invariants {
    degrees: Vec<usize>, triangles: usize, sizes: Vec<usize>, girth: Option<usize>, diameter: Option<usize>, radius: Option<usize>, bipartite: bool
}
struct UnionFind {
    parent: Vec<usize>
}
impl UnionFind {
    fn new(n: usize) -> Self {
        Self {
            parent: (0..n).collect()
        }
    }
    fn root(&mut self, v: usize) -> usize {
        if self.parent[v] != v {
            self.parent[v] = self.root(self.parent[v]);
        }
        self.parent[v]
    }
    fn join(&mut self, u: usize, v: usize) {
        let a = self.root(u);
        let b = self.root(v);
        self.parent[a] = b;
    }
    fn orbits(&mut self) -> Vec<Vec<usize>> {
        let mut groups = BTreeMap::<usize, Vec<usize>>::new();
        for v in 0..self.parent.len() {
            groups.entry(self.root(v)).or_default().push(v);
        }
        let mut result: Vec<_> = groups.into_values().collect();
        result.sort_by_key(|g| g[0]);
        result
    }
}
fn graph_name(s: &str) -> bool {
    (1..=8).contains(&s.len()) && s.as_bytes()[0].is_ascii_lowercase() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}
fn number(s: &str) -> Option<usize> {
    if !(1..=3).contains(&s.len()) || (s.len() > 1 && s.starts_with('0')) || !s.bytes().all(|c| c.is_ascii_digit()) {
        None
    } else {
        s.parse().ok()
    }
}
fn edge(s: &str) -> Option<(usize, usize)> {
    let (a, b) = s.split_once('-')?;
    Some((number(a)?, number(b)?))
}
fn fail(reason: &str) -> String {
    format!("error: {reason}")
}
fn command(registry: &mut BTreeMap<String, Graph>, w: &[&str]) -> Result<Vec<String>, String> {
    let c = w[0];
    let a = &w[1..];
    let defining = ["GRAPH", "CYCLE", "PATH", "COMPLETE", "BIPARTITE", "STAR", "WHEEL", "PETERSEN", "HYPERCUBE", "CIRCULANT", "GRID", "COMPLEMENT", "LINE", "PRODUCT", "UNION", "RELABEL", "INDUCED", "CANONIZE"];
    let known = ["DELETE", "LIST", "SHOW", "INVARIANTS", "REFINE", "CANON", "ISO", "AUT", "SUBISO", "CLASSIFY"];
    if !defining.contains(&c) && !known.contains(&c) {
        return Err(fail(&format!("unknown command {c}")));
    }
    let count = a.len();
    let shape = match c {
        "GRAPH" | "RELABEL" => count >= 2, "CIRCULANT" | "INDUCED" => count >= 3,
        "REFINE" => count >= 1, "LIST" => count == 0, "PETERSEN" | "DELETE" | "SHOW" | "INVARIANTS" | "CANON" | "AUT" | "CLASSIFY" => count == 1,
        "BIPARTITE" | "GRID" | "PRODUCT" | "UNION" => count == 3, _ => count == 2,
    };
    if !shape {
        return Err(fail("bad arguments"));
    }
    let graph_positions: Vec<usize> = match c {
        "COMPLEMENT" | "LINE" | "RELABEL" | "INDUCED" | "CANONIZE" => vec![1],
        "PRODUCT" | "UNION" => vec![1, 2], "ISO" | "SUBISO" => vec![0, 1],
        "DELETE" | "SHOW" | "INVARIANTS" | "REFINE" | "CANON" | "AUT" => vec![0], _ => Vec::new(),
    };
    let numeric_positions: Vec<usize> = match c {
        "GRAPH" => vec![1], "CYCLE" | "PATH" | "COMPLETE" | "STAR" | "WHEEL" | "HYPERCUBE" => vec![1],
        "BIPARTITE" | "GRID" => vec![1, 2], "CIRCULANT" => (1..count).collect(),
        "RELABEL" | "INDUCED" => (2..count).collect(), "REFINE" => (1..count).collect(), "CLASSIFY" => vec![0], _ => Vec::new(),
    };
    for (i, word) in a.iter().enumerate() {
        let valid = if numeric_positions.contains(&i) {
            number(word).is_some()
        }
        else if c == "GRAPH" && i >= 2 {
            edge(word).is_some()
        } else {
            graph_name(word)
        };
        if !valid {
            return Err(fail("bad arguments"));
        }
    }
    for &i in &graph_positions {
        if !registry.contains_key(a[i]) {
            return Err(fail(&format!("no graph {}", a[i])));
        }
    }
    let num = |i: usize| number(a[i]).unwrap();
    let graph = |i: usize| registry[a[i]].clone();
    let bounded = |n: usize, minimum: usize| -> Result<usize, String> {
        if n < minimum {
            Err(fail("bad value"))
        } else if n > 16 {
            Err(fail("too large"))
        } else {
            Ok(n)
        }
    };
    if defining.contains(&c) {
        let mut g = match c {
            "GRAPH" | "CYCLE" | "PATH" | "COMPLETE" | "CIRCULANT" => Graph::new(bounded(num(1), if c == "CYCLE" || c == "CIRCULANT" {
                3
            } else {
                1
            })?),
            "STAR" | "WHEEL" => {
                if num(1) < if c == "STAR" {
                    1
                } else {
                    3
                } {
                    return Err(fail("bad value"));
                } Graph::new(bounded(num(1) + 1, 1)?)
            },
            "BIPARTITE" | "GRID" => {
                if num(1) == 0 || num(2) == 0 {
                    return Err(fail("bad value"));
                } Graph::new(bounded(if c == "GRID" {
                    num(1) * num(2)
                } else {
                    num(1) + num(2)
                }, 1)?)
            },
            "HYPERCUBE" => {
                if num(1) == 0 {
                    return Err(fail("bad value"));
                }
                if num(1) > 4 {
                    return Err(fail("too large"));
                } Graph::new(1 << num(1))
            },
            "PETERSEN" => Graph::new(10),
            "COMPLEMENT" | "RELABEL" | "CANONIZE" => Graph::new(graph(1).n()),
            "LINE" => {
                let m = graph(1).edges().len();
                if m == 0 {
                    return Err(fail("no edges"));
                } Graph::new(bounded(m, 1)?)
            },
            "INDUCED" => Graph::new(count - 2),
            "PRODUCT" => Graph::new(bounded(graph(1).n() * graph(2).n(), 1)?),
            "UNION" => Graph::new(bounded(graph(1).n() + graph(2).n(), 1)?), _ => unreachable!(),
        };
        let n = g.n();
        match c {
            "GRAPH" => for &word in &a[2..] {
                let (u, v) = edge(word).unwrap();
                if u >= n || v >= n || u == v {
                    return Err(fail(&format!("bad edge {word}")));
                }
                if g.has(u, v) {
                    return Err(fail(&format!("duplicate edge {word}")));
                }
                g.join(u, v);
            },
            "CYCLE" | "PATH" => {
                for i in 0..n - 1 {
                    g.join(i, i + 1);
                }
                if c == "CYCLE" {
                    g.join(n - 1, 0);
                }
            },
            "COMPLETE" => for i in 0..n {
                for j in i + 1..n {
                    g.join(i, j);
                }
            },
            "BIPARTITE" => for i in 0..num(1) {
                for j in num(1)..n {
                    g.join(i, j);
                }
            },
            "STAR" | "WHEEL" => {
                for i in 1..n {
                    g.join(0, i);
                }
                if c == "WHEEL" {
                    for i in 1..n - 1 {
                        g.join(i, i + 1);
                    } g.join(n - 1, 1);
                }
            },
            "PETERSEN" => for i in 0..5 {
                g.join(i, (i + 1) % 5);
                g.join(i, i + 5);
                g.join(i + 5, 5 + (i + 2) % 5);
            },
            "HYPERCUBE" => for u in 0..n {
                for bit in 0..num(1) {
                    g.join(u, u ^ (1 << bit));
                }
            },
            "CIRCULANT" => {
                let jumps: Vec<_> = (2..count).map(num).collect();
                if jumps.iter().any(|&j| j == 0 || 2 * j > n) || jumps.windows(2).any(|p| p[0] >= p[1]) {
                    return Err(fail("bad value"));
                }
                for i in 0..n {
                    for &j in &jumps {
                        g.join(i, (i + j) % n);
                    }
                }
            },
            "GRID" => for x in 0..num(1) {
                for y in 0..num(2) {
                    let u = x * num(2) + y;
                    if y + 1 < num(2) {
                        g.join(u, u + 1);
                    }
                    if x + 1 < num(1) {
                        g.join(u, u + num(2));
                    }
                }
            },
            "COMPLEMENT" => {
                let old = graph(1);
                for u in 0..n {
                    for v in u + 1..n {
                        if !old.has(u, v) {
                            g.join(u, v);
                        }
                    }
                }
            },
            "LINE" => {
                let edges = graph(1).edges();
                for i in 0..n {
                    for j in i + 1..n {
                        if [edges[i].0, edges[i].1].iter().any(|&v| v == edges[j].0 || v == edges[j].1) {
                            g.join(i, j);
                        }
                    }
                }
            },
            "PRODUCT" => {
                let x = graph(1);
                let y = graph(2);
                for u in 0..x.n() {
                    for (v, w) in y.edges() {
                        g.join(u * y.n() + v, u * y.n() + w);
                    }
                }
                for (u, v) in x.edges() {
                    for w in 0..y.n() {
                        g.join(u * y.n() + w, v * y.n() + w);
                    }
                }
            },
            "UNION" => {
                let x = graph(1);
                for (u, v) in x.edges() {
                    g.join(u, v);
                }
                for (u, v) in graph(2).edges() {
                    g.join(u + x.n(), v + x.n());
                }
            },
            "RELABEL" | "CANONIZE" => {
                let old = graph(1);
                let p: Vec<_> = if c == "CANONIZE" {
                    old.canonical().label
                } else {
                    (2..count).map(num).collect()
                };
                if p.len() != n || p.iter().copied().collect::<BTreeSet<_>>() != (0..n).collect() {
                    return Err(fail("bad permutation"));
                }
                for (u, v) in old.edges() {
                    g.join(p[u], p[v]);
                }
            },
            "INDUCED" => {
                let old = graph(1);
                let p: Vec<_> = (2..count).map(num).collect();
                if p.iter().any(|&v| v >= old.n()) || p.iter().collect::<BTreeSet<_>>().len() != p.len() {
                    return Err(fail("bad vertices"));
                }
                for u in 0..n {
                    for v in u + 1..n {
                        if old.has(p[u], p[v]) {
                            g.join(u, v);
                        }
                    }
                }
            }, _ => unreachable!(),
        }
        let output = format!("{} {} n {} m {}", if registry.contains_key(a[0]) {
            "redefined"
        } else {
            "defined"
        }, a[0], n, g.edges().len());
        registry.insert(a[0].into(), g);
        return Ok(vec![output]);
    }
    if c == "LIST" {
        let mut out = vec![format!("graphs {}", registry.len())];
        out.extend(registry.iter().map(|(name, g)| format!("{name} n {} m {}", g.n(), g.edges().len())));
        return Ok(out);
    }
    if c == "DELETE" {
        registry.remove(a[0]);
        return Ok(vec![format!("deleted {}", a[0])]);
    }
    if c == "CLASSIFY" {
        let n = num(0);
        if n == 0 {
            return Err(fail("bad value"));
        }
        if n > 5 {
            return Err(fail("too large"));
        }
        let pairs = Graph::new(n).n() * (n - 1) / 2;
        let mut classes = vec![BTreeSet::new(); pairs + 1];
        for mask in 0usize..1usize << pairs {
            let mut g = Graph::new(n);
            let mut bit = 0;
            for u in 0..n {
                for v in u + 1..n {
                    if mask & (1 << bit) != 0 {
                        g.join(u, v);
                    } bit += 1;
                }
            }
            classes[mask.count_ones() as usize].insert(g.canonical().text);
        }
        let mut out = vec![format!("classify {n} total {}", classes.iter().map(BTreeSet::len).sum::<usize>())];
        for (m, set) in classes.iter().enumerate() {
            out.push(format!("edges {m} count {} {}", set.len(), set.iter().map(|s| if s.is_empty() {
                "-"
            } else {
                s
            }).collect::<Vec<_>>().join(" ")));
        }
        return Ok(out);
    }
    let g = graph(0);
    let n = g.n();
    match c {
        "SHOW" => {
            let mut out = vec![format!("graph {} n {n} m {}", a[0], g.edges().len())];
            for u in 0..n {
                let neighbors: Vec<_> = (0..n).filter(|&v| g.has(u, v)).collect();
                out.push(format!("{u}:{}", if neighbors.is_empty() {
                    String::new()
                } else {
                    " ".to_string() + &numbers(&neighbors)
                }));
            } Ok(out)
        },
        "INVARIANTS" => {
            let inv = g.invariants();
            let mut out = vec![format!("invariants {}", a[0]), format!("degrees {}", numbers(&inv.degrees)), format!("edges {} triangles {}", g.edges().len(), inv.triangles), format!("components {} sizes {}", inv.sizes.len(), numbers(&inv.sizes)), format!("girth {} diameter {} radius {}", shown(inv.girth, "none"), shown(inv.diameter, "INF"), shown(inv.radius, "INF")), format!("bipartite {}", yes(inv.bipartite))];
            if n > 12 {
                out.extend(["clique -".into(), "chromatic -".into()]);
            } else {
                let clique = g.clique();
                let (chi, colors) = g.coloring();
                out.push(format!("clique {} {}", clique.len(), numbers(&clique)));
                out.push(format!("chromatic {chi} {}", numbers(&colors)));
            } Ok(out)
        },
        "REFINE" => {
            let vertices: Vec<_> = (1..count).map(num).collect();
            if vertices.iter().any(|&v| v >= n) {
                return Err(fail("bad vertices"));
            }
            let (mut colors, mut rounds) = g.stable();
            for v in vertices {
                if colors.iter().filter(|&&x| x == colors[v]).count() == 1 {
                    return Err(fail(&format!("singleton {v}")));
                }
                let (next, r) = g.refine(individualize(&colors, v));
                colors = next;
                rounds += r;
            }
            let k = color_count(&colors);
            let mut out = vec![format!("refine {} rounds {rounds} cells {k}", a[0])];
            for cell in 0..k {
                out.push(format!("{cell}: {}", numbers(&(0..n).filter(|&v| colors[v] == cell).collect::<Vec<_>>())));
            } Ok(out)
        },
        "CANON" => {
            let result = g.canonical();
            Ok(vec![format!("canon {} nodes {} leaves {}", a[0], result.nodes, result.leaves), format!("labels {}", numbers(&result.label)), format!("string {}", if result.text.is_empty() {
                "-"
            } else {
                &result.text
            })])
        },
        "ISO" => {
            let h = graph(1);
            let x = g.invariants();
            let y = h.invariants();
            let difference = if n != h.n() {
                Some(format!("vertices {n} {}", h.n()))
            } else if g.edges().len() != h.edges().len() {
                Some(format!("edges {} {}", g.edges().len(), h.edges().len()))
            } else if x.degrees != y.degrees {
                Some("degrees".into())
            } else if x.triangles != y.triangles {
                Some(format!("triangles {} {}", x.triangles, y.triangles))
            } else if x.sizes.len() != y.sizes.len() {
                Some(format!("components {} {}", x.sizes.len(), y.sizes.len()))
            } else if x.girth != y.girth {
                Some(format!("girth {} {}", shown(x.girth, "none"), shown(y.girth, "none")))
            } else if x.diameter != y.diameter {
                Some(format!("diameter {} {}", shown(x.diameter, "INF"), shown(y.diameter, "INF")))
            } else if x.bipartite != y.bipartite {
                Some(format!("bipartite {} {}", yes(x.bipartite), yes(y.bipartite)))
            } else {
                None
            };
            if let Some(reason) = difference {
                return Ok(vec![format!("not isomorphic {reason}")]);
            }
            let (p, r) = g.stable();
            let (q, s) = h.stable();
            let sizes = |colors: &[usize]| (0..color_count(colors)).map(|c| colors.iter().filter(|&&x| x == c).count()).collect::<Vec<_>>();
            if r != s || sizes(&p) != sizes(&q) {
                return Ok(vec!["not isomorphic refinement".into()]);
            }
            let x = g.canonical();
            let y = h.canonical();
            if x.text != y.text {
                return Ok(vec!["not isomorphic canonical".into()]);
            }
            let mapping: Vec<_> = x.label.iter().map(|c| y.label.iter().position(|d| d == c).unwrap()).collect();
            Ok(vec!["isomorphic".into(), format!("mapping {}", numbers(&mapping))])
        },
        "AUT" => {
            let result = g.canonical();
            let edges = g.edges();
            let mut vertices = UnionFind::new(n);
            let mut edge_sets = UnionFind::new(edges.len());
            let mut inverse = vec![0; n];
            for v in 0..n {
                inverse[result.label[v]] = v;
            }
            for label in &result.winners {
                let map: Vec<_> = label.iter().map(|&c| inverse[c]).collect();
                for v in 0..n {
                    vertices.join(v, map[v]);
                }
                for (i, &(u, v)) in edges.iter().enumerate() {
                    let e = (map[u].min(map[v]), map[u].max(map[v]));
                    edge_sets.join(i, edges.binary_search(&e).unwrap());
                }
            }
            let vo = vertices.orbits();
            let eo = edge_sets.orbits();
            let mut out = vec![format!("aut {} order {}", a[0], result.winners.len()), format!("vertex orbits {}", vo.len())];
            out.extend(vo.iter().map(|o| format!("orbit {}", numbers(o))));
            out.push(format!("edge orbits {}", eo.len()));
            for orbit in &eo {
                out.push(format!("orbit {}", orbit.iter().map(|&i| format!("{}-{}", edges[i].0, edges[i].1)).collect::<Vec<_>>().join(" ")));
            }
            out.push(format!("transitive vertex {} edge {}", yes(vo.len() == 1), yes(eo.len() == 1)));
            Ok(out)
        },
        "SUBISO" => {
            fn enumerate(p: &Graph, t: &Graph, mapping: &mut Vec<usize>, used: u32, induced: bool, counts: &mut [usize; 2], first: &mut Vec<(Vec<usize>, bool)>) {
                let v = mapping.len();
                if v == p.n() {
                    counts[0] += 1;
                    counts[1] += usize::from(induced);
                    if first.len() < 5 {
                        first.push((mapping.clone(), induced));
                    }
                    return;
                }
                for w in 0..t.n() {
                    if used & (1 << w) != 0 || (0..v).any(|u| p.has(u, v) && !t.has(mapping[u], w)) {
                        continue;
                    }
                    let next = induced && (0..v).all(|u| p.has(u, v) == t.has(mapping[u], w));
                    mapping.push(w);
                    enumerate(p, t, mapping, used | (1 << w), next, counts, first);
                    mapping.pop();
                }
            }
            let target = graph(1);
            let mut counts = [0; 2];
            let mut first = Vec::new();
            if n <= target.n() {
                enumerate(&g, &target, &mut Vec::new(), 0, true, &mut counts, &mut first);
            }
            let order = g.canonical().winners.len();
            let mut out = vec![format!("subiso {} {} embeddings {} induced {}", a[0], a[1], counts[0], counts[1]), format!("copies {} induced {}", counts[0] / order, counts[1] / order)];
            for (mapping, induced) in first {
                out.push(format!("embedding {}{}", numbers(&mapping), if induced {
                    " induced"
                } else {
                    ""
                }));
            } Ok(out)
        }, _ => unreachable!(),
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let n: usize = lines.next().unwrap().parse().unwrap();
    let mut registry = BTreeMap::new();
    for line in lines.take(n) {
        match command(&mut registry, &line.split(' ').collect::<Vec<_>>()) {
            Ok(out) => for line in out {
                println!("{line}");
            }, Err(error) => println!("{error}")
        }
    }
}
