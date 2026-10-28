const std = @import("std");
const d = @import("document_parser.zig");
const hyphenation = @import("hyphenation.zig");
const lb = @import("line_breaker.zig");
const pb = @import("page_builder.zig");
const renderer = @import("renderer.zig");
const Context = struct { document: d.Document, params: d.Params, dictionary: hyphenation.Dictionary,
     labels: std.StringHashMap(usize), bib_keys: std.StringHashMap(usize), bib_order: []usize = &.{},
     footnotes: std.ArrayList([]const u8) = .empty, index_phrases: std.ArrayList([]const u8) = .empty };
fn removeLabel(text: *[]const u8, label: *[]const u8) void {
    if (text.len == 0 or text.*[text.len - 1] != '}') return;
    const position = std.mem.lastIndexOf(u8, text.*, " {#") orelse return;
    label.* = text.*[position + 3 .. text.len - 1];
    text.* = text.*[0..position];
}
fn authorParts(author: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var first: usize = 0;
    while (std.mem.indexOfPos(u8, author, first, " and ")) |next| {
        d.append([]const u8, &out, author[first..next]);
        first = next + 5;
    }
    d.append([]const u8, &out, author[first..]);
    return out.items;
}
fn bibLess(entries: []const d.Bib, a: usize, b: usize) bool {
    const first = entries[a];
    const second = entries[b];
    const left = [_][]const u8{ first.base, first.author, first.title, first.key };
    const right = [_][]const u8{ second.base, second.author, second.title, second.key };
    for (left, right) |x, y| {
        const order = std.mem.order(u8, x, y);
        if (order != .eq) return order == .lt;
    }
    return false;
}
fn warningLess(_: void, a: d.Warning, b: d.Warning) bool {
    return if (a.line != b.line) a.line < b.line else a.sequence < b.sequence;
}
fn prepare(c: *Context) void {
    const doc = &c.document;
    var chapter: usize = 0;
    var section: usize = 0;
    var table: usize = 0;
    var body: usize = 0;
    for (doc.blocks.items, 0..) |*block, i| {
        if (block.kind == .h1 or block.kind == .h2) {
            removeLabel(&block.text, &block.label);
            if (block.kind == .h1) {
                chapter += 1;
                section = 0;
                block.number = d.fmt("{d}", .{chapter});
                if (i > 0) block.page_break = true;
            } else {
                section += 1;
                block.number = d.fmt("{d}.{d}", .{ chapter, section });
            }
        } else if (block.kind == .table) {
            removeLabel(&block.caption, &block.label);
            if (block.caption.len > 0) {
                table += 1;
                block.number = d.fmt("{d}", .{table});
            }
        } else if (block.kind == .enum_) block.number = d.fmt("{d}", .{if (i > 0 and doc.blocks.items[i - 1].kind == .enum_) d.number(doc.blocks.items[i - 1].number) + 1 else 1});
        if (block.label.len > 0) {
            if (c.labels.contains(block.label)) {
                doc.warn(block.line, d.fmt("duplicate label {s}", .{block.label}));
                block.label = "";
            } else c.labels.put(block.label, i) catch @panic("allocation failed");
        }
        if (block.kind == .paragraph and i > 0 and (doc.blocks.items[i - 1].kind == .h1 or doc.blocks.items[i - 1].kind == .h2)) block.indent = 0;
        if (d.bodyKind(block.kind)) {
            block.body_number = body;
            body += 1;
        }
    }
    var unique: std.ArrayList(d.Bib) = .empty;
    for (doc.bibliography.items) |entry| {
        if (c.bib_keys.contains(entry.key)) doc.warn(entry.line, d.fmt("duplicate bibliography key {s}", .{entry.key})) else {
            c.bib_keys.put(entry.key, unique.items.len) catch @panic("allocation failed");
            d.append(d.Bib, &unique, entry);
        }
    }
    doc.bibliography = unique;
    for (doc.blocks.items) |*block| {
        if (block.kind == .table) {
            block.cells = d.alloc([]const []const u8, block.inner.items.len);
            for (block.inner.items, block.cells) |line, *target| {
                const cells = d.split(line.text, '|');
                if (cells.len != block.columns.len) doc.warn(line.line, d.fmt("table row has {d} cells, expected {d}",
                     .{ cells.len, block.columns.len }));
                const corrected = d.alloc([]const u8, block.columns.len);
                for (corrected, 0..) |*cell, i| cell.* = if (i < cells.len) d.trim(cells[i]) else "";
                target.* = corrected;
            }
            var width: usize = 0;
            for (renderer.table(block.*).data.items) |line| width = @max(width, line.len);
            if (width > block.width) doc.warn(block.line, d.fmt("table too wide by {d}", .{width - block.width}));
        } else if (block.kind == .verbatim) {
            for (block.inner.items) |line| if (line.text.len > block.width) doc.warn(line.line, d.fmt("verbatim line too long by {d}",
                 .{line.text.len - block.width}));
        } else if (d.bodyKind(block.kind)) {
            for (block.body.items, 0..) |source, line_index| {
                if (line_index > 0) d.append(d.Inline, &block.tokens, .{ .kind = "text", .text = " " });
                const text = source.text;
                var start: usize = 0;
                while (start < text.len) {
                    const brace = std.mem.indexOfPos(u8, text, start, "{") orelse {
                        d.append(d.Inline, &block.tokens, .{ .kind = "text", .text = text[start..] });
                        break;
                    };
                    d.append(d.Inline, &block.tokens, .{ .kind = "text", .text = text[start..brace] });
                    const close = std.mem.indexOfPos(u8, text, brace + 1, "}") orelse {
                        doc.warn(source.line, "unclosed brace");
                        d.append(d.Inline, &block.tokens, .{ .kind = "text", .text = text[brace..] });
                        break;
                    };
                    const content = text[brace + 1 .. close];
                    const colon = std.mem.indexOfScalar(u8, content, ':');
                    const command = content[0..(colon orelse content.len)];
                    const argument = if (colon) |position| content[position + 1 ..] else "";
                    const known = d.eq(command, "ref") or d.eq(command, "page") or d.eq(command, "fn") or d.eq(command,
                         "idx") or d.eq(command, "cite");
                    if (colon == null or argument.len == 0 or !known) doc.warn(source.line, d.fmt("bad command {{{s}}}",
                         .{content})) else {
                        var token: d.Inline = .{ .kind = command, .text = argument };
                        if (d.eq(command, "ref") or d.eq(command, "page")) {
                            if (!c.labels.contains(argument)) doc.warn(source.line, d.fmt("undefined label {s}", .{argument}));
                        } else if (d.eq(command, "cite")) {
                            for (d.split(argument, ',')) |key| {
                                if (c.bib_keys.get(key)) |index| doc.bibliography.items[index].cited = true else doc.warn(source.line,
                                     d.fmt("undefined citation {s}", .{key}));
                            }
                        } else if (d.eq(command, "fn")) {
                            token.id = c.footnotes.items.len;
                            d.append([]const u8, &c.footnotes, argument);
                        } else {
                            token.id = c.index_phrases.items.len;
                            d.append([]const u8, &c.index_phrases, argument);
                        }
                        d.append(d.Inline, &block.tokens, token);
                    }
                    start = close + 1;
                }
            }
        }
    }
    var bib_order: std.ArrayList(usize) = .empty;
    for (doc.bibliography.items, 0..) |*entry, i| {
        if (!entry.cited) {
            doc.warn(entry.line, d.fmt("unused bibliography entry {s}", .{entry.key}));
            continue;
        }
        const surnames = authorParts(entry.author);
        var base: d.Text = .{};
        if (surnames.len == 1) base.add("{s}", .{surnames[0][0..@min(3, surnames[0].len)]}) else {
            for (surnames[0..(if (surnames.len >= 5) @as(usize, 3) else surnames.len)]) |surname| base.add("{c}", .{surname[0]});
            if (surnames.len >= 5) base.add("+", .{});
        }
        base.add("{s}", .{entry.year[2..]});
        entry.base = base.value();
        d.append(usize, &bib_order, i);
    }
    std.mem.sort(usize, bib_order.items, @as([]const d.Bib, doc.bibliography.items), bibLess);
    var i: usize = 0;
    while (i < bib_order.items.len) {
        var end = i + 1;
        while (end < bib_order.items.len and d.eq(doc.bibliography.items[bib_order.items[end]].base,
             doc.bibliography.items[bib_order.items[i]].base)) end += 1;
        for (i..end) |j| {
            const entry = &doc.bibliography.items[bib_order.items[j]];
            entry.label = if (end - i > 1) d.fmt("{s}{c}", .{ entry.base, @as(u8, 'a') + @as(u8, @intCast(j - i)) }) else entry.base;
        }
        i = end;
    }
    c.bib_order = bib_order.items;
    std.mem.sort(d.Warning, doc.warnings.items, {}, warningLess);
}
const Mark = struct { word: usize, position: usize, id: usize, footnote: bool };
const BreakPosition = struct { word: usize, position: usize, after: bool = false, mid: bool = false, hyphen: bool = false };
const TextData = struct { words: []const []const u8, marks: []Mark, breaks: []BreakPosition, prefix: []usize };
fn textData(values: []const []const u8, marks: []Mark, c: *const Context) TextData {
    var breaks: std.ArrayList(BreakPosition) = .empty;
    d.append(BreakPosition, &breaks, .{ .word = 0, .position = 0 });
    const prefix = d.alloc(usize, values.len + 1);
    prefix[0] = 0;
    for (values, 0..) |word, i| {
        for (hyphenation.points(c.dictionary, word, c.params)) |point| d.append(BreakPosition, &breaks,
             .{ .word = i, .position = point.position, .mid = true, .hyphen = point.hyphen });
        d.append(BreakPosition, &breaks, .{ .word = i, .position = word.len, .after = true });
        prefix[i + 1] = prefix[i] + word.len;
    }
    return .{ .words = values, .marks = marks, .breaks = breaks.items, .prefix = prefix };
}
fn stringLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn expand(block: d.Block, c: *const Context, page_values: std.StringHashMap([]const u8)) TextData {
    const RawMark = struct { offset: usize, id: usize, footnote: bool };
    var expanded: d.Text = .{};
    var raw: std.ArrayList(RawMark) = .empty;
    for (block.tokens.items) |token| {
        if (d.eq(token.kind, "text")) expanded.add("{s}", .{token.text}) else if (d.eq(token.kind,
             "ref") or d.eq(token.kind, "page")) {
            if (c.labels.get(token.text)) |index| expanded.add("{s}", .{if (d.eq(token.kind, "ref")) c.document.blocks.items[index].number else page_values.get(token.text).?}) else expanded.add("??",
                 .{});
        } else if (d.eq(token.kind, "fn")) {
            d.append(RawMark, &raw, .{ .offset = expanded.data.items.len, .id = token.id.?, .footnote = true });
            expanded.add("[{d}]", .{token.id.? + 1});
        } else if (d.eq(token.kind, "idx")) d.append(RawMark, &raw, .{ .offset = expanded.data.items.len - 1,
             .id = token.id.?, .footnote = false }) else {
            var labels: std.ArrayList([]const u8) = .empty;
            var missing = false;
            for (d.split(token.text, ',')) |key| {
                if (c.bib_keys.get(key)) |index| d.append([]const u8, &labels, c.document.bibliography.items[index].label) else missing = true;
            }
            std.mem.sort([]const u8, labels.items, {}, stringLess);
            var unique: std.ArrayList([]const u8) = .empty;
            for (labels.items, 0..) |label, i| if (i == 0 or !d.eq(label, labels.items[i - 1])) d.append([]const u8,
                 &unique, label);
            if (missing) d.append([]const u8, &unique, "?");
            expanded.add("[{s}]", .{d.join(unique.items, ", ")});
        }
    }
    const text = expanded.value();
    var values: std.ArrayList([]const u8) = .empty;
    var starts: std.ArrayList(usize) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == ' ') {
            i += 1;
            continue;
        }
        const first = i;
        while (i < text.len and text[i] != ' ') i += 1;
        d.append(usize, &starts, first);
        d.append([]const u8, &values, text[first..i]);
    }
    const marks = d.alloc(Mark, raw.items.len);
    for (raw.items, marks) |mark, *located| {
        var word: usize = 0;
        while (word + 1 < starts.items.len and starts.items[word + 1] <= mark.offset) word += 1;
        located.* = .{ .word = word, .position = mark.offset - starts.items[word], .id = mark.id, .footnote = mark.footnote };
    }
    return textData(values.items, marks, c);
}
const MeasureContext = struct { text: *const TextData, first: usize, later: usize };
fn measureLine(context: MeasureContext, a: usize, b: usize) lb.Measure {
    const text = context.text;
    const start = text.breaks[a];
    const end = text.breaks[b];
    const word = if (start.after) start.word + 1 else start.word;
    const position = if (start.after) 0 else start.position;
    const gaps = end.word - word;
    const length = d.n(text.prefix[end.word]) - d.n(text.prefix[word]) - d.n(position) + d.n(end.position) + d.n(gaps) + @as(i64,
         @intFromBool(end.hyphen));
    return .{ .length = d.u(length), .slack = d.n(if (a == 0) context.first else context.later) - length,
         .gaps = gaps, .mid = end.mid, .last = b == text.breaks.len - 1, .previous_mid = start.mid };
}
fn pieces(text: TextData, a: usize, b: usize) []renderer.Piece {
    const start = text.breaks[a];
    const end = text.breaks[b];
    const first_word = if (start.after) start.word + 1 else start.word;
    const start_position = if (start.after) 0 else start.position;
    var out: std.ArrayList(renderer.Piece) = .empty;
    for (first_word..end.word + 1) |word| {
        const first = if (word == first_word) start_position else 0;
        const last = if (word == end.word) end.position else text.words[word].len;
        const value = d.dupe(u8, text.words[word][first..last]);
        for (value) |*c| if (c.* == '~') {
            c.* = ' ';
        };
        d.append(renderer.Piece, &out, .{ .word = word, .first = first, .last = last, .text = if (word == end.word and end.hyphen) d.fmt("{s}-",
             .{value}) else value });
    }
    return out.items;
}
const TextResult = struct { lines: []pb.Line, measures: []lb.Measure, cost: i64 };
fn layoutText(c: *const Context, text: TextData, first: usize, later: usize, alignment: []const u8,
     first_prefix: []const u8, later_prefix: []const u8, greedy: bool) TextResult {
    const context: MeasureContext = .{ .text = &text, .first = first, .later = later };
    const breaking = lb.breakLines(text.breaks.len - 1, context, measureLine, c.params, greedy);
    var lines: std.ArrayList(pb.Line) = .empty;
    var measures: std.ArrayList(lb.Measure) = .empty;
    var a: usize = 0;
    for (breaking.ends) |b| {
        const line = measureLine(context, a, b);
        const parts = pieces(text, a, b);
        var footnotes: std.ArrayList(usize) = .empty;
        var indices: std.ArrayList(usize) = .empty;
        for (text.marks) |mark| for (parts) |piece| {
            if (mark.word == piece.word and piece.first <= mark.position and mark.position < piece.last) {
                if (mark.footnote) d.append(usize, &footnotes, mark.id) else d.append(usize, &indices, mark.id);
            }
        };
        d.append(pb.Line, &lines, .{ .text = d.fmt("{s}{s}", .{ if (a == 0) first_prefix else later_prefix,
             renderer.line(parts, line, alignment) }), .footnotes = footnotes.items, .indices = indices.items });
        d.append(lb.Measure, &measures, line);
        a = b;
    }
    return .{ .lines = lines.items, .measures = measures.items, .cost = breaking.cost };
}
const BrokenReport = struct { name: []const u8, alignment: []const u8, body: bool, lines: []lb.Measure };
const BodyStat = struct { lines: usize = 0, cost: i64 = 0 };
const Layout = struct { pages: []pb.Page, footnotes: []d.Lines, block_pages: []usize, index_pages: []i64,
     stats: []BodyStat, reports: []BrokenReport, front: usize = 0, hyphenated: usize = 0 };
