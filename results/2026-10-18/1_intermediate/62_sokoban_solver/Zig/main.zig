const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Flags = [100]bool;
const directions = "udlr";
const level_characters = "#-.$*@+";
const step_characters = "udlrUDLR";
const opposite = [_]usize{ 1, 0, 3, 2 };

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn printLine(out: *Writer, comptime pattern: []const u8, args: anytype) Writer.Error!void {
    try out.print(pattern ++ "\n", args);
}

fn includes(text: []const u8, letter: u8) bool {
    return std.mem.findScalar(u8, text, letter) != null;
}

fn number(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}

fn isNumber(text: []const u8) bool {
    if (text.len == 0 or text.len > 6 or (text.len > 1 and text[0] == '0')) return false;
    for (text) |letter| if (!std.ascii.isDigit(letter)) return false;
    return true;
}

fn decode(gpa: Allocator, text: []const u8, allowed: []const u8) Allocator.Error!?[]const u8 {
    var result: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < text.len) {
        const start = index;
        while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {}
        const digits = text[start..index];
        if (digits.len > 2 or (digits.len > 0 and digits[0] == '0') or index == text.len) return null;
        const letter = text[index];
        if (!includes(allowed, letter)) return null;
        const count = if (digits.len == 0) 1 else number(digits);
        try result.appendNTimes(gpa, letter, count);
        index += 1;
    }
    return result.items;
}

fn encode(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    var index: usize = 0;
    while (index < text.len) {
        var end = index + 1;
        while (end < text.len and text[end] == text[index]) : (end += 1) {}
        if (end - index > 1) {
            const digits = try std.fmt.allocPrint(gpa, "{d}", .{end - index});
            try result.appendSlice(gpa, digits);
        }
        try result.append(gpa, text[index]);
        index = end;
    }
    return result.items;
}

fn pushCount(letters: []const u8) usize {
    var count: usize = 0;
    for (letters) |letter| {
        if (std.ascii.isUpper(letter)) count += 1;
    }
    return count;
}

fn countFlags(flags: Flags) usize {
    var count: usize = 0;
    for (flags) |flag| {
        if (flag) count += 1;
    }
    return count;
}

fn firstFlag(flags: Flags) u8 {
    for (flags, 0..) |flag, cell| if (flag) return @intCast(cell);
    unreachable;
}

fn before(_: void, a: u8, b: u8) bool {
    return a < b;
}

const Boxes = struct {
    cells: [4]u8 = @splat(0),
    len: usize = 0,

    fn slice(self: *const Boxes) []const u8 {
        return self.cells[0..self.len];
    }

    fn contains(self: Boxes, cell: u8) bool {
        return includes(self.slice(), cell);
    }

    fn moved(self: Boxes, source: u8, destination: u8) Boxes {
        var result = self;
        for (result.cells[0..result.len]) |*cell| {
            if (cell.* == source) cell.* = destination;
        }
        std.mem.sort(u8, result.cells[0..result.len], {}, before);
        return result;
    }
};

const Position = struct {
    player: u8 = 0,
    boxes: Boxes = .{},

    fn same(a: Position, b: Position) bool {
        return a.player == b.player and equal(a.boxes.slice(), b.boxes.slice());
    }
};

const Transform = enum {
    ROT90, ROT180, ROT270, FLIPH, FLIPV,

    fn letters(self: Transform) []const u8 {
        return switch (self) {
            .ROT90 => "rlud",
            .ROT180 => "durl",
            .ROT270 => "lrdu",
            .FLIPH => "udrl",
            .FLIPV => "dulr",
        };
    }

    fn turn(self: Transform, letter: u8) u8 {
        const direction = std.mem.findScalar(u8, directions, std.ascii.toLower(letter)).?;
        const result = self.letters()[direction];
        return if (std.ascii.isUpper(letter)) std.ascii.toUpper(result) else result;
    }

    fn turnLetters(self: Transform, gpa: Allocator, letters: []const u8) Allocator.Error![]const u8 {
        const result = try gpa.dupe(u8, letters);
        for (result) |*letter| letter.* = self.turn(letter.*);
        return result;
    }
};

const Step = struct {
    position: Position,
    letter: u8 = 0,
    failure: ?[]const u8 = null,
};

