mod dataset;
mod grid_index;
mod dbscan;
mod optics;
mod report;

use std::collections::{BTreeMap, BTreeSet};
use dataset::{Point, Params};
use grid_index::{distance, Grid};
use optics::{Ordering, INF};
use report::{ari, fraction, framed, root, write_lines};

fn integers(values: impl IntoIterator<Item = i64>) -> String {
    values.into_iter().map(|v| v.to_string()).collect::<Vec<_>>().join(" ")
}

fn label_char(label: i32) -> char {
    match label {
        -1 => '.',
        0..=25 => char::from(b'A' + label as u8),
        26..=51 => char::from(b'a' + (label - 26) as u8),
        _ => '#',
    }
}

fn integer_root(value: i64) -> i64 {
    let mut low = 0;
    let mut high = value + 1;
    while low + 1 < high {
        let mid = (low + high) / 2;
        if mid <= value / mid { low = mid; } else { high = mid; }
    }
    low
}

fn optional_value(value: i64) -> String {
    if value == INF { "-".to_owned() } else { value.to_string() }
}

fn optional_root(value: i64) -> String {
    if value == INF { "-".to_owned() } else { root(value) }
}

fn optional_index(value: Option<usize>) -> String {
    value.map(|v| v.to_string()).unwrap_or_else(|| "-".to_owned())
}

fn check_text(passed: bool) -> &'static str { if passed { "ok" } else { "mismatch" } }
fn condition_text(passed: bool) -> &'static str { if passed { "ok" } else { "fail" } }

fn join_parts(parts: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for (i, part) in parts.into_iter().enumerate() {
        if i > 0 { lines.push(String::new()); }
        lines.extend(part);
    }
    lines
}

struct Curve {
    order: Vec<usize>,
    values: Vec<i64>,
    knee: usize,
    cross: i64,
    eps: i64,
}

impl Curve {
    fn new(values: &[i64]) -> Self {
        let n = values.len();
        let mut order: Vec<usize> = (0..n).collect();
        order.sort_by_key(|&i| (std::cmp::Reverse(values[i]), i));
        let values: Vec<i64> = order.iter().map(|&i| values[i]).collect();
        let first = values[0];
        let last = values[n - 1];
        let crosses: Vec<i64> = values.iter().enumerate().map(|(r, &v)| {
            ((n - 1) as i64 * (v - first) - (last - first) * r as i64).abs()
        }).collect();
        let cross = *crosses.iter().max().unwrap();
        let knee = crosses.iter().position(|&v| v == cross).unwrap();
        let floor = integer_root(values[knee]);
        let eps = (floor + i64::from(floor * floor < values[knee])).max(1);
        Self { order, values, knee, cross, eps }
    }
}

struct Setting {
    name: String,
    kind: &'static str,
    radius: i64,
    labels: Vec<i32>,
    core: Vec<bool>,
    members: Vec<Vec<usize>>,
    noise: usize,
    core_count: usize,
}

impl Setting {
    fn new(name: String, kind: &'static str, radius: i64, labels: Vec<i32>, core: Vec<bool>) -> Self {
        let count = (labels.iter().max().unwrap() + 1) as usize;
        let mut members = vec![Vec::new(); count];
        for (i, &label) in labels.iter().enumerate() {
            if label >= 0 { members[label as usize].push(i); }
        }
        let noise = labels.iter().filter(|&&label| label == -1).count();
        let core_count = labels.iter().zip(&core).filter(|(label, core)| **label >= 0 && **core).count();
        Self { name, kind, radius, labels, core, members, noise, core_count }
    }
}

fn extract(order: &Ordering, radius: i64) -> (Vec<i32>, Vec<bool>) {
    let limit = radius * radius;
    let mut labels = vec![-1; order.points.len()];
    let mut cluster = -1;
    for &i in &order.points {
        if order.reach[i] > limit {
            if order.core[i] <= limit {
                cluster += 1;
                labels[i] = cluster;
            }
        } else {
            labels[i] = cluster;
        }
    }
    (labels, order.core.iter().map(|&d| d <= limit).collect())
}

#[derive(Clone)]
struct DownArea {
    start: usize,
    end: usize,
    high: i64,
}

