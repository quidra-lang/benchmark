const std = @import("std");
const x = @import("expressions.zig");
const p = @import("policy_parser.zig");
const r = @import("rbac.zig");
const c = @import("combining.zig");
const a = @import("analysis.zig");
const Value = x.Value;
const Attributes = x.Attributes;
const Element = p.Element;
const Decision = c.Decision;
const Evaluation = c.Evaluation;
fn inputValue(source: []const u8) Value {
    if (x.eq(source, "true") or x.eq(source, "false")) return .{ .boolean = x.eq(source, "true") };
    if (source[0] == '[') return .{ .bag = if (x.eq(source, "[]")) &.{} else x.split(source[1 .. source.len - 1],
         ',') };
    if (source[0] == '-' or (source[0] >= '0' and source[0] <= '9')) return .{ .integer = x.number(source) };
    return .{ .string = source };
}
fn attributes(fields: x.Names) Attributes {
    var values: Attributes = .empty;
    for (fields) |field| {
        const equal = std.mem.indexOfScalar(u8, field, '=').?;
        x.set(&values, field[0..equal], inputValue(field[equal + 1 ..]));
    }
    return values;
}
fn valueNotation(value: Value) []const u8 {
    return switch (value) {
        .integer => |n| x.fmt("{d}", .{n}),
        .string => |s| x.fmt("\"{s}\"", .{s}),
        .boolean => |b| if (b) "true" else "false",
        .bag => |bag| blk: {
            var items: std.ArrayList([]const u8) = .empty;
            for (bag) |s| x.append([]const u8, &items, x.fmt("\"{s}\"", .{s}));
            break :blk x.fmt("[{s}]", .{x.join(items.items, ",")});
        },
        .failure => unreachable,
    };
}
fn booleanResult(values: []const Value, veto: bool, name: []const u8) Value {
    var found = false;
    var failure: ?[]const u8 = null;
    for (values) |value| switch (value) {
        .boolean => |b| {
            found = found or b == veto;
        },
        .failure => |reason| {
            if (failure == null) failure = reason;
        },
        else => {
            if (failure == null) failure = x.fmt("type {s}", .{name});
        },
    };
    if (found) return .{ .boolean = veto };
    if (failure) |reason| return .{ .failure = reason };
    return .{ .boolean = !veto };
}
fn operation(name: []const u8, values: []const Value) Value {
    for (values) |value| if (value == .failure) return value;
    const left = values[0];
    const right = if (values.len > 1) values[1] else values[0];
    const integers = left == .integer and right == .integer;
    if (integers) {
        if (x.eq(name, "+")) return .{ .integer = left.integer + right.integer };
        if (x.eq(name, "-")) return .{ .integer = if (values.len == 1) -left.integer else left.integer - right.integer };
        if (x.eq(name, "*")) return .{ .integer = left.integer * right.integer };
        if (x.eq(name, "<")) return .{ .boolean = left.integer < right.integer };
        if (x.eq(name, "<=")) return .{ .boolean = left.integer <= right.integer };
        if (x.eq(name, ">")) return .{ .boolean = left.integer > right.integer };
        if (x.eq(name, ">=")) return .{ .boolean = left.integer >= right.integer };
    }
    if ((x.eq(name, "==") or x.eq(name, "!=")) and std.meta.activeTag(left) == std.meta.activeTag(right)) {
        const equal: ?bool = switch (left) {
            .integer => |n| n == right.integer,
            .string => |s| x.eq(s, right.string),
            .boolean => |b| b == right.boolean,
            else => null,
        };
        if (equal) |b| return .{ .boolean = if (x.eq(name, "==")) b else !b };
    }
    if (x.eq(name, "in") and left == .string and right == .bag) {
        for (right.bag) |item| if (x.eq(item, left.string)) return .{ .boolean = true };
        return .{ .boolean = false };
    }
    if (x.eq(name, "not") and left == .boolean) return .{ .boolean = !left.boolean };
    if ((x.eq(name, "starts_with") or x.eq(name, "^=")) and left == .string and right == .string) return .{ .boolean = std.mem.startsWith(u8,
         left.string, right.string) };
    if (x.eq(name, "size") and left == .bag) return .{ .integer = x.n(left.bag.len) };
    return .{ .failure = x.fmt("type {s}", .{name}) };
}
fn expression(tree: *x.Expression, values: Attributes, current: []const u8) Value {
    const name = tree.operation;
    const arguments = tree.arguments.items;
    if (x.eq(name, "literal")) return tree.literal;
    if (x.eq(name, "attribute")) return values.get(tree.literal.string) orelse .{ .failure = x.fmt("missing {s}",
         .{tree.literal.string}) };
    if (x.eq(name, "it")) return .{ .string = current };
    if (x.eq(name, "present")) return .{ .boolean = values.contains(arguments[0].literal.string) };
    if (x.eq(name, "any_of") or x.eq(name, "all_of")) {
        const bag = expression(arguments[0], values, current);
        if (bag == .failure) return bag;
        if (bag != .bag) return .{ .failure = x.fmt("type {s}", .{name}) };
        var checked: std.ArrayList(Value) = .empty;
        for (bag.bag) |item| x.append(Value, &checked, expression(arguments[1], values, item));
        return booleanResult(checked.items, x.eq(name, "any_of"), name);
    }
    var operands: std.ArrayList(Value) = .empty;
    for (arguments) |argument| x.append(Value, &operands, expression(argument, values, current));
    if (x.eq(name, "and") or x.eq(name, "or")) return booleanResult(operands.items, x.eq(name, "or"), name);
    return operation(name, operands.items);
}
fn targetGroup(results: []const c.TargetResult, conjunction: bool) c.TargetResult {
    var all = true;
    for (results) |result| {
        if (conjunction and result.kind == .no_match) return .{ .kind = .no_match };
        if (!conjunction and result.kind == .match) return .{};
        all = all and result.kind == .match;
    }
    if (conjunction and all) return .{};
    for (results) |result| if (result.kind == .indeterminate) return result;
    return .{ .kind = .no_match };
}
fn matchClause(clause: p.Clause, values: Attributes) c.TargetResult {
    const source = values.get(clause.reference) orelse return if (clause.mandatory) .{ .kind = .indeterminate,
         .reason = x.fmt("missing {s}", .{clause.reference}) } else .{ .kind = .no_match };
    var items: std.ArrayList(Value) = .empty;
    if (source == .bag) {
        for (source.bag) |item| x.append(Value, &items, .{ .string = item });
    } else x.append(Value, &items, source);
    const literal = expression(clause.literal, values, "");
    var failure: ?[]const u8 = null;
    var matched = false;
    for (items.items) |item| {
        const result = operation(clause.operation, &.{ item, literal });
        switch (result) {
            .boolean => |b| {
                matched = matched or b;
            },
            .failure => |reason| {
                if (failure == null) failure = reason;
            },
            else => unreachable,
        }
    }
    if (matched) return .{};
    if (failure) |reason| return .{ .kind = .indeterminate, .reason = reason };
    return .{ .kind = .no_match };
}
const Evaluator = struct {
    values: Attributes,
    coverage: ?*[100]u8 = null,
    pub fn target(self: *Evaluator, element: *Element) c.TargetResult {
        var lines: std.ArrayList(c.TargetResult) = .empty;
        for (element.targets.items) |line| {
            var alternatives: std.ArrayList(c.TargetResult) = .empty;
            for (line.items) |alternative| {
                var clauses: std.ArrayList(c.TargetResult) = .empty;
                for (alternative.items) |clause| x.append(c.TargetResult, &clauses, matchClause(clause, self.values));
                x.append(c.TargetResult, &alternatives, targetGroup(clauses.items, true));
            }
            x.append(c.TargetResult, &lines, targetGroup(alternatives.items, false));
        }
        return targetGroup(lines.items, true);
    }
    fn attachments(self: *Evaluator, result: *Evaluation) void {
        for (result.children.items) |state| if (state == .evaluated and state.evaluated.decision == result.decision) {
            for (state.evaluated.obligations.items) |item| x.append(c.Item, &result.obligations, item);
            for (state.evaluated.advice.items) |item| x.append(c.Item, &result.advice, item);
        };
        const effect = c.decisionName(result.decision);
        for ([_]bool{ true, false }) |obligatory| {
            const definitions = if (obligatory) result.element.obligations.items else result.element.advice.items;
            for (definitions) |definition| {
                if (!x.eq(definition.effect, effect)) continue;
                var failure: ?[]const u8 = null;
                var parts: std.ArrayList([]const u8) = .empty;
                x.append([]const u8, &parts, definition.identifier);
                for (definition.arguments.items) |argument| {
                    const value = expression(argument.expression, self.values, "");
                    if (value == .failure) {
                        if (failure == null) failure = value.failure;
                    } else x.append([]const u8, &parts, x.fmt("{s}={s}", .{ argument.name, valueNotation(value) }));
                }
                if (failure) |reason| {
                    if (obligatory) {
                        result.decision = if (x.eq(effect, "DENY")) .id else .ip;
                        result.reason = x.fmt("obligation {s}: {s}", .{ definition.identifier, reason });
                        result.decisive = null;
                        result.obligations.clearRetainingCapacity();
                        result.advice.clearRetainingCapacity();
                        return;
                    }
                    continue;
                }
                x.append(c.Item, if (obligatory) &result.obligations else &result.advice, .{ .identifier = definition.identifier,
                     .text = x.join(parts.items, " ") });
            }
        }
    }
    fn rule(self: *Evaluator, element: *Element, with_obligations: bool) *Evaluation {
        const result = x.create(Evaluation, .{ .element = element, .target = self.target(element) });
        const failure: Decision = if (x.eq(element.behavior, "DENY")) .id else .ip;
        if (result.target.kind == .indeterminate) {
            result.decision = failure;
            result.reason = result.target.reason;
        } else if (result.target.kind == .match) {
            result.condition = if (element.condition) |condition| expression(condition, self.values,
                 "") else .{ .boolean = true };
            if (result.condition != .boolean and result.condition != .failure) result.condition = .{ .failure = "type condition" };
            if (result.condition == .failure) {
                result.decision = failure;
                result.reason = result.condition.failure;
            } else if (result.condition.boolean) {
                result.decision = if (x.eq(element.behavior, "DENY")) .deny else .permit;
                result.decisive = element;
                if (with_obligations) self.attachments(result);
            }
        }
        if (self.coverage) |coverage| coverage[element.index] = switch (result.decision) {
            .permit => 'P',
            .deny => 'D',
            .na => '-',
            else => 'I',
        };
        return result;
    }
    pub fn evaluate(self: *Evaluator, element: *Element) *Evaluation {
        if (x.eq(element.kind, "rule")) return self.rule(element, true);
        const result = x.create(Evaluation, .{ .element = element, .target = self.target(element) });
        if (result.target.kind == .no_match) return result;
        const combined = c.combine(self, element);
        result.decision = combined.decision;
        result.reason = combined.reason;
        result.children = combined.children;
        if (result.target.kind == .indeterminate) {
            if (c.definite(result.decision)) result.decision = if (result.decision == .permit) .ip else .id;
            if (c.indeterminate(result.decision)) result.reason = result.target.reason;
        }
        if (c.definite(result.decision)) {
            result.decisive = element;
            for (result.children.items) |state| if (state == .evaluated and state.evaluated.decision == result.decision) {
                result.decisive = state.evaluated.decisive;
                break;
            };
            self.attachments(result);
        }
        return result;
    }
};
fn finalNotation(result: *Evaluation) []const u8 {
    return if (c.definite(result.decision)) x.fmt("{s} by {s}", .{ c.notation(result.decision,
         result.reason), result.decisive.?.identifier }) else c.notation(result.decision, result.reason);
}
fn treeLines(result: *Evaluation, lines: *x.Lines, depth: usize) void {
    const element = result.element;
    const prefix = x.alloc(u8, 2 + 2 * depth);
    @memset(prefix, ' ');
    const condition = if (x.eq(element.kind, "rule") and result.target.kind == .match) x.fmt(" condition {s}",
         .{if (result.condition == .failure) "INDETERMINATE" else if (result.condition.boolean) "TRUE" else "FALSE"}) else "";
    lines.add("{s}{s} {s} {s} target {s}{s} -> {s}", .{ prefix, element.kind, element.identifier,
         element.behavior, c.targetName(result.target.kind), condition, c.notation(result.decision,
         result.reason) });
    if (!x.eq(element.kind, "rule") and result.target.kind != .no_match) for (element.children.items,
         result.children.items) |child, state| switch (state) {
        .evaluated => |evaluated| treeLines(evaluated, lines, depth + 1),
        .skipped => lines.add("{s}  {s} {s} skipped", .{ prefix, child.kind, child.identifier }),
        .checked => |checked| lines.add("{s}  {s} {s} {s} target {s}{s}", .{ prefix, child.kind,
             child.identifier, child.behavior, c.targetName(checked.kind), if (checked.kind == .indeterminate) x.fmt(" ({s})",
             .{checked.reason}) else "" }),
    };
}
const Request = struct { identifier: []const u8 = "", user: []const u8, roles: []const u8,
     action: []const u8, resource: []const u8, environment: Attributes, explain: bool = false };
