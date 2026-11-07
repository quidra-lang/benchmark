const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}

pub const size = 15;
pub const center = [2]usize{ 7, 7 };
pub const tile_order = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?";
pub const Counts = [27]i64;
pub const Word = struct {
    data: [16]u8 = [_]u8{0} ** 16,
    len: usize = 0,
    pub fn init(text: []const u8) Word {
        var out: Word = .{};
        @memcpy(out.data[0..text.len], text);
        out.len = text.len;
        return out;
    }
    pub fn text(self: *const Word) []const u8 {
        return self.data[0..self.len];
    }
    pub fn add(self: *Word, letter: u8) void {
        self.data[self.len] = letter;
        self.len += 1;
    }
};
pub const Board = [15][15]u8;
pub const Move = struct { row: usize, column: usize, direction: usize, word: Word = .{} };
pub const Tile = struct { row: usize, column: usize, letter: u8 };
pub const Placement = struct {
    items: [15]Tile = undefined,
    count: usize = 0,
    pub fn add(self: *Placement, tile: Tile) void {
        self.items[self.count] = tile;
        self.count += 1;
    }
};
pub const Tiles = struct { items: [225]Tile = undefined, count: usize = 0 };
pub const Words = struct {
    items: [225]Move = undefined,
    count: usize = 0,
    pub fn add(self: *Words, move: Move) void {
        self.items[self.count] = move;
        self.count += 1;
    }
};
pub const premiums = [_][]const u8{ "#..+...#...+..#", ".*...^...^...*.", "..*...+.+...*..",
     "+..*...+...*..+", "....*.....*....", ".^...^...^...^.", "..+...+.+...+..", "#..+...*...+..#",
     "..+...+.+...+..", ".^...^...^...^.", "....*.....*....", "+..*...+...*..+", "..*...+.+...*..",
     ".*...^...^...*.", "#..+...#...+..#" };
pub fn upper(letter: u8) bool {
    return letter >= 'A' and letter <= 'Z';
}
pub fn lower(letter: u8) bool {
    return letter >= 'a' and letter <= 'z';
}
pub fn capital(letter: u8) u8 {
    return if (lower(letter)) letter - 'a' + 'A' else letter;
}
pub fn tileIndex(letter: u8) usize {
    return if (upper(letter)) letter - 'A' else 26;
}
pub fn inside(row: i64, column: i64) bool {
    return row >= 0 and row < 15 and column >= 0 and column < 15;
}
pub fn squareName(row: usize, column: usize) []const u8 {
    return fmt("{c}{d}", .{ @as(u8, @intCast(column)) + 'A', row + 1 });
}
pub fn position(move: Move) []const u8 {
    return if (move.direction == 1) squareName(move.row, move.column) else fmt("{d}{c}", .{ move.row + 1,
         @as(u8, @intCast(move.column)) + 'A' });
}
pub fn parsePosition(text: []const u8) ?Move {
    if (text.len < 2 or text.len > 3) return null;
    const direction: usize = if (upper(text[0])) 1 else 0;
    const column = if (direction == 1) text[0] else text[text.len - 1];
    if (column < 'A' or column > 'O') return null;
    const digits = if (direction == 1) text[1..] else text[0 .. text.len - 1];
    if (digits[0] == '0') return null;
    var row: usize = 0;
    for (digits) |digit| {
        if (digit < '0' or digit > '9') return null;
        row = row * 10 + digit - '0';
    }
    if (row < 1 or row > 15) return null;
    return .{ .row = row - 1, .column = column - 'A', .direction = direction };
}
pub fn emptyBoard() Board {
    return [_][15]u8{[_]u8{'.'} ** 15} ** 15;
}
pub fn transpose(board: *const Board) Board {
    var out: Board = undefined;
    for (0..15) |row| for (0..15) |column| {
        out[row][column] = board[column][row];
    };
    return out;
}
pub fn transposeTiles(tiles: Placement) Placement {
    var out: Placement = .{};
    for (tiles.items[0..tiles.count]) |tile| out.add(.{ .row = tile.column, .column = tile.row,
         .letter = tile.letter });
    return out;
}
pub fn boardTiles(board: *const Board) Tiles {
    var out: Tiles = .{};
    for (0..15) |row| for (0..15) |column| {
        if (board[row][column] != '.') {
            out.items[out.count] = .{ .row = row, .column = column, .letter = board[row][column] };
            out.count += 1;
        }
    };
    return out;
}
pub const Neighbors = struct { items: [4][2]usize = undefined, count: usize = 0 };
pub fn neighbors(row: usize, column: usize) Neighbors {
    var out: Neighbors = .{};
    const directions = [_][2]i64{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };
    for (directions) |delta| {
        const r = n(row) + delta[0];
        const c = n(column) + delta[1];
        if (inside(r, c)) {
            out.items[out.count] = .{ u(r), u(c) };
            out.count += 1;
        }
    }
    return out;
}
pub fn runAt(board: *const Board, initial_row: usize, initial_column: usize, direction: usize) Move {
    const dr = n(direction);
    const dc = 1 - dr;
    var row = n(initial_row);
    var column = n(initial_column);
    while (inside(row - dr, column - dc) and board[u(row - dr)][u(column - dc)] != '.') {
        row -= dr;
        column -= dc;
    }
    var out: Move = .{ .row = u(row), .column = u(column), .direction = direction };
    while (inside(row, column) and board[u(row)][u(column)] != '.') {
        out.word.add(board[u(row)][u(column)]);
        row += dr;
        column += dc;
    }
    return out;
}
pub fn boardWords(board: *const Board) Words {
    var out: Words = .{};
    for (0..2) |direction| for (0..15) |line| {
        var offset: usize = 0;
        while (offset < 15) {
            const row = if (direction == 1) offset else line;
            const column = if (direction == 1) line else offset;
            if (board[row][column] == '.') {
                offset += 1;
                continue;
            }
            const word = runAt(board, row, column, direction);
            if (word.word.len >= 2) out.add(word);
            offset += word.word.len;
        }
    };
    return out;
}
pub fn connected(board: *const Board) bool {
    const tiles = boardTiles(board);
    if (tiles.count == 0) return true;
    var seen = [_][15]bool{[_]bool{false} ** 15} ** 15;
    var pending: [225][2]usize = undefined;
    pending[0] = .{ tiles.items[0].row, tiles.items[0].column };
    seen[pending[0][0]][pending[0][1]] = true;
    var count: usize = 1;
    var head: usize = 0;
    while (head < count) {
        const adjacent = neighbors(pending[head][0], pending[head][1]);
        head += 1;
        for (adjacent.items[0..adjacent.count]) |point| if (board[point[0]][point[1]] != '.' and !seen[point[0]][point[1]]) {
            seen[point[0]][point[1]] = true;
            pending[count] = point;
            count += 1;
        };
    }
    return count == tiles.count;
}
pub fn display(board: *const Board) Lines {
    var out: Lines = .{};
    out.add("   A B C D E F G H I J K L M N O", .{});
    for (0..15) |row| {
        var text: Text = .{};
        text.add("{s}{d} ", .{ if (row < 9) " " else "", row + 1 });
        for (0..15) |column| {
            if (column > 0) text.add(" ", .{});
            text.add("{c}", .{if (board[row][column] == '.') premiums[row][column] else board[row][column]});
        }
        out.add("{s}", .{text.value()});
    }
    return out;
}
