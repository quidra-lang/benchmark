const std = @import("std");
const b = @import("bids_io.zig");
const w = @import("wdp_solver.zig");
const pay = @import("payments.zig");
const a = @import("auctions.zig");
const r = @import("report.zig");
const Fraction = r.Fraction;
const formats = [_][]const u8{ "first_price", "second_price", "english", "dutch", "all_pay" };
const labels = [_][]const u8{ "FIRST_PRICE", "SECOND_PRICE", "ENGLISH", "DUTCH", "ALL_PAY" };
const outcomes = [_][]const u8{ "vcg", "greedy", "critical", "saa" };
const mechanisms = [_][]const u8{ "vcg", "pay_as_bid", "greedy", "critical", "saa" };
const Bidder = struct { name: []const u8, xor: bool, valid: std.ArrayList(b.Bid) = .empty, eligible: usize = 0 };
const Rejection = struct { number: usize, name: []const u8, message: []const u8 };
const Auction = struct { name: []const u8, offered: u16, bidders: []const Bidder, valid: []const b.Bid,
     eligible: []const b.Bid, below: []const b.Bid, rejected: []const Rejection, bid_count: usize };
fn letters(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |character| if (character < 'a' or character > 'z') return false;
    return true;
}
fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |character| if (character < '0' or character > '9') return false;
    return true;
}
fn findItem(items: []const b.Item, name: []const u8) ?usize {
    for (items, 0..) |item, index| if (b.eq(item.name, name)) return index;
    return null;
}
const BidCheck = struct { message: ?[]const u8 = null, bundle: u16 = 0, amount: i64 = 0 };
fn checkBid(source: []const u8, bidder: Bidder, items: []const b.Item, offered: u16, params: b.Parameters) BidCheck {
    const fields = b.split(source, ':');
    if (fields.len != 2) return .{ .message = "malformed bid" };
    const names = b.split(fields[0], '+');
    const amount_text = fields[1];
    if (amount_text.len < 1 or amount_text.len > 5 or !digits(amount_text) or (amount_text.len > 1 and amount_text[0] == '0')) return .{ .message = "malformed bid" };
    for (names) |name| if (!letters(name)) return .{ .message = "malformed bid" };
    var bundle: u16 = 0;
    for (names) |name| {
        const index = findItem(items, name) orelse return .{ .message = b.fmt("unknown item {s}", .{name}) };
        if (offered & b.bit(index) == 0) return .{ .message = b.fmt("item not offered {s}", .{name}) };
        if (bundle & b.bit(index) != 0) return .{ .message = b.fmt("duplicate item {s}", .{name}) };
        bundle |= b.bit(index);
    }
    if (names.len > params.max_bundle_size) return .{ .message = "bundle too large" };
    const amount = b.number(amount_text);
    if (amount == 0) return .{ .message = "zero value" };
    for (bidder.valid.items) |earlier| if (earlier.bundle == bundle) return .{ .message = b.fmt("duplicate bundle {d}",
         .{earlier.number}) };
    if (bidder.valid.items.len >= params.max_bids_per_bidder) return .{ .message = "too many bids" };
    return .{ .bundle = bundle, .amount = amount };
}
fn validate(raw: b.RawAuction, items: []const b.Item, params: b.Parameters) Auction {
    var offered: u16 = 0;
    for (raw.items) |name| offered |= b.bit(b.indexOf(items, name));
    var bidders: std.ArrayList(Bidder) = .empty;
    var valid: std.ArrayList(b.Bid) = .empty;
    var eligible: std.ArrayList(b.Bid) = .empty;
    var below: std.ArrayList(b.Bid) = .empty;
    var rejected: std.ArrayList(Rejection) = .empty;
    var bid_count: usize = 0;
    for (raw.lines.items, 0..) |line, index| {
        var line_error: ?[]const u8 = null;
        for (raw.lines.items[0..index]) |earlier| if (b.eq(earlier.name, line.name)) {
            line_error = "duplicate bidder";
            break;
        };
        if (line_error == null and !b.eq(line.language, "XOR") and !b.eq(line.language, "OR")) line_error = b.fmt("bad language {s}",
             .{line.language});
        const id = bidders.items.len;
        if (line_error == null) b.append(Bidder, &bidders, .{ .name = line.name, .xor = b.eq(line.language, "XOR") });
        for (line.bids) |source| {
            bid_count += 1;
            if (line_error) |message| {
                b.append(Rejection, &rejected, .{ .number = bid_count, .name = line.name, .message = message });
                continue;
            }
            const result = checkBid(source, bidders.items[id], items, offered, params);
            if (result.message) |message| {
                b.append(Rejection, &rejected, .{ .number = bid_count, .name = line.name, .message = message });
                continue;
            }
            const bid: b.Bid = .{ .number = bid_count, .bidder = id, .bundle = result.bundle,
                 .amount = result.amount, .xor = bidders.items[id].xor };
            b.append(b.Bid, &bidders.items[id].valid, bid);
            b.append(b.Bid, &valid, bid);
            if (bid.amount >= b.reserve(items, bid.bundle)) {
                b.append(b.Bid, &eligible, bid);
                bidders.items[id].eligible += 1;
            } else b.append(b.Bid, &below, bid);
        }
    }
    return .{ .name = raw.name, .offered = offered, .bidders = bidders.items, .valid = valid.items,
         .eligible = eligible.items, .below = below.items, .rejected = rejected.items, .bid_count = bid_count };
}
const Allocation = struct { winning: []const b.Bid, owners: [12]?usize = @splat(null), unsold: u16,
     accepted: i64 = 0, retained: i64 = 0, welfare: i64 = 0, values: [15]i64 = @splat(0) };
