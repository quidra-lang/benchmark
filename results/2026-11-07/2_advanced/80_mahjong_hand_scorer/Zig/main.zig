const std = @import("std");
const t = @import("tiles.zig");
const d = @import("decomposition.zig");
const y = @import("yaku.zig");
const sc = @import("scoring.zig");
const sh = @import("shanten.zig");
const Record = struct { label: []const u8, fields: t.Names };
fn records(io: std.Io, filename: []const u8) ![]const Record {
    var out: std.ArrayList(Record) = .empty;
    for (try t.readLines(io, t.fmt("input/{s}", .{filename}))) |line| {
        const words = t.words(line);
        const fields = t.alloc([]const u8, words.len - 1);
        for (words[1..], fields) |word, *field| field.* = word[(std.mem.indexOfScalar(u8, word,
             '=') orelse unreachable) + 1 ..];
        t.append(Record, &out, .{ .label = words[0], .fields = fields });
    }
    return out.items;
}
const Rule = struct { name: []const u8, index: usize, open_tanyao: bool, red_fives: bool, double_yakuman: bool,
     kazoe_yakuman: bool, kiriage: bool, honba: i64 };
fn readRules(io: std.Io) ![]const Rule {
    const values = try records(io, "rules.txt");
    const rules = t.alloc(Rule, values.len);
    for (values, rules, 0..) |record, *rule, i| {
        const f = record.fields;
        rule.* = .{ .name = record.label, .index = i, .open_tanyao = t.eq(f[0], "yes"), .red_fives = t.eq(f[1],
             "yes"), .double_yakuman = t.eq(f[2], "yes"), .kazoe_yakuman = t.eq(f[3], "yes"),
             .kiriage = t.eq(f[4], "yes"), .honba = t.number(f[5]) };
    }
    return rules;
}
fn findRule(rules: []const Rule, name: []const u8) *const Rule {
    for (rules) |*rule| if (t.eq(rule.name, name)) return rule;
    unreachable;
}
const Meld = struct {
    kind: u8,
    tiles: ?t.Tiles,
    block: t.Block = .{ .first = 0 },
    valid: bool = false,
    fn parse(source: []const u8) Meld {
        var out: Meld = .{ .kind = source[0], .tiles = t.parse(source[1..], false) };
        if (out.tiles) |tiles| {
            if (tiles.len == 0) return out;
            var first = tiles[0].kind;
            for (tiles) |tile| first = @min(first, tile.kind);
            out.block = .{ .first = first, .size = tiles.len, .sequence = out.kind == 'C' };
            if (out.kind == 'C') {
                if (tiles.len != 3 or first >= 27 or first % 9 > 6) return out;
                var seen: [3]bool = @splat(false);
                for (tiles) |tile| {
                    if (tile.kind < first or tile.kind > first + 2) return out;
                    seen[tile.kind - first] = true;
                }
                out.valid = seen[0] and seen[1] and seen[2];
            } else if (out.kind == 'P' or out.kind == 'K' or out.kind == 'A') {
                out.valid = tiles.len == (if (out.kind == 'P') @as(usize, 3) else 4);
                for (tiles) |tile| out.valid = out.valid and tile.kind == first;
            }
        }
        return out;
    }
};
fn concatenate(parts: []const t.Tiles) t.Tiles {
    var out: std.ArrayList(t.Tile) = .empty;
    for (parts) |part| for (part) |tile| t.append(t.Tile, &out, tile);
    return out.items;
}
const Situation = struct {
    label: []const u8,
    rule: *const Rule,
    hand: ?t.Tiles,
    win: ?t.Tiles,
    melds: []const Meld,
    dora: ?t.Tiles,
    ura: ?t.Tiles,
    discards: ?t.Tiles,
    tsumo: bool,
    seat: u8,
    discarder: u8,
    round: u8,
    seat_tile: usize,
    round_tile: usize,
    flags: [9]bool = @splat(false),
    closed: bool = true,
    riichi: bool = false,
    kans: usize = 0,
    honba: i64 = 0,
    sticks: i64 = 0,
    winning_tile: usize = 0,
    hand_counts: t.Counts = @splat(0),
    concealed_counts: t.Counts = @splat(0),
    meld_counts: t.Counts = @splat(0),
    all_tiles: t.Tiles = &.{},
    all_counts: t.Counts = @splat(0),
    fn parse(record: Record, rules: []const Rule) Situation {
        const f = record.fields;
        var melds: std.ArrayList(Meld) = .empty;
        if (!t.eq(f[2], "-")) for (t.split(f[2], ',')) |source| t.append(Meld, &melds, Meld.parse(source));
        var out: Situation = .{ .label = record.label, .rule = findRule(rules, f[0]), .hand = t.parse(f[1],
             false), .melds = melds.items, .win = t.parse(f[3], false), .tsumo = t.eq(f[4],
             "tsumo"), .seat = f[5][0], .discarder = f[6][0], .round = f[7][0], .seat_tile = t.windTile(f[5][0]),
             .round_tile = t.windTile(f[7][0]), .dora = t.parse(f[9], false), .ura = t.parse(f[10],
             true), .discards = t.parse(f[11], true), .honba = t.number(f[12]), .sticks = t.number(f[13]) };
        for (melds.items) |meld| {
            out.closed = out.closed and meld.kind == 'A';
            out.kans += @intFromBool(meld.kind == 'K' or meld.kind == 'A');
        }
        if (!t.eq(f[8], "-")) for (t.split(f[8], ',')) |flag| for (y.flags, 0..) |name, i| if (t.eq(name, flag)) {
            out.flags[i] = true;
        };
        out.riichi = out.flags[0] or out.flags[1];
        return out;
    }
    fn prepare(self: *Situation) void {
        self.winning_tile = self.win.?[0].kind;
        self.hand_counts = t.counts(self.hand.?);
        self.concealed_counts = t.counts(concatenate(&.{ self.hand.?, self.win.? }));
        var meld_tiles: std.ArrayList(t.Tile) = .empty;
        for (self.melds) |meld| for (meld.tiles.?) |tile| t.append(t.Tile, &meld_tiles, tile);
        self.meld_counts = t.counts(meld_tiles.items);
        self.all_tiles = concatenate(&.{ self.hand.?, self.win.?, meld_tiles.items });
        self.all_counts = t.counts(self.all_tiles);
    }
};
fn copyError(tiles: t.Tiles, rule: *const Rule) ?[]const u8 {
    var reds: [3]usize = @splat(0);
    for (tiles) |tile| if (tile.red) {
        reds[tile.kind / 9] += 1;
    };
    if (!rule.red_fives and reds[0] + reds[1] + reds[2] > 0) return "red five not allowed";
    for (t.counts(tiles), 0..) |count, kind| if (count >= 5) return t.fmt("too many copies of {s}", .{t.name(kind)});
    for (reds, 0..) |count, suit| if (count >= 2) return t.fmt("too many copies of 0{c}", .{t.suits[suit]});
    return null;
}
fn validate(s: *Situation) ?[]const u8 {
    if (s.hand == null or s.win == null or s.dora == null or s.ura == null or s.discards == null) return "bad tile notation";
    for (s.melds) |meld| if (meld.tiles == null) return "bad tile notation";
    if (s.win.?.len != 1) return "bad tile notation";
    if (s.melds.len >= 5) return "bad meld";
    for (s.melds) |meld| if (!meld.valid) return "bad meld";
    if (s.hand.?.len != 13 - 3 * s.melds.len) return "wrong tile count";
    s.prepare();
    if (copyError(concatenate(&.{ s.all_tiles, s.dora.?, s.ura.?, s.discards.? }), s.rule)) |failure| return failure;
    if ((s.tsumo and s.discarder != '-') or (!s.tsumo and (s.discarder == '-' or s.discarder == s.seat))) return "invalid discarder";
    const f = s.flags;
    const flag_count = @popCount(flagMask(f));
    const valid = [9]bool{ s.closed, s.closed and !f[0], s.riichi and !f[5], s.tsumo and !f[5],
         !s.tsumo and !f[6], s.tsumo and s.kans > 0, !s.tsumo, s.seat == 'E' and s.tsumo and s.melds.len == 0 and flag_count == 1,
         s.seat != 'E' and s.tsumo and s.melds.len == 0 and flag_count == 1 };
    for (f, valid, y.flags) |has, ok, name| if (has and !ok) return t.fmt("invalid flag {s}", .{name});
    if (s.dora.?.len != 1 + s.kans) return "invalid dora indicators";
    if ((s.riichi and s.ura.?.len != s.dora.?.len) or (!s.riichi and s.ura.?.len > 0)) return "invalid ura indicators";
    if (s.riichi and s.sticks == 0) return "invalid sticks";
    if (!d.winning(s.concealed_counts, s.melds.len)) return "not a winning hand";
    return null;
}
fn flagMask(flags: [9]bool) u16 {
    var mask: u16 = 0;
    for (flags, 0..) |has, i| if (has) {
        mask |= @as(u16, 1) << @intCast(i);
    };
    return mask;
}
const Form = enum { standard, chiitoitsu, kokushi };
const Candidate = struct {
    kind: Form,
    pair: usize = 0,
    sets: []const t.Block = &.{},
    winning_block: ?t.Block = null,
    form: []const u8,
    wait: d.Wait,
    ordinary: []const y.Entry = &.{},
    yakuman: []const y.Entry = &.{},
    fu_items: []const sc.FuItem = &.{},
    multiplier: i64 = 0,
    han: i64 = 0,
    fu: i64 = 0,
    fu_total: i64 = 0,
    base: i64 = 0,
    dora: i64 = 0,
    aka: i64 = 0,
    ura: i64 = 0,
    category: usize = 0,
};
fn candidates(s: *const Situation) []Candidate {
    var out: std.ArrayList(Candidate) = .empty;
    for (d.standard(s.concealed_counts, s.melds.len)) |decomp| {
        const blocks = t.alloc(t.Block, decomp.count + 1);
        blocks[0] = .{ .first = decomp.pair, .size = 2 };
        @memcpy(blocks[1..], decomp.sets[0..decomp.count]);
        for (blocks, 0..) |chosen, index| {
            if (!chosen.contains(s.winning_tile)) continue;
            var duplicate = false;
            for (blocks[0..index]) |previous| duplicate = duplicate or chosen.same(previous);
            if (duplicate) continue;
            var parts: std.ArrayList([]const u8) = .empty;
            t.append([]const u8, &parts, "standard");
            for (blocks, 0..) |block, j| t.append([]const u8, &parts, t.fmt("{s}{s}", .{ block.text(),
                 if (j == index) "*" else "" }));
            for (s.melds) |meld| t.append([]const u8, &parts, t.fmt("{c}{s}", .{ meld.kind, meld.block.text() }));
            t.append(Candidate, &out, .{ .kind = .standard, .pair = decomp.pair, .sets = blocks[1..],
                 .winning_block = chosen, .form = t.join(parts.items, " "), .wait = d.waitShape(chosen,
                 s.winning_tile) });
        }
    }
    if (s.melds.len == 0 and d.sevenPairs(s.concealed_counts)) {
        var parts: std.ArrayList([]const u8) = .empty;
        t.append([]const u8, &parts, "chiitoitsu");
        for (s.concealed_counts, 0..) |count, kind| if (count > 0) t.append([]const u8, &parts,
             t.fmt("{s}{s}", .{ (t.Block{ .first = kind, .size = 2 }).text(), if (kind == s.winning_tile) "*" else "" }));
        t.append(Candidate, &out, .{ .kind = .chiitoitsu, .form = t.join(parts.items, " "), .wait = .tanki });
    }
    if (s.melds.len == 0 and d.thirteenOrphans(s.concealed_counts)) {
        var parts: std.ArrayList([]const u8) = .empty;
        t.append([]const u8, &parts, "kokushi");
        for (t.orphans) |kind| t.append([]const u8, &parts, t.fmt("{s}{s}", .{ (t.Block{ .first = kind,
             .size = s.concealed_counts[kind] }).text(), if (kind == s.winning_tile) "*" else "" }));
        t.append(Candidate, &out, .{ .kind = .kokushi, .form = t.join(parts.items, " "), .wait = d.orphanWait(s.hand_counts) });
    }
    std.mem.sort(Candidate, out.items, {}, struct {
        fn less(_: void, a: Candidate, b: Candidate) bool {
            return std.mem.order(u8, a.form, b.form) == .lt;
        }
    }.less);
    return out.items;
}
const Facts = struct { triplets: []const sc.Triplet, sequences: [34]usize, concealed_sequences: [34]usize,
     sequence_count: usize, concealed_sequence_count: usize, concealed_triplets: usize, kans: usize,
     dragons: usize, winds: usize, triplet_kinds: [34]bool };
