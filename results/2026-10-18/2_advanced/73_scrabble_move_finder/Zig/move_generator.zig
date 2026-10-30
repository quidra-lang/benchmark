const std = @import("std");
const b = @import("board.zig");
const dictionary = @import("dictionary_trie.zig");
const scoring = @import("scoring.zig");
pub const Anchors = struct { cells: [15][15]bool = [_][15]bool{[_]bool{false} ** 15} ** 15, count: usize = 0 };
pub const Checks = struct { masks: [15][15]u32 = [_][15]u32{[_]u32{0} ** 15} ** 15, checked: [15][15]bool = [_][15]bool{[_]bool{false} ** 15} ** 15 };
pub fn anchors(board: *const b.Board) Anchors {
    var out: Anchors = .{};
    if (b.boardTiles(board).count == 0) {
        out.cells[7][7] = true;
        out.count = 1;
        return out;
    }
    for (0..15) |row| for (0..15) |column| {
        if (board[row][column] != '.') continue;
        const adjacent = b.neighbors(row, column);
        for (adjacent.items[0..adjacent.count]) |point| if (board[point[0]][point[1]] != '.') {
            out.cells[row][column] = true;
            out.count += 1;
            break;
        };
    };
    return out;
}
pub fn crossChecks(board: *const b.Board, trie: *const dictionary.Trie) Checks {
    var out: Checks = .{};
    for (0..15) |row| for (0..15) |column| {
        if (board[row][column] != '.') continue;
        var first = row;
        var last = row;
        while (first > 0 and board[first - 1][column] != '.') first -= 1;
        while (last + 1 < 15 and board[last + 1][column] != '.') last += 1;
        if (first == last) continue;
        out.checked[row][column] = true;
        for (0..26) |letter| {
            var word: b.Word = .{};
            for (first..last + 1) |r| word.add(if (r == row) @as(u8, @intCast(letter)) + 'A' else b.capital(board[r][column]));
            if (trie.contains(word.text())) out.masks[row][column] |= @as(u32, 1) << @intCast(letter);
        }
    };
    return out;
}
const Generator = struct {
    allocator: std.mem.Allocator,
    board: *const b.Board,
    trie: *const dictionary.Trie,
    anchor_squares: Anchors,
    checks: Checks,
    counts: b.Counts = [_]i64{0} ** 27,
    out: *std.ArrayList(b.Move),
    row: usize = 0,
    anchor: usize = 0,
    fn extend(self: *Generator, node: usize, column: usize, word: b.Word, start: usize) void {
        const empty = column == 15 or self.board[self.row][column] == '.';
        if (empty and column > self.anchor and self.trie.nodes.items[node].terminal) self.out.append(self.allocator,
             .{ .row = self.row, .column = start, .direction = 0, .word = word }) catch @panic("allocation failed");
        if (column == 15) return;
        if (!empty) {
            const written = self.board[self.row][column];
            const child = self.trie.nodes.items[node].children[b.capital(written) - 'A'];
            if (child >= 0) {
                var next = word;
                next.add(written);
                self.extend(@intCast(child), column + 1, next, start);
            }
            return;
        }
        for (0..26) |letter| {
            const child = self.trie.nodes.items[node].children[letter];
            if (child < 0 or (self.checks.checked[self.row][column] and self.checks.masks[self.row][column] & (@as(u32,
                 1) << @intCast(letter)) == 0)) continue;
            for (0..2) |blank| {
                const tile = if (blank == 1) 26 else letter;
                if (self.counts[tile] > 0) {
                    self.counts[tile] -= 1;
                    var next = word;
                    next.add(@as(u8, @intCast(letter)) + (if (blank == 1) @as(u8, 'a') else 'A'));
                    self.extend(@intCast(child), column + 1, next, start);
                    self.counts[tile] += 1;
                }
            }
        }
    }
    fn leftPart(self: *Generator, node: usize, prefix: b.Word, remaining: usize) void {
        self.extend(node, self.anchor, prefix, self.anchor - prefix.len);
        if (remaining == 0) return;
        for (0..26) |letter| {
            const child = self.trie.nodes.items[node].children[letter];
            if (child < 0) continue;
            for (0..2) |blank| {
                const tile = if (blank == 1) 26 else letter;
                if (self.counts[tile] > 0) {
                    self.counts[tile] -= 1;
                    var next = prefix;
                    next.add(@as(u8, @intCast(letter)) + (if (blank == 1) @as(u8, 'a') else 'A'));
                    self.leftPart(@intCast(child), next, remaining - 1);
                    self.counts[tile] += 1;
                }
            }
        }
    }
};
fn acrossMoves(allocator: std.mem.Allocator, board: *const b.Board, rack: []const u8, trie: *const dictionary.Trie) []b.Move {
    var out: std.ArrayList(b.Move) = .empty;
    var g: Generator = .{ .allocator = allocator, .board = board, .trie = trie, .anchor_squares = anchors(board),
         .checks = crossChecks(board, trie), .out = &out };
    for (rack) |tile| g.counts[b.tileIndex(tile)] += 1;
    for (0..15) |row| for (0..15) |anchor| {
        if (!g.anchor_squares.cells[row][anchor]) continue;
        g.row = row;
        g.anchor = anchor;
        if (anchor > 0 and board[row][anchor - 1] != '.') {
            var first = anchor - 1;
            while (first > 0 and board[row][first - 1] != '.') first -= 1;
            var prefix: b.Word = .{};
            var capital: b.Word = .{};
            for (first..anchor) |column| {
                prefix.add(board[row][column]);
                capital.add(b.capital(board[row][column]));
            }
            if (trie.prefix(capital.text())) |node| g.extend(node, anchor, prefix, first);
        } else {
            var first = b.n(anchor) - 1;
            while (first >= 0 and board[row][b.u(first)] == '.' and !g.anchor_squares.cells[row][b.u(first)]) first -= 1;
            g.leftPart(0, .{}, b.u(b.n(anchor) - first - 1));
        }
    };
    return out.items;
}
pub fn generate(allocator: std.mem.Allocator, board: *const b.Board, rack: []const u8, trie: *const dictionary.Trie) []b.Move {
    var out: std.ArrayList(b.Move) = .empty;
    for (acrossMoves(allocator, board, rack, trie)) |move| out.append(allocator, move) catch @panic("allocation failed");
    const transposed = b.transpose(board);
    for (acrossMoves(allocator, &transposed, rack, trie)) |old| {
        var move = old;
        move.row = old.column;
        move.column = old.row;
        move.direction = 1;
        const tiles = scoring.placement(board, move);
        if (tiles.count == 1) {
            const after = scoring.apply(board, tiles);
            if (b.runAt(&after, tiles.items[0].row, tiles.items[0].column, 0).word.len >= 2) continue;
        }
        out.append(allocator, move) catch @panic("allocation failed");
    }
    return out.items;
}
