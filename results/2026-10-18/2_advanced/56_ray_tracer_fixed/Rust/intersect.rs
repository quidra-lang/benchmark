use crate::{fixed_point::{floor, isqrt, S}, vector3::{self, Vector}, scene::{Geometry, Object}};

#[derive(Clone, Copy)]
pub struct Ray {
    pub origin: Vector,
    pub direction: Vector,
}

#[derive(Clone, Copy)]
pub struct Slab {
    pub near: i64,
    pub near_axis: usize,
    pub far: i64,
    pub far_axis: usize,
}

#[derive(Clone, Copy)]
pub struct Hit {
    pub object: usize,
    pub distance: i64,
    pub face: Option<(usize, bool)>,
}

pub fn slab(ray: Ray, lo: Vector, hi: Vector) -> Option<Slab> {
    let mut near: Option<(i64, usize)> = None;
    let mut far: Option<(i64, usize)> = None;
    for axis in 0..3 {
        let (o, d) = (ray.origin[axis], ray.direction[axis]);
        if d == 0 {
            if o < lo[axis] || o > hi[axis] { return None; }
        } else {
            let first = floor((lo[axis] - o) * S, d);
            let second = floor((hi[axis] - o) * S, d);
            let entry = first.min(second);
            let exit = first.max(second);
            if near.map_or(true, |(value, _)| entry > value) { near = Some((entry, axis)); }
            if far.map_or(true, |(value, _)| exit < value) { far = Some((exit, axis)); }
        }
    }
    let (near, near_axis) = near.unwrap();
    let (far, far_axis) = far.unwrap();
    if near > far { None } else { Some(Slab { near, near_axis, far, far_axis }) }
}

pub fn object(ray: Ray, geometry: &Geometry, epsilon: i64) -> Option<(i64, Option<(usize, bool)>)> {
    match *geometry {
        Geometry::Sphere { center, radius } => {
            let oc = vector3::subtract(ray.origin, center);
            let b = vector3::dot(oc, ray.direction);
            let tc = floor(-b * S, vector3::dot(ray.direction, ray.direction));
            let h = vector3::add(oc, vector3::scale(ray.direction, tc));
            let q = floor(radius * radius, S) - vector3::dot(h, h);
            if q < 0 { return None; }
            let w = floor(isqrt(q * S) * S, vector3::length(ray.direction));
            if tc - w > epsilon { Some((tc - w, None)) } else if tc + w > epsilon { Some((tc + w, None)) } else { None }
        }
        Geometry::Plane { point, normal } => {
            let denominator = vector3::dot(ray.direction, normal);
            if denominator == 0 { return None; }
            let t = floor(vector3::dot(vector3::subtract(point, ray.origin), normal) * S, denominator);
            if t > epsilon { Some((t, None)) } else { None }
        }
        Geometry::Box { lo, hi } => {
            let hit = slab(ray, lo, hi)?;
            if hit.near > epsilon { Some((hit.near, Some((hit.near_axis, true)))) }
            else if hit.far > epsilon { Some((hit.far, Some((hit.far_axis, false)))) } else { None }
        }
    }
}

pub fn bounds(object: &Object, margin: i64) -> Option<(Vector, Vector)> {
    match object.geometry {
        Geometry::Sphere { center, radius } => Some(([center[0] - radius - margin, center[1] - radius - margin, center[2] - radius - margin],
            [center[0] + radius + margin, center[1] + radius + margin, center[2] + radius + margin])),
        Geometry::Box { lo, hi } => Some(([lo[0] - margin, lo[1] - margin, lo[2] - margin], [hi[0] + margin, hi[1] + margin, hi[2] + margin])),
        Geometry::Plane { .. } => None,
    }
}

pub fn outward(object: &Object, ray: Ray, point: Vector, face: Option<(usize, bool)>) -> Vector {
    match object.geometry {
        Geometry::Sphere { center, .. } => vector3::normalize(vector3::subtract(point, center)),
        Geometry::Plane { normal, .. } => normal,
        Geometry::Box { .. } => {
            let (axis, entering) = face.unwrap();
            let mut normal = [0; 3];
            let positive = ray.direction[axis] > 0;
            normal[axis] = if positive == entering { -S } else { S };
            normal
        }
    }
}
