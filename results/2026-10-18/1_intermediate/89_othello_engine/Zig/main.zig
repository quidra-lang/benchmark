const std = @import("std");
const Text = []const u8;
const Allocator = std.mem.Allocator;
const Board = [64]u8;

const weights = [_]i32{
    100, -20, 10, 5,  5,  10, -20, 100,
    -20, -50, -2, -2, -2, -2, -50, -20,
    10,  -2,  -1, -1, -1, -1, -2,  10,
    5,   -2,  -1, -1, -1, -1, -2,  5,
    5,   -2,  -1, -1, -1, -1, -2,  5,
    10,  -2,  -1, -1, -1, -1, -2,  10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10, 5,  5,  10, -20, 100,
};

fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn includes(value: Text, choices: []const Text) bool {
    for (choices) |item| {
        if (eq(item, value)) return true;
    }
    return false;
}

const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn add(self: *Builder, s: Text) !void {
        try self.bytes.appendSlice(self.gpa, s);
    }

    fn print(self: *Builder, comptime format: Text, args: anytype) !void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }

    fn line(self: *Builder, comptime format: Text, args: anytype) !void {
        try self.print(format ++ "\n", args);
    }
};

fn split(gpa: Allocator, line: Text) ![]Text {
    var tokens: std.ArrayList(Text) = .empty;
    var it = std.mem.splitScalar(u8, line, ' ');
    while (it.next()) |part| {
        try tokens.append(gpa, part);
    }
    return tokens.items;
}

fn other(side: u8) u8 {
    return if (side == 'B') 'W' else 'B';
}

fn initialBoard() Board {
    var board: [64]u8 = @splat('.');
    board[27] = 'W';
    board[36] = 'W';
    board[28] = 'B';
    board[35] = 'B';
    return board;
}

fn squareName(p: usize) [2]u8 {
    return .{ @as(u8, 'a') + @as(u8, @intCast(p % 8)), @as(u8, '1') + @as(u8, @intCast(p / 8)) };
}

fn squareIndex(s: Text) usize {
    return (@as(usize, s[1]) - '1') * 8 + @as(usize, s[0]) - 'a';
}

fn inside(r: i32, c: i32) bool {
    return r >= 0 and r < 8 and c >= 0 and c < 8;
}

const Squares = struct {
    data: [64]usize = undefined,
    len: usize = 0,

    fn add(self: *Squares, p: usize) void {
        self.data[self.len] = p;
        self.len += 1;
    }

    fn has(self: Squares, p: usize) bool {
        for (self.data[0..self.len]) |item| {
            if (item == p) return true;
        }
        return false;
    }
};

fn flips(board: *const Board, side: u8, p: usize) Squares {
    var result: Squares = .{};
    if (board[p] != '.') return result;
    const r0: i32 = @intCast(p / 8);
    const c0: i32 = @intCast(p % 8);
    for (0..3) |ri| {
        const dr: i32 = @as(i32, @intCast(ri)) - 1;
        for (0..3) |ci| {
            const dc: i32 = @as(i32, @intCast(ci)) - 1;
            if (dr == 0 and dc == 0) continue;
            var r = r0 + dr;
            var c = c0 + dc;
            var line: Squares = .{};
            while (inside(r, c) and board[@intCast(8 * r + c)] == other(side)) {
                line.add(@intCast(8 * r + c));
                r += dr;
                c += dc;
            }
            if (line.len > 0 and inside(r, c) and board[@intCast(8 * r + c)] == side) {
                for (line.data[0..line.len]) |q| result.add(q);
            }
        }
    }
    for (0..result.len) |i| {
        var j = i;
        while (j > 0 and result.data[j] < result.data[j - 1]) : (j -= 1) {
            std.mem.swap(usize, &result.data[j], &result.data[j - 1]);
        }
    }
    return result;
}

fn legal(board: *const Board, side: u8) Squares {
    var moves: Squares = .{};
    for (0..64) |p| {
        if (board[p] == '.' and flips(board, side, p).len > 0) moves.add(p);
    }
    return moves;
}

fn place(board: *const Board, side: u8, p: usize) Board {
    var result = board.*;
    const flipped = flips(board, side, p);
    for (flipped.data[0..flipped.len]) |q| result[q] = side;
    result[p] = side;
    return result;
}

