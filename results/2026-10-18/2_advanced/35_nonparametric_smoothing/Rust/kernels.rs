use crate::dataset::Point;

pub fn estimate(points: &[Point], position: i64, bandwidth: i64, kernel: &str, local_linear: bool) -> Option<(f64, Vec<f64>)> {
    let x0 = position as f64 / 100.0;
    let h = bandwidth as f64 / 100.0;
    let mut rows = Vec::new();
    let (mut s0, mut s1, mut s2, mut t0, mut t1) = (0.0, 0.0, 0.0, 0.0, 0.0);
    for (i, point) in points.iter().enumerate() {
        if (point.x - position).abs() >= bandwidth { continue; }
        let d = point.x as f64 / 100.0 - x0;
        let u = d / h;
        let t = 1.0 - u * u;
        let weight = match kernel { "epanechnikov" => 0.75 * t, "biweight" => 0.9375 * t * t, _ => 1.09375 * t * t * t };
        let y = point.y as f64 / 100.0;
        s0 += weight;
        s1 += weight * d;
        s2 += weight * d * d;
        t0 += weight * y;
        t1 += weight * d * y;
        rows.push((i, d, weight));
    }
    if rows.is_empty() || (local_linear && rows.len() < 2) { return None; }
    let mut weights = vec![0.0; points.len()];
    let value = if local_linear {
        let q = s0 * s2 - s1 * s1;
        for &(i, d, k) in &rows { weights[i] = k * (s2 - s1 * d) / q; }
        (s2 * t0 - s1 * t1) / q
    } else {
        for &(i, _, k) in &rows { weights[i] = k / s0; }
        t0 / s0
    };
    Some((value, weights))
}
