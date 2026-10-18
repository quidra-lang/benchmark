fn main() {
    let values = [72, 85, 64, 90, 85, 58, 77, 85, 69, 93, 71];
    let mut sorted = values;
    sorted.sort();
    let sum: i32 = values.iter().sum();
    let mean = f64::from(sum) / 11.0;
    let mut s = 0.0;
    for n in values {
        let d = f64::from(n) - mean;
        s += d * d;
    }
    let (mut mode, mut best) = (sorted[0], 0);
    for n in sorted {
        let count = sorted.iter().filter(|&&v| v == n).count();
        if count > best {
            best = count;
            mode = n;
        }
    }
    let m = (mean * 1000.0 + 0.5) as i32;
    let sd = ((s / 11.0).sqrt() * 1000.0 + 0.5) as i32;
    println!("mean: {}.{:03}\nmedian: {}\nmode: {}\nrange: {}\nstdev: {}.{:03}", m / 1000, m % 1000,
        sorted[5], mode, sorted[10] - sorted[0], sd / 1000, sd % 1000);
}
