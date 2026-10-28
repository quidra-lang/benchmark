use crate::mesh::Plate;

pub fn g(plate: &Plate, field: &[f64], source: &[f64], p: usize) -> f64 {
    let mut result = 0.0;
    for face in plate.faces[p] {
        if let Some(q) = face.neighbor { result += face.conductance * field[q]; }
        else if let Some(theta) = face.outside { result += face.conductance * theta; }
    }
    result + source[p]
}

pub struct Iteration {
    pub field: Vec<f64>,
    pub deltas: Vec<f64>,
    pub converged: bool,
}

pub fn iterate(plate: &Plate, source: &[f64], initial: f64, eps: f64, limit: usize, method: &str, omega: f64) -> Iteration {
    let mut field = vec![initial; source.len()];
    let mut deltas = Vec::new();
    for _ in 0..limit {
        let old = field.clone();
        for p in 0..field.len() {
            let y = g(plate, if method == "jacobi" { &old } else { &field }, source, p) / plate.diagonal[p];
            field[p] = if method == "jacobi" || method == "gauss_seidel" { y } else { field[p] + omega * (y - field[p]) };
        }
        let delta = field.iter().zip(&old).map(|(a, b)| (a-b).abs()).fold(0.0, f64::max);
        deltas.push(delta);
        if delta < eps { return Iteration { field, deltas, converged: true }; }
    }
    Iteration { field, deltas, converged: false }
}

pub fn direct(plate: &Plate, width: usize, mut rhs: Vec<Vec<f64>>) -> Vec<Vec<f64>> {
    let n = plate.faces.len();
    let mut matrix = vec![vec![0.0; n]; n];
    for p in 0..n {
        matrix[p][p] = plate.diagonal[p];
        for face in plate.faces[p] { if let Some(q) = face.neighbor { matrix[p][q] = -face.conductance; } }
    }
    for k in 0..n {
        let end = (k+width+1).min(n);
        for i in k+1..end {
            let factor = matrix[i][k] / matrix[k][k];
            matrix[i][k] = 0.0;
            for j in k+1..end {
                let value = matrix[k][j];
                matrix[i][j] -= factor * value;
            }
            for y in &mut rhs { let value = y[k]; y[i] -= factor * value; }
        }
    }
    for y in &mut rhs {
        for i in (0..n).rev() {
            for j in i+1..(i+width+1).min(n) { let value = y[j]; y[i] -= matrix[i][j] * value; }
            y[i] /= matrix[i][i];
        }
    }
    rhs
}

pub fn residual(plate: &Plate, rhs: &[f64], field: &[f64]) -> f64 {
    let mut maximum: f64 = 0.0;
    for p in 0..field.len() {
        let mut value = rhs[p];
        for face in plate.faces[p] { if let Some(q) = face.neighbor { value += face.conductance * field[q]; } }
        value -= plate.diagonal[p] * field[p];
        maximum = maximum.max(value.abs());
    }
    maximum
}
