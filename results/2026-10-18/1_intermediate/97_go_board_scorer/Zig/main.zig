const std = @import("std");
const Text = []const u8;
const Allocator = std.mem.Allocator;
const Board = [361]u8;
const Columns = "ABCDEFGHJKLMNOPQRST";
const Alphabet = "abcdefghijklmnopqrstuvwxyz";

fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn among(s: Text, options: []const Text) bool {
    for (options) |item| if (eq(s, item)) return true;
    return false;
}

const Output = struct {
    allocator: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn write(self: *Output, s: Text) !void {
        try self.bytes.appendSlice(self.allocator, s);
    }

    fn print(self: *Output, comptime fmt: Text, args: anytype) !void {
        try self.write(try std.fmt.allocPrint(self.allocator, fmt, args));
    }

    fn line(self: *Output, comptime fmt: Text, args: anytype) !void {
        try self.print(fmt ++ "\n", args);
    }
};

fn words(allocator: Allocator, text: Text) ![]Text {
    var result: std.ArrayList(Text) = .empty;
    var it = std.mem.splitScalar(u8, text, ' ');
    while (it.next()) |w| try result.append(allocator, w);
    return result.items;
}

fn opponent(color: u8) u8 {
    return if (color == 'B') 'W' else 'B';
}

fn colorIndex(color: u8) usize {
    return if (color == 'B') 0 else 1;
}

fn parseKomi(text: Text) ?i32 {
    if (text.len == 0) return null;
    var i: usize = 0;
    const negative = text[0] == '-';
    if (negative) i += 1;
    if (i >= text.len) return null;
    if (text[i] < '0' or text[i] > '9') return null;
    const start = i;
    while (i < text.len and text[i] >= '0' and text[i] <= '9') i += 1;
    if (i - start > 1 and text[start] == '0') return null;
    const integer = std.fmt.parseInt(i32, text[start..i], 10) catch return null;
    if (integer > 100) return null;
    var half: i32 = integer * 2;
    if (i < text.len) {
        if (i + 2 != text.len or text[i] != '.' or (text[i + 1] != '0' and text[i + 1] != '5')) return null;
        if (text[i + 1] == '5') half += 1;
    }
    if (negative and half == 0) return null;
    return if (negative) -half else half;
}

fn halfText(allocator: Allocator, value: i32) !Text {
    const magnitude: i32 = @intCast(@abs(value));
    return std.fmt.allocPrint(allocator, "{s}{d}.{c}", .{
        if (value < 0) "-" else "",
        @divTrunc(magnitude, 2),
        if (@mod(magnitude, 2) == 0) @as(u8, '0') else @as(u8, '5'),
    });
}

fn pointIndex(text: Text, n: usize) ?usize {
    if (text.len < 2) return null;
    const c = std.mem.indexOfScalar(u8, Columns, text[0]) orelse return null;
    if (c >= n or text[1] == '0') return null;
    for (text[1..]) |ch| if (ch < '0' or ch > '9') return null;
    const row = std.fmt.parseInt(usize, text[1..], 10) catch return null;
    if (row == 0 or row > n) return null;
    return (row - 1) * n + c;
}

fn pointText(allocator: Allocator, n: usize, p: usize) !Text {
    return std.fmt.allocPrint(allocator, "{c}{d}", .{ Columns[p % n], p / n + 1 });
}

fn sgfPoint(n: usize, p: usize) [2]u8 {
    return .{ Alphabet[p % n], Alphabet[n - 1 - p / n] };
}

const Points = struct {
    items: [4]usize = undefined,
    len: usize = 0,

    fn add(self: *Points, p: usize) void {
        self.items[self.len] = p;
        self.len += 1;
    }
};

fn adjacent(n: usize, p: usize, diagonals: bool) Points {
    var points: Points = .{};
    const row = p / n;
    const col = p % n;
    if (diagonals) {
        if (row > 0 and col > 0) points.add(p - n - 1);
        if (row > 0 and col + 1 < n) points.add(p - n + 1);
        if (row + 1 < n and col > 0) points.add(p + n - 1);
        if (row + 1 < n and col + 1 < n) points.add(p + n + 1);
    } else {
        if (row > 0) points.add(p - n);
        if (row + 1 < n) points.add(p + n);
        if (col > 0) points.add(p - 1);
        if (col + 1 < n) points.add(p + 1);
    }
    return points;
}

