const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const max_records = 2000;
const max_path = 802;

const Query = enum {
    SUMMARY,
    MALFORMED,
    STATUS,
    METHODS,
    TOP,
    HOURLY,
    TIMELINE,
    BANDWIDTH,
    VISITORS,
    LATENCY,
    HISTOGRAM,
    APDEX,
    ERRORS,
    SLOWEST,
    SESSIONS,
    BURST,
    PEAK,
    GAPS,
    IP,
    RANGE,
    FILTER,
    UNFILTER,
    RESET,
    STATE,
};
const Argument = enum {
    limit,
    minutes,
    width,
    threshold,
    length,
    times,
    kind,
    path,
    ip,
    date,
    clock,
    key,
    subject,
    value,
};
const GroupKey = enum { path, ip, method, date, endpoint };
const RankMode = enum { count, apdex, errors, slowest };
const methods = [_][]const u8{ "GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS" };
const reasons = [_][]const u8{ "fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency" };
const filter_keys = [_][]const u8{ "METHOD", "STATUS", "IP", "PATH" };
const lower_keys = [_][]const u8{ "method", "status", "ip", "path" };

fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn indexOf(value: []const u8, choices: []const []const u8) ?usize {
    for (choices, 0..) |choice, i| if (same(value, choice)) return i;
    return null;
}

fn integer(value: usize) i64 {
    return @intCast(value);
}

fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}

fn words(text: []const u8, storage: *[101][]const u8) []const []const u8 {
    var iter = std.mem.tokenizeScalar(u8, text, ' ');
    var count: usize = 0;
    while (iter.next()) |word| {
        storage[count] = word;
        count += 1;
    }
    return storage[0..count];
}

fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (c < '0' or c > '9') return false;
    return true;
}

fn canonical(text: []const u8, maximum: usize) bool {
    return text.len > 0 and text.len <= maximum and digits(text) and
        (text.len == 1 or text[0] != '0');
}

fn leap(year: i64) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

fn monthDays(year: i64, month: i64) i64 {
    const days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    return if (month == 2 and leap(year)) 29 else days[@intCast(month - 1)];
}

fn validDate(text: []const u8) bool {
    if (text.len != 10 or text[4] != '-' or text[7] != '-') return false;
    if (!digits(text[0..4]) or !digits(text[5..7]) or !digits(text[8..10])) return false;
    const year = number(text[0..4]);
    const month = number(text[5..7]);
    const day = number(text[8..10]);
    return year >= 2000 and year <= 2059 and month >= 1 and month <= 12 and
        day >= 1 and day <= monthDays(year, month);
}

fn validClock(text: []const u8) bool {
    if (text.len != 8 or text[2] != ':' or text[5] != ':') return false;
    return digits(text[0..2]) and digits(text[3..5]) and digits(text[6..8]) and
        number(text[0..2]) < 24 and number(text[3..5]) < 60 and number(text[6..8]) < 60;
}

fn parseIp(text: []const u8) ?u32 {
    var iter = std.mem.splitScalar(u8, text, '.');
    var count: usize = 0;
    var result: u32 = 0;
    while (iter.next()) |part| {
        if (count == 4 or !canonical(part, 3) or number(part) > 255) return null;
        result = (result << 8) | @as(u32, @intCast(number(part)));
        count += 1;
    }
    return if (count == 4) result else null;
}

fn validStatus(text: []const u8) bool {
    return text.len == 3 and digits(text) and number(text) >= 100 and number(text) <= 599;
}

fn statusClass(text: []const u8) bool {
    return text.len == 3 and text[0] >= '1' and text[0] <= '5' and same(text[1..], "xx");
}

fn statusMatches(pattern: []const u8, status: i64) bool {
    return if (statusClass(pattern)) @divTrunc(status, 100) == pattern[0] - '0' else status == number(pattern);
}

fn filterValue(key: []const u8, value: []const u8) bool {
    const index = indexOf(key, &filter_keys) orelse return false;
    return switch (index) {
        0 => indexOf(value, &methods) != null,
        1 => validStatus(value) or statusClass(value),
        2 => parseIp(value) != null,
        3 => std.mem.startsWith(u8, value, "/"),
        else => unreachable,
    };
}

