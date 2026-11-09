const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Texts = []const Text;
const punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
const whitespace = " \n";
const toc_marker = "\x00toc\x00";

const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }

    fn byte(self: *Builder, value: u8) Allocator.Error!void {
        try self.bytes.append(self.gpa, value);
    }

    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }

    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn starts(text: Text, prefix: Text) bool {
    return std.mem.startsWith(u8, text, prefix);
}

fn ends(text: Text, suffix: Text) bool {
    return std.mem.endsWith(u8, text, suffix);
}

fn contains(text: Text, letter: u8) bool {
    return std.mem.findScalar(u8, text, letter) != null;
}

fn find(text: Text, needle: Text, at: usize) ?usize {
    const offset = std.mem.find(u8, text[at..], needle) orelse return null;
    return at + offset;
}

fn trim(text: Text) Text {
    return std.mem.trim(u8, text, " ");
}

fn lower(gpa: Allocator, text: Text) Allocator.Error!Text {
    const result = try gpa.dupe(u8, text);
    for (result) |*letter| letter.* = std.ascii.toLower(letter.*);
    return result;
}

fn labelCharacter(letter: u8) bool {
    return std.ascii.isAlphanumeric(letter) or letter == '-' or letter == '_';
}

fn isLabel(text: Text) bool {
    if (text.len == 0) return false;
    for (text) |letter| if (!labelCharacter(letter)) return false;
    return true;
}

fn escape(gpa: Allocator, text: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (text) |letter| {
        switch (letter) {
            '&' => try out.add("&amp;"),
            '<' => try out.add("&lt;"),
            '>' => try out.add("&gt;"),
            '"' => try out.add("&quot;"),
            else => try out.byte(letter),
        }
    }
    return out.result();
}

fn stripTags(gpa: Allocator, text: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    var at: usize = 0;
    while (find(text, "<", at)) |opening| {
        const close = find(text, ">", opening + 1) orelse break;
        try out.add(text[at..opening]);
        at = close + 1;
    }
    try out.add(text[at..]);
    return out.result();
}

fn normalize(gpa: Allocator, text: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    var space = false;
    for (text) |letter| {
        if (contains(whitespace, letter)) {
            space = out.bytes.items.len > 0;
        } else {
            if (space) try out.byte(' ');
            try out.byte(std.ascii.toLower(letter));
            space = false;
        }
    }
    return out.result();
}

fn skipSpace(text: Text, start: usize) usize {
    var at = start;
    while (at < text.len and contains(whitespace, text[at])) : (at += 1) {}
    return at;
}

const Read = struct { text: Text, end: usize };

fn escapedRead(gpa: Allocator, text: Text, start: usize, stops: Text) Allocator.Error!Read {
    var out: Builder = .{ .gpa = gpa };
    var at = start;
    while (at < text.len and !contains(stops, text[at])) : (at += 1) {
        if (text[at] == '\\' and at + 1 < text.len and contains(punctuation, text[at + 1])) at += 1;
        try out.byte(text[at]);
    }
    return .{ .text = out.result(), .end = at };
}

fn runEnd(text: Text, at: usize) usize {
    var end = at + 1;
    while (end < text.len and text[end] == text[at]) : (end += 1) {}
    return end;
}

fn backtickCloser(text: Text, start: usize, length: usize) ?usize {
    var at = start;
    while (find(text, "`", at)) |next| {
        const end = runEnd(text, next);
        if (end - next == length) return next;
        at = end;
    }
    return null;
}

fn closingBracket(text: Text, start: usize) ?usize {
    var at = start;
    var depth: usize = 0;
    while (at < text.len) {
        if (text[at] == '\\') {
            at += 2;
            continue;
        }
        if (text[at] == '`') {
            const end = runEnd(text, at);
            const close = backtickCloser(text, end, end - at);
            at = if (close) |position| position + end - at else end;
            continue;
        }
        if (text[at] == '[') depth += 1;
        if (text[at] == ']') {
            depth -= 1;
            if (depth == 0) return at;
        }
        at += 1;
    }
    return null;
}

const BlockKind = enum { heading, paragraph, rule, code, quote, alert, list, table, toc };
const Block = struct {
    kind: BlockKind,
    text: Text = "",
    number: usize = 0,
    ordered: bool = false,
    lines: Texts = &.{},
    children: []const *Block = &.{},
    items: []const []const *Block = &.{},
    alignments: Texts = &.{},
    rows: []const Texts = &.{},
};
const Reference = struct { url: Text, title: ?Text = null };
const Marker = struct { marker: u8, ordered: bool, number: usize, content: Text };
const Fence = struct { fence: Text, info: Text };
const Heading = struct { text: Text, level: usize };