fn blockFacts(s: *const Situation, c: *const Candidate) Facts {
    var triplets: std.ArrayList(sc.Triplet) = .empty;
    var facts: Facts = .{ .triplets = &.{}, .sequences = @splat(0), .concealed_sequences = @splat(0),
         .sequence_count = 0, .concealed_sequence_count = 0, .concealed_triplets = 0, .kans = 0,
         .dragons = 0, .winds = 0, .triplet_kinds = @splat(false) };
    for (c.sets) |block| if (block.sequence) {
        facts.sequences[block.first] += 1;
        facts.concealed_sequences[block.first] += 1;
        facts.sequence_count += 1;
        facts.concealed_sequence_count += 1;
    } else t.append(sc.Triplet, &triplets, .{ .block = block, .concealed = s.tsumo or !block.same(c.winning_block.?),
         .kan = false });
    for (s.melds) |meld| if (meld.kind == 'C') {
        facts.sequences[meld.block.first] += 1;
        facts.sequence_count += 1;
    } else t.append(sc.Triplet, &triplets, .{ .block = meld.block, .concealed = meld.kind == 'A',
         .kan = meld.kind == 'K' or meld.kind == 'A' });
    facts.triplets = triplets.items;
    for (triplets.items) |triplet| {
        facts.concealed_triplets += @intFromBool(triplet.concealed);
        facts.kans += @intFromBool(triplet.kan);
        facts.triplet_kinds[triplet.block.first] = true;
    }
    for (31..34) |kind| facts.dragons += @intFromBool(facts.triplet_kinds[kind]);
    for (27..31) |kind| facts.winds += @intFromBool(facts.triplet_kinds[kind]);
    return facts;
}
const TileFacts = struct { honors: bool = false, all_honors: bool = true, all_terminals: bool = true,
     all_green: bool = true, all_yaochuu: bool = true, all_simple: bool = true, number_suits: u8 = 0 };
