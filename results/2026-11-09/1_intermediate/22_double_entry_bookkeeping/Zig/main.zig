const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const max_accounts = 200;
const last_day = 36524;

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn prefix(a: []const u8, b: []const u8) bool {
    return std.mem.startsWith(u8, b, a);
}
fn integer(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
fn magnitude(value: i64) i64 {
    return if (value < 0) -value else value;
}
fn cents(text: []const u8) i64 {
    return integer(text[0 .. text.len - 3]) * 100 + integer(text[text.len - 2 ..]);
}
fn money(value: i64) Money {
    return .{ .cents = value };
}
const Money = struct {
    cents: i64,
    pub fn format(value: Money, out: *std.Io.Writer) std.Io.Writer.Error!void {
        const absolute = @abs(value.cents);
        try out.print("{s}{d}.{d:0>2}", .{ if (value.cents < 0) "-" else "", absolute / 100, absolute % 100 });
    }
};
const Date = struct {
    year: i64,
    month: i64,
    day: i64,
    fn monthDays(year: i64, month: i64) i64 {
        const lengths = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        const leap = @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
        return lengths[@intCast(month - 1)] + @as(i64, if (month == 2 and leap) 1 else 0);
    }
    fn parse(text: []const u8) ?Date {
        const result: Date = .{ .year = integer(text[0..4]), .month = integer(text[5..7]), .day = integer(text[8..]) };
        if (result.year < 2000 or result.year > 2099 or result.month < 1 or result.month > 12 or result.day < 1) return null;
        if (result.day > monthDays(result.year, result.month)) return null;
        return result;
    }
    fn number(date: Date) i64 {
        const prior = date.year - 1;
        var result = 365 * (date.year - 2000) + @divTrunc(prior, 4) - @divTrunc(1999, 4) - @divTrunc(prior, 100) + @divTrunc(1999, 100) + @divTrunc(prior, 400) - @divTrunc(1999, 400);
        var month: i64 = 1;
        while (month < date.month) : (month += 1) result += monthDays(date.year, month);
        return result + date.day - 1;
    }
    fn addMonths(date: Date, count: usize) Date {
        const offset = date.month - 1 + @as(i64, @intCast(count));
        const year = date.year + @divTrunc(offset, 12);
        const month = @mod(offset, 12) + 1;
        return .{ .year = year, .month = month, .day = @min(date.day, monthDays(year, month)) };
    }
    pub fn format(date: Date, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ date.year, date.month, date.day });
    }
};
const AccountType = enum {
    ASSET,
    LIABILITY,
    EQUITY,
    REVENUE,
    EXPENSE,
    CONTRA_ASSET,
    fn sign(kind: AccountType) i64 {
        return if (kind == .ASSET or kind == .EXPENSE) 1 else -1;
    }
    fn class(kind: AccountType) AccountType {
        return if (kind == .CONTRA_ASSET) .ASSET else kind;
    }
};
const Kind = enum { journal, recurring, reversal, closing, reopen, depreciation, interest, writeoff };
const Account = struct { code: []const u8, kind: AccountType, name: []const u8, active: bool = true };
const Line = struct {
    debit: bool,
    account: usize,
    amount: i64,
    partner: ?[]const u8 = null,
    fn difference(line: Line) i64 {
        return if (line.debit) line.amount else -line.amount;
    }
    fn side(line: Line) []const u8 {
        return if (line.debit) "DR" else "CR";
    }
};
const DraftLine = struct { debit: bool, code: []const u8, amount: i64, partner: ?[]const u8 };
const Entry = struct {
    id: []const u8,
    date: Date,
    kind: Kind,
    memo: []const u8,
    lines: []const Line,
    sequence: usize,
    reversed_by: ?[]const u8 = null,
    reverses: ?[]const u8 = null,
    fn amount(entry: Entry) i64 {
        var total: i64 = 0;
        for (entry.lines) |line| if (line.debit) {
            total += line.amount;
        };
        return total;
    }
};
const Template = struct { name: []const u8, memo: []const u8, lines: []const Line, uses: usize = 0 };
const Draft = struct {
    journal: bool,
    key: []const u8,
    date: ?[]const u8,
    memo: []const u8,
    lines: std.ArrayList(DraftLine) = .empty,
    fn kind(draft: Draft) []const u8 {
        return if (draft.journal) "journal" else "template";
    }
};
const Totals = struct {
    debit: i64 = 0,
    credit: i64 = 0,
    fn add(total: *Totals, line: Line) void {
        if (line.debit) total.debit += line.amount else total.credit += line.amount;
    }
    fn difference(total: Totals) i64 {
        return total.debit - total.credit;
    }
};
const AccountTotals = [max_accounts]Totals;
const AccountOrder = struct {
    items: [max_accounts]usize = undefined,
    len: usize = 0,
    fn append(order: *AccountOrder, item: usize) void {
        order.items[order.len] = item;
        order.len += 1;
    }
    fn slice(order: *const AccountOrder) []const usize {
        return order.items[0..order.len];
    }
};
const OpenItem = struct { entry: *const Entry, original: i64, remaining: i64 };
const Settlement = struct {
    partner: []const u8,
    items: std.ArrayList(OpenItem) = .empty,
    head: usize = 0,
    unapplied: i64 = 0,
    fn open(settlement: Settlement) []const OpenItem {
        return settlement.items.items[settlement.head..];
    }
};
const CloseRecord = struct { date: Date, entry: ?*Entry };
const Section = enum {
    REVENUE,
    EXPENSE,
    ASSETS,
    LIABILITIES,
    EQUITY,
    fn includes(section: Section, kind: AccountType) bool {
        return switch (section) {
            .REVENUE => kind == .REVENUE,
            .EXPENSE => kind == .EXPENSE,
            .ASSETS => kind == .ASSET or kind == .CONTRA_ASSET,
            .LIABILITIES => kind == .LIABILITY,
            .EQUITY => kind == .EQUITY,
        };
    }
    fn sign(section: Section) i64 {
        return if (section == .ASSETS or section == .EXPENSE) 1 else -1;
    }
};

