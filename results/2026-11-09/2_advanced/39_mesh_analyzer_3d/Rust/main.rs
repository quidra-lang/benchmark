mod measure;
mod obj_io;
mod orientation;
mod repair;
mod topology;

use measure::{angle, area, centroid, cross, dot, fraction, length2, normal, real, subtract, vector, volume6, winding, Point};
use obj_io::{Face, Model};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fmt::Display;
use std::fs;
use topology::{edge, face_edges, BoundaryLoop, Edge, Topology};

struct Params {
    values: BTreeMap<String, String>,
    sections: Vec<String>,
    queries: Vec<Vec<String>>,
}

impl Params {
    fn read() -> Self {
        let mut values: BTreeMap<_, _> = [("snap", "1"), ("merge", "on"), ("degenerate", "on"), ("duplicates", "on"), ("orient", "on"), ("outward", "on"), ("fill_holes", "0"), ("keep_unused", "on")].iter().map(|&(key, value)| (key.into(), value.into())).collect();
        let mut sections = vec!["summary".into(), "components".into()];
        let mut queries = Vec::new();
        for line in fs::read_to_string("input/params.txt").unwrap().lines().filter(|line| !line.is_empty() && !line.starts_with('#')) {
            let words: Vec<_> = line.split(' ').collect();
            match words[0] {
                "sections" => sections = words[1..].iter().map(|s| s.to_string()).collect(),
                "query" => queries.push(words[1..].iter().map(|s| s.to_string()).collect()),
                _ => { values.insert(words[0].into(), words[1].into()); }
            }
        }
        Self { values, sections, queries }
    }
    fn on(&self, name: &str) -> bool { self.values[name] == "on" }
    fn number(&self, name: &str) -> i64 { self.values[name].parse().unwrap() }
}

fn list<T: Display>(values: &[T]) -> String {
    if values.is_empty() { "-".into() } else { values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ") }
}
fn yes(condition: bool) -> &'static str { if condition { "yes" } else { "no" } }
fn face_list(values: &[usize]) -> String { list(&values.iter().map(|&f| f + 1).collect::<Vec<_>>()) }

fn edge_shape(faces: &[Face], vertices: &[Point], edge: Edge, members: &[usize]) -> &'static str {
    if members.len() != 2 { return "-"; }
    let (a, b) = edge;
    let f = &faces[members[0]];
    let g = &faces[members[1]];
    if orientation::directed(f, a, b) == orientation::directed(g, a, b) { return "inconsistent"; }
    let d = *g.vertices.iter().find(|&&v| v != a && v != b).unwrap();
    let sign = dot(subtract(vertices[d], vertices[f.vertices[0]]), normal(f, vertices));
    if sign < 0 { "convex" } else if sign > 0 { "concave" } else { "flat" }
}

fn box_of(vertices: &[Point], members: &BTreeSet<usize>) -> [i64; 6] {
    std::array::from_fn(|i| {
        let coordinate = i % 3;
        if i < 3 { members.iter().map(|&v| vertices[v][coordinate]).min().unwrap() }
        else { members.iter().map(|&v| vertices[v][coordinate]).max().unwrap() }
    })
}

struct Properties {
    boundary: usize,
    nonmanifold_edges: usize,
    nonmanifold_vertices: usize,
    loops: usize,
    closed: bool,
    manifold: bool,
    consistent: bool,
    solid: bool,
    orientable: bool,
    euler: i64,
    genus: Option<i64>,
    crosscaps: Option<i64>,
    volume: i64,
    area: f64,
    normal_sum: Point,
    bbox: [i64; 6],
    inside: Vec<usize>,
    shapes: [usize; 3],
    angles: [usize; 3],
    edge_lengths: [i64; 2],
    valence: [usize; 2],
}

