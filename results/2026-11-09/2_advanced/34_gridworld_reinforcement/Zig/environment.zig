const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Table = [][4]i64;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn zero(comptime T: type, count: usize) []T {
    const values = alloc(T, count);
    @memset(values, std.mem.zeroes(T));
    return values;
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
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub const World = struct { rows: usize, cols: usize, start: usize, cells: []u8, states: []usize, terminals: []usize,
     index: []?usize, terminal_index: []?usize, wind: []usize, rewards: []i64, moves: [][4]usize };
pub fn terminal(w: *const World, cell: usize) bool {
    return w.terminal_index[cell] != null;
}
pub fn ending(w: *const World, cell: usize) []const u8 {
    return if (terminal(w, cell)) (if (w.cells[cell] == 'G') "goal" else "pit") else "timeout";
}
pub fn move(w: *const World, cell: usize, action: usize) usize {
    const offsets = [4]i64{ -n(w.cols), 1, n(w.cols), -1 };
    var next = u(n(cell) + offsets[action]);
    if (w.cells[next] == '#') next = cell;
    if (terminal(w, next)) return next;
    for (0..w.wind[cell % w.cols]) |_| {
        if (w.cells[next - w.cols] == '#') break;
        next -= w.cols;
        if (terminal(w, next)) break;
    }
    return next;
}
pub fn readWorld(io: std.Io) !World {
    const lines = try readLines(io, "input/world.txt");
    const rows = u(number(split(lines[0], ' ')[1]));
    const cols = u(number(split(lines[1], ' ')[1]));
    const cells = alloc(u8, rows * cols);
    for (0..rows) |r| @memcpy(cells[r * cols .. (r + 1) * cols], lines[r + 2]);
    const index = alloc(?usize, cells.len);
    const terminal_index = alloc(?usize, cells.len);
    @memset(index, null);
    @memset(terminal_index, null);
    var states: std.ArrayList(usize) = .empty;
    var terminals: std.ArrayList(usize) = .empty;
    var start: usize = 0;
    for (cells, 0..) |kind, cell| {
        if (kind == '#') continue;
        if (kind == 'G' or kind == 'P') {
            terminal_index[cell] = terminals.items.len;
            append(usize, &terminals, cell);
        } else {
            index[cell] = states.items.len;
            append(usize, &states, cell);
            if (kind == 'S') start = cell;
        }
    }
    const wind = alloc(usize, cols);
    for (wind, lines[rows + 2][5..]) |*value, c| value.* = c - '0';
    const rewards = zero(i64, cells.len);
    const words = split(lines[rows + 3], ' ');
    for (terminals.items, words[1..]) |cell, word| rewards[cell] = number(word);
    const w: World = .{ .rows = rows, .cols = cols, .start = start, .cells = cells, .states = states.items,
         .terminals = terminals.items, .index = index, .terminal_index = terminal_index, .wind = wind,
         .rewards = rewards, .moves = alloc([4]usize, states.items.len) };
    for (states.items, w.moves) |cell, *moves| for (moves, 0..) |*next, action| {
        next.* = move(&w, cell, action);
    };
    return w;
}
pub const Transition = struct { cell: usize, weight: i64 };
pub const Transitions = struct {
    data: [3]Transition = undefined,
    len: usize = 0,
    pub fn items(self: *const Transitions) []const Transition {
        return self.data[0..self.len];
    }
};
pub const Model = struct {
    world: *const World,
    q: i64,
    floor_slip: i64,
    ice_slip: i64,
    step_reward: i64,
    pub fn reward(self: Model, cell: usize) i64 {
        return if (terminal(self.world, cell)) self.world.rewards[cell] else self.step_reward;
    }
    pub fn slip(self: Model, state: usize) i64 {
        return if (self.world.cells[self.world.states[state]] == '~') self.ice_slip else self.floor_slip;
    }
    pub fn transitions(self: Model, state: usize, action: usize) Transitions {
        const p = self.slip(state);
        const weights = [3]i64{ self.q - 2 * p, p, p };
        const directions = [3]usize{ action, (action + 1) % 4, (action + 3) % 4 };
        var out: Transitions = .{};
        for (weights, directions) |weight, direction| if (weight > 0) {
            out.data[out.len] = .{ .cell = self.world.moves[state][direction], .weight = weight };
            out.len += 1;
        };
        return out;
    }
};
pub const Random = struct {
    value: i64,
    pub fn draw(self: *Random) i64 {
        self.value = @mod(48271 * self.value, 2147483647);
        return self.value;
    }
};
pub const Outcome = struct { cell: usize, reward: i64 };
pub fn step(model: Model, state: usize, action: usize, random: *Random) Outcome {
    const p = model.slip(state);
    const t = @mod(random.draw(), model.q);
    const direction = if (t < model.q - 2 * p) action else if (t < model.q - p) (action + 1) % 4 else (action + 3) % 4;
    const cell = model.world.moves[state][direction];
    return .{ .cell = cell, .reward = model.reward(cell) };
}
