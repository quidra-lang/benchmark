use crate::rtree::Bounds;
use std::{fs, io};

#[derive(Clone, Copy)]
pub struct Point {
    pub id: i64,
    pub x: i64,
    pub y: i64,
}

impl Point {
    pub fn bounds(self) -> Bounds {
        Bounds(self.x, self.y, self.x, self.y)
    }
}

pub struct Data {
    pub points: Vec<Point>,
    pub rectangles: Vec<(i64, Bounds)>,
    pub world: i64,
    pub bucket: usize,
    pub maximum: usize,
    pub minimum: usize,
    pub grid: i64,
    pub commands: Vec<(String, Vec<i64>)>,
}

pub fn read() -> io::Result<Data> {
    let csv = |path: &str| -> io::Result<Vec<Vec<i64>>> {
        Ok(fs::read_to_string(path)?.lines().skip(1).map(|s| s.split(',').map(|s| s.parse().unwrap()).collect()).collect())
    };
    let points = csv("input/points.csv")?.iter().map(|r| Point { id: r[0], x: r[1], y: r[2] }).collect();
    let rectangles = csv("input/rects.csv")?.iter().map(|r| (r[0], Bounds(r[1], r[2], r[3], r[4]))).collect();
    let text = fs::read_to_string("input/params.txt")?;
    let q: Vec<Vec<i64>> = text.lines().map(|s| s.split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect()).collect();
    let commands = fs::read_to_string("input/queries.txt")?.lines().map(|s| {
        let mut words = s.split_whitespace();
        (words.next().unwrap().to_owned(), words.map(|s| s.parse().unwrap()).collect())
    }).collect();
    Ok(Data { points, rectangles, world: q[0][0], bucket: q[1][0] as usize,
        maximum: q[2][0] as usize, minimum: q[2][1] as usize, grid: q[3][0], commands })
}
