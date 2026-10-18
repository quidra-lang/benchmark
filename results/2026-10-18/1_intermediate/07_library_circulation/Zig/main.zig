const std = @import("std");

const Allocator = std.mem.Allocator;
const Error = error{ BadCommand } || Allocator.Error || std.Io.Writer.Error;
fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn less(a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn integer(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}

fn amount(text: []const u8) i64 {
    const dot = std.mem.findScalar(u8, text, '.').?;
    return integer(text[0..dot]) * 100 + integer(text[dot + 1..]);
}

fn money(gpa: Allocator, n: i64) Allocator.Error![]const u8 {
    const value: u64 = @intCast(n);
    return std.fmt.allocPrint(gpa, "{d}.{d:0>2}", .{ value / 100, value % 100 });
}

fn split(gpa: Allocator, text: []const u8) Allocator.Error![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, ' ');
    while (it.next()) |part|
        try result.append(gpa, part);
    return result.items;
}

fn join(gpa: Allocator, parts: []const []const u8) Allocator.Error![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    for (parts, 0..) |part, i| {
        if (i > 0)
            try result.append(gpa, ' ');
        try result.appendSlice(gpa, part);
    }
    return result.items;
}

fn lowercase(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    const result = try gpa.dupe(u8, text);
    for (result) |*ch|
        ch.* = std.ascii.toLower(ch.*);
    return result;
}

fn digit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

fn normalizeISBN(gpa: Allocator, token: []const u8) (error{InvalidISBN} || Allocator.Error)![]const u8 {
    var s: [17]u8 = undefined;
    var len: usize = 0;
    for (token) |ch| {
        if (ch != '-') {
            s[len] = ch;
            len += 1;
        }
    }
    if (len == 10) {
        for (s[0..9]) |ch| {
            if (!digit(ch))
                return error.InvalidISBN;
        }
        if (!digit(s[9]) and s[9] != 'X')
            return error.InvalidISBN;
        var total: i64 = 0;
        for (s[0..10], 0..) |ch, i|
            total += @as(i64, @intCast(10 - i)) * @as(i64, if (ch == 'X') 10 else
                ch - '0');
        if (@mod(total, 11) != 0)
            return error.InvalidISBN;
        const result = try gpa.alloc(u8, 13);
        @memcpy(result[0..3], "978");
        @memcpy(result[3..12], s[0..9]);
        var sum: usize = 0;
        for (result[0..12], 0..) |ch, i|
            sum += @as(usize, if (i % 2 == 0) 1 else
                3) * (ch - '0');
        result[12] = @as(u8, @intCast((10 - sum % 10) % 10)) + '0';
        return result;
    }
    if (len == 13 and (equal(s[0..3], "978") or equal(s[0..3], "979"))) {
        var sum: usize = 0;
        for (s[0..13], 0..) |ch, i| {
            if (!digit(ch))
                return error.InvalidISBN;
            sum += @as(usize, if (i % 2 == 0) 1 else 3) * (ch - '0');
        }
        if (sum % 10 == 0)
            return gpa.dupe(u8, s[0..13]);
    }
    return error.InvalidISBN;
}

const MemberType = enum {
    STUDENT,
    STAFF
};

const ChargeKind = enum {
    FINE,
    FEE,
    PRICE
};

const Charge = struct {
    day: i64,
    kind: ChargeKind,
    isbn: []const u8,
    value: i64,
    unpaid: i64
};

const Member = struct {
    id: []const u8,
    kind: MemberType,
    name: []const u8,
    items: std.ArrayList(Charge) = .empty,
    history: std.ArrayList([]const u8) = .empty,

    fn loanLimit(self: *const Member) usize {
        return if (self.kind == .STUDENT) 3 else 10;
    }

    fn period(self: *const Member) i64 {
        return if (self.kind == .STUDENT) 14 else 28;
    }

    fn rate(self: *const Member) i64 {
        return if (self.kind == .STUDENT) 25 else 10;
    }

    fn cap(self: *const Member) i64 {
        return if (self.kind == .STUDENT) 1000 else 2000;
    }

    fn reservationLimit(self: *const Member) usize {
        return if (self.kind == .STUDENT) 2 else 5;
    }

    fn fee(self: *const Member) i64 {
        return if (self.kind == .STUDENT) 50 else 100;
    }

    fn balance(self: *const Member) i64 {
        var total: i64 = 0;
        for (self.items.items) |item|
            total += item.unpaid;
        return total;
    }

    fn blocked(self: *const Member) bool {
        return self.balance() > 500;
    }
};

