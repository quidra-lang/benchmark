const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = error{BadCommand} || Allocator.Error || Writer.Error;
const Phase = enum { idle, insurance, play };
const Finish = enum { bust, surrender, charlie };
const Outcome = enum { blackjack, win, charlie, push, lose, bust, surrender };
const Action = enum { hit, stand, double, split, surrender };
const DoubleRule = enum { any, hard9, hard10 };
const RuleName = enum { DEALER, PEN, MIN, MAX, BJ, DAS, DOUBLE, HANDS, RSA, SURRENDER, CHARLIE, SIDEMAX };
const Command = enum {
    SHOE, RULE, RULES, PLAYER, LEAVE, REBUY, BET, SIDE, DEAL, INSURANCE,
    HIT, STAND, DOUBLE, SPLIT, SURRENDER, HINT, AUTO, STATUS, COUNT, STATS,

    fn action(command: Command) ?Action {
        return switch (command) { .HIT => .hit, .STAND => .stand, .DOUBLE => .double, .SPLIT => .split, .SURRENDER => .surrender, else => null };
    }
    fn idleOnly(command: Command) bool {
        return switch (command) { .SHOE, .RULE, .PLAYER, .LEAVE, .REBUY, .BET, .SIDE, .DEAL => true, else => false };
    }
    fn namedPlayer(command: Command) bool {
        return command.action() != null or switch (command) { .LEAVE, .REBUY, .BET, .SIDE, .INSURANCE, .AUTO => true, else => false };
    }
    fn hasAmount(command: Command) bool {
        return switch (command) { .REBUY, .BET, .SIDE, .INSURANCE => true, else => false };
    }
};

fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
fn onOff(enabled: bool) []const u8 { return if (enabled) "ON" else "OFF"; }
const Signed = struct {
    value: i64,
    pub fn format(value: Signed, out: *Writer) Writer.Error!void {
        if (value.value >= 0) try out.writeByte('+');
        try out.print("{d}", .{value.value});
    }
};
fn signed(value: i64) Signed { return .{ .value = value }; }

const Name = struct {
    bytes: [8]u8 = @splat(0),
    len: usize = 0,
    fn init(text: []const u8) Name {
        var result: Name = .{ .len = text.len };
        @memcpy(result.bytes[0..text.len], text);
        return result;
    }
    fn matches(value: Name, text: []const u8) bool { return std.mem.eql(u8, value.bytes[0..value.len], text); }
    pub fn format(value: Name, out: *Writer) Writer.Error!void { try out.writeAll(value.bytes[0..value.len]); }
};
const HandName = struct {
    name: Name,
    index: usize,
    pub fn format(value: HandName, out: *Writer) Writer.Error!void { try out.print("{f}[{d}]", .{ value.name, value.index + 1 }); }
};

const Card = struct {
    code: u8,
    fn rank(card: Card) u8 { return card.code % 13; }
    fn suit(card: Card) u8 { return card.code / 13; }
    fn points(card: Card) i64 { return @min(card.rank() + 1, 10); }
    fn black(card: Card) bool { return card.suit() == 0 or card.suit() == 3; }
    pub fn format(card: Card, out: *Writer) Writer.Error!void {
        try out.print("{c}{c}", .{ "A23456789TJQK"[card.rank()], "CDHS"[card.suit()] });
    }
};
const Total = struct { value: i64, soft: bool };
const Hand = struct {
    cards: [22]Card = undefined,
    len: usize = 0,
    bet: i64 = 0,
    split: bool = false,
    split_aces: bool = false,
    finished: bool = false,
    reason: ?Finish = null,

    fn add(hand: *Hand, card: Card) void {
        hand.cards[hand.len] = card;
        hand.len += 1;
    }
    fn total(hand: *const Hand) Total {
        var sum: i64 = 0;
        var ace = false;
        for (hand.cards[0..hand.len]) |card| {
            sum += card.points();
            ace = ace or card.rank() == 0;
        }
        const soft = ace and sum + 10 <= 21;
        return .{ .value = sum + (if (soft) @as(i64, 10) else 0), .soft = soft };
    }
    fn natural(hand: *const Hand) bool { return !hand.split and hand.len == 2 and hand.total().value == 21; }
    pub fn format(hand: Hand, out: *Writer) Writer.Error!void {
        for (hand.cards[0..hand.len], 0..) |card, i| {
            if (i > 0) try out.writeByte(' ');
            try out.print("{f}", .{card});
        }
        try out.writeAll(" (");
        const t = hand.total();
        if (hand.natural()) try out.writeAll("blackjack") else {
            if (t.value > 21) try out.writeAll("bust ") else if (t.soft) try out.writeAll("soft ");
            try out.print("{d}", .{t.value});
        }
        try out.writeByte(')');
    }
};

