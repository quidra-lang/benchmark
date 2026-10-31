const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error;

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn number(text: Text) Int {
    return std.fmt.parseInt(Int, text, 10) catch unreachable;
}
fn truth(value: bool) Int {
    return @intFromBool(value);
}
fn words(gpa: Allocator, text: Text) Error![]const Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |item| try result.append(gpa, item);
    return result.items;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Error!void {
        const text = try std.fmt.allocPrint(self.gpa, format, args);
        defer self.gpa.free(text);
        try self.add(text);
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.print(format ++ "\n", args);
    }
};

const Expression = struct {
    op: Text,
    name: Text = "",
    value: Int = 0,
    left: ?*Expression = null,
    right: ?*Expression = null,
};
const operators = [_][]const Text{ &.{"||"}, &.{"&&"}, &.{ "==", "!=", "<", "<=", ">", ">=" }, &.{ "+", "-" }, &.{ "*", "/", "%" } };
fn member(items: []const Text, value: Text) bool {
    for (items) |item| if (equal(item, value)) return true;
    return false;
}
const ExpressionParser = struct {
    gpa: Allocator,
    tokens: []const Text,
    position: usize = 0,
    fn node(self: *ExpressionParser, value: Expression) Error!*Expression {
        const result = try self.gpa.create(Expression);
        result.* = value;
        return result;
    }
    fn binary(self: *ExpressionParser, level: usize) Error!*Expression {
        if (level == operators.len) return self.unary();
        var result = try self.binary(level + 1);
        while (self.position < self.tokens.len and member(operators[level], self.tokens[self.position])) {
            const op = self.tokens[self.position];
            self.position += 1;
            result = try self.node(.{ .op = op, .left = result, .right = try self.binary(level + 1) });
        }
        return result;
    }
    fn unary(self: *ExpressionParser) Error!*Expression {
        const token = self.tokens[self.position];
        self.position += 1;
        if (equal(token, "!") or equal(token, "-")) return self.node(.{ .op = if (equal(token, "!")) "unary!" else "unary-", .left = try self.unary() });
        if (equal(token, "(")) {
            const result = try self.binary(0);
            self.position += 1;
            return result;
        }
        if (equal(token, "in")) {
            self.position += 1;
            const name = self.tokens[self.position];
            self.position += 2;
            return self.node(.{ .op = "in", .name = name });
        }
        if (std.ascii.isDigit(token[0])) return self.node(.{ .op = "number", .value = number(token) });
        return self.node(.{ .op = "variable", .name = token });
    }
};
fn parseExpression(gpa: Allocator, text: Text) Error!*Expression {
    var tokens: std.ArrayList(Text) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (c == ' ') {
            i += 1;
            continue;
        }
        const start = i;
        if (std.ascii.isDigit(c)) {
            while (i < text.len and std.ascii.isDigit(text[i])) i += 1;
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) i += 1;
        } else {
            i += 1;
            if (i < text.len and member(&.{ "||", "&&", "==", "!=", "<=", ">=" }, text[start .. i + 1])) i += 1;
        }
        try tokens.append(gpa, text[start..i]);
    }
    var parser: ExpressionParser = .{ .gpa = gpa, .tokens = tokens.items };
    return parser.binary(0);
}
const ActionKind = enum { assign, raise, send, cancel, log };
const Action = struct {
    kind: ActionKind,
    name: Text = "",
    text: Text = "",
    delay: Int = 0,
    value: ?*Expression = null,
};
fn parseActions(gpa: Allocator, text: Text) Error![]const Action {
    var result: std.ArrayList(Action) = .empty;
    if (text.len == 0) return result.items;
    var iterator = std.mem.splitSequence(u8, text, "; ");
    while (iterator.next()) |item| {
        var action: Action = undefined;
        if (std.mem.startsWith(u8, item, "raise ")) {
            const tail = item[6..];
            const end = std.mem.findScalar(u8, tail, ' ') orelse tail.len;
            action = .{ .kind = .raise, .name = tail[0..end] };
            if (end < tail.len) action.value = try parseExpression(gpa, tail[end + 1 ..]);
        } else if (std.mem.startsWith(u8, item, "send ")) {
            const tail = item[5..];
            const end = std.mem.findScalar(u8, tail, ' ').?;
            const remainder = tail[end + 1 ..];
            const delayEnd = std.mem.findScalar(u8, remainder, ' ') orelse remainder.len;
            action = .{ .kind = .send, .name = tail[0..end], .delay = number(remainder[0..delayEnd]) };
            if (delayEnd < remainder.len) action.value = try parseExpression(gpa, remainder[delayEnd + 1 ..]);
        } else if (std.mem.startsWith(u8, item, "cancel ")) {
            action = .{ .kind = .cancel, .name = item[7..] };
        } else if (std.mem.startsWith(u8, item, "log ")) {
            action = .{ .kind = .log };
            const tail = item[4..];
            if (tail[0] == '"') {
                const end = std.mem.findScalar(u8, tail[1..], '"').? + 1;
                action.text = tail[1..end];
                if (end + 1 < tail.len) action.value = try parseExpression(gpa, tail[end + 2 ..]);
            } else action.value = try parseExpression(gpa, tail);
        } else {
            const end = std.mem.find(u8, item, " = ").?;
            action = .{ .kind = .assign, .name = item[0..end], .value = try parseExpression(gpa, item[end + 3 ..]) };
        }
        try result.append(gpa, action);
    }
    return result.items;
}

