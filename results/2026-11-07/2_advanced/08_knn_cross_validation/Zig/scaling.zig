const d = @import("dataset.zig");
pub const Scaling = struct { centers: []const f64, scales: []const f64 };
pub fn compute(rows: []const d.Row, method: d.Scaling) Scaling {
    const centers = d.alloc(f64, rows[0].values.len); const scales = d.alloc(f64, centers.len);
    for (centers, scales, 0..) |*center, *scale, j| {
        if (method == .standard) { var total: f64 = 0; for (rows) |row| total += row.values[j]; center.* = total / d.real(rows.len); var squares: f64 = 0; for (rows) |row| { const delta = row.values[j] - center.*; squares += delta * delta; } scale.* = if (rows.len == 1) 0 else @sqrt(squares / d.real(rows.len - 1)); }
        else { center.* = rows[0].values[j]; var high = center.*; for (rows) |row| { center.* = @min(center.*, row.values[j]); high = @max(high, row.values[j]); } scale.* = high - center.*; }
    }
    return .{ .centers = centers, .scales = scales };
}
pub fn transform(s: Scaling, values: []const f64, features: []const usize) []const f64 { const result = d.alloc(f64, features.len); for (features, result) |j, *value| value.* = if (s.scales[j] > 0) (values[j] - s.centers[j]) / s.scales[j] else 0; return result; }
