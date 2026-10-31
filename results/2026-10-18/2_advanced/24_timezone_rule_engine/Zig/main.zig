const std = @import("std");
const d = @import("day_rules.zig");
const p = @import("tz_parser.zig");
const tr = @import("transitions.zig");
const resolver = @import("resolver.zig");
const r = @import("report.zig");

const ZoneLine = struct {
    offset: i64,
    rules_text: []const u8,
    rule_set: ?[]const u8 = null,
    save: i64 = 0,
    format_text: []const u8,
    until: ?p.Until = null,
    start: i64 = d.neg_infinity,
    end: i64 = d.pos_infinity,
};
const SourceLine = struct {
    number: usize,
    fields: []const []const u8,
    kind: enum { unknown, rule, zone, continuation, link },
    block: ?*Block = null,
    position: usize = 0,
    zone_line: ?*ZoneLine = null,
    field_error: bool = false,
    error_text: ?[]const u8 = null,

    fn acceptsContinuation(self: SourceLine) bool {
        return (self.kind == .zone and self.fields.len >= 6) or (self.kind == .continuation and self.fields.len >= 4);
    }
};
const Block = struct {
    name: []const u8,
    number: usize,
    lines: std.ArrayList(*SourceLine) = .empty,
    defined: bool = false,
    fn add(self: *Block, line: *SourceLine) void {
        line.block = self;
        line.position = self.lines.items.len;
        r.append(*SourceLine, &self.lines, line);
    }
};
const RuleSet = struct { name: []const u8, rules: std.ArrayList(*tr.Rule) = .empty, instances: []tr.Instance = &.{} };
const Zone = struct {
    name: []const u8,
    lines: []*ZoneLine,
    aliases: r.Lines = .{},
    applied: [401]usize = @splat(0),
    periods: std.ArrayList(resolver.Period) = .empty,
    timeline: resolver.Timeline = .{ .periods = &.{} },

    fn ruleSets(self: *const Zone) []const []const u8 {
        var names: r.Lines = .{};
        for (self.lines) |line| {
            const name = line.rule_set orelse continue;
            var present = false;
            for (names.data.items) |other| if (r.eq(other, name)) { present = true; break; };
            if (!present) names.write(name);
        }
        return names.data.items;
    }
    fn usesRuleSet(self: *const Zone, name: []const u8) bool {
        for (self.lines) |line| if (line.rule_set != null and r.eq(line.rule_set.?, name)) return true;
        return false;
    }
    fn addPeriod(self: *Zone, line: *const ZoneLine, start: i64, save: i64, letter: []const u8) void {
        const period: resolver.Period = .{ .start = start, .offset = line.offset + save, .dst = save != 0, .abbreviation = tr.abbreviation(line.format_text, save, letter) };
        if (self.periods.items.len > 0 and self.periods.items[self.periods.items.len - 1].sameState(period)) return;
        r.append(resolver.Period, &self.periods, period);
    }
};
const Alias = struct { name: []const u8, zone: *Zone };
const Database = struct {
    backing: std.mem.Allocator,
    lines: std.ArrayList(*SourceLine) = .empty,
    blocks: std.ArrayList(*Block) = .empty,
    sets: std.ArrayList(*RuleSet) = .empty,
    zones: std.ArrayList(*Zone) = .empty,
    aliases: std.ArrayList(Alias) = .empty,

    fn findSet(self: *const Database, name: []const u8) ?*RuleSet {
        for (self.sets.items) |set| if (r.eq(set.name, name)) return set;
        return null;
    }
    fn findZone(self: *const Database, name: []const u8, aliases: bool) ?*Zone {
        for (self.zones.items) |zone| if (r.eq(zone.name, name)) return zone;
        if (aliases) for (self.aliases.items) |alias| { if (r.eq(alias.name, name)) return alias.zone; };
        return null;
    }
    fn assembleLines(self: *Database, raw: []const []const u8) void {
        var previous: ?*SourceLine = null;
        for (raw, 1..) |text, number| {
            const content = p.lineContent(text);
            if (content.len == 0) continue;
            const fields = r.splitFields(content);
            const line = &r.alloc(SourceLine, 1)[0];
            line.* = .{ .number = number, .fields = fields, .kind = if (content[0] == ' ') .continuation else if (r.eq(fields[0], "Rule")) .rule else if (r.eq(fields[0], "Zone")) .zone else if (r.eq(fields[0], "Link")) .link else .unknown };
            r.append(*SourceLine, &self.lines, line);
            if (line.kind == .zone) {
                const block = &r.alloc(Block, 1)[0];
                block.* = .{ .name = fields[1], .number = number };
                block.add(line);
                r.append(*Block, &self.blocks, block);
            } else if (line.kind == .continuation and previous != null and previous.?.block != null and previous.?.acceptsContinuation()) previous.?.block.?.add(line);
            previous = line;
        }
    }
    fn checkRule(self: *Database, line: *SourceLine) p.FieldError!void {
        const fields = line.fields;
        const from = try p.parseYear(fields[2]);
        const to = try p.parseTo(fields[3], from);
        if (!r.eq(fields[4], "-")) return error.Syntax;
        const month = try p.parseMonth(fields[5]);
        const day = try p.parseDaySpec(fields[6], month);
        const at = try p.parseTime(fields[7]);
        const save = try p.parseSave(fields[8]);
        const letter = try p.parseLetter(fields[9]);
        const rule = &r.alloc(tr.Rule, 1)[0];
        rule.* = .{ .number = line.number, .fields = fields, .name = fields[1], .from = from, .to = to, .month = month, .day = day, .at = at.value, .kind = at.kind, .save = save, .letter = letter };
        const set = self.findSet(rule.name) orelse blk: {
            const created = &r.alloc(RuleSet, 1)[0];
            created.* = .{ .name = rule.name };
            r.append(*RuleSet, &self.sets, created);
            break :blk created;
        };
        r.append(*tr.Rule, &set.rules, rule);
    }
    fn checkZoneLine(source: *SourceLine) p.FieldError!*ZoneLine {
        const first: usize = if (source.kind == .zone) 2 else 0;
        const fields = source.fields[first..];
        const offset = try p.parseOffset(fields[0]);
        var rule_set: ?[]const u8 = null;
        var save: i64 = 0;
        if (fields[1][0] >= '0' and fields[1][0] <= '9') save = try p.parseSave(fields[1]) else if (!r.eq(fields[1], "-")) rule_set = fields[1];
        try p.checkFormat(fields[2], rule_set != null);
        const until = if (fields.len > 3) try p.parseUntil(fields[3..]) else null;
        const line = &r.alloc(ZoneLine, 1)[0];
        line.* = .{ .offset = offset, .rules_text = fields[1], .rule_set = rule_set, .save = save, .format_text = fields[2], .until = until };
        return line;
    }
    fn parseFields(self: *Database, line: *SourceLine) p.FieldError!void {
        const count = line.fields.len;
        const valid = switch (line.kind) {
            .rule => count == 10,
            .zone => count >= 5 and count <= 9,
            .continuation => line.block != null and count >= 3 and count <= 7,
            .link => count == 3,
            .unknown => false,
        };
        if (!valid) return error.Syntax;
        if (line.kind == .rule) try self.checkRule(line) else if (line.kind == .zone or line.kind == .continuation) line.zone_line = try checkZoneLine(line);
    }
    fn structuralError(self: *const Database, line: *const SourceLine, reserved: *r.Lines) ?[]const u8 {
        const zone_line = line.zone_line.?;
        if (line.kind == .zone) {
            const name = line.fields[1];
            for (reserved.data.items) |other| if (r.eq(other, name)) return r.fmt("duplicate zone {s}", .{name});
            reserved.write(name);
        }
        if (zone_line.rule_set) |name| if (self.findSet(name) == null) return r.fmt("unknown rule {s}", .{name});
        const until = zone_line.until orelse return null;
        if (line.kind == .continuation) {
            const previous = line.block.?.lines.items[line.position - 1];
            if (!previous.field_error and until.value <= previous.zone_line.?.until.?.value) return "until not increasing";
        }
        return if (line.position + 1 == line.block.?.lines.items.len) "missing continuation" else null;
    }
    fn defineZone(self: *Database, block: *Block) void {
        const zone = &r.alloc(Zone, 1)[0];
        const lines = r.alloc(*ZoneLine, block.lines.items.len);
        for (block.lines.items, lines) |source, *line| line.* = source.zone_line.?;
        zone.* = .{ .name = block.name, .lines = lines };
        var start = d.neg_infinity;
        for (lines) |line| {
            line.start = start;
            if (line.rule_set) |name| {
                const set = self.findSet(name).?;
                var scratch = std.heap.ArenaAllocator.init(self.backing);
                defer scratch.deinit();
                const run = tr.runInstances(scratch.allocator(), set.instances, line.offset, start, line.until);
                line.end = run.end;
                if (run.pre_start) |last| zone.addPeriod(line, start, last.save, last.letter) else {
                    var letter: []const u8 = "";
                    for (set.instances) |instance| {
                        if (instance.rule.save == 0) { letter = instance.rule.letter; break; }
                    }
                    zone.addPeriod(line, start, 0, letter);
                }
                for (run.applied) |applied| {
                    zone.addPeriod(line, applied.time, applied.rule.save, applied.rule.letter);
                    zone.applied[applied.rule.number] += 1;
                }
            } else {
                if (line.until) |until| line.end = until.value - tr.adjustment(until.kind, line.offset, line.save);
                zone.addPeriod(line, start, line.save, "");
            }
            start = line.end;
        }
        zone.timeline.periods = zone.periods.items;
        r.append(*Zone, &self.zones, zone);
    }
    fn create(raw: []const []const u8, backing: std.mem.Allocator) *Database {
        const database = &r.alloc(Database, 1)[0];
        database.* = .{ .backing = backing };
        database.assembleLines(raw);
        for (database.lines.items) |line| {
            database.parseFields(line) catch |err| {
                line.field_error = true;
                line.error_text = p.errorText(err);
            };
        }
        var reserved: r.Lines = .{};
        for (database.lines.items) |line| if (line.zone_line != null) { line.error_text = database.structuralError(line, &reserved); };
        for (database.sets.items) |set| set.instances = tr.instanceSequence(set.rules.items);
        for (database.blocks.items) |block| {
            block.defined = true;
            for (block.lines.items) |line| if (line.error_text != null) { block.defined = false; };
            if (block.defined) database.defineZone(block);
        }
        for (database.lines.items) |line| {
            if (line.kind != .link or line.error_text != null) continue;
            const target = line.fields[1];
            const alias = line.fields[2];
            if (database.findZone(target, false)) |zone| {
                if (database.findZone(alias, true) != null) line.error_text = r.fmt("duplicate link {s}", .{alias}) else {
                    r.append(Alias, &database.aliases, .{ .name = alias, .zone = zone });
                    zone.aliases.write(alias);
                }
            } else line.error_text = r.fmt("unknown link target {s}", .{target});
        }
        return database;
    }
    fn errorLines(self: *const Database) r.Lines {
        var lines: r.Lines = .{};
        for (self.lines.items) |line| if (line.error_text) |error_text| { lines.add("line {d}: {s}", .{ line.number, error_text }); };
        return lines;
    }
};

