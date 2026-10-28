use crate::mesh::{Mesh, Plate};

pub fn flow(plate: &Plate, field: &[f64], p: usize, first: usize, end: usize) -> f64 {
    let mut result = 0.0;
    for face in &plate.faces[p][first..end] {
        if let Some(q) = face.neighbor { result += face.conductance * (field[q] - field[p]); }
        else if let Some(theta) = face.outside { result += face.conductance * (theta - field[p]); }
    }
    result
}

pub fn thomas(lower: &[f64], diagonal: &[f64], upper: &[f64], rhs: &[f64]) -> Vec<f64> {
    let n = rhs.len();
    let mut u = vec![0.0; n];
    let mut r = vec![0.0; n];
    u[0] = upper[0] / diagonal[0];
    r[0] = rhs[0] / diagonal[0];
    for i in 1..n {
        let kappa = diagonal[i] - lower[i] * u[i-1];
        u[i] = upper[i] / kappa;
        r[i] = (rhs[i] - lower[i] * r[i-1]) / kappa;
    }
    for i in (0..n-1).rev() {
        let next = r[i+1];
        r[i] -= u[i] * next;
    }
    r
}

pub fn sweep(mesh: &Mesh, plate: &Plate, tau: f64, rhs: &[f64], vertical: bool) -> Vec<f64> {
    let mut result = vec![0.0; rhs.len()];
    let (count, len, first) = if vertical { (mesh.width, mesh.height, 2) } else { (mesh.height, mesh.width, 0) };
    for line in 0..count {
        let cells: Vec<_> = (0..len).map(|i| if vertical { i*mesh.width+line } else { line*mesh.width+i }).collect();
        let (mut lower, mut diagonal, mut upper, mut r) = (vec![0.0; len], vec![0.0; len], vec![0.0; len], vec![0.0; len]);
        for (i, &p) in cells.iter().enumerate() {
            let (a, b) = (plate.faces[p][first], plate.faces[p][first+1]);
            if a.neighbor.is_some() { lower[i] = -a.conductance; }
            if b.neighbor.is_some() { upper[i] = -b.conductance; }
            diagonal[i] = plate.capacity[p] / tau + a.conductance + b.conductance;
            r[i] = rhs[p];
            if let Some(theta) = a.outside { r[i] += a.conductance * theta; }
            if let Some(theta) = b.outside { r[i] += b.conductance * theta; }
        }
        let values = thomas(&lower, &diagonal, &upper, &r);
        for (i, &p) in cells.iter().enumerate() { result[p] = values[i]; }
    }
    result
}

pub fn step(mesh: &Mesh, plate: &Plate, method: &str, dt: f64, old: &[f64], source: &[f64]) -> (Vec<f64>, Vec<f64>) {
    if method == "ftcs" {
        return ((0..old.len()).map(|p| old[p] + dt * (flow(plate, old, p, 0, 4) + source[p]) / plate.capacity[p]).collect(), Vec::new());
    }
    let tau = if method == "backward_euler" { dt } else { dt / 2.0 };
    let rhs: Vec<_> = (0..old.len()).map(|p| plate.capacity[p] / tau * old[p]
        + flow(plate, old, p, 2, 4) + source[p]).collect();
    let intermediate = sweep(mesh, plate, tau, &rhs, false);
    let rhs: Vec<_> = (0..old.len()).map(|p| {
        if method == "backward_euler" {
            plate.capacity[p] / dt * intermediate[p] - flow(plate, old, p, 2, 4)
        } else {
            plate.capacity[p] / tau * intermediate[p] + flow(plate, &intermediate, p, 0, 2) + source[p]
        }
    }).collect();
    (sweep(mesh, plate, tau, &rhs, true), intermediate)
}
