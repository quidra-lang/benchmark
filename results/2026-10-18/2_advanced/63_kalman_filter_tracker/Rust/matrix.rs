pub type Matrix = Vec<Vec<f64>>;

pub fn identity(n: usize) -> Matrix { (0..n).map(|i| (0..n).map(|j| if i == j { 1.0 } else { 0.0 }).collect()).collect() }
pub fn diagonal(values: &[f64]) -> Matrix {
    (0..values.len()).map(|i| (0..values.len()).map(|j| if i == j { values[i] } else { 0.0 }).collect()).collect()
}
pub fn transpose(a: &Matrix) -> Matrix { (0..a[0].len()).map(|j| a.iter().map(|row| row[j]).collect()).collect() }
pub fn product(a: &Matrix, b: &Matrix) -> Matrix {
    (0..a.len()).map(|i| (0..b[0].len()).map(|j| {
        let mut sum = 0.0;
        for k in 0..b.len() { sum += a[i][k]*b[k][j]; }
        sum
    }).collect()).collect()
}
pub fn vector(a: &Matrix, b: &[f64]) -> Vec<f64> {
    a.iter().map(|row| row.iter().zip(b).map(|(x, y)| x*y).sum()).collect()
}
pub fn add(a: &Matrix, b: &Matrix) -> Matrix {
    a.iter().zip(b).map(|(x, y)| x.iter().zip(y).map(|(x, y)| x+y).collect()).collect()
}
pub fn subtract(a: &Matrix, b: &Matrix) -> Matrix {
    a.iter().zip(b).map(|(x, y)| x.iter().zip(y).map(|(x, y)| x-y).collect()).collect()
}
pub fn inverse(a: &Matrix) -> Matrix {
    let n = a.len();
    let identity = identity(n);
    let mut x: Matrix = (0..n).map(|i| a[i].iter().chain(&identity[i]).copied().collect()).collect();
    for c in 0..n {
        let pivot = x[c][c];
        for j in 0..2*n { x[c][j] /= pivot; }
        for i in 0..n {
            if i == c { continue; }
            let factor = x[i][c];
            for j in 0..2*n { let value = x[c][j]; x[i][j] -= factor*value; }
        }
    }
    x.iter().map(|row| row[n..].to_vec()).collect()
}
pub fn determinant(a: &Matrix) -> f64 { a[0][0]*a[1][1]-a[0][1]*a[1][0] }
pub fn quadratic(u: [f64; 2], a: &Matrix) -> f64 {
    u[0]*(a[0][0]*u[0]+a[0][1]*u[1])+u[1]*(a[1][0]*u[0]+a[1][1]*u[1])
}