fn count(board: *const Board, value: u8) usize {
    var result: usize = 0;
    for (board.*) |c| {
        if (c == value) result += 1;
    }
    return result;
}

fn terminal(board: *const Board) bool {
    return legal(board, 'B').len == 0 and legal(board, 'W').len == 0;
}

fn gameOver(board: *const Board, out: *Builder) !void {
    const black = count(board, 'B');
    const white = count(board, 'W');
    const result = if (black > white) "winner B" else if (black < white) "winner W" else "draw";
    try out.line("game over B {d} W {d} {s}", .{ black, white, result });
}

fn evaluate(board: *const Board, side: u8) [4]i32 {
    var w: i32 = 0;
    for (board.*, 0..) |disc, p| {
        if (disc == side) {
            w += weights[p];
        } else if (disc == other(side)) {
            w -= weights[p];
        }
    }
    const own: i32 = @intCast(legal(board, side).len);
    const enemy: i32 = @intCast(legal(board, other(side)).len);
    return .{ w + 10 * (own - enemy), w, own, enemy };
}

const SearchKey = struct {
    board: Board,
    side: u8,
    depth: i32,
};

const Solver = struct {
    cache: std.AutoHashMap(SearchKey, i32),

    fn init(gpa: Allocator) Solver {
        return .{ .cache = std.AutoHashMap(SearchKey, i32).init(gpa) };
    }

    fn search(self: *Solver, board: Board, side: u8, depth: i32) !i32 {
        const key = SearchKey{ .board = board, .side = side, .depth = depth };
        if (self.cache.get(key)) |v| return v;
        const moves = legal(&board, side);
        const enemy = other(side);
        const next_depth = if (depth < 0) @as(i32, -1) else depth - 1;
        var result: i32 = 0;
        if (moves.len == 0 and legal(&board, enemy).len == 0) {
            const black: i32 = @intCast(count(&board, side));
            const white: i32 = @intCast(count(&board, enemy));
            result = (if (depth < 0) @as(i32, 1) else 1000) * (black - white);
        } else if (depth == 0) {
            result = evaluate(&board, side)[0];
        } else if (moves.len == 0) {
            result = -try self.search(board, enemy, next_depth);
        } else {
            result = -1000000;
            for (moves.data[0..moves.len]) |p| {
                const v = -try self.search(place(&board, side, p), enemy, next_depth);
                result = @max(result, v);
            }
        }
        if (self.cache.count() > 300000) self.cache.clearRetainingCapacity();
        try self.cache.put(key, result);
        return result;
    }

    fn ranked(self: *Solver, board: Board, side: u8, depth: i32) !Rankings {
        var result: Rankings = .{};
        const moves = legal(&board, side);
        for (moves.data[0..moves.len]) |p| {
            const value = -try self.search(place(&board, side, p), other(side), if (depth < 0) -1 else depth - 1);
            result.data[result.len] = .{ .p = p, .value = value };
            result.len += 1;
        }
        for (0..result.len) |i| {
            var j = i;
            while (j > 0 and (result.data[j].value > result.data[j - 1].value or
                (result.data[j].value == result.data[j - 1].value and result.data[j].p < result.data[j - 1].p))) : (j -= 1)
            {
                std.mem.swap(Ranking, &result.data[j], &result.data[j - 1]);
            }
        }
        return result;
    }

    fn variation(self: *Solver, start: Board, side: u8, depth: i32, gpa: Allocator) !Variation {
        var board = start;
        var turn = side;
        var remaining = depth;
        var path: std.ArrayList(u8) = .empty;
        while (remaining != 0 and !terminal(&board)) {
            if (path.items.len > 0) try path.append(gpa, ' ');
            const choices = try self.ranked(board, turn, remaining);
            if (choices.len == 0) {
                try path.appendSlice(gpa, "pass");
            } else {
                const p = choices.data[0].p;
                const sq = squareName(p);
                try path.appendSlice(gpa, &sq);
                board = place(&board, turn, p);
            }
            turn = other(turn);
            if (remaining > 0) remaining -= 1;
        }
        return .{ .path = path.items, .board = board };
    }

    fn perft(self: *Solver, board: Board, side: u8, depth: u32) !u64 {
        if (depth == 0) return 1;
        const moves = legal(&board, side);
        const enemy = other(side);
        if (moves.len == 0) {
            return if (legal(&board, enemy).len == 0) 1 else try self.perft(board, enemy, depth - 1);
        }
        var result: u64 = 0;
        for (moves.data[0..moves.len]) |p| result += try self.perft(place(&board, side, p), enemy, depth - 1);
        return result;
    }
};

