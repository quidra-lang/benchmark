const std = @import("std");
const h = @import("hashing.zig");
const w = @import("wallets.zig");
const t = @import("transactions.zig");
const b = @import("blocks.zig");
const c = @import("chain.zig");
fn put(map: anytype, key: []const u8, value: anytype) void {
    map.put(key, value) catch @panic("allocation failed");
}
const Params = struct {
    initial_bits: i64,
    retarget: i64,
    target: i64,
    initial_reward: i64,
    halving: i64,
    maturity: i64,
    max_size: i64,
    min_rate: i64,
    pool_limit: usize,
    orphan_limit: usize,
    drift: i64,
    expiry: i64,
    max_reorg: i64,
    ban: i64,
    block_penalty: i64,
    tx_penalty: i64,
    genesis: []const t.Output,
    fn read(io: std.Io, wallets: []const w.Wallet) !Params {
        const lines = try h.readLines(io, "params.txt");
        var fields: [13][]const []const u8 = undefined;
        for (lines, &fields) |line, *field| field.* = h.split(line, ' ')[1..];
        const outputs = h.alloc(t.Output, fields[12].len / 2);
        for (outputs, 0..) |*output, index| output.* = .{ .address = w.named(wallets, fields[12][index * 2]).address,
             .amount = h.number(fields[12][index * 2 + 1]) };
        return .{
            .initial_bits = h.number(fields[0][0]),
            .retarget = h.number(fields[1][0]),
            .target = h.number(fields[1][1]),
            .initial_reward = h.number(fields[2][0]),
            .halving = h.number(fields[2][1]),
            .maturity = h.number(fields[3][0]),
            .max_size = h.number(fields[4][0]),
            .min_rate = h.number(fields[5][0]),
            .pool_limit = h.u(h.number(fields[6][0])),
            .orphan_limit = h.u(h.number(fields[7][0])),
            .drift = h.number(fields[8][0]),
            .expiry = h.number(fields[9][0]),
            .max_reorg = h.number(fields[10][0]),
            .ban = h.number(fields[11][0]),
            .block_penalty = h.number(fields[11][1]),
            .tx_penalty = h.number(fields[11][2]),
            .genesis = outputs,
        };
    }
};
const Entry = struct { tx: *const t.Transaction, fee: i64, arrival: i64 };
const Peer = struct { blocks: i64 = 0, rejected_blocks: i64 = 0, orphans: i64 = 0, txs: i64 = 0, rejected_txs: i64 = 0,
     ignored: i64 = 0, score: i64 = 0 };
const Orphan = struct { block: b.Block, peer: []const u8 };
const Reorganization = struct { time: i64, fork: i64, disconnected: i64, connected: i64, old_hash: []const u8,
     new_hash: []const u8 };
