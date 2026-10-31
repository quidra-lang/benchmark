const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};

const Card = u6;
const CardSet = u64;
const seat_names = "NESW";
const suit_names = "CDSH";
const rank_names = "23456789TJQKA";
const spade_suit: u6 = 2;
const heart_suit: u6 = 3;
const two_clubs: Card = 0;
const jack_diamonds: Card = 22;
const queen_spades: Card = 36;
const king_spades: Card = 37;
const ace_spades: Card = 38;
const all_cards: CardSet = (1 << 52) - 1;
const clubs_and_diamonds: CardSet = (1 << 26) - 1;
const heart_cards: CardSet = 0x1FFF << 39;
const penalty_cards: CardSet = heart_cards | bit(queen_spades);

const Strategy = enum { BASIC, LOW, HIGH, SMART, MOON };
const MoonMethod = enum { ADD, SUB, AUTO };
const State = enum { none, between, passing, playing };
const RuleName = enum { TARGET, LIMIT, MOON, JACK, QSBREAK, BLOOD, PASS };
const AutoMode = enum { PASS, CARD, TRICK, HAND, GAME };
const Command = enum {
    RULE,
    BOT,
    SETTINGS,
    GAME,
    MATCH,
    ROTATE,
    NEW,
    ABANDON,
    STACK,
    DEAL,
    SHOW,
    PASS,
    PLAY,
    AUTO,
    UNDO,
    CLAIM,
    LEGAL,
    PREVIEW,
    SCORE,
    TAKEN,
    TRICKS,
    VOIDS,
    UNSEEN,
    STATS,
    HISTORY,
    REPLAY,
};

fn bit(card: Card) CardSet {
    return @as(CardSet, 1) << card;
}

fn has(cards: CardSet, card: Card) bool {
    return cards & bit(card) != 0;
}

fn suitOf(card: Card) u6 {
    return card / 13;
}

fn rankOf(card: Card) u6 {
    return card % 13;
}

fn makeCard(suit: usize, rank: usize) Card {
    return @intCast(suit * 13 + rank);
}

fn suitSet(cards: CardSet, suit: u6) CardSet {
    return cards & (@as(CardSet, 0x1FFF) << suit * 13);
}

fn setOf(cards: []const Card) CardSet {
    var result: CardSet = 0;
    for (cards) |card| result |= bit(card);
    return result;
}

fn cardName(card: Card) [2]u8 {
    return .{ rank_names[rankOf(card)], suit_names[suitOf(card)] };
}

fn directionName(code: u8) []const u8 {
    return switch (code) {
        'L' => "LEFT",
        'R' => "RIGHT",
        'A' => "ACROSS",
        else => "HOLD",
    };
}

fn onOffText(value: bool) []const u8 {
    return if (value) "ON" else "OFF";
}

const CardIterator = struct {
    rest: CardSet,

    fn next(iterator: *CardIterator) ?Card {
        if (iterator.rest == 0) return null;
        const card: Card = @intCast(@ctz(iterator.rest));
        iterator.rest &= iterator.rest - 1;
        return card;
    }
};

fn each(cards: CardSet) CardIterator {
    return .{ .rest = cards };
}

const CardList = struct {
    cards: CardSet,

    pub fn format(list: CardList, out: *Writer) Writer.Error!void {
        if (list.cards == 0) return out.writeAll("-");
        var iterator = each(list.cards);
        var separator: []const u8 = "";
        while (iterator.next()) |card| {
            try out.print("{s}{s}", .{ separator, &cardName(card) });
            separator = " ";
        }
    }
};

fn cardList(cards: CardSet) CardList {
    return .{ .cards = cards };
}

fn rankOrder(cards: CardSet, descending: bool, buffer: *[52]Card) []Card {
    var count: usize = 0;
    for (0..13) |step| {
        const rank = if (descending) 12 - step else step;
        for (0..4) |suit| {
            const card = makeCard(suit, rank);
            if (has(cards, card)) {
                buffer[count] = card;
                count += 1;
            }
        }
    }
    return buffer[0..count];
}

fn lowest(cards: CardSet) Card {
    var buffer: [52]Card = undefined;
    return rankOrder(cards, false, &buffer)[0];
}

fn highest(cards: CardSet) Card {
    var buffer: [52]Card = undefined;
    return rankOrder(cards, true, &buffer)[0];
}

fn chooseSuit(cards: CardSet, most: bool) ?u6 {
    var best: ?u6 = null;
    var best_count: u7 = 0;
    for (0..4) |index| {
        const suit: u6 = @intCast(index);
        const count = @popCount(suitSet(cards, suit));
        if (count == 0) continue;
        if (best == null or (most and count > best_count) or (!most and count < best_count)) {
            best = suit;
            best_count = count;
        }
    }
    return best;
}

fn PerSeat(comptime spec: []const u8, comptime T: type) type {
    return struct {
        values: [4]T,

        pub fn format(pairs: @This(), out: *Writer) Writer.Error!void {
            for (pairs.values, seat_names, 0..) |value, name, seat| {
                if (seat > 0) try out.writeByte(' ');
                try out.print("{c} " ++ spec, .{ name, value });
            }
        }
    };
}

