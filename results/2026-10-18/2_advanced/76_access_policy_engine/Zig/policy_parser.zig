const std = @import("std");
const x = @import("expressions.zig");
pub const Clause = struct { reference: []const u8, operation: []const u8, mandatory: bool, literal: *x.Expression };
pub const Alternative = std.ArrayList(Clause);
pub const TargetLine = std.ArrayList(Alternative);
pub const Argument = struct { name: []const u8, expression: *x.Expression };
pub const Attachment = struct { effect: []const u8, identifier: []const u8, arguments: std.ArrayList(Argument) = .empty };
pub const Element = struct {
    kind: []const u8,
    identifier: []const u8,
    behavior: []const u8,
    parent: ?*Element = null,
    index: usize,
    children: std.ArrayList(*Element) = .empty,
    targets: std.ArrayList(TargetLine) = .empty,
    condition: ?*x.Expression = null,
    obligations: std.ArrayList(Attachment) = .empty,
    advice: std.ArrayList(Attachment) = .empty,
};
pub const Policies = struct { elements: std.ArrayList(*Element) = .empty, root: *Element = undefined };
pub fn read(io: std.Io) !Policies {
    var out: Policies = .{};
    var stack: std.ArrayList(*Element) = .empty;
    for (try x.readLines(io, "input/policies.txt")) |raw| {
        const source = std.mem.trim(u8, raw, " ");
        if (source.len == 0 or source[0] == '#') continue;
        const space = std.mem.indexOfScalar(u8, source, ' ') orelse source.len;
        const keyword = source[0..space];
        const rest = if (space < source.len) source[space + 1 ..] else "";
        if (x.eq(keyword, "POLICYSET") or x.eq(keyword, "POLICY") or x.eq(keyword, "RULE")) {
            const f = x.words(rest);
            const element = x.create(Element, .{ .kind = if (x.eq(keyword, "RULE")) "rule" else if (x.eq(keyword,
                 "POLICY")) "policy" else "policyset", .identifier = f[0], .behavior = f[1],
                 .index = out.elements.items.len });
            if (stack.items.len > 0) {
                element.parent = stack.items[stack.items.len - 1];
                x.append(*Element, &element.parent.?.children, element);
            }
            x.append(*Element, &out.elements, element);
            x.append(*Element, &stack, element);
        } else if (x.eq(keyword, "END")) {
            _ = stack.pop();
        } else if (x.eq(keyword, "CONDITION")) stack.items[stack.items.len - 1].condition = x.parse(rest) else if (x.eq(keyword,
             "TARGET")) {
            var target: TargetLine = .empty;
            for (x.splitBy(rest, " | ")) |alternative| {
                var clauses: Alternative = .empty;
                for (x.splitBy(alternative, " & ")) |clause| {
                    const f = x.words(clause);
                    const mandatory = f[0][f[0].len - 1] == '!';
                    x.append(Clause, &clauses, .{ .reference = f[0][0 .. f[0].len - @intFromBool(mandatory)],
                         .operation = f[1], .mandatory = mandatory, .literal = x.parse(f[2]) });
                }
                x.append(Alternative, &target, clauses);
            }
            x.append(TargetLine, &stack.items[stack.items.len - 1].targets, target);
        } else {
            const first = std.mem.indexOfScalar(u8, rest, ' ').?;
            const second = std.mem.indexOfScalarPos(u8, rest, first + 1, ' ') orelse rest.len;
            var item: Attachment = .{ .effect = rest[0..first], .identifier = rest[first + 1 .. second] };
            if (second < rest.len) for (x.split(rest[second + 1 ..], ';')) |raw_argument| {
                const argument = std.mem.trim(u8, raw_argument, " ");
                const equal = std.mem.indexOfScalar(u8, argument, '=').?;
                x.append(Argument, &item.arguments, .{ .name = argument[0..equal], .expression = x.parse(argument[equal + 1 ..]) });
            };
            const element = stack.items[stack.items.len - 1];
            x.append(Attachment, if (x.eq(keyword, "OBLIGATION")) &element.obligations else &element.advice, item);
        }
    }
    out.root = out.elements.items[0];
    return out;
}
