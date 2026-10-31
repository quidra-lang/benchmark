mod dataset;
mod kdtree;
mod quadtree;
mod rtree;
mod grid;
mod report;

use dataset::Point;
use rtree::{Bounds, Target, Tree};
use std::{collections::BTreeMap, io};

const NAMES: [&str; 7] = ["kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect"];
const COMMANDS: [&str; 7] = ["RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"];

struct View {
    region: Bounds,
    held: Vec<(i64, Bounds)>,
    children: Vec<View>,
    count: usize,
    line: String,
    level: usize,
}

fn kd_regions(region: Bounds, node: &kdtree::Node) -> (Bounds, Bounds) {
    let Bounds(x1, y1, x2, y2) = region;
    if node.depth % 2 == 0 {
        (Bounds(x1, y1, node.point.x, y2), Bounds(node.point.x, y1, x2, y2))
    } else {
        (Bounds(x1, y1, x2, node.point.y), Bounds(x1, node.point.y, x2, y2))
    }
}

fn kd_view(node: &kdtree::Node, region: Bounds, mark: &str) -> View {
    let (left, right) = kd_regions(region, node);
    let mut children = Vec::new();
    if let Some(child) = &node.left { children.push(kd_view(child, left, "L")); }
    if let Some(child) = &node.right { children.push(kd_view(child, right, "R")); }
    let count = 1 + children.iter().map(|v| v.count).sum::<usize>();
    let point = node.point;
    View { region, held: vec![(point.id, point.bounds())], children, count, level: 0,
        line: format!("{} {} {} {} {} box {}", mark, if node.depth % 2 == 0 { "x" } else { "y" }, point.id, point.x, point.y, region.text()) }
}

fn quad_view(node: &quadtree::Node, mark: &str) -> View {
    let children: Vec<View> = node.children.iter().enumerate().map(|(j, c)| quad_view(c, quadtree::NAMES[j])).collect();
    let count = node.points.len() + children.iter().map(|v| v.count).sum::<usize>();
    let suffix = if children.is_empty() { format!("leaf {}", report::ids(&node.points.iter().map(|p| p.id).collect::<Vec<_>>())) }
        else { format!("node count {}", count) };
    View { region: Bounds(node.x, node.y, node.x + node.size - 1, node.y + node.size - 1),
        held: node.points.iter().map(|p| (p.id, p.bounds())).collect(), children, count, level: 0,
        line: format!("{} {} {} {} {}", mark, node.x, node.y, node.size, suffix) }
}

fn rt_view(tree: &Tree, node: usize) -> View {
    let entries = &tree.nodes[node].entries;
    let mut held = Vec::new();
    let mut children = Vec::new();
    for entry in entries {
        match entry.target {
            Target::Object(id) => held.push((id, entry.bounds)),
            Target::Child(child) => children.push(rt_view(tree, child)),
        }
    }
    let region = tree.bounds(node);
    let count = held.len() + children.iter().map(|v| v.count).sum::<usize>();
    let level = tree.nodes[node].level;
    let line = if level == 0 { format!("leaf {} ids {}", region.text(), report::ids(&held.iter().map(|r| r.0).collect::<Vec<_>>())) }
        else { format!("node {} {} entries {}", level, region.text(), entries.len()) };
    View { region, held, children, count, line, level }
}

struct Indexes {
    points: BTreeMap<i64, Point>,
    rectangles: BTreeMap<i64, Bounds>,
    kd: Option<Box<kdtree::Node>>,
    quad: quadtree::Node,
    trees: Vec<Tree>,
    grid: grid::Grid,
    world: i64,
    bucket: usize,
    maximum: usize,
    minimum: usize,
}

impl Indexes {
    fn build(data: &dataset::Data) -> Self {
        let point_objects: Vec<(i64, Bounds)> = data.points.iter().map(|p| (p.id, p.bounds())).collect();
        let mut point_tree = Tree::new(data.maximum, data.minimum);
        for &(id, bounds) in &point_objects { point_tree.insert_object(id, bounds); }
        let point_str = Tree::bulk(&point_objects, data.maximum, data.minimum);
        let mut rect_tree = Tree::new(data.maximum, data.minimum);
        for &(id, bounds) in &data.rectangles { rect_tree.insert_object(id, bounds); }
        let rect_str = Tree::bulk(&data.rectangles, data.maximum, data.minimum);
        let mut quad = quadtree::Node::new(0, 0, data.world);
        let mut grid = grid::Grid::new(data.world, data.grid);
        for &point in &data.points { quad.insert(point, data.bucket); grid.insert(point); }
        Self { points: data.points.iter().map(|&p| (p.id, p)).collect(), rectangles: data.rectangles.iter().copied().collect(),
            kd: kdtree::build(&data.points, 0), quad, trees: vec![point_tree, point_str, rect_tree, rect_str], grid,
            world: data.world, bucket: data.bucket, maximum: data.maximum, minimum: data.minimum }
    }

