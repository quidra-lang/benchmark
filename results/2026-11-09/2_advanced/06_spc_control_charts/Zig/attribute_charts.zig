const d = @import("dataset.zig");
pub const Center = struct { value: f64, fraction: f64 };
pub const Status = enum { ok, high, low };
pub const Point = struct { value: f64, lcl: f64, ucl: f64, z: f64, status: Status };
pub fn centerline(chart: usize, lots: []const d.Lot, numbers: []const usize) Center {
    var defective: i64 = 0; var defects: i64 = 0; var inspected: i64 = 0;
    for (numbers) |number| { const lot = lots[number - 1]; defective += lot.defectives; defects += lot.defects; inspected += lot.inspected; }
    return .{ .value = switch (chart) { 0 => d.real(defective) / d.real(inspected), 1 => d.real(defective) / d.real(numbers.len), 2 => d.real(defects) / d.real(numbers.len), else => d.real(defects) / d.real(inspected) }, .fraction = d.real(defective) / d.real(inspected) };
}
pub fn point(chart: usize, lot: d.Lot, center: Center) Point {
    const cl = center.value;
    const value = switch (chart) { 0 => d.real(lot.defectives) / d.real(lot.inspected), 1 => d.real(lot.defectives), 2 => d.real(lot.defects), else => d.real(lot.defects) / d.real(lot.inspected) };
    const sigma = @sqrt(switch (chart) { 0 => cl * (1 - cl) / d.real(lot.inspected), 1 => cl * (1 - center.fraction), 2 => cl, else => cl / d.real(lot.inspected) });
    const lcl = @max(0, cl - 3 * sigma);
    const ucl = cl + 3 * sigma;
    return .{ .value = value, .lcl = lcl, .ucl = ucl, .z = (value - cl) / sigma, .status = if (value > ucl) .high else if (value < lcl) .low else .ok };
}
