pub type Point = (i64, i64);

pub fn orient(p: Point, q: Point, r: Point) -> i64 {
    (q.0 - p.0) * (r.1 - p.1) - (q.1 - p.1) * (r.0 - p.0)
}

pub fn d2(p: Point, q: Point) -> i64 {
    (p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1)
}

pub fn dot(o: Point, p: Point, q: Point) -> i64 {
    (p.0 - o.0) * (q.0 - o.0) + (p.1 - o.1) * (q.1 - o.1)
}

pub fn incircle(a: Point, b: Point, c: Point, d: Point) -> i64 {
    let (ax, ay) = (a.0 - d.0, a.1 - d.1);
    let (bx, by) = (b.0 - d.0, b.1 - d.1);
    let (cx, cy) = (c.0 - d.0, c.1 - d.1);
    let aa = ax * ax + ay * ay;
    let bb = bx * bx + by * by;
    let cc = cx * cx + cy * cy;
    ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx)
}

pub fn center(a: Point, b: Point, c: Point) -> (i64, i64, i64) {
    let (bx, by) = (b.0 - a.0, b.1 - a.1);
    let (cx, cy) = (c.0 - a.0, c.1 - a.1);
    let bb = bx * bx + by * by;
    let cc = cx * cx + cy * cy;
    let d = 2 * (bx * cy - by * cx);
    (a.0 * d + cy * bb - by * cc, a.1 * d + bx * cc - cx * bb, d)
}

pub fn gcd(mut a: i64, mut b: i64) -> i64 {
    while b != 0 {
        let r = a % b;
        a = b;
        b = r;
    }
    a.abs()
}

pub fn fraction(n: i64, d: i64) -> String {
    let g = gcd(n.abs(), d);
    if d / g == 1 { (n / g).to_string() } else { format!("{}/{}", n / g, d / g) }
}

pub fn direction(u: Point, v: Point) -> Point {
    let (dx, dy) = (v.0 - u.0, v.1 - u.1);
    let g = gcd(dx.abs(), dy.abs());
    (dy / g, -dx / g)
}
