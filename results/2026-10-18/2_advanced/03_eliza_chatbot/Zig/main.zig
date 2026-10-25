const std = @import("std");
const g = @import("script_loader.zig");
const matcher = @import("matcher.zig");
const responder = @import("responder.zig");
const memory = @import("memory.zig");
const linter = @import("linter.zig");
const Strings = g.Strings;
const Clauses = []const Strings;
const fmt = g.fmt;
const add = g.append;
const eq = g.eq;
const Source = enum { keyword, memory, question, default, repeat };
const Debug = enum { prepare, @"test", reflect, keys, groups, find, script, why, trace, history, memory, forget, cycles, coverage, reset, unused, stats, say, explain, undo };

fn zeros(size: usize) []usize { const values = g.allocator.alloc(usize, size) catch @panic("allocation failed"); @memset(values, 0); return values; }
fn normalize(text: []const u8) Clauses {
    var clauses: std.ArrayList(Strings) = .empty;
    const lower = g.clone(u8, text);
    for (lower) |*c| { if (c.* >= 'A' and c.* <= 'Z') c.* += 'a' - 'A'; }
    var parts = std.mem.splitAny(u8, lower, ",.?!;");
    while (parts.next()) |part| {
        const cleaned = g.clone(u8, part);
        for (cleaned) |*c| { if (!(c.* >= 'a' and c.* <= 'z') and !(c.* >= '0' and c.* <= '9') and c.* != '\'') c.* = ' '; }
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeScalar(u8, cleaned, ' ');
        while (it.next()) |word| {
            var start: usize = 0;
            var end = word.len;
            while (start < end and word[start] == '\'') : (start += 1) {}
            while (end > start and word[end - 1] == '\'') : (end -= 1) {}
            if (start < end) add([]const u8, &words, word[start..end]);
        }
        if (words.items.len > 0) add(Strings, &clauses, words.items);
    }
    return clauses.items;
}
fn allWords(clauses: Clauses) Strings {
    var words: std.ArrayList([]const u8) = .empty;
    for (clauses) |clause| { for (clause) |word| add([]const u8, &words, word); }
    return words.items;
}
fn sameClauses(a: Clauses, b: Clauses) bool {
    if (a.len != b.len) return false;
    for (a, b) |first, second| {
        if (first.len != second.len) return false;
        for (first, second) |x, y| { if (!eq(x, y)) return false; }
    }
    return true;
}
fn sourceLine(turns: usize, counts: [5]usize) []const u8 { return fmt("turns={d} keyword={d} memory={d} question={d} default={d} repeat={d}", .{ turns, counts[0], counts[1], counts[2], counts[3], counts[4] }); }
fn numberStrings(numbers: []const usize) Strings { var result: std.ArrayList([]const u8) = .empty; for (numbers) |number| add([]const u8, &result, fmt("{d}", .{number})); return result.items; }
fn grouped(values: Strings, size: usize) Strings { var result: std.ArrayList([]const u8) = .empty; var i: usize = 0; while (i < values.len) : (i += size) add([]const u8, &result, g.join(values[i..@min(i + size, values.len)], " ")); return result.items; }
fn usizeLess(_: void, a: usize, b: usize) bool { return a < b; }
fn one(text: []const u8) Strings { return g.clone([]const u8, &.{text}); }
fn stringLess(_: void, a: []const u8, b: []const u8) bool { return g.less(a, b); }
const Count = struct { word: []const u8, count: usize };
fn countLess(_: void, a: Count, b: Count) bool { return a.count > b.count or (a.count == b.count and g.less(a.word, b.word)); }
fn increment(counts: *std.ArrayList(Count), word: []const u8) void { for (counts.items) |*entry| { if (eq(entry.word, word)) { entry.count += 1; return; } } add(Count, counts, .{ .word = word, .count = 1 }); }
fn rankedCounts(values: []const Count) []const u8 {
    if (values.len == 0) return "none";
    const ranked = g.clone(Count, values);
    std.mem.sort(Count, ranked, {}, countLess);
    var parts: std.ArrayList([]const u8) = .empty;
    for (ranked[0..@min(5, ranked.len)]) |entry| add([]const u8, &parts, fmt("{s} {d}", .{ entry.word, entry.count }));
    return g.join(parts.items, ", ");
}