fn openingFence(line: Text) ?Fence {
    if (line.len == 0 or !contains("`~", line[0])) return null;
    const end = runEnd(line, 0);
    if (end < 3) return null;
    const info = trim(line[end..]);
    if (line[0] == '`' and contains(info, '`')) return null;
    return .{ .fence = line[0..end], .info = info };
}

fn atxHeading(line: Text) ?Heading {
    var count: usize = 0;
    while (count < line.len and line[count] == '#') : (count += 1) {}
    if (count == 0 or count > 6 or (count < line.len and line[count] != ' ')) return null;
    var text = trim(line[count..]);
    var end = text.len;
    while (end > 0 and text[end - 1] == '#') : (end -= 1) {}
    if (end == 0 or text[end - 1] == ' ') text = trim(text[0..end]);
    return .{ .text = text, .level = count };
}

fn isRule(line: Text) bool {
    var count: usize = 0;
    var character: u8 = 0;
    for (line) |letter| {
        if (letter == ' ') continue;
        if (!contains("-*_", letter)) return false;
        if (character != 0 and letter != character) return false;
        character = letter;
        count += 1;
    }
    return count >= 3;
}

fn listMarker(line: Text) ?Marker {
    if (line.len < 2 or isRule(line)) return null;
    var end: usize = 0;
    var ordered = false;
    var number: usize = 1;
    var marker: u8 = undefined;
    if (contains("-*+", line[0])) {
        marker = line[0];
        end = 1;
    } else {
        while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
        if (end == 0 or end > 9 or end == line.len or !contains(".)", line[end])) return null;
        ordered = true;
        number = std.fmt.parseInt(usize, line[0..end], 10) catch unreachable;
        marker = line[end];
        end += 1;
    }
    if (end == line.len or line[end] != ' ') return null;
    while (end < line.len and line[end] == ' ') : (end += 1) {}
    return .{ .marker = marker, .ordered = ordered, .number = number, .content = line[end..] };
}

fn interrupts(line: Text) bool {
    if (line.len == 0 or line[0] == ' ') return false;
    return openingFence(line) != null or atxHeading(line) != null or isRule(line) or line[0] == '>' or listMarker(line) != null;
}

fn underline(line: Text) ?usize {
    if (line.len < 3 or !contains("=-", line[0])) return null;
    for (line) |letter| if (letter != line[0]) return null;
    return if (line[0] == '=') 1 else 2;
}

fn splitCells(gpa: Allocator, line: Text) Allocator.Error!Texts {
    var text = trim(line);
    if (starts(text, "|")) text = text[1..];
    var cells: std.ArrayList(Text) = .empty;
    var cell: Builder = .{ .gpa = gpa };
    var final_separator = false;
    var at: usize = 0;
    while (at < text.len) {
        const letter = text[at];
        final_separator = false;
        if (letter == '\\' and at + 1 < text.len) {
            if (text[at + 1] != '|') try cell.byte('\\');
            try cell.byte(text[at + 1]);
            at += 2;
        } else if (letter == '|') {
            try cells.append(gpa, trim(cell.result()));
            cell = .{ .gpa = gpa };
            final_separator = true;
            at += 1;
        } else {
            try cell.byte(letter);
            at += 1;
        }
    }
    if (!final_separator) try cells.append(gpa, trim(cell.result()));
    return cells.items;
}

fn delimiterCell(cell: Text) bool {
    var text = cell;
    if (starts(text, ":")) text = text[1..];
    if (ends(text, ":")) text = text[0 .. text.len - 1];
    if (text.len == 0) return false;
    for (text) |letter| if (letter != '-') return false;
    return true;
}

