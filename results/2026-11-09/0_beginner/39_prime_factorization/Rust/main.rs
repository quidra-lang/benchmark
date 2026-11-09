fn main() {
    for value in [84, 9973, 15625, 1001, 123456, 48000, 999958, 999999] {
        let (mut n, mut d) = (value, 2);
        let mut factors = Vec::new();
        while d * d <= n {
            let mut e = 0;
            while n % d == 0 {
                n /= d;
                e += 1;
            }
            if e > 0 {
                factors.push(if e == 1 {
                    d.to_string()
                } else {
                    format!("{}^{}", d, e)
                });
            }
            d += 1;
        }
        if n > 1 {
            factors.push(n.to_string());
        }
        println!("{} = {}", value, factors.join(" * "));
    }
}
