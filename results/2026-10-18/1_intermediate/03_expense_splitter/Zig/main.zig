const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn less(a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn amount(text: []const u8) i64 {
    const dot = std.mem.findScalar(u8, text, '.').?;
    return integer(text[0..dot]) * 100 + integer(text[dot + 1..]);
}
fn money(gpa: Allocator, value: i64) Allocator.Error![]const u8 {
    const v: u64 = @intCast(value);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>2}", .{ v / 100, v % 100 });
}
fn signedMoney(gpa: Allocator, value: i64) Allocator.Error![]const u8 {
    if (value == 0) return "0.00";
    return std.fmt.allocPrint(gpa, "{s}{s}", .{ @as([]const u8, if (value > 0) "+" else "-"),
        try money(gpa, if (value < 0) -value else value) });
}
fn percentage(gpa: Allocator, part: i64, whole: i64) Allocator.Error![]const u8 {
    return std.fmt.allocPrint(gpa, "{s}%", .{try money(gpa, @divFloor(part * 10000, whole))});
}
fn rateText(gpa: Allocator, value: i64) Allocator.Error![]const u8 {
    const v: u64 = @intCast(value);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>4}", .{ v / 10000, v % 10000 });
}
fn tokens(gpa: Allocator, text: []const u8, delimiter: u8) Allocator.Error![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |part| try result.append(gpa, part);
    return result.items;
}
fn distribute(gpa: Allocator, total: i64, weights: []const i64) Allocator.Error![]i64 {
    var sum: i64 = 0;
    for (weights) |w| sum += w;
    const result = try gpa.alloc(i64, weights.len);
    const order = try gpa.alloc(usize, weights.len);
    var allotted: i64 = 0;
    for (weights, 0..) |w, i| {
        result[i] = @divFloor(total * w, sum);
        allotted += result[i];
        order[i] = i;
    }
    for (1..weights.len) |i| {
        const entry = order[i];
        var j = i;
        while (j > 0 and @mod(total * weights[entry], sum) > @mod(total * weights[order[j - 1]], sum)) {
            order[j] = order[j - 1];
            j -= 1;
        }
        order[j] = entry;
    }
    for (0..@as(usize, @intCast(total - allotted))) |i| result[order[i]] += 1;
    return result;
}
fn equalParts(gpa: Allocator, total: i64, count: usize) Allocator.Error![]i64 {
    const result = try gpa.alloc(i64, count);
    const k: i64 = @intCast(count);
    for (result, 0..) |*value, i| value.* = @divFloor(total, k) + @as(i64, if (i < @as(usize, @intCast(@mod(total, k)))) 1 else 0);
    return result;
}
const Member = struct { name: []const u8, active: bool = true, day: i64 };
const Currency = struct { code: []const u8, rate: i64 };
const Budget = struct { category: []const u8, value: i64 };
const Entry = struct { member: usize, value: i64 };
const Mode = enum { EQUAL, EXACT, PERCENT, SHARES, ADJUST };
const Expense = struct {
    id: []const u8, day: i64, serial: usize,
    original: i64, currency: []const u8, category: []const u8, mode: Mode,
    payers: []Entry, participants: []Entry,
    total: i64, contributions: []i64, shares: []i64,
    interval: i64 = 0, next_day: i64 = 0, copies: usize = 0,
    fn includes(self: Expense, member: usize) bool {
        for (self.payers) |e| { if (e.member == member) return true; }
        for (self.participants) |e| { if (e.member == member) return true; }
        return false;
    }
    fn net(self: Expense, member: usize) i64 {
        var result: i64 = 0;
        for (self.payers, 0..) |e, i| { if (e.member == member) result += self.contributions[i]; }
        for (self.participants, 0..) |e, i| { if (e.member == member) result -= self.shares[i]; }
        return result;
    }
};
const Settlement = struct { from: usize, to: usize, original: i64, currency: []const u8, total: i64, day: i64, serial: usize };
const Transfer = struct { from: usize, to: usize, value: i64 };
const Spec = struct { value: i64, currency: []const u8 };

