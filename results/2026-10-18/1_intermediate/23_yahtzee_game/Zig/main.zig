const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const Dice = [5]u8;
const Counts = [6]u8;
const Mask = u5;
const Category = enum { ONES, TWOS, THREES, FOURS, FIVES, SIXES, THREEKIND, FOURKIND, FULLHOUSE, SMALL, LARGE, YAHTZEE, CHANCE };
const Strategy = enum { KIND, STRAIGHT, HIGH, UPPER };
const Joker = enum { FORCED, FREE, OFF };
const Rules = struct { rolls: usize = 3, joker: Joker = .FORCED };
const categories = [_]Category{ .ONES, .TWOS, .THREES, .FOURS, .FIVES, .SIXES, .THREEKIND, .FOURKIND, .FULLHOUSE, .SMALL, .LARGE, .YAHTZEE, .CHANCE };
const powers = [_]usize{ 1, 6, 36, 216, 1296, 7776 };
const lower_mask: u13 = 0x1fc0;

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn dieBit(die: usize) Mask { return @as(Mask, 1) << @intCast(4 - die); }
fn held(mask: Mask, die: usize) bool { return mask & dieBit(die) != 0; }
fn categoryBit(category: usize) u13 { return @as(u13, 1) << @intCast(category); }
fn countsOf(dice: Dice) Counts {
    var result: Counts = @splat(0);
    for (dice) |face| result[face - 1] += 1;
    return result;
}
fn decode(code: usize) Counts {
    var value = code;
    var result: Counts = undefined;
    for (&result) |*count| { count.* = @intCast(value % 6); value /= 6; }
    return result;
}
fn heldCode(dice: Dice, mask: Mask) usize {
    var result: usize = 0;
    for (dice, 0..) |face, i| if (held(mask, i)) { result += powers[face - 1]; };
    return result;
}
fn mostFrequent(counts: Counts) usize {
    var best: usize = 0;
    for (1..6) |i| if (counts[i] >= counts[best]) { best = i; };
    return best;
}
fn yahtzee(counts: Counts) bool {
    for (counts) |count| if (count == 5) return true;
    return false;
}
fn normalScore(category: Category, counts: Counts) i32 {
    const c: usize = @intFromEnum(category);
    if (c < 6) return @intCast((c + 1) * counts[c]);
    var total: i32 = 0;
    var largest: u8 = 0;
    var bits: u6 = 0;
    var pair = false;
    var triple = false;
    for (counts, 0..) |count, i| {
        total += @as(i32, @intCast(i + 1)) * count;
        largest = @max(largest, count);
        if (count > 0) bits |= @as(u6, 1) << @intCast(i);
        pair = pair or count == 2;
        triple = triple or count == 3;
    }
    return switch (category) {
        .THREEKIND => if (largest >= 3) total else 0,
        .FOURKIND => if (largest >= 4) total else 0,
        .FULLHOUSE => if (pair and triple) 25 else 0,
        .SMALL => if (bits & 15 == 15 or bits & 30 == 30 or bits & 60 == 60) 30 else 0,
        .LARGE => if (bits == 31 or bits == 62) 40 else 0,
        .YAHTZEE => if (largest == 5) 50 else 0,
        else => total,
    };
}

const Player = struct {
    name: []const u8,
    strategy: Strategy = .KIND,
    scores: [13]?i32 = @splat(null),
    yahtzee_bonus: i32 = 0,
    fn upper(player: Player) i32 {
        var result: i32 = 0;
        for (player.scores[0..6]) |score| result += score orelse 0;
        return result;
    }
    fn upperBonus(player: Player) i32 { return if (player.upper() >= 63) 35 else 0; }
    fn total(player: Player) i32 {
        var result = player.upperBonus() + player.yahtzee_bonus;
        for (player.scores) |score| result += score orelse 0;
        return result;
    }
    fn round(player: Player) usize {
        var result: usize = 1;
        for (player.scores) |score| if (score != null) { result += 1; };
        return result;
    }
};

