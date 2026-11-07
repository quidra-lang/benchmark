mod pgm_io;
mod filters;
mod canny;
mod hough;
mod corners;

use hough::Point;
use pgm_io::Image;
use std::{collections::BTreeMap, fs, io};

fn subtract(a: Point, b: Point) -> Point {
    (a.0 - b.0, a.1 - b.1)
}

fn cross(a: Point, b: Point) -> i64 {
    a.0 * b.1 - a.1 * b.0
}

fn dot(a: Point, b: Point) -> i64 {
    a.0 * b.0 + a.1 * b.1
}

fn distance(a: Point, b: Point) -> i64 {
    (a.0 - b.0).abs().max((a.1 - b.1).abs())
}

fn angle(a: usize, b: usize) -> i64 {
    let delta = (a as i64 - b as i64).abs();
    delta.min(180 - delta)
}

fn round(mut n: i64, mut d: i64) -> i64 {
    if d < 0 { n = -n; d = -d; }
    (2 * n + d).div_euclid(2 * d)
}

fn bresenham(a: Point, b: Point) -> Vec<Point> {
    let (mut x, mut y) = a;
    let dx = (b.0 - x).abs();
    let dy = -(b.1 - y).abs();
    let sx = if x < b.0 { 1 } else { -1 };
    let sy = if y < b.1 { 1 } else { -1 };
    let mut error = dx + dy;
    let mut result = Vec::new();
    loop {
        result.push((x, y));
        if (x, y) == b { break; }
        let twice = 2 * error;
        if twice >= dy { error += dy; x += sx; }
        if twice <= dx { error += dx; y += sy; }
    }
    result
}

fn index(point: Point, width: usize, height: usize) -> Option<usize> {
    if point.0 < 0 || point.1 < 0 || point.0 >= width as i64 || point.1 >= height as i64 { None }
    else { Some(point.1 as usize * width + point.0 as usize) }
}

fn is_edge(point: Point, edges: &[bool], width: usize, height: usize) -> bool {
    index(point, width, height).map_or(false, |i| edges[i])
}

fn nearby_edge(point: Point, edges: &[bool], width: usize, height: usize) -> bool {
    (-1..=1).any(|dy| (-1..=1).any(|dx| is_edge((point.0 + dx, point.1 + dy), edges, width, height)))
}

struct Circle {
    center: Point,
    radius: i64,
    votes: i64,
    offsets: Vec<Point>,
    gap: usize,
    arcs: usize,
}

struct Line {
    theta: usize,
    rho: i64,
    votes: i64,
    segments: Vec<usize>,
}

struct Segment {
    theta: usize,
    start: Point,
    end: Point,
    pixels: usize,
}

#[derive(Clone, Copy)]
struct Junction {
    point: Point,
    first: usize,
    second: usize,
}

fn junction(a: &Segment, b: &Segment, maximum_distance: i64, minimum_angle: i64) -> Option<Junction> {
    if angle(a.theta, b.theta) < minimum_angle { return None; }
    let da = subtract(a.end, a.start);
    let db = subtract(b.end, b.start);
    let den = cross(da, db);
    if den == 0 { return None; }
    let lambda = cross(subtract(b.start, a.start), db);
    let point = (round(a.start.0 * den + lambda * da.0, den), round(a.start.1 * den + lambda * da.1, den));
    let first = if distance(a.start, point) <= distance(a.end, point) { 0 } else { 1 };
    let second = if distance(b.start, point) <= distance(b.end, point) { 0 } else { 1 };
    let pa = if first == 0 { a.start } else { a.end };
    let pb = if second == 0 { b.start } else { b.end };
    if distance(pa, point) <= maximum_distance && distance(pb, point) <= maximum_distance { Some(Junction { point, first, second }) } else { None }
}

