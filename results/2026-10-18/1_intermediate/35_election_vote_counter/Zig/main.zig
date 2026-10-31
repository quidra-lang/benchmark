const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Method = enum { PLURALITY, RUNOFF, IRV, COOMBS, BUCKLIN, BORDA, BALDWIN, NANSON, BLACK, VETO, CONDORCET, COPELAND, MINIMAX, SCHULZE, RANKEDPAIRS, KEMENY, APPROVAL, STV };
const MinimaxKind = enum { WINNING, MARGIN, OPPOSITION };
const ScoreKind = enum { first, last, borda };
const Scores = [7]i64;
const Matrix = [7]Scores;
const Edges = [7][7]bool;
const zero_scores: Scores = @splat(0);
const zero_matrix: Matrix = @splat(zero_scores);
const no_edges: Edges = @splat(@as([7]bool, @splat(false)));

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn integer(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void {
    try out.print(fmt ++ "\n", args);
}
fn tieText(tie: bool) []const u8 {
    return if (tie) " (tie)" else "";
}
fn totalScores(scores: Scores) i64 {
    var result: i64 = 0;
    for (scores) |score| result += score;
    return result;
}
const MethodSpec = struct {
    kind: Method,
    parameter: usize = 0,
    minimax: MinimaxKind = .WINNING,
    fn parse(words: []const []const u8) MethodSpec {
        const kind = std.meta.stringToEnum(Method, words[0]).?;
        return switch (kind) {
            .MINIMAX => .{ .kind = kind, .minimax = std.meta.stringToEnum(MinimaxKind, words[1]).? },
            .APPROVAL, .STV => .{ .kind = kind, .parameter = integer(words[1]) },
            else => .{ .kind = kind },
        };
    }
    fn rankable(method: MethodSpec) bool {
        return method.kind != .CONDORCET and method.kind != .STV;
    }
    pub fn format(method: MethodSpec, out: *Writer) Writer.Error!void {
        try out.writeAll(@tagName(method.kind));
        switch (method.kind) {
            .MINIMAX => try out.print(" {s}", .{@tagName(method.minimax)}),
            .APPROVAL, .STV => try out.print(" {d}", .{method.parameter}),
            else => {},
        }
    }
};
const summary_methods = [_]MethodSpec{
    .{ .kind = .PLURALITY }, .{ .kind = .RUNOFF },      .{ .kind = .IRV },      .{ .kind = .COOMBS },
    .{ .kind = .BUCKLIN },   .{ .kind = .BORDA },       .{ .kind = .BALDWIN },  .{ .kind = .NANSON },
    .{ .kind = .BLACK },     .{ .kind = .VETO },        .{ .kind = .COPELAND }, .{ .kind = .MINIMAX },
    .{ .kind = .SCHULZE },   .{ .kind = .RANKEDPAIRS }, .{ .kind = .KEMENY },
};
const Name = struct {
    bytes: [12]u8 = undefined,
    len: usize = 0,
    fn init(text_value: []const u8) Name {
        var name: Name = .{ .len = text_value.len };
        @memcpy(name.bytes[0..text_value.len], text_value);
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
    items: [7]usize = undefined,
    len: usize = 0,
    fn list(sequence: *const Sequence) []const usize {
        return sequence.items[0..sequence.len];
    }
    fn append(sequence: *Sequence, candidate: usize) void {
        sequence.items[sequence.len] = candidate;
        sequence.len += 1;
    }
    fn index(sequence: *const Sequence, candidate: usize) ?usize {
        for (sequence.list(), 0..) |item, i| if (item == candidate) return i;
        return null;
    }
    fn remove(sequence: *Sequence, candidate: usize) void {
        const position = sequence.index(candidate) orelse return;
        var i = position;
        while (i + 1 < sequence.len) : (i += 1) sequence.items[i] = sequence.items[i + 1];
        sequence.len -= 1;
    }
    fn filtered(sequence: Sequence, field: Sequence) Sequence {
        var result: Sequence = .{};
        for (sequence.list()) |candidate| if (field.index(candidate) != null) result.append(candidate);
        return result;
    }
    fn extend(sequence: *Sequence, other: Sequence) void {
        for (other.list()) |candidate| sequence.append(candidate);
    }
    fn reversed(sequence: Sequence) Sequence {
        var result: Sequence = .{};
        var i = sequence.len;
        while (i > 0) {
            i -= 1;
            result.append(sequence.items[i]);
        }
        return result;
    }
};
const Ballot = struct { votes: i64, ranking: Sequence };
const Entry = []const Ballot;
const Election = struct {
    number: usize,
    names: [7]Name = undefined,
    count: usize = 0,
    withdrawn: [7]bool = @splat(false),
    tie_order: Sequence = .{},
    entries: std.ArrayList(Entry) = .empty,
    fn find(election: *const Election, text: []const u8) ?usize {
        for (election.names[0..election.count], 0..) |name, i| if (equal(name.text(), text)) return i;
        return null;
    }
    fn active(election: *const Election) Sequence {
        var result: Sequence = .{};
        for (0..election.count) |i| if (!election.withdrawn[i]) result.append(i);
        return result;
    }
    fn total(election: *const Election) i64 {
        var result: i64 = 0;
        for (election.entries.items) |entry| for (entry) |group| {
            result += group.votes;
        };
        return result;
    }
};
const NamedList = struct {
    election: *const Election,
    candidates: Sequence,
    separator: []const u8 = ", ",
    pub fn format(value: NamedList, out: *Writer) Writer.Error!void {
        for (value.candidates.list(), 0..) |candidate, i| {
            if (i > 0) try out.writeAll(value.separator);
            try out.print("{f}", .{value.election.names[candidate]});
        }
    }
};
const Amount = struct {
    value: i64,
    pub fn format(amount: Amount, out: *Writer) Writer.Error!void {
        try out.print("{d}.{d:0>2}", .{ @divTrunc(amount.value, 100), @mod(amount.value, 100) });
    }
};
const ValueList = struct {
    election: *const Election,
    candidates: Sequence,
    scores: Scores,
    amounts: bool = false,
    pub fn format(value: ValueList, out: *Writer) Writer.Error!void {
        for (value.candidates.list(), 0..) |candidate, i| {
            if (i > 0) try out.writeAll(", ");
            try out.print("{f} ", .{value.election.names[candidate]});
            if (value.amounts) try out.print("{f}", .{Amount{ .value = value.scores[candidate] }}) else try out.print("{d}", .{value.scores[candidate]});
        }
    }
};
const Selection = struct { candidate: usize, tie: bool };
const Outcome = struct { standings: Sequence = .{}, tie: bool = false, exhaustion: []const u8 = "" };
const TallyResult = struct { standings: Sequence, tie: bool, output: []const u8, exhaustion: []const u8 };
const Tally = struct {
    election: *const Election,
    field: Sequence,
    priority: [7]usize = @splat(0),
    groups: []const Ballot,
    pairwise: Matrix = zero_matrix,
    total: i64 = 0,
    fn init(gpa: Allocator, election: *const Election, field: Sequence) Allocator.Error!Tally {
        var groups: std.ArrayList(Ballot) = .empty;
        for (election.entries.items) |entry| for (entry) |group| {
            try groups.append(gpa, .{ .votes = group.votes, .ranking = group.ranking.filtered(field) });
        };
        var tally: Tally = .{ .election = election, .field = field, .groups = groups.items };
        for (election.tie_order.list(), 0..) |candidate, i| tally.priority[candidate] = i;
        for (tally.groups) |group| {
            tally.total += group.votes;
            var positions: [7]usize = @splat(7);
            for (group.ranking.list(), 0..) |candidate, i| positions[candidate] = i;
            for (field.list()) |x| for (field.list()) |y| {
                if (positions[x] < positions[y]) tally.pairwise[x][y] += group.votes;
            };
        }
        return tally;
    }
    fn names(tally: *const Tally, candidates: Sequence) NamedList {
        return .{ .election = tally.election, .candidates = candidates };
    }
    fn ranking(tally: *const Tally, candidates: Sequence) NamedList {
        return .{ .election = tally.election, .candidates = candidates, .separator = " > " };
    }
    fn values(tally: *const Tally, candidates: Sequence, totals: Scores) ValueList {
        return .{ .election = tally.election, .candidates = candidates, .scores = totals };
    }
    fn scores(tally: *const Tally, candidates: Sequence, kind: ScoreKind) Scores {
        var result = zero_scores;
        for (tally.groups) |group| {
            const ranked = group.ranking.filtered(candidates);
            switch (kind) {
                .first => if (ranked.len > 0) {
                    result[ranked.items[0]] += group.votes;
                },
                .last => {
                    if (ranked.len == candidates.len) {
                        result[ranked.items[ranked.len - 1]] += group.votes;
                    } else {
                        for (candidates.list()) |candidate| {
                            if (ranked.index(candidate) == null) result[candidate] += group.votes;
                        }
                    }
                },
                .borda => for (ranked.list(), 0..) |candidate, i| {
                    result[candidate] += group.votes * @as(i64, @intCast(candidates.len - i - 1));
                },
            }
        }
        return result;
    }
    fn approval(tally: *const Tally, depth: usize) Scores {
        var result = zero_scores;
        for (tally.groups) |group| for (group.ranking.list()[0..@min(depth, group.ranking.len)]) |candidate| {
            result[candidate] += group.votes;
        };
        return result;
    }
    fn order(tally: *const Tally, candidates: Sequence, values_: Scores, descending: bool) Sequence {
        const Context = struct {
            values: Scores,
            priority: [7]usize,
            descending: bool,
            fn less(context: @This(), a: usize, b: usize) bool {
                if (context.values[a] != context.values[b]) return if (context.descending) context.values[a] > context.values[b] else context.values[a] < context.values[b];
                return context.priority[a] < context.priority[b];
            }
        };
        var result = candidates;
        std.sort.heap(usize, result.items[0..result.len], Context{ .values = values_, .priority = tally.priority, .descending = descending }, Context.less);
        return result;
    }
    fn priorityOrder(tally: *const Tally, candidates: Sequence) Sequence {
        return tally.order(candidates, zero_scores, true);
    }
    fn topTie(order_: Sequence, counts: Scores) bool {
        return order_.len > 1 and counts[order_.items[0]] == counts[order_.items[1]];
    }
    fn eliminate(tally: *const Tally, candidates: Sequence, values_: Scores, history: []const Scores) Selection {
        var lowest = values_[candidates.items[0]];
        for (candidates.list()) |candidate| lowest = @min(lowest, values_[candidate]);
        var pool: Sequence = .{};
        for (candidates.list()) |candidate| if (values_[candidate] == lowest) pool.append(candidate);
        const tie = pool.len > 1;
        var round = history.len;
        while (round > 0) {
            round -= 1;
            const previous = history[round];
            lowest = previous[pool.items[0]];
            for (pool.list()) |candidate| lowest = @min(lowest, previous[candidate]);
            var narrowed: Sequence = .{};
            for (pool.list()) |candidate| if (previous[candidate] == lowest) narrowed.append(candidate);
            pool = narrowed;
        }
        const sorted = tally.priorityOrder(pool);
        return .{ .candidate = sorted.items[sorted.len - 1], .tie = tie };
    }
    fn condorcet(tally: *const Tally, loser: bool) ?usize {
        for (tally.field.list()) |x| {
            var qualifies = true;
            for (tally.field.list()) |y| {
                if (x == y) continue;
                if (if (loser) tally.pairwise[x][y] >= tally.pairwise[y][x] else tally.pairwise[x][y] <= tally.pairwise[y][x]) {
                    qualifies = false;
                    break;
                }
            }
            if (qualifies) return x;
        }
        return null;
    }
    fn pairLines(tally: *const Tally, out: *Writer, matrix: Matrix) Writer.Error!void {
        for (tally.field.list(), 0..) |x, i| for (tally.field.list()[i + 1 ..]) |y| {
            try out.print("{f} vs {f}: {d}-{d} (", .{ tally.election.names[x], tally.election.names[y], matrix[x][y], matrix[y][x] });
            if (matrix[x][y] == matrix[y][x]) try out.writeAll("tie") else try out.print("{f}", .{tally.election.names[if (matrix[x][y] > matrix[y][x]) x else y]});
            try out.writeAll(")\n");
        };
    }
    fn run(tally: *const Tally, gpa: Allocator, method: MethodSpec) Error!TallyResult {
        var output: Writer.Allocating = .init(gpa);
        defer output.deinit();
        const calculation: Calculation = .{ .gpa = gpa, .tally = tally, .out = &output.writer };
        const result = try calculation.run(method);
        return .{ .standings = result.standings, .tie = result.tie, .output = try output.toOwnedSlice(), .exhaustion = result.exhaustion };
    }
};

const Calculation = struct {
    gpa: Allocator,
    tally: *const Tally,
    out: *Writer,
    fn finish(calculation: Calculation, result: Outcome) Error!Outcome {
        try line(calculation.out, "winner: {f}{s}", .{ calculation.tally.election.names[result.standings.items[0]], tieText(result.tie) });
        return result;
    }
    fn scored(calculation: Calculation, counts: Scores, label: []const u8, descending: bool) Error!Outcome {
        const tally = calculation.tally;
        const order = tally.order(tally.field, counts, descending);
        try line(calculation.out, "{s}: {f}", .{ label, tally.values(tally.field, counts) });
        return calculation.finish(.{ .standings = order, .tie = Tally.topTie(order, counts) });
    }
    fn runoff(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        const first = tally.scores(tally.field, .first);
        var order = tally.order(tally.field, first, true);
        try line(calculation.out, "round 1: {f}", .{tally.values(tally.field, first)});
        if (2 * first[order.items[0]] > totalScores(first)) return calculation.finish(.{ .standings = order });
        var finalists: Sequence = .{};
        for (tally.field.list()) |candidate| if (candidate == order.items[0] or candidate == order.items[1]) finalists.append(candidate);
        const advancement = order.len > 2 and first[order.items[1]] == first[order.items[2]];
        const second = tally.scores(finalists, .first);
        const tie = second[order.items[0]] == second[order.items[1]];
        if (second[order.items[0]] < second[order.items[1]]) std.mem.swap(usize, &order.items[0], &order.items[1]);
        try line(calculation.out, "finalists: {f}{s}", .{ tally.names(finalists), tieText(advancement) });
        try line(calculation.out, "round 2: {f}", .{tally.values(finalists, second)});
        return calculation.finish(.{ .standings = order, .tie = tie });
    }
    fn instantRunoff(calculation: Calculation, coombs: bool) Error!Outcome {
        const tally = calculation.tally;
        var remaining = tally.field;
        var removed: Sequence = .{};
        var history: [7]Scores = undefined;
        var history_count: usize = 0;
        var exhaustion: Writer.Allocating = .init(calculation.gpa);
        defer exhaustion.deinit();
        var round: usize = 0;
        while (true) {
            const first = tally.scores(remaining, .first);
            const active = totalScores(first);
            round += 1;
            try calculation.out.print("round {d}: {f}", .{ round, tally.values(remaining, first) });
            try line(&exhaustion.writer, "round {d}: active {d}, exhausted {d}", .{ round, active, tally.total - active });
            var majority = false;
            for (remaining.list()) |candidate| if (2 * first[candidate] > active) {
                majority = true;
            };
            if (remaining.len == 1 or majority) {
                try calculation.out.writeByte('\n');
                var order = tally.order(remaining, first, true);
                order.extend(removed.reversed());
                return calculation.finish(.{ .standings = order, .exhaustion = try exhaustion.toOwnedSlice() });
            }
            const selection = if (coombs) choice: {
                const last = tally.scores(remaining, .last);
                var highest = last[remaining.items[0]];
                for (remaining.list()) |candidate| highest = @max(highest, last[candidate]);
                var pool: Sequence = .{};
                for (remaining.list()) |candidate| if (last[candidate] == highest) pool.append(candidate);
                const sorted = tally.order(pool, first, true);
                try calculation.out.print("; last {f}", .{tally.values(remaining, last)});
                break :choice Selection{ .candidate = sorted.items[sorted.len - 1], .tie = pool.len > 1 };
            } else tally.eliminate(remaining, first, history[0..history_count]);
            try line(calculation.out, "; eliminated {f}{s}", .{ tally.election.names[selection.candidate], tieText(selection.tie) });
            history[history_count] = first;
            history_count += 1;
            removed.append(selection.candidate);
            remaining.remove(selection.candidate);
        }
    }
    fn bucklin(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        var nonblank: i64 = 0;
        for (tally.groups) |group| if (group.ranking.len > 0) {
            nonblank += group.votes;
        };
        const majority = @divTrunc(nonblank, 2) + 1;
        try line(calculation.out, "majority: {d}", .{majority});
        var history: [7]Scores = undefined;
        var rounds: usize = 0;
        while (rounds < tally.field.len) {
            const current = tally.approval(rounds + 1);
            history[rounds] = current;
            rounds += 1;
            try line(calculation.out, "round {d}: {f}", .{ rounds, tally.values(tally.field, current) });
            var reached = false;
            for (tally.field.list()) |candidate| if (current[candidate] >= majority) {
                reached = true;
            };
            if (reached) break;
        }
        const Context = struct {
            rounds: []const Scores,
            priority: [7]usize,
            fn less(context: @This(), a: usize, b: usize) bool {
                var i = context.rounds.len;
                while (i > 0) {
                    i -= 1;
                    if (context.rounds[i][a] != context.rounds[i][b]) return context.rounds[i][a] > context.rounds[i][b];
                }
                return context.priority[a] < context.priority[b];
            }
        };
        var order = tally.field;
        std.sort.heap(usize, order.items[0..order.len], Context{ .rounds = history[0..rounds], .priority = tally.priority }, Context.less);
        return calculation.finish(.{ .standings = order, .tie = Tally.topTie(order, history[rounds - 1]) });
    }
    fn bordaElimination(calculation: Calculation, nanson: bool) Error!Outcome {
        const tally = calculation.tally;
        var remaining = tally.field;
        var removed: [7]Sequence = undefined;
        var history: [7]Scores = undefined;
        var rounds: usize = 0;
        while (remaining.len > 1) {
            const current = tally.scores(remaining, .borda);
            try calculation.out.print("round {d}: {f}", .{ rounds + 1, tally.values(remaining, current) });
            var losers: Sequence = .{};
            if (nanson) {
                const total = totalScores(current);
                for (remaining.list()) |candidate| if (current[candidate] * @as(i64, @intCast(remaining.len)) < total) losers.append(candidate);
                if (losers.len == 0) {
                    try calculation.out.writeByte('\n');
                    break;
                }
                try line(calculation.out, "; eliminated {f}", .{tally.names(losers)});
            } else {
                const selection = tally.eliminate(remaining, current, history[0..rounds]);
                losers.append(selection.candidate);
                try line(calculation.out, "; eliminated {f}{s}", .{ tally.election.names[selection.candidate], tieText(selection.tie) });
            }
            removed[rounds] = tally.order(losers, current, true);
            history[rounds] = current;
            rounds += 1;
            for (losers.list()) |candidate| remaining.remove(candidate);
        }
        var order = tally.priorityOrder(remaining);
        var i = rounds;
        while (i > 0) {
            i -= 1;
            order.extend(removed[i]);
        }
        return calculation.finish(.{ .standings = order, .tie = nanson and remaining.len > 1 });
    }
    fn black(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        const winner = tally.condorcet(false);
        const current = tally.scores(tally.field, .borda);
        var order = tally.order(tally.field, current, true);
        const tie = winner == null and Tally.topTie(order, current);
        try calculation.out.writeAll("condorcet: ");
        if (winner) |candidate| {
            try line(calculation.out, "{f}", .{tally.election.names[candidate]});
            order.remove(candidate);
            var adjusted: Sequence = .{};
            adjusted.append(candidate);
            adjusted.extend(order);
            order = adjusted;
        } else try calculation.out.writeAll("NONE\n");
        try line(calculation.out, "scores: {f}", .{tally.values(tally.field, current)});
        return calculation.finish(.{ .standings = order, .tie = tie });
    }
    fn condorcetReport(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        var weak = no_edges;
        var strong = no_edges;
        for (tally.field.list()) |x| for (tally.field.list()) |y| {
            weak[x][y] = x == y or tally.pairwise[x][y] >= tally.pairwise[y][x];
            strong[x][y] = x != y and tally.pairwise[x][y] > tally.pairwise[y][x];
        };
        for (tally.field.list()) |via| for (tally.field.list()) |x| for (tally.field.list()) |y| {
            weak[x][y] = weak[x][y] or (weak[x][via] and weak[via][y]);
            strong[x][y] = strong[x][y] or (strong[x][via] and strong[via][y]);
        };
        var smith: Sequence = .{};
        var schwartz: Sequence = .{};
        for (tally.field.list()) |x| {
            var is_smith = true;
            var is_schwartz = true;
            for (tally.field.list()) |y| {
                if (!weak[x][y]) is_smith = false;
                if (strong[y][x] and !strong[x][y]) is_schwartz = false;
            }
            if (is_smith) smith.append(x);
            if (is_schwartz) schwartz.append(x);
        }
        try calculation.out.writeAll("winner: ");
        if (tally.condorcet(false)) |candidate| try line(calculation.out, "{f}", .{tally.election.names[candidate]}) else try calculation.out.writeAll("NONE\n");
        try calculation.out.writeAll("loser: ");
        if (tally.condorcet(true)) |candidate| try line(calculation.out, "{f}", .{tally.election.names[candidate]}) else try calculation.out.writeAll("NONE\n");
        try line(calculation.out, "smith: {f}", .{tally.names(smith)});
        try line(calculation.out, "schwartz: {f}", .{tally.names(schwartz)});
        return .{};
    }
    fn copeland(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        var current = zero_scores;
        try calculation.out.writeAll("scores: ");
        for (tally.field.list(), 0..) |x, i| {
            var wins: i64 = 0;
            var draws: i64 = 0;
            var losses: i64 = 0;
            for (tally.field.list()) |y| {
                if (x == y) continue;
                if (tally.pairwise[x][y] > tally.pairwise[y][x]) wins += 1 else if (tally.pairwise[x][y] == tally.pairwise[y][x]) draws += 1 else losses += 1;
            }
            current[x] = 2 * wins + draws;
            if (i > 0) try calculation.out.writeAll(", ");
            try calculation.out.print("{f} {d}.{d} ({d}-{d}-{d})", .{ tally.election.names[x], @divTrunc(current[x], 2), @mod(current[x], 2) * 5, wins, draws, losses });
        }
        try calculation.out.writeByte('\n');
        const order = tally.order(tally.field, current, true);
        return calculation.finish(.{ .standings = order, .tie = Tally.topTie(order, current) });
    }
    fn minimax(calculation: Calculation, kind: MinimaxKind) Error!Outcome {
        const tally = calculation.tally;
        var current = zero_scores;
        for (tally.field.list()) |x| for (tally.field.list()) |y| {
            if (x == y or (kind != .OPPOSITION and tally.pairwise[y][x] <= tally.pairwise[x][y])) continue;
            current[x] = @max(current[x], if (kind == .MARGIN) tally.pairwise[y][x] - tally.pairwise[x][y] else tally.pairwise[y][x]);
        };
        return calculation.scored(current, "scores", false);
    }
    fn dominanceOrder(calculation: Calculation, edges: Edges) Outcome {
        const tally = calculation.tally;
        var remaining = tally.field;
        var order: Sequence = .{};
        var tie = false;
        while (remaining.len > 0) {
            var eligible: Sequence = .{};
            for (remaining.list()) |x| {
                var incoming = false;
                for (remaining.list()) |y| if (x != y and edges[y][x]) {
                    incoming = true;
                };
                if (!incoming) eligible.append(x);
            }
            if (order.len == 0) tie = eligible.len > 1;
            const next = tally.priorityOrder(eligible).items[0];
            order.append(next);
            remaining.remove(next);
        }
        return .{ .standings = order, .tie = tie };
    }
    fn schulze(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        var paths = zero_matrix;
        for (tally.field.list()) |x| for (tally.field.list()) |y| {
            if (x != y and tally.pairwise[x][y] > tally.pairwise[y][x]) paths[x][y] = tally.pairwise[x][y];
        };
        for (tally.field.list()) |via| for (tally.field.list()) |x| {
            if (x == via) continue;
            for (tally.field.list()) |y| {
                if (y == via or y == x) continue;
                paths[x][y] = @max(paths[x][y], @min(paths[x][via], paths[via][y]));
            }
        };
        var dominance = no_edges;
        for (tally.field.list()) |x| for (tally.field.list()) |y| {
            dominance[x][y] = paths[x][y] > paths[y][x];
        };
        const result = calculation.dominanceOrder(dominance);
        try tally.pairLines(calculation.out, paths);
        try line(calculation.out, "ranking: {f}", .{tally.ranking(result.standings)});
        return calculation.finish(result);
    }
    fn rankedPairs(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        const Pair = struct { first: usize, second: usize };
        const Context = struct {
            tally: *const Tally,
            fn less(context: @This(), a: Pair, b: Pair) bool {
                const d = context.tally.pairwise;
                if (d[a.first][a.second] != d[b.first][b.second]) return d[a.first][a.second] > d[b.first][b.second];
                if (d[a.second][a.first] != d[b.second][b.first]) return d[a.second][a.first] < d[b.second][b.first];
                const p = context.tally.priority;
                return if (p[a.first] != p[b.first]) p[a.first] < p[b.first] else p[a.second] < p[b.second];
            }
        };
        var pairs: [21]Pair = undefined;
        var count: usize = 0;
        for (tally.field.list()) |x| for (tally.field.list()) |y| {
            if (tally.pairwise[x][y] > tally.pairwise[y][x]) {
                pairs[count] = .{ .first = x, .second = y };
                count += 1;
            }
        };
        std.sort.heap(Pair, pairs[0..count], Context{ .tally = tally }, Context.less);
        var locked = no_edges;
        var reached = no_edges;
        for (pairs[0..count]) |pair| {
            const x = pair.first;
            const y = pair.second;
            const skip = reached[y][x];
            if (!skip) {
                locked[x][y] = true;
                reached[x][y] = true;
                for (tally.field.list()) |via| for (tally.field.list()) |a| for (tally.field.list()) |b| {
                    reached[a][b] = reached[a][b] or (reached[a][via] and reached[via][b]);
                };
            }
            try line(calculation.out, "{s} {f}>{f} {d}-{d}", .{ if (skip) "skip" else "lock", tally.election.names[x], tally.election.names[y], tally.pairwise[x][y], tally.pairwise[y][x] });
        }
        return calculation.finish(calculation.dominanceOrder(locked));
    }
    fn kemeny(calculation: Calculation) Error!Outcome {
        const tally = calculation.tally;
        var search: KemenySearch = .{ .tally = tally, .candidates = tally.priorityOrder(tally.field) };
        search.visit(0);
        var first_count: usize = 0;
        for (search.firsts) |present| if (present) {
            first_count += 1;
        };
        try line(calculation.out, "score: {d}", .{search.best});
        try line(calculation.out, "optimal: {d}", .{search.optimal});
        try line(calculation.out, "ranking: {f}", .{tally.ranking(search.order)});
        return calculation.finish(.{ .standings = search.order, .tie = first_count > 1 });
    }
    fn stv(calculation: Calculation, seats: usize) Error!Outcome {
        const tally = calculation.tally;
        const per_vote = try calculation.gpa.alloc(i64, tally.groups.len);
        const owners = try calculation.gpa.alloc(?usize, tally.groups.len);
        var nonblank: i64 = 0;
        for (tally.groups, 0..) |group, i| {
            per_vote[i] = if (group.ranking.len == 0) 0 else 100;
            if (group.ranking.len > 0) nonblank += group.votes;
        }
        const quota = @divTrunc(100 * nonblank, @as(i64, @intCast(seats + 1))) + 1;
        try line(calculation.out, "quota: {f}", .{Amount{ .value = quota }});
        var remaining = tally.field;
        var elected: Sequence = .{};
        var history: [7]Scores = undefined;
        var rounds: usize = 0;
        while (true) {
            var current = zero_scores;
            var exhausted: i64 = 0;
            @memset(owners, null);
            for (tally.groups, 0..) |group, i| {
                if (group.ranking.len == 0) continue;
                for (group.ranking.list()) |candidate| if (remaining.index(candidate) != null) {
                    owners[i] = candidate;
                    break;
                };
                const value = group.votes * per_vote[i];
                if (owners[i]) |candidate| current[candidate] += value else exhausted += value;
            }
            var values = tally.values(remaining, current);
            values.amounts = true;
            try calculation.out.print("round {d}: {f}; exhausted {f}", .{ rounds + 1, values, Amount{ .value = exhausted } });
            const order = tally.order(remaining, current, true);
            if (remaining.len == seats - elected.len) {
                elected.extend(order);
                try line(calculation.out, "; elected {f}", .{tally.names(order)});
                break;
            }
            const first = order.items[0];
            if (current[first] >= quota) {
                const surplus = current[first] - quota;
                elected.append(first);
                remaining.remove(first);
                for (owners, 0..) |candidate, i| if (candidate == first) {
                    per_vote[i] = @divTrunc(per_vote[i] * surplus, current[first]);
                };
                try line(calculation.out, "; elected {f} (surplus {f})", .{ tally.election.names[first], Amount{ .value = surplus } });
            } else {
                const selection = tally.eliminate(remaining, current, history[0..rounds]);
                remaining.remove(selection.candidate);
                try line(calculation.out, "; excluded {f}{s}", .{ tally.election.names[selection.candidate], tieText(selection.tie) });
            }
            history[rounds] = current;
            rounds += 1;
            if (elected.len == seats) break;
        }
        try line(calculation.out, "elected: {f}", .{tally.names(elected)});
        return .{};
    }
    fn run(calculation: Calculation, method: MethodSpec) Error!Outcome {
        const tally = calculation.tally;
        return switch (method.kind) {
            .PLURALITY => calculation.scored(tally.scores(tally.field, .first), "votes", true),
            .RUNOFF => calculation.runoff(),
            .IRV => calculation.instantRunoff(false),
            .COOMBS => calculation.instantRunoff(true),
            .BUCKLIN => calculation.bucklin(),
            .BORDA => calculation.scored(tally.scores(tally.field, .borda), "scores", true),
            .BALDWIN => calculation.bordaElimination(false),
            .NANSON => calculation.bordaElimination(true),
            .BLACK => calculation.black(),
            .VETO => calculation.scored(tally.scores(tally.field, .last), "vetoes", false),
            .CONDORCET => calculation.condorcetReport(),
            .COPELAND => calculation.copeland(),
            .MINIMAX => calculation.minimax(method.minimax),
            .SCHULZE => calculation.schulze(),
            .RANKEDPAIRS => calculation.rankedPairs(),
            .KEMENY => calculation.kemeny(),
            .APPROVAL => calculation.scored(tally.approval(method.parameter), "approvals", true),
            .STV => calculation.stv(method.parameter),
        };
    }
};

const KemenySearch = struct {
    tally: *const Tally,
    candidates: Sequence,
    used: [7]bool = @splat(false),
    path: Sequence = .{},
    order: Sequence = .{},
    best: i64 = -1,
    optimal: usize = 0,
    firsts: [7]bool = @splat(false),
    fn visit(search: *KemenySearch, score: i64) void {
        if (search.path.len == search.candidates.len) {
            if (score > search.best) {
                search.best = score;
                search.optimal = 0;
                search.firsts = @splat(false);
                search.order = search.path;
            }
            if (score == search.best) {
                search.optimal += 1;
                search.firsts[search.path.items[0]] = true;
            }
            return;
        }
        for (search.candidates.list()) |next| {
            if (search.used[next]) continue;
            var additional: i64 = 0;
            for (search.path.list()) |previous| additional += search.tally.pairwise[previous][next];
            search.path.append(next);
            search.used[next] = true;
            search.visit(score + additional);
            search.used[next] = false;
            search.path.len -= 1;
        }
    }
};

const State = struct { election: ?Election = null, count: usize = 0 };
const Session = struct {
    gpa: Allocator,
    storage: Allocator,
    state: *State,
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, fmt, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn candidate(session: *Session, election: *const Election, name: []const u8) Error!usize {
        if (election.find(name)) |index| return index;
        return session.fail("unknown candidate {s}", .{name});
    }
    fn appendName(session: *Session, election: *const Election, sequence: *Sequence, name: []const u8) Error!void {
        const index = try session.candidate(election, name);
        if (sequence.index(index) != null) return session.fail("duplicate candidate {s}", .{name});
        sequence.append(index);
    }
    fn checkedNames(session: *Session, election: *const Election, names: []const []const u8) Error!Sequence {
        var result: Sequence = .{};
        for (names) |name| try session.appendName(election, &result, name);
        return result;
    }
    fn create(session: *Session, names: []const []const u8) Error!void {
        if (names.len < 2) return session.fail("too few candidates", .{});
        var election: Election = .{ .number = session.state.count + 1 };
        for (names) |name| {
            if (election.find(name) != null) return session.fail("duplicate candidate {s}", .{name});
            election.names[election.count] = Name.init(name);
            election.tie_order.append(election.count);
            election.count += 1;
        }
        const Context = struct {
            fn less(value: *const Election, a: usize, b: usize) bool {
                return std.mem.order(u8, value.names[a].text(), value.names[b].text()) == .lt;
            }
        };
        std.sort.heap(usize, election.tie_order.items[0..election.tie_order.len], @as(*const Election, &election), Context.less);
        session.state.election = election;
        session.state.count += 1;
        try line(session.out, "election {d}: {d} candidates", .{ election.number, election.count });
    }
    fn status(session: *Session, election: *const Election) Error!void {
        var withdrawn: Sequence = .{};
        for (0..election.count) |i| if (election.withdrawn[i]) withdrawn.append(i);
        try line(session.out, "election {d}", .{election.number});
        try line(session.out, "active: {f}", .{NamedList{ .election = election, .candidates = election.active() }});
        if (withdrawn.len == 0) try session.out.writeAll("withdrawn: none\n") else try line(session.out, "withdrawn: {f}", .{NamedList{ .election = election, .candidates = withdrawn }});
        try line(session.out, "tiebreak: {f}", .{NamedList{ .election = election, .candidates = election.tie_order }});
        try line(session.out, "ballots: {d} in {d} entries", .{ election.total(), election.entries.items.len });
    }
    fn ballotsReport(session: *Session, tally: *const Tally) Error!void {
        const Summary = struct {
            text: []const u8,
            votes: i64,
            fn less(_: void, a: @This(), b: @This()) bool {
                return if (a.votes != b.votes) a.votes > b.votes else std.mem.order(u8, a.text, b.text) == .lt;
            }
        };
        var summaries: std.ArrayList(Summary) = .empty;
        var indices: std.AutoHashMapUnmanaged(u32, usize) = .empty;
        var blank: i64 = 0;
        for (tally.groups) |group| {
            var key: u32 = 1;
            for (group.ranking.list()) |index| key = key * 8 + @as(u32, @intCast(index + 1));
            if (group.ranking.len == 0) blank += group.votes;
            if (indices.get(key)) |index| {
                summaries.items[index].votes += group.votes;
            } else {
                var notation: Writer.Allocating = .init(session.gpa);
                defer notation.deinit();
                if (group.ranking.len == 0) try notation.writer.writeByte('-') else try notation.writer.print("{f}", .{NamedList{ .election = tally.election, .candidates = group.ranking, .separator = ">" }});
                try indices.put(session.gpa, key, summaries.items.len);
                try summaries.append(session.gpa, .{ .text = try notation.toOwnedSlice(), .votes = group.votes });
            }
        }
        std.sort.heap(Summary, summaries.items, {}, Summary.less);
        try line(session.out, "total {d}, blank {d}, distinct {d}", .{ tally.total, blank, summaries.items.len });
        for (summaries.items) |summary| try line(session.out, "{d} {s}", .{ summary.votes, summary.text });
    }
    fn profile(session: *Session, tally: *const Tally) Error!void {
        for (tally.field.list()) |index| {
            var positions = zero_scores;
            var unranked: i64 = 0;
            for (tally.groups) |group| {
                if (group.ranking.index(index)) |place| positions[place] += group.votes else unranked += group.votes;
            }
            try session.out.print("{f}:", .{tally.election.names[index]});
            for (positions[0..tally.field.len]) |count| try session.out.print(" {d}", .{count});
            try line(session.out, " unranked {d}", .{unranked});
        }
    }
    fn compare(session: *Session, tally: *const Tally, words: []const []const u8) Error!void {
        const election = tally.election;
        const first = try session.candidate(election, words[1]);
        if (election.withdrawn[first]) return session.fail("withdrawn candidate {s}", .{words[1]});
        const second = try session.candidate(election, words[2]);
        if (election.withdrawn[second]) return session.fail("withdrawn candidate {s}", .{words[2]});
        if (first == second) return session.fail("same candidate", .{});
        const forward = tally.pairwise[first][second];
        const backward = tally.pairwise[second][first];
        try line(session.out, "{f} {d}, {f} {d}, neither {d}", .{ election.names[first], forward, election.names[second], backward, tally.total - forward - backward });
        var methods: [2][15]usize = undefined;
        var counts: [2]usize = @splat(0);
        for (summary_methods, 0..) |method, index| {
            const result = try tally.run(session.gpa, method);
            const side: usize = if (result.standings.index(first).? < result.standings.index(second).?) 0 else 1;
            methods[side][counts[side]] = index;
            counts[side] += 1;
        }
        for ([_]usize{ first, second }, 0..) |index, side| {
            try session.out.print("{f} ahead: ", .{election.names[index]});
            if (counts[side] == 0) try session.out.writeAll("none");
            for (methods[side][0..counts[side]], 0..) |method, i| {
                if (i > 0) try session.out.writeAll(", ");
                try session.out.print("{f}", .{summary_methods[method]});
            }
            try session.out.writeByte('\n');
        }
    }
    fn execute(session: *Session, text: []const u8) Error!void {
        var words: [12][]const u8 = undefined;
        var count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, text, ' ');
        while (tokens.next()) |word| {
            words[count] = word;
            count += 1;
        }
        const w = words[0..count];
        const command = w[0];
        if (equal(command, "CANDIDATES")) return session.create(w[1..]);
        const election = if (session.state.election) |*value| value else return session.fail("no election", .{});
        if (equal(command, "BALLOT")) {
            var ranking: Sequence = .{};
            if (!equal(w[2], "-")) {
                var names = std.mem.tokenizeScalar(u8, w[2], '>');
                while (names.next()) |name| try session.appendName(election, &ranking, name);
            }
            const entry = try session.storage.alloc(Ballot, 1);
            entry[0] = .{ .votes = @intCast(integer(w[1])), .ranking = ranking };
            try election.entries.append(session.storage, entry);
            return;
        }
        if (equal(command, "RANDOM")) {
            const entry = try session.storage.alloc(Ballot, integer(w[1]));
            var state: u64 = @intCast(integer(w[2]));
            for (entry) |*group| {
                var ranking = election.active();
                var i = ranking.len - 1;
                while (i > 0) : (i -= 1) {
                    state = 48271 * state % 2147483647;
                    const j: usize = @intCast(state % @as(u64, @intCast(i + 1)));
                    if (i != j) std.mem.swap(usize, &ranking.items[i], &ranking.items[j]);
                }
                state = 48271 * state % 2147483647;
                ranking.len = @as(usize, @intCast(state % @as(u64, @intCast(ranking.len)))) + 1;
                group.* = .{ .votes = 1, .ranking = ranking };
            }
            try election.entries.append(session.storage, entry);
            return;
        }
        if (equal(command, "UNDO")) {
            if (election.entries.items.len == 0) return session.fail("nothing to undo", .{});
            _ = election.entries.pop();
            return;
        }
        if (equal(command, "WITHDRAW") or equal(command, "RESTORE")) {
            const index = try session.candidate(election, w[1]);
            if (equal(command, "WITHDRAW")) {
                if (election.withdrawn[index]) return session.fail("already withdrawn {s}", .{w[1]});
                if (election.active().len <= 2) return session.fail("too few candidates", .{});
                election.withdrawn[index] = true;
            } else {
                if (!election.withdrawn[index]) return session.fail("not withdrawn {s}", .{w[1]});
                election.withdrawn[index] = false;
            }
            return;
        }
        if (equal(command, "TIEBREAK")) {
            const order = try session.checkedNames(election, w[1..]);
            if (order.len != election.count) return session.fail("incomplete tiebreak", .{});
            election.tie_order = order;
            return;
        }
        if (equal(command, "STATUS")) {
            try line(session.out, "[{s}]", .{text});
            return session.status(election);
        }
        if (election.entries.items.len == 0) return session.fail("no ballots", .{});
        const tally = try Tally.init(session.gpa, election, election.active());
        try line(session.out, "[{s}]", .{text});
        if (equal(command, "RANKING") or equal(command, "SPOILERS")) {
            const method = MethodSpec.parse(w[1..]);
            if (!method.rankable()) return session.fail("not rankable", .{});
            if (equal(command, "SPOILERS") and tally.field.len < 3) return session.fail("too few candidates", .{});
            const result = try tally.run(session.gpa, method);
            if (equal(command, "RANKING")) return line(session.out, "{f}", .{tally.ranking(result.standings)});
            const winner = result.standings.items[0];
            try line(session.out, "winner: {f}", .{election.names[winner]});
            for (tally.field.list()) |excluded| {
                if (excluded == winner) continue;
                var field = tally.field;
                field.remove(excluded);
                const trial = try Tally.init(session.gpa, election, field);
                const other = try trial.run(session.gpa, method);
                const changed = other.standings.items[0];
                try line(session.out, "without {f}: {f}{s}", .{ election.names[excluded], election.names[changed], if (changed != winner) " (changed)" else "" });
            }
        } else if (equal(command, "COMPARE")) {
            try session.compare(&tally, w);
        } else if (equal(command, "SUMMARY")) {
            var wins = zero_scores;
            for (summary_methods) |method| {
                const result = try tally.run(session.gpa, method);
                const winner = result.standings.items[0];
                wins[winner] += 1;
                try line(session.out, "{f}: {f}", .{ method, election.names[winner] });
            }
            try line(session.out, "wins: {f}", .{tally.values(tally.field, wins)});
        } else if (equal(command, "BALLOTS")) {
            try session.ballotsReport(&tally);
        } else if (equal(command, "PROFILE")) {
            try session.profile(&tally);
        } else if (equal(command, "PAIRWISE")) {
            try tally.pairLines(session.out, tally.pairwise);
        } else {
            const method = if (equal(command, "EXHAUSTED")) MethodSpec{ .kind = .IRV } else MethodSpec.parse(w);
            if (method.kind == .STV and method.parameter >= tally.field.len) return session.fail("too many seats", .{});
            const result = try tally.run(session.gpa, method);
            try session.out.writeAll(if (equal(command, "EXHAUSTED")) result.exhaustion else result.output);
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
    var state: State = .{};
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
        var session: Session = .{ .gpa = gpa, .storage = storage.allocator(), .state = &state, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