const Candidates = struct {
    points: [13]i32 = @splat(-1),
    allowed: u13 = 0,
    joker: bool = false,
    best: Category = .ONES,
};
fn evaluate(player: *const Player, counts: Counts, rule: Joker) Candidates {
    var result: Candidates = .{};
    for (player.scores, 0..) |score, i| if (score == null) { result.allowed |= categoryBit(i); };
    result.joker = rule != .OFF and yahtzee(counts) and player.scores[11] != null;
    if (result.joker and rule == .FORCED) {
        const upper = mostFrequent(counts);
        if (result.allowed & categoryBit(upper) != 0) result.allowed = categoryBit(upper)
        else if (result.allowed & lower_mask != 0) result.allowed &= lower_mask;
    }
    var best_score: i32 = -1;
    for (categories, 0..) |category, i| {
        if (player.scores[i] != null) continue;
        result.points[i] = if (result.allowed & categoryBit(i) == 0) 0 else if (result.joker) switch (category) {
            .FULLHOUSE => 25, .SMALL => 30, .LARGE => 40, else => normalScore(category, counts),
        } else normalScore(category, counts);
        if (result.points[i] > best_score) { best_score = result.points[i]; result.best = category; }
    }
    return result;
}

const Pattern = struct {
    mask: Mask,
    pub fn format(value: Pattern, out: *std.Io.Writer) std.Io.Writer.Error!void {
        var text: [5]u8 = undefined;
        for (&text, 0..) |*c, i| c.* = if (held(value.mask, i)) '1' else '0';
        try out.writeAll(&text);
    }
};
const Faces = struct {
    dice: ?Dice,
    mask: Mask = 31,
    pub fn format(value: Faces, out: *std.Io.Writer) std.Io.Writer.Error!void {
        var first = true;
        if (value.dice) |dice| for (dice, 0..) |face, i| {
            if (!held(value.mask, i)) continue;
            if (!first) try out.writeByte(' ');
            try out.print("{d}", .{face});
            first = false;
        };
        if (first) try out.writeByte('-');
    }
};
const Fraction = struct {
    numerator: i64,
    denominator: i64,
    pub fn format(value: Fraction, out: *std.Io.Writer) std.Io.Writer.Error!void {
        var a = value.numerator;
        var b = value.denominator;
        while (b != 0) { const remainder = @mod(a, b); a = b; b = remainder; }
        const numerator = @divExact(value.numerator, a);
        const denominator = @divExact(value.denominator, a);
        try out.print("{d}", .{numerator});
        if (denominator != 1) try out.print("/{d}", .{denominator});
    }
};
const Average = struct {
    sum: i64,
    count: usize,
    pub fn format(value: Average, out: *std.Io.Writer) std.Io.Writer.Error!void {
        const hundredths = if (value.count == 0) 0 else @divTrunc(100 * value.sum, @as(i64, @intCast(value.count)));
        try out.print("{d}.{d:0>2}", .{ @divTrunc(hundredths, 100), @mod(hundredths, 100) });
    }
};
fn pattern(mask: Mask) Pattern { return .{ .mask = mask }; }
fn faces(dice: ?Dice, mask: Mask) Faces { return .{ .dice = dice, .mask = mask }; }
fn fraction(numerator: i64, denominator: i64) Fraction { return .{ .numerator = numerator, .denominator = denominator }; }
fn average(sum: i64, count: usize) Average { return .{ .sum = sum, .count = count }; }

const Outcome = struct { code: usize, weight: i64 };
const Outcomes = struct {
    items: [6]std.ArrayList(Outcome) = @splat(.empty),
    fn init(result: *Outcomes, gpa: Allocator) Allocator.Error!void {
        for (0..6) |size| try result.add(gpa, 0, size, size, 0, 1);
    }
    fn add(result: *Outcomes, gpa: Allocator, face: usize, remaining: usize, size: usize, code: usize, divisor: i64) Allocator.Error!void {
        const factorial = [_]i64{ 1, 1, 2, 6, 24, 120 };
        if (face == 6) {
            if (remaining == 0) try result.items[size].append(gpa, .{ .code = code, .weight = @divExact(factorial[size], divisor) });
            return;
        }
        for (0..remaining + 1) |count| try result.add(gpa, face + 1, remaining - count, size, code + count * powers[face], divisor * factorial[count]);
    }
};
const Adviser = struct {
    gpa: Allocator,
    player: *const Player,
    joker: Joker,
    outcomes: *const Outcomes,
    values: std.AutoHashMapUnmanaged(usize, i64) = .empty,
    expectations: std.AutoHashMapUnmanaged(usize, i64) = .empty,
    fn value(adviser: *Adviser, code: usize, depth: usize) Allocator.Error!i64 {
        const key = depth * 46656 + code;
        if (adviser.values.get(key)) |cached| return cached;
        const counts = decode(code);
        const best: i64 = if (depth == 0) blk: {
            const scores = evaluate(adviser.player, counts, adviser.joker);
            break :blk scores.points[@intFromEnum(scores.best)];
        } else try adviser.choose(counts, depth, 0, 0);
        try adviser.values.put(adviser.gpa, key, best);
        return best;
    }
    fn choose(adviser: *Adviser, counts: Counts, depth: usize, face: usize, kept: usize) Allocator.Error!i64 {
        if (face == 6) return adviser.expected(kept, depth);
        var best: i64 = -1;
        for (0..@as(usize, counts[face]) + 1) |count| best = @max(best, try adviser.choose(counts, depth, face + 1, kept + count * powers[face]));
        return best;
    }
    fn expected(adviser: *Adviser, kept: usize, depth: usize) Allocator.Error!i64 {
        const key = depth * 46656 + kept;
        if (adviser.expectations.get(key)) |cached| return cached;
        var rerolled: usize = 5;
        for (decode(kept)) |count| rerolled -= count;
        var sum: i64 = 0;
        for (adviser.outcomes.items[rerolled].items) |outcome| sum += outcome.weight * (try adviser.value(kept + outcome.code, depth - 1));
        const result = sum * @as(i64, @intCast(powers[5 - rerolled]));
        try adviser.expectations.put(adviser.gpa, key, result);
        return result;
    }
};

