use crate::gaussian::{self, Component, Point};

pub fn adjust(initial: &[Component], kind: &str) -> Vec<Component> {
    let mut result = initial.to_vec();
    let tied = [initial.iter().map(|c| c.weight * c.covariance[0]).sum::<f64>(),
        initial.iter().map(|c| c.weight * c.covariance[1]).sum::<f64>(), initial.iter().map(|c| c.weight * c.covariance[2]).sum::<f64>()];
    for component in &mut result {
        let [a, _, c] = component.covariance;
        component.covariance = match kind {
            "FULL" => component.covariance,
            "TIED" => tied,
            "DIAG" => [a, 0.0, c],
            "SPHERICAL" => [(a + c) / 2.0, 0.0, (a + c) / 2.0],
            _ => unreachable!(),
        };
    }
    result
}

pub fn expectation(points: &[Point], model: &[Component]) -> (Vec<Vec<f64>>, Vec<f64>) {
    let mut responsibilities = Vec::new();
    let mut log_density = Vec::new();
    for &point in points {
        let logs: Vec<f64> = model.iter().map(|c| gaussian::log_density(point, c)).collect();
        let maximum = logs.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let values: Vec<f64> = logs.iter().map(|l| (l - maximum).exp()).collect();
        let total: f64 = values.iter().sum();
        responsibilities.push(values.iter().map(|v| v / total).collect());
        log_density.push(maximum + total.ln());
    }
    (responsibilities, log_density)
}

pub fn maximization(points: &[Point], responsibilities: &[Vec<f64>], kind: &str, regularization: f64) -> Vec<Component> {
    let k = responsibilities[0].len();
    let n = points.len() as f64;
    let mut result = Vec::new();
    let mut sums = Vec::new();
    for j in 0..k {
        let size: f64 = responsibilities.iter().map(|r| r[j]).sum();
        let mx = points.iter().zip(responsibilities).map(|(p, r)| r[j] * p.0).sum::<f64>() / size;
        let my = points.iter().zip(responsibilities).map(|(p, r)| r[j] * p.1).sum::<f64>() / size;
        let (mut a, mut b, mut c) = (0.0, 0.0, 0.0);
        for (&point, r) in points.iter().zip(responsibilities) {
            let dx = point.0 - mx;
            let dy = point.1 - my;
            a += r[j] * dx * dx;
            b += r[j] * dx * dy;
            c += r[j] * dy * dy;
        }
        let covariance = match kind {
            "FULL" | "TIED" => [a / size + regularization, b / size, c / size + regularization],
            "DIAG" => [a / size + regularization, 0.0, c / size + regularization],
            "SPHERICAL" => {
                let v = (a / size + c / size) / 2.0 + regularization;
                [v, 0.0, v]
            }
            _ => unreachable!(),
        };
        sums.push([a, b, c]);
        result.push(Component { weight: size / n, mean: (mx, my), covariance });
    }
    if kind == "TIED" {
        let tied = [sums.iter().map(|c| c[0]).sum::<f64>() / n + regularization,
            sums.iter().map(|c| c[1]).sum::<f64>() / n, sums.iter().map(|c| c[2]).sum::<f64>() / n + regularization];
        for component in &mut result { component.covariance = tied; }
    }
    result
}

pub struct Fit {
    pub components: Vec<Component>,
    pub responsibilities: Vec<Vec<f64>>,
    pub log_density: Vec<f64>,
    pub trace: Vec<f64>,
}

pub fn fit(points: &[Point], initial: &[Component], kind: &str, iterations: usize, regularization: f64) -> Fit {
    let mut components = adjust(initial, kind);
    let (mut responsibilities, mut log_density) = expectation(points, &components);
    let mut trace = vec![log_density.iter().sum()];
    for _ in 0..iterations {
        components = maximization(points, &responsibilities, kind, regularization);
        (responsibilities, log_density) = expectation(points, &components);
        trace.push(log_density.iter().sum());
    }
    Fit { components, responsibilities, log_density, trace }
}
