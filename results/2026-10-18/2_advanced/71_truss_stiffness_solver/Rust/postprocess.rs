use crate::assembly::{Geometry, Property};
pub struct Result {
    pub displacement: Vec<f64>,
    pub forces: Vec<f64>,
    pub reactions: Vec<f64>,
    pub external: Vec<f64>
}
pub fn forces(geometry: &[Geometry], properties: &[Property], displacement: &[f64], temperature: &[f64], removed: Option<usize>) -> Vec<f64> {
    geometry.iter().enumerate().map(|(i, g)| {
        if removed == Some(i) {
            return 0.0;
        }
        let a = g.dofs;
        let extension = (displacement[a[2]]-displacement[a[0]])*g.cosine+(displacement[a[3]]-displacement[a[1]])*g.sine;
        properties[i].stiffness*extension-temperature[i]
    }).collect()
}
pub fn reactions(matrix: &[Vec<f64>], displacement: &[f64], force: &[f64], restrained: &[usize]) -> Vec<f64> {
    let mut result = vec![0.0; force.len()];
    for &r in restrained {
        let mut total = 0.0;
        for d in 0..force.len() {
            total += matrix[r][d]*displacement[d];
        }
        result[r] = total-force[r];
    }
    result
}
pub fn residual(result: &Result, geometry: &[Geometry]) -> f64 {
    let mut z: Vec<_> = result.external.iter().zip(&result.reactions).map(|(e, r)| e+r).collect();
    for (i, g) in geometry.iter().enumerate() {
        let t = [g.cosine,g.sine,-g.cosine,-g.sine];
        for a in 0..4 {
            z[g.dofs[a]] += result.forces[i]*t[a];
        }
    }
    z.iter().map(|v| v.abs()).fold(0.0, f64::max)
}
pub fn superpose(terms: &[(usize, f64)], results: &[Result]) -> Result {
    fn vector(terms: &[(usize, f64)], results: &[Result], get: fn(&Result) -> &[f64]) -> Vec<f64> {
        let mut values = vec![0.0; get(&results[0]).len()];
        for &(i, factor) in terms {
            for (v, &source) in values.iter_mut().zip(get(&results[i])) {
                *v += factor*source;
            }
        }
        values
    }
    Result {
        displacement: vector(terms, results, |r| &r.displacement),
        forces: vector(terms, results, |r| &r.forces),
        reactions: vector(terms, results, |r| &r.reactions),
        external: vector(terms, results, |r| &r.external)
    }
}
