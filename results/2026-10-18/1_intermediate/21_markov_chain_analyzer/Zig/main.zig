const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const max_states = 10;

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn index(text: []const u8) usize { return @intCast(integer(text)); }
fn yes(value: bool) []const u8 { return if (value) "yes" else "no"; }
fn gcd(a: i64, b: i64) i64 {
    var x = if (a < 0) -a else a;
    var y = if (b < 0) -b else b;
    while (y != 0) {
        const remainder = @mod(x, y);
        x = y;
        y = remainder;
    }
    return x;
}

const Fraction = struct {
    numerator: i64 = 0,
    denominator: i64 = 1,
    const zero: Fraction = .{};
    const one: Fraction = .{ .numerator = 1 };
    const two: Fraction = .{ .numerator = 2 };

    fn init(numerator: i64, denominator: i64) Fraction {
        const divisor = gcd(numerator, denominator) * @as(i64, if (denominator < 0) -1 else 1);
        return .{ .numerator = @divTrunc(numerator, divisor), .denominator = @divTrunc(denominator, divisor) };
    }
    fn add(a: Fraction, b: Fraction) Fraction {
        return init(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator);
    }
    fn sub(a: Fraction, b: Fraction) Fraction {
        return init(a.numerator * b.denominator - b.numerator * a.denominator, a.denominator * b.denominator);
    }
    fn mul(a: Fraction, b: Fraction) Fraction { return init(a.numerator * b.numerator, a.denominator * b.denominator); }
    fn div(a: Fraction, b: Fraction) Fraction { return init(a.numerator * b.denominator, a.denominator * b.numerator); }
    fn absolute(a: Fraction) Fraction { return .{ .numerator = if (a.numerator < 0) -a.numerator else a.numerator, .denominator = a.denominator }; }
    fn eq(a: Fraction, b: Fraction) bool { return a.numerator == b.numerator and a.denominator == b.denominator; }
    fn less(a: Fraction, b: Fraction) bool { return a.numerator * b.denominator < b.numerator * a.denominator; }
    fn isZero(a: Fraction) bool { return a.numerator == 0; }
    fn value(a: Fraction) Value { return .{ .fraction = a }; }
    pub fn format(a: Fraction, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{d}/{d}", .{ a.numerator, a.denominator });
    }
};
const Value = struct {
    fraction: Fraction,
    pub fn format(value: Value, out: *std.Io.Writer) std.Io.Writer.Error!void {
        const f = value.fraction;
        try out.print("{f}({d}.{d:0>6})", .{ f, @divTrunc(f.numerator, f.denominator), @divTrunc(@mod(f.numerator, f.denominator) * 1000000, f.denominator) });
    }
};
const Vector = [max_states]Fraction;
const Matrix = [max_states]Vector;
const Equations = [max_states][2 * max_states]Fraction;
const zero_vector: Vector = @splat(Fraction.zero);
const zero_matrix: Matrix = @splat(zero_vector);
const zero_equations: Equations = @splat(@splat(Fraction.zero));

fn delta(i: usize, j: usize) Fraction { return if (i == j) Fraction.one else Fraction.zero; }
fn sum(values: []const Fraction) Fraction {
    var total = Fraction.zero;
    for (values) |value| total = total.add(value);
    return total;
}
fn identity(size: usize) Matrix {
    var result = zero_matrix;
    for (0..size) |i| result[i][i] = Fraction.one;
    return result;
}
fn advance(distribution: Vector, transitions: *const Matrix, size: usize) Vector {
    var result = zero_vector;
    for (0..size) |j| for (0..size) |i| {
        result[j] = result[j].add(distribution[i].mul(transitions[i][j]));
    };
    return result;
}
fn multiply(left: *const Matrix, right: *const Matrix, size: usize) Matrix {
    var result = zero_matrix;
    for (0..size) |i| result[i] = advance(left[i], right, size);
    return result;
}
fn solve(rows: *Equations, size: usize, width: usize) Matrix {
    for (0..size) |column| {
        var pivot_row = column;
        while (rows[pivot_row][column].isZero()) pivot_row += 1;
        const swap = rows[column];
        rows[column] = rows[pivot_row];
        rows[pivot_row] = swap;
        const pivot = rows[column][column];
        for (0..width) |j| rows[column][j] = rows[column][j].div(pivot);
        for (0..size) |i| {
            if (i == column) continue;
            const factor = rows[i][column];
            if (factor.isZero()) continue;
            for (0..width) |j| rows[i][j] = rows[i][j].sub(factor.mul(rows[column][j]));
        }
    }
    var result = zero_matrix;
    for (0..size) |i| for (0..width - size) |j| {
        result[i][j] = rows[i][size + j];
    };
    return result;
}

