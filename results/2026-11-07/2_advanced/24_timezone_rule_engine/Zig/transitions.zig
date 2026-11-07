const std = @import("std");
const d = @import("day_rules.zig");
const p = @import("tz_parser.zig");
const r = @import("report.zig");
pub const Rule = struct { number: usize, fields: []const []const u8, name: []const u8, from: i64, to: i64, month: i64, day: d.DaySpec, at: i64, kind: u8, save: i64, letter: []const u8 };
pub const Instance = struct { rule: *Rule, nominal: i64 };
pub const Applied = struct { time: i64, rule: *Rule };
pub const LineRun = struct { pre_start: ?*Rule = null, applied: []Applied, end: i64 = d.pos_infinity };
fn instanceLessThan(_: void, first: Instance, second: Instance) bool { return if (first.nominal != second.nominal) first.nominal < second.nominal else first.rule.number < second.rule.number; }
pub fn instanceSequence(rules: []const *Rule) []Instance {
    var count: usize = 0;
    for (rules) |rule| count += r.u(rule.to - rule.from + 1);
    const result = r.alloc(Instance, count);
    var position: usize = 0;
    for (rules) |rule| {
        var year = rule.from;
        while (year <= rule.to) : (year += 1) { result[position] = .{ .rule = rule, .nominal = rule.day.value(year, rule.month) * 86400 + rule.at }; position += 1; }
    }
    std.mem.sort(Instance, result, {}, instanceLessThan);
    return result;
}
pub fn adjustment(kind: u8, offset: i64, save: i64) i64 { return if (kind == 'u') 0 else if (kind == 's') offset else offset + save; }
pub fn runInstances(memory: std.mem.Allocator, instances: []const Instance, offset: i64, start: i64, until: ?p.Until) LineRun {
    var applied: std.ArrayList(Applied) = .empty;
    var run: LineRun = .{ .applied = &.{} };
    var save: i64 = 0;
    for (instances) |instance| {
        const rule = instance.rule;
        const time = instance.nominal - adjustment(rule.kind, offset, save);
        if (until) |value| if (time >= value.value - adjustment(value.kind, offset, save)) break;
        if (time <= start) run.pre_start = rule else applied.append(memory, .{ .time = time, .rule = rule }) catch @panic("allocation failed");
        save = rule.save;
    }
    if (until) |value| run.end = value.value - adjustment(value.kind, offset, save);
    run.applied = applied.items;
    return run;
}
pub fn abbreviation(text: []const u8, save: i64, letter: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, text, '/')) |slash| return if (save == 0) text[0..slash] else text[slash + 1 ..];
    if (std.mem.indexOf(u8, text, "%s")) |position| return r.fmt("{s}{s}{s}", .{ text[0..position], letter, text[position + 2 ..] });
    return text;
}
