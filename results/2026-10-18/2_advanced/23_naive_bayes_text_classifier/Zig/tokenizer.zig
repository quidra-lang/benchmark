const std = @import("std");
const e = @import("evaluation.zig");
var names: std.ArrayList([]const u8) = .empty;
var buckets: []usize = &.{};

fn hashText(text: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (text) |character| hash = (hash ^ character) *% 1099511628211;
    return hash;
}
fn resizeBuckets() void {
    buckets = e.alloc(usize, if (buckets.len == 0) 1024 else 2 * buckets.len);
    @memset(buckets, 0);
    for (names.items, 0..) |term_name, i| {
        var position: usize = @intCast(hashText(term_name) & (buckets.len - 1));
        while (buckets[position] != 0) position = (position + 1) & (buckets.len - 1);
        buckets[position] = i + 1;
    }
}
fn intern(text: []const u8) usize {
    if (buckets.len == 0 or 2 * (names.items.len + 1) > buckets.len) resizeBuckets();
    var position: usize = @intCast(hashText(text) & (buckets.len - 1));
    while (buckets[position] != 0) {
        const term = buckets[position] - 1;
        if (e.eq(names.items[term], text)) return term;
        position = (position + 1) & (buckets.len - 1);
    }
    const term = names.items.len;
    e.append([]const u8, &names, text);
    buckets[position] = term + 1;
    return term;
}
pub fn count() usize { return names.items.len; }
pub fn name(term: usize) []const u8 { return names.items[term]; }
pub const Tokens = struct {
    raw_count: usize = 0,
    stopword_count: usize = 0,
    short_count: usize = 0,
    words: []const usize = &.{},
    bigram_terms: []const usize = &.{},
    pub fn terms(self: Tokens, bigrams: bool) []const usize { return if (bigrams) self.bigram_terms else self.words; }
};
pub const Document = struct { name: []const u8, label: ?usize, tokens: Tokens };
fn wordCharacter(character: u8) bool {
    return (character >= 'A' and character <= 'Z') or (character >= 'a' and character <= 'z') or (character >= '0' and character <= '9');
}
pub fn tokenize(text: []const u8, stopwords: []const []const u8) Tokens {
    var tokens: Tokens = .{};
    var words: std.ArrayList(usize) = .empty;
    var position: usize = 0;
    while (position < text.len) {
        if (!wordCharacter(text[position])) { position += 1; continue; }
        const start = position;
        while (position < text.len and wordCharacter(text[position])) position += 1;
        const word = e.alloc(u8, position - start);
        for (text[start..position], word) |character, *target| target.* = if (character >= 'A' and character <= 'Z') character + 'a' - 'A' else character;
        tokens.raw_count += 1;
        var stopped = false;
        for (stopwords) |stopword| if (e.eq(stopword, word)) { stopped = true; break; };
        if (stopped) tokens.stopword_count += 1 else if (word.len == 1) tokens.short_count += 1 else e.append(usize, &words, intern(word));
    }
    tokens.words = words.items;
    const terms = e.alloc(usize, if (words.items.len == 0) 0 else 2 * words.items.len - 1);
    @memcpy(terms[0..words.items.len], words.items);
    if (words.items.len > 0) {
        for (0..words.items.len - 1) |i| terms[words.items.len + i] = intern(e.fmt("{s}_{s}", .{ name(words.items[i]), name(words.items[i + 1]) }));
    }
    tokens.bigram_terms = terms;
    return tokens;
}