const Interval = struct { low: i64, high: i64 };
fn intervalOrder(_: void, first: Interval, second: Interval) bool {
    return if (first.low != second.low) first.low < second.low else first.high < second.high;
}
fn mergeIntervals(source: []Interval) []Interval {
    std.mem.sort(Interval, source, {}, intervalOrder);
    var result: std.ArrayList(Interval) = .empty;
    for (source) |item| {
        if (result.items.len > 0 and item.low <= result.items[result.items.len - 1].high) {
            const last = &result.items[result.items.len - 1];
            last.high = @max(last.high, item.high);
        } else r.append(Interval, &result, item);
    }
    return result.items;
}
fn intersectIntervals(first: []const Interval, second: []const Interval) []Interval {
    var pieces: std.ArrayList(Interval) = .empty;
    for (first) |a| {
        for (second) |b| {
            const low = @max(a.low, b.low);
            const high = @min(a.high, b.high);
            if (low < high) r.append(Interval, &pieces, .{ .low = low, .high = high });
        }
    }
    return mergeIntervals(pieces.items);
}
fn yearStart(year: i64) i64 { return d.dayNumber(year, 1, 1) * 86400; }
fn offsetShift(timeline: resolver.Timeline, index: usize) i64 {
    return timeline.periods[index].offset - timeline.periods[index - 1].offset;
}
fn shiftsText(timeline: resolver.Timeline, low: i64, high: i64) []const u8 {
    var gaps: usize = 0;
    var overlaps: usize = 0;
    var unchanged: usize = 0;
    for (timeline.periods[1..], 1..) |period, index| {
        if (period.start < low or period.start >= high) continue;
        const shift = offsetShift(timeline, index);
        if (shift > 0) gaps += 1 else if (shift < 0) overlaps += 1 else unchanged += 1;
    }
    return r.fmt("gaps {d}, overlaps {d}, no shift {d}", .{ gaps, overlaps, unchanged });
}
fn transitionCount(timeline: resolver.Timeline, low: i64, high: i64) usize {
    var count: usize = 0;
    for (timeline.periods[1..]) |period| if (period.start >= low and period.start < high) { count += 1; };
    return count;
}
fn transitionLine(timeline: resolver.Timeline, index: usize) []const u8 {
    const time = timeline.periods[index].start;
    const shift = offsetShift(timeline, index);
    const kind = if (shift > 0) r.fmt("gap {s}", .{r.durationText(shift)}) else if (shift < 0) r.fmt("overlap {s}", .{r.durationText(-shift)}) else "no shift";
    return r.fmt("{s} (local {s} -> {s}, {s})", .{ r.changeText(timeline, index), r.localText(time + timeline.periods[index - 1].offset), r.localText(time + timeline.periods[index].offset), kind });
}
fn candidateText(timeline: resolver.Timeline, local: i64, index: usize) []const u8 {
    return r.fmt("{s} ({s})", .{ r.utText(local - timeline.periods[index].offset), r.stateText(timeline.periods[index]) });
}
fn chosenCandidate(found: resolver.Candidates, option: ?[]const u8) ?usize {
    if (found.count == 1) return found.indices[0];
    if (found.count == 2) {
        if (option) |choice| {
            if (r.eq(choice, "EARLIER")) return found.indices[0];
            if (r.eq(choice, "LATER")) return found.indices[1];
        }
    }
    return null;
}
fn unresolvedText(timeline: resolver.Timeline, local: i64, found: resolver.Candidates) []const u8 {
    if (found.count > 0) return r.fmt("AMBIGUOUS {s} or {s}", .{ candidateText(timeline, local, found.indices[0]), candidateText(timeline, local, found.indices[1]) });
    const index = timeline.skippingTransition(local);
    const time = timeline.periods[index].start;
    return r.fmt("NONEXISTENT gap {s} to {s} at {s}", .{ r.localText(time + timeline.periods[index - 1].offset), r.localText(time + timeline.periods[index].offset), r.utText(time) });
}
fn workingHours(timeline: resolver.Timeline, start: i64, end: i64) []Interval {
    var pieces: std.ArrayList(Interval) = .empty;
    const first = timeline.indexAt(start - 57600);
    const last = timeline.indexAt(end + 57600);
    for (first..last + 1) |index| {
        const period = timeline.periods[index];
        const low = @max(start - period.offset, period.start);
        const high = @min(end - period.offset, timeline.endOf(index));
        if (low < high) r.append(Interval, &pieces, .{ .low = low, .high = high });
    }
    return mergeIntervals(pieces.items);
}
const ArgumentKind = enum { zone, local, ut, date, year };
fn parseValue(kind: ArgumentKind, word: []const u8) ?i64 {
    var date: d.DateTime = .{ .year = r.number(word[0..4]) };
    if (date.year < 1800 or date.year > 2099) return null;
    if (kind == .year) return date.year;
    date.month = r.number(word[5..7]);
    date.day = r.number(word[8..10]);
    if (date.month < 1 or date.month > 12 or date.day < 1 or date.day > d.daysInMonth(date.year, date.month)) return null;
    if (kind == .date) return d.dayNumber(date.year, date.month, date.day);
    date.hour = r.number(word[11..13]);
    date.minute = r.number(word[14..16]);
    date.second = r.number(word[17..19]);
    if (date.hour > 23 or date.minute > 59 or date.second > 59) return null;
    return d.timeValue(date);
}
const Argument = struct { zone: ?*Zone = null, value: i64 = 0 };
const QueryRunner = struct {
    database: *Database,
    work_start: i64,
    work_end: i64,
    answers: r.Lines = .{},
    transitions: r.Lines = .{},

    fn meeting(self: *const QueryRunner, values: []const Argument, words: []const []const u8) []const u8 {
        const start = values[0].value * 86400 + self.work_start;
        const end = values[0].value * 86400 + self.work_end;
        var common = workingHours(values[1].zone.?.timeline, start, end);
        for (values[2..]) |value| common = intersectIntervals(common, workingHours(value.zone.?.timeline, start, end));
        if (common.len == 0) return "NONE";
        var parts: r.Lines = .{};
        for (common) |interval| {
            var members: r.Lines = .{};
            for (values[1..], words[1..]) |value, word| {
                const timeline = value.zone.?.timeline;
                const period = timeline.periods[timeline.indexAt(interval.low)];
                members.add("{s} {s} {s}", .{ word, r.localText(interval.low + period.offset), period.abbreviation });
            }
            parts.add("{s} to {s} ({s}) [{s}]", .{ r.utText(interval.low), r.utText(interval.high), r.durationText(interval.high - interval.low), r.join(members.data.items, ", ") });
        }
        return r.join(parts.data.items, "; ");
    }
    fn answer(self: *QueryRunner, line: []const u8) []const u8 {
        const fields = r.splitFields(line);
        const command = fields[0];
        var words = fields[1..];
        var option: ?[]const u8 = null;
        if ((r.eq(command, "TOUTC") or r.eq(command, "CONVERT")) and (r.eq(words[words.len - 1], "EARLIER") or r.eq(words[words.len - 1], "LATER"))) {
            option = words[words.len - 1];
            words = words[0 .. words.len - 1];
        }
        const kinds = r.alloc(ArgumentKind, words.len);
        if (r.eq(command, "MEETING")) {
            kinds[0] = .date;
            @memset(kinds[1..], .zone);
        } else {
            kinds[0] = .zone;
            if (r.eq(command, "CONVERT")) {
                kinds[1] = .zone;
                kinds[2] = .local;
            } else if (r.eq(command, "TRANSITIONS")) {
                kinds[1] = .year;
                kinds[2] = .year;
            } else if (r.eq(command, "DURATION")) {
                kinds[1] = .local;
                kinds[2] = .local;
            } else kinds[1] = if (r.eq(command, "TOUTC")) .local else .ut;
        }
        const values = r.alloc(Argument, words.len);
        @memset(values, .{});
        for (words, kinds, values) |word, kind, *value| {
            if (kind == .zone) {
                value.zone = self.database.findZone(word, true) orelse return r.fmt("ERROR unknown zone {s}", .{word});
            } else value.value = parseValue(kind, word) orelse return r.fmt("ERROR invalid value {s}", .{word});
        }
        if (r.eq(command, "MEETING")) return self.meeting(values, words);
        const timeline = values[0].zone.?.timeline;
        const time = values[1].value;
        if (r.eq(command, "TOLOCAL")) {
            const period = timeline.periods[timeline.indexAt(time)];
            return r.fmt("{s} ({s})", .{ r.localText(time + period.offset), r.stateText(period) });
        }
        if (r.eq(command, "OFFSET")) {
            const index = timeline.indexAt(time);
            var text: r.Text = .{};
            text.write(r.stateText(timeline.periods[index]));
            if (index > 0) text.add(" since {s}", .{r.utText(timeline.periods[index].start)});
            if (index + 1 < timeline.periods.len) text.add(" until {s}", .{r.utText(timeline.periods[index + 1].start)});
            return text.value();
        }
        if (r.eq(command, "TRANSITIONS")) {
            if (values[1].value > values[2].value) return "ERROR invalid range";
            const low = yearStart(values[1].value);
            const high = yearStart(values[2].value + 1);
            var block: r.Lines = .{};
            block.write(line);
            for (timeline.periods[1..], 1..) |period, index| {
                if (period.start >= low and period.start < high) block.write(transitionLine(timeline, index));
            }
            block.write(shiftsText(timeline, low, high));
            self.transitions.paragraph(block);
            return r.fmt("transitions: {d}", .{transitionCount(timeline, low, high)});
        }
        if (r.eq(command, "DURATION")) {
            var periods: [2]resolver.Period = undefined;
            for (0..2) |i| {
                const found = timeline.candidates(values[i + 1].value);
                if (found.count != 1) return r.fmt("{s} {s}", .{ if (found.count > 0) "AMBIGUOUS" else "NONEXISTENT", words[i + 1] });
                periods[i] = timeline.periods[found.indices[0]];
            }
            const elapsed = (values[2].value - periods[1].offset) - (values[1].value - periods[0].offset);
            return r.fmt("{d} s ({s}), wall clock {s}, offset change {s}", .{ elapsed, r.durationText(elapsed), r.durationText(values[2].value - values[1].value), r.offsetText(periods[1].offset - periods[0].offset) });
        }
        const convert = r.eq(command, "CONVERT");
        const local = values[if (convert) @as(usize, 2) else 1].value;
        const found = timeline.candidates(local);
        const index = chosenCandidate(found, option) orelse return unresolvedText(timeline, local, found);
        if (!convert) return candidateText(timeline, local, index);
        const utc = local - timeline.periods[index].offset;
        const target = values[1].zone.?.timeline;
        const period = target.periods[target.indexAt(utc)];
        const target_local = utc + period.offset;
        const shift = @divFloor(target_local, 86400) - @divFloor(local, 86400);
        return r.fmt("{s} ({s}) at {s}, day shift {s}{d}", .{ r.localText(target_local), r.stateText(period), r.utText(utc), if (shift > 0) "+" else "", shift });
    }
};