fn argumentError(kind: Argument, value: []const u8, args: []const []const u8) ?[]const u8 {
    switch (kind) {
        .limit, .minutes, .width, .threshold, .length, .times => {
            const maximum: i64 = switch (kind) {
                .limit => 100,
                .minutes => 1440,
                .width, .threshold => 100000,
                .length => 86400,
                .times => 1000,
                else => unreachable,
            };
            if (!canonical(value, 6) or number(value) < 1 or number(value) > maximum)
                return "invalid number";
        },
        .kind => if (!same(value, "PATHS") and !same(value, "IPS")) return "invalid kind",
        .path => if (!std.mem.startsWith(u8, value, "/")) return "invalid path",
        .ip => if (parseIp(value) == null) return "invalid ip",
        .date => if (!validDate(value)) return "invalid timestamp",
        .clock => if (!validClock(value)) return "invalid timestamp",
        .key => if (indexOf(value, &filter_keys) == null) return "invalid key",
        .subject => if (indexOf(value, &filter_keys) == null and !same(value, "RANGE")) return "invalid key",
        .value => if (!filterValue(args[0], value)) return "invalid value",
    }
    return null;
}

fn queryForm(query: Query) []const Argument {
    return switch (query) {
        .TOP => &.{ .kind, .limit },
        .TIMELINE => &.{.minutes},
        .LATENCY => &.{.path},
        .HISTOGRAM => &.{.width},
        .APDEX => &.{.threshold},
        .SLOWEST => &.{.limit},
        .SESSIONS => &.{ .ip, .minutes },
        .BURST => &.{ .length, .times },
        .PEAK, .GAPS => &.{.length},
        .IP => &.{.ip},
        .RANGE => &.{ .date, .clock, .date, .clock },
        .FILTER => &.{ .key, .value },
        .UNFILTER => &.{.subject},
        else => &.{},
    };
}

fn requiresRecords(query: Query) bool {
    return switch (query) {
        .STATUS, .METHODS, .TOP, .HOURLY, .TIMELINE, .BANDWIDTH, .VISITORS, .HISTOGRAM, .APDEX, .ERRORS, .SLOWEST, .BURST, .PEAK, .GAPS => true,
        else => false,
    };
}

fn malformedReason(fields: []const []const u8) ?usize {
    if (fields.len != 8) return 0;
    if (!validDate(fields[0])) return 1;
    if (!validClock(fields[1])) return 2;
    if (parseIp(fields[2]) == null) return 3;
    if (indexOf(fields[3], &methods) == null) return 4;
    if (!std.mem.startsWith(u8, fields[4], "/")) return 5;
    if (!validStatus(fields[5])) return 6;
    if (!canonical(fields[6], 8)) return 7;
    if (!canonical(fields[7], 6)) return 8;
    return null;
}

fn secondsOf(date: []const u8, clock: []const u8) i64 {
    const year = number(date[0..4]);
    const month = number(date[5..7]);
    var days = number(date[8..10]) - 1;
    var y: i64 = 2000;
    while (y < year) : (y += 1) days += if (leap(y)) @as(i64, 366) else 365;
    var m: i64 = 1;
    while (m < month) : (m += 1) days += monthDays(year, m);
    return days * 86400 + number(clock[0..2]) * 3600 + number(clock[3..5]) * 60 + number(clock[6..8]);
}

fn intervalLabel(allocator: Allocator, seconds: i64) ![]const u8 {
    var days = @divTrunc(seconds, 86400);
    const minutes = @divTrunc(@mod(seconds, 86400), 60);
    var year: i64 = 2000;
    while (days >= (if (leap(year)) @as(i64, 366) else 365)) : (year += 1)
        days -= if (leap(year)) @as(i64, 366) else 365;
    var month: i64 = 1;
    while (days >= monthDays(year, month)) : (month += 1) days -= monthDays(year, month);
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{ year, month, days + 1, @divTrunc(minutes, 60), @mod(minutes, 60) });
}

fn normalizePath(allocator: Allocator, raw: []const u8) ![]const u8 {
    const end = std.mem.indexOfScalar(u8, raw, '?') orelse raw.len;
    var parts: [101][]const u8 = undefined;
    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, raw[0..end], '/');
    while (iter.next()) |part| {
        if (same(part, "..")) {
            if (count > 0) count -= 1;
        } else if (part.len > 0 and !same(part, ".")) {
            parts[count] = part;
            count += 1;
        }
    }
    for (parts[0..count]) |*part| {
        if (digits(part.*)) {
            part.* = "{id}";
        } else if (part.len >= 8) {
            var hex = true;
            var has_digit = false;
            for (part.*) |c| {
                const digit = c >= '0' and c <= '9';
                hex = hex and (digit or (c >= 'a' and c <= 'f'));
                has_digit = has_digit or digit;
            }
            if (hex and has_digit) part.* = "{hex}";
        }
    }
    const joined = try std.mem.join(allocator, "/", parts[0..count]);
    return std.fmt.allocPrint(allocator, "/{s}", .{joined});
}