const Acceptance = struct { reason: ?[]const u8 = null, fee: i64 = 0, conflicts: []const []const u8 = &.{} };
fn priority(_: void, a: Entry, z: Entry) bool {
    const left = a.fee * z.tx.size();
    const right = z.fee * a.tx.size();
    return if (left != right) left > right else std.mem.order(u8, a.tx.id, z.tx.id) == .lt;
}
fn coinOrder(_: void, a: t.Coin, z: t.Coin) bool {
    return t.referenceOrder(a.reference, z.reference);
}
fn selectionOrder(_: void, a: t.Coin, z: t.Coin) bool {
    return if (a.amount != z.amount) a.amount > z.amount else t.referenceOrder(a.reference, z.reference);
}
fn recordOrder(_: void, a: *c.Record, z: *c.Record) bool {
    return if (a.block.height != z.block.height) a.block.height < z.block.height else std.mem.order(u8,
         a.block.hash, z.block.hash) == .lt;
}
fn stringOrder(_: void, a: []const u8, z: []const u8) bool {
    return std.mem.order(u8, a, z) == .lt;
}
const Node = struct {
    params: Params,
    wallets: []const w.Wallet,
    records: std.StringHashMap(*c.Record),
    tip: *c.Record,
    main_chain: []*c.Record = &.{},
    confirmed: std.StringHashMap(i64),
    pool: std.ArrayList(Entry) = .empty,
    orphans: std.ArrayList(Orphan) = .empty,
    rejected: std.StringHashMap(void),
    drops: std.StringHashMap([]const u8),
    peers: std.StringHashMap(Peer),
    rejections: std.StringHashMap(i64),
    reorganizations: std.ArrayList(Reorganization) = .empty,
    log_lines: h.Lines = .{},
    now: i64 = 0,
    fn init(params: Params, wallets: []const w.Wallet) Node {
        const cb = t.coinbase(0, params.genesis);
        var block: b.Block = .{ .height = 0, .previous = "00000000000000000000000000000000", .root = cb.id,
             .time = 0, .difficulty = 0, .transactions = h.dupe(*const t.Transaction, &.{cb}) };
        block.hashHeader();
        var utxo: t.Utxo = .{};
        utxo.apply(cb, 0);
        const record = c.Record.create(block, null, utxo, &.{}, "genesis");
        var node: Node = .{
            .params = params,
            .wallets = wallets,
            .tip = record,
            .records = std.StringHashMap(*c.Record).init(h.allocator),
            .confirmed = std.StringHashMap(i64).init(h.allocator),
            .rejected = std.StringHashMap(void).init(h.allocator),
            .drops = std.StringHashMap([]const u8).init(h.allocator),
            .peers = std.StringHashMap(Peer).init(h.allocator),
            .rejections = std.StringHashMap(i64).init(h.allocator),
        };
        put(&node.records, block.hash, record);
        node.refresh();
        return node;
    }
    fn log(self: *Node, comptime pattern: []const u8, args: anytype) void {
        self.log_lines.add("{d} {s}", .{ self.now, h.fmt(pattern, args) });
    }
    fn tally(self: *Node, category: []const u8, reason: []const u8) void {
        const key = h.fmt("{s} {s}", .{ category, reason });
        put(&self.rejections, key, (self.rejections.get(key) orelse 0) + 1);
    }
    fn nextHeight(self: *const Node) i64 {
        return self.tip.block.height + 1;
    }
    fn blockReward(self: *const Node, height: i64) i64 {
        return c.reward(height, self.params.initial_reward, self.params.halving);
    }
    fn nextBits(self: *const Node, parent: *c.Record) i64 {
        return c.requiredDifficulty(parent, self.params.initial_bits, self.params.retarget, self.params.target);
    }
    fn refresh(self: *Node) void {
        self.main_chain = c.chainTo(self.tip);
        self.confirmed.clearRetainingCapacity();
        for (self.main_chain) |record| for (record.block.transactions) |tx| put(&self.confirmed, tx.id, record.block.height);
    }
    fn ordered(self: *const Node) []Entry {
        const result = h.dupe(Entry, self.pool.items);
        std.mem.sort(Entry, result, {}, priority);
        return result;
    }
    fn findEntry(self: *const Node, id: []const u8) ?Entry {
        for (self.pool.items) |entry| if (h.eq(entry.tx.id, id)) return entry;
        return null;
    }
    fn locked(self: *const Node, reference: t.Reference) bool {
        for (self.pool.items) |entry| for (entry.tx.inputs) |other| if (t.same(reference, other)) return true;
        return false;
    }
    fn balance(self: *const Node, address: []const u8) i64 {
        var total: i64 = 0;
        for (self.tip.utxo.coins.items) |coin| if (h.eq(coin.address, address)) {
            total += coin.amount;
        };
        return total;
    }
    fn acceptance(self: *const Node, tx: *const t.Transaction) Acceptance {
        if (tx.coinbase_height != null) return .{ .reason = "coinbase" };
        if (self.confirmed.contains(tx.id) or self.findEntry(tx.id) != null) return .{ .reason = "duplicate" };
        const check = t.check(tx, &self.tip.utxo, &.{}, self.nextHeight(), self.wallets, self.params.maturity);
        if (check.reason) |reason| return .{ .reason = reason };
        if (check.fee * 1000 < self.params.min_rate * tx.size()) return .{ .reason = "low-fee" };
        var conflicts: std.ArrayList([]const u8) = .empty;
        var fees: i64 = 0;
        var higher = true;
        for (self.pool.items) |entry| {
            var conflict = false;
            for (tx.inputs) |reference| for (entry.tx.inputs) |other| if (t.same(reference, other)) {
                conflict = true;
            };
            if (!conflict) continue;
            h.append([]const u8, &conflicts, entry.tx.id);
            fees += entry.fee;
            if (check.fee * entry.tx.size() <= entry.fee * tx.size()) higher = false;
        }
        if (conflicts.items.len > 0 and (check.fee <= fees or !higher)) return .{ .reason = "conflict" };
        return .{ .fee = check.fee, .conflicts = conflicts.items };
    }
    fn drop(self: *Node, id: []const u8, reason: []const u8) void {
        for (self.pool.items, 0..) |entry, index| if (h.eq(entry.tx.id, id)) {
            _ = self.pool.orderedRemove(index);
            break;
        };
        put(&self.drops, id, reason);
        self.log("DROP {s} {s}", .{ h.short(id), reason });
    }
    fn register(self: *Node, tx: *const t.Transaction, result: Acceptance, arrival: i64) void {
        for (result.conflicts) |id| self.drop(id, "replaced");
        h.append(Entry, &self.pool, .{ .tx = tx, .fee = result.fee, .arrival = arrival });
        if (self.pool.items.len > self.params.pool_limit) {
            const order = self.ordered();
            self.drop(order[order.len - 1].tx.id, "mempool-full");
        }
    }
    fn rebuildCandidate(self: *Node, tx: *const t.Transaction, arrival: i64, returning: bool) void {
        if (self.confirmed.contains(tx.id)) return;
        const result = self.acceptance(tx);
        if (result.reason) |reason| {
            self.drop(tx.id, reason);
            return;
        }
        if (returning) self.log("RETURN {s}", .{h.short(tx.id)});
        self.register(tx, result, arrival);
    }
    fn switchTip(self: *Node, target: *c.Record) void {
        const old = self.tip;
        const fork = c.forkPoint(old, target);
        const depth = old.block.height - fork.block.height;
        const connected = target.block.height - fork.block.height;
        if (depth > self.params.max_reorg) {
            self.log("REFUSE {d} {s} work {d} fork {d} depth {d}", .{ target.block.height, h.short(target.block.hash),
                 target.work, fork.block.height, depth });
            return;
        }
        var returned: std.ArrayList(*const t.Transaction) = .empty;
        for (self.main_chain[h.u(fork.block.height + 1)..]) |record| for (record.block.transactions[1..]) |tx| h.append(*const t.Transaction,
             &returned, tx);
        self.tip = target;
        self.refresh();
        if (depth == 0) self.log("TIP {d} {s} work {d}", .{ target.block.height, h.short(target.block.hash), target.work }) else {
            self.log("REORG {d} {s} work {d} fork {d} disconnected {d} connected {d}", .{ target.block.height,
                 h.short(target.block.hash), target.work, fork.block.height, depth, connected });
            h.append(Reorganization, &self.reorganizations, .{ .time = self.now, .fork = fork.block.height,
                 .disconnected = depth, .connected = connected, .old_hash = old.block.hash, .new_hash = target.block.hash });
        }
        const previous = self.pool.items;
        self.pool = .empty;
        for (returned.items) |tx| self.rebuildCandidate(tx, self.now, true);
        for (previous) |entry| self.rebuildCandidate(entry.tx, entry.arrival, false);
    }
    fn penalize(self: *Node, name: []const u8, amount: i64) void {
        const peer = self.peers.getPtr(name).?;
        const before = peer.score;
        peer.score += amount;
        if (before < self.params.ban and peer.score >= self.params.ban) self.log("BAN {s} score {d}", .{ name, peer.score });
    }
    fn rejectBlock(self: *Node, kind: []const u8, block: b.Block, name: []const u8, reason: []const u8) void {
        put(&self.rejected, block.hash, {});
        self.peers.getPtr(name).?.rejected_blocks += 1;
        self.tally("block", h.split(reason, ' ')[0]);
        self.log("{s} {s} {d} {s} rejected {s}", .{ kind, name, block.height, h.short(block.hash), reason });
        if (!h.eq(reason, "time-too-new")) self.penalize(name, self.params.block_penalty);
    }
    fn connect(self: *Node, kind: []const u8, block: b.Block, name: []const u8) void {
        const parent = self.records.get(block.previous).?;
        var reason: ?[]const u8 = null;
        if (block.height != parent.block.height + 1) reason = "bad-height" else if (block.difficulty != self.nextBits(parent)) reason = "bad-difficulty" else if (block.time <= c.medianTime(parent)) reason = "time-too-old" else if (block.time > self.now + self.params.drift) reason = "time-too-new";
        var utxo = parent.utxo.copy();
        var spent: std.ArrayList(t.Reference) = .empty;
        var fees: std.ArrayList(i64) = .empty;
        var total: i64 = 0;
        if (reason == null) for (block.transactions[1..], 2..) |tx, position| {
            const result = t.check(tx, &utxo, spent.items, block.height, self.wallets, self.params.maturity);
            if (result.reason) |error_reason| {
                reason = h.fmt("{s} tx {d}", .{ error_reason, position });
                break;
            }
            for (tx.inputs) |reference| h.append(t.Reference, &spent, reference);
            utxo.apply(tx, block.height);
            h.append(i64, &fees, result.fee);
            total += result.fee;
        };
        const cb = block.transactions[0];
        if (reason == null) for (cb.outputs) |output| if (w.owner(self.wallets, output.address) == null or output.amount == 0) {
            reason = "bad-output tx 1";
            break;
        };
        if (reason == null and cb.total() > self.blockReward(block.height) + total) reason = "bad-coinbase";
        if (reason) |error_reason| {
            self.rejectBlock(kind, block, name, error_reason);
            return;
        }
        utxo.apply(cb, block.height);
        const record = c.Record.create(block, parent, utxo, fees.items, name);
        put(&self.records, block.hash, record);
        self.peers.getPtr(name).?.blocks += 1;
        self.log("{s} {s} {d} {s} accepted work {d}", .{ kind, name, block.height, h.short(block.hash), record.work });
        if (record.work > self.tip.work) self.switchTip(record);
    }
    fn resolve(self: *Node, start: []const u8) void {
        var queue: std.ArrayList([]const u8) = .empty;
        h.append([]const u8, &queue, start);
        var front: usize = 0;
        while (front < queue.items.len) : (front += 1) {
            const parent = queue.items[front];
            var index: usize = 0;
            while (index < self.orphans.items.len) {
                if (!h.eq(self.orphans.items[index].block.previous, parent)) {
                    index += 1;
                    continue;
                }
                const orphan = self.orphans.orderedRemove(index);
                if (self.rejected.contains(parent)) self.rejectBlock("UNORPHAN", orphan.block, orphan.peer,
                     "bad-parent") else self.connect("UNORPHAN", orphan.block, orphan.peer);
                h.append([]const u8, &queue, orphan.block.hash);
            }
        }
    }
    fn receiveBlock(self: *Node, block: b.Block, name: []const u8) void {
        var duplicate = self.records.contains(block.hash) or self.rejected.contains(block.hash);
        for (self.orphans.items) |orphan| if (h.eq(orphan.block.hash, block.hash)) {
            duplicate = true;
        };
        if (duplicate) {
            self.peers.getPtr(name).?.rejected_blocks += 1;
            self.tally("block", "duplicate");
            self.log("BLOCK {s} {d} {s} rejected duplicate", .{ name, block.height, h.short(block.hash) });
            return;
        }
        var reason = b.contextError(block, self.params.max_size);
        if (reason == null and self.rejected.contains(block.previous)) reason = "bad-parent";
        if (reason) |error_reason| {
            self.rejectBlock("BLOCK", block, name, error_reason);
            self.resolve(block.hash);
            return;
        }
        if (!self.records.contains(block.previous)) {
            h.append(Orphan, &self.orphans, .{ .block = block, .peer = name });
            self.peers.getPtr(name).?.orphans += 1;
            self.log("BLOCK {s} {d} {s} orphan parent {s}", .{ name, block.height, h.short(block.hash),
                 h.short(block.previous) });
            if (self.orphans.items.len > self.params.orphan_limit) {
                const removed = self.orphans.orderedRemove(0);
                self.log("EVICT {s} orphan-limit", .{h.short(removed.block.hash)});
            }
            return;
        }
        self.connect("BLOCK", block, name);
        self.resolve(block.hash);
    }
    fn pay(self: *Node, fields: []const []const u8) void {
        const wallet = w.named(self.wallets, fields[2]);
        const fee = h.number(fields[3]);
        var total: i64 = 0;
        var outputs: std.ArrayList(t.Output) = .empty;
        var index: usize = 4;
        while (index < fields.len) : (index += 2) {
            const amount = h.number(fields[index + 1]);
            h.append(t.Output, &outputs, .{ .address = w.named(self.wallets, fields[index]).address, .amount = amount });
            total += amount;
        }
        const prefix = h.fmt("PAY {s} fee {d} total {d}", .{ wallet.name, fee, total });
        var coins: std.ArrayList(t.Coin) = .empty;
        for (self.tip.utxo.coins.items) |coin| if (h.eq(coin.address, wallet.address) and !self.locked(coin.reference) and coin.mature(self.nextHeight(),
             self.params.maturity)) h.append(t.Coin, &coins, coin);
        std.mem.sort(t.Coin, coins.items, {}, selectionOrder);
        var inputs: std.ArrayList(t.Reference) = .empty;
        var gathered: i64 = 0;
        for (coins.items) |coin| {
            if (gathered >= total + fee) break;
            h.append(t.Reference, &inputs, coin.reference);
            gathered += coin.amount;
        }
        if (gathered < total + fee) {
            self.log("{s} rejected insufficient-funds", .{prefix});
            self.tally("pay", "insufficient-funds");
            return;
        }
        if (gathered > total + fee) h.append(t.Output, &outputs, .{ .address = wallet.address, .amount = gathered - total - fee });
        const tx = t.payment(inputs.items, outputs.items, wallet.secret);
        const result = self.acceptance(tx);
        if (result.reason) |reason| {
            self.log("{s} tx {s} rejected {s}", .{ prefix, h.short(tx.id), reason });
            self.tally("pay", reason);
            return;
        }
        self.log("{s} tx {s} accepted inputs {d} outputs {d} size {d}", .{ prefix, h.short(tx.id),
             tx.inputs.len, tx.outputs.len, tx.size() });
        self.register(tx, result, self.now);
    }
    fn bump(self: *Node, id: []const u8, fee: i64) void {
        const prefix = h.fmt("BUMP {s} fee {d}", .{ h.short(id), fee });
        const entry = self.findEntry(id) orelse {
            self.log("{s} rejected unknown", .{prefix});
            self.tally("bump", "unknown");
            return;
        };
        const outputs = h.dupe(t.Output, entry.tx.outputs);
        const last = &outputs[outputs.len - 1];
        last.amount -= fee - entry.fee;
        var same_address = true;
        for (entry.tx.inputs) |reference| if (!h.eq(self.tip.utxo.find(reference).?.address, last.address)) {
            same_address = false;
        };
        if (!same_address or last.amount < 1) {
            self.log("{s} rejected no-change", .{prefix});
            self.tally("bump", "no-change");
            return;
        }
        const tx = t.payment(entry.tx.inputs, outputs, w.owner(self.wallets, last.address).?.secret);
        const result = self.acceptance(tx);
        if (result.reason) |reason| {
            self.log("{s} tx {s} rejected {s}", .{ prefix, h.short(tx.id), reason });
            self.tally("bump", reason);
            return;
        }
        self.log("{s} tx {s} accepted size {d}", .{ prefix, h.short(tx.id), tx.size() });
        self.register(tx, result, self.now);
    }
    fn receiveTransaction(self: *Node, name: []const u8, tx: *const t.Transaction) void {
        const result = self.acceptance(tx);
        if (result.reason) |reason| {
            self.peers.getPtr(name).?.rejected_txs += 1;
            self.tally("tx", reason);
            self.log("TX {s} {s} rejected {s}", .{ name, h.short(tx.id), reason });
            if (h.eq(reason, "coinbase") or h.eq(reason, "bad-output") or h.eq(reason, "bad-sig") or h.eq(reason,
                 "overspend")) self.penalize(name, self.params.tx_penalty);
            return;
        }
        self.peers.getPtr(name).?.txs += 1;
        self.log("TX {s} {s} accepted fee {d} size {d}", .{ name, h.short(tx.id), result.fee, tx.size() });
        self.register(tx, result, self.now);
    }
    fn mine(self: *Node, wallet: w.Wallet) void {
        const height = self.nextHeight();
        var size: i64 = 0;
        var fees: i64 = 0;
        var selected: std.ArrayList(*const t.Transaction) = .empty;
        var amounts: std.ArrayList(i64) = .empty;
        for (self.ordered()) |entry| if (size + entry.tx.size() <= self.params.max_size) {
            h.append(*const t.Transaction, &selected, entry.tx);
            h.append(i64, &amounts, entry.fee);
            size += entry.tx.size();
            fees += entry.fee;
        };
        const txs = h.alloc(*const t.Transaction, selected.items.len + 1);
        txs[0] = t.coinbase(height, &.{.{ .address = wallet.address, .amount = self.blockReward(height) + fees }});
        @memcpy(txs[1..], selected.items);
        const block = b.mine(height, self.tip.block.hash, txs, @max(self.now, c.medianTime(self.tip) + 1),
             self.nextBits(self.tip));
        var utxo = self.tip.utxo.copy();
        for (txs) |tx| utxo.apply(tx, height);
        const record = c.Record.create(block, self.tip, utxo, amounts.items, "local");
        put(&self.records, block.hash, record);
        self.log("MINE {s} {d} {s} bits {d} nonce {d} txs {d} size {d} fees {d} work {d}", .{ wallet.name,
             height, h.short(block.hash), block.difficulty, block.nonce, txs.len, size, fees, record.work });
        self.switchTip(record);
    }
    fn status(self: *Node, id: []const u8) void {
        if (self.confirmed.get(id)) |height| {
            self.log("STATUS {s} confirmed {d} confirmations {d}", .{ h.short(id), height, self.nextHeight() - height });
            return;
        }
        const order = self.ordered();
        for (order, 1..) |entry, rank| if (h.eq(entry.tx.id, id)) {
            self.log("STATUS {s} mempool rank {d} of {d}", .{ h.short(id), rank, order.len });
            return;
        };
        if (self.drops.get(id)) |reason| {
            self.log("STATUS {s} dropped {s}", .{ h.short(id), reason });
            return;
        }
        var records = self.records.valueIterator();
        while (records.next()) |record| for (record.*.block.transactions) |tx| if (h.eq(tx.id, id)) {
            self.log("STATUS {s} stale", .{h.short(id)});
            return;
        };
        self.log("STATUS {s} unknown", .{h.short(id)});
    }
    fn print(self: *Node) void {
        var size: i64 = 0;
        for (self.pool.items) |entry| size += entry.tx.size();
        self.log("PRINT height {d} tip {s} work {d} bits {d} reward {d} mempool {d} size {d} orphans {d}",
             .{ self.tip.block.height, h.short(self.tip.block.hash), self.tip.work, self.nextBits(self.tip),
             self.blockReward(self.nextHeight()), self.pool.items.len, size, self.orphans.items.len });
        for (self.ordered(), 1..) |entry, rank| self.log("MEMPOOL {d} {s} fee {d} size {d}", .{ rank,
             h.short(entry.tx.id), entry.fee, entry.tx.size() });
        for (self.wallets) |wallet| self.log("BALANCE {s} {d}", .{ wallet.name, self.balance(wallet.address) });
    }
    fn miner(self: *const Node, record: *const c.Record) []const u8 {
        return if (record.block.height == 0) "-" else w.owner(self.wallets, record.block.transactions[0].outputs[0].address).?.name;
    }
    fn chainReport(self: *Node) h.Lines {
        var out: h.Lines = .{};
        out.add("TIP {d} {s} work {d} stored {d} orphans {d}", .{ self.tip.block.height, self.tip.block.hash,
             self.tip.work, self.records.count(), self.orphans.items.len });
        var rewards: i64 = 0;
        var fees: i64 = 0;
        var coinbases: i64 = 0;
        for (self.main_chain) |record| {
            const block = record.block;
            out.add("BLOCK {d} {s} prev {s} time {d} bits {d} nonce {d} txs {d} size {d} fees {d} miner {s} source {s} work {d}",
                 .{ block.height, block.hash, h.short(block.previous), block.time, block.difficulty,
                 block.nonce, block.transactions.len, block.size(), record.fees, self.miner(record),
                 record.source, record.work });
            for (block.transactions, 0..) |tx, index| {
                if (tx.coinbase_height != null) out.add("TX {d} {s} {s} out {d} amount {d}", .{ index + 1,
                     tx.id, if (block.height == 0) "genesis" else "coinbase", tx.outputs.len, tx.total() }) else out.add("TX {d} {s} payment in {d} out {d} size {d} fee {d}",
                     .{ index + 1, tx.id, tx.inputs.len, tx.outputs.len, tx.size(), record.transaction_fees[index - 1] });
            }
            if (block.height > 0) {
                rewards += self.blockReward(block.height);
                fees += record.fees;
                coinbases += block.transactions[0].total();
            }
        }
        var stale: std.ArrayList(*c.Record) = .empty;
        var records = self.records.valueIterator();
        while (records.next()) |record| {
            var main = false;
            for (self.main_chain) |item| if (item == record.*) {
                main = true;
            };
            if (!main) h.append(*c.Record, &stale, record.*);
        }
        std.mem.sort(*c.Record, stale.items, {}, recordOrder);
        for (stale.items) |record| out.add("STALE {d} {s} prev {s} source {s} work {d}", .{ record.block.height,
             record.block.hash, h.short(record.block.previous), record.source, record.work });
        for (self.orphans.items) |orphan| out.add("ORPHAN {d} {s} prev {s} source {s}", .{ orphan.block.height,
             orphan.block.hash, h.short(orphan.block.previous), orphan.peer });
        for (self.reorganizations.items) |r| out.add("REORG {d} fork {d} disconnected {d} connected {d} old {s} new {s}",
             .{ r.time, r.fork, r.disconnected, r.connected, h.short(r.old_hash), h.short(r.new_hash) });
        for (self.wallets) |wallet| {
            var count: usize = 0;
            var amount: i64 = 0;
            var miner_fees: i64 = 0;
            for (self.main_chain[1..]) |record| if (h.eq(self.miner(record), wallet.name)) {
                count += 1;
                amount += record.block.transactions[0].total();
                miner_fees += record.fees;
            };
            if (count > 0) out.add("MINER {s} blocks {d} coinbase {d} fees {d}", .{ wallet.name, count, amount, miner_fees });
        }
        var first: usize = 1;
        while (first < self.main_chain.len) {
            var last = first;
            const bits = self.main_chain[first].block.difficulty;
            while (last + 1 < self.main_chain.len and self.main_chain[last + 1].block.difficulty == bits) last += 1;
            out.add("BITS {d} heights {d}-{d} blocks {d}", .{ bits, first, last, last - first + 1 });
            first = last + 1;
        }
        const names = h.alloc([]const u8, self.peers.count());
        var keys = self.peers.keyIterator();
        var index: usize = 0;
        while (keys.next()) |name| {
            names[index] = name.*;
            index += 1;
        }
        std.mem.sort([]const u8, names, {}, stringOrder);
        for (names) |name| {
            const peer = self.peers.get(name).?;
            out.add("PEER {s} blocks {d} rejected {d} orphans {d} txs {d} rejected {d} ignored {d} score {d} {s}",
                 .{ name, peer.blocks, peer.rejected_blocks, peer.orphans, peer.txs, peer.rejected_txs,
                 peer.ignored, peer.score, if (peer.score >= self.params.ban) "banned" else "ok" });
        }
        for (self.ordered(), 1..) |entry, rank| out.add("MEMPOOL {d} {s} fee {d} size {d} time {d}",
             .{ rank, entry.tx.id, entry.fee, entry.tx.size(), entry.arrival });
        const tallies = h.alloc([]const u8, self.rejections.count());
        var rejection_keys = self.rejections.keyIterator();
        index = 0;
        while (rejection_keys.next()) |key| {
            tallies[index] = key.*;
            index += 1;
        }
        std.mem.sort([]const u8, tallies, {}, stringOrder);
        for (tallies) |key| out.add("REJECT {s} {d}", .{ key, self.rejections.get(key).? });
        var total: i64 = 0;
        for (self.tip.utxo.coins.items) |coin| total += coin.amount;
        out.add("SUPPLY genesis {d} rewards {d} fees {d} burned {d} utxo {d}", .{ self.main_chain[0].block.transactions[0].total(),
             rewards, fees, rewards + fees - coinbases, total });
        return out;
    }
    fn balancesReport(self: *const Node) h.Lines {
        var out: h.Lines = .{};
        out.add("wallet,address,balance,immature,locked,incoming,utxos", .{});
        for (self.wallets) |wallet| {
            var amount: i64 = 0;
            var immature: i64 = 0;
            var locked_amount: i64 = 0;
            var incoming: i64 = 0;
            var count: usize = 0;
            for (self.tip.utxo.coins.items) |coin| if (h.eq(coin.address, wallet.address)) {
                amount += coin.amount;
                count += 1;
                if (!coin.mature(self.nextHeight(), self.params.maturity)) immature += coin.amount;
                if (self.locked(coin.reference)) locked_amount += coin.amount;
            };
            for (self.pool.items) |entry| for (entry.tx.outputs) |output| if (h.eq(output.address, wallet.address)) {
                incoming += output.amount;
            };
            out.add("{s},{s},{d},{d},{d},{d},{d}", .{ wallet.name, wallet.address, amount, immature,
                 locked_amount, incoming, count });
        }
        return out;
    }
    fn utxoReport(self: *const Node) h.Lines {
        var out: h.Lines = .{};
        const coins = h.dupe(t.Coin, self.tip.utxo.coins.items);
        std.mem.sort(t.Coin, coins, {}, coinOrder);
        const hashes = h.alloc([]const u8, coins.len);
        var total: i64 = 0;
        for (coins, hashes) |coin, *hash| {
            const category = if (coin.height == 0) "genesis" else if (coin.coinbase) "coinbase" else "payment";
            const state = if (!coin.mature(self.nextHeight(), self.params.maturity)) "immature" else if (self.locked(coin.reference)) "locked" else "free";
            const line = h.fmt("{s}:{d} {s} {d} height {d} {s} {s}", .{ coin.reference.id, coin.reference.index,
                 w.owner(self.wallets, coin.address).?.name, coin.amount, coin.height, category, state });
            out.add("{s}", .{line});
            hash.* = h.digest(line);
            total += coin.amount;
        }
        out.add("TOTAL {d} {d}", .{ coins.len, total });
        out.add("ROOT {s}", .{h.merkle(hashes)});
        return out;
    }
    fn referenceOutput(self: *const Node, reference: t.Reference) t.Output {
        for (self.main_chain) |record| for (record.block.transactions) |tx| if (h.eq(tx.id, reference.id)) return tx.outputs[reference.index];
        unreachable;
    }
    fn signed(value: i64) []const u8 {
        return h.fmt("{s}{d}", .{ if (value >= 0) "+" else "", value });
    }
    fn historyReport(self: *const Node) h.Lines {
        var out: h.Lines = .{};
        for (self.wallets) |wallet| {
            out.add("WALLET {s} {s}", .{ wallet.name, wallet.address });
            var count: usize = 0;
            var total_spent: i64 = 0;
            var total_received: i64 = 0;
            var balance_value: i64 = 0;
            var pending: usize = 0;
            for (self.main_chain) |record| for (record.block.transactions) |tx| {
                var spent: i64 = 0;
                var received: i64 = 0;
                for (tx.inputs) |reference| {
                    const output = self.referenceOutput(reference);
                    if (h.eq(output.address, wallet.address)) spent += output.amount;
                }
                for (tx.outputs) |output| if (h.eq(output.address, wallet.address)) {
                    received += output.amount;
                };
                if (spent == 0 and received == 0) continue;
                count += 1;
                total_spent += spent;
                total_received += received;
                balance_value += received - spent;
                const category = if (record.block.height == 0) "genesis" else if (tx.coinbase_height != null) "coinbase" else "payment";
                out.add("{d} {s} {s} spent {d} received {d} net {s} balance {d}", .{ record.block.height,
                     h.short(tx.id), category, spent, received, signed(received - spent), balance_value });
            };
            for (self.ordered()) |entry| {
                var spent: i64 = 0;
                var received: i64 = 0;
                for (entry.tx.inputs) |reference| {
                    const coin = self.tip.utxo.find(reference).?;
                    if (h.eq(coin.address, wallet.address)) spent += coin.amount;
                }
                for (entry.tx.outputs) |output| if (h.eq(output.address, wallet.address)) {
                    received += output.amount;
                };
                if (spent == 0 and received == 0) continue;
                pending += 1;
                out.add("pending {s} spent {d} received {d} net {s}", .{ h.short(entry.tx.id), spent,
                     received, signed(received - spent) });
            }
            out.add("END {s} txs {d} spent {d} received {d} balance {d} pending {d}", .{ wallet.name,
                 count, total_spent, total_received, balance_value, pending });
        }
        return out;
    }
    fn run(self: *Node, io: std.Io) !void {
        const lines = try h.readLines(io, "events.txt");
        var index: usize = 0;
        while (index < lines.len) {
            const fields = h.split(lines[index], ' ');
            index += 1;
            const kind = fields[1];
            var texts: []const []const u8 = &.{};
            if (h.eq(kind, "BLOCK")) {
                const count = h.u(h.number(fields[9]));
                texts = lines[index .. index + count];
                index += count;
            }
            self.now = h.number(fields[0]);
            var position: usize = 0;
            while (position < self.pool.items.len) {
                const entry = self.pool.items[position];
                if (self.now - entry.arrival >= self.params.expiry) self.drop(entry.tx.id, "expired") else position += 1;
            }
            if (h.eq(kind, "PAY")) self.pay(fields) else if (h.eq(kind, "BUMP")) self.bump(fields[2],
                 h.number(fields[3])) else if (h.eq(kind, "MINE")) self.mine(w.named(self.wallets,
                 fields[2])) else if (h.eq(kind, "STATUS")) self.status(fields[2]) else if (h.eq(kind,
                 "PRINT")) self.print() else {
                const name = fields[2];
                if (!self.peers.contains(name)) put(&self.peers, name, Peer{});
                if (self.peers.get(name).?.score >= self.params.ban) {
                    self.peers.getPtr(name).?.ignored += 1;
                    self.log("IGNORE {s} {s}", .{ name, kind });
                } else if (h.eq(kind, "TX")) self.receiveTransaction(name, t.parse(fields[3])) else self.receiveBlock(b.parse(fields,
                     texts), name);
            }
        }
        try std.Io.Dir.cwd().createDirPath(io, "output");
        try h.writeLines(io, "log.txt", self.log_lines);
        try h.writeLines(io, "chain.txt", self.chainReport());
        try h.writeLines(io, "balances.csv", self.balancesReport());
        try h.writeLines(io, "utxo.txt", self.utxoReport());
        try h.writeLines(io, "history.txt", self.historyReport());
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    h.allocator = arena.allocator();
    const wallets = try w.read(init.io);
    const params = try Params.read(init.io, wallets);
    var node = Node.init(params, wallets);
    try node.run(init.io);
}
