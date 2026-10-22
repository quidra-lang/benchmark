const std = @import("std");

const Allocator = std.mem.Allocator;
const Lines = []const []const u8;
const Error = error{CommandFailed} || std.Io.Writer.Error || Allocator.Error ||
    std.fmt.ParseIntError;

const data_commands = [_][]const u8{ "FILE", "PATCH", "EDIT" };
const formats_with_argument = [_][]const u8{ "IFDEF", "UNIFIED", "CONTEXT", "SIDE" };
const offsets = [_]isize{ 0, 1, -1, 2, -2, 3, -3 };
const graph_width = 20;
const max_side_width = 40;
const separator_marker = "=======";

fn fail(out: *std.Io.Writer, comptime format: []const u8, args: anytype) Error {
    out.print(format ++ "\n", args) catch |err| return err;
    return error.CommandFailed;
}

fn contains(words: Lines, word: []const u8) bool {
    for (words) |candidate| {
        if (std.mem.eql(u8, candidate, word)) return true;
    }
    return false;
}

fn linesEqual(first: Lines, second: Lines) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| {
        if (!std.mem.eql(u8, a, b)) return false;
    }
    return true;
}

fn writeLines(out: *std.Io.Writer, prefix: []const u8, lines: Lines) !void {
    for (lines) |line| try out.print("{s}{s}\n", .{ prefix, line });
}

fn splitWords(allocator: Allocator, line: []const u8) !Lines {
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.splitScalar(u8, line, ' ');
    while (parts.next()) |part| try words.append(allocator, part);
    return words.items;
}

const RangeStyle = enum { r, u, m };

const Range = struct {
    start: usize,
    count: usize,
    style: RangeStyle,

    pub fn format(self: Range, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.style == .m or self.count >= 2) {
            const last = if (self.style == .r) self.start + self.count else self.count;
            return writer.print("{d},{d}", .{ self.start + 1, last });
        }
        if (self.count == 1) return writer.print("{d}", .{self.start + 1});
        if (self.style == .u) return writer.print("{d},0", .{self.start});
        return writer.print("{d}", .{self.start});
    }
};

fn rangeR(start: usize, count: usize) Range {
    return .{ .start = start, .count = count, .style = .r };
}

fn rangeU(start: usize, count: usize) Range {
    return .{ .start = start, .count = count, .style = .u };
}

fn rangeM(start: usize, count: usize) Range {
    return .{ .start = start, .count = count, .style = .m };
}

const CompareOptions = struct {
    ignore_case: bool = false,
    ignore_white: bool = false,
    ignore_space: bool = false,

    fn parse(words: Lines) CompareOptions {
        return .{
            .ignore_case = contains(words, "ICASE"),
            .ignore_white = contains(words, "IWHITE"),
            .ignore_space = contains(words, "ISPACE"),
        };
    }
};

fn comparisonKeys(allocator: Allocator, lines: Lines, options: CompareOptions) !Lines {
    const keys = try allocator.alloc([]const u8, lines.len);
    for (keys, lines) |*key, line| {
        var text: std.ArrayList(u8) = .empty;
        for (line, 0..) |c, i| {
            const repeated = i > 0 and line[i - 1] == ' ';
            const skipped = options.ignore_white or (options.ignore_space and repeated);
            if (c == ' ' and skipped) continue;
            try text.append(allocator, if (options.ignore_case) std.ascii.toLower(c) else c);
        }
        key.* = text.items;
    }
    return keys;
}

const Pair = struct { old: usize, new: usize };

fn matchedPairs(allocator: Allocator, first: Lines, second: Lines) ![]Pair {
    const columns = second.len + 1;
    const table = try allocator.alloc(usize, (first.len + 1) * columns);
    @memset(table, 0);
    for (1..first.len + 1) |i| {
        for (1..second.len + 1) |j| {
            table[i * columns + j] = if (std.mem.eql(u8, first[i - 1], second[j - 1]))
                table[(i - 1) * columns + j - 1] + 1
            else
                @max(table[(i - 1) * columns + j], table[i * columns + j - 1]);
        }
    }
    var pairs: std.ArrayList(Pair) = .empty;
    try pairs.append(allocator, .{ .old = first.len + 1, .new = second.len + 1 });
    var i = first.len;
    var j = second.len;
    while (i >= 1 and j >= 1) {
        if (std.mem.eql(u8, first[i - 1], second[j - 1])) {
            try pairs.append(allocator, .{ .old = i, .new = j });
            i -= 1;
            j -= 1;
        } else if (table[(i - 1) * columns + j] >= table[i * columns + j - 1]) {
            i -= 1;
        } else {
            j -= 1;
        }
    }
    try pairs.append(allocator, .{ .old = 0, .new = 0 });
    std.mem.reverse(Pair, pairs.items);
    return pairs.items;
}

const ChangeBlock = struct {
    p: usize,
    q: usize,
    x: usize,
    y: usize,

    fn letter(self: ChangeBlock) u8 {
        if (self.x >= 1 and self.y >= 1) return 'c';
        return if (self.y == 0) 'd' else 'a';
    }
};

fn changeBlocks(allocator: Allocator, first: Lines, second: Lines) ![]ChangeBlock {
    const pairs = try matchedPairs(allocator, first, second);
    var blocks: std.ArrayList(ChangeBlock) = .empty;
    for (pairs[0 .. pairs.len - 1], pairs[1..]) |pair, next| {
        if (next.old - pair.old > 1 or next.new - pair.new > 1) {
            try blocks.append(allocator, .{
                .p = pair.old,
                .q = pair.new,
                .x = next.old - pair.old - 1,
                .y = next.new - pair.new - 1,
            });
        }
    }
    return blocks.items;
}

const Step = struct { old: usize, new: usize, block: ?ChangeBlock };

fn walk(
    allocator: Allocator,
    blocks: []const ChangeBlock,
    old_start: usize,
    new_start: usize,
    old_end: usize,
) ![]Step {
    var steps: std.ArrayList(Step) = .empty;
    var old_index = old_start;
    var new_index = new_start;
    for (blocks) |block| {
        while (old_index < block.p) {
            try steps.append(allocator, .{ .old = old_index, .new = new_index, .block = null });
            old_index += 1;
            new_index += 1;
        }
        try steps.append(allocator, .{ .old = old_index, .new = new_index, .block = block });
        old_index = block.p + block.x;
        new_index = block.q + block.y;
    }
    while (old_index < old_end) {
        try steps.append(allocator, .{ .old = old_index, .new = new_index, .block = null });
        old_index += 1;
        new_index += 1;
    }
    return steps.items;
}

