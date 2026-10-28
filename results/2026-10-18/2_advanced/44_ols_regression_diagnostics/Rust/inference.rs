fn log_gamma(x: f64) -> f64 {
    let coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.001208650973866179, -0.000005395239384953];
    let t = x + 5.5;
    let big_t = t - (x + 0.5) * t.ln();
    let mut s = 1.000000000190015;
    for (j, coefficient) in coefficients.iter().enumerate() { s += coefficient / (x + (j + 1) as f64); }
    -big_t + (2.5066282746310005 * s / x).ln()
}

fn small(value: f64) -> f64 { if value.abs() < 1e-300 { 1e-300 } else { value } }

fn beta_fraction(a: f64, b: f64, x: f64) -> f64 {
    let mut c = 1.0;
    let mut d = 1.0 / small(1.0 - (a + b) * x / (a + 1.0));
    let mut h = d;
    for m in 1..=1000 {
        let m = m as f64;
        let q = m * (b - m) * x / ((a - 1.0 + 2.0 * m) * (a + 2.0 * m));
        d = 1.0 / small(1.0 + q * d);
        c = small(1.0 + q / c);
        h *= d * c;
        let q = -(a + m) * (a + b + m) * x / ((a + 2.0 * m) * (a + 1.0 + 2.0 * m));
        d = 1.0 / small(1.0 + q * d);
        c = small(1.0 + q / c);
        let delta = d * c;
        h *= delta;
        if (delta - 1.0).abs() < 1e-15 { break; }
    }
    h
}

fn beta(x: f64, a: f64, b: f64) -> f64 {
    if x <= 0.0 { return 0.0; }
    if x >= 1.0 { return 1.0; }
    let factor = (log_gamma(a + b) - log_gamma(a) - log_gamma(b) + a * x.ln() + b * (1.0 - x).ln()).exp();
    if x < (a + 1.0) / (a + b + 2.0) { factor * beta_fraction(a, b, x) / a }
    else { 1.0 - factor * beta_fraction(b, a, 1.0 - x) / b }
}

fn gamma_q(a: f64, x: f64) -> f64 {
    if x == 0.0 { return 1.0; }
    let factor = (-x + a * x.ln() - log_gamma(a)).exp();
    if x < a + 1.0 {
        let mut term = 1.0 / a;
        let mut total = term;
        let mut exponent = a;
        for _ in 0..1000 {
            exponent += 1.0;
            term *= x / exponent;
            total += term;
            if term.abs() < total.abs() * 1e-15 { break; }
        }
        1.0 - total * factor
    } else {
        let mut b = x + 1.0 - a;
        let mut c = 1.0 / 1e-300;
        let mut d = 1.0 / b;
        let mut h = d;
        for i in 1..=1000 {
            let i = i as f64;
            let q = -i * (i - a);
            b += 2.0;
            d = 1.0 / small(q * d + b);
            c = small(b + q / c);
            let delta = d * c;
            h *= delta;
            if (delta - 1.0).abs() < 1e-15 { break; }
        }
        factor * h
    }
}

pub fn t_probability(t: f64, degrees: usize) -> f64 { let n = degrees as f64; beta(n / (n + t * t), n / 2.0, 0.5) }
pub fn f_probability(f: f64, first: usize, second: usize) -> f64 { let (a, b) = (first as f64, second as f64); beta(b / (b + a * f), b / 2.0, a / 2.0) }
pub fn chi_probability(value: f64, degrees: usize) -> f64 { gamma_q(degrees as f64 / 2.0, value / 2.0) }

pub fn t_quantile(confidence: f64, degrees: usize) -> f64 {
    let (mut low, mut high) = (0.0, 1000.0);
    for _ in 0..100 {
        let middle = (low + high) / 2.0;
        if t_probability(middle, degrees) > 1.0 - confidence { low = middle; } else { high = middle; }
    }
    (low + high) / 2.0
}

pub fn significance(probability: f64) -> &'static str {
    if probability < 0.001 { "***" } else if probability < 0.01 { "**" } else if probability < 0.05 { "*" } else if probability < 0.1 { "." } else { "" }
}

pub fn real(value: f64) -> String { if value.abs() < 0.00005 { "0.0000".into() } else { format!("{value:.4}") } }
pub fn probability(value: f64) -> String { if value < 0.0001 { "<0.0001".into() } else { real(value) } }