const Group = struct {
    color: u8,
    first: usize,
    stones: [361]bool = [_]bool{false} ** 361,
    liberties: [361]bool = [_]bool{false} ** 361,
    size: usize = 0,
    liberty_count: usize = 0,
};

fn group(board: *const Board, n: usize, origin: usize) Group {
    var result = Group{ .color = board[origin], .first = origin };
    var queue: [361]usize = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = origin;
    result.stones[origin] = true;
    while (head < tail) {
        const q = queue[head];
        head += 1;
        result.size += 1;
        if (q < result.first) result.first = q;
        const neighbors = adjacent(n, q, false);
        for (neighbors.items[0..neighbors.len]) |t| {
            if (board[t] == result.color and !result.stones[t]) {
                result.stones[t] = true;
                queue[tail] = t;
                tail += 1;
            } else if (board[t] == '.' and !result.liberties[t]) {
                result.liberties[t] = true;
                result.liberty_count += 1;
            }
        }
    }
    return result;
}

fn groups(allocator: Allocator, board: *const Board, n: usize, color: ?u8) ![]Group {
    var result: std.ArrayList(Group) = .empty;
    var visited = [_]bool{false} ** 361;
    for (board[0 .. n * n], 0..) |stone, p| {
        if (stone == '.' or visited[p] or (color != null and stone != color.?)) continue;
        const g = group(board, n, p);
        for (0..n * n) |q| if (g.stones[q]) { visited[q] = true; };
        try result.append(allocator, g);
    }
    return result.items;
}

const Placement = struct {
    board: Board,
    captured: usize = 0,
    reason: ?Text = null,
};

fn placement(board: *const Board, n: usize, color: u8, p: usize) Placement {
    var result = Placement{ .board = board.* };
    if (board[p] != '.') {
        result.reason = "occupied";
        return result;
    }
    result.board[p] = color;
    var visited = [_]bool{false} ** 361;
    const ns = adjacent(n, p, false);
    for (ns.items[0..ns.len]) |q| {
        if (result.board[q] != opponent(color) or visited[q]) continue;
        const enemy = group(&result.board, n, q);
        for (0..n * n) |t| if (enemy.stones[t]) { visited[t] = true; };
        if (enemy.liberty_count == 0) {
            for (0..n * n) |t| if (enemy.stones[t]) { result.board[t] = '.'; };
            result.captured += enemy.size;
        }
    }
    if (group(&result.board, n, p).liberty_count == 0) result.reason = "suicide";
    return result;
}

const Region = struct {
    first: usize,
    points: [361]bool = [_]bool{false} ** 361,
    size: usize = 0,
    owner: u8 = '.',
};

fn regions(allocator: Allocator, board: *const Board, n: usize) ![]Region {
    var result: std.ArrayList(Region) = .empty;
    var visited = [_]bool{false} ** 361;
    for (0..n * n) |p| {
        if (board[p] != '.' or visited[p]) continue;
        var r = Region{ .first = p };
        var queue: [361]usize = undefined;
        var head: usize = 0;
        var tail: usize = 1;
        queue[0] = p;
        visited[p] = true;
        r.points[p] = true;
        var border: u8 = '.';
        var mixed = false;
        while (head < tail) {
            const q = queue[head];
            head += 1;
            r.size += 1;
            const ns = adjacent(n, q, false);
            for (ns.items[0..ns.len]) |t| {
                if (board[t] == '.' and !visited[t]) {
                    visited[t] = true;
                    r.points[t] = true;
                    queue[tail] = t;
                    tail += 1;
                } else if (board[t] != '.') {
                    if (border != '.' and border != board[t]) mixed = true;
                    border = board[t];
                }
            }
        }
        r.owner = if (mixed) '.' else border;
        try result.append(allocator, r);
    }
    return result.items;
}

const Area = struct {
    points: [361]bool = [_]bool{false} ** 361,
    touching: [361]bool = [_]bool{false} ** 361,
    vital: [361]bool = [_]bool{false} ** 361,
};