fn perSeat(comptime spec: []const u8, values: anytype) PerSeat(spec, @TypeOf(values[0])) {
    return .{ .values = values };
}

const SuitList = struct {
    suits: [4]bool = @splat(false),

    pub fn format(list: SuitList, out: *Writer) Writer.Error!void {
        var empty = true;
        for (list.suits, suit_names) |marked, name| {
            if (marked) {
                try out.writeByte(name);
                empty = false;
            }
        }
        if (empty) try out.writeByte('-');
    }
};

const Rules = struct {
    target: i32 = 100,
    limit: usize = 100,
    moon: MoonMethod = .ADD,
    jack: bool = false,
    qsbreak: bool = false,
    blood: bool = false,
    pass: []const u8 = "LRAH",

    fn point(rules: Rules, card: Card) i32 {
        if (card == queen_spades) return 13;
        if (suitOf(card) == heart_suit) return 1;
        return if (card == jack_diamonds and rules.jack) -10 else 0;
    }

    fn points(rules: Rules, cards: CardSet) i32 {
        var total: i32 = 0;
        var iterator = each(cards);
        while (iterator.next()) |card| total += rules.point(card);
        return total;
    }

    fn pointCards(rules: Rules) CardSet {
        return if (rules.jack) penalty_cards | bit(jack_diamonds) else penalty_cards;
    }

    pub fn format(rules: Rules, out: *Writer) Writer.Error!void {
        try out.print("TARGET {d} LIMIT {d} MOON {t}", .{ rules.target, rules.limit, rules.moon });
        try out.print(" JACK {s} QSBREAK {s} BLOOD {s} PASS {s}", .{
            onOffText(rules.jack),
            onOffText(rules.qsbreak),
            onOffText(rules.blood),
            rules.pass,
        });
    }
};

const Generator = struct {
    state: u64,

    fn draw(generator: *Generator) u64 {
        generator.state = 48271 * generator.state % 2147483647;
        return generator.state;
    }

    fn shuffle(generator: *Generator, deck: []Card) void {
        var i = deck.len;
        while (i > 1) {
            i -= 1;
            const j: usize = @intCast(generator.draw() % (i + 1));
            std.mem.swap(Card, &deck[i], &deck[j]);
        }
    }
};

const Stats = struct {
    tricks: usize = 0,
    hearts: usize = 0,
    queens: usize = 0,
    moons: usize = 0,

    fn add(stats: *Stats, other: Stats) void {
        stats.tricks += other.tricks;
        stats.hearts += other.hearts;
        stats.queens += other.queens;
        stats.moons += other.moons;
    }

    pub fn format(stats: Stats, out: *Writer) Writer.Error!void {
        try out.print("tricks {d} hearts {d} queens {d} moons {d}", .{
            stats.tricks, stats.hearts, stats.queens, stats.moons,
        });
    }
};

const Play = struct { seat: usize, card: Card };

const Trick = struct {
    plays: [4]Play = undefined,
    len: usize = 0,

    fn items(trick: *const Trick) []const Play {
        return trick.plays[0..trick.len];
    }

    fn ledSuit(trick: *const Trick) u6 {
        return suitOf(trick.plays[0].card);
    }

    fn cards(trick: *const Trick) CardSet {
        var result: CardSet = 0;
        for (trick.items()) |play| result |= bit(play.card);
        return result;
    }

    fn winner(trick: *const Trick) usize {
        var best = trick.plays[0];
        for (trick.items()[1..]) |play| {
            if (suitOf(play.card) == suitOf(best.card) and play.card > best.card) best = play;
        }
        return best.seat;
    }

    pub fn format(trick: Trick, out: *Writer) Writer.Error!void {
        for (trick.items(), 0..) |play, index| {
            if (index > 0) try out.writeByte(' ');
            try out.print("{c} {s}", .{ seat_names[play.seat], &cardName(play.card) });
        }
    }
};

const TrickLine = struct {
    trick: *const Trick,
    number: usize,
    rules: Rules,

    pub fn format(line: TrickLine, out: *Writer) Writer.Error!void {
        try out.print("trick {d}: {f} -> {c} {d}", .{
            line.number,
            line.trick.*,
            seat_names[line.trick.winner()],
            line.rules.points(line.trick.cards()),
        });
    }
};

fn markVoids(voids: *[4]SuitList, trick: *const Trick) void {
    for (trick.items()) |play| {
        if (suitOf(play.card) != trick.ledSuit()) voids[play.seat].suits[trick.ledSuit()] = true;
    }
}