const Level = struct {
    height: usize = 0,
    width: usize = 0,
    walls: Flags = @splat(false),
    goals: Flags = @splat(false),
    interior: Flags = @splat(false),
    dead: Flags = @splat(false),
    goal_cells: Boxes = .{},
    distances: [4][100]i16 = @splat(@splat(-1)),
    reason: ?[]const u8 = null,

    fn size(self: *const Level) usize {
        return self.height * self.width;
    }

    fn neighbor(self: *const Level, cell: u8, direction: usize) ?u8 {
        const row = cell / self.width;
        const column = cell % self.width;
        const destination: usize = switch (direction) {
            0 => if (row > 0) cell - self.width else return null,
            1 => if (row + 1 < self.height) cell + self.width else return null,
            2 => if (column > 0) cell - 1 else return null,
            3 => if (column + 1 < self.width) cell + 1 else return null,
            else => unreachable,
        };
        return @intCast(destination);
    }

    fn cellText(self: *const Level, gpa: Allocator, cell: u8) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(gpa, "{d} {d}", .{ cell / self.width + 1, cell % self.width + 1 });
    }

    fn analyze(self: *Level) void {
        self.distances = @splat(@splat(-1));
        self.dead = @splat(false);
        for (self.goal_cells.slice(), 0..) |goal, goal_index| {
            const distance = &self.distances[goal_index];
            distance[goal] = 0;
            var queue: [100]u8 = undefined;
            queue[0] = goal;
            var head: usize = 0;
            var tail: usize = 1;
            while (head < tail) : (head += 1) {
                const cell = queue[head];
                for (0..4) |direction| {
                    const box = self.neighbor(cell, opposite[direction]) orelse continue;
                    const support = self.neighbor(box, opposite[direction]) orelse continue;
                    if (self.interior[box] and self.interior[support] and distance[box] == -1) {
                        distance[box] = distance[cell] + 1;
                        queue[tail] = box;
                        tail += 1;
                    }
                }
            }
        }
        for (0..self.size()) |cell| {
            self.dead[cell] = self.interior[cell] and self.goalDistance(@intCast(cell)) == null;
        }
    }

    fn goalDistance(self: *const Level, cell: u8) ?i16 {
        var best: ?i16 = null;
        for (0..self.goal_cells.len) |index| {
            const distance = self.distances[index][cell];
            if (distance >= 0 and (best == null or distance < best.?)) best = distance;
        }
        return best;
    }

    fn onGoals(self: *const Level, boxes: Boxes) usize {
        var count: usize = 0;
        for (boxes.slice()) |box| {
            if (self.goals[box]) count += 1;
        }
        return count;
    }

    fn solved(self: *const Level, boxes: Boxes) bool {
        return self.onGoals(boxes) == boxes.len;
    }

    fn reachable(self: *const Level, player: u8, boxes: Boxes) Flags {
        var seen: Flags = @splat(false);
        seen[player] = true;
        var queue: [100]u8 = undefined;
        queue[0] = player;
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) : (head += 1) {
            for (0..4) |direction| {
                const cell = self.neighbor(queue[head], direction) orelse continue;
                if (self.interior[cell] and !seen[cell] and !boxes.contains(cell)) {
                    seen[cell] = true;
                    queue[tail] = cell;
                    tail += 1;
                }
            }
        }
        return seen;
    }

    fn representative(self: *const Level, player: u8, boxes: Boxes) u8 {
        return firstFlag(self.reachable(player, boxes));
    }

    fn walkPath(self: *const Level, gpa: Allocator, start: u8, target: u8, boxes: Boxes) Allocator.Error![]const u8 {
        var seen: Flags = @splat(false);
        var previous: [100]u8 = undefined;
        var came_direction: [100]u8 = undefined;
        var queue: [100]u8 = undefined;
        seen[start] = true;
        queue[0] = start;
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) : (head += 1) {
            const cell = queue[head];
            for (0..4) |direction| {
                const neighbor_cell = self.neighbor(cell, direction) orelse continue;
                if (self.interior[neighbor_cell] and !seen[neighbor_cell] and !boxes.contains(neighbor_cell)) {
                    seen[neighbor_cell] = true;
                    previous[neighbor_cell] = cell;
                    came_direction[neighbor_cell] = directions[direction];
                    queue[tail] = neighbor_cell;
                    tail += 1;
                }
            }
        }
        var letters: [100]u8 = undefined;
        var len: usize = 0;
        var cell = target;
        while (cell != start) {
            letters[len] = came_direction[cell];
            len += 1;
            cell = previous[cell];
        }
        std.mem.reverse(u8, letters[0..len]);
        return gpa.dupe(u8, letters[0..len]);
    }

    fn step(self: *const Level, position: Position, direction: usize) Step {
        const target = self.neighbor(position.player, direction) orelse
            return .{ .position = position, .failure = "wall" };
        if (self.walls[target]) return .{ .position = position, .failure = "wall" };
        if (!position.boxes.contains(target)) {
            return .{ .position = .{ .player = target, .boxes = position.boxes }, .letter = directions[direction] };
        }
        const beyond = self.neighbor(target, direction) orelse
            return .{ .position = position, .failure = "blocked" };
        if (self.walls[beyond] or position.boxes.contains(beyond)) {
            return .{ .position = position, .failure = "blocked" };
        }
        return .{
            .position = .{ .player = target, .boxes = position.boxes.moved(target, beyond) },
            .letter = std.ascii.toUpper(directions[direction]),
        };
    }

    fn pushable(self: *const Level, box: u8, direction: usize, boxes: Boxes, reach: Flags) bool {
        const destination = self.neighbor(box, direction) orelse return false;
        const support = self.neighbor(box, opposite[direction]) orelse return false;
        return reach[support] and self.interior[destination] and !boxes.contains(destination);
    }

    fn sideBlocked(self: *const Level, box: u8, a: u8, b: u8, boxes: Boxes, assumed: Flags) bool {
        if (self.walls[a] or self.walls[b] or assumed[a] or assumed[b]) return true;
        if (self.dead[a] and self.dead[b]) return true;
        var extended = assumed;
        extended[box] = true;
        return (boxes.contains(a) and self.frozen(a, boxes, extended)) or
            (boxes.contains(b) and self.frozen(b, boxes, extended));
    }

    fn frozen(self: *const Level, box: u8, boxes: Boxes, assumed: Flags) bool {
        const left = self.neighbor(box, 2).?;
        const right = self.neighbor(box, 3).?;
        const up = self.neighbor(box, 0).?;
        const down = self.neighbor(box, 1).?;
        return self.sideBlocked(box, left, right, boxes, assumed) and
            self.sideBlocked(box, up, down, boxes, assumed);
    }

    fn hasFrozenBox(self: *const Level, boxes: Boxes) bool {
        for (boxes.slice()) |box| {
            if (!self.goals[box] and self.frozen(box, boxes, @splat(false))) return true;
        }
        return false;
    }

    fn symbol(self: *const Level, cell: u8, position: Position, dead_map: bool) u8 {
        if (self.walls[cell]) return '#';
        if (dead_map) return if (self.goals[cell]) '.' else if (self.dead[cell]) 'x' else '-';
        if (position.player == cell) return if (self.goals[cell]) '+' else '@';
        if (position.boxes.contains(cell)) return if (self.goals[cell]) '*' else '$';
        return if (self.goals[cell]) '.' else '-';
    }

    fn mapCell(self: *const Level, kind: Transform, cell: u8) u8 {
        const row = cell / self.width;
        const column = cell % self.width;
        return @intCast(switch (kind) {
            .ROT90 => column * self.height + self.height - 1 - row,
            .ROT180 => (self.height - 1 - row) * self.width + self.width - 1 - column,
            .ROT270 => (self.width - 1 - column) * self.height + row,
            .FLIPH => row * self.width + self.width - 1 - column,
            .FLIPV => (self.height - 1 - row) * self.width + column,
        });
    }

    fn mapPosition(self: *const Level, kind: Transform, position: Position) Position {
        var result = position;
        result.player = self.mapCell(kind, position.player);
        for (result.boxes.cells[0..result.boxes.len]) |*box| box.* = self.mapCell(kind, box.*);
        std.mem.sort(u8, result.boxes.cells[0..result.boxes.len], {}, before);
        return result;
    }

    fn transformed(self: *const Level, kind: Transform) Level {
        const rotate = kind == .ROT90 or kind == .ROT270;
        var result: Level = .{
            .height = if (rotate) self.width else self.height,
            .width = if (rotate) self.height else self.width,
        };
        for (0..self.size()) |cell| {
            const moved = self.mapCell(kind, @intCast(cell));
            result.walls[moved] = self.walls[cell];
            result.goals[moved] = self.goals[cell];
            result.interior[moved] = self.interior[cell];
        }
        for (0..result.size()) |cell| {
            if (result.goals[cell]) {
                result.goal_cells.cells[result.goal_cells.len] = @intCast(cell);
                result.goal_cells.len += 1;
            }
        }
        result.analyze();
        return result;
    }
};