const CopyState = enum {
    AVAILABLE,
    LOANED,
    HOLD,
    LOST,
    WITHDRAWN
};

const Title = struct {
    isbn: []const u8,
    name: []const u8,
    folded: []const u8,
    price: i64,
    borrowed: usize = 0,
    copies: std.ArrayList(*Copy) = .empty,
    queue: std.ArrayList(*Member) = .empty,

    fn countState(self: *const Title, state: CopyState) usize {
        var count: usize = 0;
        for (self.copies.items) |c| {
            if (c.state == state)
                count += 1;
        }
        return count;
    }

    fn holdings(self: *const Title) usize {
        return self.countState(.AVAILABLE) + self.countState(.LOANED) + self.countState(.HOLD);
    }
};

const Copy = struct {
    title: *Title,
    number: usize,
    state: CopyState = .AVAILABLE,
    member: ?*Member = null,
    loan_day: i64 = 0,
    due: i64 = 0,
    renewals: usize = 0,
    expiry: i64 = 0,
};

const LoanEnd = struct {
    late: i64,
    fine: i64
};

fn queueIndex(t: *const Title, m: *Member) ?usize {
    for (t.queue.items, 0..) |other, i| {
        if (m == other)
            return i;
    }
    return null;
}

fn titleCopy(m: *Member, t: *Title, state: CopyState) ?*Copy {
    for (t.copies.items) |c| {
        if (c.state == state and c.member == m)
            return c;
    }
    return null;
}

