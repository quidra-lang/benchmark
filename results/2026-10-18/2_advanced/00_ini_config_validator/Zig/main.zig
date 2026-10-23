const std = @import("std");
const parser = @import("ini_parser.zig");
const interpolation = @import("interpolate.zig");
const schemas = @import("schema.zig");
const emitter = @import("emitter.zig");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Kind = schemas.Kind;
const Spec = schemas.Spec;
const Schema = schemas.Schema;

pub fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
pub fn sectionOf(key: Text) Text { return key[0..std.mem.findLast(u8, key, ".").?]; }
pub fn nameOf(key: Text) Text { return key[std.mem.findLast(u8, key, ".").? + 1 ..]; }
pub fn lessKey(_: void, a: Text, b: Text) bool {
    const order = std.mem.order(u8, sectionOf(a), sectionOf(b));
    return if (order == .eq) std.mem.order(u8, nameOf(a), nameOf(b)) == .lt else order == .lt;
}
fn textIndex(items: []const Text, text: Text) ?usize {
    for (items, 0..) |item, i| if (equal(item, text)) return i;
    return null;
}
pub const Origin = struct {
    document: Text, line: usize,
    pub fn text(origin: Origin, gpa: Allocator) Allocator.Error!Text {
        return std.fmt.allocPrint(gpa, "{s}:{d}", .{ origin.document, origin.line });
    }
    fn same(a: Origin, b: Origin) bool { return a.line == b.line and equal(a.document, b.document); }
};
pub const Diagnostic = struct { origin: Origin, code: Text, message: Text };
fn lessDiagnostic(_: void, a: Diagnostic, b: Diagnostic) bool {
    const document = std.mem.order(u8, a.origin.document, b.origin.document);
    if (document != .eq) return document == .lt;
    if (a.origin.line != b.origin.line) return a.origin.line < b.origin.line;
    const code = std.mem.order(u8, a.code, b.code);
    return if (code == .eq) std.mem.order(u8, a.message, b.message) == .lt else code == .lt;
}
pub const Definition = struct { value: Text, origin: Origin, number: usize, history: []const Origin };
pub const Entry = struct { key: Text, definition: Definition };
pub const Configuration = struct {
    entries: std.ArrayList(Entry) = .empty,
    pub fn index(config: *const Configuration, key: Text) ?usize {
        for (config.entries.items, 0..) |entry, i| if (equal(entry.key, key)) return i;
        return null;
    }
    fn get(config: *const Configuration, key: Text) ?Definition {
        return if (config.index(key)) |i| config.entries.items[i].definition else null;
    }
    fn put(config: *Configuration, gpa: Allocator, key: Text, definition: Definition) Allocator.Error!void {
        if (config.index(key)) |i| config.entries.items[i].definition = definition
        else try config.entries.append(gpa, .{ .key = key, .definition = definition });
    }
    fn remove(config: *Configuration, key: Text) bool {
        const i = config.index(key) orelse return false;
        _ = config.entries.orderedRemove(i);
        return true;
    }
    pub fn orderedKeys(config: *const Configuration, gpa: Allocator) Allocator.Error![]const Text {
        const keys = try gpa.alloc(Text, config.entries.items.len);
        for (config.entries.items, 0..) |entry, i| keys[i] = entry.key;
        std.mem.sort(Text, keys, {}, lessKey);
        return keys;
    }
};
pub const Value = union(enum) { text: Text, integer: i64, boolean: bool, list: []const Value };
pub const OutputKey = struct {
    key: Text, definition: Definition, spec: ?usize, value: Value, notation: Text, secret: bool,
};
const Parent = struct { section: Text, parent: Text, origin: Origin };
pub const TreeLine = struct { depth: usize, text: Text };
pub const History = struct { key: Text, origins: []const Origin };
const NamedDocument = struct { name: Text, document: ?parser.Document };
const Library = struct {
    gpa: Allocator, io: std.Io,
    documents: std.ArrayList(NamedDocument) = .empty,
    fn find(library: *Library, name: Text) !?parser.Document {
        for (library.documents.items) |item| if (equal(item.name, name)) return item.document;
        const path = try std.fmt.allocPrint(library.gpa, "input/conf/{s}.ini", .{name});
        const source = std.Io.Dir.cwd().readFileAlloc(library.io, path, library.gpa, .unlimited) catch |err| switch (err) {
            error.FileNotFound => {
                try library.documents.append(library.gpa, .{ .name = name, .document = null });
                return null;
            },
            else => return err,
        };
        const document = try parser.parse(library.gpa, name, source);
        try library.documents.append(library.gpa, .{ .name = name, .document = document });
        return document;
    }
};

