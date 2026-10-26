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
    let (mut mode, mut best, mut count) = (sorted[0], 0, 0);
    for i in 0..sorted.len() {
        count = if i > 0 && sorted[i] == sorted[i - 1] {
            count + 1
        } else {
            1
        };
        if count > best {
            best = count;
            mode = sorted[i];
        }
    }
    println!(
        "mean: {:.3}\nmedian: {}\nmode: {}\nrange: {}\nstdev: {:.3}",
        mean,
        sorted[5],
        mode,
        sorted[10] - sorted[0],
        (s / 11.0).sqrt()
    );
}
