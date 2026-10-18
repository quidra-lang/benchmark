fn main() {
    let p = [[12, -7], [-33, 25], [41, 18], [-8, -44], [27, 39], [-46, -12], [5, 14], [36, -29], [-19,
        47], [-2, 3]];
    let (mut best, mut bi, mut bj) = ([0; 2], [0; 2], [0; 2]);
    for i in 0..10 {
        for j in i + 1..10 {
            let dx = p[i][0] - p[j][0];
            let dy = p[i][1] - p[j][1];
            let d = dx * dx + dy * dy;
            for k in 0..2 {
                if (i == 0 && j == 1) || (if k == 0 {
                    d < best[k]
                } else {
                    d > best[k]
                }) {
                    best[k] = d;
                    bi[k] = i;
                    bj[k] = j;
                }
            }
        }
    }
    for k in 0..2 {
        let q = (f64::from(best[k]).sqrt() * 10000.0 + 0.5) as i32;
        println!("{}: P{} P{} {}.{:04}", if k == 0 {
            "closest"
        } else {
            "farthest"
        }, bi[k], bj[k], q / 10000, q % 10000);
    }
}
