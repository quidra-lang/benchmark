const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Command = enum {
    MARKET,
    ROOMS,
    HOUSES,
    RANDOM,
    PREF,
    CAPACITY,
    SHOW,
    GS,
    GSR,
    CHECK,
    LATTICE,
    EGALITARIAN,
    MINREGRET,
    HR,
    ROOMMATES,
    TTC,
    SERIAL,
    BOSTON,
    MANIPULATE,
    STATS,
};
const Kind = enum { two_sided, roommates, housing };

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn integer(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void {
    try out.print(fmt ++ "\n", args);
}

const Name = struct {
    bytes: [8]u8 = undefined,
    len: usize = 0,
    fn init(value: []const u8) Name {
        var name: Name = .{ .len = value.len };
        @memcpy(name.bytes[0..value.len], value);
        return name;
    }
    fn text(name: *const Name) []const u8 {
        return name.bytes[0..name.len];
    }
    pub fn format(name: Name, out: *Writer) Writer.Error!void {
        try out.writeAll(name.text());
    }
};
const Sequence = struct {
    items: [24]usize = undefined,
    len: usize = 0,
    fn list(sequence: *const Sequence) []const usize {
        return sequence.items[0..sequence.len];
    }
    fn append(sequence: *Sequence, agent: usize) void {
        sequence.items[sequence.len] = agent;
        sequence.len += 1;
    }
    fn index(sequence: *const Sequence, agent: usize) ?usize {
        for (sequence.list(), 0..) |item, i| if (item == agent) return i;
        return null;
    }
    fn remove(sequence: *Sequence, agent: usize) void {
        const position = sequence.index(agent) orelse return;
        var i = position;
        while (i + 1 < sequence.len) : (i += 1) sequence.items[i] = sequence.items[i + 1];
        sequence.len -= 1;
    }
    fn rank(sequence: *const Sequence, partner: ?usize) usize {
        if (partner) |agent| if (sequence.index(agent)) |i| return i + 1;
        return sequence.len + 1;
    }
};
const Matching = struct {
    partners: [24]?usize = @splat(null),
    fn same(a: Matching, b: Matching, count: usize) bool {
        for (a.partners[0..count], b.partners[0..count]) |first, second| if (first != second) return false;
        return true;
    }
};
const Market = struct {
    name: Name,
    kind: Kind,
    names: [24]Name = undefined,
    houses: [12]Name = undefined,
    count: usize = 0,
    proposer_count: usize = 0,
    preferences: [24]Sequence = @splat(Sequence{}),
    capacities: [24]usize = @splat(1),
    current: ?Matching = null,
    source: ?Command = null,
    fn find(market: *const Market, text: []const u8) ?usize {
        for (market.names[0..market.count], 0..) |name, i| if (equal(name.text(), text)) return i;
        return null;
    }
    fn house(market: *const Market, text: []const u8) ?usize {
        for (market.houses[0..market.count], 0..) |name, i| if (equal(name.text(), text)) return i;
        return null;
    }
    fn rank(market: *const Market, agent: usize, partner: ?usize) usize {
        return market.preferences[agent].rank(partner);
    }
    fn acceptable(market: *const Market, a: usize, b: usize) bool {
        return market.preferences[a].index(b) != null and market.preferences[b].index(a) != null;
    }
    fn clear(market: *Market) void {
        market.current = null;
        market.source = null;
    }
    fn save(market: *Market, matching: Matching, command: Command) void {
        market.current = matching;
        market.source = command;
    }
    fn effective(market: *const Market, agent: usize) Sequence {
        var result = market.preferences[agent];
        if (result.index(agent)) |i| result.len = i + 1 else result.append(agent);
        return result;
    }
    fn residents(market: *const Market, matching: Matching, receiver: usize) Sequence {
        var result: Sequence = .{};
        for (0..market.proposer_count) |p| {
            if (matching.partners[p] == receiver) result.append(p);
        }
        return result;
    }
};
const Partner = struct {
    market: *const Market,
    agent: ?usize,
    pub fn format(partner: Partner, out: *Writer) Writer.Error!void {
        if (partner.agent) |a| try out.print("{f}", .{partner.market.names[a]}) else try out.writeByte('*');
    }
};
const Pairs = struct {
    market: *const Market,
    matching: Matching,
    pub fn format(pairs: Pairs, out: *Writer) Writer.Error!void {
        for (0..pairs.market.proposer_count) |p| {
            if (p > 0) try out.writeByte(' ');
            try out.print("{f}-{f}", .{ pairs.market.names[p], Partner{ .market = pairs.market, .agent = pairs.matching.partners[p] } });
        }
    }
};
const NamedList = struct {
    names: []const Name,
    sequence: Sequence,
    pub fn format(values: NamedList, out: *Writer) Writer.Error!void {
        if (values.sequence.len == 0) return out.writeByte('-');
        for (values.sequence.list(), 0..) |a, i| {
            if (i > 0) try out.writeByte(' ');
            try out.print("{f}", .{values.names[a]});
        }
    }
};
const Allocation = struct {
    market: *const Market,
    houses: [24]?usize,
    pub fn format(allocation: Allocation, out: *Writer) Writer.Error!void {
        for (0..allocation.market.count) |a| {
            if (a > 0) try out.writeByte(' ');
            try out.print("{f}-", .{allocation.market.names[a]});
            if (allocation.houses[a]) |h| try out.print("{f}", .{allocation.market.houses[h]}) else try out.writeByte('*');
        }
    }
};
const Pair = struct { first: usize, second: usize };
const MatchingResult = struct { matching: Matching, proposals: usize, log: []const u8 };
const ProposalState = struct {
    gpa: Allocator,
    market: *const Market,
    next: [24]usize = @splat(0),
    counts: [24]usize = @splat(0),
    queued: [24]bool = @splat(false),
    holding: [24]Sequence = @splat(Sequence{}),
    queue: std.ArrayList(usize) = .empty,
    fn able(state: *const ProposalState, agent: usize) bool {
        return state.counts[agent] < state.market.capacities[agent] and state.next[agent] < state.market.preferences[agent].len;
    }
    fn enqueue(state: *ProposalState, agent: usize) Allocator.Error!void {
        if (state.able(agent) and !state.queued[agent]) {
            try state.queue.append(state.gpa, agent);
            state.queued[agent] = true;
        }
    }
};
fn deferred(gpa: Allocator, market: *const Market, reverse: bool, verbose: bool) Error!MatchingResult {
    var state: ProposalState = .{ .gpa = gpa, .market = market };
    const start: usize = if (reverse) market.proposer_count else 0;
    const end = if (reverse) market.count else market.proposer_count;
    for (start..end) |a| try state.enqueue(a);
    var log: Writer.Allocating = .init(gpa);
    defer log.deinit();
    var head: usize = 0;
    while (head < state.queue.items.len) : (head += 1) {
        const x = state.queue.items[head];
        state.queued[x] = false;
        const y = market.preferences[x].items[state.next[x]];
        state.next[x] += 1;
        var accepted = false;
        var rejected: ?usize = null;
        if (market.preferences[y].index(x) != null) {
            if (state.holding[y].len < market.capacities[y]) {
                state.holding[y].append(x);
                state.counts[x] += 1;
                accepted = true;
            } else {
                var worst: usize = 0;
                for (state.holding[y].list(), 0..) |a, i| {
                    if (market.rank(y, a) > market.rank(y, state.holding[y].items[worst])) worst = i;
                }
                const previous = state.holding[y].items[worst];
                if (market.rank(y, x) < market.rank(y, previous)) {
                    state.holding[y].items[worst] = x;
                    state.counts[previous] -= 1;
                    state.counts[x] += 1;
                    accepted = true;
                    rejected = previous;
                    try state.enqueue(previous);
                }
            }
        }
        if (verbose) {
            try log.writer.print("PROPOSE {f} {f} {s}", .{ market.names[x], market.names[y], if (accepted) "HOLD" else "REJECT" });
            if (rejected) |a| try log.writer.print(" REJECT {f}", .{market.names[a]});
            try log.writer.writeByte('\n');
        }
        try state.enqueue(x);
    }
    var matching: Matching = .{};
    const receiving_start: usize = if (reverse) 0 else market.proposer_count;
    const receiving_end = if (reverse) market.proposer_count else market.count;
    for (receiving_start..receiving_end) |y| {
        for (state.holding[y].list()) |x| matching.partners[if (reverse) y else x] = if (reverse) x else y;
    }
    return .{ .matching = matching, .proposals = head, .log = try log.toOwnedSlice() };
}
fn boston(market: *const Market) MatchingResult {
    var matching: Matching = .{};
    var remaining = market.capacities;
    var rounds: usize = 0;
    for (market.preferences[0..market.proposer_count]) |preference| rounds = @max(rounds, preference.len);
    var applications: usize = 0;
    for (0..rounds) |round| {
        var applicants: [24]Sequence = @splat(Sequence{});
        for (0..market.proposer_count) |p| {
            if (matching.partners[p] != null or round >= market.preferences[p].len) continue;
            applicants[market.preferences[p].items[round]].append(p);
            applications += 1;
        }
        for (market.proposer_count..market.count) |r| {
            for (market.preferences[r].list()) |p| {
                if (remaining[r] > 0 and applicants[r].index(p) != null) {
                    matching.partners[p] = r;
                    remaining[r] -= 1;
                }
            }
        }
    }
    return .{ .matching = matching, .proposals = applications, .log = "" };
}
const CheckResult = struct {
    unacceptable: std.ArrayList(Pair) = .empty,
    blocking: std.ArrayList(Pair) = .empty,
};
fn checkMatching(gpa: Allocator, market: *const Market, matching: Matching) Allocator.Error!CheckResult {
    var result: CheckResult = .{};
    if (market.kind == .roommates) {
        for (0..market.count) |a| {
            for (a + 1..market.count) |b| {
                if (matching.partners[a] == b) {
                    if (!market.acceptable(a, b)) try result.unacceptable.append(gpa, .{ .first = a, .second = b });
                } else if (market.acceptable(a, b) and market.rank(a, b) < market.rank(a, matching.partners[a]) and
                    market.rank(b, a) < market.rank(b, matching.partners[b]))
                {
                    try result.blocking.append(gpa, .{ .first = a, .second = b });
                }
            }
        }
    } else {
        for (0..market.proposer_count) |p| {
            if (matching.partners[p]) |r| {
                if (!market.acceptable(p, r)) try result.unacceptable.append(gpa, .{ .first = p, .second = r });
            }
            for (market.proposer_count..market.count) |r| {
                if (matching.partners[p] == r or !market.acceptable(p, r) or market.rank(p, r) >= market.rank(p, matching.partners[p])) continue;
                const held = market.residents(matching, r);
                var worst: usize = 0;
                for (held.list()) |a| worst = @max(worst, market.rank(r, a));
                if (held.len < market.capacities[r] or market.rank(r, p) < worst)
                    try result.blocking.append(gpa, .{ .first = p, .second = r });
            }
        }
    }
    return result;
}
const Candidate = struct {
    matching: Matching,
    origin: usize,
    via: usize,
    cost: usize = 0,
    regret: usize = 0,
    fn init(market: *const Market, matching: Matching, origin: usize, via: usize) Candidate {
        var result: Candidate = .{ .matching = matching, .origin = origin, .via = via };
        for (0..market.proposer_count) |p| {
            if (matching.partners[p]) |r| {
                const a = market.rank(p, r);
                const b = market.rank(r, p);
                result.cost += a + b;
                result.regret = @max(result.regret, @max(a, b));
            }
        }
        return result;
    }
};
const RotationList = struct { items: [12]Sequence = undefined, len: usize = 0 };
fn rotations(market: *const Market, matching: Matching) RotationList {
    var owners: [24]?usize = @splat(null);
    for (0..market.proposer_count) |p| {
        if (matching.partners[p]) |r| owners[r] = p;
    }
    var successors: [12]?usize = @splat(null);
    for (0..market.proposer_count) |p| {
        const partner = matching.partners[p] orelse continue;
        const preference = &market.preferences[p];
        for (preference.list()[preference.index(partner).? + 1 ..]) |r| {
            if (market.preferences[r].index(p) == null) continue;
            if (owners[r] == null or market.rank(r, p) < market.rank(r, owners[r])) {
                successors[p] = owners[r];
                break;
            }
        }
    }
    var result: RotationList = .{};
    var covered: [12]bool = @splat(false);
    for (0..market.proposer_count) |start| {
        if (covered[start]) continue;
        var seen: [12]bool = @splat(false);
        var path: Sequence = .{};
        var current: ?usize = start;
        while (current) |p| {
            if (seen[p]) break;
            seen[p] = true;
            path.append(p);
            current = successors[p];
        }
        if (current != start) continue;
        result.items[result.len] = path;
        result.len += 1;
        for (path.list()) |p| covered[p] = true;
    }
    return result;
}
const Enumeration = struct {
    matchings: std.ArrayList(Candidate) = .empty,
    notations: std.ArrayList([]const u8) = .empty,
};

const RankSummary = struct {
    ranks: Sequence,
    unmatched: usize,
    pub fn format(summary: RankSummary, out: *Writer) Writer.Error!void {
        var total: usize = 0;
        var first: usize = 0;
        for (summary.ranks.list()) |rank_value| {
            total += rank_value;
            first += @intFromBool(rank_value == 1);
        }
        try out.print("sum={d} average=", .{total});
        if (summary.ranks.len == 0) {
            try out.writeAll("- truncated=-");
        } else {
            var a = total;
            var b = summary.ranks.len;
            while (b != 0) {
                const remainder = a % b;
                a = b;
                b = remainder;
            }
            const cents = total * 100 / summary.ranks.len;
            try out.print("{d}/{d} truncated={d}.{d:0>2}", .{ total / a, summary.ranks.len / a, cents / 100, cents % 100 });
        }
        try out.print(" first={d} unmatched={d}", .{ first, summary.unmatched });
    }
};

const Session = struct {
    gpa: Allocator,
    storage: Allocator,
    markets: *std.ArrayList(Market),
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn find(session: *Session, name: []const u8) ?*Market {
        for (session.markets.items) |*market| if (equal(market.name.text(), name)) return market;
        return null;
    }
    fn get(session: *Session, name: []const u8, kind: ?Kind) Error!*Market {
        const market = session.find(name) orelse return session.fail("UNKNOWN MARKET {s}", .{name});
        if (kind) |wanted| if (market.kind != wanted) return session.fail("WRONG TYPE {s}", .{name});
        return market;
    }
    fn newName(session: *Session, name: []const u8) Error!void {
        if (session.find(name) != null) return session.fail("DUPLICATE MARKET {s}", .{name});
    }
    fn agent(session: *Session, market: *const Market, name: []const u8) Error!usize {
        return market.find(name) orelse session.fail("UNKNOWN AGENT {s}", .{name});
    }
    fn proposer(session: *Session, market: *const Market, name: []const u8) Error!usize {
        const a = try session.agent(market, name);
        if (a >= market.proposer_count) return session.fail("NOT PROPOSER {s}", .{name});
        return a;
    }
    fn receiver(session: *Session, market: *const Market, name: []const u8) Error!usize {
        const a = try session.agent(market, name);
        if (a < market.proposer_count) return session.fail("NOT RECEIVER {s}", .{name});
        return a;
    }
    fn choice(session: *Session, market: *const Market, a: usize, name: []const u8) Error!usize {
        const b = (if (market.kind == .housing) market.house(name) else market.find(name)) orelse
            return session.fail("BAD CHOICE {s}", .{name});
        const valid = switch (market.kind) {
            .two_sided => (a < market.proposer_count) != (b < market.proposer_count),
            .roommates => a != b,
            .housing => true,
        };
        if (!valid) return session.fail("BAD CHOICE {s}", .{name});
        return b;
    }
    fn show(session: *Session, market: *const Market) Error!void {
        const out = session.out;
        const names = if (market.kind == .housing) market.houses[0..market.count] else market.names[0..market.count];
        if (market.kind == .two_sided) {
            try line(out, "SHOW {f} MARKET proposers={d} receivers={d}", .{ market.name, market.proposer_count, market.count - market.proposer_count });
            for (0..market.proposer_count) |p| try line(out, "PROPOSER {f} {f}", .{ market.names[p], NamedList{ .names = names, .sequence = market.preferences[p] } });
            for (market.proposer_count..market.count) |r| try line(out, "RECEIVER {f} cap={d} {f}", .{ market.names[r], market.capacities[r], NamedList{ .names = names, .sequence = market.preferences[r] } });
            try line(out, "CURRENT {s}", .{if (market.source) |source| @tagName(source) else "-"});
        } else {
            try line(out, "SHOW {f} {s} agents={d}", .{ market.name, if (market.kind == .roommates) "ROOMS" else "HOUSES", market.count });
            for (0..market.count) |a| {
                try out.print("AGENT {f} ", .{market.names[a]});
                if (market.kind == .housing) try out.print("house={f} ", .{market.houses[a]});
                try line(out, "{f}", .{NamedList{ .names = names, .sequence = market.preferences[a] }});
            }
        }
    }
    fn check(session: *Session, market: *const Market, words: []const []const u8) Error!void {
        if (market.kind == .housing) return session.fail("WRONG TYPE {f}", .{market.name});
        var matching: Matching = .{};
        var used: [24]bool = @splat(false);
        var counts: [24]usize = @splat(0);
        for (words[2..]) |word| {
            const separator = std.mem.findScalar(u8, word, '-').?;
            const x = word[0..separator];
            const y = word[separator + 1 ..];
            if (market.kind == .two_sided) {
                const p = try session.proposer(market, x);
                const r = try session.receiver(market, y);
                if (used[p]) return session.fail("DUPLICATE AGENT {s}", .{x});
                if (counts[r] + 1 > market.capacities[r]) return session.fail("OVER CAPACITY {s}", .{y});
                used[p] = true;
                counts[r] += 1;
                matching.partners[p] = r;
            } else {
                const a = try session.agent(market, x);
                const b = try session.agent(market, y);
                if (used[a]) return session.fail("DUPLICATE AGENT {s}", .{x});
                if (a == b or used[b]) return session.fail("DUPLICATE AGENT {s}", .{y});
                used[a] = true;
                used[b] = true;
                matching.partners[a] = b;
                matching.partners[b] = a;
            }
        }
        const result = try checkMatching(session.gpa, market, matching);
        if (result.unacceptable.items.len == 0 and result.blocking.items.len == 0)
            return line(session.out, "CHECK {f} STABLE", .{market.name});
        try line(session.out, "CHECK {f} UNSTABLE unacceptable={d} blocking={d}", .{ market.name, result.unacceptable.items.len, result.blocking.items.len });
        for (result.unacceptable.items) |pair| try line(session.out, "UNACCEPTABLE {f} {f}", .{ market.names[pair.first], market.names[pair.second] });
        for (result.blocking.items) |pair| try line(session.out, "BLOCKING {f} {f}", .{ market.names[pair.first], market.names[pair.second] });
    }
    fn enumerate(session: *Session, market: *const Market) Error!Enumeration {
        for (market.capacities[market.proposer_count..market.count]) |capacity| {
            if (capacity != 1) return session.fail("NOT ONE TO ONE", .{});
        }
        var result: Enumeration = .{};
        const first = try deferred(session.gpa, market, false, false);
        try result.matchings.append(session.gpa, Candidate.init(market, first.matching, 0, 0));
        var index: usize = 0;
        while (index < result.matchings.items.len) : (index += 1) {
            const matching = result.matchings.items[index].matching;
            const sequence = rotations(market, matching);
            for (sequence.items[0..sequence.len]) |rotation| {
                var buffer: Writer.Allocating = .init(session.gpa);
                defer buffer.deinit();
                for (rotation.list(), 0..) |p, i| {
                    if (i > 0) try buffer.writer.writeByte(' ');
                    try buffer.writer.print("{f}-{f}", .{ market.names[p], market.names[matching.partners[p].?] });
                }
                const notation = try buffer.toOwnedSlice();
                var number: usize = 0;
                for (result.notations.items, 0..) |previous, i| {
                    if (equal(previous, notation)) {
                        number = i + 1;
                        break;
                    }
                }
                if (number == 0) {
                    try result.notations.append(session.gpa, notation);
                    number = result.notations.items.len;
                }
                var next = matching;
                for (rotation.list(), 0..) |p, i| next.partners[p] = matching.partners[rotation.items[(i + 1) % rotation.len]];
                var seen = false;
                for (result.matchings.items) |previous| {
                    if (previous.matching.same(next, market.proposer_count)) {
                        seen = true;
                        break;
                    }
                }
                if (seen) continue;
                if (result.matchings.items.len == 50) return session.fail("TOO MANY MATCHINGS", .{});
                try result.matchings.append(session.gpa, Candidate.init(market, next, index + 1, number));
            }
        }
        return result;
    }
    fn hospitals(session: *Session, market: *const Market) Error!void {
        const a = (try deferred(session.gpa, market, false, false)).matching;
        const h = (try deferred(session.gpa, market, true, false)).matching;
        try line(session.out, "HR {f} residents={d} hospitals={d}", .{ market.name, market.proposer_count, market.count - market.proposer_count });
        try line(session.out, "RESIDENT-OPTIMAL {f}", .{Pairs{ .market = market, .matching = a }});
        try line(session.out, "HOSPITAL-OPTIMAL {f}", .{Pairs{ .market = market, .matching = h }});
        var unmatched: Sequence = .{};
        var rural = true;
        for (0..market.proposer_count) |p| {
            if (a.partners[p] == null) unmatched.append(p);
            if ((a.partners[p] == null) != (h.partners[p] == null)) rural = false;
        }
        try line(session.out, "UNMATCHED {f}", .{NamedList{ .names = market.names[0..market.count], .sequence = unmatched }});
        for (market.proposer_count..market.count) |r| {
            const first = market.residents(a, r);
            const second = market.residents(h, r);
            const same = std.mem.eql(usize, first.list(), second.list());
            try line(session.out, "HOSPITAL {f} cap={d} resident={d} hospital={d} same={s}", .{ market.names[r], market.capacities[r], first.len, second.len, if (same) "YES" else "NO" });
            if (first.len != second.len or (first.len < market.capacities[r] and !same)) rural = false;
        }
        try line(session.out, "RURAL {s}", .{if (rural) "HOLDS" else "FAILS"});
    }
    fn printTable(out: *Writer, market: *const Market, lists: *const [24]Sequence) Writer.Error!void {
        for (0..market.count) |a| try line(out, "TABLE {f} {f}", .{ market.names[a], NamedList{ .names = market.names[0..market.count], .sequence = lists[a] } });
    }
    fn empty(lists: *const [24]Sequence, count: usize) ?usize {
        for (lists[0..count], 0..) |list_value, a| if (list_value.len == 0) return a;
        return null;
    }
    fn roommates(session: *Session, market: *const Market, verbose: bool) Error!void {
        for (market.preferences[0..market.count], 0..) |preference, a| {
            if (preference.len != market.count - 1) return session.fail("INCOMPLETE {f}", .{market.names[a]});
        }
        var lists = market.preferences;
        var held: [24]?usize = @splat(null);
        var queue: std.ArrayList(usize) = .empty;
        for (0..market.count) |a| try queue.append(session.gpa, a);
        var trace: Writer.Allocating = .init(session.gpa);
        defer trace.deinit();
        var proposals: usize = 0;
        var failure: ?usize = null;
        while (proposals < queue.items.len) {
            const x = queue.items[proposals];
            proposals += 1;
            const y = lists[x].items[0];
            if (held[y]) |previous| try queue.append(session.gpa, previous);
            held[y] = x;
            const before = lists[y];
            for (before.list()[before.index(x).? + 1 ..]) |w| {
                lists[y].remove(w);
                lists[w].remove(y);
            }
            failure = empty(&lists, market.count);
            if (failure != null) break;
        }
        var rotation_count: usize = 0;
        if (failure == null) {
            if (verbose) try printTable(&trace.writer, market, &lists);
            while (true) {
                var start: ?usize = null;
                for (lists[0..market.count], 0..) |list_value, a| {
                    if (list_value.len > 1) {
                        start = a;
                        break;
                    }
                }
                var p = start orelse break;
                var seen: [24]?usize = @splat(null);
                var path: Sequence = .{};
                while (seen[p] == null) {
                    seen[p] = path.len;
                    path.append(p);
                    const q = lists[p].items[1];
                    p = lists[q].items[lists[q].len - 1];
                }
                var xs: Sequence = .{};
                var ys: Sequence = .{};
                for (path.list()[seen[p].?..]) |a| {
                    xs.append(a);
                    ys.append(lists[a].items[0]);
                }
                rotation_count += 1;
                try trace.writer.print("ROTATION {d}", .{rotation_count});
                for (xs.list(), ys.list()) |x, y| try trace.writer.print(" {f}-{f}", .{ market.names[x], market.names[y] });
                try trace.writer.writeByte('\n');
                var removals: std.ArrayList(Pair) = .empty;
                for (xs.list(), 0..) |x, i| {
                    const u = ys.items[(i + 1) % ys.len];
                    for (lists[u].list()[lists[u].index(x).? + 1 ..]) |w| try removals.append(session.gpa, .{ .first = u, .second = w });
                }
                for (removals.items) |pair| {
                    lists[pair.first].remove(pair.second);
                    lists[pair.second].remove(pair.first);
                }
                if (verbose) try printTable(&trace.writer, market, &lists);
                failure = empty(&lists, market.count);
                if (failure != null) break;
            }
        }
        try line(session.out, "ROOMMATES {f} proposals={d}", .{ market.name, proposals });
        try session.out.writeAll(trace.written());
        if (failure) |a| return line(session.out, "NO STABLE MATCHING {f}", .{market.names[a]});
        try session.out.writeAll("MATCHING");
        for (0..market.count) |a| {
            const b = lists[a].items[0];
            if (a < b) try session.out.print(" {f}-{f}", .{ market.names[a], market.names[b] });
        }
        try session.out.writeByte('\n');
    }
    fn tradingCycles(session: *Session, market: *const Market) Error!void {
        var remaining: [24]bool = @splat(true);
        var assigned: [24]?usize = @splat(null);
        var count = market.count;
        var cycles: usize = 0;
        var trace: Writer.Allocating = .init(session.gpa);
        defer trace.deinit();
        while (count > 0) {
            var pointers: [24]usize = undefined;
            var start: ?usize = null;
            for (0..market.count) |a| {
                if (!remaining[a]) continue;
                if (start == null) start = a;
                const effective = market.effective(a);
                for (effective.list()) |h| {
                    if (remaining[h]) {
                        pointers[a] = h;
                        break;
                    }
                }
            }
            var seen: [24]?usize = @splat(null);
            var path: Sequence = .{};
            var current = start.?;
            while (seen[current] == null) {
                seen[current] = path.len;
                path.append(current);
                current = pointers[current];
            }
            cycles += 1;
            try trace.writer.print("CYCLE {d}", .{cycles});
            for (path.list()[seen[current].?..]) |a| {
                assigned[a] = pointers[a];
                remaining[a] = false;
                count -= 1;
                try trace.writer.print(" {f}:{f}", .{ market.names[a], market.houses[pointers[a]] });
            }
            try trace.writer.writeByte('\n');
        }
        try line(session.out, "TTC {f} cycles={d}", .{ market.name, cycles });
        try session.out.writeAll(trace.written());
        try line(session.out, "ALLOCATION {f}", .{Allocation{ .market = market, .houses = assigned }});
    }
    fn serial(session: *Session, market: *const Market, words: []const []const u8) Error!void {
        var order: Sequence = .{};
        for (words[2..]) |word| {
            const a = try session.agent(market, word);
            if (order.index(a) != null) return session.fail("DUPLICATE AGENT {s}", .{word});
            order.append(a);
        }
        if (order.len != market.count) return session.fail("BAD ORDER", .{});
        var assigned: [24]?usize = @splat(null);
        var available: [12]bool = @splat(true);
        var count: usize = 0;
        for (order.list()) |a| {
            for (market.preferences[a].list()) |h| {
                if (available[h]) {
                    assigned[a] = h;
                    available[h] = false;
                    count += 1;
                    break;
                }
            }
        }
        var worse: Sequence = .{};
        for (0..market.count) |a| {
            const effective = market.effective(a);
            if (assigned[a] == null or effective.index(assigned[a].?) == null) worse.append(a);
        }
        try line(session.out, "SERIAL {f} assigned={d}", .{ market.name, count });
        try line(session.out, "ALLOCATION {f}", .{Allocation{ .market = market, .houses = assigned }});
        try line(session.out, "WORSE {f}", .{NamedList{ .names = market.names[0..market.count], .sequence = worse }});
    }
    fn manipulate(session: *Session, market: *const Market, agent_value: usize) Error!void {
        const truth = market.preferences[agent_value];
        const b0 = boston(market).matching.partners[agent_value];
        const g0 = (try deferred(session.gpa, market, false, false)).matching.partners[agent_value];
        const swaps = if (truth.len == 0) 0 else truth.len - 1;
        try line(session.out, "MANIPULATE {f} {f} boston={f} gs={f} swaps={d}", .{ market.name, market.names[agent_value], Partner{ .market = market, .agent = b0 }, Partner{ .market = market, .agent = g0 }, swaps });
        var improved = false;
        for (0..swaps) |i| {
            var trial = market.*;
            trial.preferences[agent_value].items[i] = truth.items[i + 1];
            trial.preferences[agent_value].items[i + 1] = truth.items[i];
            const b = boston(&trial).matching.partners[agent_value];
            const g = (try deferred(session.gpa, &trial, false, false)).matching.partners[agent_value];
            if (truth.rank(b) < truth.rank(b0)) {
                improved = true;
                try line(session.out, "IMPROVE BOSTON {d} {f} {f} result={f}", .{ i + 1, market.names[truth.items[i]], market.names[truth.items[i + 1]], Partner{ .market = market, .agent = b } });
            }
            if (truth.rank(g) < truth.rank(g0)) {
                improved = true;
                try line(session.out, "IMPROVE GS {d} {f} {f} result={f}", .{ i + 1, market.names[truth.items[i]], market.names[truth.items[i + 1]], Partner{ .market = market, .agent = g } });
            }
        }
        if (!improved) try line(session.out, "NO IMPROVEMENT", .{});
    }
    fn stats(session: *Session, market: *const Market) Error!void {
        const matching = market.current orelse return session.fail("NO MATCHING", .{});
        var proposer_ranks: Sequence = .{};
        var receiver_ranks: Sequence = .{};
        var occupied: [24]bool = @splat(false);
        for (0..market.proposer_count) |p| {
            if (matching.partners[p]) |r| {
                proposer_ranks.append(market.rank(p, r));
                receiver_ranks.append(market.rank(r, p));
                occupied[r] = true;
            }
        }
        var unmatched: usize = 0;
        for (occupied[market.proposer_count..market.count]) |has_partner| unmatched += @intFromBool(!has_partner);
        try line(session.out, "STATS {f} source={s} pairs={d}", .{ market.name, @tagName(market.source.?), proposer_ranks.len });
        try line(session.out, "PROPOSERS {f}", .{RankSummary{ .ranks = proposer_ranks, .unmatched = market.proposer_count - proposer_ranks.len }});
        try line(session.out, "RECEIVERS {f}", .{RankSummary{ .ranks = receiver_ranks, .unmatched = unmatched }});
    }
    fn execute(session: *Session, text: []const u8) Error!void {
        var words: [32][]const u8 = undefined;
        var count: usize = 0;
        var iterator = std.mem.tokenizeScalar(u8, text, ' ');
        while (iterator.next()) |word| {
            words[count] = word;
            count += 1;
        }
        const w = words[0..count];
        const command = std.meta.stringToEnum(Command, w[0]).?;
        const name = w[1];
        const out = session.out;
        switch (command) {
            .MARKET, .ROOMS => {
                try session.newName(name);
                var market: Market = .{ .name = Name.init(name), .kind = if (command == .MARKET) .two_sided else .roommates };
                for (w[2..]) |word| {
                    if (equal(word, "|")) {
                        market.proposer_count = market.count;
                        continue;
                    }
                    if (market.find(word) != null) return session.fail("DUPLICATE AGENT {s}", .{word});
                    market.names[market.count] = Name.init(word);
                    market.count += 1;
                }
                try session.markets.append(session.storage, market);
                if (command == .MARKET) {
                    try line(out, "MARKET {s} proposers={d} receivers={d}", .{ name, market.proposer_count, market.count - market.proposer_count });
                } else try line(out, "ROOMS {s} agents={d}", .{ name, market.count });
            },
            .HOUSES => {
                try session.newName(name);
                var market: Market = .{ .name = Name.init(name), .kind = .housing };
                for (w[2..]) |word| {
                    const separator = std.mem.findScalar(u8, word, ':').?;
                    const agent_name = word[0..separator];
                    const house_name = word[separator + 1 ..];
                    if (market.find(agent_name) != null) return session.fail("DUPLICATE AGENT {s}", .{agent_name});
                    if (market.house(house_name) != null) return session.fail("DUPLICATE HOUSE {s}", .{house_name});
                    market.names[market.count] = Name.init(agent_name);
                    market.houses[market.count] = Name.init(house_name);
                    market.count += 1;
                }
                try session.markets.append(session.storage, market);
                try line(out, "HOUSES {s} agents={d}", .{ name, market.count });
            },
            .RANDOM => {
                try session.newName(name);
                const size = integer(w[2]);
                const seed: u64 = @intCast(integer(w[3]));
                var state = seed;
                var market: Market = .{ .name = Name.init(name), .kind = .two_sided, .count = size * 2, .proposer_count = size };
                for (0..market.count) |a| {
                    var bytes: [8]u8 = undefined;
                    const agent_name = std.fmt.bufPrint(&bytes, "{s}{d}", .{ if (a < size) "P" else "R", a % size + 1 }) catch unreachable;
                    market.names[a] = Name.init(agent_name);
                    var preference: Sequence = .{};
                    for (0..size) |i| preference.append(if (a < size) i + size else i);
                    var length = size;
                    while (length > 1) : (length -= 1) {
                        state = 48271 * state % 2147483647;
                        const j: usize = @intCast(state % @as(u64, @intCast(length)));
                        const first = preference.items[length - 1];
                        preference.items[length - 1] = preference.items[j];
                        preference.items[j] = first;
                    }
                    market.preferences[a] = preference;
                }
                try session.markets.append(session.storage, market);
                try line(out, "RANDOM {s} n={d} seed={d}", .{ name, size, seed });
            },
            .PREF => {
                const market = try session.get(name, null);
                const agent_value = try session.agent(market, w[2]);
                var choices: Sequence = .{};
                for (w[3..]) |word| {
                    const choice_value = try session.choice(market, agent_value, word);
                    if (choices.index(choice_value) != null) return session.fail("DUPLICATE CHOICE {s}", .{word});
                    choices.append(choice_value);
                }
                market.preferences[agent_value] = choices;
                if (market.kind == .two_sided) market.clear();
                try line(out, "PREF {s} {s} length={d}", .{ name, w[2], choices.len });
            },
            .CAPACITY => {
                const market = try session.get(name, .two_sided);
                const receiver_value = try session.receiver(market, w[2]);
                const capacity = integer(w[3]);
                market.capacities[receiver_value] = capacity;
                market.clear();
                try line(out, "CAPACITY {s} {s} {d}", .{ name, w[2], capacity });
            },
            .SHOW => try session.show(try session.get(name, null)),
            .CHECK => try session.check(try session.get(name, null), w),
            .GS, .GSR, .BOSTON => {
                const market = try session.get(name, .two_sided);
                const result = if (command == .BOSTON) boston(market) else try deferred(session.gpa, market, command == .GSR, count == 3);
                market.save(result.matching, command);
                try line(out, "{s} {s} {s}={d}", .{ @tagName(command), name, if (command == .BOSTON) "applications" else "proposals", result.proposals });
                try out.writeAll(result.log);
                try line(out, "MATCHING {f}", .{Pairs{ .market = market, .matching = result.matching }});
            },
            .LATTICE, .EGALITARIAN, .MINREGRET => {
                const market = try session.get(name, .two_sided);
                const result = try session.enumerate(market);
                if (command == .LATTICE) {
                    try line(out, "LATTICE {s} matchings={d} rotations={d}", .{ name, result.matchings.items.len, result.notations.items.len });
                    for (result.matchings.items, 0..) |candidate, i| {
                        try out.print("MATCHING {d} from=", .{i + 1});
                        if (candidate.origin == 0) try out.writeByte('-') else try out.print("{d}", .{candidate.origin});
                        try out.writeAll(" via=");
                        if (candidate.via == 0) try out.writeByte('-') else try out.print("{d}", .{candidate.via});
                        try line(out, " cost={d} regret={d} {f}", .{ candidate.cost, candidate.regret, Pairs{ .market = market, .matching = candidate.matching } });
                    }
                    for (result.notations.items, 0..) |notation, i| try line(out, "ROTATION {d} {s}", .{ i + 1, notation });
                } else {
                    var best: usize = 0;
                    for (result.matchings.items, 0..) |candidate, i| {
                        if (if (command == .EGALITARIAN) candidate.cost < result.matchings.items[best].cost else candidate.regret < result.matchings.items[best].regret) best = i;
                    }
                    const selected = result.matchings.items[best];
                    market.save(selected.matching, command);
                    try line(out, "{s} {s} matching={d} {s}={d}", .{ @tagName(command), name, best + 1, if (command == .EGALITARIAN) "cost" else "regret", if (command == .EGALITARIAN) selected.cost else selected.regret });
                    try line(out, "MATCHING {f}", .{Pairs{ .market = market, .matching = selected.matching }});
                }
            },
            .HR => try session.hospitals(try session.get(name, .two_sided)),
            .ROOMMATES => try session.roommates(try session.get(name, .roommates), count == 3),
            .TTC => try session.tradingCycles(try session.get(name, .housing)),
            .SERIAL => try session.serial(try session.get(name, .housing), w),
            .MANIPULATE => {
                const market = try session.get(name, .two_sided);
                const agent_value = try session.proposer(market, w[2]);
                try session.manipulate(market, agent_value);
            },
            .STATS => try session.stats(try session.get(name, .two_sided)),
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    var markets: std.ArrayList(Market) = .empty;
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = integer(try readLine(storage.allocator(), &input.interface));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const text = try readLine(gpa, &input.interface);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = gpa, .storage = storage.allocator(), .markets = &markets, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
