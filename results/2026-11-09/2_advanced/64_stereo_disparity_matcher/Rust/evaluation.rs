use crate::refinement::decimal;

pub struct Regions { pub nonocc: Vec<usize>, pub all: Vec<usize>, pub disc: Vec<usize>, pub occluded: Vec<bool> }

pub fn regions(truth: &[i64], width: usize, height: usize) -> Regions {
    let all: Vec<_> = (0..truth.len()).filter(|&p| truth[p] != 0).collect();
    let mut occluded = vec![false; truth.len()];
    for &p in &all {
        let (x, y) = ((p%width) as i64, p/width);
        let g = truth[p];
        occluded[p] = x-g < 0 || (0..width).any(|x2| truth[y*width+x2] > g && x2 as i64-truth[y*width+x2] == x-g);
    }
    let nonocc: Vec<_> = all.iter().copied().filter(|&p| !occluded[p]).collect();
    let disc = nonocc.iter().copied().filter(|&p| {
        let (x, y) = ((p%width) as i64, (p/width) as i64);
        (-1..=1).any(|dy| (-1..=1).any(|dx| {
            let (xx, yy) = (x+dx, y+dy);
            if xx < 0 || yy < 0 || xx >= width as i64 || yy >= height as i64 || (dx == 0 && dy == 0) { false }
            else { let q = yy as usize*width+xx as usize; truth[q] != 0 && (truth[q]-truth[p]).abs() >= 2 }
        }))
    }).collect();
    Regions { nonocc, all, disc, occluded }
}

#[derive(Clone)]
pub struct Metrics { pub pixels: usize, pub valid: usize, pub bad1: usize, pub bad2: usize, pub error: i64, pub exact: usize }

pub fn evaluate(disparity: &[Option<i64>], truth: &[i64], region: &[usize]) -> Metrics {
    let mut m = Metrics { pixels: region.len(), valid: 0, bad1: 0, bad2: 0, error: 0, exact: 0 };
    for &p in region {
        if let Some(d) = disparity[p] {
            let error = (d-truth[p]).abs();
            m.valid += 1; m.bad1 += usize::from(error > 1); m.bad2 += usize::from(error > 2); m.error += error;
            m.exact += usize::from(error == 0);
        } else { m.bad1 += 1; m.bad2 += 1; }
    }
    m
}

pub fn ratio(a: usize, b: usize) -> String {
    if b == 0 { return "0/1 0.00".to_owned(); }
    let (mut x, mut y) = (a, b);
    while y != 0 { let r = x%y; x = y; y = r; }
    format!("{}/{} {}", a/x, b/x, decimal(100*a as i64, b as i64))
}