fn writeSideRow(
    out: *std.Io.Writer,
    left: []const u8,
    symbol: u8,
    right: []const u8,
    width: usize,
) !void {
    var buffer: [2 * max_side_width + 3]u8 = undefined;
    const left_part = left[0..@min(width, left.len)];
    const right_part = right[0..@min(width, right.len)];
    @memcpy(buffer[0..left_part.len], left_part);
    @memset(buffer[left_part.len..width], ' ');
    buffer[width] = ' ';
    buffer[width + 1] = symbol;
    buffer[width + 2] = ' ';
    const length = width + 3 + right_part.len;
    @memcpy(buffer[width + 3 .. length], right_part);
    try out.print("{s}\n", .{std.mem.trimEnd(u8, buffer[0..length], " ")});
}

fn writeStatGraph(out: *std.Io.Writer, inserted: usize, deleted: usize) !void {
    const total = inserted + deleted;
    var plus = inserted;
    var minus = deleted;
    if (total > graph_width) {
        plus = graph_width * inserted / total;
        minus = graph_width * deleted / total;
        if (inserted >= 1 and plus == 0) plus = 1;
        if (deleted >= 1 and minus == 0) minus = 1;
    }
    try out.splatByteAll('+', plus);
    try out.splatByteAll('-', minus);
}

const Hunk = struct {
    blocks: []const ChangeBlock,
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,

    fn init(blocks: []const ChangeBlock, context: usize, old_total: usize) Hunk {
        const first = blocks[0];
        const last = blocks[blocks.len - 1];
        const before = @min(context, first.p);
        const after = @min(context, old_total - last.p - last.x);
        const old_start = first.p - before;
        const new_start = first.q - before;
        return .{
            .blocks = blocks,
            .old_start = old_start,
            .old_count = last.p + last.x + after - old_start,
            .new_start = new_start,
            .new_count = last.q + last.y + after - new_start,
        };
    }

    fn steps(self: Hunk, allocator: Allocator) ![]Step {
        const old_end = self.old_start + self.old_count;
        return walk(allocator, self.blocks, self.old_start, self.new_start, old_end);
    }
};

const LineDiff = struct {
    old: Lines,
    new: Lines,
    blocks: []const ChangeBlock,

    fn init(allocator: Allocator, old: Lines, new: Lines, options: CompareOptions) !LineDiff {
        const old_keys = try comparisonKeys(allocator, old, options);
        const new_keys = try comparisonKeys(allocator, new, options);
        const blocks = try changeBlocks(allocator, old_keys, new_keys);
        return .{ .old = old, .new = new, .blocks = blocks };
    }

    fn deleted(self: LineDiff, block: ChangeBlock) Lines {
        return self.old[block.p .. block.p + block.x];
    }

    fn inserted(self: LineDiff, block: ChangeBlock) Lines {
        return self.new[block.q .. block.q + block.y];
    }

    fn hunks(self: LineDiff, allocator: Allocator, context: usize) ![]Hunk {
        var groups: std.ArrayList(Hunk) = .empty;
        var first: usize = 0;
        for (1..self.blocks.len + 1) |index| {
            const last = self.blocks[index - 1];
            const ends_group = index == self.blocks.len or
                self.blocks[index].p - (last.p + last.x) > 2 * context;
            if (ends_group) {
                const group = self.blocks[first..index];
                try groups.append(allocator, Hunk.init(group, context, self.old.len));
                first = index;
            }
        }
        return groups.items;
    }

    fn writeNormal(self: LineDiff, out: *std.Io.Writer) !void {
        for (self.blocks) |block| {
            const letter = block.letter();
            const old_range = rangeR(block.p, block.x);
            const new_range = rangeR(block.q, block.y);
            try out.print("{f}{c}{f}\n", .{ old_range, letter, new_range });
            try writeLines(out, "< ", self.deleted(block));
            if (letter == 'c') try out.writeAll("---\n");
            try writeLines(out, "> ", self.inserted(block));
        }
    }

    fn writeEd(self: LineDiff, out: *std.Io.Writer) !void {
        var index = self.blocks.len;
        while (index > 0) {
            index -= 1;
            const block = self.blocks[index];
            const letter = block.letter();
            try out.print("{f}{c}\n", .{ rangeR(block.p, block.x), letter });
            if (letter != 'd') {
                try writeLines(out, "", self.inserted(block));
                try out.writeAll(".\n");
            }
        }
    }

    fn writeRcs(self: LineDiff, out: *std.Io.Writer) !void {
        for (self.blocks) |block| {
            if (block.x >= 1) try out.print("d{d} {d}\n", .{ block.p + 1, block.x });
            if (block.y >= 1) {
                try out.print("a{d} {d}\n", .{ block.p + block.x, block.y });
                try writeLines(out, "", self.inserted(block));
            }
        }
    }

    fn writeIfdef(
        self: LineDiff,
        allocator: Allocator,
        out: *std.Io.Writer,
        macro: []const u8,
    ) !void {
        for (try walk(allocator, self.blocks, 0, 0, self.old.len)) |step| {
            const block = step.block orelse {
                try out.print("{s}\n", .{self.old[step.old]});
                continue;
            };
            if (block.x >= 1 and block.y >= 1) {
                try out.print("#ifndef {s}\n", .{macro});
                try writeLines(out, "", self.deleted(block));
                try out.print("#else /* {s} */\n", .{macro});
                try writeLines(out, "", self.inserted(block));
                try out.print("#endif /* {s} */\n", .{macro});
            } else if (block.y == 0) {
                try out.print("#ifndef {s}\n", .{macro});
                try writeLines(out, "", self.deleted(block));
                try out.print("#endif /* ! {s} */\n", .{macro});
            } else {
                try out.print("#ifdef {s}\n", .{macro});
                try writeLines(out, "", self.inserted(block));
                try out.print("#endif /* {s} */\n", .{macro});
            }
        }
    }

    fn writeUnified(
        self: LineDiff,
        allocator: Allocator,
        out: *std.Io.Writer,
        context: usize,
        old_name: []const u8,
        new_name: []const u8,
    ) !void {
        try out.print("--- {s}\n+++ {s}\n", .{ old_name, new_name });
        for (try self.hunks(allocator, context)) |hunk| {
            try out.print("@@ -{f} +{f} @@\n", .{
                rangeU(hunk.old_start, hunk.old_count),
                rangeU(hunk.new_start, hunk.new_count),
            });
            for (try hunk.steps(allocator)) |step| {
                if (step.block) |block| {
                    try writeLines(out, "-", self.deleted(block));
                    try writeLines(out, "+", self.inserted(block));
                } else {
                    try out.print(" {s}\n", .{self.old[step.old]});
                }
            }
        }
    }

    fn writeContext(
        self: LineDiff,
        allocator: Allocator,
        out: *std.Io.Writer,
        context: usize,
        old_name: []const u8,
        new_name: []const u8,
    ) !void {
        try out.print("*** {s}\n--- {s}\n", .{ old_name, new_name });
        for (try self.hunks(allocator, context)) |hunk| {
            const steps = try hunk.steps(allocator);
            var deletions = false;
            var insertions = false;
            for (hunk.blocks) |block| {
                deletions = deletions or block.x >= 1;
                insertions = insertions or block.y >= 1;
            }
            const old_range = rangeR(hunk.old_start, hunk.old_count);
            try out.print("***************\n*** {f} ****\n", .{old_range});
            if (deletions) {
                for (steps) |step| {
                    if (step.block) |block| {
                        try writeLines(out, if (block.y >= 1) "! " else "- ", self.deleted(block));
                    } else {
                        try out.print("  {s}\n", .{self.old[step.old]});
                    }
                }
            }
            try out.print("--- {f} ----\n", .{rangeR(hunk.new_start, hunk.new_count)});
            if (insertions) {
                for (steps) |step| {
                    if (step.block) |block| {
                        try writeLines(out, if (block.x >= 1) "! " else "+ ", self.inserted(block));
                    } else {
                        try out.print("  {s}\n", .{self.new[step.new]});
                    }
                }
            }
        }
    }

    fn writeSideBySide(
        self: LineDiff,
        allocator: Allocator,
        out: *std.Io.Writer,
        width: usize,
    ) !void {
        for (try walk(allocator, self.blocks, 0, 0, self.old.len)) |step| {
            const block = step.block orelse {
                try writeSideRow(out, self.old[step.old], ' ', self.new[step.new], width);
                continue;
            };
            for (0..@max(block.x, block.y)) |row| {
                const left = if (row < block.x) self.old[block.p + row] else "";
                const right = if (row < block.y) self.new[block.q + row] else "";
                const symbol: u8 = if (row >= block.y) '<' else if (row >= block.x) '>' else '|';
                try writeSideRow(out, left, symbol, right, width);
            }
        }
    }
};

