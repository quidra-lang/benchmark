use crate::model_io::{Case, Load, Model};
pub struct Geometry {
    pub length: f64,
    pub cosine: f64,
    pub sine: f64,
    pub dofs: [usize; 4]
}
pub struct Property {
    pub area: f64,
    pub inertia: f64,
    pub young: f64,
    pub yield_stress: f64,
    pub density: f64,
    pub expansion: f64,
    pub stiffness: f64
}
pub struct Loading {
    pub external: Vec<f64>,
    pub total: Vec<f64>,
    pub temperature: Vec<f64>,
    pub settlement: bool
}
pub fn geometry(model: &Model, dofs: &[[usize; 2]]) -> Vec<Geometry> {
    model.members.iter().map(|m| {
        let dx = model.nodes[m.end].x-model.nodes[m.start].x;
        let dy = model.nodes[m.end].y-model.nodes[m.start].y;
        let length = (dx*dx+dy*dy).sqrt();
        Geometry {
            length,
            cosine: dx/length,
            sine: dy/length,
            dofs: [dofs[m.start][0], dofs[m.start][1], dofs[m.end][0], dofs[m.end][1]]
        }
    }).collect()
}
pub fn properties(model: &Model, choices: &[usize], geometry: &[Geometry]) -> Vec<Property> {
    model.members.iter().enumerate().map(|(i, m)| {
        let s = &model.sections[choices[i]];
        let material = &model.materials[m.material];
        Property {
            area: s.area,
            inertia: s.inertia,
            young: material.young,
            yield_stress: material.yield_stress,
            density: material.density,
            expansion: material.expansion,
            stiffness: material.young*s.area/geometry[i].length
        }
    }).collect()
}
pub fn matrix(geometry: &[Geometry], properties: &[Property], size: usize, removed: Option<usize>) -> Vec<Vec<f64>> {
    let mut matrix = vec![vec![0.0; size]; size];
    for (i, g) in geometry.iter().enumerate() {
        if removed == Some(i) {
            continue;
        }
        let k = properties[i].stiffness;
        let xx = k*(g.cosine*g.cosine);
        let xy = k*(g.cosine*g.sine);
        let yy = k*(g.sine*g.sine);
        let local = [[xx,xy,-xx,-xy],[xy,yy,-xy,-yy],[-xx,-xy,xx,xy],[-xy,-yy,xy,yy]];
        for a in 0..4 {
            for b in 0..4 {
                matrix[g.dofs[a]][g.dofs[b]] += local[a][b];
            }
        }
    }
    matrix
}
pub fn weight(p: &Property, g: &Geometry) -> f64 {
    p.density*9.81*p.area*g.length/1000000000.0
}
pub fn loads(case: &Case, geometry: &[Geometry], properties: &[Property], dofs: &[[usize; 2]], removed: Option<usize>) -> Loading {
    let mut external = vec![0.0; 2*dofs.len()];
    let mut thermal = external.clone();
    let mut temperature = vec![0.0; geometry.len()];
    let mut settlement = false;
    for load in &case.loads {
        match *load {
            Load::Force(node, x, y) => {
                external[dofs[node][0]] += x*1000.0;
                external[dofs[node][1]] += y*1000.0;
            }
            Load::Temperature(i, dt) => {
                if removed == Some(i) {
                    continue;
                }
                let p = &properties[i];
                let g = &geometry[i];
                let force = p.young*p.area*p.expansion*dt;
                temperature[i] = force;
                let t = [-g.cosine,-g.sine,g.cosine,g.sine];
                for a in 0..4 {
                    thermal[g.dofs[a]] += force*t[a];
                }
            }
            Load::SelfWeight => {
                for (i, g) in geometry.iter().enumerate() {
                    if removed != Some(i) {
                        let w = weight(&properties[i], g);
                        external[g.dofs[1]] -= w/2.0;
                        external[g.dofs[3]] -= w/2.0;
                    }
                }
            }
            Load::Settlement => settlement = true
        }
    }
    let total = external.iter().zip(thermal).map(|(e, t)| e+t).collect();
    Loading {
        external,
        total,
        temperature,
        settlement
    }
}
