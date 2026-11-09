use crate::obj_io::Face;

pub type Point = [i64; 3];

pub fn subtract(a: Point, b: Point) -> Point { std::array::from_fn(|i| a[i] - b[i]) }
pub fn dot(a: Point, b: Point) -> i64 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
pub fn cross(a: Point, b: Point) -> Point { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
pub fn normal(face: &Face, vertices: &[Point]) -> Point {
    let [a, b, c] = face.vertices.map(|v| vertices[v]);
    cross(subtract(b, a), subtract(c, a))
}

pub fn determinant(face: &Face, vertices: &[Point]) -> i64 {
    let [a, b, c] = face.vertices.map(|v| vertices[v]);
    dot(a, cross(b, c))
}

pub fn area(faces: &[Face], indices: &[usize], vertices: &[Point]) -> f64 {
    indices.iter().fold(0.0, |total, &i| { let n = normal(&faces[i], vertices); total + (dot(n, n) as f64).sqrt() }) / 2.0
}

pub fn volume6(faces: &[Face], indices: &[usize], vertices: &[Point]) -> i64 {
    indices.iter().map(|&i| determinant(&faces[i], vertices)).sum()
}

pub fn centroid(faces: &[Face], indices: &[usize], vertices: &[Point]) -> String {
    let volume = volume6(faces, indices, vertices);
    (0..3).map(|coordinate| {
        let total = indices.iter().map(|&i| determinant(&faces[i], vertices) * faces[i].vertices.iter().map(|&v| vertices[v][coordinate]).sum::<i64>()).sum();
        fraction(total, 4 * volume)
    }).collect::<Vec<_>>().join(" ")
}

pub fn fraction(mut numerator: i64, mut denominator: i64) -> String {
    if denominator < 0 { numerator = -numerator; denominator = -denominator; }
    let (mut a, mut b) = (numerator.abs(), denominator);
    while b != 0 { (a, b) = (b, a % b); }
    numerator /= a;
    denominator /= a;
    if denominator == 1 { numerator.to_string() } else { format!("{numerator}/{denominator}") }
}

pub fn vector(point: Point) -> String { format!("{} {} {}", point[0], point[1], point[2]) }
pub fn real(value: f64) -> String { format!("{value:.3}") }
pub fn length2(a: Point, b: Point) -> i64 { let d = subtract(a, b); dot(d, d) }

pub fn angle(face: &Face, vertices: &[Point]) -> &'static str {
    let [a, b, c] = face.vertices.map(|v| vertices[v]);
    let minimum = [dot(subtract(b, a), subtract(c, a)), dot(subtract(c, b), subtract(a, b)), dot(subtract(a, c), subtract(b, c))].iter().copied().min().unwrap();
    if minimum < 0 { "obtuse" } else if minimum == 0 { "right" } else { "acute" }
}

pub fn winding(point: Point, faces: &[Face], indices: &[usize], vertices: &[Point]) -> i64 {
    let mut total = 0.0;
    for &i in indices {
        let [a, b, c] = faces[i].vertices.map(|v| subtract(vertices[v], point));
        let (la, lb, lc) = ((dot(a, a) as f64).sqrt(), (dot(b, b) as f64).sqrt(), (dot(c, c) as f64).sqrt());
        let denominator = la * lb * lc + dot(a, b) as f64 * lc + dot(b, c) as f64 * la + dot(c, a) as f64 * lb;
        total += 2.0 * (dot(a, cross(b, c)) as f64).atan2(denominator);
    }
    (total / (4.0 * std::f64::consts::PI)).round() as i64
}