const TokenTotals = struct {
    deleted: usize = 0,
    inserted: usize = 0,
    common: usize = 0,
};

fn splitTokens(allocator: Allocator, line: []const u8, by_word: bool) !Lines {
    var tokens: std.ArrayList([]const u8) = .empty;
    if (by_word) {
        var words = std.mem.tokenizeScalar(u8, line, ' ');
        while (words.next()) |word| try tokens.append(allocator, word);
    } else {
        for (0..line.len) |i| try tokens.append(allocator, line[i .. i + 1]);
    }
    return tokens.items;
}

fn deletion(allocator: Allocator, tokens: Lines, separator: []const u8) ![]const u8 {
    const joined = try std.mem.join(allocator, separator, tokens);
    return std.mem.concat(allocator, u8, &.{ "[-", joined, "-]" });
}

fn insertion(allocator: Allocator, tokens: Lines, separator: []const u8) ![]const u8 {
    const joined = try std.mem.join(allocator, separator, tokens);
    return std.mem.concat(allocator, u8, &.{ "{+", joined, "+}" });
}

fn compareTokens(
    allocator: Allocator,
    old_tokens: Lines,
    new_tokens: Lines,
    separator: []const u8,
    totals: *TokenTotals,
) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    const blocks = try changeBlocks(allocator, old_tokens, new_tokens);
    for (try walk(allocator, blocks, 0, 0, old_tokens.len)) |step| {
        const block = step.block orelse {
            try parts.append(allocator, old_tokens[step.old]);
            totals.common += 1;
            continue;
        };
        if (block.x >= 1) {
            const tokens = old_tokens[block.p .. block.p + block.x];
            try parts.append(allocator, try deletion(allocator, tokens, separator));
        }
        if (block.y >= 1) {
            const tokens = new_tokens[block.q .. block.q + block.y];
            try parts.append(allocator, try insertion(allocator, tokens, separator));
        }
        totals.deleted += block.x;
        totals.inserted += block.y;
    }
    return std.mem.join(allocator, separator, parts.items);
}

const BodyLine = struct { kind: u8, text: []const u8 };

const Sequences = struct { old: Lines, new: Lines };

const PatchHunk = struct {
    line_number: usize,
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    body: []const BodyLine = &.{},

    fn sequences(self: PatchHunk, allocator: Allocator, reverse: bool) !Sequences {
        const removed: u8 = if (reverse) '+' else '-';
        const added: u8 = if (reverse) '-' else '+';
        var old: std.ArrayList([]const u8) = .empty;
        var new: std.ArrayList([]const u8) = .empty;
        for (self.body) |line| {
            if (line.kind != added) try old.append(allocator, line.text);
            if (line.kind != removed) try new.append(allocator, line.text);
        }
        return .{ .old = old.items, .new = new.items };
    }

    fn start(self: PatchHunk, reverse: bool) usize {
        return if (reverse) self.new_start else self.old_start;
    }

    fn leadingContext(self: PatchHunk) usize {
        var count: usize = 0;
        while (count < self.body.len and self.body[count].kind == ' ') count += 1;
        return count;
    }

    fn trailingContext(self: PatchHunk) usize {
        var count: usize = 0;
        while (count < self.body.len and self.body[self.body.len - 1 - count].kind == ' ') {
            count += 1;
        }
        return count;
    }
};

const HunkMatch = struct {
    fuzz: usize,
    delta: isize,
    position: usize,
    lines: Lines,

    fn writeReport(self: HunkMatch, out: *std.Io.Writer, number: usize) !void {
        try out.print("Hunk #{d} succeeded at {d}", .{ number, self.position + 1 });
        if (self.fuzz >= 1) try out.print(" with fuzz {d}", .{self.fuzz});
        if (self.delta == 1 or self.delta == -1) {
            try out.print(" (offset {d} line)", .{self.delta});
        } else if (self.delta != 0) {
            try out.print(" (offset {d} lines)", .{self.delta});
        }
        try out.writeByte('\n');
    }
};

const NumberPair = struct { first: usize, second: ?usize };

fn parseNumber(text: []const u8) ?usize {
    if (text.len < 1 or text.len > 4) return null;
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return null;
    }
    return std.fmt.parseInt(usize, text, 10) catch null;
}

