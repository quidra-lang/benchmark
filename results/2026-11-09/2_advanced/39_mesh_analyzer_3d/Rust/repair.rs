use crate::measure::{normal, Point};
use crate::obj_io::{Face, Polygon};
use std::collections::{BTreeMap, BTreeSet};

pub fn triangles(polygons: &[Polygon]) -> Vec<Face> {
    let mut faces = Vec::new();
    for (index, polygon) in polygons.iter().enumerate() {
        for i in 1..polygon.vertices.len() - 1 { faces.push(Face { vertices: [polygon.vertices[0], polygon.vertices[i], polygon.vertices[i + 1]], polygon: Some(index), group: polygon.group.clone() }); }
    }
    faces
}

pub fn snap(vertices: &[Point], spacing: i64) -> Vec<Point> {
    vertices.iter().map(|point| point.map(|x| spacing * (2 * x + spacing).div_euclid(2 * spacing))).collect()
}

pub fn representatives(vertices: &[Point], merge: bool) -> Vec<usize> {
    let mut first = BTreeMap::new();
    let mut representatives = vec![0; vertices.len()];
    for (i, point) in vertices.iter().enumerate().skip(1) {
        representatives[i] = if merge { *first.entry(*point).or_insert(i) } else { i };
    }
    representatives
}

pub fn clean(triangles: &[Face], vertices: &[Point], representatives: &[usize], degenerate: bool, duplicates: bool) -> (Vec<Face>, Vec<(usize, &'static str)>) {
    let mut faces = Vec::new();
    let mut removed = Vec::new();
    let mut seen = BTreeSet::new();
    for (i, triangle) in triangles.iter().enumerate() {
        let mut face = triangle.clone();
        face.vertices = face.vertices.map(|v| representatives[v]);
        let [a, b, c] = face.vertices;
        let mut key = face.vertices;
        key.sort_unstable();
        let reason = if a == b || b == c || c == a { Some("repeated") }
            else if degenerate && normal(&face, vertices) == [0; 3] { Some("zero_area") }
            else if duplicates && seen.contains(&key) { Some("duplicate") } else { None };
        if let Some(reason) = reason { removed.push((i + 1, reason)); }
        else { seen.insert(key); faces.push(face); }
    }
    (faces, removed)
}

pub fn fill(vertices: &[usize]) -> Vec<Face> {
    (1..vertices.len() - 1).map(|i| Face { vertices: [vertices[0], vertices[i + 1], vertices[i]], polygon: None, group: "fill".into() }).collect()
}