fn namesOrNone(names: []const []const u8, separator: []const u8) []const u8 {
    return if (names.len == 0) "none" else r.join(names, separator);
}
fn databaseBlock(database: *const Database) r.Lines {
    var rule_count: usize = 0;
    var valid_rules: usize = 0;
    var link_count: usize = 0;
    var valid_links: usize = 0;
    for (database.lines.items) |line| {
        if (line.kind == .rule) {
            rule_count += 1;
            if (line.error_text == null) valid_rules += 1;
        }
        if (line.kind == .link) {
            link_count += 1;
            if (line.error_text == null) valid_links += 1;
        }
    }
    var zone_lines: usize = 0;
    for (database.zones.items) |zone| zone_lines += zone.lines.len;
    var unused: r.Lines = .{};
    var invalid: r.Lines = .{};
    const zone_counts = r.alloc(usize, database.sets.items.len);
    @memset(zone_counts, 0);
    for (database.sets.items, zone_counts) |set, *count| {
        for (database.zones.items) |zone| if (zone.usesRuleSet(set.name)) { count.* += 1; };
        if (count.* == 0) unused.write(set.name);
    }
    for (database.blocks.items) |block| if (!block.defined) { invalid.add("{s} (line {d})", .{ block.name, block.number }); };
    var lines: r.Lines = .{};
    lines.write("DATABASE");
    lines.add("rule lines: {d} valid, {d} invalid", .{ valid_rules, rule_count - valid_rules });
    lines.add("zones: {d} defined, {d} invalid", .{ database.zones.items.len, database.blocks.items.len - database.zones.items.len });
    lines.add("zone lines: {d} in defined zones", .{zone_lines});
    lines.add("links: {d} defined, {d} invalid", .{ valid_links, link_count - valid_links });
    lines.add("errors: {d}", .{database.errorLines().data.items.len});
    lines.add("unused rules: {s}", .{namesOrNone(unused.data.items, " ")});
    lines.add("invalid zones: {s}", .{namesOrNone(invalid.data.items, ", ")});
    for (database.sets.items, zone_counts) |set, count| {
        var first: i64 = 2099;
        var last: i64 = 1800;
        var has_max = false;
        for (set.rules.items) |rule| {
            first = @min(first, rule.from);
            last = @max(last, rule.to);
            has_max = has_max or r.eq(rule.fields[3], "max");
        }
        lines.add("rule set {s}: lines {d}, years {d}-{s}, zones {d}", .{ set.name, set.rules.items.len, first, if (has_max) "max" else r.fmt("{d}", .{last}), count });
    }
    return lines;
}
fn dstLines(lines: *r.Lines, timeline: resolver.Timeline, reference: i64) void {
    var first_year: ?i64 = null;
    var last_year: ?i64 = null;
    const year = d.splitTime(reference).year;
    const low = yearStart(year);
    const high = yearStart(year + 1);
    var pieces: std.ArrayList(Interval) = .empty;
    for (timeline.periods, 0..) |period, index| {
        if (!period.dst) continue;
        const start_year = d.splitTime(period.start).year;
        first_year = if (first_year) |first| @min(first, start_year) else start_year;
        last_year = if (last_year) |last| @max(last, start_year) else start_year;
        const start = @max(period.start, low);
        const end = @min(timeline.endOf(index), high);
        if (start < end) r.append(Interval, &pieces, .{ .low = start, .high = end });
    }
    if (first_year) |first| lines.add("dst years: {d}-{d}", .{ first, last_year.? }) else lines.write("dst years: none");
    const merged = mergeIntervals(pieces.items);
    var total: i64 = 0;
    for (merged) |piece| {
        lines.add("dst period: {s} to {s} ({s})", .{ r.utText(piece.low), r.utText(piece.high), r.durationText(piece.high - piece.low) });
        total += piece.high - piece.low;
    }
    lines.add("dst total {d}: {s}", .{ year, r.durationText(total) });
}
fn stateHash(period: resolver.Period) u64 {
    var hash: u64 = @bitCast(period.offset);
    hash = (hash ^ @as(u64, @intFromBool(period.dst))) *% 1099511628211;
    for (period.abbreviation) |character| hash = (hash ^ character) *% 1099511628211;
    return hash;
}
fn stateLines(lines: *r.Lines, timeline: resolver.Timeline) void {
    var capacity: usize = 1;
    while (capacity < 2 * timeline.periods.len) capacity *= 2;
    const buckets = r.alloc(usize, capacity);
    @memset(buckets, std.math.maxInt(usize));
    const firsts = r.alloc(usize, timeline.periods.len);
    const counts = r.alloc(usize, timeline.periods.len);
    var distinct: usize = 0;
    for (timeline.periods, 0..) |period, index| {
        var bucket: usize = @intCast(stateHash(period) & (capacity - 1));
        while (buckets[bucket] != std.math.maxInt(usize) and !period.sameState(timeline.periods[firsts[buckets[bucket]]])) bucket = (bucket + 1) & (capacity - 1);
        if (buckets[bucket] == std.math.maxInt(usize)) {
            buckets[bucket] = distinct;
            firsts[distinct] = index;
            counts[distinct] = 0;
            distinct += 1;
        }
        counts[buckets[bucket]] += 1;
    }
    for (firsts[0..distinct], counts[0..distinct]) |first, count| lines.add("state {s}, periods {d}", .{ r.stateText(timeline.periods[first]), count });
}
fn zoneBlock(database: *const Database, zone: *const Zone, reference: i64) r.Lines {
    const timeline = zone.timeline;
    var lines: r.Lines = .{};
    lines.add("ZONE {s}", .{zone.name});
    lines.add("aliases: {s}", .{namesOrNone(zone.aliases.data.items, " ")});
    for (zone.lines, 0..) |line, i| {
        const rules = line.rule_set orelse if (r.eq(line.rules_text, "-")) "-" else r.clockText(line.save);
        var text: r.Text = .{};
        text.add("line {d}: {s} {s} {s}", .{ i + 1, r.offsetText(line.offset), rules, line.format_text });
        if (i > 0) text.add(" from {s}", .{r.utText(line.start)});
        if (line.until) |until| text.add(" until {s} {s} {s} {s}{c} = {s}", .{ until.year_text, until.month_text, until.day_text, r.clockText(until.time), until.kind, r.utText(line.end) });
        text.add(", transitions {d}", .{transitionCount(timeline, line.start, line.end)});
        lines.write(text.value());
    }
    for (zone.ruleSets()) |name| {
        const set = database.findSet(name).?;
        for (set.rules.items) |rule| {
            const fields = rule.fields;
            lines.add("rule {s} {s} {s} {s} {s} {s}{c} {s} {s}, applied {d}", .{ rule.name, fields[2], fields[3], fields[5], fields[6], r.clockText(rule.at), rule.kind, r.clockText(rule.save), fields[9], zone.applied[rule.number] });
        }
    }
    var minimum = timeline.periods[0].offset;
    var maximum = minimum;
    for (timeline.periods[1..]) |period| {
        minimum = @min(minimum, period.offset);
        maximum = @max(maximum, period.offset);
    }
    lines.add("offset range: {s} to {s}", .{ r.offsetText(minimum), r.offsetText(maximum) });
    stateLines(&lines, timeline);
    const index = timeline.indexAt(reference);
    var line_number: usize = 0;
    for (zone.lines, 1..) |line, number| {
        if (line.start <= reference and reference < line.end) { line_number = number; break; }
    }
    const period = timeline.periods[index];
    lines.add("reference: {s} ({s}), line {d}", .{ r.localText(reference + period.offset), r.stateText(period), line_number });
    lines.add("previous transition: {s}", .{if (index > 0) r.changeText(timeline, index) else "none"});
    lines.add("next transition: {s}", .{if (index + 1 < timeline.periods.len) r.changeText(timeline, index + 1) else "none"});
    lines.add("transitions: {d}, {s}", .{ timeline.periods.len - 1, shiftsText(timeline, d.neg_infinity, d.pos_infinity) });
    dstLines(&lines, timeline, reference);
    return lines;
}
fn indented(source: r.Lines) r.Lines {
    var result: r.Lines = .{};
    for (source.data.items, 0..) |line, index| result.add("{s}{s}", .{ if (index == 0) "" else "  ", line });
    return result;
}
fn zoneOrder(_: void, first: *Zone, second: *Zone) bool {
    return std.mem.order(u8, first.name, second.name) == .lt;
}
fn clockSeconds(text: []const u8) i64 { return r.number(text[0..2]) * 3600 + r.number(text[3..5]) * 60; }

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    r.allocator = arena.allocator();
    const io = init.io;
    const raw = r.lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/tzdata.txt", r.allocator, .unlimited));
    const database = Database.create(raw, init.gpa);
    const parameters = r.lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/params.txt", r.allocator, .unlimited));
    const reference_fields = r.splitFields(parameters[0]);
    const workday = r.splitFields(parameters[1]);
    const reference = parseValue(.ut, reference_fields[1]).?;
    var runner: QueryRunner = .{ .database = database, .work_start = clockSeconds(workday[1]), .work_end = clockSeconds(workday[2]) };
    const queries = r.lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/queries.txt", r.allocator, .unlimited));
    for (queries) |query| runner.answers.add("{s} => {s}", .{ query, runner.answer(query) });
    var summary: r.Lines = .{};
    summary.paragraph(indented(databaseBlock(database)));
    const ordered = r.alloc(*Zone, database.zones.items.len);
    @memcpy(ordered, database.zones.items);
    std.mem.sort(*Zone, ordered, {}, zoneOrder);
    for (ordered) |zone| summary.paragraph(indented(zoneBlock(database, zone, reference)));
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try r.writeLines(io, "answers.txt", runner.answers);
    try r.writeLines(io, "errors.txt", database.errorLines());
    try r.writeLines(io, "transitions.txt", runner.transitions);
    try r.writeLines(io, "zone_summary.txt", summary);
}
