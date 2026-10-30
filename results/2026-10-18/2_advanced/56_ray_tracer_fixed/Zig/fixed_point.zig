pub const scale: i64 = 4096;
pub fn div(a: i64, b: i64) i64 {
    return @divFloor(a, b);
}
pub fn mul(a: i64, b: i64) i64 {
    return div(a * b, scale);
}
pub fn isqrt(value: i64) i64 {
    if (value == 0) return 0;
    var x = value;
    var y = div(x + 1, 2);
    while (y < x) {
        x = y;
        y = div(x + div(value, x), 2);
    }
    return x;
}
