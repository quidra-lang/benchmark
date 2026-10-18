const std = @import("std");

const Allocator = std.mem.Allocator;
const Failure = error{
    UnknownMatch,
    DuplicateMatch,
    InvalidOption,
    WrongEvent,
    MatchOver,
    TooManyPins,
    InvalidDart,
    PlayerNotOnCourt,
    PlayerAlreadyOnCourt,
    NoSubstitutionsLeft,
    NoTimeoutsLeft,
    NothingToUndo,
    MatchNotFinished,
};

const Error = Failure || Allocator.Error || std.Io.Writer.Error;
fn integer(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}

fn split(gpa: Allocator, text: []const u8, delimiter: u8) Allocator.Error![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |part|
        try result.append(gpa, part);
    return result.items;
}

const Sport = enum {
    TENNIS,
    TABLETENNIS,
    BADMINTON,
    VOLLEYBALL,
    BOWLING,
    DARTS
};

const Final = enum {
    TB7,
    TB10,
    ADV,
    SUPER
};

const Config = struct {
    id: []const u8,
    sport: Sport,
    names: [2][]const u8,
    first: usize = 0,
    sets: i64 = 3,
    no_ad: bool = false,
    final: Final = .TB7,
    table_games: i64 = 5,
    start: i64 = 501,
    legs: i64 = 1,
    lineup: [2][6]i64 = .{ .{ 0, 0, 0, 0, 0, 0 }, .{ 0, 0, 0, 0, 0, 0 } },

    fn rally(self: Config) bool {
        return self.sport == .TENNIS or self.sport == .TABLETENNIS or self.sport == .BADMINTON or self.sport == .VOLLEYBALL;
    }
};

const Dart = struct {
    name: []const u8,
    value: i64,
    double: bool
};

const Route = struct {
    darts: [3]usize = undefined,
    len: usize = 0
};

const DartTable = struct {
    items: [63]Dart = undefined,

    fn init(gpa: Allocator) Allocator.Error!DartTable {
        var self = DartTable{};
        for ([_]u8{ 'S', 'T', 'D' }, 0..) |prefix, group| {
            for (0..20) |i| {
                const n: i64 = @intCast(20 - i);
                self.items[group * 20 + i] = .{
                    .name = try std.fmt.allocPrint(gpa, "{c}{d}", .{ prefix, n }),
                    .value = n * @as(i64, if (prefix == 'S') 1 else if (prefix == 'T') 3 else 2),
                    .double = prefix == 'D'
                };
            }
        }
        self.items[60] = .{ .name = "25", .value = 25, .double = false };
        self.items[61] = .{ .name = "BULL", .value = 50, .double = true };
        self.items[62] = .{ .name = "MISS", .value = 0, .double = false };
        return self;
    }

    fn index(self: *const DartTable, name: []const u8) ?usize {
        for (self.items, 0..) |dart, i| {
            if (std.mem.eql(u8, dart.name, name))
                return i;
        }
        return null;
    }

    fn checkout(self: *const DartTable, score: i64, maximum: usize) ?Route {
        const b = [_]usize{
            40,
            41,
            42,
            43,
            44,
            45,
            46,
            47,
            48,
            49,
            50,
            51,
            52,
            53,
            54,
            55,
            56,
            57,
            58,
            59,
            61
        };
        for (b) |last| {
            if (self.items[last].value == score)
                return .{ .darts = .{ last, 0, 0 }, .len = 1 };
        }
        if (maximum >= 2) {
            for (0..62) |first| {
                for (b) |last| {
                    if (self.items[first].value + self.items[last].value == score)
                        return .{ .darts = .{ first, last, 0 }, .len = 2 };
                }
            }
        }
        if (maximum >= 3) {
            for (0..62) |first| {
                for (0..62) |second| {
                    for (b) |last| {
                        if (self.items[first].value + self.items[second].value + self.items[last].value == score)
                            return .{ .darts = .{ first, second, last }, .len = 3 };
                    }
                }
            }
        }
        return null;
    }

    fn write(self: *const DartTable, out: *std.Io.Writer, indices: []const usize) std.Io.Writer.Error!void {
        for (indices, 0..) |index_value, i| {
            if (i > 0)
                try out.writeByte(' ');
            try out.writeAll(self.items[index_value].name);
        }
    }
};