fn parseNumberPair(text: []const u8) ?NumberPair {
    var parts = std.mem.splitScalar(u8, text, ',');
    const first = parseNumber(parts.next().?) orelse return null;
    const second_text = parts.next() orelse return .{ .first = first, .second = null };
    if (parts.next() != null) return null;
    return .{ .first = first, .second = parseNumber(second_text) orelse return null };
}

const HunkRange = struct { start: usize, count: usize };

fn parseRange(text: []const u8, sign: u8) ?HunkRange {
    if (text.len == 0 or text[0] != sign) return null;
    const pair = parseNumberPair(text[1..]) orelse return null;
    const count = pair.second orelse 1;
    if (pair.first == 0 and count != 0) return null;
    return .{ .start = pair.first, .count = count };
}

fn parseHunkHeader(
    allocator: Allocator,
    out: *std.Io.Writer,
    line: []const u8,
    line_number: usize,
) Error!PatchHunk {
    const parts = try splitWords(allocator, line);
    if (parts.len == 4 and std.mem.eql(u8, parts[0], "@@") and std.mem.eql(u8, parts[3], "@@")) {
        if (parseRange(parts[1], '-')) |old_range| {
            if (parseRange(parts[2], '+')) |new_range| {
                return .{
                    .line_number = line_number,
                    .old_start = old_range.start,
                    .old_count = old_range.count,
                    .new_start = new_range.start,
                    .new_count = new_range.count,
                };
            }
        }
    }
    return fail(out, "PATCH ERROR line {d}: bad hunk header", .{line_number});
}

fn parsePatch(allocator: Allocator, out: *std.Io.Writer, patch_lines: Lines) Error![]PatchHunk {
    var index: usize = 0;
    while (index < patch_lines.len and !std.mem.startsWith(u8, patch_lines[index], "@@")) {
        index += 1;
    }
    if (index == patch_lines.len) return fail(out, "PATCH ERROR no hunks", .{});
    var hunks: std.ArrayList(PatchHunk) = .empty;
    while (index < patch_lines.len) {
        var hunk = try parseHunkHeader(allocator, out, patch_lines[index], index + 1);
        index += 1;
        var body: std.ArrayList(BodyLine) = .empty;
        var old_seen: usize = 0;
        var new_seen: usize = 0;
        while (old_seen < hunk.old_count or new_seen < hunk.new_count) {
            if (index == patch_lines.len)
                return fail(out, "PATCH ERROR line {d}: truncated hunk", .{hunk.line_number});
            const line = patch_lines[index];
            const kind = line[0];
            const in_old = kind == ' ' or kind == '-';
            const in_new = kind == ' ' or kind == '+';
            const old_full = in_old and old_seen == hunk.old_count;
            const new_full = in_new and new_seen == hunk.new_count;
            if (line.len < 2 or !(in_old or in_new) or old_full or new_full)
                return fail(out, "PATCH ERROR line {d}: bad hunk line", .{index + 1});
            try body.append(allocator, .{ .kind = kind, .text = line[1..] });
            if (in_old) old_seen += 1;
            if (in_new) new_seen += 1;
            index += 1;
        }
        hunk.body = body.items;
        for (hunk.body) |line| {
            if (line.kind != ' ') break;
        } else return fail(out, "PATCH ERROR line {d}: no changes", .{hunk.line_number});
        try hunks.append(allocator, hunk);
    }
    return hunks.items;
}

fn searchHunk(
    allocator: Allocator,
    hunk: PatchHunk,
    lines: Lines,
    adjustment: isize,
    reverse: bool,
    max_fuzz: usize,
) !?HunkMatch {
    const sequences = try hunk.sequences(allocator, reverse);
    const old = sequences.old;
    const new = sequences.new;
    const start: isize = @intCast(hunk.start(reverse));
    const expected = if (old.len > 0) start - 1 + adjustment else start + adjustment;
    const leading = hunk.leadingContext();
    const trailing = hunk.trailingContext();
    for (0..max_fuzz + 1) |fuzz| {
        const head = @min(fuzz, leading);
        const tail = @min(fuzz, trailing);
        const old_part = old[head .. old.len - tail];
        const new_part = new[head .. new.len - tail];
        for (offsets) |delta| {
            const signed_position = expected + @as(isize, @intCast(head)) + delta;
            if (signed_position < 0) continue;
            const position: usize = @intCast(signed_position);
            const end = position + old_part.len;
            if (end > lines.len or !linesEqual(lines[position..end], old_part)) continue;
            return .{
                .fuzz = fuzz,
                .delta = delta,
                .position = position,
                .lines = try std.mem.concat(allocator, []const u8, &.{
                    lines[0..position],
                    new_part,
                    lines[end..],
                }),
            };
        }
    }
    return null;
}

const EditCommand = struct { instruction: u8, first: usize, last: usize };

fn parseEditCommand(line: []const u8) ?EditCommand {
    const instruction = line[line.len - 1];
    const pair = parseNumberPair(line[0 .. line.len - 1]) orelse return null;
    if (instruction != 'a' and instruction != 'c' and instruction != 'd') return null;
    if (instruction == 'a' and pair.second != null) return null;
    return .{
        .instruction = instruction,
        .first = pair.first,
        .last = pair.second orelse pair.first,
    };
}

const EditResult = struct { lines: Lines, executed: usize };

fn runEditScript(
    allocator: Allocator,
    out: *std.Io.Writer,
    original: Lines,
    script: Lines,
) Error!EditResult {
    var lines: std.ArrayList([]const u8) = .empty;
    try lines.appendSlice(allocator, original);
    var executed: usize = 0;
    var index: usize = 0;
    while (index < script.len) {
        const line_number = index + 1;
        const command = parseEditCommand(script[index]) orelse
            return fail(out, "EDIT ERROR line {d}: bad command", .{line_number});
        const line_count = lines.items.len;
        const valid = if (command.instruction == 'a')
            command.first <= line_count
        else
            1 <= command.first and command.first <= command.last and command.last <= line_count;
        if (!valid) return fail(out, "EDIT ERROR line {d}: bad range", .{line_number});
        index += 1;
        var text: Lines = &.{};
        if (command.instruction != 'd') {
            var end = index;
            while (end < script.len and !std.mem.eql(u8, script[end], ".")) end += 1;
            if (end == script.len)
                return fail(out, "EDIT ERROR line {d}: missing terminator", .{line_number});
            text = script[index..end];
            index = end + 1;
        }
        if (command.instruction == 'a') {
            try lines.insertSlice(allocator, command.first, text);
        } else {
            const count = command.last - command.first + 1;
            try lines.replaceRange(allocator, command.first - 1, count, text);
        }
        executed += 1;
    }
    return .{ .lines = lines.items, .executed = executed };
}

