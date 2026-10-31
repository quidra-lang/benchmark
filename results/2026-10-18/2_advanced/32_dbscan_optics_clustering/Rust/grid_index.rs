use std::collections::BTreeMap;
use crate::dataset::Point;

pub fn distance(a: &Point, b: &Point) -> i64 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    dx * dx + dy * dy
}

pub struct Grid {
    pub radius: i64,
    pub cells: BTreeMap<(i64, i64), Vec<usize>>,
    pub neighborhoods: Vec<Vec<usize>>,
    pub candidates: usize,
    pub busiest: (i64, i64, usize),
    pub pairs: usize,
    pub brute_pairs: usize,
    pub consistent: bool,
    pub occupancy: BTreeMap<usize, usize>,
}

impl Grid {
    pub fn new(points: &[Point], radius: i64) -> Self {
        let mut cells: BTreeMap<(i64, i64), Vec<usize>> = BTreeMap::new();
        for (i, point) in points.iter().enumerate() {
            cells.entry((point.x / radius, point.y / radius)).or_default().push(i);
        }
        let mut neighborhoods = Vec::new();
        let mut candidates = 0;
        let mut brute_total = 0;
        let mut consistent = true;
        for point in points {
            let gx = point.x / radius;
            let gy = point.y / radius;
            let mut neighbors = Vec::new();
            for row in gy - 1..=gy + 1 {
                for column in gx - 1..=gx + 1 {
                    if let Some(members) = cells.get(&(column, row)) {
                        for &j in members {
                            candidates += 1;
                            if distance(point, &points[j]) <= radius * radius {
                                neighbors.push(j);
                            }
                        }
                    }
                }
            }
            let brute = points.iter().filter(|other| distance(point, other) <= radius * radius).count();
            consistent &= brute == neighbors.len();
            brute_total += brute;
            neighborhoods.push(neighbors);
        }
        let (cell, members) = cells.iter().min_by_key(|entry| {
            (std::cmp::Reverse(entry.1.len()), entry.0.1, entry.0.0)
        }).unwrap();
        let busiest = (cell.0, cell.1, members.len());
        let mut occupancy = BTreeMap::new();
        for members in cells.values() {
            *occupancy.entry(members.len()).or_insert(0) += 1;
        }
        let total: usize = neighborhoods.iter().map(Vec::len).sum();
        Self {
            radius, cells, neighborhoods, candidates, busiest,
            pairs: (total - points.len()) / 2,
            brute_pairs: (brute_total - points.len()) / 2,
            consistent, occupancy,
        }
    }
}
