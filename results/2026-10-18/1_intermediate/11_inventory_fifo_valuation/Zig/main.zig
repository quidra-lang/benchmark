const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const categories = [_][]const u8{ "received", "returned", "adjusted-in", "adjusted-out", "shipped", "written-down", "expired", "recalled" };
fn integer(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch unreachable;
}
fn amount(s: []const u8) i64 {
    const dot = std.mem.findScalar(u8, s, '.').?;
    return integer(s[0..dot]) * 100 + integer(s[dot + 1 ..]);
}
const Warehouse = struct {
    code: []const u8,
    index: usize,
};
const CardEntry = struct {
    day: i64,
    kind: []const u8,
    warehouse: *Warehouse,
    quantity: i64,
    value: i64,
};
const Item = struct {
    code: []const u8,
    name: []const u8,
    level: i64,
    last_cost: ?i64 = null,
    order_count: usize = 0,
    sold: i64 = 0,
    revenue: i64 = 0,
    cogs: i64 = 0,
    lots: std.ArrayList(*Lot) = .empty,
    card: std.ArrayList(CardEntry) = .empty,
};
const Lot = struct {
    number: usize,
    item: *Item,
    day: i64,
    initial_quantity: i64,
    initial_cost: i64,
    warehouse: *Warehouse,
    kind: []const u8,
    cost: i64,
    removed: i64 = 0,
    held: [20]i64 = @splat(0),
};
const Part = struct {
    lot: *Lot,
    quantity: i64,
    cost: i64,
};
const Issue = struct {
    parts: []Part,
    cost: i64,
};
const Order = struct {
    number: usize,
    warehouse: *Warehouse,
    item: *Item,
    day: i64,
    price: i64,
    ordered: i64,
    shipped: i64 = 0,
    backorder: i64,
    cancelled: i64 = 0,
    returned: i64 = 0,
    revenue: i64 = 0,
    cogs: i64 = 0,
    issues: std.ArrayList(Part) = .empty,
};
const Stock = struct {
    quantity: i64 = 0,
    value: i64 = 0,
};
fn held(lot: *Lot, w: ?*Warehouse) i64 {
    if (w) |warehouse| return lot.held[warehouse.index];
    var total: i64 = 0;
    for (lot.held) |q| total += q;
    return total;
}
fn stock(item: *Item, w: ?*Warehouse) Stock {
    var result: Stock = .{};
    for (item.lots.items) |lot| {
        const q = held(lot, w);
        result.quantity += q;
        result.value += q * lot.cost;
    }
    return result;
}
const Inventory = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    day: i64 = 1,
    warehouses: std.StringArrayHashMapUnmanaged(*Warehouse) = .empty,
    items: std.StringArrayHashMapUnmanaged(*Item) = .empty,
    lots: std.ArrayList(*Lot) = .empty,
    orders: std.ArrayList(*Order) = .empty,
    quantities: [8]i64 = @splat(0),
    values: [8]i64 = @splat(0),
    fn fail(self: *Inventory, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn money(self: *Inventory, c: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(if (c < 0) -c else c);
        return std.fmt.allocPrint(self.gpa, "{s}{d}.{d:0>2}", .{ if (c < 0) "-" else "", u / 100, u % 100 });
    }
    fn margin(self: *Inventory, profit: i64, revenue: i64) Allocator.Error![]const u8 {
        if (revenue == 0) return "n/a";
        const q = @divTrunc(@as(i64, @intCast(@abs(profit))) * 1000, revenue);
        return std.fmt.allocPrint(self.gpa, "{s}{d}.{d}%", .{ if (profit < 0 and q > 0) "-" else "", @divTrunc(q, 10), @mod(q, 10) });
    }
    fn warehouse(self: *Inventory, code: []const u8) Error!*Warehouse {
        return self.warehouses.get(code) orelse return self.fail("unknown warehouse {s}", .{code});
    }
    fn item(self: *Inventory, code: []const u8) Error!*Item {
        return self.items.get(code) orelse return self.fail("unknown item {s}", .{code});
    }
    fn order(self: *Inventory, token: []const u8) Error!*Order {
        const n = integer(token);
        if (n < 1 or n > @as(i64, @intCast(self.orders.items.len))) return self.fail("unknown order {s}", .{token});
        return self.orders.items[@intCast(n - 1)];
    }
    fn lot(self: *Inventory, token: []const u8) Error!*Lot {
        const n = integer(token);
        if (n < 1 or n > @as(i64, @intCast(self.lots.items.len))) return self.fail("unknown lot {s}", .{token});
        return self.lots.items[@intCast(n - 1)];
    }
    fn warehouseList(self: *Inventory) Error![]*Warehouse {
        const result = try self.gpa.dupe(*Warehouse, self.warehouses.values());
        std.mem.sort(*Warehouse, result, {}, struct {
            fn less(_: void, left: *Warehouse, right: *Warehouse) bool {
                return std.mem.order(u8, left.code, right.code) == .lt;
            }
        }.less);
        return result;
    }
    fn itemList(self: *Inventory) Error![]*Item {
        const result = try self.gpa.dupe(*Item, self.items.values());
        std.mem.sort(*Item, result, {}, struct {
            fn less(_: void, left: *Item, right: *Item) bool {
                return std.mem.order(u8, left.code, right.code) == .lt;
            }
        }.less);
        return result;
    }
    fn backorder(self: *Inventory, item_ptr: *Item, w: ?*Warehouse) i64 {
        var result: i64 = 0;
        for (self.orders.items) |o| {
            if (o.item == item_ptr and (w == null or o.warehouse == w.?)) result += o.backorder;
        }
        return result;
    }
    fn tally(self: *Inventory, category: usize, quantity: i64, value: i64) void {
        self.quantities[category] += quantity;
        self.values[category] += value;
    }
    fn card(self: *Inventory, item_ptr: *Item, kind: []const u8, w: *Warehouse, quantity: i64, value: i64) Error!void {
        try item_ptr.card.append(self.gpa, .{ .day = self.day, .kind = kind, .warehouse = w, .quantity = quantity, .value = value });
    }
    fn create(self: *Inventory, item_ptr: *Item, w: *Warehouse, q: i64, cost: i64, day: i64, kind: []const u8) Error!*Lot {
        const l = try self.gpa.create(Lot);
        l.* = .{ .number = self.lots.items.len + 1, .item = item_ptr, .day = day, .initial_quantity = q, .initial_cost = cost, .warehouse = w, .kind = kind, .cost = cost };
        l.held[w.index] = q;
        try self.lots.append(self.gpa, l);
        try item_ptr.lots.append(self.gpa, l);
        std.mem.sort(*Lot, item_ptr.lots.items, {}, struct {
            fn less(_: void, left: *Lot, right: *Lot) bool {
                return if (left.day != right.day) left.day < right.day else left.number < right.number;
            }
        }.less);
        return l;
    }
    fn issue(self: *Inventory, item_ptr: *Item, w: *Warehouse, quantity: i64, removed: bool) Error!Issue {
        var remaining = quantity;
        var cost: i64 = 0;
        var parts: std.ArrayList(Part) = .empty;
        for (item_ptr.lots.items) |l| {
            const take = @min(remaining, l.held[w.index]);
            if (take == 0) continue;
            try parts.append(self.gpa, .{ .lot = l, .quantity = take, .cost = l.cost });
            l.held[w.index] -= take;
            remaining -= take;
            cost += take * l.cost;
            if (removed) l.removed += take;
            if (remaining == 0) break;
        }
        return .{ .parts = parts.items, .cost = cost };
    }
    fn ship(self: *Inventory, o: *Order, quantity: i64, issued: Issue) Error!void {
        o.shipped += quantity;
        o.backorder -= quantity;
        o.revenue += quantity * o.price;
        o.cogs += issued.cost;
        try o.issues.appendSlice(self.gpa, issued.parts);
        o.item.sold += quantity;
        o.item.revenue += quantity * o.price;
        o.item.cogs += issued.cost;
        if (quantity > 0) self.tally(4, quantity, issued.cost);
    }
    fn allocate(self: *Inventory, w: *Warehouse, item_ptr: *Item) Error!void {
        for (self.orders.items) |o| {
            if (o.warehouse != w or o.item != item_ptr or o.backorder == 0) continue;
            const q = @min(o.backorder, stock(item_ptr, w).quantity);
            if (q == 0) break;
            const issued = try self.issue(item_ptr, w, q, false);
            try self.ship(o, q, issued);
            try self.card(item_ptr, "fill", w, -q, -issued.cost);
            try self.out.print("  FILL order {d} qty {d} revenue {s} cogs {s} profit {s} backorder {d}\n", .{ o.number, q, try self.money(q * o.price), try self.money(issued.cost), try self.money(q * o.price - issued.cost), o.backorder });
        }
    }
    fn requireQuantity(self: *Inventory, q: i64) Error!void {
        if (q == 0) return self.fail("invalid quantity", .{});
    }
    fn requireStock(self: *Inventory, item_ptr: *Item, w: *Warehouse, q: i64) Error!void {
        const h = stock(item_ptr, w).quantity;
        if (h < q) return self.fail("insufficient stock {s} {s} {d}", .{ w.code, item_ptr.code, h });
    }
    fn execute(self: *Inventory, a: []const []const u8) Error!void {
        const op = a[0];
        const id: []const u8 = if (a.len > 1) a[1] else "";
        if (std.mem.eql(u8, op, "DAY")) {
            const d = integer(id);
            if (d <= self.day) return self.fail("invalid day {s}", .{id});
            self.day = d;
            try self.out.print("DAY {d}\n", .{d});
        } else if (std.mem.eql(u8, op, "WAREHOUSE")) {
            if (self.warehouses.contains(id)) return self.fail("duplicate warehouse {s}", .{id});
            const w = try self.gpa.create(Warehouse);
            w.* = .{ .code = id, .index = self.warehouses.count() };
            try self.warehouses.put(self.gpa, id, w);
            try self.out.print("WAREHOUSE {s}\n", .{id});
        } else if (std.mem.eql(u8, op, "ITEM")) {
            const old = self.items.get(id);
            const s = old orelse try self.gpa.create(Item);
            if (old == null) {
                s.* = .{ .code = id, .name = a[3], .level = integer(a[2]) };
                try self.items.put(self.gpa, id, s);
            } else {
                s.name = a[3];
                s.level = integer(a[2]);
            }
            try self.out.print("ITEM {s} {s} {s} level {d}\n", .{ id, if (old == null) "added" else "updated", s.name, s.level });
        } else if (std.mem.eql(u8, op, "RECEIVE") or std.mem.eql(u8, op, "SHIP") or std.mem.eql(u8, op, "ADJUST") or std.mem.eql(u8, op, "COUNT")) {
            const w = try self.warehouse(id);
            const s = try self.item(a[2]);
            if (std.mem.eql(u8, op, "RECEIVE")) {
                const q = integer(a[3]);
                const c = amount(a[4]);
                const d = integer(a[5]);
                try self.requireQuantity(q);
                if (d > self.day) return self.fail("future day {s}", .{a[5]});
                const l = try self.create(s, w, q, c, d, "receive");
                s.last_cost = c;
                self.tally(0, q, q * c);
                try self.card(s, "receive", w, q, q * c);
                try self.out.print("RECEIVE {s} {s} lot {d} qty {d} cost {s} day {d} value {s}\n", .{ id, s.code, l.number, q, try self.money(c), d, try self.money(q * c) });
                try self.allocate(w, s);
            } else if (std.mem.eql(u8, op, "SHIP")) {
                const q = integer(a[3]);
                const price = amount(a[4]);
                try self.requireQuantity(q);
                const o = try self.gpa.create(Order);
                o.* = .{ .number = self.orders.items.len + 1, .warehouse = w, .item = s, .day = self.day, .price = price, .ordered = q, .backorder = q };
                try self.orders.append(self.gpa, o);
                s.order_count += 1;
                const f = @min(q, stock(s, w).quantity);
                const issued = try self.issue(s, w, f, false);
                try self.ship(o, f, issued);
                if (f > 0) try self.card(s, "ship", w, -f, -issued.cost);
                try self.out.print("SHIP order {d} {s} {s} shipped {d} revenue {s} cogs {s} profit {s} backorder {d}\n", .{ o.number, id, s.code, f, try self.money(o.revenue), try self.money(o.cogs), try self.money(o.revenue - o.cogs), o.backorder });
            } else if (std.mem.eql(u8, op, "ADJUST")) {
                const positive = a[3][0] == '+';
                const q = integer(a[3][1..]);
                try self.requireQuantity(q);
                if (positive) {
                    const c = amount(a[4]);
                    const l = try self.create(s, w, q, c, self.day, "adjust");
                    self.tally(2, q, q * c);
                    try self.card(s, "adjust", w, q, q * c);
                    try self.out.print("ADJUST {s} {s} +{d} lot {d} value {s}\n", .{ id, s.code, q, l.number, try self.money(q * c) });
                    try self.allocate(w, s);
                } else {
                    try self.requireStock(s, w, q);
                    const issued = try self.issue(s, w, q, true);
                    self.tally(3, q, issued.cost);
                    try self.card(s, "adjust", w, -q, -issued.cost);
                    try self.out.print("ADJUST {s} {s} -{d} value {s}\n", .{ id, s.code, q, try self.money(issued.cost) });
                }
            } else {
                const actual = integer(a[3]);
                const h = stock(s, w).quantity;
                if (actual == h) {
                    try self.out.print("COUNT {s} {s} qty {d} ok\n", .{ id, s.code, actual });
                } else if (actual < h) {
                    const q = h - actual;
                    const issued = try self.issue(s, w, q, true);
                    self.tally(3, q, issued.cost);
                    try self.card(s, "count", w, -q, -issued.cost);
                    try self.out.print("COUNT {s} {s} qty {d} -> {d} shortage {d} value {s}\n", .{ id, s.code, h, actual, q, try self.money(issued.cost) });
                } else {
                    const q = actual - h;
                    const c = s.last_cost orelse 0;
                    const l = try self.create(s, w, q, c, self.day, "count");
                    self.tally(2, q, q * c);
                    try self.card(s, "count", w, q, q * c);
                    try self.out.print("COUNT {s} {s} qty {d} -> {d} surplus {d} lot {d} value {s}\n", .{ id, s.code, h, actual, q, l.number, try self.money(q * c) });
                    try self.allocate(w, s);
                }
            }
        } else if (std.mem.eql(u8, op, "CANCEL")) {
            const o = try self.order(id);
            if (o.backorder == 0) return self.fail("no backorder {s}", .{id});
            const q = o.backorder;
            o.cancelled += q;
            o.backorder = 0;
            try self.out.print("CANCEL order {d} qty {d}\n", .{ o.number, q });
        } else if (std.mem.eql(u8, op, "TRANSFER")) {
            const from = try self.warehouse(id);
            const to = try self.warehouse(a[2]);
            if (from == to) return self.fail("same warehouse {s}", .{id});
            const s = try self.item(a[3]);
            const q = integer(a[4]);
            try self.requireQuantity(q);
            try self.requireStock(s, from, q);
            const issued = try self.issue(s, from, q, false);
            for (issued.parts) |p| p.lot.held[to.index] += p.quantity;
            try self.card(s, "transfer-out", from, -q, -issued.cost);
            try self.card(s, "transfer-in", to, q, issued.cost);
            try self.out.print("TRANSFER {s} -> {s} {s} qty {d} value {s} lots {d}\n", .{ id, to.code, s.code, q, try self.money(issued.cost), issued.parts.len });
            try self.allocate(to, s);
        } else if (std.mem.eql(u8, op, "RETURN")) {
            const o = try self.order(id);
            const q = integer(a[2]);
            try self.requireQuantity(q);
            if (q > o.shipped - o.returned) return self.fail("return exceeds shipped {s} {d}", .{ id, o.shipped - o.returned });
            const c = amount(a[3]);
            const l = try self.create(o.item, o.warehouse, q, c, self.day, "return");
            o.returned += q;
            o.revenue -= q * o.price;
            o.cogs -= q * c;
            o.item.sold -= q;
            o.item.revenue -= q * o.price;
            o.item.cogs -= q * c;
            self.tally(1, q, q * c);
            try self.card(o.item, "return", o.warehouse, q, q * c);
            try self.out.print("RETURN order {d} {s} {s} qty {d} lot {d} refund {s} value {s}\n", .{ o.number, o.warehouse.code, o.item.code, q, l.number, try self.money(q * o.price), try self.money(q * c) });
            try self.allocate(o.warehouse, o.item);
        } else if (std.mem.eql(u8, op, "MARKET")) {
            const s = try self.item(id);
            const price = amount(a[2]);
            var changed: usize = 0;
            var q: i64 = 0;
            var loss: i64 = 0;
            for (try self.warehouseList()) |w| {
                var warehouse_loss: i64 = 0;
                for (s.lots.items) |l| {
                    if (l.cost > price and l.held[w.index] > 0) {
                        const h = l.held[w.index];
                        const value = h * (l.cost - price);
                        changed += 1;
                        q += h;
                        loss += value;
                        warehouse_loss += value;
                    }
                }
                if (warehouse_loss > 0) try self.card(s, "writedown", w, 0, -warehouse_loss);
            }
            for (s.lots.items) |l| {
                if (l.cost > price and held(l, null) > 0) l.cost = price;
            }
            self.tally(5, q, loss);
            try self.out.print("MARKET {s} price {s} lots {d} qty {d} loss {s}\n", .{ id, try self.money(price), changed, q, try self.money(loss) });
        } else if (std.mem.eql(u8, op, "RECALL")) {
            const l = try self.lot(id);
            const q = held(l, null);
            if (q == 0) return self.fail("nothing to recall {s}", .{id});
            try self.out.print("RECALL lot {d} {s} qty {d} value {s}\n", .{ l.number, l.item.code, q, try self.money(q * l.cost) });
            for (try self.warehouseList()) |w| {
                const h = l.held[w.index];
                if (h == 0) continue;
                try self.card(l.item, "recall", w, -h, -h * l.cost);
                try self.out.print("  {s} qty {d} value {s}\n", .{ w.code, h, try self.money(h * l.cost) });
                l.held[w.index] = 0;
            }
            l.removed += q;
            self.tally(7, q, q * l.cost);
        } else if (std.mem.eql(u8, op, "EXPIRE")) {
            const age = integer(id);
            var total_q: i64 = 0;
            var total_v: i64 = 0;
            try self.out.print("EXPIRE {d}\n", .{age});
            const ws = try self.warehouseList();
            for (try self.itemList()) |s| {
                for (ws) |w| {
                    var count: usize = 0;
                    var q: i64 = 0;
                    var value: i64 = 0;
                    for (s.lots.items) |l| {
                        if (l.held[w.index] > 0 and self.day - l.day > age) {
                            const h = l.held[w.index];
                            count += 1;
                            q += h;
                            value += h * l.cost;
                            l.removed += h;
                            l.held[w.index] = 0;
                        }
                    }
                    if (count > 0) {
                        self.tally(6, q, value);
                        try self.card(s, "expire", w, -q, -value);
                        total_q += q;
                        total_v += value;
                        try self.out.print("  {s} {s} lots {d} qty {d} value {s}\n", .{ s.code, w.code, count, q, try self.money(value) });
                    }
                }
            }
            try self.out.print("  total qty {d} value {s}\n", .{ total_q, try self.money(total_v) });
        } else if (std.mem.eql(u8, op, "VALUE") or std.mem.eql(u8, op, "AGING")) {
            const w: ?*Warehouse = if (a.len > 1) try self.warehouse(id) else null;
            const ws = try self.warehouseList();
            if (std.mem.eql(u8, op, "VALUE")) {
                try self.out.print("VALUE{s}\n", .{if (w) |wh| try std.fmt.allocPrint(self.gpa, " {s}", .{wh.code}) else ""});
                var total_q: i64 = 0;
                var total_v: i64 = 0;
                for (try self.itemList()) |s| {
                    const h = stock(s, w);
                    if (h.quantity == 0) continue;
                    total_q += h.quantity;
                    total_v += h.value;
                    try self.out.print("  {s} qty {d} value {s} avg {s}\n", .{ s.code, h.quantity, try self.money(h.value), try self.money(@divTrunc(h.value, h.quantity)) });
                    if (w == null) {
                        for (ws) |wh| {
                            const whs = stock(s, wh);
                            if (whs.quantity > 0) try self.out.print("    {s} qty {d} value {s}\n", .{ wh.code, whs.quantity, try self.money(whs.value) });
                        }
                    }
                }
                try self.out.print("  total qty {d} value {s}\n", .{ total_q, try self.money(total_v) });
            } else {
                try self.out.print("AGING{s} day {d}\n", .{ if (w) |wh| try std.fmt.allocPrint(self.gpa, " {s}", .{wh.code}) else "", self.day });
                const labels = [_][]const u8{ "0-30", "31-60", "61-90", "91+" };
                var total_q: [4]i64 = @splat(0);
                var total_v: [4]i64 = @splat(0);
                for (try self.itemList()) |s| {
                    var qs: [4]i64 = @splat(0);
                    var quantity: i64 = 0;
                    for (s.lots.items) |l| {
                        const h = held(l, w);
                        const age = self.day - l.day;
                        const bucket: usize = if (age <= 30) 0 else if (age <= 60) 1 else if (age <= 90) 2 else 3;
                        qs[bucket] += h;
                        total_q[bucket] += h;
                        total_v[bucket] += h * l.cost;
                        quantity += h;
                    }
                    if (quantity > 0) {
                        try self.out.print("  {s}", .{s.code});
                        for (0..4) |k| try self.out.print(" {s} {d}", .{ labels[k], qs[k] });
                        try self.out.writeByte('\n');
                    }
                }
                try self.out.writeAll("  total");
                for (0..4) |k| try self.out.print(" {s} {d}", .{ labels[k], total_q[k] });
                try self.out.writeAll("\n  value");
                for (0..4) |k| try self.out.print(" {s} {s}", .{ labels[k], try self.money(total_v[k]) });
                try self.out.writeByte('\n');
            }
        } else if (std.mem.eql(u8, op, "LOTS")) {
            const w = try self.warehouse(id);
            const s = try self.item(a[2]);
            var count: usize = 0;
            try self.out.print("LOTS {s} {s}\n", .{ id, s.code });
            for (s.lots.items) |l| {
                const q = l.held[w.index];
                if (q > 0) {
                    count += 1;
                    try self.out.print("  lot {d} day {d} qty {d} cost {s} value {s} age {d}\n", .{ l.number, l.day, q, try self.money(l.cost), try self.money(q * l.cost), self.day - l.day });
                }
            }
            for (self.orders.items) |o| {
                if (o.warehouse == w and o.item == s and o.backorder > 0) {
                    count += 1;
                    try self.out.print("  backorder order {d} qty {d}\n", .{ o.number, o.backorder });
                }
            }
            if (count == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "REORDER") or std.mem.eql(u8, op, "ITEMS")) {
            try self.out.print("{s}\n", .{op});
            var count: usize = 0;
            for (try self.itemList()) |s| {
                const h = stock(s, null).quantity;
                const b = self.backorder(s, null);
                if (std.mem.eql(u8, op, "REORDER")) {
                    if (h - b > s.level) continue;
                    try self.out.print("  {s} {s} onhand {d} backorder {d} level {d}\n", .{ s.code, s.name, h, b, s.level });
                } else try self.out.print("  {s} {s} level {d} onhand {d} backorder {d} cost {s}\n", .{ s.code, s.name, s.level, h, b, if (s.last_cost) |c| try self.money(c) else "none" });
                count += 1;
            }
            if (count == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "MARGIN") or std.mem.eql(u8, op, "TOP")) {
            var selected: std.ArrayList(*Item) = .empty;
            for (try self.itemList()) |s| {
                if (s.order_count > 0) try selected.append(self.gpa, s);
            }
            if (std.mem.eql(u8, op, "MARGIN")) {
                try self.out.writeAll("MARGIN\n");
                var sold: i64 = 0;
                var revenue: i64 = 0;
                var cogs: i64 = 0;
                for (selected.items) |s| {
                    try self.out.print("  {s} sold {d} revenue {s} cogs {s} profit {s} margin {s}\n", .{ s.code, s.sold, try self.money(s.revenue), try self.money(s.cogs), try self.money(s.revenue - s.cogs), try self.margin(s.revenue - s.cogs, s.revenue) });
                    sold += s.sold;
                    revenue += s.revenue;
                    cogs += s.cogs;
                }
                try self.out.print("  total sold {d} revenue {s} cogs {s} profit {s} margin {s}\n", .{ sold, try self.money(revenue), try self.money(cogs), try self.money(revenue - cogs), try self.margin(revenue - cogs, revenue) });
            } else {
                std.mem.sort(*Item, selected.items, {}, struct {
                    fn less(_: void, left: *Item, right: *Item) bool {
                        const ap = left.revenue - left.cogs;
                        const bp = right.revenue - right.cogs;
                        if (ap != bp) return ap > bp;
                        if (left.revenue != right.revenue) return left.revenue > right.revenue;
                        return std.mem.order(u8, left.code, right.code) == .lt;
                    }
                }.less);
                const k: usize = @intCast(integer(id));
                try self.out.print("TOP {d}\n", .{k});
                for (selected.items[0..@min(k, selected.items.len)], 0..) |s, i| try self.out.print("  {d} {s} profit {s} revenue {s} margin {s}\n", .{ i + 1, s.code, try self.money(s.revenue - s.cogs), try self.money(s.revenue), try self.margin(s.revenue - s.cogs, s.revenue) });
                if (selected.items.len == 0) try self.out.writeAll("  (none)\n");
            }
        } else if (std.mem.eql(u8, op, "BACKORDERS")) {
            try self.out.writeAll("BACKORDERS\n");
            var count: usize = 0;
            for (self.orders.items) |o| {
                if (o.backorder > 0) {
                    count += 1;
                    try self.out.print("  order {d} {s} {s} qty {d} day {d} price {s}\n", .{ o.number, o.warehouse.code, o.item.code, o.backorder, o.day, try self.money(o.price) });
                }
            }
            if (count == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "ORDER")) {
            const o = try self.order(id);
            try self.out.print("ORDER {d} {s} {s} day {d} price {s}\n", .{ o.number, o.warehouse.code, o.item.code, o.day, try self.money(o.price) });
            try self.out.print("  ordered {d} shipped {d} backorder {d} cancelled {d} returned {d}\n", .{ o.ordered, o.shipped, o.backorder, o.cancelled, o.returned });
            for (o.issues.items) |p| try self.out.print("  lot {d} qty {d} cost {s}\n", .{ p.lot.number, p.quantity, try self.money(p.cost) });
            try self.out.print("  revenue {s} cogs {s} profit {s}\n", .{ try self.money(o.revenue), try self.money(o.cogs), try self.money(o.revenue - o.cogs) });
        } else if (std.mem.eql(u8, op, "TRACE")) {
            const l = try self.lot(id);
            try self.out.print("TRACE lot {d} {s} {s} {s} day {d} qty {d} cost {s}\n", .{ l.number, l.item.code, l.kind, l.warehouse.code, l.day, l.initial_quantity, try self.money(l.initial_cost) });
            for (try self.warehouseList()) |w| {
                if (l.held[w.index] > 0) try self.out.print("  held {s} qty {d} cost {s}\n", .{ w.code, l.held[w.index], try self.money(l.cost) });
            }
            for (self.orders.items) |o| {
                var q: i64 = 0;
                for (o.issues.items) |p| {
                    if (p.lot == l) q += p.quantity;
                }
                if (q > 0) try self.out.print("  order {d} qty {d}\n", .{ o.number, q });
            }
            if (l.removed > 0) try self.out.print("  removed qty {d}\n", .{l.removed});
        } else if (std.mem.eql(u8, op, "CARD")) {
            const s = try self.item(id);
            try self.out.print("CARD {s} {s}\n", .{ id, s.name });
            var q: i64 = 0;
            var value: i64 = 0;
            for (s.card.items) |e| {
                q += e.quantity;
                value += e.value;
                try self.out.print("  day {d} {s} {s} {s}{d} {s}{s} balance {d} {s}\n", .{ e.day, e.kind, e.warehouse.code, if (e.quantity > 0) "+" else "", e.quantity, if (e.value > 0) "+" else "", try self.money(e.value), q, try self.money(value) });
            }
            if (s.card.items.len == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "STATUS")) {
            try self.out.writeAll("STATUS\n");
            for (try self.warehouseList()) |w| {
                var skus: usize = 0;
                var q: i64 = 0;
                var value: i64 = 0;
                var b: i64 = 0;
                for (self.items.values()) |s| {
                    const h = stock(s, w);
                    if (h.quantity > 0) skus += 1;
                    q += h.quantity;
                    value += h.value;
                }
                for (self.orders.items) |o| {
                    if (o.warehouse == w) b += o.backorder;
                }
                try self.out.print("  {s} skus {d} qty {d} value {s} backorder {d}\n", .{ w.code, skus, q, try self.money(value), b });
            }
            if (self.warehouses.count() == 0) try self.out.writeAll("  (none)\n");
        } else if (std.mem.eql(u8, op, "SUMMARY")) {
            try self.out.writeAll("SUMMARY\n");
            for (0..8) |i| try self.out.print("  {s} qty {d} value {s}\n", .{ categories[i], self.quantities[i], try self.money(self.values[i]) });
            var q: i64 = 0;
            var value: i64 = 0;
            var open: usize = 0;
            var b: i64 = 0;
            for (self.items.values()) |s| {
                const h = stock(s, null);
                q += h.quantity;
                value += h.value;
            }
            for (self.orders.items) |o| {
                if (o.backorder > 0) open += 1;
                b += o.backorder;
            }
            try self.out.print("  on-hand qty {d} value {s}\n  orders {d} open {d} backorder {d}\n", .{ q, try self.money(value), self.orders.items.len, open, b });
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
    var inventory = Inventory{ .gpa = gpa, .out = &output.interface };
    const n: usize = @intCast(integer((try input.interface.takeDelimiter('\n')).?));
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var a: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |part| try a.append(gpa, part);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        inventory.out = &draft.writer;
        inventory.execute(a.items) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{inventory.error_message});
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
