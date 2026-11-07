const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(text: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(text, ' ')) |word| if (word.len > 0) append([]const u8, &out, word);
    return out.items;
}
pub fn letter(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}
pub fn lower(text: []const u8) []const u8 {
    const out = dupe(u8, text);
    for (out) |*c| if (c.* >= 'A' and c.* <= 'Z') {
        c.* = c.* - 'A' + 'a';
    };
    return out;
}
pub fn upper(text: []const u8) []const u8 {
    const out = dupe(u8, text);
    for (out) |*c| if (c.* >= 'a' and c.* <= 'z') {
        c.* = c.* - 'a' + 'A';
    };
    return out;
}
pub fn spaces(count: usize) []const u8 {
    const out = alloc(u8, count);
    @memset(out, ' ');
    return out;
}
pub fn rtrim(text: []const u8) []const u8 {
    var end = text.len;
    while (end > 0 and text[end - 1] == ' ') end -= 1;
    return text[0..end];
}
pub fn trim(text: []const u8) []const u8 {
    var first: usize = 0;
    while (first < text.len and text[first] == ' ') first += 1;
    return rtrim(text[first..]);
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn join(values: []const []const u8, delimiter: []const u8) []const u8 {
    var out: Text = .{};
    for (values, 0..) |value, i| out.add("{s}{s}", .{ if (i == 0) "" else delimiter, value });
    return out.value();
}
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub const Params = struct { line_penalty: i64 = 0, hyphen_penalty: i64 = 0, double_hyphen_demerit: i64 = 0,
     final_hyphen_demerit: i64 = 0, fitness_demerit: i64 = 0, overfull_penalty: i64 = 0, left_min: i64 = 0,
     right_min: i64 = 0, orphan_lines: i64 = 0, widow_lines: i64 = 0, underfull_slack: i64 = 0, underfull_page: i64 = 0 };
pub const Kind = enum { paragraph, item, enum_, quote, term, title, author, h1, h2, table, verbatim,
     toc, lot, index, bibliography };
pub fn bodyKind(kind: Kind) bool {
    return kind == .paragraph or kind == .item or kind == .enum_ or kind == .quote or kind == .term;
}
pub const SourceLine = struct { line: usize, text: []const u8 };
pub const Inline = struct { kind: []const u8, text: []const u8, id: ?usize = null };
pub const Block = struct { kind: Kind, line: usize, width: usize, indent: usize, alignment: []const u8,
     text: []const u8 = "", term: []const u8 = "", columns: []const u8 = "", caption: []const u8 = "",
     label: []const u8 = "", number: []const u8 = "", page_break: bool = false, body_number: ?usize = null,
     body: std.ArrayList(SourceLine) = .empty, inner: std.ArrayList(SourceLine) = .empty, tokens: std.ArrayList(Inline) = .empty,
     cells: [][]const []const u8 = &.{} };
pub const Bib = struct { line: usize, key: []const u8, author: []const u8, year: []const u8, title: []const u8,
     base: []const u8 = "", label: []const u8 = "", cited: bool = false };
pub const Warning = struct { line: usize, message: []const u8, sequence: usize };
pub const Document = struct {
    blocks: std.ArrayList(Block) = .empty,
    bibliography: std.ArrayList(Bib) = .empty,
    warnings: std.ArrayList(Warning) = .empty,
    additions: std.ArrayList([]const u8) = .empty,
    width: usize = 60,
    height: usize = 40,
    header: [3][]const u8 = @splat(""),
    footer: [3][]const u8 = @splat(""),
    pub fn warn(self: *Document, line: usize, message: []const u8) void {
        append(Warning, &self.warnings, .{ .line = line, .message = message, .sequence = self.warnings.items.len });
    }
};
const block_names = [_][]const u8{ "title", "author", "h1", "h2", "item", "enum", "quote", "term",
     "table", "verbatim", "toc", "lot", "index", "bibliography" };
const block_kinds = [_]Kind{ .title, .author, .h1, .h2, .item, .enum_, .quote, .term, .table, .verbatim,
     .toc, .lot, .index, .bibliography };
fn blockKind(name: []const u8) ?Kind {
    for (block_names, block_kinds) |text, kind| if (eq(text, name)) return kind;
    return null;
}
fn digits(text: []const u8, minimum: usize, maximum: usize) bool {
    if (text.len < minimum or text.len > maximum) return false;
    for (text) |c| if (c < '0' or c > '9') return false;
    return true;
}
fn dictionaryWord(text: []const u8) bool {
    if (text.len == 0 or text[0] == '-' or text[text.len - 1] == '-') return false;
    for (text, 0..) |c, i| if (!((c >= 'a' and c <= 'z') or c == '-') or (c == '-' and i > 0 and text[i - 1] == '-')) return false;
    return true;
}
fn valid(name: []const u8, argument: []const u8) bool {
    if (eq(name, "width") or eq(name, "indent") or eq(name, "page")) {
        if (!digits(argument, 1, 9)) return false;
        const value = number(argument);
        return if (eq(name, "width")) value >= 20 and value <= 80 else if (eq(name, "indent")) value <= 8 else value >= 10 and value <= 100;
    }
    if (eq(name, "align")) return eq(argument, "left") or eq(argument, "right") or eq(argument, "center") or eq(argument,
         "justify");
    if (eq(name, "header") or eq(name, "footer")) {
        var count: usize = 0;
        for (argument) |c| if (c == '|') {
            count += 1;
        };
        return count == 2;
    }
    for ([_][]const u8{ "newpage", "verbatim", "toc", "lot", "index", "bibliography" }) |value| if (eq(name,
         value)) return argument.len == 0;
    if (eq(name, "hyphenation")) {
        for (split(argument, ' ')) |value| if (!dictionaryWord(value)) return false;
        return argument.len > 0;
    }
    if (eq(name, "bib")) {
        const first = std.mem.indexOfScalar(u8, argument, ' ') orelse return false;
        if (first == 0) return false;
        for (argument[0..first]) |c| if (!((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9'))) return false;
        const parts = split(argument[first + 1 ..], '|');
        return parts.len == 3 and parts[0].len > 0 and digits(parts[1], 4, 4) and parts[2].len > 0;
    }
    if (eq(name, "term")) {
        const bar = std.mem.indexOfScalar(u8, argument, '|') orelse return false;
        return bar > 0 and bar + 1 < argument.len;
    }
    if (eq(name, "table")) {
        const end = std.mem.indexOfScalar(u8, argument, ' ') orelse argument.len;
        if (end == 0) return false;
        for (argument[0..end]) |c| if (c != 'l' and c != 'r' and c != 'c') return false;
        return true;
    }
    return argument.len > 0;
}
fn create(doc: *Document, kind: Kind, line: usize, argument: []const u8, width: usize, indent: usize,
     alignment: []const u8, pending: *bool) usize {
    if (doc.blocks.items.len == 0) doc.width = width;
    const index = doc.blocks.items.len;
    append(Block, &doc.blocks, .{ .kind = kind, .line = line, .width = width, .indent = indent, .alignment = alignment,
         .text = argument, .page_break = pending.* });
    pending.* = false;
    return index;
}
pub fn parse(lines: []const []const u8) Document {
    var doc: Document = .{};
    var width: usize = 60;
    var indent: usize = 0;
    var alignment: []const u8 = "left";
    var open: ?usize = null;
    var pending = false;
    var accepted = [3]bool{ false, false, false };
    var i: usize = 0;
    while (i < lines.len) : (i += 1) {
        const line = lines[i];
        if (line.len == 0) {
            open = null;
            continue;
        }
        if (line[0] != '.') {
            if (open == null) open = create(&doc, .paragraph, i + 1, "", width, indent, alignment, &pending);
            append(SourceLine, &doc.blocks.items[open.?].body, .{ .line = i + 1, .text = line });
            continue;
        }
        open = null;
        const space = std.mem.indexOfScalar(u8, line, ' ');
        const name = line[1..(space orelse line.len)];
        const argument = if (space) |position| line[position + 1 ..] else "";
        const kind = blockKind(name);
        var known = kind != null;
        for ([_][]const u8{ "width", "indent", "align", "page", "header", "footer", "newpage", "hyphenation",
             "bib" }) |setting| if (eq(name, setting)) {
            known = true;
        };
        const preamble: ?usize = if (eq(name, "page")) 0 else if (eq(name, "header")) 1 else if (eq(name, "footer")) 2 else null;
        var warning: ?[]const u8 = null;
        if (!known) warning = fmt("unknown directive .{s}", .{name}) else if (!valid(name, argument)) warning = fmt("bad argument for .{s}",
             .{name}) else if (preamble != null and doc.blocks.items.len > 0) warning = fmt(".{s} ignored after the preamble",
             .{name}) else if (preamble != null and accepted[preamble.?]) warning = fmt("duplicate .{s}",
             .{name});
        if (warning) |message| {
            doc.warn(i + 1, message);
            continue;
        }
        if (eq(name, "width")) width = u(number(argument)) else if (eq(name, "indent")) indent = u(number(argument)) else if (eq(name,
             "align")) alignment = argument else if (eq(name, "page")) {
            doc.height = u(number(argument));
            accepted[0] = true;
        } else if (eq(name, "header") or eq(name, "footer")) {
            const fields = split(argument, '|');
            if (eq(name, "header")) @memcpy(&doc.header, fields) else @memcpy(&doc.footer, fields);
            accepted[preamble.?] = true;
        } else if (eq(name, "newpage")) pending = true else if (eq(name, "hyphenation")) {
            for (split(argument, ' ')) |word| append([]const u8, &doc.additions, word);
        } else if (eq(name, "bib")) {
            const first = std.mem.indexOfScalar(u8, argument, ' ').?;
            const fields = split(argument[first + 1 ..], '|');
            append(Bib, &doc.bibliography, .{ .line = i + 1, .key = argument[0..first], .author = fields[0],
                 .year = fields[1], .title = fields[2] });
        } else {
            const index = create(&doc, kind.?, i + 1, argument, width, indent, alignment, &pending);
            const block = &doc.blocks.items[index];
            if (bodyKind(block.kind)) {
                var body = argument;
                if (block.kind == .term) {
                    const bar = std.mem.indexOfScalar(u8, argument, '|').?;
                    block.term = argument[0..bar];
                    body = argument[bar + 1 ..];
                }
                append(SourceLine, &block.body, .{ .line = i + 1, .text = body });
                open = index;
            } else if (block.kind == .verbatim or block.kind == .table) {
                if (block.kind == .table) {
                    const first = std.mem.indexOfScalar(u8, argument, ' ');
                    block.columns = argument[0..(first orelse argument.len)];
                    block.caption = if (first) |position| argument[position + 1 ..] else "";
                }
                var closed = false;
                while (i + 1 < lines.len) {
                    i += 1;
                    if (eq(lines[i], ".end")) {
                        closed = true;
                        break;
                    }
                    append(SourceLine, &block.inner, .{ .line = i + 1, .text = lines[i] });
                }
                if (!closed) doc.warn(block.line, if (block.kind == .table) "unterminated table" else "unterminated verbatim");
            }
        }
    }
    return doc;
}