fn allocation(bids: []const b.Bid, offered: u16, items: []const b.Item) Allocation {
    const winning = b.dupe(b.Bid, bids);
    std.mem.sort(b.Bid, winning, {}, struct {
        fn less(_: void, left: b.Bid, right: b.Bid) bool {
            return left.number < right.number;
        }
    }.less);
    var out: Allocation = .{ .winning = winning, .unsold = offered };
    for (winning) |bid| {
        out.accepted += bid.amount;
        out.values[bid.bidder] += bid.amount;
        out.unsold &= ~bid.bundle;
        for (items, 0..) |_, index| if (bid.bundle & b.bit(index) != 0) {
            out.owners[index] = bid.bidder;
        };
    }
    out.retained = b.reserve(items, out.unsold);
    out.welfare = out.accepted + out.retained;
    return out;
}
fn criticalFor(critical: []const pay.Critical, number: usize) pay.Critical {
    for (critical) |result| if (result.number == number) return result;
    unreachable;
}
fn numberText(number: ?usize) []const u8 {
    return if (number) |value| b.fmt("{d}", .{value}) else "-";
}
const Ascending = struct { lines: b.Lines, payments: [15]i64 = @splat(0), utilities: [15]i64 = @splat(0),
     revenue: i64 = 0, retained: i64 = 0, welfare: i64 = 0, rounds: usize, cap: bool, exposure: i64 = 0,
     exposed: usize = 0 };
