use crate::fixed_point::{floor, isqrt, S};

pub type Vector = [i64; 3];

pub fn add(a: Vector, b: Vector) -> Vector {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

pub fn subtract(a: Vector, b: Vector) -> Vector {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

pub fn negate(a: Vector) -> Vector {
    [-a[0], -a[1], -a[2]]
}

pub fn dot(a: Vector, b: Vector) -> i64 {
    floor(a[0] * b[0] + a[1] * b[1] + a[2] * b[2], S)
}

pub fn scale(a: Vector, k: i64) -> Vector {
    [floor(a[0] * k, S), floor(a[1] * k, S), floor(a[2] * k, S)]
}

pub fn length(a: Vector) -> i64 {
    isqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
}

pub fn normalize(a: Vector) -> Vector {
    let length = length(a);
    [floor(a[0] * S, length), floor(a[1] * S, length), floor(a[2] * S, length)]
}

pub fn text(a: Vector) -> String {
    format!("{} {} {}", a[0], a[1], a[2])
}
