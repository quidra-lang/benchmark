const std = @import("std");
const loader = @import("script_loader.zig");
const matcher = @import("matcher.zig");

pub fn reflect(words: loader.Strings, posts: []const loader.Substitution) loader.Strings {
    var result: std.ArrayList([]const u8) = .empty;
    for (words) |word| {
        if (loader.replacement(posts, word)) |replacement| { for (replacement) |piece| loader.append([]const u8, &result, piece); } else loader.append([]const u8, &result, word);
    }
    return result.items;
}
fn binding(bindings: matcher.Match, number: usize) loader.Strings { return if (number >= 1 and number <= bindings.count) bindings.bindings[number - 1] else &.{}; }
pub fn reply(template: []const u8, bindings: matcher.Match, posts: []const loader.Substitution) []const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < template.len) {
        if (i + 2 < template.len and loader.isReference(template[i..i + 3])) {
            bytes.appendSlice(loader.allocator, loader.join(reflect(binding(bindings, template[i + 1] - '0'), posts), " ")) catch @panic("allocation failed");
            i += 3;
        } else { loader.append(u8, &bytes, template[i]); i += 1; }
    }
    var pieces: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, bytes.items, ' ');
    while (it.next()) |word| loader.append([]const u8, &pieces, word);
    const text = loader.clone(u8, loader.join(pieces.items, " "));
    if (text.len > 0 and text[0] >= 'a' and text[0] <= 'z') text[0] -= 'a' - 'A';
    return text;
}
pub fn restate(arguments: loader.Strings, bindings: matcher.Match) loader.Strings {
    var result: std.ArrayList([]const u8) = .empty;
    for (arguments) |argument| {
        if (loader.isReference(argument)) { for (binding(bindings, argument[1] - '0')) |word| loader.append([]const u8, &result, word); } else loader.append([]const u8, &result, argument);
    }
    return result.items;
}
pub fn wrap(text: []const u8) loader.Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    var current = loader.fmt("ELIZA: {s}", .{it.next().?});
    while (it.next()) |word| {
        if (current.len + 1 + word.len <= 72) current = loader.fmt("{s} {s}", .{ current, word }) else { loader.append([]const u8, &result, current); current = loader.fmt("       {s}", .{word}); }
    }
    loader.append([]const u8, &result, current);
    return result.items;
}