struct Xi {
    reach: Vec<i64>,
    areas: Vec<(&'static str, usize, usize)>,
    clusters: Vec<(usize, usize)>,
    labels: Vec<i32>,
    cluster_labels: Vec<Option<usize>>,
    parents: Vec<Option<usize>>,
}

impl Xi {
    fn new(reach: Vec<i64>, p: &Params) -> Self {
        let n = reach.len() - 1;
        let alpha = (p.v - p.u) * (p.v - p.u);
        let beta = p.v * p.v;
        let xle = |a: i64, b: i64| b == INF || (a != INF && beta * a <= alpha * b);
        let steep_up: Vec<bool> = (0..n).map(|i| {
            (reach[i] != INF || reach[i + 1] != INF) && xle(reach[i], reach[i + 1])
        }).collect();
        let steep_down: Vec<bool> = (0..n).map(|i| {
            (reach[i] != INF || reach[i + 1] != INF) && xle(reach[i + 1], reach[i])
        }).collect();
        let up: Vec<bool> = (0..n).map(|i| reach[i] < reach[i + 1]).collect();
        let down: Vec<bool> = (0..n).map(|i| reach[i] > reach[i + 1]).collect();
        let region_end = |start: usize, steep: &[bool], reverse: &[bool]| {
            let mut end = start;
            let mut flat = 0;
            for i in start..n {
                if steep[i] {
                    end = i;
                    flat = 0;
                } else if reverse[i] {
                    break;
                } else {
                    flat += 1;
                    if flat > p.min_pts { break; }
                }
            }
            end
        };
        let mut areas = Vec::new();
        let mut clusters = Vec::new();
        let mut down_areas: Vec<DownArea> = Vec::new();
        let mut index = 0;
        let mut mib = 0i64;
        for start in 0..n {
            if start < index || !(steep_up[start] || steep_down[start]) { continue; }
            mib = mib.max(*reach[index..=start].iter().max().unwrap());
            if mib == INF {
                down_areas.clear();
            } else {
                down_areas.retain(|area| xle(mib, reach[area.start]));
                for area in &mut down_areas { area.high = area.high.max(mib); }
            }
            if steep_down[start] {
                let end = region_end(start, &steep_down, &up);
                areas.push(("down", start, end));
                down_areas.push(DownArea { start, end, high: 0 });
                index = end + 1;
                mib = reach[index];
            } else {
                let end = region_end(start, &steep_up, &down);
                areas.push(("up", start, end));
                index = end + 1;
                mib = reach[index];
                let mut candidates = Vec::new();
                for area in &down_areas {
                    let mut cs = area.start;
                    let mut ce = end;
                    if !xle(area.high, reach[ce + 1]) { continue; }
                    let wall = reach[area.start];
                    if xle(reach[ce + 1], wall) {
                        while cs < area.end && reach[cs + 1] > reach[ce + 1] { cs += 1; }
                    } else if xle(wall, reach[ce + 1]) {
                        while ce > start && reach[ce - 1] > wall { ce -= 1; }
                    }
                    if ce + 1 >= cs + p.min_size && cs <= area.end && ce >= start {
                        candidates.push((cs, ce));
                    }
                }
                clusters.extend(candidates.into_iter().rev());
            }
        }
        let mut labels = vec![-1; n];
        let mut cluster_labels = Vec::new();
        let mut next_label = 0;
        for &(start, end) in &clusters {
            if labels[start..=end].iter().all(|&label| label == -1) {
                labels[start..=end].fill(next_label);
                cluster_labels.push(Some(next_label as usize));
                next_label += 1;
            } else {
                cluster_labels.push(None);
            }
        }
        let parents = clusters.iter().enumerate().map(|(j, &(start, end))| {
            let size = end - start + 1;
            (0..clusters.len()).filter(|&i| {
                let (a, b) = clusters[i];
                let larger = b - a + 1;
                i != j && a <= start && end <= b && (larger > size || (larger == size && i > j))
            }).min_by_key(|&i| (clusters[i].1 - clusters[i].0 + 1, i))
        }).collect();
        Self { reach, areas, clusters, labels, cluster_labels, parents }
    }
}

fn hull(points: &[Point], members: &[usize]) -> Vec<usize> {
    let mut ordered = members.to_vec();
    ordered.sort_by_key(|&i| (points[i].x, points[i].y));
    if ordered.len() <= 2 { return ordered; }
    let half = |ids: Vec<usize>| {
        let mut chain: Vec<usize> = Vec::new();
        for i in ids {
            while chain.len() >= 2 {
                let o = &points[chain[chain.len() - 2]];
                let a = &points[*chain.last().unwrap()];
                let b = &points[i];
                let turn = (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
                if turn > 0 { break; }
                chain.pop();
            }
            chain.push(i);
        }
        chain.pop();
        chain
    };
    let mut vertices = half(ordered.clone());
    vertices.extend(half(ordered.into_iter().rev().collect()));
    vertices
}

fn cluster_lines(points: &[Point], setting: &Setting, label: usize) -> Vec<String> {
    let members = &setting.members[label];
    let size = members.len() as i64;
    let core = members.iter().filter(|&&i| setting.core[i]).count();
    let sx: i64 = members.iter().map(|&i| points[i].x).sum();
    let sy: i64 = members.iter().map(|&i| points[i].y).sum();
    let medoid = *members.iter().min_by_key(|&&i| {
        let dx = size * points[i].x - sx;
        let dy = size * points[i].y - sy;
        (dx * dx + dy * dy, points[i].id)
    }).unwrap();
    let xmin = members.iter().map(|&i| points[i].x).min().unwrap();
    let xmax = members.iter().map(|&i| points[i].x).max().unwrap();
    let ymin = members.iter().map(|&i| points[i].y).min().unwrap();
    let ymax = members.iter().map(|&i| points[i].y).max().unwrap();
    let area = (xmax - xmin + 1) * (ymax - ymin + 1);
    let vertices = hull(points, members);
    let mut doubled_area = 0i64;
    let mut diameter = 0i64;
    for (i, &a) in vertices.iter().enumerate() {
        let b = vertices[(i + 1) % vertices.len()];
        doubled_area += points[a].x * points[b].y - points[b].x * points[a].y;
        for &b in &vertices { diameter = diameter.max(distance(&points[a], &points[b])); }
    }
    doubled_area = doubled_area.abs();
    vec![
        format!(concat!("cluster {} {} size {} core {} border {} ",
            "centroid {} {} medoid {}"), label, label_char(label as i32), size, core, members.len() - core,
            fraction(sx, size), fraction(sy, size), points[medoid].id),
        format!("  bbox {xmin} {ymin} {xmax} {ymax} area {area} density {}", fraction(size, area)),
        format!("  hull {} hull_area {}.{} diameter_sq {diameter} diameter {}",
            vertices.len(), doubled_area / 2, if doubled_area % 2 == 0 { 0 } else { 5 }, root(diameter)),
    ]
}

fn adjusted_rand(a: &[i32], b: &[i32]) -> (i64, i64) {
    let mut pairs = BTreeMap::new();
    let mut first = BTreeMap::new();
    let mut second = BTreeMap::new();
    for (&a, &b) in a.iter().zip(b) {
        *pairs.entry((a, b)).or_insert(0i64) += 1;
        *first.entry(a).or_insert(0i64) += 1;
        *second.entry(b).or_insert(0i64) += 1;
    }
    let c2 = |n: i64| n * (n - 1) / 2;
    let z = c2(a.len() as i64);
    let s: i64 = pairs.values().map(|&n| c2(n)).sum();
    let a: i64 = first.values().map(|&n| c2(n)).sum();
    let b: i64 = second.values().map(|&n| c2(n)).sum();
    let denominator = z * (a + b) - 2 * a * b;
    if denominator == 0 { (1, 1) } else { (2 * (z * s - a * b), denominator) }
}

struct Study {
    points: Vec<Point>,
    p: Params,
    curves: Vec<Curve>,
    kdist: Vec<i64>,
    grids: BTreeMap<i64, Grid>,
    settings: Vec<Setting>,
    knee: usize,
    order: Ordering,
    xi: Xi,
    map_cells: Vec<(usize, usize)>,
}

impl Study {
    fn new(points: Vec<Point>, p: Params) -> Self {
        let rows: Vec<Vec<i64>> = points.iter().enumerate().map(|(i, point)| {
            let mut row: Vec<i64> = points.iter().enumerate().filter(|(j, _)| *j != i)
                .map(|(_, other)| distance(point, other)).collect();
            row.sort_unstable();
            row.truncate(2 * p.min_pts);
            row
        }).collect();
        let curves: Vec<Curve> = (0..2 * p.min_pts).map(|k| {
            Curve::new(&rows.iter().map(|row| row[k]).collect::<Vec<_>>())
        }).collect();
        let curve = &curves[p.min_pts - 2];
        let kdist = rows.iter().map(|row| row[p.min_pts - 2]).collect();
        let radii: BTreeSet<i64> = p.eps.iter().copied().chain([curve.eps, p.max_eps]).collect();
        let grids: BTreeMap<i64, Grid> = radii.into_iter().map(|e| (e, Grid::new(&points, e))).collect();
        let mut settings = Vec::new();
        for &e in &p.eps {
            let (labels, core) = dbscan::cluster(&grids[&e].neighborhoods, p.min_pts);
            settings.push(Setting::new(format!("db{e}"), "dbscan", e, labels, core));
        }
        let knee = settings.len();
        let e = curve.eps;
        let (labels, core) = dbscan::cluster(&grids[&e].neighborhoods, p.min_pts);
        settings.push(Setting::new(format!("knee{e}"), "dbscan", e, labels, core));
        let order = optics::order(&points, &grids[&p.max_eps].neighborhoods, p.min_pts);
        for &e in &p.extract {
            let (labels, core) = extract(&order, e);
            settings.push(Setting::new(format!("op{e}"), "extract", e, labels, core));
        }
        let reach = order.points.iter().map(|&i| order.reach[i]).chain([INF]).collect();
        let xi = Xi::new(reach, &p);
        let mut labels = vec![-1; points.len()];
        for (position, &i) in order.points.iter().enumerate() { labels[i] = xi.labels[position]; }
        let core = order.core.iter().map(|&value| value != INF).collect();
        settings.push(Setting::new("xi".to_owned(), "xi", p.max_eps, labels, core));
        let xmin = points.iter().map(|p| p.x).min().unwrap();
        let xmax = points.iter().map(|p| p.x).max().unwrap();
        let ymin = points.iter().map(|p| p.y).min().unwrap();
        let ymax = points.iter().map(|p| p.y).max().unwrap();
        let map_cells = points.iter().map(|point| (
            ((point.x - xmin) * p.width as i64 / (xmax - xmin + 1)) as usize,
            ((ymax - point.y) * p.height as i64 / (ymax - ymin + 1)) as usize,
        )).collect();
        Self { points, p, curves, kdist, grids, settings, knee, order, xi, map_cells }
    }

    fn curve(&self) -> &Curve { &self.curves[self.p.min_pts - 2] }
    fn knee(&self) -> &Setting { &self.settings[self.knee] }
    fn db_settings(&self) -> Vec<&Setting> { self.settings.iter().filter(|s| s.kind == "dbscan").collect() }

    fn labels_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("id,{}", self.settings.iter().map(|s| s.name.as_str()).collect::<Vec<_>>().join(","))];
        for (i, point) in self.points.iter().enumerate() {
            lines.push(format!("{},{}", point.id, self.settings.iter().map(|s| s.labels[i].to_string()).collect::<Vec<_>>().join(",")));
        }
        lines
    }

