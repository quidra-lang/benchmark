const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const max_cells = 900;
const max_component = 30;
const State = enum { ready, playing, won, lost };
const Mark = enum { none, flag, question };
const Safety = enum { block, cell, none };
const Preset = enum { beginner, intermediate, expert };
const MoveKind = enum { reveal, flag, unflag, question, chord, auto_reveal, auto_flag, guess };
const Move = struct {
    kind: MoveKind,
    cell: usize,
    fn name(move: Move) []const u8 {
        return switch (move.kind) {
            .auto_reveal => "auto-reveal",
            .auto_flag => "auto-flag",
            else => @tagName(move.kind),
        };
    }
};

const Command = enum {
    NEW,
    PRESET,
    LAYOUT,
    SAFETY,
    RESTART,
    REVEAL,
    FLAG,
    UNFLAG,
    QUESTION,
    CHORD,
    UNDO,
    SHOW,
    STATUS,
    CELL,
    HISTORY,
    REPLAY,
    HINT,
    AUTO,
    ANALYZE,
    PROB,
    FRONTIER,
    SOLVE,
    BOARDINFO,
    STATS,
    fn arity(command: Command) usize {
        return switch (command) {
            .NEW => 4,
            .PRESET, .LAYOUT, .REVEAL, .FLAG, .UNFLAG, .QUESTION, .CHORD, .CELL, .PROB => 2,
            .SAFETY, .HISTORY, .REPLAY => 1,
            else => 0,
        };
    }
    fn hasCell(command: Command) bool {
        return switch (command) {
            .REVEAL, .FLAG, .UNFLAG, .QUESTION, .CHORD, .CELL, .PROB => true,
            else => false,
        };
    }
    fn activeOnly(command: Command) bool {
        return switch (command) {
            .REVEAL, .FLAG, .UNFLAG, .QUESTION, .CHORD, .UNDO, .HINT, .AUTO, .ANALYZE, .PROB, .FRONTIER, .SOLVE => true,
            else => false,
        };
    }
    fn undoable(command: Command) bool {
        return switch (command) {
            .REVEAL, .FLAG, .UNFLAG, .QUESTION, .CHORD, .AUTO, .SOLVE => true,
            else => false,
        };
    }
    fn undoName(command: Command) []const u8 {
        return switch (command) {
            .REVEAL => "reveal",
            .FLAG => "flag",
            .UNFLAG => "unflag",
            .QUESTION => "question",
            .CHORD => "chord",
            .AUTO => "auto",
            .SOLVE => "solve",
            else => unreachable,
        };
    }
};

const Position = struct {
    index: usize,
    width: usize,
    pub fn format(value: Position, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{d},{d}", .{ value.index % value.width, value.index / value.width });
    }
};
const Reason = struct { kind: enum { single, subset, count }, first: usize = 0, second: usize = 0 };
const Explanation = struct {
    reason: Reason,
    width: usize,
    pub fn format(value: Explanation, out: *std.Io.Writer) std.Io.Writer.Error!void {
        const first: Position = .{ .index = value.reason.first, .width = value.width };
        const second: Position = .{ .index = value.reason.second, .width = value.width };
        switch (value.reason.kind) {
            .single => try out.print("single {f}", .{first}),
            .subset => try out.print("subset {f} {f}", .{ first, second }),
            .count => try out.writeAll("count"),
        }
    }
};
const OptionalNumber = struct {
    value: ?usize,
    pub fn format(value: OptionalNumber, out: *std.Io.Writer) std.Io.Writer.Error!void {
        if (value.value) |number| try out.print("{d}", .{number}) else try out.writeAll("-");
    }
};
const Nearby = struct {
    cells: [8]usize = @splat(0),
    len: usize = 0,
    fn append(nearby: *Nearby, cell: usize) void {
        nearby.cells[nearby.len] = cell;
        nearby.len += 1;
    }
    fn contains(nearby: *const Nearby, cell: usize) bool {
        for (nearby.cells[0..nearby.len]) |other| if (cell == other) return true;
        return false;
    }
};
const Constraint = struct { cell: usize, unknown: Nearby, remaining: i32 };
const Constraints = struct { items: [max_cells]Constraint = undefined, len: usize = 0 };
const Deduction = struct {
    safe: [max_cells]?Reason = @splat(null),
    mines: [max_cells]?Reason = @splat(null),
    fn any(result: *const Deduction, size: usize) bool {
        for (result.safe[0..size], result.mines[0..size]) |safe, mine| if (safe != null or mine != null) return true;
        return false;
    }
};
const Snapshot = struct { command: Command, revealed: [max_cells]bool, marks: [max_cells]Mark, move_count: usize };
const Totals = struct {
    rounds: usize = 0,
    flagged: usize = 0,
    opened: usize = 0,
    guesses: usize = 0,
    fn add(totals: *Totals, other: Totals) void {
        totals.rounds += other.rounds;
        totals.flagged += other.flagged;
        totals.opened += other.opened;
    }
};