const Loaded = struct { level: Level, position: Position };

fn buildLevel(gpa: Allocator, rows: []const []const u8) Allocator.Error!Loaded {
    var level: Level = .{ .height = rows.len, .width = rows[0].len };
    var position: Position = .{};
    var players: usize = 0;
    for (rows, 0..) |row, row_index| {
        for (row, 0..) |symbol, column| {
            const cell: u8 = @intCast(row_index * level.width + column);
            level.walls[cell] = symbol == '#';
            level.goals[cell] = includes(".*+", symbol);
            if (level.goals[cell]) {
                level.goal_cells.cells[level.goal_cells.len] = cell;
                level.goal_cells.len += 1;
            }
            if (includes("$*", symbol)) {
                position.boxes.cells[position.boxes.len] = cell;
                position.boxes.len += 1;
            }
            if (includes("@+", symbol)) {
                if (players == 0) position.player = cell;
                players += 1;
            }
        }
    }
    if (players == 1) {
        var queue: [100]u8 = undefined;
        queue[0] = position.player;
        level.interior[position.player] = true;
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) : (head += 1) {
            for (0..4) |direction| {
                const cell = level.neighbor(queue[head], direction) orelse continue;
                if (!level.walls[cell] and !level.interior[cell]) {
                    level.interior[cell] = true;
                    queue[tail] = cell;
                    tail += 1;
                }
            }
        }
    }
    if (players != 1) {
        level.reason = try std.fmt.allocPrint(gpa, "players {d}", .{players});
    } else if (position.boxes.len == 0) {
        level.reason = "no boxes";
    } else if (position.boxes.len != level.goal_cells.len) {
        level.reason = try std.fmt.allocPrint(gpa, "boxes {d} goals {d}", .{ position.boxes.len, level.goal_cells.len });
    } else {
        for (0..level.size()) |cell| {
            const row = cell / level.width;
            const column = cell % level.width;
            if (level.interior[cell] and (row == 0 or row + 1 == level.height or column == 0 or column + 1 == level.width)) {
                level.reason = try std.fmt.allocPrint(gpa, "open {d} {d}", .{ row + 1, column + 1 });
                break;
            }
        }
        if (level.reason == null) {
            for (0..level.size()) |cell| {
                if ((level.goals[cell] or position.boxes.contains(@intCast(cell))) and !level.interior[cell]) {
                    level.reason = try std.fmt.allocPrint(gpa, "outside {d} {d}", .{ cell / level.width + 1, cell % level.width + 1 });
                    break;
                }
            }
        }
    }
    if (level.reason == null) level.analyze();
    return .{ .level = level, .position = position };
}