const Rules = struct {
    hit_soft17: bool = false,
    penetration: usize = 75,
    minimum: i64 = 10,
    maximum: i64 = 500,
    six_to_five: bool = false,
    double_after_split: bool = true,
    doubling: DoubleRule = .any,
    hands: usize = 4,
    resplit_aces: bool = false,
    surrender: bool = true,
    charlie: usize = 0,
    side_maximum: i64 = 25,

    pub fn format(rules: Rules, out: *Writer) Writer.Error!void {
        const doubling: []const u8 = switch (rules.doubling) { .any => "ANY", .hard9 => "9-11", .hard10 => "10-11" };
        try out.print("rules DEALER {s} PEN {d} MIN {d} MAX {d} BJ {s} DAS {s} DOUBLE {s} HANDS {d} RSA {s} SURRENDER {s} CHARLIE {d} SIDEMAX {d}", .{
            if (rules.hit_soft17) "H17" else "S17", rules.penetration, rules.minimum, rules.maximum,
            if (rules.six_to_five) "6:5" else "3:2", onOff(rules.double_after_split), doubling, rules.hands,
            onOff(rules.resplit_aces), onOff(rules.surrender), rules.charlie, rules.side_maximum,
        });
    }
};
const Statistics = struct {
    rounds: u64 = 0,
    hands: u64 = 0,
    wins: u64 = 0,
    losses: u64 = 0,
    pushes: u64 = 0,
    blackjacks: u64 = 0,
    busts: u64 = 0,
    surrenders: u64 = 0,
    doubles: u64 = 0,
    splits: u64 = 0,
    pub fn format(stats: Statistics, out: *Writer) Writer.Error!void {
        try out.print("rounds {d} hands {d} wins {d} losses {d} pushes {d} blackjacks {d} busts {d} surrenders {d} doubles {d} splits {d}", .{
            stats.rounds, stats.hands, stats.wins, stats.losses, stats.pushes, stats.blackjacks, stats.busts, stats.surrenders, stats.doubles, stats.splits,
        });
    }
};
const Player = struct {
    name: Name,
    bankroll: i64,
    bet: i64 = 0,
    side: i64 = 0,
    insurance: i64 = 0,
    net: i64 = 0,
    stats: Statistics = .{},
    hands: [4]Hand = undefined,
    hand_count: usize = 0,
    fn label(player: *const Player, index: usize) HandName { return .{ .name = player.name, .index = index }; }
};
const Turn = struct { player: usize, hand: usize };