    fn optics_lines(&self) -> Vec<String> {
        let mut lines = vec!["order,id,core_sq,reach_sq,reach,predecessor".to_owned()];
        for (position, &i) in self.order.points.iter().enumerate() {
            let predecessor = self.order.predecessor[i].map(|j| self.points[j].id.to_string()).unwrap_or_else(|| "-".to_owned());
            lines.push(format!("{},{},{},{},{},{predecessor}", position + 1, self.points[i].id,
                optional_value(self.order.core[i]), optional_value(self.order.reach[i]), optional_root(self.order.reach[i])));
        }
        lines
    }

    fn kdist_lines(&self) -> Vec<String> {
        let curve = self.curve();
        let n = self.points.len();
        let mut lines = vec![format!("k_distance k {} points {n}", self.p.min_pts - 1), "rank id kdist_sq kdist".to_owned()];
        for (rank, (&i, &value)) in curve.order.iter().zip(&curve.values).enumerate() {
            lines.push(format!("{} {} {value} {}", rank + 1, self.points[i].id, root(value)));
        }
        let value = curve.values[curve.knee];
        lines.extend([
            String::new(),
            format!("knee rank {} id {} kdist_sq {value} kdist {} cross {}", curve.knee + 1,
                self.points[curve.order[curve.knee]].id, root(value), curve.cross),
            format!("suggested_eps {}", curve.eps), String::new(), "knee_table".to_owned(),
        ]);
        for (j, row) in self.curves.iter().enumerate() {
            lines.push(format!("k {} rank {} id {} kdist_sq {} eps {}", j + 1, row.knee + 1,
                self.points[row.order[row.knee]].id, row.values[row.knee], row.eps));
        }
        lines.extend([String::new(), "core_check".to_owned()]);
        for setting in self.db_settings() {
            let count = self.kdist.iter().filter(|&&d| d <= setting.radius * setting.radius).count();
            let grid_count = setting.core.iter().filter(|&&c| c).count();
            lines.push(format!("eps {} core {count} non_core {} grid_core {grid_count} {}",
                setting.radius, n - count, check_text(count == grid_count)));
        }
        let defined: Vec<usize> = (0..n).filter(|&i| self.order.core[i] != INF).collect();
        let consistent = defined.iter().all(|&i| self.order.core[i] == self.kdist[i]);
        lines.push(format!("optics max_eps {} core {} {}", self.p.max_eps, defined.len(), check_text(consistent)));
        lines
    }

