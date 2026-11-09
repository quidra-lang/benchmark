mod predicates;
mod triangulation;
mod voronoi;
mod proximity;
mod plot;

use predicates::{Point, orient, d2, dot, incircle, fraction};
use triangulation::{Triangle, Triangulation};
use std::{collections::{BTreeMap, BTreeSet}, fs, io};

fn real(value: f64) -> String {
    let text = format!("{:.3}", value);
    if text == "-0.000" { "0.000".into() } else { text }
}

fn sites(values: &[usize]) -> String {
    values.iter().map(|s| (s + 1).to_string()).collect::<Vec<_>>().join(" ")
}

fn integer(word: &str) -> bool {
    let digits = word.strip_prefix('-').unwrap_or(word);
    !digits.is_empty() && digits.bytes().all(|c| c.is_ascii_digit())
}

struct Input {
    points: Vec<Point>,
    lines: usize,
    rejected: Vec<String>,
    width: usize,
    height: usize,
    layers: Vec<String>,
    sections: Vec<String>,
    alpha: Vec<i64>,
    queries: Vec<String>,
}

fn read() -> io::Result<Input> {
    let content = fs::read_to_string("input/points.txt")?;
    let mut result = Input {
        points: Vec::new(), lines: content.lines().count(), rejected: Vec::new(), width: 61, height: 31,
        layers: vec!["edges".into(), "hull".into(), "sites".into()], sections: vec!["summary".into()], alpha: Vec::new(), queries: Vec::new(),
    };
    let mut accepted = BTreeMap::new();
    for (line, text) in content.lines().enumerate() {
        if text.is_empty() || text.starts_with('#') { continue; }
        let fields: Vec<&str> = text.split_whitespace().collect();
        if fields.len() != 2 || fields.iter().any(|s| !integer(s)) {
            result.rejected.push(format!("reject {} format", line + 1));
            continue;
        }
        let point: Point = (fields[0].parse().unwrap(), fields[1].parse().unwrap());
        if point.0 < 0 || point.0 > 1000 || point.1 < 0 || point.1 > 1000 {
            result.rejected.push(format!("reject {} range", line + 1));
        } else if let Some(&s) = accepted.get(&point) {
            result.rejected.push(format!("reject {} duplicate {}", line + 1, s));
        } else {
            result.points.push(point);
            accepted.insert(point, result.points.len());
        }
    }
    for line in fs::read_to_string("input/params.txt")?.lines() {
        if line.is_empty() || line.starts_with('#') { continue; }
        let words: Vec<&str> = line.split_whitespace().collect();
        match words[0] {
            "plot" => { result.width = words[1].parse().unwrap(); result.height = words[2].parse().unwrap(); }
            "plot_layers" => result.layers = words[1..].iter().map(|s| s.to_string()).collect(),
            "sections" => result.sections = words[1..].iter().map(|s| s.to_string()).collect(),
            "alpha" => result.alpha = words[1..].iter().map(|s| s.parse().unwrap()).collect(),
            "query" => result.queries.push(words[1..].join(" ")),
            _ => unreachable!(),
        }
    }
    Ok(result)
}

fn convex_hull(points: &[Point], selected: &[usize]) -> Vec<usize> {
    if selected.len() <= 2 { return selected.to_vec(); }
    let mut sorted = selected.to_vec();
    sorted.sort_by_key(|&s| (points[s].0, points[s].1));
    let mut lower: Vec<usize> = Vec::new();
    for &s in &sorted {
        while lower.len() >= 2 && orient(points[lower[lower.len() - 2]], points[lower[lower.len() - 1]], points[s]) <= 0 { lower.pop(); }
        lower.push(s);
    }
    let mut upper: Vec<usize> = Vec::new();
    for &s in sorted.iter().rev() {
        while upper.len() >= 2 && orient(points[upper[upper.len() - 2]], points[upper[upper.len() - 1]], points[s]) <= 0 { upper.pop(); }
        upper.push(s);
    }
    lower.pop();
    upper.pop();
    lower.extend(upper);
    let first = lower.iter().enumerate().min_by_key(|&(_, s)| s).unwrap().0;
    lower.rotate_left(first);
    lower
}