const Session = struct {
    name: []const u8,
    turns: usize = 0,
    sources: [5]usize = @splat(0),
    previous: ?Clauses = null,
    history: std.ArrayList([]const u8) = .empty,
    last_trace: ?Strings = null,
    trace_on: bool = false,
    topics: []usize,
    words: std.ArrayList(Count) = .empty,
    stored: usize = 0,
    recalled: usize = 0,
    unrecognized: std.ArrayList(usize) = .empty,
    undo: ?*State = null,
    fn copy(s: Session) Session {
        var result = s;
        result.history = g.listCopy([]const u8, s.history);
        result.topics = g.clone(usize, s.topics);
        result.words = g.listCopy(Count, s.words);
        result.unrecognized = g.listCopy(usize, s.unrecognized);
        return result;
    }
};
const State = struct {
    positions: []usize,
    hits: []usize,
    item_uses: []usize,
    keyword_uses: []usize,
    keyword_replies: []usize,
    list_positions: [3]usize = @splat(0),
    queue: memory.Queue,
    session: Session,
    fn init(script: *const g.Script) State { return .{ .positions = zeros(script.rules.items.len), .hits = zeros(script.rules.items.len), .item_uses = zeros(script.items.items.len), .keyword_uses = zeros(script.keywords.items.len), .keyword_replies = zeros(script.keywords.items.len), .queue = .{ .capacity = script.memsize }, .session = .{ .name = "", .topics = zeros(script.keywords.items.len) } }; }
    fn copy(s: State) State {
        var result = s;
        result.positions = g.clone(usize, s.positions);
        result.hits = g.clone(usize, s.hits);
        result.item_uses = g.clone(usize, s.item_uses);
        result.keyword_uses = g.clone(usize, s.keyword_uses);
        result.keyword_replies = g.clone(usize, s.keyword_replies);
        result.queue = s.queue.copy();
        result.session = s.session.copy();
        return result;
    }
    fn snapshot(s: State) *State { const result = g.allocator.create(State) catch @panic("allocation failed"); result.* = s.copy(); result.session.undo = null; return result; }
};

const KeyPosition = struct { id: usize, position: usize };
fn keyPositionLess(script: *const g.Script, a: KeyPosition, b: KeyPosition) bool { const x = script.keywords.items[a.id].rank; const y = script.keywords.items[b.id].rank; return x > y or (x == y and a.position < b.position); }
fn keyRankLess(script: *const g.Script, a: usize, b: usize) bool { const x = script.keywords.items[a]; const y = script.keywords.items[b]; return x.rank > y.rank or (x.rank == y.rank and g.less(x.word, y.word)); }
const FoundRule = struct { number: usize, id: usize, bindings: matcher.Match };
const Decision = struct { reply: []const u8, trace: Strings };
const RuleEntry = struct { label: []const u8, number: usize, id: usize };
fn ruleEntries(key: g.Keyword) []const RuleEntry {
    var result: std.ArrayList(RuleEntry) = .empty;
    for (key.memories.items, 1..) |id, number| add(RuleEntry, &result, .{ .label = "memory", .number = number, .id = id });
    for (key.decomps.items, 1..) |id, number| add(RuleEntry, &result, .{ .label = "decomp", .number = number, .id = id });
    return result.items;
}

