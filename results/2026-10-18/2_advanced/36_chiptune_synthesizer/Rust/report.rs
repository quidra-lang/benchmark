pub fn hex_dump(samples: &[i64]) -> Vec<String> {
    samples.chunks(32).map(|chunk| chunk.iter().map(|sample| format!("{sample:02X}")).collect()).collect()
}

pub fn adler(samples: &[i64]) -> i64 {
    let (mut a, mut b) = (1, 0);
    for &sample in samples { a = (a + sample) % 65521; b = (b + a) % 65521; }
    b * 65536 + a
}

pub fn isqrt(value: i64) -> i64 {
    let (mut low, mut high) = (0, value + 1);
    while high - low > 1 {
        let middle = (low + high) / 2;
        if middle <= value / middle { low = middle; } else { high = middle; }
    }
    low
}

pub fn statistics(samples: &[i64], center: i64) -> (i64, i64, usize) {
    let peak = samples.iter().map(|&sample| (sample - center).abs()).max().unwrap_or(0);
    let squares: i64 = samples.iter().map(|&sample| (sample - center) * (sample - center)).sum();
    let rms = if samples.is_empty() { 0 } else { isqrt(squares / samples.len() as i64) };
    let crossings = samples.windows(2).filter(|pair| (pair[0] < center) != (pair[1] < center)).count();
    (peak, rms, crossings)
}