#[derive(Clone, Copy)]
enum Circle {
    One(usize),
    Two(usize, usize),
    Three(usize, usize, usize),
}

impl Circle {
    fn relation(self, s: usize, points: &[Point]) -> i64 {
        match self {
            Self::One(a) => -d2(points[a], points[s]),
            Self::Two(a, b) => -dot(points[s], points[a], points[b]),
            Self::Three(a, b, c) => incircle(points[a], points[b], points[c], points[s]),
        }
    }

    fn geometry(self, points: &[Point]) -> ((i64, i64, i64), f64) {
        match self {
            Self::One(a) => ((points[a].0, points[a].1, 1), 0.0),
            Self::Two(a, b) => ((points[a].0 + points[b].0, points[a].1 + points[b].1, 2), d2(points[a], points[b]) as f64 / 4.0),
            Self::Three(a, b, c) => {
                for (u, v, w) in [(a, b, c), (a, c, b), (b, c, a)] {
                    if dot(points[w], points[u], points[v]) == 0 {
                        return Circle::Two(u, v).geometry(points);
                    }
                }
                (predicates::center(points[a], points[b], points[c]), voronoi::radius2(points[a], points[b], points[c]))
            }
        }
    }
}

fn enclosing(points: &[Point], hull: &[usize]) -> Circle {
    let mut circle = Circle::One(hull[0]);
    for i in 0..hull.len() {
        if circle.relation(hull[i], points) < 0 {
            circle = Circle::One(hull[i]);
            for j in 0..i {
                if circle.relation(hull[j], points) < 0 {
                    circle = Circle::Two(hull[i], hull[j]);
                    for k in 0..j {
                        if circle.relation(hull[k], points) < 0 {
                            let (a, b, c) = (hull[i], hull[j], hull[k]);
                            circle = if orient(points[a], points[b], points[c]) > 0 { Circle::Three(a, b, c) } else { Circle::Three(a, c, b) };
                        }
                    }
                }
            }
        }
    }
    circle
}

struct Analysis {
    input: Input,
    mesh: Triangulation,
    triangles: Vec<Triangle>,
    numbers: BTreeMap<(usize, usize), usize>,
    edges: Vec<(usize, usize)>,
    hull: Vec<usize>,
    neighbors: Vec<Vec<usize>>,
    centers: Vec<(i64, i64, i64)>,
    radius2: Vec<f64>,
    positions: Vec<&'static str>,
    gabriel: BTreeSet<(usize, usize)>,
    relative: BTreeSet<(usize, usize)>,
    mst: Vec<(usize, usize)>,
    mst_set: BTreeSet<(usize, usize)>,
    nearest: Vec<usize>,
}

impl Analysis {
    fn dual(&self, (i, j): (usize, usize)) -> String {
        if let (Some(&left), Some(&right)) = (self.numbers.get(&(i, j)), self.numbers.get(&(j, i))) {
            format!("segment {} {}", left + 1, right + 1)
        } else {
            let (u, v) = if self.numbers.contains_key(&(i, j)) { (i, j) } else { (j, i) };
            let direction = voronoi::outward(self.input.points[u], self.input.points[v]);
            format!("ray {} {} {}", self.numbers[&(u, v)] + 1, direction.0, direction.1)
        }
    }

