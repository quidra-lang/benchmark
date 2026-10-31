use std::fs;
pub struct Node {
    pub id: usize,
    pub x: f64,
    pub y: f64
}
pub struct Member {
    pub id: usize,
    pub start: usize,
    pub end: usize,
    pub section: usize,
    pub material: usize,
    pub group: usize
}
pub struct Section {
    pub name: String,
    pub area: f64,
    pub inertia: f64
}
pub struct Material {
    pub name: String,
    pub young: f64,
    pub yield_stress: f64,
    pub density: f64,
    pub expansion: f64
}
pub struct Support {
    pub node: usize,
    pub fixed: [bool; 2],
    pub prescribed: [f64; 2]
}
pub enum Load {
    Force(usize, f64, f64),
    Temperature(usize, f64),
    SelfWeight,
    Settlement
}
pub struct Case {
    pub name: String,
    pub loads: Vec<Load>
}
pub struct Combination {
    pub name: String,
    pub terms: Vec<(usize, f64)>
}
pub struct Settings {
    pub deck: Vec<usize>,
    pub influence: Vec<usize>,
    pub step: i64,
    pub axles: Vec<(i64, f64)>,
    pub rating: (usize, f64, f64),
    pub slenderness: [f64; 2],
    pub deflection: (usize, f64),
    pub vibration: (usize, usize, usize),
    pub removal: usize,
    pub drawings: Vec<(usize, f64, f64, f64)>,
    pub map: (f64, f64)
}
pub struct Model {
    pub nodes: Vec<Node>,
    pub members: Vec<Member>,
    pub sections: Vec<Section>,
    pub materials: Vec<Material>,
    pub supports: Vec<Support>,
    pub cases: Vec<Case>,
    pub combinations: Vec<Combination>,
    pub groups: Vec<String>,
    pub names: Vec<String>,
    pub settings: Settings
}
fn csv(name: &str) -> Vec<Vec<String>> {
    fs::read_to_string(format!("input/{}.csv", name)).unwrap().lines().skip(1).map(|line| line.split(',').map(str::to_owned).collect()).collect()
}
fn real(value: &str) -> f64 {
    value.parse().unwrap()
}
pub fn read() -> Model {
    let nodes: Vec<_> = csv("nodes").iter().map(|w| Node {
        id: w[0].parse().unwrap(),
        x: real(&w[1]),
        y: real(&w[2])
    }).collect();
    let sections: Vec<_> = csv("sections").iter().map(|w| Section {
        name: w[0].clone(),
        area: real(&w[1]),
        inertia: real(&w[2])
    }).collect();
    let materials: Vec<_> = csv("materials").iter().map(|w| Material {
        name: w[0].clone(),
        young: real(&w[1]),
        yield_stress: real(&w[2]),
        density: real(&w[3]),
        expansion: real(&w[4])
    }).collect();
    let node = |id: &str| nodes.iter().position(|n| n.id == id.parse::<usize>().unwrap()).unwrap();
    let mut groups = Vec::new();
    let mut members = Vec::new();
    for w in csv("members") {
        let group = if let Some(index) = groups.iter().position(|name| name == &w[5]) {
            index
        } else {
            groups.push(w[5].clone());
            groups.len()-1
        };
        members.push(Member {
            id: w[0].parse().unwrap(),
            start: node(&w[1]),
            end: node(&w[2]),
            section: sections.iter().position(|s| s.name == w[3]).unwrap(),
            material: materials.iter().position(|m| m.name == w[4]).unwrap(),
            group
        });
    }
    let member = |id: &str| members.iter().position(|m| m.id == id.parse::<usize>().unwrap()).unwrap();
    let supports = csv("supports").iter().map(|w| Support {
        node: node(&w[0]),
        fixed: [w[1] == "1", w[2] == "1"],
        prescribed: [real(&w[3]), real(&w[4])]
    }).collect();
    let input = fs::read_to_string("input/loads.txt").unwrap();
    let mut cases = Vec::<Case>::new();
    let mut combinations = Vec::new();
    for line in input.lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "LOADCASE" => cases.push(Case {
                name: w[1].to_owned(),
                loads: Vec::new()
            }), "END" => (), "COMBINATION" => combinations.push(Combination {
                name: w[1].to_owned(),
                terms: w[2..].chunks(2).map(|t| (cases.iter().position(|c| c.name == t[0]).unwrap(), real(t[1]))).collect()
            }), _ => cases.last_mut().unwrap().loads.push(match w[0] {
                "FORCE" => Load::Force(node(w[1]), real(w[2]), real(w[3])), "TEMPERATURE" => Load::Temperature(member(w[1]), real(w[2])), "SELFWEIGHT" => Load::SelfWeight, _ => Load::Settlement
            })
        }
    }
    let names: Vec<_> = cases.iter().map(|c| c.name.clone()).chain(combinations.iter().map(|c| c.name.clone())).collect();
    let result = |name: &str| names.iter().position(|n| n == name).unwrap();
    let mut settings = Settings {
        deck: Vec::new(),
        influence: Vec::new(),
        step: 1,
        axles: Vec::new(),
        rating: (0, 0.0, 0.0),
        slenderness: [0.0; 2],
        deflection: (0, 0.0),
        vibration: (0, 0, 0),
        removal: 0,
        drawings: Vec::new(),
        map: (0.0, 0.0)
    };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "deck" => settings.deck = w[1..].iter().map(|id| node(id)).collect(), "influence" => settings.influence.push(member(w[1])), "vehicle" => {
                settings.step = w[1].parse().unwrap();
                settings.axles = w[2..].chunks(2).map(|a| (a[0].parse().unwrap(), real(a[1]))).collect();
            }
            "rating" => settings.rating = (result(w[1]), real(w[2]), real(w[3])), "slenderness" => settings.slenderness = [real(w[1]), real(w[2])], "deflection" => settings.deflection = (result(w[1]), real(w[2])), "vibration" => settings.vibration = (result(w[1]), w[2].parse().unwrap(), w[3].parse().unwrap()), "removal" => settings.removal = result(w[1]), "drawing" => settings.drawings.push((result(w[1]), real(w[2]), real(w[3]), real(w[4]))), _ => settings.map = (real(w[1]), real(w[2]))
        }
    }
    Model {
        nodes,
        members,
        sections,
        materials,
        supports,
        cases,
        combinations,
        groups,
        names,
        settings
    }
}
