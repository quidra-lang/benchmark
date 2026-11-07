const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }

pub const Kind = enum {
    string, integer, boolean, enumeration, size, duration, host, path, url, date, list,
    pub fn name(kind: Kind) Text {
        return switch (kind) { .integer => "int", .boolean => "bool", .enumeration => "enum", else => @tagName(kind) };
    }
    fn parse(text: Text) Kind {
        for ([_]Kind{ .string, .integer, .boolean, .enumeration, .size, .duration, .host, .path, .url, .date, .list }) |kind| {
            if (equal(kind.name(), text)) return kind;
        }
        unreachable;
    }
};
pub const Range = struct { lower: Text, upper: Text };
pub const Spec = struct {
    line: usize, pattern: Text, section: Text, key: Text, wildcard: bool, kind: Kind,
    item: Kind = .string, required: bool = false, secret: bool = false, unique: bool = false, fixed: bool = false,
    default: ?Text = null, range: ?Range = null, values: []const Text = &.{}, aliases: []const Text = &.{},
    when: ?Text = null, le: ?Text = null,

    pub fn matches(spec: Spec, section: Text) bool {
        var pattern = std.mem.splitScalar(u8, spec.section, '.');
        var parts = std.mem.splitScalar(u8, section, '.');
        while (pattern.next()) |part| {
            const actual = parts.next() orelse return false;
            if (!equal(part, "*") and !equal(part, actual)) return false;
        }
        return parts.next() == null;
    }
};
fn split(gpa: Allocator, source: Text, delimiter: u8) Allocator.Error![]const Text {
    var result: std.ArrayList(Text) = .empty;
    var parts = std.mem.splitScalar(u8, source, delimiter);
    while (parts.next()) |part| try result.append(gpa, part);
    return result.toOwnedSlice(gpa);
}
pub const Schema = struct {
    specs: []const Spec,
    pub fn parse(gpa: Allocator, source: Text) Allocator.Error!Schema {
        var specs: std.ArrayList(Spec) = .empty;
        var lines = std.mem.splitScalar(u8, source, '\n');
        var number: usize = 0;
        while (lines.next()) |line| {
            number += 1;
            if (std.mem.trim(u8, line, " ").len == 0 or line[0] == '#') continue;
            var words = std.mem.splitScalar(u8, line, ' ');
            const pattern = words.next().?;
            const dot = std.mem.findLast(u8, pattern, ".").?;
            var spec: Spec = .{ .line = number, .pattern = pattern, .section = pattern[0..dot], .key = pattern[dot + 1 ..],
                .wildcard = std.mem.findScalar(u8, pattern, '*') != null, .kind = Kind.parse(words.next().?) };
            while (words.next()) |attribute| {
                const equals = std.mem.findScalar(u8, attribute, '=') orelse attribute.len;
                const name = attribute[0..equals];
                const argument = if (equals < attribute.len) attribute[equals + 1 ..] else "";
                if (equal(name, "required")) spec.required = true
                else if (equal(name, "secret")) spec.secret = true
                else if (equal(name, "unique")) spec.unique = true
                else if (equal(name, "fixed")) spec.fixed = true
                else if (equal(name, "default")) spec.default = argument
                else if (equal(name, "range")) {
                    const dots = std.mem.find(u8, argument, "..").?;
                    spec.range = .{ .lower = argument[0..dots], .upper = argument[dots + 2 ..] };
                } else if (equal(name, "values")) spec.values = try split(gpa, argument, ',')
                else if (equal(name, "alias")) spec.aliases = try split(gpa, argument, ',')
                else if (equal(name, "item")) spec.item = Kind.parse(argument)
                else if (equal(name, "when")) spec.when = argument
                else if (equal(name, "le")) spec.le = argument
                else unreachable;
            }
            try specs.append(gpa, spec);
        }
        return .{ .specs = try specs.toOwnedSlice(gpa) };
    }
    pub fn specFor(schema: Schema, key: Text) ?usize {
        for (schema.specs, 0..) |spec, i| if (!spec.wildcard and equal(spec.pattern, key)) return i;
        const dot = std.mem.findLast(u8, key, ".").?;
        for (schema.specs, 0..) |spec, i| {
            if (spec.wildcard and equal(spec.key, key[dot + 1 ..]) and spec.matches(key[0..dot])) return i;
        }
        return null;
    }
    pub fn targetKeys(schema: Schema, gpa: Allocator, index: usize, sections: []const Text) Allocator.Error![]const Text {
        const spec = schema.specs[index];
        var keys: std.ArrayList(Text) = .empty;
        if (!spec.wildcard) {
            try keys.append(gpa, spec.pattern);
        } else for (sections) |section| {
            if (!spec.matches(section)) continue;
            const key = try std.fmt.allocPrint(gpa, "{s}.{s}", .{ section, spec.key });
            if (schema.specFor(key) == index) try keys.append(gpa, key);
        };
        return keys.toOwnedSlice(gpa);
    }
};