const Ledger = struct {
    gpa: Allocator,
    day: i64 = 1,
    serial: usize = 0,
    members: std.ArrayList(Member) = .empty,
    rates: std.ArrayList(Currency) = .empty,
    budgets: std.ArrayList(Budget) = .empty,
    used: std.ArrayList([]const u8) = .empty,
    expenses: std.ArrayList(Expense) = .empty,
    settlements: std.ArrayList(Settlement) = .empty,
    error_buffer: [8192]u8 = undefined,
    error_len: usize = 0,
    fn fail(self: *Ledger, message: []const u8) error{BadCommand} {
        @memcpy(self.error_buffer[0..message.len], message);
        self.error_len = message.len;
        return error.BadCommand;
    }
    fn failFmt(self: *Ledger, comptime fmt: []const u8, args: anytype) error{BadCommand} {
        const text = std.fmt.bufPrint(&self.error_buffer, fmt, args) catch unreachable;
        self.error_len = text.len;
        return error.BadCommand;
    }
    fn memberIndex(self: *const Ledger, name: []const u8) ?usize {
        for (self.members.items, 0..) |m, i| { if (equal(m.name, name)) return i; }
        return null;
    }
    fn registered(self: *Ledger, name: []const u8) Error!usize {
        return self.memberIndex(name) orelse return self.failFmt("unknown member {s}", .{name});
    }
    fn active(self: *Ledger, name: []const u8) Error!usize {
        const i = try self.registered(name);
        if (!self.members.items[i].active) return self.failFmt("inactive member {s}", .{name});
        return i;
    }
    fn names(self: *const Ledger, active_only: bool) Allocator.Error![]usize {
        var result: std.ArrayList(usize) = .empty;
        for (self.members.items, 0..) |m, i| {
            if (!active_only or m.active) try result.append(self.gpa, i);
        }
        self.sortNames(result.items);
        return result.items;
    }
    fn sortNames(self: *const Ledger, values: []usize) void {
        for (1..@max(1, values.len)) |i| {
            const entry = values[i];
            var j = i;
            while (j > 0 and less(self.members.items[entry].name, self.members.items[values[j - 1]].name)) {
                values[j] = values[j - 1];
                j -= 1;
            }
            values[j] = entry;
        }
    }
    fn expenseIndex(self: *Ledger, id: []const u8) Error!usize {
        for (self.expenses.items, 0..) |e, i| { if (equal(e.id, id)) return i; }
        return self.failFmt("unknown expense {s}", .{id});
    }
    fn unfrozen(self: *Ledger, e: Expense) Error!void {
        for (e.payers) |p| {
            if (!self.members.items[p.member].active) return self.failFmt("inactive member {s}", .{self.members.items[p.member].name});
        }
        for (e.participants) |p| {
            if (!self.members.items[p.member].active) return self.failFmt("inactive member {s}", .{self.members.items[p.member].name});
        }
    }
    fn rateIndex(self: *const Ledger, code: []const u8) ?usize {
        for (self.rates.items, 0..) |r, i| { if (equal(r.code, code)) return i; }
        return null;
    }
    fn spec(self: *Ledger, text: []const u8) Error!Spec {
        if (std.mem.findScalar(u8, text, '@')) |at| {
            const code = text[at + 1..];
            if (self.rateIndex(code) == null) return self.failFmt("unknown currency {s}", .{code});
            return .{ .value = amount(text[0..at]), .currency = code };
        }
        return .{ .value = amount(text), .currency = "" };
    }
    fn convert(self: *const Ledger, value: i64, currency: []const u8) i64 {
        return if (currency.len == 0) value else @divFloor(value * self.rates.items[self.rateIndex(currency).?].rate + 5000, 10000);
    }
    fn note(self: *const Ledger, original: i64, currency: []const u8) Allocator.Error![]const u8 {
        if (currency.len == 0) return "";
        return std.fmt.allocPrint(self.gpa, " [{s} {s}]", .{ try money(self.gpa, original), currency });
    }
    fn portions(self: *const Ledger, e: Expense) Allocator.Error![]i64 {
        const values = try self.gpa.alloc(i64, e.participants.len);
        var sum: i64 = 0;
        for (e.participants, 0..) |p, i| { values[i] = p.value; sum += p.value; }
        return switch (e.mode) {
            .EQUAL => equalParts(self.gpa, e.original, values.len),
            .EXACT => values,
            .PERCENT, .SHARES => distribute(self.gpa, e.original, values),
            .ADJUST => blk: {
                const base = try equalParts(self.gpa, e.original - sum, values.len);
                for (values, base) |*v, b| v.* += b;
                break :blk values;
            },
        };
    }
    fn compute(self: *const Ledger, e: *Expense) Allocator.Error!void {
        e.total = self.convert(e.original, e.currency);
        e.shares = try distribute(self.gpa, e.total, try self.portions(e.*));
        const weights = try self.gpa.alloc(i64, e.payers.len);
        for (e.payers, 0..) |p, i| weights[i] = p.value;
        e.contributions = try distribute(self.gpa, e.total, weights);
    }
    fn build(self: *Ledger, a: []const []const u8, old: ?Expense) Error!Expense {
        const payer = try self.active(a[2]);
        const parsed = try self.spec(a[3]);
        const total = self.convert(parsed.value, parsed.currency);
        if (parsed.value == 0 or total == 0) return self.fail("invalid amount");
        const mode = std.meta.stringToEnum(Mode, a[5]).?;
        var participants: std.ArrayList(Entry) = .empty;
        if (mode == .EQUAL and equal(a[6], "ALL")) {
            for (try self.names(true)) |member| try participants.append(self.gpa, .{ .member = member, .value = 0 });
        } else {
            for (a[6..]) |token| {
            const pair = try tokens(self.gpa, token, ':');
            const member = try self.active(pair[0]);
            for (participants.items) |p| {
                if (p.member == member) return self.failFmt("duplicate member {s}", .{pair[0]});
            }
            const value = if (pair.len == 1) 0 else if (mode == .PERCENT or mode == .SHARES) integer(pair[1]) else amount(pair[1]);
            try participants.append(self.gpa, .{ .member = member, .value = value });
            }
        }
        var sum: i64 = 0;
        for (participants.items) |p| sum += p.value;
        if ((mode == .EXACT and sum != parsed.value) or (mode == .PERCENT and sum != 10000) or
            (mode == .SHARES and sum < 1) or (mode == .ADJUST and sum > parsed.value)) return self.fail("splits do not add up");
        const payers = try self.gpa.alloc(Entry, 1);
        payers[0] = .{ .member = payer, .value = parsed.value };
        var e = Expense{ .id = a[1], .day = if (old) |v| v.day else self.day,
            .serial = if (old) |v| v.serial else self.serial + 1,
            .original = parsed.value, .currency = parsed.currency, .category = a[4], .mode = mode,
            .payers = payers, .participants = participants.items, .total = total, .contributions = &.{}, .shares = &.{} };
        if (old) |v| { e.interval = v.interval; e.next_day = v.next_day; e.copies = v.copies; }
        try self.compute(&e);
        return e;
    }
    fn balances(self: *const Ledger) Allocator.Error![]i64 {
        const result = try self.gpa.alloc(i64, self.members.items.len);
        @memset(result, 0);
        for (self.expenses.items) |e| {
            for (result, 0..) |*v, i| v.* += e.net(i);
        }
        for (self.settlements.items) |s| { result[s.from] += s.total; result[s.to] -= s.total; }
        return result;
    }
    fn debts(self: *const Ledger) Allocator.Error![][]i64 {
        const ns = try self.names(false);
        const count = self.members.items.len;
        const gross = try self.gpa.alloc([]i64, count);
        const result = try self.gpa.alloc([]i64, count);
        for (0..count) |i| { gross[i] = try self.gpa.alloc(i64, count); @memset(gross[i], 0); result[i] = try self.gpa.alloc(i64, count); }
        for (self.expenses.items) |e| {
            const net = try self.gpa.alloc(i64, count);
            var borrowers: std.ArrayList(usize) = .empty;
            var lenders: std.ArrayList(usize) = .empty;
            for (ns) |member| {
                net[member] = e.net(member);
                if (net[member] < 0) try borrowers.append(self.gpa, member);
                if (net[member] > 0) try lenders.append(self.gpa, member);
            }
            var b: usize = 0;
            var l: usize = 0;
            while (b < borrowers.items.len and l < lenders.items.len) {
                const x = borrowers.items[b];
                const y = lenders.items[l];
                const transfer = @min(-net[x], net[y]);
                gross[x][y] += transfer;
                net[x] += transfer;
                net[y] -= transfer;
                if (net[x] == 0) b += 1;
                if (net[y] == 0) l += 1;
            }
        }
        for (self.settlements.items) |s| gross[s.from][s.to] -= s.total;
        for (0..count) |i| {
            for (0..count) |j| result[i][j] = gross[i][j] - gross[j][i];
        }
        return result;
    }
    fn spent(self: *const Ledger, category: []const u8) i64 {
        var result: i64 = 0;
        for (self.expenses.items) |e| { if (equal(e.category, category)) result += e.total; }
        return result;
    }
    fn warning(self: *const Ledger, out: *std.Io.Writer, category: []const u8) Error!void {
        for (self.budgets.items) |b| {
            if (equal(b.category, category) and self.spent(category) > b.value)
                try out.print("  WARNING {s} over budget by {s}\n", .{ category, try money(self.gpa, self.spent(category) - b.value) });
        }
    }
    fn chronological(self: *const Ledger) Allocator.Error![]usize {
        const result = try self.gpa.alloc(usize, self.expenses.items.len);
        for (result, 0..) |*v, i| v.* = i;
        for (1..@max(1, result.len)) |i| {
            const entry = result[i];
            const a = self.expenses.items[entry];
            var j = i;
            while (j > 0) {
                const b = self.expenses.items[result[j - 1]];
                if (a.day > b.day or (a.day == b.day and a.serial >= b.serial)) break;
                result[j] = result[j - 1]; j -= 1;
            }
            result[j] = entry;
        }
        return result;
    }
    fn greedy(self: *const Ledger, ns: []const usize, original: []const i64) Allocator.Error![]Transfer {
        const balance = try self.gpa.dupe(i64, original);
        var result: std.ArrayList(Transfer) = .empty;
        if (ns.len == 0) return result.items;
        while (true) {
            var sender = ns[0];
            var receiver = ns[0];
            for (ns) |n| {
                if (balance[n] < balance[sender]) sender = n;
                if (balance[n] > balance[receiver]) receiver = n;
            }
            if (balance[sender] == 0 and balance[receiver] == 0) break;
            const value = @min(-balance[sender], balance[receiver]);
            try result.append(self.gpa, .{ .from = sender, .to = receiver, .value = value });
            balance[sender] += value; balance[receiver] -= value;
        }
        return result.items;
    }
    fn printTransfer(self: *const Ledger, out: *std.Io.Writer, transfer: Transfer, indent: []const u8) Error!void {
        try out.print("{s}{s} -> {s} {s}\n", .{ indent, self.members.items[transfer.from].name,
            self.members.items[transfer.to].name, try money(self.gpa, transfer.value) });
    }
    fn execute(self: *Ledger, line: []const u8, out: *std.Io.Writer) Error!void {
        const a = try tokens(self.gpa, line, ' ');
        const op = a[0];
        if (equal(op, "DAY")) {
            const target = integer(a[1]);
            if (target <= self.day) return self.failFmt("invalid day {s}", .{a[1]});
            try out.print("DAY {d}\n", .{target});
            while (true) {
                var chosen: ?usize = null;
                for (self.expenses.items, 0..) |e, i| {
                    if (e.interval == 0 or e.next_day > target) continue;
                    if (chosen == null or e.next_day < self.expenses.items[chosen.?].next_day or
                        (e.next_day == self.expenses.items[chosen.?].next_day and e.serial < self.expenses.items[chosen.?].serial)) chosen = i;
                }
                const index = chosen orelse break;
                const template = self.expenses.items[index];
                var active_members = true;
                for (template.payers) |p| { if (!self.members.items[p.member].active) active_members = false; }
                for (template.participants) |p| { if (!self.members.items[p.member].active) active_members = false; }
                if (!active_members or self.convert(template.original, template.currency) == 0) {
                    self.expenses.items[index].interval = 0;
                    try out.print("  CANCEL {s}\n", .{template.id});
                    continue;
                }
                self.expenses.items[index].copies += 1;
                self.expenses.items[index].next_day += template.interval;
                self.serial += 1;
                var copy = template;
                copy.id = try std.fmt.allocPrint(self.gpa, "{s}#{d}", .{ template.id, self.expenses.items[index].copies + 1 });
                copy.day = template.next_day;
                copy.serial = self.serial;
                copy.interval = 0; copy.next_day = 0; copy.copies = 0;
                try self.compute(&copy);
                // No pointer into expenses is retained across the possible reallocation.
                try self.expenses.append(self.gpa, copy);
                try self.used.append(self.gpa, copy.id);
                try out.print("  RECUR {s} {s}\n", .{ copy.id, try money(self.gpa, copy.total) });
                try self.warning(out, copy.category);
            }
            self.day = target;
        } else if (equal(op, "MEMBER")) {
            if (self.memberIndex(a[1])) |i| {
                if (self.members.items[i].active) return self.failFmt("duplicate member {s}", .{a[1]});
                self.members.items[i].active = true;
                self.members.items[i].day = self.day;
                try out.print("MEMBER {s} rejoined\n", .{a[1]});
            } else {
                try self.members.append(self.gpa, .{ .name = a[1], .day = self.day });
                try out.print("MEMBER {s} joined\n", .{a[1]});
            }
        } else if (equal(op, "LEAVE")) {
            const member = try self.active(a[1]);
            const balance = try self.balances();
            if (balance[member] != 0) return self.failFmt("member has a balance {s}", .{a[1]});
            self.members.items[member].active = false;
            self.members.items[member].day = self.day;
            try out.print("LEAVE {s}\n", .{a[1]});
        } else if (equal(op, "CURRENCY")) {
            const value = integer(a[2]);
            try out.print("CURRENCY {s} {s}", .{ a[1], try rateText(self.gpa, value) });
            if (self.rateIndex(a[1])) |i| {
                try out.print(" was {s}", .{try rateText(self.gpa, self.rates.items[i].rate)});
                self.rates.items[i].rate = value;
            } else try self.rates.append(self.gpa, .{ .code = a[1], .rate = value });
            try out.writeByte('\n');
        } else if (equal(op, "EXPENSE") or equal(op, "EDIT")) {
            var old_index: ?usize = null;
            if (equal(op, "EXPENSE")) {
                for (self.used.items) |id| { if (equal(id, a[1])) return self.failFmt("duplicate id {s}", .{a[1]}); }
            } else { old_index = try self.expenseIndex(a[1]); try self.unfrozen(self.expenses.items[old_index.?]); }
            const e = try self.build(a, if (old_index) |i| self.expenses.items[i] else null);
            if (old_index) |i| self.expenses.items[i] = e else {
                self.serial += 1;
                try self.expenses.append(self.gpa, e);
                try self.used.append(self.gpa, e.id);
            }
            try out.print("{s} {s} {s}{s} = ", .{ op, e.id, try money(self.gpa, e.total), try self.note(e.original, e.currency) });
            for (e.participants, 0..) |p, i| {
                if (i > 0) try out.writeAll(" + ");
                try out.print("{s} {s}", .{ self.members.items[p.member].name, try money(self.gpa, e.shares[i]) });
            }
            try out.writeByte('\n');
            try self.warning(out, e.category);
        } else if (equal(op, "PAYERS")) {
            const index = try self.expenseIndex(a[1]);
            const original = self.expenses.items[index];
            try self.unfrozen(original);
            var payers: std.ArrayList(Entry) = .empty;
            var sum: i64 = 0;
            for (a[2..]) |token| {
                const pair = try tokens(self.gpa, token, ':');
                const member = try self.active(pair[0]);
                for (payers.items) |p| { if (p.member == member) return self.failFmt("duplicate member {s}", .{pair[0]}); }
                const value = amount(pair[1]); sum += value;
                try payers.append(self.gpa, .{ .member = member, .value = value });
            }
            if (sum != original.original) return self.fail("payers do not add up");
            const weights = try self.gpa.alloc(i64, payers.items.len);
            for (payers.items, 0..) |p, i| weights[i] = p.value;
            const contributions = try distribute(self.gpa, original.total, weights);
            self.expenses.items[index].payers = payers.items;
            self.expenses.items[index].contributions = contributions;
            try out.print("PAYERS {s} {s}{s} = ", .{ original.id, try money(self.gpa, original.total), try self.note(original.original, original.currency) });
            for (payers.items, 0..) |p, i| {
                if (i > 0) try out.writeAll(" + ");
                try out.print("{s} {s}", .{ self.members.items[p.member].name, try money(self.gpa, contributions[i]) });
            }
            try out.writeByte('\n');
        } else if (equal(op, "DELETE")) {
            const index = try self.expenseIndex(a[1]);
            try self.unfrozen(self.expenses.items[index]);
            _ = self.expenses.orderedRemove(index);
            try out.print("DELETE {s}\n", .{a[1]});
        } else if (equal(op, "RECURRING")) {
            const index = try self.expenseIndex(a[1]);
            const interval = integer(a[2]);
            const e = &self.expenses.items[index];
            e.interval = interval;
            if (interval == 0) try out.print("RECURRING {s} stopped\n", .{e.id}) else {
                e.next_day = self.day + interval;
                try out.print("RECURRING {s} interval {d} next {d}\n", .{ e.id, interval, e.next_day });
            }
        } else if (equal(op, "SETTLE")) {
            const from = try self.active(a[1]);
            const to = try self.active(a[2]);
            if (from == to) return self.failFmt("same member {s}", .{a[1]});
            const parsed = try self.spec(a[3]);
            const total = self.convert(parsed.value, parsed.currency);
            if (parsed.value == 0 or total == 0) return self.fail("invalid amount");
            self.serial += 1;
            try self.settlements.append(self.gpa, .{ .from = from, .to = to, .original = parsed.value,
                .currency = parsed.currency, .total = total, .day = self.day, .serial = self.serial });
            try out.print("SETTLE {s} -> {s} {s}{s}\n", .{ a[1], a[2], try money(self.gpa, total), try self.note(parsed.value, parsed.currency) });
        } else if (equal(op, "BUDGET")) {
            const value = amount(a[2]);
            var index: ?usize = null;
            for (self.budgets.items, 0..) |b, i| { if (equal(b.category, a[1])) index = i; }
            if (value == 0) { if (index) |i| _ = self.budgets.orderedRemove(i); } else if (index) |i|
                self.budgets.items[i].value = value else try self.budgets.append(self.gpa, .{ .category = a[1], .value = value });
            try out.print("BUDGET {s} {s}\n", .{ a[1], if (value == 0) "removed" else try money(self.gpa, value) });
        } else if (equal(op, "BALANCES")) {
            try out.writeAll("BALANCES\n");
            const ns = try self.names(true);
            const balance = try self.balances();
            if (ns.len == 0) try out.writeAll("  (none)\n");
            for (ns) |member| try out.print("  {s} {s}\n", .{ self.members.items[member].name, try signedMoney(self.gpa, balance[member]) });
        } else if (equal(op, "OWES")) {
            const member = try self.registered(a[1]);
            const ns = try self.names(false);
            const matrix = try self.debts();
            try out.print("OWES {s}\n", .{a[1]});
            var count: usize = 0;
            for (ns) |other| {
                const debt = matrix[member][other];
                if (debt == 0) continue;
                count += 1;
                try out.print("  {s} owes {s} {s}\n", .{
                    self.members.items[if (debt > 0) member else other].name,
                    self.members.items[if (debt > 0) other else member].name,
                    try money(self.gpa, if (debt > 0) debt else -debt),
                });
            }
            if (count == 0) try out.writeAll("  (none)\n");
        } else if (equal(op, "HISTORY")) {
            const member = try self.registered(a[1]);
            const Record = struct { day: i64, serial: usize, label: []const u8, change: i64 };
            var records: std.ArrayList(Record) = .empty;
            for (self.expenses.items) |e| {
                if (e.includes(member)) try records.append(self.gpa, .{ .day = e.day, .serial = e.serial, .label = e.id, .change = e.net(member) });
            }
            for (self.settlements.items) |s| {
                if (s.from == member or s.to == member) try records.append(self.gpa, .{ .day = s.day, .serial = s.serial,
                    .label = try std.fmt.allocPrint(self.gpa, "{s}->{s}", .{ self.members.items[s.from].name, self.members.items[s.to].name }),
                    .change = if (s.from == member) s.total else -s.total });
            }
            for (1..@max(1, records.items.len)) |i| {
                const entry = records.items[i];
                var j = i;
                while (j > 0 and (entry.day < records.items[j - 1].day or
                    (entry.day == records.items[j - 1].day and entry.serial < records.items[j - 1].serial))) {
                    records.items[j] = records.items[j - 1]; j -= 1;
                }
                records.items[j] = entry;
            }
            try out.print("HISTORY {s}\n", .{a[1]});
            var running: i64 = 0;
            for (records.items) |r| {
                running += r.change;
                try out.print("  day {d} {s} {s} balance {s}\n", .{ r.day, r.label,
                    try signedMoney(self.gpa, r.change), try signedMoney(self.gpa, running) });
            }
            if (records.items.len == 0) try out.writeAll("  (none)\n");
        } else if (equal(op, "MATRIX")) {
            try out.writeAll("MATRIX\n");
            const ns = try self.names(true);
            if (ns.len == 0) { try out.writeAll("  (none)\n"); return; }
            const matrix = try self.debts();
            var l: usize = 0;
            var w: usize = 0;
            const cells = try self.gpa.alloc([][]const u8, ns.len);
            for (ns, 0..) |member, i| {
                l = @max(l, self.members.items[member].name.len);
                cells[i] = try self.gpa.alloc([]const u8, ns.len);
                for (ns, 0..) |other, j| {
                    cells[i][j] = if (member == other) "-" else try money(self.gpa, @max(0, matrix[member][other]));
                    w = @max(w, cells[i][j].len);
                }
            }
            w = @max(w, l);
            try spaces(out, l);
            for (ns) |member| {
                const name = self.members.items[member].name;
                try spaces(out, 2 + w - name.len); try out.writeAll(name);
            }
            try out.writeByte('\n');
            for (ns, 0..) |member, i| {
                const name = self.members.items[member].name;
                try out.writeAll(name); try spaces(out, l - name.len);
                for (cells[i]) |cell| { try spaces(out, 2 + w - cell.len); try out.writeAll(cell); }
                try out.writeByte('\n');
            }
        } else if (equal(op, "CATEGORY")) {
            try out.writeAll("CATEGORY\n");
            var categories: std.ArrayList([]const u8) = .empty;
            var total: i64 = 0;
            for (self.expenses.items) |e| { try addUnique(self.gpa, &categories, e.category); total += e.total; }
            for (1..@max(1, categories.items.len)) |i| {
                const entry = categories.items[i];
                var j = i;
                while (j > 0 and (self.spent(entry) > self.spent(categories.items[j - 1]) or
                    (self.spent(entry) == self.spent(categories.items[j - 1]) and less(entry, categories.items[j - 1])))) {
                    categories.items[j] = categories.items[j - 1]; j -= 1;
                }
                categories.items[j] = entry;
            }
            for (categories.items) |category| {
                const subtotal = self.spent(category);
                try out.print("  {s} {s} {s}\n", .{ category, try money(self.gpa, subtotal), try percentage(self.gpa, subtotal, total) });
                const shares = try self.gpa.alloc(i64, self.members.items.len);
                @memset(shares, 0);
                for (self.expenses.items) |e| {
                    if (equal(e.category, category)) {
                        for (e.participants, 0..) |p, i| shares[p.member] += e.shares[i];
                    }
                }
                const ns = try self.names(false);
                for (1..@max(1, ns.len)) |i| {
                    const entry = ns[i];
                    var j = i;
                    while (j > 0 and shares[entry] > shares[ns[j - 1]]) { ns[j] = ns[j - 1]; j -= 1; }
                    ns[j] = entry;
                }
                for (ns) |member| {
                    if (shares[member] != 0) try out.print("    {s} {s} {s}\n", .{ self.members.items[member].name,
                        try money(self.gpa, shares[member]), try percentage(self.gpa, shares[member], subtotal) });
                }
            }
            if (categories.items.len == 0) try out.writeAll("  (none)\n");
        } else if (equal(op, "BUDGETS")) {
            try out.writeAll("BUDGETS\n");
            const ordered = try self.gpa.dupe(Budget, self.budgets.items);
            for (1..@max(1, ordered.len)) |i| {
                const entry = ordered[i];
                var j = i;
                while (j > 0 and less(entry.category, ordered[j - 1].category)) { ordered[j] = ordered[j - 1]; j -= 1; }
                ordered[j] = entry;
            }
            for (ordered) |b| {
                const spent_amount = self.spent(b.category);
                try out.print("  {s} spent {s} budget {s} used {s} {s} {s}\n", .{ b.category,
                    try money(self.gpa, spent_amount), try money(self.gpa, b.value), try percentage(self.gpa, spent_amount, b.value),
                    @as([]const u8, if (spent_amount <= b.value) "left" else "over"),
                    try money(self.gpa, if (spent_amount <= b.value) b.value - spent_amount else spent_amount - b.value) });
            }
            if (ordered.len == 0) try out.writeAll("  (none)\n");
        } else if (equal(op, "TOTALS")) {
            try out.writeAll("TOTALS\n");
            for (try self.names(false)) |member| {
                var paid: i64 = 0; var share: i64 = 0; var sent: i64 = 0; var received: i64 = 0;
                for (self.expenses.items) |e| {
                    for (e.payers, 0..) |p, i| { if (p.member == member) paid += e.contributions[i]; }
                    for (e.participants, 0..) |p, i| { if (p.member == member) share += e.shares[i]; }
                }
                for (self.settlements.items) |s| { if (s.from == member) sent += s.total; if (s.to == member) received += s.total; }
                try out.print("  {s} paid {s} share {s} sent {s} received {s}\n", .{ self.members.items[member].name,
                    try money(self.gpa, paid), try money(self.gpa, share), try money(self.gpa, sent), try money(self.gpa, received) });
            }
            var currencies: std.ArrayList([]const u8) = .empty;
            var expense_total: i64 = 0;
            for (self.expenses.items) |e| { if (e.currency.len > 0) try addUnique(self.gpa, &currencies, e.currency); expense_total += e.total; }
            sortStrings(currencies.items);
            for (currencies.items) |code| {
                var count: usize = 0; var original: i64 = 0; var total: i64 = 0;
                for (self.expenses.items) |e| { if (equal(e.currency, code)) { count += 1; original += e.original; total += e.total; } }
                try out.print("  currency {s} expenses {d} amount {s} base {s}\n", .{ code, count, try money(self.gpa, original), try money(self.gpa, total) });
            }
            var settlement_total: i64 = 0;
            for (self.settlements.items) |s| settlement_total += s.total;
            try out.print("  expenses {d} total {s} settlements {d} total {s}\n", .{ self.expenses.items.len,
                try money(self.gpa, expense_total), self.settlements.items.len, try money(self.gpa, settlement_total) });
        } else if (equal(op, "MEMBERS")) {
            try out.writeAll("MEMBERS\n");
            for (try self.names(false)) |member| {
                var count: usize = 0;
                for (self.expenses.items) |e| { if (e.includes(member)) count += 1; }
                const m = self.members.items[member];
                try out.print("  {s} {s} day {d} expenses {d}\n", .{ m.name,
                    @as([]const u8, if (m.active) "active" else "left"), m.day, count });
            }
            if (self.members.items.len == 0) try out.writeAll("  (none)\n");
        } else if (equal(op, "EXPENSES")) {
            const member = if (equal(a[1], "MEMBER")) try self.registered(a[2]) else 0;
            try out.print("{s}\n", .{line});
            var count: usize = 0; var total: i64 = 0;
            for (try self.chronological()) |index| {
                const e = self.expenses.items[index];
                const selected = if (equal(a[1], "ALL")) true else if (equal(a[1], "CATEGORY")) equal(e.category, a[2]) else
                    if (equal(a[1], "MEMBER")) e.includes(member) else e.day >= integer(a[2]) and e.day <= integer(a[3]);
                if (!selected) continue;
                count += 1; total += e.total;
                try out.print("  day {d} {s} {s} {s} by ", .{ e.day, e.id, e.category, try money(self.gpa, e.total) });
                for (e.payers, 0..) |p, i| {
                    if (i > 0) try out.writeByte(',');
                    try out.writeAll(self.members.items[p.member].name);
                }
                try out.writeByte('\n');
            }
            try out.print("  count {d} total {s}\n", .{ count, try money(self.gpa, total) });
        } else if (equal(op, "PERIODS")) {
            const k = integer(a[1]);
            const Group = struct { period: i64, count: usize = 0, total: i64 = 0 };
            var groups: std.ArrayList(Group) = .empty;
            for (try self.chronological()) |index| {
                const e = self.expenses.items[index];
                const period = @divFloor(e.day - 1, k);
                if (groups.items.len == 0 or groups.items[groups.items.len - 1].period != period)
                    try groups.append(self.gpa, .{ .period = period });
                const group = &groups.items[groups.items.len - 1];
                group.count += 1; group.total += e.total;
            }
            try out.print("PERIODS {d}\n", .{k});
            for (groups.items) |group| try out.print("  days {d}-{d} expenses {d} total {s}\n", .{
                group.period * k + 1, group.period * k + k, group.count, try money(self.gpa, group.total) });
            if (groups.items.len == 0) try out.writeAll("  (none)\n");
        } else if (equal(op, "SHOW")) {
            const e = self.expenses.items[try self.expenseIndex(a[1])];
            try out.print("SHOW {s}\n  day {d} category {s} mode {s} total {s}{s}\n", .{
                e.id, e.day, e.category, @tagName(e.mode), try money(self.gpa, e.total), try self.note(e.original, e.currency) });
            for (e.payers, 0..) |p, i| try out.print("  paid {s} {s}\n", .{ self.members.items[p.member].name, try money(self.gpa, e.contributions[i]) });
            var units: i64 = 0;
            for (e.participants) |p| units += p.value;
            for (e.participants, 0..) |p, i| {
                try out.print("  share {s} {s}", .{ self.members.items[p.member].name, try money(self.gpa, e.shares[i]) });
                switch (e.mode) {
                    .EQUAL => {}, .EXACT => try out.print(" {s}", .{try money(self.gpa, p.value)}),
                    .PERCENT => try out.print(" {s}%", .{try money(self.gpa, p.value)}),
                    .SHARES => try out.print(" {d}/{d}", .{ p.value, units }),
                    .ADJUST => try out.print(" +{s}", .{try money(self.gpa, p.value)}),
                }
                try out.writeByte('\n');
            }
            if (e.interval > 0) try out.print("  recurring interval {d} next {d}\n", .{ e.interval, e.next_day });
        } else if (equal(op, "SIMPLIFY")) {
            const balance = try self.balances();
            var ns: std.ArrayList(usize) = .empty;
            for (try self.names(false)) |member| { if (balance[member] != 0) try ns.append(self.gpa, member); }
            if (equal(a[1], "GREEDY")) {
                const transfers = try self.greedy(ns.items, balance);
                try out.print("SIMPLIFY GREEDY transfers {d}\n", .{transfers.len});
                for (transfers) |transfer| try self.printTransfer(out, transfer, "  ");
            } else {
                if (ns.items.len > 12) return self.fail("too many members");
                var optimal = try Optimal.init(self.gpa, ns.items, balance);
                var mask = optimal.sums.len - 1;
                const groups = optimal.solve(mask);
                try out.print("SIMPLIFY OPTIMAL transfers {d} groups {d}\n", .{ ns.items.len - @as(usize, @intCast(groups)), groups });
                while (mask != 0) {
                    const first = lowBit(mask);
                    var chosen: usize = 0;
                    var sub = mask;
                    while (sub > 0) : (sub = (sub - 1) & mask) {
                        if ((sub & first) != 0 and optimal.sums[sub] == 0 and 1 + optimal.solve(mask ^ sub) == optimal.solve(mask) and
                            (chosen == 0 or lexMaskLess(sub, chosen))) chosen = sub;
                    }
                    var group: std.ArrayList(usize) = .empty;
                    try out.writeAll("  group");
                    for (ns.items, 0..) |member, i| {
                        if ((chosen & (@as(usize, 1) << @intCast(i))) != 0) {
                            try group.append(self.gpa, member);
                            try out.print(" {s}", .{self.members.items[member].name});
                        }
                    }
                    try out.writeByte('\n');
                    for (try self.greedy(group.items, balance)) |transfer| try self.printTransfer(out, transfer, "    ");
                    mask ^= chosen;
                }
            }
        }
    }
};
fn spaces(out: *std.Io.Writer, count: usize) std.Io.Writer.Error!void {
    for (0..count) |_| try out.writeByte(' ');
}
fn addUnique(gpa: Allocator, list: *std.ArrayList([]const u8), value: []const u8) Allocator.Error!void {
    for (list.items) |old| { if (equal(old, value)) return; }
    try list.append(gpa, value);
}
fn sortStrings(values: [][]const u8) void {
    for (1..@max(1, values.len)) |i| {
        const entry = values[i];
        var j = i;
        while (j > 0 and less(entry, values[j - 1])) { values[j] = values[j - 1]; j -= 1; }
        values[j] = entry;
    }
}
fn lowBit(mask: usize) usize { return mask & (~mask + 1); }
fn lexMaskLess(left: usize, right: usize) bool {
    var a = left;
    var b = right;
    while (a != 0 and b != 0) {
        const x = lowBit(a);
        const y = lowBit(b);
        if (x != y) return x < y;
        a ^= x; b ^= y;
    }
    return a == 0 and b != 0;
}
const Optimal = struct {
    sums: []i64,
    memo: []i32,
    fn init(gpa: Allocator, ns: []const usize, balances: []const i64) Allocator.Error!Optimal {
        const size = @as(usize, 1) << @intCast(ns.len);
        const sums = try gpa.alloc(i64, size);
        const memo = try gpa.alloc(i32, size);
        @memset(memo, -200);
        sums[0] = 0; memo[0] = 0;
        for (1..size) |mask| {
            const bit = lowBit(mask);
            const index: usize = @intCast(@ctz(bit));
            sums[mask] = sums[mask ^ bit] + balances[ns[index]];
        }
        return .{ .sums = sums, .memo = memo };
    }
    fn solve(self: *Optimal, mask: usize) i32 {
        if (self.memo[mask] != -200) return self.memo[mask];
        const first = lowBit(mask);
        var best: i32 = -100;
        var sub = mask;
        while (sub > 0) : (sub = (sub - 1) & mask) {
            if ((sub & first) != 0 and self.sums[sub] == 0) best = @max(best, 1 + self.solve(mask ^ sub));
        }
        self.memo[mask] = best;
        return best;
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [16384]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    var ledger = Ledger{ .gpa = gpa };
    for (0..count) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        ledger.execute(line, &draft.writer) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{ledger.error_buffer[0..ledger.error_len]});
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