    fn grid_lines(&self) -> Vec<String> {
        let mut lines = vec!["grid".to_owned()];
        for grid in self.grids.values() {
            let (x, y, count) = grid.busiest;
            lines.push(format!(concat!("eps {} cells {} busiest {} {} {} candidates {} ",
                "pairs {} brute_pairs {} {}"), grid.radius, grid.cells.len(), x, y, count,
                grid.candidates, grid.pairs, grid.brute_pairs, check_text(grid.consistent)));
            lines.push(format!("  occupancy {}", grid.occupancy.iter()
                .map(|(size, count)| format!("{size}:{count}")).collect::<Vec<_>>().join(" ")));
        }
        lines
    }

    fn setting_lines(&self, setting: &Setting) -> Vec<String> {
        let border = self.points.len() - setting.noise - setting.core_count;
        let mut lines = vec![format!("setting {} eps {} clusters {} noise {} core {} border {border}",
            setting.name, setting.radius, setting.members.len(), setting.noise, setting.core_count)];
        for label in 0..setting.members.len() { lines.extend(cluster_lines(&self.points, setting, label)); }
        if setting.kind != "dbscan" { return lines; }
        let mut linked = true;
        let mut supported = true;
        let mut separated = true;
        let mut isolated = 0;
        let mut ambiguous = Vec::new();
        for (i, neighbors) in self.grids[&setting.radius].neighborhoods.iter().enumerate() {
            let label = setting.labels[i];
            let core_labels: BTreeSet<i32> = neighbors.iter().filter(|&&j| setting.core[j])
                .map(|&j| setting.labels[j]).collect();
            if setting.core[i] {
                linked &= core_labels.iter().all(|&other| other == label);
            } else if label >= 0 {
                supported &= core_labels.contains(&label);
                let others: Vec<i64> = core_labels.iter().filter(|&&other| other != label).map(|&v| v as i64).collect();
                if !others.is_empty() {
                    ambiguous.push(format!("  {} cluster {label} also {}", self.points[i].id, integers(others)));
                }
            } else {
                separated &= core_labels.is_empty();
                if neighbors.len() == 1 { isolated += 1; }
            }
        }
        lines.extend([
            format!("check {} {} {}", condition_text(linked), condition_text(supported), condition_text(separated)),
            format!("isolated {isolated}"), format!("ambiguous {}", ambiguous.len()),
        ]);
        lines.extend(ambiguous);
        lines
    }