const Turn = struct { seat: usize = 0, rolls: usize = 0, dice: Dice = @splat(0), hold: Mask = 0 };
const ScoreEntry = struct { before: Turn, category: Category, points: i32, bonus: i32, joker: bool };
const RedoEntry = struct { after: ?Turn, entry: ScoreEntry };
const Game = struct {
    program: *Program,
    rules: Rules,
    random_state: i64,
    quiet: bool = false,
    players: [6]Player = undefined,
    player_count: usize,
    loaded: std.ArrayList(u8) = .empty,
    loaded_head: usize = 0,
    face_totals: [6]i64 = @splat(0),
    turn: ?Turn = .{},
    entries: [78]ScoreEntry = undefined,
    entry_count: usize = 0,
    redo_entries: [78]RedoEntry = undefined,
    redo_count: usize = 0,
    fn init(program: *Program, seed: i64, names: []const []const u8) Game {
        var result: Game = .{ .program = program, .rules = program.rules, .random_state = seed, .player_count = names.len };
        for (names, 0..) |name, i| result.players[i] = .{ .name = name };
        return result;
    }
    fn emit(game: *Game, comptime fmt: []const u8, args: anytype) Error!void {
        if (!game.quiet) try game.program.emit(fmt, args);
    }
    fn current(game: *Game) *Player { return &game.players[game.turn.?.seat]; }
    fn checkTurn(game: *Game) Error!void {
        if (game.turn == null) return game.program.fail("game over", .{});
    }
    fn checkRolled(game: *Game) Error!void {
        try game.checkTurn();
        if (game.turn.?.rolls == 0) return game.program.fail("not rolled", .{});
    }
    fn checkRollsLeft(game: *Game) Error!void {
        try game.checkRolled();
        if (game.turn.?.rolls == game.rules.rolls) return game.program.fail("no rolls left", .{});
    }
    fn roll(game: *Game) Error!void {
        try game.checkTurn();
        var turn = game.turn.?;
        if (turn.rolls == game.rules.rolls) return game.program.fail("no rolls left", .{});
        if (turn.hold == 31) return game.program.fail("all dice held", .{});
        game.redo_count = 0;
        for (&turn.dice, 0..) |*face, i| {
            if (turn.rolls > 0 and held(turn.hold, i)) continue;
            if (game.loaded_head < game.loaded.items.len) {
                face.* = game.loaded.items[game.loaded_head];
                game.loaded_head += 1;
            } else {
                game.random_state = @mod(48271 * game.random_state, 2147483647);
                face.* = @intCast(@mod(game.random_state, 6) + 1);
            }
            game.face_totals[face.* - 1] += 1;
        }
        turn.rolls += 1;
        game.turn = turn;
        try game.emit("{s} roll {d}: {f}", .{ game.current().name, turn.rolls, faces(turn.dice, 31) });
    }
    fn hold(game: *Game, mask: Mask) Error!void {
        try game.checkRollsLeft();
        game.redo_count = 0;
        game.turn.?.hold = mask;
        try game.emit("{s} holds {f}: {f}", .{ game.current().name, pattern(mask), faces(game.turn.?.dice, mask) });
    }
    fn keep(game: *Game, values: []const u8) Error!void {
        try game.checkRollsLeft();
        var mask: Mask = 0;
        for (values) |value| {
            var selected: ?usize = null;
            for (game.turn.?.dice, 0..) |face, i| if (!held(mask, i) and face == value) { selected = i; break; };
            const die = selected orelse return game.program.fail("not showing {d}", .{value});
            mask |= dieBit(die);
        }
        try game.hold(mask);
    }
    fn score(game: *Game, category: Category, preview: bool) Error!void {
        try game.checkRolled();
        const player = game.current();
        const c = @intFromEnum(category);
        if (player.scores[c] != null) return game.program.fail("{s} already used", .{@tagName(category)});
        const counts = countsOf(game.turn.?.dice);
        const scores = evaluate(player, counts, game.rules.joker);
        if (scores.allowed & categoryBit(c) == 0) {
            const upper = mostFrequent(counts);
            return game.program.fail("joker requires {s}", .{if (player.scores[upper] == null) @tagName(categories[upper]) else "lower box"});
        }
        const points = scores.points[c];
        const bonus: i32 = if (yahtzee(counts) and (player.scores[11] orelse 0) == 50) 100 else 0;
        const upper_bonus: i32 = if (c < 6 and player.upper() < 63 and player.upper() + points >= 63) 35 else 0;
        const total = player.total() + points + bonus + upper_bonus;
        const entry: ScoreEntry = .{ .before = game.turn.?, .category = category, .points = points, .bonus = bonus, .joker = scores.joker };
        if (!preview) {
            game.redo_count = 0;
            game.entries[game.entry_count] = entry;
            game.entry_count += 1;
            player.scores[c] = points;
            player.yahtzee_bonus += bonus;
            game.turn = if (game.entry_count == 13 * game.player_count) null else .{ .seat = (entry.before.seat + 1) % game.player_count };
        }
        try game.emit("{s} {s} {d} in {s}{s}{s}{s} total {d}", .{
            player.name, if (preview) "would score" else "scores", points, @tagName(category),
            if (scores.joker) " joker" else "", if (bonus != 0) " ybonus 100" else "", if (upper_bonus != 0) " ubonus 35" else "", total,
        });
        if (!preview) {
            if (game.turn == null) try game.emit("game over", .{})
            else try game.emit("turn {d} {s}", .{ game.current().round(), game.current().name });
        }
    }
    fn undo(game: *Game) Error!void {
        if (game.entry_count == 0) return game.program.fail("nothing to undo", .{});
        game.entry_count -= 1;
        const entry = game.entries[game.entry_count];
        game.redo_entries[game.redo_count] = .{ .after = game.turn, .entry = entry };
        game.redo_count += 1;
        const player = &game.players[entry.before.seat];
        player.scores[@intFromEnum(entry.category)] = null;
        player.yahtzee_bonus -= entry.bonus;
        game.turn = entry.before;
        try game.emit("undo {s} {s} {d}", .{ player.name, @tagName(entry.category), entry.points });
    }
    fn redo(game: *Game) Error!void {
        if (game.redo_count == 0) return game.program.fail("nothing to redo", .{});
        game.redo_count -= 1;
        const saved = game.redo_entries[game.redo_count];
        const entry = saved.entry;
        const player = &game.players[entry.before.seat];
        player.scores[@intFromEnum(entry.category)] = entry.points;
        player.yahtzee_bonus += entry.bonus;
        game.entries[game.entry_count] = entry;
        game.entry_count += 1;
        game.turn = saved.after;
        try game.emit("redo {s} {s} {d}", .{ player.name, @tagName(entry.category), entry.points });
    }
    fn botHold(game: *Game, strategy: Strategy) Mask {
        const dice = game.turn.?.dice;
        const counts = countsOf(dice);
        var mask: Mask = 0;
        if (strategy == .STRAIGHT) {
            var best_start: usize = 0;
            var best_length: usize = 0;
            for (0..6) |start| {
                var end = start;
                while (end < 6 and counts[end] > 0) : (end += 1) {}
                if (end - start >= best_length) { best_start = start; best_length = end - start; }
            }
            if (best_length >= 3) {
                for (best_start + 1..best_start + best_length + 1) |value| {
                    for (dice, 0..) |face, i| if (face == value) { mask |= dieBit(i); break; };
                }
                return mask;
            }
        }
        const frequent = mostFrequent(counts) + 1;
        for (dice, 0..) |face, i| if (if (strategy == .HIGH) face >= 5 else face == frequent) { mask |= dieBit(i); };
        return mask;
    }
    fn botTurn(game: *Game) Error!void {
        const strategy = game.current().strategy;
        if (game.turn.?.rolls == 0) try game.roll();
        while (game.turn.?.rolls < game.rules.rolls) {
            const mask = game.botHold(strategy);
            if (mask == 31) break;
            try game.hold(mask);
            try game.roll();
        }
        const counts = countsOf(game.turn.?.dice);
        const scores = evaluate(game.current(), counts, game.rules.joker);
        const frequent = mostFrequent(counts);
        const category = if (strategy == .UPPER and counts[frequent] >= 3 and scores.allowed & categoryBit(frequent) != 0) categories[frequent] else scores.best;
        try game.score(category, false);
    }
    fn ranking(game: *const Game) [6]usize {
        var result: [6]usize = undefined;
        for (0..game.player_count) |i| result[i] = i;
        std.mem.sort(usize, result[0..game.player_count], game, struct {
            fn before(table: *const Game, a: usize, b: usize) bool {
                const first = table.players[a].total();
                const second = table.players[b].total();
                return if (first != second) first > second else a < b;
            }
        }.before);
        return result;
    }
};

