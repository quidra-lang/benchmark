const std = @import("std");
const e = @import("entities.zig");
const Minstd = @import("minstd.zig").Minstd;
pub const Room = struct { x: usize, y: usize, width: usize, height: usize };
pub const RoomCell = struct { room: usize, x: i64, y: i64 };
pub const Level = struct {
    depth: usize, width: usize, height: usize, terrain: []u8, memory: []u8,
    rooms: []Room, arrival: e.Point, arrival_room: usize, target: e.Point,
    monsters: []e.Monster = &.{}, items: []*e.Item = &.{}, items_placed: usize = 0, kills: usize = 0, picked: usize = 0,
    pub fn monsterAt(self: *const Level, x: i64, y: i64) ?*e.Monster {
        for (self.monsters) |*monster| if (monster.hp > 0 and monster.x == x and monster.y == y) return monster;
        return null;
    }
    pub fn itemAt(self: *const Level, x: i64, y: i64) ?*e.Item {
        for (self.items) |item| if (item.ground and item.x == x and item.y == y) return item;
        return null;
    }
    pub fn drawInteriorCell(self: *const Level, rng: *Minstd, number: usize) RoomCell {
        const room = self.rooms[number];
        const x = room.x + 1 + rng.rnd(room.width - 2);
        const y = room.y + 1 + rng.rnd(room.height - 2);
        return .{ .room = number, .x = e.n(x), .y = e.n(y) };
    }
    pub fn drawRoomCell(self: *const Level, rng: *Minstd) RoomCell {
        const room = rng.rnd(self.rooms.len);
        return self.drawInteriorCell(rng, room);
    }
};
const Region = struct {
    x: usize, y: usize, width: usize, height: usize, start: usize = 0, end: usize = 0,
    first: ?*Region = null, second: ?*Region = null,
    fn init(x: usize, y: usize, width: usize, height: usize) *Region {
        const result = &e.alloc(Region, 1)[0];
        result.* = .{ .x = x, .y = y, .width = width, .height = height };
        return result;
    }
};
pub const Generator = struct {
    rng: *Minstd, min_size: usize, max_split: usize, room_min: usize, room_max: usize,
    fn split(self: Generator, node: *Region, depth: usize, leaves: *std.ArrayList(*Region)) void {
        const cv = node.width >= 2 * self.min_size;
        const ch = node.height >= 2 * self.min_size;
        if (depth == self.max_split or (!cv and !ch)) {
            node.start = leaves.items.len;
            e.append(*Region, leaves, node);
            node.end = leaves.items.len;
            return;
        }
        var vertical = cv;
        if (cv and ch) {
            if (4 * node.width >= 5 * node.height) vertical = true else if (4 * node.height >= 5 * node.width) vertical = false else vertical = @mod(self.rng.draw(), 2) == 0;
        }
        if (vertical) {
            const cut = self.min_size + self.rng.rnd(node.width - 2 * self.min_size + 1);
            node.first = Region.init(node.x, node.y, cut, node.height);
            node.second = Region.init(node.x + cut, node.y, node.width - cut, node.height);
        } else {
            const cut = self.min_size + self.rng.rnd(node.height - 2 * self.min_size + 1);
            node.first = Region.init(node.x, node.y, node.width, cut);
            node.second = Region.init(node.x, node.y + cut, node.width, node.height - cut);
        }
        self.split(node.first.?, depth + 1, leaves);
        self.split(node.second.?, depth + 1, leaves);
        node.start = node.first.?.start;
        node.end = node.second.?.end;
    }
    fn makeRoom(self: Generator, level: *Level, leaf: *const Region) Room {
        const width = self.room_min + self.rng.rnd(@min(self.room_max, leaf.width - 1) - self.room_min + 1);
        const height = self.room_min + self.rng.rnd(@min(self.room_max, leaf.height - 1) - self.room_min + 1);
        const x = leaf.x + self.rng.rnd(leaf.width - width);
        const y = leaf.y + self.rng.rnd(leaf.height - height);
        for (y..y + height) |row| {
            for (x..x + width) |column| {
                level.terrain[row * level.width + column] = if (row == y or row == y + height - 1) '-' else if (column == x or column == x + width - 1) '|' else '.';
            }
        }
        return .{ .x = x, .y = y, .width = width, .height = height };
    }
    fn connect(self: Generator, level: *Level, node: *const Region) void {
        const first = node.first orelse return;
        const second = node.second.?;
        self.connect(level, first);
        self.connect(level, second);
        var chosen_a: ?usize = null;
        var chosen_b: usize = 0;
        var minimum: i64 = 0;
        for (first.start..first.end) |a| {
            const ca = center(level.rooms[a]);
            for (second.start..second.end) |b| {
                const cb = center(level.rooms[b]);
                const distance = e.abs(ca.x - cb.x) + e.abs(ca.y - cb.y);
                if (chosen_a == null or distance < minimum) { chosen_a = a; chosen_b = b; minimum = distance; }
            }
        }
        const a = center(level.rooms[chosen_a.?]);
        const b = center(level.rooms[chosen_b]);
        const sx: i64 = if (b.x >= a.x) 1 else -1;
        const sy: i64 = if (b.y >= a.y) 1 else -1;
        if (@mod(self.rng.draw(), 2) == 0) {
            var x = a.x;
            while (true) : (x += sx) { digCell(level, x, a.y); if (x == b.x) break; }
            var y = a.y;
            while (true) : (y += sy) { digCell(level, b.x, y); if (y == b.y) break; }
        } else {
            var y = a.y;
            while (true) : (y += sy) { digCell(level, a.x, y); if (y == b.y) break; }
            var x = a.x;
            while (true) : (x += sx) { digCell(level, x, b.y); if (x == b.x) break; }
        }
    }
    pub fn generate(self: Generator, depth: usize, width: usize, height: usize) Level {
        var level: Level = .{ .depth = depth, .width = width, .height = height, .terrain = e.alloc(u8, width * height), .memory = e.alloc(u8, width * height), .rooms = undefined, .arrival = undefined, .arrival_room = undefined, .target = undefined };
        @memset(level.terrain, ' ');
        @memset(level.memory, ' ');
        const root = Region.init(0, 0, width, height);
        var leaves: std.ArrayList(*Region) = .empty;
        self.split(root, 0, &leaves);
        level.rooms = e.alloc(Room, leaves.items.len);
        for (leaves.items, level.rooms) |leaf, *room| room.* = self.makeRoom(&level, leaf);
        self.connect(&level, root);
        const arrival = level.drawRoomCell(self.rng);
        level.arrival = .{ .x = arrival.x, .y = arrival.y };
        level.arrival_room = arrival.room;
        level.terrain[e.u(arrival.y) * width + e.u(arrival.x)] = '<';
        var other = self.rng.rnd(level.rooms.len - 1);
        if (other >= arrival.room) other += 1;
        const target = level.drawInteriorCell(self.rng, other);
        level.target = .{ .x = target.x, .y = target.y };
        return level;
    }
};
fn center(room: Room) e.Point { return .{ .x = e.n(room.x + room.width / 2), .y = e.n(room.y + room.height / 2) }; }
fn digCell(level: *Level, x: i64, y: i64) void {
    const cell = &level.terrain[e.u(y) * level.width + e.u(x)];
    if (cell.* == ' ') cell.* = '#' else if (cell.* == '-' or cell.* == '|') cell.* = '+';
}
