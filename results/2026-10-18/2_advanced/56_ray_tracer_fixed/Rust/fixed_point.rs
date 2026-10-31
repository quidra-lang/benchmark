pub const S: i64 = 4096;

pub fn floor(a: i64, b: i64) -> i64 {
    let quotient = a / b;
    let remainder = a % b;
    if remainder != 0 && (remainder < 0) != (b < 0) { quotient - 1 } else { quotient }
}

pub fn mul(a: i64, b: i64) -> i64 {
    floor(a * b, S)
}

pub fn isqrt(n: i64) -> i64 {
    if n < 2 { return n; }
    let mut x = n;
    let mut next = (x + 1) / 2;
    while next < x {
        x = next;
        next = (x + n / x) / 2;
    }
    x
}