fn ascending(auction: Auction, items: []const b.Item, params: b.Parameters, optimum: i64) Ascending {
    var choices: [15][]const a.Candidate = undefined;
    var eligibility: [15]usize = @splat(0);
    var prices: [12]i64 = @splat(0);
    var holders: [12]?usize = @splat(null);
    var bid_counts: [12]usize = @splat(0);
    var bid_rounds: [12]usize = @splat(0);
    var last_rounds: [12]usize = @splat(0);
    for (auction.bidders, 0..) |bidder, id| {
        choices[id] = a.candidates(bidder.valid.items, bidder.xor);
        for (choices[id]) |candidate| eligibility[id] = @max(eligibility[id], @popCount(candidate.bundle));
    }
    for (items, 0..) |item, index| prices[index] = item.reserve;
    var state = params.seed;
    var lines: b.Lines = .{};
    lines.add("AUCTION {s} increment {d}", .{ auction.name, params.saa_increment });
    var round: usize = 0;
    var cap = false;
    while (round < params.round_cap) {
        round += 1;
        var activities: [15]usize = @splat(0);
        var new_bids: [15]u16 = @splat(0);
        var demand: usize = 0;
        for (auction.bidders, 0..) |_, id| {
            var held: u16 = 0;
            for (items, 0..) |_, index| if (auction.offered & b.bit(index) != 0 and holders[index] == id) {
                held |= b.bit(index);
            };
            var chosen: ?a.Candidate = null;
            var best_surplus: i64 = 0;
            for (choices[id]) |candidate| {
                if (@popCount(candidate.bundle | held) > eligibility[id]) continue;
                var asking: i64 = 0;
                for (items, 0..) |_, index| if (candidate.bundle & b.bit(index) != 0) {
                    asking += prices[index] + (if (holders[index] != null and holders[index] != id) params.saa_increment else 0);
                };
                const surplus = candidate.value - asking;
                if (surplus > best_surplus) {
                    chosen = candidate;
                    best_surplus = surplus;
                }
            }
            const wanted = if (chosen) |candidate| candidate.bundle else @as(u16, 0);
            activities[id] = @popCount(wanted | held);
            new_bids[id] = wanted & ~held;
            demand += @popCount(new_bids[id]);
        }
        if (demand == 0) lines.add("ROUND {d} none", .{round}) else {
            var line: b.Text = .{};
            line.add("ROUND {d} demand {d}", .{ round, demand });
            for (auction.bidders, 0..) |bidder, id| if (new_bids[id] != 0) line.add(" {s}:{s}",
                 .{ bidder.name, r.bundle(new_bids[id], items, "+") });
            lines.add("{s}", .{line.value()});
            for (items, 0..) |_, index| {
                if (auction.offered & b.bit(index) == 0) continue;
                var contenders: [15]usize = undefined;
                var count: usize = 0;
                for (0..auction.bidders.len) |id| if (new_bids[id] & b.bit(index) != 0) {
                    contenders[count] = id;
                    count += 1;
                };
                if (count == 0) continue;
                var chosen: usize = 0;
                if (count >= 2) {
                    state = @mod(48271 * state, 2147483647);
                    chosen = b.u(@mod(state, b.n(count)));
                }
                if (holders[index] != null) prices[index] += params.saa_increment;
                holders[index] = contenders[chosen];
                bid_counts[index] += count;
                bid_rounds[index] += 1;
                last_rounds[index] = round;
            }
            var standing: b.Text = .{};
            standing.add("STANDING", .{});
            for (items, 0..) |item, index| if (auction.offered & b.bit(index) != 0) standing.add(" {s}={d}@{s}",
                 .{ item.name, prices[index], if (holders[index]) |id| auction.bidders[id].name else "-" });
            lines.add("{s}", .{standing.value()});
        }
        var changed: b.Text = .{};
        var changes: usize = 0;
        for (auction.bidders, 0..) |bidder, id| if (activities[id] < eligibility[id]) {
            eligibility[id] = activities[id];
            changed.add(" {s}={d}", .{ bidder.name, eligibility[id] });
            changes += 1;
        };
        if (changes > 0) lines.add("ELIGIBILITY{s}", .{changed.value()});
        if (demand == 0) break;
        if (round == params.round_cap) {
            cap = true;
            break;
        }
    }
    lines.add("END rounds {d} {s}", .{ round, if (cap) "cap" else "quiet" });
    var result: Ascending = .{ .lines = .{}, .rounds = round, .cap = cap };
    for (items, 0..) |item, index| if (auction.offered & b.bit(index) != 0) {
        if (holders[index]) |id| lines.add("ITEM {s} price {d} holder {s} bids {d} rounds {d} last {d}",
             .{ item.name, prices[index], auction.bidders[id].name, bid_counts[index], bid_rounds[index],
             last_rounds[index] }) else {
            result.retained += item.reserve;
            lines.add("ITEM {s} unsold reserve {d}", .{ item.name, item.reserve });
        }
    };
    var values_total: i64 = 0;
    for (auction.bidders, 0..) |bidder, id| {
        var won: u16 = 0;
        var paid: i64 = 0;
        for (items, 0..) |_, index| if (auction.offered & b.bit(index) != 0 and holders[index] == id) {
            won |= b.bit(index);
            paid += prices[index];
        };
        const value = a.valueOf(choices[id], won);
        const utility = value - paid;
        result.payments[id] = paid;
        result.utilities[id] = utility;
        values_total += value;
        result.revenue += paid;
        if (utility < 0) {
            result.exposure -= utility;
            result.exposed += 1;
        }
        lines.add("BIDDER {s} won {s} paid {d} value {d} utility {d} eligibility {d}{s}", .{ bidder.name,
             r.bundle(won, items, "+"), paid, value, utility, eligibility[id], if (utility < 0) " exposed" else "" });
    }
    result.welfare = values_total + result.retained;
    lines.add("TOTAL revenue {d} welfare {d} efficiency {s} exposure {d} exposed {d}", .{ result.revenue,
         result.welfare, Fraction.init(result.welfare, optimum).text(), result.exposure, result.exposed });
    result.lines = lines;
    return result;
}
fn coalitionText(mask: u16, bidders: []const Bidder) []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (bidders, 0..) |bidder, id| if (mask & b.bit(id) != 0) b.append([]const u8, &names, bidder.name);
    return if (names.items.len == 0) "-" else b.join(names.items, "+");
}
const AuctionReports = struct { wdp: b.Lines, vcg: b.Lines, core: b.Lines, saa: b.Lines, summary: b.Lines,
     wdp_totals: [6]i64, revenues: [5]i64, core_totals: [6]i64, saa_totals: [5]i64 };