fn tileFacts(counts: t.Counts) TileFacts {
    var out: TileFacts = .{};
    for (counts, 0..) |count, kind| if (count > 0) {
        out.honors = out.honors or t.honor(kind);
        out.all_honors = out.all_honors and t.honor(kind);
        out.all_terminals = out.all_terminals and t.terminal(kind);
        out.all_green = out.all_green and t.green(kind);
        out.all_yaochuu = out.all_yaochuu and t.yaochuu(kind);
        out.all_simple = out.all_simple and !t.yaochuu(kind);
        if (kind < 27) out.number_suits |= @as(u8, 1) << @intCast(kind / 9);
    };
    return out;
}
fn yakumanNames(s: *const Situation, c: *const Candidate, f: Facts, k: TileFacts) [15]bool {
    var names: [15]bool = @splat(false);
    names[0] = s.flags[7];
    names[1] = s.flags[8];
    names[9] = k.all_honors;
    names[10] = k.all_terminals;
    names[11] = k.all_green;
    if (s.melds.len == 0 and @popCount(k.number_suits) == 1 and !k.honors) {
        const suit: usize = @ctz(k.number_suits);
        const start = suit * 9;
        var valid = s.all_counts[start] >= 3 and s.all_counts[start + 8] >= 3;
        for (start + 1..start + 8) |kind| valid = valid and s.all_counts[kind] > 0;
        if (valid) {
            var pure = true;
            for (0..9) |i| pure = pure and s.hand_counts[start + i] == (if (i == 0 or i == 8) @as(u32, 3) else 1);
            names[if (pure) @as(usize, 13) else 12] = true;
        }
    }
    if (c.kind == .kokushi) names[if (c.wait == .thirteen) @as(usize, 3) else 2] = true;
    if (c.kind == .standard) {
        if (f.concealed_triplets == 4) names[if (c.wait == .tanki) @as(usize, 5) else 4] = true;
        names[6] = f.dragons == 3;
        names[7] = f.winds == 3 and c.pair >= 27 and c.pair <= 30;
        names[8] = f.winds == 4;
        names[14] = f.kans == 4;
    }
    return names;
}
fn ordinaryNames(s: *const Situation, c: *const Candidate, f: Facts, k: TileFacts) [30]bool {
    var names: [30]bool = @splat(false);
    names[0] = s.flags[0];
    names[1] = s.flags[1];
    names[2] = s.flags[2];
    for (3..7) |i| names[9 + i] = s.flags[i];
    names[3] = s.closed and s.tsumo;
    names[5] = k.all_simple and (s.closed or s.rule.open_tanyao);
    names[25] = k.all_yaochuu;
    if (@popCount(k.number_suits) == 1) names[if (k.honors) @as(usize, 26) else 29] = true;
    names[16] = c.kind == .chiitoitsu;
    if (c.kind != .standard) return names;
    const yakuhai = c.pair >= 31 or c.pair == s.seat_tile or c.pair == s.round_tile;
    names[4] = s.closed and s.melds.len == 0 and f.concealed_sequence_count == 4 and !yakuhai and c.wait == .ryanmen;
    var repetitions: usize = 0;
    var repeated = false;
    for (f.concealed_sequences) |count| {
        repetitions += count / 2;
        repeated = repeated or count >= 2;
    }
    names[28] = s.closed and f.concealed_sequence_count == 4 and repetitions == 2;
    names[6] = s.closed and !names[28] and repeated;
    names[7] = f.triplet_kinds[31];
    names[8] = f.triplet_kinds[32];
    names[9] = f.triplet_kinds[33];
    names[10] = f.triplet_kinds[s.seat_tile];
    names[11] = f.triplet_kinds[s.round_tile];
    names[17] = f.triplets.len == 4;
    names[18] = f.concealed_triplets == 3;
    for (0..7) |start| if (f.sequences[start] > 0 and f.sequences[start + 9] > 0 and f.sequences[start + 18] > 0) {
        names[19] = true;
    };
    for (0..9) |number| if (f.triplet_kinds[number] and f.triplet_kinds[number + 9] and f.triplet_kinds[number + 18]) {
        names[20] = true;
    };
    for (0..3) |suit| if (f.sequences[suit * 9] > 0 and f.sequences[suit * 9 + 3] > 0 and f.sequences[suit * 9 + 6] > 0) {
        names[21] = true;
    };
    var all_blocks = t.yaochuu(c.pair);
    for (c.sets) |block| all_blocks = all_blocks and (t.yaochuu(block.first) or (block.sequence and t.yaochuu(block.first + 2)));
    for (s.melds) |meld| all_blocks = all_blocks and (t.yaochuu(meld.block.first) or (meld.block.sequence and t.yaochuu(meld.block.first + 2)));
    if (f.sequence_count > 0 and all_blocks) names[if (k.honors) @as(usize, 22) else 27] = true;
    names[23] = f.kans == 3;
    names[24] = f.dragons == 2 and c.pair >= 31;
    return names;
}
fn evaluateCandidate(s: *const Situation, c: *Candidate) void {
    const f = blockFacts(s, c);
    const k = tileFacts(s.all_counts);
    c.yakuman = y.yakuman(yakumanNames(s, c, f, k), s.rule.double_yakuman);
    if (c.yakuman.len > 0) {
        for (c.yakuman) |entry| c.multiplier += entry.value;
        c.base = 8000 * c.multiplier;
        c.category = 6;
        return;
    }
    const names = ordinaryNames(s, c, f, k);
    c.ordinary = y.ordinary(names, s.closed);
    for (s.dora.?) |tile| c.dora += s.all_counts[t.nextDora(tile.kind)];
    for (s.ura.?) |tile| c.ura += s.all_counts[t.nextDora(tile.kind)];
    for (s.all_tiles) |tile| c.aka += @intFromBool(tile.red);
    const fu = sc.fuBreakdown(c.kind == .chiitoitsu, c.pair, f.triplets, c.wait, s.closed,
         s.tsumo, s.seat_tile, s.round_tile, names[4]);
    c.fu_items = fu.items;
    c.fu_total = fu.total;
    c.fu = fu.value;
    if (c.ordinary.len > 0) {
        c.han = c.dora + c.aka + c.ura;
        for (c.ordinary) |entry| c.han += entry.value;
        const limit = sc.limit(c.han, c.fu, s.rule.kazoe_yakuman, s.rule.kiriage);
        c.base = limit.base;
        c.category = limit.category;
    }
}
fn evaluateCandidates(s: *const Situation) []Candidate {
    const out = candidates(s);
    for (out) |*candidate| evaluateCandidate(s, candidate);
    return out;
}
fn better(a: Candidate, b: Candidate) bool {
    if (a.base != b.base) return a.base > b.base;
    if ((a.yakuman.len > 0) != (b.yakuman.len > 0)) return a.yakuman.len > 0;
    if (a.yakuman.len == 0) {
        if (a.han != b.han) return a.han > b.han;
        if (a.fu != b.fu) return a.fu > b.fu;
    }
    return std.mem.order(u8, a.form, b.form) == .lt;
}
fn bestCandidate(values: []const Candidate) ?Candidate {
    var best: ?Candidate = null;
    for (values) |candidate| if (candidate.base > 0 and (best == null or better(candidate, best.?))) {
        best = candidate;
    };
    return best;
}
fn candidateLine(out: *t.Lines, c: Candidate) void {
    const evaluation = if (c.yakuman.len > 0) t.fmt("yakuman {d} base {d} yaku {s}", .{ c.multiplier,
         c.base, y.names(c.yakuman, ",") }) else if (c.ordinary.len == 0) "no_yaku" else t.fmt("han {d} fu {d} base {d} yaku {s}",
         .{ c.han, c.fu, c.base, y.names(c.ordinary, ",") });
    out.add("CANDIDATE {s} = {s} {s}", .{ c.form, d.wait_names[@intFromEnum(c.wait)], evaluation });
}
fn signed(value: i64) []const u8 {
    return if (value > 0) t.fmt("+{d}", .{value}) else t.fmt("{d}", .{value});
}
fn winningLines(out: *t.Lines, s: *const Situation, c: Candidate) i64 {
    out.add("FORM {s}", .{c.form});
    out.add("WAIT {s}", .{d.wait_names[@intFromEnum(c.wait)]});
    if (c.yakuman.len > 0) {
        for (c.yakuman) |entry| out.add("YAKUMAN {s} {d}", .{ entry.name, entry.value });
        out.add("SCORE yakuman {d} base {d}", .{ c.multiplier, c.base });
    } else {
        for (c.ordinary) |entry| out.add("YAKU {s} {d}", .{ entry.name, entry.value });
        out.add("DORA dora {d} aka {d} ura {d}", .{ c.dora, c.aka, c.ura });
        for (c.fu_items) |item| out.add("FU {s} {d}", .{ item.name, item.value });
        out.add("FU total {d} {d}", .{ c.fu_total, c.fu });
        out.add("SCORE han {d} fu {d} limit {s} base {d}", .{ c.han, c.fu, y.categories[c.category], c.base });
    }
    const payments = sc.payments(c.base, s.seat == 'E', s.tsumo);
    if (!s.tsumo) out.add("PAY ron {d}", .{payments.ron}) else if (s.seat == 'E') out.add("PAY tsumo all {d}",
         .{payments.nondealer}) else out.add("PAY tsumo dealer {d} nondealer {d}", .{ payments.dealer,
         payments.nondealer });
    const honba = s.honba * s.rule.honba;
    const sticks = s.sticks * 1000;
    const gain = payments.total + honba + sticks;
    out.add("BONUS honba {d} sticks {d}", .{ honba, sticks });
    out.add("TOTAL points {d} gain {d}", .{ payments.total, gain });
    var changes: [4]i64 = @splat(0);
    if (!s.tsumo) changes[t.windTile(s.discarder) - 27] = -payments.ron - honba else for (t.winds,
         0..) |wind, i| if (wind != s.seat) {
        changes[i] = -(if (wind == 'E') payments.dealer else payments.nondealer) - @divTrunc(honba, 3);
    };
    changes[s.seat_tile - 27] = gain;
    out.add("DELTA E {s} S {s} W {s} N {s}", .{ signed(changes[0]), signed(changes[1]), signed(changes[2]),
         signed(changes[3]) });
    return payments.total;
}
const Stats = struct { wins: i64 = 0, furiten: i64 = 0, no_yaku: i64 = 0, errors: i64 = 0,
     points: i64 = 0, win_counts: [4]i64 = @splat(0), wait_counts: [7]i64 = @splat(0), han_counts: [256]i64 = @splat(0),
     fu_counts: [256]i64 = @splat(0), limits: [7]i64 = @splat(0), ordinary: [30]i64 = @splat(0),
     yakuman: [15]i64 = @splat(0), rules: [26][3]i64 = @splat(@splat(0)), maximum: i64 = 0,
     maximum_hand: []const u8 = "-" };
