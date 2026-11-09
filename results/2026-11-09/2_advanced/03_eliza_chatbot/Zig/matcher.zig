const loader = @import("script_loader.zig");
pub const Match = struct { bindings: [8]loader.Strings = undefined, count: usize = 0 };

pub fn wildcard(element: []const u8) bool { return loader.eq(element, "*") or loader.eq(element, "#") or element[0] == '@'; }
fn wordFits(element: []const u8, word: []const u8, script: *const loader.Script) bool {
    if (loader.eq(element, "#")) return true;
    if (element[0] == '@') { const group = script.group(element[1..]) orelse return false; return loader.has(group.members, word); }
    return loader.eq(element, word);
}
fn matchFrom(pattern: loader.Strings, words: loader.Strings, script: *const loader.Script, position: usize, start: usize, ends: *[8]usize) bool {
    if (position == pattern.len) return start == words.len;
    if (loader.eq(pattern[position], "*")) {
        for (start..words.len + 1) |end| {
            ends[position] = end;
            if (matchFrom(pattern, words, script, position + 1, end, ends)) return true;
        }
    } else if (start < words.len and wordFits(pattern[position], words[start], script)) {
        ends[position] = start + 1;
        return matchFrom(pattern, words, script, position + 1, start + 1, ends);
    }
    return false;
}
pub fn match(pattern: loader.Strings, words: loader.Strings, script: *const loader.Script) ?Match {
    var ends: [8]usize = undefined;
    if (!matchFrom(pattern, words, script, 0, 0, &ends)) return null;
    var result: Match = .{};
    var start: usize = 0;
    for (pattern, 0..) |element, i| {
        if (wildcard(element)) { result.bindings[result.count] = words[start..ends[i]]; result.count += 1; }
        start = ends[i];
    }
    return result;
}
fn elementCovers(element: []const u8, other: []const u8, script: *const loader.Script) bool {
    if (loader.eq(element, "#")) return !loader.eq(other, "*");
    if (element[0] == '@') {
        const group = script.group(element[1..]) orelse return false;
        if (other[0] == '@') {
            const subgroup = script.group(other[1..]) orelse return false;
            for (subgroup.members) |word| { if (!loader.has(group.members, word)) return false; }
            return true;
        }
        return loader.has(group.members, other);
    }
    return loader.eq(element, other);
}
fn coversFrom(earlier: loader.Strings, later: loader.Strings, script: *const loader.Script, position: usize, start: usize) bool {
    if (position == earlier.len) return start == later.len;
    if (loader.eq(earlier[position], "*")) {
        for (start..later.len + 1) |end| { if (coversFrom(earlier, later, script, position + 1, end)) return true; }
        return false;
    }
    return start < later.len and elementCovers(earlier[position], later[start], script) and coversFrom(earlier, later, script, position + 1, start + 1);
}
pub fn covers(earlier: loader.Strings, later: loader.Strings, script: *const loader.Script) bool { return coversFrom(earlier, later, script, 0, 0); }