fn processAuction(auction: Auction, items: []const b.Item, params: b.Parameters) AuctionReports {
    const optimal = w.solve(items, auction.offered, auction.eligible, true);
    const exact = allocation(optimal.winning, auction.offered, items);
    const order = w.greedyOrder(auction.eligible);
    const greedy = allocation(w.greedySelect(order, null), auction.offered, items);
    const critical = pay.criticalPayments(order, greedy.winning, items);
    const vcg_details = pay.vcgPayments(items, auction.offered, auction.eligible, optimal, auction.bidders.len);
    var vcg_paid: [15]i64 = @splat(0);
    var vcg_utilities: [15]i64 = @splat(0);
    var critical_paid: [15]i64 = @splat(0);
    var critical_utilities: [15]i64 = @splat(0);
    var vcg_revenue: i64 = 0;
    var critical_revenue: i64 = 0;
    var utilities_total: i64 = 0;
    for (auction.bidders, 0..) |_, id| {
        if (vcg_details[id]) |details| vcg_paid[id] = details.payment;
        vcg_utilities[id] = exact.values[id] - vcg_paid[id];
        vcg_revenue += vcg_paid[id];
        utilities_total += vcg_utilities[id];
        for (greedy.winning) |bid| if (bid.bidder == id) {
            critical_paid[id] += criticalFor(critical, bid.number).payment;
        };
        critical_utilities[id] = greedy.values[id] - critical_paid[id];
        critical_revenue += critical_paid[id];
    }
    const saa = ascending(auction, items, params, exact.welfare);
    var wdp: b.Lines = .{};
    var vcg: b.Lines = .{};
    var core: b.Lines = .{};
    var summary: b.Lines = .{};
    wdp.add("AUCTION {s} items {d} bidders {d} bids {d} valid {d} eligible {d}", .{ auction.name,
         @popCount(auction.offered), auction.bidders.len, auction.bid_count, auction.valid.len,
         auction.eligible.len });
    for (auction.bidders) |bidder| wdp.add("BIDDER {s} {s} valid {d} eligible {d}", .{ bidder.name,
         if (bidder.xor) "XOR" else "OR", bidder.valid.items.len, bidder.eligible });
    for (auction.rejected) |rejected| wdp.add("REJECT {d} {s} {s}", .{ rejected.number, rejected.name,
         rejected.message });
    for (auction.below) |bid| wdp.add("BELOW_RESERVE {d} {s} value {d} reserve {d}", .{ bid.number,
         auction.bidders[bid.bidder].name, bid.amount, b.reserve(items, bid.bundle) });
    for (items, 0..) |item, index| if (auction.offered & b.bit(index) != 0) {
        const share = optimal.root.values[index];
        wdp.add("SHARE {s} {s} {s}", .{ item.name, share.value.text(), if (share.source) |number| b.fmt("bid {d}",
             .{number}) else "reserve" });
    };
    wdp.add("ROOT_BOUND {s}", .{optimal.root.bound.text()});
    for (optimal.improvements.items) |improvement| {
        var numbers: b.Text = .{};
        for (improvement.numbers[0..improvement.count], 0..) |number, index| numbers.add("{s}{d}",
             .{ if (index == 0) "" else "+", number });
        wdp.add("IMPROVE {d} welfare {d} bids {s}", .{ improvement.nodes, improvement.welfare,
             if (improvement.count == 0) "-" else numbers.value() });
    }
    wdp.add("OPTIMAL welfare {d} accepted {d} retained {d} winners {d}", .{ exact.welfare,
         exact.accepted, exact.retained, exact.winning.len });
    for (exact.winning) |bid| wdp.add("WIN {d} {s} {s} {d}", .{ bid.number, auction.bidders[bid.bidder].name,
         r.bundle(bid.bundle, items, "+"), bid.amount });
    wdp.add("UNSOLD {s}", .{r.bundle(exact.unsold, items, " ")});
    wdp.add("SEARCH nodes {d} pruned {d} leaves {d} improvements {d}", .{ optimal.nodes, optimal.pruned,
         optimal.leaves, optimal.improvements.items.len });
    var order_text: b.Text = .{};
    for (order, 0..) |bid, index| order_text.add("{s}{d}", .{ if (index == 0) "" else " ", bid.number });
    wdp.add("GREEDY_ORDER {s}", .{if (order.len == 0) "-" else order_text.value()});
    wdp.add("GREEDY welfare {d} accepted {d} retained {d} winners {d} efficiency {s}", .{ greedy.welfare,
         greedy.accepted, greedy.retained, greedy.winning.len, Fraction.init(greedy.welfare,
         exact.welfare).text() });
    for (greedy.winning) |bid| {
        const price = criticalFor(critical, bid.number);
        wdp.add("GWIN {d} {s} {s} {d} critical {d} against {s}", .{ bid.number, auction.bidders[bid.bidder].name,
             r.bundle(bid.bundle, items, "+"), bid.amount, price.payment, numberText(price.rival) });
    }
    wdp.add("GUNSOLD {s}", .{r.bundle(greedy.unsold, items, " ")});
    for (items, 0..) |item, index| if (auction.offered & b.bit(index) != 0) {
        var demand: usize = 0;
        for (auction.eligible) |bid| demand += @intFromBool(bid.bundle & b.bit(index) != 0);
        wdp.add("ITEM {s} reserve {d} demand {d} optimal {s} greedy {s}", .{ item.name, item.reserve,
             demand, if (exact.owners[index]) |id| auction.bidders[id].name else "-", if (greedy.owners[index]) |id| auction.bidders[id].name else "-" });
    };
    vcg.add("AUCTION {s} welfare {d}", .{ auction.name, exact.welfare });
    for (auction.bidders, 0..) |bidder, id| if (vcg_details[id]) |details| {
        var won: std.ArrayList(b.Bid) = .empty;
        for (exact.winning) |bid| if (bid.bidder == id) b.append(b.Bid, &won, bid);
        vcg.add("BIDDER {s} won {s} value {d} without {d} alternative {s} payment {d} utility {d}",
             .{ bidder.name, r.numbers(won.items), exact.values[id], details.alternative.welfare.?,
             r.numbers(details.alternative.winning), details.payment, vcg_utilities[id] });
    } else vcg.add("BIDDER {s} lost", .{bidder.name});
    vcg.add("TOTAL revenue {d} pay_as_bid {d} retained {d} seller {d} bidders {d}", .{ vcg_revenue,
         exact.accepted, exact.retained, vcg_revenue + exact.retained, utilities_total });
    for (auction.bidders, 0..) |bidder, id| vcg.add("PAYMENTS {s} vcg {d} pay_as_bid {d} greedy {d} critical {d} saa {d}",
         .{ bidder.name, vcg_paid[id], exact.values[id], greedy.values[id], critical_paid[id],
         saa.payments[id] });
    for (auction.bidders, 0..) |bidder, id| vcg.add("UTILITIES {s} vcg {d} critical {d} saa {d}",
         .{ bidder.name, vcg_utilities[id], critical_utilities[id], saa.utilities[id] });
    var core_totals: [6]i64 = @splat(0);
    core.add("AUCTION {s} bidders {d}", .{ auction.name, auction.bidders.len });
    if (auction.bidders.len > params.core_max_bidders) {
        core.add("SKIPPED", .{});
        core_totals[1] = 1;
    } else {
        core_totals[0] = 1;
        const coalitions = pay.coalitionWelfares(items, auction.offered, auction.eligible, auction.bidders.len);
        core.add("COALITIONS {d}", .{coalitions.len});
        const zeros: [15]i64 = @splat(0);
        const sellers = [4]i64{ vcg_revenue + exact.retained, greedy.welfare, critical_revenue + greedy.retained,
             saa.revenue + saa.retained };
        const utilities = [4][]const i64{ vcg_utilities[0..auction.bidders.len], zeros[0..auction.bidders.len],
             critical_utilities[0..auction.bidders.len], saa.utilities[0..auction.bidders.len] };
        for (outcomes, sellers, utilities, 0..) |name, seller, values, index| {
            var text: b.Text = .{};
            text.add("OUTCOME {s} seller {d} utilities", .{ name, seller });
            for (values) |value| text.add(" {d}", .{value});
            core.add("{s}", .{text.value()});
            const blocking = pay.blockingCoalitions(coalitions, seller, values);
            var minimal: usize = 0;
            var worst: ?pay.Blocking = null;
            for (blocking) |record| {
                if (worst == null or record.deficit > worst.?.deficit) worst = record;
                if (!record.minimal) continue;
                minimal += 1;
                core.add("BLOCK {s} welfare {d} payoff {d} deficit {d} bids {s}", .{ coalitionText(record.coalition.mask,
                     auction.bidders), record.coalition.welfare, record.payoff, record.deficit,
                     r.numbers(record.coalition.winning) });
            }
            if (worst) |record| core.add("RESULT blocked {d} minimal {d} max_deficit {d} by {s}",
                 .{ blocking.len, minimal, record.deficit, coalitionText(record.coalition.mask,
                 auction.bidders) }) else {
                core.add("RESULT core", .{});
                core_totals[index + 2] += 1;
            }
        }
    }
    const revenues = [5]i64{ vcg_revenue, exact.accepted, greedy.accepted, critical_revenue, saa.revenue };
    const welfares = [5]i64{ exact.welfare, exact.welfare, greedy.welfare, greedy.welfare, saa.welfare };
    for (mechanisms, revenues, welfares) |name, revenue, welfare| summary.add("{s}/{s},{d},{d},{s}",
         .{ auction.name, name, revenue, welfare, Fraction.init(welfare, exact.welfare).text() });
    return .{ .wdp = wdp, .vcg = vcg, .core = core, .saa = saa.lines, .summary = summary, .wdp_totals = .{ 1,
         b.n(auction.bid_count), b.n(auction.valid.len), b.n(auction.eligible.len), optimal.nodes,
         @intFromBool(greedy.welfare == exact.welfare) }, .revenues = revenues, .core_totals = core_totals,
         .saa_totals = .{ 1, b.n(saa.rounds), @intFromBool(saa.cap), b.n(saa.exposed), saa.exposure } };
}