const Component = struct {
    cells: std.ArrayList(usize) = .empty,
    constraints: std.ArrayList(Constraint) = .empty,
    configurations: usize = 0,
    minimum: usize = 0,
    maximum: usize = 0,
    mine_counts: [max_component]usize = @splat(0),
    counted: bool = false,
    fn count(component: *Component) void {
        if (component.counted) return;
        component.counted = true;
        component.minimum = component.cells.items.len;
        for (component.constraints.items) |c| if (c.remaining < 0 or c.remaining > @as(i32, @intCast(c.unknown.len))) return;
        var search: Counter = .{ .component = component };
        var index: [max_cells]usize = undefined;
        for (component.cells.items, 0..) |cell, i| {
            index[cell] = i;
            search.order[i] = i;
        }
        for (component.constraints.items, 0..) |c, i| {
            search.remaining[i] = @intCast(c.unknown.len);
            for (c.unknown.cells[0..c.unknown.len]) |cell| search.links[index[cell]].append(i);
        }
        const size = component.cells.items.len;
        std.mem.sort(usize, search.order[0..size], @as([]const Nearby, search.links[0..size]), Counter.before);
        search.visit(0, 0);
    }
};

const Counter = struct {
    component: *Component,
    links: [max_component]Nearby = @splat(.{}),
    order: [max_component]usize = undefined,
    assignment: [max_component]usize = @splat(0),
    remaining: [max_cells]i32 = @splat(0),
    sums: [max_cells]i32 = @splat(0),
    fn before(links: []const Nearby, a: usize, b: usize) bool {
        return if (links[a].len != links[b].len) links[a].len > links[b].len else a < b;
    }
    fn visit(search: *Counter, depth: usize, mines: usize) void {
        const component = search.component;
        if (depth == component.cells.items.len) {
            component.configurations += 1;
            component.minimum = @min(component.minimum, mines);
            component.maximum = @max(component.maximum, mines);
            for (0..component.cells.items.len) |i| component.mine_counts[i] += search.assignment[i];
            return;
        }
        const variable = search.order[depth];
        const links = &search.links[variable];
        for (0..2) |value| {
            search.assignment[variable] = value;
            var possible = true;
            for (links.cells[0..links.len]) |c| {
                search.remaining[c] -= 1;
                search.sums[c] += @intCast(value);
                const required = component.constraints.items[c].remaining;
                if (search.sums[c] > required or search.sums[c] + search.remaining[c] < required) possible = false;
            }
            if (possible) search.visit(depth + 1, mines + value);
            for (links.cells[0..links.len]) |c| {
                search.sums[c] -= @intCast(value);
                search.remaining[c] += 1;
            }
        }
    }
};

const Frontier = struct { components: std.ArrayList(Component) = .empty, at: [max_cells]?usize = @splat(null) };

fn rootOf(parents: *[max_cells]usize, first: usize) usize {
    var cell = first;
    while (parents[cell] != cell) {
        parents[cell] = parents[parents[cell]];
        cell = parents[cell];
    }
    return cell;
}