fn roman(value: usize) []const u8 {
    const small = [_][]const u8{ "", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix" };
    const tens = d.alloc(u8, value / 10);
    @memset(tens, 'x');
    return d.fmt("{s}{s}", .{ tens, small[value % 10] });
}
const IndexEntry = struct { name: []const u8, key: []const u8, pages: std.ArrayList(i64) = .empty,
     references: std.ArrayList([]const u8) = .empty, children: std.ArrayList(*IndexEntry) = .empty };
fn indexEntry(entries: *std.ArrayList(*IndexEntry), name: []const u8) *IndexEntry {
    for (entries.items) |entry| if (d.eq(entry.name, name)) return entry;
    const storage = d.alloc(IndexEntry, 1);
    storage[0] = .{ .name = name, .key = d.lower(name) };
    d.append(*IndexEntry, entries, &storage[0]);
    return &storage[0];
}
fn indexLess(_: void, a: *IndexEntry, b: *IndexEntry) bool {
    const order = std.mem.order(u8, a.key, b.key);
    return if (order != .eq) order == .lt else std.mem.order(u8, a.name, b.name) == .lt;
}
fn integerLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
fn pageList(pages: []i64) []const u8 {
    std.mem.sort(i64, pages, {}, integerLess);
    var unique: std.ArrayList(i64) = .empty;
    for (pages, 0..) |page, i| if (i == 0 or page != pages[i - 1]) d.append(i64, &unique, page);
    var values: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < unique.items.len) {
        var end = i + 1;
        while (end < unique.items.len and unique.items[end] == unique.items[end - 1] + 1) end += 1;
        if (end - i >= 3) d.append([]const u8, &values, d.fmt("{d}-{d}", .{ unique.items[i], unique.items[end - 1] })) else for (unique.items[i..end]) |page| d.append([]const u8,
             &values, d.fmt("{d}", .{page}));
        i = end;
    }
    return d.join(values.items, ", ");
}
fn indexLine(name: []const u8, entry: *IndexEntry) []const u8 {
    var text: d.Text = .{};
    text.add("{s}", .{name});
    if (entry.pages.items.len > 0) text.add(", {s}", .{pageList(entry.pages.items)});
    if (entry.references.items.len > 0) {
        std.mem.sort([]const u8, entry.references.items, {}, stringLess);
        var unique: std.ArrayList([]const u8) = .empty;
        for (entry.references.items, 0..) |reference, i| if (i == 0 or !d.eq(reference, entry.references.items[i - 1])) d.append([]const u8,
             &unique, reference);
        text.add(", see {s}", .{d.join(unique.items, ", ")});
    }
    return text.value();
}
fn indexLines(c: *const Context, pages: []const i64) d.Lines {
    var parents: std.ArrayList(*IndexEntry) = .empty;
    for (c.index_phrases.items, pages) |phrase, page| {
        const bar = std.mem.indexOfScalar(u8, phrase, '|');
        const entry = phrase[0..(bar orelse phrase.len)];
        const bang = std.mem.indexOfScalar(u8, entry, '!');
        const parent = entry[0..(bang orelse entry.len)];
        var node = indexEntry(&parents, parent);
        if (bang) |position| node = indexEntry(&node.children, entry[position + 1 ..]);
        if (bar) |position| d.append([]const u8, &node.references, phrase[position + 1 ..]) else d.append(i64, &node.pages, page);
    }
    std.mem.sort(*IndexEntry, parents.items, {}, indexLess);
    var out: d.Lines = .{};
    var previous: []const u8 = "";
    for (parents.items) |entry| {
        const group = if (d.letter(entry.name[0])) d.upper(entry.name[0..1]) else "Symbols";
        if (!d.eq(group, previous)) {
            out.add("{s}", .{group});
            previous = group;
        }
        out.add("{s}", .{indexLine(entry.name, entry)});
        std.mem.sort(*IndexEntry, entry.children.items, {}, indexLess);
        for (entry.children.items) |child| out.add("{s}", .{indexLine(d.fmt("  {s}", .{child.name}), child)});
    }
    return out;
}
fn entryLine(target: d.Block, width: usize, page: []const u8) []const u8 {
    const left = if (target.kind == .table) d.fmt("Table {s}. {s}", .{ target.number, target.caption }) else d.fmt("{s}{s} {s}",
         .{ if (target.kind == .h2) "  " else "", target.number, target.text });
    const dots = d.alloc(u8, width - left.len - page.len - 2);
    @memset(dots, '.');
    return d.fmt("{s} {s} {s}", .{ left, dots, page });
}
fn plainLines(values: []const []const u8) []pb.Line {
    const out = d.alloc(pb.Line, values.len);
    for (values, out) |text, *line| line.* = .{ .text = text };
    return out;
}
fn addLayout(out: *std.ArrayList(pb.Block), lines: []pb.Line, type_: pb.Type, list: bool, page_break: bool,
     first: *bool, block: usize) void {
    if (first.* and lines.len > 0) lines[0].first_block = block;
    d.append(pb.Block, out, .{ .lines = lines, .type_ = type_, .list = list, .page_break = first.* and page_break });
    first.* = false;
}
fn layoutOnce(c: *const Context, page_values: std.StringHashMap([]const u8), greedy: bool) Layout {
    const doc = &c.document;
    const footnotes = d.alloc(d.Lines, c.footnotes.items.len);
    @memset(footnotes, .{});
    var footnote_reports: std.ArrayList(BrokenReport) = .empty;
    for (c.footnotes.items, footnotes, 0..) |text, *lines, i| {
        const prefix = d.fmt("[{d}] ", .{i + 1});
        const data = textData(d.words(text), &.{}, c);
        const result = layoutText(c, data, doc.width - prefix.len, doc.width - prefix.len, "left",
             prefix, d.spaces(prefix.len), greedy);
        for (result.lines) |line| lines.add("{s}", .{line.text});
        d.append(BrokenReport, &footnote_reports, .{ .name = d.fmt("footnote {d}", .{i + 1}), .alignment = "left",
             .body = false, .lines = result.measures });
    }
    var body_count: usize = 0;
    for (doc.blocks.items) |block| if (block.body_number) |number| {
        body_count = @max(body_count, number + 1);
    };
    const stats = d.alloc(BodyStat, body_count);
    @memset(stats, .{});
    var reports: std.ArrayList(BrokenReport) = .empty;
    var layout_blocks: std.ArrayList(pb.Block) = .empty;
    const unknown_index_pages = d.alloc(i64, c.index_phrases.items.len);
    @memset(unknown_index_pages, 0);
    const index = indexLines(c, unknown_index_pages);
    var bibliography_prefix: usize = 0;
    for (c.bib_order) |id| bibliography_prefix = @max(bibliography_prefix, doc.bibliography.items[id].label.len + 3);
    var hyphenated: usize = 0;
    for (doc.blocks.items, 0..) |block, b| {
        var first = true;
        if (d.bodyKind(block.kind)) {
            var first_capacity = block.width;
            var later_capacity = block.width;
            var first_prefix: []const u8 = "";
            var later_prefix: []const u8 = "";
            switch (block.kind) {
                .paragraph => {
                    first_capacity -= block.indent;
                    first_prefix = d.spaces(block.indent);
                },
                .item => {
                    first_capacity -= 2;
                    later_capacity -= 2;
                    first_prefix = "- ";
                    later_prefix = "  ";
                },
                .enum_ => {
                    first_capacity -= 4;
                    later_capacity -= 4;
                    first_prefix = d.fmt("{s}{s}. ", .{ d.spaces(2 - block.number.len), block.number });
                    later_prefix = "    ";
                },
                .quote => {
                    first_capacity -= 8;
                    later_capacity -= 8;
                    first_prefix = "    ";
                    later_prefix = "    ";
                },
                .term => {
                    first_capacity -= 12;
                    later_capacity -= 12;
                    first_prefix = if (block.term.len <= 10) d.fmt("{s}{s}", .{ block.term, d.spaces(12 - block.term.len) }) else d.spaces(12);
                    later_prefix = d.spaces(12);
                },
                else => unreachable,
            }
            const result = layoutText(c, expand(block, c, page_values), first_capacity, later_capacity,
                 block.alignment, first_prefix, later_prefix, greedy);
            var lines: std.ArrayList(pb.Line) = .empty;
            if (block.kind == .term and block.term.len >= 11) d.append(pb.Line, &lines, .{ .text = block.term });
            for (result.lines) |line| d.append(pb.Line, &lines, line);
            addLayout(&layout_blocks, lines.items, .flow, block.kind == .item or block.kind == .enum_ or block.kind == .term,
                 block.page_break, &first, b);
            d.append(BrokenReport, &reports, .{ .name = d.fmt("paragraph {d}", .{block.body_number.? + 1}),
                 .alignment = block.alignment, .body = true, .lines = result.measures });
            stats[block.body_number.?] = .{ .lines = result.measures.len, .cost = result.cost };
            for (result.measures) |line| if (line.mid) {
                hyphenated += 1;
            };
        } else if (block.kind == .title or block.kind == .author) {
            const text = if (block.kind == .title) d.upper(block.text) else block.text;
            const values = [_][]const u8{d.fmt("{s}{s}", .{ d.spaces((block.width - text.len) / 2), text })};
            addLayout(&layout_blocks, plainLines(&values), .heading, false, block.page_break, &first, b);
        } else if (block.kind == .h1 or block.kind == .h2) {
            const text = d.fmt("{s} {s}", .{ block.number, if (block.kind == .h1) d.upper(block.text) else block.text });
            const rule = d.alloc(u8, text.len);
            @memset(rule, if (block.kind == .h1) '=' else '-');
            addLayout(&layout_blocks, plainLines(&.{ text, rule }), .heading, false, block.page_break, &first, b);
        } else if (block.kind == .table) addLayout(&layout_blocks, plainLines(renderer.table(block).data.items),
             .solid, false, block.page_break, &first, b) else if (block.kind == .verbatim) {
            const values = d.alloc([]const u8, block.inner.items.len);
            for (block.inner.items, values) |line, *value| value.* = line.text;
            addLayout(&layout_blocks, plainLines(values), .flow, false, block.page_break, &first, b);
        } else if (block.kind == .toc or block.kind == .lot) {
            addLayout(&layout_blocks, plainLines(if (block.kind == .toc) &.{ "CONTENTS", "========" } else &.{ "TABLES",
                 "======" }), .heading, false, block.page_break, &first, b);
            var lines: std.ArrayList(pb.Line) = .empty;
            for (doc.blocks.items, 0..) |target, target_index| {
                const include = if (block.kind == .toc) target.kind == .h1 or target.kind == .h2 else target.kind == .table and target.caption.len > 0;
                if (include) d.append(pb.Line, &lines, .{ .text = entryLine(target, block.width, "??"),
                     .toc_target = target_index, .dynamic_width = block.width });
            }
            addLayout(&layout_blocks, lines.items, .flow, false, block.page_break, &first, b);
        } else if (block.kind == .index) {
            addLayout(&layout_blocks, plainLines(&.{ "INDEX", "=====" }), .heading, false, block.page_break, &first, b);
            const lines = d.alloc(pb.Line, index.data.items.len);
            for (index.data.items, lines, 0..) |text, *line, i| line.* = .{ .text = text, .index_entry = i };
            addLayout(&layout_blocks, lines, .flow, false, block.page_break, &first, b);
        } else {
            addLayout(&layout_blocks, plainLines(&.{ "REFERENCES", "==========" }), .heading, false, block.page_break, &first, b);
            for (c.bib_order) |id| {
                const entry = doc.bibliography.items[id];
                const label = d.fmt("[{s}]", .{entry.label});
                const data = textData(d.words(d.fmt("{s}. {s}. {s}", .{ entry.author, entry.year, entry.title })), &.{}, c);
                const result = layoutText(c, data, block.width - bibliography_prefix, block.width - bibliography_prefix,
                     "left", d.fmt("{s}{s}", .{ label, d.spaces(bibliography_prefix - label.len) }),
                     d.spaces(bibliography_prefix), greedy);
                addLayout(&layout_blocks, result.lines, .flow, true, block.page_break, &first, b);
                d.append(BrokenReport, &reports, .{ .name = d.fmt("reference {s}", .{entry.label}),
                     .alignment = "left", .body = false, .lines = result.measures });
            }
        }
    }
    const raw = pb.build(layout_blocks.items, footnotes, c.params, doc.height);
    var pages: std.ArrayList(pb.Page) = .empty;
    for (raw) |page| {
        const chapter = page.content.len > 0 and page.content[0].first_block != null and doc.blocks.items[page.content[0].first_block.?].kind == .h1;
        if (chapter and (pages.items.len + 1) % 2 == 0) d.append(pb.Page, &pages, .{ .blank = true });
        d.append(pb.Page, &pages, page);
    }
    const block_pages = d.alloc(usize, doc.blocks.items.len);
    @memset(block_pages, 0);
    for (pages.items, 1..) |page, serial| for (page.content) |line| {
        if (line.first_block) |block| block_pages[block] = serial;
    };
    var front: usize = 0;
    for (doc.blocks.items, block_pages) |block, page| if (block.kind == .h1) {
        front = page - 1;
        break;
    };
    for (pages.items, 1..) |*page, serial| {
        page.body_number = d.n(serial) - d.n(front);
        page.display = if (serial <= front) roman(serial) else d.fmt("{d}", .{page.body_number});
    }
    const index_pages = d.alloc(i64, c.index_phrases.items.len);
    @memset(index_pages, 0);
    for (pages.items) |page| for (page.content) |line| {
        for (line.indices) |id| index_pages[id] = page.body_number;
    };
    for (footnote_reports.items) |report| d.append(BrokenReport, &reports, report);
    return .{ .pages = pages.items, .footnotes = footnotes, .block_pages = block_pages, .index_pages = index_pages,
         .stats = stats, .reports = reports.items, .front = front, .hyphenated = hyphenated };
}
fn layout(c: *const Context, greedy: bool) Layout {
    var values = std.StringHashMap([]const u8).init(d.allocator);
    var iterator = c.labels.keyIterator();
    while (iterator.next()) |label| values.put(label.*, "??") catch @panic("allocation failed");
    var result: Layout = undefined;
    while (true) {
        result = layoutOnce(c, values, greedy);
        var computed = std.StringHashMap([]const u8).init(d.allocator);
        var equal = true;
        var labels = c.labels.iterator();
        while (labels.next()) |entry| {
            const value = result.pages[result.block_pages[entry.value_ptr.*] - 1].display;
            computed.put(entry.key_ptr.*, value) catch @panic("allocation failed");
            if (!d.eq(value, values.get(entry.key_ptr.*).?)) equal = false;
        }
        if (equal) break;
        values = computed;
    }
    const index = indexLines(c, result.index_pages);
    for (result.pages) |*page| for (page.content) |*line| {
        if (line.toc_target) |target| line.text = entryLine(c.document.blocks.items[target], line.dynamic_width,
             result.pages[result.block_pages[target] - 1].display);
        if (line.index_entry) |entry| line.text = index.data.items[entry];
    };
    return result;
}
fn layoutWarnings(c: *const Context, result: Layout, method: []const u8) d.Lines {
    var out: d.Lines = .{};
    for (result.reports) |report| for (report.lines, 1..) |line, i| {
        if (line.slack < 0) out.add("{s}: {s} line {d}: overfull by {d}", .{ method, report.name,
             i, -line.slack }) else if (report.body and d.eq(report.alignment, "justify") and !line.last and line.slack >= c.params.underfull_slack) out.add("{s}: {s} line {d}: underfull, slack {d}",
             .{ method, report.name, i, line.slack });
    };
    for (result.pages, 1..) |page, i| {
        const empty = c.document.height - page.height;
        if (!page.blank and !page.forced and d.n(empty) >= c.params.underfull_page) out.add("{s}: page {d}: underfull, {d} empty lines",
             .{ method, i, empty });
    }
    out.add("{s}: {d} pages, {d} hyphenated lines", .{ method, result.pages.len, result.hyphenated });
    return out;
}
fn write(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    var params: d.Params = .{};
    for (try d.readLines(init.io, "input/params.txt")) |line| {
        const fields = d.split(line, ' ');
        inline for (std.meta.fields(d.Params)) |field| if (d.eq(fields[0], field.name)) {
            @field(params, field.name) = d.number(fields[1]);
        };
    }
    var c: Context = .{ .document = d.parse(try d.readLines(init.io, "input/document.txt")), .params = params,
         .dictionary = hyphenation.Dictionary.init(d.allocator), .labels = std.StringHashMap(usize).init(d.allocator),
         .bib_keys = std.StringHashMap(usize).init(d.allocator) };
    for (try d.readLines(init.io, "input/hyphenation.txt")) |word| hyphenation.register(&c.dictionary, word);
    for (c.document.additions.items) |word| hyphenation.register(&c.dictionary, word);
    prepare(&c);
    const kp = layout(&c, false);
    const greedy = layout(&c, true);
    try write(init.io, "pages.txt", renderer.pages(kp.pages, kp.footnotes, &c.document, kp.block_pages, kp.front));
    try write(init.io, "greedy_pages.txt", renderer.pages(greedy.pages, greedy.footnotes, &c.document,
         greedy.block_pages, greedy.front));
    var stats: d.Lines = .{};
    stats.add("paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy", .{});
    var totals = std.mem.zeroes([4]i64);
    for (kp.stats, greedy.stats, 1..) |a, b, i| {
        stats.add("{d},{d},{d},{d},{d}", .{ i, a.lines, a.cost, b.lines, b.cost });
        totals[0] += d.n(a.lines);
        totals[1] += a.cost;
        totals[2] += d.n(b.lines);
        totals[3] += b.cost;
    }
    stats.add("total,{d},{d},{d},{d}", .{ totals[0], totals[1], totals[2], totals[3] });
    try write(init.io, "stats.csv", stats);
    var logs: d.Lines = .{};
    for (c.document.warnings.items) |warning| logs.add("line {d}: {s}", .{ warning.line, warning.message });
    logs.extend(layoutWarnings(&c, kp, "kp"));
    logs.extend(layoutWarnings(&c, greedy, "greedy"));
    try write(init.io, "log.txt", logs);
}