const Resource = struct { resource_type: []const u8, attributes: Attributes };
const Activation = struct { role: []const u8, reason: ?[]const u8 = null };
const Prepared = struct { activations: std.ArrayList(Activation) = .empty, roles: r.Roles = 0,
     grant: ?usize = null, values: Attributes = .empty };
const Counter = struct { identifier: []const u8, count: usize = 1 };
fn countItem(counters: *std.ArrayList(Counter), identifier: []const u8) void {
    for (counters.items) |*entry| if (x.eq(entry.identifier, identifier)) {
        entry.count += 1;
        return;
    };
    x.append(Counter, counters, .{ .identifier = identifier });
}
const Engine = struct {
    work_allocator: std.mem.Allocator,
    rbac: r.RBAC = .{},
    policies: p.Policies = .{},
    rules: std.ArrayList(*Element) = .empty,
    subjects: std.StringHashMapUnmanaged(Attributes) = .empty,
    resources: std.StringHashMapUnmanaged(Resource) = .empty,
    domains: std.ArrayList(a.Domain) = .empty,
    reference: Attributes = .empty,
    requests: std.ArrayList(Request) = .empty,
    coverage: [100]std.ArrayList(u8) = @splat(.empty),
    decisive: [100]usize = @splat(0),
    decisions: [5]usize = @splat(0),
    grants: []usize = undefined,
    refused: usize = 0,
    obligations: std.ArrayList(Counter) = .empty,
    advice: std.ArrayList(Counter) = .empty,
    fn read(self: *Engine, io: std.Io) !void {
        try self.rbac.read(io);
        self.policies = try p.read(io);
        for (self.policies.elements.items) |element| if (x.eq(element.kind, "rule")) x.append(*Element,
             &self.rules, element);
        self.grants = x.alloc(usize, self.rbac.grants.items.len);
        @memset(self.grants, 0);
        for (try x.readLines(io, "input/attributes.txt")) |line| {
            const f = x.words(line);
            if (x.eq(f[0], "SUBJECT")) self.subjects.put(x.allocator, f[1], attributes(f[2..])) catch @panic("allocation failed") else if (x.eq(f[0],
                 "RESOURCE")) self.resources.put(x.allocator, f[1], .{ .resource_type = f[2],
                 .attributes = attributes(f[3..]) }) catch @panic("allocation failed") else if (x.eq(f[0],
                 "DOMAIN")) {
                var candidates: std.ArrayList(Value) = .empty;
                for (f[2..]) |value| x.append(Value, &candidates, inputValue(value));
                x.append(a.Domain, &self.domains, .{ .reference = f[1], .candidates = candidates.items });
            } else self.reference = attributes(f[1..]);
        }
        for (try x.readLines(io, "input/requests.txt")) |line| {
            var f = x.words(line);
            const explain = x.eq(f[f.len - 1], "EXPLAIN");
            if (explain) f = f[0 .. f.len - 1];
            x.append(Request, &self.requests, .{ .identifier = f[0], .user = f[1], .roles = f[2],
                 .action = f[3], .resource = f[4], .environment = attributes(f[5..]), .explain = explain });
        }
    }
    fn check(self: *Engine, request: Request) ?[]const u8 {
        if (!self.subjects.contains(request.user)) return x.fmt("unknown user {s}", .{request.user});
        if (!self.resources.contains(request.resource)) return x.fmt("unknown resource {s}", .{request.resource});
        const day = request.environment.get("day") orelse return "bad day";
        if (day != .integer or day.integer < 1 or day.integer > 365) return "bad day";
        return null;
    }
    fn prepare(self: *Engine, request: Request) Prepared {
        var out: Prepared = .{};
        const day = request.environment.get("day").?.integer;
        const authorized = self.rbac.authorized(request.user, day);
        var active: r.Roles = 0;
        const candidates: x.Names = if (x.eq(request.roles, "-")) &.{} else if (x.eq(request.roles,
             "*")) self.rbac.names(authorized) else x.split(request.roles, ',');
        for (candidates, 0..) |candidate, i| {
            const role = self.rbac.find(candidate);
            var seen = false;
            for (candidates[0..i]) |earlier| if (x.eq(earlier, candidate)) {
                seen = true;
                break;
            };
            var reason: ?[]const u8 = null;
            if (role == null) reason = "unknown" else if (seen) reason = "duplicate" else if (authorized & r.bit(role.?) == 0) reason = "unauthorized" else for (self.rbac.dsd.items) |constraint| if (r.cardinality(constraint.roles & self.rbac.closure(active | r.bit(role.?))) >= constraint.cardinality) {
                reason = x.fmt("dsd {s}", .{constraint.name});
                break;
            };
            if (reason == null) active |= r.bit(role.?);
            x.append(Activation, &out.activations, .{ .role = candidate, .reason = reason });
        }
        out.roles = self.rbac.closure(active);
        const resource = self.resources.get(request.resource).?;
        const names = self.rbac.names(out.roles);
        for (names) |name| {
            const role = self.rbac.find(name).?;
            if (self.rbac.permits(role, request.action, resource.resource_type)) {
                out.grant = role;
                break;
            }
        }
        const subject = self.subjects.get(request.user).?;
        var subject_iterator = subject.iterator();
        while (subject_iterator.next()) |entry| x.set(&out.values, x.fmt("subject.{s}", .{entry.key_ptr.*}),
             entry.value_ptr.*);
        x.set(&out.values, "subject.id", .{ .string = request.user });
        x.set(&out.values, "subject.role", .{ .bag = names });
        x.set(&out.values, "subject.rbac", .{ .boolean = out.grant != null });
        var resource_iterator = resource.attributes.iterator();
        while (resource_iterator.next()) |entry| x.set(&out.values, x.fmt("resource.{s}", .{entry.key_ptr.*}),
             entry.value_ptr.*);
        x.set(&out.values, "resource.id", .{ .string = request.resource });
        x.set(&out.values, "resource.type", .{ .string = resource.resource_type });
        x.set(&out.values, "action.id", .{ .string = request.action });
        var environment_iterator = request.environment.iterator();
        while (environment_iterator.next()) |entry| x.set(&out.values, x.fmt("environment.{s}",
             .{entry.key_ptr.*}), entry.value_ptr.*);
        return out;
    }
    fn processRequests(self: *Engine) struct { decisions: x.Lines, traces: x.Lines } {
        var output: x.Lines = .{};
        var traces: x.Lines = .{};
        for (self.requests.items) |request| {
            const persistent = x.allocator;
            var work: std.heap.ArenaAllocator = .init(self.work_allocator);
            defer work.deinit();
            x.allocator = work.allocator();
            var symbols: [100]u8 = @splat('.');
            const failure = self.check(request);
            var prepared: Prepared = undefined;
            var result: *Evaluation = undefined;
            if (failure == null) {
                prepared = self.prepare(request);
                var evaluator: Evaluator = .{ .values = prepared.values, .coverage = &symbols };
                result = evaluator.evaluate(self.policies.root);
            }
            x.allocator = persistent;
            if (request.explain) {
                if (traces.data.items.len > 0) traces.add("", .{});
                traces.add("request {s}", .{request.identifier});
            }
            if (failure) |reason| {
                output.add("{s} ERROR {s}", .{ request.identifier, reason });
                self.decisions[4] += 1;
                if (request.explain) traces.add("  error {s}", .{reason});
            } else {
                output.add("{s} {s}", .{ request.identifier, finalNotation(result) });
                for (prepared.activations.items) |activation| if (activation.reason) |reason| {
                    output.add("  refused {s} {s}", .{ activation.role, reason });
                    self.refused += 1;
                };
                for (result.obligations.items) |item| {
                    output.add("  obligation {s}", .{item.text});
                    countItem(&self.obligations, item.identifier);
                }
                for (result.advice.items) |item| {
                    output.add("  advice {s}", .{item.text});
                    countItem(&self.advice, item.identifier);
                }
                const resource = self.resources.get(request.resource).?;
                if (prepared.grant) |role| for (self.rbac.grants.items, 0..) |grant, i| if (grant.role == role and x.eq(grant.action,
                     request.action) and x.eq(grant.resource_type, resource.resource_type)) {
                    self.grants[i] += 1;
                    break;
                };
                self.decisions[if (c.indeterminate(result.decision)) 3 else @intFromEnum(result.decision)] += 1;
                if (c.definite(result.decision)) self.decisive[result.decisive.?.index] += 1;
                if (request.explain) {
                    traces.add("  user {s} resource {s} type {s} action {s} day {d}", .{ request.user,
                         request.resource, resource.resource_type, request.action, request.environment.get("day").?.integer });
                    for (prepared.activations.items) |activation| traces.add("  activate {s} {s}",
                         .{ activation.role, if (activation.reason) |reason| x.fmt("refused {s}",
                         .{reason}) else "ok" });
                    traces.add("  roles {s}", .{if (prepared.roles != 0) x.join(self.rbac.names(prepared.roles),
                         ",") else "-"});
                    traces.add("  rbac {s}", .{if (prepared.grant) |role| x.fmt("yes {s}",
                         .{self.rbac.roles.items[role]}) else "no"});
                    treeLines(result, &traces, 0);
                    traces.add("  decision {s}", .{finalNotation(result)});
                }
            }
            for (self.rules.items) |rule| x.append(u8, &self.coverage[rule.index], symbols[rule.index]);
        }
        return .{ .decisions = output, .traces = traces };
    }
    fn permissionReport(self: *Engine) x.Lines {
        var out: x.Lines = .{};
        var users: std.ArrayList([]const u8) = .empty;
        for (self.rbac.assignments.items) |assignment| {
            var found = false;
            for (users.items) |user| if (x.eq(user, assignment.user)) {
                found = true;
                break;
            };
            if (!found) x.append([]const u8, &users, assignment.user);
        }
        std.mem.sort([]const u8, users.items, {}, struct {
            fn less(_: void, left: []const u8, right: []const u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.less);
        for (users.items) |user| {
            if (out.data.items.len > 0) out.add("", .{});
            out.add("user {s}", .{user});
            var assigned: [40]a.Days = std.mem.zeroes([40]a.Days);
            var authorized: [40]a.Days = std.mem.zeroes([40]a.Days);
            var present: r.Roles = 0;
            for (self.rbac.assignments.items) |assignment| if (x.eq(assignment.user, user)) {
                present |= r.bit(assignment.role);
                for (x.u(assignment.first)..x.u(assignment.last) + 1) |day| assigned[assignment.role][day] = true;
            };
            const all = self.rbac.closure(present);
            for (0..self.rbac.roles.items.len) |role| if (present & r.bit(role) != 0) {
                const inherited = self.rbac.closure(r.bit(role));
                for (0..self.rbac.roles.items.len) |target| if (inherited & r.bit(target) != 0) for (1..366) |day| {
                    authorized[target][day] = authorized[target][day] or assigned[role][day];
                };
            };
            for (self.rbac.names(present)) |name| out.add("  assigned {s} {s}", .{ name, a.dayNotation(assigned[self.rbac.find(name).?]) });
            for (self.rbac.names(all)) |name| out.add("  authorized {s} {s}", .{ name, a.dayNotation(authorized[self.rbac.find(name).?]) });
            const Permission = struct { action: []const u8, resource_type: []const u8, roles: r.Roles = 0 };
            var permissions: std.ArrayList(Permission) = .empty;
            for (self.rbac.grants.items) |grant| {
                if (all & r.bit(grant.role) == 0) continue;
                var found: ?usize = null;
                for (permissions.items, 0..) |permission, i| if (x.eq(permission.action, grant.action) and x.eq(permission.resource_type,
                     grant.resource_type)) {
                    found = i;
                    break;
                };
                if (found == null) {
                    found = permissions.items.len;
                    x.append(Permission, &permissions, .{ .action = grant.action, .resource_type = grant.resource_type });
                }
                permissions.items[found.?].roles |= r.bit(grant.role);
            }
            std.mem.sort(Permission, permissions.items, {}, struct {
                fn less(_: void, left: Permission, right: Permission) bool {
                    return if (x.eq(left.action, right.action)) std.mem.lessThan(u8, left.resource_type,
                         right.resource_type) else std.mem.lessThan(u8, left.action, right.action);
                }
            }.less);
            for (permissions.items) |permission| {
                var days: a.Days = @splat(false);
                for (0..self.rbac.roles.items.len) |role| if (permission.roles & r.bit(role) != 0) for (1..366) |day| {
                    days[day] = days[day] or authorized[role][day];
                };
                var effective: []const u8 = "-";
                if (self.subjects.contains(user)) {
                    var permitted: usize = 0;
                    var total: usize = 0;
                    var iterator = self.resources.iterator();
                    while (iterator.next()) |entry| if (x.eq(entry.value_ptr.resource_type, permission.resource_type)) {
                        total += 1;
                        const persistent = x.allocator;
                        var work: std.heap.ArenaAllocator = .init(self.work_allocator);
                        defer work.deinit();
                        x.allocator = work.allocator();
                        const request: Request = .{ .user = user, .roles = "*", .action = permission.action,
                             .resource = entry.key_ptr.*, .environment = self.reference };
                        const prepared = self.prepare(request);
                        var evaluator: Evaluator = .{ .values = prepared.values };
                        if (evaluator.evaluate(self.policies.root).decision == .permit) permitted += 1;
                        x.allocator = persistent;
                    };
                    effective = x.fmt("{d}/{d}", .{ permitted, total });
                }
                out.add("  permission {s} {s} {s} via {s} effective {s}", .{ permission.action,
                     permission.resource_type, a.dayNotation(days), x.join(self.rbac.names(permission.roles),
                     ","), effective });
            }
        }
        return out;
    }
    fn domainAnalysis(self: *Engine) x.Lines {
        var counts: [100]usize = @splat(0);
        var examples: [100][]const u8 = @splat("-");
        var shadowed: [100]bool = @splat(false);
        var blockers: [100][100]bool = std.mem.zeroes([100][100]bool);
        var conflicts: [100][100]usize = std.mem.zeroes([100][100]usize);
        const Pair = struct { policy: *Element, earlier: *Element, later: *Element };
        var pairs: std.ArrayList(Pair) = .empty;
        for (self.rules.items) |rule| shadowed[rule.index] = x.eq(rule.parent.?.behavior, "first-applicable");
        for (self.policies.elements.items) |policy| if (x.eq(policy.kind, "policy")) {
            for (policy.children.items, 0..) |earlier, i| for (policy.children.items[i + 1 ..]) |later| if (!x.eq(earlier.behavior,
                 later.behavior)) x.append(Pair, &pairs, .{ .policy = policy, .earlier = earlier,
                 .later = later });
        };
        const point_count = a.pointCount(self.domains.items);
        for (0..point_count) |ordinal| {
            const persistent = x.allocator;
            var work: std.heap.ArenaAllocator = .init(self.work_allocator);
            defer work.deinit();
            x.allocator = work.allocator();
            const values = a.point(self.domains.items, ordinal);
            var evaluator: Evaluator = .{ .values = values };
            var targets: [100]c.TargetKind = @splat(.match);
            var standalone: [100]Decision = @splat(.na);
            var applies: [100]bool = @splat(false);
            for (self.policies.elements.items) |element| if (!x.eq(element.kind, "rule")) {
                targets[element.index] = evaluator.target(element).kind;
            };
            for (self.rules.items) |rule| standalone[rule.index] = evaluator.rule(rule, false).decision;
            for (self.rules.items) |rule| {
                var applicable = c.definite(standalone[rule.index]);
                var parent = rule.parent;
                while (parent) |element| {
                    applicable = applicable and targets[element.index] == .match;
                    parent = element.parent;
                }
                if (!applicable) continue;
                applies[rule.index] = true;
                counts[rule.index] += 1;
                if (counts[rule.index] == 1) {
                    var parts: std.ArrayList([]const u8) = .empty;
                    for (self.domains.items) |domain| if (domain.candidates.len >= 2) x.append([]const u8,
                         &parts, x.fmt("{s}={s}", .{ domain.reference, valueNotation(values.get(domain.reference).?) }));
                    const example = x.join(parts.items, " ");
                    x.allocator = persistent;
                    examples[rule.index] = x.dupe(u8, example);
                    x.allocator = work.allocator();
                }
                if (shadowed[rule.index]) {
                    if (a.blocker(rule, standalone)) |earlier| blockers[rule.index][earlier.index] = true else shadowed[rule.index] = false;
                }
            }
            for (pairs.items) |pair| if (applies[pair.earlier.index] and applies[pair.later.index]) {
                conflicts[pair.earlier.index][pair.later.index] += 1;
            };
            x.allocator = persistent;
        }
        var out: x.Lines = .{};
        out.add("applicability {d}", .{point_count});
        var dead: usize = 0;
        var shadows: usize = 0;
        var conflict_count: usize = 0;
        for (self.rules.items) |rule| {
            out.add("  {s} {d} {s}", .{ rule.identifier, counts[rule.index], examples[rule.index] });
            if (counts[rule.index] == 0) {
                dead += 1;
                shadowed[rule.index] = false;
            }
            shadows += @intFromBool(shadowed[rule.index]);
        }
        out.add("dead {d}", .{dead});
        for (self.rules.items) |rule| if (counts[rule.index] == 0) out.add("  {s}", .{rule.identifier});
        out.add("shadowed {d}", .{shadows});
        for (self.rules.items) |rule| if (shadowed[rule.index]) {
            var names: std.ArrayList([]const u8) = .empty;
            for (self.rules.items) |earlier| if (blockers[rule.index][earlier.index]) x.append([]const u8,
                 &names, earlier.identifier);
            out.add("  {s} by {s}", .{ rule.identifier, x.join(names.items, ",") });
        };
        for (pairs.items) |pair| if (conflicts[pair.earlier.index][pair.later.index] > 0) {
            conflict_count += 1;
        };
        out.add("conflicts {d}", .{conflict_count});
        for (pairs.items) |pair| {
            const count = conflicts[pair.earlier.index][pair.later.index];
            if (count > 0) out.add("  {s} {s} {s} {d} {s}", .{ pair.policy.identifier, pair.earlier.identifier,
                 pair.later.identifier, count, a.conflictWinner(pair.policy, pair.earlier,
                 pair.later).identifier });
        }
        return out;
    }
    fn analysisReport(self: *Engine) x.Lines {
        var out: x.Lines = .{};
        out.add("rbac {d}", .{self.rbac.diagnostics.items.len});
        for (self.rbac.diagnostics.items) |diagnostic| out.add("  line {d} {s} {s}", .{ diagnostic.number,
             diagnostic.keyword, diagnostic.message });
        const order = x.alloc(usize, self.rbac.grants.items.len);
        for (order, 0..) |*item, i| item.* = i;
        const context: *const Engine = self;
        std.mem.sort(usize, order, context, struct {
            fn less(engine: *const Engine, left: usize, right: usize) bool {
                const l = engine.rbac.grants.items[left];
                const rr = engine.rbac.grants.items[right];
                const ln = engine.rbac.roles.items[l.role];
                const rn = engine.rbac.roles.items[rr.role];
                if (!x.eq(ln, rn)) return std.mem.lessThan(u8, ln, rn);
                if (!x.eq(l.action, rr.action)) return std.mem.lessThan(u8, l.action, rr.action);
                return std.mem.lessThan(u8, l.resource_type, rr.resource_type);
            }
        }.less);
        out.add("grants {d}", .{order.len});
        for (order) |i| {
            const grant = self.rbac.grants.items[i];
            out.add("  {s} {s} {s} {d}", .{ self.rbac.roles.items[grant.role], grant.action,
                 grant.resource_type, self.grants[i] });
        }
        out.extend(self.domainAnalysis());
        out.add("coverage {d}", .{self.requests.items.len});
        var uncovered: std.ArrayList(*Element) = .empty;
        for (self.rules.items) |rule| {
            const symbols = self.coverage[rule.index].items;
            var count: usize = 0;
            for (symbols) |symbol| if (symbol == 'P' or symbol == 'D') {
                count += 1;
            };
            out.add("  {s} {s} {d}", .{ rule.identifier, symbols, count });
            if (count == 0) x.append(*Element, &uncovered, rule);
        }
        out.add("uncovered {d}", .{uncovered.items.len});
        for (uncovered.items) |rule| out.add("  {s}", .{rule.identifier});
        out.add("summary", .{});
        for ([_][]const u8{ "PERMIT", "DENY", "NOT_APPLICABLE", "INDETERMINATE", "ERROR" },
             self.decisions) |name, count| out.add("  decision {s} {d}", .{ name, count });
        out.add("  refused {d}", .{self.refused});
        for (self.policies.elements.items) |element| if (self.decisive[element.index] > 0) out.add("  decisive {s} {d}",
             .{ element.identifier, self.decisive[element.index] });
        for ([_]*std.ArrayList(Counter){ &self.obligations, &self.advice }, [_][]const u8{ "obligation",
             "advice" }) |list, kind| {
            std.mem.sort(Counter, list.items, {}, struct {
                fn less(_: void, left: Counter, right: Counter) bool {
                    return std.mem.lessThan(u8, left.identifier, right.identifier);
                }
            }.less);
            for (list.items) |entry| out.add("  {s} {s} {d}", .{ kind, entry.identifier, entry.count });
        }
        return out;
    }
    fn write(io: std.Io, name: []const u8, lines: x.Lines) !void {
        var data: x.Text = .{};
        for (lines.data.items) |line| data.add("{s}\n", .{line});
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = x.fmt("output/{s}", .{name}), .data = data.value() });
    }
    fn run(self: *Engine, io: std.Io) !void {
        try self.read(io);
        const requests = self.processRequests();
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try write(io, "decisions.txt", requests.decisions);
        try write(io, "traces.txt", requests.traces);
        try write(io, "permissions.txt", self.permissionReport());
        try write(io, "analysis.txt", self.analysisReport());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    x.allocator = arena.allocator();
    var engine: Engine = .{ .work_allocator = init.gpa };
    try engine.run(init.io);
}