    fn query(&self, text: &str) -> String {
        let words: Vec<&str> = text.split_whitespace().collect();
        let values: Vec<i64> = words[1..].iter().map(|s| s.parse().unwrap()).collect();
        let p = &self.input.points;
        let kind = words[0];
        let answer = if ["locate", "walk", "natural"].contains(&kind) {
            let q = (values[0], values[1]);
            match kind {
                "locate" => {
                    let location = if let Some(s) = p.iter().position(|&x| x == q) {
                        format!("vertex {}", s + 1)
                    } else if let Some(&(i, j)) = self.edges.iter().find(|&&(i, j)| orient(p[i], p[j], q) == 0 && dot(q, p[i], p[j]) < 0) {
                        format!("edge {} {}", i + 1, j + 1)
                    } else if let Some(tri) = self.triangles.iter().find(|&&[a, b, c]| orient(p[a], p[b], q) > 0 && orient(p[b], p[c], q) > 0 && orient(p[c], p[a], q) > 0) {
                        format!("triangle {}", sites(tri))
                    } else { "outside".into() };
                    let s = (0..p.len()).min_by_key(|&s| (d2(p[s], q), s)).unwrap();
                    format!("{} nearest {} d2 {}", location, s + 1, d2(p[s], q))
                }
                "walk" => {
                    let (path, outside) = triangulation::walk(q, p, &self.triangles, &self.numbers);
                    let end = outside.map_or_else(|| format!("triangle {}", path.last().unwrap() + 1), |(a, b)| format!("outside {} {}", a + 1, b + 1));
                    format!("steps {} {} path {}", path.len() - 1, end, sites(&path))
                }
                _ => {
                    let triangles: Vec<Triangle> = self.triangles.iter().copied().filter(|&[a, b, c]| incircle(p[a], p[b], p[c], q) > 0).collect();
                    let selected: Vec<usize> = triangles.iter().flat_map(|t| t.iter().copied()).collect::<BTreeSet<_>>().into_iter().collect();
                    format!("triangles {} sites {}", triangles.len(), if selected.is_empty() { "-".into() } else { sites(&selected) })
                }
            }
        } else if values.iter().any(|&s| s < 1 || s > p.len() as i64) {
            "error unknown_site".into()
        } else {
            let i = values[0] as usize - 1;
            let j = values.get(1).map_or(i, |&s| s as usize - 1);
            match kind {
                "neighbors" => format!("degree {} sites {}", self.neighbors[i].len(), sites(&self.neighbors[i])),
                "route" => {
                    let (path, length) = proximity::route(i, j, p, &self.neighbors);
                    format!("hops {} length {} path {}", path.len() - 1, real(length), sites(&path))
                }
                "path" => {
                    let (distances, previous) = proximity::dijkstra(i, p, &self.neighbors);
                    let mut path = vec![j];
                    while *path.last().unwrap() != i { path.push(previous[*path.last().unwrap()].unwrap()); }
                    path.reverse();
                    let stretch = if i == j { "-".into() } else { real(distances[j] / (d2(p[i], p[j]) as f64).sqrt()) };
                    format!("length {} stretch {} hops {} sites {}", real(distances[j]), stretch, path.len() - 1, sites(&path))
                }
                _ => {
                    if i == j { "error same_site".into() }
                    else {
                        let edge = (i.min(j), i.max(j));
                        if self.edges.binary_search(&edge).is_ok() {
                            let yes = |value| if value { "yes" } else { "no" };
                            format!("delaunay len2 {} gabriel {} rng {} mst {} dual {}", d2(p[i], p[j]), yes(self.gabriel.contains(&edge)),
                                yes(self.relative.contains(&edge)), yes(self.mst_set.contains(&edge)), self.dual(edge))
                        } else {
                            let crossing: Vec<String> = self.edges.iter().filter(|&&(u, v)|
                                orient(p[i], p[j], p[u]) * orient(p[i], p[j], p[v]) < 0 && orient(p[u], p[v], p[i]) * orient(p[u], p[v], p[j]) < 0)
                                .map(|&(u, v)| format!("{}-{}", u + 1, v + 1)).collect();
                            if crossing.is_empty() { "missing crossings 0".into() } else { format!("missing crossings {} {}", crossing.len(), crossing.join(" ")) }
                        }
                    }
                }
            }
        };
        format!("{} {}", text, answer)
    }
}