const Game = struct {
    gpa: Allocator,
    width: usize,
    height: usize,
    mine_count: usize,
    seed: u64,
    placed: bool = false,
    mines: [max_cells]bool = @splat(false),
    numbers: [max_cells]u8 = @splat(0),
    neighbors: [max_cells]Nearby = @splat(.{}),
    revealed: [max_cells]bool = @splat(false),
    marks: [max_cells]Mark = @splat(.none),
    state: State = .ready,
    exploded: usize = 0,
    moves: std.ArrayList(Move) = .empty,
    undo: std.ArrayList(Snapshot) = .empty,

    fn initialize(game: *Game, gpa: Allocator, width: usize, height: usize, mines: usize, seed: u64, placement: ?[max_cells]bool) void {
        game.* = .{ .gpa = gpa, .width = width, .height = height, .mine_count = mines, .seed = seed };
        for (0..game.cellCount()) |cell| {
            const x: i32 = @intCast(cell % width);
            const y: i32 = @intCast(cell / width);
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) {
                    const nx = x + dx;
                    const ny = y + dy;
                    if ((dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < @as(i32, @intCast(width)) and ny < @as(i32, @intCast(height)))
                        game.neighbors[cell].append(@as(usize, @intCast(ny)) * width + @as(usize, @intCast(nx)));
                }
            }
        }
        if (placement) |fixed| game.setPlacement(fixed);
    }
    fn cellCount(game: *const Game) usize {
        return game.width * game.height;
    }
    fn isFinished(game: *const Game) bool {
        return game.state == .won or game.state == .lost;
    }
    fn remainingMines(game: *const Game) i32 {
        var left: i32 = @intCast(game.mine_count);
        for (game.marks[0..game.cellCount()]) |mark| if (mark == .flag) {
            left -= 1;
        };
        return left;
    }
    fn revealedCount(game: *const Game) usize {
        var opened: usize = 0;
        for (game.revealed[0..game.cellCount()]) |value| if (value) {
            opened += 1;
        };
        return opened;
    }
    fn position(game: *const Game, cell: usize) Position {
        return .{ .index = cell, .width = game.width };
    }
    fn isUnknown(game: *const Game, cell: usize) bool {
        return !game.revealed[cell] and game.marks[cell] != .flag;
    }
    fn flagNeighbors(game: *const Game, cell: usize) usize {
        var flags: usize = 0;
        const nearby = &game.neighbors[cell];
        for (nearby.cells[0..nearby.len]) |neighbor| if (game.marks[neighbor] == .flag) {
            flags += 1;
        };
        return flags;
    }
    fn unknownNeighbors(game: *const Game, cell: usize) Nearby {
        var unknown: Nearby = .{};
        const nearby = &game.neighbors[cell];
        for (nearby.cells[0..nearby.len]) |neighbor| if (game.isUnknown(neighbor)) {
            unknown.append(neighbor);
        };
        return unknown;
    }
    fn setPlacement(game: *Game, placement: [max_cells]bool) void {
        game.mines = placement;
        game.placed = true;
        for (game.neighbors[0..game.cellCount()], 0..) |nearby, cell| {
            game.numbers[cell] = 0;
            for (nearby.cells[0..nearby.len]) |neighbor| if (game.mines[neighbor]) {
                game.numbers[cell] += 1;
            };
        }
        game.state = .playing;
    }
    fn generatePlacement(game: *Game, first: usize, safety: Safety) void {
        var candidates: [max_cells]usize = undefined;
        var length: usize = 0;
        const sx: i32 = @intCast(first % game.width);
        const sy: i32 = @intCast(first / game.width);
        for (0..game.cellCount()) |cell| {
            const eligible = switch (safety) {
                .none => true,
                .cell => cell != first,
                .block => @abs(@as(i32, @intCast(cell % game.width)) - sx) >= 2 or @abs(@as(i32, @intCast(cell / game.width)) - sy) >= 2,
            };
            if (eligible) {
                candidates[length] = cell;
                length += 1;
            }
        }
        var placement: [max_cells]bool = @splat(false);
        var random = game.seed;
        for (0..game.mine_count) |_| {
            random = 48271 * random % 2147483647;
            const index: usize = @intCast(random % @as(u64, @intCast(length)));
            placement[candidates[index]] = true;
            std.mem.copyForwards(usize, candidates[index .. length - 1], candidates[index + 1 .. length]);
            length -= 1;
        }
        game.setPlacement(placement);
    }
    fn restart(game: *Game) void {
        game.revealed = @splat(false);
        game.marks = @splat(.none);
        game.moves.clearRetainingCapacity();
        game.undo.clearRetainingCapacity();
        game.exploded = 0;
        game.state = if (game.placed) .playing else .ready;
    }
    fn saveSnapshot(game: *const Game, command: Command) Snapshot {
        return .{ .command = command, .revealed = game.revealed, .marks = game.marks, .move_count = game.moves.items.len };
    }
    fn restoreSnapshot(game: *Game, saved: Snapshot) void {
        game.revealed = saved.revealed;
        game.marks = saved.marks;
        game.moves.shrinkRetainingCapacity(saved.move_count);
    }
    fn clone(game: *const Game, gpa: Allocator, reset: bool) Allocator.Error!*Game {
        const copy = try gpa.create(Game);
        copy.* = game.*;
        copy.gpa = gpa;
        copy.moves = .empty;
        copy.undo = .empty;
        if (reset) copy.restart() else try copy.moves.appendSlice(gpa, game.moves.items);
        return copy;
    }
    fn appendMove(game: *Game, kind: MoveKind, cell: usize) Allocator.Error!void {
        try game.moves.append(game.gpa, .{ .kind = kind, .cell = cell });
    }
    fn reveal(game: *Game, first: usize, safety: Safety) usize {
        if (!game.placed) game.generatePlacement(first, safety);
        if (game.mines[first]) {
            game.state = .lost;
            game.exploded = first;
            return 0;
        }
        var queue: [max_cells]usize = undefined;
        queue[0] = first;
        var head: usize = 0;
        var length: usize = 1;
        game.revealed[first] = true;
        game.marks[first] = .none;
        while (head < length) : (head += 1) {
            const cell = queue[head];
            if (game.numbers[cell] != 0) continue;
            const nearby = &game.neighbors[cell];
            for (nearby.cells[0..nearby.len]) |neighbor| if (game.isUnknown(neighbor)) {
                game.revealed[neighbor] = true;
                game.marks[neighbor] = .none;
                queue[length] = neighbor;
                length += 1;
            };
        }
        return length;
    }
    fn chord(game: *Game, cell: usize, safety: Safety) usize {
        var opened: usize = 0;
        const nearby = &game.neighbors[cell];
        for (nearby.cells[0..nearby.len]) |neighbor| if (game.isUnknown(neighbor)) {
            opened += game.reveal(neighbor, safety);
            if (game.state == .lost) break;
        };
        return opened;
    }
    fn checkWin(game: *Game) void {
        if (game.state != .playing or game.revealedCount() != game.cellCount() - game.mine_count) return;
        game.state = .won;
        for (game.mines[0..game.cellCount()], 0..) |mine, cell| if (mine) {
            game.marks[cell] = .flag;
        };
    }
    fn show(game: *const Game, out: *std.Io.Writer) std.Io.Writer.Error!void {
        for (0..game.height) |y| {
            var row: [30]u8 = undefined;
            for (0..game.width) |x| {
                const cell = y * game.width + x;
                row[x] = if (game.state == .lost and game.mines[cell])
                    (if (cell == game.exploded) '!' else if (game.marks[cell] == .flag) 'F' else '*')
                else if (game.state == .lost and game.marks[cell] == .flag) 'X' else if (game.revealed[cell]) (if (game.numbers[cell] == 0) '.' else '0' + game.numbers[cell]) else switch (game.marks[cell]) {
                    .none => '#',
                    .flag => 'F',
                    .question => '?',
                };
            }
            try out.writeAll(row[0..game.width]);
            try out.writeByte('\n');
        }
    }
    fn makeConstraints(game: *const Game) Constraints {
        var result: Constraints = .{};
        for (0..game.cellCount()) |cell| if (game.revealed[cell] and game.numbers[cell] > 0) {
            const unknown = game.unknownNeighbors(cell);
            if (unknown.len > 0) {
                result.items[result.len] = .{ .cell = cell, .unknown = unknown, .remaining = @as(i32, game.numbers[cell]) - @as(i32, @intCast(game.flagNeighbors(cell))) };
                result.len += 1;
            }
        };
        return result;
    }
    fn deduce(game: *const Game) Deduction {
        const constraints = game.makeConstraints();
        var result: Deduction = .{};
        for (constraints.items[0..constraints.len]) |c| if (c.remaining == 0) {
            for (c.unknown.cells[0..c.unknown.len]) |cell| if (result.safe[cell] == null) {
                result.safe[cell] = .{ .kind = .single, .first = c.cell };
            };
        };
        if (result.any(game.cellCount())) return result;
        for (constraints.items[0..constraints.len]) |c| if (c.remaining == @as(i32, @intCast(c.unknown.len))) {
            for (c.unknown.cells[0..c.unknown.len]) |cell| if (result.mines[cell] == null) {
                result.mines[cell] = .{ .kind = .single, .first = c.cell };
            };
        };
        if (result.any(game.cellCount())) return result;
        for (constraints.items[0..constraints.len]) |a| {
            for (constraints.items[0..constraints.len]) |b| {
                if (a.unknown.len >= b.unknown.len) continue;
                var subset = true;
                for (a.unknown.cells[0..a.unknown.len]) |cell| if (!b.unknown.contains(cell)) {
                    subset = false;
                    break;
                };
                if (!subset) continue;
                const difference: i32 = @intCast(b.unknown.len - a.unknown.len);
                const left = b.remaining - a.remaining;
                if (left != 0 and left != difference) continue;
                const side = if (left == 0) &result.safe else &result.mines;
                for (b.unknown.cells[0..b.unknown.len]) |cell| if (!a.unknown.contains(cell) and side[cell] == null) {
                    side[cell] = .{ .kind = .subset, .first = a.cell, .second = b.cell };
                };
            }
        }
        if (result.any(game.cellCount())) return result;
        if (game.state == .playing and game.remainingMines() == 0)
            for (0..game.cellCount()) |cell| if (game.isUnknown(cell)) {
                result.safe[cell] = .{ .kind = .count };
            };
        return result;
    }
    fn buildFrontier(game: *const Game, gpa: Allocator) Allocator.Error!Frontier {
        const constraints = game.makeConstraints();
        var parents: [max_cells]usize = undefined;
        var frontier: [max_cells]bool = @splat(false);
        for (0..game.cellCount()) |cell| parents[cell] = cell;
        for (constraints.items[0..constraints.len]) |c| {
            for (c.unknown.cells[0..c.unknown.len]) |cell| {
                frontier[cell] = true;
                parents[rootOf(&parents, cell)] = rootOf(&parents, c.unknown.cells[0]);
            }
        }
        var result: Frontier = .{};
        var groups: [max_cells]?usize = @splat(null);
        for (0..game.cellCount()) |cell| if (frontier[cell]) {
            const root = rootOf(&parents, cell);
            if (groups[root] == null) {
                groups[root] = result.components.items.len;
                try result.components.append(gpa, .{});
            }
            const group = groups[root].?;
            result.at[cell] = group;
            try result.components.items[group].cells.append(gpa, cell);
        };
        for (constraints.items[0..constraints.len]) |c| {
            const group = result.at[c.unknown.cells[0]].?;
            try result.components.items[group].constraints.append(gpa, c);
        }
        return result;
    }
    fn playAuto(game: *Game, safety: Safety) Allocator.Error!Totals {
        var totals: Totals = .{};
        while (game.state == .playing) {
            const deduction = game.deduce();
            if (!deduction.any(game.cellCount())) break;
            totals.rounds += 1;
            for (0..game.cellCount()) |cell| if (deduction.safe[cell] != null and !game.revealed[cell]) {
                try game.appendMove(.auto_reveal, cell);
                totals.opened += game.reveal(cell, safety);
                game.checkWin();
                if (game.isFinished()) return totals;
            };
            for (0..game.cellCount()) |cell| if (deduction.mines[cell] != null and game.isUnknown(cell)) {
                game.marks[cell] = .flag;
                totals.flagged += 1;
                try game.appendMove(.auto_flag, cell);
            };
        }
        return totals;
    }
    fn playSolve(game: *Game, safety: Safety) Allocator.Error!Totals {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        var totals: Totals = .{};
        while (!game.isFinished()) {
            totals.add(try game.playAuto(safety));
            if (game.isFinished()) break;
            _ = arena.reset(.retain_capacity);
            const frontier = try game.buildFrontier(arena.allocator());
            var numerators: [max_cells]usize = @splat(0);
            var denominators: [max_cells]usize = @splat(0);
            for (frontier.components.items) |*component| {
                component.count();
                for (component.cells.items, 0..) |cell, i| {
                    numerators[cell] = component.mine_counts[i];
                    denominators[cell] = component.configurations;
                }
            }
            var unknown_count: usize = 0;
            for (0..game.cellCount()) |cell| if (game.isUnknown(cell)) {
                unknown_count += 1;
            };
            const background: usize = @intCast(@max(game.remainingMines(), 0));
            var chosen: ?usize = null;
            var best_numerator: usize = 0;
            var best_denominator: usize = 1;
            for (0..game.cellCount()) |cell| if (game.isUnknown(cell)) {
                const numerator = if (frontier.at[cell] == null) background else numerators[cell];
                const denominator = if (frontier.at[cell] == null) unknown_count else denominators[cell];
                if (denominator != 0 and (chosen == null or numerator * best_denominator < best_numerator * denominator)) {
                    chosen = cell;
                    best_numerator = numerator;
                    best_denominator = denominator;
                }
            };
            const chosen_cell = chosen orelse break;
            totals.guesses += 1;
            try game.appendMove(.guess, chosen_cell);
            totals.opened += game.reveal(chosen_cell, safety);
            game.checkWin();
        }
        return totals;
    }
    fn replay(game: *const Game, gpa: Allocator, count: usize, safety: Safety) Allocator.Error!*Game {
        const copy = try game.clone(gpa, true);
        for (game.moves.items[0..count]) |move| {
            switch (move.kind) {
                .reveal, .auto_reveal, .guess => {
                    _ = copy.reveal(move.cell, safety);
                },
                .chord => {
                    _ = copy.chord(move.cell, safety);
                },
                .flag, .auto_flag => copy.marks[move.cell] = .flag,
                .unflag => copy.marks[move.cell] = .none,
                .question => copy.marks[move.cell] = if (copy.marks[move.cell] == .question) .none else .question,
            }
            try copy.moves.append(gpa, move);
            copy.checkWin();
        }
        return copy;
    }
    fn isBlank(game: *const Game, cell: usize) bool {
        return !game.mines[cell] and game.numbers[cell] == 0;
    }
    fn boardInfo(game: *const Game) struct { bv: usize, openings: usize, largest: usize } {
        var visited: [max_cells]bool = @splat(false);
        var openings: usize = 0;
        var largest: usize = 0;
        var isolated: usize = 0;
        for (0..game.cellCount()) |first| {
            if (game.isBlank(first) and !visited[first]) {
                openings += 1;
                var area: [max_cells]bool = @splat(false);
                var queue: [max_cells]usize = undefined;
                queue[0] = first;
                area[first] = true;
                visited[first] = true;
                var head: usize = 0;
                var length: usize = 1;
                var area_size: usize = 1;
                while (head < length) : (head += 1) {
                    const nearby = &game.neighbors[queue[head]];
                    for (nearby.cells[0..nearby.len]) |neighbor| {
                        if (!area[neighbor]) {
                            area[neighbor] = true;
                            area_size += 1;
                        }
                        if (game.isBlank(neighbor) and !visited[neighbor]) {
                            visited[neighbor] = true;
                            queue[length] = neighbor;
                            length += 1;
                        }
                    }
                }
                largest = @max(largest, area_size);
            }
            if (!game.mines[first] and game.numbers[first] > 0) {
                const nearby = &game.neighbors[first];
                var has_blank = false;
                for (nearby.cells[0..nearby.len]) |neighbor| if (game.isBlank(neighbor)) {
                    has_blank = true;
                    break;
                };
                if (!has_blank) isolated += 1;
            }
        }
        return .{ .bv = openings + isolated, .openings = openings, .largest = largest };
    }
};

