const std = @import("std");
const Text = []const u8;
const I = i64;
const Position = [2][26]I;
fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn ix(a: I) usize {
    return @intCast(a);
}
fn color(side: usize) Text {
    return if (side == 0) "W" else "B";
}
fn multiplier(kind: Text) I {
    return if (eq(kind, "backgammon")) 3 else if (eq(kind, "gammon")) 2 else 1;
}
fn parsedNumber(word: Text) ?I {
    if (word.len == 0 or (word.len > 1 and word[0] == '0')) return null;
    for (word) |c| if (!std.ascii.isDigit(c)) return null;
    return std.fmt.parseInt(I, word, 10) catch null;
}
fn inRange(word: Text, low: I, high: I) bool {
    const value = parsedNumber(word) orelse return false;
    return value >= low and value <= high;
}
const Host = struct {
    a: std.mem.Allocator,
    out: *std.Io.Writer,
    fn text(h: Host, comptime f: Text, args: anytype) !Text {
        return std.fmt.allocPrint(h.a, f, args);
    }
    fn line(h: Host, comptime f: Text, args: anytype) !void {
        try h.out.print(f ++ "\n", args);
    }
};
fn positionsEqual(a: Position, b: Position) bool {
    return std.mem.eql(I, &a[0], &b[0]) and std.mem.eql(I, &a[1], &b[1]);
}
fn standardPosition() Position {
    var pos: Position = .{ @splat(0), @splat(0) };
    for (0..2) |side| {
        pos[side][24] = 2;
        pos[side][13] = 5;
        pos[side][8] = 3;
        pos[side][6] = 5;
    }
    return pos;
}
fn pips(pos: Position, side: usize) I {
    var result: I = 0;
    for (1..26) |point| result += @as(I, @intCast(point)) * pos[side][point];
    return result;
}
fn keith(pos: Position, side: usize) I {
    const own = pos[side];
    var result = pips(pos, side) + 2 * @max(own[1] - 1, 0) + @max(own[2] - 1, 0) + @max(own[3] - 3, 0);
    for (4..7) |point| if (own[point] == 0) {
        result += 1;
    };
    return result;
}
fn contact(pos: Position) bool {
    var white: I = 0;
    var black: I = 25;
    for (1..26) |point| {
        if (pos[0][point] > 0) white = @intCast(point);
        if (pos[1][point] > 0) black = 25 - @as(I, @intCast(point));
    }
    return white > black;
}
const Evaluation = struct { value: I, pip_delta: I, blots: I, home: I, prime: I, anchors: I, bar_delta: I };
fn evaluate(pos: Position, side: usize) Evaluation {
    const other = 1 - side;
    const own = pos[side];
    var s: I = 0;
    var h: I = 0;
    var r: I = 0;
    var run: I = 0;
    var anchors_count: I = 0;
    for (1..25) |point| {
        if (own[point] >= 2) {
            run += 1;
            r = @max(r, run);
            if (point <= 6) h += 1;
            if (point >= 19) anchors_count += 1;
        } else run = 0;
        if (own[point] == 1) {
            var distances: [25]bool = @splat(false);
            for (0..point) |q| if (pos[other][25 - q] > 0) {
                distances[point - q] = true;
            };
            for (1..7) |a| for (1..7) |b| {
                if (distances[a] or distances[b] or distances[a + b] or (a == b and (distances[3 * a] or distances[4 * a]))) s += 1;
            };
        }
    }
    const p = pips(pos, other) - pips(pos, side);
    const g = pos[other][25] - own[25];
    return .{ .value = 2 * p - s + 4 * h + 3 * r + 3 * anchors_count + 6 * g, .pip_delta = p, .blots = s, .home = h, .prime = r, .anchors = anchors_count, .bar_delta = g };
}
const Move = struct { source: usize, target: usize };
const Sequence = struct {
    values: [4]Move = undefined,
    len: usize = 0,
    fn add(s: *Sequence, pair: Move) void {
        s.values[s.len] = pair;
        s.len += 1;
    }
    fn erase(s: *Sequence, at: usize) void {
        var j = at;
        while (j + 1 < s.len) : (j += 1) s.values[j] = s.values[j + 1];
        s.len -= 1;
    }
    fn sort(s: *Sequence) void {
        std.mem.sort(Move, s.values[0..s.len], {}, struct {
            fn less(_: void, a: Move, b: Move) bool {
                return a.source > b.source or (a.source == b.source and a.target > b.target);
            }
        }.less);
    }
};
fn canonicalKey(sequence: Sequence, hits: [26]bool) Sequence {
    var result = sequence;
    result.sort();
    while (true) {
        var first: ?usize = null;
        var second: usize = 0;
        for (result.values[0..result.len], 0..) |pair, j| {
            if (pair.target == 0 or hits[pair.target]) continue;
            for (result.values[0..result.len], 0..) |candidate, k| {
                if (candidate.source == pair.target) {
                    first = j;
                    second = k;
                    break;
                }
            }
            if (first != null) break;
        }
        const a = first orelse return result;
        const merged: Move = .{ .source = result.values[a].source, .target = result.values[second].target };
        result.erase(@max(a, second));
        result.erase(@min(a, second));
        result.add(merged);
        result.sort();
    }
}
const Play = struct {
    final_position: Position,
    key: Sequence,
    hits: [26]bool,
    used: usize,
    first_die: usize,
    fn notation(p: Play, h: Host) !Text {
        if (p.key.len == 0) return "none";
        var b: std.Io.Writer.Allocating = .init(h.a);
        var printed_hit: [26]bool = @splat(false);
        var at: usize = 0;
        while (at < p.key.len) {
            const pair = p.key.values[at];
            var count: usize = 1;
            while (at + count < p.key.len and (p.key.values[at + count].source == pair.source and p.key.values[at + count].target == pair.target)) count += 1;
            if (at > 0) try b.writer.writeByte(' ');
            if (pair.source == 25) try b.writer.writeAll("bar") else try b.writer.print("{d}", .{pair.source});
            try b.writer.writeByte('/');
            if (pair.target == 0) try b.writer.writeAll("off") else try b.writer.print("{d}", .{pair.target});
            if (p.hits[pair.target] and !printed_hit[pair.target]) {
                try b.writer.writeByte('*');
                printed_hit[pair.target] = true;
            }
            if (count > 1) try b.writer.print("({d})", .{count});
            at += count;
        }
        return b.toOwnedSlice();
    }
};
fn before(_: void, a: Play, b: Play) bool {
    for (0..@min(a.key.len, b.key.len)) |j| {
        if (a.key.values[j].source != b.key.values[j].source) return a.key.values[j].source > b.key.values[j].source;
        if (a.key.values[j].target != b.key.values[j].target) return a.key.values[j].target > b.key.values[j].target;
    }
    return a.key.len > b.key.len;
}
fn enumeratePlays(a: std.mem.Allocator, pos: Position, side: usize, remaining: [7]usize, sequence: Sequence, hits: [26]bool, first_die: usize, results: *std.ArrayList(Play)) anyerror!void {
    try results.append(a, .{ .final_position = pos, .key = canonicalKey(sequence, hits), .hits = hits, .used = sequence.len, .first_die = first_die });
    const own = pos[side];
    var home_only = true;
    for (7..26) |point| if (own[point] > 0) {
        home_only = false;
    };
    for (1..7) |die| {
        if (remaining[die] == 0) continue;
        var source: usize = 25;
        while (source >= 1) : (source -= 1) {
            if (own[source] == 0 or (own[25] > 0 and source != 25)) continue;
            const signed_target = @as(I, @intCast(source)) - @as(I, @intCast(die));
            var target: usize = 0;
            if (signed_target > 0) {
                target = ix(signed_target);
                if (pos[1 - side][25 - target] >= 2) continue;
            } else {
                if (!home_only) continue;
                var farther = false;
                if (source < 6) for (source + 1..7) |point| {
                    farther = farther or own[point] > 0;
                };
                if (signed_target < 0 and farther) continue;
            }
            var next_pos = pos;
            var next_hits = hits;
            next_pos[side][source] -= 1;
            next_pos[side][target] += 1;
            if (target > 0 and next_pos[1 - side][25 - target] == 1) {
                next_pos[1 - side][25 - target] = 0;
                next_pos[1 - side][25] += 1;
                next_hits[target] = true;
            }
            var next_remaining = remaining;
            next_remaining[die] -= 1;
            var next_sequence = sequence;
            next_sequence.add(.{ .source = source, .target = target });
            try enumeratePlays(a, next_pos, side, next_remaining, next_sequence, next_hits, if (sequence.len == 0) die else first_die, results);
        }
    }
}
const Generated = struct { possible: std.ArrayList(Play), legal: std.ArrayList(Play), maximum_used: usize };
fn generate(a: std.mem.Allocator, pos: Position, side: usize, d1: usize, d2: usize) !Generated {
    var remaining: [7]usize = @splat(0);
    remaining[d1] += if (d1 == d2) 4 else 1;
    if (d1 != d2) remaining[d2] += 1;
    var possible: std.ArrayList(Play) = .empty;
    try enumeratePlays(a, pos, side, remaining, .{}, @splat(false), 0, &possible);
    var maximum_used: usize = 0;
    var larger = false;
    for (possible.items) |play| {
        maximum_used = @max(maximum_used, play.used);
        larger = larger or (play.used == 1 and play.first_die == @max(d1, d2));
    }
    var legal: std.ArrayList(Play) = .empty;
    for (possible.items) |play| {
        if (play.used != maximum_used or (maximum_used == 1 and d1 != d2 and larger and play.first_die != @max(d1, d2))) continue;
        var duplicate = false;
        for (legal.items) |prior| if (positionsEqual(prior.final_position, play.final_position)) {
            duplicate = true;
            break;
        };
        if (!duplicate) try legal.append(a, play);
    }
    std.mem.sort(Play, legal.items, {}, before);
    return .{ .possible = possible, .legal = legal, .maximum_used = maximum_used };
}
fn bestPlay(plays: []const Play, side: usize) usize {
    var chosen: usize = 0;
    var best_value = evaluate(plays[0].final_position, side).value;
    for (plays[1..], 1..) |play, j| {
        const value = evaluate(play.final_position, side).value;
        if (value > best_value) {
            chosen = j;
            best_value = value;
        }
    }
    return chosen;
}
const State = struct {
    pos: Position = standardPosition(),
    side: usize = 0,
    cube: I = 1,
    owner: ?usize = null,
    pending: bool = false,
    over: bool = false,
    score: [2]I = .{ 0, 0 },
    winner: usize = 0,
    kind: Text = "",
    points: I = 0,
    fn ownerText(s: State) Text {
        return if (s.owner) |owner| color(owner) else "center";
    }
    fn cubeDecision(s: State, prohibited: bool) Text {
        if (s.owner == 1 - s.side or s.cube == 64 or prohibited) return "unavailable";
        if (contact(s.pos)) {
            const value = evaluate(s.pos, s.side).value;
            return if (value < 60) "no double" else if (value <= 100) "double take" else "double drop";
        }
        const value = 8 * keith(s.pos, s.side) - 7 * keith(s.pos, 1 - s.side);
        const limit: I = if (s.owner == null) 28 else 21;
        return if (value > limit) "no double" else if (value >= 14) "double take" else "double drop";
    }
    fn finish(s: *State, winning_side: usize, result_kind: Text) void {
        s.over = true;
        s.pending = false;
        s.winner = winning_side;
        s.kind = result_kind;
        s.points = multiplier(result_kind) * s.cube;
        s.score[winning_side] += s.points;
    }
    fn applyPlay(s: *State, play: Play) void {
        s.pos = play.final_position;
        if (s.pos[s.side][0] == 15) {
            const other = 1 - s.side;
            var result_kind: Text = "single";
            if (s.pos[other][0] == 0) {
                result_kind = "gammon";
                var backgammon = s.pos[other][25] > 0;
                for (19..25) |point| backgammon = backgammon or s.pos[other][point] > 0;
                if (backgammon) result_kind = "backgammon";
            }
            s.finish(s.side, result_kind);
        } else s.side = 1 - s.side;
    }
    fn resultLine(s: State, h: Host) !Text {
        return h.text("result {s} {s} {d}", .{ color(s.winner), s.kind, s.points });
    }
};
const Random = struct {
    seed: I,
    fn nextValue(r: *Random) I {
        r.seed = @mod(48271 * r.seed, 2147483647);
        return r.seed;
    }
    fn die(r: *Random) usize {
        return ix(@mod(r.nextValue(), 6) + 1);
    }
};
const GameResult = struct { state_value: State, first_player: usize, turns: usize };
fn simulate(h: Host, start_state: State, strategies: [2]Text, generator: *Random, opening: bool, match_limit: I, match_scores: [2]I, crawford: bool, verbose: bool) !GameResult {
    var current = start_state;
    var d1: usize = 0;
    var d2: usize = 0;
    if (opening) {
        while (d1 == d2) {
            d1 = generator.die();
            d2 = generator.die();
        }
        current.side = if (d1 > d2) 0 else 1;
    }
    const first_player = current.side;
    var turn_number: usize = 1;
    var plays_made: usize = 0;
    while (!current.over) : (turn_number += 1) {
        const side = current.side;
        const other = 1 - side;
        if (!(opening and turn_number == 1)) {
            const prohibited = crawford or (match_limit > 0 and match_scores[side] + current.cube >= match_limit);
            const decision = current.cubeDecision(prohibited);
            if (eq(decision, "double take") or eq(decision, "double drop")) {
                if (verbose) {
                    try h.line("{d} {s} doubles {d}", .{ turn_number, color(side), current.cube * 2 });
                    try h.line("{d} {s} {s}", .{ turn_number, color(other), if (eq(decision, "double take")) @as(Text, "takes") else "drops" });
                }
                if (eq(decision, "double drop")) {
                    current.finish(side, "drop");
                    break;
                }
                current.cube *= 2;
                current.owner = other;
            }
            d1 = generator.die();
            d2 = generator.die();
        }
        var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer scratch.deinit();
        const generated = try generate(scratch.allocator(), current.pos, side, d1, d2);
        const plays = generated.legal.items;
        const strategy = strategies[side];
        const choice = if (eq(strategy, "BEST")) bestPlay(plays, side) else if (eq(strategy, "RANDOM")) ix(@mod(generator.nextValue(), @as(I, @intCast(plays.len)))) else 0;
        if (verbose) try h.line("{d} {s} {d}-{d} {s}", .{ turn_number, color(side), d1, d2, try plays[choice].notation(h) });
        current.applyPlay(plays[choice]);
        plays_made += 1;
    }
    if (verbose) try h.line("{s}", .{try current.resultLine(h)});
    return .{ .state_value = current, .first_player = first_player, .turns = plays_made };
}
fn parsePlay(a: std.mem.Allocator, elements: []const Text) ![]Move {
    if (elements.len == 1 and eq(elements[0], "none")) return &.{};
    var result: std.ArrayList(Move) = .empty;
    for (elements) |original| {
        var element = original;
        var copies: usize = 1;
        if (std.mem.endsWith(u8, element, ")")) {
            const size = element.len;
            if (size < 3 or element[size - 3] != '(' or element[size - 2] < '2' or element[size - 2] > '4') return error.Syntax;
            copies = element[size - 2] - '0';
            element = element[0 .. size - 3];
        }
        if (std.mem.indexOfAny(u8, element, "()") != null) return error.Syntax;
        var parts = std.mem.splitScalar(u8, element, '/');
        const first = parts.next().?;
        const source_value: I = if (eq(first, "bar")) 25 else parsedNumber(first) orelse return error.Syntax;
        if (source_value < 1 or source_value > 25 or (source_value == 25 and !eq(first, "bar"))) return error.Syntax;
        var source = ix(source_value);
        var count_parts: usize = 1;
        while (parts.next()) |original_part| {
            var part = original_part;
            if (std.mem.endsWith(u8, part, "*")) {
                part = part[0 .. part.len - 1];
                if (eq(part, "off")) return error.Syntax;
            }
            const target_value: I = if (eq(part, "off")) 0 else parsedNumber(part) orelse return error.Syntax;
            if (target_value < 0 or target_value > 24 or (target_value == 0 and !eq(part, "off")) or ix(target_value) >= source) return error.Syntax;
            const target = ix(target_value);
            for (0..copies) |_| try result.append(a, .{ .source = source, .target = target });
            source = target;
            count_parts += 1;
        }
        if (count_parts < 2) return error.Syntax;
    }
    return result.toOwnedSlice(a);
}
const Entry = struct { record_text: Text, before_state: State, after_state: State };
const Referee = struct {
    h: Host,
    state_value: State = .{},
    history: std.ArrayList(Entry) = .empty,
    redo_list: std.ArrayList(Entry) = .empty,
    fn makePlay(s: *Referee, play: Play, d1: usize, d2: usize, response: Text) !void {
        const old_state = s.state_value;
        const record_text = try s.h.text("{s} {d}-{d} {s}", .{ color(s.state_value.side), d1, d2, try play.notation(s.h) });
        s.state_value.applyPlay(play);
        try s.history.append(s.h.a, .{ .record_text = record_text, .before_state = old_state, .after_state = s.state_value });
        s.redo_list = .empty;
        try s.h.line("{s}", .{response});
        if (s.state_value.over) try s.h.line("{s}", .{try s.state_value.resultLine(s.h)});
    }
    fn boardRow(s: *const Referee, upper: bool, row: I) !void {
        for (0..12) |j| {
            const point = if (upper) 13 + j else 12 - j;
            if (j == 6) try s.h.out.writeAll(" |");
            var cell = try s.h.text("{d}", .{point});
            if (row > 0) {
                const white = s.state_value.pos[0][point];
                const black = s.state_value.pos[1][25 - point];
                const count_men = @max(white, black);
                cell = if (count_men < row) "." else if (row == 5 and count_men > 5) try s.h.text("{d}", .{count_men}) else if (white > 0) "W" else "B";
            }
            try s.h.out.splatByteAll(' ', 3 - cell.len);
            try s.h.out.writeAll(cell);
        }
        try s.h.out.writeByte('\n');
    }
    fn command(s: *Referee, words: []const Text) !void {
        const op = words[0];
        const no_args = [_]Text{ "NEW", "SHOW", "BOARD", "PIPS", "RACE", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "SCORE", "HISTORY" };
        var known = false;
        var valid = false;
        for (no_args) |candidate| {
            if (eq(candidate, op)) {
                known = true;
                valid = words.len == 1;
            }
        }
        if (eq(op, "POS")) {
            if (words.len != 5 or !inRange(words[2], 0, 15) or !inRange(words[3], 0, 15) or (!eq(words[4], "W") and !eq(words[4], "B"))) return s.h.line("ERROR bad position", .{});
            var next_state: State = .{};
            next_state.pos = .{ @splat(0), @splat(0) };
            next_state.score = s.state_value.score;
            next_state.side = if (eq(words[4], "W")) 0 else 1;
            var totals: [2]I = .{ parsedNumber(words[2]).?, parsedNumber(words[3]).? };
            next_state.pos[0][25] = totals[0];
            next_state.pos[1][25] = totals[1];
            var points = std.mem.splitScalar(u8, words[1], ',');
            var point: usize = 1;
            while (points.next()) |word| : (point += 1) {
                if (point > 24) return s.h.line("ERROR bad position", .{});
                const value = std.fmt.parseInt(I, word, 10) catch return s.h.line("ERROR bad position", .{});
                if (value > 0) {
                    next_state.pos[0][point] = value;
                    totals[0] += value;
                } else if (value < 0) {
                    next_state.pos[1][25 - point] = -value;
                    totals[1] -= value;
                }
            }
            if (point != 25 or totals[0] < 1 or totals[0] > 15 or totals[1] < 1 or totals[1] > 15) return s.h.line("ERROR bad position", .{});
            next_state.pos[0][0] = 15 - totals[0];
            next_state.pos[1][0] = 15 - totals[1];
            s.state_value = next_state;
            s.history = .empty;
            s.redo_list = .empty;
            return s.h.line("OK", .{});
        }
        if (eq(op, "MOVES") or eq(op, "PLAY") or eq(op, "AUTO") or eq(op, "HINT")) {
            known = true;
            valid = if (eq(op, "PLAY")) words.len >= 4 else if (eq(op, "HINT")) words.len == 4 else words.len == 3;
            if (valid) valid = inRange(words[1], 1, 6) and inRange(words[2], 1, 6) and (!eq(op, "HINT") or inRange(words[3], 1, 1000));
        } else if (eq(op, "UNDO") or eq(op, "REDO")) {
            known = true;
            valid = words.len == 2 and inRange(words[1], 1, 1000);
        } else if (eq(op, "RESIGN")) {
            known = true;
            valid = words.len == 2 and (eq(words[1], "single") or eq(words[1], "gammon") or eq(words[1], "backgammon"));
        } else if (eq(op, "GAME")) {
            known = true;
            valid = words.len == 4;
            if (valid) {
                valid = inRange(words[1], 1, 2147483646);
                for (words[2..4]) |strategy| valid = valid and (eq(strategy, "BEST") or eq(strategy, "FIRST") or eq(strategy, "RANDOM"));
            }
        } else if (eq(op, "MATCH") or eq(op, "STATS")) {
            known = true;
            valid = words.len == 3 and inRange(words[1], 1, if (eq(op, "MATCH")) 15 else 50) and inRange(words[2], 1, 2147483646);
        }
        if (!known) return s.h.line("ERROR unknown command", .{});
        if (!valid) return s.h.line("ERROR bad arguments", .{});
        const disallow_over = eq(op, "RACE") or eq(op, "MOVES") or eq(op, "PLAY") or eq(op, "AUTO") or eq(op, "HINT") or eq(op, "EVAL") or eq(op, "SHOTS") or eq(op, "CUBE") or eq(op, "DOUBLE") or eq(op, "TAKE") or eq(op, "DROP") or eq(op, "RESIGN") or eq(op, "GAME");
        if (disallow_over and s.state_value.over) return s.h.line("ERROR game over", .{});
        const disallow_pending = eq(op, "PLAY") or eq(op, "AUTO") or eq(op, "CUBE") or eq(op, "DOUBLE") or eq(op, "RESIGN") or eq(op, "GAME");
        if (disallow_pending and s.state_value.pending) return s.h.line("ERROR double pending", .{});
        const side = s.state_value.side;
        const pos = s.state_value.pos;
        if (eq(op, "NEW")) {
            const old_score = s.state_value.score;
            s.state_value = .{ .score = old_score };
            s.history = .empty;
            s.redo_list = .empty;
            return s.h.line("OK", .{});
        }
        if (eq(op, "SHOW")) {
            try s.h.out.writeAll("POS ");
            for (1..25) |point| {
                if (point > 1) try s.h.out.writeByte(',');
                try s.h.out.print("{d}", .{pos[0][point] - pos[1][25 - point]});
            }
            return s.h.line(" {d} {d} {s}", .{ pos[0][25], pos[1][25], color(side) });
        }
        if (eq(op, "BOARD")) {
            try s.boardRow(true, 0);
            for (1..6) |row| try s.boardRow(true, @intCast(row));
            const status = if (s.state_value.over) "game over" else try s.h.text("{s} {s}", .{ color(side), if (s.state_value.pending) @as(Text, "doubles") else "to move" });
            try s.h.line("bar W{d} B{d} | off W{d} B{d} | cube {d} {s} | {s}", .{ pos[0][25], pos[1][25], pos[0][0], pos[1][0], s.state_value.cube, s.state_value.ownerText(), status });
            var row: I = 5;
            while (row >= 1) : (row -= 1) try s.boardRow(false, row);
            return s.boardRow(false, 0);
        }
        if (eq(op, "PIPS")) return s.h.line("pips W {d} B {d}", .{ pips(pos, 0), pips(pos, 1) });
        if (eq(op, "RACE")) {
            if (contact(pos)) return s.h.line("contact", .{});
            return s.h.line("race W {d} B {d}", .{ keith(pos, 0), keith(pos, 1) });
        }
        if (eq(op, "EVAL")) {
            const ev = evaluate(pos, side);
            return s.h.line("eval {d} pips {d} blots {d} home {d} prime {d} anchors {d} bar {d}", .{ ev.value, ev.pip_delta, ev.blots, ev.home, ev.prime, ev.anchors, ev.bar_delta });
        }
        if (eq(op, "CUBE")) return s.h.line("cube {s}", .{s.state_value.cubeDecision(false)});
        if (eq(op, "SCORE")) return s.h.line("score W {d} B {d}", .{ s.state_value.score[0], s.state_value.score[1] });
        if (eq(op, "HISTORY")) {
            try s.h.line("history {d}", .{s.history.items.len});
            for (s.history.items, 1..) |entry, j| try s.h.line("{d} {s}", .{ j, entry.record_text });
            return;
        }
        if (eq(op, "UNDO") or eq(op, "REDO")) {
            const count = ix(parsedNumber(words[1]).?);
            if (eq(op, "UNDO")) {
                if (count > s.history.items.len) return s.h.line("ERROR cannot undo", .{});
                const at = s.history.items.len - count;
                s.state_value = s.history.items[at].before_state;
                var new_redo: std.ArrayList(Entry) = .empty;
                try new_redo.appendSlice(s.h.a, s.history.items[at..]);
                try new_redo.appendSlice(s.h.a, s.redo_list.items);
                s.redo_list = new_redo;
                s.history.shrinkRetainingCapacity(at);
            } else {
                if (count > s.redo_list.items.len) return s.h.line("ERROR cannot redo", .{});
                s.state_value = s.redo_list.items[count - 1].after_state;
                try s.history.appendSlice(s.h.a, s.redo_list.items[0..count]);
                var new_redo: std.ArrayList(Entry) = .empty;
                try new_redo.appendSlice(s.h.a, s.redo_list.items[count..]);
                s.redo_list = new_redo;
            }
            return s.h.line("OK", .{});
        }
        if (eq(op, "DOUBLE")) {
            if (s.state_value.owner == 1 - side or s.state_value.cube == 64) return s.h.line("ERROR cube unavailable", .{});
            s.state_value.pending = true;
            s.redo_list = .empty;
            return s.h.line("OK double {d}", .{s.state_value.cube * 2});
        }
        if (eq(op, "TAKE") or eq(op, "DROP")) {
            if (!s.state_value.pending) return s.h.line("ERROR no double", .{});
            s.state_value.pending = false;
            s.redo_list = .empty;
            if (eq(op, "TAKE")) {
                s.state_value.cube *= 2;
                s.state_value.owner = 1 - side;
                return s.h.line("OK take {d} {s}", .{ s.state_value.cube, s.state_value.ownerText() });
            }
            s.state_value.finish(side, "drop");
            try s.h.line("OK drop", .{});
            return s.h.line("{s}", .{try s.state_value.resultLine(s.h)});
        }
        if (eq(op, "RESIGN")) {
            s.state_value.finish(1 - side, words[1]);
            s.redo_list = .empty;
            try s.h.line("OK resign", .{});
            return s.h.line("{s}", .{try s.state_value.resultLine(s.h)});
        }
        if (eq(op, "GAME")) {
            var generator: Random = .{ .seed = parsedNumber(words[1]).? };
            _ = try simulate(s.h, s.state_value, .{ words[2], words[3] }, &generator, false, 0, .{ 0, 0 }, false, true);
            return;
        }
        if (eq(op, "MATCH") or eq(op, "STATS")) {
            const count = parsedNumber(words[1]).?;
            var generator: Random = .{ .seed = parsedNumber(words[2]).? };
            var scores: [2]I = .{ 0, 0 };
            var wins: [4][2]usize = .{ @splat(0), @splat(0), @splat(0), @splat(0) };
            const kinds = [_]Text{ "single", "gammon", "backgammon", "drop" };
            var total_turns: usize = 0;
            var game_number: I = 0;
            var crawford_used = false;
            while ((eq(op, "STATS") and game_number < count) or (eq(op, "MATCH") and @max(scores[0], scores[1]) < count)) {
                const crawford = eq(op, "MATCH") and !crawford_used and @max(scores[0], scores[1]) == count - 1;
                crawford_used = crawford_used or crawford;
                const result = try simulate(s.h, .{}, .{ "BEST", "BEST" }, &generator, true, if (eq(op, "MATCH")) count else 0, scores, crawford, false);
                const ended = result.state_value;
                scores[ended.winner] += ended.points;
                total_turns += result.turns;
                game_number += 1;
                for (kinds, 0..) |kind, j| if (eq(kind, ended.kind)) {
                    wins[j][ended.winner] += 1;
                };
                if (eq(op, "MATCH")) try s.h.line("game {d}{s} start {s} turns {d} {s} score {d}-{d}", .{ game_number, if (crawford) @as(Text, " crawford") else "", color(result.first_player), result.turns, try ended.resultLine(s.h), scores[0], scores[1] });
            }
            if (eq(op, "MATCH")) return s.h.line("match {s} {d}-{d}", .{ color(if (scores[0] >= count) 0 else 1), scores[0], scores[1] });
            for (kinds, wins) |kind, counts| try s.h.line("{s} W {d} B {d}", .{ kind, counts[0], counts[1] });
            try s.h.line("points W {d} B {d}", .{ scores[0], scores[1] });
            return s.h.line("turns {d}", .{total_turns});
        }
        if (eq(op, "SHOTS")) {
            var counts: [26]I = @splat(0);
            var total: I = 0;
            var rolls: std.Io.Writer.Allocating = .init(s.h.a);
            var a: usize = 6;
            while (a >= 1) : (a -= 1) {
                var b = a;
                while (b >= 1) : (b -= 1) {
                    var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
                    defer scratch.deinit();
                    const generated = try generate(scratch.allocator(), pos, 1 - side, a, b);
                    var hit_points: [26]bool = @splat(false);
                    for (generated.legal.items) |play| for (1..25) |point| {
                        if (play.hits[point]) hit_points[25 - point] = true;
                    };
                    var any_hit = false;
                    const weight: I = if (a == b) 1 else 2;
                    for (1..25) |point| {
                        if (pos[side][point] == 1 and hit_points[point]) {
                            counts[point] += weight;
                            any_hit = true;
                        }
                    }
                    if (any_hit) {
                        total += weight;
                        try rolls.writer.print(" {d}-{d}", .{ a, b });
                    }
                }
            }
            try s.h.line("shots {d}/36{s}", .{ total, rolls.written() });
            var point: usize = 24;
            while (point >= 1) : (point -= 1) if (pos[side][point] == 1) {
                try s.h.line("blot {d} {d}/36", .{ point, counts[point] });
            };
            return;
        }
        const d1 = ix(parsedNumber(words[1]).?);
        const d2 = ix(parsedNumber(words[2]).?);
        var scratch: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer scratch.deinit();
        const generated = try generate(scratch.allocator(), pos, side, d1, d2);
        if (eq(op, "MOVES")) {
            for (generated.legal.items) |play| try s.h.line("{s}", .{try play.notation(s.h)});
            return s.h.line("total {d}", .{generated.legal.items.len});
        }
        if (eq(op, "HINT")) {
            const ranked = generated.legal.items;
            var j: usize = 1;
            while (j < ranked.len) : (j += 1) {
                var k = j;
                while (k > 0 and evaluate(ranked[k].final_position, side).value > evaluate(ranked[k - 1].final_position, side).value) : (k -= 1) std.mem.swap(Play, &ranked[k], &ranked[k - 1]);
            }
            for (ranked[0..@min(ix(parsedNumber(words[3]).?), ranked.len)]) |play| try s.h.line("{d} {s}", .{ evaluate(play.final_position, side).value, try play.notation(s.h) });
            return;
        }
        if (eq(op, "AUTO")) {
            const chosen = generated.legal.items[bestPlay(generated.legal.items, side)];
            return s.makePlay(chosen, d1, d2, try s.h.text("OK {s} eval {d}", .{ try chosen.notation(s.h), evaluate(chosen.final_position, side).value }));
        }
        const moves = parsePlay(scratch.allocator(), words[3..]) catch |err| {
            if (err == error.Syntax) return s.h.line("ILLEGAL syntax", .{});
            return err;
        };
        var final_position = pos;
        var destinations: [26]bool = @splat(false);
        var nonbar = false;
        var bearing = false;
        var blocked = false;
        for (moves) |pair| {
            final_position[side][pair.source] -= 1;
            final_position[side][pair.target] += 1;
            destinations[pair.target] = true;
            nonbar = nonbar or pair.source != 25;
            bearing = bearing or pair.target == 0;
            blocked = blocked or (pair.target > 0 and pos[1 - side][25 - pair.target] >= 2);
        }
        for (1..25) |point| if (destinations[point] and pos[1 - side][25 - point] == 1) {
            final_position[1 - side][25 - point] = 0;
            final_position[1 - side][25] += 1;
        };
        for (1..26) |point| if (final_position[side][point] < 0) return s.h.line("ILLEGAL no checker", .{});
        if (final_position[side][25] > 0 and nonbar) return s.h.line("ILLEGAL bar", .{});
        if (blocked) return s.h.line("ILLEGAL blocked", .{});
        if (bearing) for (7..26) |point| {
            if (final_position[side][point] > 0) return s.h.line("ILLEGAL bear-off", .{});
        };
        for (generated.legal.items) |play| if (positionsEqual(play.final_position, final_position)) {
            return s.makePlay(play, d1, d2, try s.h.text("OK {s}", .{try play.notation(s.h)}));
        };
        var possible = false;
        var too_few = false;
        for (generated.possible.items) |play| if (positionsEqual(play.final_position, final_position)) {
            possible = true;
            too_few = too_few or play.used < generated.maximum_used;
        };
        return s.h.line("ILLEGAL {s}", .{if (too_few) @as(Text, "too few dice") else if (possible) "larger die required" else "impossible"});
    }
};
fn readLine(r: *std.Io.Reader, a: std.mem.Allocator) !?Text {
    var b: std.Io.Writer.Allocating = .init(a);
    defer b.deinit();
    _ = try r.streamDelimiterEnding(&b.writer, '\n');
    if (r.bufferedLen() == 0 and b.written().len == 0) return null;
    if (r.bufferedLen() > 0) r.toss(1);
    return b.toOwnedSlice();
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var referee: Referee = .{ .h = .{ .a = a, .out = &output.interface } };
    const count = parsedNumber(std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r")).?;
    for (0..ix(count)) |_| {
        const line = std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r");
        var words: std.ArrayList(Text) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |word| try words.append(a, word);
        try referee.command(words.items);
        try output.interface.flush();
    }
    try output.interface.flush();
}