fn main() -> io::Result<()> {
    let input = read()?;
    let points = &input.points;
    let n = points.len();
    let (mut mesh, initial) = Triangulation::new(points);
    let insertions: Vec<_> = (3..n).map(|s| mesh.insert(s, points)).collect();
    let triangles = mesh.triangles();
    let t = triangles.len();
    let edges: Vec<(usize, usize)> = mesh.directed.keys().map(|&(i, j)| (i.min(j), i.max(j))).collect::<BTreeSet<_>>().into_iter().collect();
    let hull = mesh.hull();
    let neighbors: Vec<Vec<usize>> = (0..n).map(|s| voronoi::neighbors(s, &mesh, &hull)).collect();
    let mut numbers = BTreeMap::new();
    for (k, &[a, b, c]) in triangles.iter().enumerate() {
        for edge in [(a, b), (b, c), (c, a)] { numbers.insert(edge, k); }
    }
    let centers: Vec<_> = triangles.iter().map(|&[a, b, c]| predicates::center(points[a], points[b], points[c])).collect();
    let radius2: Vec<f64> = triangles.iter().map(|&[a, b, c]| voronoi::radius2(points[a], points[b], points[c])).collect();
    let positions: Vec<&'static str> = centers.iter().map(|&c| voronoi::position(c, points, &hull)).collect();
    let gabriel = edges.iter().copied().filter(|&(i, j)| proximity::gabriel(i, j, points, &mesh)).collect();
    let relative = edges.iter().copied().filter(|&(i, j)| proximity::relative(i, j, points)).collect();
    let mst = proximity::kruskal(points, &edges);
    let mst_set = mst.iter().copied().collect();
    let nearest = proximity::nearest(points);
    let analysis = Analysis { input, mesh, triangles, numbers, edges, hull, neighbors, centers, radius2, positions, gabriel, relative, mst, mst_set, nearest };
    let a = &analysis;
    let points = &a.input.points;
    let edges = &a.edges;
    let hull = &a.hull;
    let h = hull.len();
    let mut sections: BTreeMap<&str, Vec<String>> = BTreeMap::new();
    let mut lines = vec![format!("lines {}", a.input.lines), format!("accepted {}", n), format!("rejected {}", a.input.rejected.len())];
    lines.extend(a.input.rejected.iter().cloned());
    sections.insert("input", lines);
    let mut kinds = Vec::new();
    let mut areas = Vec::new();
    let mut angles_min = Vec::new();
    let mut angles_max = Vec::new();
    for &[i, j, k] in &a.triangles {
        let area = orient(points[i], points[j], points[k]);
        areas.push(area);
        let vertices = [i, j, k];
        let dots: Vec<i64> = (0..3).map(|v| dot(points[vertices[v]], points[vertices[(v + 1) % 3]], points[vertices[(v + 2) % 3]])).collect();
        kinds.push(if dots.contains(&0) { "right" } else if dots.iter().any(|&d| d < 0) { "obtuse" } else { "acute" });
        let angles: Vec<f64> = dots.iter().map(|&d| (area as f64).atan2(d as f64) * 180.0 / std::f64::consts::PI).collect();
        angles_min.push(angles.iter().copied().fold(f64::INFINITY, f64::min));
        angles_max.push(angles.iter().copied().fold(f64::NEG_INFINITY, f64::max));
    }
    let maximum_flips = if insertions.is_empty() { "max_flips none".into() } else {
        let j = (0..insertions.len()).max_by_key(|&j| (insertions[j].flips, std::cmp::Reverse(j))).unwrap();
        format!("max_flips {} {}", j + 4, insertions[j].flips)
    };
    sections.insert("summary", vec![format!("sites {}", n), format!("triangles {}", t), format!("edges {}", edges.len()),
        format!("hull_vertices {}", h), format!("interior_sites {}", n - h), format!("euler {}", n as i64 - edges.len() as i64 + t as i64),
        format!("flips {}", insertions.iter().map(|r| r.flips).sum::<usize>()), format!("outside_insertions {}", insertions.iter().filter(|r| r.containing.is_none()).count()),
        maximum_flips, format!("acute {}", kinds.iter().filter(|&&s| s == "acute").count()), format!("right {}", kinds.iter().filter(|&&s| s == "right").count()),
        format!("obtuse {}", kinds.iter().filter(|&&s| s == "obtuse").count())]);
    let mut lines = vec![format!("init {}", sites(&initial))];
    for (j, r) in insertions.iter().enumerate() {
        let kind = if let Some(containing) = r.containing { format!("inside {}", sites(&containing)) } else { format!("outside {}", r.visible) };
        lines.push(format!("insert {} {} flips {} triangles {} hull {}", j + 4, kind, r.flips, r.triangles, r.hull));
    }
    sections.insert("insertions", lines);
    let mut lines = Vec::new();
    for (k, &[i, j, l]) in a.triangles.iter().enumerate() {
        let adjacent: Vec<String> = [(l, j), (i, l), (j, i)].iter().map(|edge| a.numbers.get(edge).map_or("-".into(), |k| (k + 1).to_string())).collect();
        lines.push(format!("tri {} {} area2 {} {} adj {}", k + 1, sites(&[i, j, l]), areas[k], kinds[k], adjacent.join(" ")));
    }
    sections.insert("triangles", lines);
    let mut lines = Vec::new();
    for &(i, j) in edges {
        let left = a.numbers.get(&(i, j));
        let right = a.numbers.get(&(j, i));
        lines.push(format!("edge {} {} {} len2 {} left {} right {}", i + 1, j + 1, if left.is_some() && right.is_some() { "inner" } else { "hull" }, d2(points[i], points[j]),
            left.map_or("-".into(), |k| (k + 1).to_string()), right.map_or("-".into(), |k| (k + 1).to_string())));
    }
    sections.insert("edges", lines);
    let perimeter: f64 = (0..h).map(|j| (d2(points[hull[j]], points[hull[(j + 1) % h]]) as f64).sqrt()).sum();
    let area2: i64 = (0..h).map(|j| {
        let p = points[hull[j]];
        let q = points[hull[(j + 1) % h]];
        p.0 * q.1 - q.0 * p.1
    }).sum();
    sections.insert("hull", vec![format!("hull_vertices {}", h), format!("order {}", sites(hull)), format!("perimeter {}", real(perimeter)), format!("area2 {}", area2)]);
    let mut remaining: Vec<usize> = (0..n).collect();
    let mut layers = Vec::new();
    let mut depths = vec![0; n];
    while !remaining.is_empty() {
        let layer = convex_hull(points, &remaining);
        for &s in &layer { depths[s] = layers.len() + 1; }
        let selected: BTreeSet<usize> = layer.iter().copied().collect();
        remaining.retain(|s| !selected.contains(s));
        layers.push(layer);
    }
    let mut lines = vec![format!("layers {}", layers.len())];
    for (j, layer) in layers.iter().enumerate() { lines.push(format!("layer {} size {} sites {}", j + 1, layer.len(), sites(layer))); }
    sections.insert("convex_layers", lines);
    let min_angle = (0..t).min_by(|&i, &j| angles_min[i].partial_cmp(&angles_min[j]).unwrap().then(i.cmp(&j))).unwrap();
    let max_angle = (0..t).min_by(|&i, &j| angles_max[j].partial_cmp(&angles_max[i]).unwrap().then(i.cmp(&j))).unwrap();
    let mut lines = vec![format!("min_angle {} tri {}", real(angles_min[min_angle]), min_angle + 1), format!("max_angle {} tri {}", real(angles_max[max_angle]), max_angle + 1),
        format!("mean_min_angle {}", real(angles_min.iter().sum::<f64>() / t as f64))];
    for bin in 0..6 { lines.push(format!("bin {} {} {}", bin * 10, (bin + 1) * 10, angles_min.iter().filter(|&&v| v >= (bin * 10) as f64 && v < ((bin + 1) * 10) as f64).count())); }
    sections.insert("quality", lines);
    let mut lines: Vec<String> = ["inside", "on", "outside"].iter().map(|kind| format!("{} {}", kind, a.positions.iter().filter(|&&p| p == *kind).count())).collect();
    for k in 0..t {
        let (x, y, d) = a.centers[k];
        lines.push(format!("v {} {} {} r {} {}", k + 1, fraction(x, d), fraction(y, d), real(a.radius2[k].sqrt()), a.positions[k]));
    }
    sections.insert("vertices", lines);
    let mut lines = vec![format!("segments {}", edges.len() - h), format!("rays {}", h)];
    for &edge in edges { lines.push(format!("ve {} {} {}", edge.0 + 1, edge.1 + 1, a.dual(edge))); }
    sections.insert("voronoi_edges", lines);
    let mut cell_vertices = Vec::new();
    let mut cell_areas = Vec::new();
    let mut clipped = Vec::new();
    for s in 0..n {
        let vertices: Vec<usize> = a.neighbors[s].iter().filter_map(|&v| a.numbers.get(&(s, v)).copied()).collect();
        cell_areas.push(if hull.contains(&s) { None } else { Some(voronoi::bounded_area(points[s], &vertices.iter().map(|&k| a.centers[k]).collect::<Vec<_>>())) });
        cell_vertices.push(vertices);
        clipped.push(voronoi::clipped_area(s, &a.neighbors[s], points));
    }
    let mut lines = vec![format!("bounded {}", n - h), format!("unbounded {}", h), format!("total_area {}", real(cell_areas.iter().filter_map(|&v| v).sum())),
        format!("clip_total {}", real(clipped.iter().sum()))];
    let largest = (0..n).filter(|&s| cell_areas[s].is_some()).min_by(|&i, &j| cell_areas[j].unwrap().partial_cmp(&cell_areas[i].unwrap()).unwrap().then(i.cmp(&j)));
    lines.push(largest.map_or("largest none".into(), |s| format!("largest {} area {}", s + 1, real(cell_areas[s].unwrap()))));
    for s in 0..n {
        if let Some(area) = cell_areas[s] {
            lines.push(format!("cell {} bounded {} area {} clip {} vertices {}", s + 1, cell_vertices[s].len(), real(area), real(clipped[s]), sites(&cell_vertices[s])));
        } else {
            let j = hull.iter().position(|&v| v == s).unwrap();
            let incoming = voronoi::outward(points[s], points[hull[(j + 1) % h]]);
            let outgoing = voronoi::outward(points[hull[(j + h - 1) % h]], points[s]);
            lines.push(format!("cell {} unbounded {} clip {} from {} {} vertices {} to {} {}", s + 1, cell_vertices[s].len(), real(clipped[s]), incoming.0, incoming.1,
                sites(&cell_vertices[s]), outgoing.0, outgoing.1));
        }
    }
    sections.insert("cells", lines);
    let nn_edges: Vec<(usize, usize)> = (0..n).map(|s| (s.min(a.nearest[s]), s.max(a.nearest[s]))).collect::<BTreeSet<_>>().into_iter().collect();
    let mutual = (0..n).filter(|&s| s < a.nearest[s] && a.nearest[a.nearest[s]] == s).count();
    let closest = *edges.iter().min_by_key(|&&(i, j)| (d2(points[i], points[j]), i, j)).unwrap();
    let mut lines = vec![format!("mutual_pairs {}", mutual), format!("closest_pair {} {} d2 {}", closest.0 + 1, closest.1 + 1, d2(points[closest.0], points[closest.1]))];
    for s in 0..n { lines.push(format!("nn {} {} d2 {} {}", s + 1, a.nearest[s] + 1, d2(points[s], points[a.nearest[s]]), if a.nearest[a.nearest[s]] == s { "mutual" } else { "-" })); }
    sections.insert("nearest", lines);
    let components = proximity::components(n, &nn_edges);
    let mut component_of = vec![0; n];
    let mut lines = vec![format!("components {}", components.len())];
    for (j, component) in components.iter().enumerate() {
        for &s in component { component_of[s] = j + 1; }
        let s = *component.iter().find(|&&s| s < a.nearest[s] && a.nearest[a.nearest[s]] == s).unwrap();
        lines.push(format!("component {} size {} pair {} {} sites {}", j + 1, component.len(), s + 1, a.nearest[s] + 1, sites(component)));
    }
    sections.insert("components", lines);
    let longest = *a.mst.last().unwrap();
    let mut lines = vec![format!("edges {}", n - 1), format!("total_length {}", real(a.mst.iter().map(|&(i, j)| (d2(points[i], points[j]) as f64).sqrt()).sum())),
        format!("longest {} {} len2 {}", longest.0 + 1, longest.1 + 1, d2(points[longest.0], points[longest.1]))];
    for &(i, j) in &a.mst { lines.push(format!("mst {} {} len2 {}", i + 1, j + 1, d2(points[i], points[j]))); }
    sections.insert("mst", lines);
    let mut lines = vec![format!("delaunay {}", edges.len()), format!("gabriel {}", a.gabriel.len()), format!("rng {}", a.relative.len()), format!("mst {}", n - 1), format!("nn {}", nn_edges.len())];
    for &(i, j) in a.relative.difference(&a.mst_set) { lines.push(format!("rng_extra {} {} len2 {}", i + 1, j + 1, d2(points[i], points[j]))); }
    sections.insert("proximity", lines);
    let mut degrees = BTreeMap::new();
    for neighbors in &a.neighbors { *degrees.entry(neighbors.len()).or_insert(0) += 1; }
    let mut lines = vec![format!("min {}", degrees.keys().next().unwrap()), format!("max {}", degrees.keys().last().unwrap())];
    lines.extend(degrees.iter().map(|(d, c)| format!("degree {} count {}", d, c)));
    sections.insert("degrees", lines);
    let candidates: Vec<usize> = (0..t).filter(|&k| a.positions[k] == "inside").collect();
    let empty_circle = candidates.iter().copied().min_by(|&i, &j| a.radius2[j].partial_cmp(&a.radius2[i]).unwrap().then(i.cmp(&j)));
    let mut lines = vec![format!("candidates {}", candidates.len())];
    if let Some(k) = empty_circle {
        let (x, y, d) = a.centers[k];
        lines.extend([format!("vertex {}", k + 1), format!("center {} {}", fraction(x, d), fraction(y, d)), format!("radius {}", real(a.radius2[k].sqrt())), format!("sites {}", sites(&a.triangles[k]))]);
    } else { lines.push("none".into()); }
    sections.insert("empty_circle", lines);
    let pairs: Vec<(usize, usize)> = (0..n).flat_map(|i| (i + 1..n).map(move |j| (i, j))).collect();
    let diameter = *pairs.iter().min_by_key(|&&(i, j)| (std::cmp::Reverse(d2(points[i], points[j])), i, j)).unwrap();
    let widths: Vec<f64> = (0..h).map(|j| {
        let (u, v) = (hull[j], hull[(j + 1) % h]);
        let maximum = hull.iter().map(|&s| orient(points[u], points[v], points[s])).max().unwrap();
        maximum as f64 / (d2(points[u], points[v]) as f64).sqrt()
    }).collect();
    let width = (0..h).min_by(|&i, &j| widths[i].partial_cmp(&widths[j]).unwrap().then(i.cmp(&j))).unwrap();
    let circle = enclosing(points, hull);
    let ((x, y, d), r2) = circle.geometry(points);
    let boundary: Vec<usize> = (0..n).filter(|&s| circle.relation(s, points) == 0).collect();
    sections.insert("extent", vec![format!("diameter {} {} d2 {}", diameter.0 + 1, diameter.1 + 1, d2(points[diameter.0], points[diameter.1])),
        format!("width {} edge {} {}", real(widths[width]), hull[width] + 1, hull[(width + 1) % h] + 1),
        format!("enclosing_center {} {}", fraction(x, d), fraction(y, d)), format!("enclosing_radius {}", real(r2.sqrt())), format!("enclosing_sites {}", sites(&boundary))]);
    let distances: Vec<Vec<f64>> = (0..n).map(|s| proximity::dijkstra(s, points, &a.neighbors).0).collect();
    let stretches: Vec<f64> = pairs.iter().map(|&(i, j)| distances[i][j] / (d2(points[i], points[j]) as f64).sqrt()).collect();
    let maximum = (0..pairs.len()).min_by(|&i, &j| stretches[j].partial_cmp(&stretches[i]).unwrap().then(i.cmp(&j))).unwrap();
    let (i, j) = pairs[maximum];
    sections.insert("spanner", vec![format!("pairs {}", pairs.len()), format!("max_stretch {} pair {} {} length {} distance {}", real(stretches[maximum]), i + 1, j + 1,
        real(distances[i][j]), real((d2(points[i], points[j]) as f64).sqrt())), format!("mean_stretch {}", real(stretches.iter().sum::<f64>() / pairs.len() as f64))]);
    let mut lines = Vec::new();
    for &alpha in &a.input.alpha {
        let selected: BTreeSet<usize> = (0..t).filter(|&k| a.radius2[k] <= alpha as f64).collect();
        let mut counts: BTreeMap<(usize, usize), usize> = BTreeMap::new();
        for &k in &selected {
            let [i, j, l] = a.triangles[k];
            for (u, v) in [(i, j), (j, l), (l, i)] { *counts.entry((u.min(v), u.max(v))).or_insert(0) += 1; }
        }
        for &(i, j) in &a.gabriel {
            if d2(points[i], points[j]) <= 4 * alpha { counts.entry((i, j)).or_insert(0); }
        }
        let edges: Vec<(usize, usize)> = counts.keys().copied().collect();
        let components = proximity::components(n, &edges).len();
        let incident: BTreeSet<usize> = edges.iter().flat_map(|&(i, j)| [i, j]).collect();
        lines.push(format!("alpha {} triangles {} edges {} boundary {} dangling {} isolated {} components {} holes {} area2 {}", alpha, selected.len(), edges.len(),
            counts.values().filter(|&&c| c == 1).count(), counts.values().filter(|&&c| c == 0).count(), n - incident.len(), components,
            components as i64 - (n as i64 - edges.len() as i64 + selected.len() as i64), selected.iter().map(|&k| areas[k]).sum::<i64>()));
    }
    sections.insert("alpha", lines);
    let mut lines = Vec::new();
    for s in 0..n {
        let degree = |edges: &BTreeSet<(usize, usize)>| edges.iter().filter(|&&(i, j)| i == s || j == s).count();
        lines.push(format!("site {} {} {} {} dt {} gg {} rng {} mst {} nn {} comp {} depth {}", s + 1, points[s].0, points[s].1,
            if hull.contains(&s) { "hull" } else { "inner" }, a.neighbors[s].len(), degree(&a.gabriel), degree(&a.relative), degree(&a.mst_set), a.nearest[s] + 1, component_of[s], depths[s]));
    }
    sections.insert("sites", lines);
    sections.insert("queries", a.input.queries.iter().map(|text| a.query(text)).collect());
    let mut canvas = plot::Canvas::new(a.input.width, a.input.height);
    for layer in &a.input.layers {
        match layer.as_str() {
            "edges" => for &(i, j) in edges { canvas.line(points[i], points[j], '.'); },
            "mst" => for &(i, j) in &a.mst { canvas.line(points[i], points[j], '*'); },
            "hull" => for j in 0..h { canvas.line(points[hull[j]], points[hull[(j + 1) % h]], '#'); },
            "sites" => for &(x, y) in points { let position = canvas.position((x, y, 1)); canvas.set(position, 'o'); },
            "circle" => if let Some(k) = empty_circle { let position = canvas.position(a.centers[k]); canvas.set(position, '@'); },
            _ => unreachable!(),
        }
    }
    sections.insert("delaunay_plot", canvas.frame());
    let mut canvas = plot::Canvas::new(a.input.width, a.input.height);
    canvas.voronoi(points);
    for &(x, y) in points { let position = canvas.position((x, y, 1)); canvas.set(position, 'o'); }
    sections.insert("voronoi_plot", canvas.frame());
    let mut outputs = vec![Vec::<String>::new(); 4];
    for section in &a.input.sections {
        let index = if ["input", "summary", "insertions", "triangles", "edges", "hull", "convex_layers", "quality"].contains(&section.as_str()) { 0 }
            else if ["vertices", "voronoi_edges", "cells"].contains(&section.as_str()) { 1 }
            else if ["delaunay_plot", "voronoi_plot"].contains(&section.as_str()) { 3 } else { 2 };
        outputs[index].push(format!("[{}]", section));
        outputs[index].extend(sections[section.as_str()].iter().cloned());
    }
    fs::create_dir_all("output")?;
    for (index, name) in ["triangulation.txt", "voronoi.txt", "derived.txt", "plot.txt"].iter().enumerate() {
        let content = if outputs[index].is_empty() { String::new() } else { outputs[index].join("\n") + "\n" };
        fs::write(format!("output/{}", name), content)?;
    }
    Ok(())
}