const Statistics = struct {
    played: usize = 0,
    wins: usize = 0,
    losses: usize = 0,
    streak: usize = 0,
    best: usize = 0,
    fastest: ?usize = null,
    fn record(stats: *Statistics, game: *const Game) void {
        stats.played += 1;
        if (game.state == .won) {
            stats.wins += 1;
            stats.streak += 1;
            stats.best = @max(stats.best, stats.streak);
            stats.fastest = @min(stats.fastest orelse game.moves.items.len, game.moves.items.len);
        } else {
            stats.losses += 1;
            stats.streak = 0;
        }
    }
};

const Program = struct {
    arena: std.heap.ArenaAllocator,
    scratch: Allocator,
    input: *std.Io.Reader,
    out: *std.Io.Writer,
    game: ?*Game = null,
    safety: Safety = .block,
    stats: Statistics = .{},
    error_message: []const u8 = "",
    fn fail(program: *Program, comptime fmt: []const u8, args: anytype) Error {
        program.error_message = try std.fmt.allocPrint(program.scratch, fmt, args);
        return error.BadCommand;
    }
    fn emit(program: *Program, comptime fmt: []const u8, args: anytype) Error!void {
        try program.out.print(fmt ++ "\n", args);
    }
    fn parseNumber(program: *Program, word: []const u8) Error!i64 {
        if (word.len > 10 or (word.len > 1 and word[0] == '0')) return program.fail("bad arguments", .{});
        for (word) |c| if (c < '0' or c > '9') return program.fail("bad arguments", .{});
        return std.fmt.parseInt(i64, word, 10) catch unreachable;
    }
    fn newGame(program: *Program, width: usize, height: usize, mines: usize, seed: u64, placement: ?[max_cells]bool) Allocator.Error!void {
        _ = program.arena.reset(.retain_capacity);
        const gpa = program.arena.allocator();
        const game = try gpa.create(Game);
        game.initialize(gpa, width, height, mines, seed, placement);
        program.game = game;
    }
    fn layout(program: *Program, words: []const []const u8) !void {
        const width = std.fmt.parseInt(usize, words[1], 10) catch unreachable;
        const height = std.fmt.parseInt(usize, words[2], 10) catch unreachable;
        var rows: [30][]const u8 = undefined;
        for (rows[0..height]) |*row| row.* = try readLine(program.scratch, program.input);
        for (rows[0..height], 1..) |row, i| {
            if (row.len != width) return program.fail("bad row {d}", .{i});
            for (row) |c| if (c != '*' and c != '.') return program.fail("bad row {d}", .{i});
        }
        var placement: [max_cells]bool = @splat(false);
        var mines: usize = 0;
        for (rows[0..height], 0..) |row, y| for (row, 0..) |c, x| {
            placement[y * width + x] = c == '*';
            if (c == '*') mines += 1;
        };
        if (mines == 0 or mines == width * height) return program.fail("bad mine count {d}", .{mines});
        try program.newGame(width, height, mines, 0, placement);
        try program.emit("layout {d}x{d} mines {d}", .{ width, height, mines });
    }
    fn finishOutput(program: *Program, game: *const Game) Error!void {
        if (game.state == .lost) {
            try program.emit("boom {f}", .{game.position(game.exploded)});
            try game.show(program.out);
        } else if (game.state == .won) try program.emit("win moves {d}", .{game.moves.items.len});
    }
    fn execute(program: *Program, words: []const []const u8) !void {
        if (std.mem.eql(u8, words[0], "LAYOUT")) return program.layout(words);
        const command = std.meta.stringToEnum(Command, words[0]) orelse return program.fail("unknown command {s}", .{words[0]});
        if (words.len != command.arity() + 1) return program.fail("bad arguments", .{});
        var values: [4]i64 = @splat(0);
        var preset: Preset = .beginner;
        var safety = program.safety;
        for (words[1..], 0..) |word, i| {
            if (command == .PRESET and i == 0) preset = std.meta.stringToEnum(Preset, word) orelse return program.fail("bad arguments", .{}) else if (command == .SAFETY) safety = std.meta.stringToEnum(Safety, word) orelse return program.fail("bad arguments", .{}) else values[i] = try program.parseNumber(word);
        }
        if (command == .NEW or command == .PRESET) {
            const dimensions: [3]i64 = if (command == .NEW) values[0..3].* else switch (preset) {
                .beginner => .{ 9, 9, 10 },
                .intermediate => .{ 16, 16, 40 },
                .expert => .{ 30, 16, 99 },
            };
            const width = dimensions[0];
            const height = dimensions[1];
            const mines = dimensions[2];
            const seed = if (command == .NEW) values[3] else values[1];
            if (width < 1 or width > 30 or height < 1 or height > 30 or mines < 1 or mines > width * height - 9 or seed < 1 or seed > 2147483646)
                return program.fail("bad value", .{});
            try program.newGame(@intCast(width), @intCast(height), @intCast(mines), @intCast(seed), null);
            try program.emit("new {d}x{d} mines {d}", .{ width, height, mines });
            return;
        }
        if (command == .HISTORY and values[0] == 0) return program.fail("bad value", .{});
        if (command == .SAFETY) {
            program.safety = safety;
            try program.emit("safety {s}", .{@tagName(safety)});
            return;
        }
        if (command == .STATS) {
            const stats = program.stats;
            try program.out.print("stats played {d} won {d} lost {d} rate ", .{ stats.played, stats.wins, stats.losses });
            if (stats.played == 0) try program.out.writeAll("-") else try program.out.print("{d}%", .{stats.wins * 100 / stats.played});
            try program.emit(" streak {d} best {d} fastest {f}", .{ stats.streak, stats.best, OptionalNumber{ .value = stats.fastest } });
            return;
        }
        const game = program.game orelse return program.fail("no game", .{});
        var cell: usize = 0;
        if (command.hasCell()) {
            if (values[0] >= @as(i64, @intCast(game.width)) or values[1] >= @as(i64, @intCast(game.height))) return program.fail("out of range", .{});
            cell = @as(usize, @intCast(values[1])) * game.width + @as(usize, @intCast(values[0]));
        }
        if (game.isFinished() and command.activeOnly()) return program.fail("game over", .{});
        if (!game.placed and (command == .ANALYZE or command == .BOARDINFO)) return program.fail("not started", .{});
        const was_finished = game.isFinished();
        const snapshot: ?Snapshot = if (command.undoable()) game.saveSnapshot(command) else null;
        switch (command) {
            .RESTART => {
                game.restart();
                try program.emit("restart {d}x{d} mines {d}", .{ game.width, game.height, game.mine_count });
            },
            .REVEAL => {
                if (game.revealed[cell]) return program.fail("already revealed", .{});
                if (game.marks[cell] == .flag) return program.fail("flagged", .{});
                try game.appendMove(.reveal, cell);
                const opened = game.reveal(cell, program.safety);
                if (game.state != .lost) try program.emit("revealed {d}", .{opened});
                game.checkWin();
                try program.finishOutput(game);
            },
            .FLAG, .UNFLAG, .QUESTION => {
                if (game.revealed[cell]) return program.fail("already revealed", .{});
                if (command == .FLAG and game.marks[cell] == .flag) return program.fail("already flagged", .{});
                if (command == .UNFLAG and game.marks[cell] != .flag) return program.fail("not flagged", .{});
                const action: []const u8 = if (command == .FLAG) "flagged" else if (command == .UNFLAG) "unflagged" else if (game.marks[cell] == .question) "unmarked" else "questioned";
                game.marks[cell] = if (command == .FLAG) .flag else if (command == .UNFLAG or game.marks[cell] == .question) .none else .question;
                try game.appendMove(if (command == .FLAG) .flag else if (command == .UNFLAG) .unflag else .question, cell);
                try program.emit("{s} {f} left {d}", .{ action, game.position(cell), game.remainingMines() });
            },
            .CHORD => {
                if (!game.revealed[cell]) return program.fail("not revealed", .{});
                if (game.numbers[cell] == 0) return program.fail("no number", .{});
                const flags = game.flagNeighbors(cell);
                if (flags != game.numbers[cell]) return program.fail("flags {d} of {d}", .{ flags, game.numbers[cell] });
                if (game.unknownNeighbors(cell).len == 0) return program.fail("nothing to reveal", .{});
                try game.appendMove(.chord, cell);
                const opened = game.chord(cell, program.safety);
                if (game.state != .lost) try program.emit("chorded {d}", .{opened});
                game.checkWin();
                try program.finishOutput(game);
            },
            .UNDO => {
                const saved = game.undo.pop() orelse return program.fail("nothing to undo", .{});
                game.restoreSnapshot(saved);
                try program.emit("undo {s} moves {d}", .{ saved.command.undoName(), game.moves.items.len });
            },
            .SHOW => try game.show(program.out),
            .STATUS => try program.emit("status {s} left {d} moves {d} revealed {d}/{d}", .{ @tagName(game.state), game.remainingMines(), game.moves.items.len, game.revealedCount(), game.cellCount() - game.mine_count }),
            .CELL => {
                if (game.revealed[cell]) {
                    try program.emit("cell {f} number {d} flags {d} unknown {d}", .{ game.position(cell), game.numbers[cell], game.flagNeighbors(cell), game.unknownNeighbors(cell).len });
                } else {
                    var opened: usize = 0;
                    const nearby = &game.neighbors[cell];
                    for (nearby.cells[0..nearby.len]) |neighbor| if (game.revealed[neighbor]) {
                        opened += 1;
                    };
                    try program.emit("cell {f} hidden mark {s} open {d}", .{ game.position(cell), @tagName(game.marks[cell]), opened });
                }
            },
            .HISTORY => {
                const length = game.moves.items.len;
                const count: usize = @intCast(@min(values[0], @as(i64, @intCast(length))));
                try program.emit("history {d}", .{length});
                for (game.moves.items[length - count ..], length - count + 1..) |move, i|
                    try program.emit("{d} {s} {f}", .{ i, move.name(), game.position(move.cell) });
            },
            .REPLAY => {
                if (values[0] > @as(i64, @intCast(game.moves.items.len))) return program.fail("no move {d}", .{values[0]});
                try program.emit("replay {d}/{d}", .{ values[0], game.moves.items.len });
                const copy = try game.replay(program.scratch, @intCast(values[0]), program.safety);
                try copy.show(program.out);
            },
            .HINT => {
                const deduction = game.deduce();
                var found = false;
                for (deduction.safe[0..game.cellCount()], 0..) |maybe_reason, target| if (maybe_reason) |reason| {
                    try program.emit("hint safe {f} by {f}", .{ game.position(target), Explanation{ .reason = reason, .width = game.width } });
                    found = true;
                    break;
                };
                if (!found) for (deduction.mines[0..game.cellCount()], 0..) |maybe_reason, target| if (maybe_reason) |reason| {
                    try program.emit("hint mine {f} by {f}", .{ game.position(target), Explanation{ .reason = reason, .width = game.width } });
                    found = true;
                    break;
                };
                if (!found) try program.emit("hint none", .{});
            },
            .AUTO, .SOLVE => {
                const totals = if (command == .AUTO) try game.playAuto(program.safety) else try game.playSolve(program.safety);
                if (command == .AUTO) try program.emit("auto rounds {d} flagged {d} revealed {d}", .{ totals.rounds, totals.flagged, totals.opened }) else try program.emit("solve guesses {d} rounds {d} flagged {d} revealed {d}", .{ totals.guesses, totals.rounds, totals.flagged, totals.opened });
                try program.finishOutput(game);
            },
            .ANALYZE => {
                const copy = try game.clone(program.scratch, false);
                const totals = try copy.playAuto(program.safety);
                if (copy.state == .lost) try program.emit("analyze boom {f} rounds {d}", .{ copy.position(copy.exploded), totals.rounds }) else if (copy.state == .won) try program.emit("analyze clear rounds {d}", .{totals.rounds}) else try program.emit("analyze stuck rounds {d} revealed {d}/{d}", .{ totals.rounds, copy.revealedCount(), copy.cellCount() - copy.mine_count });
            },
            .PROB => {
                if (game.revealed[cell]) return program.fail("already revealed", .{});
                if (game.marks[cell] == .flag) return program.fail("flagged", .{});
                const frontier = try game.buildFrontier(program.scratch);
                if (frontier.at[cell]) |group| {
                    const component = &frontier.components.items[group];
                    component.count();
                    if (component.configurations == 0) try program.emit("prob {f} inconsistent", .{game.position(cell)}) else {
                        var numerator: usize = 0;
                        for (component.cells.items, 0..) |candidate, i| if (candidate == cell) {
                            numerator = component.mine_counts[i];
                            break;
                        };
                        const denominator = component.configurations;
                        var a = numerator;
                        var b = denominator;
                        while (b != 0) {
                            const remainder = a % b;
                            a = b;
                            b = remainder;
                        }
                        try program.emit("prob {f} {d}/{d} size {d} configs {d}", .{ game.position(cell), numerator / a, denominator / a, component.cells.items.len, denominator });
                    }
                } else try program.emit("prob {f} unconstrained", .{game.position(cell)});
            },
            .FRONTIER => {
                const frontier = try game.buildFrontier(program.scratch);
                var count: usize = 0;
                for (frontier.components.items) |component| count += component.cells.items.len;
                try program.emit("frontier {d} components {d}", .{ count, frontier.components.items.len });
                for (frontier.components.items) |*component| {
                    component.count();
                    if (component.configurations == 0) try program.emit("component {f} size {d} inconsistent", .{ game.position(component.cells.items[0]), component.cells.items.len }) else try program.emit("component {f} size {d} configs {d} min {d} max {d}", .{ game.position(component.cells.items[0]), component.cells.items.len, component.configurations, component.minimum, component.maximum });
                }
            },
            .BOARDINFO => {
                const info = game.boardInfo();
                try program.emit("3bv {d} openings {d} largest {d} mines {d} safe {d}", .{ info.bv, info.openings, info.largest, game.mine_count, game.cellCount() - game.mine_count });
            },
            .NEW, .PRESET, .LAYOUT, .SAFETY, .STATS => unreachable,
        }
        if (snapshot) |saved| if (game.moves.items.len > saved.move_count) {
            try game.undo.append(game.gpa, saved);
        };
        if (!was_finished and game.isFinished()) program.stats.record(game);
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const line = try buffer.toOwnedSlice();
    return if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
}
fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    const line = try readLine(gpa, input);
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    while (parts.next()) |word| try words.append(gpa, word);
    return try words.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var program: Program = .{ .arena = .init(std.heap.page_allocator), .scratch = scratch.allocator(), .input = &input.interface, .out = &output.interface };
    defer program.arena.deinit();
    const count = std.fmt.parseInt(usize, (try readWords(scratch.allocator(), &input.interface))[0], 10) catch unreachable;
    for (0..count) |_| {
        _ = scratch.reset(.retain_capacity);
        const words = try readWords(scratch.allocator(), &input.interface);
        var response: std.Io.Writer.Allocating = .init(scratch.allocator());
        defer response.deinit();
        program.out = &response.writer;
        program.execute(words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("error: {s}\n", .{program.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
