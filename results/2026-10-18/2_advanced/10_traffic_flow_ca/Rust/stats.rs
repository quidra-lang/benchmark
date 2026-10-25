pub fn gcd(mut a: i64, mut b: i64) -> i64 { while b != 0 { let next = a % b; a = b; b = next; } a }
pub fn dec(numerator: i64, denominator: i64, places: usize) -> String {
    if denominator == 0 { return "-".to_owned(); } let scale = 10i64.pow(places as u32); let value = (2 * numerator * scale + denominator) / (2 * denominator);
    format!("{}.{:0places$}", value / scale, value % scale)
}
pub fn frac(numerator: i64, denominator: i64) -> String { if denominator == 0 { "-".to_owned() } else { let divisor = gcd(numerator, denominator); format!("{}/{}", numerator / divisor, denominator / divisor) } }
pub fn percentile(times: &[i64], q: usize) -> i64 { times[(q * times.len() + 99) / 100 - 1] }
pub fn histogram_lines(times: &[i64], width: i64) -> Vec<String> {
    let first = times[0] / width; let mut counts = vec![0; (times[times.len() - 1] / width - first + 1) as usize]; for &time in times { counts[(time / width - first) as usize] += 1; }
    let peak = *counts.iter().max().unwrap(); counts.iter().enumerate().map(|(j, &count)| {
        let low = (first + j as i64) * width; let stars = (80 * count + peak) / (2 * peak);
        format!("  {low}-{} {count}{}", low + width - 1, if stars > 0 { format!(" {}", "*".repeat(stars as usize)) } else { String::new() })
    }).collect()
}
