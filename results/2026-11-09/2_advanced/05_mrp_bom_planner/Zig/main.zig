const std = @import("std");
const r = @import("report.zig");
const master = @import("items.zig");
const bom = @import("bom.zig");
const lot = @import("lot_sizing.zig");
const capacity = @import("capacity.zig");
const costing = @import("costing.zig");
const Strings = r.Strings;
const fmt = r.fmt;
const add = r.append;
const money = r.money;
const Weeks = [27]i64;
const DemandKind = enum { MPS, ORDER, DEPENDENT, SAFETY };
const SupplyKind = enum { STOCK, RECEIPT, ORDER };
const ScheduleRow = struct { item: usize, week: usize, quantity: i64, line: usize };
const Inquiry = struct { id: []const u8, item: usize, quantity: i64, week: usize, line: usize };
const Demand = struct { item: usize, kind: DemandKind, week: usize, quantity: i64, order_id: []const u8 = "", line: usize = 0, parent: usize = 0, parent_number: usize = 0 };
const PlannedOrder = struct { item: usize, number: usize, receipt: usize, quantity: i64, original: i64, release: usize };
const Allocation = struct { demand: Demand, share: i64 };
const Supply = struct {
    kind: SupplyKind,
    week: usize,
    quantity: i64,
    line: usize = 0,
    order_index: usize = 0,
    remaining: i64,
    allocations: std.ArrayList(Allocation) = .empty,
    roots: std.ArrayList(Demand) = .empty,
};
const ItemPlan = struct {
    receipts: Weeks = @splat(0),
    gross: Weeks = @splat(0),
    on_hand: Weeks = @splat(0),
    net: Weeks = @splat(0),
    planned_receipts: Weeks = @splat(0),
    planned_releases: Weeks = @splat(0),
    past_due: i64 = 0,
    demands: std.ArrayList(Demand) = .empty,
    orders: std.ArrayList(PlannedOrder) = .empty,
    supplies: std.ArrayList(Supply) = .empty,
    order_supplies: []*Supply = &.{},
};
const Plan = struct { owner: *std.heap.ArenaAllocator, items: []ItemPlan, loads: []Weeks, overloads: []Weeks };
const Promise = struct { inquiry: Inquiry, week: usize = 0, material_week: usize = 0, reason: []const u8 = "" };