fn safeGroups(allocator: Allocator, board: *const Board, n: usize, color: u8) ![]Group {
    const own = try groups(allocator, board, n, color);
    var areas: std.ArrayList(Area) = .empty;
    var visited = [_]bool{false} ** 361;
    for (0..n * n) |p| {
        if (board[p] == color or visited[p]) continue;
        var a = Area{};
        var queue: [361]usize = undefined;
        var head: usize = 0;
        var tail: usize = 1;
        queue[0] = p;
        visited[p] = true;
        a.points[p] = true;
        while (head < tail) {
            const q = queue[head];
            head += 1;
            const ns = adjacent(n, q, false);
            for (ns.items[0..ns.len]) |t| {
                if (board[t] != color and !visited[t]) {
                    visited[t] = true;
                    a.points[t] = true;
                    queue[tail] = t;
                    tail += 1;
                }
            }
        }
        for (own, 0..) |g, i| {
            var vital = true;
            var touching = false;
            for (0..n * n) |q| {
                if (!a.points[q]) continue;
                if (board[q] == '.' and !g.liberties[q]) vital = false;
                const ns = adjacent(n, q, false);
                for (ns.items[0..ns.len]) |t| {
                    if (g.stones[t]) touching = true;
                }
            }
            a.touching[i] = touching;
            a.vital[i] = vital;
        }
        try areas.append(allocator, a);
    }
    var live = [_]bool{false} ** 361;
    var active = [_]bool{false} ** 361;
    for (0..own.len) |i| live[i] = true;
    for (0..areas.items.len) |i| active[i] = true;
    while (true) {
        var changed = false;
        for (0..own.len) |i| {
            if (!live[i]) continue;
            var count: usize = 0;
            for (areas.items, 0..) |a, j| {
                if (active[j] and a.vital[i]) count += 1;
            }
            if (count < 2) {
                live[i] = false;
                changed = true;
            }
        }
        for (areas.items, 0..) |a, j| {
            if (!active[j]) continue;
            for (0..own.len) |i| {
                if (a.touching[i] and !live[i]) {
                    active[j] = false;
                    changed = true;
                    break;
                }
            }
        }
        if (!changed) break;
    }
    var result: std.ArrayList(Group) = .empty;
    for (own, 0..) |g, i| if (live[i]) { try result.append(allocator, g); };
    return result.items;
}

const Reading = struct {
    success: bool,
    move: ?usize = null,
};

fn ladderRead(board: Board, n: usize, target: usize, depth: usize, defending: bool) Reading {
    if (depth >= 40) return .{ .success = defending };
    const g = group(&board, n, target);
    const defender = g.color;
    const attacker = opponent(defender);
    var candidate = g.liberties;
    if (defending) {
        var seen = [_]bool{false} ** 361;
        for (0..n * n) |p| {
            if (!g.stones[p]) continue;
            const ns = adjacent(n, p, false);
            for (ns.items[0..ns.len]) |q| {
                if (board[q] != attacker or seen[q]) continue;
                const enemy = group(&board, n, q);
                for (0..n * n) |s| if (enemy.stones[s]) { seen[s] = true; };
                if (enemy.liberty_count == 1) {
                    for (0..n * n) |s| if (enemy.liberties[s]) { candidate[s] = true; };
                }
            }
        }
    }
    for (0..n * n) |p| {
        if (!candidate[p]) continue;
        const next = placement(&board, n, if (defending) defender else attacker, p);
        if (next.reason != null) continue;
        const after = group(&next.board, n, target);
        var good = false;
        if (defending) {
            if (after.liberty_count >= 3) good = true
            else if (after.liberty_count == 2) {
                good = !ladderRead(next.board, n, target, depth + 1, false).success;
            }
        } else if (after.liberty_count == 1) {
            good = !ladderRead(next.board, n, target, depth + 1, true).success;
        }
        if (good) return .{ .success = true, .move = p };
    }
    return .{ .success = false };
}

const Snapshot = struct {
    board: Board,
    turn: u8,
    captures: [2]usize,
    passes: usize,
    over: bool,
};

const Move = struct {
    color: u8,
    point: ?usize,
    captured: usize,
    before: Snapshot,
};

const Record = struct {
    color: u8,
    point: ?usize,
};

fn records(allocator: Allocator, text: Text, n: usize) !?[]Record {
    if (text.len == 0) return null;
    var result: std.ArrayList(Record) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (i + 4 > text.len or text[i] != ';' or (text[i + 1] != 'B' and text[i + 1] != 'W') or text[i + 2] != '[') return null;
        var j = i + 3;
        while (j < text.len and text[j] != ']') j += 1;
        if (j == text.len) return null;
        var p: ?usize = null;
        if (j != i + 3) {
            if (j != i + 5) return null;
            const a = std.mem.indexOfScalar(u8, Alphabet, text[i + 3]) orelse return null;
            const b = std.mem.indexOfScalar(u8, Alphabet, text[i + 4]) orelse return null;
            if (a >= n or b >= n) return null;
            p = (n - 1 - b) * n + a;
        }
        try result.append(allocator, .{ .color = text[i + 1], .point = p });
        i = j + 1;
    }
    return result.items;
}