const Chatbot = struct {
    script: *const g.Script,
    state: State,
    transcript: std.ArrayList([]const u8) = .empty,
    total_turns: usize = 0,
    total_sources: [5]usize = @splat(0),
    fn prefix(bot: *const Chatbot) []const u8 { return fmt("{s} {d}", .{ bot.state.session.name, bot.state.session.turns }); }
    fn indent(bot: *Chatbot, output: Strings) void { for (output) |line| add([]const u8, &bot.transcript, fmt("  {s}", .{line})); }
    fn eliza(bot: *Chatbot, text: []const u8) void { for (responder.wrap(text)) |line| add([]const u8, &bot.transcript, line); }
    fn cycleReset(bot: *Chatbot) void { @memset(bot.state.positions, 0); bot.state.list_positions = @splat(0); }
    fn takeText(bot: *Chatbot, name: g.Directive) []const u8 {
        const texts = bot.script.texts[@intFromEnum(name)].items;
        const index = @intFromEnum(name) - 2;
        const position = bot.state.list_positions[index];
        bot.state.list_positions[index] = (position + 1) % texts.len;
        return texts[position];
    }
    fn takeItem(bot: *Chatbot, rule_id: usize) struct { number: usize, item: g.Item } {
        const rule = bot.script.rules.items[rule_id];
        const position = bot.state.positions[rule_id];
        const item_id = rule.items.items[position];
        bot.state.item_uses[item_id] += 1;
        bot.state.positions[rule_id] = (position + 1) % rule.items.items.len;
        return .{ .number = position + 1, .item = bot.script.items.items[item_id] };
    }
    fn preSubstitute(bot: *const Chatbot, clauses: Clauses) Clauses {
        var result: std.ArrayList(Strings) = .empty;
        for (clauses) |clause| {
            var words: std.ArrayList([]const u8) = .empty;
            for (clause) |word| {
                if (g.replacement(bot.script.pres.items, word)) |replacement| { for (replacement) |part| add([]const u8, &words, part); } else add([]const u8, &words, word);
            }
            add(Strings, &result, words.items);
        }
        return result.items;
    }
    fn prepared(bot: *const Chatbot, text: []const u8) Clauses { return bot.preSubstitute(normalize(text)); }
    fn isQuit(bot: *const Chatbot, text: []const u8) bool { const words = allWords(normalize(text)); return words.len == 1 and g.has(bot.script.quit.items, words[0]); }
    fn selectClause(bot: *const Chatbot, clauses: Clauses) ?usize { for (clauses, 0..) |clause, i| { for (clause) |word| { if (bot.script.keyword(word) != null) return i; } } return null; }
    fn keywordList(bot: *const Chatbot, words: Strings) []const KeyPosition {
        var result: std.ArrayList(KeyPosition) = .empty;
        for (words, 0..) |word, position| {
            if (bot.script.keyword(word)) |id| {
                var found = false;
                for (result.items) |entry| { if (entry.id == id) found = true; }
                if (!found) add(KeyPosition, &result, .{ .id = id, .position = position });
            }
        }
        std.mem.sort(KeyPosition, result.items, bot.script, keyPositionLess);
        return result.items;
    }
    fn findRule(bot: *const Chatbot, rules: []const usize, words: Strings) ?FoundRule {
        for (rules, 1..) |id, number| { if (matcher.match(bot.script.rules.items[id].pattern, words, bot.script)) |bindings| return .{ .number = number, .id = id, .bindings = bindings }; }
        return null;
    }
    fn applyMemory(bot: *Chatbot, id: usize, words: Strings, trace: *std.ArrayList([]const u8)) void {
        const key = bot.script.keywords.items[id];
        const found = bot.findRule(key.memories.items, words) orelse return;
        add([]const u8, trace, fmt("MEMORY {s} {d}", .{ key.word, found.number }));
        bot.state.hits[found.id] += 1;
        if (bot.script.rules.items[found.id].items.items.len == 0) return;
        const taken = bot.takeItem(found.id);
        const text = responder.reply(taken.item.text, found.bindings, bot.script.posts.items);
        if (bot.state.queue.store(bot.prefix(), key.word, text)) bot.state.session.stored += 1;
    }
    fn followKeyword(bot: *Chatbot, initial_id: usize, initial_words: Strings, entered: []bool, trace: *std.ArrayList([]const u8)) ?[]const u8 {
        var id = initial_id;
        var words = initial_words;
        while (true) {
            const key = bot.script.keywords.items[id];
            entered[id] = true;
            bot.state.keyword_uses[id] += 1;
            const found = bot.findRule(key.decomps.items, words) orelse { add([]const u8, trace, fmt("NOMATCH {s}", .{key.word})); return null; };
            bot.state.hits[found.id] += 1;
            if (bot.script.rules.items[found.id].items.items.len == 0) { add([]const u8, trace, fmt("DECOMP {s} {d} 0", .{ key.word, found.number })); return null; }
            const taken = bot.takeItem(found.id);
            const item = taken.item;
            add([]const u8, trace, fmt("DECOMP {s} {d} {d}", .{ key.word, found.number, taken.number }));
            if (item.kind == .REASM) {
                bot.state.keyword_replies[id] += 1;
                bot.state.session.topics[id] += 1;
                return responder.reply(item.text, found.bindings, bot.script.posts.items);
            }
            if (item.kind == .NEWKEY) return null;
            const target_word = item.arguments[0];
            const target = bot.script.keyword(target_word);
            if (target == null or entered[target.?]) { add([]const u8, trace, fmt("BLOCKED {s}", .{target_word})); return null; }
            if (item.kind == .RESTATE) {
                words = responder.restate(item.arguments[1..], found.bindings);
                add([]const u8, trace, if (words.len == 0) fmt("RESTATE {s}", .{target_word}) else fmt("RESTATE {s} {s}", .{ target_word, g.join(words, " ") }));
            } else add([]const u8, trace, fmt("GOTO {s}", .{target_word}));
            id = target.?;
        }
    }
    fn keywordReply(bot: *Chatbot, clauses: Clauses, trace: *std.ArrayList([]const u8)) ?[]const u8 {
        const selected = bot.selectClause(clauses) orelse { add([]const u8, trace, "CLAUSE none"); return null; };
        const words = clauses[selected];
        add([]const u8, trace, fmt("CLAUSE {d} {s}", .{ selected + 1, g.join(words, " ") }));
        const keys = bot.keywordList(words);
        var names: std.ArrayList([]const u8) = .empty;
        for (keys) |entry| add([]const u8, &names, bot.script.keywords.items[entry.id].word);
        add([]const u8, trace, fmt("KEYS {s}", .{g.join(names.items, " ")}));
        bot.applyMemory(keys[0].id, words, trace);
        const entered = g.allocator.alloc(bool, bot.script.keywords.items.len) catch @panic("allocation failed");
        @memset(entered, false);
        for (keys) |entry| {
            if (entered[entry.id]) continue;
            add([]const u8, trace, fmt("ENTER {s}", .{bot.script.keywords.items[entry.id].word}));
            if (bot.followKeyword(entry.id, words, entered, trace)) |reply| return reply;
        }
        return null;
    }
    fn decide(bot: *Chatbot, text: []const u8) Decision {
        const clauses = normalize(text);
        var trace: std.ArrayList([]const u8) = .empty;
        var source: Source = .keyword;
        var reply: []const u8 = undefined;
        const repeated = if (bot.state.session.previous) |previous| sameClauses(clauses, previous) else false;
        if (bot.script.texts[@intFromEnum(g.Directive.REPEAT)].items.len > 0 and clauses.len > 0 and repeated) {
            add([]const u8, &trace, "REPEAT");
            reply = bot.takeText(.REPEAT);
            source = .repeat;
        } else if (bot.keywordReply(bot.preSubstitute(clauses), &trace)) |answer| {
            reply = answer;
        } else if (bot.state.queue.texts.items.len > 0) {
            reply = bot.state.queue.recall(bot.prefix());
            bot.state.session.recalled += 1;
            source = .memory;
        } else if (text.len > 0 and text[text.len - 1] == '?' and bot.script.texts[@intFromEnum(g.Directive.QUESTION)].items.len > 0) {
            reply = bot.takeText(.QUESTION);
            source = .question;
        } else {
            reply = bot.takeText(.DEFAULT);
            source = .default;
        }
        add([]const u8, &trace, fmt("REPLY {s}", .{@tagName(source)}));
        bot.state.session.previous = clauses;
        bot.state.session.sources[@intFromEnum(source)] += 1;
        if (source == .question or source == .default) add(usize, &bot.state.session.unrecognized, bot.state.session.turns);
        return .{ .reply = reply, .trace = trace.items };
    }
    fn respond(bot: *Chatbot, line: []const u8) void {
        bot.state.session.undo = bot.state.snapshot();
        bot.state.session.turns += 1;
        for (allWords(normalize(line))) |word| { if (!g.has(bot.script.stop.items, word)) increment(&bot.state.session.words, word); }
        add([]const u8, &bot.state.session.history, fmt("{d}: {s}", .{ bot.state.session.turns, line }));
        const decision = bot.decide(line);
        bot.eliza(decision.reply);
        bot.state.session.last_trace = decision.trace;
        if (bot.state.session.trace_on) bot.indent(decision.trace);
    }
    fn command(bot: *Chatbot, line: []const u8) Strings {
        const space = std.mem.findScalar(u8, line, ' ') orelse line.len;
        const name = line[0..space];
        const text = if (space < line.len) line[space + 1..] else "";
        const args: Strings = if (text.len == 0) &.{} else g.split(text, ' ');
        const cmd = g.enumValue(Debug, name[1..]) orelse return one(fmt("unknown command {s}", .{name}));
        const valid = switch (cmd) {
            .keys, .why, .history, .memory, .forget, .reset, .unused, .stats, .undo => args.len == 0,
            .prepare, .reflect, .say, .explain => text.len > 0,
            .groups, .find, .script, .cycles, .coverage => args.len == 1,
            .trace => args.len == 1 and (eq(args[0], "on") or eq(args[0], "off")),
            .@"test" => args.len >= 2,
        };
        if (!valid) return &.{"bad arguments"};
        const requires_key = cmd == .script or cmd == .cycles or cmd == .coverage or cmd == .@"test";
        const key_id: ?usize = if (requires_key) bot.script.keyword(args[0]) else null;
        if (requires_key and key_id == null) return one(fmt("unknown keyword {s}", .{args[0]}));
        var output: std.ArrayList([]const u8) = .empty;
        switch (cmd) {
            .prepare => {
                const clauses = bot.prepared(text);
                for (clauses, 1..) |clause, number| add([]const u8, &output, fmt("clause {d}: {s}", .{ number, g.join(clause, " ") }));
                if (clauses.len == 0) add([]const u8, &output, "no words");
                if (bot.selectClause(clauses)) |selected| {
                    add([]const u8, &output, fmt("selected {d}", .{selected + 1}));
                    var labels: std.ArrayList([]const u8) = .empty;
                    for (bot.keywordList(clauses[selected])) |entry| { const key = bot.script.keywords.items[entry.id]; add([]const u8, &labels, fmt("{s}/{d}", .{ key.word, key.rank })); }
                    add([]const u8, &output, fmt("keys {s}", .{g.join(labels.items, " ")}));
                } else add([]const u8, &output, "selected none");
            },
            .@"test" => {
                const words = allWords(bot.prepared(text[args[0].len + 1..]));
                for (ruleEntries(bot.script.keywords.items[key_id.?])) |entry| {
                    const found = matcher.match(bot.script.rules.items[entry.id].pattern, words, bot.script);
                    var result: []const u8 = "no match";
                    if (found) |bindings| {
                        var values: std.ArrayList([]const u8) = .empty;
                        for (bindings.bindings[0..bindings.count]) |bound| add([]const u8, &values, fmt("[{s}]", .{g.join(bound, " ")}));
                        result = if (bindings.count == 0) "match" else g.join(values.items, " ");
                    }
                    add([]const u8, &output, fmt("{s} {d}: {s}", .{ entry.label, entry.number, result }));
                }
                if (output.items.len == 0) add([]const u8, &output, "no rules");
            },
            .reflect => {
                const clauses = bot.prepared(text);
                for (clauses) |clause| add([]const u8, &output, g.join(responder.reflect(clause, bot.script.posts.items), " "));
                if (clauses.len == 0) add([]const u8, &output, "no words");
            },
            .keys => {
                const ids = zeros(bot.script.keywords.items.len);
                for (ids, 0..) |*id, i| id.* = i;
                std.mem.sort(usize, ids, bot.script, keyRankLess);
                var labels: std.ArrayList([]const u8) = .empty;
                for (ids) |id| { const key = bot.script.keywords.items[id]; add([]const u8, &labels, fmt("{s}/{d}", .{ key.word, key.rank })); }
                for (grouped(labels.items, 8)) |part| add([]const u8, &output, part);
            },
            .groups => {
                var names: std.ArrayList([]const u8) = .empty;
                for (bot.script.groups.items) |group| { if (g.has(group.members, args[0])) add([]const u8, &names, group.name); }
                std.mem.sort([]const u8, names.items, {}, stringLess);
                add([]const u8, &output, if (names.items.len == 0) "none" else g.join(names.items, " "));
            },
            .find => {
                const word = args[0];
                if (bot.script.keyword(word)) |id| add([]const u8, &output, fmt("keyword rank {d}", .{bot.script.keywords.items[id].rank}));
                const labels = [_][]const u8{ "pre", "post" };
                for ([_][]const g.Substitution{ bot.script.pres.items, bot.script.posts.items }, labels) |substitutions, label| {
                    for (substitutions) |entry| { if (eq(entry.source, word) or g.has(entry.replacement, word)) add([]const u8, &output, fmt("{s} {d}: {s} -> {s}", .{ label, entry.line, entry.source, g.join(entry.replacement, " ") })); }
                }
                for (bot.script.groups.items) |group| { if (g.has(group.members, word)) add([]const u8, &output, fmt("group {s} line {d}", .{ group.name, group.line })); }
                for (bot.script.keywords.items) |key| { for (ruleEntries(key)) |entry| { if (g.has(bot.script.rules.items[entry.id].pattern, word)) add([]const u8, &output, fmt("pattern {s} {s} {d}", .{ key.word, entry.label, entry.number })); } }
                if (g.has(bot.script.stop.items, word)) add([]const u8, &output, "stop word");
                if (g.has(bot.script.quit.items, word)) add([]const u8, &output, "quit word");
                if (output.items.len == 0) add([]const u8, &output, "not found");
            },
            .script => {
                const key = bot.script.keywords.items[key_id.?];
                var numbers: std.ArrayList(usize) = .empty;
                add(usize, &numbers, key.line);
                for (ruleEntries(key)) |entry| {
                    const rule = bot.script.rules.items[entry.id];
                    add(usize, &numbers, rule.line);
                    for (rule.items.items) |item| add(usize, &numbers, bot.script.items.items[item].line);
                }
                std.mem.sort(usize, numbers.items, {}, usizeLess);
                for (numbers.items) |number| add([]const u8, &output, fmt("{d} {s}", .{ number, bot.script.source[number - 1] }));
            },
            .why => { if (bot.state.session.last_trace) |trace| { for (trace) |part| add([]const u8, &output, part); } else add([]const u8, &output, "no reply yet"); },
            .trace => { bot.state.session.trace_on = eq(args[0], "on"); add([]const u8, &output, fmt("trace {s}", .{args[0]})); },
            .history => {
                const history = bot.state.session.history.items;
                if (history.len == 0) add([]const u8, &output, "no turns yet") else { for (history[history.len - @min(5, history.len)..]) |part| add([]const u8, &output, part); }
            },
            .memory => {
                add([]const u8, &output, fmt("memory {d}/{d}", .{ bot.state.queue.texts.items.len, bot.state.queue.capacity }));
                for (bot.state.queue.texts.items, 1..) |stored, number| add([]const u8, &output, fmt("{d}: {s}", .{ number, stored }));
            },
            .forget => { add([]const u8, &output, fmt("forgot {d}", .{bot.state.queue.texts.items.len})); bot.state.queue.clear(bot.prefix()); },
            .cycles, .coverage => {
                for (ruleEntries(bot.script.keywords.items[key_id.?])) |entry| {
                    const rule = bot.script.rules.items[entry.id];
                    const result = if (cmd == .cycles) (if (rule.items.items.len == 0) "empty" else fmt("next {d}/{d}", .{ bot.state.positions[entry.id] + 1, rule.items.items.len })) else blk: {
                        var uses: std.ArrayList([]const u8) = .empty;
                        for (rule.items.items) |item| add([]const u8, &uses, fmt("{d}", .{bot.state.item_uses[item]}));
                        break :blk fmt("hits {d} entries {s}", .{ bot.state.hits[entry.id], if (uses.items.len == 0) @as([]const u8, "-") else g.join(uses.items, " ") });
                    };
                    add([]const u8, &output, fmt("{s} {d}: {s}", .{ entry.label, entry.number, result }));
                }
                if (output.items.len == 0) add([]const u8, &output, "no rules");
            },
            .reset => { bot.cycleReset(); add([]const u8, &output, "cycles reset"); },
            .unused => {
                var numbers: std.ArrayList(usize) = .empty;
                for (bot.script.items.items, bot.state.item_uses) |item, uses| { if (uses == 0) add(usize, &numbers, item.line); }
                std.mem.sort(usize, numbers.items, {}, usizeLess);
                add([]const u8, &output, fmt("unused {d}", .{numbers.items.len}));
                for (grouped(numberStrings(numbers.items), 12)) |part| add([]const u8, &output, part);
            },
            .stats => add([]const u8, &output, sourceLine(bot.state.session.turns, bot.state.session.sources)),
            .say, .explain => {
                if (bot.isQuit(text)) add([]const u8, &output, "would quit") else {
                    const saved = bot.state.copy();
                    const decision = bot.decide(text);
                    bot.state = saved;
                    if (cmd == .say) add([]const u8, &output, decision.reply) else { for (decision.trace) |part| add([]const u8, &output, part); }
                }
            },
            .undo => {
                if (bot.state.session.undo) |snapshot| { bot.state = snapshot.*; add([]const u8, &output, fmt("undone turn {d}", .{bot.state.session.turns + 1})); } else add([]const u8, &output, "nothing to undo");
            },
        }
        return output.items;
    }
    fn notes(bot: *Chatbot) void {
        const session = bot.state.session;
        var topics: std.ArrayList(Count) = .empty;
        for (session.topics, bot.script.keywords.items) |count, key| { if (count > 0) add(Count, &topics, .{ .word = key.word, .count = count }); }
        add([]const u8, &bot.transcript, fmt("NOTES {s}", .{session.name}));
        bot.indent(&.{ sourceLine(session.turns, session.sources), fmt("topics: {s}", .{rankedCounts(topics.items)}), fmt("words: {s}", .{rankedCounts(session.words.items)}), fmt("memory: stored={d} recalled={d} pending={d}", .{ session.stored, session.recalled, bot.state.queue.texts.items.len }), fmt("unrecognized: {s}", .{if (session.unrecognized.items.len == 0) @as([]const u8, "none") else g.join(numberStrings(session.unrecognized.items), " ")}) });
        bot.total_turns += session.turns;
        for (0..5) |i| bot.total_sources[i] += session.sources[i];
    }
    fn run(bot: *Chatbot, dialogue: Strings) void {
        var sessions: usize = 0;
        for (dialogue) |line| {
            if (std.mem.startsWith(u8, line, "SESSION ")) {
                sessions += 1;
                const name = line[8..];
                if (sessions >= 2) {
                    add([]const u8, &bot.transcript, "");
                    if (!bot.script.persist_cycles) bot.cycleReset();
                    if (!bot.script.persist_memory) bot.state.queue.clear(fmt("{s} 0", .{name}));
                }
                bot.state.session = .{ .name = name, .topics = zeros(bot.script.keywords.items.len) };
                add([]const u8, &bot.transcript, line);
                const greetings = bot.script.texts[@intFromEnum(g.Directive.INITIAL)].items;
                bot.eliza(greetings[(sessions - 1) % greetings.len]);
            } else if (line[0] == ':') {
                add([]const u8, &bot.transcript, line);
                bot.indent(bot.command(line));
            } else {
                add([]const u8, &bot.transcript, fmt("YOU: {s}", .{line}));
                if (bot.isQuit(line)) {
                    const farewells = bot.script.texts[@intFromEnum(g.Directive.FINAL)].items;
                    bot.eliza(farewells[(sessions - 1) % farewells.len]);
                    bot.notes();
                } else bot.respond(line);
            }
        }
        add([]const u8, &bot.transcript, "");
        add([]const u8, &bot.transcript, fmt("SUMMARY sessions={d} {s}", .{ sessions, sourceLine(bot.total_turns, bot.total_sources) }));
    }
    fn keywordStats(bot: *const Chatbot) Strings {
        var rows: std.ArrayList([]const u8) = .empty;
        add([]const u8, &rows, "keyword,rank,uses,replies,decomposition_hits");
        var ranked: std.ArrayList(Count) = .empty;
        for (bot.script.keywords.items, bot.state.keyword_uses) |key, uses| add(Count, &ranked, .{ .word = key.word, .count = uses });
        std.mem.sort(Count, ranked.items, {}, countLess);
        for (ranked.items) |entry| {
            const id = bot.script.keyword(entry.word).?;
            const key = bot.script.keywords.items[id];
            var hits: std.ArrayList([]const u8) = .empty;
            for (key.decomps.items) |rule_id| add([]const u8, &hits, fmt("{d}", .{bot.state.hits[rule_id]}));
            add([]const u8, &rows, fmt("{s},{d},{d},{d},{s}", .{ key.word, key.rank, entry.count, bot.state.keyword_replies[id], if (hits.items.len == 0) @as([]const u8, "-") else g.join(hits.items, "/") }));
        }
        return rows.items;
    }
};

