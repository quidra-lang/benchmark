pub struct Golden { pub point: f64, pub value: f64, pub records: Vec<[f64; 6]> }

pub fn golden<F: Fn(f64) -> f64>(function: F, mut a: f64, mut b: f64, iterations: usize) -> Golden {
    let phi = 0.6180339887498949;
    let mut c = b-phi*(b-a);
    let mut d = a+phi*(b-a);
    let mut fc = function(c);
    let mut fd = function(d);
    let mut records = vec![[a, b, c, d, fc, fd]];
    for _ in 0..iterations {
        if fc < fd {
            b = d; d = c; fd = fc;
            c = b-phi*(b-a); fc = function(c);
        } else {
            a = c; c = d; fc = fd;
            d = a+phi*(b-a); fd = function(d);
        }
        records.push([a, b, c, d, fc, fd]);
    }
    let (point, value) = if fc < fd { (c, fc) } else { (d, fd) };
    Golden { point, value, records }
}

#[derive(Clone)]
pub struct Vertex { pub point: [f64; 2], pub value: f64, pub number: usize }
pub struct Simplex { pub initial: Vec<Vertex>, pub final_vertices: Vec<Vertex>, pub records: Vec<(String, Vertex)> }

fn order(vertices: &mut [Vertex]) { vertices.sort_by(|a, b| a.value.total_cmp(&b.value).then(a.number.cmp(&b.number))); }
fn interpolate(u: [f64; 2], v: [f64; 2], t: f64) -> [f64; 2] { [u[0]+t*(v[0]-u[0]), u[1]+t*(v[1]-u[1])] }

pub fn nelder_mead<F: Fn([f64; 2]) -> f64>(function: F, start: [f64; 2], delta: [f64; 2], coefficients: [f64; 4], iterations: usize) -> Simplex {
    let initial: Vec<_> = [start, [start[0]+delta[0], start[1]], [start[0], start[1]+delta[1]]].iter().copied().enumerate()
        .map(|(number, point)| Vertex { point, value: function(point), number }).collect();
    let mut vertices = initial.clone();
    let mut number = 3;
    let mut records = Vec::new();
    let [alpha, chi, psi, omega] = coefficients;
    for _ in 0..iterations {
        order(&mut vertices);
        let (first, second, third) = (vertices[0].clone(), vertices[1].clone(), vertices[2].clone());
        let centroid = [(first.point[0]+second.point[0])/2.0, (first.point[1]+second.point[1])/2.0];
        let reflected = [centroid[0]+alpha*(centroid[0]-third.point[0]), centroid[1]+alpha*(centroid[1]-third.point[1])];
        let fr = function(reflected);
        let mut accepted = None;
        let operation;
        if fr < first.value {
            let expanded = interpolate(centroid, reflected, chi);
            let fe = function(expanded);
            if fe < fr { accepted = Some((expanded, fe)); operation = "expand"; }
            else { accepted = Some((reflected, fr)); operation = "reflect"; }
        } else if fr < second.value {
            accepted = Some((reflected, fr)); operation = "reflect";
        } else if fr < third.value {
            let contracted = interpolate(centroid, reflected, psi);
            let fc = function(contracted);
            if fc <= fr { accepted = Some((contracted, fc)); operation = "contract_out"; }
            else { operation = "shrink"; }
        } else {
            let contracted = interpolate(centroid, third.point, psi);
            let fc = function(contracted);
            if fc < third.value { accepted = Some((contracted, fc)); operation = "contract_in"; }
            else { operation = "shrink"; }
        }
        if let Some((point, value)) = accepted {
            vertices[2] = Vertex { point, value, number }; number += 1;
        } else {
            for i in 1..3 {
                let point = interpolate(first.point, vertices[i].point, omega);
                vertices[i] = Vertex { point, value: function(point), number }; number += 1;
            }
        }
        order(&mut vertices);
        records.push((operation.to_owned(), vertices[0].clone()));
    }
    Simplex { initial, final_vertices: vertices, records }
}