const ChunkKind = enum { stable, a, b, both, conflict };

const Location = struct {
    base: Range,
    ours: Range,
    theirs: Range,

    pub fn format(self: Location, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return writer.print("base {f} a {f} b {f}", .{ self.base, self.ours, self.theirs });
    }
};

const Chunk = struct {
    kind: ChunkKind,
    base_start: usize,
    ours_start: usize,
    theirs_start: usize,
    base: Lines,
    ours: Lines,
    theirs: Lines,

    fn location(self: Chunk) Location {
        return .{
            .base = rangeM(self.base_start, self.base.len),
            .ours = rangeM(self.ours_start, self.ours.len),
            .theirs = rangeM(self.theirs_start, self.theirs.len),
        };
    }
};

fn chunkKind(base: Lines, ours: Lines, theirs: Lines) ChunkKind {
    if (linesEqual(ours, base)) return .b;
    if (linesEqual(theirs, base)) return .a;
    if (linesEqual(ours, theirs)) return .both;
    return .conflict;
}

fn matchTable(allocator: Allocator, first: Lines, second: Lines) ![]usize {
    const matches = try allocator.alloc(usize, first.len + 2);
    @memset(matches, 0);
    const pairs = try matchedPairs(allocator, first, second);
    for (pairs[1 .. pairs.len - 1]) |pair| matches[pair.old] = pair.new;
    return matches;
}

fn threeWayChunks(allocator: Allocator, base: Lines, ours: Lines, theirs: Lines) ![]Chunk {
    const ours_match = try matchTable(allocator, base, ours);
    const theirs_match = try matchTable(allocator, base, theirs);
    var chunks: std.ArrayList(Chunk) = .empty;
    var x: usize = 0;
    var y: usize = 0;
    var z: usize = 0;
    while (x < base.len or y < ours.len or z < theirs.len) {
        if (x < base.len and ours_match[x + 1] == y + 1 and theirs_match[x + 1] == z + 1) {
            try chunks.append(allocator, .{
                .kind = .stable,
                .base_start = x,
                .ours_start = y,
                .theirs_start = z,
                .base = base[x .. x + 1],
                .ours = ours[y .. y + 1],
                .theirs = theirs[z .. z + 1],
            });
            x += 1;
            y += 1;
            z += 1;
            continue;
        }
        var anchor = x + 1;
        while (anchor <= base.len and (ours_match[anchor] == 0 or theirs_match[anchor] == 0)) {
            anchor += 1;
        }
        var next_x = base.len;
        var next_y = ours.len;
        var next_z = theirs.len;
        if (anchor <= base.len) {
            next_x = anchor - 1;
            next_y = ours_match[anchor] - 1;
            next_z = theirs_match[anchor] - 1;
        }
        const base_part = base[x..next_x];
        const ours_part = ours[y..next_y];
        const theirs_part = theirs[z..next_z];
        try chunks.append(allocator, .{
            .kind = chunkKind(base_part, ours_part, theirs_part),
            .base_start = x,
            .ours_start = y,
            .theirs_start = z,
            .base = base_part,
            .ours = ours_part,
            .theirs = theirs_part,
        });
        x = next_x;
        y = next_y;
        z = next_z;
    }
    return chunks.items;
}

const KindCounts = struct {
    a: usize = 0,
    b: usize = 0,
    both: usize = 0,
    conflict: usize = 0,

    fn of(chunks: []const Chunk) KindCounts {
        var counts: KindCounts = .{};
        for (chunks) |chunk| {
            switch (chunk.kind) {
                .stable => {},
                .a => counts.a += 1,
                .b => counts.b += 1,
                .both => counts.both += 1,
                .conflict => counts.conflict += 1,
            }
        }
        return counts;
    }

    pub fn format(self: KindCounts, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return writer.print("a={d} b={d} both={d} conflicts={d}", .{
            self.a,
            self.b,
            self.both,
            self.conflict,
        });
    }
};

fn commonPrefixLength(first: Lines, second: Lines) usize {
    var length: usize = 0;
    while (length < first.len and length < second.len and
        std.mem.eql(u8, first[length], second[length]))
    {
        length += 1;
    }
    return length;
}

fn commonSuffixLength(first: Lines, second: Lines, limit: usize) usize {
    var length: usize = 0;
    while (length < limit and
        std.mem.eql(u8, first[first.len - 1 - length], second[second.len - 1 - length]))
    {
        length += 1;
    }
    return length;
}

fn conflictLines(
    allocator: Allocator,
    chunk: Chunk,
    mode: []const u8,
    base_name: []const u8,
    ours_name: []const u8,
    theirs_name: []const u8,
) !Lines {
    if (std.mem.eql(u8, mode, "OURS")) return chunk.ours;
    if (std.mem.eql(u8, mode, "THEIRS")) return chunk.theirs;
    const start_marker = try std.fmt.allocPrint(allocator, "<<<<<<< {s}", .{ours_name});
    const end_marker = try std.fmt.allocPrint(allocator, ">>>>>>> {s}", .{theirs_name});
    if (std.mem.eql(u8, mode, "DIFF3")) {
        const base_marker = try std.fmt.allocPrint(allocator, "||||||| {s}", .{base_name});
        return std.mem.concat(allocator, []const u8, &.{
            &.{start_marker},
            chunk.ours,
            &.{base_marker},
            chunk.base,
            &.{separator_marker},
            chunk.theirs,
            &.{end_marker},
        });
    }
    const ours = chunk.ours;
    const theirs = chunk.theirs;
    const head = commonPrefixLength(ours, theirs);
    const tail = commonSuffixLength(ours, theirs, @min(ours.len, theirs.len) - head);
    const ours_middle = ours[head .. ours.len - tail];
    const theirs_middle = theirs[head .. theirs.len - tail];
    const middle = if (std.mem.eql(u8, mode, "UNION"))
        try std.mem.concat(allocator, []const u8, &.{ ours_middle, theirs_middle })
    else
        try std.mem.concat(allocator, []const u8, &.{
            &.{start_marker},
            ours_middle,
            &.{separator_marker},
            theirs_middle,
            &.{end_marker},
        });
    return std.mem.concat(allocator, []const u8, &.{
        ours[0..head],
        middle,
        ours[ours.len - tail ..],
    });
}

const Marker = enum { none, start, base, separator, end };