const Ranking = struct {
    p: usize,
    value: i32,
};

const Rankings = struct {
    data: [64]Ranking = undefined,
    len: usize = 0,
};

const Variation = struct {
    path: Text,
    board: Board,
};

fn stable(board: *const Board) [2]usize {
    var known: [64]bool = @splat(false);
    const axes = [_][2]i32{ .{ 0, 1 }, .{ 1, 0 }, .{ 1, 1 }, .{ 1, -1 } };
    while (true) {
        var found: Squares = .{};
        for (0..64) |p| {
            if (board[p] == '.' or known[p]) continue;
            var valid = true;
            for (axes) |axis| {
                var full = true;
                var anchor = false;
                for ([_]i32{ -1, 1 }) |sign| {
                    var r: i32 = @as(i32, @intCast(p / 8)) + axis[0] * sign;
                    var c: i32 = @as(i32, @intCast(p % 8)) + axis[1] * sign;
                    if (!inside(r, c)) {
                        anchor = true;
                    } else if (known[@intCast(8 * r + c)] and board[@intCast(8 * r + c)] == board[p]) {
                        anchor = true;
                    }
                    while (inside(r, c)) {
                        if (board[@intCast(8 * r + c)] == '.') full = false;
                        r += axis[0] * sign;
                        c += axis[1] * sign;
                    }
                }
                if (!full and !anchor) {
                    valid = false;
                    break;
                }
            }
            if (valid) found.add(p);
        }
        if (found.len == 0) break;
        for (found.data[0..found.len]) |p| known[p] = true;
    }
    var result = [_]usize{ 0, 0 };
    for (0..64) |p| {
        if (known[p] and board[p] == 'B') result[0] += 1;
        if (known[p] and board[p] == 'W') result[1] += 1;
    }
    return result;
}

fn transform(p: usize, operation: Text) usize {
    const r = p / 8;
    const c = p % 8;
    if (eq(operation, "rot90")) return 8 * c + 7 - r;
    if (eq(operation, "rot180")) return 63 - p;
    if (eq(operation, "rot270")) return 8 * (7 - c) + r;
    if (eq(operation, "mirror")) return 8 * r + 7 - c;
    if (eq(operation, "flip")) return 8 * (7 - r) + c;
    if (eq(operation, "diag")) return 8 * c + r;
    return 8 * (7 - c) + 7 - r;
}

fn transformBoard(board: *const Board, operation: Text) Board {
    var result: [64]u8 = @splat('.');
    for (0..64) |p| result[transform(p, operation)] = board[p];
    return result;
}

const Random = struct {
    state: u64,

    fn draw(self: *Random) u64 {
        self.state = self.state * 48271 % 2147483647;
        return self.state;
    }
};

fn randomGame(start: Board, side: u8, random: *Random) Board {
    var board = start;
    var turn = side;
    while (true) {
        const choices = legal(&board, turn);
        if (choices.len > 0) {
            const n: usize = @intCast(random.draw() % @as(u64, @intCast(choices.len)));
            board = place(&board, turn, choices.data[n]);
        } else if (legal(&board, other(turn)).len == 0) return board;
        turn = other(turn);
    }
}

fn validSquare(s: Text) bool {
    return s.len == 2 and s[0] >= 'a' and s[0] <= 'h' and s[1] >= '1' and s[1] <= '8';
}

fn validRecord(s: Text) bool {
    if (s.len == 0 or s.len > 120 or s.len % 2 != 0) return false;
    var i: usize = 0;
    while (i < s.len) : (i += 2) if (!validSquare(s[i .. i + 2])) return false;
    return true;
}

fn number(s: Text) ?u64 {
    if (s.len == 0) return null;
    for (s) |c| if (c < '0' or c > '9') {
        return null;
    };
    return std.fmt.parseInt(u64, s, 10) catch null;
}

