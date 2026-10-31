const e = @import("entities.zig");
const Level = @import("dungeon_gen.zig").Level;
pub const direction_names = [_][]const u8{ "N", "NE", "E", "SE", "S", "SW", "W", "NW" };
pub const directions = [_]e.Point{ .{ .x = 0, .y = -1 }, .{ .x = 1, .y = -1 }, .{ .x = 1, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 1 }, .{ .x = -1, .y = 1 }, .{ .x = -1, .y = 0 }, .{ .x = -1, .y = -1 } };
pub fn passable(level: *const Level, x: i64, y: i64) bool {
    if (x < 0 or y < 0 or x >= e.n(level.width) or y >= e.n(level.height)) return false;
    const value = level.terrain[e.u(y) * level.width + e.u(x)];
    return value == '.' or value == '#' or value == '+' or value == '<' or value == '>';
}
pub fn canMove(level: *const Level, x: i64, y: i64, dx: i64, dy: i64) bool {
    if (!passable(level, x + dx, y + dy)) return false;
    return dx == 0 or dy == 0 or (level.terrain[e.u(y) * level.width + e.u(x)] != '+' and level.terrain[e.u(y + dy) * level.width + e.u(x + dx)] != '+');
}
fn lineVisible(level: *const Level, px: i64, py: i64, target_x: i64, target_y: i64) bool {
    const dx = e.abs(target_x - px);
    const dy = e.abs(target_y - py);
    const sx: i64 = if (target_x > px) 1 else -1;
    const sy: i64 = if (target_y > py) 1 else -1;
    var x = px;
    var y = py;
    var err = dx - dy;
    while (x != target_x or y != target_y) {
        const twice = 2 * err;
        if (twice > -dy) { err -= dy; x += sx; }
        if (twice < dx) { err += dx; y += sy; }
        if ((x != target_x or y != target_y) and !passable(level, x, y)) return false;
    }
    return true;
}
pub fn fieldOfView(level: *const Level, px: i64, py: i64, radius: i64) []bool {
    const visible = e.alloc(bool, level.terrain.len);
    @memset(visible, false);
    for (0..level.height) |y| {
        for (0..level.width) |x| {
            const dx = e.n(x) - px;
            const dy = e.n(y) - py;
            if (dx * dx + dy * dy <= radius * radius) visible[y * level.width + x] = lineVisible(level, px, py, e.n(x), e.n(y));
        }
    }
    return visible;
}
pub fn distances(level: *const Level, px: i64, py: i64) []i64 {
    const result = e.alloc(i64, level.terrain.len);
    @memset(result, -1);
    var queue: [2400]usize = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    queue[0] = e.u(py) * level.width + e.u(px);
    result[queue[0]] = 0;
    while (head < tail) {
        const cell = queue[head];
        head += 1;
        const x = e.n(cell % level.width);
        const y = e.n(cell / level.width);
        for (directions) |direction| {
            if (!canMove(level, x, y, direction.x, direction.y)) continue;
            const next = e.u(y + direction.y) * level.width + e.u(x + direction.x);
            if (result[next] >= 0) continue;
            result[next] = result[cell] + 1;
            queue[tail] = next;
            tail += 1;
        }
    }
    return result;
}
