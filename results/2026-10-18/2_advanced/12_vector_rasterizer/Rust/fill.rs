use std::collections::BTreeMap;
use crate::canvas::Layer;
use crate::clipping::Rect;
use crate::primitives::{Pixels, Point};

pub fn fill_polygons(sequences: &[Vec<Point>], rule: &str, clip: Rect) -> Pixels {
    let mut edges = Vec::new();
    for vertices in sequences {
        for (i, &start) in vertices.iter().enumerate() { let end = vertices[(i + 1) % vertices.len()]; if start.1 != end.1 { edges.push((start, end)); } }
    }
    let mut pixels = Pixels::new();
    for y in clip[1]..=clip[3] {
        let mut crossings = Vec::new();
        for &((xa, ya), (xb, yb)) in &edges {
            if y < ya.min(yb) || y >= ya.max(yb) { continue; }
            let mut d = yb - ya;
            let mut n = 2 * xa * d + (2 * y + 1 - 2 * ya) * (xb - xa);
            let direction = if d > 0 { 1 } else { -1 };
            if d < 0 { n = -n; d = -d; }
            crossings.push(((n - d).div_euclid(2 * d) + 1, direction));
        }
        crossings.sort_unstable();
        let (mut count, mut wind, mut index) = (0, 0, 0);
        for x in clip[0]..=clip[2] {
            while index < crossings.len() && crossings[index].0 <= x { count += 1; wind += crossings[index].1; index += 1; }
            let filled = if rule == "evenodd" { count % 2 != 0 } else { wind != 0 };
            if filled { pixels.insert((x, y)); }
        }
    }
    pixels
}
pub fn fill_shape((cx, cy): Point, points: &Pixels, clip: Rect) -> Pixels {
    let mut extents: BTreeMap<i64, i64> = BTreeMap::new();
    for &(dx, dy) in points { let extent = extents.entry(dy).or_default(); *extent = (*extent).max(dx.abs()); }
    let mut pixels = Pixels::new();
    for (dy, extent) in extents { let y = cy + dy; if y < clip[1] || y > clip[3] { continue; } for x in clip[0].max(cx - extent)..=clip[2].min(cx + extent) { pixels.insert((x, y)); } }
    pixels
}
pub fn flood_fill(layer: &Layer, seed: Point, clip: Rect) -> Pixels {
    let target = layer.colors[seed.1 as usize][seed.0 as usize];
    let mut pixels = Pixels::from([seed]);
    let mut pending = vec![seed];
    while let Some((x, y)) = pending.pop() {
        for p in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
            if pixels.contains(&p) || p.0 < clip[0] || p.0 > clip[2] || p.1 < clip[1] || p.1 > clip[3] { continue; }
            if layer.colors[p.1 as usize][p.0 as usize] == target { pixels.insert(p); pending.push(p); }
        }
    }
    pixels
}
