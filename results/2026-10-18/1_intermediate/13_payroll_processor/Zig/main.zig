const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const setting_names = @typeInfo(Setting).@"enum".field_names;
const Setting = enum { STATE, SUPP, SSRATE, MEDRATE, ADDMED, UIRATE, MATCH, MATCHMAX, GARNCAP, SSBASE, ADDBASE, UIBASE, RETIRECAP, ALLOWANCE, NIGHT };
const V = enum { r, o, d, n, p, accrued, salary, leave, leave_deduction, sales, commission, earnings, bonus, gross, retirement, health, federal, supplemental, state, ss, medicare, garnishment, net, employer_ss, employer_medicare, unemployment, match, employer_total, w, y, f, j };
const value_count = @typeInfo(V).@"enum".field_names.len;
fn integer(s: []const u8) i64 { return std.fmt.parseInt(i64, s, 10) catch unreachable; }
fn amount(s: []const u8) i64 {
    const dot = std.mem.findScalar(u8, s, '.').?;
    return integer(s[0..dot]) * 100 + integer(s[dot + 1..]);
}
fn period(day: usize) usize { return (day - 1) / 14 + 1; }
fn weekday(day: usize) []const u8 { return ([_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" })[(day - 1) % 7]; }
const PayType = enum { HOURLY, SALARIED, COMMISSION };
const Band = struct {
    bound: i64,
    rate: i64,
};
const Shift = struct {
    start: i64,
    end: i64,
};
const Garnishment = struct {
    rate: i64,
    balance: i64,
};
const Day = struct {
    shifts: std.ArrayList(Shift) = .empty,
    pto: ?i64 = null,
    leave: bool = false,
};
const Stub = struct {
    values: [value_count]i64 = @splat(0),
    post_pto: i64 = 0,
    post_garnishment: i64 = 0,
    balances: [10]i64 = @splat(0),
    fn get(s: *const Stub, key: V) i64 { return s.values[@intFromEnum(key)]; }
    fn set(s: *Stub, key: V, value: i64) void { s.values[@intFromEnum(key)] = value; }
    fn add(s: *Stub, other: Stub) void {
        for (0..value_count) |i| s.values[i] += other.values[i];
    }
};
const Record = struct {
    stub: Stub,
    department: []const u8,
};
const Employee = struct {
    id: i64,
    department: []const u8,
    kind: PayType,
    base: i64,
    active: bool = true,
    retirement: i64 = 0,
    health: i64 = 0,
    allowances: i64 = 0,
    extra: i64 = 0,
    bonus: i64 = 0,
    pto: i64 = 0,
    stub_count: usize = 0,
    garnishments: std.ArrayList(Garnishment) = .empty,
    days: [365]Day = @splat(.{}),
    sales: [27]i64 = @splat(0),
    records: [27]?Record = @splat(null),
    ytd: Stub = .{},
    fn garnishmentBalance(e: *Employee) i64 {
        var total: i64 = 0;
        for (e.garnishments.items) |g| total += g.balance;
        return total;
    }
};
fn progressive(table: []const Band, x: i64) i64 {
    var total: i64 = 0;
    for (table, 0..) |b, i| {
        if (b.bound < x) total += b.rate * ((if (i + 1 == table.len) x else @min(x, table[i + 1].bound)) - b.bound);
    }
    return @divTrunc(total, 10000);
}
fn deduct(s: *Stub, left: *i64, key: V, value: i64) void {
    const taken = @min(left.*, value);
    s.set(key, taken);
    left.* -= taken;
}
const Payroll = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    closed: usize = 0,
    config: [15]i64 = .{ 500, 2200, 620, 145, 90, 270, 5000, 600, 2500, 16860000, 20000000, 700000, 2300000, 15000, 100 },
    tax_table: std.ArrayList(Band) = .empty,
    commission_table: std.ArrayList(Band) = .empty,
    holidays: [365]bool = @splat(false),
    employees: std.AutoArrayHashMapUnmanaged(i64, *Employee) = .empty,
    fn fail(self: *Payroll, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn setting(self: *Payroll, key: Setting) i64 { return self.config[@intFromEnum(key)]; }
    fn money(self: *Payroll, n: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(n);
        return std.fmt.allocPrint(self.gpa, "{d}.{d:0>2}", .{ u / 100, u % 100 });
    }
    fn rateText(self: *Payroll, n: i64) Allocator.Error![]const u8 { return std.fmt.allocPrint(self.gpa, "{s}%", .{try self.money(n)}); }
    fn duration(self: *Payroll, m: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(m);
        return std.fmt.allocPrint(self.gpa, "{d}:{d:0>2}", .{ u / 60, u % 60 });
    }
    fn clock(self: *Payroll, m: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(m);
        return std.fmt.allocPrint(self.gpa, "{d:0>2}:{d:0>2}", .{ u / 60, u % 60 });
    }
    fn people(self: *Payroll) Error![]*Employee {
        const result = try self.gpa.dupe(*Employee, self.employees.values());
        std.mem.sort(*Employee, result, {}, struct {
            fn less(_: void, left: *Employee, right: *Employee) bool { return left.id < right.id; }
        }.less);
        return result;
    }
    fn employee(self: *Payroll, id: []const u8, active: bool) Error!*Employee {
        const e = self.employees.get(integer(id)) orelse return self.fail("unknown employee {s}", .{id});
        if (active and !e.active) return self.fail("terminated employee {s}", .{id});
        return e;
    }
    fn typeCheck(self: *Payroll, e: *Employee, kind: PayType) Error!void {
        if (e.kind != kind) return self.fail("not {s} {d}", .{ if (kind == .HOURLY) "hourly" else if (kind == .SALARIED) "salaried" else "commission", e.id });
    }
    fn dayCheck(self: *Payroll, token: []const u8) Error!usize {
        const day = integer(token);
        if (day < 1 or day > 364) return self.fail("invalid day {s}", .{token});
        const d: usize = @intCast(day);
        if (period(d) <= self.closed) return self.fail("period closed {d}", .{period(d)});
        return d;
    }
    fn periodCheck(self: *Payroll, token: []const u8) Error!usize {
        const p = integer(token);
        if (p < 1 or p > 26) return self.fail("invalid period {s}", .{token});
        return @intCast(p);
    }
    fn rateCheck(self: *Payroll, token: []const u8) Error!void {
        if (amount(token) > 10000) return self.fail("invalid rate {s}", .{token});
    }
    fn amountCheck(self: *Payroll, n: i64) Error!void {
        if (n == 0) return self.fail("invalid amount", .{});
    }
    fn timeCheck(self: *Payroll, token: []const u8) Error!i64 {
        const h = integer(token[0..2]);
        const m = integer(token[3..5]);
        if (h > 23 or m > 59) return self.fail("invalid time {s}", .{token});
        return h * 60 + m;
    }
    fn daily(self: *Payroll, e: *Employee, day: usize) [6]i64 {
        var worked: i64 = 0;
        var night: i64 = 0;
        for (e.days[day].shifts.items) |s| {
            worked += s.end - s.start;
            night += @max(0, @min(s.end, 360) - s.start) + @max(0, s.end - @max(s.start, 1320));
        }
        const special = day % 7 == 0 or self.holidays[day];
        return .{ worked, if (special) 0 else @min(worked, 480), if (special) 0 else @min(@max(worked - 480, 0), 240), if (special) worked else @max(0, worked - 720), night, e.days[day].pto orelse 0 };
    }
    fn weekly(self: *Payroll, e: *Employee, week: usize) [6]i64 {
        var result: [6]i64 = @splat(0);
        for (week * 7 - 6..week * 7 + 1) |d| {
            const b = self.daily(e, d);
            for (0..5) |i| result[i] += b[i + 1];
        }
        result[5] = @max(0, result[0] - 2400);
        result[0] -= result[5];
        result[1] += result[5];
        return result;
    }
    fn breakdown(self: *Payroll, e: *Employee, p: usize) [5]i64 {
        const a = self.weekly(e, 2 * p - 1);
        const b = self.weekly(e, 2 * p);
        var result: [5]i64 = undefined;
        for (0..5) |i| result[i] = a[i] + b[i];
        return result;
    }
    fn calculate(self: *Payroll, e: *Employee, p: usize) ?Stub {
        var s: Stub = .{};
        switch (e.kind) {
            .HOURLY => {
                const b = self.breakdown(e, p);
                for (0..5) |i| s.values[i] = b[i];
                s.set(.earnings, @divTrunc((2 * (b[0] + b[4]) + 3 * b[1] + 4 * b[2]) * e.base + 2 * b[3] * self.setting(.NIGHT), 120));
            },
            .SALARIED => {
                if (e.active) {
                    s.set(.salary, @divTrunc(e.base, 26));
                    var count: i64 = 0;
                    for (14 * p - 13..14 * p + 1) |d| {
                        if (e.days[d].leave and !self.holidays[d]) count += 1;
                    }
                    s.set(.leave, count);
                    s.set(.leave_deduction, count * @divTrunc(e.base, 260));
                    s.set(.earnings, s.get(.salary) - s.get(.leave_deduction));
                }
            },
            .COMMISSION => {
                s.set(.sales, e.sales[p]);
                s.set(.commission, progressive(self.commission_table.items, s.get(.sales)));
                s.set(.earnings, s.get(.commission) + (if (e.active) e.base else @as(i64, 0)));
            },
        }
        s.set(.bonus, e.bonus);
        s.set(.gross, s.get(.earnings) + s.get(.bonus));
        if (s.get(.gross) == 0) return null;
        var left = s.get(.gross);
        deduct(&s, &left, .retirement, @min(@divTrunc(s.get(.gross) * e.retirement, 10000), @max(0, self.setting(.RETIRECAP) - e.ytd.get(.retirement))));
        deduct(&s, &left, .health, e.health);
        s.set(.w, left);
        const q = @max(0, s.get(.earnings) - s.get(.retirement) - s.get(.health));
        const taxable = @max(0, q - e.allowances * self.setting(.ALLOWANCE));
        deduct(&s, &left, .federal, progressive(self.tax_table.items, taxable) + e.extra);
        deduct(&s, &left, .supplemental, @divTrunc((s.get(.w) - q) * self.setting(.SUPP), 10000));
        deduct(&s, &left, .state, @divTrunc(s.get(.w) * self.setting(.STATE), 10000));
        s.set(.f, s.get(.gross) - s.get(.health));
        s.set(.y, @min(s.get(.f), @max(0, self.setting(.SSBASE) - e.ytd.get(.y))));
        const additional = @max(0, @min(s.get(.f), e.ytd.get(.f) + s.get(.f) - self.setting(.ADDBASE)));
        deduct(&s, &left, .ss, @divTrunc(s.get(.y) * self.setting(.SSRATE), 10000));
        deduct(&s, &left, .medicare, @divTrunc(s.get(.f) * self.setting(.MEDRATE), 10000) + @divTrunc(additional * self.setting(.ADDMED), 10000));
        const disposable = left;
        const cap = @divTrunc(disposable * self.setting(.GARNCAP), 10000);
        var garnished: i64 = 0;
        for (e.garnishments.items, 0..) |g, i| {
            const take = @min(@divTrunc(disposable * g.rate, 10000), g.balance, cap - garnished);
            garnished += take;
            s.balances[i] = g.balance - take;
            s.post_garnishment += g.balance - take;
        }
        s.set(.garnishment, garnished);
        s.set(.net, left - garnished);
        s.set(.employer_ss, @divTrunc(s.get(.y) * self.setting(.SSRATE), 10000));
        s.set(.employer_medicare, @divTrunc(s.get(.f) * self.setting(.MEDRATE), 10000));
        s.set(.j, @min(s.get(.f), @max(0, self.setting(.UIBASE) - e.ytd.get(.j))));
        s.set(.unemployment, @divTrunc(s.get(.j) * self.setting(.UIRATE), 10000));
        s.set(.match, @divTrunc(@min(s.get(.retirement), @divTrunc(s.get(.gross) * self.setting(.MATCHMAX), 10000)) * self.setting(.MATCH), 10000));
        s.set(.employer_total, s.get(.employer_ss) + s.get(.employer_medicare) + s.get(.unemployment) + s.get(.match));
        s.set(.accrued, if (e.kind == .HOURLY) @min(960 - e.pto, @divTrunc(s.get(.r) + s.get(.o) + s.get(.d), 20)) else 0);
        s.post_pto = e.pto + s.get(.accrued);
        return s;
    }
    fn block(self: *Payroll, e: *Employee, s: *const Stub, indent: []const u8, ytd: bool) Error!void {
        switch (e.kind) {
            .HOURLY => {
                try self.out.print("{s}hours reg {s} ot {s} dbl {s} night {s} pto {s}\n", .{ indent, try self.duration(s.get(.r)), try self.duration(s.get(.o)), try self.duration(s.get(.d)), try self.duration(s.get(.n)), try self.duration(s.get(.p)) });
                try self.out.print("{s}pto accrued {s} balance {s}\n", .{ indent, try self.duration(s.get(.accrued)), try self.duration(if (ytd) e.pto else s.post_pto) });
            },
            .SALARIED => try self.out.print("{s}salary {s} leave {d} deduction {s}\n", .{ indent, try self.money(s.get(.salary)), s.get(.leave), try self.money(s.get(.leave_deduction)) }),
            .COMMISSION => try self.out.print("{s}sales {s} commission {s}\n", .{ indent, try self.money(s.get(.sales)), try self.money(s.get(.commission)) }),
        }
        const labels = [_][]const u8{ "earnings", "bonus", "gross", "retirement", "health", "federal", "supplemental", "state", "social-security", "medicare" };
        const keys = [_]V{ .earnings, .bonus, .gross, .retirement, .health, .federal, .supplemental, .state, .ss, .medicare };
        for (labels, keys) |label, key| try self.out.print("{s}{s} {s}\n", .{ indent, label, try self.money(s.get(key)) });
        try self.out.print("{s}garnishment {s} balance {s}\n{s}net {s}\n", .{ indent, try self.money(s.get(.garnishment)), try self.money(if (ytd) e.garnishmentBalance() else s.post_garnishment), indent, try self.money(s.get(.net)) });
        try self.out.print("{s}employer social-security {s} medicare {s} unemployment {s} match {s}\n", .{ indent, try self.money(s.get(.employer_ss)), try self.money(s.get(.employer_medicare)), try self.money(s.get(.unemployment)), try self.money(s.get(.match)) });
    }
    fn stub(self: *Payroll, e: *Employee, s: *const Stub, p: usize, department: []const u8) Error!void {
        try self.out.print("  STUB {d} {s} {s} period {d}\n", .{ e.id, department, @tagName(e.kind), p });
        try self.block(e, s, "    ", false);
    }
    fn hours(self: *Payroll, e: *Employee, p: usize) Error!void {
        try self.out.print("HOURS {d} period {d}\n", .{ e.id, p });
        var count: usize = 0;
        for (14 * p - 13..14 * p + 1) |d| {
            const shifts = e.days[d].shifts.items;
            if (shifts.len == 0 and e.days[d].pto == null) continue;
            count += 1;
            const b = self.daily(e, d);
            try self.out.print("  day {d} {s}{s}", .{ d, weekday(d), if (self.holidays[d]) " holiday" else "" });
            for (shifts) |s| try self.out.print(" {s}-{s}", .{ try self.clock(s.start), try self.clock(s.end) });
            try self.out.print(" total {s} reg {s} ot {s} dbl {s} night {s} pto {s}\n", .{ try self.duration(b[0]), try self.duration(b[1]), try self.duration(b[2]), try self.duration(b[3]), try self.duration(b[4]), try self.duration(b[5]) });
        }
        if (count == 0) try self.out.writeAll("  (none)\n");
        for ([_]usize{ 2 * p - 1, 2 * p }) |w| {
            const b = self.weekly(e, w);
            try self.out.print("  week {d} reg {s} ot {s} dbl {s} night {s} pto {s} weekly-ot {s}\n", .{ w, try self.duration(b[0]), try self.duration(b[1]), try self.duration(b[2]), try self.duration(b[3]), try self.duration(b[4]), try self.duration(b[5]) });
        }
        const b = self.breakdown(e, p);
        try self.out.print("  total reg {s} ot {s} dbl {s} night {s} pto {s}\n", .{ try self.duration(b[0]), try self.duration(b[1]), try self.duration(b[2]), try self.duration(b[3]), try self.duration(b[4]) });
    }
    fn reportLine(self: *Payroll, name: []const u8, s: *const Stub, count: usize) Error!void {
        try self.out.print("  {s} stubs {d} gross {s} pretax {s} taxes {s} garnishment {s} net {s} employer {s}\n", .{ name, count, try self.money(s.get(.gross)), try self.money(s.get(.retirement) + s.get(.health)), try self.money(s.get(.federal) + s.get(.supplemental) + s.get(.state) + s.get(.ss) + s.get(.medicare)), try self.money(s.get(.garnishment)), try self.money(s.get(.net)), try self.money(s.get(.employer_total)) });
    }
    fn execute(self: *Payroll, a: []const []const u8) Error!void {
        const op = a[0];
        const id: []const u8 = if (a.len > 1) a[1] else "";
        if (std.mem.eql(u8, op, "SET")) {
            const key = std.meta.stringToEnum(Setting, id) orelse return self.fail("unknown setting {s}", .{id});
            const i = @intFromEnum(key);
            if (i < 9) try self.rateCheck(a[2]);
            const old = self.config[i];
            const value = amount(a[2]);
            self.config[i] = value;
            try self.out.print("SET {s} {s} -> {s}\n", .{ id, if (i < 9) try self.rateText(old) else try self.money(old), if (i < 9) try self.rateText(value) else try self.money(value) });
        } else if (std.mem.eql(u8, op, "BRACKET") or std.mem.eql(u8, op, "TIER")) {
            try self.rateCheck(a[2]);
            const table = if (std.mem.eql(u8, op, "BRACKET")) &self.tax_table else &self.commission_table;
            const bound = amount(id);
            const rate = amount(a[2]);
            var replaced = false;
            for (table.items) |*b| {
                if (b.bound == bound) {
                    b.rate = rate;
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                try table.append(self.gpa, .{ .bound = bound, .rate = rate });
                std.mem.sort(Band, table.items, {}, struct {
                    fn less(_: void, left: Band, right: Band) bool { return left.bound < right.bound; }
                }.less);
            }
            try self.out.print("{s} {s} {s} {s}\n", .{ op, try self.money(bound), try self.rateText(rate), if (replaced) "replaced" else "added" });
        } else if (std.mem.eql(u8, op, "EMP")) {
            const number = integer(id);
            if (self.employees.contains(number)) return self.fail("duplicate employee {s}", .{id});
            const base = amount(a[4]);
            try self.amountCheck(base);
            const e = try self.gpa.create(Employee);
            const kind: PayType = if (std.mem.eql(u8, a[3], "HOURLY")) .HOURLY else if (std.mem.eql(u8, a[3], "SALARIED")) .SALARIED else .COMMISSION;
            e.* = .{ .id = number, .department = a[2], .kind = kind, .base = base };
            try self.employees.put(self.gpa, number, e);
            try self.out.print("EMP {s} {s} {s} {s}\n", .{ id, a[2], a[3], try self.money(base) });
        } else if (std.mem.eql(u8, op, "HOLIDAY")) {
            const d = try self.dayCheck(id);
            if (self.holidays[d]) return self.fail("duplicate holiday {s}", .{id});
            self.holidays[d] = true;
            try self.out.print("HOLIDAY {d} {s}\n", .{ d, weekday(d) });
        } else if (std.mem.eql(u8, op, "RUN")) {
            const p: usize = @intCast(integer(id));
            if (p != self.closed + 1 or p > 26) return self.fail("invalid period {s}", .{id});
            self.closed = p;
            try self.out.print("RUN {d} days {d}-{d}\n", .{ p, 14 * p - 13, 14 * p });
            var paid_count: usize = 0;
            var skipped: usize = 0;
            var total: Stub = .{};
            for (try self.people()) |e| {
                const s = self.calculate(e, p) orelse {
                    if (e.active) skipped += 1;
                    continue;
                };
                try self.stub(e, &s, p, e.department);
                paid_count += 1;
                total.add(s);
                e.bonus = 0;
                e.pto = s.post_pto;
                for (e.garnishments.items, 0..) |*g, i| g.balance = s.balances[i];
                e.ytd.add(s);
                e.stub_count += 1;
                e.records[p] = .{ .stub = s, .department = e.department };
            }
            try self.out.print("  TOTAL paid {d} skipped {d} gross {s} deductions {s} net {s} employer {s}\n", .{ paid_count, skipped, try self.money(total.get(.gross)), try self.money(total.get(.gross) - total.get(.net)), try self.money(total.get(.net)), try self.money(total.get(.employer_total)) });
        } else if (std.mem.eql(u8, op, "JOURNAL")) {
            const p: usize = @intCast(integer(id));
            if (p < 1 or p > self.closed) return self.fail("no run {s}", .{id});
            var total: Stub = .{};
            var count: usize = 0;
            for (self.employees.values()) |e| {
                if (e.records[p]) |r| {
                    count += 1;
                    total.add(r.stub);
                }
            }
            try self.out.print("JOURNAL {d} stubs {d}\n", .{ p, count });
            const amounts = [_]i64{ total.get(.gross), total.get(.employer_ss) + total.get(.employer_medicare) + total.get(.unemployment), total.get(.match), total.get(.retirement) + total.get(.match), total.get(.health), total.get(.federal) + total.get(.supplemental), total.get(.state), total.get(.ss) + total.get(.medicare) + total.get(.employer_ss) + total.get(.employer_medicare), total.get(.unemployment), total.get(.garnishment), total.get(.net) };
            const labels = [_][]const u8{ "debit wages", "debit employer-tax", "debit retirement-match", "credit retirement", "credit health", "credit federal", "credit state", "credit fica", "credit unemployment", "credit garnishment", "credit net-pay" };
            var debit: i64 = 0;
            var credit: i64 = 0;
            for (amounts, labels, 0..) |value, label, i| {
                try self.out.print("  {s} {s}\n", .{ label, try self.money(value) });
                if (i < 3) debit += value else credit += value;
            }
            try self.out.print("  total debit {s} credit {s}\n", .{ try self.money(debit), try self.money(credit) });
        } else if (std.mem.eql(u8, op, "REPORT")) {
            const Department = struct {
                name: []const u8,
                total: Stub = .{},
                count: usize = 0,
            };
            var departments: std.StringArrayHashMapUnmanaged(Department) = .empty;
            var all: Stub = .{};
            var count: usize = 0;
            for (self.employees.values()) |e| {
                for (e.records) |maybe| {
                    const r = maybe orelse continue;
                    const entry = try departments.getOrPut(self.gpa, r.department);
                    if (!entry.found_existing) entry.value_ptr.* = .{ .name = r.department };
                    const d = entry.value_ptr;
                    d.total.add(r.stub);
                    d.count += 1;
                    all.add(r.stub);
                    count += 1;
                }
            }
            const ordered = try self.gpa.dupe(Department, departments.values());
            std.mem.sort(Department, ordered, {}, struct {
                fn less(_: void, left: Department, right: Department) bool {
                    return std.mem.order(u8, left.name, right.name) == .lt;
                }
            }.less);
            try self.out.print("REPORT period {d}\n", .{self.closed});
            for (ordered) |d| try self.reportLine(d.name, &d.total, d.count);
            try self.reportLine("total", &all, count);
        } else if (std.mem.eql(u8, op, "TOP")) {
            const k: usize = @intCast(integer(id));
            var selected: std.ArrayList(*Employee) = .empty;
            for (self.employees.values()) |e| {
                if (e.stub_count > 0) try selected.append(self.gpa, e);
            }
            std.mem.sort(*Employee, selected.items, {}, struct {
                fn less(_: void, left: *Employee, right: *Employee) bool {
                    const ag = left.ytd.get(.gross);
                    const bg = right.ytd.get(.gross);
                    return if (ag != bg) ag > bg else left.id < right.id;
                }
            }.less);
            try self.out.print("TOP {d}\n", .{k});
            for (selected.items[0..@min(k, selected.items.len)], 0..) |e, i| try self.out.print("  {d} {d} {s} gross {s} net {s}\n", .{ i + 1, e.id, e.department, try self.money(e.ytd.get(.gross)), try self.money(e.ytd.get(.net)) });
            if (selected.items.len == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "EMPLOYEES")) {
            try self.out.writeAll("EMPLOYEES\n");
            for (try self.people()) |e| {
                try self.out.print("  {d} {s} {s} {s} {s} retirement {s} health {s} allowances {d} extra {s} bonus {s}\n", .{ e.id, e.department, @tagName(e.kind), try self.money(e.base), if (e.active) "active" else "terminated", try self.rateText(e.retirement), try self.money(e.health), e.allowances, try self.money(e.extra), try self.money(e.bonus) });
                for (e.garnishments.items, 0..) |g, i| try self.out.print("    garnish {d} {s} balance {s}\n", .{ i + 1, try self.rateText(g.rate), try self.money(g.balance) });
            }
            if (self.employees.count() == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "CONFIG")) {
            try self.out.writeAll("CONFIG\n");
            for (setting_names, 0..) |name, i| try self.out.print("  {s} {s}\n", .{ name, if (i < 9) try self.rateText(self.config[i]) else try self.money(self.config[i]) });
            for (self.tax_table.items) |b| try self.out.print("  bracket {s} {s}\n", .{ try self.money(b.bound), try self.rateText(b.rate) });
            for (self.commission_table.items) |b| try self.out.print("  tier {s} {s}\n", .{ try self.money(b.bound), try self.rateText(b.rate) });
        } else {
            const read_only = std.mem.eql(u8, op, "HOURS") or std.mem.eql(u8, op, "PREVIEW") or std.mem.eql(u8, op, "REPRINT") or std.mem.eql(u8, op, "YTD");
            const e = try self.employee(id, !read_only);
            if (std.mem.eql(u8, op, "RATE")) {
                const m = amount(a[2]);
                try self.amountCheck(m);
                const old = e.base;
                e.base = m;
                try self.out.print("RATE {s} {s} -> {s}\n", .{ id, try self.money(old), try self.money(m) });
            } else if (std.mem.eql(u8, op, "DEPT")) {
                if (std.mem.eql(u8, e.department, a[2])) return self.fail("same department {s}", .{a[2]});
                const old = e.department;
                e.department = a[2];
                try self.out.print("DEPT {s} {s} -> {s}\n", .{ id, old, a[2] });
            } else if (std.mem.eql(u8, op, "BENEFIT")) {
                try self.rateCheck(a[2]);
                e.retirement = amount(a[2]);
                e.health = amount(a[3]);
                try self.out.print("BENEFIT {s} retirement {s} health {s}\n", .{ id, try self.rateText(e.retirement), try self.money(e.health) });
            } else if (std.mem.eql(u8, op, "W4")) {
                e.allowances = integer(a[2]);
                e.extra = amount(a[3]);
                try self.out.print("W4 {s} allowances {d} extra {s}\n", .{ id, e.allowances, try self.money(e.extra) });
            } else if (std.mem.eql(u8, op, "GARNISH")) {
                try self.rateCheck(a[2]);
                const m = amount(a[3]);
                try self.amountCheck(m);
                const rate = amount(a[2]);
                try e.garnishments.append(self.gpa, .{ .rate = rate, .balance = m });
                try self.out.print("GARNISH {s} order {d} {s} balance {s}\n", .{ id, e.garnishments.items.len, try self.rateText(rate), try self.money(m) });
            } else if (std.mem.eql(u8, op, "TERM")) {
                e.active = false;
                try self.out.print("TERM {s}\n", .{id});
            } else if (std.mem.eql(u8, op, "TIME") or std.mem.eql(u8, op, "UNTIME") or std.mem.eql(u8, op, "PTO") or std.mem.eql(u8, op, "LEAVE") or std.mem.eql(u8, op, "SALES")) {
                try self.typeCheck(e, if (std.mem.eql(u8, op, "LEAVE")) .SALARIED else if (std.mem.eql(u8, op, "SALES")) .COMMISSION else .HOURLY);
                const d = try self.dayCheck(a[2]);
                if (std.mem.eql(u8, op, "TIME") or std.mem.eql(u8, op, "UNTIME")) {
                    const start = try self.timeCheck(a[3]);
                    const shifts = &e.days[d].shifts;
                    if (std.mem.eql(u8, op, "TIME")) {
                        const end = try self.timeCheck(a[4]);
                        if (start >= end) return self.fail("invalid shift {s}-{s}", .{ a[3], a[4] });
                        var worked: i64 = 0;
                        for (shifts.items) |s| {
                            if (start < s.end and s.start < end) return self.fail("overlapping shift {s}-{s}", .{ try self.clock(s.start), try self.clock(s.end) });
                            worked += s.end - s.start;
                        }
                        if (worked + end - start > 960) return self.fail("daily limit {s} {s}", .{ id, a[2] });
                        try shifts.append(self.gpa, .{ .start = start, .end = end });
                        std.mem.sort(Shift, shifts.items, {}, struct {
                            fn less(_: void, left: Shift, right: Shift) bool { return left.start < right.start; }
                        }.less);
                        try self.out.print("TIME {s} day {d} {s}-{s} {s}\n", .{ id, d, try self.clock(start), try self.clock(end), try self.duration(end - start) });
                    } else {
                        var found: ?usize = null;
                        for (shifts.items, 0..) |s, i| {
                            if (s.start == start) {
                                found = i;
                                break;
                            }
                        }
                        const index = found orelse return self.fail("no shift {s} {s} {s}", .{ id, a[2], a[3] });
                        const s = shifts.orderedRemove(index);
                        try self.out.print("UNTIME {s} day {d} {s}-{s}\n", .{ id, d, try self.clock(s.start), try self.clock(s.end) });
                    }
                } else if (std.mem.eql(u8, op, "PTO")) {
                    const mm = integer(a[3][3..5]);
                    const len = integer(a[3][0..2]) * 60 + mm;
                    if (mm > 59 or len < 1 or len > 480) return self.fail("invalid duration {s}", .{a[3]});
                    if (e.days[d].pto != null) return self.fail("duplicate pto {s} {s}", .{ id, a[2] });
                    if (len > e.pto) return self.fail("insufficient pto {s} {s}", .{ id, try self.duration(e.pto) });
                    e.days[d].pto = len;
                    e.pto -= len;
                    try self.out.print("PTO {s} day {d} {s} balance {s}\n", .{ id, d, try self.duration(len), try self.duration(e.pto) });
                } else if (std.mem.eql(u8, op, "LEAVE")) {
                    if (d % 7 == 0 or d % 7 == 6 or self.holidays[d]) return self.fail("not workday {s}", .{a[2]});
                    if (e.days[d].leave) return self.fail("duplicate leave {s} {s}", .{ id, a[2] });
                    e.days[d].leave = true;
                    try self.out.print("LEAVE {s} day {d} {s}\n", .{ id, d, weekday(d) });
                } else {
                    const m = amount(a[3]);
                    try self.amountCheck(m);
                    e.sales[period(d)] += m;
                    try self.out.print("SALES {s} day {d} {s} period {d} total {s}\n", .{ id, d, try self.money(m), period(d), try self.money(e.sales[period(d)]) });
                }
            } else if (std.mem.eql(u8, op, "BONUS")) {
                const m = amount(a[2]);
                try self.amountCheck(m);
                e.bonus += m;
                try self.out.print("BONUS {s} {s} pending {s}\n", .{ id, try self.money(m), try self.money(e.bonus) });
            } else if (std.mem.eql(u8, op, "HOURS")) {
                try self.typeCheck(e, .HOURLY);
                const p = try self.periodCheck(a[2]);
                try self.hours(e, p);
            } else if (std.mem.eql(u8, op, "PREVIEW")) {
                const p = self.closed + 1;
                try self.out.print("PREVIEW {s} period {d}\n", .{ id, p });
                if (self.calculate(e, p)) |s| {
                    try self.stub(e, &s, p, e.department);
                } else {
                    try self.out.writeAll("  no pay\n");
                }
            } else if (std.mem.eql(u8, op, "REPRINT")) {
                const p = try self.periodCheck(a[2]);
                const r = e.records[p] orelse return self.fail("no stub {s} {s}", .{ id, a[2] });
                try self.out.print("REPRINT {s} {d}\n", .{ id, p });
                try self.stub(e, &r.stub, p, r.department);
            } else if (std.mem.eql(u8, op, "YTD")) {
                try self.out.print("YTD {s} {s} {s} {s} periods {d}\n", .{ id, e.department, @tagName(e.kind), if (e.active) "active" else "terminated", e.stub_count });
                try self.block(e, &e.ytd, "  ", true);
                try self.out.print("  wages federal {s} social-security {s} medicare {s} unemployment {s}\n  retirement-room {s} pending-bonus {s}\n", .{ try self.money(e.ytd.get(.w)), try self.money(e.ytd.get(.y)), try self.money(e.ytd.get(.f)), try self.money(e.ytd.get(.j)), try self.money(@max(0, self.setting(.RETIRECAP) - e.ytd.get(.retirement))), try self.money(e.bonus) });
            }
        }
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var ob: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var payroll = Payroll{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var a: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |part| try a.append(gpa, part);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        payroll.out = &draft.writer;
        payroll.execute(a.items) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{payroll.error_message});
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
