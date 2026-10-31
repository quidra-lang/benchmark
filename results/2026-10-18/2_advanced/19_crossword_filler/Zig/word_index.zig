const std = @import("std");
const g = @import("grid.zig");
pub fn validWord(text: []const u8) bool {
    if (text.len < 3 or text.len > 15) return false;
    for (text) |letter| if (letter < 'A' or letter > 'Z') return false;
    return true;
}
pub fn validInteger(text: []const u8, low: usize, high: usize) bool {
    if (text.len == 0 or text[0] == '0') return false;
    var value: usize = 0;
    for (text) |digit| {
        if (digit < '0' or digit > '9' or value > high / 10) return false;
        value = 10 * value + digit - '0';
        if (value > high) return false;
    }
    return value >= low;
}
pub fn wordLineError(line: []const u8) ?[]const u8 {
    const parts = g.split(line, ' ');
    if (parts.len != 2) return "bad format";
    if (!validWord(parts[0])) return "bad word";
    return if (validInteger(parts[1], 1, 100)) null else "bad score";
}
pub fn clueLineError(line: []const u8) ?[]const u8 {
    const parts = g.split(line, '|');
    if (parts.len != 2) return "bad format";
    if (!validWord(parts[0])) return "bad word";
    const clue = parts[1];
    return if (clue.len < 1 or clue.len > 60 or clue[0] == ' ' or clue[clue.len - 1] == ' ') "bad clue" else null;
}
pub const Word = struct { text: []const u8, score: usize, first: usize, clues: std.ArrayList(usize) = .empty };
fn rankLess(_: void, first: Word, second: Word) bool { return if (first.score != second.score) first.score > second.score else std.mem.order(u8, first.text, second.text) == .lt; }
pub fn wordMatches(word: []const u8, pattern: []const u8) bool {
    for (word, pattern) |letter, mark| if (mark != '.' and mark != letter) return false;
    return true;
}
pub const Index = struct {
    words: []Word,
    length: [16][]usize,
    letter: [16][15][26][]usize,
    pub fn init(words: []Word) Index {
        std.mem.sort(Word, words, {}, rankLess);
        var result: Index = .{ .words = words, .length = undefined, .letter = undefined };
        var lengths = [_]usize{0} ** 16;
        var letters: [16][15][26]usize = undefined;
        @memset(std.mem.asBytes(&letters), 0);
        for (words) |word| {
            lengths[word.text.len] += 1;
            for (word.text, 0..) |letter, i| letters[word.text.len][i][letter - 'A'] += 1;
        }
        for (0..16) |length| {
            result.length[length] = g.alloc(usize, lengths[length]);
            for (0..15) |position| {
                for (0..26) |letter| result.letter[length][position][letter] = g.alloc(usize, letters[length][position][letter]);
            }
        }
        @memset(&lengths, 0);
        @memset(std.mem.asBytes(&letters), 0);
        for (words, 0..) |word, id| {
            const length = word.text.len;
            result.length[length][lengths[length]] = id;
            lengths[length] += 1;
            for (word.text, 0..) |letter, position| {
                const value = letter - 'A';
                result.letter[length][position][value][letters[length][position][value]] = id;
                letters[length][position][value] += 1;
            }
        }
        return result;
    }
    pub fn find(self: *const Index, word: []const u8) ?usize {
        for (self.words, 0..) |entry, i| if (g.eq(entry.text, word)) return i;
        return null;
    }
    pub fn candidates(self: *const Index, pattern: []const u8, min_score: usize, used: []const bool, result: ?[]usize) usize {
        var pool = self.length[pattern.len];
        for (pattern, 0..) |mark, i| {
            if (mark == '.') continue;
            const bucket = self.letter[pattern.len][i][mark - 'A'];
            if (bucket.len < pool.len) pool = bucket;
        }
        var count: usize = 0;
        for (pool) |word| {
            if (self.words[word].score < min_score) break;
            if (!used[word] and wordMatches(self.words[word].text, pattern)) {
                if (result) |values| values[count] = word;
                count += 1;
            }
        }
        return count;
    }
};