const SearchNode = struct {
    boxes: Boxes,
    representative: u8,
    parent: ?usize = null,
    box: u8 = 0,
    direction: usize = 0,
};
const SearchKey = struct { boxes: [4]u8, representative: u8 };
const Outcome = enum { found, no_solution, limit };
const SearchResult = struct { outcome: Outcome, expanded: usize, states: usize, notation: []const u8 = "" };

fn solutionNotation(gpa: Allocator, level: *const Level, start: Position, nodes: []const SearchNode) Allocator.Error![]const u8 {
    var pushes: std.ArrayList(SearchNode) = .empty;
    var index = nodes.len - 1;
    while (nodes[index].parent) |parent| {
        try pushes.append(gpa, nodes[index]);
        index = parent;
    }
    var notation: std.ArrayList(u8) = .empty;
    var position = start;
    var remaining = pushes.items.len;
    while (remaining > 0) {
        remaining -= 1;
        const push = pushes.items[remaining];
        const support = level.neighbor(push.box, opposite[push.direction]).?;
        const path = try level.walkPath(gpa, position.player, support, position.boxes);
        try notation.appendSlice(gpa, path);
        try notation.append(gpa, std.ascii.toUpper(directions[push.direction]));
        position = .{ .player = push.box, .boxes = position.boxes.moved(push.box, level.neighbor(push.box, push.direction).?) };
    }
    return notation.items;
}

fn pushSearch(gpa: Allocator, level: *const Level, start: Position, fixed: Boxes, target: ?u8, pruning: bool, limit: ?usize) Allocator.Error!SearchResult {
    const representative = level.representative(start.player, start.boxes);
    var nodes: std.ArrayList(SearchNode) = .empty;
    var known: std.AutoHashMapUnmanaged(SearchKey, void) = .empty;
    try nodes.append(gpa, .{ .boxes = start.boxes, .representative = representative });
    try known.put(gpa, .{ .boxes = start.boxes.cells, .representative = representative }, {});
    var expanded: usize = 0;
    while (expanded < nodes.items.len) {
        if (limit != null and expanded == limit.?) return .{ .outcome = .limit, .expanded = expanded, .states = nodes.items.len };
        const parent = expanded;
        const node = nodes.items[parent];
        expanded += 1;
        const reach = level.reachable(node.representative, node.boxes);
        for (node.boxes.slice()) |box| {
            if (fixed.contains(box)) continue;
            for (0..4) |direction| {
                if (!level.pushable(box, direction, node.boxes, reach)) continue;
                const destination = level.neighbor(box, direction).?;
                const boxes = node.boxes.moved(box, destination);
                if (pruning and (level.dead[destination] or level.hasFrozenBox(boxes))) continue;
                const next_rep = level.representative(box, boxes);
                const entry = try known.getOrPut(gpa, .{ .boxes = boxes.cells, .representative = next_rep });
                if (entry.found_existing) continue;
                try nodes.append(gpa, .{ .boxes = boxes, .representative = next_rep, .parent = parent, .box = box, .direction = direction });
                const reached = if (target) |goal| destination == goal else level.solved(boxes);
                if (reached) return .{
                    .outcome = .found, .expanded = expanded, .states = nodes.items.len,
                    .notation = try solutionNotation(gpa, level, start, nodes.items),
                };
            }
        }
    }
    return .{ .outcome = .no_solution, .expanded = expanded, .states = nodes.items.len };
}

const Kind = enum { number, steps, direction, name, transform, text };
const Command = enum {
    IMPORT, VALID, INFO, SHOW, EXPORT, MOVE, PUSH, BRING, PATH, UNDO, REDO, RESET,
    STATUS, HISTORY, BOXES, REACH, DEADSQUARES, DEADLOCK, BOUND, SAVE, RESTORE,
    CHECK, SOLVE, HINT, PLAY, TRANSFORM,

    fn kinds(self: Command) []const Kind {
        return switch (self) {
            .IMPORT => &.{.text},
            .MOVE, .CHECK => &.{.steps},
            .PUSH => &.{ .number, .number, .direction },
            .BRING => &.{ .number, .number, .number, .number },
            .PATH => &.{ .number, .number },
            .UNDO, .REDO, .SOLVE, .HINT => &.{.number},
            .SAVE, .RESTORE => &.{.name},
            .TRANSFORM => &.{.transform},
            else => &.{},
        };
    }
};