const Round = struct {
    hands: [4]CardSet,
    taken: [4]CardSet = @splat(0),
    tricks: [13]Trick = undefined,
    completed: usize = 0,
    won: [4]usize = @splat(0),
    current: Trick = .{},
    leader: usize = 0,
    broken: bool = false,

    fn completedTricks(round: *const Round) []const Trick {
        return round.tricks[0..round.completed];
    }

    fn actor(round: *const Round) usize {
        return (round.leader + round.current.len) % 4;
    }

    fn queenPlayed(round: *const Round) bool {
        var played = round.current.cards();
        for (round.taken) |taken| played |= taken;
        return has(played, queen_spades);
    }

    fn legal(round: *const Round, rules: Rules) CardSet {
        const hand = round.hands[round.actor()];
        if (round.current.len == 0) {
            if (round.completed == 0) return bit(two_clubs);
            const non_hearts = hand & ~heart_cards;
            return if (!round.broken and non_hearts != 0) non_hearts else hand;
        }
        const followers = suitSet(hand, round.current.ledSuit());
        if (followers != 0) return followers;
        if (round.completed == 0 and !rules.blood) {
            const safe = hand & ~penalty_cards;
            if (safe != 0) return safe;
        }
        return hand;
    }

    fn choosePlay(round: *const Round, rules: Rules, bots: *const [4]Strategy) Card {
        const seat = round.actor();
        const hand = round.hands[seat];
        const playable = round.legal(rules);
        var strategy = bots[seat];
        if (strategy == .LOW) return lowest(playable);
        if (strategy == .HIGH) return highest(playable);
        if (strategy == .MOON) {
            for (round.taken, 0..) |taken, other| {
                if (other != seat and taken & penalty_cards != 0) strategy = .BASIC;
            }
        }
        if (round.current.len == 0) {
            if (strategy == .SMART and !round.queenPlayed() and !has(hand, queen_spades)) {
                const small_spades = suitSet(playable, spade_suit) & (bit(queen_spades) - 1);
                if (small_spades != 0) return lowest(small_spades);
            }
            if (strategy == .MOON) return highest(suitSet(playable, chooseSuit(playable, true).?));
            return lowest(suitSet(playable, chooseSuit(playable, false).?));
        }
        const led = round.current.ledSuit();
        if (suitSet(hand, led) != 0) {
            var winning: u6 = 0;
            for (round.current.items()) |play| {
                if (suitOf(play.card) == led) winning = @max(winning, rankOf(play.card));
            }
            if (strategy == .MOON) {
                const high = highest(playable);
                return if (rankOf(high) > winning) high else lowest(playable);
            }
            var lower: CardSet = 0;
            var iterator = each(playable);
            while (iterator.next()) |card| {
                if (rankOf(card) < winning) lower |= bit(card);
            }
            if (lower != 0) return highest(lower);
            if (strategy == .SMART and round.current.len == 3) {
                const others = playable & ~bit(queen_spades);
                return if (others != 0) highest(others) else queen_spades;
            }
            return lowest(playable);
        }
        if (strategy == .MOON) {
            const safe = playable & ~penalty_cards;
            return lowest(if (safe != 0) safe else playable);
        }
        if (has(playable, queen_spades)) return queen_spades;
        if (strategy == .SMART and !round.queenPlayed()) {
            if (has(playable, ace_spades)) return ace_spades;
            if (has(playable, king_spades)) return king_spades;
        }
        const heart_choices = playable & heart_cards;
        return highest(if (heart_choices != 0) heart_choices else playable);
    }

    fn add(round: *Round, rules: Rules, card: Card) void {
        const seat = round.actor();
        round.hands[seat] &= ~bit(card);
        round.current.plays[round.current.len] = .{ .seat = seat, .card = card };
        round.current.len += 1;
        if (suitOf(card) == heart_suit or (card == queen_spades and rules.qsbreak)) {
            round.broken = true;
        }
        if (round.current.len < 4) return;
        const winner = round.current.winner();
        round.taken[winner] |= round.current.cards();
        round.won[winner] += 1;
        round.tricks[round.completed] = round.current;
        round.completed += 1;
        round.current = .{};
        round.leader = winner;
    }
};

const PassChoice = struct {
    cards: CardSet = 0,
    count: usize = 0,

    fn add(choice: *PassChoice, card: Card) void {
        if (choice.count == 3 or has(choice.cards, card)) return;
        choice.cards |= bit(card);
        choice.count += 1;
    }

    fn addAll(choice: *PassChoice, cards: CardSet, descending: bool) void {
        var buffer: [52]Card = undefined;
        for (rankOrder(cards, descending, &buffer)) |card| choice.add(card);
    }

    fn addSpecial(choice: *PassChoice, hand: CardSet) void {
        for ([_]Card{ queen_spades, king_spades, ace_spades }) |card| {
            if (has(hand, card)) choice.add(card);
        }
    }
};

const LogLine = struct { level: u8, text: []const u8 };

const FinishedHand = struct {
    number: usize,
    direction: []const u8,
    points: [4]i32,
    shooter: ?usize,
    record: []const []const u8,
};

const Undo = struct { round: Round, log_len: usize, record_len: usize, seat: usize, card: Card };

fn scoreLess(scores: *const [4]i32, a: usize, b: usize) bool {
    return scores[a] < scores[b] or (scores[a] == scores[b] and a < b);
}

