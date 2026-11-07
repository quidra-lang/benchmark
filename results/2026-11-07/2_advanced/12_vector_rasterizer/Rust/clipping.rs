use crate::canvas::round_ratio;
use crate::primitives::Point;

pub type Rect = [i64; 4];
fn region_code((x, y): Point, c: Rect) -> u8 {
    u8::from(x < c[0]) | (u8::from(x > c[2]) << 1) | (u8::from(y < c[1]) << 2) | (u8::from(y > c[3]) << 3)
}
pub fn clip_segment(mut start: Point, mut end: Point, [x0, y0, x1, y1]: Rect) -> Option<(Point, Point)> {
    loop {
        let sc = region_code(start, [x0, y0, x1, y1]);
        let ec = region_code(end, [x0, y0, x1, y1]);
        if sc | ec == 0 { return Some((start, end)); }
        if sc & ec != 0 { return None; }
        let (code, (ax, ay), (bx, by)) = if sc != 0 { (sc, start, end) } else { (ec, end, start) };
        let p = if code & 4 != 0 { (ax + round_ratio((bx - ax) * (y0 - ay), by - ay), y0) }
            else if code & 8 != 0 { (ax + round_ratio((bx - ax) * (y1 - ay), by - ay), y1) }
            else if code & 2 != 0 { (x1, ay + round_ratio((by - ay) * (x1 - ax), bx - ax)) }
            else { (x0, ay + round_ratio((by - ay) * (x0 - ax), bx - ax)) };
        if sc != 0 { start = p; } else { end = p; }
    }
}
fn inside(point: Point, axis: usize, limit: i64, minimum: bool) -> bool {
    let value = if axis == 0 { point.0 } else { point.1 };
    if minimum { value >= limit } else { value <= limit }
}
fn intersection((sx, sy): Point, (ex, ey): Point, axis: usize, limit: i64) -> Point {
    if axis == 0 { (limit, sy + round_ratio((limit - sx) * (ey - sy), ex - sx)) }
    else { (sx + round_ratio((limit - sy) * (ex - sx), ey - sy), limit) }
}
pub fn clip_polygon(mut vertices: Vec<Point>, clip: Rect) -> Vec<Point> {
    for (axis, limit, minimum) in [(0, clip[0], true), (0, clip[2] + 1, false), (1, clip[1], true), (1, clip[3] + 1, false)] {
        let mut output = Vec::new();
        for (i, &end) in vertices.iter().enumerate() {
            let start = vertices[(i + vertices.len() - 1) % vertices.len()];
            let si = inside(start, axis, limit, minimum);
            let ei = inside(end, axis, limit, minimum);
            if ei { if !si { output.push(intersection(start, end, axis, limit)); } output.push(end); }
            else if si { output.push(intersection(start, end, axis, limit)); }
        }
        vertices = output;
    }
    vertices
}