fn push(comptime T: type, allocator: std.mem.Allocator, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
fn allocAt(comptime T: type, allocator: std.mem.Allocator, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
fn sum(values: []const i64) i64 { var total: i64 = 0; for (values) |value| total += value; return total; }
fn weekValues(horizon: usize) []const i64 { const values = r.alloc(i64, horizon); for (values, 1..) |*value, week| value.* = @intCast(week); return values; }
fn depthLabel(depth: usize) []const u8 { return fmt("{s}{d}", .{ r.repeat('.', depth), depth }); }
fn planningLess(codes: []const i64, a: usize, b: usize) bool { return codes[a] < codes[b] or (codes[a] == codes[b] and a < b); }
fn receiptLess(_: void, a: ScheduleRow, b: ScheduleRow) bool { return a.week < b.week or (a.week == b.week and a.line < b.line); }
fn demandLess(_: void, a: Demand, b: Demand) bool {
    if (a.week != b.week) return a.week < b.week;
    if (a.kind != b.kind) return @intFromEnum(a.kind) < @intFromEnum(b.kind);
    if (a.line != b.line) return a.line < b.line;
    if (a.parent != b.parent) return a.parent < b.parent;
    return a.parent_number < b.parent_number;
}
fn supplyLess(_: void, a: Supply, b: Supply) bool {
    if (a.week != b.week) return a.week < b.week;
    if (a.kind != b.kind) return @intFromEnum(a.kind) < @intFromEnum(b.kind);
    return a.line < b.line;
}
fn rootRank(kind: DemandKind) usize { return switch (kind) { .MPS => 0, .ORDER => 1, .SAFETY => 2, .DEPENDENT => unreachable }; }
fn rootLess(_: void, a: Demand, b: Demand) bool {
    if (a.item != b.item) return a.item < b.item;
    if (a.kind != b.kind) return rootRank(a.kind) < rootRank(b.kind);
    if (a.week != b.week) return a.week < b.week;
    return r.less(a.order_id, b.order_id);
}
fn sameRoot(a: Demand, b: Demand) bool { return a.item == b.item and a.kind == b.kind and a.week == b.week and r.eq(a.order_id, b.order_id); }
fn addRoot(allocator: std.mem.Allocator, roots: *std.ArrayList(Demand), root: Demand) void { for (roots.items) |existing| { if (sameRoot(existing, root)) return; } push(Demand, allocator, roots, root); }
fn parentSupply(plan: *const Plan, demand: Demand) *Supply { return plan.items[demand.parent].order_supplies[demand.parent_number - 1]; }

const Data = struct {
    horizon: usize,
    peg: []const usize,
    tree_quantity: i64,
    items: []const master.Item,
    graph: bom.Graph,
    centers: []const capacity.Center,
    routings: []std.ArrayList(capacity.Operation),
    mps: []const Demand,
    receipts: []std.ArrayList(ScheduleRow),
    scheduled: []Weeks,
    inquiries: []const Inquiry,
    codes: []const i64,
    cumulative: []const i64,
    order: []const usize,
    errors: Strings,
    fn scheduleRows(name: []const u8, text: []const u8, items: []const master.Item, horizon: usize, unique: bool, errors: *std.ArrayList([]const u8)) []const ScheduleRow {
        var result: std.ArrayList(ScheduleRow) = .empty;
        for (r.rows(text)) |row| {
            const f = row.fields;
            const item = master.find(items, f[0]) orelse { r.problem(errors, name, row.number, fmt("unknown item {s}", .{f[0]})); continue; };
            const week = r.integer(f[1]);
            if (week < 1 or week > @as(i64, @intCast(horizon))) { r.problem(errors, name, row.number, fmt("week {d} outside horizon", .{week})); continue; }
            const quantity = r.integer(f[2]);
            if (quantity < 1) { r.problem(errors, name, row.number, fmt("bad quantity {d}", .{quantity})); continue; }
            var duplicate = false;
            if (unique) { for (result.items) |existing| { if (existing.item == item and existing.week == @as(usize, @intCast(week))) duplicate = true; } }
            if (duplicate) { r.problem(errors, name, row.number, fmt("duplicate {s} week {d}", .{ f[0], week })); continue; }
            add(ScheduleRow, &result, .{ .item = item, .week = @intCast(week), .quantity = quantity, .line = row.number });
        }
        return result.items;
    }
    fn load(inputs: [8][]const u8) Data {
        const params = r.lines(inputs[7]);
        const horizon: usize = @intCast(r.integer(r.split(params[0], ' ')[1]));
        const peg_names = r.split(params[1], ' ')[1..];
        const tree_quantity = r.integer(r.split(params[2], ' ')[1]);
        var errors: std.ArrayList([]const u8) = .empty;
        const items = master.load(inputs[0], &errors);
        const graph = bom.load(inputs[1], items, &errors);
        const centers = capacity.loadCenters(inputs[2], &errors);
        const routings = capacity.loadRoutings(inputs[3], items, centers, graph, &errors);
        const mps_rows = scheduleRows("mps.csv", inputs[4], items, horizon, true, &errors);
        const receipt_rows = scheduleRows("receipts.csv", inputs[5], items, horizon, false, &errors);
        var inquiries: std.ArrayList(Inquiry) = .empty;
        for (r.rows(inputs[6])) |row| {
            const f = row.fields;
            var duplicate = false;
            for (inquiries.items) |inquiry| { if (r.eq(inquiry.id, f[0])) duplicate = true; }
            if (duplicate) { r.problem(&errors, "orders.csv", row.number, fmt("duplicate order {s}", .{f[0]})); continue; }
            const item = master.find(items, f[1]) orelse { r.problem(&errors, "orders.csv", row.number, fmt("unknown item {s}", .{f[1]})); continue; };
            const week = r.integer(f[3]);
            if (week < 1 or week > @as(i64, @intCast(horizon))) { r.problem(&errors, "orders.csv", row.number, fmt("week {d} outside horizon", .{week})); continue; }
            const quantity = r.integer(f[2]);
            if (quantity < 1) { r.problem(&errors, "orders.csv", row.number, fmt("bad quantity {d}", .{quantity})); continue; }
            add(Inquiry, &inquiries, .{ .id = f[0], .item = item, .quantity = quantity, .week = @intCast(week), .line = row.number });
        }
        const receipts = r.alloc(std.ArrayList(ScheduleRow), items.len);
        const scheduled = r.alloc(Weeks, items.len);
        @memset(receipts, .empty);
        @memset(scheduled, @splat(0));
        for (receipt_rows) |row| { add(ScheduleRow, &receipts[row.item], row); scheduled[row.item][row.week] += row.quantity; }
        for (receipts) |entries| std.mem.sort(ScheduleRow, entries.items, {}, receiptLess);
        var mps: std.ArrayList(Demand) = .empty;
        for (mps_rows) |row| add(Demand, &mps, .{ .item = row.item, .kind = .MPS, .week = row.week, .quantity = row.quantity });
        const codes = graph.codes();
        const cumulative = graph.cumulative(items);
        const order = r.alloc(usize, items.len);
        for (order, 0..) |*item, index| item.* = index;
        std.mem.sort(usize, order, codes, planningLess);
        const peg = r.alloc(usize, peg_names.len);
        for (peg_names, peg) |id, *index| index.* = master.find(items, id).?;
        return .{ .horizon = horizon, .peg = peg, .tree_quantity = tree_quantity, .items = items, .graph = graph, .centers = centers, .routings = routings, .mps = mps.items, .receipts = receipts, .scheduled = scheduled, .inquiries = inquiries.items, .codes = codes, .cumulative = cumulative, .order = order, .errors = errors.items };
    }
};

fn runMrp(data: *const Data, inquiries: []const Demand) *Plan {
    const owner = r.allocator.create(std.heap.ArenaAllocator) catch @panic("allocation failed");
    owner.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = owner.allocator();
    const result = allocator.create(Plan) catch @panic("allocation failed");
    const plans = allocAt(ItemPlan, allocator, data.items.len);
    const loads = allocAt(Weeks, allocator, data.centers.len);
    const overloads = allocAt(Weeks, allocator, data.centers.len);
    @memset(plans, .{});
    @memset(loads, @splat(0));
    @memset(overloads, @splat(0));
    result.* = .{ .owner = owner, .items = plans, .loads = loads, .overloads = overloads };
    for (data.scheduled, plans) |scheduled, *plan| plan.receipts = scheduled;
    for (data.mps) |demand| push(Demand, allocator, &plans[demand.item].demands, demand);
    for (inquiries) |demand| push(Demand, allocator, &plans[demand.item].demands, demand);
    for (data.order) |id| {
        const plan = &plans[id];
        const item = data.items[id];
        for (plan.demands.items) |demand| plan.gross[demand.week] += demand.quantity;
        plan.on_hand[0] = item.on_hand;
        for (1..data.horizon + 1) |week| {
            const available = plan.on_hand[week - 1] + plan.receipts[week] - plan.gross[week];
            var projected = available;
            if (available < item.safety) {
                const quantity = lot.quantity(item, week, available, &plan.receipts, &plan.gross, data.horizon);
                const original = @as(i64, @intCast(week)) - item.lead;
                const release: usize = @intCast(@max(1, original));
                const order: PlannedOrder = .{ .item = id, .number = plan.orders.items.len + 1, .receipt = week, .quantity = quantity, .original = original, .release = release };
                push(PlannedOrder, allocator, &plan.orders, order);
                plan.net[week] = item.safety - available;
                plan.planned_receipts[week] = quantity;
                plan.planned_releases[release] += quantity;
                if (original < 1) plan.past_due += quantity;
                projected += quantity;
            }
            plan.on_hand[week] = projected;
        }
        for (plan.orders.items) |order| { for (data.graph.children[id].items) |edge| push(Demand, allocator, &plans[edge.child].demands, .{ .item = edge.child, .kind = .DEPENDENT, .week = order.release, .quantity = bom.need(edge, order.quantity), .parent = id, .parent_number = order.number }); }
    }
    for (data.routings, 0..) |operations, id| {
        for (plans[id].orders.items) |order| { for (operations.items, 0..) |operation, index| {
            const week = capacity.operationWeek(order.receipt, data.items[id].lead, index, operations.items.len);
            loads[operation.center][week] += operation.minutes(order.quantity);
        } }
    }
    for (data.centers, 0..) |center, id| { for (1..data.horizon + 1) |week| overloads[id][week] = @max(0, loads[id][week] - center.available); }
    return result;
}
fn materialReason(data: *const Data, current: *const Plan, trial: *const Plan) ?[]const u8 { for (data.order) |id| { if (trial.items[id].past_due > current.items[id].past_due) return data.items[id].id; } return null; }
fn capacityReason(data: *const Data, current: *const Plan, trial: *const Plan) ?[]const u8 { for (data.centers, 0..) |center, id| { for (1..data.horizon + 1) |week| { if (trial.overloads[id][week] > current.overloads[id][week]) return fmt("{s} week {d}", .{ center.id, week }); } } return null; }
fn promiseInquiries(data: *const Data, base: *Plan) struct { promises: []const Promise, final: *Plan } {
    var current = base;
    var promised: std.ArrayList(Demand) = .empty;
    var promises: std.ArrayList(Promise) = .empty;
    for (data.inquiries) |inquiry| {
        var promise: Promise = .{ .inquiry = inquiry };
        for (inquiry.week..data.horizon + 1) |week| {
            const demand: Demand = .{ .item = inquiry.item, .kind = .ORDER, .week = week, .quantity = inquiry.quantity, .order_id = inquiry.id, .line = inquiry.line };
            var trial_demands: [51]Demand = undefined;
            @memcpy(trial_demands[0..promised.items.len], promised.items);
            trial_demands[promised.items.len] = demand;
            const trial = runMrp(data, trial_demands[0..promised.items.len + 1]);
            var reason = materialReason(data, current, trial);
            if (reason == null) { if (promise.material_week == 0) promise.material_week = week; reason = capacityReason(data, current, trial); }
            if (reason == null) {
                promise.week = week;
                add(Demand, &promised, demand);
                if (current != base) current.owner.deinit();
                current = trial;
                break;
            }
            if (week == inquiry.week) promise.reason = reason.?;
            trial.owner.deinit();
        }
        add(Promise, &promises, promise);
    }
    return .{ .promises = promises.items, .final = current };
}

fn pegPlan(data: *const Data, plan: *Plan) void {
    const allocator = plan.owner.allocator();
    for (data.order) |id| {
        const item = data.items[id];
        const item_plan = &plan.items[id];
        var demands: std.ArrayList(Demand) = .empty;
        for (item_plan.demands.items) |demand| push(Demand, allocator, &demands, demand);
        std.mem.sort(Demand, demands.items, {}, demandLess);
        var all_demands: std.ArrayList(Demand) = .empty;
        if (item.safety > 0) push(Demand, allocator, &all_demands, .{ .item = id, .kind = .SAFETY, .week = 0, .quantity = item.safety });
        for (demands.items) |demand| push(Demand, allocator, &all_demands, demand);
        if (item.on_hand > 0) push(Supply, allocator, &item_plan.supplies, .{ .kind = .STOCK, .week = 0, .quantity = item.on_hand, .remaining = item.on_hand });
        for (data.receipts[id].items) |receipt| push(Supply, allocator, &item_plan.supplies, .{ .kind = .RECEIPT, .week = receipt.week, .quantity = receipt.quantity, .remaining = receipt.quantity, .line = receipt.line });
        for (item_plan.orders.items, 0..) |order, index| push(Supply, allocator, &item_plan.supplies, .{ .kind = .ORDER, .week = order.receipt, .quantity = order.quantity, .remaining = order.quantity, .order_index = index });
        std.mem.sort(Supply, item_plan.supplies.items, {}, supplyLess);
        var index: usize = 0;
        for (all_demands.items) |demand| {
            var remaining = demand.quantity;
            while (remaining > 0) {
                while (item_plan.supplies.items[index].remaining == 0) : (index += 1) {}
                const supply = &item_plan.supplies.items[index];
                const share = @min(remaining, supply.remaining);
                push(Allocation, allocator, &supply.allocations, .{ .demand = demand, .share = share });
                remaining -= share;
                supply.remaining -= share;
            }
        }
        item_plan.order_supplies = allocAt(*Supply, allocator, item_plan.orders.items.len);
        for (item_plan.supplies.items) |*supply| { if (supply.kind == .ORDER) item_plan.order_supplies[supply.order_index] = supply; }
        for (item_plan.order_supplies) |supply| {
            for (supply.allocations.items) |allocation| {
                const demand = allocation.demand;
                if (demand.kind == .DEPENDENT) { for (parentSupply(plan, demand).roots.items) |root| addRoot(allocator, &supply.roots, root); } else addRoot(allocator, &supply.roots, demand);
            }
            std.mem.sort(Demand, supply.roots.items, {}, rootLess);
        }
    }
}

fn demandText(data: *const Data, demand: Demand) []const u8 {
    const id = data.items[demand.item].id;
    return switch (demand.kind) { .SAFETY => fmt("SAFETY {s}", .{id}), .MPS => fmt("MPS {s} week {d}", .{ id, demand.week }), .ORDER => fmt("ORDER {s} {s} week {d}", .{ demand.order_id, id, demand.week }), .DEPENDENT => fmt("{s} order {d} week {d}", .{ data.items[demand.parent].id, demand.parent_number, demand.week }) };
}
fn gridLines(data: *const Data, plan: *const Plan) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    const weeks = weekValues(data.horizon);
    for (data.order) |id| {
        const item = data.items[id];
        const item_plan = &plan.items[id];
        add([]const u8, &output, fmt("ITEM {s} LLC {d} LT {d} LOT {s} SS {d} OH {d} {s}", .{ item.id, data.codes[id], item.lead, item.label(), item.safety, item.on_hand, item.description }));
        const labels = [_][]const u8{ "WEEK", "GROSS", "RECEIPTS", "ON_HAND", "NET", "PLAN_RCPT", "PLAN_REL" };
        const values = [_][]const i64{ weeks, item_plan.gross[1..data.horizon + 1], item_plan.receipts[1..data.horizon + 1], item_plan.on_hand[1..data.horizon + 1], item_plan.net[1..data.horizon + 1], item_plan.planned_receipts[1..data.horizon + 1], item_plan.planned_releases[1..data.horizon + 1] };
        for (labels, values) |label, numbers| add([]const u8, &output, r.table(label, numbers, 6));
        add([]const u8, &output, fmt("TOTAL gross {d} receipts {d} planned {d} orders {d} ending {d}", .{ sum(&item_plan.gross), sum(&item_plan.receipts), sum(&item_plan.planned_receipts), item_plan.orders.items.len, item_plan.on_hand[data.horizon] }));
    }
    return output.items;
}
fn whereUsed(output: *std.ArrayList([]const u8), data: *const Data, id: usize, depth: usize, extension: i64) void {
    for (data.graph.parents[id].items) |edge| {
        const ext = extension * edge.quantity;
        add([]const u8, output, fmt("{s} {s} qty {d} ext {d}", .{ depthLabel(depth), data.items[edge.parent].id, edge.quantity, ext }));
        whereUsed(output, data, edge.parent, depth + 1, ext);
    }
}
fn allocationLines(output: *std.ArrayList([]const u8), data: *const Data, plan: *const Plan, supply: *const Supply, depth: usize) void {
    for (supply.allocations.items) |allocation| {
        add([]const u8, output, fmt("{s}ALLOC {d} {s}", .{ r.repeat(' ', depth * 2), allocation.share, demandText(data, allocation.demand) }));
        if (supply.kind == .ORDER and allocation.demand.kind == .DEPENDENT) allocationLines(output, data, plan, parentSupply(plan, allocation.demand), depth + 1);
    }
}
fn peggingLines(data: *const Data, plan: *const Plan) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    for (data.peg) |id| {
        const item_plan = &plan.items[id];
        add([]const u8, &output, fmt("PEG {s} orders {d}", .{ data.items[id].id, item_plan.orders.items.len }));
        whereUsed(&output, data, id, 1, 1);
        for ([_]SupplyKind{ .STOCK, .RECEIPT, .ORDER }) |kind| {
            for (item_plan.supplies.items) |*supply| {
                if (supply.kind != kind) continue;
                switch (kind) {
                    .STOCK => add([]const u8, &output, fmt("STOCK quantity {d}", .{supply.quantity})),
                    .RECEIPT => add([]const u8, &output, fmt("RECEIPT line {d} week {d} quantity {d}", .{ supply.line, supply.week, supply.quantity })),
                    .ORDER => { const order = item_plan.orders.items[supply.order_index]; add([]const u8, &output, fmt("ORDER {d} receipt {d} release {d} quantity {d}", .{ order.number, order.receipt, order.release, order.quantity })); },
                }
                allocationLines(&output, data, plan, supply, 1);
                if (supply.remaining > 0) add([]const u8, &output, fmt("  EXCESS {d}", .{supply.remaining}));
                for (supply.roots.items) |root| add([]const u8, &output, fmt("  ROOT {s}", .{demandText(data, root)}));
            }
        }
    }
    return output.items;
}
fn explosionLines(output: *std.ArrayList([]const u8), totals: []i64, data: *const Data, id: usize, gross: i64, extension: i64, depth: usize) void {
    for (data.graph.children[id].items) |edge| {
        const child = data.items[edge.child];
        const ext = extension * edge.quantity;
        const needed = bom.need(edge, gross);
        totals[edge.child] += needed;
        add([]const u8, output, fmt("{s} {s} qty {d} scrap {d} ext {d} gross {d} lt {d} cum {d} {s}", .{ depthLabel(depth), child.id, edge.quantity, edge.scrap, ext, needed, child.lead, data.cumulative[edge.child], child.description }));
        explosionLines(output, totals, data, edge.child, needed, ext, depth + 1);
    }
}
fn bomLines(data: *const Data) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    for (data.items, 0..) |item, id| {
        if (!data.graph.manufactured(id) or data.graph.parents[id].items.len != 0) continue;
        add([]const u8, &output, fmt("TREE {s} quantity {d}", .{ item.id, data.tree_quantity }));
        add([]const u8, &output, fmt("0 {s} ext 1 gross {d} lt {d} cum {d} {s}", .{ item.id, data.tree_quantity, item.lead, data.cumulative[id], item.description }));
        const totals = r.alloc(i64, data.items.len);
        @memset(totals, 0);
        explosionLines(&output, totals, data, id, data.tree_quantity, 1, 1);
        for (totals, data.items) |total, child| { if (total > 0) add([]const u8, &output, fmt("SUM {s} {d}", .{ child.id, total })); }
        var path: std.ArrayList([]const u8) = .empty;
        var current = id;
        add([]const u8, &path, item.id);
        while (data.graph.manufactured(current)) {
            const children = data.graph.children[current].items;
            var best = children[0].child;
            for (children[1..]) |edge| { if (data.cumulative[edge.child] > data.cumulative[best]) best = edge.child; }
            current = best;
            add([]const u8, &path, data.items[current].id);
        }
        add([]const u8, &output, fmt("CRITICAL {s} cum {d}", .{ r.join(path.items, " -> "), data.cumulative[id] }));
    }
    return output.items;
}
fn costLines(data: *const Data, plan: *const Plan, costs: []const costing.Cost) Strings {
    const usages = r.alloc(i64, data.items.len);
    const values = r.alloc(i64, data.items.len);
    for (plan.items, costs, 0..) |item_plan, cost, id| { usages[id] = sum(&item_plan.gross); values[id] = usages[id] * cost.total; }
    const classes = costing.abc(values);
    var output: std.ArrayList([]const u8) = .empty;
    add([]const u8, &output, "item,material,labor,total,usage,value,class");
    for (data.items, costs, usages, values, classes) |item, cost, usage, value, class| add([]const u8, &output, fmt("{s},{s},{s},{s},{d},{s},{c}", .{ item.id, money(cost.material), money(cost.labor), money(cost.total), usage, money(value), class }));
    return output.items;
}

