use crate::assembly::{Geometry, Property};
use crate::model_io::Section;
use crate::postprocess::Result;
pub const PI: f64 = 3.141592653589793;
pub fn buckling(p: &Property, g: &Geometry, inertia: f64) -> f64 {
    PI*PI*p.young*inertia/(g.length*g.length)
}
pub fn utilization(force: f64, p: &Property, g: &Geometry, area: f64, inertia: f64) -> f64 {
    ((force/area).abs()/p.yield_stress).max(0.0f64.max(-force)/buckling(p, g, inertia))
}
pub fn slenderness(g: &Geometry, area: f64, inertia: f64) -> f64 {
    g.length/(inertia/area).sqrt()
}
pub fn limit(member: usize, combinations: &[Result], limits: [f64; 2]) -> f64 {
    if combinations.iter().any(|r| r.forces[member] < 0.0) {
        limits[0]
    } else {
        limits[1]
    }
}
pub fn select(members: &[usize], sections: &[Section], properties: &[Property], geometry: &[Geometry], combinations: &[Result], limits: &[f64]) -> usize {
    sections.iter().position(|s| members.iter().all(|&m| slenderness(&geometry[m], s.area, s.inertia) <= limits[m] && combinations.iter().all(|r| utilization(r.forces[m], &properties[m], &geometry[m], s.area, s.inertia) <= 1.0))).unwrap_or(sections.len()-1)
}
