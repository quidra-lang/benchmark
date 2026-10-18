fn decimal(x: f64) -> String {
    let q = (x.abs() * 10000.0 + 0.5) as i64;
    format!("{}{}.{:04}", if x < 0.0 {
        "-"
    } else {
        ""
    }, q / 10000, q % 10000)
}

fn main() {
    for (a, b, c) in [(1, -3, -10), (-2, 5, 4), (3, 1, -2), (4, -12, 9), (1, 2, 5), (-2, 3, -4)] {
        let d = b * b - 4 * a * c;
        print!("{} {} {}: ", a, b, c);
        if d > 0 {
            let x = (f64::from(-b) + f64::from(d).sqrt()) / f64::from(2 * a);
            let y = (f64::from(-b) - f64::from(d).sqrt()) / f64::from(2 * a);
            println!("x1 = {}, x2 = {}", decimal(x.max(y)), decimal(x.min(y)));
        } else if d == 0 {
            println!("x = {}", decimal(f64::from(-b) / f64::from(2 * a)));
        } else {
            let p = decimal(f64::from(-b) / f64::from(2 * a));
            let q = decimal(f64::from(-d).sqrt() / (2.0 * f64::from(a).abs()));
            println!("x = {} + {}i, {} - {}i", p, q, p, q);
        }
    }
}