const Game = struct {
    gpa: Allocator,
    rules: Rules,
    bots: *const [4]Strategy,
    generator: *Generator,
    state: State = .between,
    number: usize = 0,
    scores: [4]i32 = @splat(0),
    stats: [4]Stats = @splat(.{}),
    stacked: [4]?CardSet = @splat(null),
    history: std.ArrayList(FinishedHand) = .empty,
    log: std.ArrayList(LogLine) = .empty,
    record: std.ArrayList([]const u8) = .empty,
    pass_code: u8 = 'H',
    passes: [4]?CardSet = @splat(null),
    round: Round = .{ .hands = @splat(0) },
    undo: std.ArrayList(Undo) = .empty,

    fn write(
        game: *Game,
        level: u8,
        comptime pattern: []const u8,
        args: anytype,
    ) Allocator.Error!void {
        const text = try std.fmt.allocPrint(game.gpa, pattern, args);
        try game.log.append(game.gpa, .{ .level = level, .text = text });
        if (level > 0) try game.record.append(game.gpa, text);
    }

    fn deal(game: *Game) Allocator.Error!void {
        game.number += 1;
        game.pass_code = game.rules.pass[(game.number - 1) % game.rules.pass.len];
        var hands: [4]CardSet = @splat(0);
        var used: CardSet = 0;
        var free: [4]usize = undefined;
        var free_count: usize = 0;
        for (game.stacked, 0..) |stacked, seat| {
            if (stacked) |cards| {
                hands[seat] = cards;
                used |= cards;
            } else {
                free[free_count] = seat;
                free_count += 1;
            }
        }
        var deck: [52]Card = undefined;
        var size: usize = 0;
        var remaining = each(all_cards & ~used);
        while (remaining.next()) |card| {
            deck[size] = card;
            size += 1;
        }
        game.generator.shuffle(deck[0..size]);
        for (deck[0..size], 0..) |card, index| hands[free[index % free_count]] |= bit(card);
        game.stacked = @splat(null);
        game.passes = @splat(null);
        game.round = .{ .hands = hands };
        game.undo.clearRetainingCapacity();
        game.record.clearRetainingCapacity();
        try game.write(1, "hand {d} pass {s}", .{ game.number, directionName(game.pass_code) });
        for (hands, seat_names) |cards, name| {
            try game.write(2, "{c}: {f}", .{ name, cardList(cards) });
        }
        if (game.pass_code == 'H') {
            try game.beginPlay();
        } else {
            game.state = .passing;
        }
    }

    fn beginPlay(game: *Game) Allocator.Error!void {
        game.state = .playing;
        for (game.round.hands, 0..) |hand, seat| {
            if (has(hand, two_clubs)) game.round.leader = seat;
        }
        try game.write(2, "lead {c}", .{seat_names[game.round.leader]});
    }

    fn passCards(game: *Game, seat: usize, cards: CardSet) Allocator.Error!void {
        game.round.hands[seat] &= ~cards;
        game.passes[seat] = cards;
        try game.write(2, "{c} passes {f}", .{ seat_names[seat], cardList(cards) });
        for (game.passes) |passed| if (passed == null) return;
        const offset: usize = switch (game.pass_code) {
            'L' => 1,
            'R' => 3,
            else => 2,
        };
        for (game.passes, 0..) |passed, source| game.round.hands[(source + offset) % 4] |= passed.?;
        try game.beginPlay();
    }

    fn choosePass(game: *const Game, seat: usize) CardSet {
        const hand = game.round.hands[seat];
        var choice: PassChoice = .{};
        switch (game.bots[seat]) {
            .LOW => choice.addAll(hand, true),
            .HIGH => choice.addAll(hand, false),
            .MOON => {
                choice.addAll(hand & ~heart_cards, false);
                choice.addAll(hand & heart_cards, false);
            },
            .SMART => {
                const spades = @popCount(suitSet(hand, spade_suit));
                const protected = has(hand, queen_spades) and spades >= 5;
                if (!protected) choice.addSpecial(hand);
                if (chooseSuit(hand & clubs_and_diamonds, false)) |suit| {
                    choice.addAll(suitSet(hand, suit), true);
                }
                choice.addAll(hand & heart_cards, true);
                choice.addAll(hand, true);
            },
            .BASIC => {
                choice.addSpecial(hand);
                choice.addAll(hand & heart_cards, true);
                choice.addAll(hand, true);
            },
        }
        return choice.cards;
    }

    fn choosePlay(game: *const Game) Card {
        return game.round.choosePlay(game.rules, game.bots);
    }

    fn play(game: *Game, card: Card) Allocator.Error!void {
        const round = &game.round;
        try game.undo.append(game.gpa, .{
            .round = round.*,
            .log_len = game.log.items.len,
            .record_len = game.record.items.len,
            .seat = round.actor(),
            .card = card,
        });
        round.add(game.rules, card);
        if (round.current.len > 0) return;
        const number = round.completed;
        try game.write(2, "{f}", .{game.trickLine(&round.tricks[number - 1], number)});
        if (number == 13) try game.finishHand();
    }

    fn trickLine(game: *const Game, trick: *const Trick, number: usize) TrickLine {
        return .{ .trick = trick, .number = number, .rules = game.rules };
    }

    fn undoCard(game: *Game) Undo {
        const last = game.undo.pop().?;
        game.round = last.round;
        game.log.shrinkRetainingCapacity(last.log_len);
        game.record.shrinkRetainingCapacity(last.record_len);
        return last;
    }

    fn claim(game: *Game, seat: usize) Allocator.Error!void {
        var remaining: CardSet = 0;
        for (game.round.hands) |hand| remaining |= hand;
        const count = 13 - game.round.completed;
        game.round.taken[seat] |= remaining;
        game.round.won[seat] += count;
        game.round.hands = @splat(0);
        const points = game.rules.points(remaining);
        try game.write(2, "claim {c} tricks {d} points {d}", .{ seat_names[seat], count, points });
        try game.finishHand();
    }

    fn ended(game: *const Game, scores: [4]i32) bool {
        return game.number >= game.rules.limit or std.mem.max(i32, &scores) >= game.rules.target;
    }

    fn finishHand(game: *Game) Allocator.Error!void {
        var points: [4]i32 = undefined;
        var shooter: ?usize = null;
        for (game.round.taken, 0..) |taken, seat| {
            points[seat] = game.rules.points(taken);
            if (taken & penalty_cards == penalty_cards) shooter = seat;
        }
        if (shooter) |moon| {
            points[moon] -= 26;
            var method = game.rules.moon;
            if (method == .AUTO) {
                var added = game.scores;
                for (&added, points, 0..) |*total, hand_points, seat| {
                    total.* += hand_points;
                    if (seat != moon) total.* += 26;
                }
                var winner: usize = 0;
                for (added, 0..) |total, seat| {
                    if (total < added[winner]) winner = seat;
                }
                method = if (game.ended(added) and winner != moon) .SUB else .ADD;
            }
            if (method == .SUB) {
                points[moon] -= 26;
            } else {
                for (&points, 0..) |*value, seat| {
                    if (seat != moon) value.* += 26;
                }
            }
            try game.write(1, "moon {c} {t}", .{ seat_names[moon], method });
            game.stats[moon].moons += 1;
        }
        for (0..4) |seat| {
            const taken = game.round.taken[seat];
            game.scores[seat] += points[seat];
            game.stats[seat].tricks += game.round.won[seat];
            game.stats[seat].hearts += @popCount(taken & heart_cards);
            if (has(taken, queen_spades)) game.stats[seat].queens += 1;
        }
        try game.write(1, "points {f}", .{perSeat("{d}", points)});
        try game.write(1, "scores {f}", .{perSeat("{d}", game.scores)});
        try game.history.append(game.gpa, .{
            .number = game.number,
            .direction = directionName(game.pass_code),
            .points = points,
            .shooter = shooter,
            .record = try game.gpa.dupe([]const u8, game.record.items),
        });
        const over = game.ended(game.scores);
        game.state = if (over) .none else .between;
        if (!over) return;
        try game.write(0, "game over hands {d}", .{game.number});
        const order = game.ranking();
        for (order, 1..) |seat, rank| {
            try game.write(0, "rank {d} {c} {d}", .{ rank, seat_names[seat], game.scores[seat] });
        }
        for (game.stats, seat_names) |stats, name| {
            try game.write(0, "stats {c} {f}", .{ name, stats });
        }
    }

    fn ranking(game: *const Game) [4]usize {
        var order: [4]usize = .{ 0, 1, 2, 3 };
        std.mem.sort(usize, &order, &game.scores, scoreLess);
        return order;
    }

    fn autoPass(game: *Game) Allocator.Error!void {
        for (0..4) |seat| {
            if (game.passes[seat] == null) try game.passCards(seat, game.choosePass(seat));
        }
    }

    fn autoHand(game: *Game) Allocator.Error!void {
        if (game.state == .passing) try game.autoPass();
        while (game.state == .playing) try game.play(game.choosePlay());
    }

    fn autoGame(game: *Game) Allocator.Error!void {
        if (game.state == .passing or game.state == .playing) try game.autoHand();
        while (game.state != .none) {
            try game.deal();
            try game.autoHand();
        }
    }
};

