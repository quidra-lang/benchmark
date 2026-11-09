use crate::matrix::{self, Matrix};

pub struct Decomposition {
    pub values: Vec<f64>,
    pub vectors: Matrix,
    pub sweeps: usize,
}

fn off(a: &Matrix) -> f64 {
    let mut value = 0.0;
    for p in 0..a.len() - 1 {
        for q in p + 1..a.len() {
            value += a[p][q] * a[p][q];
        }
    }
    value
}

fn rotate(a: &mut Matrix, v: &mut Matrix, p: usize, q: usize) {
    if a[p][q] == 0.0 {
        return;
    }
    let theta = (a[q][q] - a[p][p]) / (2.0 * a[p][q]);
    let mut t = 1.0 / (theta.abs() + (theta * theta + 1.0).sqrt());
    if theta < 0.0 {
        t = -t;
    }
    let c = 1.0 / (t * t + 1.0).sqrt();
    let s = t * c;
    for r in 0..a.len() {
        if r != p && r != q {
            let x = a[r][p];
            let y = a[r][q];
            let left = c * x - s * y;
            let right = s * x + c * y;
            a[r][p] = left;
            a[p][r] = left;
            a[r][q] = right;
            a[q][r] = right;
        }
    }
    let w = a[p][q];
    a[p][p] -= t * w;
    a[q][q] += t * w;
    a[p][q] = 0.0;
    a[q][p] = 0.0;
    for row in v {
        let x = row[p];
        let y = row[q];
        row[p] = c * x - s * y;
        row[q] = s * x + c * y;
    }
}

pub fn jacobi(input: &Matrix) -> Decomposition {
    let n = input.len();
    let mut a = matrix::copy(input);
    let mut v = matrix::identity(n);
    let initial = off(&a);
    let mut sweeps = 0;
    if initial > 0.0 {
        for sweep in 1..=100 {
            for p in 0..n - 1 {
                for q in p + 1..n {
                    rotate(&mut a, &mut v, p, q);
                }
            }
            let remaining = off(&a);
            if sweeps == 0 && remaining < 1e-16 * initial {
                sweeps = sweep;
            }
            if remaining < 1e-22 * initial {
                break;
            }
        }
    }
    let mut order: Vec<usize> = (0..n).collect();
    order.sort_by(|&i, &j| a[j][j].partial_cmp(&a[i][i]).unwrap().then(i.cmp(&j)));
    let values = order.iter().map(|&j| a[j][j]).collect();
    let vectors = order.iter().map(|&j| {
        let mut vector = matrix::normalize(&matrix::column(&v, j));
        matrix::orient(&mut vector);
        vector
    }).collect();
    Decomposition { values, vectors, sweeps }
}

pub struct Power {
    pub value: f64,
    pub agreement: Option<usize>,
    pub matches: bool,
}

pub fn power(input: &Matrix, jacobi: &Decomposition) -> Vec<Power> {
    let mut b = matrix::copy(input);
    let mut output = Vec::new();
    for k in 0..input.len() {
        let mut x = vec![1.0; input.len()];
        let negative: Vec<f64> = jacobi.vectors[k].iter().map(|v| -v).collect();
        let mut agreement = None;
        for iteration in 1..=1000 {
            x = matrix::normalize(&matrix::product(&b, &x));
            let distance = matrix::maximum_difference(&x, &jacobi.vectors[k])
                .min(matrix::maximum_difference(&x, &negative));
            if agreement.is_none() && distance < 0.000001 {
                agreement = Some(iteration);
            }
        }
        let w = matrix::product(&b, &x);
        let value = matrix::dot(&x, &w);
        let mut y = matrix::normalize(&x);
        matrix::orient(&mut y);
        let matches = (value - jacobi.values[k]).abs() <= 1e-8 * jacobi.values[0]
            && matrix::maximum_difference(&y, &jacobi.vectors[k]) <= 0.000001;
        matrix::deflate(&mut b, value, &y);
        output.push(Power { value, agreement, matches });
    }
    output
}
