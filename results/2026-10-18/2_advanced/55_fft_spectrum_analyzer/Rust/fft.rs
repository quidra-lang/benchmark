use std::ops::{Add, Sub, Mul, Div};

pub const PI: f64 = 3.141592653589793;

#[derive(Clone, Copy, Default)]
pub struct Complex {
    pub re: f64,
    pub im: f64,
}

impl Complex {
    pub fn new(re: f64, im: f64) -> Self { Self { re, im } }

    pub fn conj(self) -> Self { Self::new(self.re, -self.im) }

    pub fn norm2(self) -> f64 { self.re * self.re + self.im * self.im }

    pub fn abs(self) -> f64 { self.norm2().sqrt() }

    pub fn arg(self) -> f64 { self.im.atan2(self.re) }

    pub fn scale(self, value: f64) -> Self { Self::new(self.re * value, self.im * value) }
}

impl Add for Complex {
    type Output = Self;
    fn add(self, other: Self) -> Self { Self::new(self.re + other.re, self.im + other.im) }
}

impl Sub for Complex {
    type Output = Self;
    fn sub(self, other: Self) -> Self { Self::new(self.re - other.re, self.im - other.im) }
}

impl Mul for Complex {
    type Output = Self;
    fn mul(self, other: Self) -> Self { Self::new(self.re * other.re - self.im * other.im, self.re * other.im + self.im * other.re) }
}

impl Div<f64> for Complex {
    type Output = Self;
    fn div(self, other: f64) -> Self { Self::new(self.re / other, self.im / other) }
}

pub fn rot(angle: f64) -> Complex {
    Complex::new(angle.cos(), -angle.sin())
}

pub fn pow2(n: usize) -> usize {
    n.next_power_of_two()
}

pub fn radix2(values: &[Complex], inverse: bool) -> Vec<Complex> {
    let q = values.len();
    let mut a = values.to_vec();
    let bits = q.trailing_zeros();
    for n in 1..q {
        let r = n.reverse_bits() >> (usize::BITS - bits);
        if n < r { a.swap(n, r); }
    }
    let twiddles: Vec<Complex> = (0..q / 2).map(|k| {
        let value = rot(2.0 * PI * k as f64 / q as f64);
        if inverse { value.conj() } else { value }
    }).collect();
    let mut size = 2;
    while size <= q {
        for base in (0..q).step_by(size) {
            for j in 0..size / 2 {
                let t = twiddles[j * (q / size)] * a[base + j + size / 2];
                let u = a[base + j];
                a[base + j] = u + t;
                a[base + j + size / 2] = u - t;
            }
        }
        size *= 2;
    }
    if inverse { for value in &mut a { *value = *value / q as f64; } }
    a
}

fn bluestein(values: &[Complex]) -> Vec<Complex> {
    let m = values.len();
    let q = pow2(2 * m - 1);
    let chirp: Vec<Complex> = (0..m).map(|n| rot(PI * ((n * n) % (2 * m)) as f64 / m as f64)).collect();
    let mut a = vec![Complex::default(); q];
    let mut b = a.clone();
    for n in 0..m { a[n] = values[n] * chirp[n]; }
    b[0] = chirp[0].conj();
    for n in 1..m { b[n] = chirp[n].conj(); b[q - n] = chirp[n].conj(); }
    let a = radix2(&a, false);
    let b = radix2(&b, false);
    let product: Vec<Complex> = a.iter().zip(&b).map(|(&x, &y)| x * y).collect();
    let convolution = radix2(&product, true);
    (0..m).map(|k| chirp[k] * convolution[k]).collect()
}

pub fn transform(values: &[Complex], inverse: bool) -> Vec<Complex> {
    if values.len().is_power_of_two() { return radix2(values, inverse); }
    if inverse {
        let conjugates: Vec<Complex> = values.iter().map(|&v| v.conj()).collect();
        bluestein(&conjugates).iter().map(|&v| v.conj() / values.len() as f64).collect()
    } else { bluestein(values) }
}

pub fn real(values: &[f64]) -> Vec<Complex> {
    transform(&values.iter().map(|&v| Complex::new(v, 0.0)).collect::<Vec<_>>(), false)
}

pub fn packed(values: &[f64]) -> Vec<Complex> {
    let q = values.len();
    let h = q / 2;
    let z: Vec<Complex> = (0..h).map(|j| Complex::new(values[2 * j], values[2 * j + 1])).collect();
    let z = radix2(&z, false);
    (0..=h).map(|k| {
        let a = z[k % h];
        let b = z[(h - k) % h].conj();
        let even = (a + b) / 2.0;
        let difference = a - b;
        let odd = Complex::new(difference.im / 2.0, -difference.re / 2.0);
        even + rot(2.0 * PI * k as f64 / q as f64) * odd
    }).collect()
}

pub fn convolution(first: &[f64], second: &[f64]) -> Vec<f64> {
    let length = first.len() + second.len() - 1;
    let q = pow2(length);
    let mut a = vec![Complex::default(); q];
    let mut b = a.clone();
    for i in 0..first.len() { a[i].re = first[i]; }
    for i in 0..second.len() { b[i].re = second[i]; }
    let a = radix2(&a, false);
    let b = radix2(&b, false);
    let product: Vec<Complex> = a.iter().zip(&b).map(|(&x, &y)| x * y).collect();
    radix2(&product, true)[..length].iter().map(|v| v.re).collect()
}

pub fn chirp_z(values: &[f64], start: f64, step: f64, count: usize, rate: f64) -> Vec<Complex> {
    let m = values.len();
    let q = pow2(m + count - 1);
    let mut a = vec![Complex::default(); q];
    let mut b = a.clone();
    for n in 0..m {
        a[n] = Complex::new(values[n], 0.0) * rot(2.0 * PI * start * n as f64 / rate) * rot(PI * step * (n * n) as f64 / rate);
    }
    for n in -(m as i64 - 1)..=count as i64 - 1 {
        b[n.rem_euclid(q as i64) as usize] = rot(PI * step * (n * n) as f64 / rate).conj();
    }
    let a = radix2(&a, false);
    let b = radix2(&b, false);
    let product: Vec<Complex> = a.iter().zip(&b).map(|(&x, &y)| x * y).collect();
    let convolution = radix2(&product, true);
    (0..count).map(|j| rot(PI * step * (j * j) as f64 / rate) * convolution[j]).collect()
}