const FinishedSet = struct {
    score: [2]i64,
    tie_loser: ?i64 = null,
    super_tie: bool = false,

    fn write(self: FinishedSet, out: *std.Io.Writer, reverse: bool) std.Io.Writer.Error!void {
        if (self.super_tie)
            try out.writeByte('[');
        try writePair(out, self.score, reverse);
        if (self.super_tie)
            try out.writeByte(']');
        if (self.tie_loser) |loser|
            try out.print("({d})", .{ loser });
    }
};

const EventKind = enum {
    POINT,
    ROLL,
    THROW,
    SUB,
    TIMEOUT
};

const Event = struct {
    kind: EventKind,
    side: usize = 0,
    first: i64 = 0,
    second: i64 = 0
};

const TennisKind = enum {
    normal,
    tie,
    super
};

const State = struct {
    finished: bool = false,
    winner: usize = 0,
    points: [2]i64 = .{ 0, 0 },
    games: [2]i64 = .{ 0, 0 },
    wins: [2]i64 = .{ 0, 0 },
    completed: [16]FinishedSet = undefined,
    completed_len: usize = 0,
    server: usize = 0,
    previous_winner: ?usize = null,
    current_run: i64 = 0,
    rally_points: [2]i64 = .{ 0, 0 },
    served: [2]i64 = .{ 0, 0 },
    serve_wins: [2]i64 = .{ 0, 0 },
    runs: [2]i64 = .{ 0, 0 },
    holds: [2]i64 = .{ 0, 0 },
    service_games: [2]i64 = .{ 0, 0 },
    breaks: [2]i64 = .{ 0, 0 },
    opportunities: [2]i64 = .{ 0, 0 },
    converted_breaks: [2]i64 = .{ 0, 0 },
    lineup: [2][6]i64 = undefined,
    substitutions: [2]i64 = .{ 0, 0 },
    timeouts: [2]i64 = .{ 0, 0 },
    frames: [10][3]i64 = undefined,
    marks: [10][3]u8 = undefined,
    frame_lengths: [10]usize = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    frame: usize = 0,
    standing: i64 = 10,
    new_pins: bool = true,
    remaining: [2]i64 = .{ 0, 0 },
    legs: [2]i64 = .{ 0, 0 },
    leg_number: usize = 1,
    turn_start: i64 = 0,
    turn_value: i64 = 0,
    turn: [3]usize = undefined,
    turn_len: usize = 0,
    dart_count: [2]i64 = .{ 0, 0 },
    scored: [2]i64 = .{ 0, 0 },
    busts: [2]i64 = .{ 0, 0 },
    high: [2]i64 = .{ 0, 0 },
    tons: [2]i64 = .{ 0, 0 },
    maximums: [2]i64 = .{ 0, 0 },
    attempts: [2]i64 = .{ 0, 0 },
    hits: [2]i64 = .{ 0, 0 },

    fn init(config: Config) State {
        return .{
            .server = config.first,
            .lineup = config.lineup,
            .remaining = .{ config.start, config.start },
            .turn_start = config.start
        };
    }

    fn finalTennisSet(self: *const State, config: Config) bool {
        return self.wins[0] == @divFloor(config.sets, 2) and self.wins[1] == self.wins[0];
    }

    fn tennisKind(self: *const State, config: Config) TennisKind {
        if (self.finalTennisSet(config) and config.final == .SUPER)
            return .super;
        if (self.games[0] == 6 and self.games[1] == 6 and !(self.finalTennisSet(config) and config.final == .ADV))
            return .tie;
        return .normal;
    }

    fn nextServer(self: *const State, config: Config) usize {
        if (config.sport == .TENNIS) {
            if (self.tennisKind(config) == .normal)
                return self.server;
            return self.server ^ @as(usize, @intCast(@mod(@divFloor(self.points[0] + self.points[1] + 1,
                2), 2)));
        }
        if (config.sport == .TABLETENNIS) {
            const t = self.points[0] + self.points[1];
            return config.first ^ (self.completed_len % 2) ^ @as(usize, @intCast(@mod(if (t < 20) @divFloor(t,
                2) else t, 2)));
        }
        return self.server;
    }

    fn normalGameWin(self: *const State, config: Config, side: usize, extra: i64) bool {
        return self.points[side] + extra >= 4 and (config.no_ad or self.points[side] + extra - self.points[1 - side] >= 2);
    }

    fn endSet(self: *State, config: Config, side: usize, result: FinishedSet) void {
        self.completed[self.completed_len] = result;
        self.completed_len += 1;
        self.wins[side] += 1;
        const target: i64 = switch (config.sport) {
            .TENNIS => @divFloor(config.sets, 2) + 1,
            .TABLETENNIS => @divFloor(config.table_games, 2) + 1,
            .BADMINTON => 2,
            else => 3,
        };
        if (self.wins[side] == target) {
            self.finished = true;
            self.winner = side;
            return;
        }
        self.points = .{ 0, 0 };
        self.games = .{ 0, 0 };
        if (config.sport == .VOLLEYBALL) {
            self.lineup = config.lineup;
            self.substitutions = .{ 0, 0 };
            self.timeouts = .{ 0, 0 };
            self.server = config.first ^ (self.completed_len % 2);
        }
    }

    fn point(self: *State, config: Config, side: usize) void {
        const serving = self.nextServer(config);
        const kind = if (config.sport == .TENNIS) self.tennisKind(config) else .normal;
        self.rally_points[side] += 1;
        self.served[serving] += 1;
        if (side == serving)
            self.serve_wins[side] += 1;
        if (self.previous_winner != null and self.previous_winner.? == side)
            self.current_run += 1 else {
                self.previous_winner = side;
                self.current_run = 1;
            }
        self.runs[side] = @max(self.runs[side], self.current_run);
        if (config.sport == .TENNIS and kind == .normal) {
            const receiver = 1 - self.server;
            if (self.normalGameWin(config, receiver, 1)) {
                self.opportunities[receiver] += 1;
                if (side == receiver)
                    self.converted_breaks[receiver] += 1;
            }
        }
        self.points[side] += 1;
        if (config.sport == .TENNIS) {
            if (kind != .normal) {
                const target: i64 = if (kind == .super or (self.finalTennisSet(config) and config.final == .TB10)) 10 else 7;
                if (self.points[side] >= target and self.points[side] - self.points[1 - side] >= 2) {
                    self.server = 1 - self.server;
                    if (kind == .super)
                        self.endSet(config, side, .{ .score = self.points, .super_tie = true }) else {
                            self.games[side] = 7;
                            self.endSet(config, side, .{ .score = self.games, .tie_loser = self.points[1 - side] });
                        }
                }
            } else if (self.normalGameWin(config, side, 0)) {
                self.service_games[self.server] += 1;
                if (side == self.server)
                    self.holds[side] += 1 else
                        self.breaks[side] += 1;
                self.games[side] += 1;
                self.points = .{ 0, 0 };
                self.server = 1 - self.server;
                if (self.games[side] >= 6 and self.games[side] - self.games[1 - side] >= 2)
                    self.endSet(config, side, .{ .score = self.games });
            }
            return;
        }
        if (config.sport == .BADMINTON)
            self.server = side;
        if (config.sport == .VOLLEYBALL and self.server != side) {
            self.server = side;
            std.mem.rotate(i64, &self.lineup[side], 1);
        }
        const target: i64 = if (config.sport == .TABLETENNIS) 11 else if (config.sport == .BADMINTON) 21 else if (self.completed_len == 4) 15 else 25;
        if ((self.points[side] >= target and self.points[side] - self.points[1 - side] >= 2) or (config.sport == .BADMINTON
            and self.points[side] == 30))
            self.endSet(config, side, .{ .score = self.points });
    }

    fn roll(self: *State, pins: i64) Failure!void {
        if (pins > self.standing)
            return error.TooManyPins;
        const len = self.frame_lengths[self.frame];
        self.marks[self.frame][len] = if (self.new_pins and pins == 10) 'X' else if (pins == self.standing) '/' else if (pins == 0) '-' else @as(u8,
            @intCast(pins)) + '0';
        self.frames[self.frame][len] = pins;
        self.frame_lengths[self.frame] += 1;
        self.standing -= pins;
        self.new_pins = false;
        if (self.frame < 9) {
            if (self.frames[self.frame][0] == 10 or len + 1 == 2) {
                self.frame += 1;
                self.standing = 10;
                self.new_pins = true;
            }
        } else if (len + 1 == 3 or (len + 1 == 2 and self.frames[9][0] != 10 and self.frames[9][0] + self.frames[9][1] < 10)) {
            self.finished = true;
        } else if (self.standing == 0) {
            self.standing = 10;
            self.new_pins = true;
        }
    }

    fn frameScores(self: *const State) [10]?i64 {
        var result = [_]?i64{ null } ** 10;
        for (0..10) |i| {
            const len = self.frame_lengths[i];
            if (len == 0)
                continue;
            var later: [21]i64 = undefined;
            var later_len: usize = 0;
            for (i + 1..10) |j| {
                const count = self.frame_lengths[j];
                @memcpy(later[later_len..][0..count], self.frames[j][0..count]);
                later_len += count;
            }
            if (i == 9) {
                if (self.finished) {
                    var total: i64 = 0;
                    for (self.frames[i][0..len]) |pins|
                        total += pins;
                    result[i] = total;
                }
            } else if (self.frames[i][0] == 10) {
                if (later_len >= 2)
                    result[i] = 10 + later[0] + later[1];
            } else if (len == 2) {
                const base = self.frames[i][0] + self.frames[i][1];
                if (base < 10)
                    result[i] = base else if (later_len > 0) result[i] = 10 + later[0];
            }
        }
        return result;
    }

    fn finalBowlingScore(self: *const State) i64 {
        var result: i64 = 0;
        for (self.frameScores()) |score|
            result += score orelse 0;
        return result;
    }

    fn endTurn(self: *State) void {
        self.server = 1 - self.server;
        self.turn_len = 0;
        self.turn_value = 0;
        self.turn_start = self.remaining[self.server];
    }

    fn completedTurn(self: *State, side: usize) void {
        self.high[side] = @max(self.high[side], self.turn_value);
        if (self.turn_value >= 100)
            self.tons[side] += 1;
        if (self.turn_value == 180)
            self.maximums[side] += 1;
    }

    fn throwDart(self: *State, config: Config, table: *const DartTable, index: usize) void {
        const dart = table.items[index];
        const side = self.server;
        const before = self.remaining[side];
        if (before == 50 or (before <= 40 and @mod(before, 2) == 0))
            self.attempts[side] += 1;
        self.dart_count[side] += 1;
        const rest = before - dart.value;
        if (rest < 0 or rest == 1 or (rest == 0 and !dart.double)) {
            self.scored[side] -= self.turn_value;
            self.remaining[side] = self.turn_start;
            self.busts[side] += 1;
            self.endTurn();
            return;
        }
        self.remaining[side] = rest;
        self.scored[side] += dart.value;
        self.turn_value += dart.value;
        self.turn[self.turn_len] = index;
        self.turn_len += 1;
        if (rest == 0) {
            self.hits[side] += 1;
            self.completedTurn(side);
            self.legs[side] += 1;
            if (self.legs[side] == config.legs) {
                self.completed[self.completed_len] = .{ .score = self.legs };
                self.completed_len += 1;
                self.wins[side] += 1;
                if (self.wins[side] == config.sets) {
                    self.finished = true;
                    self.winner = side;
                    return;
                }
                self.legs = .{ 0, 0 };
            }
            self.leg_number += 1;
            self.remaining = .{ config.start, config.start };
            self.server = config.first ^ ((self.leg_number - 1) % 2);
            self.turn_len = 0;
            self.turn_value = 0;
            self.turn_start = self.remaining[self.server];
        } else if (self.turn_len == 3) {
            self.completedTurn(side);
            self.endTurn();
        }
    }

    fn apply(self: *State, config: Config, table: *const DartTable, event: Event) Failure!void {
        if (self.finished)
            return error.MatchOver;
        switch (event.kind) {
            .POINT => self.point(config, event.side),
            .ROLL => try self.roll(event.first),
            .THROW => self.throwDart(config, table, @intCast(event.first)),
            .SUB => {
                const position = std.mem.findScalar(i64, &self.lineup[event.side], event.first) orelse return error.PlayerNotOnCourt;
                if (std.mem.findScalar(i64, &self.lineup[event.side], event.second) != null)
                    return error.PlayerAlreadyOnCourt;
                if (self.substitutions[event.side] == 6)
                    return error.NoSubstitutionsLeft;
                self.lineup[event.side][position] = event.second;
                self.substitutions[event.side] += 1;
            },
            .TIMEOUT => {
                if (self.timeouts[event.side] == 2)
                    return error.NoTimeoutsLeft;
                self.timeouts[event.side] += 1;
            },
        }
    }

    fn situation(self: *const State, config: Config, side: usize) ?[]const u8 {
        var trial = self.*;
        trial.point(config, side);
        if (trial.finished)
            return "match point";
        if (trial.completed_len > self.completed_len)
            return if (config.sport == .TABLETENNIS or config.sport == .BADMINTON) "game point" else
                "set point";
        if (config.sport == .TENNIS and self.tennisKind(config) == .normal and trial.games[side] != self.games[side])
            return if (side == self.nextServer(config)) "game point" else
                "break point";
        return null;
    }

    fn writeScore(self: *const State, config: Config, table: *const DartTable, out: *std.Io.Writer) Error!void {
        if (config.sport == .BOWLING) {
            try out.print("{s}: {s}", .{ config.id, config.names[0] });
            const scores = self.frameScores();
            var cumulative: i64 = 0;
            for (0..10) |i| {
                if (self.frame_lengths[i] == 0)
                    continue;
                try out.writeByte(' ');
                try out.writeAll(self.marks[i][0..self.frame_lengths[i]]);
                if (scores[i]) |value| {
                    cumulative += value;
                    try out.print("({d})", .{ cumulative });
                }
            }
            try out.writeByte('\n');
            return;
        }
        const serving = self.nextServer(config);
        try out.print("{s}: {s}{s} vs {s}{s}", .{
            config.id,
            config.names[0],
            @as([]const u8, if (!self.finished and serving == 0) "*" else ""),
            config.names[1],
            @as([]const u8, if (!self.finished and serving == 1) "*" else "")
        });
        if (config.sport == .DARTS) {
            try out.writeAll(" sets ");
            try writePair(out, self.wins, false);
            try out.writeAll(" legs ");
            try writePair(out, self.legs, false);
            try out.writeAll(" score ");
            try writePair(out, self.remaining, false);
            if (!self.finished) {
                if (self.turn_len > 0) {
                    try out.writeAll(" turn ");
                    try table.write(out, self.turn[0..self.turn_len]);
                }
                if (table.checkout(self.remaining[self.server], 3 - self.turn_len)) |route| {
                    try out.writeAll(" checkout ");
                    try table.write(out, route.darts[0..route.len]);
                }
            }
        } else {
            for (self.completed[0..self.completed_len]) |set| {
                try out.writeByte(' ');
                try set.write(out, false);
            }
            if (!self.finished) {
                try out.writeByte(' ');
                if (config.sport == .TENNIS) {
                    const kind = self.tennisKind(config);
                    if (kind == .super) {
                        try out.writeByte('[');
                        try writePair(out, self.points, false);
                        try out.writeByte(']');
                    } else {
                        try writePair(out, self.games, false);
                        try out.writeByte(' ');
                        if (kind == .tie) {
                            try writePair(out, self.points, false);
                        } else if (!config.no_ad and self.points[0] >= 3 and self.points[1] >= 3) {
                            const display = if (self.points[0] == self.points[1]) "40-40" else
                                if (self.points[0] > self.points[1]) "AD-40" else "40-AD";
                            try out.writeAll(display);
                        } else {
                            const labels = [_][]const u8{ "0", "15", "30", "40" };
                            try out.print("{s}-{s}", .{
                                labels[@intCast(self.points[0])],
                                labels[@intCast(self.points[1])],
                            });
                        }
                    }
                } else {
                    try writePair(out, self.points, false);
                    if (config.sport == .VOLLEYBALL)
                        try out.print(" server {d}", .{ self.lineup[self.server][0] });
                }
                for (0..2) |side| {
                    if (self.situation(config, side)) |condition|
                        try out.print(" ({s} {s})", .{ condition, config.names[side] });
                }
            }
        }
        try out.writeByte('\n');
    }

    fn stats(self: *const State, config: Config, out: *std.Io.Writer) Error!void {
        const sides: usize = if (config.sport == .BOWLING) 1 else 2;
        for (0..sides) |side| {
            try out.print("{s} {s}: ", .{ config.id, config.names[side] });
            if (config.rally()) {
                try out.print("points {d} serve {d}/{d} run {d}", .{
                    self.rally_points[side],
                    self.serve_wins[side],
                    self.served[side],
                    self.runs[side]
                });
                if (config.sport == .TENNIS)
                    try out.print(" holds {d}/{d} breaks {d} break points {d}/{d}", .{
                        self.holds[side],
                        self.service_games[side],
                        self.breaks[side],
                        self.converted_breaks[side],
                        self.opportunities[side]
                    });
                if (config.sport == .VOLLEYBALL) {
                    try out.print(" subs {d} timeouts {d} lineup ", .{ self.substitutions[side], self.timeouts[side] });
                    for (self.lineup[side], 0..) |number, i| {
                        if (i > 0)
                            try out.writeByte(',');
                        try out.print("{d}", .{ number });
                    }
                }
            } else if (config.sport == .BOWLING) {
                var strikes: i64 = 0;
                var spares: i64 = 0;
                var open: i64 = 0;
                for (0..10) |i| {
                    const marks = self.marks[i][0..self.frame_lengths[i]];
                    strikes += @intCast(std.mem.countScalar(u8, marks, 'X'));
                    spares += @intCast(std.mem.countScalar(u8, marks, '/'));
                    if (self.frame_lengths[i] >= 2 and self.frames[i][0] != 10 and self.frames[i][0] + self.frames[i][1] < 10)
                        open += 1;
                }
                var trial = self.*;
                while (!trial.finished)
                    try trial.roll(trial.standing);
                try out.print("strikes {d} spares {d} open {d} max {d}", .{ strikes, spares, open, trial.finalBowlingScore() });
            } else {
                const average: u64 = @intCast(if (self.dart_count[side] == 0) 0 else @divFloor(self.scored[side] * 300,
                    self.dart_count[side]));
                try out.print("darts {d} average {d}.{d:0>2} busts {d} high {d} tons {d} 180s {d} doubles {d}/{d}",
                    .{
                    self.dart_count[side],
                    average / 100,
                    average % 100,
                    self.busts[side],
                    self.high[side],
                    self.tons[side],
                    self.maximums[side],
                    self.hits[side],
                    self.attempts[side]
                });
            }
            try out.writeByte('\n');
        }
    }

    fn writeResult(self: *const State, config: Config, out: *std.Io.Writer) Error!void {
        if (!self.finished)
            return error.MatchNotFinished;
        if (config.sport == .BOWLING)
            try out.print("{s}: {s} {d}", .{ config.id, config.names[0], self.finalBowlingScore() }) else {
                try out.print("{s}: {s} def. {s}", .{
                    config.id,
                    config.names[self.winner],
                    config.names[1 - self.winner]
                });
                for (self.completed[0..self.completed_len]) |set| {
                    try out.writeByte(' ');
                    try set.write(out, self.winner == 1);
                }
            }
        try out.writeByte('\n');
    }
};

