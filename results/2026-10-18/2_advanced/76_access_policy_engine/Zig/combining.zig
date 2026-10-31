const std = @import("std");
const x = @import("expressions.zig");
const Element = @import("policy_parser.zig").Element;
pub const Decision = enum { permit, deny, na, ip, id, idp };
pub fn definite(d: Decision) bool {
    return d == .permit or d == .deny;
}
pub fn indeterminate(d: Decision) bool {
    return d == .ip or d == .id or d == .idp;
}
pub fn decisionName(d: Decision) []const u8 {
    return switch (d) {
        .permit => "PERMIT",
        .deny => "DENY",
        .na => "NOT_APPLICABLE",
        .ip => "INDETERMINATE{P}",
        .id => "INDETERMINATE{D}",
        .idp => "INDETERMINATE{DP}",
    };
}
pub fn notation(d: Decision, reason: []const u8) []const u8 {
    return if (indeterminate(d)) x.fmt("{s} ({s})", .{ decisionName(d), reason }) else decisionName(d);
}
pub const TargetKind = enum { match, no_match, indeterminate };
pub const TargetResult = struct { kind: TargetKind = .match, reason: []const u8 = "" };
pub fn targetName(kind: TargetKind) []const u8 {
    return switch (kind) {
        .match => "MATCH",
        .no_match => "NO_MATCH",
        .indeterminate => "INDETERMINATE",
    };
}
pub const ChildState = union(enum) { skipped, checked: TargetResult, evaluated: *Evaluation };
pub const Item = struct { identifier: []const u8, text: []const u8 };
pub const Evaluation = struct { element: *Element, target: TargetResult, decision: Decision = .na,
     reason: []const u8 = "", decisive: ?*Element = null, condition: x.Value = .{ .boolean = false },
     children: std.ArrayList(ChildState) = .empty, obligations: std.ArrayList(Item) = .empty,
     advice: std.ArrayList(Item) = .empty };
pub const Combined = struct { decision: Decision = .na, reason: []const u8 = "", children: std.ArrayList(ChildState) = .empty };
pub fn combine(evaluator: anytype, element: *Element) Combined {
    var out: Combined = .{};
    for (element.children.items) |_| x.append(ChildState, &out.children, .skipped);
    const algorithm = element.behavior;
    if (x.eq(algorithm, "only-one-applicable")) {
        var matched: ?usize = null;
        for (element.children.items, 0..) |child, i| {
            const checked = evaluator.target(child);
            out.children.items[i] = .{ .checked = checked };
            if (checked.kind == .indeterminate) {
                out.decision = .idp;
                out.reason = checked.reason;
                return out;
            }
            if (checked.kind == .match) {
                if (matched) |earlier| {
                    out.decision = .idp;
                    out.reason = x.fmt("multiple applicable {s} {s}", .{ element.children.items[earlier].identifier,
                         child.identifier });
                    return out;
                }
                matched = i;
            }
        }
        if (matched) |i| {
            const result = evaluator.evaluate(element.children.items[i]);
            out.children.items[i] = .{ .evaluated = result };
            out.decision = result.decision;
            out.reason = result.reason;
        }
        return out;
    }
    var present: [6]bool = @splat(false);
    var first_error: []const u8 = "";
    for (element.children.items, 0..) |child, i| {
        const result = evaluator.evaluate(child);
        out.children.items[i] = .{ .evaluated = result };
        const d = result.decision;
        present[@intFromEnum(d)] = true;
        if (indeterminate(d) and first_error.len == 0) first_error = result.reason;
        const stop = (x.eq(algorithm, "first-applicable") and d != .na) or ((x.eq(algorithm,
             "deny-overrides") or x.eq(algorithm, "permit-unless-deny")) and d == .deny) or ((x.eq(algorithm,
             "permit-overrides") or x.eq(algorithm, "deny-unless-permit")) and d == .permit);
        if (stop) {
            out.decision = d;
            out.reason = result.reason;
            return out;
        }
    }
    const permit = present[@intFromEnum(Decision.permit)];
    const deny = present[@intFromEnum(Decision.deny)];
    const ip = present[@intFromEnum(Decision.ip)];
    const id = present[@intFromEnum(Decision.id)];
    const idp = present[@intFromEnum(Decision.idp)];
    if (x.eq(algorithm, "deny-unless-permit")) out.decision = .deny else if (x.eq(algorithm,
         "permit-unless-deny")) out.decision = .permit else if (x.eq(algorithm, "deny-overrides")) out.decision = if (idp or (id and (ip or permit))) .idp else if (id) .id else if (permit) .permit else if (ip) .ip else .na else if (x.eq(algorithm,
         "permit-overrides")) out.decision = if (idp or (ip and (id or deny))) .idp else if (ip) .ip else if (deny) .deny else if (id) .id else .na;
    if (indeterminate(out.decision)) out.reason = first_error;
    return out;
}
