const std = @import("std");
const loader = @import("script_loader.zig");
const matcher = @import("matcher.zig");

pub fn isError(code: loader.Code) bool { return switch (code) { .SYNTAX, .ORPHAN, .DUPLICATE, .SYNON_UNKNOWN, .REF_UNBOUND, .TARGET_UNDEFINED, .TARGET_CYCLE => true, else => false }; }
fn unknown(pattern: loader.Strings, script: *const loader.Script) bool { for (pattern) |element| { if (element[0] == '@' and script.group(element[1..]) == null) return true; } return false; }
fn moves(item: loader.Item) bool { return item.kind == .GOTO or item.kind == .RESTATE; }
fn diagnosticLess(_: void, a: loader.Diagnostic, b: loader.Diagnostic) bool {
    if (a.line != b.line) return a.line < b.line;
    if (a.code != b.code) return @intFromEnum(a.code) < @intFromEnum(b.code);
    return a.order < b.order;
}
pub fn lint(script: *loader.Script) void {
    for (script.keywords.items) |key| {
        if (key.decomps.items.len == 0) script.problem(key.line, .KEY_NO_DECOMP, loader.fmt("keyword {s} has no DECOMP", .{key.word}));
        var replaced = false;
        for (script.pres.items) |pre| { if (loader.has(pre.replacement, key.word)) replaced = true; }
        var target = false;
        for (script.items.items) |item| { if (moves(item) and loader.eq(item.arguments[0], key.word)) target = true; }
        if (loader.replacement(script.pres.items, key.word) != null and !replaced and !target) script.problem(key.line, .KEY_UNREACHABLE, loader.fmt("keyword {s} is replaced by PRE", .{key.word}));
    }
    for (script.groups.items) |group| {
        var used = false;
        for (script.rules.items) |rule| { for (rule.pattern) |element| { if (element[0] == '@' and loader.eq(element[1..], group.name)) used = true; } }
        if (!used) script.problem(group.line, .SYNON_UNUSED, loader.fmt("group {s} is never used", .{group.name}));
    }
    for (script.pres.items) |pre| { for (pre.replacement) |word| { if (loader.replacement(script.pres.items, word) != null) script.problem(pre.line, .PRE_CHAIN, loader.fmt("replacement {s} is itself replaced by PRE", .{word})); } }
    var reach: [100][100]bool = @splat(@splat(false));
    const n = script.keywords.items.len;
    for (script.keywords.items, 0..) |key, source| {
        reach[source][source] = true;
        for (key.decomps.items) |rule_id| { for (script.rules.items[rule_id].items.items) |item_id| {
            const item = script.items.items[item_id];
            if (moves(item)) { if (script.keyword(item.arguments[0])) |target| reach[source][target] = true; }
        } }
    }
    for (0..n) |k| { for (0..n) |i| { for (0..n) |j| reach[i][j] = reach[i][j] or (reach[i][k] and reach[k][j]); } }
    for (script.keywords.items, 0..) |key, source| {
        for ([_][]const usize{ key.memories.items, key.decomps.items }) |rules| {
            for (rules, 0..) |rule_id, position| {
                const rule = script.rules.items[rule_id];
                for (rule.pattern) |element| { if (element[0] == '@' and script.group(element[1..]) == null) script.problem(rule.line, .SYNON_UNKNOWN, loader.fmt("unknown group {s}", .{element[1..]})); }
                if (rule.items.items.len == 0) script.problem(rule.line, .RULE_NO_REASM, "rule has no reassembly");
                if (!unknown(rule.pattern, script)) {
                    for (rules[0..position]) |earlier_id| {
                        const earlier = script.rules.items[earlier_id];
                        if (!unknown(earlier.pattern, script) and matcher.covers(earlier.pattern, rule.pattern, script)) { script.problem(rule.line, .RULE_SHADOWED, loader.fmt("pattern is shadowed by line {d}", .{earlier.line})); break; }
                    }
                }
                var wildcards: usize = 0;
                for (rule.pattern) |element| { if (matcher.wildcard(element)) wildcards += 1; }
                for (rule.items.items) |item_id| {
                    const item = script.items.items[item_id];
                    if (item.kind == .REASM) {
                        var i: usize = 0;
                        while (i + 2 < item.text.len) : (i += 1) { if (loader.isReference(item.text[i..i + 3])) { const number = item.text[i + 1] - '0'; if (number == 0 or number > wildcards) script.problem(item.line, .REF_UNBOUND, loader.fmt("reference ({d}) is not bound", .{number})); } }
                    } else if (item.kind == .RESTATE) {
                        for (item.arguments[1..]) |arg| { if (loader.isReference(arg)) { const number = arg[1] - '0'; if (number == 0 or number > wildcards) script.problem(item.line, .REF_UNBOUND, loader.fmt("reference ({d}) is not bound", .{number})); } }
                    }
                    if (!moves(item)) continue;
                    const target_word = item.arguments[0];
                    if (script.keyword(target_word)) |target| {
                        if (reach[target][source]) script.problem(item.line, .TARGET_CYCLE, loader.fmt("edge {s} -> {s} is on a cycle", .{ key.word, target_word }));
                    } else script.problem(item.line, .TARGET_UNDEFINED, loader.fmt("target {s} is not a keyword", .{target_word}));
                }
            }
        }
    }
    std.mem.sort(loader.Diagnostic, script.diagnostics.items, {}, diagnosticLess);
}