fn connection(a: usize, b: usize, junctions: &BTreeMap<(usize, usize), Junction>) -> Option<Junction> {
    if a < b { junctions.get(&(a, b)).copied() }
    else { junctions.get(&(b, a)).map(|j| Junction { point: j.point, first: j.second, second: j.first }) }
}

struct Polygon {
    segments: Vec<usize>,
    vertices: Vec<Point>,
    sigma: i64,
    angles: Vec<i64>,
    lengths: Vec<i64>,
    supports: Vec<usize>,
    boundary: Vec<Vec<Point>>,
    kind: &'static str,
    corners: Vec<Option<usize>>,
}

fn polygon_cycles(count: usize, junctions: &BTreeMap<(usize, usize), Junction>, k: usize) -> Vec<Vec<usize>> {
    fn extend(path: &mut Vec<usize>, count: usize, junctions: &BTreeMap<(usize, usize), Junction>, k: usize, result: &mut Vec<Vec<usize>>) {
        if path.len() == k {
            if path[1] >= path[k - 1] || connection(path[k - 1], path[0], junctions).is_none() { return; }
            let mut vertices = Vec::new();
            for i in 0..k {
                let incoming = connection(path[(i + k - 1) % k], path[i], junctions).unwrap();
                let outgoing = connection(path[i], path[(i + 1) % k], junctions).unwrap();
                if incoming.second == outgoing.first { return; }
                vertices.push(incoming.point);
            }
            let signs: Vec<i64> = (0..k).map(|i| cross(subtract(vertices[(i + 1) % k], vertices[i]), subtract(vertices[(i + 2) % k], vertices[(i + 1) % k]))).collect();
            if signs.iter().all(|&z| z > 0) || signs.iter().all(|&z| z < 0) { result.push(path.clone()); }
            return;
        }
        let previous = *path.last().unwrap();
        for next in path[0] + 1..count {
            if !path.contains(&next) && connection(previous, next, junctions).is_some() {
                path.push(next);
                extend(path, count, junctions, k, result);
                path.pop();
            }
        }
    }
    let mut result = Vec::new();
    for start in 0..count { extend(&mut vec![start], count, junctions, k, &mut result); }
    result.sort();
    result
}

fn polygon(sequence: Vec<usize>, segments: &[Segment], junctions: &BTreeMap<(usize, usize), Junction>, edges: &[bool], width: usize, height: usize,
    tolerance: i64, square_tolerance: i64) -> Polygon {
    let k = sequence.len();
    let vertices: Vec<Point> = (0..k).map(|i| connection(sequence[(i + k - 1) % k], sequence[i], junctions).unwrap().point).collect();
    let mut angles = Vec::new();
    let mut lengths = Vec::new();
    let mut boundary = Vec::new();
    let mut supports = Vec::new();
    let mut sigma = 0;
    for i in 0..k {
        let previous = vertices[(i + k - 1) % k];
        let current = vertices[i];
        let next = vertices[(i + 1) % k];
        let phi = angle(segments[sequence[(i + k - 1) % k]].theta, segments[sequence[i]].theta);
        angles.push(if dot(subtract(previous, current), subtract(next, current)) < 0 { 180 - phi } else { phi });
        let delta = subtract(next, current);
        lengths.push(dot(delta, delta));
        sigma += cross(current, next);
        let side = bresenham(current, next);
        let support = side.iter().filter(|&&p| nearby_edge(p, edges, width, height)).count();
        supports.push(100 * support / side.len());
        boundary.push(side);
    }
    let kind = if k == 3 {
        if angles.iter().all(|&a| (a - 60).abs() <= tolerance) { "equilateral_triangle" }
        else if angles.iter().any(|&a| (a - 90).abs() <= tolerance) { "right_triangle" } else { "triangle" }
    } else {
        let first = angle(segments[sequence[0]].theta, segments[sequence[2]].theta) <= tolerance;
        let second = angle(segments[sequence[1]].theta, segments[sequence[3]].theta) <= tolerance;
        if !first && !second { "quadrilateral" } else if first != second { "trapezoid" }
        else if angles.iter().any(|&a| (a - 90).abs() > tolerance) { "parallelogram" }
        else {
            let maximum = *lengths.iter().max().unwrap();
            let minimum = *lengths.iter().min().unwrap();
            if 100 * (maximum - minimum) <= square_tolerance * maximum { "square" } else { "rectangle" }
        }
    };
    Polygon { segments: sequence, vertices, sigma, angles, lengths, supports, boundary, kind, corners: vec![None; k] }
}