const Table = struct {
    gpa: Allocator,
    rules: Rules = .{},
    bots: [4]Strategy = @splat(.BASIC),
    generator: Generator = .{ .state = 1 },
    game: ?Game = null,
    problem: []const u8 = "",

    fn fail(table: *Table, comptime pattern: []const u8, args: anytype) Error {
        table.problem = std.fmt.allocPrint(table.gpa, pattern, args) catch return error.OutOfMemory;
        return error.Invalid;
    }

    fn badValue(table: *Table, word: []const u8) Error {
        return table.fail("bad value {s}", .{word});
    }

    fn require(table: *Table, allowed: bool, comptime problem: []const u8) Error!void {
        if (!allowed) return table.fail(problem, .{});
    }

    fn tableState(table: *const Table) State {
        return if (table.game) |game| game.state else .none;
    }

    fn parseSeat(table: *Table, word: []const u8) Error!usize {
        if (word.len == 1) {
            if (std.mem.findScalar(u8, seat_names, word[0])) |seat| return seat;
        }
        return table.fail("bad seat {s}", .{word});
    }

    fn parseCard(table: *Table, word: []const u8) Error!Card {
        if (word.len == 2) {
            const rank = std.mem.findScalar(u8, rank_names, word[0]);
            const suit = std.mem.findScalar(u8, suit_names, word[1]);
            if (rank != null and suit != null) return makeCard(suit.?, rank.?);
        }
        return table.fail("bad card {s}", .{word});
    }

    fn parseCards(table: *Table, words: []const []const u8) Error![]const Card {
        const cards = try table.gpa.alloc(Card, words.len);
        for (cards, words) |*card, word| card.* = try table.parseCard(word);
        return cards;
    }

    fn bounded(table: *Table, word: []const u8, low: i64, high: i64) Error!i64 {
        const value = std.fmt.parseInt(i64, word, 10) catch return table.badValue(word);
        if (value < low or value > high) return table.badValue(word);
        return value;
    }

    fn parseSwitch(table: *Table, word: []const u8) Error!bool {
        if (std.mem.eql(u8, word, "ON")) return true;
        if (std.mem.eql(u8, word, "OFF")) return false;
        return table.badValue(word);
    }

    fn setRule(table: *Table, rules: *Rules, name: RuleName, word: []const u8) Error!void {
        switch (name) {
            .TARGET => rules.target = @intCast(try table.bounded(word, 1, 1000)),
            .LIMIT => rules.limit = @intCast(try table.bounded(word, 1, 100)),
            .MOON => rules.moon = std.meta.stringToEnum(MoonMethod, word) orelse
                return table.badValue(word),
            .JACK => rules.jack = try table.parseSwitch(word),
            .QSBREAK => rules.qsbreak = try table.parseSwitch(word),
            .BLOOD => rules.blood = try table.parseSwitch(word),
            .PASS => {
                if (word.len == 0 or word.len > 8) return table.badValue(word);
                for (word) |char| {
                    if (std.mem.findScalar(u8, "LRAH", char) == null) return table.badValue(word);
                }
                rules.pass = word;
            },
        }
    }

    fn requireTurn(table: *Table, round: *const Round, seat: usize) Error!void {
        if (seat != round.actor()) {
            return table.fail("waiting for {c}", .{seat_names[round.actor()]});
        }
    }

    fn checkDuplicates(table: *Table, cards: []const Card) Error!void {
        var seen: CardSet = 0;
        for (cards) |card| {
            if (has(seen, card)) return table.fail("duplicate card {s}", .{&cardName(card)});
            seen |= bit(card);
        }
    }

    fn checkHolds(table: *Table, hand: CardSet, seat: usize, cards: []const Card) Error!void {
        for (cards) |card| {
            if (!has(hand, card)) {
                return table.fail("{c} does not hold {s}", .{ seat_names[seat], &cardName(card) });
            }
        }
    }

    fn simulate(table: *Table, command: Command, seed: i64, count: usize, out: *Writer) Error!void {
        var generator: Generator = .{ .state = @intCast(seed) };
        if (command == .GAME) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            var game: Game = .{
                .gpa = arena.allocator(),
                .rules = table.rules,
                .bots = &table.bots,
                .generator = &generator,
            };
            try game.autoGame();
            try out.print("game seed {d}\n", .{seed});
            for (game.log.items) |entry| {
                if (entry.level <= count) try out.print("{s}\n", .{entry.text});
            }
            return;
        }
        const rounds: usize = if (command == .ROTATE) 4 else 1;
        var places: [4][4]usize = @splat(@splat(0));
        var totals: [4]i64 = @splat(0);
        var stats: [4]Stats = @splat(.{});
        var hands: usize = 0;
        for (0..rounds) |rotation| {
            var strategies: [4]Strategy = undefined;
            for (table.bots, 0..) |bot, seat| strategies[(seat + rotation) % 4] = bot;
            for (0..count) |_| {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                var game: Game = .{
                    .gpa = arena.allocator(),
                    .rules = table.rules,
                    .bots = &strategies,
                    .generator = &generator,
                };
                try game.autoGame();
                hands += game.number;
                const order = game.ranking();
                for (0..4) |original| {
                    const actual = (original + rotation) % 4;
                    places[original][std.mem.findScalar(usize, &order, actual).?] += 1;
                    totals[original] += game.scores[actual];
                    stats[original].add(game.stats[actual]);
                }
            }
        }
        const games: i64 = @intCast(rounds * count);
        const label = if (command == .ROTATE) "rotate" else "match";
        try out.print("{s} seed {d} games {d} hands {d}\n", .{ label, seed, games, hands });
        for (0..4) |seat| {
            const cents = @divFloor(100 * totals[seat], games);
            const magnitude = @abs(cents);
            const sign = if (cents < 0) "-" else "";
            try out.print("{c}", .{seat_names[seat]});
            if (command == .ROTATE) try out.print(" {t}", .{table.bots[seat]});
            try out.print(" places {d} {d} {d} {d} total {d} average {s}{d}.{d:0>2} {f}\n", .{
                places[seat][0], places[seat][1], places[seat][2], places[seat][3], totals[seat],
                sign,            magnitude / 100, magnitude % 100, stats[seat],
            });
        }
    }

    fn execute(table: *Table, words: []const []const u8, out: *Writer) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]) orelse
            return table.fail("unknown command {s}", .{words[0]});
        const args = words[1..];
        switch (command) {
            .RULE => {
                const name = std.meta.stringToEnum(RuleName, args[0]) orelse
                    return table.fail("unknown rule {s}", .{args[0]});
                var rules = table.rules;
                try table.setRule(&rules, name, args[1]);
                try table.require(table.tableState() == .none, "game in progress");
                table.rules = rules;
                try out.print("rule {s} {s}\n", .{ args[0], args[1] });
            },
            .BOT => {
                const seat = try table.parseSeat(args[0]);
                table.bots[seat] = std.meta.stringToEnum(Strategy, args[1]) orelse
                    return table.badValue(args[1]);
                try out.print("bot {c} {s}\n", .{ seat_names[seat], args[1] });
            },
            .SETTINGS => {
                try out.print("rules {f}\n", .{table.rules});
                try out.print("bots {f}\n", .{perSeat("{t}", table.bots)});
            },
            .GAME, .MATCH, .ROTATE => {
                const seed = try table.bounded(args[0], 1, 2147483646);
                const high: i64 = switch (command) {
                    .GAME => 2,
                    .MATCH => 50,
                    else => 10,
                };
                const count = try table.bounded(args[1], if (command == .GAME) 0 else 1, high);
                try table.simulate(command, seed, @intCast(count), out);
            },
            .NEW => {
                const seed = try table.bounded(args[0], 1, 2147483646);
                try table.require(table.tableState() == .none, "game in progress");
                table.generator = .{ .state = @intCast(seed) };
                table.game = .{
                    .gpa = table.gpa,
                    .rules = table.rules,
                    .bots = &table.bots,
                    .generator = &table.generator,
                };
                try out.print("new game seed {d}\n", .{seed});
            },
            .ABANDON => {
                try table.require(table.tableState() != .none, "no game");
                table.game = null;
                try out.writeAll("game abandoned\n");
            },
            else => try table.tableCommand(command, args, out),
        }
    }

    fn tableCommand(
        table: *Table,
        command: Command,
        args: []const []const u8,
        out: *Writer,
    ) Error!void {
        const seat = switch (command) {
            .STACK, .PASS, .PLAY, .CLAIM => try table.parseSeat(args[0]),
            else => 0,
        };
        const cards = switch (command) {
            .STACK, .PASS, .PLAY => try table.parseCards(args[1..]),
            else => &.{},
        };
        if (command == .STACK and cards.len != 13) return table.fail("need 13 cards", .{});
        var mode: AutoMode = .PASS;
        if (command == .AUTO) {
            mode = std.meta.stringToEnum(AutoMode, args[0]) orelse return table.badValue(args[0]);
        }

        const state = table.tableState();
        const in_hand = state == .passing or state == .playing;
        switch (command) {
            .STACK, .DEAL => {
                try table.require(state != .none, "no game");
                try table.require(state == .between, "hand in progress");
            },
            .SHOW => try table.require(in_hand, "no hand"),
            .PASS => try table.require(state == .passing, "not passing"),
            .PLAY, .UNDO, .CLAIM, .LEGAL, .PREVIEW, .TAKEN, .TRICKS, .VOIDS, .UNSEEN => {
                try table.require(state == .playing, "not playing");
            },
            .SCORE, .STATS, .HISTORY, .REPLAY => try table.require(state != .none, "no game"),
            .AUTO => switch (mode) {
                .PASS => try table.require(state == .passing, "not passing"),
                .CARD, .TRICK => try table.require(state == .playing, "not playing"),
                .HAND => try table.require(in_hand, "no hand"),
                .GAME => try table.require(state != .none, "no game"),
            },
            else => unreachable,
        }
        const game = &table.game.?;
        const round = &game.round;
        const before = game.log.items.len;
        switch (command) {
            .STACK => {
                try table.checkDuplicates(cards);
                for (cards) |card| {
                    for (game.stacked, seat_names, 0..) |stacked, name, owner| {
                        if (owner == seat or !has(stacked orelse 0, card)) continue;
                        return table.fail("{s} stacked for {c}", .{ &cardName(card), name });
                    }
                }
                game.stacked[seat] = setOf(cards);
                return out.print("stacked {c}\n", .{seat_names[seat]});
            },
            .DEAL => try game.deal(),
            .SHOW => {
                for (round.hands, seat_names) |hand, name| {
                    try out.print("{c}: {f}\n", .{ name, cardList(hand) });
                }
                return;
            },
            .PASS => {
                if (game.passes[seat] != null) {
                    return table.fail("{c} already passed", .{seat_names[seat]});
                }
                try table.checkDuplicates(cards);
                try table.checkHolds(round.hands[seat], seat, cards);
                try game.passCards(seat, setOf(cards));
            },
            .PLAY => {
                const card = cards[0];
                try table.requireTurn(round, seat);
                try table.checkHolds(round.hands[seat], seat, cards);
                if (!has(round.legal(game.rules), card)) {
                    if (round.current.len == 0) {
                        if (round.completed == 0) return table.fail("must lead 2C", .{});
                        return table.fail("hearts not broken", .{});
                    }
                    const led = round.current.ledSuit();
                    if (suitSet(round.hands[seat], led) != 0) {
                        return table.fail("must follow {c}", .{suit_names[led]});
                    }
                    return table.fail("no points on first trick", .{});
                }
                try out.print("{c} plays {s}\n", .{ seat_names[seat], &cardName(card) });
                try game.play(card);
            },
            .AUTO => switch (mode) {
                .PASS => try game.autoPass(),
                .CARD => {
                    const actor = round.actor();
                    const card = game.choosePlay();
                    try out.print("{c} plays {s}\n", .{ seat_names[actor], &cardName(card) });
                    try game.play(card);
                },
                .TRICK => {
                    const count = round.completed;
                    while (game.state == .playing and round.completed == count) {
                        try game.play(game.choosePlay());
                    }
                },
                .HAND => try game.autoHand(),
                .GAME => try game.autoGame(),
            },
            .UNDO => {
                if (game.undo.items.len == 0) return table.fail("nothing to undo", .{});
                const last = game.undoCard();
                const card_name = cardName(last.card);
                return out.print("undo {c} {s}\n", .{ seat_names[last.seat], &card_name });
            },
            .CLAIM => {
                try table.requireTurn(round, seat);
                if (round.current.len > 0) return table.fail("trick in progress", .{});
                var others: CardSet = 0;
                for (round.hands, 0..) |hand, other| {
                    if (other != seat) others |= hand;
                }
                var held = each(round.hands[seat]);
                while (held.next()) |card| {
                    const higher = suitSet(others, suitOf(card)) & ~(bit(card) - 1);
                    if (higher != 0) return table.fail("claim rejected", .{});
                }
                try game.claim(seat);
            },
            .LEGAL => return out.print("legal {c}: {f} bot {s}\n", .{
                seat_names[round.actor()],
                cardList(round.legal(game.rules)),
                &cardName(game.choosePlay()),
            }),
            .PREVIEW => {
                var choices = each(round.legal(game.rules));
                while (choices.next()) |card| {
                    var preview = round.*;
                    const count = preview.completed;
                    preview.add(game.rules, card);
                    while (preview.completed == count) {
                        preview.add(game.rules, preview.choosePlay(game.rules, game.bots));
                    }
                    const trick = &preview.tricks[count];
                    try out.print("preview {s} -> {c} {d}\n", .{
                        &cardName(card),
                        seat_names[trick.winner()],
                        game.rules.points(trick.cards()),
                    });
                }
                return;
            },
            .SCORE => {
                try out.print("scores {f}\n", .{perSeat("{d}", game.scores)});
                if (game.state == .playing) {
                    var taken: [4]i32 = undefined;
                    for (&taken, round.taken) |*value, cards_taken| {
                        value.* = game.rules.points(cards_taken);
                    }
                    try out.print("taken {f}\n", .{perSeat("{d}", taken)});
                }
                return;
            },
            .TAKEN => {
                for (round.taken, seat_names) |taken, name| {
                    const scoring = taken & game.rules.pointCards();
                    try out.print("{c}: {f}\n", .{ name, cardList(scoring) });
                }
                return;
            },
            .TRICKS => {
                for (round.completedTricks(), 1..) |*trick, number| {
                    try out.print("{f}\n", .{game.trickLine(trick, number)});
                }
                if (round.current.len > 0) try out.print("current: {f}\n", .{round.current});
                if (round.completed == 0 and round.current.len == 0) {
                    try out.writeAll("no tricks\n");
                }
                return;
            },
            .VOIDS => {
                var voids: [4]SuitList = @splat(.{});
                for (round.completedTricks()) |*trick| markVoids(&voids, trick);
                markVoids(&voids, &round.current);
                return out.print("voids {f}\n", .{perSeat("{f}", voids)});
            },
            .UNSEEN => {
                var seen = round.hands[round.actor()] | round.current.cards();
                for (round.taken) |taken| seen |= taken;
                return out.print("unseen {c}: {f}\n", .{
                    seat_names[round.actor()],
                    cardList(all_cards & ~seen),
                });
            },
            .STATS => {
                for (game.stats, seat_names) |stats, name| {
                    try out.print("stats {c} {f}\n", .{ name, stats });
                }
                return;
            },
            .HISTORY => {
                for (game.history.items) |hand| {
                    try out.print("hand {d} pass {s} points {f}", .{
                        hand.number,
                        hand.direction,
                        perSeat("{d}", hand.points),
                    });
                    if (hand.shooter) |shooter| try out.print(" moon {c}", .{seat_names[shooter]});
                    try out.writeByte('\n');
                }
                if (game.history.items.len == 0) try out.writeAll("no hands\n");
                return;
            },
            .REPLAY => {
                const number = try table.bounded(args[0], 1, @intCast(game.history.items.len));
                for (game.history.items[@intCast(number - 1)].record) |text| {
                    try out.print("{s}\n", .{text});
                }
                return;
            },
            else => unreachable,
        }
        for (game.log.items[before..]) |entry| try out.print("{s}\n", .{entry.text});
    }
};

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &output.interface;
    const data = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.tokenizeAny(u8, data, "\r\n");
    const count = try std.fmt.parseInt(usize, lines.next() orelse return, 10);
    var table: Table = .{ .gpa = gpa };
    for (0..count) |_| {
        const text = lines.next() orelse break;
        var words: std.ArrayList([]const u8) = .empty;
        var parts = std.mem.splitScalar(u8, text, ' ');
        while (parts.next()) |word| try words.append(gpa, word);
        table.execute(words.items, out) catch |err| {
            if (err != error.Invalid) return err;
            try out.print("error: {s}\n", .{table.problem});
        };
    }
    try out.flush();
}
