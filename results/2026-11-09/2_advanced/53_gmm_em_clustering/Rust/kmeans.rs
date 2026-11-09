use crate::gaussian::Point;

pub fn squared(a: Point, b: Point) -> f64 {
    (a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1)
}

pub fn distance(a: Point, b: Point) -> f64 {
    squared(a, b).sqrt()
}

fn assign(points: &[Point], centers: &[Point]) -> Vec<usize> {
    points.iter().map(|&point| {
        let mut best = 0;
        let mut minimum = squared(point, centers[0]);
        for j in 1..centers.len() {
            let d = squared(point, centers[j]);
            if d < minimum { best = j; minimum = d; }
        }
        best
    }).collect()
}

pub struct Partition {
    pub centers: Vec<Point>,
    pub assignment: Vec<usize>,
    pub iterations: usize,
    pub inertia: f64,
}

pub fn fit(points: &[Point], initial: &[Point], maximum: usize) -> Partition {
    let mut centers = initial.to_vec();
    let mut assignment = assign(points, &centers);
    let mut iterations = 0;
    for t in 1..=maximum {
        for j in 0..centers.len() {
            let selected: Vec<Point> = points.iter().enumerate().filter(|(i, _)| assignment[*i] == j).map(|(_, &p)| p).collect();
            if !selected.is_empty() {
                centers[j] = (selected.iter().map(|p| p.0).sum::<f64>() / selected.len() as f64,
                    selected.iter().map(|p| p.1).sum::<f64>() / selected.len() as f64);
            }
        }
        let next = assign(points, &centers);
        iterations = t;
        let unchanged = next == assignment;
        assignment = next;
        if unchanged { break; }
    }
    let inertia = points.iter().zip(&assignment).map(|(&p, &j)| squared(p, centers[j])).sum();
    Partition { centers, assignment, iterations, inertia }
}
