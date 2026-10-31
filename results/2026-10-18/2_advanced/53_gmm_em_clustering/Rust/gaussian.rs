pub type Point = (f64, f64);
pub type Covariance = [f64; 3];

#[derive(Clone)]
pub struct Component {
    pub weight: f64,
    pub mean: Point,
    pub covariance: Covariance,
}

pub fn determinant([a, b, c]: Covariance) -> f64 {
    a * c - b * b
}

pub fn mahalanobis(point: Point, mean: Point, covariance: Covariance) -> f64 {
    let [a, b, c] = covariance;
    let (dx, dy) = (point.0 - mean.0, point.1 - mean.1);
    (c * dx * dx - 2.0 * b * dx * dy + a * dy * dy) / determinant(covariance)
}

pub fn log_density(point: Point, component: &Component) -> f64 {
    component.weight.ln() - (2.0 * std::f64::consts::PI).ln() - determinant(component.covariance).ln() / 2.0
        - mahalanobis(point, component.mean, component.covariance) / 2.0
}

pub struct Ellipse {
    pub eigenvalues: [f64; 2],
    pub direction: Point,
    pub angle: f64,
}

pub fn ellipse([a, b, c]: Covariance) -> Ellipse {
    let h = (a + c) / 2.0;
    let g = (((a - c) / 2.0) * ((a - c) / 2.0) + b * b).sqrt();
    let eigenvalues = [h + g, h - g];
    let direction = if b == 0.0 {
        if a >= c { (1.0, 0.0) } else { (0.0, 1.0) }
    } else {
        let (mut x, mut y) = if a >= c { (eigenvalues[0] - c, b) } else { (b, eigenvalues[0] - a) };
        let length = (x * x + y * y).sqrt();
        if x < 0.0 { x = -x; y = -y; }
        (x / length, y / length)
    };
    Ellipse { eigenvalues, direction, angle: direction.1.atan2(direction.0) * 180.0 / std::f64::consts::PI }
}

pub fn bhattacharyya(first: &Component, second: &Component) -> f64 {
    let average = [(first.covariance[0] + second.covariance[0]) / 2.0,
        (first.covariance[1] + second.covariance[1]) / 2.0, (first.covariance[2] + second.covariance[2]) / 2.0];
    mahalanobis(second.mean, first.mean, average) / 8.0
        + (determinant(average) / (determinant(first.covariance) * determinant(second.covariance)).sqrt()).ln() / 2.0
}
