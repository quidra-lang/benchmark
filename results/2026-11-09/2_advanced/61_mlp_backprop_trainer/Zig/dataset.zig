const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}
const network = @import("network.zig");
const layers = @import("layers.zig");
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn real(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub const Image = struct { id: []const u8, pixels: []const u8, label: usize, input: [64]f64 = [_]f64{0} ** 64 };
pub const Optimizer = enum { SGD, MOMENTUM, ADAM };
pub const Run = struct { name: []const u8, optimizer: Optimizer, network: usize, eta: f64,
     decay: f64, mu: f64 = 0, beta1: f64 = 0, beta2: f64 = 0, epsilon: f64 = 0 };
pub const Params = struct { seed: i64 = 0, batch: usize = 0, epochs: usize = 0, patience: usize = 0,
     lr_step: usize = 0, stride: usize = 0, bins: usize = 0, gamma: f64 = 0, prune: []const usize = &.{},
     noise: []const i64 = &.{}, runs: std.ArrayList(Run) = .empty };
pub const Input = struct { width: usize, height: usize, classes: usize, train: []const Image,
     test_data: []const Image, networks: []network.Network, params: Params };
fn images(io: std.Io, path: []const u8) ![]const Image {
    const lines = try readLines(io, path);
    const out = alloc(Image, lines.len - 1);
    for (lines[1..], out) |line, *image| {
        const row = split(line, ',');
        image.* = .{ .id = row[0], .label = u(number(row[1])), .pixels = row[2] };
        for (row[2], 0..) |pixel, i| image.input[i] = if (pixel == '1') 1 else 0;
    }
    return out;
}
fn networkIndex(networks: []const network.Network, name: []const u8) usize {
    for (networks, 0..) |net, i| if (eq(net.name, name)) return i;
    unreachable;
}
pub fn load(io: std.Io) !Input {
    const definitions = try readLines(io, "input/network.txt");
    const dimensions = words(definitions[0]);
    const width = u(number(dimensions[1]));
    const height = u(number(dimensions[2]));
    var networks: std.ArrayList(network.Network) = .empty;
    for (definitions[1..]) |line| {
        if (line.len == 0) continue;
        const row = words(line);
        if (eq(row[0], "NETWORK")) append(network.Network, &networks, .{ .name = row[1], .inputs = width * height }) else networks.items[networks.items.len - 1].addLayer(u(number(row[1])),
             std.meta.stringToEnum(layers.Function, row[2]).?, eq(row[0], "OUTPUT"));
    }
    const weights = try readLines(io, "input/weights.txt");
    var current: usize = 0;
    var row_index: usize = 0;
    while (row_index < weights.len) {
        if (weights[row_index].len == 0) {
            row_index += 1;
            continue;
        }
        const row = words(weights[row_index]);
        if (eq(row[0], "NETWORK")) {
            current = networkIndex(networks.items, row[1]);
            row_index += 1;
        } else {
            const layer = networks.items[current].layers[u(number(row[1])) - 1];
            row_index += 1;
            for (0..layer.units) |j| {
                const values = words(weights[row_index]);
                for (values[1..], 0..) |value, i| networks.items[current].initial[layer.weights + j * layer.inputs + i] = real(value);
                row_index += 1;
            }
            const biases = words(weights[row_index]);
            for (biases[1..], 0..) |value, j| networks.items[current].initial[layer.biases + j] = real(value);
            row_index += 1;
        }
    }
    var params: Params = .{};
    for (try readLines(io, "input/params.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "SEED")) params.seed = number(row[1]) else if (eq(key, "BATCH_SIZE")) params.batch = u(number(row[1])) else if (eq(key,
             "MAX_EPOCHS")) params.epochs = u(number(row[1])) else if (eq(key, "PATIENCE")) params.patience = u(number(row[1])) else if (eq(key,
             "LR_STEP")) {
            params.lr_step = u(number(row[1]));
            params.gamma = real(row[2]);
        } else if (eq(key, "GRADIENT_CHECK_STRIDE")) params.stride = u(number(row[1])) else if (eq(key,
             "CALIBRATION_BINS")) params.bins = u(number(row[1])) else if (eq(key, "PRUNE")) {
            const values = alloc(usize, row.len - 1);
            for (row[1..], values) |value, *destination| destination.* = u(number(value));
            params.prune = values;
        } else if (eq(key, "NOISE")) {
            const values = alloc(i64, row.len - 1);
            for (row[1..], values) |value, *destination| destination.* = number(value);
            params.noise = values;
        } else if (eq(key, "RUN")) {
            var run: Run = .{ .name = row[1], .network = networkIndex(networks.items, row[2]),
                 .optimizer = std.meta.stringToEnum(Optimizer, row[3]).?, .eta = real(row[4]),
                 .decay = real(row[5]) };
            if (run.optimizer == .MOMENTUM) run.mu = real(row[6]) else if (run.optimizer == .ADAM) {
                run.beta1 = real(row[6]);
                run.beta2 = real(row[7]);
                run.epsilon = real(row[8]);
            }
            append(Run, &params.runs, run);
        }
    }
    return .{ .width = width, .height = height, .classes = networks.items[0].classes, .train = try images(io,
         "input/train.csv"), .test_data = try images(io, "input/test.csv"), .networks = networks.items,
         .params = params };
}
pub const Random = struct {
    state: i64,
    pub fn draw(self: *Random) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return self.state;
    }
    pub fn shuffle(self: *Random, order: []usize) void {
        var i = order.len;
        while (i >= 2) : (i -= 1) {
            const j = u(@mod(self.draw(), n(i)));
            std.mem.swap(usize, &order[i - 1], &order[j]);
        }
    }
};
