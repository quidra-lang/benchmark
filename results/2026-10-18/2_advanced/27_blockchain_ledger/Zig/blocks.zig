const std = @import("std");
const h = @import("hashing.zig");
const t = @import("transactions.zig");
pub const Block = struct {
    height: i64,
    previous: []const u8,
    root: []const u8,
    time: i64,
    difficulty: i64,
    nonce: i64 = 0,
    transactions: []const *const t.Transaction,
    hash: []const u8 = "",
    pub fn header(self: Block) []const u8 {
        return h.fmt("{d}|{s}|{s}|{d}|{d}|{d}", .{ self.height, self.previous, self.root, self.time,
             self.difficulty, self.nonce });
    }
    pub fn hashHeader(self: *Block) void {
        self.hash = h.digest(self.header());
    }
    pub fn size(self: Block) i64 {
        var value: i64 = 0;
        for (self.transactions[1..]) |tx| value += tx.size();
        return value;
    }
    pub fn proof(self: Block) bool {
        for (self.hash[0..h.u(self.difficulty)]) |character| if (character != '0') return false;
        return true;
    }
    pub fn ids(self: Block) []const []const u8 {
        const result = h.alloc([]const u8, self.transactions.len);
        for (self.transactions, result) |tx, *id| id.* = tx.id;
        return result;
    }
};
pub fn parse(fields: []const []const u8, texts: []const []const u8) Block {
    const txs = h.alloc(*const t.Transaction, texts.len);
    for (texts, txs) |text, *tx| tx.* = t.parse(text);
    var block: Block = .{ .height = h.number(fields[3]), .previous = fields[4], .root = fields[5],
         .time = h.number(fields[6]), .difficulty = h.number(fields[7]), .nonce = h.number(fields[8]),
         .transactions = txs };
    block.hashHeader();
    return block;
}
pub fn mine(height: i64, previous: []const u8, txs: []const *const t.Transaction, time: i64, difficulty: i64) Block {
    var block: Block = .{ .height = height, .previous = previous, .root = "", .time = time, .difficulty = difficulty,
         .transactions = txs };
    block.root = h.merkle(block.ids());
    while (true) : (block.nonce += 1) {
        block.hashHeader();
        if (block.proof()) break;
    }
    return block;
}
pub fn contextError(block: Block, limit: i64) ?[]const u8 {
    if (!block.proof()) return "bad-pow";
    if (!h.eq(h.merkle(block.ids()), block.root)) return "bad-merkle";
    if (block.transactions[0].coinbase_height == null or block.transactions[0].coinbase_height.? != block.height) return "bad-structure";
    for (block.transactions[1..]) |tx| if (tx.coinbase_height != null) return "bad-structure";
    if (block.size() > limit) return "too-large";
    return null;
}