const Books = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    accounts: [max_accounts]Account = undefined,
    account_count: usize = 0,
    account_codes: std.StringHashMapUnmanaged(usize) = .empty,
    entries: std.ArrayList(*Entry) = .empty,
    entry_ids: std.StringHashMapUnmanaged(*Entry) = .empty,
    templates: std.StringHashMapUnmanaged(*Template) = .empty,
    closes: std.ArrayList(CloseRecord) = .empty,
    draft: ?*Draft = null,
    close_count: usize = 0,
    depreciation_count: usize = 0,
    interest_count: usize = 0,
    writeoff_count: usize = 0,

    fn fail(books: *Books, comptime format: []const u8, args: anytype) Error {
        books.error_message = try std.fmt.allocPrint(books.gpa, format, args);
        return error.BadCommand;
    }
    fn date(books: *Books, token: []const u8) Error!Date {
        return Date.parse(token) orelse return books.fail("invalid date {s}", .{token});
    }
    fn account(books: *Books, code: []const u8) Error!usize {
        return books.account_codes.get(code) orelse return books.fail("unknown account {s}", .{code});
    }
    fn entry(books: *Books, id: []const u8) Error!*Entry {
        return books.entry_ids.get(id) orelse return books.fail("unknown entry {s}", .{id});
    }
    fn typedAccount(books: *Books, code: []const u8, kind: AccountType) Error!usize {
        const found = try books.account(code);
        if (books.accounts[found].kind != kind) return books.fail("wrong type {s} {s}", .{ code, @tagName(kind) });
        return found;
    }
    fn active(books: *Books, selected: []const usize) Error!void {
        for (selected) |i| if (!books.accounts[i].active) return books.fail("inactive account {s}", .{books.accounts[i].code});
    }
    fn activeLines(books: *Books, lines: []const Line) Error!void {
        for (lines) |line| try books.active(&.{line.account});
    }
    fn checkClosed(books: *Books, value: Date) Error!void {
        if (books.closes.items.len > 0 and value.number() <= books.closes.items[books.closes.items.len - 1].date.number())
            return books.fail("period closed {f}", .{value});
    }
    fn closedText(books: *Books) Allocator.Error![]const u8 {
        if (books.closes.items.len == 0) return "none";
        return std.fmt.allocPrint(books.gpa, "{f}", .{books.closes.items[books.closes.items.len - 1].date});
    }
    fn range(books: *Books, first: []const u8, last: []const u8) Error!struct { first: Date, last: Date } {
        const a = try books.date(first);
        const b = try books.date(last);
        if (a.number() > b.number()) return books.fail("invalid range {s} {s}", .{ first, last });
        return .{ .first = a, .last = b };
    }
    fn accountLess(books: *const Books, a: usize, b: usize) bool {
        return std.mem.lessThan(u8, books.accounts[a].code, books.accounts[b].code);
    }
    fn orderedAccounts(books: *const Books) AccountOrder {
        var result: AccountOrder = .{};
        for (0..books.account_count) |i| result.append(i);
        std.mem.sort(usize, result.items[0..result.len], books, accountLess);
        return result;
    }
    fn entryLess(_: void, a: *Entry, b: *Entry) bool {
        const first = a.date.number();
        const second = b.date.number();
        return if (first == second) a.sequence < b.sequence else first < second;
    }
    fn orderedEntries(books: *Books) Allocator.Error![]*Entry {
        const result = try books.gpa.dupe(*Entry, books.entries.items);
        std.mem.sort(*Entry, result, {}, entryLess);
        return result;
    }
    fn aggregate(books: *const Books, first: i64, last: i64, operating: bool) AccountTotals {
        var result: AccountTotals = @splat(.{});
        for (books.entries.items) |posted| {
            if (posted.date.number() < first or posted.date.number() > last or (operating and (posted.kind == .closing or posted.kind == .reopen))) continue;
            for (posted.lines) |line| result[line.account].add(line);
        }
        return result;
    }
    fn balance(books: *const Books, selected: usize, last: i64) i64 {
        var difference: i64 = 0;
        for (books.entries.items) |posted| {
            if (posted.date.number() > last) continue;
            for (posted.lines) |line| if (line.account == selected) {
                difference += line.difference();
            };
        }
        return difference * books.accounts[selected].kind.sign();
    }
    fn dailySum(books: *const Books, selected: usize, first: i64, last: i64) i64 {
        var total: i64 = 0;
        for (books.entries.items) |posted| {
            const day = posted.date.number();
            if (day > last) continue;
            var change: i64 = 0;
            for (posted.lines) |line| if (line.account == selected) {
                change += line.difference();
            };
            total += change * books.accounts[selected].kind.sign() * (last - @max(first, day) + 1);
        }
        return total;
    }
    fn parent(books: *const Books, selected: usize) ?usize {
        var found: ?usize = null;
        for (books.accounts[0..books.account_count], 0..) |other, i| {
            if (i == selected or !prefix(other.code, books.accounts[selected].code)) continue;
            if (found == null or other.code.len > books.accounts[found.?].code.len) found = i;
        }
        return found;
    }
    fn parentCode(books: *const Books, selected: usize) []const u8 {
        return if (books.parent(selected)) |i| books.accounts[i].code else "none";
    }
    fn top(books: *const Books, selected: usize) usize {
        var found = selected;
        for (books.accounts[0..books.account_count], 0..) |other, i|
            if (other.code.len < books.accounts[found].code.len and prefix(other.code, books.accounts[selected].code)) {
                found = i;
            };
        return found;
    }
    fn post(books: *Books, id: []const u8, value: Date, kind: Kind, memo: []const u8, lines: []const Line) Allocator.Error!*Entry {
        const posted = try books.gpa.create(Entry);
        posted.* = .{ .id = id, .date = value, .kind = kind, .memo = memo, .lines = try books.gpa.dupe(Line, lines), .sequence = books.entries.items.len + 1 };
        try books.entries.append(books.gpa, posted);
        try books.entry_ids.put(books.gpa, id, posted);
        return posted;
    }
    fn reverse(books: *Books, original: *Entry, value: Date, kind: Kind, memo: []const u8) Allocator.Error!*Entry {
        const lines = try books.gpa.dupe(Line, original.lines);
        for (lines) |*line| line.debit = !line.debit;
        const id = try std.fmt.allocPrint(books.gpa, "{s}-R", .{original.id});
        const posted = try books.post(id, value, kind, memo, lines);
        original.reversed_by = id;
        posted.reverses = original.id;
        return posted;
    }
    fn postText(books: *Books, posted: *const Entry, indent: usize) std.Io.Writer.Error!void {
        try books.out.splatByteAll(' ', indent);
        try books.out.print("POST {s} {f} lines {d} amount {f}\n", .{ posted.id, posted.date, posted.lines.len, money(posted.amount()) });
    }
    fn settlementLess(_: void, a: Settlement, b: Settlement) bool {
        return std.mem.lessThan(u8, a.partner, b.partner);
    }
    fn settlements(books: *Books, selected: usize, day: i64) Allocator.Error![]Settlement {
        var result: std.ArrayList(Settlement) = .empty;
        var partners: std.StringHashMapUnmanaged(usize) = .empty;
        for (try books.orderedEntries()) |posted| {
            if (posted.date.number() > day) continue;
            for (posted.lines) |line| {
                if (line.account != selected) continue;
                const partner = line.partner orelse continue;
                const index = partners.get(partner) orelse blk: {
                    const position = result.items.len;
                    try result.append(books.gpa, .{ .partner = partner });
                    try partners.put(books.gpa, partner, position);
                    break :blk position;
                };
                const settlement = &result.items[index];
                const signed = line.difference() * books.accounts[selected].kind.sign();
                if (signed > 0) {
                    const applied = @min(signed, settlement.unapplied);
                    settlement.unapplied -= applied;
                    if (signed > applied) try settlement.items.append(books.gpa, .{ .entry = posted, .original = signed, .remaining = signed - applied });
                } else {
                    var remaining = -signed;
                    while (remaining > 0 and settlement.head < settlement.items.items.len) {
                        const item = &settlement.items.items[settlement.head];
                        const applied = @min(remaining, item.remaining);
                        item.remaining -= applied;
                        remaining -= applied;
                        if (item.remaining == 0) settlement.head += 1;
                    }
                    settlement.unapplied += remaining;
                }
            }
        }
        std.mem.sort(Settlement, result.items, {}, settlementLess);
        return try result.toOwnedSlice(books.gpa);
    }
    fn section(books: *Books, heading: Section, totals: *const AccountTotals, earnings: ?i64) std.Io.Writer.Error!i64 {
        const order = books.orderedAccounts();
        var roots: [max_accounts]usize = undefined;
        for (order.slice()) |i| roots[i] = books.top(i);
        var total = earnings orelse 0;
        for (order.slice()) |i| if (heading.includes(books.accounts[i].kind)) {
            total += totals[i].difference() * heading.sign();
        };
        try books.out.print("  {s} {f}\n", .{ @tagName(heading), money(total) });
        for (order.slice()) |root| {
            if (roots[root] != root) continue;
            var group: i64 = 0;
            var visible = false;
            for (order.slice()) |i| {
                if (!heading.includes(books.accounts[i].kind) or roots[i] != root) continue;
                const value = totals[i].difference() * heading.sign();
                group += value;
                visible = visible or value != 0;
            }
            if (!visible) continue;
            try books.out.print("    {s} {s} {f}\n", .{ books.accounts[root].code, books.accounts[root].name, money(group) });
            for (order.slice()) |i| {
                if (!heading.includes(books.accounts[i].kind) or roots[i] != root) continue;
                const value = totals[i].difference() * heading.sign();
                if (value != 0) try books.out.print("      {s} {s} {f}\n", .{ books.accounts[i].code, books.accounts[i].name, money(value) });
            }
        }
        if (earnings) |value| try books.out.print("    current earnings {f}\n", .{money(value)});
        return total;
    }
    fn postDraft(books: *Books) Error!void {
        const block = books.draft orelse return books.fail("no open entry", .{});
        books.draft = null;
        var value: Date = undefined;
        if (block.journal) {
            if (books.entry_ids.contains(block.key)) return books.fail("duplicate entry {s}", .{block.key});
            value = try books.date(block.date.?);
            try books.checkClosed(value);
        } else if (books.templates.contains(block.key)) return books.fail("duplicate template {s}", .{block.key});
        if (block.lines.items.len < 2) return books.fail("too few lines {s}", .{block.key});
        const lines = try books.gpa.alloc(Line, block.lines.items.len);
        var totals: Totals = .{};
        for (block.lines.items, lines) |source, *line| {
            const selected = try books.account(source.code);
            if (block.journal) try books.active(&.{selected});
            if (source.amount == 0) return books.fail("zero amount {s}", .{source.code});
            line.* = .{ .debit = source.debit, .account = selected, .amount = source.amount, .partner = source.partner };
            totals.add(line.*);
        }
        if (totals.debit != totals.credit) return books.fail("unbalanced {s} debit {f} credit {f}", .{ block.key, money(totals.debit), money(totals.credit) });
        if (block.journal) {
            const posted = try books.post(block.key, value, .journal, block.memo, lines);
            try books.postText(posted, 0);
        } else {
            const template = try books.gpa.create(Template);
            template.* = .{ .name = block.key, .memo = block.memo, .lines = lines };
            try books.templates.put(books.gpa, block.key, template);
            try books.out.print("TEMPLATE {s} lines {d} amount {f}\n", .{ block.key, lines.len, money(totals.debit) });
        }
    }
    fn close(books: *Books, value: Date, code: []const u8) Error!void {
        try books.checkClosed(value);
        const equity = try books.typedAccount(code, .EQUITY);
        try books.active(&.{equity});
        const totals = books.aggregate(0, value.number(), false);
        const order = books.orderedAccounts();
        var targets: AccountOrder = .{};
        for (order.slice()) |i| if ((books.accounts[i].kind == .REVENUE or books.accounts[i].kind == .EXPENSE) and totals[i].difference() != 0) {
            targets.append(i);
        };
        try books.active(targets.slice());
        var lines: std.ArrayList(Line) = .empty;
        var income: i64 = 0;
        for (targets.slice()) |i| {
            const difference = totals[i].difference();
            try lines.append(books.gpa, .{ .debit = difference < 0, .account = i, .amount = magnitude(difference) });
            income -= difference;
        }
        if (income != 0) try lines.append(books.gpa, .{ .debit = income < 0, .account = equity, .amount = magnitude(income) });
        books.close_count += 1;
        var posted: ?*Entry = null;
        if (lines.items.len > 0) {
            const id = try std.fmt.allocPrint(books.gpa, "CLOSE-{d}", .{books.close_count});
            posted = try books.post(id, value, .closing, "closing", lines.items);
            try books.out.print("CLOSE {f} entry {s} lines {d} net income {f}\n", .{ value, id, lines.items.len, money(income) });
        } else try books.out.print("CLOSE {f} no entry\n", .{value});
        try books.closes.append(books.gpa, .{ .date = value, .entry = posted });
    }
    fn ledger(books: *Books, selected: usize, first: Date, last: Date) Error!void {
        const found = books.accounts[selected];
        var running = books.balance(selected, first.number() - 1);
        var totals: Totals = .{};
        try books.out.print("LEDGER {s} {s} {f} {f}\n  opening {f}\n", .{ found.code, found.name, first, last, money(running) });
        for (try books.orderedEntries()) |posted| {
            if (posted.date.number() < first.number() or posted.date.number() > last.number()) continue;
            for (posted.lines) |line| {
                if (line.account != selected) continue;
                running += line.difference() * found.kind.sign();
                totals.add(line);
                try books.out.print("  {f} {s} {s} {f} balance {f} {s}\n", .{ posted.date, posted.id, line.side(), money(line.amount), money(running), posted.memo });
            }
        }
        const days = last.number() - first.number() + 1;
        try books.out.print("  ending {f} debits {f} credits {f} days {d} average {f}\n", .{ money(running), money(totals.debit), money(totals.credit), days, money(@divTrunc(books.dailySum(selected, first.number(), last.number()), days)) });
    }
    fn agingLine(books: *Books, label: []const u8, values: [5]i64) std.Io.Writer.Error!void {
        const balance_value = values[0] + values[1] + values[2] + values[3] - values[4];
        try books.out.print("  {s} 0-30 {f} 31-60 {f} 61-90 {f} 91+ {f} unapplied {f} balance {f}\n", .{ label, money(values[0]), money(values[1]), money(values[2]), money(values[3]), money(values[4]), money(balance_value) });
    }
    const Command = enum {
        ACCOUNT,
        DEACTIVATE,
        JOURNAL,
        TEMPLATE,
        DR,
        CR,
        POST,
        DRAFT,
        REVERSE,
        RECUR,
        DEPRECIATE,
        INTEREST,
        WRITEOFF,
        CLOSE,
        REOPEN,
        LEDGER,
        ACTIVITY,
        TRIAL,
        INCOME,
        BALANCE,
        ROLLUP,
        AGING,
        ITEMS,
        ENTRY,
        DAYBOOK,
        ACCOUNTS,
        TEMPLATES,
        STATUS,
    };
    fn templateLess(_: void, a: *Template, b: *Template) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }
    fn execute(books: *Books, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]).?;
        switch (command) {
            .ACCOUNT => {
                const code = words[1];
                if (books.account_codes.contains(code)) return books.fail("duplicate account {s}", .{code});
                const kind = std.meta.stringToEnum(AccountType, words[2]).?;
                const order = books.orderedAccounts();
                for (order.slice()) |i| {
                    const other = books.accounts[i];
                    if ((prefix(code, other.code) or prefix(other.code, code)) and kind.class() != other.kind.class())
                        return books.fail("class mismatch {s} {s}", .{ code, other.code });
                }
                const selected = books.account_count;
                books.accounts[selected] = .{ .code = code, .kind = kind, .name = words[3] };
                books.account_count += 1;
                try books.account_codes.put(books.gpa, code, selected);
                try books.out.print("ACCOUNT {s} {s} {s} parent {s}\n", .{ code, @tagName(kind), words[3], books.parentCode(selected) });
            },
            .DEACTIVATE => {
                const selected = try books.account(words[1]);
                const found = &books.accounts[selected];
                if (!found.active) return books.fail("already inactive {s}", .{found.code});
                const current = books.balance(selected, last_day);
                if (current != 0) return books.fail("nonzero balance {s} {f}", .{ found.code, money(current) });
                found.active = false;
                try books.out.print("DEACTIVATE {s} {s}\n", .{ found.code, found.name });
            },
            .JOURNAL, .TEMPLATE => {
                if (books.draft) |previous| try books.out.print("DISCARD {s} lines {d}\n", .{ previous.key, previous.lines.items.len });
                const block = try books.gpa.create(Draft);
                block.* = .{ .journal = command == .JOURNAL, .key = words[1], .date = if (command == .JOURNAL) words[2] else null, .memo = if (command == .JOURNAL) words[3] else words[2] };
                books.draft = block;
            },
            .DR, .CR => {
                const block = books.draft orelse return books.fail("no open entry", .{});
                try block.lines.append(books.gpa, .{ .debit = command == .DR, .code = words[1], .amount = cents(words[2]), .partner = if (words.len == 4) words[3] else null });
            },
            .POST => try books.postDraft(),
            .DRAFT => {
                const block = books.draft orelse return books.fail("no open entry", .{});
                var totals: Totals = .{};
                for (block.lines.items) |line| if (line.debit) {
                    totals.debit += line.amount;
                } else {
                    totals.credit += line.amount;
                };
                try books.out.print("DRAFT {s} {s} lines {d} debit {f} credit {f} difference {f}\n", .{ block.kind(), block.key, block.lines.items.len, money(totals.debit), money(totals.credit), money(totals.difference()) });
            },
            .REVERSE => {
                const original = try books.entry(words[1]);
                if (original.kind == .reversal or original.kind == .closing or original.kind == .reopen) return books.fail("cannot reverse {s}", .{original.id});
                if (original.reversed_by != null) return books.fail("already reversed {s}", .{original.id});
                const value = try books.date(words[2]);
                if (value.number() < original.date.number()) return books.fail("reverse before entry {s} {f}", .{ original.id, original.date });
                try books.checkClosed(value);
                try books.activeLines(original.lines);
                const posted = try books.reverse(original, value, .reversal, original.memo);
                try books.out.print("REVERSE {s} entry {s} {f} amount {f}\n", .{ original.id, posted.id, value, money(posted.amount()) });
            },
            .RECUR => {
                const template = books.templates.get(words[1]) orelse return books.fail("unknown template {s}", .{words[1]});
                const value = try books.date(words[2]);
                const count: usize = @intCast(integer(words[3]));
                if (count == 0) return books.fail("invalid count", .{});
                try books.checkClosed(value);
                try books.activeLines(template.lines);
                try books.out.print("RECUR {s} count {d}\n", .{ template.name, count });
                for (0..count) |month| {
                    template.uses += 1;
                    const id = try std.fmt.allocPrint(books.gpa, "{s}-{d}", .{ template.name, template.uses });
                    const posted = try books.post(id, value.addMonths(month), .recurring, template.memo, template.lines);
                    try books.postText(posted, 2);
                }
            },
            .DEPRECIATE => {
                const value = try books.date(words[1]);
                try books.checkClosed(value);
                const asset = try books.typedAccount(words[2], .ASSET);
                const contra = try books.typedAccount(words[3], .CONTRA_ASSET);
                const expense = try books.typedAccount(words[4], .EXPENSE);
                try books.active(&.{ contra, expense });
                const cost = books.balance(asset, value.number());
                const accumulated = books.balance(contra, value.number());
                const amount = if (cost > 0) @min(@divTrunc(cost, integer(words[5])), cost - accumulated) else 0;
                if (amount <= 0) return books.fail("nothing to depreciate {s}", .{words[2]});
                books.depreciation_count += 1;
                const id = try std.fmt.allocPrint(books.gpa, "DEP-{d}", .{books.depreciation_count});
                _ = try books.post(id, value, .depreciation, "depreciation", &.{ .{ .debit = true, .account = expense, .amount = amount }, .{ .debit = false, .account = contra, .amount = amount } });
                try books.out.print("DEPRECIATE {s} entry {s} {f} amount {f} accumulated {f} book {f}\n", .{ words[2], id, value, money(amount), money(accumulated + amount), money(cost - accumulated - amount) });
            },
            .INTEREST => {
                const selected = try books.account(words[1]);
                const kind = books.accounts[selected].kind;
                if (kind != .ASSET and kind != .LIABILITY) return books.fail("not interest bearing {s}", .{words[1]});
                const offset = try books.typedAccount(words[2], if (kind == .ASSET) .REVENUE else .EXPENSE);
                const period = try books.range(words[3], words[4]);
                try books.checkClosed(period.last);
                try books.active(&.{ selected, offset });
                const sum = books.dailySum(selected, period.first.number(), period.last.number());
                const amount = @divTrunc(sum * integer(words[5]), 3650000);
                if (amount <= 0) return books.fail("no interest {s}", .{words[1]});
                const debit = if (kind == .ASSET) selected else offset;
                const credit = if (kind == .ASSET) offset else selected;
                books.interest_count += 1;
                const id = try std.fmt.allocPrint(books.gpa, "INT-{d}", .{books.interest_count});
                _ = try books.post(id, period.last, .interest, "interest", &.{ .{ .debit = true, .account = debit, .amount = amount }, .{ .debit = false, .account = credit, .amount = amount } });
                const days = period.last.number() - period.first.number() + 1;
                try books.out.print("INTEREST {s} entry {s} {f} days {d} average {f} amount {f}\n", .{ words[1], id, period.last, days, money(@divTrunc(sum, days)), money(amount) });
            },
            .WRITEOFF => {
                const value = try books.date(words[1]);
                try books.checkClosed(value);
                const selected = try books.typedAccount(words[2], .ASSET);
                const expense = try books.typedAccount(words[3], .EXPENSE);
                try books.active(&.{ selected, expense });
                const age = integer(words[4]);
                var targets: std.ArrayList(struct { partner: []const u8, amount: i64 }) = .empty;
                var total: i64 = 0;
                for (try books.settlements(selected, value.number())) |settlement| {
                    var amount: i64 = 0;
                    for (settlement.open()) |item| if (value.number() - item.entry.date.number() > age) {
                        amount += item.remaining;
                    };
                    if (amount > 0) {
                        try targets.append(books.gpa, .{ .partner = settlement.partner, .amount = amount });
                        total += amount;
                    }
                }
                if (total == 0) return books.fail("nothing to write off {s}", .{words[2]});
                var lines: std.ArrayList(Line) = .empty;
                try lines.append(books.gpa, .{ .debit = true, .account = expense, .amount = total });
                for (targets.items) |target| try lines.append(books.gpa, .{ .debit = false, .account = selected, .amount = target.amount, .partner = target.partner });
                books.writeoff_count += 1;
                const id = try std.fmt.allocPrint(books.gpa, "WO-{d}", .{books.writeoff_count});
                _ = try books.post(id, value, .writeoff, "writeoff", lines.items);
                try books.out.print("WRITEOFF {s} entry {s} {f} partners {d} amount {f}\n", .{ words[2], id, value, targets.items.len, money(total) });
                for (targets.items) |target| try books.out.print("  {s} {f}\n", .{ target.partner, money(target.amount) });
            },
            .CLOSE => try books.close(try books.date(words[1]), words[2]),
            .REOPEN => {
                if (books.closes.items.len == 0) return books.fail("nothing to reopen", .{});
                const record = books.closes.items[books.closes.items.len - 1];
                var posted: ?*Entry = null;
                if (record.entry) |original| {
                    try books.activeLines(original.lines);
                    posted = try books.reverse(original, record.date, .reopen, "reopen");
                }
                books.closes.items.len -= 1;
                try books.out.print("REOPEN {f} ", .{record.date});
                if (posted) |created| try books.out.print("entry {s}", .{created.id}) else try books.out.writeAll("no entry");
                try books.out.print(" closed {s}\n", .{try books.closedText()});
            },
            .LEDGER => {
                const selected = try books.account(words[1]);
                const period = try books.range(words[2], words[3]);
                try books.ledger(selected, period.first, period.last);
            },
            .ACTIVITY => {
                const selected = try books.account(words[1]);
                const year = integer(words[2]);
                const found = books.accounts[selected];
                var annual: Totals = .{};
                try books.out.print("ACTIVITY {s} {s} {d}\n", .{ found.code, found.name, year });
                var month: i64 = 1;
                while (month <= 12) : (month += 1) {
                    const first: Date = .{ .year = year, .month = month, .day = 1 };
                    const last: Date = .{ .year = year, .month = month, .day = Date.monthDays(year, month) };
                    const totals = books.aggregate(first.number(), last.number(), false)[selected];
                    annual.debit += totals.debit;
                    annual.credit += totals.credit;
                    try books.out.print("  {d:0>4}-{d:0>2} debit {f} credit {f} balance {f}\n", .{ year, month, money(totals.debit), money(totals.credit), money(books.balance(selected, last.number())) });
                }
                try books.out.print("  total debit {f} credit {f}\n", .{ money(annual.debit), money(annual.credit) });
            },
            .TRIAL => {
                const value = try books.date(words[1]);
                const totals = books.aggregate(0, value.number(), false);
                const order = books.orderedAccounts();
                var debit: i64 = 0;
                var credit: i64 = 0;
                try books.out.print("TRIAL {f}\n", .{value});
                for (order.slice()) |i| {
                    const difference = totals[i].difference();
                    if (difference == 0) continue;
                    if (difference > 0) debit += difference else credit -= difference;
                    try books.out.print("  {s} {s} {s} {f}\n", .{ books.accounts[i].code, books.accounts[i].name, if (difference > 0) "debit" else "credit", money(magnitude(difference)) });
                }
                try books.out.print("  total debit {f} credit {f}\n", .{ money(debit), money(credit) });
            },
            .INCOME => {
                const period = try books.range(words[1], words[2]);
                const totals = books.aggregate(period.first.number(), period.last.number(), true);
                try books.out.print("INCOME {f} {f}\n", .{ period.first, period.last });
                const revenue = try books.section(.REVENUE, &totals, null);
                const expense = try books.section(.EXPENSE, &totals, null);
                try books.out.print("  NET INCOME {f}\n", .{money(revenue - expense)});
            },
            .BALANCE => {
                const value = try books.date(words[1]);
                const totals = books.aggregate(0, value.number(), false);
                var earnings: i64 = 0;
                for (books.accounts[0..books.account_count], 0..) |found, i|
                    if (found.kind == .REVENUE or found.kind == .EXPENSE) {
                        earnings -= totals[i].difference();
                    };
                try books.out.print("BALANCE {f}\n", .{value});
                const assets = try books.section(.ASSETS, &totals, null);
                const liabilities = try books.section(.LIABILITIES, &totals, null);
                const equity = try books.section(.EQUITY, &totals, earnings);
                if (assets == liabilities + equity) try books.out.writeAll("  check ok\n") else try books.out.print("  check mismatch {f}\n", .{money(assets - liabilities - equity)});
            },
            .ROLLUP => {
                const value = try books.date(words[2]);
                const order = books.orderedAccounts();
                var targets: AccountOrder = .{};
                for (order.slice()) |i| if (prefix(words[1], books.accounts[i].code)) {
                    targets.append(i);
                };
                try books.out.print("ROLLUP {s} {f}\n", .{ words[1], value });
                if (targets.len == 0) {
                    try books.out.writeAll("  (none)\n");
                    return;
                }
                const totals = books.aggregate(0, value.number(), false);
                var debit: i64 = 0;
                var credit: i64 = 0;
                for (targets.slice()) |i| {
                    const found = books.accounts[i];
                    var depth: usize = 0;
                    var subtotal: i64 = 0;
                    for (targets.slice()) |other| {
                        if (i != other and prefix(books.accounts[other].code, found.code)) depth += 1;
                        if (prefix(found.code, books.accounts[other].code)) subtotal += totals[other].difference();
                    }
                    debit += totals[i].debit;
                    credit += totals[i].credit;
                    try books.out.splatByteAll(' ', 2 * (1 + depth));
                    try books.out.print("{s} {s} own {f} total {f}\n", .{ found.code, found.name, money(totals[i].difference() * found.kind.sign()), money(subtotal * found.kind.sign()) });
                }
                try books.out.print("  postings debit {f} credit {f}\n", .{ money(debit), money(credit) });
            },
            .AGING, .ITEMS => {
                const selected = try books.account(words[1]);
                const value = try books.date(words[words.len - 1]);
                const found = books.accounts[selected];
                const settlements_list = try books.settlements(selected, value.number());
                if (command == .ITEMS) {
                    try books.out.print("ITEMS {s} {s} {s} {f}\n", .{ found.code, found.name, words[2], value });
                    var settlement: Settlement = .{ .partner = words[2] };
                    for (settlements_list) |candidate| if (equal(candidate.partner, words[2])) {
                        settlement = candidate;
                        break;
                    };
                    var remaining: i64 = 0;
                    for (settlement.open()) |item| {
                        remaining += item.remaining;
                        try books.out.print("  {f} {s} amount {f} open {f} age {d}\n", .{ item.entry.date, item.entry.id, money(item.original), money(item.remaining), value.number() - item.entry.date.number() });
                    }
                    try books.out.print("  unapplied {f} balance {f}\n", .{ money(settlement.unapplied), money(remaining - settlement.unapplied) });
                } else {
                    try books.out.print("AGING {s} {s} {f}\n", .{ found.code, found.name, value });
                    var total: [5]i64 = @splat(0);
                    for (settlements_list) |settlement| {
                        if (settlement.open().len == 0 and settlement.unapplied == 0) continue;
                        var values: [5]i64 = @splat(0);
                        for (settlement.open()) |item| {
                            const age = value.number() - item.entry.date.number();
                            const bucket: usize = if (age <= 30) 0 else if (age <= 60) 1 else if (age <= 90) 2 else 3;
                            values[bucket] += item.remaining;
                        }
                        values[4] = settlement.unapplied;
                        for (0..5) |i| total[i] += values[i];
                        try books.agingLine(settlement.partner, values);
                    }
                    try books.agingLine("total", total);
                }
            },
            .ENTRY => {
                const posted = try books.entry(words[1]);
                try books.out.print("ENTRY {s} {f} {s} {s}\n", .{ posted.id, posted.date, @tagName(posted.kind), posted.memo });
                for (posted.lines) |line| {
                    const found = books.accounts[line.account];
                    try books.out.print("  {s} {s} {s} {f}", .{ line.side(), found.code, found.name, money(line.amount) });
                    if (line.partner) |partner| try books.out.print(" {s}", .{partner});
                    try books.out.writeAll("\n");
                }
                try books.out.print("  total {f}\n", .{money(posted.amount())});
                if (posted.reverses) |id| try books.out.print("  reverses {s}\n", .{id});
                if (posted.reversed_by) |id| try books.out.print("  reversed by {s}\n", .{id});
            },
            .DAYBOOK => {
                const period = try books.range(words[1], words[2]);
                try books.out.print("DAYBOOK {f} {f}\n", .{ period.first, period.last });
                var count: usize = 0;
                var amount: i64 = 0;
                for (try books.orderedEntries()) |posted| {
                    if (posted.date.number() < period.first.number() or posted.date.number() > period.last.number()) continue;
                    count += 1;
                    amount += posted.amount();
                    try books.out.print("  {f} {s} {s} {f} {s}\n", .{ posted.date, posted.id, @tagName(posted.kind), money(posted.amount()), posted.memo });
                }
                try books.out.print("  total entries {d} amount {f}\n", .{ count, money(amount) });
            },
            .ACCOUNTS => {
                const totals = books.aggregate(0, last_day, false);
                const order = books.orderedAccounts();
                try books.out.writeAll("ACCOUNTS\n");
                for (order.slice()) |i| {
                    const found = books.accounts[i];
                    try books.out.print("  {s} {s} {s} parent {s} balance {f} {s}\n", .{ found.code, @tagName(found.kind), found.name, books.parentCode(i), money(totals[i].difference() * found.kind.sign()), if (found.active) "active" else "inactive" });
                }
                if (order.len == 0) try books.out.writeAll("  (none)\n");
            },
            .TEMPLATES => {
                var selected: std.ArrayList(*Template) = .empty;
                var iterator = books.templates.valueIterator();
                while (iterator.next()) |value| try selected.append(books.gpa, value.*);
                std.mem.sort(*Template, selected.items, {}, templateLess);
                try books.out.writeAll("TEMPLATES\n");
                for (selected.items) |template| {
                    var totals: Totals = .{};
                    for (template.lines) |line| totals.add(line);
                    try books.out.print("  {s} {s} lines {d} amount {f} used {d}\n", .{ template.name, template.memo, template.lines.len, money(totals.debit), template.uses });
                }
                if (selected.items.len == 0) try books.out.writeAll("  (none)\n");
            },
            .STATUS => {
                var inactive: usize = 0;
                for (books.accounts[0..books.account_count]) |found| if (!found.active) {
                    inactive += 1;
                };
                try books.out.print("STATUS accounts {d} inactive {d} entries {d} templates {d} closed {s} open {s}\n", .{ books.account_count, inactive, books.entries.items.len, books.templates.count(), try books.closedText(), if (books.draft) |block| block.key else "none" });
            },
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
    const count: usize = @intCast(integer((try readWords(gpa, &input.interface))[0]));
    var books: Books = .{ .gpa = gpa, .out = &output.interface };
    for (0..count) |_| {
        const words = try readWords(gpa, &input.interface);
        var response: std.Io.Writer.Allocating = .init(gpa);
        defer response.deinit();
        books.out = &response.writer;
        books.execute(words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{books.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