const StateList = struct {
    items: [max_states]usize = @splat(0),
    len: usize = 0,
    fn append(list: *StateList, state: usize) void {
        list.items[list.len] = state;
        list.len += 1;
    }
    fn slice(list: *const StateList) []const usize { return list.items[0..list.len]; }
    fn contains(list: *const StateList, state: usize) bool {
        for (list.slice()) |item| if (item == state) return true;
        return false;
    }
    fn sort(list: *StateList) void { std.mem.sort(usize, list.items[0..list.len], {}, std.sort.asc(usize)); }
};
const Component = struct {
    states: StateList = .{},
    closed: bool = true,
    period: i64 = 0,
    levels: [max_states]i64 = @splat(-1),
};
const Graph = struct {
    reach: [max_states][max_states]bool = @splat(@splat(false)),
    classes: [max_states]Component = undefined,
    count: usize = 0,
    class_of: [max_states]usize = @splat(0),
    fn reaches(graph: *const Graph, from: usize, targets: *const StateList) bool {
        for (targets.slice()) |target| if (graph.reach[from][target]) return true;
        return false;
    }
};
const Hitting = struct {
    probability: Vector = zero_vector,
    time: [max_states]?Fraction = @splat(null),
};
const Absorption = struct {
    transient: StateList = .{},
    absorbing: StateList = .{},
    fundamental: Matrix = zero_matrix,
    probability: Matrix = zero_matrix,
    mean: Vector = zero_vector,
    variance: Vector = zero_vector,
};

const Chain = struct {
    size: usize = 0,
    names: [max_states][]const u8 = @splat(""),
    p: Matrix = zero_matrix,

    fn find(chain: *const Chain, name: []const u8) ?usize {
        for (chain.names[0..chain.size], 0..) |candidate, i| if (equal(candidate, name)) return i;
        return null;
    }
    fn graph(chain: *const Chain) Graph {
        var result: Graph = .{};
        for (0..chain.size) |i| for (0..chain.size) |j| {
            result.reach[i][j] = i == j or !chain.p[i][j].isZero();
        };
        for (0..chain.size) |k| for (0..chain.size) |i| for (0..chain.size) |j| {
            result.reach[i][j] = result.reach[i][j] or (result.reach[i][k] and result.reach[k][j]);
        };
        var assigned: [max_states]bool = @splat(false);
        for (0..chain.size) |first| {
            if (assigned[first]) continue;
            var component: Component = .{};
            for (0..chain.size) |j| if (result.reach[first][j] and result.reach[j][first]) {
                component.states.append(j);
                assigned[j] = true;
                result.class_of[j] = result.count;
            };
            for (component.states.slice()) |i| for (0..chain.size) |j| {
                if (!component.states.contains(j) and !chain.p[i][j].isZero()) component.closed = false;
            };
            component.levels[first] = 0;
            var queue: StateList = .{};
            queue.append(first);
            var head: usize = 0;
            while (head < queue.len) : (head += 1) {
                const i = queue.items[head];
                for (component.states.slice()) |j| if (component.levels[j] < 0 and !chain.p[i][j].isZero()) {
                    component.levels[j] = component.levels[i] + 1;
                    queue.append(j);
                };
            }
            for (component.states.slice()) |i| for (component.states.slice()) |j| {
                if (!chain.p[i][j].isZero()) component.period = gcd(component.period, component.levels[i] + 1 - component.levels[j]);
            };
            result.classes[result.count] = component;
            result.count += 1;
        }
        return result;
    }
    fn stationary(chain: *const Chain, states: *const StateList) Vector {
        var equations = zero_equations;
        for (0..states.len - 1) |row| for (0..states.len) |col| {
            equations[row][col] = chain.p[states.items[col]][states.items[row]].sub(delta(col, row));
        };
        @memset(equations[states.len - 1][0..states.len + 1], Fraction.one);
        const solution = solve(&equations, states.len, states.len + 1);
        var distribution = zero_vector;
        for (states.slice(), 0..) |state, i| distribution[state] = solution[i][0];
        return distribution;
    }
    fn blockSum(chain: *const Chain, from: usize, targets: *const StateList) Fraction {
        var total = Fraction.zero;
        for (targets.slice()) |j| total = total.add(chain.p[from][j]);
        return total;
    }
    fn hitting(chain: *const Chain, targets: *const StateList, with_times: bool) Hitting {
        const topology = chain.graph();
        var unknown: StateList = .{};
        var result: Hitting = .{};
        for (targets.slice()) |i| {
            result.probability[i] = Fraction.one;
            result.time[i] = Fraction.zero;
        }
        for (0..chain.size) |i| if (!targets.contains(i) and topology.reaches(i, targets)) {
            unknown.append(i);
        };
        if (unknown.len > 0) {
            var equations = zero_equations;
            for (unknown.slice(), 0..) |from, i| {
                for (unknown.slice(), 0..) |to, j| equations[i][j] = delta(i, j).sub(chain.p[from][to]);
                equations[i][unknown.len] = chain.blockSum(from, targets);
            }
            const solution = solve(&equations, unknown.len, unknown.len + 1);
            for (unknown.slice(), 0..) |state, i| result.probability[state] = solution[i][0];
        }
        if (with_times) {
            var certain: StateList = .{};
            for (unknown.slice()) |i| if (result.probability[i].eq(Fraction.one)) {
                certain.append(i);
            };
            if (certain.len > 0) {
                var equations = zero_equations;
                for (certain.slice(), 0..) |from, i| {
                    for (certain.slice(), 0..) |to, j| equations[i][j] = delta(i, j).sub(chain.p[from][to]);
                    equations[i][certain.len] = Fraction.one;
                }
                const solution = solve(&equations, certain.len, certain.len + 1);
                for (certain.slice(), 0..) |state, i| result.time[state] = solution[i][0];
            }
        }
        return result;
    }
    fn absorption(chain: *const Chain) Absorption {
        var result: Absorption = .{};
        for (0..chain.size) |i| {
            if (chain.p[i][i].eq(Fraction.one)) result.absorbing.append(i) else result.transient.append(i);
        }
        const size = result.transient.len;
        if (size == 0) return result;
        var equations = zero_equations;
        for (result.transient.slice(), 0..) |from, i| for (result.transient.slice(), 0..) |to, j| {
            equations[i][j] = delta(i, j).sub(chain.p[from][to]);
            equations[i][size + j] = delta(i, j);
        };
        result.fundamental = solve(&equations, size, 2 * size);
        for (0..size) |i| result.mean[i] = sum(result.fundamental[i][0..size]);
        for (0..size) |i| {
            for (0..size) |j| result.variance[i] = result.variance[i].add(Fraction.two.mul(result.fundamental[i][j]).sub(delta(i, j)).mul(result.mean[j]));
            result.variance[i] = result.variance[i].sub(result.mean[i].mul(result.mean[i]));
            for (result.absorbing.slice(), 0..) |absorbing, j| for (result.transient.slice(), 0..) |transient, k| {
                result.probability[i][j] = result.probability[i][j].add(result.fundamental[i][k].mul(chain.p[transient][absorbing]));
            };
        }
        return result;
    }
};

