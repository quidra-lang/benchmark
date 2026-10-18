fn main() {
    for (a, b, c) in [(1, -3, -10), (-2, 5, 4), (3, 1, -2), (4, -12, 9), (1, 2, 5), (-2, 3, -4)] {
        let d = b * b - 4 * a * c;
        print!("{} {} {}: ", a, b, c);
        if d > 0 {
            let root = f64::from(d).sqrt();
            let x = (f64::from(-b) + root) / f64::from(2 * a);
            let y = (f64::from(-b) - root) / f64::from(2 * a);
            println!("x1 = {:.4}, x2 = {:.4}", x.max(y), x.min(y));
        } else if d == 0 {
            println!("x = {:.4}", f64::from(-b) / f64::from(2 * a));
        } else {
            let p = f64::from(-b) / f64::from(2 * a);
            let q = f64::from(-d).sqrt() / (2.0 * f64::from(a).abs());
            println!("x = {:.4} + {:.4}i, {:.4} - {:.4}i", p, q, p, q);
        }
    }
}