const Parser = struct {
    gpa: Allocator,
    references: std.StringHashMapUnmanaged(Reference) = .empty,
    footnotes: std.StringHashMapUnmanaged(Text) = .empty,

    fn block(self: *Parser, kind: BlockKind, text: Text, number: usize) Allocator.Error!*Block {
        const result = try self.gpa.create(Block);
        result.* = .{ .kind = kind, .text = text, .number = number };
        return result;
    }

    fn definition(self: *Parser, line: Text) Allocator.Error!bool {
        if (!starts(line, "[")) return false;
        const close = find(line, "]", 1) orelse return false;
        if (close + 1 == line.len or line[close + 1] != ':') return false;
        const label = line[1..close];
        const body = trim(line[close + 2 ..]);
        if (starts(label, "^") and isLabel(label[1..]) and body.len > 0) {
            const key = try lower(self.gpa, label[1..]);
            const entry = try self.footnotes.getOrPut(self.gpa, key);
            if (!entry.found_existing) entry.value_ptr.* = body;
            return true;
        }
        if (contains(label, '[') or trim(label).len == 0 or starts(label, "^")) return false;
        const url = try escapedRead(self.gpa, line, skipSpace(line, close + 2), " ");
        if (url.text.len == 0) return false;
        const at = skipSpace(line, url.end);
        var title: ?Text = null;
        if (at < line.len) {
            if (at == url.end or !contains("\"'", line[at])) return false;
            const quoted = try escapedRead(self.gpa, line, at + 1, line[at .. at + 1]);
            if (quoted.end != line.len - 1) return false;
            title = quoted.text;
        }
        const key = try normalize(self.gpa, label);
        const entry = try self.references.getOrPut(self.gpa, key);
        if (!entry.found_existing) entry.value_ptr.* = .{ .url = url.text, .title = title };
        return true;
    }

    fn parse(self: *Parser, lines: Texts) Allocator.Error![]const *Block {
        var blocks: std.ArrayList(*Block) = .empty;
        var at: usize = 0;
        while (at < lines.len) {
            const line = lines[at];
            if (line.len == 0) {
                at += 1;
                continue;
            }
            if (starts(line, "    ")) {
                var end = at;
                while (end < lines.len and (lines[end].len == 0 or starts(lines[end], "    "))) : (end += 1) {}
                while (lines[end - 1].len == 0) : (end -= 1) {}
                const code = try self.block(.code, "", 0);
                var code_lines: std.ArrayList(Text) = .empty;
                while (at < end) : (at += 1) {
                    try code_lines.append(self.gpa, if (lines[at].len == 0) "" else lines[at][4..]);
                }
                code.lines = code_lines.items;
                try blocks.append(self.gpa, code);
                continue;
            }
            if (line[0] != ' ') {
                if (openingFence(line)) |fence| {
                    const space = std.mem.findScalar(u8, fence.info, ' ') orelse fence.info.len;
                    const code = try self.block(.code, fence.info[0..space], 0);
                    var code_lines: std.ArrayList(Text) = .empty;
                    at += 1;
                    while (at < lines.len) {
                        const row = lines[at];
                        at += 1;
                        var closing = row.len >= fence.fence.len;
                        for (row) |letter| {
                            if (letter != fence.fence[0]) closing = false;
                        }
                        if (closing) break;
                        try code_lines.append(self.gpa, row);
                    }
                    code.lines = code_lines.items;
                    try blocks.append(self.gpa, code);
                    continue;
                }
                if (atxHeading(line)) |heading| {
                    try blocks.append(self.gpa, try self.block(.heading, heading.text, heading.level));
                    at += 1;
                    continue;
                }
                if (isRule(line)) {
                    try blocks.append(self.gpa, try self.block(.rule, "", 0));
                    at += 1;
                    continue;
                }
                if (line[0] == '>') {
                    var content: std.ArrayList(Text) = .empty;
                    while (at < lines.len and starts(lines[at], ">")) : (at += 1) {
                        var row = lines[at][1..];
                        if (starts(row, " ")) row = row[1..];
                        try content.append(self.gpa, row);
                    }
                    const quote = try self.block(.quote, "", 0);
                    var first: usize = 0;
                    for ([_]Text{ "NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION" }) |kind| {
                        const marker = try std.fmt.allocPrint(self.gpa, "[!{s}]", .{kind});
                        if (equal(content.items[0], marker)) {
                            quote.kind = .alert;
                            quote.text = kind;
                            first = 1;
                            break;
                        }
                    }
                    quote.children = try self.parse(content.items[first..]);
                    try blocks.append(self.gpa, quote);
                    continue;
                }
                if (listMarker(line)) |first_marker| {
                    const list = try self.block(.list, "", first_marker.number);
                    list.ordered = first_marker.ordered;
                    var items: std.ArrayList([]const *Block) = .empty;
                    var marker = first_marker;
                    while (true) {
                        var content: std.ArrayList(Text) = .empty;
                        try content.append(self.gpa, marker.content);
                        at += 1;
                        while (at < lines.len and starts(lines[at], "  ")) : (at += 1) {
                            try content.append(self.gpa, lines[at][2..]);
                        }
                        try items.append(self.gpa, try self.parse(content.items));
                        var next = at;
                        while (next < lines.len and lines[next].len == 0) : (next += 1) {}
                        if (next == lines.len) break;
                        marker = listMarker(lines[next]) orelse break;
                        if (marker.marker != first_marker.marker or marker.ordered != first_marker.ordered) break;
                        at = next;
                    }
                    list.items = items.items;
                    try blocks.append(self.gpa, list);
                    continue;
                }
                if (try self.definition(line)) {
                    at += 1;
                    continue;
                }
                if (at + 1 < lines.len and contains(line, '|') and contains(lines[at + 1], '|')) {
                    const header = try splitCells(self.gpa, line);
                    const delimiters = try splitCells(self.gpa, lines[at + 1]);
                    var valid = header.len == delimiters.len;
                    for (delimiters) |cell| {
                        if (!delimiterCell(cell)) valid = false;
                    }
                    if (valid) {
                        const table = try self.block(.table, "", 0);
                        table.lines = header;
                        const alignments = try self.gpa.alloc(Text, delimiters.len);
                        for (delimiters, 0..) |cell, index| {
                            const left = starts(cell, ":");
                            const right = ends(cell, ":");
                            alignments[index] = if (left) (if (right) "center" else "left") else (if (right) "right" else "");
                        }
                        table.alignments = alignments;
                        var rows: std.ArrayList(Texts) = .empty;
                        at += 2;
                        while (at < lines.len and lines[at].len > 0 and contains(lines[at], '|')) : (at += 1) {
                            const cells = try splitCells(self.gpa, lines[at]);
                            const row = try self.gpa.alloc(Text, delimiters.len);
                            for (row, 0..) |*cell, index| cell.* = if (index < cells.len) cells[index] else "";
                            try rows.append(self.gpa, row);
                        }
                        table.rows = rows.items;
                        try blocks.append(self.gpa, table);
                        continue;
                    }
                }
            }
            var text_lines: std.ArrayList(Text) = .empty;
            try text_lines.append(self.gpa, std.mem.trimStart(u8, line, " "));
            at += 1;
            var level: usize = 0;
            while (at < lines.len and lines[at].len > 0) {
                if (underline(lines[at])) |heading_level| {
                    level = heading_level;
                    at += 1;
                    break;
                }
                if (interrupts(lines[at])) break;
                try text_lines.append(self.gpa, std.mem.trimStart(u8, lines[at], " "));
                at += 1;
            }
            const text = try std.mem.join(self.gpa, "\n", text_lines.items);
            const kind: BlockKind = if (level > 0) .heading else if (equal(text, "[TOC]")) .toc else .paragraph;
            try blocks.append(self.gpa, try self.block(kind, text, level));
        }
        return blocks.items;
    }
};

