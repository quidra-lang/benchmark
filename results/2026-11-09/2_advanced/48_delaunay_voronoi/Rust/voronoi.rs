use crate::{predicates::{self, Point}, triangulation::Triangulation};

pub fn radius2(a: Point, b: Point, c: Point) -> f64 {
    let area = predicates::orient(a, b, c);
    let l1 = predicates::d2(a, b);
    let l2 = predicates::d2(b, c);
    let l3 = predicates::d2(c, a);
    ((l1 as f64 * l2 as f64) * l3 as f64) / ((4.0 * area as f64) * area as f64)
}

pub fn position(center: (i64, i64, i64), points: &[Point], hull: &[usize]) -> &'static str {
    let (x, y, d) = center;
    let mut zero = false;
    for t in 0..hull.len() {
        let a = points[hull[t]];
        let b = points[hull[(t + 1) % hull.len()]];
        let sigma = (b.0 - a.0) * (y - a.1 * d) - (b.1 - a.1) * (x - a.0 * d);
        if sigma < 0 { return "outside"; }
        if sigma == 0 { zero = true; }
    }
    if zero { "on" } else { "inside" }
}

pub fn neighbors(s: usize, triangulation: &Triangulation, hull: &[usize]) -> Vec<usize> {
    let first = if let Some(j) = hull.iter().position(|&u| u == s) {
        hull[(j + 1) % hull.len()]
    } else {
        *triangulation.directed.keys().filter(|&&(u, _)| u == s).map(|(_, v)| v).min().unwrap()
    };
    let mut result = vec![first];
    let mut current = first;
    while let Some(&next) = triangulation.directed.get(&(s, current)) {
        if next == first { break; }
        result.push(next);
        current = next;
    }
    result
}

pub fn outward(a: Point, b: Point) -> Point {
    predicates::direction(a, b)
}

pub fn bounded_area(s: Point, vertices: &[(i64, i64, i64)]) -> f64 {
    let positions: Vec<(f64, f64)> = vertices.iter().map(|&(x, y, d)| (x as f64 / d as f64 - s.0 as f64, y as f64 / d as f64 - s.1 as f64)).collect();
    let mut area = 0.0;
    for j in 0..positions.len() {
        let (x, y) = positions[j];
        let (u, v) = positions[(j + 1) % positions.len()];
        area += x * v - u * y;
    }
    area / 2.0
}

pub fn clipped_area(s: usize, neighbors: &[usize], points: &[Point]) -> f64 {
    let mut polygon = vec![(0.0, 0.0), (1000.0, 0.0), (1000.0, 1000.0), (0.0, 1000.0)];
    let (sx, sy) = points[s];
    for &t in neighbors {
        let (tx, ty) = points[t];
        let c1 = 2 * (tx - sx);
        let c2 = 2 * (ty - sy);
        let c3 = tx * tx + ty * ty - sx * sx - sy * sy;
        let f = |p: (f64, f64)| c1 as f64 * p.0 + c2 as f64 * p.1 - c3 as f64;
        let mut next = Vec::new();
        for i in 0..polygon.len() {
            let p = polygon[i];
            let q = polygon[(i + 1) % polygon.len()];
            let (fp, fq) = (f(p), f(q));
            if fp <= 0.0 { next.push(p); }
            if (fp < 0.0 && fq > 0.0) || (fq < 0.0 && fp > 0.0) {
                let lambda = fp / (fp - fq);
                next.push((p.0 + (q.0 - p.0) * lambda, p.1 + (q.1 - p.1) * lambda));
            }
        }
        polygon = next;
    }
    let mut area = 0.0;
    for i in 0..polygon.len() {
        let p = polygon[i];
        let q = polygon[(i + 1) % polygon.len()];
        area += p.0 * q.1 - q.0 * p.1;
    }
    area / 2.0
}
