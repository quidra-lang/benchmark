const std = @import("std");
const b = @import("board.zig");
pub const Node = struct { children: [26]i32 = [_]i32{-1} ** 26, terminal: bool = false };
pub const Trie = struct {
    nodes: std.ArrayList(Node) = .empty,
    words: usize = 0,
    pub fn init() Trie {
        var out: Trie = .{};
        b.append(Node, &out.nodes, .{});
        return out;
    }
    pub fn add(self: *Trie, word: []const u8) bool {
        var node: usize = 0;
        for (word) |letter| {
            const index = letter - 'A';
            if (self.nodes.items[node].children[index] < 0) {
                const child: i32 = @intCast(self.nodes.items.len);
                self.nodes.items[node].children[index] = child;
                b.append(Node, &self.nodes, .{});
            }
            node = @intCast(self.nodes.items[node].children[index]);
        }
        if (self.nodes.items[node].terminal) return false;
        self.nodes.items[node].terminal = true;
        self.words += 1;
        return true;
    }
    pub fn prefix(self: *const Trie, word: []const u8) ?usize {
        var node: usize = 0;
        for (word) |letter| {
            const child = self.nodes.items[node].children[letter - 'A'];
            if (child < 0) return null;
            node = @intCast(child);
        }
        return node;
    }
    pub fn contains(self: *const Trie, word: []const u8) bool {
        return if (self.prefix(word)) |node| self.nodes.items[node].terminal else false;
    }
    fn visit(self: *const Trie, allocator: std.mem.Allocator, node: usize, counts: *b.Counts,
         word: b.Word, out: *std.ArrayList(b.Word)) void {
        if (self.nodes.items[node].terminal) out.append(allocator, word) catch @panic("allocation failed");
        for (0..26) |letter| {
            const child = self.nodes.items[node].children[letter];
            if (child < 0) continue;
            const tile: usize = if (counts[letter] > 0) letter else 26;
            if (counts[tile] > 0) {
                counts[tile] -= 1;
                var next = word;
                next.add(@as(u8, @intCast(letter)) + 'A');
                self.visit(allocator, @intCast(child), counts, next, out);
                counts[tile] += 1;
            }
        }
    }
    pub fn anagrams(self: *const Trie, allocator: std.mem.Allocator, rack: []const u8) []b.Word {
        var counts = [_]i64{0} ** 27;
        for (rack) |tile| counts[b.tileIndex(tile)] += 1;
        var out: std.ArrayList(b.Word) = .empty;
        self.visit(allocator, 0, &counts, .{}, &out);
        return out.items;
    }
};
