use crate::{fixed_point::{floor, mul, isqrt, S}, vector3::{self, Vector}, scene::{Material, Color}};

pub fn base(material: &Material, point: Vector) -> Color {
    if let Some((other, size)) = material.checker {
        let parity = floor(point[0], size) + floor(point[1], size) + floor(point[2], size);
        if parity % 2 != 0 { return other; }
    }
    material.color
}

pub fn components(material: &Material, normal: Vector, light: Vector, view: Vector, intensity: i64, ndl: i64) -> (i64, i64) {
    let diffuse = mul(mul(material.diffuse, ndl), intensity);
    let reflected = vector3::subtract(vector3::scale(normal, 2 * ndl), light);
    let rv = vector3::dot(reflected, view);
    let specular = if rv > 0 {
        let mut p = S;
        for _ in 0..material.exponent { p = mul(p, rv); }
        mul(mul(material.specular, p), intensity)
    } else { 0 };
    (diffuse, specular)
}

pub fn reflection(direction: Vector, normal: Vector) -> Vector {
    vector3::normalize(vector3::subtract(direction, vector3::scale(normal, 2 * vector3::dot(direction, normal))))
}

pub struct Weights {
    pub reflected: i64,
    pub transmitted: i64,
    pub direction: Option<Vector>,
    pub total_internal: bool,
}

pub fn refraction(material: &Material, direction: Vector, normal: Vector, front: bool) -> Weights {
    let mut result = Weights { reflected: material.reflection, transmitted: material.transmission, direction: None, total_internal: false };
    if material.transmission == 0 { return result; }
    let eta = if front { floor(S * S, material.ior) } else { material.ior };
    let cn = -vector3::dot(direction, normal);
    let discriminant = S * S - floor(mul(eta, eta) * (S * S - cn * cn), S);
    if discriminant < 0 {
        result.reflected = material.reflection + material.transmission;
        result.transmitted = 0;
        result.total_internal = true;
    } else {
        result.direction = Some(vector3::normalize(vector3::add(vector3::scale(direction, eta), vector3::scale(normal, mul(eta, cn) - isqrt(discriminant)))));
        let r0 = floor((material.ior - S) * S, material.ior + S);
        let r0 = mul(r0, r0);
        let x = S - cn.min(S);
        let mut p = S;
        for _ in 0..5 { p = mul(p, x); }
        let fresnel = r0 + mul(S - r0, p);
        let fr = mul(material.transmission, fresnel);
        result.reflected = material.reflection + fr;
        result.transmitted = material.transmission - fr;
    }
    result
}

pub fn mix(colors: &[(Color, i64)]) -> Color {
    let mut result = [0; 3];
    for &(color, weight) in colors {
        for component in 0..3 { result[component] += floor(color[component] * weight, S); }
    }
    result
}
