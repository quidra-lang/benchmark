const std = @import("std");
const Dice = @import("combat.zig").Dice;
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn number(source: []const u8) i64 { return std.fmt.parseInt(i64, source, 10) catch unreachable; }
pub fn integer(source: []const u8) usize { return u(number(source)); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, source: []const u8) void { self.data.appendSlice(allocator, source) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, source: []const u8) void { append([]const u8, &self.data, source); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
};
pub const Point = struct { x: i64, y: i64 };
pub const MonsterType = struct {
    name: []const u8, symbol: u8, min_depth: usize, max_depth: usize, weight: usize,
    hp: Dice, damage: Dice, to_hit: i64, defense: i64, speed: usize, xp: i64,
    erratic: bool, stationary: bool, regenerates: bool, poisonous: bool,
    pub fn parse(tokens: Strings) MonsterType {
        return .{
            .name = tokens[0], .symbol = tokens[1][0], .min_depth = integer(tokens[2]), .max_depth = integer(tokens[3]), .weight = integer(tokens[4]),
            .hp = Dice.parse(tokens[5]), .to_hit = number(tokens[6]), .defense = number(tokens[7]), .damage = Dice.parse(tokens[8]), .speed = integer(tokens[9]), .xp = number(tokens[10]),
            .erratic = std.mem.indexOfScalar(u8, tokens[11], 'E') != null, .stationary = std.mem.indexOfScalar(u8, tokens[11], 'S') != null,
            .regenerates = std.mem.indexOfScalar(u8, tokens[11], 'R') != null, .poisonous = std.mem.indexOfScalar(u8, tokens[11], 'P') != null,
        };
    }
};
pub const ItemClass = enum { weapon, armor, potion, scroll, food, gold, amulet };
pub const ItemType = struct {
    category: ItemClass, name: []const u8, min_depth: usize = 0, max_depth: usize = 0, weight: usize = 0,
    dice: Dice = .{ .count = 1, .sides = 1 }, effect: []const u8 = "", to_hit: i64 = 0, armor: i64 = 0, poison_turns: i64 = 0, nutrition: i64 = 0,
    pub fn parse(tokens: Strings) ItemType {
        var category: ItemClass = undefined;
        inline for (std.meta.fields(ItemClass)) |field| if (eq(tokens[0], field.name)) { category = @enumFromInt(field.value); };
        var result: ItemType = .{ .category = category, .name = tokens[1], .min_depth = integer(tokens[2]), .max_depth = integer(tokens[3]), .weight = integer(tokens[4]) };
        switch (category) {
            .weapon => { result.dice = Dice.parse(tokens[5]); result.to_hit = number(tokens[6]); },
            .armor => result.armor = number(tokens[5]),
            .potion => {
                result.effect = tokens[5];
                if (eq(result.effect, "heal")) result.dice = Dice.parse(tokens[6]) else if (eq(result.effect, "poison")) result.poison_turns = number(tokens[6]);
            },
            .scroll => result.effect = tokens[5],
            .food => result.nutrition = number(tokens[5]),
            .gold => result.dice = Dice.parse(tokens[5]),
            .amulet => unreachable,
        }
        return result;
    }
};
pub const Monster = struct {
    number: usize = 0, kind: *const MonsterType = undefined, x: i64 = 0, y: i64 = 0,
    hp: i64 = 0, max_hp: i64 = 0, energy: usize = 0, asleep: bool = false, was_visible: bool = false,
};
pub const Item = struct {
    kind: *const ItemType, x: i64 = 0, y: i64 = 0, amount: i64 = 0, bonus: i64 = 0, ground: bool = false,
    pub fn symbol(self: *const Item) u8 { return ")[!?%$\""[@intFromEnum(self.kind.category)]; }
    pub fn displayName(self: *const Item) []const u8 {
        const name = alloc(u8, self.kind.name.len);
        for (self.kind.name, name) |character, *target| target.* = if (character == '_') ' ' else character;
        if (self.kind.category == .weapon or self.kind.category == .armor) return fmt("+{d} {s}", .{ self.bonus, name });
        if (self.kind.category == .gold) return fmt("{d} gold", .{self.amount});
        return name;
    }
    pub fn referenceName(self: *const Item) []const u8 { return if (self.kind.category == .gold) self.displayName() else fmt("the {s}", .{self.displayName()}); }
};
