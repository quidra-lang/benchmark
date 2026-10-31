const std = @import("std");

pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub const Directive = enum { INITIAL, FINAL, DEFAULT, QUESTION, REPEAT, QUIT, STOP, MEMSIZE, PERSIST, PRE, POST, SYNON, KEY, DECOMP, MEMORY, REASM, GOTO, NEWKEY, RESTATE };
pub const Code = enum { SYNTAX, ORPHAN, DUPLICATE, KEY_NO_DECOMP, KEY_UNREACHABLE, SYNON_UNUSED, PRE_CHAIN, SYNON_UNKNOWN, RULE_NO_REASM, RULE_SHADOWED, REF_UNBOUND, TARGET_UNDEFINED, TARGET_CYCLE };

pub fn eq(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
pub fn less(a: []const u8, b: []const u8) bool { return std.mem.order(u8, a, b) == .lt; }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), item: T) void { list.append(allocator, item) catch @panic("allocation failed"); }
pub fn clone(comptime T: type, items: []const T) []T { return allocator.dupe(T, items) catch @panic("allocation failed"); }
pub fn listCopy(comptime T: type, list: std.ArrayList(T)) std.ArrayList(T) { return .{ .items = clone(T, list.items), .capacity = list.items.len }; }
pub fn join(parts: Strings, separator: []const u8) []const u8 { return std.mem.join(allocator, separator, parts) catch @panic("allocation failed"); }
pub fn has(parts: Strings, word: []const u8) bool { for (parts) |part| { if (eq(part, word)) return true; } return false; }
pub fn enumValue(comptime T: type, text: []const u8) ?T {
    inline for (@typeInfo(T).@"enum".field_names) |name| { if (eq(name, text)) return @field(T, name); }
    return null;
}
pub fn split(text: []const u8, delimiter: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(text: []const u8) Strings { const all = split(text, '\n'); return all[0..all.len - 1]; }
pub fn isWord(text: []const u8) bool {
    if (text.len == 0 or text[0] == '\'' or text[text.len - 1] == '\'') return false;
    for (text) |c| { if (!(c >= 'a' and c <= 'z') and !(c >= '0' and c <= '9') and c != '\'') return false; }
    return true;
}
pub fn isReference(text: []const u8) bool { return text.len == 3 and text[0] == '(' and text[1] >= '0' and text[1] <= '9' and text[2] == ')'; }
fn number(text: []const u8) ?usize {
    if (text.len == 0 or text.len > 2) return null;
    for (text) |c| { if (c < '0' or c > '9') return null; }
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
fn isElement(text: []const u8) bool { return eq(text, "*") or eq(text, "#") or (if (std.mem.startsWith(u8, text, "@")) isWord(text[1..]) else isWord(text)); }
fn allWords(args: Strings) bool { for (args) |arg| { if (!isWord(arg)) return false; } return true; }
fn wellFormed(name: Directive, args: Strings) bool {
    return switch (name) {
        .INITIAL, .FINAL, .DEFAULT, .QUESTION, .REPEAT, .REASM => args.len >= 1,
        .QUIT, .STOP => args.len >= 1 and allWords(args),
        .MEMSIZE => args.len == 1 and (if (number(args[0])) |n| n >= 1 and n <= 20 else false),
        .PERSIST => args.len == 1 and (eq(args[0], "cycles") or eq(args[0], "memory")),
        .PRE, .SYNON => args.len >= 2 and allWords(args),
        .POST => args.len >= 2 and isWord(args[0]),
        .KEY => args.len == 2 and isWord(args[0]) and number(args[1]) != null,
        .DECOMP, .MEMORY => blk: { if (args.len == 0) break :blk false; for (args) |arg| { if (!isElement(arg)) break :blk false; } break :blk true; },
        .GOTO => args.len == 1 and isWord(args[0]),
        .NEWKEY => args.len == 0,
        .RESTATE => blk: { if (args.len < 2 or !isWord(args[0])) break :blk false; for (args[1..]) |arg| { if (!isWord(arg) and !isReference(arg)) break :blk false; } break :blk true; },
    };
}

pub const Diagnostic = struct { line: usize, code: Code, message: []const u8, order: usize };
pub const Substitution = struct { source: []const u8, replacement: Strings, line: usize };
pub const Group = struct { name: []const u8, members: Strings, line: usize };
pub const Item = struct { kind: Directive, text: []const u8, arguments: Strings, line: usize };
pub const Rule = struct { kind: Directive, pattern: Strings, line: usize, items: std.ArrayList(usize) = .empty };
pub const Keyword = struct { word: []const u8, rank: usize, line: usize, memories: std.ArrayList(usize) = .empty, decomps: std.ArrayList(usize) = .empty };
pub const Script = struct {
    source: Strings,
    texts: [5]std.ArrayList([]const u8) = @splat(.empty),
    quit: std.ArrayList([]const u8) = .empty,
    stop: std.ArrayList([]const u8) = .empty,
    memsize: usize = 3,
    persist_cycles: bool = false,
    persist_memory: bool = false,
    pres: std.ArrayList(Substitution) = .empty,
    posts: std.ArrayList(Substitution) = .empty,
    groups: std.ArrayList(Group) = .empty,
    keywords: std.ArrayList(Keyword) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    items: std.ArrayList(Item) = .empty,
    diagnostics: std.ArrayList(Diagnostic) = .empty,

    pub fn keyword(s: *const Script, word: []const u8) ?usize { for (s.keywords.items, 0..) |key, i| { if (eq(key.word, word)) return i; } return null; }
    pub fn group(s: *const Script, name: []const u8) ?Group { for (s.groups.items) |entry| { if (eq(entry.name, name)) return entry; } return null; }
    pub fn problem(s: *Script, line: usize, code: Code, message: []const u8) void { append(Diagnostic, &s.diagnostics, .{ .line = line, .code = code, .message = message, .order = s.diagnostics.items.len }); }
};

pub fn replacement(substitutions: []const Substitution, word: []const u8) ?Strings {
    for (substitutions) |entry| { if (eq(entry.source, word)) return entry.replacement; }
    return null;
}

pub fn load(text: []const u8) Script {
    const Definition = struct { key: []const u8, line: usize };
    var definitions: std.ArrayList(Definition) = .empty;
    var script: Script = .{ .source = lines(text) };
    var current_keyword: ?usize = null;
    var current_rule: ?usize = null;
    var ignoring = false;
    for (script.source, 1..) |line, line_number| {
        if (line.len == 0 or line[0] == '#') continue;
        const tokens = split(line, ' ');
        const directive = enumValue(Directive, tokens[0]);
        const args = tokens[1..];
        if (directive) |name| {
            switch (name) {
                .DECOMP, .MEMORY => { if (ignoring) continue; current_rule = null; },
                .REASM, .GOTO, .NEWKEY, .RESTATE => { if (ignoring) continue; },
                else => { current_keyword = null; current_rule = null; ignoring = false; },
            }
        }
        const name = directive orelse { script.problem(line_number, .SYNTAX, fmt("unknown directive {s}", .{tokens[0]})); continue; };
        if (!wellFormed(name, args)) { script.problem(line_number, .SYNTAX, fmt("bad arguments for {s}", .{@tagName(name)})); continue; }
        if ((name == .DECOMP or name == .MEMORY) and current_keyword == null) { script.problem(line_number, .ORPHAN, fmt("{s} without KEY", .{@tagName(name)})); continue; }
        if (name == .REASM and current_rule == null) { script.problem(line_number, .ORPHAN, "REASM without DECOMP or MEMORY"); continue; }
        if ((name == .GOTO or name == .NEWKEY or name == .RESTATE) and (current_rule == null or script.rules.items[current_rule.?].kind == .MEMORY)) { script.problem(line_number, .ORPHAN, fmt("{s} without DECOMP", .{@tagName(name)})); continue; }
        const definition: ?[]const u8 = switch (name) { .MEMSIZE => "MEMSIZE", .KEY, .SYNON, .PRE, .POST, .PERSIST => fmt("{s} {s}", .{ @tagName(name), args[0] }), else => null };
        if (definition) |key| {
            var first: ?usize = null;
            for (definitions.items) |entry| { if (eq(entry.key, key)) first = entry.line; }
            if (first) |original| {
                script.problem(line_number, .DUPLICATE, fmt("{s} first defined at line {d}", .{ key, original }));
                if (name == .KEY) ignoring = true;
                continue;
            }
            append(Definition, &definitions, .{ .key = key, .line = line_number });
        }
        const content = if (args.len > 0) line[tokens[0].len + 1..] else "";
        switch (name) {
            .INITIAL, .FINAL, .DEFAULT, .QUESTION, .REPEAT => append([]const u8, &script.texts[@intFromEnum(name)], content),
            .QUIT, .STOP => for (args) |word| { append([]const u8, if (name == .QUIT) &script.quit else &script.stop, word); },
            .MEMSIZE => script.memsize = number(args[0]).?,
            .PERSIST => { if (eq(args[0], "cycles")) script.persist_cycles = true else script.persist_memory = true; },
            .PRE, .POST => append(Substitution, if (name == .PRE) &script.pres else &script.posts, .{ .source = args[0], .replacement = args[1..], .line = line_number }),
            .SYNON => append(Group, &script.groups, .{ .name = args[0], .members = args, .line = line_number }),
            .KEY => { current_keyword = script.keywords.items.len; append(Keyword, &script.keywords, .{ .word = args[0], .rank = number(args[1]).?, .line = line_number }); },
            .DECOMP, .MEMORY => {
                current_rule = script.rules.items.len;
                append(Rule, &script.rules, .{ .kind = name, .pattern = args, .line = line_number });
                const key = &script.keywords.items[current_keyword.?];
                append(usize, if (name == .MEMORY) &key.memories else &key.decomps, current_rule.?);
            },
            .REASM, .GOTO, .NEWKEY, .RESTATE => {
                append(usize, &script.rules.items[current_rule.?].items, script.items.items.len);
                append(Item, &script.items, .{ .kind = name, .text = content, .arguments = args, .line = line_number });
            },
        }
    }
    return script;
}