fn validArgument(gpa: Allocator, kind: Kind, text: []const u8) Allocator.Error!bool {
    switch (kind) {
        .number => return isNumber(text),
        .steps => return (try decode(gpa, text, step_characters)) != null,
        .direction => return text.len == 1 and includes(directions, text[0]),
        .name => {
            if (text.len == 0 or text.len > 8) return false;
            for (text) |letter| if (letter < 'a' or letter > 'z') return false;
            return true;
        },
        .transform => return std.meta.stringToEnum(Transform, text) != null,
        .text => return true,
    }
}

const Simulation = struct {
    position: Position,
    letters: []const u8,
    failed_step: usize = 0,
    failure: ?[]const u8 = null,
};
const Snapshot = struct { position: Position, history: []const u8 };
const Solution = struct { position: Position, notation: []const u8 };
const Assignment = struct { order: [4]usize = @splat(0), total: ?usize = null };

fn assignGoals(level: *const Level, boxes: Boxes, depth: usize, used: [4]bool, order: [4]usize, total: usize, best: *Assignment) void {
    if (depth == boxes.len) {
        if (best.total == null or total < best.total.?) best.* = .{ .order = order, .total = total };
        return;
    }
    for (0..level.goal_cells.len) |goal| {
        const distance = level.distances[goal][boxes.cells[depth]];
        if (used[goal] or distance < 0) continue;
        var next_used = used;
        var next_order = order;
        next_used[goal] = true;
        next_order[depth] = goal;
        assignGoals(level, boxes, depth + 1, next_used, next_order, total + @as(usize, @intCast(distance)), best);
    }
}