const Command = enum {
    CHAIN, P, ROW, SHOW, CHECK, BUILD, GAMBLER, CLASSES, CLASSIFY, STEP, POWER, STATIONARY, RECURRENCE,
    ABSORB, HITTING, PASSAGE, FIRSTPASSAGE, PATHPROB, MOSTLIKELY, REVERSIBLE, REVERSE, MIXING, LUMP, REWARD, RESTRICT, SIMULATE,
};
const Analyzer = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    chains: std.StringHashMapUnmanaged(Chain) = .empty,
    error_message: []const u8 = "",

    fn fail(self: *Analyzer, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn state(self: *Analyzer, chain: *const Chain, name: []const u8) Error!usize {
        return chain.find(name) orelse return self.fail("UNKNOWN STATE {s}", .{name});
    }
    fn stateSet(self: *Analyzer, chain: *const Chain, words: []const []const u8) Error!StateList {
        var states: StateList = .{};
        for (words) |word| {
            const i = try self.state(chain, word);
            if (states.contains(i)) return self.fail("DUPLICATE STATE {s}", .{word});
            states.append(i);
        }
        states.sort();
        return states;
    }
    fn probability(self: *Analyzer, text: []const u8) Error!Fraction {
        var parts = std.mem.splitScalar(u8, text, '/');
        const numerator = integer(parts.next().?);
        const denominator = if (parts.next()) |part| integer(part) else 1;
        if (denominator == 0 or numerator > denominator) return self.fail("BAD PROBABILITY", .{});
        return Fraction.init(numerator, denominator);
    }
    fn stochastic(self: *Analyzer, chain: *const Chain) Error!void {
        for (0..chain.size) |i| if (!sum(chain.p[i][0..chain.size]).eq(Fraction.one)) {
            return self.fail("NOT STOCHASTIC {s}", .{chain.names[i]});
        };
    }
    fn uniqueStationary(self: *Analyzer, chain: *const Chain) Error!Vector {
        const topology = chain.graph();
        if (topology.count != 1) return self.fail("NOT IRREDUCIBLE", .{});
        return chain.stationary(&topology.classes[0].states);
    }
    fn labels(self: *Analyzer, chain: *const Chain, states: []const usize, separator: []const u8) Error!void {
        for (states, 0..) |i, position| {
            if (position > 0) try self.out.writeAll(separator);
            try self.out.writeAll(chain.names[i]);
        }
    }
    fn display(self: *Analyzer, chain: *const Chain, values: *const Matrix, label: []const u8) Error!void {
        try self.out.writeAll("STATES");
        for (chain.names[0..chain.size]) |name| try self.out.print(" {s}", .{name});
        try self.out.writeAll("\n");
        for (0..chain.size) |i| {
            try self.out.print("{s} {s}", .{ label, chain.names[i] });
            for (values[i][0..chain.size]) |value| try self.out.print(" {f}", .{value});
            try self.out.writeAll("\n");
        }
    }
    fn create(self: *Analyzer, words: []const []const u8) Error!void {
        if (words.len - 2 > max_states) return self.fail("TOO MANY STATES", .{});
        var chain: Chain = .{};
        for (words[2..]) |name| {
            if (chain.find(name) != null) return self.fail("DUPLICATE STATE {s}", .{name});
            chain.names[chain.size] = name;
            chain.size += 1;
        }
        try self.chains.put(self.gpa, words[1], chain);
        try self.out.print("CHAIN {s} states={d}\n", .{ words[1], chain.size });
    }
    fn build(self: *Analyzer, words: []const []const u8) Error!void {
        const order = index(words[2]);
        if (order != 1 and order != 2) return self.fail("BAD ORDER", .{});
        const tokens = words[3..];
        if (tokens.len <= order) return self.fail("TOO FEW TOKENS", .{});
        const count = tokens.len - order + 1;
        var observations: [60]usize = undefined;
        var chain: Chain = .{};
        for (0..count) |i| {
            const name = if (order == 1) tokens[i] else try std.fmt.allocPrint(self.gpa, "{s}.{s}", .{ tokens[i], tokens[i + 1] });
            if (chain.find(name)) |state_index| {
                observations[i] = state_index;
            } else {
                if (chain.size == max_states) return self.fail("TOO MANY STATES", .{});
                observations[i] = chain.size;
                chain.names[chain.size] = name;
                chain.size += 1;
            }
        }
        var counts: [max_states][max_states]i64 = @splat(@splat(0));
        var totals: [max_states]i64 = @splat(0);
        for (0..count - 1) |i| {
            counts[observations[i]][observations[i + 1]] += 1;
            totals[observations[i]] += 1;
        }
        for (0..chain.size) |i| {
            if (totals[i] == 0) {
                chain.p[i][i] = Fraction.one;
            } else {
                for (0..chain.size) |j| chain.p[i][j] = Fraction.init(counts[i][j], totals[i]);
            }
        }
        try self.chains.put(self.gpa, words[1], chain);
        try self.out.print("BUILD {s} order={d} states={d} transitions={d}\n", .{ words[1], order, chain.size, count - 1 });
        for (0..chain.size) |i| {
            try self.out.print("FROM {s} total={d}", .{ chain.names[i], totals[i] });
            if (totals[i] == 0) {
                try self.out.writeAll(" absorbing");
            } else {
                for (0..chain.size) |j| if (counts[i][j] > 0) {
                    try self.out.print(" {s}:{d}", .{ chain.names[j], counts[i][j] });
                };
            }
            try self.out.writeAll("\n");
        }
    }
    fn gambler(self: *Analyzer, words: []const []const u8) Error!void {
        const goal = index(words[2]);
        const start = index(words[3]);
        if (goal == 0 or goal > 9) return self.fail("BAD SIZE", .{});
        if (start > goal) return self.fail("BAD START", .{});
        const up = try self.probability(words[4]);
        if (up.isZero() or up.eq(Fraction.one)) return self.fail("BAD PROBABILITY", .{});
        var chain: Chain = .{ .size = goal + 1 };
        for (0..chain.size) |i| chain.names[i] = try std.fmt.allocPrint(self.gpa, "s{d}", .{i});
        chain.p[0][0] = Fraction.one;
        chain.p[goal][goal] = Fraction.one;
        for (1..goal) |i| {
            chain.p[i][i - 1] = Fraction.one.sub(up);
            chain.p[i][i + 1] = up;
        }
        const result = chain.absorption();
        var ruin = zero_vector;
        var duration = zero_vector;
        ruin[0] = Fraction.one;
        for (result.transient.slice(), 0..) |state_index, i| {
            ruin[state_index] = result.probability[i][0];
            duration[state_index] = result.mean[i];
        }
        try self.chains.put(self.gpa, words[1], chain);
        try self.out.print("GAMBLER {s} g={d} p={f} start=s{d} ruin={f} duration={f}\n", .{ words[1], goal, up, start, ruin[start].value(), duration[start].value() });
        for (0..chain.size) |i| try self.out.print("CAPITAL s{d} ruin={f} win={f} duration={f}\n", .{ i, ruin[i].value(), Fraction.one.sub(ruin[i]).value(), duration[i].value() });
    }
    fn classes(self: *Analyzer, name: []const u8, chain: *const Chain) Error!void {
        const topology = chain.graph();
        try self.out.print("CLASSES {s} count={d}\n", .{ name, topology.count });
        for (topology.classes[0..topology.count], 0..) |component, i| {
            try self.out.print("CLASS {d} {s} period={d} size={d} ", .{ i + 1, if (component.closed) "RECURRENT" else "TRANSIENT", component.period, component.states.len });
            try self.labels(chain, component.states.slice(), " ");
            try self.out.writeAll("\n");
            if (component.period >= 2) {
                var residue: i64 = 0;
                while (residue < component.period) : (residue += 1) {
                    try self.out.print("CYCLIC {d}", .{residue});
                    for (component.states.slice()) |state_index| if (@mod(component.levels[state_index], component.period) == residue) {
                        try self.out.print(" {s}", .{chain.names[state_index]});
                    };
                    try self.out.writeAll("\n");
                }
            }
        }
    }
    fn classify(self: *Analyzer, name: []const u8, chain: *const Chain) Error!void {
        const topology = chain.graph();
        var absorbing: StateList = .{};
        for (0..chain.size) |i| if (chain.p[i][i].eq(Fraction.one)) {
            absorbing.append(i);
        };
        var all_absorbed = absorbing.len > 0;
        for (0..chain.size) |i| if (!topology.reaches(i, &absorbing)) {
            all_absorbed = false;
        };
        var edges: [max_states][max_states]bool = @splat(@splat(false));
        for (0..chain.size) |i| for (0..chain.size) |j| {
            edges[i][j] = !chain.p[i][j].isZero();
        };
        var power = edges;
        var exponent: ?usize = null;
        const bound = (chain.size - 1) * (chain.size - 1) + 1;
        for (1..bound + 1) |t| {
            var all = true;
            for (0..chain.size) |i| for (0..chain.size) |j| {
                if (!power[i][j]) all = false;
            };
            if (all) {
                exponent = t;
                break;
            }
            var next: [max_states][max_states]bool = @splat(@splat(false));
            for (0..chain.size) |i| for (0..chain.size) |j| for (0..chain.size) |k| {
                next[i][j] = next[i][j] or (power[i][k] and edges[k][j]);
            };
            power = next;
        }
        try self.out.print("CLASSIFY {s} absorbing_states={d} absorbing={s} ergodic={s} regular={s} exponent=", .{ name, absorbing.len, yes(all_absorbed), yes(topology.count == 1), yes(exponent != null) });
        if (exponent) |value| try self.out.print("{d}\n", .{value}) else try self.out.writeAll("-\n");
    }
    fn step(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        var distribution = zero_vector;
        if (std.ascii.isDigit(words[2][0])) {
            var parts = std.mem.splitScalar(u8, words[2], ',');
            var count: usize = 0;
            while (parts.next() != null) count += 1;
            if (count != chain.size) return self.fail("BAD LENGTH", .{});
            parts = std.mem.splitScalar(u8, words[2], ',');
            for (0..chain.size) |i| distribution[i] = try self.probability(parts.next().?);
            if (!sum(distribution[0..chain.size]).eq(Fraction.one)) return self.fail("BAD DISTRIBUTION", .{});
        } else {
            distribution[try self.state(chain, words[2])] = Fraction.one;
        }
        const steps = index(words[3]);
        for (0..steps) |_| {
            const next = advance(distribution, &chain.p, chain.size);
            distribution = next;
        }
        try self.out.print("STEP {s} k={d}\n", .{ words[1], steps });
        for (0..chain.size) |i| try self.out.print("PROB {s} {f}\n", .{ chain.names[i], distribution[i].value() });
    }
    fn stationary(self: *Analyzer, name: []const u8, chain: *const Chain) Error!void {
        const topology = chain.graph();
        var closed: usize = 0;
        for (topology.classes[0..topology.count]) |component| if (component.closed) {
            closed += 1;
        };
        try self.out.print("STATIONARY {s} count={d}\n", .{ name, closed });
        var number: usize = 0;
        for (topology.classes[0..topology.count], 0..) |component, i| {
            if (!component.closed) continue;
            const distribution = chain.stationary(&component.states);
            number += 1;
            try self.out.print("DIST {d} class={d} size={d}\n", .{ number, i + 1, component.states.len });
            for (component.states.slice()) |state_index| try self.out.print("PI {s} {f}\n", .{ chain.names[state_index], distribution[state_index].value() });
        }
    }
    fn recurrence(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const state_index = try self.state(chain, words[2]);
        const topology = chain.graph();
        const component = topology.classes[topology.class_of[state_index]];
        if (!component.closed) return self.fail("TRANSIENT STATE {s}", .{words[2]});
        const rho = chain.stationary(&component.states)[state_index];
        try self.out.print("RECURRENCE {s} {s} pi={f} mean={f} period={d}\n", .{ words[1], words[2], rho.value(), Fraction.one.div(rho).value(), component.period });
    }
    fn absorb(self: *Analyzer, name: []const u8, chain: *const Chain) Error!void {
        var absorbing: StateList = .{};
        for (0..chain.size) |i| if (chain.p[i][i].eq(Fraction.one)) {
            absorbing.append(i);
        };
        if (absorbing.len == 0) return self.fail("NO ABSORBING STATE", .{});
        const topology = chain.graph();
        for (0..chain.size) |i| if (!absorbing.contains(i) and !topology.reaches(i, &absorbing)) {
            return self.fail("NOT ABSORBING {s}", .{chain.names[i]});
        };
        const result = chain.absorption();
        try self.out.print("ABSORB {s} transient={d} absorbing={d}\n", .{ name, result.transient.len, result.absorbing.len });
        if (result.transient.len == 0) return;
        try self.out.writeAll("TRANSIENT ");
        try self.labels(chain, result.transient.slice(), " ");
        try self.out.writeAll("\nABSORBING ");
        try self.labels(chain, result.absorbing.slice(), " ");
        try self.out.writeAll("\n");
        for (result.transient.slice(), 0..) |state_index, i| {
            try self.out.print("N {s}", .{chain.names[state_index]});
            for (result.fundamental[i][0..result.transient.len]) |value| try self.out.print(" {f}", .{value});
            try self.out.writeAll("\n");
        }
        for (result.transient.slice(), 0..) |state_index, i| try self.out.print("STEPS {s} mean={f} var={f}\n", .{ chain.names[state_index], result.mean[i].value(), result.variance[i].value() });
        for (result.transient.slice(), 0..) |state_index, i| {
            try self.out.print("B {s}", .{chain.names[state_index]});
            for (result.probability[i][0..result.absorbing.len]) |value| try self.out.print(" {f}", .{value});
            try self.out.writeAll("\n");
        }
    }
    fn hitting(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const targets = try self.stateSet(chain, words[2..]);
        const result = chain.hitting(&targets, true);
        try self.out.print("HITTING {s} targets=", .{words[1]});
        try self.labels(chain, targets.slice(), ",");
        try self.out.writeAll("\n");
        for (0..chain.size) |i| {
            try self.out.print("HIT {s} prob={f} time=", .{ chain.names[i], result.probability[i].value() });
            if (result.time[i]) |time| try self.out.print("{f}\n", .{time.value()}) else try self.out.writeAll("inf\n");
        }
    }
    fn passage(self: *Analyzer, name: []const u8, chain: *const Chain) Error!void {
        const pi = try self.uniqueStationary(chain);
        var values = zero_matrix;
        for (0..chain.size) |j| {
            var targets: StateList = .{};
            targets.append(j);
            const result = chain.hitting(&targets, true);
            for (0..chain.size) |i| values[i][j] = if (i == j) Fraction.one.div(pi[j]) else result.time[i].?;
        }
        var kemeny = Fraction.zero;
        for (1..chain.size) |j| kemeny = kemeny.add(pi[j].mul(values[0][j]));
        try self.out.print("PASSAGE {s} kemeny={f}\n", .{ name, kemeny.value() });
        try self.display(chain, &values, "M");
    }
    fn firstPassage(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const from = try self.state(chain, words[2]);
        const target = try self.state(chain, words[3]);
        const steps = index(words[4]);
        if (steps == 0) return self.fail("BAD STEPS", .{});
        var current = zero_vector;
        for (0..chain.size) |i| current[i] = chain.p[i][target];
        var probabilities: [30]Fraction = undefined;
        var cumulative: [30]Fraction = undefined;
        var total = Fraction.zero;
        for (0..steps) |t| {
            probabilities[t] = current[from];
            total = total.add(current[from]);
            cumulative[t] = total;
            if (t + 1 < steps) {
                var next = zero_vector;
                for (0..chain.size) |i| for (0..chain.size) |j| {
                    if (j != target) next[i] = next[i].add(chain.p[i][j].mul(current[j]));
                };
                current = next;
            }
        }
        try self.out.print("FIRSTPASSAGE {s} {s} {s} k={d} total={f}\n", .{ words[1], words[2], words[3], steps, total.value() });
        for (0..steps) |t| try self.out.print("FP {d} {f} cum={f}\n", .{ t + 1, probabilities[t].value(), cumulative[t].value() });
    }
    fn pathProbability(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        var states: [30]usize = undefined;
        const count = words.len - 2;
        for (words[2..], 0..) |word, i| states[i] = try self.state(chain, word);
        var product = Fraction.one;
        var zero_at: ?usize = null;
        for (1..count) |i| {
            product = product.mul(chain.p[states[i - 1]][states[i]]);
            if (product.isZero() and zero_at == null) zero_at = i;
        }
        try self.out.print("PATHPROB {s} steps={d} prob={f}", .{ words[1], count - 1, product.value() });
        if (zero_at) |value| try self.out.print(" zero_at={d}", .{value});
        try self.out.writeAll("\n");
    }
    fn mostLikely(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const start = try self.state(chain, words[2]);
        const steps = index(words[3]);
        if (steps == 0) return self.fail("BAD STEPS", .{});
        var best: [21]Vector = @splat(zero_vector);
        best[steps] = @splat(Fraction.one);
        var remaining = steps;
        while (remaining > 0) {
            remaining -= 1;
            for (0..chain.size) |i| for (0..chain.size) |j| {
                const candidate = chain.p[i][j].mul(best[remaining + 1][j]);
                if (best[remaining][i].less(candidate)) best[remaining][i] = candidate;
            };
        }
        var path: [21]usize = undefined;
        path[0] = start;
        for (0..steps) |t| {
            const from = path[t];
            for (0..chain.size) |j| if (chain.p[from][j].mul(best[t + 1][j]).eq(best[t][from])) {
                path[t + 1] = j;
                break;
            };
        }
        try self.out.print("MOSTLIKELY {s} {s} k={d} prob={f}\nPATH ", .{ words[1], words[2], steps, best[0][start].value() });
        try self.labels(chain, path[0..steps + 1], " ");
        try self.out.writeAll("\n");
    }
    fn reversible(self: *Analyzer, name: []const u8, chain: *const Chain) Error!void {
        const pi = try self.uniqueStationary(chain);
        const Violation = struct { from: usize, to: usize, forward: Fraction, backward: Fraction };
        var violations: [45]Violation = undefined;
        var count: usize = 0;
        for (0..chain.size) |i| for (i + 1..chain.size) |j| {
            const forward = pi[i].mul(chain.p[i][j]);
            const backward = pi[j].mul(chain.p[j][i]);
            if (!forward.eq(backward)) {
                violations[count] = .{ .from = i, .to = j, .forward = forward, .backward = backward };
                count += 1;
            }
        };
        if (count == 0) {
            try self.out.print("REVERSIBLE {s} yes\n", .{name});
        } else {
            try self.out.print("REVERSIBLE {s} no violations={d}\n", .{ name, count });
            for (violations[0..count]) |pair| try self.out.print("VIOLATION {s} {s} {f} {f}\n", .{ chain.names[pair.from], chain.names[pair.to], pair.forward.value(), pair.backward.value() });
        }
    }
    fn reverse(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const pi = try self.uniqueStationary(chain);
        var reversed = chain.*;
        var same = true;
        for (0..chain.size) |i| for (0..chain.size) |j| {
            reversed.p[i][j] = pi[j].mul(chain.p[j][i]).div(pi[i]);
            if (!reversed.p[i][j].eq(chain.p[i][j])) same = false;
        };
        try self.chains.put(self.gpa, words[2], reversed);
        try self.out.print("REVERSE {s} {s} reversible={s}\n", .{ words[1], words[2], yes(same) });
        try self.display(&reversed, &reversed.p, "ROW");
    }
    fn mixing(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const steps = index(words[2]);
        if (steps == 0) return self.fail("BAD STEPS", .{});
        const epsilon = try self.probability(words[3]);
        const pi = try self.uniqueStationary(chain);
        var power = identity(chain.size);
        var distances: [20]Fraction = undefined;
        var worst: [20]usize = undefined;
        var mixing_time: ?usize = null;
        for (0..steps) |t| {
            const next = multiply(&power, &chain.p, chain.size);
            power = next;
            var distance = Fraction.zero;
            var from: usize = 0;
            for (0..chain.size) |i| {
                var current = Fraction.zero;
                for (0..chain.size) |j| current = current.add(power[i][j].sub(pi[j]).absolute());
                current = current.div(Fraction.two);
                if (distance.less(current)) {
                    distance = current;
                    from = i;
                }
            }
            if (!epsilon.less(distance) and mixing_time == null) mixing_time = t + 1;
            distances[t] = distance;
            worst[t] = from;
        }
        try self.out.print("MIXING {s} k={d} eps={f} time=", .{ words[1], steps, epsilon });
        if (mixing_time) |time| try self.out.print("{d}\n", .{time}) else try self.out.writeAll("none\n");
        for (0..steps) |t| try self.out.print("TV {d} {f} from={s}\n", .{ t + 1, distances[t].value(), chain.names[worst[t]] });
    }
    fn lessBlock(_: void, a: StateList, b: StateList) bool { return a.items[0] < b.items[0]; }
    fn lump(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        var blocks: [max_states]StateList = undefined;
        var count: usize = 0;
        var seen: StateList = .{};
        var groups = std.mem.splitScalar(u8, words[3], '|');
        while (groups.next()) |group| {
            var block: StateList = .{};
            var names = std.mem.splitScalar(u8, group, ',');
            while (names.next()) |name| {
                const state_index = try self.state(chain, name);
                if (seen.contains(state_index)) return self.fail("BAD PARTITION", .{});
                seen.append(state_index);
                block.append(state_index);
            }
            block.sort();
            blocks[count] = block;
            count += 1;
        }
        if (seen.len != chain.size) return self.fail("BAD PARTITION", .{});
        std.mem.sort(StateList, blocks[0..count], {}, lessBlock);
        var lumped: Chain = .{ .size = count };
        for (blocks[0..count], 0..) |block, i| lumped.names[i] = chain.names[block.items[0]];
        for (blocks[0..count], 0..) |block, i| for (blocks[0..count], 0..) |target, j| {
            const representative = block.items[0];
            const baseline = chain.blockSum(representative, &target);
            for (block.slice()) |state_index| {
                const value = chain.blockSum(state_index, &target);
                if (!value.eq(baseline)) {
                    try self.out.print("LUMP {s} not lumpable block={s} target={s} {s}={f} {s}={f}\n", .{
                        words[1], chain.names[representative], chain.names[target.items[0]],
                        chain.names[representative], baseline.value(), chain.names[state_index], value.value(),
                    });
                    return;
                }
            }
            lumped.p[i][j] = baseline;
        };
        try self.chains.put(self.gpa, words[2], lumped);
        try self.out.print("LUMP {s} {s} blocks={d}\n", .{ words[1], words[2], count });
        try self.display(&lumped, &lumped.p, "ROW");
    }
    fn reward(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        if (words.len - 3 != chain.size) return self.fail("BAD LENGTH", .{});
        const discount = try self.probability(words[2]);
        if (discount.eq(Fraction.one)) return self.fail("BAD DISCOUNT", .{});
        var rewards = zero_vector;
        var equations = zero_equations;
        for (0..chain.size) |i| {
            rewards[i] = Fraction.init(integer(words[i + 3]), 1);
            for (0..chain.size) |j| equations[i][j] = delta(i, j).sub(discount.mul(chain.p[i][j]));
            equations[i][chain.size] = rewards[i];
        }
        const discounted = solve(&equations, chain.size, chain.size + 1);
        var gain = zero_vector;
        const topology = chain.graph();
        for (topology.classes[0..topology.count]) |component| {
            if (!component.closed) continue;
            const rho = chain.stationary(&component.states);
            var average = Fraction.zero;
            for (component.states.slice()) |i| average = average.add(rho[i].mul(rewards[i]));
            const result = chain.hitting(&component.states, false);
            for (0..chain.size) |i| gain[i] = gain[i].add(result.probability[i].mul(average));
        }
        try self.out.print("REWARD {s} gamma={f}\n", .{ words[1], discount });
        for (0..chain.size) |i| try self.out.print("VALUE {s} discounted={f} gain={f}\n", .{ chain.names[i], discounted[i][0].value(), gain[i].value() });
    }
    fn restrict(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        const states = try self.stateSet(chain, words[3..]);
        for (states.slice()) |i| for (0..chain.size) |j| {
            if (!states.contains(j) and !chain.p[i][j].isZero()) return self.fail("NOT CLOSED {s}", .{chain.names[i]});
        };
        var restricted: Chain = .{ .size = states.len };
        for (states.slice(), 0..) |from, i| {
            restricted.names[i] = chain.names[from];
            for (states.slice(), 0..) |to, j| restricted.p[i][j] = chain.p[from][to];
        }
        try self.chains.put(self.gpa, words[2], restricted);
        try self.out.print("RESTRICT {s} {s} states={d}\n", .{ words[1], words[2], states.len });
        try self.display(&restricted, &restricted.p, "ROW");
    }
    fn simulate(self: *Analyzer, words: []const []const u8, chain: *const Chain) Error!void {
        var current = try self.state(chain, words[2]);
        const steps = index(words[3]);
        if (steps == 0) return self.fail("BAD STEPS", .{});
        const seed = integer(words[4]);
        if (seed == 0 or seed >= 2147483647) return self.fail("BAD SEED", .{});
        var random = seed;
        var path: [61]usize = undefined;
        var visits: [max_states]usize = @splat(0);
        path[0] = current;
        visits[current] = 1;
        for (0..steps) |t| {
            var denominator: i64 = 1;
            for (chain.p[current][0..chain.size]) |value| denominator = @divTrunc(denominator, gcd(denominator, value.denominator)) * value.denominator;
            random = @mod(48271 * random, 2147483647);
            const sample = @mod(random, denominator);
            var cumulative = Fraction.zero;
            for (0..chain.size) |j| {
                cumulative = cumulative.add(chain.p[current][j]);
                if (cumulative.numerator * @divTrunc(denominator, cumulative.denominator) > sample) {
                    current = j;
                    break;
                }
            }
            path[t + 1] = current;
            visits[current] += 1;
        }
        try self.out.print("SIMULATE {s} {s} steps={d} seed={d} end={s}\nPATH ", .{ words[1], words[2], steps, seed, chain.names[current] });
        try self.labels(chain, path[0..steps + 1], " ");
        try self.out.writeAll("\n");
        for (0..chain.size) |i| try self.out.print("VISIT {s} {d}\n", .{ chain.names[i], visits[i] });
    }
    fn execute(self: *Analyzer, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]).?;
        const name = words[1];
        switch (command) {
            .CHAIN => return self.create(words),
            .BUILD => return self.build(words),
            .GAMBLER => return self.gambler(words),
            else => {},
        }
        var chain = self.chains.get(name) orelse return self.fail("UNKNOWN CHAIN {s}", .{name});
        switch (command) {
            .P, .ROW, .SHOW, .CHECK => {},
            else => try self.stochastic(&chain),
        }
        switch (command) {
            .P => {
                const from = try self.state(&chain, words[2]);
                const to = try self.state(&chain, words[3]);
                const value = try self.probability(words[4]);
                chain.p[from][to] = value;
                try self.chains.put(self.gpa, name, chain);
                try self.out.print("P {s} {s} {s} {f} rowsum={f}\n", .{ name, words[2], words[3], value, sum(chain.p[from][0..chain.size]) });
            },
            .ROW => {
                const from = try self.state(&chain, words[2]);
                if (words.len - 3 != chain.size) return self.fail("BAD LENGTH", .{});
                for (words[3..], 0..) |word, j| chain.p[from][j] = try self.probability(word);
                try self.chains.put(self.gpa, name, chain);
                try self.out.print("ROW {s} {s} rowsum={f}\n", .{ name, words[2], sum(chain.p[from][0..chain.size]) });
            },
            .SHOW => {
                try self.out.print("MATRIX {s} states={d}\n", .{ name, chain.size });
                try self.display(&chain, &chain.p, "ROW");
            },
            .CHECK => {
                var sums = zero_vector;
                var bad: StateList = .{};
                for (0..chain.size) |i| {
                    sums[i] = sum(chain.p[i][0..chain.size]);
                    if (!sums[i].eq(Fraction.one)) bad.append(i);
                }
                if (bad.len == 0) {
                    try self.out.print("CHECK {s} ok\n", .{name});
                } else {
                    try self.out.print("CHECK {s} bad={d}\n", .{ name, bad.len });
                    for (bad.slice()) |i| try self.out.print("BADROW {s} sum={f}\n", .{ chain.names[i], sums[i] });
                }
            },
            .CLASSES => try self.classes(name, &chain),
            .CLASSIFY => try self.classify(name, &chain),
            .STEP => try self.step(words, &chain),
            .POWER => {
                const steps = index(words[2]);
                var power = identity(chain.size);
                for (0..steps) |_| {
                    const next = multiply(&power, &chain.p, chain.size);
                    power = next;
                }
                try self.out.print("POWER {s} k={d}\n", .{ name, steps });
                try self.display(&chain, &power, "ROW");
            },
            .STATIONARY => try self.stationary(name, &chain),
            .RECURRENCE => try self.recurrence(words, &chain),
            .ABSORB => try self.absorb(name, &chain),
            .HITTING => try self.hitting(words, &chain),
            .PASSAGE => try self.passage(name, &chain),
            .FIRSTPASSAGE => try self.firstPassage(words, &chain),
            .PATHPROB => try self.pathProbability(words, &chain),
            .MOSTLIKELY => try self.mostLikely(words, &chain),
            .REVERSIBLE => try self.reversible(name, &chain),
            .REVERSE => try self.reverse(words, &chain),
            .MIXING => try self.mixing(words, &chain),
            .LUMP => try self.lump(words, &chain),
            .REWARD => try self.reward(words, &chain),
            .RESTRICT => try self.restrict(words, &chain),
            .SIMULATE => try self.simulate(words, &chain),
            .CHAIN, .BUILD, .GAMBLER => unreachable,
        }
    }
};

fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const line = try buffer.toOwnedSlice();
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeAny(u8, line, " \r");
    while (parts.next()) |part| try words.append(gpa, part);
    return try words.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = index((try readWords(gpa, &input.interface))[0]);
    var analyzer: Analyzer = .{ .gpa = gpa, .out = &output.interface };
    for (0..count) |_| {
        const words = try readWords(gpa, &input.interface);
        var response: std.Io.Writer.Allocating = .init(gpa);
        defer response.deinit();
        analyzer.out = &response.writer;
        analyzer.execute(words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{analyzer.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