    fn hierarchy_lines(&self) -> Vec<String> {
        let mut ordered = self.db_settings();
        ordered.sort_by_key(|s| s.radius);
        let mut lines = vec!["hierarchy".to_owned()];
        for pair in ordered.windows(2) {
            let (smaller, larger) = (pair[0], pair[1]);
            lines.push(format!("{} -> {}", smaller.name, larger.name));
            let mut sources = vec![Vec::new(); larger.members.len()];
            for (label, members) in smaller.members.iter().enumerate() {
                let first = *members.iter().find(|&&i| smaller.core[i]).unwrap();
                sources[larger.labels[first] as usize].push(label as i64);
            }
            for (label, source) in sources.into_iter().enumerate() {
                lines.push(format!("  {label} <- {}", if source.is_empty() { "-".to_owned() } else { integers(source) }));
            }
        }
        lines
    }

    fn comparison_lines(&self) -> Vec<String> {
        let mut lines = vec!["optics_vs_dbscan".to_owned()];
        for extracted in self.settings.iter().filter(|s| s.kind == "extract") {
            let reference = self.settings.iter().find(|s| s.kind == "dbscan" && s.radius == extracted.radius);
            let Some(reference) = reference else { continue; };
            let pairs: BTreeSet<(i32, i32)> = extracted.labels.iter().zip(&reference.labels).zip(&extracted.core)
                .filter(|(_, core)| **core).map(|((&a, &b), _)| (a, b)).collect();
            let first: BTreeSet<i32> = pairs.iter().map(|p| p.0).collect();
            let second: BTreeSet<i32> = pairs.iter().map(|p| p.1).collect();
            let same = pairs.len() == first.len() && pairs.len() == second.len();
            let border_noise = extracted.labels.iter().zip(&reference.labels).filter(|(a, b)| **a == -1 && **b >= 0).count();
            let moved = if same {
                let mapping: BTreeMap<i32, i32> = pairs.into_iter().collect();
                extracted.labels.iter().zip(&reference.labels)
                    .filter(|(a, b)| **a >= 0 && mapping[&**a] != **b).count().to_string()
            } else { "-".to_owned() };
            lines.push(format!("{} {} core_partition {} border_as_noise {border_noise} moved {moved}",
                extracted.name, reference.name, if same { "same" } else { "different" }));
        }
        lines
    }