const StateKind = enum { root, state, parallel, final, history };
const State = struct {
    name: Text = "",
    kind: StateKind,
    parent: usize = 0,
    depth: usize = 0,
    initialName: Text = "",
    defaultName: Text = "",
    initial: usize = 0,
    defaultTarget: usize = 0,
    deep: bool = false,
    children: std.ArrayList(usize) = .empty,
    childStates: std.ArrayList(usize) = .empty,
    entries: std.ArrayList([]const Action) = .empty,
    exits: std.ArrayList([]const Action) = .empty,
    transitions: std.ArrayList(*Transition) = .empty,
    history: ?[]const usize = null,
    entered: Int = 0,
    taken: Int = 0,
    dwell: Int = 0,
    entryTime: Int = 0,
};
const TriggerKind = enum { event, timer, always };
const Mode = enum { internal, external, local };
const Transition = struct {
    source: usize,
    target: ?usize = null,
    targetName: Text = "",
    kind: TriggerKind = .event,
    mode: Mode = .internal,
    descriptors: []const Text = &.{},
    delay: Int = 0,
    guard: ?*Expression = null,
    actions: []const Action = &.{},
};
const Definition = struct { text: Text, line: usize, kind: Text = "", state: usize = 0, problem: ?Text = null };
const Event = struct { name: Text = "", value: Int = 0 };
const Reservation = struct { due: Int, order: Int = 0, timer: ?*Transition = null, event: Event = .{} };
const Trigger = struct { kind: TriggerKind = .event, timer: ?*Transition = null, event: Event = .{} };
const Selected = struct { transition: *Transition, scope: usize = 0, exits: []bool };