const Table = struct {
    rules: Rules = .{},
    seats: [7]?Player = @splat(null),
    participants: [7]usize = undefined,
    participant_count: usize = 0,
    phase: Phase = .idle,
    round: u64 = 0,
    dealer_blackjacks: u64 = 0,
    dealer_busts: u64 = 0,
    decks: usize = 0,
    drawn: usize = 0,
    running: i64 = 0,
    insurance_turn: usize = 0,
    random: u64 = 1,
    shoe: [416]Card = undefined,
    shoe_len: usize = 0,
    dealer: Hand = .{},
    hole_revealed: bool = false,

    fn player(table: *Table, seat: usize) *Player {
        if (table.seats[seat]) |*value| return value;
        unreachable;
    }
    fn owner(table: *const Table, seat: usize) *const Player {
        if (table.seats[seat]) |*value| return value;
        unreachable;
    }
    fn find(table: *const Table, text: []const u8) ?usize {
        for (table.seats, 0..) |slot, seat| if (slot) |value| {
            if (value.name.matches(text)) return seat;
        };
        return null;
    }
    fn cut(table: *const Table) usize { return table.shoe_len * table.rules.penetration / 100; }
    fn shuffle(table: *Table) void {
        table.shoe_len = 52 * table.decks;
        for (0..table.shoe_len) |i| table.shoe[i] = .{ .code = @intCast(i % 52) };
        var i = table.shoe_len - 1;
        while (i > 0) : (i -= 1) {
            table.random = table.random * 48271 % 2147483647;
            const j: usize = @intCast(table.random % (i + 1));
            if (i != j) std.mem.swap(Card, &table.shoe[i], &table.shoe[j]);
        }
        table.drawn = 0;
        table.running = 0;
    }
    fn countCard(table: *Table, card: Card) void {
        const value = card.points();
        table.running += if (value >= 2 and value <= 6) @as(i64, 1) else if (value == 1 or value == 10) -1 else 0;
    }
    fn draw(table: *Table, face_up: bool) Card {
        const card = table.shoe[table.drawn];
        table.drawn += 1;
        if (face_up) table.countCard(card);
        return card;
    }
    fn revealDealer(table: *Table, out: *Writer) Writer.Error!void {
        if (!table.hole_revealed) {
            table.countCard(table.dealer.cards[1]);
            table.hole_revealed = true;
        }
        try line(out, "dealer: {f}", .{table.dealer});
    }
    fn current(table: *const Table) ?Turn {
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.owner(seat);
            for (p.hands[0..p.hand_count], 0..) |hand, i| if (!hand.finished) return .{ .player = seat, .hand = i };
        }
        return null;
    }
    fn finishCheck(table: *const Table, p: *const Player, hand: *Hand) void {
        const value = hand.total().value;
        if (value > 21) {
            hand.reason = .bust;
            hand.finished = true;
        } else if (table.rules.charlie != 0 and hand.len == table.rules.charlie) {
            hand.reason = .charlie;
            hand.finished = true;
        } else if (value == 21) {
            hand.finished = true;
        } else if (hand.split_aces and hand.len == 2) {
            hand.finished = !(hand.cards[0].rank() == 0 and hand.cards[1].rank() == 0 and table.rules.resplit_aces and p.hand_count < table.rules.hands);
        }
    }
    fn settle(table: *Table, natural: bool, out: *Writer) Writer.Error!void {
        const dealer_total = table.dealer.total().value;
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.player(seat);
            for (p.hands[0..p.hand_count], 0..) |hand, i| {
                const value = hand.total().value;
                const result: Outcome = if (natural) (if (hand.natural()) .push else .lose)
                    else if (hand.natural()) .blackjack
                    else if (hand.reason) |reason| switch (reason) { .bust => .bust, .surrender => .surrender, .charlie => .charlie }
                    else if (dealer_total > 21 or value > dealer_total) .win else if (value == dealer_total) .push else .lose;
                const profit: i64 = switch (result) {
                    .blackjack => if (table.rules.six_to_five) @divTrunc(hand.bet * 6, 5) else @divTrunc(hand.bet * 3, 2),
                    .win, .charlie => hand.bet,
                    .push => 0,
                    .surrender => @divTrunc(hand.bet, 2) - hand.bet,
                    .lose, .bust => -hand.bet,
                };
                p.bankroll += hand.bet + profit;
                p.net += profit;
                p.stats.hands += 1;
                switch (result) {
                    .blackjack, .win, .charlie => p.stats.wins += 1,
                    .push => p.stats.pushes += 1,
                    else => p.stats.losses += 1,
                }
                if (result == .blackjack) p.stats.blackjacks += 1;
                if (result == .bust) p.stats.busts += 1;
                if (result == .surrender) p.stats.surrenders += 1;
                try line(out, "{f} {s} {f}", .{ p.label(i), @tagName(result), signed(profit) });
            }
            try line(out, "{f} bankroll {d}", .{ p.name, p.bankroll });
        }
        for (0..7) |seat| if (table.seats[seat] != null) {
            const p = table.player(seat);
            p.bet = 0;
            p.side = 0;
        };
        table.phase = .idle;
    }
    fn dealerTurn(table: *Table, out: *Writer) Writer.Error!void {
        try table.revealDealer(out);
        var required = false;
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.owner(seat);
            for (p.hands[0..p.hand_count]) |hand| required = required or (hand.reason == null and !hand.natural());
        }
        var drew = false;
        if (required) while (true) {
            const t = table.dealer.total();
            if (!(t.value <= 16 or t.value == 17 and t.soft and table.rules.hit_soft17)) break;
            table.dealer.add(table.draw(true));
            drew = true;
            try line(out, "dealer hits: {f}", .{table.dealer});
        };
        if (drew and table.dealer.total().value > 21) table.dealer_busts += 1;
        try table.settle(false, out);
    }
    fn advanceHands(table: *Table, out: *Writer) Writer.Error!void {
        while (table.current()) |turn| {
            const p = table.player(turn.player);
            const hand = &p.hands[turn.hand];
            if (hand.len != 1) return;
            hand.add(table.draw(true));
            try line(out, "{f}: {f}", .{ p.label(turn.hand), hand.* });
            table.finishCheck(p, hand);
            if (!hand.finished) return;
        }
        try table.dealerTurn(out);
    }
    fn peek(table: *Table, out: *Writer) Writer.Error!void {
        const natural = table.dealer.natural();
        try line(out, "dealer peeks: {s}", .{if (natural) "blackjack" else "no blackjack"});
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.player(seat);
            if (p.insurance == 0) continue;
            const profit = p.insurance * (if (natural) @as(i64, 2) else -1);
            p.bankroll += p.insurance + profit;
            p.net += profit;
            try line(out, "{f} insurance {f}", .{ p.name, signed(profit) });
        }
        if (natural) {
            table.dealer_blackjacks += 1;
            try table.revealDealer(out);
            try table.settle(true, out);
        } else {
            table.phase = .play;
            try table.advanceHands(out);
        }
    }
    fn deal(table: *Table, out: *Writer) Writer.Error!void {
        if (table.drawn >= table.cut()) {
            table.shuffle();
            try line(out, "shuffle", .{});
        }
        table.round += 1;
        try line(out, "round {d}", .{table.round});
        table.participant_count = 0;
        for (table.seats, 0..) |slot, seat| if (slot) |value| {
            if (value.bet != 0) {
                table.participants[table.participant_count] = seat;
                table.participant_count += 1;
            }
        };
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.player(seat);
            p.bankroll -= p.bet + p.side;
            p.insurance = 0;
            p.stats.rounds += 1;
            p.hand_count = 1;
            p.hands[0] = .{ .bet = p.bet };
            p.hands[0].add(table.draw(true));
        }
        table.dealer = .{};
        table.dealer.add(table.draw(true));
        for (table.participants[0..table.participant_count]) |seat| {
            const hand = &table.player(seat).hands[0];
            hand.add(table.draw(true));
            hand.finished = hand.natural();
        }
        table.dealer.add(table.draw(false));
        table.hole_revealed = false;
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.owner(seat);
            try line(out, "{f}: {f}", .{ p.label(0), p.hands[0] });
        }
        try line(out, "dealer: {f} ??", .{table.dealer.cards[0]});
        for (table.participants[0..table.participant_count]) |seat| {
            const p = table.player(seat);
            if (p.side == 0) continue;
            const first = p.hands[0].cards[0];
            const second = p.hands[0].cards[1];
            const result: []const u8 = if (first.rank() != second.rank()) "lose" else if (first.suit() == second.suit()) "perfect" else if (first.black() == second.black()) "colored" else "mixed";
            const multiplier: i64 = if (first.rank() != second.rank()) -1 else if (first.suit() == second.suit()) 25 else if (first.black() == second.black()) 12 else 6;
            const profit = p.side * multiplier;
            p.bankroll += p.side + profit;
            p.net += profit;
            try line(out, "{f} side {s} {f}", .{ p.name, result, signed(profit) });
        }
        const up = table.dealer.cards[0].points();
        if (up == 1) {
            table.phase = .insurance;
            table.insurance_turn = 0;
            try line(out, "insurance offered", .{});
        } else if (up == 10) try table.peek(out) else {
            table.phase = .play;
            try table.advanceHands(out);
        }
    }
    fn actionError(table: *const Table, action: Action, p: *const Player, hand: *const Hand) ?[]const u8 {
        switch (action) {
            .hit => if (hand.split_aces) return "split aces",
            .double => {
                if (hand.split_aces) return "split aces";
                if (hand.len != 2) return "two cards only";
                const t = hand.total();
                if (table.rules.doubling != .any and (t.soft or t.value < (if (table.rules.doubling == .hard9) @as(i64, 9) else 10) or t.value > 11)
                    or !table.rules.double_after_split and hand.split) return "double not allowed";
                if (p.bankroll < hand.bet) return "insufficient funds";
            },
            .split => {
                if (hand.len != 2) return "two cards only";
                if (hand.cards[0].points() != hand.cards[1].points()) return "not a pair";
                if (p.hand_count >= table.rules.hands) return "hand limit";
                if (p.bankroll < hand.bet) return "insufficient funds";
            },
            .surrender => {
                if (!table.rules.surrender or hand.split) return "surrender not allowed";
                if (hand.len != 2) return "two cards only";
            },
            .stand => {},
        }
        return null;
    }
    fn perform(table: *Table, action: Action, out: *Writer) Writer.Error!void {
        const turn = table.current().?;
        const p = table.player(turn.player);
        const label = p.label(turn.hand);
        if (action == .split) {
            const old = p.hands[turn.hand];
            const first = old.cards[0];
            const second = old.cards[1];
            const aces = old.split_aces or first.points() == 1;
            p.bankroll -= old.bet;
            p.stats.splits += 1;
            try line(out, "{f} splits {f} {f}", .{ label, first, second });
            var i = p.hand_count;
            while (i > turn.hand + 1) : (i -= 1) p.hands[i] = p.hands[i - 1];
            p.hand_count += 1;
            p.hands[turn.hand] = .{ .bet = old.bet, .split = true, .split_aces = aces };
            p.hands[turn.hand].add(first);
            p.hands[turn.hand + 1] = .{ .bet = old.bet, .split = true, .split_aces = aces };
            p.hands[turn.hand + 1].add(second);
            const hand = &p.hands[turn.hand];
            hand.add(table.draw(true));
            try line(out, "{f}: {f}", .{ label, hand.* });
            table.finishCheck(p, hand);
        } else {
            const hand = &p.hands[turn.hand];
            if (action == .stand or action == .surrender) {
                hand.finished = true;
                if (action == .surrender) hand.reason = .surrender;
                try line(out, "{f} {s}: {f}", .{ label, if (action == .stand) "stands" else "surrenders", hand.* });
            } else {
                if (action == .double) {
                    p.bankroll -= hand.bet;
                    hand.bet *= 2;
                    p.stats.doubles += 1;
                }
                hand.add(table.draw(true));
                try line(out, "{f} {s}: {f}", .{ label, if (action == .double) "doubles" else "hits", hand.* });
                table.finishCheck(p, hand);
                if (action == .double) hand.finished = true;
            }
        }
        try table.advanceHands(out);
    }
    fn recommend(table: *const Table) Action {
        const turn = table.current().?;
        const p = table.owner(turn.player);
        const hand = &p.hands[turn.hand];
        const up: i64 = if (table.dealer.cards[0].points() == 1) 11 else table.dealer.cards[0].points();
        const can_split = table.actionError(.split, p, hand) == null;
        if (hand.split_aces) return if (can_split) .split else .stand;
        if (hand.len == 2 and hand.cards[0].points() == hand.cards[1].points() and can_split) {
            const pair = hand.cards[0].points();
            if (pair == 1 or pair == 8 or pair == 9 and up != 7 and up != 10 and up != 11
                or (pair == 2 or pair == 3 or pair == 7) and up <= 7 or pair == 6 and up <= 6 or pair == 4 and (up == 5 or up == 6)) return .split;
        }
        const t = hand.total();
        const Symbol = enum { H, S, D, Ds, R };
        var symbol: Symbol = .H;
        if (t.soft) {
            if (t.value >= 19) symbol = .S else if (t.value == 18) {
                symbol = if (up >= 3 and up <= 6) .Ds else if (up == 2 or up == 7 or up == 8) .S else .H;
            } else if (t.value == 17 and up >= 3 and up <= 6
                or (t.value == 15 or t.value == 16) and up >= 4 and up <= 6
                or (t.value == 13 or t.value == 14) and (up == 5 or up == 6)) symbol = .D;
        } else {
            if (t.value >= 17) symbol = .S else if (t.value >= 13) {
                symbol = if (up <= 6) .S else if (t.value == 16 and up >= 9 or t.value == 15 and up == 10) .R else .H;
            } else if (t.value == 12) symbol = if (up >= 4 and up <= 6) .S else .H
            else if (t.value == 11 and up <= 10 or t.value == 10 and up <= 9 or t.value == 9 and up >= 3 and up <= 6) symbol = .D;
        }
        return switch (symbol) {
            .S => .stand,
            .H => .hit,
            .D => if (table.actionError(.double, p, hand) == null) .double else .hit,
            .Ds => if (table.actionError(.double, p, hand) == null) .double else .stand,
            .R => if (table.actionError(.surrender, p, hand) == null) .surrender else .hit,
        };
    }
    fn status(table: *const Table, out: *Writer) Writer.Error!void {
        try out.print("table {s} round {d}", .{ @tagName(table.phase), table.round });
        if (table.phase == .insurance) try out.print(" next {f}", .{table.owner(table.participants[table.insurance_turn]).name})
        else if (table.phase == .play) {
            const turn = table.current().?;
            try out.print(" turn {f}", .{table.owner(turn.player).label(turn.hand)});
        }
        try out.writeByte('\n');
        if (table.phase != .idle) try line(out, "dealer: {f} ??", .{table.dealer.cards[0]});
        for (table.seats, 0..) |slot, seat| if (slot) |p| {
            try line(out, "seat {d} {f} bankroll {d} bet {d} side {d}", .{ seat + 1, p.name, p.bankroll, p.bet, p.side });
            if (table.phase != .idle) for (table.participants[0..table.participant_count]) |participant| {
                if (participant == seat) {
                    for (p.hands[0..p.hand_count], 0..) |hand, i| try line(out, "{f}: {f} bet {d}", .{ p.label(i), hand, hand.bet });
                    break;
                }
            };
        };
    }
};

