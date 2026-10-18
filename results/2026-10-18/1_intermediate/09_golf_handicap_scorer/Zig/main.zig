const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn less(a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
fn integer(s: []const u8) i64 { return std.fmt.parseInt(i64, s, 10) catch unreachable; }
fn sum(xs: []const i64) i64 { var result: i64 = 0; for (xs) |x| result += x; return result; }
fn away(n: i64, d: i64) i64 { return if (n < 0) -@divTrunc(-n * 2 + d, 2 * d) else @divTrunc(n * 2 + d, 2 * d); }
fn halfUp(n: i64, d: i64) i64 { return @divFloor(2 * n + d, 2 * d); }
const Tee = struct { id: []const u8, rating: i64, slope: i64 };
const Course = struct { id: []const u8, pars: [18]i64, si: [18]i64, tees: std.ArrayList(*Tee) = .empty };
const Calculation = struct { k: usize, average: i64, adjustment: i64, low: ?i64, hard: bool, soft: bool, maximum: bool };
const IndexRecord = struct { day: i64, value: i64 };
const Round = struct {
    course: *Course, tee: *Tee, day: i64, scores: [18]i64, handicap: ?i64,
    adjusted: [18]i64, ags: i64, diff: i64, exceptional: i64,
    old_index: ?i64, old_calculation: ?Calculation, old_records: usize,
};
const Player = struct {
    id: []const u8, name: []const u8, index: ?i64,
    calculation: ?Calculation = null, rounds: std.ArrayList(*Round) = .empty, records: std.ArrayList(IndexRecord) = .empty,
};
const Event = struct { id: []const u8, format: []const u8, course: *Course, tee: *Tee, day: i64, allowance: i64, players: []*Player };
const Pick = struct { number: usize, value: i64, counting: bool = false };
const Picks = struct { items: [20]Pick = undefined, len: usize = 0 };
const Rows = struct { items: [10]usize = undefined, len: usize = 0 };
const Result = struct {
    event: *Event, rounds: [10]*Round = undefined, ph: [10]i64 = undefined,
    nets: [10][18]?i64 = undefined, points: [10][18]i64 = undefined,
};
fn allocation(h: i64, c: *Course) [18]i64 {
    var strokes: [18]i64 = undefined;
    for (c.si, 0..) |si, i| {
        strokes[i] = if (h >= 0) @divTrunc(h, 18) + @as(i64, if (si <= @mod(h, 18)) 1 else 0)
            else -@divTrunc(-h, 18) - @as(i64, if (si >= 19 - @mod(-h, 18)) 1 else 0);
    }
    return strokes;
}
fn handicap(index: i64, c: *Course, t: *Tee) i64 { return halfUp(index * t.slope + 113 * (t.rating - 10 * sum(&c.pars)), 1130); }
fn points(net: ?i64, par: i64) i64 { return if (net) |n| @max(0, par + 2 - n) else 0; }
fn rule(n: usize) struct { k: usize, adjustment: i64 } {
    if (n <= 5) return .{ .k = 1, .adjustment = if (n == 3) -20 else if (n == 4) -10 else 0 };
    if (n == 6) return .{ .k = 2, .adjustment = -10 };
    return .{ .k = if (n <= 8) 2 else if (n <= 11) 3 else if (n <= 14) 4 else if (n <= 16) 5 else if (n <= 18) 6 else if (n == 19) 7 else 8, .adjustment = 0 };
}
fn eligible(p: *Player) Picks {
    var result: Picks = .{};
    result.len = @min(20, p.rounds.items.len);
    var reduction: i64 = 0; var i = p.rounds.items.len;
    while (i > p.rounds.items.len - result.len) {
        i -= 1; const r = p.rounds.items[i]; reduction += r.exceptional;
        result.items[i - (p.rounds.items.len - result.len)] = .{ .number = i + 1, .value = r.diff - reduction };
    }
    if (result.len >= 3) {
        var order: [20]usize = undefined;
        for (0..result.len) |j| order[j] = j;
        for (1..result.len) |j| {
            const entry = order[j]; var k = j;
            while (k > 0) : (k -= 1) {
                const a = result.items[entry]; const b = result.items[order[k - 1]];
                if (!(a.value < b.value or (a.value == b.value and a.number > b.number))) break;
                order[k] = order[k - 1];
            }
            order[k] = entry;
        }
        for (order[0..rule(result.len).k]) |j| result.items[j].counting = true;
    }
    return result;
}
fn lowIndex(p: *Player, day: i64) ?IndexRecord {
    var best: ?IndexRecord = null;
    for (p.records.items) |r| {
        if (r.day < day - 365 or r.day >= day) continue;
        if (best == null or r.value < best.?.value or (r.value == best.?.value and r.day < best.?.day)) best = r;
    }
    return best;
}
fn compareValues(a: [18]i64, b: [18]i64, higher: bool) i8 {
    for ([_]usize{ 0, 9, 12, 15, 17 }) |start| {
        const av = sum(a[start..]); const bv = sum(b[start..]);
        if (av != bv) return if ((av < bv) != higher) -1 else 1;
    }
    return 0;
}
const Golf = struct {
    gpa: Allocator, out: *std.Io.Writer, error_message: []const u8 = "",
    courses: std.ArrayList(*Course) = .empty, players: std.ArrayList(*Player) = .empty, events: std.ArrayList(*Event) = .empty,
    fn emit(self: *Golf, comptime fmt: []const u8, args: anytype) Error!void { try self.out.print(fmt, args); }
    fn text(self: *Golf, comptime fmt: []const u8, args: anytype) Allocator.Error![]const u8 { return std.fmt.allocPrint(self.gpa, fmt, args); }
    fn fail(self: *Golf, reason: []const u8) Error { self.error_message = reason; return error.BadCommand; }
    fn decimal(self: *Golf, v: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(if (v < 0) -v else v);
        return self.text("{s}{d}.{d}", .{ if (v < 0) "-" else "", u / 10, u % 10 });
    }
    fn indexText(self: *Golf, v: ?i64) Allocator.Error![]const u8 {
        const n = v orelse return "none";
        if (n < 0) return self.text("+{s}", .{try self.decimal(-n)});
        return self.decimal(n);
    }
    fn hcpText(self: *Golf, v: ?i64) Allocator.Error![]const u8 {
        const n = v orelse return "none";
        return self.text("{s}{d}", .{ if (n < 0) "+" else "", if (n < 0) -n else n });
    }
    fn two(self: *Golf, n: i64, d: i64) Allocator.Error![]const u8 {
        const q: u64 = @intCast(@divTrunc(n * 100, d));
        return self.text("{d}.{d:0>2}", .{ q / 100, q % 100 });
    }
    fn status(self: *Golf, lead: i64) Allocator.Error![]const u8 {
        if (lead == 0) return "AS";
        return self.text("{d} {s}", .{ if (lead < 0) -lead else lead, if (lead > 0) "UP" else "DN" });
    }
    fn findPlayer(self: *Golf, id: []const u8) ?*Player { for (self.players.items) |p| { if (eq(p.id, id)) return p; } return null; }
    fn player(self: *Golf, id: []const u8) Error!*Player { return self.findPlayer(id) orelse return self.fail("unknown player"); }
    fn findCourse(self: *Golf, id: []const u8) ?*Course { for (self.courses.items) |c| { if (eq(c.id, id)) return c; } return null; }
    fn course(self: *Golf, id: []const u8) Error!*Course { return self.findCourse(id) orelse return self.fail("unknown course"); }
    fn findTee(c: *Course, id: []const u8) ?*Tee { for (c.tees.items) |t| { if (eq(t.id, id)) return t; } return null; }
    fn tee(self: *Golf, c: *Course, id: []const u8) Error!*Tee { return findTee(c, id) orelse return self.fail("unknown tee"); }
    fn findEvent(self: *Golf, id: []const u8) ?*Event { for (self.events.items) |e| { if (eq(e.id, id)) return e; } return null; }
    fn update(self: *Golf, p: *Player, day: i64) void {
        _ = self;
        const picks = eligible(p);
        if (picks.len < 3) { p.calculation = null; return; }
        const r = rule(picks.len); var total: i64 = 0;
        for (picks.items[0..picks.len]) |pick| { if (pick.counting) total += pick.value; }
        const average = away(total, @intCast(r.k)); var value = average + r.adjustment;
        const low: ?i64 = if (lowIndex(p, day)) |record| record.value else null;
        var soft = false; var hard = false; var maximum = false;
        if (low) |l| {
            if (value - l > 30) { const capped = l + 30 + @divTrunc(value - l - 30, 2); soft = capped != value; value = capped; }
            if (value - l > 50) { value = l + 50; hard = true; }
        }
        if (value > 540) { value = 540; maximum = true; }
        p.index = value; p.calculation = .{ .k = r.k, .average = average, .adjustment = r.adjustment, .low = low, .hard = hard, .soft = soft, .maximum = maximum };
    }
    fn evaluate(self: *Golf, e: *Event) Error!Result {
        var r = Result{ .event = e }; var minimum: i64 = std.math.maxInt(i64);
        for (e.players, 0..) |p, i| {
            var selected: ?*Round = null;
            for (p.rounds.items) |round| {
                if (round.course == e.course and round.tee == e.tee and round.day == e.day) { selected = round; break; }
            }
            const round = selected orelse return self.fail("missing round");
            const hcp = round.handicap orelse return self.fail("no index");
            r.rounds[i] = round; r.ph[i] = halfUp(hcp * e.allowance, 100); minimum = @min(minimum, r.ph[i]);
        }
        const relative = eq(e.format, "MATCH") or eq(e.format, "NASSAU") or eq(e.format, "FOURBALL");
        for (e.players, 0..) |_, i| {
            const strokes = allocation(r.ph[i] - (if (relative) minimum else @as(i64, 0)), e.course);
            for (0..18) |h| {
                r.nets[i][h] = if (r.rounds[i].scores[h] > 0) r.rounds[i].scores[h] - strokes[h] else null;
                r.points[i][h] = points(r.nets[i][h], e.course.pars[h]);
            }
        }
        return r;
    }
    fn rank(r: *const Result, gross: bool) Rows {
        const e = r.event; var rows: Rows = .{}; var values: [10][18]i64 = undefined;
        for (e.players, 0..) |_, i| {
            var complete = true; for (r.nets[i]) |n| { if (n == null) complete = false; }
            if (eq(e.format, "STROKE") and !complete) continue;
            rows.items[rows.len] = i; rows.len += 1;
            for (0..18) |h| {
                values[i][h] = if (gross) r.rounds[i].scores[h]
                    else if (eq(e.format, "STABLEFORD")) r.points[i][h]
                    else if (eq(e.format, "PAR")) (if (r.nets[i][h] == null or r.nets[i][h].? > e.course.pars[h]) @as(i64, -1) else if (r.nets[i][h].? == e.course.pars[h]) @as(i64, 0) else @as(i64, 1))
                    else r.nets[i][h].?;
            }
        }
        for (1..@max(1, rows.len)) |i| {
            const entry = rows.items[i]; var j = i;
            while (j > 0) : (j -= 1) {
                const other = rows.items[j - 1]; const c = compareValues(values[entry], values[other], !gross and !eq(e.format, "STROKE"));
                if (!(c < 0 or (c == 0 and less(e.players[entry].id, e.players[other].id)))) break;
                rows.items[j] = other;
            }
            rows.items[j] = entry;
        }
        return rows;
    }
    fn match(self: *Golf, wins: [18]i64, first: usize, end: usize, side1: []const u8, side2: []const u8) Error!struct { statuses: []const u8, result: []const u8 } {
        var lead: i64 = 0; var remaining: usize = end - first;
        var statuses: std.Io.Writer.Allocating = .init(self.gpa);
        for (first..end) |h| {
            lead += wins[h]; remaining = end - h - 1;
            if (h > first) try statuses.writer.writeAll(", ");
            try statuses.writer.writeAll(try self.status(lead));
            if (@abs(lead) > remaining) break;
        }
        var result: []const u8 = "AS";
        if (lead != 0) {
            const side = if (lead > 0) side1 else side2;
            result = if (remaining > 0) try self.text("{s} {d}&{d}", .{ side, @abs(lead), remaining }) else try self.text("{s} {d} UP", .{ side, @abs(lead) });
        }
        return .{ .statuses = statuses.writer.buffered(), .result = result };
    }
    fn results(self: *Golf, r: *const Result) Error!void {
        const e = r.event; const f = e.format;
        try self.emit("results {s}: {s} {s} {s} day {d} allowance {d}\n", .{ e.id, f, e.course.id, e.tee.id, e.day, e.allowance });
        if (eq(f, "STROKE") or eq(f, "STABLEFORD") or eq(f, "PAR")) {
            const ranked = rank(r, false);
            for (ranked.items[0..ranked.len], 0..) |i, place| {
                try self.emit("{d} {s}", .{ place + 1, e.players[i].id });
                if (eq(f, "STROKE")) {
                    var net: i64 = 0; for (r.nets[i]) |n| net += n.?;
                    try self.emit(" net {d} gross {d}", .{ net, sum(&r.rounds[i].scores) });
                } else if (eq(f, "STABLEFORD")) { try self.emit(" points {d}", .{sum(&r.points[i])});
                } else {
                    var record: i64 = 0;
                    for (0..18) |h| record += if (r.nets[i][h] == null or r.nets[i][h].? > e.course.pars[h]) @as(i64, -1) else if (r.nets[i][h].? == e.course.pars[h]) @as(i64, 0) else @as(i64, 1);
                    try self.emit(" {s}", .{try self.status(record)});
                }
                try self.emit(" hcp {s}\n", .{try self.hcpText(r.ph[i])});
            }
            if (eq(f, "STROKE")) {
                var nr: Rows = .{};
                for (e.players, 0..) |_, i| {
                    var complete = true; for (r.nets[i]) |n| { if (n == null) complete = false; }
                    if (!complete) { nr.items[nr.len] = i; nr.len += 1; }
                }
                sortIDs(e, nr.items[0..nr.len]);
                for (nr.items[0..nr.len]) |i| try self.emit("NR {s} hcp {s}\n", .{ e.players[i].id, try self.hcpText(r.ph[i]) });
                if (ranked.len > 0) { const i = rank(r, true).items[0]; try self.emit("gross {s} {d}\n", .{ e.players[i].id, sum(&r.rounds[i].scores) }); }
            }
        } else if (eq(f, "MATCH") or eq(f, "NASSAU") or eq(f, "FOURBALL")) {
            var minimum = r.ph[0]; for (r.ph[0..e.players.len]) |ph| minimum = @min(minimum, ph);
            try self.out.writeAll("strokes");
            for (e.players, 0..) |p, i| try self.emit(" {s} {d}", .{ p.id, r.ph[i] - minimum });
            try self.out.writeByte('\n');
            const four = eq(f, "FOURBALL");
            const side1 = if (four) try self.text("{s}+{s}", .{ e.players[0].id, e.players[1].id }) else e.players[0].id;
            const side2 = if (four) try self.text("{s}+{s}", .{ e.players[2].id, e.players[3].id }) else e.players[1].id;
            var wins: [18]i64 = undefined;
            for (0..18) |h| {
                var a = r.nets[0][h]; var b = r.nets[if (four) 2 else 1][h];
                if (four) {
                    if (r.nets[1][h]) |n| { if (a == null or n < a.?) a = n; }
                    if (r.nets[3][h]) |n| { if (b == null or n < b.?) b = n; }
                }
                wins[h] = if (a == null) (if (b == null) @as(i64, 0) else @as(i64, -1)) else if (b == null) 1 else if (a.? < b.?) 1 else if (a.? > b.?) -1 else 0;
            }
            if (eq(f, "NASSAU")) {
                try self.emit("front {s}\nback {s}\ntotal {s}\n", .{ (try self.match(wins, 0, 9, side1, side2)).result, (try self.match(wins, 9, 18, side1, side2)).result, (try self.match(wins, 0, 18, side1, side2)).result });
            } else { const m = try self.match(wins, 0, 18, side1, side2); try self.emit("status {s}\nresult {s}\n", .{ m.statuses, m.result }); }
        } else if (eq(f, "BETTERBALL")) {
            var values: [5][18]i64 = undefined; var teams: [5]usize = undefined; const count = e.players.len / 2;
            for (0..count) |i| { teams[i] = i; for (0..18) |h| values[i][h] = @max(r.points[2 * i][h], r.points[2 * i + 1][h]); }
            for (1..count) |i| {
                const entry = teams[i]; var j = i;
                while (j > 0) : (j -= 1) {
                    const other = teams[j - 1]; const c = compareValues(values[entry], values[other], true);
                    if (!(c < 0 or (c == 0 and less(e.players[2 * entry].id, e.players[2 * other].id)))) break;
                    teams[j] = other;
                }
                teams[j] = entry;
            }
            for (teams[0..count], 0..) |team, place| {
                const i = team * 2;
                try self.emit("{d} {s}+{s} points {d} hcp {s} {s}\n", .{ place + 1, e.players[i].id, e.players[i + 1].id, sum(&values[team]), try self.hcpText(r.ph[i]), try self.hcpText(r.ph[i + 1]) });
            }
        } else {
            var carry: i64 = 0; var totals: [10]i64 = @splat(0);
            for (0..18) |h| {
                carry += 1; const ws = winners(r, h);
                if (ws.len == 1) { const i = ws.items[0]; totals[i] += carry * 100; try self.emit("hole {d} {s} {d}\n", .{ h + 1, e.players[i].id, carry }); carry = 0; }
            }
            if (carry > 0) {
                var ws = winners(r, 17);
                if (ws.len == 0) { ws.len = e.players.len; for (0..ws.len) |i| ws.items[i] = i; }
                sortIDs(e, ws.items[0..ws.len]); try self.emit("carry {d}", .{carry});
                for (ws.items[0..ws.len]) |i| { totals[i] += @divTrunc(carry * 100, @as(i64, @intCast(ws.len))); try self.emit(" {s}", .{e.players[i].id}); }
                try self.out.writeByte('\n');
            }
            var ids: [10]usize = undefined; for (0..e.players.len) |i| ids[i] = i;
            for (1..e.players.len) |i| {
                const entry = ids[i]; var j = i;
                while (j > 0) : (j -= 1) {
                    const b = ids[j - 1];
                    if (!(totals[entry] > totals[b] or (totals[entry] == totals[b] and less(e.players[entry].id, e.players[b].id)))) break;
                    ids[j] = b;
                }
                ids[j] = entry;
            }
            for (ids[0..e.players.len]) |i| try self.emit("{s} {s}\n", .{ e.players[i].id, try self.two(totals[i], 100) });
        }
    }
    fn cardTotal(self: *Golf, label: []const u8, r: *Round, strokes: [18]i64, first: usize, end: usize) Error!void {
        var complete = true; var score: i64 = 0; var net: i64 = 0; var pts: i64 = 0;
        for (first..end) |h| {
            if (r.scores[h] <= 0) { complete = false; } else { score += r.scores[h]; net += r.scores[h] - strokes[h]; pts += points(r.scores[h] - strokes[h], r.course.pars[h]); }
        }
        try self.emit("{s} {d} {s} {d} {d} {s} {d}\n", .{ label, sum(r.course.pars[first..end]), if (complete) try self.text("{d}", .{score}) else "-", sum(r.adjusted[first..end]), sum(strokes[first..end]), if (complete) try self.text("{d}", .{net}) else "-", pts });
    }
    fn card(self: *Golf, p: *Player, no: usize, r: *Round) Error!void {
        const c = r.course; const strokes = allocation(r.handicap orelse 0, c);
        try self.emit("card {s} {d}: {s} {s} day {d} handicap {s}\n", .{ p.id, no, c.id, r.tee.id, r.day, try self.hcpText(r.handicap) });
        for (0..18) |h| {
            const s = r.scores[h]; const net: ?i64 = if (s > 0) s - strokes[h] else null;
            try self.emit("{d} {d} {d} {s} {d} {d} {s} {d}\n", .{ h + 1, c.pars[h], c.si[h], if (s < 0) "-" else if (s == 0) "X" else try self.text("{d}", .{s}), r.adjusted[h], strokes[h], if (net) |n| try self.text("{d}", .{n}) else "-", points(net, c.pars[h]) });
            if (h == 8) try self.cardTotal("OUT", r, strokes, 0, 9);
            if (h == 17) { try self.cardTotal("IN", r, strokes, 9, 18); try self.cardTotal("TOTAL", r, strokes, 0, 18); }
        }
        try self.emit("ags {d} diff {s}\n", .{ r.ags, try self.decimal(r.diff) });
    }
    fn stats(self: *Golf, p: *Player) Error!void {
        var categories: [7]i64 = @splat(0); var par_sum: [6]i64 = @splat(0); var par_count: [6]i64 = @splat(0);
        var best: ?i64 = null; var complete_sum: i64 = 0; var complete_count: i64 = 0;
        for (p.rounds.items) |r| {
            var complete = true;
            for (0..18) |h| {
                const s = r.scores[h]; const par: usize = @intCast(r.course.pars[h]);
                if (s <= 0) { complete = false; if (s == 0) categories[6] += 1; continue; }
                const d = s - r.course.pars[h]; const cat: usize = if (d <= -2) 0 else if (d == -1) 1 else if (d == 0) 2 else if (d == 1) 3 else if (d == 2) 4 else 5;
                categories[cat] += 1; par_sum[par] += s; par_count[par] += 1;
            }
            if (complete) { const s = sum(&r.scores); best = if (best) |b| @min(b, s) else s; complete_sum += s; complete_count += 1; }
        }
        try self.emit("stats {s}: rounds {d} best {s} average {s} eagles {d} birdies {d} pars {d} bogeys {d} doubles {d} others {d} pickups {d}", .{ p.id, p.rounds.items.len, if (best) |b| try self.text("{d}", .{b}) else "-", if (complete_count == 0) "-" else try self.two(complete_sum, complete_count), categories[0], categories[1], categories[2], categories[3], categories[4], categories[5], categories[6] });
        for (3..6) |k| try self.emit(" par{d} {s}", .{ k, if (par_count[k] == 0) "-" else try self.two(par_sum[k], par_count[k]) });
        try self.out.writeByte('\n');
    }
    fn execute(self: *Golf, a: []const []const u8) Error!void {
        const op = a[0]; const id: []const u8 = if (a.len > 1) a[1] else "";
        if (eq(op, "COURSE")) {
            if (self.findCourse(id) != null) return self.fail("duplicate course");
            var pars: [18]i64 = undefined; var si: [18]i64 = undefined; var seen: [19]bool = @splat(false);
            for (0..18) |h| {
                pars[h] = integer(a[h + 2]); si[h] = integer(a[h + 20]);
                if (pars[h] < 3 or pars[h] > 5 or si[h] < 1 or si[h] > 18) return self.fail("invalid course");
                const s: usize = @intCast(si[h]); if (seen[s]) return self.fail("invalid course"); seen[s] = true;
            }
            const c = try self.gpa.create(Course); c.* = .{ .id = id, .pars = pars, .si = si }; try self.courses.append(self.gpa, c);
        } else if (eq(op, "TEE")) {
            const c = try self.course(id); if (findTee(c, a[2]) != null) return self.fail("duplicate tee");
            const r = integer(a[3]); const s = integer(a[4]);
            if (r < 500 or r > 900 or s < 55 or s > 155) return self.fail("invalid tee");
            const t = try self.gpa.create(Tee); t.* = .{ .id = a[2], .rating = r, .slope = s }; try c.tees.append(self.gpa, t);
        } else if (eq(op, "PLAYER")) {
            if (self.findPlayer(id) != null) return self.fail("duplicate player");
            const value: ?i64 = if (a.len > 3) integer(a[3]) else null;
            if (value) |v| { if (v < -100 or v > 540) return self.fail("invalid index"); }
            const p = try self.gpa.create(Player); p.* = .{ .id = id, .name = a[2], .index = value }; try self.players.append(self.gpa, p);
        } else if (eq(op, "ROUND")) {
            const p = try self.player(id); const c = try self.course(a[2]); const t = try self.tee(c, a[3]); const day = integer(a[4]);
            if (p.rounds.items.len > 0 and day < p.rounds.items[p.rounds.items.len - 1].day) return self.fail("invalid day");
            var scores: [18]i64 = undefined; var missing: usize = 0;
            for (0..18) |h| { scores[h] = if (eq(a[h + 5], "-")) -1 else if (eq(a[h + 5], "X")) 0 else integer(a[h + 5]); if (scores[h] < 0) missing += 1; }
            if (missing >= 5) return self.fail("too few holes");
            const hcp: ?i64 = if (p.index) |value| handicap(value, c, t) else null; const strokes = allocation(hcp orelse 0, c);
            var adjusted: [18]i64 = undefined;
            for (0..18) |h| {
                const limit = c.pars[h] + (if (p.index == null) @as(i64, 5) else 2 + strokes[h]);
                adjusted[h] = if (scores[h] < 0) c.pars[h] + strokes[h] else if (scores[h] == 0) limit else @min(scores[h], limit);
            }
            const ags = sum(&adjusted); const diff = away(113 * (10 * ags - t.rating), t.slope);
            var exceptional: i64 = 0;
            if (p.index) |value| { if (value - diff >= 70) exceptional = if (value - diff < 100) 10 else 20; }
            const r = try self.gpa.create(Round);
            r.* = .{ .course = c, .tee = t, .day = day, .scores = scores, .handicap = hcp, .adjusted = adjusted, .ags = ags, .diff = diff, .exceptional = exceptional, .old_index = p.index, .old_calculation = p.calculation, .old_records = p.records.items.len };
            try p.rounds.append(self.gpa, r); self.update(p, day);
            if (p.index) |value| try p.records.append(self.gpa, .{ .day = day, .value = value });
            try self.emit("round {s} {d}: ags {d} diff {s}", .{ id, p.rounds.items.len, ags, try self.decimal(diff) });
            if (exceptional != 0) try self.emit(" exceptional {s}", .{try self.decimal(-exceptional)});
            try self.emit(" index {s}\n", .{try self.indexText(p.index)});
        } else if (eq(op, "REMOVE")) {
            const p = try self.player(id); if (p.rounds.items.len == 0) return self.fail("no rounds");
            const no = p.rounds.items.len; const r = p.rounds.pop().?;
            p.index = r.old_index; p.calculation = r.old_calculation; p.records.shrinkRetainingCapacity(r.old_records);
            try self.emit("removed {s} {d}: index {s}\n", .{ id, no, try self.indexText(p.index) });
        } else if (eq(op, "INDEX") or eq(op, "HISTORY") or eq(op, "LOWINDEX") or eq(op, "STATS") or eq(op, "CARD")) {
            const p = try self.player(id);
            if (eq(op, "INDEX")) {
                try self.emit("index {s}: {s} rounds {d}", .{ id, try self.indexText(p.index), p.rounds.items.len });
                if (p.calculation) |c| {
                    try self.emit(" lowest {d} average {s} adjustment {s}", .{ c.k, try self.decimal(c.average), try self.decimal(c.adjustment) });
                    if (c.low) |l| try self.emit(" low {s}", .{try self.indexText(l)});
                    if (c.hard) try self.out.writeAll(" hard cap") else if (c.soft) try self.out.writeAll(" soft cap");
                    if (c.maximum) try self.out.writeAll(" maximum");
                }
                try self.out.writeByte('\n');
            } else if (eq(op, "HISTORY")) {
                try self.emit("history {s}: rounds {d}\n", .{ id, p.rounds.items.len }); const picks = eligible(p);
                for (picks.items[0..picks.len]) |pick| {
                    const r = p.rounds.items[pick.number - 1];
                    try self.emit("{d} day {d} {s} {s} ags {d} diff {s}", .{ pick.number, r.day, r.course.id, r.tee.id, r.ags, try self.decimal(r.diff) });
                    if (pick.value != r.diff) try self.emit(" adjusted {s}", .{try self.decimal(pick.value)});
                    if (pick.counting) try self.out.writeAll(" *"); try self.out.writeByte('\n');
                }
            } else if (eq(op, "LOWINDEX")) {
                const day = integer(a[2]); try self.emit("lowindex {s} {d}: ", .{ id, day });
                if (lowIndex(p, day)) |r| try self.emit("{s} day {d}\n", .{ try self.indexText(r.value), r.day }) else try self.out.writeAll("none\n");
            } else if (eq(op, "STATS")) { try self.stats(p);
            } else {
                const no: usize = @intCast(integer(a[2])); if (no > p.rounds.items.len) return self.fail("unknown round"); try self.card(p, no, p.rounds.items[no - 1]);
            }
        } else if (eq(op, "COURSEHCP")) {
            const p = try self.player(id); const c = try self.course(a[2]); const t = try self.tee(c, a[3]); const value = p.index orelse return self.fail("no index");
            const hcp = handicap(value, c, t); try self.emit("coursehcp {s} {s} {s}: {s} strokes", .{ id, c.id, t.id, try self.hcpText(hcp) });
            for (allocation(hcp, c)) |s| try self.emit(" {d}", .{s}); try self.out.writeByte('\n');
        } else if (eq(op, "HCPTABLE")) {
            const c = try self.course(id); const t = try self.tee(c, a[2]); const first = integer(a[3]); const last = integer(a[4]);
            if (first < -100 or first > last or last > 540) return self.fail("invalid index");
            try self.emit("hcptable {s} {s}: {s} to {s}\n", .{ id, t.id, try self.indexText(first), try self.indexText(last) });
            var start = first; var current = handicap(first, c, t); var i = first + 1;
            while (i <= last + 1) : (i += 1) {
                const hcp: ?i64 = if (i > last) null else handicap(i, c, t);
                if (hcp == null or hcp.? != current) { try self.emit("{s} to {s}: {s}\n", .{ try self.indexText(start), try self.indexText(i - 1), try self.hcpText(current) }); start = i; if (hcp) |h| current = h; }
            }
        } else if (eq(op, "HOLESTATS")) {
            const c = try self.course(id); var sums: [18]i64 = @splat(0); var counts: [18]i64 = @splat(0); var rounds: usize = 0;
            for (self.players.items) |p| {
                for (p.rounds.items) |r| { if (r.course != c) continue; rounds += 1; for (0..18) |h| { if (r.scores[h] > 0) { counts[h] += 1; sums[h] += r.scores[h]; } } }
            }
            var holes: [18]usize = undefined; for (0..18) |h| holes[h] = h;
            for (1..18) |i| {
                const entry = holes[i]; var j = i;
                while (j > 0) : (j -= 1) {
                    const b = holes[j - 1]; var before = false;
                    if (counts[entry] == 0 or counts[b] == 0) { before = if (counts[entry] == counts[b]) entry < b else counts[entry] > 0; }
                    else {
                        const av = (sums[entry] - c.pars[entry] * counts[entry]) * counts[b]; const bv = (sums[b] - c.pars[b] * counts[b]) * counts[entry];
                        before = av > bv or (av == bv and entry < b);
                    }
                    if (!before) break; holes[j] = b;
                }
                holes[j] = entry;
            }
            var ranks: [18]usize = undefined; for (holes, 0..) |h, i| ranks[h] = i + 1;
            try self.emit("holestats {s}: rounds {d}\n", .{ id, rounds });
            for (0..18) |h| try self.emit("{d} par {d} si {d} scores {d} avg {s} rank {d}\n", .{ h + 1, c.pars[h], c.si[h], counts[h], if (counts[h] == 0) "-" else try self.two(sums[h], counts[h]), ranks[h] });
        } else if (eq(op, "PLAYERS")) {
            const ps = try self.gpa.dupe(*Player, self.players.items);
            for (1..@max(1, ps.len)) |i| {
                const p = ps[i]; var j = i;
                while (j > 0) : (j -= 1) {
                    const b = ps[j - 1]; const before = if (p.index == null or b.index == null) (if (p.index == b.index) less(p.id, b.id) else p.index != null) else p.index.? < b.index.? or (p.index.? == b.index.? and less(p.id, b.id));
                    if (!before) break; ps[j] = b;
                }
                ps[j] = p;
            }
            try self.emit("players {d}\n", .{ps.len});
            for (ps) |p| try self.emit("{s} {s} {s} rounds {d}\n", .{ p.id, p.name, try self.indexText(p.index), p.rounds.items.len });
        } else if (eq(op, "EVENT")) {
            if (self.findEvent(id) != null) return self.fail("duplicate event");
            const c = try self.course(a[3]); const t = try self.tee(c, a[4]); const allowance = integer(a[6]);
            if (allowance < 1 or allowance > 100) return self.fail("invalid allowance");
            const ps = try self.gpa.alloc(*Player, a.len - 7); for (a[7..], 0..) |name, i| ps[i] = try self.player(name);
            const f = a[2]; const n = ps.len;
            var valid = if (eq(f, "MATCH") or eq(f, "NASSAU")) n == 2 else if (eq(f, "FOURBALL")) n == 4 else if (eq(f, "BETTERBALL")) n == 4 or n == 6 or n == 8 else n >= 2 and n <= 8;
            for (ps, 0..) |p, i| { for (ps[0..i]) |b| { if (p == b) valid = false; } }
            if (!valid) return self.fail("invalid players");
            const e = try self.gpa.create(Event); e.* = .{ .id = id, .format = f, .course = c, .tee = t, .day = integer(a[5]), .allowance = allowance, .players = ps }; try self.events.append(self.gpa, e);
        } else if (eq(op, "RESULTS")) {
            const e = self.findEvent(id) orelse return self.fail("unknown event"); const r = try self.evaluate(e); try self.results(&r);
        } else if (eq(op, "MERIT")) {
            const Merit = struct { player: *Player, points: i64 = 0, wins: i64 = 0, appearances: i64 = 0 };
            const values = try self.gpa.alloc(Merit, self.players.items.len); for (self.players.items, 0..) |p, i| values[i] = .{ .player = p };
            var counted: usize = 0;
            for (self.events.items) |e| {
                if (!eq(e.format, "STROKE") and !eq(e.format, "STABLEFORD") and !eq(e.format, "PAR")) continue;
                const r = self.evaluate(e) catch |err| { if (err == error.BadCommand) continue; return err; }; counted += 1;
                for (e.players) |p| { for (values) |*v| { if (v.player == p) v.appearances += 1; } }
                const ranked = rank(&r, false); const awards = [_]i64{ 10, 8, 6, 5, 4, 3, 2, 1 };
                for (ranked.items[0..ranked.len], 0..) |i, place| { for (values) |*v| { if (v.player == e.players[i]) { v.points += awards[place]; if (place == 0) v.wins += 1; } } }
            }
            for (1..@max(1, values.len)) |i| {
                const v = values[i]; var j = i;
                while (j > 0) : (j -= 1) {
                    const b = values[j - 1]; if (!(v.points > b.points or (v.points == b.points and (v.wins > b.wins or (v.wins == b.wins and less(v.player.id, b.player.id)))))) break;
                    values[j] = b;
                }
                values[j] = v;
            }
            try self.emit("merit: events {d}\n", .{counted}); var place: usize = 0;
            for (values) |v| { if (v.appearances == 0) continue; place += 1; try self.emit("{d} {s} {d} wins {d} played {d}\n", .{ place, v.player.id, v.points, v.wins, v.appearances }); }
        }
    }
};
fn sortIDs(e: *Event, ids: []usize) void {
    for (1..@max(1, ids.len)) |i| {
        const entry = ids[i]; var j = i;
        while (j > 0 and less(e.players[entry].id, e.players[ids[j - 1]].id)) : (j -= 1) ids[j] = ids[j - 1];
        ids[j] = entry;
    }
}
fn winners(r: *const Result, h: usize) Rows {
    var rows: Rows = .{}; var minimum: ?i64 = null;
    for (r.event.players, 0..) |_, i| {
        if (r.nets[i][h]) |net| {
            if (minimum == null or net < minimum.?) { minimum = net; rows.len = 0; }
            if (net == minimum.?) { rows.items[rows.len] = i; rows.len += 1; }
        }
    }
    return rows;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit(); const gpa = arena.allocator();
    var ib: [4096]u8 = undefined; var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var ob: [8192]u8 = undefined; var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var golf = Golf{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var tokens: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, line, ' '); while (it.next()) |part| try tokens.append(gpa, part);
        var draft: std.Io.Writer.Allocating = .init(gpa); golf.out = &draft.writer;
        golf.execute(tokens.items) catch |err| {
            if (err == error.BadCommand) { try output.interface.print("ERROR {s}\n", .{golf.error_message}); continue; } return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
