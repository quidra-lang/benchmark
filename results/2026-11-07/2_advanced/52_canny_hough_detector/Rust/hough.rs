use std::collections::{BTreeMap, BTreeSet};

pub type Point = (i64, i64);

pub fn rho(point: Point, angle: usize, trig: &[(i64, i64)], step: i64) -> i64 {
    (point.0 * trig[angle].0 + point.1 * trig[angle].1).div_euclid(16384 * step)
}

pub fn line_votes(points: &[Point], trig: &[(i64, i64)], step: i64) -> BTreeMap<(usize, i64), i64> {
    let mut votes = BTreeMap::new();
    for &point in points {
        for angle in 0..180 { *votes.entry((angle, rho(point, angle, trig, step))).or_insert(0) += 1; }
    }
    votes
}

pub fn line_peaks(votes: &BTreeMap<(usize, i64), i64>, threshold: i64) -> Vec<(usize, i64, i64)> {
    let mut peaks = Vec::new();
    for (&(angle, radius), &count) in votes {
        if count < threshold { continue; }
        let mut peak = true;
        for a in angle as i64 - 2..=angle as i64 + 2 {
            for r in radius - 2..=radius + 2 {
                if a < 0 || a >= 180 || (a as usize, r) == (angle, radius) { continue; }
                let other = votes.get(&(a as usize, r)).copied().unwrap_or(0);
                if other > count || (other == count && (a as usize, r) < (angle, radius)) { peak = false; }
            }
        }
        if peak { peaks.push((angle, radius, count)); }
    }
    peaks.sort_by_key(|&(a, r, count)| (std::cmp::Reverse(count), a, r));
    peaks
}

pub fn circle_points(radius: i64) -> Vec<Point> {
    let (mut a, mut b, mut e) = (radius, 0, 1 - radius);
    let mut points = BTreeSet::new();
    while a >= b {
        points.extend([(a, b), (b, a), (-b, a), (-a, b), (-a, -b), (-b, -a), (b, -a), (a, -b)]);
        b += 1;
        if e < 0 { e += 2 * b + 1; } else { a -= 1; e += 2 * (b - a) + 1; }
    }
    points.into_iter().collect()
}

pub struct CircleVotes {
    pub minimum: i64,
    pub points: Vec<Vec<Point>>,
    pub votes: Vec<Vec<i64>>,
    pub width: usize,
    pub height: usize,
}

pub fn circle_votes(edges: &[Point], minimum: i64, maximum: i64, width: usize, height: usize) -> CircleVotes {
    let mut points = Vec::new();
    let mut votes = Vec::new();
    for radius in minimum..=maximum {
        let offsets = circle_points(radius);
        let mut counts = vec![0; width * height];
        for &(x, y) in edges {
            for &(dx, dy) in &offsets {
                let (a, b) = (x + dx, y + dy);
                if a >= 0 && b >= 0 && a < width as i64 && b < height as i64 { counts[b as usize * width + a as usize] += 1; }
            }
        }
        points.push(offsets);
        votes.push(counts);
    }
    CircleVotes { minimum, points, votes, width, height }
}

pub fn circle_peaks(circles: &CircleVotes, percent: i64) -> (usize, Vec<(usize, usize)>) {
    let mut candidates = 0;
    let mut peaks = Vec::new();
    for k in 0..circles.points.len() {
        for i in 0..circles.width * circles.height {
            let count = circles.votes[k][i];
            let denominator = circles.points[k].len() as i64;
            if 100 * count < percent * denominator { continue; }
            candidates += 1;
            let (x, y) = ((i % circles.width) as i64, (i / circles.width) as i64);
            let mut peak = true;
            for r in (k as i64 - 2).max(0)..=(k as i64 + 2).min(circles.points.len() as i64 - 1) {
                for b in (y - 2).max(0)..=(y + 2).min(circles.height as i64 - 1) {
                    for a in (x - 2).max(0)..=(x + 2).min(circles.width as i64 - 1) {
                        let j = b as usize * circles.width + a as usize;
                        if (r as usize, j) == (k, i) { continue; }
                        let other = circles.votes[r as usize][j];
                        let left = count * circles.points[r as usize].len() as i64;
                        let right = other * denominator;
                        if right > left || (right == left && (r as usize, j) < (k, i)) { peak = false; }
                    }
                }
            }
            if peak { peaks.push((k, i)); }
        }
    }
    peaks.sort_by(|&(a, i), &(b, j)| {
        let left = circles.votes[a][i] * circles.points[b].len() as i64;
        let right = circles.votes[b][j] * circles.points[a].len() as i64;
        right.cmp(&left).then((a, i).cmp(&(b, j)))
    });
    (candidates, peaks)
}
