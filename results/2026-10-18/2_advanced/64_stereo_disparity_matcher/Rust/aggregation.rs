use crate::{costs::Volume, pgm_io::{Image, Params}};

pub const DIRECTIONS: [(i64, i64); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (-1, 1), (1, -1)];

pub fn paths(cost: &Volume, left: &Image, params: &Params) -> Vec<Volume> {
    let n = cost.len();
    let disparities = cost[0].len();
    let mut sum = vec![vec![0; disparities]; n];
    let mut stages = Vec::new();
    for &(rx, ry) in &DIRECTIONS[..params.paths] {
        let mut path = vec![vec![0; disparities]; n];
        let ys: Vec<_> = if ry < 0 { (0..left.height).rev().collect() } else { (0..left.height).collect() };
        let xs: Vec<_> = if rx < 0 { (0..left.width).rev().collect() } else { (0..left.width).collect() };
        for &y in &ys { for &x in &xs {
            let p = y*left.width+x;
            let (qx, qy) = (x as i64-rx, y as i64-ry);
            if qx < 0 || qy < 0 || qx >= left.width as i64 || qy >= left.height as i64 { path[p].clone_from(&cost[p]); }
            else {
                let q = qy as usize*left.width+qx as usize;
                let minimum = *path[q].iter().min().unwrap();
                let p2 = params.p1.max(params.p2*params.gamma/(params.gamma+(left.pixels[p]-left.pixels[q]).abs()));
                for d in 0..disparities {
                    let mut value = path[q][d].min(minimum+p2);
                    if d > 0 { value = value.min(path[q][d-1]+params.p1); }
                    if d+1 < disparities { value = value.min(path[q][d+1]+params.p1); }
                    path[p][d] = cost[p][d]+value-minimum;
                }
            }
            for d in 0..disparities { sum[p][d] += path[p][d]; }
        } }
        stages.push(sum.clone());
    }
    stages
}