const Piece = struct {
    html: Text = "",
    delimiter: u8 = 0,
    length: usize = 0,
    can_open: bool = false,
    can_close: bool = false,
};

fn emphasis(gpa: Allocator, pieces: []const Piece) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    var at: usize = 0;
    while (at < pieces.len) : (at += 1) {
        const piece = pieces[at];
        if (piece.delimiter == 0) {
            try out.add(piece.html);
            continue;
        }
        var closer: ?usize = null;
        if (piece.can_open) {
            for (pieces[at + 1 ..], at + 1..) |other, index| {
                if (other.delimiter == piece.delimiter and other.length == piece.length and other.can_close) {
                    closer = index;
                    break;
                }
            }
        }
        if (closer) |close| {
            const opening: Text = if (piece.delimiter == '~') "<del>" else switch (piece.length) {
                1 => "<em>",
                2 => "<strong>",
                3 => "<em><strong>",
                else => unreachable,
            };
            const closing: Text = if (piece.delimiter == '~') "</del>" else switch (piece.length) {
                1 => "</em>",
                2 => "</strong>",
                3 => "</strong></em>",
                else => unreachable,
            };
            try out.add(opening);
            try out.add(try emphasis(gpa, pieces[at + 1 .. close]));
            try out.add(closing);
            at = close;
        } else {
            for (0..piece.length) |_| try out.byte(piece.delimiter);
        }
    }
    return out.result();
}

