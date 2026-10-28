const std = @import("std");
const h = @import("hashing.zig");
pub const Wallet = struct { name: []const u8, secret: []const u8, address: []const u8 };
pub fn read(io: std.Io) ![]Wallet {
    const lines = try h.readLines(io, "wallets.txt");
    const wallets = h.alloc(Wallet, lines.len);
    for (wallets, lines) |*wallet, line| {
        const fields = h.split(line, ' ');
        wallet.* = .{ .name = fields[0], .secret = fields[1], .address = h.digest(h.fmt("addr:{s}", .{fields[1]}))[0..16] };
    }
    return wallets;
}
pub fn owner(wallets: []const Wallet, address: []const u8) ?Wallet {
    for (wallets) |wallet| if (h.eq(wallet.address, address)) return wallet;
    return null;
}
pub fn named(wallets: []const Wallet, name: []const u8) Wallet {
    for (wallets) |wallet| if (h.eq(wallet.name, name)) return wallet;
    unreachable;
}
pub fn sign(secret: []const u8, index: usize, body: []const u8) []const u8 {
    return h.digest(h.fmt("{s}:{d}:{s}", .{ secret, index, body }))[0..16];
}