fn encodeLines(lines: Strings) []const u8 { return if (lines.len == 0) "" else fmt("{s}\n", .{g.join(lines, "\n")}); }

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    g.allocator = arena.allocator();
    const cwd = std.Io.Dir.cwd();
    const script_text = try cwd.readFileAlloc(init.io, "input/script.txt", g.allocator, .unlimited);
    const dialogue_text = try cwd.readFileAlloc(init.io, "input/dialogue.txt", g.allocator, .unlimited);
    var script = g.load(script_text);
    linter.lint(&script);
    var lint_lines: std.ArrayList([]const u8) = .empty;
    var errors: usize = 0;
    for (script.diagnostics.items) |entry| {
        add([]const u8, &lint_lines, fmt("{d} {s} {s}", .{ entry.line, @tagName(entry.code), entry.message }));
        if (linter.isError(entry.code)) errors += 1;
    }
    add([]const u8, &lint_lines, if (script.diagnostics.items.len == 0) "OK" else fmt("TOTAL {d} errors={d} warnings={d}", .{ script.diagnostics.items.len, errors, script.diagnostics.items.len - errors }));
    var bot: Chatbot = .{ .script = &script, .state = State.init(&script) };
    bot.run(g.lines(dialogue_text));
    try cwd.createDirPath(init.io, "output");
    try cwd.writeFile(init.io, .{ .sub_path = "output/lint.txt", .data = encodeLines(lint_lines.items) });
    try cwd.writeFile(init.io, .{ .sub_path = "output/transcript.txt", .data = encodeLines(bot.transcript.items) });
    try cwd.writeFile(init.io, .{ .sub_path = "output/keyword_stats.csv", .data = encodeLines(bot.keywordStats()) });
    try cwd.writeFile(init.io, .{ .sub_path = "output/memory_log.txt", .data = encodeLines(bot.state.queue.log.items) });
}
