pub fn rdiv(numerator: i64, denominator: i64) -> i64 { (2 * numerator + denominator).div_euclid(2 * denominator) }

pub fn decimal2(value: i64) -> String {
    format!("{}{}.{:02}", if value < 0 { "-" } else { "" }, value.abs() / 100, value.abs() % 100)
}

pub fn decimal4(value: i64) -> String { format!("{}.{:04}", value / 10000, value % 10000) }

pub fn fraction(mut numerator: i64, mut denominator: i64) -> String {
    let (mut a, mut b) = (numerator, denominator);
    while b != 0 { (a, b) = (b, a % b); }
    numerator /= a;
    denominator /= a;
    format!("{numerator}/{denominator}")
}

pub fn ratio(numerator: i64, denominator: i64) -> String {
    if denominator == 0 { format!("{numerator}/0 none") }
    else { format!("{numerator}/{denominator} reduced={} percent={}", fraction(numerator, denominator), decimal2(rdiv(10000 * numerator, denominator))) }
}

pub fn missing(value: Option<i64>) -> String { value.map_or_else(|| "-".into(), |value| value.to_string()) }