fn decimal(allocator: Allocator, numerator: i64, denominator: i64, comptime places: usize) ![]const u8 {
    const scale: i64 = switch (places) {
        1 => 10,
        2 => 100,
        3 => 1000,
        else => @compileError("unsupported decimal width"),
    };
    const value = @divTrunc(numerator * scale, denominator);
    const format = "{d}.{d:0>" ++ std.fmt.comptimePrint("{d}", .{places}) ++ "}";
    return std.fmt.allocPrint(allocator, format, .{ @divTrunc(value, scale), @mod(value, scale) });
}

fn percentage(allocator: Allocator, part: i64, total: i64) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}%", .{try decimal(allocator, part * 100, total, 2)});
}

fn bytesText(allocator: Allocator, bytes: i64) ![]const u8 {
    if (bytes < 1024) return std.fmt.allocPrint(allocator, "{d}B", .{bytes});
    const unit: i64 = if (bytes >= 1073741824) 1073741824 else if (bytes >= 1048576) 1048576 else 1024;
    const label: []const u8 = if (unit == 1073741824) "GB" else if (unit == 1048576) "MB" else "KB";
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ try decimal(allocator, bytes, unit, 1), label });
}

fn barLine(out: *Writer, label: []const u8, count: usize, maximum: usize) !void {
    try out.print("{s} {d}", .{ label, count });
    if (count > 0) {
        try out.writeByte(' ');
        const width = (count * 30 + maximum - 1) / maximum;
        for (0..width) |_| try out.writeByte('#');
    }
    try out.writeByte('\n');
}

const Record = struct {
    line: usize,
    date: []const u8,
    stamp: []const u8,
    ip: []const u8,
    method: []const u8,
    path: []const u8,
    ip_number: u32,
    hour: usize,
    seconds: i64,
    status: i64,
    bytes: i64,
    latency: i64,
};
const Rows = []const *const Record;

fn chronological(_: void, a: Record, b: Record) bool {
    return if (a.seconds != b.seconds) a.seconds < b.seconds else a.line < b.line;
}

fn keyText(row: *const Record, kind: GroupKey) []const u8 {
    return switch (kind) {
        .ip => row.ip,
        .method => row.method,
        .date => row.date,
        .path, .endpoint => row.path,
    };
}

fn keyOrder(a: *const Record, b: *const Record, kind: GroupKey) std.math.Order {
    if (kind == .ip) return std.math.order(a.ip_number, b.ip_number);
    const order = std.mem.order(u8, keyText(a, kind), keyText(b, kind));
    if (order != .eq or kind != .endpoint) return order;
    return std.mem.order(u8, a.method, b.method);
}

fn rowLess(kind: GroupKey, a: *const Record, b: *const Record) bool {
    const order = keyOrder(a, b, kind);
    return if (order != .eq) order == .lt else chronological({}, a.*, b.*);
}

const Stats = struct {
    count: i64 = 0,
    bytes: i64 = 0,
    latency: i64 = 0,
    maximum: i64 = 0,
    client: i64 = 0,
    server: i64 = 0,
    satisfied: i64 = 0,
    tolerating: i64 = 0,

    fn of(rows: Rows, threshold: i64) Stats {
        var result = Stats{ .count = integer(rows.len) };
        for (rows) |row| {
            result.bytes += row.bytes;
            result.latency += row.latency;
            result.maximum = @max(result.maximum, row.latency);
            result.client += @intFromBool(@divTrunc(row.status, 100) == 4);
            result.server += @intFromBool(@divTrunc(row.status, 100) == 5);
            if (row.status < 500) {
                result.satisfied += @intFromBool(row.latency <= threshold);
                result.tolerating += @intFromBool(row.latency > threshold and row.latency <= threshold * 4);
            }
        }
        return result;
    }

    fn points(self: Stats) i64 {
        return 2 * self.satisfied + self.tolerating;
    }

    fn rating(self: Stats) []const u8 {
        const value = 100 * self.points();
        const total = 2 * self.count;
        return if (value >= 94 * total) "excellent" else if (value >= 85 * total) "good" else if (value >= 70 * total) "fair" else if (value >= 50 * total) "poor" else "unacceptable";
    }
};

const Group = struct { rows: Rows, stats: Stats };

fn grouped(allocator: Allocator, rows: Rows, kind: GroupKey, threshold: i64) ![]Group {
    const ordered = try allocator.dupe(*const Record, rows);
    std.mem.sort(*const Record, ordered, kind, rowLess);
    const groups = try allocator.alloc(Group, rows.len);
    var first: usize = 0;
    var count: usize = 0;
    while (first < ordered.len) {
        var end = first + 1;
        while (end < ordered.len and keyOrder(ordered[first], ordered[end], kind) == .eq) : (end += 1) {}
        const members = ordered[first..end];
        groups[count] = .{ .rows = members, .stats = Stats.of(members, threshold) };
        count += 1;
        first = end;
    }
    return groups[0..count];
}