fn digits(text: Text, minimum: usize, maximum: usize) bool {
    if (text.len < minimum or text.len > maximum) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn decimal(text: Text) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn parseInt(text: Text) ?i64 {
    if (text.len == 0) return null;
    const signed = text[0] == '+' or text[0] == '-';
    const number = text[@intFromBool(signed)..];
    const negative = text[0] == '-';
    const value = if (std.mem.startsWith(u8, number, "0x") or std.mem.startsWith(u8, number, "0X")) hexadecimal: {
        const hex_digits = number[2..];
        if (hex_digits.len == 0 or hex_digits.len > 10) return null;
        for (hex_digits) |c| {
            const lower = std.ascii.toLower(c);
            if (!std.ascii.isDigit(c) and (lower < 'a' or lower > 'f')) return null;
        }
        break :hexadecimal std.fmt.parseInt(i64, hex_digits, 16) catch return null;
    } else dec: {
        if (number.len == 0) return null;
        var count: usize = 0;
        var total: i64 = 0;
        for (number, 0..) |c, i| {
            if (c == '_') {
                if (i == 0 or i + 1 == number.len or !std.ascii.isDigit(number[i - 1]) or !std.ascii.isDigit(number[i + 1])) return null;
            } else if (std.ascii.isDigit(c)) {
                count += 1;
                if (count > 12) return null;
                total = total * 10 + c - '0';
            } else return null;
        }
        break :dec total;
    };
    return if (negative) -value else value;
}
fn parseSize(text: Text) ?i64 {
    var start: usize = 0;
    while (start < text.len and (std.ascii.isDigit(text[start]) or text[start] == '.')) : (start += 1) {}
    const unit = text[start..];
    const factor: i64 = if (unit.len == 0 or std.ascii.eqlIgnoreCase(unit, "b")) 1
        else if (std.ascii.eqlIgnoreCase(unit, "kb")) 1024
        else if (std.ascii.eqlIgnoreCase(unit, "mb")) 1048576
        else if (std.ascii.eqlIgnoreCase(unit, "gb")) 1073741824 else return null;
    const number = text[0..start];
    const dot = std.mem.findScalar(u8, number, '.');
    const whole = number[0 .. dot orelse number.len];
    if (!digits(whole, 1, 6)) return null;
    var result = decimal(whole) * factor;
    if (dot) |position| {
        const fraction = number[position + 1 ..];
        if (!digits(fraction, 1, 3)) return null;
        var divisor: i64 = 1;
        for (fraction) |_| divisor *= 10;
        const scaled = decimal(fraction) * factor;
        if (@mod(scaled, divisor) != 0) return null;
        result += @divExact(scaled, divisor);
    }
    return result;
}
fn parseDuration(text: Text) ?i64 {
    if (digits(text, 1, 6)) return decimal(text);
    var position: usize = 0;
    var previous: u8 = 0;
    var result: i64 = 0;
    while (position < text.len) {
        const start = position;
        while (position < text.len and std.ascii.isDigit(text[position])) : (position += 1) {}
        if (!digits(text[start..position], 1, 6) or position == text.len) return null;
        const order: u8, const factor: i64 = switch (text[position]) {
            'h' => .{ 1, 3600 }, 'm' => .{ 2, 60 }, 's' => .{ 3, 1 }, else => return null,
        };
        if (order <= previous) return null;
        previous = order;
        result += decimal(text[start..position]) * factor;
        position += 1;
    }
    return if (previous == 0) null else result;
}
fn parseHost(gpa: Allocator, text: Text) Allocator.Error!?Text {
    var ipv4 = true;
    for (text) |c| if (!std.ascii.isDigit(c) and c != '.') { ipv4 = false; break; };
    var parts = std.mem.splitScalar(u8, text, '.');
    if (ipv4) {
        var count: usize = 0;
        while (parts.next()) |part| {
            count += 1;
            if (!digits(part, 1, 3) or (part.len > 1 and part[0] == '0') or decimal(part) > 255) return null;
        }
        if (count != 4) return null;
        return text;
    }
    if (text.len > 253) return null;
    while (parts.next()) |part| {
        if (part.len == 0 or part.len > 63 or part[0] == '-' or part[part.len - 1] == '-') return null;
        for (part) |c| if (!std.ascii.isAlphanumeric(c) and c != '-') return null;
    }
    const result = try gpa.dupe(u8, text);
    for (result) |*c| c.* = std.ascii.toLower(c.*);
    return result;
}
fn parsePath(gpa: Allocator, text: Text) Allocator.Error!?Text {
    if (text.len == 0 or std.mem.findScalar(u8, text, ' ') != null or std.mem.findScalar(u8, text, '\n') != null or std.mem.findScalar(u8, text, '\t') != null) return null;
    const absolute = text[0] == '/';
    var parts: std.ArrayList(Text) = .empty;
    var input = std.mem.splitScalar(u8, text, '/');
    while (input.next()) |part| {
        if (part.len == 0 or equal(part, ".")) continue;
        if (equal(part, "..")) {
            if (parts.items.len > 0 and !equal(parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
            } else if (absolute) return null
            else try parts.append(gpa, part);
        } else try parts.append(gpa, part);
    }
    const joined = try std.mem.join(gpa, "/", parts.items);
    if (absolute) return try std.fmt.allocPrint(gpa, "/{s}", .{joined});
    return if (joined.len == 0) "." else joined;
}
fn parseUrl(gpa: Allocator, text: Text) Allocator.Error!?Text {
    const separator = std.mem.find(u8, text, "://") orelse return null;
    const scheme = text[0..separator];
    if (scheme.len == 0 or !std.ascii.isAlphabetic(scheme[0])) return null;
    for (scheme) |c| if (!std.ascii.isAlphanumeric(c) and std.mem.findScalar(u8, "+-.", c) == null) return null;
    const rest = text[separator + 3 ..];
    if (std.mem.findScalar(u8, rest, '?') != null or std.mem.findScalar(u8, rest, '#') != null) return null;
    const slash = std.mem.findScalar(u8, rest, '/');
    const authority = rest[0 .. slash orelse rest.len];
    const path = if (slash) |i| rest[i + 1 ..] else "";
    const colon = std.mem.findScalar(u8, authority, ':');
    const host = (try parseHost(gpa, authority[0 .. colon orelse authority.len])) orelse return null;
    const normalized_path = (try parsePath(gpa, try std.fmt.allocPrint(gpa, "/{s}", .{path}))) orelse return null;
    const lower_scheme = try gpa.dupe(u8, scheme);
    for (lower_scheme) |*c| c.* = std.ascii.toLower(c.*);
    var port_part: Text = "";
    if (colon) |i| {
        const port = authority[i + 1 ..];
        if (!digits(port, 1, 5) or port[0] == '0' or decimal(port) > 65535) return null;
        const default = (equal(lower_scheme, "http") and decimal(port) == 80) or (equal(lower_scheme, "https") and decimal(port) == 443);
        if (!default) port_part = try std.fmt.allocPrint(gpa, ":{s}", .{port});
    }
    return try std.fmt.allocPrint(gpa, "{s}://{s}{s}{s}", .{ lower_scheme, host, port_part, normalized_path });
}
fn parseDate(text: Text) ?Text {
    if (text.len != 10 or text[4] != '-' or text[7] != '-' or !digits(text[0..4], 4, 4) or !digits(text[5..7], 2, 2) or !digits(text[8..], 2, 2)) return null;
    const year = decimal(text[0..4]);
    const month = decimal(text[5..7]);
    const day = decimal(text[8..]);
    if (year == 0 or month < 1 or month > 12) return null;
    const month_days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var days = month_days[@intCast(month - 1)];
    if (month == 2 and ((@mod(year, 4) == 0 and @mod(year, 100) != 0) or @mod(year, 400) == 0)) days = 29;
    return if (day >= 1 and day <= days) text else null;
}
fn scalar(gpa: Allocator, kind: Kind, text: Text, choices: []const Text) Allocator.Error!?Value {
    switch (kind) {
        .string => return .{ .text = text },
        .integer => return if (parseInt(text)) |n| .{ .integer = n } else null,
        .size => return if (parseSize(text)) |n| .{ .integer = n } else null,
        .duration => return if (parseDuration(text)) |n| .{ .integer = n } else null,
        .boolean => {
            for ([_]Text{ "true", "yes", "on", "1" }) |word| if (std.ascii.eqlIgnoreCase(text, word)) return .{ .boolean = true };
            for ([_]Text{ "false", "no", "off", "0" }) |word| if (std.ascii.eqlIgnoreCase(text, word)) return .{ .boolean = false };
            return null;
        },
        .enumeration => {
            for (choices) |choice| if (std.ascii.eqlIgnoreCase(text, choice)) return .{ .text = choice };
            return null;
        },
        .host => return if (try parseHost(gpa, text)) |s| .{ .text = s } else null,
        .path => return if (try parsePath(gpa, text)) |s| .{ .text = s } else null,
        .url => return if (try parseUrl(gpa, text)) |s| .{ .text = s } else null,
        .date => return if (parseDate(text)) |s| .{ .text = s } else null,
        .list => unreachable,
    }
}
const Problem = struct { code: Text, message: Text };
const Checked = union(enum) { value: Value, problem: Problem };
fn invalid(gpa: Allocator, key: Text, kind: Kind, choices: []const Text, text: Text, secret: bool, item: bool) Allocator.Error!Problem {
    const checked = if (secret) emitter.mask else try emitter.stringNotation(gpa, text);
    const display = if (item) try std.fmt.allocPrint(gpa, "item {s}", .{checked}) else checked;
    return if (kind == .enumeration)
        .{ .code = "E_ENUM", .message = try std.fmt.allocPrint(gpa, "{s}: {s} is not one of {s}", .{ key, display, try std.mem.join(gpa, ",", choices) }) }
    else .{ .code = "E_TYPE", .message = try std.fmt.allocPrint(gpa, "{s}: {s} is not a valid {s}", .{ key, display, kind.name() }) };
}
fn bound(gpa: Allocator, kind: Kind, text: Text) Allocator.Error!?Value {
    if (text.len == 0) return null;
    if (kind == .string or kind == .list) return .{ .integer = decimal(text) };
    return scalar(gpa, kind, text, &.{});
}
fn lessValue(a: Value, b: Value) bool {
    return switch (a) { .integer => |n| n < b.integer, .text => |s| std.mem.order(u8, s, b.text) == .lt, else => unreachable };
}
fn checkRange(gpa: Allocator, key: Text, spec: Spec, value: Value) Allocator.Error!?Problem {
    const range = spec.range orelse return null;
    const measure: Value = switch (spec.kind) {
        .string => .{ .integer = @intCast(value.text.len) }, .list => .{ .integer = @intCast(value.list.len) }, else => value,
    };
    const lower = try bound(gpa, spec.kind, range.lower);
    const upper = try bound(gpa, spec.kind, range.upper);
    if ((lower != null and lessValue(measure, lower.?)) or (upper != null and lessValue(upper.?, measure))) {
        const display = switch (spec.kind) {
            .string => try std.fmt.allocPrint(gpa, "length {d}", .{measure.integer}),
            .list => try std.fmt.allocPrint(gpa, "count {d}", .{measure.integer}),
            else => if (spec.secret) emitter.mask else try emitter.valueNotation(gpa, spec.kind, spec.item, value),
        };
        const lower_text = if (lower) |v| try emitter.valueNotation(gpa, spec.kind, .string, v) else "";
        const upper_text = if (upper) |v| try emitter.valueNotation(gpa, spec.kind, .string, v) else "";
        return .{ .code = "E_RANGE", .message = try std.fmt.allocPrint(gpa, "{s}: {s} is out of range {s}..{s}", .{ key, display, lower_text, upper_text }) };
    }
    return null;
}

pub const Profile = struct {
    gpa: Allocator, name: Text, root: Text,
    configuration: Configuration = .{}, definitions: usize = 0,
    parents: std.ArrayList(Parent) = .empty,
    tree: std.ArrayList(TreeLine) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    outputs: std.ArrayList(OutputKey) = .empty,
    overridden: std.ArrayList(History) = .empty,
    document_keys: usize = 0, manifest_keys: usize = 0, default_keys: usize = 0,
    dropped: usize = 0, errors: usize = 0, warnings: usize = 0,

    fn report(profile: *Profile, origin: Origin, code: Text, message: Text) Allocator.Error!void {
        for (profile.diagnostics.items) |d| if (d.origin.same(origin) and equal(d.code, code) and equal(d.message, message)) return;
        try profile.diagnostics.append(profile.gpa, .{ .origin = origin, .code = code, .message = message });
    }
    fn define(profile: *Profile, key: Text, value: Text, origin: Origin) Allocator.Error!void {
        profile.definitions += 1;
        var history: std.ArrayList(Origin) = .empty;
        if (profile.configuration.get(key)) |old| try history.appendSlice(profile.gpa, old.history);
        if (history.items.len == 0 or !history.items[history.items.len - 1].same(origin)) try history.append(profile.gpa, origin);
        try profile.configuration.put(profile.gpa, key, .{ .value = value, .origin = origin, .number = profile.definitions, .history = try history.toOwnedSlice(profile.gpa) });
    }
    fn parentIndex(profile: *const Profile, section: Text) ?usize {
        for (profile.parents.items, 0..) |parent, i| if (equal(parent.section, section)) return i;
        return null;
    }
    fn apply(profile: *Profile, library: *Library, name: Text, chain: *std.ArrayList(Text)) anyerror!void {
        const document = (try library.find(name)).?;
        const gpa = profile.gpa;
        try profile.tree.append(gpa, .{ .depth = chain.items.len - 1, .text = name });
        for (document.diagnostics) |d| try profile.report(d.origin, d.code, d.message);
        for (document.statements) |statement| {
            const origin: Origin = .{ .document = name, .line = statement.line };
            switch (statement.kind) {
                .assign => try profile.define(statement.target, statement.value, origin),
                .append => {
                    var value = statement.value;
                    if (profile.configuration.get(statement.target)) |old| {
                        if (old.value.len > 0) value = try std.fmt.allocPrint(gpa, "{s},{s}", .{ old.value, value });
                    }
                    try profile.define(statement.target, value, origin);
                },
                .unset => if (!profile.configuration.remove(statement.target)) {
                    try profile.report(origin, "W_UNSET", try std.fmt.allocPrint(gpa, "{s} is not set", .{statement.target}));
                },
                .inherit => {
                    const parent: Parent = .{ .section = statement.target, .parent = statement.value, .origin = origin };
                    if (profile.parentIndex(statement.target)) |i| profile.parents.items[i] = parent
                    else try profile.parents.append(gpa, parent);
                },
                .include => {
                    const target = statement.target;
                    if (textIndex(chain.items, target)) |start| {
                        var path: std.ArrayList(Text) = .empty;
                        try path.appendSlice(gpa, chain.items[start..]); try path.append(gpa, target);
                        try profile.report(origin, "E_INCLUDE_CYCLE", try std.fmt.allocPrint(gpa, "include cycle {s}", .{try std.mem.join(gpa, " -> ", path.items)}));
                        try profile.tree.append(gpa, .{ .depth = chain.items.len, .text = try std.fmt.allocPrint(gpa, "{s} (cycle)", .{target}) });
                    } else if ((try library.find(target)) == null) {
                        try profile.report(origin, "E_INCLUDE_MISSING", try std.fmt.allocPrint(gpa, "missing document {s}", .{target}));
                        try profile.tree.append(gpa, .{ .depth = chain.items.len, .text = try std.fmt.allocPrint(gpa, "{s} (missing)", .{target}) });
                    } else {
                        try chain.append(gpa, target); try profile.apply(library, target, chain); _ = chain.pop();
                    }
                },
            }
        }
    }
    fn inherit(profile: *Profile) Allocator.Error!void {
        const gpa = profile.gpa;
        const own = try gpa.dupe(Entry, profile.configuration.entries.items);
        for (profile.parents.items) |declaration| {
            var chain: std.ArrayList(Text) = .empty;
            try chain.append(gpa, declaration.section);
            while (profile.parentIndex(chain.items[chain.items.len - 1])) |i| {
                const next = profile.parents.items[i].parent;
                if (textIndex(chain.items, next) != null) break;
                try chain.append(gpa, next);
            }
            if (profile.parentIndex(chain.items[chain.items.len - 1])) |i| {
                try chain.append(gpa, profile.parents.items[i].parent);
                try profile.report(declaration.origin, "E_INHERIT_CYCLE", try std.fmt.allocPrint(gpa, "inheritance cycle {s}", .{try std.mem.join(gpa, " -> ", chain.items)}));
                continue;
            }
            var has_own = false;
            for (own) |entry| if (equal(sectionOf(entry.key), declaration.parent)) { has_own = true; break; };
            if (profile.parentIndex(declaration.parent) == null and !has_own) {
                try profile.report(declaration.origin, "W_PARENT_EMPTY", try std.fmt.allocPrint(gpa, "section {s} inherits from empty section {s}", .{ declaration.section, declaration.parent }));
            }
            for (chain.items[1..]) |ancestor| {
                for (own) |entry| {
                    if (!equal(sectionOf(entry.key), ancestor)) continue;
                    const key = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ declaration.section, nameOf(entry.key) });
                    if (profile.configuration.index(key) == null) try profile.configuration.put(gpa, key, entry.definition);
                }
            }
        }
    }
    fn aliases(profile: *Profile, schema: Schema) Allocator.Error!void {
        const gpa = profile.gpa;
        for (schema.specs) |spec| {
            var candidates: std.ArrayList(Text) = .empty;
            var present_aliases: std.ArrayList(Text) = .empty;
            if (profile.configuration.index(spec.pattern) != null) try candidates.append(gpa, spec.pattern);
            for (spec.aliases) |alias| {
                if (profile.configuration.index(alias) != null) { try candidates.append(gpa, alias); try present_aliases.append(gpa, alias); }
            }
            if (present_aliases.items.len == 0) continue;
            var winner = candidates.items[0];
            for (candidates.items[1..]) |candidate| {
                if (profile.configuration.get(candidate).?.number > profile.configuration.get(winner).?.number) winner = candidate;
            }
            const chosen = profile.configuration.get(winner).?;
            for (candidates.items) |candidate| {
                const origin = profile.configuration.get(candidate).?.origin;
                if (!equal(candidate, spec.pattern)) try profile.report(origin, "W_DEPRECATED", try std.fmt.allocPrint(gpa, "{s} is deprecated, use {s}", .{ candidate, spec.pattern }));
                if (!equal(candidate, winner)) try profile.report(origin, "W_SHADOWED", try std.fmt.allocPrint(gpa, "{s} is superseded by {s} at {s}", .{ candidate, winner, try chosen.origin.text(gpa) }));
            }
            try profile.configuration.put(gpa, spec.pattern, chosen);
            for (present_aliases.items) |alias| _ = profile.configuration.remove(alias);
        }
    }
    fn normalize(profile: *Profile, key: Text, spec: Spec, text: Text, origin: Origin) Allocator.Error!Checked {
        const gpa = profile.gpa;
        const value: Value = if (spec.kind != .list) (try scalar(gpa, spec.kind, text, spec.values)) orelse {
            return .{ .problem = try invalid(gpa, key, spec.kind, spec.values, text, spec.secret, false) };
        } else list: {
            var items: std.ArrayList(Text) = .empty;
            var values: std.ArrayList(Value) = .empty;
            if (std.mem.trim(u8, text, " ").len > 0) {
                var split = std.mem.splitScalar(u8, text, ',');
                var empty = false;
                while (split.next()) |part| {
                    const item = std.mem.trim(u8, part, " ");
                    if (item.len == 0) empty = true else try items.append(gpa, item);
                }
                if (empty) try profile.report(origin, "W_EMPTY_ITEM", try std.fmt.allocPrint(gpa, "{s}: empty list item ignored", .{key}));
                for (items.items) |item| {
                    const parsed = (try scalar(gpa, spec.item, item, spec.values)) orelse {
                        return .{ .problem = try invalid(gpa, key, spec.item, spec.values, item, spec.secret, true) };
                    };
                    try values.append(gpa, parsed);
                }
            }
            if (spec.unique) {
                var seen: std.ArrayList(Text) = .empty;
                var unique: std.ArrayList(Value) = .empty;
                for (values.items) |element| {
                    const notation = try emitter.valueNotation(gpa, spec.item, .string, element);
                    if (textIndex(seen.items, notation) == null) { try seen.append(gpa, notation); try unique.append(gpa, element); }
                }
                if (unique.items.len < values.items.len) try profile.report(origin, "W_DUPLICATE_ITEM", try std.fmt.allocPrint(gpa, "{s}: duplicate items removed", .{key}));
                values = unique;
            }
            break :list .{ .list = try values.toOwnedSlice(gpa) };
        };
        if (try checkRange(gpa, key, spec, value)) |problem| return .{ .problem = problem };
        return .{ .value = value };
    }
    pub fn outputIndex(profile: *const Profile, key: Text) ?usize {
        for (profile.outputs.items, 0..) |out, i| if (equal(out.key, key)) return i;
        return null;
    }
    pub fn output(profile: *const Profile, key: Text) ?OutputKey {
        return if (profile.outputIndex(key)) |i| profile.outputs.items[i] else null;
    }
    fn outputKeys(profile: *const Profile) Allocator.Error![]const Text {
        const keys = try profile.gpa.alloc(Text, profile.outputs.items.len);
        for (profile.outputs.items, 0..) |entry, i| keys[i] = entry.key;
        std.mem.sort(Text, keys, {}, lessKey);
        return keys;
    }
    fn process(profile: *Profile, number: usize, overrides: []const Text, schema: Schema, library: *Library, earlier: []const Profile) !void {
        const gpa = profile.gpa;
        var chain: std.ArrayList(Text) = .empty;
        try chain.append(gpa, profile.root);
        try profile.apply(library, profile.root, &chain);
        for (overrides) |override| {
            const equals = std.mem.findScalar(u8, override, '=').?;
            try profile.define(override[0..equals], override[equals + 1 ..], .{ .document = "manifest", .line = number });
        }
        try profile.inherit(); try profile.aliases(schema);
        var sections: std.ArrayList(Text) = .empty;
        for (profile.configuration.entries.items) |entry| {
            const section = sectionOf(entry.key);
            if (textIndex(sections.items, section) == null) try sections.append(gpa, section);
        }
        std.mem.sort(Text, sections.items, {}, struct { fn less(_: void, a: Text, b: Text) bool { return std.mem.order(u8, a, b) == .lt; } }.less);
        for (schema.specs, 0..) |spec, i| {
            if (spec.default) |default| {
                for (try schema.targetKeys(gpa, i, sections.items)) |key| {
                    if (profile.configuration.index(key) == null) try profile.define(key, default, .{ .document = "schema", .line = spec.line });
                }
            }
        }
        const expansion = try interpolation.expand(gpa, &profile.configuration);
        for (expansion.diagnostics) |d| try profile.report(d.origin, d.code, d.message);
        for (try profile.configuration.orderedKeys(gpa)) |key| {
            const index = profile.configuration.index(key).?;
            const text = expansion.results[index] orelse continue;
            const definition = profile.configuration.entries.items[index].definition;
            const spec_index = schema.specFor(key);
            var kind: Kind = .string;
            var item: Kind = .string;
            var secret = false;
            var value: Value = .{ .text = text };
            if (spec_index) |i| {
                const spec = schema.specs[i]; kind = spec.kind; item = spec.item; secret = spec.secret;
                switch (try profile.normalize(key, spec, text, definition.origin)) {
                    .value => |normalized| value = normalized,
                    .problem => |problem| { try profile.report(definition.origin, problem.code, problem.message); continue; },
                }
            } else try profile.report(definition.origin, "W_UNKNOWN", try std.fmt.allocPrint(gpa, "{s} is not in the schema", .{key}));
            try profile.outputs.append(gpa, .{ .key = key, .definition = definition, .spec = spec_index, .value = value,
                .notation = try emitter.valueNotation(gpa, kind, item, value), .secret = secret });
        }
        var rejected: std.ArrayList(Text) = .empty;
        for (profile.outputs.items) |out| {
            const i = out.spec orelse continue;
            const le = schema.specs[i].le orelse continue;
            const limit_key = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ sectionOf(out.key), le });
            const limit = profile.output(limit_key) orelse continue;
            if (std.meta.activeTag(out.value) == .integer and std.meta.activeTag(limit.value) == .integer and out.value.integer > limit.value.integer) {
                try profile.report(out.definition.origin, "E_ORDER", try std.fmt.allocPrint(gpa, "{s}: {s} is greater than {s} ({s})", .{ out.key, emitter.shown(out), limit_key, emitter.shown(limit) }));
                try rejected.append(gpa, out.key);
            }
        }
        for (rejected.items) |key| _ = profile.outputs.orderedRemove(profile.outputIndex(key).?);
        for (schema.specs, 0..) |spec, i| {
            if (!spec.required) continue;
            for (try schema.targetKeys(gpa, i, sections.items)) |key| {
                if (profile.configuration.index(key) != null) continue;
                const message = if (spec.when) |when| conditional: {
                    const condition_key = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ sectionOf(key), when });
                    const condition = profile.output(condition_key) orelse continue;
                    if (std.meta.activeTag(condition.value) != .boolean or !condition.value.boolean) continue;
                    break :conditional try std.fmt.allocPrint(gpa, "{s} is required when {s} is true", .{ key, condition_key });
                } else try std.fmt.allocPrint(gpa, "{s} is required", .{key});
                try profile.report(.{ .document = profile.root, .line = 0 }, "E_REQUIRED", message);
            }
        }
        for (try profile.outputKeys()) |key| {
            const out = profile.output(key).?;
            if (out.spec == null or !schema.specs[out.spec.?].fixed) continue;
            for (earlier) |*previous| {
                const reference = previous.output(key) orelse continue;
                if (!equal(reference.notation, out.notation)) {
                    try profile.report(out.definition.origin, "E_FIXED", try std.fmt.allocPrint(gpa, "{s}: value differs from profile {s}", .{ key, previous.name }));
                    _ = profile.outputs.orderedRemove(profile.outputIndex(key).?);
                }
                break;
            }
        }
        profile.dropped = profile.configuration.entries.items.len - profile.outputs.items.len;
        std.mem.sort(Diagnostic, profile.diagnostics.items, {}, lessDiagnostic);
        for (profile.diagnostics.items) |d| { if (std.mem.startsWith(u8, d.code, "E_")) profile.errors += 1 else profile.warnings += 1; }
        for (profile.outputs.items) |out| {
            if (out.definition.history.len >= 2) try profile.overridden.append(gpa, .{ .key = out.key, .origins = out.definition.history });
            if (equal(out.definition.origin.document, "manifest")) profile.manifest_keys += 1
            else if (equal(out.definition.origin.document, "schema")) profile.default_keys += 1
            else profile.document_keys += 1;
        }
    }
};
pub const DifferenceEntry = struct { key: Text, before: ?Text, after: ?Text };
pub const Difference = struct { first: Text, second: Text, added: usize = 0, removed: usize = 0, changed: usize = 0, entries: []const DifferenceEntry = &.{} };
fn difference(gpa: Allocator, first: *const Profile, second: *const Profile) Allocator.Error!Difference {
    var diff: Difference = .{ .first = first.name, .second = second.name };
    var keys: std.ArrayList(Text) = .empty;
    for (first.outputs.items) |out| try keys.append(gpa, out.key);
    for (second.outputs.items) |out| if (textIndex(keys.items, out.key) == null) try keys.append(gpa, out.key);
    std.mem.sort(Text, keys.items, {}, lessKey);
    var entries: std.ArrayList(DifferenceEntry) = .empty;
    for (keys.items) |key| {
        const before = first.output(key);
        const after = second.output(key);
        if (before == null) diff.added += 1
        else if (after == null) diff.removed += 1
        else if (!equal(before.?.notation, after.?.notation)) diff.changed += 1
        else continue;
        try entries.append(gpa, .{ .key = key, .before = if (before) |v| emitter.shown(v) else null, .after = if (after) |v| emitter.shown(v) else null });
    }
    diff.entries = try entries.toOwnedSlice(gpa);
    return diff;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const gpa = arena.allocator();
    const schema_source = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/schema.txt", gpa, .unlimited);
    const schema = try Schema.parse(gpa, schema_source);
    const manifest = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/manifest.txt", gpa, .unlimited);
    var library: Library = .{ .gpa = gpa, .io = init.io };
    var profiles: std.ArrayList(Profile) = .empty;
    var lines = std.mem.tokenizeScalar(u8, manifest, '\n');
    var number: usize = 0;
    while (lines.next()) |line| {
        number += 1;
        var words = std.mem.splitScalar(u8, line, ' ');
        var profile: Profile = .{ .gpa = gpa, .name = words.next().?, .root = words.next().? };
        var overrides: std.ArrayList(Text) = .empty;
        while (words.next()) |word| try overrides.append(gpa, word);
        try profile.process(number, overrides.items, schema, &library, profiles.items);
        try profiles.append(gpa, profile);
    }
    var diffs: std.ArrayList(Difference) = .empty;
    for (1..profiles.items.len) |i| try diffs.append(gpa, try difference(gpa, &profiles.items[i - 1], &profiles.items[i]));
    try emitter.writeOutputs(gpa, init.io, profiles.items, diffs.items);
}