fn handicapNames(n: usize) []const Text {
    return switch (n) {
        9 => &.{ "C3", "G7", "C7", "G3", "C5", "G5", "E3", "E7", "E5" },
        13 => &.{ "D4", "K10", "D10", "K4", "D7", "K7", "G4", "G10", "G7" },
        else => &.{ "D4", "Q16", "D16", "Q4", "D10", "Q10", "K4", "K16", "K10" },
    };
}

const Game = struct {
    n: usize = 19,
    komi: i32 = 13,
    board: Board = [_]u8{'.'} ** 361,
    turn: u8 = 'B',
    captures: [2]usize = .{ 0, 0 },
    passes: usize = 0,
    over: bool = false,
    superko: bool = false,
    handicap: [9]usize = undefined,
    handicap_len: usize = 0,
    history: [500]Move = undefined,
    history_len: usize = 0,
    positions: [501]Board = undefined,
    dead: [361]bool = [_]bool{false} ** 361,

    fn init() Game {
        var self: Game = .{};
        self.reset(19, 13);
        return self;
    }

    fn reset(self: *Game, n: usize, komi: i32) void {
        self.n = n;
        self.komi = komi;
        self.board = [_]u8{'.'} ** 361;
        self.turn = 'B';
        self.captures = .{ 0, 0 };
        self.passes = 0;
        self.over = false;
        self.handicap_len = 0;
        self.history_len = 0;
        self.positions[0] = self.board;
        self.dead = [_]bool{false} ** 361;
    }

    fn clean(self: *const Game) Board {
        var b = self.board;
        for (0..self.n * self.n) |p| if (self.dead[p]) { b[p] = '.'; };
        return b;
    }

    fn check(self: *const Game, color: u8, p: usize) Placement {
        var result = placement(&self.board, self.n, color, p);
        if (result.reason == null and self.history_len > 0) {
            if (std.mem.eql(u8, result.board[0 .. self.n * self.n], self.positions[self.history_len - 1][0 .. self.n * self.n])) {
                result.reason = "ko";
            }
        }
        if (result.reason == null and self.superko) {
            for (self.positions[0 .. self.history_len + 1]) |before| {
                if (std.mem.eql(u8, result.board[0 .. self.n * self.n], before[0 .. self.n * self.n])) {
                    result.reason = "superko";
                    break;
                }
            }
        }
        return result;
    }

    fn move(self: *Game, color: u8, p: ?usize) usize {
        var record = Move{ .color = color, .point = p, .captured = 0, .before = .{
            .board = self.board, .turn = self.turn, .captures = self.captures,
            .passes = self.passes, .over = self.over,
        } };
        if (p) |point_| {
            const next = self.check(color, point_);
            self.board = next.board;
            record.captured = next.captured;
            self.captures[colorIndex(color)] += next.captured;
            self.passes = 0;
        } else {
            self.passes += 1;
            if (self.passes == 2) self.over = true;
        }
        self.turn = opponent(color);
        self.history[self.history_len] = record;
        self.history_len += 1;
        self.positions[self.history_len] = self.board;
        self.dead = [_]bool{false} ** 361;
        return record.captured;
    }

    fn display(self: *const Game, out: *Output, mapped: bool) !void {
        const b = if (mapped) self.clean() else self.board;
        var cells = b;
        if (mapped) {
            const rs = try regions(out.allocator, &b, self.n);
            for (rs) |r| {
                const symbol: u8 = if (r.owner == 'B') 'x' else if (r.owner == 'W') 'o' else '.';
                for (0..self.n * self.n) |p| if (r.points[p]) { cells[p] = symbol; };
            }
        }
        for (0..self.n * self.n) |p| {
            if (b[p] == 'B') cells[p] = if (!mapped and self.dead[p]) 'x' else 'X'
            else if (b[p] == 'W') cells[p] = if (!mapped and self.dead[p]) 'o' else 'O'
            else if (!mapped) {
                var star = false;
                for (handicapNames(self.n), 0..) |loc, i| {
                    if (self.n != 19 and i >= 4 and i != 8) continue;
                    if (p == pointIndex(loc, self.n).?) star = true;
                }
                cells[p] = if (star) '+' else '.';
            }
        }
        try out.write("   ");
        for (0..self.n) |i| {
            if (i > 0) try out.write(" ");
            try out.print("{c}", .{Columns[i]});
        }
        try out.write("\n");
        var row = self.n;
        while (row > 0) {
            if (row < 10) try out.write(" ");
            try out.print("{d} ", .{row});
            for (0..self.n) |c| {
                if (c > 0) try out.write(" ");
                try out.print("{c}", .{cells[(row - 1) * self.n + c]});
            }
            try out.line(" {d}", .{row});
            row -= 1;
        }
        try out.write("   ");
        for (0..self.n) |i| {
            if (i > 0) try out.write(" ");
            try out.print("{c}", .{Columns[i]});
        }
        try out.write("\n");
    }

    fn score(self: *const Game, method: Text, out: *Output) !void {
        const b = self.clean();
        const rs = try regions(out.allocator, &b, self.n);
        var territory = [_]usize{ 0, 0 };
        for (rs) |r| {
            if (r.owner == 'B' or r.owner == 'W') territory[colorIndex(r.owner)] += r.size;
        }
        var total = [_]i32{ 0, 0 };
        for (0..2) |i| {
            const color: u8 = if (i == 0) 'B' else 'W';
            const bonus: i32 = if (i == 1) self.komi else 0;
            if (eq(method, "AREA")) {
                var stone_count: usize = 0;
                for (b[0 .. self.n * self.n]) |stone| if (stone == color) { stone_count += 1; };
                total[i] = 2 * @as(i32, @intCast(stone_count + territory[i])) + bonus;
                if (i == 0) {
                    try out.line("B stones {d} territory {d} total {s}", .{ stone_count, territory[i], try halfText(out.allocator, total[i]) });
                } else {
                    try out.line("W stones {d} territory {d} komi {s} total {s}", .{
                        stone_count, territory[i], try halfText(out.allocator, self.komi), try halfText(out.allocator, total[i]),
                    });
                }
            } else {
                var prisoners = self.captures[i];
                for (0..self.n * self.n) |p| {
                    if (self.dead[p] and self.board[p] == opponent(color)) prisoners += 1;
                }
                total[i] = 2 * @as(i32, @intCast(territory[i] + prisoners)) + bonus;
                if (i == 0) {
                    try out.line("B territory {d} prisoners {d} total {s}", .{ territory[i], prisoners, try halfText(out.allocator, total[i]) });
                } else {
                    try out.line("W territory {d} prisoners {d} komi {s} total {s}", .{
                        territory[i], prisoners, try halfText(out.allocator, self.komi), try halfText(out.allocator, total[i]),
                    });
                }
            }
        }
        const difference = total[0] - total[1];
        if (difference > 0) {
            try out.line("result B+{s}", .{try halfText(out.allocator, difference)});
        } else if (difference < 0) {
            try out.line("result W+{s}", .{try halfText(out.allocator, -difference)});
        } else {
            try out.line("result Draw", .{});
        }
    }

    fn execute(self: *Game, input: Text, out: *Output) !void {
        const parts = try words(out.allocator, input);
        const cmd = parts[0];
        const args = parts[1..];
        const cmds = [_]Text{
            "BOARD", "KOMI", "SUPERKO", "HANDICAP", "PLAY", "PASS", "REPLAY", "UNDO",
            "SHOW", "MAP", "STATUS", "CAPTURES", "HISTORY", "MOVES", "GROUP", "GROUPS",
            "ATARI", "LEGAL", "EYES", "SAFE", "LADDER", "DEAD", "REGIONS", "SCORE",
        };
        const arities = [_]usize{ 2, 1, 1, 1, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 0, 1 };
        var index: usize = 0;
        while (index < cmds.len and !eq(cmd, cmds[index])) index += 1;
        if (index == cmds.len) {
            try out.line("ERROR unknown command", .{});
            return;
        }
        if (args.len != arities[index]) {
            try out.line("ERROR bad arguments", .{});
            return;
        }
        const a: Text = if (args.len > 0) args[0] else "";
        const b: Text = if (args.len > 1) args[1] else "";
        var valid = true;
        if (eq(cmd, "BOARD")) valid = among(a, &.{ "9", "13", "19" }) and parseKomi(b) != null
        else if (eq(cmd, "KOMI")) valid = parseKomi(a) != null
        else if (eq(cmd, "SUPERKO")) valid = among(a, &.{ "ON", "OFF" })
        else if (eq(cmd, "HANDICAP")) valid = among(a, &.{ "2", "3", "4", "5", "6", "7", "8", "9" })
        else if (among(cmd, &.{ "PLAY", "PASS", "LEGAL", "EYES", "SAFE" })) valid = among(a, &.{ "B", "W" })
        else if (eq(cmd, "SCORE")) valid = among(a, &.{ "AREA", "TERRITORY" });
        if (!valid) {
            try out.line("ERROR bad arguments", .{});
            return;
        }
        var p: ?usize = null;
        if (among(cmd, &.{ "PLAY", "GROUP", "LADDER", "DEAD" })) {
            p = pointIndex(if (eq(cmd, "PLAY")) b else a, self.n);
            if (p == null) {
                try out.line("ERROR bad point", .{});
                return;
            }
        }
        var parsed_records: ?[]Record = null;
        if (eq(cmd, "REPLAY")) {
            parsed_records = try records(out.allocator, a, self.n);
            if (parsed_records == null) {
                try out.line("ERROR bad sequence", .{});
                return;
            }
        }
        if (self.over and among(cmd, &.{ "PLAY", "PASS", "REPLAY" })) {
            try out.line("ERROR game over", .{});
            return;
        }
        if (eq(cmd, "BOARD")) {
            self.reset(std.fmt.parseInt(usize, a, 10) catch unreachable, parseKomi(b).?);
            try out.line("board {d} komi {s}", .{ self.n, try halfText(out.allocator, self.komi) });
        } else if (eq(cmd, "KOMI")) {
            self.komi = parseKomi(a).?;
            try out.line("komi {s}", .{try halfText(out.allocator, self.komi)});
        } else if (eq(cmd, "SUPERKO")) {
            self.superko = eq(a, "ON");
            try out.line("superko {s}", .{if (self.superko) "on" else "off"});
        } else if (eq(cmd, "HANDICAP")) {
            if (self.history_len > 0) {
                try out.line("ERROR handicap not allowed", .{});
                return;
            }
            for (self.board[0 .. self.n * self.n]) |stone| {
                if (stone != '.') {
                    try out.line("ERROR handicap not allowed", .{});
                    return;
                }
            }
            const k = std.fmt.parseInt(usize, a, 10) catch unreachable;
            const locations = handicapNames(self.n);
            for (0..k) |i| {
                const h: usize = if (k == 5 and i == 4) 8 else if (k == 7 and i == 6) 8 else i;
                const pt = pointIndex(locations[h], self.n).?;
                self.handicap[i] = pt;
                self.board[pt] = 'B';
            }
            self.handicap_len = k;
            self.turn = 'W';
            self.positions[0] = self.board;
            self.dead = [_]bool{false} ** 361;
            try out.print("handicap {d}", .{k});
            for (self.handicap[0..k]) |pt| try out.print(" {s}", .{try pointText(out.allocator, self.n, pt)});
            try out.write("\n");
        } else if (eq(cmd, "PLAY")) {
            if (a[0] != self.turn) {
                try out.line("ILLEGAL {c} {s} turn", .{ a[0], b });
                return;
            }
            const result = self.check(a[0], p.?);
            if (result.reason) |reason| {
                try out.line("ILLEGAL {c} {s} {s}", .{ a[0], b, reason });
            } else {
                const captured = self.move(a[0], p);
                try out.print("{c} {s}", .{ a[0], b });
                if (captured > 0) try out.print(" captures {d}", .{captured});
                try out.write("\n");
            }
        } else if (eq(cmd, "PASS")) {
            if (a[0] != self.turn) {
                try out.line("ILLEGAL {c} pass turn", .{a[0]});
            } else {
                _ = self.move(a[0], null);
                try out.line("{c} pass", .{a[0]});
                if (self.over) try out.line("game over", .{});
            }
        } else if (eq(cmd, "REPLAY")) {
            var count: usize = 0;
            var failed: ?Record = null;
            var why: Text = "";
            for (parsed_records.?) |r| {
                if (self.over) {
                    failed = r;
                    why = "game over";
                    break;
                }
                if (r.color != self.turn) {
                    failed = r;
                    why = "turn";
                    break;
                }
                if (r.point) |q| {
                    if (self.check(r.color, q).reason) |reason| {
                        failed = r;
                        why = reason;
                        break;
                    }
                }
                _ = self.move(r.color, r.point);
                count += 1;
            }
            try out.print("replay {d} moves", .{count});
            if (failed) |r| {
                const pt = if (r.point) |q| try pointText(out.allocator, self.n, q) else "pass";
                try out.print(" stopped {c} {s} {s}", .{ r.color, pt, why });
            }
            try out.write("\n");
            if (self.over) try out.line("game over", .{});
        } else if (eq(cmd, "UNDO")) {
            if (self.history_len == 0) {
                try out.line("ERROR nothing to undo", .{});
            } else {
                self.history_len -= 1;
                const m = self.history[self.history_len];
                self.board = m.before.board;
                self.turn = m.before.turn;
                self.captures = m.before.captures;
                self.passes = m.before.passes;
                self.over = m.before.over;
                self.dead = [_]bool{false} ** 361;
                const pt = if (m.point) |q| try pointText(out.allocator, self.n, q) else "pass";
                try out.line("undo {c} {s}", .{ m.color, pt });
            }
        } else if (eq(cmd, "SHOW") or eq(cmd, "MAP")) {
            try self.display(out, eq(cmd, "MAP"));
        } else if (eq(cmd, "STATUS")) {
            try out.line("size {d} komi {s} handicap {d} superko {s}", .{
                self.n, try halfText(out.allocator, self.komi), self.handicap_len, if (self.superko) "on" else "off",
            });
            if (self.over) try out.line("moves {d} game over", .{self.history_len})
            else try out.line("moves {d} next {c} passes {d}", .{ self.history_len, self.turn, self.passes });
        } else if (eq(cmd, "CAPTURES")) {
            try out.line("captures B {d} W {d}", .{ self.captures[0], self.captures[1] });
        } else if (eq(cmd, "HISTORY")) {
            try out.line("history {d}", .{self.history_len});
            for (self.history[0..self.history_len], 0..) |m, i| {
                const pt = if (m.point) |q| try pointText(out.allocator, self.n, q) else "pass";
                try out.print("{d} {c} {s}", .{ i + 1, m.color, pt });
                if (m.captured > 0) try out.print(" captures {d}", .{m.captured});
                try out.write("\n");
            }
        } else if (eq(cmd, "MOVES")) {
            try out.print("(;GM[1]FF[4]SZ[{d}]KM[{s}]", .{ self.n, try halfText(out.allocator, self.komi) });
            if (self.handicap_len > 0) {
                try out.print("HA[{d}]AB", .{self.handicap_len});
                for (self.handicap[0..self.handicap_len]) |pt| {
                    const loc = sgfPoint(self.n, pt);
                    try out.print("[{s}]", .{&loc});
                }
            }
            for (self.history[0..self.history_len]) |m| {
                if (m.point) |q| {
                    const loc = sgfPoint(self.n, q);
                    try out.print(";{c}[{s}]", .{ m.color, &loc });
                } else {
                    try out.print(";{c}[]", .{m.color});
                }
            }
            try out.write(")\n");
        } else if (eq(cmd, "GROUP") or eq(cmd, "DEAD") or eq(cmd, "LADDER")) {
            if (self.board[p.?] == '.') {
                try out.line("ERROR no stone", .{});
                return;
            }
            const g = group(&self.board, self.n, p.?);
            const first = try pointText(out.allocator, self.n, g.first);
            if (eq(cmd, "GROUP")) {
                try out.line("group {c} {s} size {d} liberties {d}", .{ g.color, first, g.size, g.liberty_count });
                try out.write("stones");
                for (0..self.n * self.n) |q| {
                    if (g.stones[q]) try out.print(" {s}", .{try pointText(out.allocator, self.n, q)});
                }
                try out.write("\nliberties");
                for (0..self.n * self.n) |q| {
                    if (g.liberties[q]) try out.print(" {s}", .{try pointText(out.allocator, self.n, q)});
                }
                try out.write("\n");
            } else if (eq(cmd, "DEAD")) {
                const is_dead = self.dead[p.?];
                for (0..self.n * self.n) |q| if (g.stones[q]) { self.dead[q] = !is_dead; };
                try out.line("{s} {c} {s} size {d}", .{ if (is_dead) "alive" else "dead", g.color, first, g.size });
            } else if (g.liberty_count >= 3) {
                try out.line("ladder {s} safe", .{a});
            } else {
                const defending = g.liberty_count == 1;
                const reading = ladderRead(self.board, self.n, p.?, 0, defending);
                if (defending) {
                    if (reading.success) {
                        try out.line("ladder {s} escapes {s}", .{ a, try pointText(out.allocator, self.n, reading.move.?) });
                    } else {
                        try out.line("ladder {s} captured", .{a});
                    }
                } else if (reading.success) {
                    try out.line("ladder {s} captured {s}", .{ a, try pointText(out.allocator, self.n, reading.move.?) });
                } else {
                    try out.line("ladder {s} escapes", .{a});
                }
            }
        } else if (eq(cmd, "GROUPS") or eq(cmd, "ATARI")) {
            const all = try groups(out.allocator, &self.board, self.n, null);
            if (eq(cmd, "GROUPS")) try out.line("groups {d}", .{all.len});
            var count: usize = 0;
            for (all) |g| {
                const first = try pointText(out.allocator, self.n, g.first);
                if (eq(cmd, "GROUPS")) {
                    try out.line("{c} {s} size {d} liberties {d}{s}", .{
                        g.color, first, g.size, g.liberty_count, if (self.dead[g.first]) " dead" else "",
                    });
                } else if (g.liberty_count == 1) {
                    count += 1;
                    var liberty: usize = 0;
                    while (!g.liberties[liberty]) liberty += 1;
                    try out.line("atari {c} {s} size {d} at {s}", .{
                        g.color, first, g.size, try pointText(out.allocator, self.n, liberty),
                    });
                }
            }
            if (eq(cmd, "ATARI") and count == 0) try out.line("atari none", .{});
        } else if (eq(cmd, "LEGAL")) {
            var count: usize = 0;
            var rejected: std.ArrayList(struct { p: usize, reason: Text }) = .empty;
            for (0..self.n * self.n) |q| {
                if (self.board[q] != '.') continue;
                const result = self.check(a[0], q);
                if (result.reason) |reason| {
                    try rejected.append(out.allocator, .{ .p = q, .reason = reason });
                } else count += 1;
            }
            try out.line("legal {c} {d}", .{ a[0], count });
            for (rejected.items) |r| {
                try out.line("{s} {s}", .{ try pointText(out.allocator, self.n, r.p), r.reason });
            }
        } else if (eq(cmd, "EYES")) {
            var found: std.ArrayList(struct { p: usize, real: bool }) = .empty;
            for (0..self.n * self.n) |q| {
                if (self.board[q] != '.') continue;
                const ns = adjacent(self.n, q, false);
                var shaped = true;
                for (ns.items[0..ns.len]) |t| if (self.board[t] != a[0]) { shaped = false; };
                if (!shaped) continue;
                const diag = adjacent(self.n, q, true);
                var enemy_count: usize = 0;
                for (diag.items[0..diag.len]) |t| if (self.board[t] == opponent(a[0])) { enemy_count += 1; };
                const real = if (ns.len == 4) enemy_count <= 1 else enemy_count == 0;
                try found.append(out.allocator, .{ .p = q, .real = real });
            }
            try out.line("eyes {c} {d}", .{ a[0], found.items.len });
            for (found.items) |e| {
                try out.line("{s} {s}", .{ try pointText(out.allocator, self.n, e.p), if (e.real) "real" else "false" });
            }
        } else if (eq(cmd, "SAFE")) {
            const alive = try safeGroups(out.allocator, &self.board, self.n, a[0]);
            try out.line("safe {c} {d}", .{ a[0], alive.len });
            for (alive) |g| try out.line("{s} size {d}", .{ try pointText(out.allocator, self.n, g.first), g.size });
        } else if (eq(cmd, "REGIONS")) {
            const bclean = self.clean();
            const rs = try regions(out.allocator, &bclean, self.n);
            try out.line("regions {d}", .{rs.len});
            for (rs) |r| {
                const owner: Text = if (r.owner == '.') "neutral" else if (r.owner == 'B') "B" else "W";
                try out.line("{s} size {d} {s}", .{ try pointText(out.allocator, self.n, r.first), r.size, owner });
            }
        } else if (eq(cmd, "SCORE")) {
            try self.score(a, out);
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var input_buffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const input_text = try input.interface.allocRemaining(allocator, .unlimited);
    var lines = std.mem.splitScalar(u8, input_text, '\n');
    const count = try std.fmt.parseInt(usize, std.mem.trim(u8, lines.next().?, "\r"), 10);
    const game = try allocator.create(Game);
    game.* = Game.init();
    var output = Output{ .allocator = allocator };
    for (0..count) |_| {
        try game.execute(std.mem.trimEnd(u8, lines.next().?, "\r"), &output);
    }
    var output_buffer: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try sink.interface.writeAll(output.bytes.items);
    try sink.interface.flush();
}