fn distinctCount(allocator: Allocator, rows: Rows, kind: GroupKey) !usize {
    const ordered = try allocator.dupe(*const Record, rows);
    std.mem.sort(*const Record, ordered, kind, rowLess);
    var result: usize = 0;
    for (ordered, 0..) |row, i| {
        if (i == 0 or keyOrder(ordered[i - 1], row, kind) != .eq) result += 1;
    }
    return result;
}

const Rank = struct { mode: RankMode, key: GroupKey };

fn groupLess(rank: Rank, a: Group, b: Group) bool {
    const x = a.stats;
    const y = b.stats;
    var difference: i64 = 0;
    switch (rank.mode) {
        .count => difference = y.count - x.count,
        .apdex => {
            difference = x.points() * y.count - y.points() * x.count;
            if (difference == 0) difference = y.count - x.count;
        },
        .errors => {
            difference = (y.client + y.server) * x.count - (x.client + x.server) * y.count;
            if (difference == 0) difference = y.client + y.server - x.client - x.server;
        },
        .slowest => {
            difference = y.latency * x.count - x.latency * y.count;
            if (difference == 0) difference = y.maximum - x.maximum;
        },
    }
    return if (difference != 0) difference < 0 else keyOrder(a.rows[0], b.rows[0], rank.key) == .lt;
}

const Window = struct { count: usize, first: *const Record, last: *const Record };

fn peak(rows: Rows, width: i64) Window {
    var result = Window{ .count = 0, .first = rows[0], .last = rows[0] };
    var first: usize = 0;
    for (rows, 0..) |row, last| {
        while (row.seconds - rows[first].seconds >= width) first += 1;
        if (last - first + 1 > result.count)
            result = .{ .count = last - first + 1, .first = rows[first], .last = row };
    }
    return result;
}

fn windowLess(_: void, a: Window, b: Window) bool {
    return if (a.count != b.count) a.count > b.count else a.first.ip_number < b.first.ip_number;
}

fn latencyLess(_: void, a: i64, b: i64) bool {
    return a < b;
}

fn ipRows(allocator: Allocator, rows: Rows, address: []const u8) !Rows {
    const found = try allocator.alloc(*const Record, rows.len);
    var count: usize = 0;
    for (rows) |row| if (same(row.ip, address)) {
        found[count] = row;
        count += 1;
    };
    return found[0..count];
}

const DateRange = struct { first: i64, last: i64, first_label: [19]u8, last_label: [19]u8 };
const BadLine = struct { number: usize, reason: usize };