    fn views(&self) -> Vec<View> {
        let region = Bounds(0, 0, self.world - 1, self.world - 1);
        let mut cells = Vec::new();
        for j in 0..self.grid.count {
            for i in 0..self.grid.count {
                let points = &self.grid.cells[j * self.grid.count + i];
                let x = i as i64 * self.grid.side;
                let y = j as i64 * self.grid.side;
                cells.push(View { region: Bounds(x, y, x + self.grid.side - 1, y + self.grid.side - 1),
                    held: points.iter().map(|p| (p.id, p.bounds())).collect(), children: Vec::new(), count: points.len(), line: String::new(), level: 0 });
            }
        }
        vec![kd_view(self.kd.as_ref().unwrap(), region, "root"), quad_view(&self.quad, "root"),
            rt_view(&self.trees[0], self.trees[0].root), rt_view(&self.trees[1], self.trees[1].root),
            View { region, held: Vec::new(), children: cells, count: self.points.len(), line: String::new(), level: 0 },
            rt_view(&self.trees[2], self.trees[2].root), rt_view(&self.trees[3], self.trees[3].root)]
    }

    fn insert(&mut self, point: Point) {
        kdtree::insert(&mut self.kd, point, 0);
        self.quad.insert(point, self.bucket);
        self.trees[0].insert_object(point.id, point.bounds());
        self.trees[1].insert_object(point.id, point.bounds());
        self.grid.insert(point);
        self.points.insert(point.id, point);
    }

    fn delete(&mut self, id: i64) -> bool {
        if let Some(point) = self.points.remove(&id) {
            self.kd = kdtree::delete(self.kd.take(), point);
            self.quad.delete(point, self.bucket);
            self.trees[0].delete(id);
            self.trees[1].delete(id);
            self.grid.delete(point);
            true
        } else { false }
    }

    fn locate(&self, id: i64) -> String {
        let point = self.points[&id];
        let mut node = self.kd.as_ref().unwrap();
        let mut kd = String::new();
        while node.point.id != id {
            if kdtree::key(point, node.depth % 2) < kdtree::key(node.point, node.depth % 2) {
                kd.push('L');
                node = node.left.as_ref().unwrap();
            } else {
                kd.push('R');
                node = node.right.as_ref().unwrap();
            }
        }
        let mut node = &self.quad;
        let mut quad = Vec::new();
        while !node.children.is_empty() {
            let j = node.destination(point);
            quad.push(quadtree::NAMES[j]);
            node = &node.children[j];
        }
        let path = |tree: &Tree| tree.locate(id).iter().map(ToString::to_string).collect::<Vec<_>>().join("/");
        format!("kdtree {} quadtree {} rtree {} str {} grid {} {}", if kd.is_empty() { "-" } else { &kd },
            if quad.is_empty() { "-".into() } else { quad.join("/") }, path(&self.trees[0]), path(&self.trees[1]), point.x / self.grid.side, point.y / self.grid.side)
    }
}

#[derive(PartialEq)]
enum Answer {
    Ids(Vec<i64>),
    Nearest(Vec<(i64, i64)>),
    Count(usize),
    Join(Vec<(i64, i64)>),
}

#[derive(Default, Clone, Copy)]
struct Visits {
    nodes: usize,
    tests: usize,
}

fn window(values: &[i64]) -> Bounds {
    Bounds(values[0], values[1], values[2], values[3])
}

fn region_matches(command: &str, values: &[i64], region: Bounds) -> bool {
    match command {
        "RANGE" | "WINDOWCOUNT" => region.intersects(window(values)),
        "RADIUS" => region.distance(values[0], values[1]) <= values[2] * values[2],
        "CONTAINS" => region.contains(Bounds(values[0], values[1], values[0], values[1])),
        _ => unreachable!(),
    }
}

fn object_matches(command: &str, values: &[i64], object: Bounds) -> bool {
    match command {
        "RANGE" | "WINDOWCOUNT" => window(values).contains(object),
        "RADIUS" => object.distance(values[0], values[1]) <= values[2] * values[2],
        "CONTAINS" => object.contains(Bounds(values[0], values[1], values[0], values[1])),
        _ => unreachable!(),
    }
}

