const std = @import("std");
const lexer = @import("lexer.zig");
const core = @import("main.zig");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const equal = core.equal;

pub fn isName(text: Text) bool {
    if (text.len == 0 or !std.ascii.isLower(text[0])) return false;
    for (text[1..]) |c| if (!std.ascii.isLower(c) and !std.ascii.isDigit(c) and c != '_') return false;
    return true;
}
pub fn isSection(text: Text) bool {
    var parts = std.mem.splitScalar(u8, text, '.');
    while (parts.next()) |part| if (!isName(part)) return false;
    return true;
}
pub const StatementKind = enum { assign, append, unset, inherit, include };
pub const Statement = struct { kind: StatementKind, line: usize, target: Text, value: Text = "" };
pub const Document = struct { statements: []const Statement, diagnostics: []const core.Diagnostic };
const Assigned = struct { key: Text, line: usize };
fn trimmed(gpa: Allocator, segments: []const Text) Allocator.Error![]Text {
    const result = try gpa.dupe(Text, segments);
    result[0] = std.mem.trimStart(u8, result[0], " ");
    result[result.len - 1] = std.mem.trimEnd(u8, result[result.len - 1], " ");
    return result;
}
const Parser = struct {
    gpa: Allocator, name: Text,
    section: ?Text = null, base: ?Text = null,
    assigned: std.ArrayList(Assigned) = .empty,
    statements: std.ArrayList(Statement) = .empty,
    diagnostics: std.ArrayList(core.Diagnostic) = .empty,

    fn report(parser: *Parser, line: usize, code: Text, message: Text) Allocator.Error!void {
        try parser.diagnostics.append(parser.gpa, .{ .origin = .{ .document = parser.name, .line = line }, .code = code, .message = message });
    }
    fn headerError(parser: *Parser, number: usize, message: Text) Allocator.Error!void {
        parser.section = null;
        try parser.report(number, "E_SECTION", message);
    }
    fn header(parser: *Parser, number: usize, segments: []const Text) Allocator.Error!void {
        const text = segments[0];
        if (segments.len != 1 or !std.mem.endsWith(u8, text, "]")) return parser.headerError(number, "invalid section header");
        const inside = text[1 .. text.len - 1];
        const colon = std.mem.findScalar(u8, inside, ':');
        const child = std.mem.trim(u8, inside[0 .. colon orelse inside.len], " ");
        const parent: ?Text = if (colon) |position| std.mem.trim(u8, inside[position + 1 ..], " ") else null;
        const relative = child.len > 0 and child[0] == '.' and isSection(child[1..]);
        if ((!relative and !isSection(child)) or (parent != null and !isSection(parent.?))) return parser.headerError(number, "invalid section header");
        if (relative and parser.base == null) return parser.headerError(number, "relative section without base");
        const section = if (relative) try std.fmt.allocPrint(parser.gpa, "{s}{s}", .{ parser.base.?, child }) else child;
        parser.section = section;
        if (!relative) parser.base = section;
        if (parent) |value| try parser.statements.append(parser.gpa, .{ .kind = .inherit, .line = number, .target = section, .value = value });
    }
    fn directive(parser: *Parser, number: usize, segments: []const Text) Allocator.Error!void {
        var words = std.mem.tokenizeScalar(u8, segments[0], ' ');
        const verb = words.next().?;
        const target = words.next();
        if (segments.len != 1 or target == null or words.next() != null or (!equal(verb, "@include") and !equal(verb, "@unset")) or !isName(target.?)) {
            return parser.report(number, "E_SYNTAX", "invalid directive");
        }
        if (equal(verb, "@include")) {
            try parser.statements.append(parser.gpa, .{ .kind = .include, .line = number, .target = target.? });
        } else if (parser.section) |section| {
            try parser.statements.append(parser.gpa, .{ .kind = .unset, .line = number, .target = try std.fmt.allocPrint(parser.gpa, "{s}.{s}", .{ section, target.? }) });
        } else try parser.report(number, "E_NO_SECTION", "no current section");
    }
    fn assignment(parser: *Parser, number: usize, segments: []const Text) Allocator.Error!void {
        var outside_equals = false;
        for (segments, 0..) |segment, index| {
            if (index % 2 == 0 and std.mem.findScalar(u8, segment, '=') != null) outside_equals = true;
        }
        if (!outside_equals) return parser.report(number, "E_SYNTAX", "invalid line");
        const equals = std.mem.findScalar(u8, segments[0], '=') orelse return parser.report(number, "E_SYNTAX", "invalid key");
        var key = std.mem.trim(u8, segments[0][0..equals], " ");
        const append = std.mem.endsWith(u8, key, "+");
        if (append) key = std.mem.trimEnd(u8, key[0 .. key.len - 1], " ");
        if (!isName(key)) return parser.report(number, "E_SYNTAX", "invalid key");
        const value_segments = try parser.gpa.dupe(Text, segments);
        value_segments[0] = segments[0][equals + 1 ..];
        const parts = try trimmed(parser.gpa, value_segments);
        const value = if (parts.len == 1) parts[0]
            else if (parts.len == 3 and parts[0].len == 0 and parts[2].len == 0) parts[1]
            else return parser.report(number, "E_SYNTAX", "invalid value");
        const section = parser.section orelse return parser.report(number, "E_NO_SECTION", "no current section");
        const full_key = try std.fmt.allocPrint(parser.gpa, "{s}.{s}", .{ section, key });
        if (!append) {
            var previous: ?usize = null;
            for (parser.assigned.items, 0..) |earlier, i| if (equal(earlier.key, full_key)) { previous = i; break; };
            if (previous) |i| {
                try parser.report(number, "W_DUPLICATE", try std.fmt.allocPrint(parser.gpa, "{s} already set at line {d}", .{ full_key, parser.assigned.items[i].line }));
                parser.assigned.items[i].line = number;
            } else try parser.assigned.append(parser.gpa, .{ .key = full_key, .line = number });
        }
        try parser.statements.append(parser.gpa, .{ .kind = if (append) .append else .assign, .line = number, .target = full_key, .value = value });
    }
    fn interpret(parser: *Parser, line: lexer.LogicalLine) Allocator.Error!void {
        if (line.problem) |problem| return parser.report(line.number, problem.code, problem.message);
        const segments = try trimmed(parser.gpa, line.segments);
        const first = segments[0];
        if (segments.len == 1 and first.len == 0) return;
        if (std.mem.startsWith(u8, first, "[")) try parser.header(line.number, segments)
        else if (std.mem.startsWith(u8, first, "@")) try parser.directive(line.number, segments)
        else try parser.assignment(line.number, segments);
    }
};
pub fn parse(gpa: Allocator, name: Text, source: Text) Allocator.Error!Document {
    var parser: Parser = .{ .gpa = gpa, .name = name };
    for (try lexer.logicalLines(gpa, source)) |line| try parser.interpret(line);
    return .{ .statements = try parser.statements.toOwnedSlice(gpa), .diagnostics = try parser.diagnostics.toOwnedSlice(gpa) };
}