enum Shape<'a> {
    Polygon(&'a Polygon),
    Circle(&'a Circle),
}

impl Shape<'_> {
    fn representatives(&self) -> Vec<Point> {
        match self {
            Self::Polygon(p) => p.vertices.clone(),
            Self::Circle(c) => vec![(c.center.0 + c.radius, c.center.1), (c.center.0, c.center.1 + c.radius),
                (c.center.0 - c.radius, c.center.1), (c.center.0, c.center.1 - c.radius)],
        }
    }

    fn contains(&self, point: Point) -> bool {
        match self {
            Self::Polygon(p) => (0..p.vertices.len()).all(|i| {
                let v = cross(subtract(p.vertices[(i + 1) % p.vertices.len()], p.vertices[i]), subtract(point, p.vertices[i]));
                v == 0 || v.signum() == p.sigma.signum()
            }),
            Self::Circle(c) => {
                let delta = subtract(point, c.center);
                dot(delta, delta) <= c.radius * c.radius
            }
        }
    }

    fn explains(&self, point: Point) -> bool {
        match self {
            Self::Polygon(p) => p.boundary.iter().any(|side| side.iter().any(|&q| distance(point, q) <= 1)),
            Self::Circle(c) => {
                let delta = subtract(point, c.center);
                let squared = dot(delta, delta);
                (c.radius - 1) * (c.radius - 1) <= squared && squared <= (c.radius + 1) * (c.radius + 1)
            }
        }
    }
}

struct Measurement {
    pixels: usize,
    mean: i64,
    contrast: i64,
    enclosing: Option<usize>,
}

fn measure(shape: &Shape, image: &Image, margin: i64) -> Measurement {
    let representatives = shape.representatives();
    let xmin = (representatives.iter().map(|p| p.0).min().unwrap() - margin).max(0);
    let xmax = (representatives.iter().map(|p| p.0).max().unwrap() + margin).min(image.width as i64 - 1);
    let ymin = (representatives.iter().map(|p| p.1).min().unwrap() - margin).max(0);
    let ymax = (representatives.iter().map(|p| p.1).max().unwrap() + margin).min(image.height as i64 - 1);
    let (mut inside, mut outside, mut inner_sum, mut outer_sum) = (0usize, 0usize, 0i64, 0i64);
    for y in ymin..=ymax {
        for x in xmin..=xmax {
            let value = image.pixels[y as usize * image.width + x as usize];
            if shape.contains((x, y)) { inside += 1; inner_sum += value; }
            else { outside += 1; outer_sum += value; }
        }
    }
    let mean = if inside == 0 { 0 } else { inner_sum.div_euclid(inside as i64) };
    let outer = if outside == 0 { 0 } else { outer_sum.div_euclid(outside as i64) };
    Measurement { pixels: inside, mean, contrast: mean - outer, enclosing: None }
}

fn shape_name(index: Option<usize>, polygons: usize) -> String {
    index.map_or("none".into(), |i| if i < polygons { format!("polygon {}", i + 1) } else { format!("circle {}", i - polygons + 1) })
}

