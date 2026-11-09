use crate::{filters::clamped, canny};

pub fn detect(gx: &[i64], gy: &[i64], width: usize, height: usize, window: i64, threshold: i64) -> (Vec<i64>, Vec<usize>) {
    let half = window / 2;
    let mut response = Vec::new();
    for y in 0..height {
        for x in 0..width {
            let (mut xx, mut yy, mut xy) = (0, 0, 0);
            for j in -half..=half {
                for i in -half..=half {
                    let a = clamped(gx, width, height, x as i64 + i, y as i64 + j);
                    let b = clamped(gy, width, height, x as i64 + i, y as i64 + j);
                    xx += a * a;
                    yy += b * b;
                    xy += a * b;
                }
            }
            response.push(xx * yy - xy * xy - ((xx + yy) * (xx + yy)).div_euclid(25));
        }
    }
    let mut candidates: Vec<usize> = (0..response.len()).filter(|&i| response[i] >= threshold && canny::neighbors(i, width, height).iter()
        .all(|&j| if j < i { response[i] > response[j] } else { response[i] >= response[j] })).collect();
    candidates.sort_by_key(|&i| (std::cmp::Reverse(response[i]), i));
    (response, candidates)
}