fn duplicateName(participants: []const b.Participant) ?[]const u8 {
    for (participants, 0..) |participant, index| for (participants[0..index]) |earlier| if (b.eq(earlier.name,
         participant.name)) return participant.name;
    return null;
}
const GroupCheck = struct { message: ?[]const u8 = null, rates: []const Fraction = &.{} };
fn validateGroup(group: b.Group) GroupCheck {
    var rates: std.ArrayList(Fraction) = .empty;
    const participants = group.participants.items;
    if (group.slots) {
        for (group.arguments) |source| {
            const f = b.split(source, '/');
            if (f.len != 2 or !digits(f[0]) or !digits(f[1]) or f[0][0] == '0' or f[1][0] == '0') return .{ .message = b.fmt("bad ctr {s}",
                 .{source}) };
            const rate = Fraction.init(b.number(f[0]), b.number(f[1]));
            if (Fraction.integer(1).less(rate) or (rates.items.len > 0 and !rate.less(rates.items[rates.items.len - 1]))) return .{ .message = b.fmt("bad ctr {s}",
                 .{source}) };
            b.append(Fraction, &rates, rate);
        }
        if (participants.len == 0) return .{ .message = "no advertisers" };
        if (duplicateName(participants)) |name| return .{ .message = b.fmt("duplicate advertiser {s}", .{name}) };
    } else {
        if (participants.len == 0) return .{ .message = "no bidders" };
        if (duplicateName(participants)) |name| return .{ .message = b.fmt("duplicate bidder {s}", .{name}) };
        for (participants) |participant| if (participant.bid > participant.value) return .{ .message = b.fmt("bid above value {s}",
             .{participant.name}) };
    }
    return .{ .rates = rates.items };
}
const GroupReports = struct { lines: b.Lines, summary: b.Lines, totals: [6]i64 };
fn lot(group: b.Group, params: b.Parameters) GroupReports {
    const participants = group.participants.items;
    const reserve = b.number(group.arguments[0]);
    var first: ?usize = null;
    var efficient: ?usize = null;
    var optimum = reserve;
    for (participants, 0..) |participant, index| {
        if (participant.bid >= reserve and (first == null or participant.bid > participants[first.?].bid)) first = index;
        if (participant.value > optimum or (participant.value == optimum and efficient == null)) {
            optimum = participant.value;
            efficient = index;
        }
    }
    var second_price: i64 = 0;
    if (efficient != null) {
        second_price = reserve;
        for (participants, 0..) |participant, index| if (index != efficient and participant.value >= reserve) {
            second_price = @max(second_price, participant.value);
        };
    }
    const ascending_clock = a.english(participants, reserve, params.english_increment);
    const descending_clock = a.dutch(participants, reserve, params.dutch_start, params.dutch_decrement);
    const winners = [5]?usize{ first, efficient, ascending_clock.winner, descending_clock.winner, first };
    const first_price = if (first) |index| participants[index].bid else 0;
    const prices = [5]i64{ first_price, second_price, ascending_clock.price, descending_clock.price, first_price };
    var utilities: [5][20]i64 = @splat(@splat(0));
    var revenues: [5]i64 = @splat(0);
    var lines: b.Lines = .{};
    var summary: b.Lines = .{};
    lines.add("LOT {s} reserve {d} bidders {d} efficient {s} optimum {d}", .{ group.name, reserve,
         participants.len, if (efficient) |index| participants[index].name else "-", optimum });
    for (formats, labels, winners, prices, 0..) |name, label, winner, price, index| {
        var revenue = price;
        if (index == 4) {
            revenue = 0;
            for (participants, 0..) |participant, id| if (participant.bid >= reserve) {
                revenue += participant.bid;
                utilities[index][id] = -participant.bid;
            };
        }
        var welfare = reserve;
        var text: b.Text = .{};
        if (winner) |id| {
            utilities[index][id] = participants[id].value - price;
            welfare = participants[id].value;
            text.add("{s} winner {s} price {d} utility {d}", .{ label, participants[id].name,
                 price, utilities[index][id] });
        } else text.add("{s} unsold", .{label});
        if (index == 2 or index == 3) text.add(" steps {d}", .{if (index == 2) ascending_clock.steps else descending_clock.steps});
        const efficiency = Fraction.init(welfare, optimum);
        text.add(" revenue {d} welfare {d} efficiency {s}", .{ revenue, welfare, efficiency.text() });
        lines.add("{s}", .{text.value()});
        if (index == 2) {
            var drops: b.Text = .{};
            drops.add("ENGLISH_DROPS", .{});
            for (participants, ascending_clock.drops) |participant, drop| drops.add(" {s}={s}",
                 .{ participant.name, if (drop) |value| b.fmt("{d}", .{value}) else "-" });
            lines.add("{s}", .{drops.value()});
        }
        summary.add("{s}/{s},{d},{d},{s}", .{ group.name, name, revenue, welfare, efficiency.text() });
        revenues[index] = revenue;
    }
    for (participants, 0..) |participant, id| lines.add("UTILITY {s} {d} {d} {d} {d} {d}",
         .{ participant.name, utilities[0][id], utilities[1][id], utilities[2][id], utilities[3][id],
         utilities[4][id] });
    var ranking = [5]usize{ 0, 1, 2, 3, 4 };
    std.mem.sort(usize, &ranking, revenues, struct {
        fn less(values: [5]i64, left: usize, right: usize) bool {
            return if (values[left] == values[right]) left < right else values[left] > values[right];
        }
    }.less);
    var text: b.Text = .{};
    text.add("RANKING", .{});
    for (ranking) |index| text.add(" {s}", .{formats[index]});
    lines.add("{s}", .{text.value()});
    return .{ .lines = lines, .summary = summary, .totals = .{ 1, 0, 0, 0, 0, 0 } };
}
fn slots(group: b.Group, rates: []const Fraction) GroupReports {
    const ranked_bids = b.dupe(b.Participant, group.participants.items);
    const ranked_values = b.dupe(b.Participant, group.participants.items);
    std.mem.sort(b.Participant, ranked_bids, {}, struct {
        fn less(_: void, left: b.Participant, right: b.Participant) bool {
            return if (left.bid == right.bid) left.order < right.order else left.bid > right.bid;
        }
    }.less);
    std.mem.sort(b.Participant, ranked_values, {}, struct {
        fn less(_: void, left: b.Participant, right: b.Participant) bool {
            return if (left.value == right.value) left.order < right.order else left.value > right.value;
        }
    }.less);
    const count = ranked_bids.len;
    const slot_count = rates.len;
    var lines: b.Lines = .{};
    var summary: b.Lines = .{};
    lines.add("SLOTS {s} slots {d} advertisers {d}", .{ group.name, slot_count, count });
    var gsp_revenue: Fraction = .{};
    var gsp_welfare: Fraction = .{};
    var vcg_revenue: Fraction = .{};
    var optimum: Fraction = .{};
    for (0..@min(count, slot_count)) |rank| {
        const bidder = ranked_bids[rank];
        const rate = rates[rank];
        const price = pay.gspPrice(ranked_bids, rank);
        const payment = rate.scale(price);
        const utility = rate.scale(bidder.value - price);
        gsp_revenue = gsp_revenue.add(payment);
        gsp_welfare = gsp_welfare.add(rate.scale(bidder.value));
        optimum = optimum.add(rate.scale(ranked_values[rank].value));
        lines.add("GSP {d} {s} ctr {s} bid {d} price {d} payment {s} utility {s}", .{ rank + 1,
             bidder.name, rate.text(), bidder.bid, price, payment.text(), utility.text() });
    }
    const efficiency = gsp_welfare.divide(optimum);
    lines.add("GSP_TOTAL revenue {s} welfare {s} efficiency {s}", .{ gsp_revenue.text(), gsp_welfare.text(),
         efficiency.text() });
    for (0..@min(count, slot_count)) |rank| {
        const bidder = ranked_values[rank];
        const rate = rates[rank];
        const payment = pay.slotVcgPayment(ranked_values, rates, rank);
        vcg_revenue = vcg_revenue.add(payment);
        lines.add("VCG {d} {s} ctr {s} value {d} payment {s} price {s} utility {s}", .{ rank + 1,
             bidder.name, rate.text(), bidder.value, payment.text(), payment.divide(rate).text(),
             rate.scale(bidder.value).subtract(payment).text() });
    }
    lines.add("VCG_TOTAL revenue {s} welfare {s} efficiency 1", .{ vcg_revenue.text(), optimum.text() });
    var violations: usize = 0;
    for (1..@min(count, slot_count + 1)) |rank| {
        const bidder = ranked_bids[rank];
        const rate = if (rank < slot_count) rates[rank] else Fraction{};
        const stay = rate.scale(bidder.value - pay.gspPrice(ranked_bids, rank));
        const swap = rates[rank - 1].scale(bidder.value - bidder.bid);
        const violated = stay.less(swap);
        violations += @intFromBool(violated);
        lines.add("ENVY {d} {s} stay {s} swap {s} {s}", .{ rank + 1, bidder.name, stay.text(),
             swap.text(), if (violated) "violated" else "ok" });
    }
    if (violations == 0) lines.add("ENVY_FREE yes", .{}) else lines.add("ENVY_FREE no violations {d}", .{violations});
    var deviations: usize = 0;
    for (ranked_bids, 0..) |bidder, rank| {
        const rate = if (rank < slot_count) rates[rank] else Fraction{};
        const current = rate.scale(bidder.value - pay.gspPrice(ranked_bids, rank));
        for (rates, 0..) |target_rate, target| {
            if (target == rank) continue;
            const price = if (target < rank) (if (target < count) ranked_bids[target].bid else 0) else pay.gspPrice(ranked_bids,
                 target);
            const payoff = target_rate.scale(bidder.value - price);
            if (current.less(payoff)) {
                deviations += 1;
                lines.add("DEVIATE {s} from {d} to {d} gain {s}", .{ bidder.name, rank + 1,
                     target + 1, payoff.subtract(current).text() });
            }
        }
    }
    if (deviations == 0) lines.add("NASH yes", .{}) else lines.add("NASH no deviations {d}", .{deviations});
    const equilibrium = violations == 0 and deviations == 0;
    lines.add("EQUILIBRIUM {s}", .{if (equilibrium) "yes" else "no"});
    summary.add("{s}/gsp,{s},{s},{s}", .{ group.name, gsp_revenue.text(), gsp_welfare.text(), efficiency.text() });
    summary.add("{s}/vcg,{s},{s},1", .{ group.name, vcg_revenue.text(), optimum.text() });
    return .{ .lines = lines, .summary = summary, .totals = .{ 0, 1, 0, @intFromBool(violations == 0),
         @intFromBool(deviations == 0), @intFromBool(equilibrium) } };
}
fn addTotals(comptime count: usize, target: *[count]i64, values: [count]i64) void {
    for (target, values) |*total, value| total.* += value;
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    b.allocator = arena.allocator();
    const inputs = try b.read(init.io);
    const params = inputs.parameters;
    var wdp: b.Lines = .{};
    var vcg: b.Lines = .{};
    var core: b.Lines = .{};
    var ascending_lines: b.Lines = .{};
    var single: b.Lines = .{};
    var summary: b.Lines = .{};
    summary.add("mechanism,revenue,welfare,efficiency", .{});
    var wdp_totals: [6]i64 = @splat(0);
    var revenues: [5]i64 = @splat(0);
    var core_totals: [6]i64 = @splat(0);
    var saa_totals: [5]i64 = @splat(0);
    var group_totals: [6]i64 = @splat(0);
    for (params.runs) |name| {
        const persistent = b.allocator;
        var work: std.heap.ArenaAllocator = .init(init.gpa);
        defer work.deinit();
        b.allocator = work.allocator();
        const raw = inputs.auctions[b.indexOf(inputs.auctions, name)];
        const auction = validate(raw, inputs.items, params);
        const reports = processAuction(auction, inputs.items, params);
        b.allocator = persistent;
        wdp.extend(reports.wdp);
        vcg.extend(reports.vcg);
        core.extend(reports.core);
        ascending_lines.extend(reports.saa);
        summary.extend(reports.summary);
        addTotals(6, &wdp_totals, reports.wdp_totals);
        addTotals(5, &revenues, reports.revenues);
        addTotals(6, &core_totals, reports.core_totals);
        addTotals(5, &saa_totals, reports.saa_totals);
    }
    for (inputs.groups) |group| {
        const persistent = b.allocator;
        var work: std.heap.ArenaAllocator = .init(init.gpa);
        defer work.deinit();
        b.allocator = work.allocator();
        const checked = validateGroup(group);
        var reports: GroupReports = undefined;
        if (checked.message) |message| {
            var lines: b.Lines = .{};
            lines.add("{s} {s} ERROR {s}", .{ if (group.slots) "SLOTS" else "LOT", group.name, message });
            reports = .{ .lines = lines, .summary = .{}, .totals = .{ @intFromBool(!group.slots),
                 @intFromBool(group.slots), 1, 0, 0, 0 } };
        } else reports = if (group.slots) slots(group, checked.rates) else lot(group, params);
        b.allocator = persistent;
        single.extend(reports.lines);
        summary.extend(reports.summary);
        addTotals(6, &group_totals, reports.totals);
    }
    wdp.add("TOTAL auctions {d} bids {d} valid {d} eligible {d} nodes {d} greedy_optimal {d}",
         .{ wdp_totals[0], wdp_totals[1], wdp_totals[2], wdp_totals[3], wdp_totals[4], wdp_totals[5] });
    vcg.add("OVERALL vcg {d} pay_as_bid {d} greedy {d} critical {d} saa {d}", .{ revenues[0],
         revenues[1], revenues[2], revenues[3], revenues[4] });
    core.add("SUMMARY checked {d} skipped {d} vcg {d} greedy {d} critical {d} saa {d}", .{ core_totals[0],
         core_totals[1], core_totals[2], core_totals[3], core_totals[4], core_totals[5] });
    ascending_lines.add("SUMMARY auctions {d} rounds {d} capped {d} exposed {d} exposure {d}",
         .{ saa_totals[0], saa_totals[1], saa_totals[2], saa_totals[3], saa_totals[4] });
    single.add("SUMMARY lots {d} slot_groups {d} errors {d} envy_free {d} nash {d} equilibria {d}",
         .{ group_totals[0], group_totals[1], group_totals[2], group_totals[3], group_totals[4],
         group_totals[5] });
    try r.write(init.io, "wdp.txt", wdp);
    try r.write(init.io, "vcg.txt", vcg);
    try r.write(init.io, "core_check.txt", core);
    try r.write(init.io, "ascending_log.txt", ascending_lines);
    try r.write(init.io, "single_item.txt", single);
    try r.write(init.io, "summary.csv", summary);
}
