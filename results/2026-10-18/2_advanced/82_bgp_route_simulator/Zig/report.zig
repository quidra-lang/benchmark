const std = @import("std");
const t = @import("topology.zig");
const p = @import("policy.zig");
const d = @import("decision.zig");
pub fn pathText(path: []const usize, network: *const t.Topology) []const u8 {
    var out: t.Text = .{};
    for (path, 0..) |owner, i| out.add("{s}{d}", .{ if (i == 0) "" else ",", network.ases[owner].number });
    return out.value();
}
pub fn attributeText(attribute: *const d.Attribute, network: *const t.Topology) []const u8 {
    return t.fmt("path {s} origin {s} med {d} comm {s}", .{ pathText(attribute.path, network),
         t.origin_names[@intFromEnum(attribute.origin)], attribute.med, p.communitiesText(attribute.communities) });
}
pub fn routeText(route: ?d.Route, network: *const t.Topology) []const u8 {
    const r = route orelse return "NONE";
    const a = r.attribute;
    if (r.local()) return t.fmt("LOCAL origin {s} comm {s}", .{ t.origin_names[@intFromEnum(a.origin)],
         p.communitiesText(a.communities) });
    return t.fmt("next {d} path {s} link {s} lp {d} med {d} origin {s} comm {s}", .{ network.ases[r.neighbor()].number,
         pathText(a.path, network), network.links[r.link.?].name, r.local_pref, a.med, t.origin_names[@intFromEnum(a.origin)],
         p.communitiesText(a.communities) });
}
pub fn write(io: std.Io, filename: []const u8, lines: t.Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: t.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = t.fmt("output/{s}", .{filename}), .data = out.value() });
}