const Analyzer = struct {
    records: [max_records]Record = undefined,
    record_count: usize = 0,
    malformed: [max_records]BadLine = undefined,
    malformed_count: usize = 0,
    line_count: usize = 0,
    filters: [4][max_path]u8 = undefined,
    filter_lengths: [4]usize = @splat(0),
    range: ?DateRange = null,

    fn ingest(self: *Analyzer, allocator: Allocator, input: []const u8) !void {
        self.line_count += 1;
        const line = try allocator.dupe(u8, input);
        var storage: [101][]const u8 = undefined;
        const fields = words(line, &storage);
        if (malformedReason(fields)) |reason| {
            self.malformed[self.malformed_count] = .{ .number = self.line_count, .reason = reason };
            self.malformed_count += 1;
            return;
        }
        self.records[self.record_count] = .{
            .line = self.line_count,
            .date = fields[0],
            .stamp = try std.fmt.allocPrint(allocator, "{s} {s}", .{ fields[0], fields[1] }),
            .ip = fields[2],
            .method = fields[3],
            .path = try normalizePath(allocator, fields[4]),
            .ip_number = parseIp(fields[2]).?,
            .hour = @intCast(number(fields[1][0..2])),
            .seconds = secondsOf(fields[0], fields[1]),
            .status = number(fields[5]),
            .bytes = number(fields[6]),
            .latency = number(fields[7]),
        };
        self.record_count += 1;
    }

    fn filter(self: *const Analyzer, index: usize) []const u8 {
        return self.filters[index][0..self.filter_lengths[index]];
    }

    fn selected(self: *const Analyzer, allocator: Allocator) !Rows {
        const result = try allocator.alloc(*const Record, self.record_count);
        var count: usize = 0;
        for (self.records[0..self.record_count]) |*row| {
            if (self.range) |range| {
                if (row.seconds < range.first or row.seconds > range.last) continue;
            }
            if (self.filter_lengths[0] > 0 and !same(row.method, self.filter(0))) continue;
            if (self.filter_lengths[1] > 0 and !statusMatches(self.filter(1), row.status)) continue;
            if (self.filter_lengths[2] > 0 and !same(row.ip, self.filter(2))) continue;
            if (self.filter_lengths[3] > 0 and !same(row.path, self.filter(3))) continue;
            result[count] = row;
            count += 1;
        }
        return result[0..count];
    }

    fn execute(self: *Analyzer, allocator: Allocator, line: []const u8, out: *Writer) !void {
        var storage: [101][]const u8 = undefined;
        const fields = words(line, &storage);
        const name = if (fields.len == 0) "" else fields[0];
        const query = std.meta.stringToEnum(Query, name) orelse {
            try out.writeAll("ERROR unknown query\n");
            return;
        };
        const args = fields[1..];
        const form = queryForm(query);
        const minimum = form.len - @as(usize, @intFromBool(query == .LATENCY or query == .SESSIONS));
        if (args.len < minimum or args.len > form.len) {
            try out.writeAll("ERROR wrong arguments\n");
            return;
        }
        for (args, 0..) |arg, i| if (argumentError(form[i], arg, args)) |reason| {
            try out.print("ERROR {s}\n", .{reason});
            return;
        };
        const rows = try self.selected(allocator);
        if (rows.len == 0 and requiresRecords(query)) {
            try out.print("{s} no records\n", .{name});
            return;
        }
        try self.run(allocator, query, args, rows, out);
    }

    fn run(self: *Analyzer, allocator: Allocator, query: Query, args: []const []const u8, rows: Rows, out: *Writer) !void {
        const n = integer(rows.len);
        switch (query) {
            .SUMMARY => {
                const total = Stats.of(rows, 0);
                try out.print("SUMMARY lines {d} valid {d} malformed {d}\n", .{ self.line_count, self.record_count, self.malformed_count });
                try out.print("requests {d} bytes {d} ips {d} paths {d}\n", .{ n, total.bytes, try distinctCount(allocator, rows, .ip), try distinctCount(allocator, rows, .path) });
                if (rows.len == 0) try out.writeAll("span none\n") else try out.print("span {s} {s} {d}\n", .{ rows[0].stamp, rows[rows.len - 1].stamp, rows[rows.len - 1].seconds - rows[0].seconds });
            },
            .MALFORMED => {
                try out.print("MALFORMED {d}\n", .{self.malformed_count});
                for (reasons, 0..) |reason, index| {
                    var count: usize = 0;
                    for (self.malformed[0..self.malformed_count]) |bad| if (bad.reason == index) {
                        count += 1;
                    };
                    if (count == 0) continue;
                    try out.print("{s} {d}", .{ reason, count });
                    for (self.malformed[0..self.malformed_count]) |bad| if (bad.reason == index)
                        try out.print(" {d}", .{bad.number});
                    try out.writeByte('\n');
                }
            },
            .STATUS => {
                var classes: [5]i64 = @splat(0);
                var statuses: [600]i64 = @splat(0);
                for (rows) |row| {
                    classes[@intCast(@divTrunc(row.status, 100) - 1)] += 1;
                    statuses[@intCast(row.status)] += 1;
                }
                try out.print("STATUS {d}\n", .{n});
                for (classes, 1..) |count, category|
                    try out.print("{d}xx {d} {s}\n", .{ category, count, try percentage(allocator, count, n) });
                for (statuses, 0..) |count, status| if (count > 0)
                    try out.print("{d} {d} {s}\n", .{ status, count, try percentage(allocator, count, n) });
            },
            .METHODS, .TOP => {
                const kind: GroupKey = if (query == .METHODS) .method else if (same(args[0], "IPS")) .ip else .path;
                const groups = try grouped(allocator, rows, kind, 0);
                std.mem.sort(Group, groups, Rank{ .mode = .count, .key = kind }, groupLess);
                const limit = if (query == .METHODS) groups.len else @min(@as(usize, @intCast(number(args[1]))), groups.len);
                if (query == .METHODS) try out.print("METHODS {d}\n", .{n}) else try out.print("TOP {s} {d} of {d}\n", .{ args[0], limit, groups.len });
                var rank: usize = 0;
                for (groups[0..limit], 0..) |group, i| {
                    if (i == 0 or group.stats.count != groups[i - 1].stats.count) rank = i + 1;
                    if (query == .TOP) try out.print("{d} ", .{rank});
                    try out.print("{s} {d} {s}\n", .{ keyText(group.rows[0], kind), group.stats.count, try percentage(allocator, group.stats.count, n) });
                }
            },
            .HOURLY => {
                var counts: [24]usize = @splat(0);
                for (rows) |row| counts[row.hour] += 1;
                const maximum = std.mem.max(usize, &counts);
                const first = std.mem.indexOfScalar(usize, &counts, maximum).?;
                try out.print("HOURLY {d} peak {d:0>2} {d}\n", .{ n, first, maximum });
                for (counts, 0..) |count, hour|
                    try barLine(out, try std.fmt.allocPrint(allocator, "{d:0>2}", .{hour}), count, maximum);
            },
            .TIMELINE, .HISTOGRAM => {
                const parameter = number(args[0]);
                const width = if (query == .TIMELINE) parameter * 60 else parameter;
                const values = try allocator.alloc(i64, rows.len);
                for (rows, 0..) |row, i| values[i] = @divTrunc(if (query == .TIMELINE) row.seconds else row.latency, width);
                const low = std.mem.min(i64, values);
                const high = std.mem.max(i64, values);
                if (high - low + 1 > 60) {
                    try out.writeAll("ERROR too many buckets\n");
                    return;
                }
                var buffer: [60]usize = @splat(0);
                const counts = buffer[0..@as(usize, @intCast(high - low + 1))];
                for (values) |value| counts[@intCast(value - low)] += 1;
                const maximum = std.mem.max(usize, counts);
                try out.print("{s} {d} {d}\n", .{ @tagName(query), parameter, counts.len });
                for (counts, 0..) |count, i| {
                    const start = (low + integer(i)) * width;
                    const label = if (query == .TIMELINE) try intervalLabel(allocator, start) else try std.fmt.allocPrint(allocator, "{d}-{d}", .{ start, start + width - 1 });
                    try barLine(out, label, count, maximum);
                }
            },
            .BANDWIDTH => {
                const groups = try grouped(allocator, rows, .date, 0);
                const total = Stats.of(rows, 0);
                try out.print("BANDWIDTH {d} {d} {s}\n", .{ groups.len, total.bytes, try bytesText(allocator, total.bytes) });
                for (groups) |group| try out.print("{s} {d} {d} {s}\n", .{
                    group.rows[0].date, group.stats.count, group.stats.bytes, try bytesText(allocator, group.stats.bytes),
                });
            },
            .VISITORS => {
                const days = try grouped(allocator, rows, .date, 0);
                const ips = try grouped(allocator, rows, .ip, 0);
                try out.print("VISITORS {d} {d}\n", .{ days.len, ips.len });
                for (days) |day| {
                    const unique = try distinctCount(allocator, day.rows, .ip);
                    var fresh: usize = 0;
                    for (ips) |ip| if (same(ip.rows[0].date, day.rows[0].date)) {
                        fresh += 1;
                    };
                    try out.print("{s} unique {d} new {d} returning {d}\n", .{ day.rows[0].date, unique, fresh, unique - fresh });
                }
            },
            .LATENCY => {
                const label = if (args.len == 0) "all" else try normalizePath(allocator, args[0]);
                const buffer = try allocator.alloc(i64, rows.len);
                var count: usize = 0;
                for (rows) |row| if (args.len == 0 or same(row.path, label)) {
                    buffer[count] = row.latency;
                    count += 1;
                };
                if (count == 0) {
                    try out.writeAll("LATENCY no records\n");
                    return;
                }
                const values = buffer[0..count];
                std.mem.sort(i64, values, {}, latencyLess);
                const trim = count / 10;
                var total: i64 = 0;
                var trimmed: i64 = 0;
                for (values, 0..) |value, i| {
                    total += value;
                    if (i >= trim and i < count - trim) trimmed += value;
                }
                try out.print("LATENCY {s} count {d} min {d} p50 {d} p90 {d} p99 {d} max {d} mean {s} trimmed {s}\n", .{
                    label,                               count,             values[0],                                        values[(50 * count + 99) / 100 - 1],                           values[(90 * count + 99) / 100 - 1],
                    values[(99 * count + 99) / 100 - 1], values[count - 1], try decimal(allocator, total, integer(count), 2), try decimal(allocator, trimmed, integer(count - 2 * trim), 2),
                });
            },
            .APDEX => {
                const threshold = number(args[0]);
                const total = Stats.of(rows, threshold);
                try out.print("APDEX {d} {s} {s} satisfied {d} tolerating {d} frustrated {d}\n", .{
                    threshold,       try decimal(allocator, total.points(), 2 * n, 3), total.rating(),
                    total.satisfied, total.tolerating,                                 n - total.satisfied - total.tolerating,
                });
                const groups = try grouped(allocator, rows, .path, threshold);
                std.mem.sort(Group, groups, Rank{ .mode = .apdex, .key = .path }, groupLess);
                for (groups) |group| try out.print("{s} {s} {s} {d}\n", .{
                    group.rows[0].path, try decimal(allocator, group.stats.points(), 2 * group.stats.count, 3), group.stats.rating(), group.stats.count,
                });
            },
            .ERRORS => {
                const total = Stats.of(rows, 0);
                const failed = total.client + total.server;
                try out.print("ERRORS {d} of {d} {s}\n", .{ failed, n, try percentage(allocator, failed, n) });
                const groups = try grouped(allocator, rows, .path, 0);
                std.mem.sort(Group, groups, Rank{ .mode = .errors, .key = .path }, groupLess);
                for (groups) |group| {
                    const stats = group.stats;
                    if (stats.client + stats.server == 0) continue;
                    try out.print("{s} {d} {d} {d} {s}\n", .{ group.rows[0].path, stats.count, stats.client, stats.server, try percentage(allocator, stats.client + stats.server, stats.count) });
                }
            },
            .SLOWEST => {
                const groups = try grouped(allocator, rows, .endpoint, 0);
                std.mem.sort(Group, groups, Rank{ .mode = .slowest, .key = .endpoint }, groupLess);
                const limit = @min(@as(usize, @intCast(number(args[0]))), groups.len);
                try out.print("SLOWEST {d} of {d}\n", .{ limit, groups.len });
                for (groups[0..limit], 1..) |group, rank|
                    try out.print("{d} {s} {s} count {d} avg {s} max {d}\n", .{ rank, group.rows[0].method, group.rows[0].path, group.stats.count, try decimal(allocator, group.stats.latency, group.stats.count, 2), group.stats.maximum });
            },
            .SESSIONS => {
                const found = try ipRows(allocator, rows, args[0]);
                if (found.len == 0) {
                    try out.writeAll("SESSIONS no records\n");
                    return;
                }
                const minutes = if (args.len == 2) number(args[1]) else 30;
                const starts = try allocator.alloc(usize, found.len + 1);
                starts[0] = 0;
                var count: usize = 1;
                for (1..found.len) |i| if (found[i].seconds - found[i - 1].seconds > minutes * 60) {
                    starts[count] = i;
                    count += 1;
                };
                starts[count] = found.len;
                var duration: i64 = 0;
                for (0..count) |i| duration += found[starts[i + 1] - 1].seconds - found[starts[i]].seconds;
                try out.print("SESSIONS {s} timeout {d} count {d} requests {d} avg_duration {s} avg_requests {s}\n", .{
                    args[0],                                                       minutes, count, found.len, try decimal(allocator, duration, integer(count), 1),
                    try decimal(allocator, integer(found.len), integer(count), 1),
                });
                for (0..count) |i| {
                    const session = found[starts[i]..starts[i + 1]];
                    const first = session[0];
                    const last = session[session.len - 1];
                    try out.print("{d} {s} {s} {d} {d} {d}\n", .{ i + 1, first.stamp, last.stamp, last.seconds - first.seconds, session.len, try distinctCount(allocator, session, .path) });
                }
            },
            .BURST => {
                const width = number(args[0]);
                const threshold = number(args[1]);
                const failed = try allocator.alloc(*const Record, rows.len);
                var failure_count: usize = 0;
                for (rows) |row| if (row.status >= 400) {
                    failed[failure_count] = row;
                    failure_count += 1;
                };
                const groups = try grouped(allocator, failed[0..failure_count], .ip, 0);
                const buffer = try allocator.alloc(Window, groups.len);
                var count: usize = 0;
                for (groups) |group| {
                    const window = peak(group.rows, width);
                    if (integer(window.count) >= threshold) {
                        buffer[count] = window;
                        count += 1;
                    }
                }
                const matches = buffer[0..count];
                std.mem.sort(Window, matches, {}, windowLess);
                try out.print("BURST {d} {d} {d}\n", .{ width, threshold, count });
                for (matches) |window| try out.print("{s} {d} {s} {s}\n", .{ window.first.ip, window.count, window.first.stamp, window.last.stamp });
            },
            .PEAK => {
                const width = number(args[0]);
                const window = peak(rows, width);
                try out.print("PEAK {d} {d} {s} {s}\n", .{ width, window.count, window.first.stamp, window.last.stamp });
            },
            .GAPS => {
                const width = number(args[0]);
                var count: usize = 0;
                for (1..rows.len) |i| if (rows[i].seconds - rows[i - 1].seconds >= width) {
                    count += 1;
                };
                try out.print("GAPS {d} {d}\n", .{ width, count });
                for (1..rows.len) |i| if (rows[i].seconds - rows[i - 1].seconds >= width)
                    try out.print("{s} {s} {d}\n", .{ rows[i - 1].stamp, rows[i].stamp, rows[i].seconds - rows[i - 1].seconds });
            },
            .IP => {
                const found = try ipRows(allocator, rows, args[0]);
                if (found.len == 0) {
                    try out.writeAll("IP no records\n");
                    return;
                }
                const total = Stats.of(found, 0);
                try out.print("IP {s} requests {d} bytes {d} errors {d} paths {d}\n", .{
                    args[0], found.len, total.bytes, total.client + total.server, try distinctCount(allocator, found, .path),
                });
                try out.print("first {s} last {s}\nmethods", .{ found[0].stamp, found[found.len - 1].stamp });
                const method_groups = try grouped(allocator, found, .method, 0);
                std.mem.sort(Group, method_groups, Rank{ .mode = .count, .key = .method }, groupLess);
                for (method_groups) |group| try out.print(" {s} {d}", .{ group.rows[0].method, group.stats.count });
                try out.writeAll("\nclasses");
                var classes: [5]usize = @splat(0);
                for (found) |row| classes[@intCast(@divTrunc(row.status, 100) - 1)] += 1;
                for (classes, 1..) |count, category| try out.print(" {d}xx {d}", .{ category, count });
                try out.writeByte('\n');
                const path_groups = try grouped(allocator, found, .path, 0);
                std.mem.sort(Group, path_groups, Rank{ .mode = .count, .key = .path }, groupLess);
                for (path_groups[0..@min(3, path_groups.len)]) |group|
                    try out.print("path {s} {d}\n", .{ group.rows[0].path, group.stats.count });
            },
            .RANGE => {
                const first = secondsOf(args[0], args[1]);
                const last = secondsOf(args[2], args[3]);
                if (first > last) {
                    try out.writeAll("ERROR invalid range\n");
                    return;
                }
                var range = DateRange{ .first = first, .last = last, .first_label = undefined, .last_label = undefined };
                _ = try std.fmt.bufPrint(&range.first_label, "{s} {s}", .{ args[0], args[1] });
                _ = try std.fmt.bufPrint(&range.last_label, "{s} {s}", .{ args[2], args[3] });
                self.range = range;
                try out.print("RANGE {s} {s} active {d}\n", .{ range.first_label, range.last_label, (try self.selected(allocator)).len });
            },
            .FILTER => {
                const key = indexOf(args[0], &filter_keys).?;
                const value = if (key == 3) try normalizePath(allocator, args[1]) else args[1];
                std.mem.copyForwards(u8, self.filters[key][0..value.len], value);
                self.filter_lengths[key] = value.len;
                try out.print("FILTER {s} {s} active {d}\n", .{ args[0], value, (try self.selected(allocator)).len });
            },
            .UNFILTER => {
                if (same(args[0], "RANGE")) {
                    if (self.range == null) {
                        try out.writeAll("ERROR not filtered\n");
                        return;
                    }
                    self.range = null;
                } else {
                    const key = indexOf(args[0], &filter_keys).?;
                    if (self.filter_lengths[key] == 0) {
                        try out.writeAll("ERROR not filtered\n");
                        return;
                    }
                    self.filter_lengths[key] = 0;
                }
                try out.print("UNFILTER {s} active {d}\n", .{ args[0], (try self.selected(allocator)).len });
            },
            .RESET => {
                self.range = null;
                self.filter_lengths = @splat(0);
                try out.print("RESET active {d}\n", .{(try self.selected(allocator)).len});
            },
            .STATE => {
                try out.print("STATE active {d} range ", .{n});
                if (self.range) |range| try out.print("{s} {s}", .{ range.first_label, range.last_label }) else try out.writeByte('-');
                for (lower_keys, 0..) |label, key|
                    try out.print(" {s} {s}", .{ label, if (self.filter_lengths[key] == 0) "-" else self.filter(key) });
                try out.writeByte('\n');
            },
        }
    }
};

pub fn main(init: std.process.Init) !void {
    var persistent = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer persistent.deinit();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &output.interface;
    var analyzer = Analyzer{};
    var queries = false;
    while (try input.interface.takeDelimiter('\n')) |line| {
        if (!queries) {
            if (same(line, "---")) {
                queries = true;
                std.mem.sort(Record, analyzer.records[0..analyzer.record_count], {}, chronological);
            } else try analyzer.ingest(persistent.allocator(), line);
        } else {
            if (same(line, "END")) break;
            var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer scratch.deinit();
            try analyzer.execute(scratch.allocator(), line, out);
        }
    }
    try out.flush();
}