fn condition(node: &View, command: &str, values: &[i64], result: &mut Vec<i64>, count: &mut usize, visits: &mut Visits) {
    visits.nodes += 1;
    if command == "WINDOWCOUNT" && window(values).contains(node.region) {
        *count += node.count;
        return;
    }
    visits.tests += node.held.len();
    for &(id, bounds) in &node.held {
        if object_matches(command, values, bounds) { result.push(id); *count += 1; }
    }
    for child in &node.children {
        if region_matches(command, values, child.region) { condition(child, command, values, result, count, visits); }
    }
}

enum QueueEntry<'a> {
    Node(&'a View),
    Object(i64, i64),
}

fn nearest(root: &View, values: &[i64]) -> (Answer, Visits) {
    let (x, y, k) = (values[0], values[1], values[2] as usize);
    let mut queue = BTreeMap::new();
    queue.insert((root.region.distance(x, y), 0u8, 0i64), QueueEntry::Node(root));
    let mut serial = 1;
    let mut visits = Visits::default();
    let mut result = Vec::new();
    while let Some((_, entry)) = queue.pop_first() {
        match entry {
            QueueEntry::Object(id, distance) => {
                result.push((id, distance));
                if result.len() == k { break; }
            }
            QueueEntry::Node(node) => {
                visits.nodes += 1;
                visits.tests += node.held.len();
                for &(id, bounds) in &node.held {
                    let distance = bounds.distance(x, y);
                    queue.insert((distance, 1, id), QueueEntry::Object(id, distance));
                }
                for child in &node.children {
                    queue.insert((child.region.distance(x, y), 0, serial), QueueEntry::Node(child));
                    serial += 1;
                }
            }
        }
    }
    (Answer::Nearest(result), visits)
}

fn search(root: &View, command: &str, values: &[i64]) -> (Answer, Visits) {
    if command == "KNN" || command == "NEAREST" { return nearest(root, values); }
    let (mut result, mut count, mut visits) = (Vec::new(), 0, Visits::default());
    condition(root, command, values, &mut result, &mut count, &mut visits);
    result.sort();
    (if command == "WINDOWCOUNT" { Answer::Count(count) } else { Answer::Ids(result) }, visits)
}

fn join(a: &View, b: &View, answer: &mut Vec<(i64, i64)>, visits: &mut Visits) {
    visits.nodes += 1;
    match (a.children.is_empty(), b.children.is_empty()) {
        (true, true) => {
            visits.tests += a.held.len() * b.held.len();
            for &(point, pb) in &a.held {
                for &(rectangle, rb) in &b.held {
                    if rb.contains(pb) { answer.push((rectangle, point)); }
                }
            }
        }
        (true, false) => for child in &b.children { if child.region.intersects(a.region) { join(a, child, answer, visits); } },
        (false, true) => for child in &a.children { if child.region.intersects(b.region) { join(child, b, answer, visits); } },
        (false, false) => for child_a in &a.children {
            for child_b in &b.children {
                if child_a.region.intersects(child_b.region) { join(child_a, child_b, answer, visits); }
            }
        },
    }
}

fn brute(indexes: &Indexes, command: &str, values: &[i64]) -> Answer {
    if command == "JOIN" {
        let mut pairs = Vec::new();
        for (&rectangle, &bounds) in &indexes.rectangles {
            for (&id, point) in &indexes.points { if bounds.contains(point.bounds()) { pairs.push((rectangle, id)); } }
        }
        return Answer::Join(pairs);
    }
    let objects: Vec<(i64, Bounds)> = if command == "CONTAINS" || command == "NEAREST" {
        indexes.rectangles.iter().map(|(&id, &bounds)| (id, bounds)).collect()
    } else { indexes.points.iter().map(|(&id, p)| (id, p.bounds())).collect() };
    if command == "KNN" || command == "NEAREST" {
        let mut distances: Vec<(i64, i64)> = objects.iter().map(|&(id, b)| (id, b.distance(values[0], values[1]))).collect();
        distances.sort_by_key(|&(id, distance)| (distance, id));
        distances.truncate(values[2] as usize);
        Answer::Nearest(distances)
    } else {
        let selected: Vec<i64> = objects.iter().filter(|(_, b)| object_matches(command, values, *b)).map(|(id, _)| *id).collect();
        if command == "WINDOWCOUNT" { Answer::Count(selected.len()) } else { Answer::Ids(selected) }
    }
}

fn flatten<'a>(node: &'a View, depth: usize, nodes: &mut Vec<(usize, &'a View)>) {
    nodes.push((depth, node));
    for child in &node.children { flatten(child, depth + 1, nodes); }
}