fn allowedNumber(cmd: Text, args: []const Text) bool {
    const expected: usize = if (eq(cmd, "AUTOPLAY") or eq(cmd, "MC")) 2 else 1;
    if (args.len != expected) return false;
    const a = number(args[0]) orelse return false;
    const b = if (expected == 2) (number(args[1]) orelse return false) else 0;
    if (eq(cmd, "AUTOPLAY")) return a >= 1 and a <= 4 and b >= 1 and b <= 4;
    if (includes(cmd, &.{ "HINT", "PV", "AI", "ANALYZE" })) return a >= 1 and a <= 4;
    if (includes(cmd, &.{ "PERFT", "DIVIDE" })) return a >= 1 and a <= 8;
    if (eq(cmd, "MC")) return a >= 1 and a <= 100 and b >= 1 and b <= 2147483646;
    if (eq(cmd, "RANDOM")) return a >= 1 and a <= 2147483646;
    return a >= 1;
}

const Position = struct {
    board: Board,
    side: u8,
    over: bool,

    fn init() Position {
        return .{ .board = initialBoard(), .side = 'B', .over = false };
    }
};

const Move = struct {
    side: u8,
    p: usize,
    flipped: usize,
    passed: bool,
    before: Position,
    after: Position,
};

const Game = struct {
    pos: Position,
    history: [64]Move = undefined,
    redo: [64]Move = undefined,
    nh: usize = 0,
    nr: usize = 0,
    solver: Solver,

    fn init(gpa: Allocator) Game {
        return .{ .pos = Position.init(), .solver = Solver.init(gpa) };
    }

    fn reset(self: *Game) void {
        self.pos = Position.init();
        self.nh = 0;
        self.nr = 0;
    }

    fn status(self: *const Game, out: *Builder) !void {
        if (self.pos.over) try gameOver(&self.pos.board, out) else try out.line("{c} to move", .{self.pos.side});
    }

    fn adjust(self: *Game, out: *Builder, quiet: bool) !bool {
        if (legal(&self.pos.board, self.pos.side).len > 0) return false;
        if (legal(&self.pos.board, other(self.pos.side)).len > 0) {
            if (!quiet) try out.line("{c} passes", .{self.pos.side});
            self.pos.side = other(self.pos.side);
            return true;
        }
        self.pos.over = true;
        if (!quiet) try gameOver(&self.pos.board, out);
        return false;
    }

    fn play(self: *Game, p: usize, out: *Builder, quiet: bool, value: ?i32) !bool {
        const before = self.pos;
        const s = self.pos.side;
        const flipped = flips(&self.pos.board, s, p).len;
        self.pos.board = place(&self.pos.board, s, p);
        if (!quiet) {
            const sq = squareName(p);
            if (value) |v| try out.line("{c} {s} flips {d} value {d}", .{ s, &sq, flipped, v }) else try out.line("{c} {s} flips {d}", .{ s, &sq, flipped });
        }
        self.pos.side = other(s);
        const passed = try self.adjust(out, quiet);
        self.history[self.nh] = .{ .side = s, .p = p, .flipped = flipped, .passed = passed, .before = before, .after = self.pos };
        self.nh += 1;
        self.nr = 0;
        return passed;
    }

    fn reason(self: *const Game, p: usize) ?Text {
        if (self.pos.over) return "game over";
        if (self.pos.board[p] != '.') return "occupied";
        if (flips(&self.pos.board, self.pos.side, p).len == 0) return "no flips";
        return null;
    }

    fn record(self: *Game, text: Text, out: *Builder) !void {
        var trial = Game.init(out.gpa);
        var passes: usize = 0;
        var squares: [60]usize = undefined;
        for (0..text.len / 2) |i| {
            const p = squareIndex(text[2 * i .. 2 * i + 2]);
            if (trial.reason(p)) |why| {
                const sq = squareName(p);
                try out.line("ILLEGAL move {d} {s} {s}", .{ i + 1, &sq, why });
                return;
            }
            squares[i] = p;
            if (try trial.play(p, out, true, null)) passes += 1;
        }
        self.pos = trial.pos;
        for (trial.history[0..trial.nh], 0..) |m, i| self.history[i] = m;
        self.nh = trial.nh;
        self.nr = 0;
        const first = squareName(squares[0]);
        const operation: Text = if (eq(&first, "e6")) "diag" else if (eq(&first, "d3")) "anti" else if (eq(&first, "c4")) "rot180" else "";
        var normalized: [120]u8 = undefined;
        for (squares[0 .. text.len / 2], 0..) |p, i| {
            const sq = squareName(if (operation.len == 0) p else transform(p, operation));
            normalized[2 * i] = sq[0];
            normalized[2 * i + 1] = sq[1];
        }
        try out.line("record {d} moves {d} passes", .{ trial.nh, passes });
        try out.line("normal {s}", .{normalized[0..text.len]});
        try self.status(out);
    }

    fn sheet(self: *const Game, out: *Builder) !void {
        const board = if (self.nh == 0) self.pos.board else self.history[0].before.board;
        var fields: [64]Text = undefined;
        for (0..64) |p| {
            fields[p] = try std.fmt.allocPrint(out.gpa, "{c}", .{board[p]});
        }
        for (0..self.nh) |i| fields[self.history[i].p] = try std.fmt.allocPrint(out.gpa, "{d}", .{i + 1});
        try out.line("   a  b  c  d  e  f  g  h", .{});
        for (0..8) |r| {
            try out.print("{d}", .{r + 1});
            for (fields[8 * r .. 8 * r + 8]) |item| try out.print("{s: >3}", .{item});
            try out.add("\n");
        }
    }

    fn stats(self: *const Game, out: *Builder) !void {
        var flipped: usize = 0;
        var passes: usize = 0;
        for (self.history[0..self.nh]) |m| {
            flipped += m.flipped;
            if (m.passed) passes += 1;
        }
        if (self.nh == 0) try out.line("moves 0", .{}) else try out.line("moves {d} flips {d} avg {d}.{d:0>2} passes {d}", .{
            self.nh, flipped, flipped * 100 / self.nh / 100, (flipped * 100 / self.nh) % 100, passes,
        });
        for ([_]u8{ 'B', 'W' }) |side| {
            var n: usize = 0;
            var total: usize = 0;
            var highest: usize = 0;
            var square: usize = 0;
            var corners: usize = 0;
            for (self.history[0..self.nh]) |m| {
                if (m.side != side) continue;
                n += 1;
                total += m.flipped;
                if (n == 1 or m.flipped > highest) {
                    highest = m.flipped;
                    square = m.p;
                }
                if (m.p == 0 or m.p == 7 or m.p == 56 or m.p == 63) corners += 1;
            }
            if (n == 0) {
                try out.line("{c} moves 0", .{side});
            } else {
                const sq = squareName(square);
                const scaled = total * 100 / n;
                try out.line("{c} moves {d} flips {d} avg {d}.{d:0>2} max {d} {s} corners {d}", .{
                    side, n, total, scaled / 100, scaled % 100, highest, &sq, corners,
                });
            }
        }
    }

    fn transformGame(self: *Game, operation: Text) void {
        self.pos.board = transformBoard(&self.pos.board, operation);
        for (self.history[0..self.nh]) |*m| {
            m.p = transform(m.p, operation);
            m.before.board = transformBoard(&m.before.board, operation);
            m.after.board = transformBoard(&m.after.board, operation);
        }
        for (self.redo[0..self.nr]) |*m| {
            m.p = transform(m.p, operation);
            m.before.board = transformBoard(&m.before.board, operation);
            m.after.board = transformBoard(&m.after.board, operation);
        }
    }

    fn automatic(self: *Game, black: i32, white: i32, seed: ?u64, out: *Builder) !void {
        var random = Random{ .state = seed orelse 0 };
        var line: [120]u8 = undefined;
        var moves: usize = 0;
        var passes: usize = 0;
        while (!self.pos.over) {
            const p = if (seed != null) blk: {
                const available = legal(&self.pos.board, self.pos.side);
                break :blk available.data[@intCast(random.draw() % @as(u64, @intCast(available.len)))];
            } else (try self.solver.ranked(self.pos.board, self.pos.side, if (self.pos.side == 'B') black else white)).data[0].p;
            const sq = squareName(p);
            line[2 * moves] = sq[0];
            line[2 * moves + 1] = sq[1];
            moves += 1;
            if (try self.play(p, out, true, null)) passes += 1;
        }
        try out.line("{s} {d} moves {d} passes", .{ if (seed != null) "random" else "autoplay", moves, passes });
        try out.line("moves {s}", .{line[0 .. 2 * moves]});
        try gameOver(&self.pos.board, out);
    }

    fn monteCarlo(self: *const Game, trials: usize, seed: u64, out: *Builder) !void {
        var random = Random{ .state = seed };
        var best: i32 = -1;
        var best_square: usize = 0;
        const moves = legal(&self.pos.board, self.pos.side);
        for (moves.data[0..moves.len]) |p| {
            var wins: i32 = 0;
            var draws: i32 = 0;
            var losses: i32 = 0;
            const first = place(&self.pos.board, self.pos.side, p);
            for (0..trials) |_| {
                const last = randomGame(first, other(self.pos.side), &random);
                const x: i32 = @intCast(count(&last, self.pos.side));
                const y: i32 = @intCast(count(&last, other(self.pos.side)));
                if (x > y) wins += 1 else if (x == y) draws += 1 else losses += 1;
            }
            const sq = squareName(p);
            try out.line("{s} {d} {d} {d}", .{ &sq, wins, draws, losses });
            const points = 2 * wins + draws;
            if (points > best) {
                best = points;
                best_square = p;
            }
        }
        const sq = squareName(best_square);
        try out.line("best {s} {d}", .{ &sq, best });
    }

    fn execute(self: *Game, cmdline: Text, out: *Builder) !void {
        const words = try split(out.gpa, cmdline);
        const cmd = words[0];
        const args = words[1..];
        const zero = [_]Text{ "NEW", "DUMP", "SHOW", "SCORE", "LEGAL", "HISTORY", "SHEET", "STATS", "EVAL", "STABLE", "SOLVE" };
        const numeric = [_]Text{ "UNDO", "REDO", "HINT", "PV", "AI", "ANALYZE", "RANDOM", "PERFT", "DIVIDE" };
        const additional = [_]Text{ "LOAD", "TRANSFORM", "AUTOPLAY", "MC", "FLIPS", "MOVE", "PLAY", "RECORD" };
        const active = [_]Text{ "FLIPS", "MOVE", "PLAY", "HINT", "PV", "AI", "SOLVE", "AUTOPLAY", "RANDOM", "MC", "DIVIDE" };
        if (!includes(cmd, &zero) and !includes(cmd, &numeric) and !includes(cmd, &additional)) {
            try out.line("ERROR unknown command", .{});
            return;
        }
        var error_message: ?Text = null;
        if (eq(cmd, "LOAD")) {
            if (args.len != 2 or args[0].len != 64) {
                error_message = "bad board";
            } else {
                for (args[0]) |c| {
                    if (c != '.' and c != 'B' and c != 'W') error_message = "bad board";
                }
                if (!eq(args[1], "B") and !eq(args[1], "W")) error_message = "bad board";
            }
        } else if (eq(cmd, "MOVE") or eq(cmd, "FLIPS")) {
            if (args.len != 1) error_message = "bad arguments" else if (!validSquare(args[0])) error_message = "bad square";
        } else if (eq(cmd, "PLAY") or eq(cmd, "RECORD")) {
            if (args.len != 1) error_message = "bad arguments" else if (!validRecord(args[0])) error_message = "bad record";
        } else if (includes(cmd, &zero)) {
            if (args.len != 0) error_message = "bad arguments";
        } else if (eq(cmd, "TRANSFORM")) {
            if (args.len != 1 or !includes(args[0], &.{ "rot90", "rot180", "rot270", "mirror", "flip", "diag", "anti" }))
                error_message = "bad arguments";
        } else if (!allowedNumber(cmd, args)) {
            error_message = "bad arguments";
        }
        if (error_message) |msg| {
            try out.line("ERROR {s}", .{msg});
            return;
        }
        if (self.pos.over and includes(cmd, &active)) {
            try out.line("ERROR game over", .{});
            return;
        }
        const n: usize = if (includes(cmd, &numeric) or eq(cmd, "MC") or eq(cmd, "AUTOPLAY")) @intCast(number(args[0]).?) else 0;
        if (eq(cmd, "NEW")) {
            self.reset();
            try out.line("OK", .{});
        } else if (eq(cmd, "LOAD")) {
            @memcpy(self.pos.board[0..], args[0]);
            self.pos.side = args[1][0];
            self.pos.over = false;
            self.nh = 0;
            self.nr = 0;
            try out.line("OK", .{});
            _ = try self.adjust(out, false);
        } else if (eq(cmd, "DUMP")) {
            try out.line("board {s} {c}", .{ &self.pos.board, self.pos.side });
        } else if (eq(cmd, "SHOW")) {
            try out.line("  a b c d e f g h", .{});
            const moves = if (self.pos.over) Squares{} else legal(&self.pos.board, self.pos.side);
            for (0..8) |r| {
                try out.print("{d}", .{r + 1});
                for (0..8) |c| {
                    const p = 8 * r + c;
                    try out.print(" {c}", .{if (moves.has(p)) @as(u8, '*') else self.pos.board[p]});
                }
                try out.add("\n");
            }
            try self.status(out);
        } else if (eq(cmd, "SCORE")) {
            try out.line("score B {d} W {d} empty {d}", .{
                count(&self.pos.board, 'B'), count(&self.pos.board, 'W'), count(&self.pos.board, '.'),
            });
        } else if (eq(cmd, "LEGAL")) {
            const moves = if (self.pos.over) Squares{} else legal(&self.pos.board, self.pos.side);
            try out.print("legal {d}", .{moves.len});
            for (moves.data[0..moves.len]) |p| {
                const sq = squareName(p);
                try out.print(" {s}", .{&sq});
            }
            try out.add("\n");
        } else if (eq(cmd, "MOVE") or eq(cmd, "FLIPS")) {
            const p = squareIndex(args[0]);
            if (self.reason(p)) |why| try out.line("ILLEGAL {s}", .{why}) else if (eq(cmd, "MOVE")) _ = try self.play(p, out, false, null) else {
                const flipped = flips(&self.pos.board, self.pos.side, p);
                try out.print("flips {s} {d}", .{ args[0], flipped.len });
                for (flipped.data[0..flipped.len]) |q| {
                    const sq = squareName(q);
                    try out.print(" {s}", .{&sq});
                }
                try out.add("\n");
            }
        } else if (eq(cmd, "PLAY")) {
            for (0..args[0].len / 2) |i| {
                const p = squareIndex(args[0][2 * i .. 2 * i + 2]);
                if (self.reason(p)) |why| {
                    const sq = squareName(p);
                    try out.line("ILLEGAL move {d} {s} {s}", .{ i + 1, &sq, why });
                    break;
                }
                _ = try self.play(p, out, false, null);
            }
        } else if (eq(cmd, "RECORD")) {
            try self.record(args[0], out);
        } else if (eq(cmd, "UNDO")) {
            if (n > self.nh) {
                try out.line("ERROR cannot undo", .{});
            } else {
                const start = self.nh - n;
                self.pos = self.history[start].before;
                var i = self.nr;
                while (i > 0) {
                    i -= 1;
                    self.redo[i + n] = self.redo[i];
                }
                for (0..n) |j| self.redo[j] = self.history[start + j];
                self.nh = start;
                self.nr += n;
                try self.status(out);
            }
        } else if (eq(cmd, "REDO")) {
            if (n > self.nr) {
                try out.line("ERROR cannot redo", .{});
            } else {
                for (0..n) |j| self.history[self.nh + j] = self.redo[j];
                self.nh += n;
                self.pos = self.redo[n - 1].after;
                self.nr -= n;
                for (0..self.nr) |j| self.redo[j] = self.redo[n + j];
                try self.status(out);
            }
        } else if (eq(cmd, "HISTORY")) {
            try out.line("history {d}", .{self.nh});
            for (self.history[0..self.nh], 0..) |m, i| {
                const sq = squareName(m.p);
                try out.line("{d} {c} {s} {d}{s}", .{ i + 1, m.side, &sq, m.flipped, if (m.passed) " pass" else "" });
            }
        } else if (eq(cmd, "SHEET")) {
            try self.sheet(out);
        } else if (eq(cmd, "STATS")) {
            try self.stats(out);
        } else if (eq(cmd, "TRANSFORM")) {
            self.transformGame(args[0]);
            try out.line("OK", .{});
        } else if (eq(cmd, "EVAL")) {
            const values = evaluate(&self.pos.board, self.pos.side);
            try out.line("eval {d} weights {d} mobility {d} {d}", .{ values[0], values[1], values[2], values[3] });
        } else if (eq(cmd, "STABLE")) {
            const values = stable(&self.pos.board);
            try out.line("stable B {d} W {d}", .{ values[0], values[1] });
        } else if (eq(cmd, "HINT")) {
            const choices = try self.solver.ranked(self.pos.board, self.pos.side, @intCast(n));
            for (choices.data[0..choices.len]) |choice| {
                const sq = squareName(choice.p);
                try out.line("{s} {d}", .{ &sq, choice.value });
            }
        } else if (eq(cmd, "PV")) {
            const value = try self.solver.search(self.pos.board, self.pos.side, @intCast(n));
            const pv = try self.solver.variation(self.pos.board, self.pos.side, @intCast(n), out.gpa);
            try out.line("pv {d} {s}", .{ value, pv.path });
        } else if (eq(cmd, "AI")) {
            const choices = try self.solver.ranked(self.pos.board, self.pos.side, @intCast(n));
            _ = try self.play(choices.data[0].p, out, false, choices.data[0].value);
        } else if (eq(cmd, "ANALYZE")) {
            var losses = [_]i32{ 0, 0 };
            for (self.history[0..self.nh], 0..) |m, i| {
                const choices = try self.solver.ranked(m.before.board, m.side, @intCast(n));
                const best = choices.data[0];
                var played: i32 = best.value;
                for (choices.data[0..choices.len]) |choice| {
                    if (choice.p == m.p) played = choice.value;
                }
                losses[if (m.side == 'B') 0 else 1] += best.value - played;
                const sq = squareName(m.p);
                const winner = squareName(best.p);
                try out.line("{d} {c} {s} {d} best {s} {d}", .{ i + 1, m.side, &sq, played, &winner, best.value });
            }
            try out.line("loss B {d} W {d}", .{ losses[0], losses[1] });
        } else if (eq(cmd, "SOLVE")) {
            if (count(&self.pos.board, '.') >= 9) {
                try out.line("ERROR too many empties", .{});
            } else {
                const choices = try self.solver.ranked(self.pos.board, self.pos.side, -1);
                for (choices.data[0..choices.len]) |choice| {
                    const sq = squareName(choice.p);
                    try out.line("{s} {d}", .{ &sq, choice.value });
                }
                const pv = try self.solver.variation(self.pos.board, self.pos.side, -1, out.gpa);
                try out.line("line {s}", .{pv.path});
                try out.line("final B {d} W {d}", .{ count(&pv.board, 'B'), count(&pv.board, 'W') });
            }
        } else if (eq(cmd, "AUTOPLAY")) {
            try self.automatic(@intCast(n), @intCast(number(args[1]).?), null, out);
        } else if (eq(cmd, "RANDOM")) {
            try self.automatic(0, 0, n, out);
        } else if (eq(cmd, "MC")) {
            try self.monteCarlo(n, number(args[1]).?, out);
        } else if (eq(cmd, "PERFT")) {
            try out.line("perft {d} {d}", .{ n, try self.solver.perft(self.pos.board, self.pos.side, @intCast(n)) });
        } else if (eq(cmd, "DIVIDE")) {
            const moves = legal(&self.pos.board, self.pos.side);
            var total: u64 = 0;
            for (moves.data[0..moves.len]) |p| {
                const value = try self.solver.perft(place(&self.pos.board, self.pos.side, p), other(self.pos.side), @intCast(n - 1));
                const sq = squareName(p);
                try out.line("{s} {d}", .{ &sq, value });
                total += value;
            }
            try out.line("total {d}", .{total});
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const commands = try std.fmt.parseInt(usize, std.mem.trim(u8, lines.next().?, "\r"), 10);
    var out: Builder = .{ .gpa = gpa };
    var game = Game.init(gpa);
    for (0..commands) |_| {
        try game.execute(std.mem.trimEnd(u8, lines.next().?, "\r"), &out);
    }
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
