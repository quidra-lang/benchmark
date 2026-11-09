const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const Strings = [][]const u8;

fn unsigned(text: []const u8, limit: usize) ?i64 {
    if (text.len == 0 or text.len > limit) return null;
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return null;
    }
    return std.fmt.parseInt(i64, text, 10) catch null;
}
fn timeValue(text: []const u8) ?i64 {
    if (text.len != 12 or text[2] != ':' or text[5] != ':' or text[8] != ',') return null;
    const h = unsigned(text[0..2], 2) orelse return null;
    const m = unsigned(text[3..5], 2) orelse return null;
    const s = unsigned(text[6..8], 2) orelse return null;
    const ms = unsigned(text[9..12], 3) orelse return null;
    if (m > 59 or s > 59) return null;
    return h * 3600000 + m * 60000 + s * 1000 + ms;
}
fn roundRatio(numerator: i64, denominator: i64) i64 {
    const a = if (denominator < 0) -numerator else numerator;
    const b = if (denominator < 0) -denominator else denominator;
    return @divFloor(2 * a + b, 2 * b);
}
fn timeText(gpa: Allocator, value: i64, vtt: bool) Allocator.Error![]const u8 {
    const t: u64 = @intCast(value);
    return std.fmt.allocPrint(gpa, "{d:0>2}:{d:0>2}:{d:0>2}{c}{d:0>3}", .{
        t / 3600000,                    t / 60000 % 60, t / 1000 % 60,
        @as(u8, if (vtt) '.' else ','), t % 1000,
    });
}
fn assTime(gpa: Allocator, value: i64) Allocator.Error![]const u8 {
    const c: u64 = @intCast(@divFloor(value + 5, 10));
    return std.fmt.allocPrint(gpa, "{d}:{d:0>2}:{d:0>2}.{d:0>2}", .{
        c / 360000, c / 6000 % 60, c / 100 % 60, c % 100,
    });
}
fn decimal(gpa: Allocator, value: i64) Allocator.Error![]const u8 {
    const v: u64 = @intCast(value);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>2}", .{ v / 100, v % 100 });
}
fn split(gpa: Allocator, text: []const u8, delimiter: u8, skip_empty: bool) Allocator.Error!Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, text, delimiter);
    while (parts.next()) |part| {
        if (!skip_empty or part.len > 0) try result.append(gpa, part);
    }
    return result.items;
}
fn words(gpa: Allocator, lines: []const []const u8) Allocator.Error!Strings {
    var result: std.ArrayList([]const u8) = .empty;
    for (lines) |line| try result.appendSlice(gpa, try split(gpa, line, ' ', true));
    return result.items;
}
fn wrap(gpa: Allocator, lines: []const []const u8, width: usize) Allocator.Error!Strings {
    var result: std.ArrayList([]const u8) = .empty;
    for (try words(gpa, lines)) |word| {
        if (result.items.len > 0 and result.items[result.items.len - 1].len + 1 + word.len <= width) {
            const last = result.items.len - 1;
            result.items[last] = try std.fmt.allocPrint(gpa, "{s} {s}", .{ result.items[last], word });
        } else try result.append(gpa, word);
    }
    return result.items;
}
fn sameLines(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (!std.mem.eql(u8, x, y)) return false;
    }
    return true;
}
fn normalized(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    return std.mem.join(gpa, " ", try split(gpa, text, ' ', true));
}

fn remainderLess(remainders: []const i64, a: usize, b: usize) bool {
    return remainders[a] > remainders[b];
}

const Cue = struct {
    index: i64,
    start: i64,
    end: i64,
    text: Strings,
    fn duration(self: Cue) i64 {
        return self.end - self.start;
    }
    fn characters(self: Cue) i64 {
        var count: i64 = 0;
        for (self.text) |line| count += @intCast(line.len);
        return count;
    }
    fn dialogue(self: Cue) bool {
        for (self.text) |line| {
            if (std.mem.startsWith(u8, line, "- ")) return true;
        }
        return false;
    }
};
const format_tags = [_][]const u8{ "<i>", "</i>", "<b>", "</b>", "<u>", "</u>" };
const ass_tags = [_][]const u8{ "{\\i1}", "{\\i0}", "{\\b1}", "{\\b0}", "{\\u1}", "{\\u0}" };
const Markup = struct { len: usize, kind: enum { format, font, position, ordinary }, detail: usize = 0 };
fn markup(line: []const u8, p: usize) Markup {
    const tail = line[p..];
    for (format_tags, 0..) |tag, i| {
        if (std.mem.startsWith(u8, tail, tag)) return .{ .len = tag.len, .kind = .format, .detail = i };
    }
    if (std.mem.startsWith(u8, tail, "</font>")) return .{ .len = 7, .kind = .font };
    if (std.mem.startsWith(u8, tail, "<font") and tail.len > 5 and (tail[5] == ' ' or tail[5] == '>')) {
        if (std.mem.findScalar(u8, tail[5..], '>')) |end| return .{ .len = end + 6, .kind = .font };
    }
    if (tail.len >= 6 and std.mem.startsWith(u8, tail, "{\\an") and
        tail[4] >= '1' and tail[4] <= '9' and tail[5] == '}')
        return .{ .len = 6, .kind = .position, .detail = tail[4] - '0' };
    return .{ .len = 1, .kind = .ordinary };
}

