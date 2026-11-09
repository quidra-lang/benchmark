const r = @import("rational.zig");
pub fn onSegment(point: r.Point, first: r.Point, second: r.Point) bool {
    if (r.cross(first, second, point).numerator != 0) return false;
    const low_x = if (first.x.less(second.x)) first.x else second.x;
    const high_x = if (first.x.less(second.x)) second.x else first.x;
    const low_y = if (first.y.less(second.y)) first.y else second.y;
    const high_y = if (first.y.less(second.y)) second.y else first.y;
    return !point.x.less(low_x) and !high_x.less(point.x) and !point.y.less(low_y) and !high_y.less(point.y);
}
fn opposite(first: r.Fraction, second: r.Fraction) bool {
    return (first.numerator < 0 and second.numerator > 0) or (first.numerator > 0 and second.numerator < 0);
}
pub fn touch(first: r.Point, second: r.Point, third: r.Point, fourth: r.Point) bool {
    return (opposite(r.cross(first, second, third), r.cross(first, second, fourth)) and opposite(r.cross(third,
         fourth, first), r.cross(third, fourth, second))) or onSegment(third, first, second) or onSegment(fourth,
         first, second) or onSegment(first, third, fourth) or onSegment(second, third, fourth);
}
pub fn overlap(first: r.Point, second: r.Point, third: r.Point, fourth: r.Point) bool {
    if (r.cross(first, second, third).numerator != 0 or r.cross(first, second, fourth).numerator != 0) return false;
    const x = !first.x.same(second.x);
    const a = if (x) first.x else first.y;
    const b = if (x) second.x else second.y;
    const c = if (x) third.x else third.y;
    const d = if (x) fourth.x else fourth.y;
    const low_a = if (a.less(b)) a else b;
    const high_a = if (a.less(b)) b else a;
    const low_b = if (c.less(d)) c else d;
    const high_b = if (c.less(d)) d else c;
    const low = if (low_a.less(low_b)) low_b else low_a;
    const high = if (high_a.less(high_b)) high_a else high_b;
    return low.less(high);
}
pub const Crossing = struct { first: r.Fraction, second: r.Fraction, point: r.Point };
pub fn crossing(first: r.Point, second: r.Point, third: r.Point, fourth: r.Point) ?Crossing {
    const a = second.subtract(first);
    const b = fourth.subtract(third);
    const den = a.x.multiply(b.y).subtract(a.y.multiply(b.x));
    if (den.numerator == 0) return null;
    const g = third.subtract(first);
    const t = g.x.multiply(b.y).subtract(g.y.multiply(b.x)).divide(den);
    const u = g.x.multiply(a.y).subtract(g.y.multiply(a.x)).divide(den);
    if (t.numerator <= 0 or !t.less(r.Fraction.integer(1)) or u.numerator <= 0 or !u.less(r.Fraction.integer(1))) return null;
    return .{ .first = t, .second = u, .point = r.along(first, second, t) };
}
pub fn clippingPoint(previous: r.Point, current: r.Point, previous_cross: r.Fraction, current_cross: r.Fraction) r.Point {
    return r.along(previous, current, previous_cross.divide(previous_cross.subtract(current_cross)));
}