fn markerKind(line: []const u8) Marker {
    if (std.mem.eql(u8, line, separator_marker)) return .separator;
    if (line.len < 7 or (line.len > 7 and line[7] != ' ')) return .none;
    const prefix = line[0..7];
    if (std.mem.eql(u8, prefix, "<<<<<<<")) return .start;
    if (std.mem.eql(u8, prefix, "|||||||")) return .base;
    if (std.mem.eql(u8, prefix, ">>>>>>>")) return .end;
    return .none;
}

fn nextMarker(lines: Lines, index: usize) usize {
    var next = index + 1;
    while (next < lines.len and markerKind(lines[next]) == .none) next += 1;
    return next;
}

const ConflictRegion = struct {
    start: usize,
    end: usize,
    ours: Lines,
    base: ?Lines,
    theirs: Lines,

    fn part(self: ConflictRegion, allocator: Allocator, side: []const u8) !Lines {
        if (std.mem.eql(u8, side, "OURS")) return self.ours;
        if (std.mem.eql(u8, side, "THEIRS")) return self.theirs;
        if (std.mem.eql(u8, side, "BASE")) return self.base.?;
        return std.mem.concat(allocator, []const u8, &.{ self.ours, self.theirs });
    }
};

fn regionAt(lines: Lines, start: usize) ?ConflictRegion {
    if (markerKind(lines[start]) != .start) return null;
    var middle = nextMarker(lines, start);
    var base_marker: ?usize = null;
    if (middle < lines.len and markerKind(lines[middle]) == .base) {
        base_marker = middle;
        middle = nextMarker(lines, middle);
    }
    if (middle == lines.len or markerKind(lines[middle]) != .separator) return null;
    const end = nextMarker(lines, middle);
    if (end == lines.len or markerKind(lines[end]) != .end) return null;
    return .{
        .start = start + 1,
        .end = end + 1,
        .ours = lines[start + 1 .. base_marker orelse middle],
        .base = if (base_marker) |marker| lines[marker + 1 .. middle] else null,
        .theirs = lines[middle + 1 .. end],
    };
}

fn conflictRegions(allocator: Allocator, lines: Lines) ![]ConflictRegion {
    var regions: std.ArrayList(ConflictRegion) = .empty;
    var index: usize = 0;
    while (index < lines.len) {
        if (regionAt(lines, index)) |region| {
            try regions.append(allocator, region);
            index = region.end;
        } else {
            index += 1;
        }
    }
    return regions.items;
}

const Entry = struct {
    name: []const u8,
    content: ?Lines,
    history: std.ArrayList(?Lines),
};