const Op = enum {
    LIST,
    VALIDATE,
    SEARCH,
    AT,
    GAPS,
    STATS,
    PRINT,
    TOVTT,
    TOASS,
    FRAMES,
    SHIFT,
    SHIFTFROM,
    SCALE,
    SYNC,
    SNAP,
    FIXOVERLAP,
    EXTEND,
    TIME,
    SORT,
    RENUMBER,
    MERGE,
    SPLIT,
    INSERT,
    DELETE,
    TEXT,
    BALANCE,
    STRIP,
    CLEANHI,
    REPLACE,
    UNDO,
};
const Kind = enum { position, time, gap, minimum, width, scale, signed, fps, string, text, replacement };
const Arg = struct {
    number: i64 = 0,
    string: []const u8 = "",
    lines: Strings = &.{},
    a: i64 = 0,
    b: i64 = 1,
};
const Command = struct {
    op: Op,
    args: [4]Arg = .{ .{}, .{}, .{}, .{} },
    count: usize = 0,
    fn n(self: Command, i: usize) i64 {
        return self.args[i].number;
    }
    fn p(self: Command, i: usize) usize {
        return @intCast(self.n(i) - 1);
    }
};
const Record = struct { op: Op, cues: []Cue };

const Editor = struct {
    gpa: Allocator,
    cues: []Cue = &.{},
    history: std.ArrayList(Record) = .empty,
    blocks: usize = 0,
    bad: usize = 0,
    error_buffer: [1024]u8 = undefined,
    error_len: usize = 0,

    fn fail(self: *Editor, message: []const u8) error{BadCommand} {
        @memcpy(self.error_buffer[0..message.len], message);
        self.error_len = message.len;
        return error.BadCommand;
    }
    fn failFmt(self: *Editor, comptime fmt: []const u8, args: anytype) error{BadCommand} {
        const text = std.fmt.bufPrint(&self.error_buffer, fmt, args) catch unreachable;
        self.error_len = text.len;
        return error.BadCommand;
    }
    fn parseCommand(self: *Editor, line: []const u8) Error!Command {
        const fields = try split(self.gpa, line, ' ', false);
        const op = std.meta.stringToEnum(Op, fields[0]) orelse return self.fail("unknown command");
        const schema: []const Kind = switch (op) {
            .SEARCH => &.{.string},
            .AT => &.{.time},
            .GAPS, .FIXOVERLAP, .MERGE => &.{.gap},
            .FRAMES, .SNAP => &.{.fps},
            .SHIFT => &.{.signed},
            .SHIFTFROM => &.{ .position, .signed },
            .SCALE => &.{ .scale, .scale },
            .SYNC => &.{ .position, .time, .position, .time },
            .EXTEND => &.{.minimum},
            .TIME => &.{ .position, .time, .time },
            .SPLIT => &.{.width},
            .INSERT => &.{ .position, .time, .time, .text },
            .DELETE => if (fields.len == 3) &.{ .position, .position } else &.{.position},
            .TEXT => &.{ .position, .text },
            .REPLACE => &.{.replacement},
            else => &.{},
        };
        const string_last = schema.len > 0 and switch (schema[schema.len - 1]) {
            .string, .text, .replacement => true,
            else => false,
        };
        if (fields.len < schema.len + 1 or (!string_last and fields.len != schema.len + 1))
            return self.fail("bad arguments");
        var command = Command{ .op = op, .count = schema.len };
        for (schema, 0..) |kind, i| {
            const raw = if (string_last and i == schema.len - 1)
                try std.mem.join(self.gpa, " ", fields[i + 1 ..])
            else
                fields[i + 1];
            var arg = Arg{};
            switch (kind) {
                .string => arg.string = raw,
                .text, .replacement => {
                    arg.lines = try split(self.gpa, raw, '|', false);
                    for (arg.lines) |part| {
                        if (part.len == 0) return self.fail("bad arguments");
                    }
                    if (kind == .replacement and arg.lines.len != 2) return self.fail("bad arguments");
                },
                .fps => {
                    const parts = try split(self.gpa, raw, '/', false);
                    if (parts.len > 2) return self.fail("bad arguments");
                    arg.a = unsigned(parts[0], 9) orelse return self.fail("bad arguments");
                    arg.b = if (parts.len == 1) 1 else unsigned(parts[1], 9) orelse return self.fail("bad arguments");
                    if (arg.a < 1 or arg.a > 100000 or arg.b < 1 or arg.b > 100000) return self.fail("bad arguments");
                },
                else => {
                    arg.number = if (kind == .time) timeValue(raw) orelse return self.fail("bad arguments") else if (kind == .signed and raw.len > 0 and raw[0] == '-')
                        -(unsigned(raw[1..], 9) orelse return self.fail("bad arguments"))
                    else
                        unsigned(raw, 9) orelse return self.fail("bad arguments");
                    const value = arg.number;
                    if ((kind == .position and value < 1) or (kind == .gap and value > 60000) or
                        (kind == .minimum and (value < 1 or value > 60000)) or
                        (kind == .width and (value < 10 or value > 80)) or
                        (kind == .scale and (value < 1 or value > 100000))) return self.fail("bad arguments");
                },
            }
            command.args[i] = arg;
        }
        if (op == .DELETE and command.count == 2 and command.n(1) < command.n(0)) return self.fail("bad arguments");
        for (schema, 0..) |kind, i| {
            const limit = self.cues.len + @as(usize, if (op == .INSERT) 1 else 0);
            if (kind == .position and command.n(i) > @as(i64, @intCast(limit)))
                return self.failFmt("no cue {d}", .{command.n(i)});
        }
        return command;
    }
    fn load(self: *Editor, block: []const []const u8, out: *std.Io.Writer) Error!void {
        if (block.len == 0) return;
        self.blocks += 1;
        const index = unsigned(block[0], 6);
        var start: ?i64 = null;
        var end: ?i64 = null;
        var load_problem: ?[]const u8 = null;
        if (index == null) load_problem = "index" else if (block.len < 2 or block[1].len != 29 or
            !std.mem.eql(u8, block[1][12..17], " --> ")) load_problem = "time" else {
            start = timeValue(block[1][0..12]);
            end = timeValue(block[1][17..]);
            if (start == null or end == null) load_problem = "time" else if (block.len < 3) load_problem = "no text";
        }
        if (load_problem) |message| {
            self.bad += 1;
            try out.print("BAD CUE {d}: {s}\n", .{ self.blocks, message });
        } else {
            const cues = try self.gpa.alloc(Cue, self.cues.len + 1);
            @memcpy(cues[0..self.cues.len], self.cues);
            cues[self.cues.len] = .{ .index = index.?, .start = start.?, .end = end.?, .text = try self.gpa.dupe([]const u8, block[2..]) };
            self.cues = cues;
        }
    }
    fn snapshot(self: *Editor) Allocator.Error![]Cue {
        const result = try self.gpa.dupe(Cue, self.cues);
        for (result) |*c| c.text = try self.gpa.dupe([]const u8, c.text);
        return result;
    }
    fn listCue(self: *Editor, out: *std.Io.Writer, i: usize) Error!void {
        const c = self.cues[i];
        try out.print("{d} {d} {s} {s} {s}\n", .{ i + 1, c.index, try timeText(self.gpa, c.start, false), try timeText(self.gpa, c.end, false), try std.mem.join(self.gpa, "|", c.text) });
    }
    fn problem(out: *std.Io.Writer, count: *usize, comptime fmt: []const u8, args: anytype) Error!void {
        try out.print(fmt, args);
        try out.writeByte('\n');
        count.* += 1;
    }
    fn execute(self: *Editor, line: []const u8, out: *std.Io.Writer) Error!void {
        const command = try self.parseCommand(line);
        const op = command.op;
        const args = command.args;
        if (op == .SYNC and self.cues[command.p(0)].start == self.cues[command.p(2)].start)
            return self.fail("sync points coincide");
        if (op == .UNDO) {
            if (self.history.items.len == 0) return self.fail("nothing to undo");
            const entry = self.history.pop().?;
            self.cues = entry.cues;
            try out.print("UNDO command={s}\n", .{@tagName(entry.op)});
            return;
        }
        switch (op) {
            .SHIFT, .SHIFTFROM, .SCALE, .SYNC, .SNAP, .FIXOVERLAP, .EXTEND, .TIME, .SORT, .RENUMBER, .MERGE, .SPLIT, .INSERT, .DELETE, .TEXT, .BALANCE, .STRIP, .CLEANHI, .REPLACE => try self.history.append(self.gpa, .{ .op = op, .cues = try self.snapshot() }),
            else => {},
        }
        switch (op) {
            .LIST => for (0..self.cues.len) |i| try self.listCue(out, i),
            .VALIDATE => {
                var problems: usize = 0;
                for (self.cues, 0..) |c, i| {
                    const p = i + 1;
                    const d = c.duration();
                    if (c.index != @as(i64, @intCast(p))) try problem(out, &problems, "cue {d}: index {d} (expected {d})", .{ p, c.index, p });
                    if (d <= 0) try problem(out, &problems, "cue {d}: end not after start", .{p});
                    if (i > 0 and c.start < self.cues[i - 1].end) try problem(out, &problems, "cue {d}: overlaps previous by {d} ms", .{ p, self.cues[i - 1].end - c.start });
                    if (d >= 1 and d < 700) try problem(out, &problems, "cue {d}: too short ({d} ms)", .{ p, d });
                    if (d > 7000) try problem(out, &problems, "cue {d}: too long ({d} ms)", .{ p, d });
                    for (c.text, 0..) |text, j| {
                        if (text.len > 42) try problem(out, &problems, "cue {d}: line {d} too long ({d} chars)", .{ p, j + 1, text.len });
                    }
                    if (c.text.len >= 3) try problem(out, &problems, "cue {d}: too many lines ({d})", .{ p, c.text.len });
                    if (d > 0 and c.characters() * 1000 > 21 * d) try problem(out, &problems, "cue {d}: too fast ({s} cps)", .{ p, try decimal(self.gpa, @divFloor(c.characters() * 100000, d)) });
                }
                try out.print("VALIDATE problems={d}\n", .{problems});
            },
            .SEARCH => {
                var found: usize = 0;
                for (self.cues, 0..) |c, i| {
                    for (c.text) |text| {
                        if (std.mem.find(u8, text, args[0].string) != null) {
                            try out.print("{d} {s} {s}\n", .{ i + 1, try timeText(self.gpa, c.start, false), text });
                            found += 1;
                            break;
                        }
                    }
                }
                try out.print("SEARCH found={d}\n", .{found});
            },
            .AT => {
                var active: usize = 0;
                for (self.cues, 0..) |c, i| {
                    if (c.start <= command.n(0) and command.n(0) < c.end) {
                        try self.listCue(out, i);
                        active += 1;
                    }
                }
                try out.print("AT active={d}\n", .{active});
            },
            .GAPS => {
                var count: usize = 0;
                var i: usize = 0;
                while (i + 1 < self.cues.len) : (i += 1) {
                    const gap = self.cues[i + 1].start - self.cues[i].end;
                    if (gap < command.n(0)) {
                        try out.print("{d} {d} {d}\n", .{ i + 1, i + 2, gap });
                        count += 1;
                    }
                }
                try out.print("GAPS count={d}\n", .{count});
            },
            .STATS => {
                try out.print("STATS cues={d}\n", .{self.cues.len});
                if (self.cues.len == 0) return;
                var total: i64 = 0;
                var chars: i64 = 0;
                var longest: usize = 0;
                var maximum: i64 = -1;
                for (self.cues, 0..) |c, i| {
                    const d = @max(0, c.duration());
                    total += d;
                    if (d > 0) chars += c.characters();
                    if (d > maximum) {
                        maximum = d;
                        longest = i;
                    }
                }
                try out.print("duration total={s} mean={s}\n", .{ try timeText(self.gpa, total, false), try timeText(self.gpa, @divFloor(total, @as(i64, @intCast(self.cues.len))), false) });
                try out.print("speed {s}\n", .{if (total == 0) "-" else try decimal(self.gpa, @divFloor(chars * 100000, total))});
                try out.print("longest cue={d} duration={s}\n", .{ longest + 1, try timeText(self.gpa, maximum, false) });
                if (self.cues.len == 1) try out.writeAll("gap none\n") else {
                    var position: usize = 0;
                    var gap = self.cues[1].start - self.cues[0].end;
                    var i: usize = 1;
                    while (i + 1 < self.cues.len) : (i += 1) {
                        const candidate = self.cues[i + 1].start - self.cues[i].end;
                        if (candidate > gap) {
                            gap = candidate;
                            position = i;
                        }
                    }
                    try out.print("gap cue={d} ms={d}\n", .{ position + 1, gap });
                }
            },
            .PRINT => for (self.cues) |c| {
                try out.print("{d}\n{s} --> {s}\n", .{ c.index, try timeText(self.gpa, c.start, false), try timeText(self.gpa, c.end, false) });
                for (c.text) |text| try out.print("{s}\n", .{text});
                try out.writeByte('\n');
            },
            .TOVTT => {
                try out.writeAll("WEBVTT\n\n");
                for (self.cues) |c| {
                    var lines: std.ArrayList([]const u8) = .empty;
                    var code: usize = 0;
                    for (c.text) |text| {
                        var bytes: std.ArrayList(u8) = .empty;
                        var p: usize = 0;
                        while (p < text.len) {
                            const item = markup(text, p);
                            if (item.kind == .position and code == 0) code = item.detail;
                            if (item.kind == .format) try bytes.appendSlice(self.gpa, text[p .. p + item.len]);
                            if (item.kind == .ordinary) try bytes.appendSlice(self.gpa, switch (text[p]) {
                                '&' => "&amp;",
                                '<' => "&lt;",
                                '>' => "&gt;",
                                else => text[p .. p + 1],
                            });
                            p += item.len;
                        }
                        const converted = std.mem.trim(u8, bytes.items, " ");
                        if (converted.len > 0) try lines.append(self.gpa, converted);
                    }
                    if (lines.items.len == 0) continue;
                    try out.print("{d}\n{s} --> {s}", .{ c.index, try timeText(self.gpa, c.start, true), try timeText(self.gpa, c.end, true) });
                    if (code >= 7) try out.writeAll(" line:0") else if (code >= 4) try out.writeAll(" line:50%");
                    if (code == 1 or code == 4 or code == 7) try out.writeAll(" align:start");
                    if (code == 3 or code == 6 or code == 9) try out.writeAll(" align:end");
                    try out.writeByte('\n');
                    for (lines.items) |text| try out.print("{s}\n", .{text});
                    try out.writeByte('\n');
                }
            },
            .TOASS => {
                try out.writeAll("[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n");
                for (self.cues) |c| {
                    try out.print("Dialogue: 0,{s},{s},Default,,0,0,0,,", .{ try assTime(self.gpa, c.start), try assTime(self.gpa, c.end) });
                    for (c.text, 0..) |text, i| {
                        if (i > 0) try out.writeAll("\\N");
                        var p: usize = 0;
                        while (p < text.len) {
                            const item = markup(text, p);
                            if (item.kind == .format) try out.writeAll(ass_tags[item.detail]) else if (item.kind != .font)
                                try out.writeAll(text[p .. p + item.len]);
                            p += item.len;
                        }
                    }
                    try out.writeByte('\n');
                }
            },
            .FRAMES => for (self.cues, 0..) |c, i| {
                try out.print("{d} {d} {d}\n", .{ i + 1, @divFloor(c.start * args[0].a, 1000 * args[0].b), @divFloor(c.end * args[0].a, 1000 * args[0].b) });
            },
            .SHIFT, .SHIFTFROM, .SCALE, .SYNC, .SNAP => {
                const first = if (op == .SHIFTFROM) command.p(0) else 0;
                var clamped: usize = 0;
                var changed: usize = 0;
                const s1 = if (op == .SYNC) self.cues[command.p(0)].start else 0;
                const s2 = if (op == .SYNC) self.cues[command.p(2)].start else 0;
                for (self.cues[first..]) |*c| {
                    var clamp = false;
                    const before = [_]i64{ c.start, c.end };
                    var after: [2]i64 = undefined;
                    for (before, 0..) |t, i| {
                        var value: i64 = switch (op) {
                            .SCALE => roundRatio(t * command.n(0), command.n(1)),
                            .SYNC => roundRatio(command.n(1) * (s2 - s1) + (t - s1) * (command.n(3) - command.n(1)), s2 - s1),
                            .SNAP => roundRatio(roundRatio(t * args[0].a, 1000 * args[0].b) * 1000 * args[0].b, args[0].a),
                            else => t + command.n(if (op == .SHIFT) 0 else 1),
                        };
                        if (value < 0) {
                            value = 0;
                            clamp = true;
                        }
                        if (value != t) changed += 1;
                        after[i] = value;
                    }
                    c.start = after[0];
                    c.end = after[1];
                    if (clamp) clamped += 1;
                }
                if (op == .SNAP) try out.print("SNAP changed={d}\n", .{changed}) else if (op == .SCALE)
                    try out.print("SCALE cues={d}\n", .{self.cues.len})
                else
                    try out.print("{s} cues={d} clamped={d}\n", .{ @tagName(op), self.cues.len - first, clamped });
            },
            .FIXOVERLAP => {
                var fixed: usize = 0;
                var failed: usize = 0;
                var i: usize = 0;
                while (i + 1 < self.cues.len) : (i += 1) {
                    const candidate = self.cues[i + 1].start - command.n(0);
                    if (self.cues[i].end > candidate) {
                        if (candidate > self.cues[i].start) {
                            self.cues[i].end = candidate;
                            fixed += 1;
                        } else {
                            try out.print("cue {d}: cannot fix\n", .{i + 1});
                            failed += 1;
                        }
                    }
                }
                try out.print("FIXOVERLAP fixed={d} failed={d}\n", .{ fixed, failed });
            },
            .EXTEND => {
                var extended: usize = 0;
                var short: usize = 0;
                for (self.cues, 0..) |*c, i| {
                    if (c.duration() < command.n(0)) {
                        var candidate = c.start + command.n(0);
                        if (i + 1 < self.cues.len) candidate = @min(candidate, self.cues[i + 1].start);
                        if (candidate > c.end) {
                            c.end = candidate;
                            extended += 1;
                        }
                    }
                    if (c.duration() < command.n(0)) short += 1;
                }
                try out.print("EXTEND extended={d} short={d}\n", .{ extended, short });
            },
            .TIME => {
                self.cues[command.p(0)].start = command.n(1);
                self.cues[command.p(0)].end = command.n(2);
                try out.print("TIME cue={d}\n", .{command.n(0)});
            },
            .SORT => {
                const Entry = struct {
                    cue: Cue,
                    position: usize,

                    fn less(_: void, a: @This(), b: @This()) bool {
                        return if (a.cue.start != b.cue.start) a.cue.start < b.cue.start else a.cue.end < b.cue.end;
                    }
                };
                const ordered = try self.gpa.alloc(Entry, self.cues.len);
                for (self.cues, 0..) |c, i|
                    ordered[i] = .{ .cue = c, .position = i };
                std.mem.sort(Entry, ordered, {}, Entry.less);
                var moved: usize = 0;
                for (ordered, 0..) |entry, i| {
                    if (entry.position != i) moved += 1;
                    self.cues[i] = entry.cue;
                }
                try out.print("SORT moved={d}\n", .{moved});
            },
            .RENUMBER => {
                var changed: usize = 0;
                for (self.cues, 0..) |*c, i| {
                    if (c.index != @as(i64, @intCast(i + 1))) {
                        c.index = @intCast(i + 1);
                        changed += 1;
                    }
                }
                try out.print("RENUMBER changed={d}\n", .{changed});
            },
            .MERGE => {
                var result: std.ArrayList(Cue) = .empty;
                var merged: usize = 0;
                for (self.cues) |b| {
                    if (result.items.len > 0) {
                        const a = &result.items[result.items.len - 1];
                        const combined = try std.mem.concat(self.gpa, []const u8, &.{ a.text, b.text });
                        const wrapped = try wrap(self.gpa, combined, 42);
                        if (b.start - a.end < command.n(0) and !a.dialogue() and !b.dialogue() and wrapped.len <= 2) {
                            a.end = @max(a.end, b.end);
                            a.text = wrapped;
                            merged += 1;
                            continue;
                        }
                    }
                    try result.append(self.gpa, b);
                }
                self.cues = result.items;
                try out.print("MERGE merged={d} cues={d}\n", .{ merged, self.cues.len });
            },
            .SPLIT => {
                var result: std.ArrayList(Cue) = .empty;
                var count: usize = 0;
                for (self.cues) |original| {
                    var c = original;
                    if (c.duration() < 1 or c.dialogue()) {
                        try result.append(self.gpa, c);
                        continue;
                    }
                    const lines = try wrap(self.gpa, c.text, @intCast(command.n(0)));
                    if (lines.len <= 2) {
                        c.text = lines;
                        try result.append(self.gpa, c);
                        continue;
                    }
                    count += 1;
                    const len = (lines.len + 1) / 2;
                    const counts = try self.gpa.alloc(i64, len);
                    const times = try self.gpa.alloc(i64, len);
                    const order = try self.gpa.alloc(usize, len);
                    const remainders = try self.gpa.alloc(i64, len);
                    var total: i64 = 0;
                    for (0..len) |i| {
                        counts[i] = 0;
                        for (lines[i * 2 .. @min(i * 2 + 2, lines.len)]) |text| counts[i] += @intCast(text.len);
                        total += counts[i];
                        order[i] = i;
                    }
                    var allotted: i64 = 0;
                    for (0..len) |i| {
                        const share = c.duration() * counts[i];
                        times[i] = @divFloor(share, total);
                        remainders[i] = @mod(share, total);
                        allotted += times[i];
                    }
                    std.mem.sort(usize, order, @as([]const i64, remainders), remainderLess);
                    for (0..@as(usize, @intCast(c.duration() - allotted))) |i| times[order[i]] += 1;
                    var start = c.start;
                    for (0..len) |i| {
                        try result.append(self.gpa, .{ .index = c.index, .start = start, .end = start + times[i], .text = lines[i * 2 .. @min(i * 2 + 2, lines.len)] });
                        start += times[i];
                    }
                }
                self.cues = result.items;
                try out.print("SPLIT split={d} cues={d}\n", .{ count, self.cues.len });
            },
            .INSERT => {
                const p = command.p(0);
                const result = try self.gpa.alloc(Cue, self.cues.len + 1);
                @memcpy(result[0..p], self.cues[0..p]);
                result[p] = .{ .index = command.n(0), .start = command.n(1), .end = command.n(2), .text = args[3].lines };
                @memcpy(result[p + 1 ..], self.cues[p..]);
                self.cues = result;
                try out.print("INSERT cue={d} cues={d}\n", .{ command.n(0), self.cues.len });
            },
            .DELETE => {
                const first = command.p(0);
                const end = if (command.count == 2) command.p(1) + 1 else first + 1;
                const result = try self.gpa.alloc(Cue, self.cues.len - (end - first));
                @memcpy(result[0..first], self.cues[0..first]);
                @memcpy(result[first..], self.cues[end..]);
                self.cues = result;
                try out.print("DELETE removed={d} cues={d}\n", .{ end - first, self.cues.len });
            },
            .TEXT => {
                self.cues[command.p(0)].text = args[1].lines;
                try out.print("TEXT cue={d} lines={d}\n", .{ command.n(0), args[1].lines.len });
            },
            .BALANCE => {
                var changed: usize = 0;
                var skipped: usize = 0;
                var dialogue: usize = 0;
                for (self.cues) |*c| {
                    if (c.dialogue()) {
                        dialogue += 1;
                        continue;
                    }
                    const ws = try words(self.gpa, c.text);
                    const text = try std.mem.join(self.gpa, " ", ws);
                    var candidate: ?Strings = null;
                    if (text.len <= 42) candidate = try self.gpa.dupe([]const u8, &.{text}) else {
                        var best_difference: usize = std.math.maxInt(usize);
                        var best_first: usize = std.math.maxInt(usize);
                        for (1..@max(1, ws.len)) |j| {
                            const left = try std.mem.join(self.gpa, " ", ws[0..j]);
                            const right = try std.mem.join(self.gpa, " ", ws[j..]);
                            const difference = @max(left.len, right.len) - @min(left.len, right.len);
                            if (left.len <= 42 and right.len <= 42 and (difference < best_difference or
                                (difference == best_difference and left.len < best_first)))
                            {
                                best_difference = difference;
                                best_first = left.len;
                                candidate = try self.gpa.dupe([]const u8, &.{ left, right });
                            }
                        }
                    }
                    if (candidate) |lines| {
                        if (!sameLines(c.text, lines)) {
                            c.text = lines;
                            changed += 1;
                        }
                    } else skipped += 1;
                }
                try out.print("BALANCE changed={d} skipped={d} dialogue={d}\n", .{ changed, skipped, dialogue });
            },
            .STRIP, .CLEANHI => {
                var tags: usize = 0;
                var segments: usize = 0;
                var labels: usize = 0;
                var removed_lines: usize = 0;
                var removed_cues: usize = 0;
                var result: std.ArrayList(Cue) = .empty;
                for (self.cues) |original| {
                    var c = original;
                    var lines: std.ArrayList([]const u8) = .empty;
                    for (c.text) |text| {
                        var bytes: std.ArrayList(u8) = .empty;
                        var p: usize = 0;
                        while (p < text.len) {
                            if (op == .STRIP) {
                                const item = markup(text, p);
                                if (item.kind == .ordinary) try bytes.append(self.gpa, text[p]) else tags += 1;
                                p += item.len;
                            } else {
                                const close: u8 = if (text[p] == '[') ']' else if (text[p] == '(') ')' else 0;
                                const offset = if (close == 0) null else std.mem.findScalar(u8, text[p + 1 ..], close);
                                if (offset) |end| {
                                    segments += 1;
                                    p += end + 2;
                                } else {
                                    try bytes.append(self.gpa, text[p]);
                                    p += 1;
                                }
                            }
                        }
                        var line_text = if (op == .STRIP) std.mem.trim(u8, bytes.items, " ") else try normalized(self.gpa, bytes.items);
                        if (op == .CLEANHI) {
                            const dialogue_prefix = std.mem.startsWith(u8, line_text, "- ");
                            const body = if (dialogue_prefix) line_text[2..] else line_text;
                            if (std.mem.findScalar(u8, body, ':')) |colon| {
                                var is_label = colon > 0 and body[0] >= 'A' and body[0] <= 'Z';
                                for (body[0..colon]) |ch| {
                                    if (!((ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == ' ')) is_label = false;
                                }
                                if (is_label) {
                                    line_text = try normalized(self.gpa, try std.fmt.allocPrint(self.gpa, "{s}{s}", .{
                                        @as([]const u8, if (dialogue_prefix) "- " else ""), body[colon + 1 ..],
                                    }));
                                    labels += 1;
                                }
                            }
                        }
                        if (line_text.len == 0 or (op == .CLEANHI and std.mem.eql(u8, line_text, "-"))) removed_lines += 1 else try lines.append(self.gpa, line_text);
                    }
                    if (lines.items.len == 0) removed_cues += 1 else {
                        c.text = lines.items;
                        try result.append(self.gpa, c);
                    }
                }
                self.cues = result.items;
                if (op == .STRIP) try out.print("STRIP tags={d} removed_lines={d} removed_cues={d}\n", .{ tags, removed_lines, removed_cues }) else try out.print("CLEANHI segments={d} labels={d} removed_lines={d} removed_cues={d}\n", .{ segments, labels, removed_lines, removed_cues });
            },
            .REPLACE => {
                const old = args[0].lines[0];
                const replacement = args[0].lines[1];
                var count: usize = 0;
                var changed_cues: usize = 0;
                for (self.cues) |*c| {
                    var changed = false;
                    for (c.text) |*text| {
                        const replacements = std.mem.count(u8, text.*, old);
                        if (replacements > 0) {
                            count += replacements;
                            changed = true;
                            text.* = try std.mem.replaceOwned(u8, self.gpa, text.*, old, replacement);
                        }
                    }
                    if (changed) changed_cues += 1;
                }
                try out.print("REPLACE count={d} cues={d}\n", .{ count, changed_cues });
            },
            .UNDO => unreachable,
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &output.interface;
    var editor = Editor{ .gpa = gpa };
    var block: std.ArrayList([]const u8) = .empty;
    while (true) {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        if (std.mem.eql(u8, line, "###")) {
            try editor.load(block.items, out);
            break;
        }
        if (line.len == 0) {
            try editor.load(block.items, out);
            block = .empty;
        } else try block.append(gpa, line);
    }
    try out.print("LOAD cues={d} bad={d}\n", .{ editor.cues.len, editor.bad });
    const count: usize = @intCast(unsigned((try input.interface.takeDelimiter('\n')).?, 9).?);
    for (0..count) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        editor.execute(line, &draft.writer) catch |err| {
            if (err == error.BadCommand) {
                try out.print("ERROR {s}\n", .{editor.error_buffer[0..editor.error_len]});
                continue;
            }
            return err;
        };
        try out.writeAll(draft.writer.buffered());
    }
    try out.flush();
}