const Library = struct {
    gpa: Allocator,
    day: i64 = 1,
    titles: std.ArrayList(*Title) = .empty,
    members: std.ArrayList(*Member) = .empty,
    closed: std.ArrayList(i64) = .empty,
    borrowed: usize = 0,
    returned: usize = 0,
    renewed: usize = 0,
    lost: usize = 0,
    charged: [3]i64 = .{ 0, 0, 0 },
    paid: i64 = 0,
    waived: i64 = 0,
    error_message: []const u8 = "",

    fn fail(self: *Library, message: []const u8) error{ BadCommand } {
        self.error_message = message;
        return error.BadCommand;
    }

    fn normalized(self: *Library, token: []const u8) Error![]const u8 {
        return normalizeISBN(self.gpa, token) catch |err| {
            if (err == error.InvalidISBN)
                return self.fail("invalid isbn");
            return err;
        };
    }

    fn findMember(self: *Library, id: []const u8) Error! * Member {
        for (self.members.items) |m| {
            if (equal(m.id, id))
                return m;
        }
        return self.fail("unknown member");
    }

    fn findTitle(self: *Library, token: []const u8) Error! * Title {
        const isbn = try self.normalized(token);
        for (self.titles.items) |t| {
            if (equal(t.isbn, isbn))
                return t;
        }
        return self.fail("unknown book");
    }

    fn titlesSorted(self: *const Library) Allocator.Error![] * Title {
        const result = try self.gpa.dupe(*Title, self.titles.items);
        for (1..@max(1, result.len)) |i| {
            const entry = result[i];
            var j = i;
            while (j > 0 and less(entry.isbn, result[j - 1].isbn)) {
                result[j] = result[j - 1];
                j -= 1;
            }
            result[j] = entry;
        }
        return result;
    }

    fn membersSorted(self: *const Library) Allocator.Error![] * Member {
        const result = try self.gpa.dupe(*Member, self.members.items);
        for (1..@max(1, result.len)) |i| {
            const entry = result[i];
            var j = i;
            while (j > 0 and less(entry.id, result[j - 1].id)) {
                result[j] = result[j - 1];
                j -= 1;
            }
            result[j] = entry;
        }
        return result;
    }

    fn copiesInState(self: *const Library, state: CopyState, owner: ?*Member) Allocator.Error![] * Copy {
        var result: std.ArrayList(*Copy) = .empty;
        for (self.titles.items) |t|
            for (t.copies.items) | c | {
                if (c.state == state and (owner == null or c.member == owner))
                    try result.append(self.gpa, c);
        };
        return result.items;
    }

    fn reservations(self: *const Library, m: *Member) usize {
        var count: usize = 0;
        for (self.titles.items) |t| {
            if (queueIndex(t, m) != null)
                count += 1;
            for (t.copies.items) |c| {
                if (c.state == .HOLD and c.member == m)
                    count += 1;
            }
        }
        return count;
    }

    fn isClosed(self: *const Library, d: i64) bool {
        for (self.closed.items) |other| {
            if (d == other)
                return true;
        }
        return false;
    }

    fn openDay(self: *const Library, d: i64) i64 {
        var current = d;
        while (self.isClosed(current))
            current += 1;
        return current;
    }

    fn daysLate(self: *const Library, c: *const Copy) i64 {
        return @max(0, self.day - c.due);
    }

    fn lateFine(self: *const Library, c: *const Copy) i64 {
        return @min(self.daysLate(c) * c.member.?.rate(), c.member.?.cap());
    }

    fn addCharge(self: *Library, m: *Member, t: *Title, kind: ChargeKind, value: i64) Allocator.Error!void {
        if (value == 0)
            return;
        try m.items.append(self.gpa, .{
            .day = self.day,
            .kind = kind,
            .isbn = t.isbn,
            .value = value,
            .unpaid = value
        });
        self.charged[@intFromEnum(kind)] += value;
    }

    fn release(self: *Library, c: *Copy, out: *std.Io.Writer) Error!void {
        if (c.title.queue.items.len == 0) {
            c.state = .AVAILABLE;
            c.member = null;
            return;
        }
        const m = c.title.queue.orderedRemove(0);
        c.state = .HOLD;
        c.member = m;
        c.expiry = self.openDay(self.day + 3);
        try out.print("HOLD {s} copy {d} {s} until {d}\n", .{ c.title.isbn, c.number, m.id, c.expiry });
    }

    fn endLoan(self: *Library, c: *Copy, result: []const u8) Error!LoanEnd {
        const m = c.member.?;
        const late = self.daysLate(c);
        const value = self.lateFine(c);
        try self.addCharge(m, c.title, .FINE, value);
        try m.history.append(self.gpa, try std.fmt.allocPrint(self.gpa, "{s} {s} copy {d} from {d} to {d} late {d} fine {s}",
            .{
            result,
            c.title.isbn,
            c.number,
            c.loan_day,
            self.day,
            late,
            try money(self.gpa, value)
        }));
        c.state = .AVAILABLE;
        c.member = null;
        return .{ .late = late, .fine = value };
    }

    fn processLoss(self: *Library, c: *Copy, heading: []const u8, out: *std.Io.Writer) Error!void {
        const m = c.member.?;
        const t = c.title;
        const result = try self.endLoan(c, "LOST");
        const last = m.history.items.len - 1;
        m.history.items[last] = try std.fmt.allocPrint(self.gpa, "{s} price {s}", .{ m.history.items[last],
            try money(self.gpa, t.price) });
        try self.addCharge(m, t, .PRICE, t.price);
        c.state = .LOST;
        self.lost += 1;
        try out.print("{s} {s} {s} copy {d} late {d} fine {s} price {s} balance {s}\n", .{
            heading,
            m.id,
            t.isbn,
            c.number,
            result.late,
            try money(self.gpa, result.fine),
            try money(self.gpa, t.price),
            try money(self.gpa, m.balance())
        });
        if (t.holdings() == 0) {
            for (t.queue.items) |member|
                try out.print("DROPPED {s} {s}\n", .{ t.isbn, member.id });
            t.queue.items.len = 0;
        }
    }

    fn renewalProblem(self: *const Library, c: *const Copy) ?[]const u8 {
        if (c.due < self.day)
            return "loan overdue";
        if (c.renewals == 2)
            return "renewal limit";
        if (c.title.queue.items.len > 0)
            return "title reserved";
        return null;
    }

    fn performRenew(self: *Library, c: *Copy, out: *std.Io.Writer) Error!void {
        c.due = self.openDay(self.day + c.member.?.period());
        c.renewals += 1;
        self.renewed += 1;
        try out.print("RENEW {s} {s} copy {d} due {d} renewals {d}\n", .{ c.member.?.id, c.title.isbn,
            c.number, c.due, c.renewals });
    }

    fn dueOrder(copies: [] * Copy, expiry: bool) void {
        for (1..@max(1, copies.len)) |i| {
            const entry = copies[i];
            var j = i;
            const x = if (expiry) entry.expiry else entry.due;
            while (j > 0) {
                const b = copies[j - 1];
                const y = if (expiry) b.expiry else b.due;
                if (!(x < y or (x == y and less(entry.title.isbn, b.title.isbn))))
                    break;
                copies[j] = b;
                j -= 1;
            }
            copies[j] = entry;
        }
    }

    fn execute(self: *Library, line: []const u8, out: *std.Io.Writer) Error!void {
        const a = try split(self.gpa, line);
        const op = a[0];
        if (equal(op, "DAY")) {
            const target = integer(a[1]);
            if (target <= self.day)
                return self.fail("invalid day");
            const ordered_titles = try self.titlesSorted();
            try out.print("DAY {d}\n", .{ target });
            while (self.day < target) {
                self.day += 1;
                var automatic: std.ArrayList(*Copy) = .empty;
                for (try self.copiesInState(.LOANED, null)) |c| {
                    if (c.due + 365 <= self.day)
                        try automatic.append(self.gpa, c);
                }
                for (1..@max(1, automatic.items.len)) |i| {
                    const entry = automatic.items[i];
                    var j = i;
                    while (j > 0) {
                        const b = automatic.items[j - 1];
                        if (!(less(entry.member.?.id, b.member.?.id) or (equal(entry.member.?.id, b.member.?.id) and less(entry.title.isbn,
                            b.title.isbn))))
                            break;
                        automatic.items[j] = b;
                        j -= 1;
                    }
                    automatic.items[j] = entry;
                }
                for (automatic.items) |c|
                    try self.processLoss(c, "AUTOLOST", out);
                // Snapshot expiry targets after automatic losses, before releasing any hold.
                var expired: std.ArrayList(*Copy) = .empty;
                for (ordered_titles) |t|
                    for (t.copies.items) | c | {
                        if (c.state == .HOLD and c.expiry < self.day)
                            try expired.append(self.gpa, c);
                };
                for (expired.items) |c| {
                    const m = c.member.?;
                    try self.addCharge(m, c.title, .FEE, m.fee());
                    try out.print("EXPIRED {s} copy {d} {s} fee {s}\n", .{ c.title.isbn, c.number, m.id, try money(self.gpa,
                        m.fee()) });
                    try self.release(c, out);
                }
            }
        } else if (equal(op, "CLOSED")) {
            const target = integer(a[1]);
            if (target <= self.day)
                return self.fail("invalid day");
            if (self.isClosed(target))
                return self.fail("already closed");
            try self.closed.append(self.gpa, target);
            try out.print("CLOSED {d}\n", .{ target });
            for (try self.titlesSorted()) |t|
                for (t.copies.items) | c | {
                    if (c.state == .LOANED and c.due == target) {
                        c.due = self.openDay(target);
                        try out.print("MOVED {s} copy {d} {s} due {d}\n", .{ t.isbn, c.number, c.member.?.id, c.due });
                    } else if (c.state == .HOLD and c.expiry == target) {
                        c.expiry = self.openDay(target);
                        try out.print("MOVED {s} copy {d} {s} until {d}\n", .{ t.isbn, c.number, c.member.?.id, c.expiry });
                    }
            };
        } else if (equal(op, "ADDBOOK")) {
            const isbn = try self.normalized(a[1]);
            const name = try join(self.gpa, a[4..]);
            var existing: ?*Title = null;
            for (self.titles.items) |t| {
                if (equal(t.isbn, isbn))
                    existing = t;
            }
            if (existing) |t| {
                if (!equal(t.name, name))
                    return self.fail("title mismatch");
            }
            const t = existing orelse blk: {
                const title = try self.gpa.create(Title);
                title.* = .{
                    .isbn = isbn,
                    .name = name,
                    .folded = try lowercase(self.gpa, name),
                    .price = amount(a[3])
                };
                try self.titles.append(self.gpa, title);
                break: blk title;
            };
            t.price = amount(a[3]);
            const count: usize = @intCast(integer(a[2]));
            const first = t.copies.items.len;
            for (0..count) |_| {
                const c = try self.gpa.create(Copy);
                c.* = .{ .title = t, .number = t.copies.items.len + 1 };
                try t.copies.append(self.gpa, c);
            }
            try out.print("ADDBOOK {s} added {d} total {d}\n", .{ isbn, count, t.holdings() });
            for (t.copies.items[first..]) |c|
                try self.release(c, out);
        } else if (equal(op, "ADDMEMBER")) {
            for (self.members.items) |m| {
                if (equal(m.id, a[1]))
                    return self.fail("duplicate member");
            }
            const kind = std.meta.stringToEnum(MemberType, a[2]) orelse return self.fail("unknown type");
            const m = try self.gpa.create(Member);
            m.* = .{ .id = a[1], .kind = kind, .name = try join(self.gpa, a[3..]) };
            try self.members.append(self.gpa, m);
            try out.print("ADDMEMBER {s} {s} loans {d} days {d}\n", .{ m.id, @tagName(m.kind), m.loanLimit(),
                m.period() });
        } else if (equal(op, "WITHDRAW")) {
            const t = try self.findTitle(a[1]);
            const n = integer(a[2]);
            if (n < 1 or n > @as(i64, @intCast(t.copies.items.len)))
                return self.fail("unknown copy");
            const c = t.copies.items[@intCast(n - 1)];
            if (c.state != .AVAILABLE)
                return self.fail("copy not available");
            c.state = .WITHDRAWN;
            try out.print("WITHDRAW {s} copy {d} total {d}\n", .{ t.isbn, n, t.holdings() });
        } else if (equal(op, "BORROW") or equal(op, "RETURN") or equal(op, "RENEW") or equal(op, "RESERVE") or equal(op,
            "CANCEL") or equal(op, "LOST")) {
            const m = try self.findMember(a[1]);
            const t = try self.findTitle(a[2]);
            const current = titleCopy(m, t, .LOANED);
            const held = titleCopy(m, t, .HOLD);
            if (equal(op, "BORROW")) {
                if (self.isClosed(self.day))
                    return self.fail("library closed");
                if (current != null)
                    return self.fail("already borrowed");
                if (m.blocked())
                    return self.fail("member blocked");
                const loans = try self.copiesInState(.LOANED, m);
                for (loans) |c| {
                    if (c.due < self.day)
                        return self.fail("overdue loans");
                }
                if (loans.len >= m.loanLimit())
                    return self.fail("loan limit");
                var selected = held;
                if (selected == null)
                    for (t.copies.items) | c | {
                        if (c.state == .AVAILABLE) {
                            selected = c;
                            break;
                        }
                };
                const c = selected orelse return self.fail(if (t.countState(.HOLD) > 0) "all copies on hold" else "no copy available");
                c.state = .LOANED;
                c.member = m;
                c.loan_day = self.day;
                c.due = self.openDay(self.day + m.period());
                c.renewals = 0;
                t.borrowed += 1;
                self.borrowed += 1;
                try out.print("BORROW {s} {s} copy {d} due {d}\n", .{ m.id, t.isbn, c.number, c.due });
            } else if (equal(op, "RETURN") or equal(op, "LOST")) {
                const c = current orelse return self.fail("not borrowed");
                if (equal(op, "LOST"))
                    try self.processLoss(c, "LOST", out) else {
                        const result = try self.endLoan(c, "RETURNED");
                        self.returned += 1;
                        try out.print("RETURN {s} {s} copy {d} late {d} fine {s} balance {s}\n", .{
                            m.id,
                            t.isbn,
                            c.number,
                            result.late,
                            try money(self.gpa, result.fine),
                            try money(self.gpa, m.balance())
                        });
                        try self.release(c, out);
                    }
            } else if (equal(op, "RENEW")) {
                const c = current orelse return self.fail("not borrowed");
                if (m.blocked())
                    return self.fail("member blocked");
                if (self.renewalProblem(c)) |reason|
                    return self.fail(reason);
                try self.performRenew(c, out);
            } else if (equal(op, "RESERVE")) {
                if (current != null)
                    return self.fail("already borrowed");
                if (queueIndex(t, m) != null or held != null)
                    return self.fail("already reserved");
                if (m.blocked())
                    return self.fail("member blocked");
                if (self.reservations(m) >= m.reservationLimit())
                    return self.fail("reservation limit");
                if (t.holdings() == 0)
                    return self.fail("no copies");
                if (t.countState(.AVAILABLE) > 0)
                    return self.fail("copy available");
                try t.queue.append(self.gpa, m);
                const p = t.queue.items.len;
                var due: std.ArrayList(i64) = .empty;
                for (t.copies.items) |c| {
                    if (c.state == .LOANED)
                        try due.append(self.gpa, c.due);
                }
                for (1..@max(1, due.items.len)) |i| {
                    const entry = due.items[i];
                    var j = i;
                    while (j > 0 and entry < due.items[j - 1]) {
                        due.items[j] = due.items[j - 1];
                        j -= 1;
                    }
                    due.items[j] = entry;
                }
                try out.print("RESERVE {s} {s} position {d} estimate ", .{ m.id, t.isbn, p });
                if (p <= due.items.len)
                    try out.print("{d}\n", .{ due.items[p - 1] }) else
                        try out.writeAll("none\n");
            } else {
                const queued = queueIndex(t, m);
                if (queued == null and held == null)
                    return self.fail("not reserved");
                if (queued) |i| {
                    _ = t.queue.orderedRemove(i);
                    try out.print("CANCEL {s} {s} queue\n", .{ m.id, t.isbn });
                } else {
                    const c = held.?;
                    try out.print("CANCEL {s} {s} hold copy {d}\n", .{ m.id, t.isbn, c.number });
                    try self.release(c, out);
                }
            }
        } else if (equal(op, "RENEWALL")) {
            const m = try self.findMember(a[1]);
            const loans = try self.copiesInState(.LOANED, m);
            if (loans.len == 0)
                return self.fail("no loans");
            if (m.blocked())
                return self.fail("member blocked");
            sortISBN(loans);
            var success: usize = 0;
            var skipped: usize = 0;
            for (loans) |c| {
                if (self.renewalProblem(c)) |reason| {
                    try out.print("SKIP {s} {s}\n", .{ c.title.isbn, reason });
                    skipped += 1;
                } else {
                    try self.performRenew(c, out);
                    success += 1;
                }
            }
            try out.print("RENEWALL {s} renewed {d} skipped {d}\n", .{ m.id, success, skipped });
        } else if (equal(op, "PAYFINE")) {
            const m = try self.findMember(a[1]);
            if (m.balance() == 0)
                return self.fail("no fines");
            const Applied = struct {
                item: usize,
                value: i64
            };
            var applied: std.ArrayList(Applied) = .empty;
            const total = amount(a[2]);
            var remaining = total;
            for (m.items.items, 0..) |*item, i| {
                if (remaining == 0)
                    break;
                const value = @min(item.unpaid, remaining);
                if (value == 0)
                    continue;
                item.unpaid -= value;
                remaining -= value;
                try applied.append(self.gpa, .{ .item = i, .value = value });
            }
            self.paid += total - remaining;
            try out.print("PAYFINE {s} paid {s} change {s} balance {s}\n", .{
                m.id,
                try money(self.gpa, total - remaining),
                try money(self.gpa, remaining),
                try money(self.gpa, m.balance())
            });
            for (applied.items) |entry| {
                const item = m.items.items[entry.item];
                try out.print("ITEM {d} {s} paid {s} remaining {s}\n", .{
                    entry.item + 1,
                    @tagName(item.kind),
                    try money(self.gpa, entry.value),
                    try money(self.gpa, item.unpaid)
                });
            }
        } else if (equal(op, "WAIVE")) {
            const m = try self.findMember(a[1]);
            const n = integer(a[2]);
            if (n < 1 or n > @as(i64, @intCast(m.items.items.len)))
                return self.fail("unknown item");
            const item = &m.items.items[@intCast(n - 1)];
            if (item.unpaid == 0)
                return self.fail("item settled");
            const value = item.unpaid;
            item.unpaid = 0;
            self.waived += value;
            try out.print("WAIVE {s} item {d} {s} amount {s} balance {s}\n", .{
                m.id,
                n,
                @tagName(item.kind),
                try money(self.gpa, value),
                try money(self.gpa, m.balance())
            });
        } else if (equal(op, "FINES")) {
            const m = try self.findMember(a[1]);
            var count: usize = 0;
            for (m.items.items) |item| {
                if (item.unpaid > 0)
                    count += 1;
            }
            try out.print("FINES {s} items {d} balance {s}\n", .{ m.id, count, try money(self.gpa, m.balance()) });
            for (m.items.items, 0..) |item, i| {
                if (item.unpaid > 0)
                    try out.print("{d} day {d} {s} {s} amount {s} remaining {s}\n", .{
                        i + 1,
                        item.day,
                        @tagName(item.kind),
                        item.isbn,
                        try money(self.gpa, item.value),
                        try money(self.gpa, item.unpaid)
                    });
            }
        } else if (equal(op, "SEARCH")) {
            const keyword = try lowercase(self.gpa, try join(self.gpa, a[1..]));
            var selected: std.ArrayList(*Title) = .empty;
            for (try self.titlesSorted()) |t| {
                if (std.mem.find(u8, t.folded, keyword) != null)
                    try selected.append(self.gpa, t);
            }
            for (1..@max(1, selected.items.len)) |i| {
                const entry = selected.items[i];
                var j = i;
                while (j > 0 and less(entry.folded, selected.items[j - 1].folded)) {
                    selected.items[j] = selected.items[j - 1];
                    j -= 1;
                }
                selected.items[j] = entry;
            }
            try out.print("SEARCH {d}\n", .{ selected.items.len });
            for (selected.items) |t|
                try out.print("{s} {d}/{d} {s}\n", .{ t.isbn, t.countState(.AVAILABLE), t.holdings(), t.name });
        } else if (equal(op, "OVERDUE")) {
            var copies: std.ArrayList(*Copy) = .empty;
            for (try self.copiesInState(.LOANED, null)) |c| {
                if (c.due < self.day)
                    try copies.append(self.gpa, c);
            }
            for (1..@max(1, copies.items.len)) |i| {
                const entry = copies.items[i];
                var j = i;
                while (j > 0) {
                    const b = copies.items[j - 1];
                    const before = entry.due < b.due or (entry.due == b.due and (less(entry.member.?.id, b.member.?.id) or (equal(entry.member.?.id,
                        b.member.?.id) and less(entry.title.isbn, b.title.isbn))));
                    if (!before)
                        break;
                    copies.items[j] = b;
                    j -= 1;
                }
                copies.items[j] = entry;
            }
            try out.print("OVERDUE {d}\n", .{ copies.items.len });
            for (copies.items) |c|
                try out.print("{s} {s} copy {d} due {d} late {d} fine {s}\n", .{
                    c.member.?.id,
                    c.title.isbn,
                    c.number,
                    c.due,
                    self.daysLate(c),
                    try money(self.gpa, self.lateFine(c))
                });
        } else if (equal(op, "NOTICES")) {
            var lines: std.ArrayList([]const u8) = .empty;
            for (try self.membersSorted()) |m| {
                const loans = try self.copiesInState(.LOANED, m);
                dueOrder(loans, false);
                for (loans) |c| {
                    if (c.due < self.day)
                        try lines.append(self.gpa, try std.fmt.allocPrint(self.gpa, "OVERDUE {s} {s} due {d}", .{ m.id,
                            c.title.isbn, c.due }));
                }
                for (loans) |c| {
                    if (c.due >= self.day and c.due <= self.day + 2)
                        try lines.append(self.gpa, try std.fmt.allocPrint(self.gpa, "DUESOON {s} {s} due {d}", .{ m.id,
                            c.title.isbn, c.due }));
                }
                const holds = try self.copiesInState(.HOLD, m);
                dueOrder(holds, true);
                for (holds) |c|
                    try lines.append(self.gpa, try std.fmt.allocPrint(self.gpa, "PICKUP {s} {s} until {d}", .{ m.id,
                        c.title.isbn, c.expiry }));
            }
            try out.print("NOTICES {d}\n", .{ lines.items.len });
            for (lines.items) |text|
                try out.print("{s}\n", .{ text });
        } else if (equal(op, "MEMBER") or equal(op, "MEMBERS")) {
            const single = equal(op, "MEMBER");
            const ms = if (single) try self.gpa.dupe(*Member, &.{ try self.findMember(a[1]) }) else try self.membersSorted();
            if (!single)
                try out.print("MEMBERS {d}\n", .{ ms.len });
            for (ms) |m| {
                const loans = try self.copiesInState(.LOANED, m);
                dueOrder(loans, false);
                const status: []const u8 = if (m.blocked()) "BLOCKED" else "OK";
                if (!single) {
                    try out.print("{s} {s} loans {d} reservations {d} balance {s} {s}\n", .{
                        m.id,
                        @tagName(m.kind),
                        loans.len,
                        self.reservations(m),
                        try money(self.gpa, m.balance()),
                        status
                    });
                    continue;
                }
                try out.print("MEMBER {s} {s} {s}\nSTATUS loans {d}/{d} reservations {d}/{d} balance {s} {s}\n",
                    .{
                    m.id,
                    @tagName(m.kind),
                    m.name,
                    loans.len,
                    m.loanLimit(),
                    self.reservations(m),
                    m.reservationLimit(),
                    try money(self.gpa, m.balance()),
                    status
                });
                for (loans) |c| {
                    try out.print("LOAN {s} copy {d} due {d} renewals {d}", .{ c.title.isbn, c.number, c.due, c.renewals });
                    if (c.due < self.day)
                        try out.print(" late {d} fine {s}", .{ self.daysLate(c), try money(self.gpa, self.lateFine(c)) });
                    try out.writeByte('\n');
                }
                const holds = try self.copiesInState(.HOLD, m);
                dueOrder(holds, true);
                for (holds) |c|
                    try out.print("HOLD {s} copy {d} until {d}\n", .{ c.title.isbn, c.number, c.expiry });
                for (try self.titlesSorted()) |t| {
                    if (queueIndex(t, m)) |i|
                        try out.print("QUEUE {s} position {d}\n", .{ t.isbn, i + 1 });
                }
            }
        } else if (equal(op, "BOOK")) {
            const t = try self.findTitle(a[1]);
            try out.print("BOOK {s} {s}\nPRICE {s} copies {d} borrowed {d}\n", .{
                t.isbn,
                t.name,
                try money(self.gpa, t.price),
                t.holdings(),
                t.borrowed
            });
            for (t.copies.items) |c| {
                try out.print("COPY {d} {s}", .{ c.number, @tagName(c.state) });
                if (c.state == .LOANED)
                    try out.print(" {s} due {d}", .{ c.member.?.id, c.due }) else if (c.state == .HOLD) try out.print(" {s} until {d}",
                        .{ c.member.?.id, c.expiry });
                try out.writeByte('\n');
            }
            try out.print("QUEUE {d}", .{ t.queue.items.len });
            for (t.queue.items) |m|
                try out.print(" {s}", .{ m.id });
            try out.writeByte('\n');
        } else if (equal(op, "INVENTORY")) {
            var counts = [_]usize{ 0, 0, 0, 0, 0 };
            for (self.titles.items) |t|
                for (t.copies.items) | c | {
                    counts[@intFromEnum(c.state)] += 1;
            };
            try out.print("INVENTORY titles {d} copies {d} available {d} loaned {d} hold {d} lost {d} withdrawn {d}\n",
                .{
                self.titles.items.len,
                counts[0] + counts[1] + counts[2],
                counts[0],
                counts[1],
                counts[2],
                counts[3],
                counts[4]
            });
            for (try self.titlesSorted()) |t|
                try out.print("{s} copies {d} available {d} loaned {d} hold {d} queue {d}\n", .{
                    t.isbn,
                    t.holdings(),
                    t.countState(.AVAILABLE),
                    t.countState(.LOANED),
                    t.countState(.HOLD),
                    t.queue.items.len
                });
        } else if (equal(op, "HISTORY")) {
            const m = try self.findMember(a[1]);
            try out.print("HISTORY {s} {d}\n", .{ m.id, m.history.items.len });
            for (m.history.items) |text|
                try out.print("{s}\n", .{ text });
        } else if (equal(op, "STATS")) {
            try out.print("STATS day {d} titles {d} members {d} closed {d}\n", .{
                self.day,
                self.titles.items.len,
                self.members.items.len,
                self.closed.items.len
            });
            try out.print("LOANS borrowed {d} returned {d} renewed {d} lost {d} active {d}\n", .{
                self.borrowed,
                self.returned,
                self.renewed,
                self.lost,
                (try self.copiesInState(.LOANED, null)).len
            });
            var outstanding: i64 = 0;
            for (self.members.items) |m|
                outstanding += m.balance();
            try out.print("MONEY fines {s} fees {s} charges {s} paid {s} waived {s} outstanding {s}\n", .{
                try money(self.gpa, self.charged[0]),
                try money(self.gpa, self.charged[1]),
                try money(self.gpa, self.charged[2]),
                try money(self.gpa, self.paid),
                try money(self.gpa, self.waived),
                try money(self.gpa, outstanding)
            });
            var top: std.ArrayList(*Title) = .empty;
            for (try self.titlesSorted()) |t| {
                if (t.borrowed > 0)
                    try top.append(self.gpa, t);
            }
            for (1..@max(1, top.items.len)) |i| {
                const entry = top.items[i];
                var j = i;
                while (j > 0 and entry.borrowed > top.items[j - 1].borrowed) {
                    top.items[j] = top.items[j - 1];
                    j -= 1;
                }
                top.items[j] = entry;
            }
            for (top.items[0..@min(3, top.items.len)], 0..) |t, i|
                try out.print("TOP {d} {s} {d} {s}\n", .{ i + 1, t.isbn, t.borrowed, t.name });
        }
    }
};

fn sortISBN(copies: [] * Copy) void {
    for (1..@max(1, copies.len)) |i| {
        const entry = copies[i];
        var j = i;
        while (j > 0 and less(entry.title.isbn, copies[j - 1].title.isbn)) {
            copies[j] = copies[j - 1];
            j -= 1;
        }
        copies[j] = entry;
    }
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var library = Library{ .gpa = gpa };
    const count: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..count) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        library.execute(line, &draft.writer) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{ library.error_message });
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