const Game = struct {
    gpa: Allocator,
    scratch: Allocator,
    out: *Writer,
    level: Level = .{},
    initial: Position = .{},
    current: Position = .{},
    history: std.ArrayList(u8) = .empty,
    redo_list: std.ArrayList(u8) = .empty,
    snapshots: std.StringHashMapUnmanaged(Snapshot) = .empty,
    solution: ?Solution = null,
    problem: []const u8 = "",

    fn fail(self: *Game, comptime pattern: []const u8, args: anytype) Error {
        self.problem = std.fmt.allocPrint(self.scratch, pattern, args) catch return error.OutOfMemory;
        return error.Invalid;
    }

    fn load(self: *Game, rows: []const []const u8) Allocator.Error!void {
        const loaded = try buildLevel(self.gpa, rows);
        self.level = loaded.level;
        self.initial = loaded.position;
        self.current = loaded.position;
        self.history.clearRetainingCapacity();
        self.redo_list.clearRetainingCapacity();
        self.snapshots.clearRetainingCapacity();
        self.solution = null;
    }

    fn cellArgument(self: *const Game, arguments: []const []const u8, index: usize) u8 {
        return @intCast((number(arguments[index]) - 1) * self.level.width + number(arguments[index + 1]) - 1);
    }

    fn simulate(self: *const Game, letters: []const u8) Allocator.Error!Simulation {
        var position = self.current;
        var notation: std.ArrayList(u8) = .empty;
        for (letters, 0..) |letter, index| {
            const direction = std.mem.findScalar(u8, directions, std.ascii.toLower(letter)).?;
            const result = self.level.step(position, direction);
            if (result.failure) |failure| return .{
                .position = position, .letters = notation.items, .failed_step = index + 1, .failure = failure,
            };
            position = result.position;
            try notation.append(self.scratch, result.letter);
        }
        return .{ .position = position, .letters = notation.items };
    }

    fn takeSteps(self: *Game, letters: []const u8) Allocator.Error!Simulation {
        const result = try self.simulate(letters);
        self.current = result.position;
        try self.history.appendSlice(self.gpa, result.letters);
        if (result.letters.len > 0) self.redo_list.clearRetainingCapacity();
        return result;
    }

    fn progress(self: *const Game, boxes: Boxes) Writer.Error!void {
        const on_goals = self.level.onGoals(boxes);
        try self.out.print("goals {d}/{d}", .{ on_goals, boxes.len });
        if (on_goals == boxes.len) try self.out.writeAll(" solved");
        try self.out.writeByte('\n');
    }

    fn counted(self: *const Game, label: []const u8, letters: []const u8) Writer.Error!void {
        try self.out.print("{s} {d}", .{ label, letters.len });
        if (letters.len > 0) try self.out.print(" {s}", .{letters});
        try self.out.writeByte('\n');
    }

    fn show(self: *const Game, dead_map: bool, export_level: bool) Error!void {
        if (export_level) try self.out.writeAll("level ");
        for (0..self.level.height) |row| {
            var symbols: [10]u8 = undefined;
            for (0..self.level.width) |column| {
                symbols[column] = self.level.symbol(@intCast(row * self.level.width + column), self.current, dead_map);
            }
            const text = symbols[0..self.level.width];
            if (export_level) {
                if (row > 0) try self.out.writeByte('|');
                try self.out.writeAll(try encode(self.scratch, text));
            } else try printLine(self.out, "{s}", .{text});
        }
        if (export_level) try self.out.writeByte('\n');
    }

    fn solveOrHint(self: *Game, command: Command, limit: usize) Error!void {
        if (command == .SOLVE) self.solution = null;
        if (self.level.solved(self.current.boxes)) {
            try self.out.writeAll("already solved\n");
            return;
        }
        const result = try pushSearch(self.scratch, &self.level, self.current, .{}, null, true, limit);
        if (result.outcome != .found) {
            try printLine(self.out, "{s} expanded {d} states {d}", .{
                if (result.outcome == .limit) @as([]const u8, "limit") else "no solution", result.expanded, result.states,
            });
            return;
        }
        const notation = result.notation;
        if (command == .SOLVE) {
            try printLine(self.out, "solution pushes {d} moves {d} expanded {d} states {d}", .{
                pushCount(notation), notation.len, result.expanded, result.states,
            });
            try printLine(self.out, "{s}", .{notation});
            self.solution = .{ .position = self.current, .notation = try self.gpa.dupe(u8, notation) };
        } else {
            var end: usize = 0;
            while (!std.ascii.isUpper(notation[end])) : (end += 1) {}
            const part = notation[0 .. end + 1];
            _ = try self.takeSteps(part);
            try printLine(self.out, "hint {s}", .{part});
        }
    }

    fn process(self: *Game, command: Command, a: []const []const u8) Error!void {
        switch (command) {
            .IMPORT => {
                var rows: std.ArrayList([]const u8) = .empty;
                var parts = std.mem.splitScalar(u8, a[0], '|');
                while (parts.next()) |part| {
                    const row = (try decode(self.scratch, part, level_characters)) orelse return self.fail("bad level", .{});
                    try rows.append(self.scratch, row);
                }
                if (rows.items.len > 10 or rows.items[0].len == 0 or rows.items[0].len > 10) return self.fail("bad level", .{});
                for (rows.items) |row| if (row.len != rows.items[0].len) return self.fail("bad level", .{});
                try self.load(rows.items);
                try printLine(self.out, "loaded {d}x{d}", .{ self.level.height, self.level.width });
            },
            .VALID => {
                if (self.level.reason) |reason| try printLine(self.out, "invalid {s}", .{reason})
                else try self.out.writeAll("valid\n");
            },
            .INFO => try printLine(self.out, "size {d}x{d} walls {d} cells {d} boxes {d} dead {d}", .{
                self.level.height, self.level.width, countFlags(self.level.walls), countFlags(self.level.interior), self.current.boxes.len, countFlags(self.level.dead),
            }),
            .SHOW => try self.show(false, false),
            .EXPORT => try self.show(false, true),
            .MOVE => {
                const result = try self.takeSteps((try decode(self.scratch, a[0], step_characters)).?);
                if (result.letters.len > 0) try printLine(self.out, "moved {s}", .{result.letters});
                if (result.failure) |failure| return self.fail("step {d} {s}", .{ result.failed_step, failure });
            },
            .PUSH => {
                const box = self.cellArgument(a, 0);
                const direction = std.mem.findScalar(u8, directions, a[2][0]).?;
                if (!self.current.boxes.contains(box)) return self.fail("no box", .{});
                const destination = self.level.neighbor(box, direction) orelse return self.fail("blocked", .{});
                if (!self.level.interior[destination] or self.current.boxes.contains(destination)) return self.fail("blocked", .{});
                const support = self.level.neighbor(box, opposite[direction]) orelse return self.fail("unreachable", .{});
                const reach = self.level.reachable(self.current.player, self.current.boxes);
                if (!reach[support]) return self.fail("unreachable", .{});
                const path = try self.level.walkPath(self.scratch, self.current.player, support, self.current.boxes);
                const sequence = try std.mem.concat(self.scratch, u8, &.{ path, a[2] });
                const result = try self.takeSteps(sequence);
                try printLine(self.out, "pushed {s}", .{result.letters});
            },
            .BRING => {
                const source = self.cellArgument(a, 0);
                const target = self.cellArgument(a, 2);
                if (!self.current.boxes.contains(source)) return self.fail("no box", .{});
                if (source == target) {
                    try self.out.writeAll("brought 0\n");
                    return;
                }
                var fixed: Boxes = .{};
                for (self.current.boxes.slice()) |box| {
                    if (box == source) continue;
                    fixed.cells[fixed.len] = box;
                    fixed.len += 1;
                }
                const result = try pushSearch(self.scratch, &self.level, self.current, fixed, target, false, null);
                if (result.outcome != .found) return self.fail("no route", .{});
                _ = try self.takeSteps(result.notation);
                try printLine(self.out, "brought {d} {s}", .{ pushCount(result.notation), result.notation });
            },
            .PATH => {
                const target = self.cellArgument(a, 0);
                const reach = self.level.reachable(self.current.player, self.current.boxes);
                if (!reach[target]) return self.fail("unreachable", .{});
                const path = try self.level.walkPath(self.scratch, self.current.player, target, self.current.boxes);
                const result = try self.takeSteps(path);
                try self.counted("path", result.letters);
            },
            .UNDO => {
                if (self.history.items.len == 0) return self.fail("nothing to undo", .{});
                const count = @min(number(a[0]), self.history.items.len);
                for (0..count) |_| {
                    const letter = self.history.items[self.history.items.len - 1];
                    self.history.items.len -= 1;
                    const lower = std.ascii.toLower(letter);
                    const direction = std.mem.findScalar(u8, directions, lower).?;
                    const player = self.current.player;
                    if (std.ascii.isUpper(letter)) {
                        self.current.boxes = self.current.boxes.moved(self.level.neighbor(player, direction).?, player);
                    }
                    self.current.player = self.level.neighbor(player, opposite[direction]).?;
                    try self.redo_list.append(self.gpa, lower);
                }
                try printLine(self.out, "undone {d}", .{count});
            },
            .REDO => {
                if (self.redo_list.items.len == 0) return self.fail("nothing to redo", .{});
                const count = @min(number(a[0]), self.redo_list.items.len);
                for (0..count) |_| {
                    const letter = self.redo_list.items[self.redo_list.items.len - 1];
                    self.redo_list.items.len -= 1;
                    const result = self.level.step(self.current, std.mem.findScalar(u8, directions, letter).?);
                    self.current = result.position;
                    try self.history.append(self.gpa, result.letter);
                }
                try printLine(self.out, "redone {d}", .{count});
            },
            .RESET => {
                self.current = self.initial;
                self.history.clearRetainingCapacity();
                self.redo_list.clearRetainingCapacity();
                try self.out.writeAll("reset\n");
            },
            .STATUS => {
                try self.out.print("moves {d} pushes {d} ", .{ self.history.items.len, pushCount(self.history.items) });
                try self.progress(self.current.boxes);
            },
            .HISTORY => try self.counted("history", self.history.items),
            .BOXES => {
                try printLine(self.out, "boxes {d}", .{self.current.boxes.len});
                const reach = self.level.reachable(self.current.player, self.current.boxes);
                for (self.current.boxes.slice()) |box| {
                    try self.out.print("box {s} ", .{try self.level.cellText(self.scratch, box)});
                    if (self.level.goalDistance(box)) |distance| try self.out.print("{d} ", .{distance})
                    else try self.out.writeAll("dead ");
                    var letters: [4]u8 = undefined;
                    var len: usize = 0;
                    for (0..4) |direction| {
                        if (self.level.pushable(box, direction, self.current.boxes, reach)) {
                            letters[len] = directions[direction];
                            len += 1;
                        }
                    }
                    try printLine(self.out, "{s}", .{if (len == 0) @as([]const u8, "-") else letters[0..len]});
                }
            },
            .REACH => {
                const reach = self.level.reachable(self.current.player, self.current.boxes);
                try printLine(self.out, "reach {d} first {s}", .{ countFlags(reach), try self.level.cellText(self.scratch, firstFlag(reach)) });
            },
            .DEADSQUARES => {
                try printLine(self.out, "dead {d}", .{countFlags(self.level.dead)});
                try self.show(true, false);
            },
            .DEADLOCK => {
                for (self.current.boxes.slice()) |box| {
                    if (self.level.dead[box]) {
                        try printLine(self.out, "deadlock dead {s}", .{try self.level.cellText(self.scratch, box)});
                        return;
                    }
                }
                for (self.current.boxes.slice()) |box| {
                    if (!self.level.goals[box] and self.level.frozen(box, self.current.boxes, @splat(false))) {
                        try printLine(self.out, "deadlock frozen {s}", .{try self.level.cellText(self.scratch, box)});
                        return;
                    }
                }
                try self.out.writeAll("no deadlock\n");
            },
            .BOUND => {
                var best: Assignment = .{};
                assignGoals(&self.level, self.current.boxes, 0, @splat(false), @splat(0), 0, &best);
                const total = best.total orelse {
                    try self.out.writeAll("bound none\n");
                    return;
                };
                try printLine(self.out, "bound {d}", .{total});
                for (self.current.boxes.slice(), 0..) |box, index| {
                    const goal = best.order[index];
                    try printLine(self.out, "box {s} goal {s} pushes {d}", .{
                        try self.level.cellText(self.scratch, box), try self.level.cellText(self.scratch, self.level.goal_cells.cells[goal]), self.level.distances[goal][box],
                    });
                }
            },
            .SAVE => {
                const entry = try self.snapshots.getOrPut(self.gpa, a[0]);
                if (!entry.found_existing) entry.key_ptr.* = try self.gpa.dupe(u8, a[0]);
                entry.value_ptr.* = .{ .position = self.current, .history = try self.gpa.dupe(u8, self.history.items) };
                try printLine(self.out, "saved {s} moves {d}", .{ a[0], self.history.items.len });
            },
            .RESTORE => {
                const snapshot = self.snapshots.get(a[0]) orelse return self.fail("no snapshot {s}", .{a[0]});
                self.current = snapshot.position;
                self.history.clearRetainingCapacity();
                try self.history.appendSlice(self.gpa, snapshot.history);
                self.redo_list.clearRetainingCapacity();
                try printLine(self.out, "restored {s} moves {d}", .{ a[0], self.history.items.len });
            },
            .CHECK => {
                const result = try self.simulate((try decode(self.scratch, a[0], step_characters)).?);
                if (result.failure) |failure| {
                    try printLine(self.out, "check fail step {d} {s}", .{ result.failed_step, failure });
                } else {
                    try self.out.print("check ok moves {d} pushes {d} ", .{ result.letters.len, pushCount(result.letters) });
                    try self.progress(result.position.boxes);
                }
            },
            .SOLVE, .HINT => try self.solveOrHint(command, number(a[0])),
            .PLAY => {
                const solution = self.solution orelse return self.fail("no solution", .{});
                if (!solution.position.same(self.current)) return self.fail("no solution", .{});
                _ = try self.takeSteps(solution.notation);
                try printLine(self.out, "played pushes {d} moves {d}", .{ pushCount(solution.notation), solution.notation.len });
            },
            .TRANSFORM => {
                const kind = std.meta.stringToEnum(Transform, a[0]).?;
                const old = self.level;
                self.level = old.transformed(kind);
                self.initial = old.mapPosition(kind, self.initial);
                self.current = old.mapPosition(kind, self.current);
                for (self.history.items) |*letter| letter.* = kind.turn(letter.*);
                for (self.redo_list.items) |*letter| letter.* = kind.turn(letter.*);
                var snapshots = self.snapshots.valueIterator();
                while (snapshots.next()) |snapshot| {
                    snapshot.position = old.mapPosition(kind, snapshot.position);
                    snapshot.history = try kind.turnLetters(self.gpa, snapshot.history);
                }
                if (self.solution) |*solution| {
                    solution.position = old.mapPosition(kind, solution.position);
                    solution.notation = try kind.turnLetters(self.gpa, solution.notation);
                }
                try printLine(self.out, "transformed {d}x{d}", .{ self.level.height, self.level.width });
            },
        }
    }

    fn execute(self: *Game, words: []const []const u8, rows: []const []const u8) Error!void {
        if (equal(words[0], "LOAD")) {
            const width = number(words[2]);
            for (rows, 0..) |row, index| {
                if (row.len != width) return self.fail("bad row {d}", .{index + 1});
                for (row) |symbol| if (!includes(level_characters, symbol)) return self.fail("bad row {d}", .{index + 1});
            }
            try self.load(rows);
            try printLine(self.out, "loaded {d}x{d}", .{ rows.len, width });
            return;
        }
        const command = std.meta.stringToEnum(Command, words[0]) orelse return self.fail("unknown command {s}", .{words[0]});
        const arguments = words[1..];
        const kinds = command.kinds();
        if (arguments.len != kinds.len) return self.fail("bad arguments", .{});
        for (kinds, arguments) |kind, text| if (!try validArgument(self.scratch, kind, text)) return self.fail("bad arguments", .{});
        if (command != .IMPORT and command != .VALID) {
            if (self.level.reason != null) return self.fail("invalid level", .{});
            const cells: usize = if (command == .BRING) 2 else if (command == .PATH or command == .PUSH) 1 else 0;
            for (0..cells) |index| {
                const row = number(arguments[2 * index]);
                const column = number(arguments[2 * index + 1]);
                if (row < 1 or row > self.level.height or column < 1 or column > self.level.width) return self.fail("bad value", .{});
            }
            if ((command == .UNDO or command == .REDO) and number(arguments[0]) < 1) return self.fail("bad value", .{});
            if ((command == .SOLVE or command == .HINT) and (number(arguments[0]) < 1 or number(arguments[0]) > 100000)) return self.fail("bad value", .{});
        }
        try self.process(command, arguments);
    }
};

fn splitWords(gpa: Allocator, line: []const u8) Allocator.Error![]const []const u8 {
    var words: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.splitScalar(u8, line, ' ');
    while (pieces.next()) |piece| try words.append(gpa, piece);
    return words.items;
}

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.splitScalar(u8, text, '\n');
    while (pieces.next()) |piece| try lines.append(gpa, piece);
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var game: Game = .{ .gpa = gpa, .scratch = scratch.allocator(), .out = &output.interface };
    const header = try splitWords(gpa, lines.items[0]);
    const height = number(header[0]);
    try game.load(lines.items[1 .. height + 1]);
    const count = number(lines.items[height + 1]);
    var index = height + 2;
    for (0..count) |_| {
        _ = scratch.reset(.retain_capacity);
        const words = try splitWords(game.scratch, lines.items[index]);
        index += 1;
        var rows: []const []const u8 = &.{};
        if (equal(words[0], "LOAD")) {
            const load_height = number(words[1]);
            rows = lines.items[index .. index + load_height];
            index += load_height;
        }
        game.execute(words, rows) catch |err| {
            if (err != error.Invalid) return err;
            try printLine(&output.interface, "error: {s}", .{game.problem});
        };
    }
    try output.interface.flush();
}