fn entryLess(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

const Workspace = struct {
    storage: Allocator,
    out: *std.Io.Writer,
    entries: std.ArrayList(Entry) = .empty,

    fn find(self: *Workspace, name: []const u8) ?*Entry {
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
    }

    fn require(self: *Workspace, name: []const u8) Error!Lines {
        if (self.find(name)) |entry| {
            if (entry.content) |content| return content;
        }
        return fail(self.out, "ERROR no such file {s}", .{name});
    }

    fn save(self: *Workspace, name: []const u8, lines: Lines) Allocator.Error!void {
        const content = try self.storage.alloc([]const u8, lines.len);
        for (content, lines) |*owned, line| owned.* = try self.storage.dupe(u8, line);
        const entry = self.find(name) orelse blk: {
            const created = try self.entries.addOne(self.storage);
            created.* = .{
                .name = try self.storage.dupe(u8, name),
                .content = null,
                .history = .empty,
            };
            break :blk created;
        };
        try entry.history.append(self.storage, entry.content);
        entry.content = content;
    }

    fn loadFile(self: *Workspace, arguments: Lines, data: Lines) Error!void {
        const name = arguments[0];
        try self.save(name, data);
        try self.out.print("FILE {s} lines={d}\n", .{ name, data.len });
    }

    fn copy(self: *Workspace, arguments: Lines) Error!void {
        const source = arguments[0];
        const target = arguments[1];
        const lines = try self.require(source);
        try self.save(target, lines);
        try self.out.print("COPY {s} {s} lines={d}\n", .{ source, target, lines.len });
    }

    fn printFile(self: *Workspace, arguments: Lines) Error!void {
        const name = arguments[0];
        const lines = try self.require(name);
        try self.out.print("PRINT {s} lines={d}\n", .{ name, lines.len });
        for (lines, 1..) |line, number| try self.out.print("{d: >3}| {s}\n", .{ number, line });
    }

    fn listFiles(self: *Workspace) Error!void {
        std.mem.sort(Entry, self.entries.items, {}, entryLess);
        var count: usize = 0;
        for (self.entries.items) |entry| {
            if (entry.content != null) count += 1;
        }
        try self.out.print("FILES count={d}\n", .{count});
        for (self.entries.items) |entry| {
            const content = entry.content orelse continue;
            try self.out.print("{s} lines={d} undo={d}\n", .{
                entry.name,
                content.len,
                entry.history.items.len,
            });
        }
    }

    fn undo(self: *Workspace, arguments: Lines) Error!void {
        const name = arguments[0];
        const entry = self.find(name) orelse
            return fail(self.out, "ERROR nothing to undo {s}", .{name});
        const state = entry.history.pop() orelse
            return fail(self.out, "ERROR nothing to undo {s}", .{name});
        entry.content = state;
        if (state) |lines| {
            try self.out.print("UNDO {s} lines={d}\n", .{ name, lines.len });
        } else {
            try self.out.print("UNDO {s} removed\n", .{name});
        }
    }

    fn diff(self: *Workspace, allocator: Allocator, arguments: Lines) Error!void {
        const old_name = arguments[0];
        const new_name = arguments[1];
        const form = arguments[2];
        const old = try self.require(old_name);
        const new = try self.require(new_name);
        const has_parameter = contains(&formats_with_argument, form);
        const parameter = if (has_parameter) arguments[3] else "";
        const option_start: usize = if (has_parameter) 4 else 3;
        const options = CompareOptions.parse(arguments[option_start..]);
        const line_diff = try LineDiff.init(allocator, old, new, options);
        if (line_diff.blocks.len == 0) {
            try self.out.print("Files {s} and {s} are identical\n", .{ old_name, new_name });
        } else if (std.mem.eql(u8, form, "BRIEF")) {
            try self.out.print("Files {s} and {s} differ\n", .{ old_name, new_name });
        } else if (std.mem.eql(u8, form, "NORMAL")) {
            try line_diff.writeNormal(self.out);
        } else if (std.mem.eql(u8, form, "ED")) {
            try line_diff.writeEd(self.out);
        } else if (std.mem.eql(u8, form, "RCS")) {
            try line_diff.writeRcs(self.out);
        } else if (std.mem.eql(u8, form, "IFDEF")) {
            try line_diff.writeIfdef(allocator, self.out, parameter);
        } else if (std.mem.eql(u8, form, "UNIFIED")) {
            const context = try std.fmt.parseInt(usize, parameter, 10);
            try line_diff.writeUnified(allocator, self.out, context, old_name, new_name);
        } else if (std.mem.eql(u8, form, "CONTEXT")) {
            const context = try std.fmt.parseInt(usize, parameter, 10);
            try line_diff.writeContext(allocator, self.out, context, old_name, new_name);
        } else {
            const width = try std.fmt.parseInt(usize, parameter, 10);
            try line_diff.writeSideBySide(allocator, self.out, width);
        }
    }

    fn tokenDiff(
        self: *Workspace,
        allocator: Allocator,
        arguments: Lines,
        by_word: bool,
    ) Error!void {
        const old_name = arguments[0];
        const new_name = arguments[1];
        const old = try self.require(old_name);
        const new = try self.require(new_name);
        const line_diff = try LineDiff.init(allocator, old, new, .{});
        if (line_diff.blocks.len == 0) {
            try self.out.print("Files {s} and {s} are identical\n", .{ old_name, new_name });
            return;
        }
        const separator: []const u8 = if (by_word) " " else "";
        var totals: TokenTotals = .{};
        for (line_diff.blocks) |block| {
            for (0..@max(block.x, block.y)) |row| {
                const old_number = block.p + row + 1;
                const new_number = block.q + row + 1;
                if (row < block.x and row < block.y) {
                    const old_tokens = try splitTokens(allocator, old[old_number - 1], by_word);
                    const new_tokens = try splitTokens(allocator, new[new_number - 1], by_word);
                    const text = try compareTokens(
                        allocator,
                        old_tokens,
                        new_tokens,
                        separator,
                        &totals,
                    );
                    try self.out.print("a{d} b{d}: {s}\n", .{ old_number, new_number, text });
                } else if (row < block.x) {
                    const old_tokens = try splitTokens(allocator, old[old_number - 1], by_word);
                    totals.deleted += old_tokens.len;
                    const text = try deletion(allocator, old_tokens, separator);
                    try self.out.print("a{d}: {s}\n", .{ old_number, text });
                } else {
                    const new_tokens = try splitTokens(allocator, new[new_number - 1], by_word);
                    totals.inserted += new_tokens.len;
                    const text = try insertion(allocator, new_tokens, separator);
                    try self.out.print("b{d}: {s}\n", .{ new_number, text });
                }
            }
        }
        const label = if (by_word) "WORDS" else "CHARS";
        try self.out.print("{s} deleted={d} inserted={d} common={d}\n", .{
            label,
            totals.deleted,
            totals.inserted,
            totals.common,
        });
    }

    fn stat(self: *Workspace, allocator: Allocator, arguments: Lines) Error!void {
        const old_name = arguments[0];
        const new_name = arguments[1];
        const old = try self.require(old_name);
        const new = try self.require(new_name);
        const options = CompareOptions.parse(arguments[2..]);
        const line_diff = try LineDiff.init(allocator, old, new, options);
        var deleted: usize = 0;
        var inserted: usize = 0;
        for (line_diff.blocks) |block| {
            deleted += block.x;
            inserted += block.y;
        }
        const total = deleted + inserted;
        const unchanged = old.len - deleted;
        try self.out.print("{s} -> {s} | {d}", .{ old_name, new_name, total });
        if (total > 0) {
            try self.out.writeByte(' ');
            try writeStatGraph(self.out, inserted, deleted);
        }
        try self.out.writeByte('\n');
        const line_total = old.len + new.len;
        const similarity = if (line_total > 0) 200 * unchanged / line_total else 100;
        try self.out.print(
            "changes={d} insertions={d} deletions={d} unchanged={d} similarity={d}%\n",
            .{ line_diff.blocks.len, inserted, deleted, unchanged, similarity },
        );
    }

    fn patch(self: *Workspace, allocator: Allocator, arguments: Lines, data: Lines) Error!void {
        const name = arguments[0];
        var lines = try self.require(name);
        const options = arguments[2..];
        const reverse = contains(options, "REVERSE");
        const dry_run = contains(options, "DRYRUN");
        var max_fuzz: usize = 0;
        for (options, 0..) |option, index| {
            if (std.mem.eql(u8, option, "FUZZ"))
                max_fuzz = try std.fmt.parseInt(usize, options[index + 1], 10);
        }
        const hunks = try parsePatch(allocator, self.out, data);
        try self.out.print("{s} file {s}\n", .{ if (dry_run) "checking" else "patching", name });
        const first = hunks[0];
        if ((try searchHunk(allocator, first, lines, 0, reverse, max_fuzz)) == null and
            (try searchHunk(allocator, first, lines, 0, !reverse, max_fuzz)) != null)
        {
            try self.out.writeAll("Reversed (or previously applied) patch detected! Skipping patch.\n");
            try self.out.print(
                "RESULT applied=0 failed=0 ignored={d} lines={d}\n",
                .{ hunks.len, lines.len },
            );
            return;
        }
        var adjustment: isize = 0;
        var applied: usize = 0;
        var failed: usize = 0;
        for (hunks, 1..) |hunk, number| {
            const found = try searchHunk(allocator, hunk, lines, adjustment, reverse, max_fuzz);
            const match = found orelse {
                failed += 1;
                try self.out.print("Hunk #{d} FAILED at {d}\n", .{ number, hunk.start(reverse) });
                continue;
            };
            const sequences = try hunk.sequences(allocator, reverse);
            lines = match.lines;
            adjustment += match.delta + @as(isize, @intCast(sequences.new.len)) -
                @as(isize, @intCast(sequences.old.len));
            applied += 1;
            try match.writeReport(self.out, number);
        }
        try self.out.print(
            "RESULT applied={d} failed={d} ignored=0 lines={d}\n",
            .{ applied, failed, lines.len },
        );
        if (!dry_run and applied >= 1) try self.save(name, lines);
    }

    fn edit(self: *Workspace, allocator: Allocator, arguments: Lines, data: Lines) Error!void {
        const name = arguments[0];
        const result = try runEditScript(allocator, self.out, try self.require(name), data);
        try self.out.print(
            "EDIT {s} commands={d} lines={d}\n",
            .{ name, result.executed, result.lines.len },
        );
        try self.save(name, result.lines);
    }

    fn threeWay(self: *Workspace, allocator: Allocator, arguments: Lines) Error![]Chunk {
        const base = try self.require(arguments[0]);
        const ours = try self.require(arguments[1]);
        const theirs = try self.require(arguments[2]);
        return threeWayChunks(allocator, base, ours, theirs);
    }

    fn diff3(self: *Workspace, allocator: Allocator, arguments: Lines) Error!void {
        const chunks = try self.threeWay(allocator, arguments);
        var changes: usize = 0;
        for (chunks) |chunk| {
            if (chunk.kind == .stable) continue;
            changes += 1;
            try self.out.print("==== {s} {f}\n", .{ @tagName(chunk.kind), chunk.location() });
            try writeLines(self.out, "O ", chunk.base);
            if (chunk.kind != .b) try writeLines(self.out, "A ", chunk.ours);
            if (chunk.kind == .b or chunk.kind == .conflict)
                try writeLines(self.out, "B ", chunk.theirs);
        }
        try self.out.print("DIFF3 chunks={d} {f}\n", .{ changes, KindCounts.of(chunks) });
    }

    fn merge(self: *Workspace, allocator: Allocator, arguments: Lines) Error!void {
        const base_name = arguments[0];
        const ours_name = arguments[1];
        const theirs_name = arguments[2];
        const target = arguments[3];
        const mode = if (arguments.len == 5) arguments[4] else "MARKERS";
        const chunks = try self.threeWay(allocator, arguments);
        var result: std.ArrayList([]const u8) = .empty;
        var conflict_chunks: std.ArrayList(Chunk) = .empty;
        for (chunks) |chunk| {
            switch (chunk.kind) {
                .b => try result.appendSlice(allocator, chunk.theirs),
                .conflict => {
                    const lines = try conflictLines(
                        allocator,
                        chunk,
                        mode,
                        base_name,
                        ours_name,
                        theirs_name,
                    );
                    try result.appendSlice(allocator, lines);
                    try conflict_chunks.append(allocator, chunk);
                },
                else => try result.appendSlice(allocator, chunk.ours),
            }
        }
        try self.out.print(
            "MERGE {s} lines={d} {f}\n",
            .{ target, result.items.len, KindCounts.of(chunks) },
        );
        for (conflict_chunks.items, 1..) |chunk, number| {
            try self.out.print("CONFLICT {d} {f}\n", .{ number, chunk.location() });
        }
        try self.save(target, result.items);
    }

    fn conflicts(self: *Workspace, allocator: Allocator, arguments: Lines) Error!void {
        const name = arguments[0];
        const regions = try conflictRegions(allocator, try self.require(name));
        try self.out.print("CONFLICTS {s} count={d}\n", .{ name, regions.len });
        for (regions, 1..) |region, number| {
            try self.out.print(
                "{d}: lines {d}-{d} ours={d} base=",
                .{ number, region.start, region.end, region.ours.len },
            );
            if (region.base) |base| {
                try self.out.print("{d}", .{base.len});
            } else {
                try self.out.writeAll("none");
            }
            try self.out.print(" theirs={d}\n", .{region.theirs.len});
        }
    }

    fn resolve(self: *Workspace, allocator: Allocator, arguments: Lines) Error!void {
        const name = arguments[0];
        const side = arguments[2];
        const lines = try self.require(name);
        const number = try std.fmt.parseInt(usize, arguments[1], 10);
        const regions = try conflictRegions(allocator, lines);
        if (regions.len < number)
            return fail(self.out, "ERROR no conflict {d} in {s}", .{ number, name });
        const region = regions[number - 1];
        if (std.mem.eql(u8, side, "BASE") and region.base == null)
            return fail(self.out, "ERROR no base section in conflict {d}", .{number});
        const content = try std.mem.concat(allocator, []const u8, &.{
            lines[0 .. region.start - 1],
            try region.part(allocator, side),
            lines[region.end..],
        });
        const remaining = (try conflictRegions(allocator, content)).len;
        try self.out.print(
            "RESOLVE {s} {d} {s} lines={d} remaining={d}\n",
            .{ name, number, side, content.len, remaining },
        );
        try self.save(name, content);
    }

    fn execute(self: *Workspace, allocator: Allocator, words: Lines, data: Lines) Error!void {
        const command = words[0];
        const arguments = words[1..];
        if (std.mem.eql(u8, command, "FILE")) return self.loadFile(arguments, data);
        if (std.mem.eql(u8, command, "COPY")) return self.copy(arguments);
        if (std.mem.eql(u8, command, "PRINT")) return self.printFile(arguments);
        if (std.mem.eql(u8, command, "FILES")) return self.listFiles();
        if (std.mem.eql(u8, command, "DIFF")) return self.diff(allocator, arguments);
        if (std.mem.eql(u8, command, "WORDDIFF")) return self.tokenDiff(allocator, arguments, true);
        if (std.mem.eql(u8, command, "CHARDIFF"))
            return self.tokenDiff(allocator, arguments, false);
        if (std.mem.eql(u8, command, "STAT")) return self.stat(allocator, arguments);
        if (std.mem.eql(u8, command, "PATCH")) return self.patch(allocator, arguments, data);
        if (std.mem.eql(u8, command, "EDIT")) return self.edit(allocator, arguments, data);
        if (std.mem.eql(u8, command, "DIFF3")) return self.diff3(allocator, arguments);
        if (std.mem.eql(u8, command, "MERGE")) return self.merge(allocator, arguments);
        if (std.mem.eql(u8, command, "CONFLICTS")) return self.conflicts(allocator, arguments);
        if (std.mem.eql(u8, command, "RESOLVE")) return self.resolve(allocator, arguments);
        return self.undo(arguments);
    }
};

pub fn main(init: std.process.Init) !void {
    const storage = init.arena.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var lines: std.ArrayList([]const u8) = .empty;
    while (try input.interface.takeDelimiter('\n')) |line| {
        try lines.append(storage, try storage.dupe(u8, line));
    }
    var workspace: Workspace = .{ .storage = storage, .out = &output.interface };
    var scratch = std.heap.ArenaAllocator.init(init.gpa);
    defer scratch.deinit();
    const command_count = try std.fmt.parseInt(usize, lines.items[0], 10);
    var position: usize = 1;
    for (0..command_count) |_| {
        _ = scratch.reset(.retain_capacity);
        const allocator = scratch.allocator();
        const words = try splitWords(allocator, lines.items[position]);
        position += 1;
        var data: Lines = &.{};
        if (contains(&data_commands, words[0])) {
            const count = try std.fmt.parseInt(usize, words[2], 10);
            data = lines.items[position .. position + count];
            position += count;
        }
        workspace.execute(allocator, words, data) catch |err| switch (err) {
            error.CommandFailed => {},
            else => return err,
        };
    }
    try output.interface.flush();
}