fn exceptionLines(data: *const Data, plan: *const Plan) Strings {
    const kinds = [_][]const u8{ "BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD" };
    var output: std.ArrayList([]const u8) = .empty;
    for (data.errors) |error_text| add([]const u8, &output, fmt("ERROR {s}", .{error_text}));
    var messages: std.ArrayList([]const u8) = .empty;
    for (data.order) |id| {
        const item = data.items[id];
        const item_plan = &plan.items[id];
        if (item.on_hand < item.safety) add([]const u8, &messages, fmt("BELOW_SAFETY {s} on hand {d} safety {d}", .{ item.id, item.on_hand, item.safety }));
        for (item_plan.orders.items) |order| {
            if (order.original < 1) add([]const u8, &messages, fmt("PAST_DUE {s} order {d} receipt {d} release {d} late {d} quantity {d}", .{ item.id, order.number, order.receipt, order.original, 1 - order.original, order.quantity })) else if (order.original == 1) add([]const u8, &messages, fmt("RELEASE {s} order {d} receipt {d} quantity {d}", .{ item.id, order.number, order.receipt, order.quantity }));
        }
        var balances: Weeks = @splat(0);
        var balance = item.on_hand;
        for (1..data.horizon + 1) |week| { balance -= item_plan.gross[week]; balances[week] = balance; }
        var covered: i64 = 0;
        for (data.receipts[id].items) |receipt| {
            var need_week: usize = 0;
            for (1..data.horizon + 1) |week| { if (balances[week] + covered < item.safety) { need_week = week; break; } }
            const content = fmt("{s} receipt line {d} week {d} quantity {d}", .{ item.id, receipt.line, receipt.week, receipt.quantity });
            if (need_week == 0) add([]const u8, &messages, fmt("CANCEL {s}", .{content})) else if (need_week < receipt.week) add([]const u8, &messages, fmt("EXPEDITE {s} to {d}", .{ content, need_week })) else if (need_week > receipt.week) add([]const u8, &messages, fmt("DEFER {s} to {d}", .{ content, need_week }));
            covered += receipt.quantity;
        }
        if (data.graph.manufactured(id) and data.routings[id].items.len == 0) add([]const u8, &messages, fmt("NO_ROUTING {s}", .{item.id}));
        if (sum(&item_plan.gross) == 0 and item.on_hand > 0) add([]const u8, &messages, fmt("NO_DEMAND {s} on hand {d}", .{ item.id, item.on_hand }));
    }
    for (data.centers, 0..) |center, id| { for (1..data.horizon + 1) |week| { if (plan.overloads[id][week] > 0) add([]const u8, &messages, fmt("OVERLOAD {s} week {d} load {d} available {d}", .{ center.id, week, plan.loads[id][week], center.available })); } }
    for (messages.items) |message| add([]const u8, &output, message);
    var counts: [9]usize = @splat(0);
    for (messages.items) |message| { const space = std.mem.findScalar(u8, message, ' ') orelse message.len; for (kinds, 0..) |kind, i| { if (r.eq(kind, message[0..space])) counts[i] += 1; } }
    add([]const u8, &output, fmt("SUMMARY errors {d} below_safety {d} past_due {d} release {d} expedite {d} defer {d} cancel {d} no_routing {d} no_demand {d} overload {d}", .{ data.errors.len, counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], counts[7], counts[8] }));
    return output.items;
}
const CenterRank = struct { id: usize, total: i64, available: i64 };
fn centerRankLess(_: void, a: CenterRank, b: CenterRank) bool { const left = a.total * b.available; const right = b.total * a.available; return left > right or (left == right and a.id < b.id); }
fn capacityLines(data: *const Data, plan: *const Plan) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    var ranked: std.ArrayList(CenterRank) = .empty;
    for (data.centers, 0..) |center, id| {
        const loads = plan.loads[id][0..data.horizon + 1];
        const overloads = plan.overloads[id][0..data.horizon + 1];
        const leveled = capacity.level(loads, center.available);
        const total = sum(loads);
        const available = center.available * @as(i64, @intCast(data.horizon));
        var peak: usize = 0;
        var overloaded: usize = 0;
        const utilization = r.alloc(i64, data.horizon);
        for (1..data.horizon + 1) |week| {
            if (loads[week] > 0 and (peak == 0 or loads[week] > loads[peak])) peak = week;
            if (overloads[week] > 0) overloaded += 1;
            utilization[week - 1] = r.percent(loads[week], center.available);
        }
        add([]const u8, &output, fmt("CENTER {s} minutes {d} efficiency {d} available {d} {s}", .{ center.id, center.minutes, center.efficiency, center.available, center.description }));
        const labels = [_][]const u8{ "WEEK", "LOAD", "UTIL", "OVER", "LEVELED" };
        const values = [_][]const i64{ weekValues(data.horizon), loads[1..], utilization, overloads[1..], leveled[1..] };
        for (labels, values) |label, numbers| add([]const u8, &output, r.table(label, numbers, 7));
        add([]const u8, &output, fmt("TOTAL load {d} available {d} utilization {d} overloaded {d} peak {d} backlog {d}", .{ total, available, r.percent(total, available), overloaded, peak, @max(0, leveled[1] - center.available) }));
        add(CenterRank, &ranked, .{ .id = id, .total = total, .available = center.available });
    }
    std.mem.sort(CenterRank, ranked.items, {}, centerRankLess);
    for (ranked.items, 1..) |entry, rank| add([]const u8, &output, fmt("RANK {d} {s} load {d} utilization {d}", .{ rank, data.centers[entry.id].id, entry.total, r.percent(entry.total, entry.available * @as(i64, @intCast(data.horizon))) }));
    return output.items;
}
fn promiseLines(data: *const Data, promises: []const Promise, base: *const Plan, final: *const Plan) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    var counts: [3]usize = @splat(0);
    for (promises) |promise| {
        const inquiry = promise.inquiry;
        const head = fmt("ORDER {s} {s} quantity {d} requested {d}", .{ inquiry.id, data.items[inquiry.item].id, inquiry.quantity, inquiry.week });
        const material = if (promise.material_week == 0) "none" else fmt("{d}", .{promise.material_week});
        if (promise.week == 0) {
            counts[2] += 1;
            add([]const u8, &output, fmt("{s} rejected material {s} reason {s}", .{ head, material, promise.reason }));
            continue;
        } else if (promise.week == inquiry.week) {
            counts[0] += 1;
            add([]const u8, &output, fmt("{s} promised {d}", .{ head, promise.week }));
        } else {
            counts[1] += 1;
            add([]const u8, &output, fmt("{s} promised {d} late {d} material {s} reason {s}", .{ head, promise.week, promise.week - inquiry.week, material, promise.reason }));
        }
        for (data.order) |id| {
            for (final.items[id].order_supplies) |supply| {
                var serves = false;
                for (supply.roots.items) |root| { if (root.kind == .ORDER and r.eq(root.order_id, inquiry.id)) serves = true; }
                if (!serves) continue;
                const order = final.items[id].orders.items[supply.order_index];
                add([]const u8, &output, fmt("  SUPPLY {s} order {d} receipt {d} release {d} quantity {d}", .{ data.items[id].id, order.number, order.receipt, order.release, order.quantity }));
            }
        }
    }
    for (data.order) |id| {
        const before = &base.items[id];
        const after = &final.items[id];
        var changed: usize = 0;
        for (1..data.horizon + 1) |week| { if (before.planned_receipts[week] != after.planned_receipts[week]) { changed = week; break; } }
        if (changed > 0) add([]const u8, &output, fmt("CHANGE {s} from {d} planned {d} -> {d} orders {d} -> {d}", .{ data.items[id].id, changed, sum(&before.planned_receipts), sum(&after.planned_receipts), before.orders.items.len, after.orders.items.len }));
    }
    add([]const u8, &output, fmt("SUMMARY orders {d} on_time {d} late {d} rejected {d}", .{ promises.len, counts[0], counts[1], counts[2] }));
    return output.items;
}
fn releaseLess(_: void, a: PlannedOrder, b: PlannedOrder) bool {
    if (a.original != b.original) return a.original < b.original;
    if (a.item != b.item) return a.item < b.item;
    return a.number < b.number;
}
fn releaseLines(data: *const Data, plan: *const Plan) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    var orders: std.ArrayList(PlannedOrder) = .empty;
    for (data.order) |id| { for (plan.items[id].orders.items) |order| { if (order.release == 1) add(PlannedOrder, &orders, order); } }
    std.mem.sort(PlannedOrder, orders.items, {}, releaseLess);
    const available = r.alloc(i64, data.items.len);
    for (data.items, 0..) |item, id| available[id] = item.on_hand + data.scheduled[id][1];
    var made: usize = 0;
    var ready_count: usize = 0;
    var bought: usize = 0;
    var purchase_total: i64 = 0;
    for (orders.items) |order| {
        const item = data.items[order.item];
        const late = if (order.original < 1) fmt(" late {d}", .{1 - order.original}) else "";
        const head = fmt("{s} order {d} receipt {d} quantity {d}{s}", .{ item.id, order.number, order.receipt, order.quantity, late });
        if (!data.graph.manufactured(order.item)) {
            const value = order.quantity * item.material;
            bought += 1;
            purchase_total += value;
            add([]const u8, &output, fmt("BUY {s} value {s}", .{ head, money(value) }));
            continue;
        }
        made += 1;
        const children = data.graph.children[order.item].items;
        var ready = true;
        for (children) |edge| { if (bom.need(edge, order.quantity) > available[edge.child]) ready = false; }
        if (ready) ready_count += 1;
        add([]const u8, &output, fmt("MAKE {s} {s}", .{ head, if (ready) @as([]const u8, "READY") else "SHORT" }));
        for (children) |edge| {
            const need = bom.need(edge, order.quantity);
            add([]const u8, &output, fmt("  PICK {s} need {d} available {d} short {d}", .{ data.items[edge.child].id, need, available[edge.child], @max(0, need - available[edge.child]) }));
        }
        if (ready) { for (children) |edge| available[edge.child] -= bom.need(edge, order.quantity); }
        const operations = data.routings[order.item].items;
        for (operations, 0..) |operation, index| add([]const u8, &output, fmt("  OPERATION {d} {s} week {d} minutes {d}", .{ operation.number, data.centers[operation.center].id, capacity.operationWeek(order.receipt, item.lead, index, operations.len), operation.minutes(order.quantity) }));
    }
    add([]const u8, &output, fmt("SUMMARY make {d} ready {d} short {d} buy {d} value {s}", .{ made, ready_count, made - ready_count, bought, money(purchase_total) }));
    return output.items;
}
fn valueLines(data: *const Data, plan: *const Plan, costs: []const costing.Cost) Strings {
    var output: std.ArrayList([]const u8) = .empty;
    add([]const u8, &output, "week,inventory,purchases,labor");
    for (1..data.horizon + 1) |week| {
        var inventory: i64 = 0;
        var purchases: i64 = 0;
        var labor: i64 = 0;
        for (data.order) |id| {
            const item_plan = &plan.items[id];
            inventory += item_plan.on_hand[week] * costs[id].total;
            if (data.graph.manufactured(id)) labor += item_plan.planned_releases[week] * data.items[id].labor else purchases += item_plan.planned_releases[week] * data.items[id].material;
        }
        add([]const u8, &output, fmt("{d},{s},{s},{s}", .{ week, money(inventory), money(purchases), money(labor) }));
    }
    return output.items;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    r.allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();
    const names = [_][]const u8{ "items.csv", "bom.csv", "workcenters.csv", "routings.csv", "mps.csv", "receipts.csv", "orders.csv", "params.txt" };
    var inputs: [8][]const u8 = undefined;
    for (names, 0..) |name, i| inputs[i] = try cwd.readFileAlloc(init.io, fmt("input/{s}", .{name}), r.allocator, .unlimited);
    const data = Data.load(inputs);
    const base = runMrp(&data, &.{});
    defer base.owner.deinit();
    const promised = promiseInquiries(&data, base);
    const final = promised.final;
    defer if (final != base) final.owner.deinit();
    pegPlan(&data, final);
    const costs = costing.rollup(data.items, data.graph, data.order);
    try r.write(init.io, "mrp_grid.txt", gridLines(&data, final));
    try r.write(init.io, "pegging.txt", peggingLines(&data, final));
    try r.write(init.io, "bom_tree.txt", bomLines(&data));
    try r.write(init.io, "cost_rollup.csv", costLines(&data, final, costs));
    try r.write(init.io, "exceptions.txt", exceptionLines(&data, final));
    try r.write(init.io, "capacity.txt", capacityLines(&data, final));
    try r.write(init.io, "promises.txt", promiseLines(&data, promised.promises, base, final));
    try r.write(init.io, "releases.txt", releaseLines(&data, final));
    try r.write(init.io, "value_plan.csv", valueLines(&data, final, costs));
}
