const std = @import("std");
const d = @import("document_parser.zig");
const lb = @import("line_breaker.zig");
const pb = @import("page_builder.zig");
pub const Piece = struct { word: usize, first: usize, last: usize, text: []const u8 };
pub fn line(pieces: []const Piece, measure: lb.Measure, alignment: []const u8) []const u8 {
    var gap: usize = 1;
    var remainder: usize = 0;
    if (measure.slack > 0 and d.eq(alignment, "justify") and !measure.last and measure.gaps > 0) {
        gap += d.u(measure.slack) / measure.gaps;
        remainder = d.u(measure.slack) % measure.gaps;
    }
    var out: d.Text = .{};
    if (measure.slack > 0) {
        if (d.eq(alignment, "right")) out.add("{s}", .{d.spaces(d.u(measure.slack))}) else if (d.eq(alignment,
             "center")) out.add("{s}", .{d.spaces(d.u(measure.slack) / 2)});
    }
    for (pieces, 0..) |piece, i| {
        if (i > 0) out.add("{s}", .{d.spaces(gap + @intFromBool(i - 1 < remainder))});
        out.add("{s}", .{piece.text});
    }
    return out.value();
}
pub fn table(block: d.Block) d.Lines {
    const widths = d.alloc(usize, block.columns.len);
    @memset(widths, 0);
    for (block.cells) |row| for (row, widths) |cell, *width| {
        width.* = @max(width.*, cell.len);
    };
    var out: d.Lines = .{};
    if (block.caption.len > 0) out.add("Table {s}. {s}", .{ block.number, block.caption });
    for (block.cells, 0..) |row, index| {
        const cells = d.alloc([]const u8, widths.len);
        for (row, widths, block.columns, cells) |value, width, alignment, *cell| {
            const missing = width - value.len;
            cell.* = if (alignment == 'l') d.fmt("{s}{s}", .{ value, d.spaces(missing) }) else if (alignment == 'r') d.fmt("{s}{s}",
                 .{ d.spaces(missing), value }) else d.fmt("{s}{s}{s}", .{ d.spaces(missing / 2),
                 value, d.spaces(missing - missing / 2) });
        }
        out.add("{s}", .{d.rtrim(d.join(cells, " | "))});
        if (index == 0) {
            const rules = d.alloc([]const u8, widths.len);
            for (widths, rules) |width, *rule| {
                const text = d.alloc(u8, width);
                @memset(text, '-');
                rule.* = text;
            }
            out.add("{s}", .{d.join(rules, "-+-")});
        }
    }
    return out;
}
fn replace(text: []const u8, key: []const u8, value: []const u8) []const u8 {
    var out: d.Text = .{};
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, text, cursor, key)) |found| {
        out.add("{s}{s}", .{ text[cursor..found], value });
        cursor = found + key.len;
    }
    out.add("{s}", .{text[cursor..]});
    return out.value();
}
pub const HeadValues = struct { page: []const u8, pages: []const u8, chapter: []const u8, section: []const u8 };
pub fn runningHead(fields_: [3][]const u8, values: HeadValues, width: usize, serial: usize) []const u8 {
    var fields = fields_;
    for (&fields) |*field| {
        for ([_][]const u8{ "{page}", "{pages}", "{chapter}", "{section}" }, [_][]const u8{ values.page,
             values.pages, values.chapter, values.section }) |key, value| field.* = replace(field.*,
             key, value);
    }
    if (serial % 2 == 0) std.mem.swap([]const u8, &fields[0], &fields[2]);
    const result = d.alloc(u8, width);
    @memset(result, ' ');
    @memcpy(result[0..fields[0].len], fields[0]);
    const middle = (width - fields[1].len) / 2;
    @memcpy(result[middle .. middle + fields[1].len], fields[1]);
    @memcpy(result[width - fields[2].len ..], fields[2]);
    return d.rtrim(result);
}
pub fn pages(pages_: []const pb.Page, footnotes: []const d.Lines, doc: *const d.Document, block_pages: []const usize,
     front: usize) d.Lines {
    var out: d.Lines = .{};
    for (pages_, 0..) |page, i| {
        out.add("--- page {d} ---", .{i + 1});
        var chapter: []const u8 = "";
        var section: []const u8 = "";
        for (doc.blocks.items, block_pages) |block, block_page| if (block_page > 0 and block_page <= i + 1) {
            if (block.kind == .h1) {
                chapter = d.fmt("{s} {s}", .{ block.number, block.text });
                section = "";
            } else if (block.kind == .h2) section = d.fmt("{s} {s}", .{ block.number, block.text });
        };
        const first_chapter = page.content.len > 0 and page.content[0].first_block != null and doc.blocks.items[page.content[0].first_block.?].kind == .h1;
        const values: HeadValues = .{ .page = page.display, .pages = d.fmt("{d}", .{pages_.len - front}),
             .chapter = chapter, .section = section };
        out.add("{s}", .{if (page.blank or first_chapter) "" else runningHead(doc.header, values, doc.width, i + 1)});
        out.add("", .{});
        var note_height: usize = 0;
        for (page.footnotes) |id| note_height += footnotes[id].data.items.len;
        for (page.content) |content| out.add("{s}", .{content.text});
        const pad = doc.height - note_height - @as(usize, @intFromBool(page.footnotes.len > 0)) - page.content.len;
        for (0..pad) |_| out.add("", .{});
        if (page.footnotes.len > 0) {
            out.add("----------", .{});
            for (page.footnotes) |id| out.extend(footnotes[id]);
        }
        out.add("", .{});
        out.add("{s}", .{if (page.blank) "" else runningHead(doc.footer, values, doc.width, i + 1)});
    }
    return out;
}
