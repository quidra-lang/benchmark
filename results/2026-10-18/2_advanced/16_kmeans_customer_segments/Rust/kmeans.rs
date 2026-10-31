use crate::features::Point;

pub fn squared_distance(first: &[f64], second: &[f64]) -> f64 {
    let mut total = 0.0;
    for (a, b) in first.iter().zip(second) { let difference = a - b; total += difference * difference; }
    total
}
pub fn assign(points: &[Point], centers: &[Point]) -> (Vec<usize>, Vec<f64>) {
    let mut labels = Vec::new();
    let mut errors = Vec::new();
    for point in points {
        let mut best = 0;
        let mut best_distance = squared_distance(point, &centers[0]);
        for (index, center) in centers.iter().enumerate().skip(1) {
            let distance = squared_distance(point, center);
            if distance < best_distance { best = index; best_distance = distance; }
        }
        labels.push(best);
        errors.push(best_distance);
    }
    (labels, errors)
}
pub fn mean_point(points: &[Point]) -> Point {
    let mut totals = vec![0.0; points[0].len()];
    for point in points { for (index, &value) in point.iter().enumerate() { totals[index] += value; } }
    totals.iter().map(|total| total / points.len() as f64).collect()
}
pub fn cluster_sizes(labels: &[usize], k: usize) -> Vec<usize> {
    let mut sizes = vec![0; k];
    for &label in labels { sizes[label] += 1; }
    sizes
}
pub fn cluster_center(points: &[Point], labels: &[usize], cluster: usize) -> Point {
    let members: Vec<_> = points.iter().zip(labels).filter(|(_, label)| **label == cluster).map(|(point, _)| point.clone()).collect();
    mean_point(&members)
}
pub fn cluster_centers(points: &[Point], labels: &[usize], k: usize) -> Vec<Point> {
    (0..k).map(|cluster| cluster_center(points, labels, cluster)).collect()
}
pub fn refill(labels: &mut [usize], errors: &mut [f64], k: usize) -> usize {
    let mut sizes = cluster_sizes(labels, k);
    let mut reseeds = 0;
    for cluster in 0..k {
        if sizes[cluster] > 0 { continue; }
        let mut chosen: Option<usize> = None;
        for (index, &label) in labels.iter().enumerate() {
            if sizes[label] >= 2 && chosen.is_none_or(|previous| errors[index] > errors[previous]) { chosen = Some(index); }
        }
        let index = chosen.unwrap();
        sizes[labels[index]] -= 1;
        sizes[cluster] += 1;
        labels[index] = cluster;
        errors[index] = 0.0;
        reseeds += 1;
    }
    reseeds
}
pub struct LloydResult {
    pub labels: Vec<usize>,
    pub centers: Vec<Point>,
    pub iterations: usize,
    pub converged: bool,
    pub reseeds: usize,
}
pub fn lloyd(points: &[Point], initial: &[Point], maximum: usize) -> LloydResult {
    let k = initial.len();
    let (mut labels, mut errors) = assign(points, initial);
    let mut iterations = 0;
    let mut reseeds = 0;
    let mut converged = false;
    while iterations < maximum && !converged {
        reseeds += refill(&mut labels, &mut errors, k);
        let centers = cluster_centers(points, &labels, k);
        iterations += 1;
        let (next, next_errors) = assign(points, &centers);
        converged = next == labels;
        labels = next;
        errors = next_errors;
    }
    reseeds += refill(&mut labels, &mut errors, k);
    let centers = cluster_centers(points, &labels, k);
    LloydResult { labels, centers, iterations, converged, reseeds }
}
pub fn sse(points: &[Point], labels: &[usize], centers: &[Point]) -> f64 {
    let mut total = 0.0;
    for (point, &label) in points.iter().zip(labels) { total += squared_distance(point, &centers[label]); }
    total
}
