const std = @import("std");
const obj = @import("object_parser.zig");
pub const Member = struct { object: *obj.Object, exports: []const obj.Text, loaded: bool = false };
pub const Archive = struct { name: obj.Text, members: []Member };
pub fn parse(a: std.mem.Allocator, name: obj.Text, text: obj.Text) !Archive {
    const lines = try obj.lines(a, text); var index: usize = 0; var members: std.ArrayList(Member) = .empty;
    while (index < lines.len) {
        var words = std.mem.splitScalar(u8, lines[index], ' '); _ = words.next(); const member = words.next().?; var exports: std.ArrayList(obj.Text) = .empty;
        while (words.next()) |n| try exports.append(a, n); index += 1;
        const object = try obj.parse(a, lines, &index, try std.fmt.allocPrint(a, "{s}({s})", .{name, member}));
        try members.append(a, .{ .object = object, .exports = exports.items });
    }
    return .{ .name = name, .members = members.items };
}
pub fn scan(archive: *Archive, linker: anytype) !usize {
    var count: usize = 0;
    while (true) {
        var changed = false;
        for (archive.members) |*member| {
            if (member.loaded) continue;
            for (member.exports) |name| if (linker.@"undefined"(name)) { member.loaded = true; try linker.extract(member.object, name); changed = true; count += 1; break; };
        }
        if (!changed) return count;
    }
}