const Record = struct { games: usize = 0, wins: usize = 0, best: i32 = 0, sum: i64 = 0 };
const SimulationTotal = struct { wins: usize = 0, sum: i64 = 0, best: i32 = 0, bonus: usize = 0, yahtzee: usize = 0 };
const Program = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    rules: Rules = .{},
    game: ?*Game = null,
    records: std.StringHashMapUnmanaged(Record) = .empty,
    outcomes: Outcomes = .{},
    fn fail(program: *Program, comptime fmt: []const u8, args: anytype) Error {
        program.error_message = try std.fmt.allocPrint(program.gpa, fmt, args);
        return error.BadCommand;
    }
    fn emit(program: *Program, comptime fmt: []const u8, args: anytype) Error!void { try program.out.print(fmt ++ "\n", args); }
    fn table(program: *Program) Error!*Game { return program.game orelse return program.fail("no game", .{}); }
    fn positive(program: *Program, word: []const u8, maximum: i64) Error!i64 {
        if (word[0] < '1' or word[0] > '9') return program.fail("bad value {s}", .{word});
        for (word) |c| if (c < '0' or c > '9') return program.fail("bad value {s}", .{word});
        const value = std.fmt.parseInt(i64, word, 10) catch unreachable;
        if (value > maximum) return program.fail("bad value {s}", .{word});
        return value;
    }
    fn checkName(program: *Program, word: []const u8) Error!void {
        if (word.len > 8) return program.fail("bad name {s}", .{word});
        for (word) |c| if (c < 'A' or c > 'Z') return program.fail("bad name {s}", .{word});
    }
    fn parsePattern(program: *Program, word: []const u8) Error!Mask {
        if (word.len != 5) return program.fail("bad pattern {s}", .{word});
        for (word) |c| if (c != '0' and c != '1') return program.fail("bad pattern {s}", .{word});
        return std.fmt.parseInt(Mask, word, 2) catch unreachable;
    }
    fn parseCategory(program: *Program, word: []const u8) Error!Category {
        return std.meta.stringToEnum(Category, word) orelse return program.fail("bad category {s}", .{word});
    }
    fn parseStrategy(program: *Program, word: []const u8) Error!Strategy {
        return std.meta.stringToEnum(Strategy, word) orelse return program.fail("bad strategy {s}", .{word});
    }
    fn odds(program: *Program, game: *Game, mask: Mask) Error!void {
        try game.checkRollsLeft();
        const kept = heldCode(game.turn.?.dice, mask);
        var rerolled: usize = 5;
        for (decode(kept)) |count| rerolled -= count;
        const outcome_count: i64 = @intCast(powers[rerolled]);
        var sums: [13]i64 = @splat(0);
        var chances: [13]i64 = @splat(0);
        var best: i64 = 0;
        for (program.outcomes.items[rerolled].items) |outcome| {
            const scores = evaluate(game.current(), decode(kept + outcome.code), game.rules.joker);
            for (scores.points, 0..) |points, i| {
                if (points < 0) continue;
                sums[i] += outcome.weight * points;
                if (points > 0) chances[i] += outcome.weight;
            }
            best += outcome.weight * scores.points[@intFromEnum(scores.best)];
        }
        try program.emit("odds {f} outcomes {d}", .{ pattern(mask), outcome_count });
        for (categories, 0..) |c, i| if (game.current().scores[i] == null) {
            try program.emit("{s} expect {f} chance {f}", .{ @tagName(c), fraction(sums[i], outcome_count), fraction(chances[i], outcome_count) });
        };
        try program.emit("best expect {f}", .{fraction(best, outcome_count)});
    }
    fn advise(program: *Program, game: *Game) Error!void {
        try game.checkRollsLeft();
        const turn = game.turn.?;
        const depth = game.rules.rolls - turn.rolls;
        var temporary = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer temporary.deinit();
        var adviser: Adviser = .{ .gpa = temporary.allocator(), .player = game.current(), .joker = game.rules.joker, .outcomes = &program.outcomes };
        var best: i64 = -1;
        var chosen: Mask = 0;
        var denominator: i64 = 1;
        for (0..depth) |_| denominator *= 7776;
        for (0..32) |i| {
            const mask: Mask = @intCast(i);
            const value = try adviser.expected(heldCode(turn.dice, mask), depth);
            if (value > best) { best = value; chosen = mask; }
        }
        try program.emit("advise {f}: {f} expect {f}", .{ pattern(chosen), faces(turn.dice, chosen), fraction(best, denominator) });
    }
    fn card(program: *Program, game: *Game) Error!void {
        const totals = [_][]const u8{ "UPPER", "BONUS", "YBONUS", "TOTAL" };
        for (0..18) |row| {
            const heading = if (row == 0) "CATEGORY" else if (row <= 13) @tagName(categories[row - 1]) else totals[row - 14];
            try program.out.writeAll(heading);
            try program.out.splatByteAll(' ', 9 - heading.len);
            for (game.players[0..game.player_count]) |player| {
                var buffer: [32]u8 = undefined;
                const cell = if (row == 0) player.name else blk: {
                    const value: ?i32 = if (row <= 13) player.scores[row - 1] else switch (row) {
                        14 => player.upper(), 15 => player.upperBonus(), 16 => player.yahtzee_bonus, else => player.total(),
                    };
                    break :blk if (value) |number| std.fmt.bufPrint(&buffer, "{d}", .{number}) catch unreachable else "-";
                };
                const width = @max(@as(usize, 4), player.name.len);
                try program.out.splatByteAll(' ', 1 + width - @min(width, cell.len));
                try program.out.writeAll(cell);
            }
            try program.out.writeByte('\n');
        }
    }
    fn simulate(program: *Program, seed: i64, count: usize, strategies: []const Strategy) Error!void {
        var totals: [6]SimulationTotal = @splat(.{});
        const names = [_][]const u8{ "A", "B", "C", "D", "E", "F" };
        var state = seed;
        for (0..count) |_| {
            var simulation = Game.init(program, state, names[0..strategies.len]);
            simulation.quiet = true;
            for (strategies, 0..) |bot, i| simulation.players[i].strategy = bot;
            while (simulation.turn != null) try simulation.botTurn();
            state = simulation.random_state;
            const order = simulation.ranking();
            totals[order[0]].wins += 1;
            for (simulation.players[0..strategies.len], 0..) |player, i| {
                totals[i].sum += player.total();
                totals[i].best = @max(totals[i].best, player.total());
                if (player.upperBonus() == 35) totals[i].bonus += 1;
                if ((player.scores[11] orelse 0) == 50) totals[i].yahtzee += 1;
            }
        }
        try program.emit("sim seed {d} games {d} players {d}", .{ seed, count, strategies.len });
        for (strategies, 0..) |bot, i| {
            const total = totals[i];
            try program.emit("seat {d} {s} wins {d} average {f} best {d} bonus {d} yahtzee {d}", .{ i + 1, @tagName(bot), total.wins, average(total.sum, count), total.best, total.bonus, total.yahtzee });
        }
    }
    const Command = enum { RULE, GAME, BOT, LOAD, ROLL, HOLD, KEEP, SCORE, WHATIF, UNDO, REDO, SUGGEST, ODDS, ADVISE, AUTO, STATUS, CARD, BONUS, STATS, LOG, FACES, STANDINGS, END, RECORDS, SIM };
    fn execute(program: *Program, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]) orelse return program.fail("unknown command {s}", .{words[0]});
        switch (command) {
            .RULE => {
                if (!equal(words[1], "ROLLS") and !equal(words[1], "JOKER")) return program.fail("unknown rule {s}", .{words[1]});
                var changed = program.rules;
                if (equal(words[1], "ROLLS")) changed.rolls = @intCast(try program.positive(words[2], 4))
                else changed.joker = std.meta.stringToEnum(Joker, words[2]) orelse return program.fail("bad value {s}", .{words[2]});
                if (program.game != null) return program.fail("game in progress", .{});
                program.rules = changed;
                try program.emit("rule {s} {s}", .{ words[1], words[2] });
            },
            .GAME => {
                const seed = try program.positive(words[1], 2147483646);
                const names = words[2..];
                for (names) |word| try program.checkName(word);
                if (names.len > 6) return program.fail("too many players", .{});
                if (program.game != null) return program.fail("game in progress", .{});
                for (names, 0..) |word, i| for (names[0..i]) |previous| if (equal(word, previous)) return program.fail("duplicate name {s}", .{word});
                const game = try program.gpa.create(Game);
                game.* = Game.init(program, seed, names);
                program.game = game;
                try program.out.print("game seed {d} players", .{seed});
                for (names) |word| try program.out.print(" {s}", .{word});
                try program.out.writeByte('\n');
                try program.emit("turn 1 {s}", .{names[0]});
            },
            .BOT => {
                try program.checkName(words[1]);
                const bot = try program.parseStrategy(words[2]);
                const game = try program.table();
                const player: *Player = blk: {
                    for (game.players[0..game.player_count]) |*candidate| if (equal(candidate.name, words[1])) break :blk candidate;
                    return program.fail("no player {s}", .{words[1]});
                };
                player.strategy = bot;
                try program.emit("bot {s} {s}", .{ words[1], words[2] });
            },
            .LOAD, .KEEP => {
                var values: [20]u8 = undefined;
                const count = words.len - 1;
                for (words[1..], 0..) |word, i| values[i] = @intCast(try program.positive(word, 6));
                const game = try program.table();
                if (command == .KEEP) try game.keep(values[0..count]) else {
                    try game.loaded.appendSlice(program.gpa, values[0..count]);
                    try program.emit("loaded {d}", .{game.loaded.items.len - game.loaded_head});
                }
            },
            .ROLL => try (try program.table()).roll(),
            .HOLD, .ODDS => {
                const mask = try program.parsePattern(words[1]);
                const game = try program.table();
                if (command == .HOLD) try game.hold(mask) else try program.odds(game, mask);
            },
            .SCORE, .WHATIF => {
                const category = try program.parseCategory(words[1]);
                try (try program.table()).score(category, command == .WHATIF);
            },
            .UNDO => try (try program.table()).undo(),
            .REDO => try (try program.table()).redo(),
            .SUGGEST => {
                const game = try program.table();
                try game.checkRolled();
                const scores = evaluate(game.current(), countsOf(game.turn.?.dice), game.rules.joker);
                try program.out.writeAll("suggest");
                for (categories, 0..) |category, i| if (scores.points[i] >= 0) try program.out.print(" {s} {d}", .{ @tagName(category), scores.points[i] });
                try program.out.print(" best {s} {d}\n", .{ @tagName(scores.best), scores.points[@intFromEnum(scores.best)] });
            },
            .ADVISE => try program.advise(try program.table()),
            .AUTO => {
                const count: usize = @intCast(try program.positive(words[1], 100));
                const game = try program.table();
                try game.checkTurn();
                game.redo_count = 0;
                for (0..count) |_| {
                    if (game.turn == null) break;
                    try game.botTurn();
                }
            },
            .STATUS => {
                const game = try program.table();
                if (game.turn) |turn| try program.emit("status round {d} player {s} rolls {d} dice {f} holds {f}", .{ game.current().round(), game.current().name, turn.rolls, faces(if (turn.rolls == 0) null else turn.dice, 31), pattern(turn.hold) })
                else try program.emit("status game over", .{});
            },
            .CARD => try program.card(try program.table()),
            .BONUS => {
                const game = try program.table();
                for (game.players[0..game.player_count]) |player| {
                    const upper = player.upper();
                    var maximum = upper;
                    for (player.scores[0..6], 0..) |score, i| if (score == null) { maximum += @intCast(5 * (i + 1)); };
                    const status = if (upper >= 63) "made" else if (maximum < 63) "lost" else "open";
                    try program.emit("bonus {s} upper {d} need {d} max {d} {s}", .{ player.name, upper, @max(63 - upper, 0), maximum, status });
                }
            },
            .STATS => {
                const game = try program.table();
                for (game.players[0..game.player_count], 0..) |player, i| {
                    var turns: usize = 0;
                    var rolls: usize = 0;
                    var zeros: usize = 0;
                    var yahtzees: usize = 0;
                    var sum: i64 = 0;
                    for (game.entries[0..game.entry_count]) |entry| {
                        if (entry.before.seat != i) continue;
                        turns += 1;
                        rolls += entry.before.rolls;
                        zeros += @intFromBool(entry.points == 0);
                        yahtzees += @intFromBool(yahtzee(countsOf(entry.before.dice)));
                        sum += entry.points;
                    }
                    try program.emit("stats {s} turns {d} rolls {d} zeros {d} yahtzees {d} average {f}", .{ player.name, turns, rolls, zeros, yahtzees, average(sum, turns) });
                }
            },
            .LOG => {
                const game = try program.table();
                for (game.entries[0..game.entry_count], 0..) |entry, i| {
                    try program.emit("log {d} {s} {f} {s} {d}{s}{s}", .{ i + 1, game.players[entry.before.seat].name, faces(entry.before.dice, 31), @tagName(entry.category), entry.points, if (entry.joker) " joker" else "", if (entry.bonus != 0) " ybonus 100" else "" });
                }
                if (game.entry_count == 0) try program.emit("no scores", .{});
            },
            .FACES => {
                const game = try program.table();
                var total: i64 = 0;
                var squares: i64 = 0;
                try program.out.writeAll("faces");
                for (game.face_totals) |count| { total += count; squares += count * count; try program.out.print(" {d}", .{count}); }
                try program.out.print(" total {d} chi2 {f}\n", .{ total, fraction(6 * squares - total * total, if (total == 0) 1 else total) });
            },
            .STANDINGS, .END => {
                const game = try program.table();
                const ranking = game.ranking();
                const finished = game.turn == null;
                if (command == .END) try program.emit("end {s}", .{if (finished) "final" else "abandoned"});
                for (ranking[0..game.player_count], 0..) |seat, rank| {
                    const player = game.players[seat];
                    if (command == .STANDINGS) try program.emit("standing {d} {s} {d} behind {d}", .{ rank + 1, player.name, player.total(), game.players[ranking[0]].total() - player.total() }) else {
                        try program.emit("rank {d} {s} {d}", .{ rank + 1, player.name, player.total() });
                        if (finished) {
                            var record = program.records.get(player.name) orelse Record{};
                            record.games += 1;
                            record.wins += @intFromBool(rank == 0);
                            record.sum += player.total();
                            record.best = @max(record.best, player.total());
                            try program.records.put(program.gpa, player.name, record);
                        }
                    }
                }
                if (command == .END) program.game = null;
            },
            .RECORDS => {
                var names: std.ArrayList([]const u8) = .empty;
                var iterator = program.records.iterator();
                while (iterator.next()) |item| try names.append(program.gpa, item.key_ptr.*);
                std.mem.sort([]const u8, names.items, program, struct {
                    fn before(context: *Program, a: []const u8, b: []const u8) bool {
                        const first = context.records.get(a).?;
                        const second = context.records.get(b).?;
                        if (first.wins != second.wins) return first.wins > second.wins;
                        if (first.best != second.best) return first.best > second.best;
                        return std.mem.lessThan(u8, a, b);
                    }
                }.before);
                for (names.items) |word| {
                    const record = program.records.get(word).?;
                    try program.emit("record {s} games {d} wins {d} best {d} average {f}", .{ word, record.games, record.wins, record.best, average(record.sum, record.games) });
                }
                if (names.items.len == 0) try program.emit("no records", .{});
            },
            .SIM => {
                const seed = try program.positive(words[1], 2147483646);
                const count: usize = @intCast(try program.positive(words[2], 50));
                var strategies: [8]Strategy = undefined;
                for (words[3..], 0..) |word, i| strategies[i] = try program.parseStrategy(word);
                const size = words.len - 3;
                if (size > 6) return program.fail("too many players", .{});
                try program.simulate(seed, count, strategies[0..size]);
            },
        }
    }
};

fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const line = try buffer.toOwnedSlice();
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeAny(u8, line, " \r");
    while (parts.next()) |part| try words.append(gpa, part);
    return try words.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = std.fmt.parseInt(usize, (try readWords(gpa, &input.interface))[0], 10) catch unreachable;
    var program: Program = .{ .gpa = gpa, .out = &output.interface };
    try program.outcomes.init(gpa);
    for (0..count) |_| {
        const words = try readWords(gpa, &input.interface);
        var response: std.Io.Writer.Allocating = .init(gpa);
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
