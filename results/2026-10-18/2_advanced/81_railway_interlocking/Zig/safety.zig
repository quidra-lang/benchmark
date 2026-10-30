const l = @import("layout.zig");
const inter = @import("interlocking.zig");
pub const properties = [_][]const u8{ "OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING" };
pub const Safety = struct {
    checks: [4]i64 = @splat(0),
    violations: [4]i64 = @splat(0),
    records: l.Lines = .{},
    pub fn check(self: *Safety, time: i64, kind: usize, details: ?[]const u8) void {
        self.checks[kind] += 1;
        if (details) |text| {
            self.violations[kind] += 1;
            self.records.add("VIOLATION {d} {s} {s}", .{ time, properties[kind], text });
        }
    }
    pub fn inspect(self: *Safety, time: i64, layout: *const l.Layout, interlocking: *const inter.Interlocking,
         names: l.Names) void {
        for (layout.sections) |section| {
            var details: ?[]const u8 = null;
            if (@popCount(section.occupants) >= 2) {
                var text: l.Text = .{};
                text.add("{s} ", .{section.name});
                var first = true;
                for (names, 0..) |name, index| if (section.occupants & (@as(u32, 1) << @intCast(index)) != 0) {
                    text.add("{s}{s}", .{ if (first) "" else ",", name });
                    first = false;
                };
                details = text.value();
            }
            self.check(time, 0, details);
        }
        for (layout.points) |point| if (point.moving) {
            var details: ?[]const u8 = null;
            if (layout.sections[point.common].occupants != 0) details = l.fmt("{s} occupied",
                 .{point.name}) else for (interlocking.routes, 0..) |route, index| if (point.locks() & l.bit(index) != 0 and (route.state == .used or route.state == .approach)) {
                details = l.fmt("{s} locked", .{point.name});
                break;
            };
            self.check(time, 1, details);
        };
        for (interlocking.routes, 0..) |first, a| if (inter.protected(first.state)) {
            for (interlocking.routes[a + 1 ..], a + 1..) |second, b| if (inter.protected(second.state)) {
                var conflict = false;
                for (first.conflicts) |index| conflict = conflict or index == b;
                for (second.conflicts) |index| conflict = conflict or index == a;
                self.check(time, 2, if (conflict) l.fmt("{s} {s}", .{ first.name, second.name }) else null);
            };
        };
    }
    pub fn report(self: Safety) l.Lines {
        var out: l.Lines = .{};
        for (properties, self.checks, self.violations) |name, checks, violations| out.add("{s} {s} checks {d} violations {d}",
             .{ name, if (violations > 0) "FAIL" else "OK", checks, violations });
        out.extend(self.records);
        out.add("RESULT {s}", .{if (self.records.data.items.len > 0) "UNSAFE" else "SAFE"});
        return out;
    }
};