struct Analysis {
    model: Model,
    snapped: Vec<Point>,
    representatives: Vec<usize>,
    output_map: Vec<usize>,
    vertices: Vec<Point>,
    faces: Vec<Face>,
    triangles: Vec<Face>,
    removed: Vec<(usize, &'static str)>,
    groups: Vec<String>,
    nonplanar: Vec<bool>,
    topology: Topology,
    properties: Vec<Properties>,
    loops: Vec<BoundaryLoop>,
    boundaries: Vec<String>,
    initial_faces: usize,
    inconsistent_before: usize,
    flipped_faces: usize,
    outward_components: usize,
}

fn boundary_lines(topology: &Topology, faces: &[Face], loops: &[BoundaryLoop]) -> Vec<String> {
    let mut lines = vec![format!("loops {}", loops.len())];
    for (i, boundary) in loops.iter().enumerate() {
        lines.push(format!("loop {} component {} length {} {} {} vertices {}", i + 1, boundary.component + 1, boundary.length, boundary.kind, if boundary.filled { "filled" } else { "kept" }, list(&boundary.vertices)));
    }
    let nonmanifold: Vec<_> = topology.edges.iter().filter(|(_, members)| members.len() >= 3).collect();
    lines.push(format!("nonmanifold_edges {}", nonmanifold.len()));
    for (&(a, b), members) in nonmanifold { lines.push(format!("edge {a} {b} faces {}", face_list(members))); }
    let nonmanifold: Vec<_> = topology.fans.iter().enumerate().filter(|(_, fans)| fans.len() >= 2).collect();
    lines.push(format!("nonmanifold_vertices {}", nonmanifold.len()));
    for (vertex, fans) in nonmanifold {
        let components: BTreeSet<_> = fans.iter().map(|fan| topology.face_component[fan[0]] + 1).collect();
        lines.push(format!("vertex {vertex} fans {} components {}", fans.len(), list(&components.into_iter().collect::<Vec<_>>())));
    }
    let inconsistent = orientation::inconsistent(faces, topology);
    lines.push(format!("inconsistent_edges {}", inconsistent.len()));
    for (a, b) in inconsistent { lines.push(format!("edge {a} {b} faces {}", face_list(&topology.edges[&(a, b)]))); }
    lines
}

fn analyze(params: &Params) -> Analysis {
    let model = obj_io::read();
    let snapped = repair::snap(&model.vertices, params.number("snap"));
    let representatives = repair::representatives(&snapped, params.on("merge"));
    let triangles = repair::triangles(&model.polygons);
    let (mut faces, removed) = repair::clean(&triangles, &snapped, &representatives, params.on("degenerate"), params.on("duplicates"));
    let used: BTreeSet<_> = faces.iter().flat_map(|face| face.vertices).collect();
    let mut output_map = vec![0; snapped.len()];
    let mut vertices = vec![[0; 3]];
    for i in 1..snapped.len() {
        if representatives[i] == i && (params.on("keep_unused") || used.contains(&i)) {
            output_map[i] = vertices.len();
            vertices.push(snapped[i]);
        }
    }
    for face in &mut faces { face.vertices = face.vertices.map(|v| output_map[v]); }
    let initial_faces = faces.len();
    let original_sequences: Vec<_> = faces.iter().map(|face| face.vertices).collect();
    let topology = Topology::build(&faces, vertices.len() - 1);
    let inconsistent_before = orientation::inconsistent(&faces, &topology).len();
    if params.on("orient") { orientation::repair(&mut faces, &topology); }
    let inconsistent = orientation::inconsistent(&faces, &topology);
    let mut loops = topology::loops(&topology);
    for boundary in &mut loops {
        if boundary.kind == "open" { continue; }
        let directions: Vec<_> = (0..boundary.vertices.len()).map(|i| {
            let a = boundary.vertices[i];
            let b = boundary.vertices[(i + 1) % boundary.vertices.len()];
            orientation::directed(&faces[topology.edges[&edge(a, b)][0]], a, b)
        }).collect();
        if directions.iter().all(|&same| same) { boundary.kind = "coherent"; }
        else if directions.iter().all(|&same| !same) {
            boundary.kind = "coherent";
            boundary.vertices[1..].reverse();
        }
        let component = &topology.components[boundary.component];
        let clean = component.edges.iter().all(|edge| topology.edges[edge].len() < 3 && !inconsistent.contains(edge));
        let distinct: BTreeSet<_> = boundary.vertices.iter().copied().collect();
        boundary.filled = boundary.kind == "coherent" && boundary.length >= 3 && boundary.length <= params.number("fill_holes") as usize && distinct.len() == boundary.vertices.len() && clean;
    }
    let boundaries = boundary_lines(&topology, &faces, &loops);
    for boundary in loops.iter().filter(|boundary| boundary.filled) { faces.extend(repair::fill(&boundary.vertices)); }
    let topology = Topology::build(&faces, vertices.len() - 1);
    let final_loops = topology::loops(&topology);
    let inconsistent = orientation::inconsistent(&faces, &topology);
    let solid: Vec<_> = topology.components.iter().enumerate().map(|(i, component)| {
        component.edges.iter().all(|edge| topology.edges[edge].len() == 2 && !inconsistent.contains(edge)) && topology.component_nonmanifold_vertices(i) == 0
    }).collect();
    let mut insides = vec![Vec::new(); topology.components.len()];
    for c in 0..topology.components.len() {
        if !solid[c] { continue; }
        for d in 0..topology.components.len() {
            if c == d || !solid[d] { continue; }
            let z = topology.components[c].vertices.iter().find(|&&v| !topology.components[d].vertices.contains(&v));
            if let Some(&z) = z {
                if winding(vertices[z], &faces, &topology.components[d].faces, &vertices) != 0 { insides[c].push(d + 1); }
            }
        }
    }
    let mut outward_components = 0;
    if params.on("outward") {
        for (i, component) in topology.components.iter().enumerate() {
            if !solid[i] { continue; }
            let volume = volume6(&faces, &component.faces, &vertices);
            if volume != 0 && ((insides[i].len() % 2 == 0 && volume < 0) || (insides[i].len() % 2 == 1 && volume > 0)) {
                for &face in &component.faces { orientation::flip(&mut faces[face]); }
                outward_components += 1;
            }
        }
    }
    let flipped_faces = original_sequences.iter().zip(&faces).filter(|(original, face)| **original != face.vertices).count();
    let mut oriented = faces.clone();
    orientation::repair(&mut oriented, &topology);
    let remaining = orientation::inconsistent(&oriented, &topology);
    let mut properties = Vec::new();
    for (i, component) in topology.components.iter().enumerate() {
        let boundary = component.edges.iter().filter(|&&edge| topology.edges[&edge].len() == 1).count();
        let nonmanifold_edges = component.edges.iter().filter(|&&edge| topology.edges[&edge].len() >= 3).count();
        let nonmanifold_vertices = topology.component_nonmanifold_vertices(i);
        let consistent = component.edges.iter().all(|edge| !inconsistent.contains(edge));
        let orientable = component.edges.iter().all(|edge| !remaining.contains(edge));
        let manifold = nonmanifold_edges == 0 && nonmanifold_vertices == 0;
        let loop_count = final_loops.iter().filter(|boundary| boundary.component == i).count();
        let euler = component.vertices.len() as i64 - component.edges.len() as i64 + component.faces.len() as i64;
        let normal_sum = component.faces.iter().fold([0; 3], |sum, &face| {
            let n = normal(&faces[face], &vertices);
            std::array::from_fn(|coordinate| sum[coordinate] + n[coordinate])
        });
        let shapes = std::array::from_fn(|s| component.edges.iter().filter(|&&edge| edge_shape(&faces, &vertices, edge, &topology.edges[&edge]) == ["convex", "concave", "flat"][s]).count());
        let angles = std::array::from_fn(|a| component.faces.iter().filter(|&&face| angle(&faces[face], &vertices) == ["acute", "right", "obtuse"][a]).count());
        let lengths: Vec<_> = component.edges.iter().map(|&(a, b)| length2(vertices[a], vertices[b])).collect();
        let degrees: Vec<_> = component.vertices.iter().map(|&v| component.edges.iter().filter(|&&(a, b)| a == v || b == v).count()).collect();
        properties.push(Properties {
            boundary, nonmanifold_edges, nonmanifold_vertices, loops: loop_count, closed: boundary == 0,
            manifold, consistent, solid: solid[i], orientable, euler,
            genus: (manifold && orientable).then_some((2 - euler - loop_count as i64) / 2),
            crosscaps: (manifold && !orientable).then_some(2 - euler - loop_count as i64),
            volume: volume6(&faces, &component.faces, &vertices), area: area(&faces, &component.faces, &vertices), normal_sum,
            bbox: box_of(&vertices, &component.vertices), inside: insides[i].clone(), shapes, angles,
            edge_lengths: [*lengths.iter().min().unwrap(), *lengths.iter().max().unwrap()], valence: [*degrees.iter().min().unwrap(), *degrees.iter().max().unwrap()],
        });
    }
    let nonplanar = model.polygons.iter().map(|polygon| {
        let first = snapped[polygon.vertices[0]];
        let mut n = [0; 3];
        for j in 1..polygon.vertices.len() - 1 {
            let term = cross(subtract(snapped[polygon.vertices[j]], first), subtract(snapped[polygon.vertices[j + 1]], first));
            for k in 0..3 { n[k] += term[k]; }
        }
        polygon.vertices.iter().any(|&v| dot(subtract(snapped[v], first), n) != 0)
    }).collect();
    let mut groups = model.groups.clone();
    if faces.len() > initial_faces { groups.push("fill".into()); }
    Analysis { model, snapped, representatives, output_map, vertices, faces, triangles, removed, groups, nonplanar, topology, properties, loops, boundaries, initial_faces, inconsistent_before, flipped_faces, outward_components }
}

fn summary(analysis: &Analysis) -> Vec<String> {
    let a = analysis;
    let snapped = (1..a.snapped.len()).filter(|&i| a.snapped[i] != a.model.vertices[i]).count();
    let merged = (1..a.representatives.len()).filter(|&i| a.representatives[i] != i).count();
    let mut lines = vec!["[summary]".into(), format!("lines {}", a.model.lines), format!("vertices {}", a.model.vertices.len() - 1), format!("polygons {}", a.model.polygons.len()), format!("errors {}", a.model.errors.len()), format!("ignored {}", a.model.ignored), format!("nonplanar_polygons {}", a.nonplanar.iter().filter(|&&value| value).count())];
    let mut sizes = BTreeMap::new();
    for polygon in &a.model.polygons { *sizes.entry(polygon.vertices.len()).or_insert(0) += 1; }
    lines.extend(sizes.iter().map(|(size, count)| format!("polygon_size {size} {count}")));
    lines.extend([format!("triangles {}", a.triangles.len()), format!("snapped {snapped}"), format!("merged {merged}")]);
    for reason in ["repeated", "zero_area", "duplicate"] { lines.push(format!("removed_{reason} {}", a.removed.iter().filter(|(_, r)| *r == reason).count())); }
    lines.extend([format!("faces {}", a.initial_faces), format!("inconsistent_before {}", a.inconsistent_before), format!("flipped_faces {}", a.flipped_faces), format!("outward_components {}", a.outward_components), format!("boundary_loops {}", a.loops.len()), format!("holes_filled {}", a.loops.iter().filter(|boundary| boundary.filled).count()), format!("fill_faces {}", a.faces.len() - a.initial_faces), format!("final_vertices {}", a.vertices.len() - 1), format!("final_faces {}", a.faces.len()), format!("components {}", a.properties.len()), format!("solids {}", a.properties.iter().filter(|p| p.solid).count()), format!("total_area {}", real(area(&a.faces, &(0..a.faces.len()).collect::<Vec<_>>(), &a.vertices))), format!("total_volume {}", fraction(a.properties.iter().filter(|p| p.solid).map(|p| p.volume).sum(), 6))]);
    lines
}

fn cleanup(a: &Analysis) -> Vec<String> {
    let snapped: Vec<_> = (1..a.snapped.len()).filter(|&i| a.snapped[i] != a.model.vertices[i]).collect();
    let merged = (1..a.representatives.len()).filter(|&i| a.representatives[i] != i).count();
    let mut lines = vec!["[cleanup]".into(), format!("snapped {}", snapped.len())];
    for i in snapped { lines.push(format!("snap {i} {} to {}", vector(a.model.vertices[i]), vector(a.snapped[i]))); }
    lines.push(format!("merged {merged}"));
    let mut groups: BTreeMap<usize, Vec<usize>> = BTreeMap::new();
    for i in 1..a.representatives.len() { groups.entry(a.representatives[i]).or_default().push(i); }
    for (representative, members) in groups.into_iter().filter(|(_, members)| members.len() >= 2) {
        let number = if a.output_map[representative] == 0 { "-".into() } else { a.output_map[representative].to_string() };
        lines.push(format!("merge {number} {}", list(&members)));
    }
    lines.push(format!("removed {}", a.removed.len()));
    for &(triangle, reason) in &a.removed {
        let polygon = a.triangles[triangle - 1].polygon.unwrap();
        lines.push(format!("remove {triangle} polygon {} line {} {reason}", polygon + 1, a.model.polygons[polygon].line));
    }
    lines
}

fn component_lines(a: &Analysis) -> Vec<String> {
    let mut lines = Vec::new();
    for (index, (component, p)) in a.topology.components.iter().zip(&a.properties).enumerate() {
        let groups: Vec<_> = a.groups.iter().filter(|group| component.faces.iter().any(|&f| &a.faces[f].group == *group)).cloned().collect();
        lines.extend([format!("[component {}]", index + 1), format!("groups {}", list(&groups)), format!("faces {}", component.faces.len()), format!("vertices {}", component.vertices.len()), format!("edges {}", component.edges.len()), format!("boundary_edges {}", p.boundary), format!("nonmanifold_edges {}", p.nonmanifold_edges), format!("nonmanifold_vertices {}", p.nonmanifold_vertices), format!("boundary_loops {}", p.loops), format!("closed {}", yes(p.closed)), format!("manifold {}", yes(p.manifold)), format!("orientable {}", yes(p.orientable)), format!("consistent {}", yes(p.consistent)), format!("solid {}", yes(p.solid)), format!("euler {}", p.euler)]);
        lines.push(if let Some(genus) = p.genus { format!("genus {genus}") } else if let Some(crosscaps) = p.crosscaps { format!("crosscaps {crosscaps}") } else { "genus -".into() });
        lines.extend([format!("volume {}", if p.solid { fraction(p.volume, 6) } else { "-".into() }), format!("area {}", real(p.area)), format!("normal_sum {}", vector(p.normal_sum)), format!("bbox {}", list(&p.bbox)), format!("inside {}", if p.solid { list(&p.inside) } else { "-".into() }), format!("centroid {}", if p.solid && p.volume != 0 { centroid(&a.faces, &component.faces, &a.vertices) } else { "-".into() })]);
        for (name, count) in ["convex", "concave", "flat"].iter().zip(p.shapes) { lines.push(format!("{name} {count}")); }
        for (name, count) in ["acute", "right", "obtuse"].iter().zip(p.angles) { lines.push(format!("{name} {count}")); }
        lines.extend([format!("edge_len2 {} {}", p.edge_lengths[0], p.edge_lengths[1]), format!("valence {} {}", p.valence[0], p.valence[1])]);
    }
    lines
}

fn group_lines(a: &Analysis) -> Vec<String> {
    let mut lines = Vec::new();
    for group in &a.groups {
        let polygons: Vec<_> = a.model.polygons.iter().enumerate().filter(|(_, p)| &p.group == group).map(|(i, _)| i).collect();
        let faces: Vec<_> = a.faces.iter().enumerate().filter(|(_, f)| &f.group == group).map(|(i, _)| i).collect();
        let components: BTreeSet<_> = faces.iter().map(|&f| a.topology.face_component[f] + 1).collect();
        lines.extend([format!("[group {group}]"), format!("polygons {}", polygons.len()), format!("triangles {}", a.triangles.iter().filter(|t| &t.group == group).count()), format!("nonplanar {}", polygons.iter().filter(|&&p| a.nonplanar[p]).count()), format!("faces {}", faces.len()), format!("area {}", real(area(&a.faces, &faces, &a.vertices))), format!("components {}", list(&components.into_iter().collect::<Vec<_>>()))]);
    }
    lines
}

fn contacts(a: &Analysis) -> Vec<String> {
    let mut lines = vec!["[contacts]".into()];
    for i in 0..a.properties.len() {
        for j in i + 1..a.properties.len() {
            let b = &a.properties[i].bbox;
            let c = &a.properties[j].bbox;
            if !(0..3).all(|k| b[k] <= c[k + 3] && c[k] <= b[k + 3]) { continue; }
            let first = &a.topology.components[i].vertices;
            let second = &a.topology.components[j].vertices;
            let shared = first.intersection(second).count();
            let gap = first.iter().flat_map(|&u| second.iter().filter(move |&&w| u != w).map(move |&w| length2(a.vertices[u], a.vertices[w]))).min().unwrap();
            lines.push(format!("contact {} {} shared {} gap2 {}", i + 1, j + 1, shared, gap));
        }
    }
    lines
}

fn edges(a: &Analysis) -> Vec<String> {
    let mut lines = vec!["[edges]".into(), format!("edges {}", a.topology.edges.len())];
    for (kind, length) in [("boundary", 1), ("manifold", 2), ("nonmanifold", 3)] {
        let count = a.topology.edges.values().filter(|members| if length == 3 { members.len() >= 3 } else { members.len() == length }).count();
        lines.push(format!("{kind} {count}"));
    }
    lines.push(format!("max_faces {}", a.topology.edges.values().map(Vec::len).max().unwrap()));
    for shape in ["convex", "concave", "flat", "inconsistent"] {
        lines.push(format!("{shape} {}", a.topology.edges.iter().filter(|&(edge, members)| edge_shape(&a.faces, &a.vertices, *edge, members) == shape).count()));
    }
    let mut shortest = *a.topology.edges.first_key_value().unwrap().0;
    let mut longest = shortest;
    let length = |(u, v)| length2(a.vertices[u], a.vertices[v]);
    for &edge in a.topology.edges.keys() {
        if length(edge) < length(shortest) { shortest = edge; }
        if length(edge) > length(longest) { longest = edge; }
    }
    lines.extend([format!("shortest {} {} len2 {}", shortest.0, shortest.1, length(shortest)), format!("longest {} {} len2 {}", longest.0, longest.1, length(longest))]);
    lines
}

fn valence(a: &Analysis) -> Vec<String> {
    let used: BTreeSet<_> = a.faces.iter().flat_map(|f| f.vertices).collect();
    let mut counts = BTreeMap::new();
    let mut total = 0;
    for &vertex in &used { let degree = a.topology.degree(vertex); total += degree; *counts.entry(degree).or_insert(0) += 1; }
    let mut lines = vec!["[valence]".into(), format!("used {}", used.len()), format!("isolated {}", a.vertices.len() - 1 - used.len()), format!("min {}", counts.first_key_value().unwrap().0), format!("max {}", counts.last_key_value().unwrap().0), format!("mean {}", fraction(total as i64, used.len() as i64))];
    lines.extend(counts.into_iter().map(|(degree, count)| format!("degree {degree} {count}")));
    lines
}

fn query(a: &Analysis, words: &[String]) -> String {
    let values: Vec<i64> = words[1..].iter().map(|value| value.parse().unwrap()).collect();
    let valid_vertex = |value| value >= 1 && value < a.vertices.len() as i64;
    match words[0].as_str() {
        "vertex" => {
            let v = values[0];
            if !valid_vertex(v) { return format!("vertex {v} invalid"); }
            let vertex = v as usize;
            let faces = a.faces.iter().filter(|face| face.vertices.contains(&vertex)).count();
            let boundary = a.topology.edges.iter().any(|(&(u, w), members)| (u == vertex || w == vertex) && members.len() == 1);
            let components: Vec<_> = a.topology.components.iter().enumerate().filter(|(_, component)| component.vertices.contains(&vertex)).map(|(i, _)| i + 1).collect();
            format!("vertex {v} at {} faces {} valence {} fans {} boundary {} components {}", vector(a.vertices[vertex]), faces, a.topology.degree(vertex), a.topology.fans[vertex].len(), yes(boundary), list(&components))
        }
        "face" => {
            let f = values[0];
            if f < 1 || f > a.faces.len() as i64 { return format!("face {f} invalid"); }
            let index = f as usize - 1;
            let face = &a.faces[index];
            let polygon = face.polygon.map_or_else(|| "-".into(), |p| (p + 1).to_string());
            let line = face.polygon.map_or_else(|| "-".into(), |p| a.model.polygons[p].line.to_string());
            let neighbors: Vec<_> = face_edges(face).iter().map(|edge| {
                let members = &a.topology.edges[edge];
                match members.len() { 1 => "-".into(), 2 => (members.iter().find(|&&member| member != index).unwrap() + 1).to_string(), _ => "*".into() }
            }).collect();
            format!("face {f} vertices {} group {} polygon {} line {} component {} normal {} area {} neighbors {}", list(&face.vertices), face.group, polygon, line, a.topology.face_component[index] + 1, vector(normal(face, &a.vertices)), real(area(&a.faces, &[index], &a.vertices)), neighbors.join(" "))
        }
        "edge" => {
            let (u, v) = (values[0].min(values[1]), values[0].max(values[1]));
            let edge = (u as usize, v as usize);
            let Some(members) = a.topology.edges.get(&edge) else { return format!("edge {u} {v} none"); };
            let kind = match members.len() { 1 => "boundary", 2 => "manifold", _ => "nonmanifold" };
            format!("edge {u} {v} faces {} kind {} shape {} len2 {}", face_list(members), kind, edge_shape(&a.faces, &a.vertices, edge, members), length2(a.vertices[edge.0], a.vertices[edge.1]))
        }
        "point" => {
            let point = [values[0], values[1], values[2]];
            let mut inside = Vec::new();
            let mut total = 0;
            for (i, _) in a.properties.iter().enumerate().filter(|(_, p)| p.solid) {
                let w = winding(point, &a.faces, &a.topology.components[i].faces, &a.vertices);
                if w != 0 { inside.push(i + 1); total += w; }
            }
            format!("point {} inside {} winding {}", vector(point), list(&inside), total)
        }
        "path" => {
            let (u, v) = (values[0], values[1]);
            if !valid_vertex(u) || !valid_vertex(v) { return format!("path {u} {v} invalid"); }
            let mut parents = vec![None; a.vertices.len()];
            parents[u as usize] = Some(u as usize);
            let mut queue = VecDeque::from([u as usize]);
            while let Some(w) = queue.pop_front() {
                let neighbors: BTreeSet<_> = a.topology.edges.keys().filter_map(|&(x, y)| if x == w { Some(y) } else if y == w { Some(x) } else { None }).collect();
                for y in neighbors { if parents[y].is_none() { parents[y] = Some(w); queue.push_back(y); } }
            }
            if parents[v as usize].is_none() { return format!("path {u} {v} none"); }
            let mut path = vec![v as usize];
            while *path.last().unwrap() != u as usize { path.push(parents[*path.last().unwrap()].unwrap()); }
            path.reverse();
            format!("path {u} {v} hops {} vertices {}", path.len() - 1, list(&path))
        }
        "view" => {
            let direction = [values[0], values[1], values[2]];
            let signs: Vec<_> = a.faces.iter().map(|face| dot(normal(face, &a.vertices), direction)).collect();
            let silhouette = a.topology.edges.values().filter(|members| members.len() == 2 && signs[members[0]].signum() * signs[members[1]].signum() == -1).count();
            format!("view {} front {} back {} side {} silhouette {}", vector(direction), signs.iter().filter(|&&s| s > 0).count(), signs.iter().filter(|&&s| s < 0).count(), signs.iter().filter(|&&s| s == 0).count(), silhouette)
        }
        _ => unreachable!(),
    }
}

fn main() {
    let params = Params::read();
    let analysis = analyze(&params);
    let mut report = Vec::new();
    for section in &params.sections {
        report.extend(match section.as_str() {
            "summary" => summary(&analysis),
            "warnings" => std::iter::once("[warnings]".into()).chain(analysis.model.errors.iter().map(|(line, error)| format!("line {line} {error}"))).collect(),
            "cleanup" => cleanup(&analysis), "components" => component_lines(&analysis), "groups" => group_lines(&analysis),
            "contacts" => contacts(&analysis), "edges" => edges(&analysis), "valence" => valence(&analysis),
            "queries" => std::iter::once("[queries]".into()).chain(params.queries.iter().map(|words| query(&analysis, words))).collect(),
            _ => unreachable!(),
        });
    }
    let mut csv = vec!["component,faces,vertices,closed,euler,genus,volume6,area".into()];
    for (i, (component, p)) in analysis.topology.components.iter().zip(&analysis.properties).enumerate() {
        csv.push(format!("{},{},{},{},{},{},{},{}", i + 1, component.faces.len(), component.vertices.len(), yes(p.closed), p.euler, p.genus.map_or_else(|| "-".into(), |g| g.to_string()), if p.solid { p.volume.to_string() } else { "-".into() }, real(p.area)));
    }
    fs::create_dir_all("output").unwrap();
    for (name, lines) in [("report.txt", report), ("components.csv", csv), ("boundaries.txt", analysis.boundaries)] {
        fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { format!("{}\n", lines.join("\n")) }).unwrap();
    }
    obj_io::write(&analysis.vertices, &analysis.faces);
}