fn main() -> io::Result<()> {
    let input = pgm_io::read()?;
    let image = &input.image;
    let (w, h) = (image.width, image.height);
    let p: Vec<i64> = input.params.iter().map(|v| v[0]).collect();
    let smoothed = filters::smooth(image, p[0] as usize, &input.params[1], p[2]);
    let (gx, gy, magnitude) = filters::gradient(&smoothed, w, h);
    let directions = canny::directions(&gx, &gy);
    let nms = canny::suppress(&magnitude, &directions, w, h);
    let edges = canny::hysteresis(&nms, w, h, p[3], p[4]);
    let components = canny::components(&edges, w, h);
    let edge_points: Vec<Point> = (0..w * h).filter(|&i| edges[i]).map(|i| ((i % w) as i64, (i / w) as i64)).collect();
    let circle_votes = hough::circle_votes(&edge_points, p[5], p[6], w, h);
    let (circle_candidates, circle_peaks) = hough::circle_peaks(&circle_votes, p[7]);
    let mut circles = Vec::new();
    for &(k, i) in circle_peaks.iter().take(p[8] as usize) {
        let center = ((i % w) as i64, (i / w) as i64);
        let mut offsets = circle_votes.points[k].clone();
        let half = |point: Point| if point.1 > 0 || (point.1 == 0 && point.0 > 0) { 0 } else { 1 };
        offsets.sort_by(|&a, &b| half(a).cmp(&half(b)).then_with(|| cross(b, a).cmp(&0)).then(a.cmp(&b)));
        let hits: Vec<bool> = offsets.iter().map(|&(dx, dy)| is_edge((center.0 + dx, center.1 + dy), &edges, w, h)).collect();
        let mut gap = 0;
        if let Some(start) = hits.iter().position(|&hit| hit) {
            let mut length = 0;
            for j in 1..=hits.len() {
                if hits[(start + j) % hits.len()] { length = 0; } else { length += 1; gap = gap.max(length); }
            }
        } else { gap = hits.len(); }
        let arcs = if hits.iter().all(|&hit| hit) { 1 } else { (0..hits.len()).filter(|&j| hits[j] && !hits[(j + hits.len() - 1) % hits.len()]).count() };
        circles.push(Circle { center, radius: circle_votes.minimum + k as i64, votes: circle_votes.votes[k][i], offsets, gap, arcs });
    }
    let circle_shapes: Vec<Shape> = circles.iter().map(Shape::Circle).collect();
    let circle_edge_pixels = edge_points.iter().filter(|&&point| circle_shapes.iter().any(|s| s.explains(point))).count();
    let line_points: Vec<Point> = edge_points.iter().copied().filter(|&point| !circle_shapes.iter().any(|s| s.explains(point))).collect();
    let votes = hough::line_votes(&line_points, &input.trig, p[9]);
    let line_peaks = hough::line_peaks(&votes, p[10]);
    let mut lines = Vec::new();
    let mut segments = Vec::new();
    let mut claimed = vec![false; w * h];
    for &(theta, radius, count) in &line_peaks {
        if lines.len() == p[11] as usize { break; }
        let mut candidates: Vec<(i64, Point)> = line_points.iter().copied().filter(|&point| !claimed[index(point, w, h).unwrap()]
            && (hough::rho(point, theta, &input.trig, p[9]) - radius).abs() <= p[12])
            .map(|point| (point.1 * input.trig[theta].0 - point.0 * input.trig[theta].1, point)).collect();
        candidates.sort_by_key(|&(u, point)| (u, point.0, point.1));
        let mut groups: Vec<Vec<Point>> = Vec::new();
        let mut previous = None;
        for (u, point) in candidates {
            if previous.map_or(true, |before| u - before > p[13] * 16384) { groups.push(Vec::new()); }
            groups.last_mut().unwrap().push(point);
            previous = Some(u);
        }
        let mut selected = Vec::new();
        for group in groups {
            let start = group[0];
            let end = *group.last().unwrap();
            if distance(start, end) + 1 < p[14] { continue; }
            selected.push(segments.len());
            segments.push(Segment { theta, start, end, pixels: group.len() });
            for point in group { claimed[index(point, w, h).unwrap()] = true; }
        }
        if !selected.is_empty() { lines.push(Line { theta, rho: radius, votes: count, segments: selected }); }
    }
    let mut junctions = BTreeMap::new();
    for i in 0..segments.len() {
        for j in i + 1..segments.len() {
            if let Some(junction) = junction(&segments[i], &segments[j], p[15], p[16]) { junctions.insert((i, j), junction); }
        }
    }
    let mut polygons = Vec::new();
    for k in [3, 4] {
        for sequence in polygon_cycles(segments.len(), &junctions, k) {
            polygons.push(polygon(sequence, &segments, &junctions, &edges, w, h, p[17], p[18]));
        }
    }
    let (response, corner_candidates) = corners::detect(&gx, &gy, w, h, p[20], p[21]);
    let corner_indices: Vec<usize> = corner_candidates.iter().copied().take(p[22] as usize).collect();
    let corner_points: Vec<Point> = corner_indices.iter().map(|&i| ((i % w) as i64, (i / w) as i64)).collect();
    let mut corner_matches = Vec::new();
    let mut on_vertices = 0;
    let mut on_segments = 0;
    for &corner in &corner_points {
        let mut vertices = Vec::new();
        for (i, polygon) in polygons.iter().enumerate() {
            for (j, &vertex) in polygon.vertices.iter().enumerate() {
                let d = distance(corner, vertex);
                if d <= p[23] { vertices.push((d, i, j)); }
            }
        }
        if let Some(&(_, i, j)) = vertices.iter().min() {
            corner_matches.push(format!("polygon {} vertex {}", i + 1, j + 1));
            on_vertices += 1;
        } else {
            let mut ends = Vec::new();
            for (j, segment) in segments.iter().enumerate() {
                for (k, point) in [segment.start, segment.end].iter().enumerate() {
                    let d = distance(corner, *point);
                    if d <= p[23] { ends.push((d, j, k)); }
                }
            }
            if let Some(&(_, j, k)) = ends.iter().min() { corner_matches.push(format!("segment {} {}", j + 1, if k == 0 { "start" } else { "end" })); on_segments += 1; }
            else { corner_matches.push("none".into()); }
        }
    }
    let mut vertices_with_corner = 0;
    for polygon in &mut polygons {
        for (j, &vertex) in polygon.vertices.iter().enumerate() {
            let candidate = corner_points.iter().enumerate().map(|(i, &point)| (distance(vertex, point), i)).filter(|&(d, _)| d <= p[23]).min();
            if let Some((_, i)) = candidate { polygon.corners[j] = Some(i); vertices_with_corner += 1; }
        }
    }
    let shapes: Vec<Shape> = polygons.iter().map(Shape::Polygon).chain(circles.iter().map(Shape::Circle)).collect();
    let mut measurements: Vec<Measurement> = shapes.iter().map(|s| measure(s, image, p[19])).collect();
    for i in 0..shapes.len() {
        let representatives = shapes[i].representatives();
        let parent = (0..shapes.len()).filter(|&j| i != j && measurements[j].pixels > measurements[i].pixels && representatives.iter().all(|&p| shapes[j].contains(p)))
            .min_by_key(|&j| (measurements[j].pixels, j));
        measurements[i].enclosing = parent;
    }
    let mut line_output = vec![format!("lines {}", lines.len())];
    for (i, line) in lines.iter().enumerate() {
        line_output.push(format!("line {} theta {} rho {} votes {} segments {}", i + 1, line.theta, line.rho, line.votes, line.segments.len()));
        for &j in &line.segments {
            let segment = &segments[j];
            line_output.push(format!("segment {} start {} {} end {} {} length {} pixels {}", j + 1, segment.start.0, segment.start.1, segment.end.0, segment.end.1,
                distance(segment.start, segment.end) + 1, segment.pixels));
        }
    }
    let mut circle_output = vec![format!("circles {}", circles.len())];
    for (j, circle) in circles.iter().enumerate() {
        let m = &measurements[polygons.len() + j];
        circle_output.push(format!("circle {} center {} {} radius {} votes {} points {} gap {} arcs {} pixels {} mean {} contrast {} inside {}", j + 1,
            circle.center.0, circle.center.1, circle.radius, circle.votes, circle.offsets.len(), circle.gap, circle.arcs, m.pixels, m.mean, m.contrast, shape_name(m.enclosing, polygons.len())));
    }
    let mut polygon_output = vec![format!("polygons {}", polygons.len())];
    for (j, polygon) in polygons.iter().enumerate() {
        let m = &measurements[j];
        polygon_output.push(format!("polygon {} {} segments {} area {}.{} pixels {} mean {} contrast {} inside {}", j + 1, polygon.kind,
            polygon.segments.iter().map(|i| (i + 1).to_string()).collect::<Vec<_>>().join(" "), polygon.sigma.abs() / 2, if polygon.sigma.abs() % 2 == 0 { 0 } else { 5 },
            m.pixels, m.mean, m.contrast, shape_name(m.enclosing, polygons.len())));
        for i in 0..polygon.vertices.len() {
            polygon_output.push(format!("vertex {} {} {} angle {} corner {}", i + 1, polygon.vertices[i].0, polygon.vertices[i].1, polygon.angles[i],
                polygon.corners[i].map_or("none".into(), |c| (c + 1).to_string())));
        }
        for i in 0..polygon.segments.len() {
            polygon_output.push(format!("side {} segment {} length2 {} support {}", i + 1, polygon.segments[i] + 1, polygon.lengths[i], polygon.supports[i]));
        }
    }
    let mut corner_output = vec![format!("corners {}", corner_indices.len())];
    for (j, &i) in corner_indices.iter().enumerate() { corner_output.push(format!("corner {} {} {} response {} match {}", j + 1, i % w, i / w, response[i], corner_matches[j])); }
    let mut component_output = vec![format!("components {}", components.len())];
    for (j, component) in components.iter().enumerate() {
        let minimum_x = component.iter().map(|i| i % w).min().unwrap();
        let maximum_x = component.iter().map(|i| i % w).max().unwrap();
        let minimum_y = component.iter().map(|i| i / w).min().unwrap();
        let maximum_y = component.iter().map(|i| i / w).max().unwrap();
        let ends = component.iter().filter(|&&i| canny::neighbors(i, w, h).iter().filter(|&&k| edges[k]).count() == 1).count();
        let strength = component.iter().map(|&i| magnitude[i]).sum::<i64>().div_euclid(component.len() as i64);
        let mut counts = [0usize; 4];
        for &i in component { counts[(directions[i] / 45) as usize] += 1; }
        let mut main_direction = 0;
        for i in 1..4 { if counts[i] > counts[main_direction] { main_direction = i; } }
        let mut maximum = 0;
        let mut matched = None;
        for (i, shape) in shapes.iter().enumerate() {
            let count = component.iter().filter(|&&i| shape.explains(((i % w) as i64, (i / w) as i64))).count();
            if count > maximum { maximum = count; matched = Some(i); }
        }
        component_output.push(format!("component {} pixels {} box {} {} {} {} ends {} strength {} direction {} shape {} explained {}", j + 1, component.len(),
            minimum_x, minimum_y, maximum_x, maximum_y, ends, strength, main_direction * 45, shape_name(matched, polygons.len()), maximum));
    }
    let corners_of_image = [(0, 0), (w as i64 - 1, 0), (0, h as i64 - 1), (w as i64 - 1, h as i64 - 1)];
    let mut rlo = i64::MAX;
    let mut rhi = i64::MIN;
    for point in corners_of_image {
        for t in 0..180 {
            let r = hough::rho(point, t, &input.trig, p[9]);
            rlo = rlo.min(r);
            rhi = rhi.max(r);
        }
    }
    let maximum_votes = votes.values().copied().max().unwrap_or(0);
    let mut vote_pixels = Vec::new();
    for r in rlo..=rhi {
        for theta in 0..180 {
            vote_pixels.push(if maximum_votes == 0 { 0 } else { 255 * votes.get(&(theta, r)).copied().unwrap_or(0) / maximum_votes });
        }
    }
    let mut overlay: Vec<i64> = image.pixels.iter().map(|i| i.div_euclid(p[24])).collect();
    let mut draw = |point| if let Some(i) = index(point, w, h) { overlay[i] = 255; };
    for segment in &segments { for point in bresenham(segment.start, segment.end) { draw(point); } }
    for circle in &circles { for &(dx, dy) in &circle.offsets { draw((circle.center.0 + dx, circle.center.1 + dy)); } }
    for &(x, y) in &corner_points { for e in -2..=2 { draw((x + e, y)); draw((x, y + e)); } }
    let strong = nms.iter().filter(|&&n| n >= p[4]).count();
    let weak = nms.iter().filter(|&&n| n >= p[3] && n < p[4]).count();
    let weak_kept = (0..w * h).filter(|&i| edges[i] && nms[i] >= p[3] && nms[i] < p[4]).count();
    let mut report = vec![format!("image {} {}", w, h)];
    for (name, value) in [("gradient_nonzero", magnitude.iter().filter(|&&m| m > 0).count()), ("gradient_max", *magnitude.iter().max().unwrap() as usize),
        ("nms_kept", nms.iter().filter(|&&n| n > 0).count()), ("strong", strong), ("weak", weak), ("edges", edge_points.len()), ("weak_kept", weak_kept),
        ("weak_dropped", weak - weak_kept), ("edge_components", components.len())] { report.push(format!("{} {}", name, value)); }
    for direction in [0, 45, 90, 135] { report.push(format!("direction_{} {}", direction, (0..w * h).filter(|&i| edges[i] && directions[i] == direction).count())); }
    for (name, value) in [("circle_candidates", circle_candidates), ("circle_peaks", circle_peaks.len()), ("circles", circles.len()), ("circle_edge_pixels", circle_edge_pixels),
        ("line_edge_pixels", line_points.len()), ("hough_max_votes", maximum_votes as usize), ("hough_peaks", line_peaks.len()), ("lines", lines.len()),
        ("segments", segments.len()), ("claimed_pixels", claimed.iter().filter(|&&c| c).count()), ("junctions", junctions.len()), ("polygons", polygons.len())] { report.push(format!("{} {}", name, value)); }
    for kind in ["equilateral_triangle", "right_triangle", "triangle", "square", "rectangle", "parallelogram", "trapezoid", "quadrilateral"] {
        report.push(format!("{} {}", kind, polygons.iter().filter(|p| p.kind == kind).count()));
    }
    for (name, value) in [("corner_candidates", corner_candidates.len()), ("corners", corner_indices.len()), ("corners_on_vertices", on_vertices), ("corners_on_segments", on_segments),
        ("corners_unmatched", corner_indices.len() - on_vertices - on_segments), ("vertices_with_corner", vertices_with_corner)] { report.push(format!("{} {}", name, value)); }
    fs::create_dir_all("output")?;
    pgm_io::write("edges.pgm", &Image { width: w, height: h, pixels: edges.iter().map(|&e| if e { 255 } else { 0 }).collect() })?;
    pgm_io::write("hough.pgm", &Image { width: 180, height: (rhi - rlo + 1) as usize, pixels: vote_pixels })?;
    pgm_io::write("overlay.pgm", &Image { width: w, height: h, pixels: overlay })?;
    for (name, lines) in [("lines.txt", line_output), ("circles.txt", circle_output), ("polygons.txt", polygon_output), ("corners.txt", corner_output),
        ("components.txt", component_output), ("report.txt", report)] {
        fs::write(format!("output/{}", name), lines.join("\n") + "\n")?;
    }
    Ok(())
}