fn scores(records_values: []const Record, rules: []const Rule, work_allocator: std.mem.Allocator) struct { scores: t.Lines,
     summary: t.Lines } {
    var out: t.Lines = .{};
    var summary: t.Lines = .{};
    summary.add("hand,han,fu,points,yaku", .{});
    var stats: Stats = .{};
    for (records_values) |record| {
        const persistent = t.allocator;
        var work: std.heap.ArenaAllocator = .init(work_allocator);
        defer work.deinit();
        t.allocator = work.allocator();
        var local: t.Lines = .{};
        var local_summary: t.Lines = .{};
        var s = Situation.parse(record, rules);
        stats.rules[s.rule.index][0] += 1;
        local.add("HAND {s}", .{record.label});
        if (validate(&s)) |failure| {
            stats.errors += 1;
            local.add("ERROR {s}", .{failure});
            local_summary.add("{s},-,-,0,ERROR", .{record.label});
        } else {
            const waiting = d.waitingTiles(s.hand_counts, s.meld_counts, s.melds.len);
            var names: std.ArrayList([]const u8) = .empty;
            for (waiting) |kind| t.append([]const u8, &names, t.name(kind));
            local.add("WAITS {s}", .{t.join(names.items, " ")});
            const evaluated = evaluateCandidates(&s);
            for (evaluated) |candidate| candidateLine(&local, candidate);
            var furiten = false;
            if (!s.tsumo) for (s.discards.?) |tile| for (waiting) |kind| {
                furiten = furiten or tile.kind == kind;
            };
            if (furiten) {
                stats.furiten += 1;
                local.add("RESULT furiten", .{});
                local_summary.add("{s},-,-,0,FURITEN", .{record.label});
            } else if (bestCandidate(evaluated)) |best| {
                const points = winningLines(&local, &s, best);
                stats.wins += 1;
                stats.points += points;
                stats.rules[s.rule.index][1] += 1;
                stats.rules[s.rule.index][2] += points;
                stats.win_counts[(if (s.seat == 'E') @as(usize, 0) else 2) + @intFromBool(s.tsumo)] += 1;
                stats.wait_counts[@intFromEnum(best.wait)] += 1;
                stats.limits[best.category] += 1;
                if (best.yakuman.len > 0) {
                    for (best.yakuman) |entry| stats.yakuman[entry.index] += 1;
                    local_summary.add("{s},Y{d},-,{d},{s}", .{ record.label, best.multiplier,
                         points, y.names(best.yakuman, ";") });
                } else {
                    for (best.ordinary) |entry| stats.ordinary[entry.index] += 1;
                    stats.han_counts[t.u(best.han)] += 1;
                    stats.fu_counts[t.u(best.fu)] += 1;
                    local_summary.add("{s},{d},{d},{d},{s}", .{ record.label, best.han, best.fu,
                         points, y.names(best.ordinary, ";") });
                }
                if (points > stats.maximum) {
                    stats.maximum = points;
                    stats.maximum_hand = record.label;
                }
            } else {
                stats.no_yaku += 1;
                local.add("RESULT no_yaku", .{});
                local_summary.add("{s},-,-,0,NO_YAKU", .{record.label});
            }
        }
        t.allocator = persistent;
        out.extend(local);
        summary.extend(local_summary);
    }
    out.add("STATS hands {d} wins {d} furiten {d} no_yaku {d} errors {d}", .{ records_values.len,
         stats.wins, stats.furiten, stats.no_yaku, stats.errors });
    out.add("WINS dealer_ron {d} dealer_tsumo {d} nondealer_ron {d} nondealer_tsumo {d}", .{ stats.win_counts[0],
         stats.win_counts[1], stats.win_counts[2], stats.win_counts[3] });
    var wait_counts_text: t.Text = .{};
    wait_counts_text.add("WAIT_COUNT", .{});
    for (d.wait_names, stats.wait_counts) |name, count| wait_counts_text.add(" {s} {d}", .{ name, count });
    out.add("{s}", .{wait_counts_text.value()});
    for (stats.han_counts, 0..) |count, han| if (count > 0) out.add("HAN_COUNT {d} {d}", .{ han, count });
    for (stats.fu_counts, 0..) |count, fu| if (count > 0) out.add("FU_COUNT {d} {d}", .{ fu, count });
    for (y.categories, stats.limits) |name, count| out.add("LIMIT {s} {d}", .{ name, count });
    for (y.ordinary_table, stats.ordinary) |entry, count| if (count > 0) out.add("YAKU_COUNT {s} {d}",
         .{ entry.name, count });
    for (y.yakuman_table, stats.yakuman) |entry, count| if (count > 0) out.add("YAKU_COUNT {s} {d}",
         .{ entry.name, count });
    out.add("POINTS total {d} max {d} hand {s}", .{ stats.points, stats.maximum, stats.maximum_hand });
    for (rules) |rule| out.add("RULE {s} hands {d} wins {d} points {d}", .{ rule.name, stats.rules[rule.index][0],
         stats.rules[rule.index][1], stats.rules[rule.index][2] });
    return .{ .scores = out, .summary = summary };
}
fn hypothetical(record: Record, rules: []const Rule, hand: t.Tiles, dora: t.Tiles, kind: usize, tsumo: bool) Situation {
    const f = record.fields;
    const win = t.alloc(t.Tile, 1);
    win[0] = .{ .kind = kind };
    var out: Situation = .{ .label = record.label, .rule = findRule(rules, f[0]), .hand = hand,
         .win = win, .melds = &.{}, .dora = dora, .ura = &.{}, .discards = &.{}, .tsumo = tsumo,
         .seat = f[2][0], .discarder = if (tsumo) '-' else if (f[2][0] == 'E') 'S' else 'E',
         .round = f[3][0], .seat_tile = t.windTile(f[2][0]), .round_tile = t.windTile(f[3][0]),
         .riichi = t.eq(f[4], "yes") };
    out.flags[0] = out.riichi;
    out.prepare();
    return out;
}
fn waits(records_values: []const Record, rules: []const Rule, work_allocator: std.mem.Allocator) t.Lines {
    var out: t.Lines = .{};
    var errors: usize = 0;
    var tenpai: usize = 0;
    var furiten_count: usize = 0;
    var shanten_counts: [7]usize = @splat(0);
    for (records_values) |record| {
        const persistent = t.allocator;
        var work: std.heap.ArenaAllocator = .init(work_allocator);
        defer work.deinit();
        t.allocator = work.allocator();
        var local: t.Lines = .{};
        local.add("HAND {s}", .{record.label});
        const f = record.fields;
        const hand = t.parse(f[1], false);
        const dora = t.parse(f[5], false);
        const discards = t.parse(f[6], true);
        const visible = t.parse(f[7], true);
        var failure: ?[]const u8 = null;
        var observed: t.Tiles = &.{};
        if (hand == null or dora == null or discards == null or visible == null) failure = "bad tile notation" else if (hand.?.len != 13) failure = "wrong tile count" else {
            observed = concatenate(&.{ hand.?, dora.?, discards.?, visible.? });
            failure = copyError(observed, findRule(rules, f[0]));
        }
        if (failure) |reason| {
            errors += 1;
            local.add("ERROR {s}", .{reason});
        } else {
            var counts = t.counts(hand.?);
            const known = t.counts(observed);
            const numbers = sh.numbers(counts);
            const current = sh.minimum(numbers);
            shanten_counts[t.u(current)] += 1;
            local.add("SHANTEN standard {d} chiitoitsu {d} kokushi {d}", .{ numbers[0], numbers[1], numbers[2] });
            const Accepted = struct { kind: usize, left: i64 };
            var accepted: std.ArrayList(Accepted) = .empty;
            var total: i64 = 0;
            for (0..34) |kind| {
                if (counts[kind] >= 4) continue;
                counts[kind] += 1;
                const advances = sh.minimum(sh.numbers(counts)) < current;
                counts[kind] -= 1;
                if (advances) {
                    const left = 4 - @as(i64, known[kind]);
                    total += left;
                    t.append(Accepted, &accepted, .{ .kind = kind, .left = left });
                }
            }
            if (current != 0) {
                var line: t.Text = .{};
                line.add("ACCEPT kinds {d} tiles {d}", .{ accepted.items.len, total });
                for (accepted.items) |item| line.add(" {s}:{d}", .{ t.name(item.kind), item.left });
                local.add("{s}", .{line.value()});
            } else {
                tenpai += 1;
                var furiten = false;
                for (discards.?) |tile| for (accepted.items) |item| {
                    furiten = furiten or tile.kind == item.kind;
                };
                furiten_count += @intFromBool(furiten);
                local.add("TENPAI kinds {d} tiles {d} furiten {s}", .{ accepted.items.len,
                     total, if (furiten) "yes" else "no" });
                var best_points: [2]i64 = @splat(0);
                var best_tiles: [2]?usize = @splat(null);
                for (accepted.items) |item| {
                    var results: [2][]const u8 = undefined;
                    for (0..2) |method| {
                        if (method == 0 and furiten) {
                            results[method] = "furiten";
                            continue;
                        }
                        const situation = hypothetical(record, rules, hand.?, dora.?, item.kind, method == 1);
                        if (bestCandidate(evaluateCandidates(&situation))) |best| {
                            const points = sc.payments(best.base, situation.seat == 'E', method == 1).total;
                            results[method] = t.fmt("{d}", .{points});
                            if (best_tiles[method] == null or points > best_points[method]) {
                                best_points[method] = points;
                                best_tiles[method] = item.kind;
                            }
                        } else results[method] = "no_yaku";
                    }
                    local.add("WAIT {s} left {d} ron {s} tsumo {s}", .{ t.name(item.kind),
                         item.left, results[0], results[1] });
                }
                var choices: [2][]const u8 = undefined;
                for (0..2) |method| choices[method] = if (best_tiles[method]) |kind| t.fmt("{s} {d}",
                     .{ t.name(kind), best_points[method] }) else "none";
                local.add("BEST ron {s} tsumo {s}", .{ choices[0], choices[1] });
            }
        }
        t.allocator = persistent;
        out.extend(local);
    }
    out.add("STATS hands {d} errors {d} tenpai {d} furiten {d}", .{ records_values.len, errors,
         tenpai, furiten_count });
    for (shanten_counts, 0..) |count, k| out.add("SHANTEN_COUNT {d} {d}", .{ k, count });
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    t.allocator = arena.allocator();
    sh.cache_allocator = t.allocator;
    const rules = try readRules(init.io);
    const situations = try records(init.io, "hands.txt");
    const hands = try records(init.io, "waits.txt");
    const score_reports = scores(situations, rules, init.gpa);
    const wait_report = waits(hands, rules, init.gpa);
    try t.writeLines(init.io, "scores.txt", score_reports.scores);
    try t.writeLines(init.io, "waits.txt", wait_report);
    try t.writeLines(init.io, "summary.csv", score_reports.summary);
}