fn snapshot(indexes: &Indexes, number: usize, query: usize) -> (Vec<String>, Vec<String>) {
    let header = format!("snapshot {} query {} points {} rects {}", number, query, indexes.points.len(), indexes.rectangles.len());
    let mut structures = vec![header.clone()];
    let mut statistics = vec![header];
    let views = indexes.views();
    for index in [0, 1, 2, 3, 5, 6] {
        let root = &views[index];
        let mut nodes = Vec::new();
        flatten(root, 0, &mut nodes);
        structures.push(NAMES[index].into());
        for (depth, node) in &nodes { structures.push(format!("{}{}", " ".repeat(2 * (depth + 1)), node.line)); }
        let height = nodes.iter().map(|(depth, _)| depth + 1).max().unwrap();
        if index == 0 {
            let count = nodes.len();
            let leaves = nodes.iter().filter(|(_, n)| n.children.is_empty()).count();
            let one = nodes.iter().filter(|(_, n)| n.children.len() == 1).count();
            let depth_sum: usize = nodes.iter().map(|(d, _)| *d).sum();
            let mut ideal = 0;
            while (1usize << ideal) - 1 < count { ideal += 1; }
            statistics.push(format!("kdtree height {} ideal {} nodes {} leaves {} one_child {} depth_sum {} avg_depth {}", height, ideal, count, leaves, one, depth_sum,
                report::fraction(depth_sum as i64, count as i64)));
            for depth in 0..height {
                let row: Vec<&View> = nodes.iter().filter(|(d, _)| *d == depth).map(|(_, n)| *n).collect();
                statistics.push(format!("  depth {} nodes {} leaves {} one_child {}", depth, row.len(), row.iter().filter(|n| n.children.is_empty()).count(), row.iter().filter(|n| n.children.len() == 1).count()));
            }
        } else if index == 1 {
            let leaves: Vec<&View> = nodes.iter().filter(|(_, n)| n.children.is_empty()).map(|(_, n)| *n).collect();
            statistics.push(format!("quadtree height {} internal {} leaves {} empty {} max_leaf {} fill {}", height, nodes.len() - leaves.len(), leaves.len(),
                leaves.iter().filter(|n| n.held.is_empty()).count(), leaves.iter().map(|n| n.held.len()).max().unwrap(),
                report::fraction(indexes.points.len() as i64, (leaves.len() * indexes.bucket) as i64)));
            for depth in 0..height {
                let row: Vec<&View> = nodes.iter().filter(|(d, _)| *d == depth).map(|(_, n)| *n).collect();
                statistics.push(format!("  depth {} internal {} leaves {} points {}", depth, row.iter().filter(|n| !n.children.is_empty()).count(),
                    row.iter().filter(|n| n.children.is_empty()).count(), row.iter().map(|n| n.held.len()).sum::<usize>()));
            }
        } else {
            let entries = |n: &View| if n.children.is_empty() { n.held.len() } else { n.children.len() };
            let total: usize = nodes.iter().map(|(_, n)| entries(n)).sum();
            statistics.push(format!("{} height {} nodes {} leaves {} entries {} fill {}", NAMES[index], height, nodes.len(), nodes.iter().filter(|(_, n)| n.children.is_empty()).count(), total,
                report::fraction(total as i64, (nodes.len() * indexes.maximum) as i64)));
            for level in (0..height).rev() {
                let row: Vec<&View> = nodes.iter().filter(|(_, n)| n.level == level).map(|(_, n)| *n).collect();
                let mut overlap = 0;
                for i in 0..row.len() {
                    for j in i + 1..row.len() { overlap += row[i].region.overlap(row[j].region); }
                }
                statistics.push(format!("  level {} nodes {} entries {} min {} max {} under {} area {} overlap {}", level, row.len(), row.iter().map(|n| entries(n)).sum::<usize>(),
                    row.iter().map(|n| entries(n)).min().unwrap(), row.iter().map(|n| entries(n)).max().unwrap(), row.iter().filter(|n| entries(n) < indexes.minimum).count(),
                    row.iter().map(|n| n.region.area()).sum::<i64>(), overlap));
            }
        }
    }
    let mut occupancy = BTreeMap::new();
    for cell in &indexes.grid.cells { *occupancy.entry(cell.len()).or_insert(0usize) += 1; }
    statistics.push(format!("grid cells {} used {} max {}", indexes.grid.cells.len(), indexes.grid.cells.iter().filter(|c| !c.is_empty()).count(), occupancy.keys().last().unwrap()));
    statistics.push(format!("  occupancy {}", occupancy.iter().map(|(k, count)| format!("{}:{}", k, count)).collect::<Vec<_>>().join(" ")));
    (structures, statistics)
}

