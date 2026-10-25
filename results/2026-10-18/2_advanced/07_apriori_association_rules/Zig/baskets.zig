const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub var backing: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub const Counts = std.AutoHashMapUnmanaged(u128, i64);
pub const Product = struct { name: []const u8, category: usize, price: i64, code: usize };
pub const Transaction = struct { tid: []const u8, customer: []const u8, day: i64, units: []i64, mask: u128 = 0 };
pub const Frequent = struct { mask: u128, count: i64 };
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, source: []const T) []T { return allocator.dupe(T, source) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn put(counts: *Counts, mask: u128, count: i64) void { counts.put(allocator, mask, count) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(a: []const u8, c: []const u8) bool { return std.mem.eql(u8, a, c); }
pub fn textLess(a: []const u8, c: []const u8) bool { return std.mem.order(u8, a, c) == .lt; }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub fn split(text: []const u8, separator: u8) Strings { var result: std.ArrayList([]const u8) = .empty; var it = std.mem.splitScalar(u8, text, separator); while (it.next()) |part| append([]const u8, &result, part); return result.items; }
pub fn lines(text: []const u8) Strings { const result = split(text, '\n'); return result[0..result.len - 1]; }
pub fn rows(text: []const u8) []const Strings { var result: std.ArrayList(Strings) = .empty; for (lines(text)[1..]) |line| append(Strings, &result, split(line, ',')); return result.items; }
pub fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn int(value: anytype) i64 { return @intCast(value); }
pub fn bit(code: usize) u128 { return @as(u128, 1) << @intCast(code); }
pub fn contains(basket: u128, itemset: u128) bool { return basket & itemset == itemset; }
pub const Iterator = struct { mask: u128, pub fn next(it: *Iterator) ?usize { if (it.mask == 0) return null; const code: usize = @intCast(@ctz(it.mask)); it.mask &= it.mask - 1; return code; } };
pub fn iterator(mask: u128) Iterator { return .{ .mask = mask }; }
pub fn members(mask: u128) []const usize { var result: std.ArrayList(usize) = .empty; var it = iterator(mask); while (it.next()) |code| append(usize, &result, code); return result.items; }
pub fn size(mask: u128) usize { return @intCast(@popCount(mask)); }
pub fn setLess(a: u128, c: u128) bool { var first = iterator(a); var second = iterator(c); while (first.next()) |left| { const right = second.next() orelse return false; if (left != right) return left < right; } return second.next() != null; }
pub fn sizeLess(_: void, a: Frequent, c: Frequent) bool { return if (size(a.mask) == size(c.mask)) setLess(a.mask, c.mask) else size(a.mask) < size(c.mask); }
pub fn maskLess(_: void, a: u128, c: u128) bool { return setLess(a, c); }
pub fn extended(basket: Transaction, products: []const Product) u128 { var mask = basket.mask; for (basket.units, products) |quantity, product| { if (quantity > 0) mask |= bit(product.category); } return mask; }
