const std = @import("std");
const d = @import("data_io.zig");
pub const GoldenRecord = struct { a: f64, b: f64, c: f64, d: f64, fc: f64, fd: f64 };
pub const Golden = struct { point: f64, value: f64, records: []const GoldenRecord };
pub fn golden(context: anytype, comptime function: anytype, first: f64, last: f64, iterations: usize) Golden {
    const phi: f64 = 0.6180339887498949;
    var a = first;
    var b = last;
    var c = b - phi * (b - a);
    var x = a + phi * (b - a);
    var fc = function(context, c);
    var fd = function(context, x);
    const records = d.alloc(GoldenRecord, iterations + 1);
    records[0] = .{ .a = a, .b = b, .c = c, .d = x, .fc = fc, .fd = fd };
    for (0..iterations) |i| {
        if (fc < fd) {
            b = x;
            x = c;
            fd = fc;
            c = b - phi * (b - a);
            fc = function(context, c);
        } else {
            a = c;
            c = x;
            fc = fd;
            x = a + phi * (b - a);
            fd = function(context, x);
        }
        records[i + 1] = .{ .a = a, .b = b, .c = c, .d = x, .fc = fc, .fd = fd };
    }
    return .{ .point = if (fc < fd) c else x, .value = if (fc < fd) fc else fd, .records = records };
}
pub const Point = [2]f64;
pub const Vertex = struct { point: Point, value: f64, number: usize };
pub const SimplexRecord = struct { operation: []const u8, best: Vertex };
pub const Simplex = struct { initial: [3]Vertex, final: [3]Vertex, records: []const SimplexRecord };
fn less(_: void, a: Vertex, b: Vertex) bool {
    return if (a.value != b.value) a.value < b.value else a.number < b.number;
}
fn along(a: Point, t: f64, b: Point) Point {
    return .{ a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]) };
}
pub fn nelderMead(context: anytype, comptime function: anytype, start: Point, params: d.Params) Simplex {
    const points = [3]Point{ start, .{ start[0] + params.delta_beta, start[1] }, .{ start[0],
         start[1] + params.delta_gamma } };
    var vertices: [3]Vertex = undefined;
    for (points, 0..) |point, i| vertices[i] = .{ .point = point, .value = function(context, point), .number = i };
    const initial = vertices;
    var serial: usize = 3;
    const records = d.alloc(SimplexRecord, params.nelder);
    for (records) |*record| {
        std.mem.sort(Vertex, &vertices, {}, less);
        const first = vertices[0];
        const second = vertices[1];
        const third = vertices[2];
        const centroid = Point{ (first.point[0] + second.point[0]) / 2, (first.point[1] + second.point[1]) / 2 };
        const reflected = Point{ centroid[0] + params.alpha * (centroid[0] - third.point[0]),
             centroid[1] + params.alpha * (centroid[1] - third.point[1]) };
        const fr = function(context, reflected);
        var value = fr;
        var accepted = reflected;
        var operation: []const u8 = "reflect";
        var shrink = false;
        if (fr < first.value) {
            const expanded = along(centroid, params.chi, reflected);
            const fe = function(context, expanded);
            if (fe < fr) {
                accepted = expanded;
                value = fe;
                operation = "expand";
            }
        } else if (fr < second.value) {} else if (fr < third.value) {
            const contracted = along(centroid, params.psi, reflected);
            const fc = function(context, contracted);
            if (fc <= fr) {
                accepted = contracted;
                value = fc;
                operation = "contract_out";
            } else shrink = true;
        } else {
            const contracted = along(centroid, params.psi, third.point);
            const fc = function(context, contracted);
            if (fc < third.value) {
                accepted = contracted;
                value = fc;
                operation = "contract_in";
            } else shrink = true;
        }
        if (shrink) {
            operation = "shrink";
            for (1..3) |i| {
                const point = along(first.point, params.omega, vertices[i].point);
                vertices[i] = .{ .point = point, .value = function(context, point), .number = serial };
                serial += 1;
            }
        } else {
            vertices[2] = .{ .point = accepted, .value = value, .number = serial };
            serial += 1;
        }
        std.mem.sort(Vertex, &vertices, {}, less);
        record.* = .{ .operation = operation, .best = vertices[0] };
    }
    std.mem.sort(Vertex, &vertices, {}, less);
    return .{ .initial = initial, .final = vertices, .records = records };
}
