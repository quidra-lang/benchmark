use crate::vector3::{self, Vector};
use std::{collections::BTreeMap, fs, io};

pub type Color = [i64; 3];

pub struct Material {
    pub name: String,
    pub color: Color,
    pub diffuse: i64,
    pub specular: i64,
    pub exponent: usize,
    pub reflection: i64,
    pub transmission: i64,
    pub ior: i64,
    pub checker: Option<(Color, i64)>,
}

#[derive(Clone, Copy)]
pub enum Geometry {
    Sphere { center: Vector, radius: i64 },
    Plane { point: Vector, normal: Vector },
    Box { lo: Vector, hi: Vector },
}

pub struct Object {
    pub label: char,
    pub material: usize,
    pub geometry: Geometry,
}

impl Object {
    pub fn kind(&self) -> &'static str {
        match self.geometry { Geometry::Sphere { .. } => "sphere", Geometry::Plane { .. } => "plane", Geometry::Box { .. } => "box" }
    }
}

#[derive(Clone, Copy)]
pub enum LightKind {
    Point(Vector),
    Spot { position: Vector, direction: Vector, outer: i64, inner: i64 },
    Sun(Vector),
    Area { position: Vector, u: Vector, v: Vector, divisions: usize },
}

pub struct Light {
    pub kind: LightKind,
    pub intensity: i64,
}

impl Light {
    pub fn kind(&self) -> &'static str {
        match self.kind { LightKind::Point(_) => "point", LightKind::Spot { .. } => "spot", LightKind::Sun(_) => "sun", LightKind::Area { .. } => "area" }
    }

    pub fn samples(&self) -> usize {
        if let LightKind::Area { divisions, .. } = self.kind { divisions * divisions } else { 1 }
    }
}

pub struct Fog {
    pub color: Color,
    pub start: i64,
    pub end: i64,
}

pub struct Scene {
    pub eye: Vector,
    pub forward: Vector,
    pub right: Vector,
    pub up: Vector,
    pub half_width: i64,
    pub half_height: i64,
    pub background: Color,
    pub ambient: i64,
    pub fog: Option<Fog>,
    pub materials: Vec<Material>,
    pub objects: Vec<Object>,
    pub lights: Vec<Light>,
}

pub fn read() -> io::Result<Scene> {
    let mut scene = Scene { eye: [0; 3], forward: [0; 3], right: [0; 3], up: [0; 3], half_width: 0, half_height: 0, background: [0; 3],
        ambient: 0, fog: None, materials: Vec::new(), objects: Vec::new(), lights: Vec::new() };
    let mut materials = BTreeMap::new();
    for line in fs::read_to_string("input/scene.txt")?.lines() {
        if line.is_empty() || line.starts_with('#') { continue; }
        let words: Vec<&str> = line.split_whitespace().collect();
        let value = |i: usize| words[i].parse::<i64>().unwrap();
        let vector = |i: usize| [value(i), value(i + 1), value(i + 2)];
        match words[0] {
            "eye" => scene.eye = vector(1),
            "forward" => scene.forward = vector(1),
            "right" => scene.right = vector(1),
            "up" => scene.up = vector(1),
            "view" => { scene.half_width = value(1); scene.half_height = value(2); }
            "background" => scene.background = vector(1),
            "ambient" => scene.ambient = value(1),
            "fog" => scene.fog = Some(Fog { color: vector(1), start: value(4), end: value(5) }),
            "material" => {
                let index = scene.materials.len();
                materials.insert(words[1].to_owned(), index);
                scene.materials.push(Material { name: words[1].into(), color: vector(2), diffuse: value(5), specular: value(6), exponent: value(7) as usize,
                    reflection: value(8), transmission: value(9), ior: value(10), checker: None });
            }
            "checker" => scene.materials[materials[words[1]]].checker = Some((vector(2), value(5))),
            "sphere" | "plane" | "box" => {
                let geometry = match words[0] {
                    "sphere" => Geometry::Sphere { center: vector(3), radius: value(6) },
                    "plane" => Geometry::Plane { point: vector(3), normal: vector3::normalize(vector(6)) },
                    _ => Geometry::Box { lo: vector(3), hi: vector(6) },
                };
                scene.objects.push(Object { label: words[1].chars().next().unwrap(), material: materials[words[2]], geometry });
            }
            "point" => scene.lights.push(Light { kind: LightKind::Point(vector(1)), intensity: value(4) }),
            "spot" => scene.lights.push(Light { kind: LightKind::Spot { position: vector(1), direction: vector3::normalize(vector(4)), outer: value(7), inner: value(8) }, intensity: value(9) }),
            "sun" => scene.lights.push(Light { kind: LightKind::Sun(vector3::normalize(vector3::negate(vector(1)))), intensity: value(4) }),
            "area" => scene.lights.push(Light { kind: LightKind::Area { position: vector(1), u: vector(4), v: vector(7), divisions: value(10) as usize }, intensity: value(11) }),
            _ => unreachable!(),
        }
    }
    Ok(scene)
}