fn isEmail(text: Text) bool {
    const at = std.mem.findScalar(u8, text, '@') orelse return false;
    if (at == 0) return false;
    for (text[0..at]) |letter| {
        if (!std.ascii.isAlphanumeric(letter) and !contains(".+-_", letter)) return false;
    }
    var parts = std.mem.splitScalar(u8, text[at + 1 ..], '.');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        for (part) |letter| if (!std.ascii.isAlphanumeric(letter) and letter != '-') return false;
        count += 1;
    }
    return count >= 2;
}

const Destination = struct { reference: Reference, end: usize };
const Bracket = struct { html: Text, end: usize };
const HeadingEntry = struct {
    level: usize,
    id: Text,
    label: Text,
    children: std.ArrayList(usize) = .empty,
};
const Renderer = struct {
    gpa: Allocator,
    references: std.StringHashMapUnmanaged(Reference),
    footnotes: std.StringHashMapUnmanaged(Text),
    used_ids: std.StringHashMapUnmanaged(void) = .empty,
    headings: std.ArrayList(HeadingEntry) = .empty,
    footnote_numbers: std.StringHashMapUnmanaged(usize) = .empty,
    footnote_names: std.ArrayList(Text) = .empty,
    footnote_counts: std.ArrayList(usize) = .empty,

    fn destination(self: *Renderer, text: Text, at: usize, label: Text) Allocator.Error!?Destination {
        if (at < text.len and text[at] == '[') {
            if (find(text, "]", at + 1)) |close| {
                const key = text[at + 1 .. close];
                if (!contains(key, '[')) {
                    const name = try normalize(self.gpa, if (key.len == 0) label else key);
                    const reference = self.references.get(name) orelse return null;
                    return .{ .reference = reference, .end = close + 1 };
                }
            }
        } else if (at < text.len and text[at] == '(') {
            const url = try escapedRead(self.gpa, text, skipSpace(text, at + 1), " \n)");
            var next = skipSpace(text, url.end);
            var title: ?Text = null;
            var valid = true;
            if (next > url.end and next < text.len and contains("\"'", text[next])) {
                const quoted = try escapedRead(self.gpa, text, next + 1, text[next .. next + 1]);
                if (quoted.end == text.len) valid = false else {
                    title = quoted.text;
                    next = skipSpace(text, quoted.end + 1);
                }
            }
            if (valid and next < text.len and text[next] == ')') return .{
                .reference = .{ .url = url.text, .title = title },
                .end = next + 1,
            };
        }
        const reference = self.references.get(try normalize(self.gpa, label)) orelse return null;
        return .{ .reference = reference, .end = at };
    }

    fn referenceId(self: *const Renderer, number: usize, count: usize) Allocator.Error!Text {
        if (count == 1) return std.fmt.allocPrint(self.gpa, "fnref-{d}", .{number});
        return std.fmt.allocPrint(self.gpa, "fnref-{d}-{d}", .{ number, count });
    }

    fn footnoteReference(self: *Renderer, name: Text) Allocator.Error!Text {
        const entry = try self.footnote_numbers.getOrPut(self.gpa, name);
        if (!entry.found_existing) {
            entry.value_ptr.* = self.footnote_names.items.len;
            try self.footnote_names.append(self.gpa, name);
            try self.footnote_counts.append(self.gpa, 0);
        }
        const index = entry.value_ptr.*;
        self.footnote_counts.items[index] += 1;
        const id = try self.referenceId(index + 1, self.footnote_counts.items[index]);
        return std.fmt.allocPrint(self.gpa, "<sup id=\"{s}\"><a href=\"#fn-{d}\">{d}</a></sup>", .{ id, index + 1, index + 1 });
    }

    fn bracket(self: *Renderer, text: Text, at: usize, links: bool, notes: bool) Allocator.Error!?Bracket {
        if (links and notes and starts(text[at..], "[^")) {
            if (find(text, "]", at + 2)) |close| {
                const name = try lower(self.gpa, text[at + 2 .. close]);
                if (self.footnotes.contains(name)) return .{ .html = try self.footnoteReference(name), .end = close + 1 };
            }
        }
        const image = text[at] == '!';
        if (!image and !links) return null;
        const opening = if (image) at + 1 else at;
        const close = closingBracket(text, opening) orelse return null;
        const label = text[opening + 1 .. close];
        const dest = (try self.destination(text, close + 1, label)) orelse return null;
        const content = try self.inlineHtml(label, false, false);
        var out: Builder = .{ .gpa = self.gpa };
        const url = try escape(self.gpa, dest.reference.url);
        if (image) try out.print("<img src=\"{s}\" alt=\"{s}\"", .{ url, try stripTags(self.gpa, content) }) else try out.print("<a href=\"{s}\"", .{url});
        if (dest.reference.title) |title| try out.print(" title=\"{s}\"", .{try escape(self.gpa, title)});
        if (image) try out.add(" />") else try out.print(">{s}</a>", .{content});
        return .{ .html = out.result(), .end = dest.end };
    }

    fn inlineHtml(self: *Renderer, text: Text, links: bool, notes: bool) Allocator.Error!Text {
        var pieces: std.ArrayList(Piece) = .empty;
        var at: usize = 0;
        while (at < text.len) {
            const letter = text[at];
            if (letter == '\\') {
                if (at + 1 < text.len and contains(punctuation, text[at + 1])) {
                    try pieces.append(self.gpa, .{ .html = try escape(self.gpa, text[at + 1 .. at + 2]) });
                    at += 2;
                } else if (at + 1 < text.len and text[at + 1] == '\n') {
                    try pieces.append(self.gpa, .{ .html = "<br />\n" });
                    at += 2;
                } else {
                    try pieces.append(self.gpa, .{ .html = "\\" });
                    at += 1;
                }
                continue;
            }
            if (letter == '`') {
                const end = runEnd(text, at);
                if (backtickCloser(text, end, end - at)) |close| {
                    const code = try self.gpa.dupe(u8, text[end..close]);
                    for (code) |*character| {
                        if (character.* == '\n') character.* = ' ';
                    }
                    var value: Text = code;
                    if (starts(value, " ") and ends(value, " ") and trim(value).len > 0) value = value[1 .. value.len - 1];
                    try pieces.append(self.gpa, .{ .html = try std.fmt.allocPrint(self.gpa, "<code>{s}</code>", .{try escape(self.gpa, value)}) });
                    at = close + end - at;
                } else {
                    try pieces.append(self.gpa, .{ .html = text[at..end] });
                    at = end;
                }
                continue;
            }
            if (links and letter == '<') {
                if (find(text, ">", at + 1)) |close| {
                    const target = text[at + 1 .. close];
                    var clean = true;
                    for (target) |character| {
                        if (contains(" \n<", character)) clean = false;
                    }
                    var href: ?Text = null;
                    if (clean and ((starts(target, "http://") and target.len > 7) or (starts(target, "https://") and target.len > 8))) {
                        href = target;
                    } else if (isEmail(target)) {
                        href = try std.mem.concat(self.gpa, u8, &.{ "mailto:", target });
                    }
                    if (href) |url| {
                        try pieces.append(self.gpa, .{ .html = try std.fmt.allocPrint(self.gpa, "<a href=\"{s}\">{s}</a>", .{
                            try escape(self.gpa, url), try escape(self.gpa, target),
                        }) });
                        at = close + 1;
                        continue;
                    }
                }
            }
            if (links and (starts(text[at..], "http://") or starts(text[at..], "https://")) and
                (at == 0 or contains(" \n*_~(", text[at - 1])))
            {
                var end = at;
                while (end < text.len and !contains(" \n<", text[end])) : (end += 1) {}
                while (end > at and contains(".,:;!?*_~)", text[end - 1])) : (end -= 1) {}
                const url = text[at..end];
                if (!equal(url, "http://") and !equal(url, "https://")) {
                    const escaped = try escape(self.gpa, url);
                    try pieces.append(self.gpa, .{ .html = try std.fmt.allocPrint(self.gpa, "<a href=\"{s}\">{s}</a>", .{ escaped, escaped }) });
                    at = end;
                    continue;
                }
            }
            if (letter == '[' or (letter == '!' and at + 1 < text.len and text[at + 1] == '[')) {
                if (try self.bracket(text, at, links, notes)) |result| {
                    try pieces.append(self.gpa, .{ .html = result.html });
                    at = result.end;
                } else {
                    try pieces.append(self.gpa, .{ .html = text[at .. at + 1] });
                    at += 1;
                }
                continue;
            }
            if (contains("*_~", letter)) {
                const end = runEnd(text, at);
                const length = end - at;
                const before: u8 = if (at == 0) ' ' else text[at - 1];
                const after: u8 = if (end == text.len) ' ' else text[end];
                var can_open = !contains(whitespace, after);
                var can_close = !contains(whitespace, before);
                if (letter == '_' and std.ascii.isAlphanumeric(before) and std.ascii.isAlphanumeric(after)) {
                    can_open = false;
                    can_close = false;
                }
                if ((letter != '~' and length <= 3) or (letter == '~' and length == 2)) {
                    try pieces.append(self.gpa, .{ .delimiter = letter, .length = length, .can_open = can_open, .can_close = can_close });
                } else try pieces.append(self.gpa, .{ .html = text[at..end] });
                at = end;
                continue;
            }
            try pieces.append(self.gpa, .{ .html = try escape(self.gpa, text[at .. at + 1]) });
            at += 1;
        }
        return emphasis(self.gpa, pieces.items);
    }

    fn blocks(self: *Renderer, items: []const *Block) Allocator.Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        for (items) |item| {
            try out.add(try self.render(item));
            try out.byte('\n');
        }
        return out.result();
    }

    fn heading(self: *Renderer, level: usize, original: Text) Allocator.Error!Text {
        var text = original;
        var explicit: ?usize = null;
        var at: usize = 0;
        while (find(text, " {#", at)) |position| {
            explicit = position;
            at = position + 1;
        }
        var identifier: ?Text = null;
        if (ends(text, "}") and explicit != null) {
            const start = explicit.?;
            const candidate = text[start + 3 .. text.len - 1];
            if (isLabel(candidate)) {
                identifier = candidate;
                text = std.mem.trimEnd(u8, text[0..start], " ");
            }
        }
        if (identifier == null) {
            var slug: Builder = .{ .gpa = self.gpa };
            for (text) |character| {
                const letter = std.ascii.toLower(character);
                if (labelCharacter(letter)) try slug.byte(letter) else if (contains(whitespace, letter)) try slug.byte('-');
            }
            const base: Text = if (slug.result().len == 0) "heading" else slug.result();
            identifier = base;
            var suffix: usize = 1;
            while (self.used_ids.contains(identifier.?)) : (suffix += 1) {
                identifier = try std.fmt.allocPrint(self.gpa, "{s}-{d}", .{ base, suffix });
            }
        }
        const id = identifier.?;
        try self.used_ids.put(self.gpa, id, {});
        const html = try self.inlineHtml(text, true, true);
        try self.headings.append(self.gpa, .{ .level = level, .id = id, .label = try stripTags(self.gpa, html) });
        return std.fmt.allocPrint(self.gpa, "<h{d} id=\"{s}\">{s}</h{d}>", .{ level, id, html, level });
    }

    fn item(self: *Renderer, content: []const *Block) Allocator.Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        try out.add("<li>");
        for (content, 0..) |block, index| {
            if (block.kind == .paragraph) {
                var text = block.text;
                if (index == 0 and text.len > 4 and (starts(text, "[ ] ") or starts(text, "[x] ") or starts(text, "[X] "))) {
                    try out.add(if (text[1] == ' ') "<input type=\"checkbox\" disabled=\"\" /> " else "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
                    text = text[4..];
                }
                try out.add(try self.inlineHtml(text, true, true));
            } else {
                if (!ends(out.result(), "\n")) try out.byte('\n');
                try out.add(try self.render(block));
                try out.byte('\n');
            }
        }
        try out.add("</li>");
        return out.result();
    }

    fn tableCells(self: *Renderer, tag: Text, table: *const Block, cells: Texts) Allocator.Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        for (cells, 0..) |cell, index| {
            try out.print("<{s}", .{tag});
            if (table.alignments[index].len > 0) try out.print(" style=\"text-align:{s}\"", .{table.alignments[index]});
            try out.print(">{s}</{s}>\n", .{ try self.inlineHtml(cell, true, true), tag });
        }
        return out.result();
    }

    fn render(self: *Renderer, block: *const Block) Allocator.Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        switch (block.kind) {
            .heading => return self.heading(block.number, block.text),
            .paragraph => return std.fmt.allocPrint(self.gpa, "<p>{s}</p>", .{try self.inlineHtml(block.text, true, true)}),
            .rule => return "<hr />",
            .code => {
                try out.add("<pre><code");
                if (block.text.len > 0) try out.print(" class=\"language-{s}\"", .{try escape(self.gpa, block.text)});
                try out.byte('>');
                for (block.lines) |line| {
                    try out.add(try escape(self.gpa, line));
                    try out.byte('\n');
                }
                try out.add("</code></pre>");
            },
            .quote => try out.print("<blockquote>\n{s}</blockquote>", .{try self.blocks(block.children)}),
            .alert => {
                const kind = try lower(self.gpa, block.text);
                const title = try self.gpa.dupe(u8, kind);
                title[0] = std.ascii.toUpper(title[0]);
                try out.print("<div class=\"alert alert-{s}\">\n<p class=\"alert-title\">{s}</p>\n{s}</div>", .{
                    kind, title, try self.blocks(block.children),
                });
            },
            .list => {
                const tag: Text = if (block.ordered) "ol" else "ul";
                try out.print("<{s}", .{tag});
                if (block.ordered and block.number != 1) try out.print(" start=\"{d}\"", .{block.number});
                try out.add(">\n");
                for (block.items) |content| {
                    try out.add(try self.item(content));
                    try out.byte('\n');
                }
                try out.print("</{s}>", .{tag});
            },
            .table => {
                try out.print("<table>\n<thead>\n<tr>\n{s}</tr>\n</thead>\n", .{try self.tableCells("th", block, block.lines)});
                if (block.rows.len > 0) {
                    try out.add("<tbody>\n");
                    for (block.rows) |row| try out.print("<tr>\n{s}</tr>\n", .{try self.tableCells("td", block, row)});
                    try out.add("</tbody>\n");
                }
                try out.add("</table>");
            },
            .toc => return toc_marker,
        }
        return out.result();
    }

    fn tocList(self: *const Renderer, entries: []const usize) Allocator.Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        try out.add("<ul>\n");
        for (entries) |index| {
            const entry = self.headings.items[index];
            try out.print("<li><a href=\"#{s}\">{s}</a>", .{ entry.id, entry.label });
            if (entry.children.items.len > 0) try out.print("\n{s}\n", .{try self.tocList(entry.children.items)});
            try out.add("</li>\n");
        }
        try out.add("</ul>");
        return out.result();
    }

    fn toc(self: *Renderer) Allocator.Error!Text {
        if (self.headings.items.len == 0) return "<nav class=\"toc\">\n</nav>";
        var roots: std.ArrayList(usize) = .empty;
        var parents: std.ArrayList(usize) = .empty;
        for (0..self.headings.items.len) |index| {
            while (parents.items.len > 0 and self.headings.items[parents.items[parents.items.len - 1]].level >= self.headings.items[index].level) {
                parents.items.len -= 1;
            }
            if (parents.items.len == 0) try roots.append(self.gpa, index) else try self.headings.items[parents.items[parents.items.len - 1]].children.append(self.gpa, index);
            try parents.append(self.gpa, index);
        }
        return std.fmt.allocPrint(self.gpa, "<nav class=\"toc\">\n{s}\n</nav>", .{try self.tocList(roots.items)});
    }

    fn footnoteList(self: *Renderer) Allocator.Error!Text {
        var out: Builder = .{ .gpa = self.gpa };
        try out.add("<section class=\"footnotes\">\n<ol>\n");
        for (self.footnote_names.items, 0..) |name, index| {
            const body = try self.inlineHtml(self.footnotes.get(name).?, true, false);
            try out.print("<li id=\"fn-{d}\">{s}", .{ index + 1, body });
            for (1..self.footnote_counts.items[index] + 1) |count| {
                try out.print(" <a href=\"#{s}\">&#8617;</a>", .{try self.referenceId(index + 1, count)});
            }
            try out.add("</li>\n");
        }
        try out.add("</ol>\n</section>\n");
        return out.result();
    }

    fn document(self: *Renderer, content: []const *Block) Allocator.Error!Text {
        const html = try self.blocks(content);
        const contents = try self.toc();
        var out: Builder = .{ .gpa = self.gpa };
        var at: usize = 0;
        while (find(html, toc_marker, at)) |position| {
            try out.add(html[at..position]);
            try out.add(contents);
            at = position + toc_marker.len;
        }
        try out.add(html[at..]);
        if (self.footnote_names.items.len > 0) try out.add(try self.footnoteList());
        return out.result();
    }
};

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines: std.ArrayList(Text) = .empty;
    var pieces = std.mem.splitScalar(u8, text, '\n');
    while (pieces.next()) |line| {
        if (equal(line, "@@END@@")) break;
        try lines.append(gpa, line);
    }
    var parser: Parser = .{ .gpa = gpa };
    const blocks = try parser.parse(lines.items);
    var renderer: Renderer = .{ .gpa = gpa, .references = parser.references, .footnotes = parser.footnotes };
    try output.interface.writeAll(try renderer.document(blocks));
    try output.interface.flush();
}
