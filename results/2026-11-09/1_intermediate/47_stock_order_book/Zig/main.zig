const std = @import("std");
const A = std.mem.Allocator;
const Text = []const u8;
const I = i64;
const Kind = enum {
    LIMIT,
    MARKET,
    STOP,
    STOPLIMIT,
    ICEBERG,
};
const Status = enum {
    PENDING,
    OPEN,
    PARTIAL,
    FILLED,
    CANCELLED,
};
const Condition = enum {
    none,
    IOC,
    FOK,
    POSTONLY,
};
const Verb = enum {
    LIMIT,
    MARKET,
    STOP,
    STOPLIMIT,
    ICEBERG,
    CANCEL,
    REPLACE,
    CANCELALL,
    HALT,
    RESUME,
    RISK,
    FEE,
    BAND,
    TICK,
    LOT,
    BOOK,
    ORDERS,
    STATUS,
    HISTORY,
    POSITION,
    FILLS,
    LAST,
    VWAP,
    SPREAD,
    IMPACT,
    TRADES,
    BARS,
    RANK,
    FLOW,
    SUMMARY,
};
const Order = struct {
    id: Text,
    trader: usize,
    kind: Kind,
    sell: bool,
    price: I = -1,
    trigger: I = 0,
    peak: I = 0,
    quantity: I,
    remaining: I,
    visible: I = 0,
    filled: I = 0,
    value: I = 0,
    priority: I = 0,
    status: Status = .PENDING,
    condition: Condition = .none,
    history: std.ArrayList(Text) = .empty,
};
const Trader = struct {
    name: Text,
    bought: I = 0,
    sold: I = 0,
    cash: I = 0,
    fees: I = 0,
    limit: ?I = null,
};
const Trade = struct {
    price: I,
    quantity: I,
    buy: usize,
    sell: usize,
    taker: usize,
    buy_fee: I,
    sell_fee: I,
};
const Level = struct {
    price: I,
    visible: I = 0,
    count: usize = 0,
};

fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn number(s: Text) I {
    return std.fmt.parseInt(I, s, 10) catch unreachable;
}

fn abs(x: I) I {
    return if (x < 0) -x else x;
}

fn resting(o: Order) bool {
    return o.status == .OPEN or o.status == .PARTIAL;
}

fn active(o: Order) bool {
    return resting(o) or o.status == .PENDING;
}