const Chart = struct {
    gpa: Allocator,
    out: *Builder,
    states: std.ArrayList(*State) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    variables: std.StringHashMapUnmanaged(Int) = .empty,
    variableNames: std.ArrayList(Text) = .empty,
    document: std.ArrayList(usize) = .empty,
    active: []bool = &.{},
    queue: std.ArrayList(Event) = .empty,
    queueHead: usize = 0,
    reservations: std.ArrayList(Reservation) = .empty,
    time: Int = 0,
    creation: Int = 0,
    data: Int = 0,
    macrosteps: Int = 0,
    microsteps: Int = 0,
    trace: bool = false,
    halted: bool = false,

    fn makeSet(self: *Chart) Error![]bool {
        const result = try self.gpa.alloc(bool, self.states.items.len);
        @memset(result, false);
        return result;
    }
    fn descendant(self: *Chart, child: usize, ancestor: usize) bool {
        var id = child;
        while (id != 0) {
            id = self.states.items[id].parent;
            if (id == ancestor) return true;
        }
        return false;
    }
    fn compound(self: *Chart, id: usize) bool {
        return id == 0 or self.states.items[id].kind == .state and self.states.items[id].childStates.items.len > 0;
    }
    fn parallel(self: *Chart, id: usize) bool {
        return self.states.items[id].kind == .parallel and self.states.items[id].childStates.items.len > 0;
    }
    fn problem(self: *Chart, comptime format: Text, args: anytype) Error!?Text {
        return try std.fmt.allocPrint(self.gpa, format, args);
    }
    fn reference(self: *Chart, expression: ?*const Expression) Error!?Text {
        const e = expression orelse return null;
        if (equal(e.op, "variable") and !equal(e.name, "_data") and !self.variables.contains(e.name)) return self.problem("unknown variable {s}", .{e.name});
        if (equal(e.op, "in") and !self.names.contains(e.name)) return self.problem("unknown state {s}", .{e.name});
        if (try self.reference(e.left)) |message| return message;
        return self.reference(e.right);
    }
    fn actionReferences(self: *Chart, actions: []const Action) Error!?Text {
        for (actions) |action| {
            if (action.kind == .assign and !self.variables.contains(action.name)) return self.problem("unknown variable {s}", .{action.name});
            if (try self.reference(action.value)) |message| return message;
        }
        return null;
    }
    fn parseTransition(self: *Chart, text: Text) Error!*Transition {
        const endSource = std.mem.findScalar(u8, text[3..], ' ').? + 3;
        const transition = try self.gpa.create(Transition);
        transition.* = .{ .source = self.names.get(text[3..endSource]).? };
        var tail = text[endSource + 1 ..];
        var bracket: usize = 0;
        var i: usize = 0;
        while (i + 2 < tail.len) : (i += 1) {
            if (tail[i] == '[') bracket += 1;
            if (tail[i] == ']') bracket -= 1;
            if (bracket == 0 and equal(tail[i .. i + 3], " / ")) {
                transition.actions = try parseActions(self.gpa, tail[i + 3 ..]);
                tail = tail[0..i];
                break;
            }
        }
        if (std.mem.find(u8, tail, " [")) |start| {
            const end = std.mem.findScalar(u8, tail[start + 2 ..], ']').? + start + 2;
            transition.guard = try parseExpression(self.gpa, tail[start + 2 .. end]);
            tail = try std.mem.concat(self.gpa, u8, &.{ tail[0..start], tail[end + 1 ..] });
        }
        for ([_]Text{ " -> ", " ~> " }) |arrow| {
            if (std.mem.find(u8, tail, arrow)) |position| {
                transition.mode = if (equal(arrow, " -> ")) .external else .local;
                transition.targetName = tail[position + 4 ..];
                transition.target = self.names.get(transition.targetName);
                tail = tail[0..position];
                break;
            }
        }
        if (equal(tail, "always")) {
            transition.kind = .always;
        } else if (std.mem.startsWith(u8, tail, "after ")) {
            transition.kind = .timer;
            transition.delay = number(tail[6..]);
        } else {
            var descriptors: std.ArrayList(Text) = .empty;
            var iterator = std.mem.splitScalar(u8, tail, '|');
            while (iterator.next()) |descriptor| try descriptors.append(self.gpa, descriptor);
            transition.descriptors = descriptors.items;
        }
        return transition;
    }
    fn visit(self: *Chart, id: usize) Error!void {
        try self.document.append(self.gpa, id);
        for (self.states.items[id].children.items) |child| try self.visit(child);
    }
    fn define(self: *Chart, definitions: []Definition) Error!bool {
        const root = try self.gpa.create(State);
        root.* = .{ .kind = .root };
        try self.states.append(self.gpa, root);
        for (definitions) |*definition| {
            const fields = try words(self.gpa, definition.text);
            definition.kind = fields[0];
            if (member(&.{ "state", "parallel", "final", "history" }, definition.kind)) {
                const name = fields[1];
                if (self.names.contains(name)) {
                    definition.problem = try self.problem("duplicate state {s}", .{name});
                    continue;
                }
                const parentName = if (fields.len > 2 and !equal(fields[2], "initial")) fields[2] else "";
                var parent: usize = 0;
                if (parentName.len > 0) {
                    parent = self.names.get(parentName) orelse {
                        definition.problem = try self.problem("unknown state {s}", .{parentName});
                        continue;
                    };
                    if (self.states.items[parent].kind == .final or self.states.items[parent].kind == .history) {
                        definition.problem = try self.problem("{s} cannot have children", .{parentName});
                        continue;
                    }
                }
                const state = try self.gpa.create(State);
                state.* = .{ .name = name, .kind = std.meta.stringToEnum(StateKind, definition.kind).?, .parent = parent, .depth = self.states.items[parent].depth + 1 };
                if (state.kind == .state) {
                    for (fields[2..], 2..) |field, index| if (equal(field, "initial")) {
                        state.initialName = fields[index + 1];
                        break;
                    };
                }
                if (state.kind == .history) {
                    state.deep = equal(fields[3], "deep");
                    if (fields.len == 5) state.defaultName = fields[4];
                }
                definition.state = self.states.items.len;
                try self.names.put(self.gpa, name, definition.state);
                try self.states.append(self.gpa, state);
                try self.states.items[parent].children.append(self.gpa, definition.state);
                if (state.kind != .history) try self.states.items[parent].childStates.append(self.gpa, definition.state);
            } else if (equal(definition.kind, "var")) {
                if (self.variables.contains(fields[1])) {
                    definition.problem = try self.problem("duplicate variable {s}", .{fields[1]});
                } else {
                    try self.variables.put(self.gpa, fields[1], number(fields[2]));
                    try self.variableNames.append(self.gpa, fields[1]);
                }
            }
        }
        for (definitions) |*definition| {
            if (definition.problem != null) continue;
            const fields = try words(self.gpa, definition.text);
            if (equal(definition.kind, "state")) {
                const state = self.states.items[definition.state];
                if (state.initialName.len > 0) {
                    if (self.names.get(state.initialName)) |child| {
                        if (self.states.items[child].parent != definition.state or self.states.items[child].kind == .history) definition.problem = try self.problem("{s} is not a child of {s}", .{ state.initialName, state.name });
                    } else definition.problem = try self.problem("unknown state {s}", .{state.initialName});
                }
            } else if (member(&.{ "final", "history" }, definition.kind)) {
                const state = self.states.items[definition.state];
                const parent = self.states.items[state.parent];
                if (parent.kind != .state or parent.childStates.items.len == 0) {
                    definition.problem = try self.problem("{s} needs a compound parent", .{state.name});
                } else if (state.kind == .history and state.defaultName.len > 0) {
                    if (self.names.get(state.defaultName)) |target| {
                        if (!self.descendant(target, state.parent) or self.states.items[target].kind == .history) definition.problem = try self.problem("{s} is not a descendant of {s}", .{ state.defaultName, parent.name });
                    } else definition.problem = try self.problem("unknown state {s}", .{state.defaultName});
                }
            } else if (member(&.{ "entry", "exit" }, definition.kind)) {
                if (self.names.get(fields[1])) |id| {
                    const state = self.states.items[id];
                    if (state.kind == .history) {
                        definition.problem = try self.problem("{s} cannot have actions", .{state.name});
                    } else {
                        const separator = std.mem.find(u8, definition.text, " / ").?;
                        const actions = try parseActions(self.gpa, definition.text[separator + 3 ..]);
                        definition.problem = try self.actionReferences(actions);
                        if (definition.problem == null) {
                            if (equal(definition.kind, "entry")) {
                                try state.entries.append(self.gpa, actions);
                            } else try state.exits.append(self.gpa, actions);
                        }
                    }
                } else definition.problem = try self.problem("unknown state {s}", .{fields[1]});
            } else if (equal(definition.kind, "on")) {
                if (self.names.get(fields[1])) |id| {
                    const state = self.states.items[id];
                    if (state.kind == .final or state.kind == .history) {
                        definition.problem = try self.problem("{s} cannot have transitions", .{state.name});
                    } else {
                        const transition = try self.parseTransition(definition.text);
                        definition.problem = try self.reference(transition.guard);
                        if (definition.problem == null and transition.targetName.len > 0 and transition.target == null) definition.problem = try self.problem("unknown state {s}", .{transition.targetName});
                        if (definition.problem == null) definition.problem = try self.actionReferences(transition.actions);
                        if (definition.problem == null) try state.transitions.append(self.gpa, transition);
                    }
                } else definition.problem = try self.problem("unknown state {s}", .{fields[1]});
            }
        }
        var valid = true;
        for (definitions) |definition| if (definition.problem) |message| {
            try self.out.line("error line {d}: {s}", .{ definition.line, message });
            valid = false;
        };
        if (!valid) return false;
        for (self.states.items) |state| if (state.childStates.items.len > 0) {
            state.initial = if (state.initialName.len > 0) self.names.get(state.initialName).? else state.childStates.items[0];
        };
        for (self.states.items) |state| if (state.kind == .history) {
            state.defaultTarget = if (state.defaultName.len > 0) self.names.get(state.defaultName).? else self.states.items[state.parent].initial;
        };
        for (root.children.items) |child| try self.visit(child);
        std.mem.sort(Text, self.variableNames.items, {}, struct {
            fn less(_: void, a: Text, b: Text) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.less);
        self.active = try self.makeSet();
        return true;
    }
    fn warn(self: *Chart) Error!void {
        const reachable = try self.makeSet();
        reachable[self.states.items[0].initial] = true;
        var changed = true;
        while (changed) {
            changed = false;
            for (self.document.items) |id| {
                if (!reachable[id]) continue;
                const state = self.states.items[id];
                if (state.parent != 0 and !reachable[state.parent]) {
                    reachable[state.parent] = true;
                    changed = true;
                }
                if (self.compound(id) and !reachable[state.initial]) {
                    reachable[state.initial] = true;
                    changed = true;
                }
                if (self.parallel(id)) for (state.childStates.items) |child| {
                    if (!reachable[child]) {
                        reachable[child] = true;
                        changed = true;
                    }
                };
                for (state.transitions.items) |transition| if (transition.target) |rawTarget| {
                    const target = if (self.states.items[rawTarget].kind == .history) self.states.items[rawTarget].defaultTarget else rawTarget;
                    if (!reachable[target]) {
                        reachable[target] = true;
                        changed = true;
                    }
                };
            }
        }
        for (self.document.items) |id| if (self.states.items[id].kind != .history and !reachable[id]) try self.out.line("warning: unreachable state {s}", .{self.states.items[id].name});
    }
    fn evaluate(self: *Chart, e: *const Expression) ?Int {
        if (equal(e.op, "number")) return e.value;
        if (equal(e.op, "variable")) return if (equal(e.name, "_data")) self.data else self.variables.get(e.name).?;
        if (equal(e.op, "in")) return truth(self.active[self.names.get(e.name).?]);
        const a = self.evaluate(e.left.?) orelse return null;
        if (equal(e.op, "unary!")) return truth(a == 0);
        if (equal(e.op, "unary-")) return -a;
        if (equal(e.op, "&&") and a == 0) return 0;
        if (equal(e.op, "||") and a != 0) return 1;
        const b = self.evaluate(e.right.?) orelse return null;
        if (equal(e.op, "+")) return a + b;
        if (equal(e.op, "-")) return a - b;
        if (equal(e.op, "*")) return a * b;
        if (equal(e.op, "/") or equal(e.op, "%")) {
            if (b == 0) return null;
            return if (equal(e.op, "/")) @divTrunc(a, b) else @rem(a, b);
        }
        if (equal(e.op, "==")) return truth(a == b);
        if (equal(e.op, "!=")) return truth(a != b);
        if (equal(e.op, "<")) return truth(a < b);
        if (equal(e.op, "<=")) return truth(a <= b);
        if (equal(e.op, ">")) return truth(a > b);
        if (equal(e.op, ">=")) return truth(a >= b);
        return truth(b != 0);
    }
    fn enqueue(self: *Chart, name: Text, value: Int) Error!void {
        try self.queue.append(self.gpa, .{ .name = name, .value = value });
    }
    fn reserve(self: *Chart, raw: Reservation) Error!void {
        self.creation += 1;
        var reservation = raw;
        reservation.order = self.creation;
        try self.reservations.append(self.gpa, reservation);
    }
    fn perform(self: *Chart, actions: []const Action) Error!void {
        for (actions) |action| {
            var value: Int = 0;
            if (action.value) |expression| value = self.evaluate(expression) orelse {
                try self.enqueue("error.execution", 0);
                return;
            };
            switch (action.kind) {
                .assign => try self.variables.put(self.gpa, action.name, value),
                .raise => try self.enqueue(action.name, value),
                .send => try self.reserve(.{ .due = self.time + action.delay, .event = .{ .name = action.name, .value = value } }),
                .cancel => {
                    var i: usize = 0;
                    while (i < self.reservations.items.len) {
                        const reservation = self.reservations.items[i];
                        if (reservation.timer == null and equal(reservation.event.name, action.name)) {
                            _ = self.reservations.orderedRemove(i);
                        } else i += 1;
                    }
                },
                .log => {
                    if (action.value != null) {
                        try self.out.line("{s}{d}", .{ action.text, value });
                    } else try self.out.line("{s}", .{action.text});
                },
            }
        }
    }
    fn targets(self: *Chart, transition: *const Transition) Error![]const usize {
        const target = transition.target.?;
        if (self.states.items[target].kind == .history) {
            if (self.states.items[target].history) |recorded| return recorded;
            const result = try self.gpa.alloc(usize, 1);
            result[0] = self.states.items[target].defaultTarget;
            return result;
        }
        const result = try self.gpa.alloc(usize, 1);
        result[0] = target;
        return result;
    }
    fn containsTargets(self: *Chart, scope: usize, targetList: []const usize) bool {
        for (targetList) |target| if (!self.descendant(target, scope)) return false;
        return true;
    }
    fn transitionSet(self: *Chart, transition: *Transition) Error!Selected {
        var result: Selected = .{ .transition = transition, .exits = try self.makeSet() };
        if (transition.mode == .internal) return result;
        const targetList = try self.targets(transition);
        if (transition.mode == .local and self.compound(transition.source) and self.containsTargets(transition.source, targetList)) {
            result.scope = transition.source;
        } else {
            var id = self.states.items[transition.source].parent;
            while (!(self.compound(id) and self.containsTargets(id, targetList))) id = self.states.items[id].parent;
            result.scope = id;
        }
        for (self.document.items) |id| result.exits[id] = self.active[id] and self.descendant(id, result.scope);
        return result;
    }
    fn matches(transition: *const Transition, trigger: Trigger) bool {
        if (transition.kind != trigger.kind) return false;
        if (trigger.kind == .always) return true;
        if (trigger.kind == .timer) return transition == trigger.timer.?;
        for (transition.descriptors) |descriptor| {
            const name = trigger.event.name;
            if (equal(descriptor, "*") or equal(descriptor, name) or name.len > descriptor.len and std.mem.startsWith(u8, name, descriptor) and name[descriptor.len] == '.') return true;
        }
        return false;
    }
    fn selectTransitions(self: *Chart, trigger: Trigger) Error![]const Selected {
        var result: std.ArrayList(Selected) = .empty;
        var seen: std.ArrayList(*Transition) = .empty;
        const occupied = try self.makeSet();
        for (self.document.items) |atomic| {
            if (!self.active[atomic] or self.states.items[atomic].childStates.items.len != 0) continue;
            var found: ?*Transition = null;
            var id = atomic;
            while (id != 0 and found == null) : (id = self.states.items[id].parent) {
                for (self.states.items[id].transitions.items) |transition| {
                    if (!matches(transition, trigger)) continue;
                    const value: ?Int = if (transition.guard) |guard| self.evaluate(guard) else 1;
                    if (value) |actual| {
                        if (actual != 0) {
                            found = transition;
                            break;
                        }
                    } else try self.enqueue("error.execution", 0);
                }
            }
            const transition = found orelse continue;
            if (std.mem.findScalar(*Transition, seen.items, transition) != null) continue;
            try seen.append(self.gpa, transition);
            const selected = try self.transitionSet(transition);
            var conflict = false;
            for (self.document.items) |candidate| if (selected.exits[candidate] and occupied[candidate]) {
                conflict = true;
                break;
            };
            if (!conflict) {
                try result.append(self.gpa, selected);
                for (self.document.items) |candidate| occupied[candidate] = occupied[candidate] or selected.exits[candidate];
            }
        }
        return result.items;
    }
    fn expand(self: *Chart, entries: []bool) void {
        var changed = true;
        while (changed) {
            changed = false;
            for (self.document.items) |id| {
                if (!entries[id]) continue;
                const state = self.states.items[id];
                if (self.parallel(id)) {
                    for (state.childStates.items) |child| if (!entries[child]) {
                        entries[child] = true;
                        changed = true;
                    };
                } else if (self.compound(id)) {
                    var hasChild = false;
                    for (state.childStates.items) |child| if (entries[child]) {
                        hasChild = true;
                        break;
                    };
                    if (!hasChild) {
                        entries[state.initial] = true;
                        changed = true;
                    }
                }
            }
        }
    }
    fn complete(self: *Chart, id: usize) bool {
        const state = self.states.items[id];
        if (self.compound(id)) {
            for (state.childStates.items) |child| if (self.states.items[child].kind == .final and self.active[child]) return true;
        } else if (self.parallel(id)) {
            for (state.childStates.items) |child| if (!self.complete(child)) return false;
            return true;
        }
        return false;
    }
    fn enter(self: *Chart, entries: []const bool) Error!void {
        for (self.document.items) |id| {
            if (!entries[id]) continue;
            const state = self.states.items[id];
            self.active[id] = true;
            state.entered += 1;
            state.entryTime = self.time;
            for (state.transitions.items) |transition| if (transition.kind == .timer) try self.reserve(.{ .due = self.time + transition.delay, .timer = transition });
            for (state.entries.items) |actions| try self.perform(actions);
            if (state.kind == .final) {
                const parent = state.parent;
                try self.enqueue(try std.fmt.allocPrint(self.gpa, "done.state.{s}", .{self.states.items[parent].name}), 0);
                const grandparent = self.states.items[parent].parent;
                if (self.parallel(grandparent) and self.complete(grandparent)) try self.enqueue(try std.fmt.allocPrint(self.gpa, "done.state.{s}", .{self.states.items[grandparent].name}), 0);
            }
        }
    }
    fn stateList(self: *Chart, set: []const bool, reverse: bool) Error!Text {
        var result: Builder = .{ .gpa = self.gpa };
        var count: usize = 0;
        var index: usize = 0;
        while (index < self.document.items.len) : (index += 1) {
            const id = self.document.items[if (reverse) self.document.items.len - 1 - index else index];
            if (set[id]) {
                if (count > 0) try result.add(",");
                try result.add(self.states.items[id].name);
                count += 1;
            }
        }
        return if (count == 0) "-" else result.bytes.items;
    }
    fn microstep(self: *Chart, trigger: Trigger, transitions: []const Selected) Error!void {
        const exits = try self.makeSet();
        for (transitions) |selected| for (self.document.items) |id| {
            exits[id] = exits[id] or selected.exits[id];
        };
        for (self.document.items) |id| {
            const history = self.states.items[id];
            if (history.kind != .history or !exits[history.parent]) continue;
            var recorded: std.ArrayList(usize) = .empty;
            for (self.document.items) |candidate| {
                const state = self.states.items[candidate];
                if (self.active[candidate] and (history.deep and state.childStates.items.len == 0 and self.descendant(candidate, history.parent) or !history.deep and state.parent == history.parent)) try recorded.append(self.gpa, candidate);
            }
            history.history = recorded.items;
        }
        const entries = try self.makeSet();
        for (transitions) |selected| {
            if (selected.transition.mode == .internal) continue;
            for (try self.targets(selected.transition)) |target| {
                entries[target] = true;
                var parent = self.states.items[target].parent;
                while (parent != 0 and self.descendant(parent, selected.scope)) : (parent = self.states.items[parent].parent) entries[parent] = true;
            }
        }
        self.expand(entries);
        if (self.trace) {
            var sources: Builder = .{ .gpa = self.gpa };
            for (transitions, 0..) |selected, i| {
                if (i > 0) try sources.add(",");
                try sources.add(self.states.items[selected.transition.source].name);
            }
            const display = switch (trigger.kind) {
                .always => "always",
                .timer => try std.fmt.allocPrint(self.gpa, "after({d})@{s}", .{ trigger.timer.?.delay, self.states.items[trigger.timer.?.source].name }),
                .event => if (trigger.event.value == 0) trigger.event.name else try std.fmt.allocPrint(self.gpa, "{s}={d}", .{ trigger.event.name, trigger.event.value }),
            };
            try self.out.line("[t={d}] {s} ({s}): exit {s}; enter {s}", .{ self.time, display, sources.bytes.items, try self.stateList(exits, true), try self.stateList(entries, false) });
        }
        var index = self.document.items.len;
        while (index > 0) {
            index -= 1;
            const id = self.document.items[index];
            if (!exits[id]) continue;
            const state = self.states.items[id];
            for (state.exits.items) |actions| try self.perform(actions);
            self.active[id] = false;
            state.dwell += self.time - state.entryTime;
            var i: usize = 0;
            while (i < self.reservations.items.len) {
                if (self.reservations.items[i].timer) |timer| {
                    if (timer.source == id) {
                        _ = self.reservations.orderedRemove(i);
                        continue;
                    }
                }
                i += 1;
            }
        }
        for (transitions) |selected| {
            try self.perform(selected.transition.actions);
            self.states.items[selected.transition.source].taken += 1;
        }
        try self.enter(entries);
    }
    fn performMicrostep(self: *Chart, trigger: Trigger, transitions: []const Selected, count: *usize) Error!bool {
        if (transitions.len == 0) return true;
        if (count.* == 1000) {
            try self.out.line("LIVELOCK t={d}", .{self.time});
            self.halted = true;
            return false;
        }
        count.* += 1;
        self.microsteps += 1;
        try self.microstep(trigger, transitions);
        return true;
    }
    fn macrostep(self: *Chart, start: bool, trigger: Trigger) Error!void {
        self.macrosteps += 1;
        var count: usize = 0;
        self.data = 0;
        if (start) {
            const entries = try self.makeSet();
            entries[self.states.items[0].initial] = true;
            self.expand(entries);
            try self.enter(entries);
        } else {
            if (trigger.kind == .event) self.data = trigger.event.value;
            if (!try self.performMicrostep(trigger, try self.selectTransitions(trigger), &count)) return;
        }
        while (true) {
            self.data = 0;
            const always: Trigger = .{ .kind = .always };
            const transitions = try self.selectTransitions(always);
            if (transitions.len > 0) {
                if (!try self.performMicrostep(always, transitions, &count)) return;
                continue;
            }
            if (self.queueHead == self.queue.items.len) return;
            const event = self.queue.items[self.queueHead];
            self.queueHead += 1;
            self.data = event.value;
            const next: Trigger = .{ .kind = .event, .event = event };
            if (!try self.performMicrostep(next, try self.selectTransitions(next), &count)) return;
        }
    }
    fn dump(self: *Chart) Error!void {
        try self.out.line("dump t={d}", .{self.time});
        for (self.document.items) |id| if (self.active[id]) {
            for (0..self.states.items[id].depth * 2) |_| try self.out.add(" ");
            try self.out.line("{s}", .{self.states.items[id].name});
        };
        for (self.variableNames.items) |name| try self.out.line("  var {s} = {d}", .{ name, self.variables.get(name).? });
        for (self.document.items) |id| if (self.states.items[id].history) |recorded| {
            var list: Builder = .{ .gpa = self.gpa };
            for (recorded, 0..) |target, i| {
                if (i > 0) try list.add(",");
                try list.add(self.states.items[target].name);
            }
            try self.out.line("  history {s} = {s}", .{ self.states.items[id].name, if (recorded.len == 0) "-" else list.bytes.items });
        };
        const reservations = try self.gpa.dupe(Reservation, self.reservations.items);
        std.mem.sort(Reservation, reservations, {}, struct {
            fn less(_: void, a: Reservation, b: Reservation) bool {
                return reservationLess(a, b);
            }
        }.less);
        for (reservations) |reservation| {
            if (reservation.timer) |timer| {
                try self.out.line("  timer {d} after({d})@{s}", .{ reservation.due, timer.delay, self.states.items[timer.source].name });
            } else try self.out.line("  send {d} {s} {d}", .{ reservation.due, reservation.event.name, reservation.event.value });
        }
    }
    fn script(self: *Chart, text: Text) Error!void {
        if (self.halted) return;
        const fields = try words(self.gpa, text);
        if (equal(fields[0], "event")) {
            try self.macrostep(false, .{ .event = .{ .name = fields[1], .value = if (fields.len == 3) number(fields[2]) else 0 } });
        } else if (equal(fields[0], "tick")) {
            const finish = self.time + number(fields[1]);
            while (!self.halted) {
                var best: ?usize = null;
                for (self.reservations.items, 0..) |reservation, i| if (reservation.due <= finish and (best == null or reservationLess(reservation, self.reservations.items[best.?]))) {
                    best = i;
                };
                const index = best orelse break;
                const reservation = self.reservations.orderedRemove(index);
                self.time = reservation.due;
                try self.macrostep(false, if (reservation.timer) |timer| .{ .kind = .timer, .timer = timer } else .{ .event = reservation.event });
            }
            if (!self.halted) self.time = finish;
        } else if (equal(fields[0], "set")) {
            if (self.variables.contains(fields[1])) {
                try self.variables.put(self.gpa, fields[1], number(fields[2]));
            } else try self.out.line("error: unknown variable {s}", .{fields[1]});
        } else if (equal(fields[0], "trace")) {
            self.trace = equal(fields[1], "on");
        } else if (equal(fields[0], "eval")) {
            const raw = text[5..];
            const expression = try parseExpression(self.gpa, raw);
            if (try self.reference(expression)) |message| {
                try self.out.line("error: {s}", .{message});
            } else {
                self.data = 0;
                if (self.evaluate(expression)) |value| {
                    try self.out.line("{s} -> {d}", .{ raw, value });
                } else try self.out.line("error: division by zero", .{});
            }
        } else if (equal(fields[0], "dump")) try self.dump();
    }
    fn statistics(self: *Chart) Error!void {
        try self.out.line("end t={d} macrosteps={d} microsteps={d}", .{ self.time, self.macrosteps, self.microsteps });
        for (self.document.items) |id| {
            const state = self.states.items[id];
            if (state.kind == .history) continue;
            const dwell = state.dwell + if (self.active[id]) self.time - state.entryTime else 0;
            try self.out.line("  {s} entered={d} taken={d} time={d}", .{ state.name, state.entered, state.taken, dwell });
        }
    }
};
fn reservationLess(a: Reservation, b: Reservation) bool {
    return a.due < b.due or a.due == b.due and a.order < b.order;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const count = number(std.mem.trimEnd(u8, lines.next().?, "\r"));
    var lineNumber: usize = 1;
    var out: Builder = .{ .gpa = gpa };
    var chartIndex: Int = 0;
    while (chartIndex < count) : (chartIndex += 1) {
        const header = std.mem.trimEnd(u8, lines.next().?, "\r");
        lineNumber += 1;
        try out.line("chart {s}", .{header[6..]});
        var chartArena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer chartArena.deinit();
        const chartAllocator = chartArena.allocator();
        var definitions: std.ArrayList(Definition) = .empty;
        while (lines.next()) |raw| {
            lineNumber += 1;
            const line = std.mem.trimEnd(u8, raw, "\r");
            if (equal(line, "RUN")) break;
            try definitions.append(chartAllocator, .{ .text = line, .line = lineNumber });
        }
        var chart: Chart = .{ .gpa = chartAllocator, .out = &out };
        const valid = try chart.define(definitions.items);
        if (valid) {
            try chart.warn();
            try chart.macrostep(true, .{});
        }
        while (lines.next()) |raw| {
            lineNumber += 1;
            const line = std.mem.trimEnd(u8, raw, "\r");
            if (equal(line, "END")) break;
            if (valid) try chart.script(line);
        }
        if (valid) try chart.statistics();
    }
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
