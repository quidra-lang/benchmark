const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const Command = enum { PLAN, TIER, TAX, CUSTOMER, COUPON, PAYMETHOD, CREDIT, DAY, SUBSCRIBE, CHANGE, PAUSE, RESUME, CANCEL, USAGE, APPLY, PAY, REFUND, INVOICE, SUB, PREVIEW, STATEMENT, LEDGER, MRR, AGING, DUNNING, REVENUE, EVENTS };
const State = enum { NONE, TRIALING, ACTIVE, PAST_DUE, UNPAID, PAUSED, CANCELED };
const Cycle = enum {
    WEEKLY,
    MONTHLY,
    YEARLY,
    fn days(c: Cycle) i64 {
        return switch (c) {
            .WEEKLY => 7,
            .MONTHLY => 30,
            .YEARLY => 360,
        };
    }
};
const Mode = enum { GRADUATED, VOLUME };
const Kind = enum { first, renewal, upgrade, final };
fn integer(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch unreachable;
}
fn amount(s: []const u8) i64 {
    const dot = std.mem.findScalar(u8, s, '.').?;
    return integer(s[0..dot]) * 100 + integer(s[dot + 1 ..]);
}
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
const Tier = struct { limit: ?i64, unit: i64, flat: i64 };
const Plan = struct {
    name: []const u8,
    price: i64,
    cycle: Cycle,
    trial: i64 = 0,
    setup: i64 = 0,
    per_seat: bool = false,
    mode: ?Mode = null,
    tiers: std.ArrayList(Tier) = .empty,
    fn fee(p: *const Plan, seats: i64) i64 {
        return p.price * (if (p.per_seat) seats else 1);
    }
    fn usageCharge(p: *const Plan, units: i64) i64 {
        var total: i64 = 0;
        var lower: i64 = 0;
        for (p.tiers.items, 0..) |t, i| {
            const upper = if (i + 1 == p.tiers.items.len) units else t.limit.?;
            if (p.mode.? == .VOLUME) {
                if (units <= upper) return units * t.unit + t.flat;
            } else if (lower < units) {
                total += (@min(units, upper) - lower) * t.unit + t.flat;
            }
            lower = upper;
        }
        return total;
    }
};
const BalanceEntry = struct { day: i64, description: []const u8, change: i64, balance: i64 };
const Customer = struct {
    name: []const u8,
    region: []const u8,
    method_ok: bool = true,
    balance: i64 = 0,
    log: std.ArrayList(BalanceEntry) = .empty,
};
const Coupon = struct {
    name: []const u8,
    percent: bool,
    value: i64,
    applications: ?i64,
    maximum: ?i64 = null,
    redemptions: i64 = 0,
};
const Selection = struct { plan: *Plan, seats: i64 };
const Subscription = struct {
    id: usize,
    customer: *Customer,
    plan: *Plan,
    seats: i64,
    state: State = .NONE,
    start: i64 = 0,
    end: i64 = 0,
    trial_end: i64 = 0,
    pause_day: i64 = 0,
    pending: ?Selection = null,
    cancel_end: bool = false,
    cancel_day: ?i64 = null,
    canceled_on: i64 = 0,
    coupon: ?*Coupon = null,
    left: ?i64 = null,
    usage: i64 = 0,
    invoices: std.ArrayList(*Invoice) = .empty,
};
const Item = struct { description: []const u8, amount: i64 };
const Totals = struct { subtotal: i64 = 0, discount: i64 = 0, tax: i64 = 0, total: i64 = 0, credit: i64 = 0, due: i64 = 0 };
const Invoice = struct {
    id: usize,
    sub: *Subscription,
    day: i64,
    kind: Kind,
    items: []const Item,
    sums: Totals,
    paid: i64 = 0,
    refunded: i64 = 0,
    outstanding: i64,
    attempts: usize = 0,
    retries: [3]i64 = @splat(0),
    next_retry: usize = 3,
};
const Event = struct { day: i64, sub_id: usize, from: State, to: State };
const Billing = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    day: i64 = 1,
    plans: std.StringArrayHashMapUnmanaged(*Plan) = .empty,
    customers: std.StringArrayHashMapUnmanaged(*Customer) = .empty,
    coupons: std.StringHashMapUnmanaged(*Coupon) = .empty,
    taxes: std.StringHashMapUnmanaged(i64) = .empty,
    subscriptions: std.ArrayList(*Subscription) = .empty,
    invoices: std.ArrayList(*Invoice) = .empty,
    events: std.ArrayList(Event) = .empty,

    fn fail(self: *Billing, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn money(self: *Billing, n: i64) Allocator.Error![]const u8 {
        const u = @abs(n);
        return std.fmt.allocPrint(self.gpa, "{s}{d}.{d:0>2}", .{ if (n < 0) "-" else "", u / 100, u % 100 });
    }
    fn rate(self: *Billing, n: i64) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.gpa, "{s}%", .{try self.money(n)});
    }
    fn ordered(self: *Billing, comptime T: type, values: []const *T) Allocator.Error![]*T {
        const result = try self.gpa.dupe(*T, values);
        std.mem.sort(*T, result, {}, struct {
            fn less(_: void, a: *T, b: *T) bool {
                return std.mem.order(u8, a.name, b.name) == .lt;
            }
        }.less);
        return result;
    }
    fn plan(self: *Billing, name: []const u8) Error!*Plan {
        return self.plans.get(name) orelse return self.fail("unknown plan {s}", .{name});
    }
    fn customer(self: *Billing, name: []const u8) Error!*Customer {
        return self.customers.get(name) orelse return self.fail("unknown customer {s}", .{name});
    }
    fn coupon(self: *Billing, name: []const u8) Error!*Coupon {
        const c = self.coupons.get(name) orelse return self.fail("unknown coupon {s}", .{name});
        if (c.maximum) |maximum| {
            if (c.redemptions == maximum) return self.fail("coupon exhausted {s}", .{name});
        }
        return c;
    }
    fn subscription(self: *Billing, token: []const u8) Error!*Subscription {
        const id: usize = @intCast(integer(token));
        if (id == 0 or id > self.subscriptions.items.len) return self.fail("unknown sub {s}", .{token});
        return self.subscriptions.items[id - 1];
    }
    fn invoice(self: *Billing, token: []const u8) Error!*Invoice {
        const id: usize = @intCast(integer(token));
        if (id == 0 or id > self.invoices.items.len) return self.fail("unknown invoice {s}", .{token});
        return self.invoices.items[id - 1];
    }
    fn requireState(self: *Billing, s: *Subscription, states: []const State) Error!void {
        for (states) |state| if (s.state == state) return;
        return self.fail("invalid state {d} {s}", .{ s.id, @tagName(s.state) });
    }
    fn balance(self: *Billing, c: *Customer, change: i64, comptime fmt: []const u8, args: anytype) Error!void {
        if (change == 0) return;
        c.balance += change;
        try c.log.append(self.gpa, .{ .day = self.day, .description = try std.fmt.allocPrint(self.gpa, fmt, args), .change = change, .balance = c.balance });
    }
    fn transition(self: *Billing, s: *Subscription, to: State) Error!void {
        const from = s.state;
        try self.out.print("  day {d} sub {d} {s} -> {s}\n", .{ self.day, s.id, @tagName(from), @tagName(to) });
        try self.events.append(self.gpa, .{ .day = self.day, .sub_id = s.id, .from = from, .to = to });
        if (from == .PAST_DUE) {
            for (s.invoices.items) |inv| inv.next_retry = 3;
        }
        s.state = to;
    }
    fn completed(self: *Billing, inv: *Invoice) Error!void {
        inv.next_retry = 3;
        const s = inv.sub;
        if (s.state != .PAST_DUE and s.state != .UNPAID) return;
        for (s.invoices.items) |other| if (other.outstanding > 0) return;
        s.cancel_day = null;
        try self.transition(s, .ACTIVE);
    }
    fn item(self: *Billing, items: *std.ArrayList(Item), value: i64, comptime fmt: []const u8, args: anytype) Error!void {
        try items.append(self.gpa, .{ .description = try std.fmt.allocPrint(self.gpa, fmt, args), .amount = value });
    }
    fn charge(self: *Billing, items: *std.ArrayList(Item), p: *Plan, seats: i64, start: i64) Error!void {
        try self.item(items, p.fee(seats), "charge {s} seats {d} {d}-{d}", .{ p.name, seats, start, start + p.cycle.days() });
    }
    fn opening(self: *Billing, s: *Subscription, start: i64) Error!std.ArrayList(Item) {
        var items: std.ArrayList(Item) = .empty;
        try self.charge(&items, s.plan, s.seats, start);
        if (s.plan.setup > 0) try self.item(&items, s.plan.setup, "setup {s}", .{s.plan.name});
        return items;
    }
    fn usageItem(self: *Billing, items: *std.ArrayList(Item), s: *Subscription, close: bool) Error!void {
        if (s.plan.mode == null or s.usage == 0) return;
        try self.item(items, s.plan.usageCharge(s.usage), "usage {s} {d} units", .{ s.plan.name, s.usage });
        if (close) s.usage = 0;
    }
    fn totals(self: *Billing, s: *Subscription, items: []const Item) Totals {
        var t: Totals = .{};
        for (items) |line| t.subtotal += line.amount;
        if (s.coupon) |c| {
            if ((s.left == null or s.left.? > 0) and t.subtotal > 0) {
                t.discount = if (c.percent) @divTrunc(t.subtotal * c.value, 10000) else @min(c.value, t.subtotal);
            }
        }
        t.tax = @divTrunc((t.subtotal - t.discount) * (self.taxes.get(s.customer.region) orelse 0), 10000);
        t.total = t.subtotal - t.discount + t.tax;
        t.credit = @min(s.customer.balance, t.total);
        t.due = t.total - t.credit;
        return t;
    }
    fn issue(self: *Billing, s: *Subscription, kind: Kind, items: std.ArrayList(Item)) Error!void {
        const t = self.totals(s, items.items);
        if (s.coupon != null and t.subtotal > 0) {
            if (s.left) |left| if (left > 0) {
                s.left = left - 1;
            };
        }
        const inv = try self.gpa.create(Invoice);
        inv.* = .{ .id = self.invoices.items.len + 1, .sub = s, .day = self.day, .kind = kind, .items = items.items, .sums = t, .outstanding = t.due };
        try self.invoices.append(self.gpa, inv);
        try s.invoices.append(self.gpa, inv);
        try self.balance(s.customer, -t.credit, "applied invoice {d}", .{inv.id});
        var result: []const u8 = "PAID";
        if (t.due > 0) {
            if (s.state == .UNPAID) {
                result = "OPEN";
            } else {
                inv.attempts = 1;
                if (s.customer.method_ok) {
                    inv.paid = t.due;
                    inv.outstanding = 0;
                } else result = "FAILED";
            }
        }
        try self.out.print("  day {d} invoice {d} sub {d} {s} total {s} credit {s} due {s} {s}\n", .{ self.day, inv.id, s.id, @tagName(kind), try self.money(t.total), try self.money(t.credit), try self.money(t.due), result });
        if (equal(result, "FAILED")) {
            if (s.state == .ACTIVE) try self.transition(s, .PAST_DUE);
            if (s.state == .PAST_DUE) {
                inv.retries = .{ self.day + 3, self.day + 5, self.day + 7 };
                inv.next_retry = 0;
            }
        }
    }
    fn cancel(self: *Billing, s: *Subscription) Error!void {
        try self.transition(s, .CANCELED);
        s.canceled_on = self.day;
        s.pending = null;
        s.cancel_end = false;
        s.cancel_day = null;
        var items: std.ArrayList(Item) = .empty;
        try self.usageItem(&items, s, true);
        if (items.items.len > 0) try self.issue(s, .final, items);
    }
    fn advance(self: *Billing, target: i64) Error!void {
        while (self.day < target) {
            self.day += 1;
            for (self.subscriptions.items) |s| {
                if (s.state == .PAUSED or s.state == .CANCELED) continue;
                for (s.invoices.items) |inv| {
                    if (inv.next_retry == 3 or inv.retries[inv.next_retry] != self.day) continue;
                    inv.next_retry += 1;
                    inv.attempts += 1;
                    try self.out.print("  day {d} retry {d} invoice {d} {s}\n", .{ self.day, inv.attempts - 1, inv.id, if (s.customer.method_ok) "PAID" else "FAILED" });
                    if (s.customer.method_ok) {
                        inv.paid += inv.outstanding;
                        inv.outstanding = 0;
                        try self.completed(inv);
                    } else if (inv.next_retry == 3) {
                        try self.transition(s, .UNPAID);
                        s.cancel_day = self.day + 14;
                    }
                }
                if (s.state == .UNPAID and s.cancel_day == self.day) try self.cancel(s);
                if (s.state == .TRIALING and s.trial_end == self.day) {
                    if (s.cancel_end) {
                        try self.cancel(s);
                    } else {
                        try self.transition(s, .ACTIVE);
                        s.start = self.day;
                        s.end = self.day + s.plan.cycle.days();
                        try self.issue(s, .first, try self.opening(s, self.day));
                    }
                }
                if ((s.state == .ACTIVE or s.state == .PAST_DUE or s.state == .UNPAID) and s.end == self.day) {
                    if (s.cancel_end) {
                        try self.cancel(s);
                    } else {
                        var items: std.ArrayList(Item) = .empty;
                        try self.usageItem(&items, s, true);
                        if (s.pending) |pending| {
                            try self.out.print("  day {d} sub {d} {s} seats {d} -> {s} seats {d}\n", .{ self.day, s.id, s.plan.name, s.seats, pending.plan.name, pending.seats });
                            s.plan = pending.plan;
                            s.seats = pending.seats;
                            s.pending = null;
                        }
                        s.start = self.day;
                        s.end = self.day + s.plan.cycle.days();
                        try self.charge(&items, s.plan, s.seats, self.day);
                        try self.issue(s, .renewal, items);
                    }
                }
            }
        }
    }
    fn printItems(self: *Billing, items: []const Item, t: Totals) Error!void {
        for (items) |line| try self.out.print("  {s} {s}\n", .{ line.description, try self.money(line.amount) });
        try self.out.print("  subtotal {s} discount {s} tax {s} total {s}\n", .{ try self.money(t.subtotal), try self.money(t.discount), try self.money(t.tax), try self.money(t.total) });
    }
    fn preview(self: *Billing, s: *Subscription) Error!void {
        try self.requireState(s, &.{ .TRIALING, .ACTIVE, .PAST_DUE, .UNPAID });
        const day = if (s.state == .TRIALING) s.trial_end else s.end;
        const kind: Kind = if (s.cancel_end) .final else if (s.state == .TRIALING) .first else .renewal;
        var items: std.ArrayList(Item) = .empty;
        if (kind == .first) {
            items = try self.opening(s, day);
        } else if (s.state != .TRIALING) {
            try self.usageItem(&items, s, false);
            if (kind == .renewal) {
                const selection = s.pending orelse Selection{ .plan = s.plan, .seats = s.seats };
                try self.charge(&items, selection.plan, selection.seats, day);
            }
        }
        try self.out.print("PREVIEW sub {d} day {d} {s}\n", .{ s.id, day, @tagName(kind) });
        if (items.items.len == 0) return self.out.writeAll("  (none)\n");
        const t = self.totals(s, items.items);
        try self.printItems(items.items, t);
        try self.out.print("  credit {s} due {s}\n", .{ try self.money(t.credit), try self.money(t.due) });
    }
    fn printSub(self: *Billing, s: *Subscription) Error!void {
        try self.out.print("SUB {d} {s} {s} seats {d} {s}\n", .{ s.id, s.customer.name, s.plan.name, s.seats, @tagName(s.state) });
        if (s.state == .TRIALING) try self.out.print("  trial until {d}\n", .{s.trial_end});
        if (s.state == .ACTIVE or s.state == .PAST_DUE or s.state == .UNPAID or s.state == .PAUSED) try self.out.print("  period {d}-{d}\n", .{ s.start, s.end });
        if (s.state == .PAUSED) try self.out.print("  paused since {d}\n", .{s.pause_day});
        if (s.pending) |p| try self.out.print("  pending {s} seats {d}\n", .{ p.plan.name, p.seats });
        if (s.cancel_end) try self.out.writeAll("  cancel at end\n");
        if (s.cancel_day) |day| try self.out.print("  cancel on {d}\n", .{day});
        if (s.state == .CANCELED) try self.out.print("  canceled on {d}\n", .{s.canceled_on});
        if (s.coupon) |c| {
            if (s.left) |left| {
                if (left > 0) try self.out.print("  coupon {s} left {d}\n", .{ c.name, left });
            } else try self.out.print("  coupon {s} forever\n", .{c.name});
        }
        if (s.plan.mode != null and s.state != .CANCELED) try self.out.print("  usage {d}\n", .{s.usage});
        var found = false;
        for (s.invoices.items) |inv| {
            if (inv.outstanding == 0) continue;
            if (!found) try self.out.writeAll("  open");
            found = true;
            try self.out.print(" {d}", .{inv.id});
        }
        if (found) try self.out.writeAll("\n");
    }
    fn agingLine(self: *Billing, name: []const u8, buckets: [3]i64) Error!void {
        try self.out.print("  {s} 0-30 {s} 31-60 {s} 61+ {s} sum {s}\n", .{ name, try self.money(buckets[0]), try self.money(buckets[1]), try self.money(buckets[2]), try self.money(buckets[0] + buckets[1] + buckets[2]) });
    }
    fn execute(self: *Billing, a: []const []const u8) Error!void {
        const op = std.meta.stringToEnum(Command, a[0]).?;
        const id: []const u8 = if (a.len > 1) a[1] else "";
        switch (op) {
            .PLAN => {
                if (self.plans.contains(id)) return self.fail("duplicate plan {s}", .{id});
                const p = try self.gpa.create(Plan);
                p.* = .{ .name = id, .price = amount(a[2]), .cycle = std.meta.stringToEnum(Cycle, a[3]).? };
                var i: usize = 4;
                while (i < a.len) : (i += 1) {
                    if (equal(a[i], "TRIAL")) {
                        i += 1;
                        p.trial = integer(a[i]);
                    } else if (equal(a[i], "SETUP")) {
                        i += 1;
                        p.setup = amount(a[i]);
                    } else if (equal(a[i], "PERSEAT")) {
                        p.per_seat = true;
                    } else {
                        p.mode = std.meta.stringToEnum(Mode, a[i]).?;
                    }
                }
                try self.plans.put(self.gpa, id, p);
                try self.out.print("PLAN {s} {s} {s}", .{ id, a[3], try self.money(p.price) });
                if (p.trial > 0) try self.out.print(" trial {d}", .{p.trial});
                if (p.setup > 0) try self.out.print(" setup {s}", .{try self.money(p.setup)});
                if (p.per_seat) try self.out.writeAll(" perseat");
                if (p.mode) |mode| try self.out.writeAll(if (mode == .GRADUATED) " graduated" else " volume");
                try self.out.writeAll("\n");
            },
            .TIER => {
                const p = try self.plan(id);
                if (p.mode == null) return self.fail("not metered {s}", .{id});
                const limit: ?i64 = if (equal(a[2], "INF")) null else integer(a[2]);
                if (p.tiers.items.len > 0) {
                    const last = p.tiers.items[p.tiers.items.len - 1].limit;
                    if (last == null or (limit != null and limit.? <= last.?)) return self.fail("tier order {s}", .{id});
                }
                try p.tiers.append(self.gpa, .{ .limit = limit, .unit = amount(a[3]), .flat = amount(a[4]) });
                try self.out.print("TIER {s} {d} upto {s} unit {s} flat {s}\n", .{ id, p.tiers.items.len, a[2], a[3], a[4] });
            },
            .TAX => {
                const bp = integer(a[2]);
                try self.taxes.put(self.gpa, id, bp);
                try self.out.print("TAX {s} {s}\n", .{ id, try self.rate(bp) });
            },
            .CUSTOMER => {
                if (self.customers.contains(id)) return self.fail("duplicate customer {s}", .{id});
                const c = try self.gpa.create(Customer);
                c.* = .{ .name = id, .region = a[2] };
                try self.customers.put(self.gpa, id, c);
                try self.out.print("CUSTOMER {s} region {s}\n", .{ id, c.region });
            },
            .COUPON => {
                if (self.coupons.contains(id)) return self.fail("duplicate coupon {s}", .{id});
                const c = try self.gpa.create(Coupon);
                const percent = equal(a[2], "PERCENT");
                c.* = .{ .name = id, .percent = percent, .value = if (percent) integer(a[3]) else amount(a[3]), .applications = if (equal(a[4], "FOREVER")) null else if (equal(a[4], "ONCE")) 1 else integer(a[5]) };
                const i: usize = if (equal(a[4], "REPEATING")) 6 else 5;
                if (i < a.len) c.maximum = integer(a[i + 1]);
                try self.coupons.put(self.gpa, id, c);
                try self.out.print("COUPON {s} {s} {s} ", .{ id, if (percent) "percent" else "amount", if (percent) try self.rate(c.value) else try self.money(c.value) });
                if (equal(a[4], "REPEATING")) try self.out.print("repeating {d}", .{c.applications.?}) else try self.out.writeAll(if (c.applications == null) "forever" else "once");
                if (c.maximum) |maximum| try self.out.print(" max {d}", .{maximum});
                try self.out.writeAll("\n");
            },
            .PAYMETHOD, .CREDIT, .STATEMENT, .LEDGER => {
                const c = try self.customer(id);
                switch (op) {
                    .PAYMETHOD => {
                        c.method_ok = equal(a[2], "OK");
                        try self.out.print("PAYMETHOD {s} {s}\n", .{ id, a[2] });
                    },
                    .CREDIT => {
                        const value = amount(a[2]);
                        if (value == 0) return self.fail("invalid amount", .{});
                        try self.balance(c, value, "grant", .{});
                        try self.out.print("CREDIT {s} amount {s} balance {s}\n", .{ id, a[2], try self.money(c.balance) });
                    },
                    .STATEMENT => {
                        try self.out.print("STATEMENT {s} region {s} tax {s} method {s} balance {s}\n", .{ id, c.region, try self.rate(self.taxes.get(c.region) orelse 0), if (c.method_ok) "OK" else "FAIL", try self.money(c.balance) });
                        for (self.subscriptions.items) |s| if (s.customer == c) {
                            try self.out.print("  sub {d} {s} {s}\n", .{ s.id, s.plan.name, @tagName(s.state) });
                        };
                        var outstanding: i64 = 0;
                        for (self.invoices.items) |inv| {
                            if (inv.sub.customer != c) continue;
                            outstanding += inv.outstanding;
                            try self.out.print("  invoice {d} day {d} sub {d} {s} total {s} outstanding {s}\n", .{ inv.id, inv.day, inv.sub.id, @tagName(inv.kind), try self.money(inv.sums.total), try self.money(inv.outstanding) });
                        }
                        try self.out.print("  outstanding {s}\n", .{try self.money(outstanding)});
                    },
                    .LEDGER => {
                        try self.out.print("LEDGER {s} balance {s}\n", .{ id, try self.money(c.balance) });
                        for (c.log.items) |entry| try self.out.print("  day {d} {s} {s}{s} balance {s}\n", .{ entry.day, entry.description, if (entry.change > 0) "+" else "", try self.money(entry.change), try self.money(entry.balance) });
                        if (c.log.items.len == 0) try self.out.writeAll("  (none)\n");
                    },
                    else => unreachable,
                }
            },
            .DAY => {
                const day = integer(id);
                if (day <= self.day) return self.fail("invalid day {s}", .{id});
                try self.out.print("DAY {d}\n", .{day});
                try self.advance(day);
            },
            .SUBSCRIBE => {
                const c = try self.customer(id);
                const p = try self.plan(a[2]);
                var i: usize = 3;
                var seats: i64 = 1;
                if (i < a.len and equal(a[i], "SEATS")) {
                    if (!p.per_seat) return self.fail("not per-seat {s}", .{p.name});
                    seats = integer(a[i + 1]);
                    i += 2;
                }
                if (seats == 0) return self.fail("invalid seats", .{});
                const cp: ?*Coupon = if (i < a.len) try self.coupon(a[i + 1]) else null;
                const s = try self.gpa.create(Subscription);
                s.* = .{ .id = self.subscriptions.items.len + 1, .customer = c, .plan = p, .seats = seats, .coupon = cp };
                if (cp) |coupon_value| {
                    coupon_value.redemptions += 1;
                    s.left = coupon_value.applications;
                }
                try self.subscriptions.append(self.gpa, s);
                try self.out.print("SUBSCRIBE sub {d} {s} {s} seats {d}", .{ s.id, id, p.name, seats });
                if (cp) |coupon_value| try self.out.print(" coupon {s}", .{coupon_value.name});
                try self.out.writeAll("\n");
                if (p.trial > 0) {
                    s.trial_end = self.day + p.trial;
                    try self.transition(s, .TRIALING);
                } else {
                    try self.transition(s, .ACTIVE);
                    s.start = self.day;
                    s.end = self.day + p.cycle.days();
                    try self.issue(s, .first, try self.opening(s, self.day));
                }
            },
            .PAY, .REFUND, .INVOICE => {
                const inv = try self.invoice(id);
                if (op == .PAY) {
                    if (inv.outstanding == 0) return self.fail("already paid {s}", .{id});
                    try self.out.print("PAY invoice {d} amount {s}\n", .{ inv.id, try self.money(inv.outstanding) });
                    inv.paid += inv.outstanding;
                    inv.outstanding = 0;
                    try self.completed(inv);
                } else if (op == .REFUND) {
                    const value = amount(a[2]);
                    if (value == 0) return self.fail("invalid amount", .{});
                    if (value > inv.sums.total - inv.refunded) return self.fail("refund exceeds {s} {s}", .{ id, try self.money(inv.sums.total - inv.refunded) });
                    const applied = @min(value, inv.outstanding);
                    inv.refunded += value;
                    inv.outstanding -= applied;
                    try self.balance(inv.sub.customer, value - applied, "refund invoice {d}", .{inv.id});
                    try self.out.print("REFUND invoice {d} amount {s} applied {s} balance {s}\n", .{ inv.id, a[2], try self.money(applied), try self.money(inv.sub.customer.balance) });
                    if (applied > 0 and inv.outstanding == 0) try self.completed(inv);
                } else {
                    try self.out.print("INVOICE {d} sub {d} {s} day {d} {s} {s}\n", .{ inv.id, inv.sub.id, inv.sub.customer.name, inv.day, @tagName(inv.kind), if (inv.outstanding == 0) "PAID" else "OPEN" });
                    try self.printItems(inv.items, inv.sums);
                    try self.out.print("  credit {s} due {s} paid {s} refunded {s} outstanding {s}\n", .{ try self.money(inv.sums.credit), try self.money(inv.sums.due), try self.money(inv.paid), try self.money(inv.refunded), try self.money(inv.outstanding) });
                }
            },
            .CHANGE, .PAUSE, .RESUME, .CANCEL, .USAGE, .APPLY, .SUB, .PREVIEW => {
                const s = try self.subscription(id);
                switch (op) {
                    .CHANGE => {
                        try self.requireState(s, &.{ .ACTIVE, .TRIALING });
                        var p = s.plan;
                        var seats = s.seats;
                        if (equal(a[2], "PLAN")) {
                            p = try self.plan(a[3]);
                            if (!p.per_seat) seats = 1;
                        } else {
                            if (!p.per_seat) return self.fail("not per-seat {s}", .{p.name});
                            seats = integer(a[3]);
                            if (seats == 0) return self.fail("invalid seats", .{});
                        }
                        if (p == s.plan and seats == s.seats) return self.fail("no change {s}", .{id});
                        const old_fee = s.plan.fee(s.seats);
                        const new_fee = p.fee(seats);
                        const upgrade = new_fee * s.plan.cycle.days() > old_fee * p.cycle.days();
                        s.pending = null;
                        try self.out.print("CHANGE sub {d} {s} seats {d} -> {s} seats {d}", .{ s.id, s.plan.name, s.seats, p.name, seats });
                        if (s.state == .TRIALING) {
                            s.plan = p;
                            s.seats = seats;
                            try self.out.writeAll(" now\n");
                        } else if (upgrade) {
                            try self.out.writeAll(" now\n");
                            const remaining = s.end - self.day;
                            var items: std.ArrayList(Item) = .empty;
                            try self.usageItem(&items, s, true);
                            try self.item(&items, -@divTrunc(old_fee * remaining, s.plan.cycle.days()), "unused {s} seats {d} {d} days", .{ s.plan.name, s.seats, remaining });
                            try self.item(&items, @divTrunc(new_fee * remaining, p.cycle.days()), "remaining {s} seats {d} {d} days", .{ p.name, seats, remaining });
                            s.plan = p;
                            s.seats = seats;
                            try self.issue(s, .upgrade, items);
                        } else {
                            s.pending = .{ .plan = p, .seats = seats };
                            try self.out.print(" at {d}\n", .{s.end});
                        }
                    },
                    .PAUSE => {
                        try self.requireState(s, &.{.ACTIVE});
                        try self.out.print("PAUSE sub {d}\n", .{s.id});
                        s.pause_day = self.day;
                        try self.transition(s, .PAUSED);
                    },
                    .RESUME => {
                        try self.requireState(s, &.{.PAUSED});
                        const shift = self.day - s.pause_day;
                        s.end += shift;
                        s.pause_day = 0;
                        try self.out.print("RESUME sub {d} shift {d} period {d}-{d}\n", .{ s.id, shift, s.start, s.end });
                        try self.transition(s, .ACTIVE);
                    },
                    .CANCEL => {
                        if (equal(a[2], "END")) {
                            try self.requireState(s, &.{ .ACTIVE, .TRIALING });
                            if (s.cancel_end) return self.fail("already canceling {s}", .{id});
                            s.cancel_end = true;
                            try self.out.print("CANCEL sub {d} end {d}\n", .{ s.id, if (s.state == .TRIALING) s.trial_end else s.end });
                        } else {
                            try self.requireState(s, &.{ .TRIALING, .ACTIVE, .PAST_DUE, .UNPAID, .PAUSED });
                            const remaining = if (s.state == .ACTIVE) s.end - self.day else if (s.state == .PAUSED) s.end - s.pause_day else 0;
                            const credit = @divTrunc(s.plan.fee(s.seats) * remaining, s.plan.cycle.days());
                            try self.balance(s.customer, credit, "cancel sub {d}", .{s.id});
                            try self.out.print("CANCEL sub {d} now credit {s}\n", .{ s.id, try self.money(credit) });
                            try self.cancel(s);
                        }
                    },
                    .USAGE => {
                        try self.requireState(s, &.{ .ACTIVE, .PAST_DUE });
                        if (s.plan.mode == null) return self.fail("not metered {s}", .{s.plan.name});
                        const units = integer(a[2]);
                        if (units == 0) return self.fail("invalid units", .{});
                        s.usage += units;
                        try self.out.print("USAGE sub {d} units {d} total {d}\n", .{ s.id, units, s.usage });
                    },
                    .APPLY => {
                        try self.requireState(s, &.{ .TRIALING, .ACTIVE, .PAST_DUE, .UNPAID, .PAUSED });
                        const cp = try self.coupon(a[2]);
                        cp.redemptions += 1;
                        s.coupon = cp;
                        s.left = cp.applications;
                        try self.out.print("APPLY sub {d} coupon {s}\n", .{ s.id, cp.name });
                    },
                    .SUB => try self.printSub(s),
                    .PREVIEW => try self.preview(s),
                    else => unreachable,
                }
            },
            .MRR => {
                try self.out.writeAll("MRR\n");
                var total: i64 = 0;
                var count: usize = 0;
                for (try self.ordered(Plan, self.plans.values())) |p| {
                    var plan_total: i64 = 0;
                    var plan_count: usize = 0;
                    for (self.subscriptions.items) |s| {
                        if (s.plan != p or (s.state != .ACTIVE and s.state != .PAST_DUE)) continue;
                        const fee = p.fee(s.seats);
                        plan_total += switch (p.cycle) {
                            .MONTHLY => fee,
                            .YEARLY => @divTrunc(fee, 12),
                            .WEEKLY => @divTrunc(fee * 30, 7),
                        };
                        plan_count += 1;
                    }
                    if (plan_count > 0) try self.out.print("  {s} subs {d} mrr {s}\n", .{ p.name, plan_count, try self.money(plan_total) });
                    total += plan_total;
                    count += plan_count;
                }
                try self.out.print("  total subs {d} mrr {s}\n", .{ count, try self.money(total) });
            },
            .AGING => {
                try self.out.print("AGING day {d}\n", .{self.day});
                var totals_by_age: [3]i64 = @splat(0);
                for (try self.ordered(Customer, self.customers.values())) |c| {
                    var buckets: [3]i64 = @splat(0);
                    for (self.invoices.items) |inv| {
                        if (inv.sub.customer != c or inv.outstanding == 0) continue;
                        const age = self.day - inv.day;
                        const bucket: usize = if (age <= 30) 0 else if (age <= 60) 1 else 2;
                        buckets[bucket] += inv.outstanding;
                    }
                    if (buckets[0] + buckets[1] + buckets[2] > 0) try self.agingLine(c.name, buckets);
                    for (0..3) |i| totals_by_age[i] += buckets[i];
                }
                try self.agingLine("total", totals_by_age);
            },
            .DUNNING => {
                try self.out.writeAll("DUNNING\n");
                var found = false;
                for (self.invoices.items) |inv| {
                    if (inv.next_retry == 3) continue;
                    found = true;
                    try self.out.print("  invoice {d} sub {d} {s} outstanding {s} attempts {d} next {d}\n", .{ inv.id, inv.sub.id, inv.sub.customer.name, try self.money(inv.outstanding), inv.attempts, inv.retries[inv.next_retry] });
                }
                if (!found) try self.out.writeAll("  (none)\n");
            },
            .REVENUE => {
                var sums: Totals = .{};
                var paid: i64 = 0;
                var refunded: i64 = 0;
                var outstanding: i64 = 0;
                var balances: i64 = 0;
                for (self.invoices.items) |inv| {
                    sums.subtotal += inv.sums.subtotal;
                    sums.discount += inv.sums.discount;
                    sums.tax += inv.sums.tax;
                    sums.total += inv.sums.total;
                    sums.credit += inv.sums.credit;
                    paid += inv.paid;
                    refunded += inv.refunded;
                    outstanding += inv.outstanding;
                }
                for (self.customers.values()) |c| balances += c.balance;
                try self.out.print("REVENUE\n  invoices {d} subtotal {s} discount {s} tax {s} total {s}\n  credit {s} paid {s} refunded {s} outstanding {s} balances {s}\n", .{ self.invoices.items.len, try self.money(sums.subtotal), try self.money(sums.discount), try self.money(sums.tax), try self.money(sums.total), try self.money(sums.credit), try self.money(paid), try self.money(refunded), try self.money(outstanding), try self.money(balances) });
            },
            .EVENTS => {
                const s: ?*Subscription = if (a.len == 2) try self.subscription(id) else null;
                if (s) |sub| try self.out.print("EVENTS sub {d}\n", .{sub.id}) else try self.out.writeAll("EVENTS\n");
                var found = false;
                for (self.events.items) |event| {
                    if (s != null and event.sub_id != s.?.id) continue;
                    found = true;
                    try self.out.print("  day {d} sub {d} {s} -> {s}\n", .{ event.day, event.sub_id, @tagName(event.from), @tagName(event.to) });
                }
                if (!found) try self.out.writeAll("  (none)\n");
            },
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var billing = Billing{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var tokens: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |token| try tokens.append(gpa, token);
        billing.execute(tokens.items) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{billing.error_message});
        };
    }
    try output.interface.flush();
}
