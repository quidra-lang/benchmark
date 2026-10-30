const b = @import("config_io.zig");
pub const TransactionKind = enum { rd, rdx, upgr, wr, wb };
pub const transaction_names = [_][]const u8{ "BusRd", "BusRdX", "BusUpgr", "BusWr", "WB" };
pub fn dirty(state: u8) bool {
    return state == 'M' or state == 'O';
}
pub const RequestTransition = struct { transaction: ?TransactionKind, state: u8 };
pub const SnoopTransition = struct { state: u8, supply: bool = false, flush: bool = false };
pub fn requester(protocol: b.Protocol, old: u8, operation: u8, other: bool) RequestTransition {
    if (protocol == .vi) {
        if (operation == 'R') return .{ .transaction = if (old == 'I') .rd else null, .state = 'V' };
        return .{ .transaction = .wr, .state = if (old == 'I') 'I' else 'V' };
    }
    if (old == 'I') {
        if (operation == 'W') return .{ .transaction = .rdx, .state = 'M' };
        return .{ .transaction = .rd, .state = if (protocol == .msi or other) 'S' else 'E' };
    }
    if (operation == 'R') return .{ .transaction = null, .state = old };
    if (old == 'M' or old == 'E') return .{ .transaction = null, .state = 'M' };
    return .{ .transaction = .upgr, .state = 'M' };
}
pub fn snoop(protocol: b.Protocol, old: u8, transaction: TransactionKind) SnoopTransition {
    if (protocol == .vi) return .{ .state = if (transaction == .rd) 'V' else 'I' };
    if (transaction == .rd) {
        if (old == 'M') return .{ .state = if (protocol == .moesi) 'O' else 'S', .supply = true,
             .flush = protocol != .moesi };
        if (old == 'O') return .{ .state = 'O', .supply = true };
        return .{ .state = 'S' };
    }
    return .{ .state = 'I', .supply = transaction == .rdx and dirty(old) };
}