fn writePair(out: *std.Io.Writer, values: [2]i64, reverse: bool) std.Io.Writer.Error!void {
    try out.print("{d}-{d}", .{ values[if (reverse) 1 else 0], values[if (reverse) 0 else 1] });
}

const Match = struct {
    config: Config,
    state: State,
    history: std.ArrayList(Event) = .empty
};

fn oneOf(value: []const u8, choices: []const []const u8) bool {
    for (choices) |choice| {
        if (std.mem.eql(u8, value, choice))
            return true;
    }
    return false;
}

fn configure(gpa: Allocator, a: []const []const u8) Error!Config {
    const sport = std.meta.stringToEnum(Sport, a[2]).?;
    var config = Config{
        .id = a[1],
        .sport = sport,
        .names = .{ a[3], if (sport == .BOWLING) "" else a[4] }
    };
    if (sport == .DARTS)
        config.sets = 1;
    if (sport == .VOLLEYBALL) {
        for (0..2) |side| {
            const lineup = try split(gpa, a[5 + side], ',');
            for (lineup, 0..) |number, i|
                config.lineup[side][i] = integer(number);
        }
    }
    const start: usize = if (sport == .BOWLING) 4 else if (sport == .VOLLEYBALL) 7 else 5;
    var seen = [_]bool{ false } ** 7;
    const keys = [_][]const u8{ "SETS", "DEUCE", "FINAL", "FIRST", "GAMES", "START", "LEGS" };
    for (a[start..]) |option| {
        const parts = try split(gpa, option, '=');
        if (parts.len != 2)
            return error.InvalidOption;
        var key: ?usize = null;
        for (keys, 0..) |name, i| {
            if (std.mem.eql(u8, name, parts[0]))
                key = i;
        }
        const index = key orelse return error.InvalidOption;
        if (seen[index])
            return error.InvalidOption;
        seen[index] = true;
        const value = parts[1];
        switch (index) {
            0 => {
                if (sport == .TENNIS) {
                    if (!oneOf(value, &.{ "3", "5" }))
                        return error.InvalidOption;
                } else if (sport == .DARTS) {
                    if (!oneOf(value, &.{ "1", "2", "3", "4", "5" }))
                        return error.InvalidOption;
                } else return error.InvalidOption;
                config.sets = integer(value);
            },
            1 => {
                if (sport != .TENNIS or !oneOf(value, &.{ "AD", "NOAD" }))
                    return error.InvalidOption;
                config.no_ad = std.mem.eql(u8, value, "NOAD");
            },
            2 => {
                if (sport != .TENNIS)
                    return error.InvalidOption;
                config.final = std.meta.stringToEnum(Final, value) orelse return error.InvalidOption;
            },
            3 => {
                if (sport == .BOWLING or !oneOf(value, &.{ "A", "B" }))
                    return error.InvalidOption;
                config.first = if (std.mem.eql(u8, value, "A")) 0 else 1;
            },
            4 => {
                if (sport != .TABLETENNIS or !oneOf(value, &.{ "5", "7" }))
                    return error.InvalidOption;
                config.table_games = integer(value);
            },
            5 => {
                if (sport != .DARTS or !oneOf(value, &.{ "301", "501", "701" }))
                    return error.InvalidOption;
                config.start = integer(value);
            },
            6 => {
                if (sport != .DARTS or !oneOf(value, &.{ "1", "2", "3", "4", "5" }))
                    return error.InvalidOption;
                config.legs = integer(value);
            },
            else => unreachable,
        }
    }
    return config;
}

