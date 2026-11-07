pub type Matrix = Vec<Vec<f64>>;

pub fn identity(n: usize) -> Matrix {
    let mut a = vec![vec![0.0; n]; n];
    for i in 0..n {
        a[i][i] = 1.0;
    }
    a
}

pub fn copy(a: &Matrix) -> Matrix {
    a.clone()
}

pub fn column(a: &Matrix, j: usize) -> Vec<f64> {
    a.iter().map(|r| r[j]).collect()
}

pub fn dot(a: &[f64], b: &[f64]) -> f64 {
    let mut total = 0.0;
    for i in 0..a.len() {
        total += a[i] * b[i];
    }
    total
}

pub fn product(a: &Matrix, x: &[f64]) -> Vec<f64> {
    a.iter().map(|r| dot(r, x)).collect()
}

pub fn length(a: &[f64]) -> f64 {
    dot(a, a).sqrt()
}

pub fn normalize(a: &[f64]) -> Vec<f64> {
    let norm = length(a);
    a.iter().map(|x| x / norm).collect()
}

pub fn orient(a: &mut [f64]) {
    let mut largest = 0;
    for j in 1..a.len() {
        if a[j].abs() > a[largest].abs() {
            largest = j;
        }
    }
    if a[largest] < 0.0 {
        for x in a {
            *x = -*x;
        }
    }
}

pub fn maximum_difference(a: &[f64], b: &[f64]) -> f64 {
    a.iter().zip(b).map(|(x, y)| (x - y).abs()).fold(0.0, f64::max)
}

pub fn deflate(a: &mut Matrix, value: f64, v: &[f64]) {
    for i in 0..v.len() {
        for j in 0..v.len() {
            a[i][j] -= value * v[i] * v[j];
        }
    }
}

pub fn inverse_determinant(a: &Matrix) -> (Matrix, f64) {
    let n = a.len();
    let mut work = vec![vec![0.0; 2 * n]; n];
    for i in 0..n {
        work[i][..n].copy_from_slice(&a[i]);
        work[i][n + i] = 1.0;
    }
    let mut determinant = 1.0;
    for k in 0..n {
        let pivot = work[k][k];
        determinant *= pivot;
        for h in 0..2 * n {
            work[k][h] /= pivot;
        }
        for i in 0..n {
            if i != k {
                let gamma = work[i][k];
                for h in 0..2 * n {
                    let correction = gamma * work[k][h];
                    work[i][h] -= correction;
                }
            }
        }
    }
    (work.iter().map(|r| r[n..].to_vec()).collect(), determinant)
}