    fn optics_summary(&self) -> Vec<String> {
        let mut components = Vec::new();
        for &i in &self.order.points {
            if self.order.reach[i] == INF { components.push(0); }
            *components.last_mut().unwrap() += 1;
        }
        vec![format!("optics max_eps {} core {} components {} singletons {} largest {}", self.p.max_eps,
            self.order.core.iter().filter(|&&v| v != INF).count(), components.len(),
            components.iter().filter(|&&c| c == 1).count(), components.iter().max().unwrap())]
    }

    fn sweep_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("sweep max_eps {}", self.p.max_eps), "eps clusters noise largest".to_owned()];
        let mut counts = Vec::new();
        for eps in 1..=self.p.max_eps {
            let (labels, _) = extract(&self.order, eps);
            let clusters = (labels.iter().max().unwrap() + 1) as usize;
            let mut sizes = vec![0; clusters];
            for &label in &labels { if label >= 0 { sizes[label as usize] += 1; } }
            counts.push(clusters);
            lines.push(format!("{eps} {clusters} {} {}", labels.iter().filter(|&&v| v == -1).count(),
                sizes.iter().max().unwrap_or(&0)));
        }
        let mut stable = None;
        let mut start = 0;
        for end in 1..=counts.len() {
            if end < counts.len() && counts[end] == counts[start] { continue; }
            let length = end - start;
            if counts[start] >= 2 && stable.is_none_or(|(_, _, _, old_length)| length > old_length) {
                stable = Some((counts[start], start + 1, end, length));
            }
            start = end;
        }
        lines.push(stable.map_or_else(|| "stable -".to_owned(), |(count, first, last, length)| {
            format!("stable clusters {count} eps {first} {last} length {length}")
        }));
        lines
    }

    fn xi_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("xi {} min_size {} steep_areas {}", self.p.xi, self.p.min_size, self.xi.areas.len())];
        for &(kind, start, end) in &self.xi.areas { lines.push(format!("{kind} {} {}", start + 1, end + 1)); }
        lines.push(format!("xi_clusters {}", self.xi.clusters.len()));
        for (j, &(start, end)) in self.xi.clusters.iter().enumerate() {
            let valley = self.xi.reach[start + 1..=end].iter().filter(|&&r| r != INF).min().copied().unwrap_or(INF);
            lines.push(format!(concat!("{} start {} end {} size {} label {} parent {} walls {} {} valley {}"),
                j, start + 1, end + 1, end - start + 1, optional_index(self.xi.cluster_labels[j]),
                optional_index(self.xi.parents[j]), optional_root(self.xi.reach[start]),
                optional_root(self.xi.reach[end + 1]), optional_root(valley)));
        }
        lines
    }

    fn outlier_lines(&self) -> Vec<String> {
        let knee = self.knee();
        let core: Vec<usize> = (0..self.points.len()).filter(|&i| knee.core[i]).collect();
        let mut rows = Vec::new();
        for (i, &label) in knee.labels.iter().enumerate() {
            if label != -1 { continue; }
            let nearest = *core.iter().min_by_key(|&&j| (distance(&self.points[i], &self.points[j]), self.points[j].id)).unwrap();
            rows.push((distance(&self.points[i], &self.points[nearest]), i, nearest));
        }
        rows.sort_by_key(|&(distance, i, _)| (std::cmp::Reverse(distance), self.points[i].id));
        let mut lines = vec![format!("outliers {} count {}", knee.name, rows.len())];
        for (distance, i, nearest) in rows {
            lines.push(format!("{} nearest_core {} cluster {} dist_sq {distance} dist {}", self.points[i].id,
                self.points[nearest].id, knee.labels[nearest], root(distance)));
        }
        lines
    }

    fn gap_lines(&self) -> Vec<String> {
        let knee = self.knee();
        let mut lines = vec![format!("gaps {}", knee.name)];
        for a in 0..knee.members.len() {
            for b in a + 1..knee.members.len() {
                let mut best = None;
                for &i in &knee.members[a] {
                    for &j in &knee.members[b] {
                        let value = distance(&self.points[i], &self.points[j]);
                        if best.is_none_or(|(old, _, _)| value < old) { best = Some((value, i, j)); }
                    }
                }
                let (value, i, j) = best.unwrap();
                lines.push(format!("{a} {b} dist_sq {value} dist {} between {} {}", root(value), self.points[i].id, self.points[j].id));
            }
        }
        lines
    }

    fn contingency_lines(&self) -> Vec<String> {
        let knee = self.knee();
        let xi = self.settings.last().unwrap();
        let mut table = vec![vec![0i64; xi.members.len() + 1]; knee.members.len() + 1];
        for (&row, &column) in knee.labels.iter().zip(&xi.labels) { table[(row + 1) as usize][(column + 1) as usize] += 1; }
        let mut lines = vec![format!("contingency {} xi", knee.name),
            format!("columns {}", integers(-1..xi.members.len() as i64))];
        for (r, row) in table.iter().enumerate() { lines.push(format!("{} {}", r as i64 - 1, integers(row.iter().copied()))); }
        for c in 0..xi.members.len() {
            let mut matching = 0;
            for r in 1..knee.members.len() {
                if table[r + 1][c + 1] > table[matching + 1][c + 1] { matching = r; }
            }
            let shared = table[matching + 1][c + 1];
            let union = knee.members[matching].len() as i64 + xi.members[c].len() as i64 - shared;
            lines.push(format!("match {c} {matching} shared {shared} jaccard {}", fraction(shared, union)));
        }
        lines
    }

    fn ari_lines(&self) -> Vec<String> {
        let mut lines = vec!["ari".to_owned()];
        for (i, first) in self.settings.iter().enumerate() {
            for second in &self.settings[i + 1..] {
                let (a, b) = adjusted_rand(&first.labels, &second.labels);
                lines.push(format!("{} {} {}", first.name, second.name, ari(a, b)));
            }
        }
        lines
    }

    fn clusters_lines(&self) -> Vec<String> {
        let names = self.settings.iter().map(|s| s.name.as_str()).collect::<Vec<_>>().join(" ");
        let mut parts = vec![vec![format!("points {} min_pts {}", self.points.len(), self.p.min_pts),
            format!("settings {names}")], self.grid_lines()];
        parts.extend(self.settings.iter().map(|s| self.setting_lines(s)));
        parts.extend([self.hierarchy_lines(), self.comparison_lines(), self.optics_summary(), self.sweep_lines(),
            self.xi_lines(), self.outlier_lines(), self.gap_lines(), self.contingency_lines(), self.ari_lines()]);
        join_parts(parts)
    }

    fn cluster_map(&self, setting: &Setting) -> Vec<String> {
        let mut labels = vec![vec![BTreeSet::new(); self.p.width]; self.p.height];
        let mut occupied = vec![vec![false; self.p.width]; self.p.height];
        for (i, &(column, row)) in self.map_cells.iter().enumerate() {
            occupied[row][column] = true;
            if setting.labels[i] >= 0 { labels[row][column].insert(setting.labels[i]); }
        }
        (0..self.p.height).map(|r| (0..self.p.width).map(|c| {
            if !occupied[r][c] { ' ' } else if labels[r][c].is_empty() { '.' }
            else if labels[r][c].len() == 1 { label_char(*labels[r][c].first().unwrap()) } else { '*' }
        }).collect()).collect()
    }

    fn kind_map(&self) -> Vec<String> {
        let knee = self.knee();
        let mut cells: Vec<Vec<usize>> = vec![vec![0; self.p.width]; self.p.height];
        for (i, &(column, row)) in self.map_cells.iter().enumerate() {
            let kind = if knee.core[i] { 3 } else if knee.labels[i] >= 0 { 2 } else { 1 };
            cells[row][column] = cells[row][column].max(kind);
        }
        cells.iter().map(|row| row.iter().map(|&kind| [ ' ', '.', '+', '#' ][kind]).collect()).collect()
    }

    fn maps_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for setting in &self.settings {
            lines.push(format!("map {} clusters {} noise {}", setting.name, setting.members.len(), setting.noise));
            lines.extend(framed(self.cluster_map(setting), self.p.width));
            let legend = setting.members.iter().enumerate().map(|(label, members)| {
                format!("{}={}", label_char(label as i32), members.len())
            }).collect::<Vec<_>>().join(" ");
            lines.push(format!("legend {}", if legend.is_empty() { "-" } else { &legend }));
            lines.push(String::new());
        }
        lines.push(format!("kinds {}", self.knee().name));
        lines.extend(framed(self.kind_map(), self.p.width));
        lines.push(String::new());
        let curve = self.curve();
        let top = curve.values[0];
        let mut heights = Vec::new();
        let mut knee_column = 0;
        for c in 0..self.p.k_width {
            let first = c * self.points.len() / self.p.k_width;
            let last = (c + 1) * self.points.len() / self.p.k_width;
            let height = self.p.k_height as i64;
            heights.push(integer_root(height * height * curve.values[first] / top) as usize);
            if first <= curve.knee && curve.knee < last { knee_column = c; }
        }
        let rows = (0..self.p.k_height).map(|r| (0..self.p.k_width).map(|c| {
            if self.p.k_height - r <= heights[c] { '#' } else if c == knee_column { ':' } else { ' ' }
        }).collect()).collect();
        lines.push(format!("kdist_plot k {} max {} knee_column {}", self.p.min_pts - 1, root(top), knee_column + 1));
        lines.extend(framed(rows, self.p.k_width));
        lines.push(String::new());
        let reach_top = *self.order.reach.iter().filter(|&&r| r != INF).max().unwrap();
        let columns: Vec<&Setting> = self.settings.iter().filter(|s| s.kind != "dbscan").collect();
        lines.push(format!("reachability width {} max_reach {} columns {}", self.p.plot_width, root(reach_top),
            columns.iter().map(|s| s.name.as_str()).collect::<Vec<_>>().join(" ")));
        for (position, &i) in self.order.points.iter().enumerate() {
            let reach = self.order.reach[i];
            let bar = if reach == INF { "-".repeat(self.p.plot_width) } else {
                let width = self.p.plot_width as i64;
                "#".repeat(integer_root(width * width * reach / reach_top) as usize)
            };
            let labels: String = columns.iter().map(|s| label_char(s.labels[i])).collect();
            lines.push(format!("{:>4} {:>5} {:>7} {labels} |{bar}", position + 1, self.points[i].id, optional_root(reach)));
        }
        lines
    }
}

fn main() -> std::io::Result<()> {
    let (points, params) = dataset::read_inputs()?;
    let study = Study::new(points, params);
    write_lines("labels.csv", study.labels_lines())?;
    write_lines("optics_order.csv", study.optics_lines())?;
    write_lines("kdist.txt", study.kdist_lines())?;
    write_lines("clusters.txt", study.clusters_lines())?;
    write_lines("maps.txt", study.maps_lines())
}