fn main() -> io::Result<()> {
    let data = dataset::read()?;
    let mut indexes = Indexes::build(&data);
    let (mut structures, mut stats) = snapshot(&indexes, 0, 0);
    let mut snapshots = 0;
    let mut answers = Vec::new();
    let mut visits = vec!["query,command,structure,nodes,tests".into()];
    let mut joined = vec!["query,rect,point".into()];
    let mut totals: BTreeMap<(String, usize), Vec<Visits>> = BTreeMap::new();
    for (command_number, (command, values)) in data.commands.iter().enumerate() {
        let q = command_number + 1;
        match command.as_str() {
            "INSERT" => {
                indexes.insert(Point { id: values[0], x: values[1], y: values[2] });
                answers.push(format!("{} INSERT {} inserted points {}", q, values[0], indexes.points.len()));
            }
            "DELETE" => {
                let deleted = indexes.delete(values[0]);
                answers.push(format!("{} DELETE {} {} points {}", q, values[0], if deleted { "deleted" } else { "missing" }, indexes.points.len()));
            }
            "LOCATE" => {
                answers.push(if indexes.points.contains_key(&values[0]) { format!("{} LOCATE {} {}", q, values[0], indexes.locate(values[0])) }
                    else { format!("{} LOCATE {} missing", q, values[0]) });
            }
            "DUMP" => {
                snapshots += 1;
                let (dump, summary) = snapshot(&indexes, snapshots, q);
                structures.push(String::new());
                structures.extend(dump);
                stats.push(String::new());
                stats.extend(summary);
                answers.push(format!("{} DUMP snapshot {}", q, snapshots));
            }
            _ => {
                let reference = brute(&indexes, command, values);
                let views = indexes.views();
                let selected: Vec<usize> = match command.as_str() {
                    "CONTAINS" | "NEAREST" => vec![5, 6],
                    "JOIN" => vec![2, 3],
                    _ => vec![0, 1, 2, 3, 4],
                };
                let mut mismatches = Vec::new();
                for index in selected {
                    let (answer, counts) = if command == "JOIN" {
                        let mut result = Vec::new();
                        let mut visits = Visits::default();
                        join(&views[index], &views[index + 3], &mut result, &mut visits);
                        result.sort();
                        (Answer::Join(result), visits)
                    } else { search(&views[index], command, values) };
                    if answer != reference { mismatches.push(NAMES[index]); }
                    visits.push(format!("{},{},{},{},{}", q, command, NAMES[index], counts.nodes, counts.tests));
                    totals.entry((command.clone(), index)).or_default().push(counts);
                }
                let check = if mismatches.is_empty() { "ok".into() } else { format!("mismatch {}", mismatches.join(" ")) };
                let result = match reference {
                    Answer::Ids(ids) => format!("count {} ids {}", ids.len(), report::ids(&ids)),
                    Answer::Nearest(items) => format!("count {} ids {}", items.len(), items.iter().map(|(id, distance)| format!("{}:{}", id, distance)).collect::<Vec<_>>().join(" ")),
                    Answer::Count(count) => format!("count {}", count),
                    Answer::Join(pairs) => {
                        for &(rectangle, point) in &pairs { joined.push(format!("{},{},{}", q, rectangle, point)); }
                        format!("count {}", pairs.len())
                    }
                };
                answers.push(format!("{} {} {} check {}", q, command, result, check));
            }
        }
    }
    stats.extend([String::new(), "visits".into()]);
    for command in COMMANDS {
        let mut ranking = Vec::new();
        for index in 0..NAMES.len() {
            if let Some(values) = totals.get(&(command.to_owned(), index)) {
                let nodes: usize = values.iter().map(|v| v.nodes).sum();
                let tests: usize = values.iter().map(|v| v.tests).sum();
                let maximum = values.iter().map(|v| v.nodes).max().unwrap();
                stats.push(format!("{} {} queries {} nodes {} tests {} max_nodes {} mean_nodes {}", command, NAMES[index], values.len(), nodes, tests, maximum,
                    report::fraction(nodes as i64, values.len() as i64)));
                ranking.push((nodes, tests, index));
            }
        }
        if !ranking.is_empty() {
            ranking.sort();
            stats.push(format!("rank {} {}", command, ranking.iter().map(|&(_, _, index)| NAMES[index]).collect::<Vec<_>>().join(" ")));
        }
    }
    report::write("answers.txt", &answers)?;
    report::write("visits.csv", &visits)?;
    report::write("join.csv", &joined)?;
    report::write("structures.txt", &structures)?;
    report::write("stats.txt", &stats)?;
    Ok(())
}