const Program = struct {
    table: Table = .{},
    scratch: Allocator,
    out: *Writer,
    error_message: []const u8 = "",

    fn fail(program: *Program, comptime fmt: []const u8, args: anytype) Error {
        program.error_message = std.fmt.allocPrint(program.scratch, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn integer(program: *Program, text: []const u8, minimum: i64, maximum: i64) Error!i64 {
        if (text.len < 1 or text.len > 10 or text.len > 1 and text[0] == '0') return program.fail("bad value {s}", .{text});
        var value: i64 = 0;
        for (text) |ch| {
            if (ch < '0' or ch > '9') return program.fail("bad value {s}", .{text});
            value = value * 10 + ch - '0';
        }
        if (value < minimum or value > maximum) return program.fail("bad value {s}", .{text});
        return value;
    }
    fn option(program: *Program, text: []const u8, choices: []const []const u8) Error!usize {
        for (choices, 0..) |word, i| if (std.mem.eql(u8, text, word)) return i;
        return program.fail("bad value {s}", .{text});
    }
    fn changedRules(program: *Program, name: []const u8, text: []const u8) Error!Rules {
        const rule = std.meta.stringToEnum(RuleName, name) orelse return program.fail("unknown rule {s}", .{name});
        var next = program.table.rules;
        switch (rule) {
            .DEALER => next.hit_soft17 = (try program.option(text, &.{ "S17", "H17" })) == 1,
            .PEN => next.penetration = @intCast(try program.integer(text, 50, 90)),
            .MIN => next.minimum = try program.integer(text, 1, 10000),
            .MAX => next.maximum = try program.integer(text, 1, 10000),
            .BJ => next.six_to_five = (try program.option(text, &.{ "3:2", "6:5" })) == 1,
            .DAS => next.double_after_split = (try program.option(text, &.{ "OFF", "ON" })) == 1,
            .DOUBLE => next.doubling = @enumFromInt(try program.option(text, &.{ "ANY", "9-11", "10-11" })),
            .HANDS => next.hands = @intCast(try program.integer(text, 1, 4)),
            .RSA => next.resplit_aces = (try program.option(text, &.{ "OFF", "ON" })) == 1,
            .SURRENDER => next.surrender = (try program.option(text, &.{ "OFF", "ON" })) == 1,
            .CHARLIE => {
                const choices = [_]usize{ 0, 5, 6, 7 };
                next.charlie = choices[try program.option(text, &.{ "0", "5", "6", "7" })];
            },
            .SIDEMAX => next.side_maximum = try program.integer(text, 0, 1000),
        }
        return next;
    }
    fn execute(program: *Program, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]) orelse return program.fail("unknown command {s}", .{words[0]});
        const first = if (words.len > 1) words[1] else "";
        const second = if (words.len > 2) words[2] else "";
        const table = &program.table;
        const out = program.out;
        const action = command.action();
        var target: ?usize = null;
        var value: i64 = 0;
        var seed: u64 = 0;
        var proposed = table.rules;

        if (command == .SHOE) {
            value = try program.integer(first, 1, 8);
            seed = @intCast(try program.integer(second, 1, 2147483646));
        } else if (command == .RULE) {
            proposed = try program.changedRules(first, second);
        } else if (command == .PLAYER) {
            if (first.len < 1 or first.len > 8) return program.fail("bad name {s}", .{first});
            for (first) |ch| if (ch < 'A' or ch > 'Z') return program.fail("bad name {s}", .{first});
            value = try program.integer(second, 1, 1000000);
        } else if (command.namedPlayer()) {
            target = table.find(first) orelse return program.fail("unknown player {s}", .{first});
            if (command.hasAmount()) value = try program.integer(second, if (command == .REBUY) 1 else 0, 1000000);
        }
        if (command.idleOnly()) {
            if (table.phase != .idle) return program.fail("round in progress", .{});
        } else if (command == .INSURANCE) {
            if (table.phase != .insurance) return program.fail("no insurance", .{});
        } else if (action != null or command == .AUTO or command == .HINT) {
            if (table.phase == .idle) return program.fail("no round", .{});
            if (table.phase == .insurance) return program.fail("insurance pending", .{});
        }
        if (action != null or command == .AUTO) {
            const turn = table.current().?;
            const p = table.owner(turn.player);
            if (turn.player != target.?) return program.fail("waiting for {f}", .{p.label(turn.hand)});
            if (action) |selected| {
                if (table.actionError(selected, p, &p.hands[turn.hand])) |problem| return program.fail("{s}", .{problem});
                try table.perform(selected, out);
            } else while (table.phase == .play and table.current().?.player == target.?) {
                try table.perform(table.recommend(), out);
            };
            return;
        }
        switch (command) {
            .SHOE => {
                table.decks = @intCast(value);
                table.random = seed;
                table.shuffle();
                try line(out, "shoe {d} decks {d} cards cut {d}", .{ table.decks, table.shoe_len, table.cut() });
            },
            .RULE => {
                if (proposed.minimum > proposed.maximum) return program.fail("min above max", .{});
                table.rules = proposed;
                try line(out, "rule {s} {s}", .{ first, second });
            },
            .RULES => try line(out, "{f}", .{table.rules}),
            .PLAYER => {
                if (table.find(first) != null) return program.fail("player exists", .{});
                var empty: ?usize = null;
                for (table.seats, 0..) |slot, seat| if (slot == null) { empty = seat; break; };
                const seat = empty orelse return program.fail("table full", .{});
                table.seats[seat] = .{ .name = Name.init(first), .bankroll = value };
                try line(out, "{f} sits at seat {d} with {d}", .{ table.owner(seat).name, seat + 1, value });
            },
            .LEAVE => {
                const p = table.owner(target.?);
                try line(out, "{f} leaves with {d} net {f}", .{ p.name, p.bankroll, signed(p.net) });
                table.seats[target.?] = null;
            },
            .REBUY => {
                const p = table.player(target.?);
                p.bankroll += value;
                try line(out, "{f} rebuys {d} bankroll {d}", .{ p.name, value, p.bankroll });
            },
            .BET => {
                const p = table.player(target.?);
                if (value != 0) {
                    if (value < table.rules.minimum or value > table.rules.maximum) return program.fail("bet out of limits", .{});
                    if (value + p.side > p.bankroll) return program.fail("insufficient funds", .{});
                }
                p.bet = value;
                if (value == 0) {
                    p.side = 0;
                    try line(out, "{f} bet cleared", .{p.name});
                } else try line(out, "{f} bets {d}", .{ p.name, value });
            },
            .SIDE => {
                const p = table.player(target.?);
                if (value != 0) {
                    if (p.bet == 0) return program.fail("no bet", .{});
                    if (value > table.rules.side_maximum) return program.fail("side out of limits", .{});
                    if (p.bet + value > p.bankroll) return program.fail("insufficient funds", .{});
                }
                p.side = value;
                if (value == 0) try line(out, "{f} side cleared", .{p.name}) else try line(out, "{f} side {d}", .{ p.name, value });
            },
            .DEAL => {
                if (table.decks == 0) return program.fail("no shoe", .{});
                var bets = false;
                for (table.seats) |slot| if (slot) |p| { bets = bets or p.bet != 0; };
                if (!bets) return program.fail("no bets", .{});
                try table.deal(out);
            },
            .INSURANCE => {
                const waiting = table.participants[table.insurance_turn];
                if (target.? != waiting) return program.fail("waiting for {f}", .{table.owner(waiting).name});
                const p = table.player(target.?);
                if (value > @divTrunc(p.bet, 2)) return program.fail("insurance out of limits", .{});
                if (value > p.bankroll) return program.fail("insufficient funds", .{});
                p.bankroll -= value;
                p.insurance = value;
                if (value == 0) try line(out, "{f} declines insurance", .{p.name}) else try line(out, "{f} insures {d}", .{ p.name, value });
                table.insurance_turn += 1;
                if (table.insurance_turn == table.participant_count) try table.peek(out);
            },
            .HINT => {
                const turn = table.current().?;
                try line(out, "hint {f}: {s}", .{ table.owner(turn.player).label(turn.hand), @tagName(table.recommend()) });
            },
            .STATUS => try table.status(out),
            .COUNT => {
                if (table.decks == 0) return program.fail("no shoe", .{});
                const remaining = table.shoe_len - table.drawn;
                const magnitude: u64 = @intCast(if (table.running < 0) -table.running else table.running);
                const hundredths = magnitude * 5200 / remaining;
                try line(out, "count running {d} true {s}{d}.{d:0>2} remaining {d}", .{ table.running, if (table.running < 0) "-" else "", hundredths / 100, hundredths % 100, remaining });
            },
            .STATS => {
                var any = false;
                for (table.seats) |slot| if (slot != null) { any = true; };
                if (!any) return program.fail("no players", .{});
                for (table.seats) |slot| if (slot) |p| try line(out, "stats {f} {f} net {f}", .{ p.name, p.stats, signed(p.net) });
                try line(out, "stats dealer rounds {d} blackjacks {d} busts {d}", .{ table.round, table.dealer_blackjacks, table.dealer_busts });
            },
            .HIT, .STAND, .DOUBLE, .SPLIT, .SURRENDER, .AUTO => unreachable,
        }
    }
};

fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeAny(u8, text, " \r");
    while (parts.next()) |word| try words.append(gpa, word);
    return try words.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var program: Program = .{ .scratch = scratch.allocator(), .out = &output.interface };
    const count = try std.fmt.parseInt(usize, (try readWords(scratch.allocator(), &input.interface))[0], 10);
    for (0..count) |_| {
        _ = scratch.reset(.retain_capacity);
        const words = try readWords(scratch.allocator(), &input.interface);
        var response: Writer.Allocating = .init(scratch.allocator());
        defer response.deinit();
        program.out = &response.writer;
        program.execute(words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("error: {s}\n", .{program.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