fn matchable(sell: bool, price: I, other: I) bool {
    return price < 0 or (if (sell) other >= price else other <= price);
}
const Engine = struct {
    gpa: A,
    out: *std.Io.Writer,
    orders: std.ArrayList(Order) = .empty,
    traders: std.ArrayList(Trader) = .empty,
    trades: std.ArrayList(Trade) = .empty,
    priority: I = 0,
    maker: I = 0,
    taker: I = 0,
    band: I = 0,
    tick: I = 1,
    lot: I = 1,
    halted: bool = false,

    fn format(e: *Engine, comptime f: Text, args: anytype) !Text {
        return std.fmt.allocPrint(e.gpa, f, args);
    }

    fn line(e: *Engine, comptime f: Text, args: anytype) !void {
        try e.out.print(f ++ "\n", args);
    }

    fn history(e: *Engine, i: usize, comptime f: Text, args: anytype) !void {
        const text = try e.format(f, args);
        try e.orders.items[i].history.append(e.gpa, text);
    }

    fn findOrder(e: *const Engine, id: Text) ?usize {
        for (e.orders.items, 0..) |o, i| if (eq(o.id, id)) return i;
        return null;
    }

    fn findTrader(e: *const Engine, name: Text) ?usize {
        for (e.traders.items, 0..) |t, i| if (eq(t.name, name)) return i;
        return null;
    }

    fn register(e: *Engine, name: Text) !usize {
        if (e.findTrader(name)) |i| return i;
        const i = e.traders.items.len;
        try e.traders.append(e.gpa, .{ .name = name });
        return i;
    }

    fn last(e: *const Engine) I {
        return if (e.trades.items.len == 0) 0 else e.trades.items[e.trades.items.len - 1].price;
    }

    fn net(e: *const Engine, t: usize) I {
        return e.traders.items[t].bought - e.traders.items[t].sold;
    }

    fn pnl(e: *const Engine, t: usize) I {
        return e.traders.items[t].cash + e.net(t) * e.last();
    }

    fn exposure(e: *const Engine, t: usize, sell: bool, exclude: ?usize) I {
        var value = if (sell) -e.net(t) else e.net(t);
        for (e.orders.items, 0..) |o, i| {
            if (exclude != null and exclude.? == i) continue;
            if (active(o) and o.trader == t and o.sell == sell) value += o.remaining;
        }
        return value;
    }

    fn risk(e: *const Engine, t: ?usize, sell: bool, q: I, exclude: ?usize) bool {
        if (t) |i| {
            if (e.traders.items[i].limit) |limit| return e.exposure(i, sell, exclude) + q > limit;
        }
        return false;
    }

    fn outside(e: *const Engine, p: I) bool {
        return e.band > 0 and e.trades.items.len > 0 and abs(p - e.last()) > e.band;
    }

    fn best(e: *const Engine, sell: bool) ?usize {
        var result: ?usize = null;
        for (e.orders.items, 0..) |o, i| {
            if (!resting(o) or o.sell != sell) continue;
            if (result) |b| {
                const previous = e.orders.items[b];
                if ((if (sell) o.price < previous.price else o.price > previous.price) or (o.price == previous.price and o.priority < previous.priority)) result = i;
            } else result = i;
        }
        return result;
    }

    fn decimal(e: *Engine, value: I) !Text {
        return e.format("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
    }

    fn orderLine(e: *Engine, i: usize) !void {
        const o = e.orders.items[i];
        try e.line("ORDER {s} {s} {d}/{d}", .{ o.id, @tagName(o.status), o.filled, o.quantity });
    }

    fn details(e: *Engine, i: usize) !void {
        const o = e.orders.items[i];
        const p = if (o.price < 0) "-" else try e.format("{d}", .{o.price});
        const avg = if (o.filled == 0) "-" else try e.decimal(@divTrunc(o.value * 100, o.filled));
        try e.out.print("{s} {s} {s} {s} {s} {s} {d}/{d} avg {s}", .{ o.id, e.traders.items[o.trader].name, @tagName(o.kind), if (o.sell) "SELL" else "BUY", p, @tagName(o.status), o.filled, o.quantity, avg });
        if (o.kind == .STOP or o.kind == .STOPLIMIT) try e.out.print(" trigger {d}", .{o.trigger});
        try e.out.writeByte('\n');
    }

    fn position(e: *Engine, i: usize) !void {
        const t = e.traders.items[i];
        try e.line("POSITION {s} bought {d} sold {d} net {d} cash {d} fees {d} pnl {d}", .{ t.name, t.bought, t.sold, e.net(i), t.cash, t.fees, e.pnl(i) });
    }

    fn tradeLine(e: *Engine, i: usize) !void {
        const x = e.trades.items[i];
        const b = e.orders.items[x.buy];
        const s = e.orders.items[x.sell];
        try e.line("TRADE {d} {d} {d} {s} {s} {s} {s}", .{ i + 1, x.price, x.quantity, b.id, e.traders.items[b.trader].name, s.id, e.traders.items[s.trader].name });
    }

    fn executeOrder(e: *Engine, i: usize) !void {
        while (e.orders.items[i].remaining > 0) {
            const incoming = e.orders.items[i];
            const j = e.best(!incoming.sell) orelse break;
            const resting_order = e.orders.items[j];
            if (!matchable(incoming.sell, incoming.price, resting_order.price)) break;
            if (incoming.trader == resting_order.trader) {
                try e.line("STP {s} {d}", .{ resting_order.id, resting_order.remaining });
                try e.history(j, "STP {d}", .{resting_order.remaining});
                e.orders.items[j].remaining = 0;
                e.orders.items[j].visible = 0;
                e.orders.items[j].status = .CANCELLED;
                continue;
            }
            const q = @min(incoming.remaining, resting_order.visible);
            const p = resting_order.price;
            const bi = if (incoming.sell) j else i;
            const si = if (incoming.sell) i else j;
            const bf = q * (if (bi == i) e.taker else e.maker);
            const sf = q * (if (si == i) e.taker else e.maker);
            try e.trades.append(e.gpa, .{ .price = p, .quantity = q, .buy = bi, .sell = si, .taker = i, .buy_fee = bf, .sell_fee = sf });
            for ([_]usize{ i, j }) |affected| {
                e.orders.items[affected].remaining -= q;
                e.orders.items[affected].filled += q;
                e.orders.items[affected].value += q * p;
                try e.history(affected, "FILL {d} {d} {d}", .{ e.trades.items.len, p, q });
            }
            e.orders.items[j].visible -= q;
            const buyer = e.orders.items[bi].trader;
            const seller = e.orders.items[si].trader;
            e.traders.items[buyer].bought += q;
            e.traders.items[buyer].cash -= q * p + bf;
            e.traders.items[buyer].fees += bf;
            e.traders.items[seller].sold += q;
            e.traders.items[seller].cash += q * p - sf;
            e.traders.items[seller].fees += sf;
            try e.tradeLine(e.trades.items.len - 1);
            if (e.orders.items[j].remaining == 0) e.orders.items[j].status = .FILLED else {
                e.orders.items[j].status = .PARTIAL;
                if (e.orders.items[j].visible == 0) {
                    e.priority += 1;
                    e.orders.items[j].priority = e.priority;
                    const visible = @min(resting_order.peak, e.orders.items[j].remaining);
                    const hidden = e.orders.items[j].remaining - visible;
                    e.orders.items[j].visible = visible;
                    try e.history(j, "REFRESH {d} {d}", .{ visible, hidden });
                    try e.line("REFRESH {s} {d} {d}", .{ resting_order.id, visible, hidden });
                }
            }
        }
    }

    fn finish(e: *Engine, i: usize, stay: bool) !void {
        if (e.orders.items[i].remaining == 0) e.orders.items[i].status = .FILLED else if (stay) {
            e.priority += 1;
            e.orders.items[i].priority = e.priority;
            const o = e.orders.items[i];
            const visible = if (o.kind == .ICEBERG) @min(o.peak, o.remaining) else o.remaining;
            e.orders.items[i].visible = visible;
            e.orders.items[i].status = if (o.filled > 0) .PARTIAL else .OPEN;
            try e.history(i, "REST {d} {d}", .{ o.price, visible });
        } else {
            try e.history(i, "EXPIRE {d}", .{e.orders.items[i].remaining});
            e.orders.items[i].remaining = 0;
            e.orders.items[i].visible = 0;
            e.orders.items[i].status = .CANCELLED;
        }
        try e.orderLine(i);
    }

    fn triggers(e: *Engine) !void {
        while (e.trades.items.len > 0) {
            var selected: [1000]usize = undefined;
            var n: usize = 0;
            const p = e.last();
            for (e.orders.items, 0..) |o, i| if (o.status == .PENDING and (if (o.sell) p <= o.trigger else p >= o.trigger)) {
                selected[n] = i;
                n += 1;
            };
            if (n == 0) break;
            for (selected[0..n]) |i| e.orders.items[i].status = .CANCELLED;
            for (selected[0..n]) |i| {
                try e.line("TRIGGER {s}", .{e.orders.items[i].id});
                try e.history(i, "TRIGGER", .{});
                try e.executeOrder(i);
                try e.finish(i, e.orders.items[i].kind == .STOPLIMIT);
            }
        }
    }

    fn cancel(e: *Engine, i: usize) !void {
        try e.history(i, "CANCEL {d}", .{e.orders.items[i].remaining});
        e.orders.items[i].remaining = 0;
        e.orders.items[i].visible = 0;
        e.orders.items[i].status = .CANCELLED;
        try e.orderLine(i);
    }

    fn levels(e: *Engine, sell: bool) ![]Level {
        var result: std.ArrayList(Level) = .empty;
        for (e.orders.items) |o| if (resting(o) and o.sell == sell) {
            var index: ?usize = null;
            for (result.items, 0..) |v, j| if (v.price == o.price) {
                index = j;
                break;
            };
            if (index == null) {
                index = result.items.len;
                try result.append(e.gpa, .{ .price = o.price });
            }
            result.items[index.?].visible += o.visible;
            result.items[index.?].count += 1;
        };
        for (0..result.items.len) |i| {
            const value = result.items[i];
            var j = i;
            while (j > 0 and result.items[j - 1].price > value.price) : (j -= 1) result.items[j] = result.items[j - 1];
            result.items[j] = value;
        }
        return result.items;
    }

    fn reject(e: *Engine, id: Text, reason: Text) !void {
        try e.line("REJECT {s} {s}", .{ id, reason });
    }

    fn fail(e: *Engine, reason: Text) !void {
        try e.line("ERROR {s}", .{reason});
    }

    fn newOrder(e: *Engine, w: []const Text, kind: Kind) !void {
        const sell = eq(w[3], "SELL");
        const t = e.findTrader(w[2]);
        var p: I = -1;
        var r: I = 0;
        var q: I = 0;
        var peak: I = 0;
        var condition: Condition = .none;
        switch (kind) {
            .LIMIT, .ICEBERG => {
                p = number(w[4]);
                q = number(w[5]);
                if (kind == .ICEBERG) peak = number(w[6]) else if (w.len == 7) condition = std.meta.stringToEnum(Condition, w[6]).?;
            },
            .MARKET => q = number(w[4]),
            .STOP => {
                r = number(w[4]);
                q = number(w[5]);
            },
            .STOPLIMIT => {
                r = number(w[4]);
                p = number(w[5]);
                q = number(w[6]);
            },
        }
        const stop = kind == .STOP or kind == .STOPLIMIT;
        var reason: ?Text = null;
        if (e.halted) reason = "halted" else if (e.findOrder(w[1]) != null) reason = "duplicate id" else if (p == 0 or (stop and r == 0)) reason = "invalid price" else if (q == 0) reason = "invalid quantity" else if ((p >= 0 and @mod(p, e.tick) != 0) or (stop and @mod(r, e.tick) != 0)) reason = "invalid tick" else if (@mod(q, e.lot) != 0) reason = "invalid lot" else if (kind == .ICEBERG and (peak == 0 or peak > q or @mod(peak, e.lot) != 0)) reason = "invalid peak" else if (stop and e.trades.items.len > 0 and (if (sell) r >= e.last() else r <= e.last())) reason = "invalid trigger" else if (p >= 0 and e.outside(p)) reason = "outside band" else if (e.risk(t, sell, q, null)) reason = "risk limit";
        if (reason == null and condition == .POSTONLY) {
            if (e.best(!sell)) |j| if (matchable(sell, p, e.orders.items[j].price)) {
                reason = "would cross";
            };
        }
        if (reason == null and condition == .FOK) {
            var available: I = 0;
            for (e.orders.items) |o| if (resting(o) and o.sell != sell and (t == null or o.trader != t.?) and matchable(sell, p, o.price)) {
                available += o.remaining;
            };
            if (available < q) reason = "unfillable";
        }
        if (reason) |text| return e.reject(w[1], text);
        const trader = try e.register(w[2]);
        const i = e.orders.items.len;
        try e.orders.append(e.gpa, .{ .id = w[1], .trader = trader, .kind = kind, .sell = sell, .price = p, .trigger = r, .peak = peak, .quantity = q, .remaining = q, .condition = condition });
        try e.history(i, "ACCEPT", .{});
        if (stop) try e.orderLine(i) else {
            if (condition != .POSTONLY) try e.executeOrder(i);
            try e.finish(i, kind == .ICEBERG or (kind == .LIMIT and condition != .IOC));
            try e.triggers();
        }
    }

    fn command(e: *Engine, w: []const Text) !void {
        const verb = std.meta.stringToEnum(Verb, w[0]).?;
        switch (verb) {
            .LIMIT, .MARKET, .STOP, .STOPLIMIT, .ICEBERG => return e.newOrder(w, std.meta.stringToEnum(Kind, w[0]).?),
            .CANCEL, .REPLACE => {
                const replace = verb == .REPLACE;
                if (replace and e.halted) return e.reject(w[1], "halted");
                const i = e.findOrder(w[1]) orelse return e.reject(w[1], "unknown order");
                const o = e.orders.items[i];
                if (if (replace) !resting(o) else !active(o)) return e.reject(w[1], "not open");
                if (!replace) return e.cancel(i);
                const p = number(w[2]);
                const q = number(w[3]);
                const reason: ?Text = if (p == 0) "invalid price" else if (q == 0) "invalid quantity" else if (p != o.price and @mod(p, e.tick) != 0) "invalid tick" else if (@mod(q, e.lot) != 0) "invalid lot" else if (p == o.price and q == o.remaining) "no change" else if (p != o.price and e.outside(p)) "outside band" else if (q > o.remaining and e.risk(o.trader, o.sell, q, i)) "risk limit" else null;
                if (reason) |text| return e.reject(w[1], text);
                const kept = p == o.price and q < o.remaining;
                const mode: Text = if (kept) "kept" else "lost";
                e.orders.items[i].quantity = o.filled + q;
                e.orders.items[i].remaining = q;
                try e.history(i, "REPLACE {d} {d} {s}", .{ p, q, mode });
                try e.line("REPLACE {s} {s}", .{ o.id, mode });
                if (kept) {
                    e.orders.items[i].visible = @min(o.visible, q);
                    try e.orderLine(i);
                } else {
                    e.orders.items[i].status = .CANCELLED;
                    e.orders.items[i].price = p;
                    try e.executeOrder(i);
                    try e.finish(i, true);
                    try e.triggers();
                }
            },
            .HALT, .RESUME => {
                const h = verb == .HALT;
                if (e.halted == h) return e.fail(if (h) "already halted" else "not halted");
                e.halted = h;
                try e.line("{s}", .{w[0]});
            },
            .RISK => {
                const t = try e.register(w[1]);
                const limit = number(w[2]);
                e.traders.items[t].limit = limit;
                try e.line("RISK {s} {d} exposure buy {d} sell {d}", .{ w[1], limit, e.exposure(t, false, null), e.exposure(t, true, null) });
            },
            .FEE => {
                const a = number(w[1]);
                const b = number(w[2]);
                if (a + b < 0) return e.fail("invalid fee");
                e.maker = a;
                e.taker = b;
                try e.line("FEE maker {d} taker {d}", .{ a, b });
            },
            .BAND, .TICK, .LOT => {
                const v = number(w[1]);
                if (verb != .BAND and v == 0) return e.fail("invalid size");
                switch (verb) {
                    .BAND => e.band = v,
                    .TICK => e.tick = v,
                    else => e.lot = v,
                }
                try e.line("{s} {d}", .{ w[0], v });
            },
            .CANCELALL, .ORDERS, .POSITION, .FILLS => {
                const t = e.findTrader(w[1]) orelse return e.fail("unknown trader");
                if (verb == .POSITION) return e.position(t);
                var count: usize = 0;
                if (verb == .FILLS) {
                    for (e.trades.items) |x| if (e.orders.items[x.buy].trader == t or e.orders.items[x.sell].trader == t) {
                        count += 1;
                    };
                    try e.line("FILLS {s} {d}", .{ w[1], count });
                    var cumulative: I = 0;
                    for (e.trades.items, 0..) |x, j| {
                        const buy = e.orders.items[x.buy].trader == t;
                        const own = if (buy) x.buy else x.sell;
                        if (e.orders.items[own].trader != t) continue;
                        cumulative += if (buy) x.quantity else -x.quantity;
                        try e.line("{d} {s} {d} {d} {s} {s} fee {d} net {d}", .{ j + 1, if (buy) "BUY" else "SELL", x.price, x.quantity, e.orders.items[own].id, if (own == x.taker) "TAKER" else "MAKER", if (buy) x.buy_fee else x.sell_fee, cumulative });
                    }
                } else {
                    for (e.orders.items) |o| if (active(o) and o.trader == t) {
                        count += 1;
                    };
                    try e.line("{s} {s} {d}", .{ w[0], w[1], count });
                    for (0..e.orders.items.len) |i| if (active(e.orders.items[i]) and e.orders.items[i].trader == t) {
                        if (verb == .CANCELALL) try e.cancel(i) else try e.details(i);
                    };
                }
            },
            .STATUS, .HISTORY => {
                const i = e.findOrder(w[1]) orelse return e.fail("unknown order");
                if (verb == .STATUS) {
                    try e.out.writeAll("STATUS ");
                    try e.details(i);
                } else {
                    try e.line("HISTORY {s} {d}", .{ w[1], e.orders.items[i].history.items.len });
                    for (e.orders.items[i].history.items) |text| try e.line("{s}", .{text});
                }
            },
            .BOOK => {
                const depth: usize = @intCast(number(w[1]));
                if (depth == 0) return e.fail("invalid depth");
                const bids = try e.levels(false);
                const asks = try e.levels(true);
                try e.line("BOOK bids {d} asks {d}", .{ bids.len, asks.len });
                const n = @min(depth, asks.len);
                for (0..n) |j| {
                    const v = asks[n - j - 1];
                    try e.line("ASK {d} {d} {d}", .{ v.price, v.visible, v.count });
                }
                for (0..@min(depth, bids.len)) |j| {
                    const v = bids[bids.len - j - 1];
                    try e.line("BID {d} {d} {d}", .{ v.price, v.visible, v.count });
                }
            },
            .IMPACT => {
                const sell = eq(w[1], "SELL");
                const q = number(w[2]);
                if (q == 0) return e.fail("invalid quantity");
                const book = try e.levels(!sell);
                var remainder = q;
                var cost: I = 0;
                var total: I = 0;
                var worst: I = 0;
                var used: usize = 0;
                for (0..book.len) |j| {
                    const v = book[if (sell) book.len - j - 1 else j];
                    total += v.visible;
                    if (remainder > 0) {
                        const taken = @min(remainder, v.visible);
                        remainder -= taken;
                        cost += taken * v.price;
                        worst = v.price;
                        used += 1;
                    }
                }
                if (remainder > 0) try e.line("IMPACT {s} {d} insufficient {d}", .{ w[1], q, total }) else try e.line("IMPACT {s} {d} avg {s} worst {d} levels {d}", .{ w[1], q, try e.decimal(@divTrunc(cost * 100, q)), worst, used });
            },
            .LAST => {
                if (e.trades.items.len == 0) try e.line("LAST none", .{}) else try e.line("LAST {d} {d}", .{ e.last(), e.trades.items[e.trades.items.len - 1].quantity });
            },
            .SPREAD => {
                const bi = e.best(false);
                const si = e.best(true);
                const b = if (bi) |i| try e.format("{d}", .{e.orders.items[i].price}) else "none";
                const a = if (si) |i| try e.format("{d}", .{e.orders.items[i].price}) else "none";
                try e.out.print("SPREAD bid {s} ask {s}", .{ b, a });
                if (bi != null and si != null) {
                    const bp = e.orders.items[bi.?].price;
                    const ap = e.orders.items[si.?].price;
                    try e.out.print(" spread {d} mid {d}.{d}", .{ ap - bp, @divTrunc(ap + bp, 2), if (@mod(ap + bp, 2) == 0) @as(I, 0) else @as(I, 5) });
                }
                try e.out.writeByte('\n');
            },
            .TRADES, .BARS => {
                const k: usize = @intCast(number(w[1]));
                if (k == 0) return e.fail("invalid count");
                const n = e.trades.items.len;
                if (verb == .TRADES) {
                    const shown = @min(k, n);
                    try e.line("TRADES {d} of {d}", .{ shown, n });
                    for (n - shown..n) |i| try e.tradeLine(i);
                } else {
                    try e.line("BARS {d}", .{(n + k - 1) / k});
                    var start: usize = 0;
                    var group: usize = 1;
                    while (start < n) : (group += 1) {
                        const end = @min(start + k, n);
                        var high: I = 0;
                        var low = e.trades.items[start].price;
                        var volume: I = 0;
                        for (e.trades.items[start..end]) |x| {
                            high = @max(high, x.price);
                            low = @min(low, x.price);
                            volume += x.quantity;
                        }
                        try e.line("{d} open {d} high {d} low {d} close {d} volume {d}", .{ group, e.trades.items[start].price, high, low, e.trades.items[end - 1].price, volume });
                        start = end;
                    }
                }
            },
            .FLOW => {
                var buy: I = 0;
                var sell: I = 0;
                for (e.trades.items) |x| {
                    if (e.orders.items[x.taker].sell) sell += x.quantity else buy += x.quantity;
                }
                try e.line("FLOW buy {d} sell {d} net {d}", .{ buy, sell, buy - sell });
            },
            .VWAP, .SUMMARY => {
                const n = e.trades.items.len;
                var volume: I = 0;
                var cost: I = 0;
                var fees: I = 0;
                var high: I = 0;
                var low: I = if (n == 0) 0 else e.trades.items[0].price;
                for (e.trades.items) |x| {
                    volume += x.quantity;
                    cost += x.price * x.quantity;
                    fees += x.buy_fee + x.sell_fee;
                    high = @max(high, x.price);
                    low = @min(low, x.price);
                }
                if (verb == .VWAP) {
                    if (n == 0) try e.line("VWAP none", .{}) else try e.line("VWAP {s} volume {d} trades {d}", .{ try e.decimal(@divTrunc(cost * 100, volume)), volume, n });
                } else {
                    if (n == 0) try e.line("SUMMARY trades 0", .{}) else try e.line("SUMMARY trades {d} volume {d} open {d} high {d} low {d} close {d} fees {d}", .{ n, volume, e.trades.items[0].price, high, low, e.last(), fees });
                    try e.traderListing(false);
                }
            },
            .RANK => try e.traderListing(true),
        }
    }

    fn before(e: *Engine, a: usize, b: usize, ranked: bool) bool {
        if (ranked) {
            if (e.pnl(a) != e.pnl(b)) return e.pnl(a) > e.pnl(b);
            const av = e.traders.items[a].bought + e.traders.items[a].sold;
            const bv = e.traders.items[b].bought + e.traders.items[b].sold;
            if (av != bv) return av > bv;
        }
        return std.mem.order(u8, e.traders.items[a].name, e.traders.items[b].name) == .lt;
    }

    fn traderListing(e: *Engine, ranked: bool) !void {
        var ids: [2000]usize = undefined;
        const n = e.traders.items.len;
        for (0..n) |i| {
            var j = i;
            while (j > 0 and e.before(i, ids[j - 1], ranked)) : (j -= 1) ids[j] = ids[j - 1];
            ids[j] = i;
        }
        if (ranked) try e.line("RANK {d}", .{n});
        for (ids[0..n], 0..) |i, rank| {
            if (ranked) try e.line("{d} {s} pnl {d} volume {d}", .{ rank + 1, e.traders.items[i].name, e.pnl(i), e.traders.items[i].bought + e.traders.items[i].sold }) else try e.position(i);
        }
    }
};

fn readLine(reader: *std.Io.Reader, gpa: A) !?Text {
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try reader.streamDelimiterEnding(&buffer.writer, '\n');
    if (reader.bufferedLen() == 0 and buffer.written().len == 0) return null;
    if (reader.bufferedLen() > 0) reader.toss(1);
    return try buffer.toOwnedSlice();
}

pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var engine: Engine = .{ .gpa = gpa, .out = &output.interface };
    const first = (try readLine(&input.interface, gpa)).?;
    const n: usize = @intCast(number(std.mem.trim(u8, first, "\r")));
    for (0..n) |_| {
        const text = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
        var words: [10]Text = undefined;
        var count: usize = 0;
        var it = std.mem.splitScalar(u8, text, ' ');
        while (it.next()) |word| {
            words[count] = word;
            count += 1;
        }
        try engine.command(words[0..count]);
    }
    try output.interface.flush();
}
