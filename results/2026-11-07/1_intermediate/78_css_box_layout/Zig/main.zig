const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error;
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn number(s: Text) Int {
    return std.fmt.parseInt(Int, s, 10) catch unreachable;
}
fn u(n: Int) usize {
    return @intCast(n);
}
fn si(n: usize) Int {
    return @intCast(n);
}
fn unsigned(s: Text) bool {
    if (s.len == 0 or s.len > 3) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn positive(s: Text) bool {
    return unsigned(s) and number(s) > 0;
}
fn signed(s: Text) bool {
    return unsigned(s) or std.mem.startsWith(u8, s, "-") and unsigned(s[1..]);
}
fn percentage(s: Text) bool {
    return std.mem.endsWith(u8, s, "%") and unsigned(s[0 .. s.len - 1]);
}
fn oneOf(s: Text, choices: []const Text) bool {
    for (choices) |choice| if (equal(s, choice)) return true;
    return false;
}
fn split(gpa: Allocator, s: Text, separator: Text) Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    while (std.mem.find(u8, s[start..], separator)) |offset| {
        const at = start + offset;
        try result.append(gpa, s[start..at]);
        start = at + separator.len;
    }
    try result.append(gpa, s[start..]);
    return result.items;
}
fn join(gpa: Allocator, list: []const Text, separator: Text) Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (list, 0..) |item, i| {
        if (i > 0) try out.add(separator);
        try out.add(item);
    }
    return out.bytes.items;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, s: Text) Error!void {
        try self.bytes.appendSlice(self.gpa, s);
    }
    fn print(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, format, args));
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Error!void {
        try self.print(format ++ "\n", args);
    }
};
const Property = enum {
    display,
    position,
    @"box-sizing",
    width,
    height,
    @"min-width",
    @"min-height",
    @"max-width",
    @"max-height",
    @"margin-top",
    @"margin-right",
    @"margin-bottom",
    @"margin-left",
    @"padding-top",
    @"padding-right",
    @"padding-bottom",
    @"padding-left",
    @"border-top",
    @"border-right",
    @"border-bottom",
    @"border-left",
    top,
    right,
    bottom,
    left,
    @"flex-direction",
    @"flex-wrap",
    @"justify-content",
    @"align-items",
    @"align-self",
    @"row-gap",
    @"column-gap",
    order,
    @"flex-grow",
    @"flex-shrink",
    @"flex-basis",
    @"grid-template-columns",
    @"grid-template-rows",
    @"grid-column",
    @"grid-row",
};
const propertyCount = std.meta.fields(Property).len;
const defaults = [propertyCount]Text{
    "block", "static",  "content-box", "auto", "auto", "0",    "0",    "none", "none",
    "0",     "0",       "0",           "0",    "0",    "0",    "0",    "0",    "0",
    "0",     "0",       "0",           "auto", "auto", "auto", "auto", "row",  "nowrap",
    "start", "stretch", "auto",        "0",    "0",    "0",    "0",    "1",    "auto",
    "none",  "none",    "auto",        "auto",
};
const Declaration = struct { property: Property, value: Text };
fn property(name: Text) ?Property {
    return std.meta.stringToEnum(Property, name);
}
fn gridValue(value: Text, parts: []const Text) bool {
    if (parts.len == 1) return equal(value, "auto") or positive(parts[0]);
    if (parts.len == 2) return equal(parts[0], "span") and positive(parts[1]);
    if (parts.len == 3) return positive(parts[0]) and equal(parts[1], "/") and positive(parts[2]) and number(parts[0]) < number(parts[2]);
    return parts.len == 4 and positive(parts[0]) and equal(parts[1], "/") and equal(parts[2], "span") and positive(parts[3]);
}
fn valid(gpa: Allocator, name: Text, value: Text) Error!?[]Declaration {
    const parts = try split(gpa, value, " ");
    var result: std.ArrayList(Declaration) = .empty;
    if (oneOf(name, &.{ "margin", "padding", "border", "gap" })) {
        if (parts.len == 0 or parts.len > (if (equal(name, "gap")) @as(usize, 2) else 4)) return null;
        for (parts) |part| if (!unsigned(part) or equal(name, "border") and !oneOf(part, &.{ "0", "1" })) return null;
        if (equal(name, "gap")) {
            try result.append(gpa, .{ .property = .@"row-gap", .value = parts[0] });
            try result.append(gpa, .{ .property = .@"column-gap", .value = if (parts.len == 2) parts[1] else parts[0] });
        } else {
            const values = [4]Text{ parts[0], if (parts.len > 1) parts[1] else parts[0], if (parts.len > 2) parts[2] else parts[0], if (parts.len > 3) parts[3] else if (parts.len > 1) parts[1] else parts[0] };
            for ([_]Text{ "top", "right", "bottom", "left" }, 0..) |side, i| {
                const longhand = try std.fmt.allocPrint(gpa, "{s}-{s}", .{ name, side });
                try result.append(gpa, .{ .property = property(longhand).?, .value = values[i] });
            }
        }
        return result.items;
    }
    const p = property(name) orelse return null;
    var good = false;
    if (p == .@"grid-template-columns" or p == .@"grid-template-rows") {
        good = equal(value, "none");
        if (!good) {
            good = true;
            for (parts) |part| {
                if (!unsigned(part) and !equal(part, "auto") and !(std.mem.endsWith(u8, part, "fr") and positive(part[0 .. part.len - 2]))) {
                    good = false;
                    break;
                }
            }
        }
    } else if (p == .@"grid-column" or p == .@"grid-row") {
        good = gridValue(value, parts);
    } else if (parts.len == 1) {
        good = switch (p) {
            .display => oneOf(value, &.{ "block", "flex", "grid", "none" }),
            .position => oneOf(value, &.{ "static", "relative", "absolute" }),
            .@"box-sizing" => oneOf(value, &.{ "content-box", "border-box" }),
            .width, .height, .@"flex-basis" => equal(value, "auto") or unsigned(value) or percentage(value),
            .@"min-width", .@"min-height" => unsigned(value) or percentage(value),
            .@"max-width", .@"max-height" => equal(value, "none") or unsigned(value) or percentage(value),
            .top, .right, .bottom, .left => equal(value, "auto") or signed(value),
            .@"flex-direction" => oneOf(value, &.{ "row", "row-reverse", "column", "column-reverse" }),
            .@"flex-wrap" => oneOf(value, &.{ "nowrap", "wrap" }),
            .@"justify-content" => oneOf(value, &.{ "start", "end", "center", "space-between", "space-around", "space-evenly" }),
            .@"align-items" => oneOf(value, &.{ "stretch", "start", "end", "center" }),
            .@"align-self" => oneOf(value, &.{ "auto", "stretch", "start", "end", "center" }),
            .order => signed(value),
            .@"border-top", .@"border-right", .@"border-bottom", .@"border-left" => oneOf(value, &.{ "0", "1" }),
            else => unsigned(value),
        };
    }
    if (!good) return null;
    try result.append(gpa, .{ .property = p, .value = value });
    return result.items;
}
const Rule = struct { selectors: []const Text, declarations: []const Declaration };
const Rect = struct { x: Int, y: Int, w: Int, h: Int };
const Element = struct {
    kind: Text,
    id: Text,
    text: ?Text = null,
    classes: []const Text,
    parent: ?*Element = null,
    children: std.ArrayList(*Element) = .empty,
    depth: usize,
    index: usize,
    overrides: [propertyCount]?Text = @as([propertyCount]?Text, @splat(null)),
    style: [propertyCount]Text = defaults,
    displayed: bool = false,
    cw: Int = 0,
    ch: Int = 0,
    rx: Int = 0,
    ry: Int = 0,
    x: Int = 0,
    y: Int = 0,
    lines: []const Text = &.{},
    containing: ?*Element = null,
    fn s(self: *const Element, p: Property) Text {
        return self.style[@backingInt(p)];
    }
    fn n(self: *const Element, p: Property) Int {
        return number(self.s(p));
    }
    fn frame(self: *const Element, horizontal: bool) Int {
        return if (horizontal) self.n(.@"padding-left") + self.n(.@"padding-right") + self.n(.@"border-left") + self.n(.@"border-right") else self.n(.@"padding-top") + self.n(.@"padding-bottom") + self.n(.@"border-top") + self.n(.@"border-bottom");
    }
    fn margin(self: *const Element, horizontal: bool) Int {
        return if (horizontal) self.n(.@"margin-left") + self.n(.@"margin-right") else self.n(.@"margin-top") + self.n(.@"margin-bottom");
    }
    fn resolve(self: *const Element, p: Property, reference: ?Int, horizontal: bool) ?Int {
        const value = self.s(p);
        if (equal(value, "auto") or equal(value, "none")) return null;
        var nvalue: Int = 0;
        if (std.mem.endsWith(u8, value, "%")) {
            const r = reference orelse return null;
            nvalue = @divTrunc(r * number(value[0 .. value.len - 1]), 100);
        } else {
            nvalue = number(value);
        }
        if (equal(self.s(.@"box-sizing"), "border-box")) nvalue = @max(0, nvalue - self.frame(horizontal));
        return nvalue;
    }
    fn clamp(self: *const Element, value: Int, reference: ?Int, horizontal: bool) Int {
        const lower = self.resolve(if (horizontal) .@"min-width" else .@"min-height", reference, horizontal) orelse 0;
        const upper = self.resolve(if (horizontal) .@"max-width" else .@"max-height", reference, horizontal);
        return @max(lower, if (upper) |limit| @min(value, limit) else value);
    }
    fn flow(self: *const Element, gpa: Allocator) Error![]*Element {
        var result: std.ArrayList(*Element) = .empty;
        for (self.children.items) |child| if (child.displayed and !equal(child.s(.position), "absolute")) try result.append(gpa, child);
        return result.items;
    }
    fn items(self: *const Element, gpa: Allocator) Error![]*Element {
        const result = try self.flow(gpa);
        std.mem.sort(*Element, result, {}, itemLess);
        return result;
    }
    fn alignment(self: *const Element, parent: *const Element) Text {
        return if (equal(self.s(.@"align-self"), "auto")) parent.s(.@"align-items") else self.s(.@"align-self");
    }
    fn border(self: *const Element) Rect {
        return .{ .x = self.x, .y = self.y, .w = self.cw + self.frame(true), .h = self.ch + self.frame(false) };
    }
    fn content(self: *const Element) Rect {
        return .{ .x = self.x + self.n(.@"border-left") + self.n(.@"padding-left"), .y = self.y + self.n(.@"border-top") + self.n(.@"padding-top"), .w = self.cw, .h = self.ch };
    }
    fn marginBox(self: *const Element) Rect {
        const r = self.border();
        return .{ .x = r.x - self.n(.@"margin-left"), .y = r.y - self.n(.@"margin-top"), .w = r.w + self.margin(true), .h = r.h + self.margin(false) };
    }
};
fn itemLess(_: void, a: *Element, b: *Element) bool {
    return a.n(.order) < b.n(.order) or a.n(.order) == b.n(.order) and a.index < b.index;
}
fn sum(list: []const Int) Int {
    var result: Int = 0;
    for (list) |value| result += value;
    return result;
}
fn distribute(gpa: Allocator, total: Int, weights: []const Int) Error![]Int {
    const result = try gpa.alloc(Int, weights.len);
    @memset(result, 0);
    const totalWeight = sum(weights);
    if (totalWeight == 0) return result;
    var used: Int = 0;
    for (weights, 0..) |weight, i| {
        result[i] = @divTrunc(total * weight, totalWeight);
        used += result[i];
    }
    for (weights, 0..) |weight, i| {
        if (used == total) break;
        if (weight > 0) {
            result[i] += 1;
            used += 1;
        }
    }
    return result;
}
const GridSpec = struct { start: Int, span: Int };
fn gridSpec(gpa: Allocator, value: Text) Error!GridSpec {
    const parts = try split(gpa, value, " ");
    if (equal(value, "auto")) return .{ .start = 0, .span = 1 };
    if (equal(parts[0], "span")) return .{ .start = 0, .span = number(parts[1]) };
    const start = number(parts[0]);
    return .{ .start = start, .span = if (parts.len == 1) 1 else if (parts.len == 3) number(parts[2]) - start else number(parts[3]) };
}
const TrackKind = enum { fixed, auto, fr };
const Track = struct { kind: TrackKind, value: Int = 0 };
fn tracks(gpa: Allocator, value: Text, columns: bool) Error![]Track {
    var result: std.ArrayList(Track) = .empty;
    if (equal(value, "none")) {
        if (columns) try result.append(gpa, .{ .kind = .auto });
        return result.items;
    }
    for (try split(gpa, value, " ")) |word| {
        const t: Track = if (equal(word, "auto")) .{ .kind = .auto } else if (std.mem.endsWith(u8, word, "fr")) .{ .kind = .fr, .value = number(word[0 .. word.len - 2]) } else .{ .kind = .fixed, .value = number(word) };
        try result.append(gpa, t);
    }
    return result.items;
}
const Placement = struct { e: *Element, row: Int, col: Int, rows: Int, cols: Int };
const Grid = struct { items: []Placement, columns: Int, rows: Int };
const Cell = struct { row: Int, col: Int };
fn overlaps(occupied: std.AutoHashMapUnmanaged(Cell, void), p: Placement, r: Int, c: Int) bool {
    var y = r;
    while (y < r + p.rows) : (y += 1) {
        var x = c;
        while (x < c + p.cols) : (x += 1) if (occupied.contains(.{ .row = y, .col = x })) return true;
    }
    return false;
}
fn mark(gpa: Allocator, occupied: *std.AutoHashMapUnmanaged(Cell, void), p: Placement) Error!void {
    var y = p.row;
    while (y < p.row + p.rows) : (y += 1) {
        var x = p.col;
        while (x < p.col + p.cols) : (x += 1) try occupied.put(gpa, .{ .row = y, .col = x }, {});
    }
}
fn trackSizes(gpa: Allocator, spec: []const Track, count: Int, available: ?Int, gap: Int, items: []const Placement, contributions: []const Int, horizontal: bool) Error![]Int {
    const sizes = try gpa.alloc(Int, u(count));
    const weights = try gpa.alloc(Int, u(count));
    const kinds = try gpa.alloc(TrackKind, u(count));
    @memset(sizes, 0);
    @memset(weights, 0);
    var hasFR = false;
    for (sizes, 0..) |*size, i| {
        const t: Track = if (i < spec.len) spec[i] else .{ .kind = .auto };
        kinds[i] = t.kind;
        if (t.kind == .fixed) {
            size.* = t.value;
        } else if (t.kind == .auto or available == null) {
            for (items, 0..) |p, j| {
                const start = if (horizontal) p.col else p.row;
                const span = if (horizontal) p.cols else p.rows;
                if (start == si(i) + 1 and span == 1) size.* = @max(size.*, contributions[j]);
            }
        }
        if (t.kind == .fr) {
            weights[i] = t.value;
            hasFR = true;
        }
    }
    if (available != null and count > 0) {
        const left = available.? - sum(sizes) - gap * (count - 1);
        if (left > 0) {
            if (!hasFR) {
                for (kinds, 0..) |kind, i| if (kind == .auto) {
                    weights[i] = 1;
                };
            }
            const extra = try distribute(gpa, left, weights);
            for (sizes, extra) |*size, value| size.* += value;
        }
    }
    return sizes;
}
const Area = struct { size: Int, offset: Int };
fn area(sizes: []const Int, start: Int, span: Int, gap: Int) Area {
    return .{ .size = sum(sizes[u(start - 1)..u(start - 1 + span)]) + gap * (span - 1), .offset = sum(sizes[0..u(start - 1)]) + gap * (start - 1) };
}
fn position(e: *Element, child: *Element, x: Int, y: Int) void {
    child.rx = x + e.n(.@"border-left") + e.n(.@"padding-left");
    child.ry = y + e.n(.@"border-top") + e.n(.@"padding-top");
}
fn wrap(gpa: Allocator, text: Text, width: Int) Error![]Text {
    var lines: std.ArrayList(Text) = .empty;
    for (try split(gpa, text, " ")) |word| {
        if (lines.items.len == 0 or si(lines.items[lines.items.len - 1].len + 1 + word.len) > width) {
            try lines.append(gpa, word);
        } else {
            lines.items[lines.items.len - 1] = try std.fmt.allocPrint(gpa, "{s} {s}", .{ lines.items[lines.items.len - 1], word });
        }
    }
    return lines.items;
}
const FlexItem = struct { e: *Element, base: Int = 0, hypothetical: Int = 0, outer: Int = 0, cross: Int = 0, weight: Int = 0, size: Int = 0, frozen: bool = false };
const Document = struct {
    gpa: Allocator,
    temp: Allocator,
    out: *Builder,
    layoutArena: std.heap.ArenaAllocator,
    width: Int,
    height: Int,
    rules: std.ArrayList(Rule) = .empty,
    elements: std.ArrayList(*Element) = .empty,
    byID: std.StringHashMapUnmanaged(*Element) = .empty,
    fn placement(self: *Document, e: *Element) Error!Grid {
        const gpa = self.temp;
        var columns = si((try tracks(gpa, e.s(.@"grid-template-columns"), true)).len);
        var rows = si((try tracks(gpa, e.s(.@"grid-template-rows"), false)).len);
        var list: std.ArrayList(Placement) = .empty;
        for (try e.items(gpa)) |child| {
            const c = try gridSpec(gpa, child.s(.@"grid-column"));
            const r = try gridSpec(gpa, child.s(.@"grid-row"));
            try list.append(gpa, .{ .e = child, .row = r.start, .col = c.start, .rows = r.span, .cols = c.span });
            columns = @max(columns, if (c.start > 0) c.start + c.span - 1 else c.span);
        }
        var occupied: std.AutoHashMapUnmanaged(Cell, void) = .empty;
        for (list.items) |p| if (p.row > 0 and p.col > 0) try mark(gpa, &occupied, p);
        var cr: Int = 1;
        var cc: Int = 1;
        for (list.items) |*p| {
            if (p.row > 0 and p.col > 0) continue;
            if (p.row > 0) {
                p.col = 1;
                var c: Int = 1;
                while (c <= columns - p.cols + 1) : (c += 1) {
                    if (!overlaps(occupied, p.*, p.row, c)) {
                        p.col = c;
                        break;
                    }
                }
            } else if (p.col > 0) {
                if (p.col < cc) cr += 1;
                var r = cr;
                while (overlaps(occupied, p.*, r, p.col)) r += 1;
                p.row = r;
                cr = r;
                cc = p.col + p.cols;
            } else {
                var r = cr;
                var c = cc;
                while (true) {
                    if (c + p.cols - 1 > columns) {
                        r += 1;
                        c = 1;
                    } else if (overlaps(occupied, p.*, r, c)) {
                        c += 1;
                    } else break;
                }
                p.row = r;
                p.col = c;
                cr = r;
                cc = c + p.cols;
            }
            try mark(gpa, &occupied, p.*);
        }
        for (list.items) |p| rows = @max(rows, p.row + p.rows - 1);
        return .{ .items = list.items, .columns = columns, .rows = rows };
    }
    fn contribution(self: *Document, e: *Element) Error!Int {
        const width = e.resolve(.width, null, true) orelse try self.maxContent(e);
        return e.clamp(width, null, true) + e.frame(true) + e.margin(true);
    }
    fn maxContent(self: *Document, e: *Element) Error!Int {
        if (e.text) |text| return si(text.len);
        if (equal(e.s(.display), "flex") and std.mem.startsWith(u8, e.s(.@"flex-direction"), "row")) {
            const children = try e.flow(self.temp);
            var value: Int = 0;
            for (children) |child| value += try self.contribution(child);
            return value + if (children.len > 0) e.n(.@"column-gap") * (si(children.len) - 1) else 0;
        }
        if (equal(e.s(.display), "grid")) {
            const placed = try self.placement(e);
            const values = try self.temp.alloc(Int, placed.items.len);
            for (placed.items, 0..) |p, i| values[i] = try self.contribution(p.e);
            const sizes = try trackSizes(self.temp, try tracks(self.temp, e.s(.@"grid-template-columns"), true), placed.columns, null, e.n(.@"column-gap"), placed.items, values, true);
            return sum(sizes) + e.n(.@"column-gap") * (placed.columns - 1);
        }
        var value: Int = 0;
        for (try e.flow(self.temp)) |child| value = @max(value, try self.contribution(child));
        return value;
    }
    fn layoutElement(self: *Document, e: *Element, cw: Int, ch: ?Int, fw: ?Int, height: ?Int) Error!Int {
        e.cw = fw orelse e.clamp(e.resolve(.width, cw, true) orelse @max(0, cw - e.margin(true) - e.frame(true)), cw, true);
        var fh = height;
        if (fh == null) {
            if (e.resolve(.height, ch, false)) |value| fh = e.clamp(value, ch, false);
        }
        var a: Int = 0;
        e.lines = &.{};
        if (e.text) |text| {
            e.lines = try wrap(self.temp, text, e.cw);
            a = si(e.lines.len);
        } else if (equal(e.s(.display), "flex")) {
            a = try self.flex(e, fh, ch);
        } else if (equal(e.s(.display), "grid")) {
            a = try self.grid(e, fh);
        } else {
            a = try self.block(e, fh);
        }
        e.ch = fh orelse e.clamp(a, ch, false);
        return a;
    }
    fn block(self: *Document, e: *Element, k: ?Int) Error!Int {
        var bottom: Int = 0;
        var previous: Int = 0;
        var count: usize = 0;
        for (try e.flow(self.temp)) |child| {
            _ = try self.layoutElement(child, e.cw, k, null, null);
            var y = child.n(.@"margin-top");
            if (count > 0) y = bottom + @max(previous, y);
            position(e, child, child.n(.@"margin-left"), y);
            bottom = y + child.ch + child.frame(false);
            previous = child.n(.@"margin-bottom");
            count += 1;
        }
        return if (count == 0) 0 else bottom + previous;
    }
    fn flex(self: *Document, e: *Element, k: ?Int, ch: ?Int) Error!Int {
        const gpa = self.temp;
        const horizontal = std.mem.startsWith(u8, e.s(.@"flex-direction"), "row");
        const reversed = std.mem.endsWith(u8, e.s(.@"flex-direction"), "reverse");
        const mainRef: ?Int = if (horizontal) e.cw else k;
        const gap = e.n(if (horizontal) .@"column-gap" else .@"row-gap");
        var items: std.ArrayList(*FlexItem) = .empty;
        for (try e.items(gpa)) |child| {
            const item = try gpa.create(FlexItem);
            item.* = .{ .e = child, .outer = child.frame(horizontal) + child.margin(horizontal) };
            if (!horizontal) {
                const r = @max(0, e.cw - child.frame(true) - child.margin(true));
                const c = if (!equal(child.s(.width), "auto")) child.resolve(.width, e.cw, true).? else if (equal(child.alignment(e), "stretch")) r else @min(try self.maxContent(child), r);
                item.cross = child.clamp(c, e.cw, true);
            }
            var base = child.resolve(.@"flex-basis", mainRef, horizontal);
            if (base == null) base = child.resolve(if (horizontal) .width else .height, mainRef, horizontal);
            item.base = base orelse if (horizontal) try self.maxContent(child) else try self.layoutElement(child, e.cw, k, item.cross, null);
            item.hypothetical = child.clamp(item.base, mainRef, horizontal);
            try items.append(gpa, item);
        }
        var length: Int = 0;
        if (horizontal) {
            length = e.cw;
        } else if (k) |value| {
            length = value;
        } else {
            for (items.items) |item| length += item.hypothetical + item.outer;
            if (items.items.len > 0) length += gap * (si(items.items.len) - 1);
            length = e.clamp(length, ch, false);
        }
        var lines: std.ArrayList(std.ArrayList(*FlexItem)) = .empty;
        var used: Int = 0;
        for (items.items) |item| {
            if (lines.items.len == 0) {
                try lines.append(gpa, .empty);
                used = 0;
            }
            var line = &lines.items[lines.items.len - 1];
            if (horizontal and equal(e.s(.@"flex-wrap"), "wrap") and line.items.len > 0 and used + gap + item.hypothetical + item.outer > length) {
                try lines.append(gpa, .empty);
                line = &lines.items[lines.items.len - 1];
                used = 0;
            }
            if (line.items.len > 0) used += gap;
            try line.append(gpa, item);
            used += item.hypothetical + item.outer;
        }
        var crossStart: Int = 0;
        var totalCross: Int = 0;
        for (lines.items) |lineList| {
            const line = lineList.items;
            const gaps = gap * (si(line.len) - 1);
            var hypothetical = gaps;
            for (line) |item| hypothetical += item.hypothetical + item.outer;
            const growing = hypothetical < length;
            for (line) |item| {
                item.weight = if (growing) item.e.n(.@"flex-grow") else item.e.n(.@"flex-shrink") * item.base;
                item.frozen = item.weight == 0 or growing and item.base > item.hypothetical or !growing and item.base < item.hypothetical;
                item.size = item.hypothetical;
            }
            while (true) {
                var free = length - gaps;
                const weights = try gpa.alloc(Int, line.len);
                @memset(weights, 0);
                var unfrozen: usize = 0;
                for (line, 0..) |item, i| {
                    if (item.frozen) {
                        free -= item.size + item.outer;
                    } else {
                        free -= item.base + item.outer;
                        weights[i] = item.weight;
                        unfrozen += 1;
                    }
                }
                if (unfrozen == 0) break;
                const assignments = try distribute(gpa, @max(0, if (growing) free else -free), weights);
                const violations = try gpa.alloc(Int, line.len);
                @memset(violations, 0);
                var totalViolation: Int = 0;
                for (line, 0..) |item, i| {
                    if (item.frozen) continue;
                    const tentative = item.base + if (growing) assignments[i] else -assignments[i];
                    item.size = item.e.clamp(tentative, mainRef, horizontal);
                    violations[i] = item.size - tentative;
                    totalViolation += violations[i];
                }
                for (line, 0..) |item, i| if (!item.frozen and (totalViolation == 0 or totalViolation > 0 and violations[i] > 0 or totalViolation < 0 and violations[i] < 0)) {
                    item.frozen = true;
                };
            }
            var lc = e.cw;
            if (horizontal) {
                lc = 0;
                for (line) |item| {
                    _ = try self.layoutElement(item.e, e.cw, k, item.size, null);
                    item.cross = item.e.ch;
                    lc = @max(lc, item.cross + item.e.frame(false) + item.e.margin(false));
                }
                if (lines.items.len == 1) lc = k orelse e.clamp(lc, ch, false);
            }
            var remaining = length - gaps;
            for (line) |item| remaining -= item.size + item.outer;
            const spaces = try gpa.alloc(Int, line.len);
            @memset(spaces, 0);
            const justify = e.s(.@"justify-content");
            if (remaining > 0) {
                if (equal(justify, "end")) {
                    spaces[0] = remaining;
                } else if (equal(justify, "center")) {
                    spaces[0] = @divTrunc(remaining, 2);
                } else if (oneOf(justify, &.{ "space-between", "space-around", "space-evenly" })) {
                    const weights = try gpa.alloc(Int, line.len + 1);
                    for (weights, 0..) |*weight, i| {
                        weight.* = if (equal(justify, "space-between")) (if (i == 0 or i == line.len) @as(Int, 0) else 1) else if (equal(justify, "space-around")) (if (i == 0 or i == line.len) @as(Int, 1) else 2) else 1;
                    }
                    const values = try distribute(gpa, remaining, weights);
                    @memcpy(spaces, values[0..line.len]);
                }
            }
            var cursor: Int = 0;
            for (line, 0..) |item, i| {
                const child = item.e;
                const alignment = child.alignment(e);
                var c = item.cross;
                if (horizontal) {
                    if (equal(alignment, "stretch") and equal(child.s(.height), "auto")) {
                        c = child.clamp(@max(0, lc - child.frame(false) - child.margin(false)), k, false);
                        _ = try self.layoutElement(child, e.cw, k, item.size, c);
                    } else {
                        _ = try self.layoutElement(child, e.cw, k, item.size, null);
                        c = child.ch;
                    }
                } else {
                    _ = try self.layoutElement(child, e.cw, k, c, item.size);
                }
                const q = lc - c - child.frame(!horizontal) - child.margin(!horizontal);
                const offset = if (q > 0 and equal(alignment, "end")) q else if (q > 0 and equal(alignment, "center")) @divTrunc(q, 2) else 0;
                cursor += spaces[i];
                const side: Property = if (horizontal) (if (reversed) .@"margin-right" else .@"margin-left") else (if (reversed) .@"margin-bottom" else .@"margin-top");
                const main = if (reversed) length - cursor - child.n(side) - item.size - child.frame(horizontal) else cursor + child.n(side);
                const cross = offset + child.n(if (horizontal) .@"margin-top" else .@"margin-left") + if (horizontal) crossStart else 0;
                if (horizontal) position(e, child, main, cross) else position(e, child, cross, main);
                cursor += item.size + item.outer + gap;
            }
            crossStart += lc + e.n(.@"row-gap");
            totalCross += lc;
        }
        if (!horizontal) return length;
        return totalCross + if (lines.items.len > 0) e.n(.@"row-gap") * (si(lines.items.len) - 1) else 0;
    }
    fn grid(self: *Document, e: *Element, k: ?Int) Error!Int {
        const gpa = self.temp;
        const placed = try self.placement(e);
        const contributions = try gpa.alloc(Int, placed.items.len);
        for (placed.items, 0..) |p, i| contributions[i] = try self.contribution(p.e);
        const columns = try trackSizes(gpa, try tracks(gpa, e.s(.@"grid-template-columns"), true), placed.columns, e.cw, e.n(.@"column-gap"), placed.items, contributions, true);
        const widths = try gpa.alloc(Int, placed.items.len);
        const positions = try gpa.alloc(Int, placed.items.len);
        const actual = try gpa.alloc(Int, placed.items.len);
        for (placed.items, 0..) |p, i| {
            const a = area(columns, p.col, p.cols, e.n(.@"column-gap"));
            const gw = p.e.clamp(p.e.resolve(.width, a.size, true) orelse @max(0, a.size - p.e.margin(true) - p.e.frame(true)), a.size, true);
            widths[i] = a.size;
            positions[i] = a.offset;
            actual[i] = gw;
            _ = try self.layoutElement(p.e, a.size, null, gw, null);
            contributions[i] = p.e.ch + p.e.frame(false) + p.e.margin(false);
        }
        const rows = try trackSizes(gpa, try tracks(gpa, e.s(.@"grid-template-rows"), false), placed.rows, k, e.n(.@"row-gap"), placed.items, contributions, false);
        for (placed.items, 0..) |p, i| {
            const a = area(rows, p.row, p.rows, e.n(.@"row-gap"));
            const child = p.e;
            const alignment = child.alignment(e);
            const fh: ?Int = if (equal(alignment, "stretch") and equal(child.s(.height), "auto")) child.clamp(@max(0, a.size - child.frame(false) - child.margin(false)), a.size, false) else null;
            _ = try self.layoutElement(child, widths[i], a.size, actual[i], fh);
            const q = a.size - child.ch - child.frame(false) - child.margin(false);
            const offset = if (q > 0 and equal(alignment, "end")) q else if (q > 0 and equal(alignment, "center")) @divTrunc(q, 2) else 0;
            position(e, child, positions[i] + child.n(.@"margin-left"), a.offset + offset + child.n(.@"margin-top"));
        }
        return if (placed.rows == 0) 0 else sum(rows) + e.n(.@"row-gap") * (placed.rows - 1);
    }
    fn layout(self: *Document) Error!void {
        _ = self.layoutArena.reset(.retain_capacity);
        self.temp = self.layoutArena.allocator();
        for (self.elements.items) |e| {
            e.style = defaults;
            var specificities: [propertyCount]i8 = @splat(-1);
            for (self.rules.items) |rule| {
                var specificity: i8 = -1;
                for (rule.selectors) |selector| {
                    if (selector[0] == '#') {
                        if (equal(e.id, selector[1..])) specificity = @max(specificity, 2);
                    } else if (selector[0] == '.') {
                        for (e.classes) |class| if (equal(class, selector[1..])) {
                            specificity = @max(specificity, 1);
                        };
                    } else if (equal(e.kind, selector)) {
                        specificity = @max(specificity, 0);
                    }
                }
                if (specificity < 0) continue;
                for (rule.declarations) |decl| {
                    const p = @backingInt(decl.property);
                    if (specificity >= specificities[p]) {
                        e.style[p] = decl.value;
                        specificities[p] = specificity;
                    }
                }
            }
            for (e.overrides, 0..) |value, p| if (value) |text| {
                e.style[p] = text;
            };
            e.displayed = !equal(e.s(.display), "none") and (e.parent == null or e.parent.?.displayed);
            e.containing = null;
        }
        const root = self.elements.items[0];
        if (root.displayed and !equal(root.s(.position), "absolute")) {
            _ = try self.layoutElement(root, self.width, self.height, null, null);
            root.rx = root.n(.@"margin-left");
            root.ry = root.n(.@"margin-top");
        }
        for (self.elements.items) |e| {
            if (!e.displayed or !equal(e.s(.position), "absolute")) continue;
            var ancestor = e.parent;
            while (ancestor != null and equal(ancestor.?.s(.position), "static")) ancestor = ancestor.?.parent;
            e.containing = ancestor;
            var cbw = self.width;
            var cbh = self.height;
            if (ancestor) |a| {
                cbw = a.cw + a.n(.@"padding-left") + a.n(.@"padding-right");
                cbh = a.ch + a.n(.@"padding-top") + a.n(.@"padding-bottom");
            }
            var w: Int = 0;
            if (e.resolve(.width, cbw, true)) |value| {
                w = value;
            } else {
                const left = if (equal(e.s(.left), "auto")) 0 else e.n(.left);
                const right = if (equal(e.s(.right), "auto")) 0 else e.n(.right);
                const r = @max(0, cbw - left - right - e.margin(true) - e.frame(true));
                w = if (!equal(e.s(.left), "auto") and !equal(e.s(.right), "auto")) r else @min(try self.maxContent(e), r);
            }
            w = e.clamp(w, cbw, true);
            const fh: ?Int = if (equal(e.s(.height), "auto") and !equal(e.s(.top), "auto") and !equal(e.s(.bottom), "auto")) e.clamp(@max(0, cbh - e.n(.top) - e.n(.bottom) - e.margin(false) - e.frame(false)), cbh, false) else null;
            _ = try self.layoutElement(e, cbw, cbh, w, fh);
            e.rx = if (!equal(e.s(.left), "auto")) e.n(.left) + e.n(.@"margin-left") else if (!equal(e.s(.right), "auto")) cbw - e.n(.right) - e.n(.@"margin-right") - e.cw - e.frame(true) else e.n(.@"margin-left");
            e.ry = if (!equal(e.s(.top), "auto")) e.n(.top) + e.n(.@"margin-top") else if (!equal(e.s(.bottom), "auto")) cbh - e.n(.bottom) - e.n(.@"margin-bottom") - e.ch - e.frame(false) else e.n(.@"margin-top");
        }
        for (self.elements.items) |e| {
            if (!e.displayed) continue;
            var x: Int = 0;
            var y: Int = 0;
            if (equal(e.s(.position), "absolute")) {
                if (e.containing) |a| {
                    x = a.x + a.n(.@"border-left");
                    y = a.y + a.n(.@"border-top");
                }
            } else if (e.parent) |parent| {
                x = parent.x;
                y = parent.y;
            }
            e.x = x + e.rx;
            e.y = y + e.ry;
            if (equal(e.s(.position), "relative")) {
                e.x += if (!equal(e.s(.left), "auto")) e.n(.left) else if (!equal(e.s(.right), "auto")) -e.n(.right) else 0;
                e.y += if (!equal(e.s(.top), "auto")) e.n(.top) else if (!equal(e.s(.bottom), "auto")) -e.n(.bottom) else 0;
            }
        }
    }
    fn snapshot(self: *Document) Error![][5]Int {
        const result = try self.gpa.alloc([5]Int, self.elements.items.len);
        @memset(result, [5]Int{ 0, 0, 0, 0, 0 });
        for (self.elements.items, 0..) |e, i| if (e.displayed) {
            const r = e.border();
            result[i] = .{ 1, r.x, r.y, r.w, r.h };
        };
        return result;
    }
    fn changed(self: *Document, before: []const [5]Int) Error!Text {
        const after = try self.snapshot();
        var names: std.ArrayList(Text) = .empty;
        for (self.elements.items, 0..) |e, i| if (!std.mem.eql(Int, &before[i], &after[i])) try names.append(self.gpa, e.id);
        return if (names.items.len == 0) "no change" else try join(self.gpa, names.items, " ");
    }
    fn rectangleLine(self: *Document, name: Text, r: Rect) Error!void {
        try self.out.line("{s} {d} {d} {d} {d}", .{ name, r.x, r.y, r.w, r.h });
    }
    fn render(self: *Document) Error!void {
        const screen = try self.gpa.alloc(u8, u(self.width * self.height));
        @memset(screen, '.');
        for (self.elements.items) |e| {
            if (!e.displayed) continue;
            const r = e.border();
            var y = @max(0, r.y);
            while (y < @min(self.height, r.y + r.h)) : (y += 1) {
                var x = @max(0, r.x);
                while (x < @min(self.width, r.x + r.w)) : (x += 1) {
                    const horizontal = e.n(.@"border-top") == 1 and y == r.y or e.n(.@"border-bottom") == 1 and y == r.y + r.h - 1;
                    const vertical = e.n(.@"border-left") == 1 and x == r.x or e.n(.@"border-right") == 1 and x == r.x + r.w - 1;
                    screen[u(y * self.width + x)] = if (horizontal and vertical) '+' else if (horizontal) '-' else if (vertical) '|' else ' ';
                }
            }
            const content = e.content();
            for (e.lines, 0..) |line, i| {
                for (line, 0..) |c, j| {
                    const x = content.x + si(j);
                    const yy = content.y + si(i);
                    if (x >= 0 and x < self.width and yy >= 0 and yy < self.height) screen[u(yy * self.width + x)] = c;
                }
            }
        }
        try self.out.line("render {d}x{d}", .{ self.width, self.height });
        const border = try self.gpa.alloc(u8, u(self.width + 2));
        @memset(border, '#');
        try self.out.line("{s}", .{border});
        for (0..u(self.height)) |y| try self.out.line("#{s}#", .{screen[y * u(self.width) .. (y + 1) * u(self.width)]});
        try self.out.line("{s}", .{border});
    }
    fn command(self: *Document, line: Text) Error!void {
        const tokens = try split(self.gpa, line, " ");
        const name = tokens[0];
        const args = tokens[1..];
        if (equal(name, "LAYOUT")) {
            try self.out.line("layout {d}x{d}", .{ self.width, self.height });
            for (self.elements.items) |e| {
                for (0..e.depth * 2) |_| try self.out.add(" ");
                if (e.displayed) {
                    const r = e.border();
                    try self.out.line("{s} {d} {d} {d} {d}", .{ e.id, r.x, r.y, r.w, r.h });
                } else try self.out.line("{s} none", .{e.id});
            }
        } else if (equal(name, "BOX")) {
            const e = self.byID.get(args[0]) orelse {
                try self.out.line("error: unknown element {s}", .{args[0]});
                return;
            };
            if (!e.displayed) {
                try self.out.line("box {s}: none", .{e.id});
                return;
            }
            try self.out.line("box {s}", .{e.id});
            const r = e.border();
            try self.rectangleLine("margin", e.marginBox());
            try self.rectangleLine("border", r);
            try self.rectangleLine("padding", .{ .x = r.x + e.n(.@"border-left"), .y = r.y + e.n(.@"border-top"), .w = e.cw + e.n(.@"padding-left") + e.n(.@"padding-right"), .h = e.ch + e.n(.@"padding-top") + e.n(.@"padding-bottom") });
            try self.rectangleLine("content", e.content());
        } else if (equal(name, "RENDER")) {
            try self.render();
        } else if (equal(name, "HIT")) {
            const x = number(args[0]);
            const y = number(args[1]);
            if (x >= self.width or y >= self.height) {
                try self.out.line("error: point {d} {d} outside viewport", .{ x, y });
                return;
            }
            var found: ?*Element = null;
            for (self.elements.items) |e| {
                const r = e.border();
                if (e.displayed and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h) found = e;
            }
            var path: std.ArrayList(Text) = .empty;
            while (found) |e| {
                try path.append(self.gpa, e.id);
                found = e.parent;
            }
            std.mem.reverse(Text, path.items);
            try self.out.line("hit {d} {d}: {s}", .{ x, y, if (path.items.len == 0) "none" else try join(self.gpa, path.items, " > ") });
        } else if (equal(name, "SET")) {
            const e = self.byID.get(args[0]) orelse {
                try self.out.line("error: unknown element {s}", .{args[0]});
                return;
            };
            const prop = args[1];
            const value = try join(self.gpa, args[2..], " ");
            if (property(prop) == null and !oneOf(prop, &.{ "margin", "padding", "border", "gap" })) {
                try self.out.line("error: unknown property {s}", .{prop});
                return;
            }
            const declarations = (try valid(self.gpa, prop, value)) orelse {
                try self.out.line("error: invalid value for {s}: {s}", .{ prop, value });
                return;
            };
            const before = try self.snapshot();
            for (declarations) |decl| e.overrides[@backingInt(decl.property)] = decl.value;
            try self.layout();
            try self.out.line("set {s} {s} {s}: {s}", .{ e.id, prop, value, try self.changed(before) });
        } else if (equal(name, "VIEWPORT")) {
            const w = number(args[0]);
            const h = number(args[1]);
            if (w < 1 or w > 80 or h < 1 or h > 40) {
                try self.out.line("error: invalid viewport {d} {d}", .{ w, h });
                return;
            }
            const before = try self.snapshot();
            self.width = w;
            self.height = h;
            try self.layout();
            try self.out.line("viewport {d} {d}: {s}", .{ w, h, try self.changed(before) });
        } else if (equal(name, "OVERFLOW")) {
            var names: std.ArrayList(Text) = .empty;
            for (self.elements.items) |e| {
                if (!e.displayed) continue;
                var overflow = false;
                if (e.text != null) {
                    overflow = si(e.lines.len) > e.ch;
                    for (e.lines) |text| if (si(text.len) > e.cw) {
                        overflow = true;
                    };
                } else {
                    const content = e.content();
                    for (try e.flow(self.gpa)) |child| {
                        const r = child.marginBox();
                        if (r.x < content.x or r.y < content.y or r.x + r.w > content.x + content.w or r.y + r.h > content.y + content.h) overflow = true;
                    }
                }
                if (overflow) try names.append(self.gpa, e.id);
            }
            try self.out.line("overflow: {s}", .{if (names.items.len == 0) "none" else try join(self.gpa, names.items, " ")});
        } else try self.out.line("error: unknown command {s}", .{name});
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const dimensions = try split(gpa, std.mem.trimEnd(u8, lines.next().?, "\r"), " ");
    var out: Builder = .{ .gpa = gpa };
    var d: Document = .{ .gpa = gpa, .temp = gpa, .out = &out, .layoutArena = std.heap.ArenaAllocator.init(std.heap.page_allocator), .width = number(dimensions[0]), .height = number(dimensions[1]) };
    defer d.layoutArena.deinit();
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "---")) break;
        const at = std.mem.find(u8, line, " { ").?;
        const selectors = try split(gpa, line[0..at], ", ");
        const declarationText = line[at + 3 .. line.len - 2];
        var declarations: std.ArrayList(Declaration) = .empty;
        for (try split(gpa, declarationText, "; ")) |part| {
            const colon = std.mem.find(u8, part, ": ").?;
            if (try valid(gpa, part[0..colon], part[colon + 2 ..])) |items| try declarations.appendSlice(gpa, items);
        }
        try d.rules.append(gpa, .{ .selectors = selectors, .declarations = declarations.items });
    }
    var stack: std.ArrayList(*Element) = .empty;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "===")) break;
        var spaces: usize = 0;
        while (spaces < line.len and line[spaces] == ' ') : (spaces += 1) {}
        const depth = spaces / 2;
        const body = line[spaces..];
        const at = std.mem.findScalar(u8, body, ' ') orelse body.len;
        const head = body[0..at];
        const elementText: ?Text = if (at < body.len) body[at + 2 .. body.len - 1] else null;
        const hash = std.mem.findScalar(u8, head, '#').?;
        const parts = try split(gpa, head[hash + 1 ..], ".");
        const e = try gpa.create(Element);
        e.* = .{ .kind = head[0..hash], .id = parts[0], .classes = parts[1..], .text = elementText, .depth = depth, .index = d.elements.items.len };
        if (depth > 0) {
            e.parent = stack.items[depth - 1];
            try e.parent.?.children.append(gpa, e);
        }
        stack.shrinkRetainingCapacity(depth);
        try stack.append(gpa, e);
        try d.elements.append(gpa, e);
        try d.byID.put(gpa, e.id, e);
    }
    try d.layout();
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "END")) break;
        try d.command(line);
    }
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
