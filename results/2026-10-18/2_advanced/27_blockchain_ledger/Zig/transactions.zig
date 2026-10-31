const std = @import("std");
const h = @import("hashing.zig");
const w = @import("wallets.zig");
pub const Reference = struct { id: []const u8, index: usize };
pub fn same(a: Reference, b: Reference) bool {
    return a.index == b.index and h.eq(a.id, b.id);
}
pub fn referenceOrder(a: Reference, b: Reference) bool {
    const order = std.mem.order(u8, a.id, b.id);
    return if (order == .eq) a.index < b.index else order == .lt;
}
pub const Output = struct { address: []const u8, amount: i64 };
pub const Transaction = struct {
    text: []const u8,
    id: []const u8,
    body: []const u8 = "",
    inputs: []const Reference = &.{},
    outputs: []const Output,
    signatures: []const []const u8 = &.{},
    coinbase_height: ?i64 = null,
    pub fn total(self: *const Transaction) i64 {
        var result: i64 = 0;
        for (self.outputs) |output| result += output.amount;
        return result;
    }
    pub fn size(self: *const Transaction) i64 {
        return h.n(self.text.len);
    }
};
pub const Coin = struct {
    reference: Reference,
    address: []const u8,
    amount: i64,
    height: i64,
    coinbase: bool,
    pub fn mature(self: Coin, height: i64, maturity: i64) bool {
        return !self.coinbase or self.height == 0 or height >= self.height + maturity;
    }
};
pub const Utxo = struct {
    coins: std.ArrayList(Coin) = .empty,
    pub fn find(self: *const Utxo, reference: Reference) ?Coin {
        for (self.coins.items) |coin| if (same(coin.reference, reference)) return coin;
        return null;
    }
    pub fn copy(self: Utxo) Utxo {
        var result: Utxo = .{};
        for (self.coins.items) |coin| h.append(Coin, &result.coins, coin);
        return result;
    }
    pub fn apply(self: *Utxo, tx: *const Transaction, height: i64) void {
        for (tx.inputs) |reference| {
            for (self.coins.items, 0..) |coin, index| if (same(coin.reference, reference)) {
                _ = self.coins.orderedRemove(index);
                break;
            };
        }
        for (tx.outputs, 0..) |output, index| {
            const coin: Coin = .{ .reference = .{ .id = tx.id, .index = index }, .address = output.address,
                 .amount = output.amount, .height = height, .coinbase = tx.coinbase_height != null };
            var replaced = false;
            for (self.coins.items) |*old| if (same(old.reference, coin.reference)) {
                old.* = coin;
                replaced = true;
                break;
            };
            if (!replaced) h.append(Coin, &self.coins, coin);
        }
    }
};
pub fn parse(text: []const u8) *const Transaction {
    const fields = h.split(text, ';');
    const values = h.split(fields[1][4..], ',');
    const outputs = h.alloc(Output, values.len);
    for (values, outputs) |value, *output| {
        const pair = h.split(value, ':');
        output.* = .{ .address = pair[0], .amount = h.number(pair[1]) };
    }
    var tx: Transaction = .{ .text = text, .id = h.digest(text), .outputs = outputs };
    if (std.mem.startsWith(u8, fields[0], "cb=")) tx.coinbase_height = h.number(fields[0][3..]) else {
        tx.body = text[0..std.mem.indexOf(u8, text, ";sig=").?];
        const refs = h.split(fields[0][3..], ',');
        const inputs = h.alloc(Reference, refs.len);
        for (refs, inputs) |value, *reference| {
            const pair = h.split(value, ':');
            reference.* = .{ .id = pair[0], .index = h.u(h.number(pair[1])) };
        }
        tx.inputs = inputs;
        tx.signatures = h.split(fields[2][4..], ',');
    }
    return h.create(Transaction, tx);
}
fn appendOutputs(text: *h.Text, outputs: []const Output) void {
    for (outputs, 0..) |output, index| text.add("{s}{s}:{d}", .{ if (index > 0) "," else "", output.address, output.amount });
}
pub fn payment(inputs: []const Reference, outputs: []const Output, secret: []const u8) *const Transaction {
    var body: h.Text = .{};
    body.add("in=", .{});
    for (inputs, 0..) |reference, index| body.add("{s}{s}:{d}", .{ if (index > 0) "," else "", reference.id, reference.index });
    body.add(";out=", .{});
    appendOutputs(&body, outputs);
    var text: h.Text = .{};
    text.add("{s};sig=", .{body.value()});
    for (inputs, 0..) |_, index| text.add("{s}{s}", .{ if (index > 0) "," else "", w.sign(secret, index, body.value()) });
    return parse(text.value());
}
pub fn coinbase(height: i64, outputs: []const Output) *const Transaction {
    var text: h.Text = .{};
    text.add("cb={d};out=", .{height});
    appendOutputs(&text, outputs);
    return parse(text.value());
}
pub const Check = struct { reason: ?[]const u8 = null, fee: i64 = 0 };
pub fn check(tx: *const Transaction, utxo: *const Utxo, spent: []const Reference, height: i64, wallets: []const w.Wallet,
     maturity: i64) Check {
    for (tx.outputs) |output| if (w.owner(wallets, output.address) == null or output.amount == 0) return .{ .reason = "bad-output" };
    var total: i64 = 0;
    for (tx.inputs, 0..) |reference, index| {
        for (spent) |other| if (same(reference, other)) return .{ .reason = "double-spend" };
        for (tx.inputs[0..index]) |other| if (same(reference, other)) return .{ .reason = "double-spend" };
        const coin = utxo.find(reference) orelse return .{ .reason = "missing-input" };
        if (!coin.mature(height, maturity)) return .{ .reason = "immature" };
        if (!h.eq(tx.signatures[index], w.sign(w.owner(wallets, coin.address).?.secret, index, tx.body))) return .{ .reason = "bad-sig" };
        total += coin.amount;
    }
    if (total < tx.total()) return .{ .reason = "overspend" };
    return .{ .fee = total - tx.total() };
}