const Engine = struct {
    gpa: Allocator,
    darts: DartTable,
    matches: std.StringHashMapUnmanaged(*Match) = .empty,

    fn standings(self: *const Engine, out: *std.Io.Writer) Error!void {
        const Record = struct {
            name: []const u8,
            wins: i64 = 0,
            losses: i64 = 0,

            fn less(_: void, a: @This(), b: @This()) bool {
                return a.wins > b.wins or (a.wins == b.wins and (a.losses < b.losses or
                    (a.losses == b.losses and std.mem.order(u8, a.name, b.name) == .lt)));
            }
        };
        var totals: std.StringHashMapUnmanaged(Record) = .empty;
        var matches = self.matches.valueIterator();
        while (matches.next()) |entry| {
            const match = entry.*;
            if (match.config.sport == .BOWLING or !match.state.finished)
                continue;
            for (0..2) |side| {
                const name = match.config.names[side];
                const record = try totals.getOrPut(self.gpa, name);
                if (!record.found_existing)
                    record.value_ptr.* = .{ .name = name };
                if (side == match.state.winner)
                    record.value_ptr.wins += 1
                else
                    record.value_ptr.losses += 1;
            }
        }
        var records: std.ArrayList(Record) = .empty;
        var values = totals.valueIterator();
        while (values.next()) |record|
            try records.append(self.gpa, record.*);
        std.mem.sort(Record, records.items, {}, Record.less);
        try out.writeAll("standings: ");
        if (records.items.len == 0)
            try out.writeAll("none");
        for (records.items, 0..) |r, i| {
            if (i > 0)
                try out.writeAll(", ");
            try out.print("{s} {d}-{d}", .{ r.name, r.wins, r.losses });
        }
        try out.writeByte('\n');
    }

    fn event(self: *Engine, match: *Match, event_value: Event) Error!void {
        try match.state.apply(match.config, &self.darts, event_value);
        try match.history.append(self.gpa, event_value);
    }

    fn execute(self: *Engine, line: []const u8, out: *std.Io.Writer) Error!void {
        const a = try split(self.gpa, line, ' ');
        const op = a[0];
        if (std.mem.eql(u8, op, "MATCH")) {
            if (self.matches.get(a[1]) != null)
                return error.DuplicateMatch;
            const config = try configure(self.gpa, a);
            const match = try self.gpa.create(Match);
            match.* = .{ .config = config, .state = State.init(config) };
            try self.matches.put(self.gpa, a[1], match);
        } else if (std.mem.eql(u8, op, "CHECKOUT")) {
            const score = integer(a[1]);
            try out.print("checkout {d}: ", .{ score });
            if (self.darts.checkout(score, 3)) |route|
                try self.darts.write(out, route.darts[0..route.len]) else
                    try out.writeAll("none");
            try out.writeByte('\n');
        } else if (std.mem.eql(u8, op, "STANDINGS")) try self.standings(out) else {
            const match = self.matches.get(a[1]) orelse return error.UnknownMatch;
            if (std.mem.eql(u8, op, "UNDO")) {
                if (match.history.items.len == 0)
                    return error.NothingToUndo;
                _ = match.history.pop();
                match.state = State.init(match.config);
                for (match.history.items) |entry|
                    try match.state.apply(match.config, &self.darts, entry);
            } else if (std.mem.eql(u8, op, "SCORE")) try match.state.writeScore(match.config, &self.darts, out) else if (std.mem.eql(u8, op,
                "STATS")) try match.state.stats(match.config, out) else if (std.mem.eql(u8, op, "RESULT")) try match.state.writeResult(match.config,
                out) else {
                const kind = std.meta.stringToEnum(EventKind, op).?;
                const sport = match.config.sport;
                if ((kind == .POINT and !match.config.rally()) or (kind == .ROLL and sport != .BOWLING) or (kind == .THROW
                    and sport != .DARTS) or ((kind == .SUB or kind == .TIMEOUT) and sport != .VOLLEYBALL))
                    return error.WrongEvent;
                if (kind == .POINT) {
                    for (a[2]) |side|
                        try self.event(match, .{ .kind = .POINT, .side = if (side == 'A') 0 else
                            1 });
                } else if (kind == .ROLL or kind == .THROW) {
                    for (a[2..]) |token| {
                        if (match.state.finished)
                            return error.MatchOver;
                        const value: i64 = if (kind == .ROLL) integer(token) else @intCast(self.darts.index(token) orelse return error.InvalidDart);
                        try self.event(match, .{ .kind = kind, .first = value });
                    }
                } else try self.event(match, .{
                    .kind = kind,
                    .side = if (std.mem.eql(u8, a[2], "A")) 0 else 1,
                    .first = if (kind == .SUB) integer(a[3]) else 0,
                    .second = if (kind == .SUB) integer(a[4]) else 0
                });
            }
        }
    }
};

fn reason(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.UnknownMatch => "unknown match",
        error.DuplicateMatch => "duplicate match",
        error.InvalidOption => "invalid option",
        error.WrongEvent => "wrong event",
        error.MatchOver => "match over",
        error.TooManyPins => "too many pins",
        error.InvalidDart => "invalid dart",
        error.PlayerNotOnCourt => "player not on court",
        error.PlayerAlreadyOnCourt => "player already on court",
        error.NoSubstitutionsLeft => "no substitutions left",
        error.NoTimeoutsLeft => "no timeouts left",
        error.NothingToUndo => "nothing to undo",
        error.MatchNotFinished => "match not finished",
        else => null,
    };
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var engine = Engine{ .gpa = gpa, .darts = try DartTable.init(gpa) };
    const count: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..count) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        engine.execute(line, &draft.writer) catch |err| {
            if (reason(err)) |message| {
                try output.interface.print("ERROR {s}\n", .{ message });
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
