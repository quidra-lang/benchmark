const std = @import("std");
const core = @import("main.zig");
const Kind = @import("schema.zig").Kind;
const Allocator = std.mem.Allocator;
const Text = []const u8;
pub const mask: Text = "********";

pub fn stringNotation(gpa: Allocator, text: Text) Allocator.Error!Text {
    var result: std.ArrayList(u8) = .empty;
    try result.append(gpa, '"');
    for (text) |c| {
        const escaped: ?Text = switch (c) { '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\t' => "\\t", else => null };
        if (escaped) |part| try result.appendSlice(gpa, part) else try result.append(gpa, c);
    }
    try result.append(gpa, '"');
    return result.toOwnedSlice(gpa);
}
pub fn valueNotation(gpa: Allocator, kind: Kind, item: Kind, value: core.Value) Allocator.Error!Text {
    return switch (value) {
        .text => |text| if (kind == .string) try stringNotation(gpa, text) else text,
        .integer => |n| try std.fmt.allocPrint(gpa, "{d}", .{n}),
        .boolean => |b| if (b) "true" else "false",
        .list => |values| list: {
            var notations: std.ArrayList(Text) = .empty;
            for (values) |element| try notations.append(gpa, try valueNotation(gpa, item, .string, element));
            break :list try std.fmt.allocPrint(gpa, "[{s}]", .{try std.mem.join(gpa, ", ", notations.items)});
        },
    };
}
pub fn shown(out: core.OutputKey) Text { return if (out.secret) mask else out.notation; }
fn add(gpa: Allocator, lines: *std.ArrayList(Text), comptime format: Text, args: anytype) Allocator.Error!void {
    try lines.append(gpa, try std.fmt.allocPrint(gpa, format, args));
}
fn normalized(gpa: Allocator, profile: *const core.Profile) Allocator.Error!Text {
    var lines: std.ArrayList(Text) = .empty;
    try add(gpa, &lines, "profile {s}", .{profile.name});
    var current: Text = "";
    for (profile.outputs.items) |out| {
        const section = core.sectionOf(out.key);
        if (!core.equal(current, section)) { try add(gpa, &lines, "[{s}]", .{section}); current = section; }
        try add(gpa, &lines, "{s} = {s}", .{ core.nameOf(out.key), shown(out) });
    }
    return std.mem.join(gpa, "\n", lines.items);
}
fn diagnostics(gpa: Allocator, profile: *const core.Profile) Allocator.Error!Text {
    var lines: std.ArrayList(Text) = .empty;
    try add(gpa, &lines, "profile {s} errors {d} warnings {d}", .{ profile.name, profile.errors, profile.warnings });
    for (profile.diagnostics.items) |d| try add(gpa, &lines, "{s}:{d} {s} {s}", .{ d.origin.document, d.origin.line, d.code, d.message });
    return std.mem.join(gpa, "\n", lines.items);
}
fn report(gpa: Allocator, profile: *const core.Profile) Allocator.Error!Text {
    var lines: std.ArrayList(Text) = .empty;
    try add(gpa, &lines, "profile {s}", .{profile.name});
    try lines.append(gpa, "includes");
    for (profile.tree.items) |entry| {
        const indent = try gpa.alloc(u8, 2 + 2 * entry.depth);
        @memset(indent, ' ');
        try add(gpa, &lines, "{s}{s}", .{ indent, entry.text });
    }
    try lines.append(gpa, "overridden");
    if (profile.overridden.items.len == 0) try lines.append(gpa, "  (none)");
    for (profile.overridden.items) |history| {
        var origins: std.ArrayList(Text) = .empty;
        for (history.origins) |origin| try origins.append(gpa, try origin.text(gpa));
        try add(gpa, &lines, "  {s}: {s}", .{ history.key, try std.mem.join(gpa, " -> ", origins.items) });
    }
    try add(gpa, &lines, "keys {d} documents {d} manifest {d} defaults {d}", .{ profile.outputs.items.len, profile.document_keys, profile.manifest_keys, profile.default_keys });
    try add(gpa, &lines, "dropped {d}", .{profile.dropped});
    try add(gpa, &lines, "errors {d} warnings {d}", .{ profile.errors, profile.warnings });
    return std.mem.join(gpa, "\n", lines.items);
}
fn difference(gpa: Allocator, diff: core.Difference) Allocator.Error!Text {
    var lines: std.ArrayList(Text) = .empty;
    try add(gpa, &lines, "diff {s} -> {s}: {d} added, {d} removed, {d} changed", .{ diff.first, diff.second, diff.added, diff.removed, diff.changed });
    for (diff.entries) |entry| {
        if (entry.before == null) try add(gpa, &lines, "+ {s} = {s}", .{ entry.key, entry.after.? })
        else if (entry.after == null) try add(gpa, &lines, "- {s} = {s}", .{ entry.key, entry.before.? })
        else try add(gpa, &lines, "~ {s}: {s} -> {s}", .{ entry.key, entry.before.?, entry.after.? });
    }
    return std.mem.join(gpa, "\n", lines.items);
}
fn write(gpa: Allocator, io: std.Io, path: Text, blocks: []const Text) !void {
    const text = try std.fmt.allocPrint(gpa, "{s}\n", .{try std.mem.join(gpa, "\n\n", blocks)});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text });
}
pub fn writeOutputs(gpa: Allocator, io: std.Io, profiles: []const core.Profile, diffs: []const core.Difference) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var configs: std.ArrayList(Text) = .empty;
    var problems: std.ArrayList(Text) = .empty;
    var reports: std.ArrayList(Text) = .empty;
    var differences: std.ArrayList(Text) = .empty;
    for (profiles) |*profile| {
        try configs.append(gpa, try normalized(gpa, profile));
        try problems.append(gpa, try diagnostics(gpa, profile));
        try reports.append(gpa, try report(gpa, profile));
    }
    for (diffs) |diff| try differences.append(gpa, try difference(gpa, diff));
    try write(gpa, io, "output/normalized.txt", configs.items);
    try write(gpa, io, "output/diagnostics.txt", problems.items);
    try write(gpa, io, "output/report.txt", reports.items);
    try write(gpa, io, "output/diff.txt", differences.items);
}
