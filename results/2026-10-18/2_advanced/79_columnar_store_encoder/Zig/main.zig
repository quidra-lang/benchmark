const std = @import("std");
const s = @import("schema_io.zig");
const b = @import("bitstream.zig");
const e = @import("encoding.zig");
const q = @import("query.zig");
const Value = s.Value;
const Values = s.Values;
const Row = s.Row;
const Table = s.Table;
fn statistics(values: Values) ?s.Bounds {
    var out: ?s.Bounds = null;
    for (values) |value| if (value != .null_value) {
        if (out) |*bounds| {
            if (s.valueCompare(value, bounds.low) < 0) bounds.low = value;
            if (s.valueCompare(bounds.high, value) < 0) bounds.high = value;
        } else out = .{ .low = value, .high = value };
    };
    return out;
}
fn statisticsText(column: s.Column, bounds: ?s.Bounds) []const u8 {
    return if (bounds) |range| s.fmt("min {s} max {s}", .{ s.valueText(column.kind, range.low,
         "NULL"), s.valueText(column.kind, range.high, "NULL") }) else "stats none";
}
fn methodBit(method: e.Method) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(method));
}
fn methodList(mask: u8) []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (e.methods, 0..) |name, i| if (mask & methodBit(@enumFromInt(i)) != 0) s.append([]const u8, &names, name);
    return s.join(names.items, ",");
}
fn columnLine(index: usize, column: s.Column) []const u8 {
    return s.fmt("column {d} {s} {s} {s}", .{ index, column.name, s.type_names[@intFromEnum(column.kind)],
         if (column.nullable) "NULLABLE" else "REQUIRED" });
}
const Page = struct {
    offset: usize,
    header_size: usize,
    body_size: usize,
    body_offset: usize,
    kind: u8,
    method: e.Method,
    count: usize,
    nulls: usize,
    checksum: i64,
    bounds: ?s.Bounds,
    fn size(self: Page) usize {
        return self.header_size + self.body_size;
    }
};
const Chunk = struct { offset: usize = 0, size: usize = 0, methods: u8 = 0, has_dictionary: bool = false,
     page_count: usize = 0, nulls: usize = 0, bounds: ?s.Bounds = null, dictionary: ?Page = null,
     pages: []const Page = &.{} };
const Group = struct { rows: usize, first_row: usize = 0, chunks: []Chunk };
const BuiltChunk = struct { data: []const u8, info: Chunk, fallback: usize };
fn containsValue(values: Values, value: Value) bool {
    for (values) |existing| if (s.valueEqual(existing, value)) return true;
    return false;
}
fn buildPage(column: s.Column, kind: u8, method: e.Method, values: Values, dictionary: Values) []const u8 {
    var body: b.Writer = .{};
    var nulls: usize = 0;
    var bounds: ?s.Bounds = null;
    if (kind == 1) body.raw(e.encodeValues(column.kind, .plain, values, &.{})) else {
        var present: std.ArrayList(Value) = .empty;
        const levels = s.alloc(i64, values.len);
        for (values, levels) |value, *level| {
            level.* = @intFromBool(value != .null_value);
            if (value == .null_value) nulls += 1 else s.append(Value, &present, value);
        }
        bounds = statistics(values);
        if (column.nullable) {
            const encoded = b.hybridEncode(levels, 1);
            body.integer(s.n(encoded.len));
            body.raw(encoded);
        }
        body.raw(e.encodeValues(column.kind, method, present.items, dictionary));
    }
    var out: b.Writer = .{};
    out.byte(kind);
    out.byte(@intFromEnum(method));
    out.uleb(s.n(values.len));
    out.uleb(s.n(nulls));
    out.uleb(s.n(body.bytes().len));
    out.integer(b.adler32(body.bytes()));
    out.raw(e.encodeStatistics(column.kind, bounds));
    out.raw(body.bytes());
    return out.bytes();
}
fn buildChunk(column: s.Column, values: Values, method: e.Method, options: s.Options) BuiltChunk {
    const page_count = (values.len + options.page_size - 1) / options.page_size;
    var dictionary: std.ArrayList(Value) = .empty;
    var dictionary_pages: usize = 0;
    var dictionary_bytes: usize = 0;
    if (method == .dictionary) for (0..page_count) |page| {
        const start = page * options.page_size;
        const end = @min(start + options.page_size, values.len);
        var additions: std.ArrayList(Value) = .empty;
        for (values[start..end]) |value| if (value != .null_value and !containsValue(dictionary.items,
             value) and !containsValue(additions.items, value)) s.append(Value, &additions,
             value);
        const proposed = dictionary_bytes + e.encodeValues(column.kind, .plain, additions.items, &.{}).len;
        if (proposed > options.dictionary_limit) break;
        for (additions.items) |value| s.append(Value, &dictionary, value);
        dictionary_bytes = proposed;
        dictionary_pages += 1;
    };
    if (dictionary.items.len == 0) dictionary_pages = 0;
    var out: b.Writer = .{};
    var methods: u8 = 0;
    if (dictionary_pages > 0) out.raw(buildPage(column, 1, .plain, dictionary.items, &.{}));
    for (0..page_count) |page| {
        const start = page * options.page_size;
        const end = @min(start + options.page_size, values.len);
        const selected: e.Method = if (method == .dictionary) (if (page < dictionary_pages) .dictionary else .plain) else method;
        methods |= methodBit(selected);
        out.raw(buildPage(column, 0, selected, values[start..end], dictionary.items));
    }
    var nulls: usize = 0;
    for (values) |value| if (value == .null_value) {
        nulls += 1;
    };
    return .{ .data = out.bytes(), .info = .{ .size = out.bytes().len, .methods = methods,
         .has_dictionary = dictionary_pages > 0, .page_count = page_count, .nulls = nulls,
         .bounds = statistics(values) }, .fallback = if (method == .dictionary) page_count - dictionary_pages else 0 };
}
fn buildFile(inputs: s.Inputs, work_allocator: std.mem.Allocator) struct { data: []const u8, report: s.Lines } {
    var data: b.Writer = .{};
    data.raw("MPTC");
    var groups: std.ArrayList(Group) = .empty;
    var report: s.Lines = .{};
    report.add("row_group,column,encoding,bytes,fallback_pages,chosen", .{});
    var first: usize = 0;
    while (first < inputs.rows.len) : (first += inputs.options.row_group_size) {
        const count = @min(inputs.options.row_group_size, inputs.rows.len - first);
        const chunks = s.alloc(Chunk, inputs.columns.len);
        for (inputs.columns, 0..) |column, index| {
            const persistent = s.allocator;
            var work: std.heap.ArenaAllocator = .init(work_allocator);
            defer work.deinit();
            s.allocator = work.allocator();
            const values = s.alloc(Value, count);
            for (values, 0..) |*value, row| value.* = inputs.rows[first + row][index];
            const methods = e.candidates(column.kind);
            var choices: [5]?BuiltChunk = @splat(null);
            for (methods) |method| choices[@intFromEnum(method)] = buildChunk(column, values, method, inputs.options);
            var chosen = e.findMethod(inputs.options.encoding[index]);
            if (chosen == null) {
                chosen = methods[0];
                for (methods[1..]) |method| if (choices[@intFromEnum(method)].?.data.len < choices[@intFromEnum(chosen.?)].?.data.len) {
                    chosen = method;
                };
            } else if (chosen.? == .dictionary and !choices[@intFromEnum(e.Method.dictionary)].?.info.has_dictionary) chosen = .plain;
            s.allocator = persistent;
            for (methods) |method| {
                const candidate = choices[@intFromEnum(method)].?;
                report.add("{d},{s},{s},{d},{d},{s}", .{ groups.items.len, column.name, e.methods[@intFromEnum(method)],
                     candidate.data.len, candidate.fallback, if (method == chosen.?) "yes" else "no" });
            }
            const selected = choices[@intFromEnum(chosen.?)].?;
            chunks[index] = selected.info;
            chunks[index].offset = data.bytes().len;
            data.raw(selected.data);
        }
        s.append(Group, &groups, .{ .rows = count, .first_row = first, .chunks = chunks });
    }
    var footer: b.Writer = .{};
    footer.uleb(1);
    footer.uleb(s.n(inputs.columns.len));
    for (inputs.columns) |column| {
        footer.uleb(s.n(column.name.len));
        footer.raw(column.name);
        footer.byte(@intFromEnum(column.kind));
        footer.byte(@intFromBool(column.nullable));
    }
    footer.uleb(s.n(inputs.rows.len));
    footer.uleb(s.n(groups.items.len));
    for (groups.items) |group| {
        footer.uleb(s.n(group.rows));
        for (group.chunks, inputs.columns) |chunk, column| {
            footer.uleb(s.n(chunk.offset));
            footer.uleb(s.n(chunk.size));
            footer.uleb(@popCount(chunk.methods));
            for (0..5) |i| if (chunk.methods & methodBit(@enumFromInt(i)) != 0) footer.byte(@intCast(i));
            footer.byte(@intFromBool(chunk.has_dictionary));
            footer.uleb(s.n(chunk.page_count));
            footer.uleb(s.n(chunk.nulls));
            footer.raw(e.encodeStatistics(column.kind, chunk.bounds));
        }
    }
    data.raw(footer.bytes());
    data.integer(s.n(footer.bytes().len));
    data.raw("MPTC");
    return .{ .data = data.bytes(), .report = report };
}
const File = struct { data: []const u8, version: i64, rows: usize, columns: []const s.Column,
     groups: []Group, footer_size: usize, footer_offset: usize };
fn parseFile(data: []const u8) File {
    var length: b.Reader = .{ .data = data, .position = data.len - 8 };
    const footer_size = s.u(length.integer(false));
    const footer_offset = data.len - 8 - footer_size;
    var reader: b.Reader = .{ .data = data, .position = footer_offset };
    const version = reader.uleb();
    const columns = s.alloc(s.Column, s.u(reader.uleb()));
    for (columns) |*column| {
        const size = s.u(reader.uleb());
        const name = reader.read(size);
        const kind: s.Type = @enumFromInt(reader.byte());
        const nullable = reader.byte() != 0;
        column.* = .{ .name = name, .kind = kind, .nullable = nullable };
    }
    const rows = s.u(reader.uleb());
    const groups = s.alloc(Group, s.u(reader.uleb()));
    var first: usize = 0;
    for (groups) |*group| {
        const count = s.u(reader.uleb());
        group.* = .{ .rows = count, .first_row = first, .chunks = s.alloc(Chunk, columns.len) };
        first += count;
        for (columns, group.chunks) |column, *chunk| {
            chunk.* = .{};
            chunk.offset = s.u(reader.uleb());
            chunk.size = s.u(reader.uleb());
            const method_count = s.u(reader.uleb());
            for (0..method_count) |_| {
                const method: e.Method = @enumFromInt(reader.byte());
                chunk.methods |= methodBit(method);
            }
            chunk.has_dictionary = reader.byte() != 0;
            chunk.page_count = s.u(reader.uleb());
            chunk.nulls = s.u(reader.uleb());
            chunk.bounds = e.decodeStatistics(&reader, column.kind);
        }
    }
    for (groups) |group| for (group.chunks, columns) |*chunk, column| {
        var pages: b.Reader = .{ .data = data, .position = chunk.offset };
        var number: usize = 0;
        var parsed: std.ArrayList(Page) = .empty;
        while (pages.position < chunk.offset + chunk.size) {
            const offset = pages.position;
            const kind = pages.byte();
            const method: e.Method = @enumFromInt(pages.byte());
            const count = s.u(pages.uleb());
            const nulls = s.u(pages.uleb());
            const body_size = s.u(pages.uleb());
            const checksum = pages.integer(false);
            const bounds = e.decodeStatistics(&pages, column.kind);
            const page: Page = .{ .offset = offset, .header_size = pages.position - offset,
                 .body_size = body_size, .body_offset = pages.position, .kind = kind, .method = method,
                 .count = count, .nulls = nulls, .checksum = checksum, .bounds = bounds };
            pages.position += body_size;
            if (chunk.has_dictionary and number == 0) chunk.dictionary = page else s.append(Page, &parsed, page);
            number += 1;
        }
        chunk.pages = parsed.items;
    };
    return .{ .data = data, .version = version, .rows = rows, .columns = columns, .groups = groups,
         .footer_size = footer_size, .footer_offset = footer_offset };
}
fn pageBody(file: *const File, page: Page) []const u8 {
    return file.data[page.body_offset .. page.body_offset + page.body_size];
}
fn decodeDictionary(file: *const File, column: s.Column, page: Page) Values {
    var reader: b.Reader = .{ .data = pageBody(file, page) };
    return e.decodeValues(&reader, column.kind, .plain, page.count, &.{});
}
fn decodePage(file: *const File, column: s.Column, page: Page, dictionary: Values) Values {
    var reader: b.Reader = .{ .data = pageBody(file, page) };
    var levels: s.Numbers = undefined;
    if (column.nullable) {
        const size = s.u(reader.integer(false));
        var definitions: b.Reader = .{ .data = reader.read(size) };
        levels = b.hybridDecode(&definitions, 1, page.count);
    } else levels = s.zero(i64, page.count, 1);
    var present: usize = 0;
    for (levels) |level| if (level == 1) {
        present += 1;
    };
    const values = e.decodeValues(&reader, column.kind, page.method, present, dictionary);
    const out = s.alloc(Value, page.count);
    var index: usize = 0;
    for (levels, out) |level, *value| {
        if (level == 1) {
            value.* = values[index];
            index += 1;
        } else value.* = .null_value;
    }
    return out;
}
fn verifyAndDescribe(file: *const File, original: Table) s.Lines {
    var out: s.Lines = .{};
    out.add("file bytes {d} footer_offset {d} footer_bytes {d}", .{ file.data.len, file.footer_offset,
         file.footer_size });
    out.add("table version {d} rows {d} columns {d} row_groups {d}", .{ file.version, file.rows,
         file.columns.len, file.groups.len });
    for (file.columns, 0..) |column, i| out.add("{s}", .{columnLine(i, column)});
    const Summary = struct { bytes: usize = 0, data_pages: usize = 0, dictionary_pages: usize = 0, methods: u8 = 0 };
    const summaries = s.zero(Summary, file.columns.len, .{});
    var cells: usize = 0;
    var nulls: usize = 0;
    var mismatches: usize = 0;
    var checksum_errors: usize = 0;
    for (file.groups, 0..) |group, g| {
        var size: usize = 0;
        for (group.chunks) |chunk| size += chunk.size;
        out.add("row_group {d} rows {d} first_row {d} bytes {d}", .{ g, group.rows, group.first_row, size });
        for (group.chunks, file.columns, 0..) |chunk, column, index| {
            out.add("chunk {d} {s} offset {d} size {d} encodings {s} dictionary {s} pages {d} nulls {d} {s}",
                 .{ g, column.name, chunk.offset, chunk.size, methodList(chunk.methods), if (chunk.has_dictionary) "yes" else "no",
                 chunk.page_count, chunk.nulls, statisticsText(column, chunk.bounds) });
            const summary = &summaries[index];
            summary.bytes += chunk.size;
            summary.data_pages += chunk.page_count;
            summary.dictionary_pages += @intFromBool(chunk.has_dictionary);
            summary.methods |= chunk.methods;
            var dictionary: Values = &.{};
            if (chunk.dictionary) |page| {
                checksum_errors += @intFromBool(b.adler32(pageBody(file, page)) != page.checksum);
                dictionary = decodeDictionary(file, column, page);
                out.add("page {d} {s} dict offset {d} header {d} body {d} checksum {s} entries {d}",
                     .{ g, column.name, page.offset, page.header_size, page.body_size, b.checksumText(page.checksum),
                     page.count });
            }
            var row = group.first_row;
            for (chunk.pages, 0..) |page, number| {
                checksum_errors += @intFromBool(b.adler32(pageBody(file, page)) != page.checksum);
                out.add("page {d} {s} {d} offset {d} header {d} body {d} checksum {s} encoding {s} values {d} nulls {d} {s}",
                     .{ g, column.name, number, page.offset, page.header_size, page.body_size,
                     b.checksumText(page.checksum), e.methods[@intFromEnum(page.method)], page.count,
                     page.nulls, statisticsText(column, page.bounds) });
                for (decodePage(file, column, page, dictionary)) |value| {
                    cells += 1;
                    nulls += @intFromBool(value == .null_value);
                    mismatches += @intFromBool(!s.valueEqual(value, original[row][index]));
                    row += 1;
                }
            }
        }
    }
    for (summaries, file.columns) |summary, column| out.add("summary {s} bytes {d} data_pages {d} dictionary_pages {d} encodings {s}",
         .{ column.name, summary.bytes, summary.data_pages, summary.dictionary_pages, methodList(summary.methods) });
    out.add("roundtrip {s} cells {d} nulls {d} mismatches {d} checksum_errors {d}", .{ if (mismatches == 0 and checksum_errors == 0) "ok" else "failed",
         cells, nulls, mismatches, checksum_errors });
    return out;
}

fn columnBit(column: usize) u16 {
    return @as(u16, 1) << @intCast(column);
}
fn conditionLeaves(tree: ?*q.Condition, leaves: *std.ArrayList(*q.Condition)) void {
    const node = tree orelse return;
    if (s.eq(node.operation, "NOT")) conditionLeaves(node.left, leaves) else if (s.eq(node.operation,
         "AND") or s.eq(node.operation, "OR")) {
        conditionLeaves(node.left, leaves);
        conditionLeaves(node.right, leaves);
    } else s.append(*q.Condition, leaves, node);
}
fn findColumn(columns: []const s.Column, name: []const u8) ?usize {
    for (columns, 0..) |column, i| if (s.eq(column.name, name)) return i;
    return null;
}
fn itemHeader(item: q.Item) []const u8 {
    if (s.eq(item.operation, "COLUMN")) return item.name;
    if (s.eq(item.operation, "COUNT_DISTINCT")) return s.fmt("COUNT(DISTINCT {s})", .{item.name});
    return s.fmt("{s}({s})", .{ item.operation, if (item.name.len > 0) item.name else "*" });
}
fn checkQuery(query: *q.Query, columns: []const s.Column) ?[]const u8 {
    if (query.star) for (columns) |column| s.append(q.Item, &query.items, .{ .operation = "COLUMN",
         .name = column.name });
    var leaves: std.ArrayList(*q.Condition) = .empty;
    conditionLeaves(query.condition, &leaves);
    var names: std.ArrayList([]const u8) = .empty;
    for (query.items.items) |item| if (item.name.len > 0) s.append([]const u8, &names, item.name);
    for (leaves.items) |leaf| s.append([]const u8, &names, leaf.name);
    if (query.group_name) |name| s.append([]const u8, &names, name);
    if (query.order_name) |name| s.append([]const u8, &names, name);
    for (names.items) |name| if (findColumn(columns, name) == null) return "unknown_column";
    for (leaves.items) |leaf| {
        const kind = columns[findColumn(columns, leaf.name).?].kind;
        const expected: s.Type = if (kind == .date) .string else kind;
        for (leaf.literals.items) |literal| if (literal.kind != expected) return "type_mismatch";
    }
    for (query.items.items) |item| if ((s.eq(item.operation, "SUM") or s.eq(item.operation,
         "AVG")) and columns[findColumn(columns, item.name).?].kind != .integer) return "bad_aggregate";
    query.aggregate = query.group_name != null;
    for (query.items.items) |item| {
        query.aggregate = query.aggregate or !s.eq(item.operation, "COLUMN");
    }
    if (query.aggregate) for (query.items.items) |item| if (s.eq(item.operation, "COLUMN") and (query.group_name == null or !s.eq(item.name,
         query.group_name.?))) return "not_grouped";
    if (query.aggregate and query.order_name != null) return "bad_order";
    for (names.items) |name| query.needed |= columnBit(findColumn(columns, name).?);
    var headers: std.ArrayList([]const u8) = .empty;
    for (query.items.items) |*item| {
        item.column = if (item.name.len == 0) null else findColumn(columns, item.name).?;
        s.append([]const u8, &headers, itemHeader(item.*));
    }
    query.headers = headers.items;
    for (leaves.items) |leaf| {
        leaf.column = findColumn(columns, leaf.name).?;
        query.condition_columns |= columnBit(leaf.column.?);
        if (columns[leaf.column.?].kind == .date) for (leaf.literals.items) |*literal| {
            literal.value = .{ .integer = s.dayNumber(literal.value.string) };
        };
    }
    if (query.group_name) |name| query.group = findColumn(columns, name).?;
    if (query.order_name) |name| query.order = findColumn(columns, name).?;
    return null;
}
const Truth = enum { false_value, true_value, unknown_value };
fn truth(value: bool) Truth {
    return if (value) .true_value else .false_value;
}
fn logicalNot(value: Truth) Truth {
    return switch (value) {
        .false_value => .true_value,
        .true_value => .false_value,
        .unknown_value => .unknown_value,
    };
}
fn logicalPair(operation: []const u8, left: Truth, right: Truth) Truth {
    if (s.eq(operation, "AND")) {
        if (left == .false_value or right == .false_value) return .false_value;
        return if (left == .unknown_value or right == .unknown_value) .unknown_value else .true_value;
    }
    if (left == .true_value or right == .true_value) return .true_value;
    return if (left == .unknown_value or right == .unknown_value) .unknown_value else .false_value;
}
fn compareValue(condition: *const q.Condition, value: Value) Truth {
    const op = condition.operation;
    const literals = condition.literals.items;
    if (s.eq(op, "IS_NULL")) return truth(value == .null_value);
    if (s.eq(op, "IS_NOT_NULL")) return truth(value != .null_value);
    if (value == .null_value) return .unknown_value;
    if (s.eq(op, "BETWEEN")) return truth(s.valueCompare(value, literals[0].value) >= 0 and s.valueCompare(value,
         literals[1].value) <= 0);
    if (s.eq(op, "IN")) {
        for (literals) |literal| if (s.valueEqual(value, literal.value)) return .true_value;
        return .false_value;
    }
    const comparison = s.valueCompare(value, literals[0].value);
    if (s.eq(op, "=")) return truth(comparison == 0);
    if (s.eq(op, "<>")) return truth(comparison != 0);
    if (s.eq(op, "<")) return truth(comparison < 0);
    if (s.eq(op, "<=")) return truth(comparison <= 0);
    if (s.eq(op, ">")) return truth(comparison > 0);
    return truth(comparison >= 0);
}
fn evaluate(tree: ?*q.Condition, row: Row) Truth {
    const node = tree orelse return .true_value;
    if (s.eq(node.operation, "NOT")) return logicalNot(evaluate(node.left, row));
    if (s.eq(node.operation, "AND") or s.eq(node.operation, "OR")) return logicalPair(node.operation,
         evaluate(node.left, row), evaluate(node.right, row));
    return compareValue(node, row[node.column.?]);
}
fn rangePossibilities(condition: *const q.Condition, low: Value, high: Value) struct { can_true: bool,
     can_false: bool } {
    const op = condition.operation;
    const values = condition.literals.items;
    if (s.eq(op, "BETWEEN")) {
        const first = values[0].value;
        const last = values[1].value;
        return .{ .can_true = s.valueCompare(low, last) <= 0 and s.valueCompare(high, first) >= 0 and s.valueCompare(first,
             last) <= 0, .can_false = s.valueCompare(low, first) < 0 or s.valueCompare(high,
             last) > 0 };
    }
    if (s.eq(op, "IN")) {
        var inside = false;
        var equal = false;
        for (values) |literal| {
            inside = inside or (s.valueCompare(low, literal.value) <= 0 and s.valueCompare(literal.value, high) <= 0);
            equal = equal or s.valueEqual(low, literal.value);
        }
        return .{ .can_true = inside, .can_false = !(s.valueEqual(low, high) and equal) };
    }
    const value = values[0].value;
    const inside = s.valueCompare(low, value) <= 0 and s.valueCompare(value, high) <= 0;
    const constant = s.valueEqual(low, value) and s.valueEqual(high, value);
    if (s.eq(op, "=")) return .{ .can_true = inside, .can_false = !constant };
    if (s.eq(op, "<>")) return .{ .can_true = !constant, .can_false = inside };
    if (s.eq(op, "<")) return .{ .can_true = s.valueCompare(low, value) < 0, .can_false = s.valueCompare(high,
         value) >= 0 };
    if (s.eq(op, "<=")) return .{ .can_true = s.valueCompare(low, value) <= 0, .can_false = s.valueCompare(high,
         value) > 0 };
    if (s.eq(op, ">")) return .{ .can_true = s.valueCompare(high, value) > 0, .can_false = s.valueCompare(low,
         value) <= 0 };
    return .{ .can_true = s.valueCompare(high, value) >= 0, .can_false = s.valueCompare(low, value) < 0 };
}
const Zone = struct { bounds: ?s.Bounds = null, nulls: usize = 0, rows: usize = 0 };
fn truthBit(value: Truth) u8 {
    return @as(u8, 1) << @intCast(@intFromEnum(value));
}
fn zoneValues(tree: *const q.Condition, zones: [12]Zone) u8 {
    const op = tree.operation;
    if (s.eq(op, "NOT")) {
        const source = zoneValues(tree.left.?, zones);
        var out: u8 = 0;
        for (0..3) |i| {
            const value: Truth = @enumFromInt(i);
            if (source & truthBit(value) != 0) out |= truthBit(logicalNot(value));
        }
        return out;
    }
    if (s.eq(op, "AND") or s.eq(op, "OR")) {
        const left = zoneValues(tree.left.?, zones);
        const right = zoneValues(tree.right.?, zones);
        var out: u8 = 0;
        for (0..3) |i| for (0..3) |j| {
            const first: Truth = @enumFromInt(i);
            const second: Truth = @enumFromInt(j);
            if (left & truthBit(first) != 0 and right & truthBit(second) != 0) out |= truthBit(logicalPair(op,
                 first, second));
        };
        return out;
    }
    const zone = zones[tree.column.?];
    var out: u8 = 0;
    if (s.eq(op, "IS_NULL") or s.eq(op, "IS_NOT_NULL")) {
        if (zone.nulls > 0) out |= truthBit(truth(s.eq(op, "IS_NULL")));
        if (zone.nulls < zone.rows) out |= truthBit(truth(s.eq(op, "IS_NOT_NULL")));
        return out;
    }
    if (zone.nulls > 0) out |= truthBit(.unknown_value);
    if (zone.bounds) |bounds| {
        const possible = rangePossibilities(tree, bounds.low, bounds.high);
        if (possible.can_true) out |= truthBit(.true_value);
        if (possible.can_false) out |= truthBit(.false_value);
    }
    return out;
}
const scan_names = [_][]const u8{ "row_groups_read", "row_groups_skipped", "pages_read", "pages_skipped",
     "pages_unneeded", "dictionary_pages_read", "bytes_read", "rows_scanned", "rows_matched" };
const Counts = [9]i64;
const DictionaryCache = struct { values: Values = &.{}, ready: bool = false };
fn readScanPage(file: *const File, group: usize, index: usize, number: usize, dictionaries: []DictionaryCache,
     counts: *Counts) Values {
    const chunk = file.groups[group].chunks[index];
    const page = chunk.pages[number];
    var dictionary: Values = &.{};
    if (page.method == .dictionary) {
        const cached = &dictionaries[group * file.columns.len + index];
        if (!cached.ready) {
            cached.ready = true;
            cached.values = decodeDictionary(file, file.columns[index], chunk.dictionary.?);
            counts[5] += 1;
            counts[6] += s.n(chunk.dictionary.?.size());
        }
        dictionary = cached.values;
    }
    counts[2] += 1;
    counts[6] += s.n(page.size());
    return decodePage(file, file.columns[index], page, dictionary);
}
fn emptyRow(count: usize) []Value {
    return s.zero(Value, count, .null_value);
}
const Scan = struct { matched: Table, counts: Counts, records: []const ?[]const u8 };
fn scan(file: *const File, query: *const q.Query) Scan {
    var matched: std.ArrayList(Row) = .empty;
    var counts: Counts = @splat(0);
    const records = s.zero(?[]const u8, file.groups.len, null);
    const dictionaries = s.zero(DictionaryCache, file.groups.len * file.columns.len, .{});
    const remaining = query.needed & ~query.condition_columns;
    for (file.groups, 0..) |group, g| {
        var zones: [12]Zone = @splat(.{});
        for (group.chunks, 0..) |chunk, index| if (query.condition_columns & columnBit(index) != 0) {
            zones[index] = .{ .bounds = chunk.bounds, .nulls = chunk.nulls, .rows = group.rows };
        };
        if (query.condition) |condition| if (zoneValues(condition, zones) & truthBit(.true_value) == 0) {
            counts[1] += 1;
            continue;
        };
        counts[0] += 1;
        if (query.needed == 0) {
            counts[7] += s.n(group.rows);
            for (0..group.rows) |_| s.append(Row, &matched, emptyRow(file.columns.len));
            records[g] = "-";
            continue;
        }
        var record: std.ArrayList(u8) = .empty;
        for (0..group.chunks[0].page_count) |number| {
            for (group.chunks, 0..) |chunk, index| if (query.condition_columns & columnBit(index) != 0) {
                const page = chunk.pages[number];
                zones[index] = .{ .bounds = page.bounds, .nulls = page.nulls, .rows = page.count };
            };
            if (query.condition) |condition| if (zoneValues(condition, zones) & truthBit(.true_value) == 0) {
                counts[3] += @popCount(query.needed);
                s.append(u8, &record, 's');
                continue;
            };
            const count = group.chunks[0].pages[number].count;
            counts[7] += s.n(count);
            const rows = s.alloc([]Value, count);
            for (rows) |*row| row.* = emptyRow(file.columns.len);
            for (0..file.columns.len) |index| if (query.condition_columns & columnBit(index) != 0) {
                const values = readScanPage(file, g, index, number, dictionaries, &counts);
                for (rows, values) |row, value| row[index] = value;
            };
            const selected = s.alloc(bool, count);
            var selected_count: usize = 0;
            for (rows, selected) |row, *value| {
                value.* = evaluate(query.condition, row) == .true_value;
                selected_count += @intFromBool(value.*);
            }
            if (selected_count == 0 and remaining != 0) {
                counts[4] += @popCount(remaining);
                s.append(u8, &record, 'u');
                continue;
            }
            for (0..file.columns.len) |index| if (remaining & columnBit(index) != 0) {
                const values = readScanPage(file, g, index, number, dictionaries, &counts);
                for (rows, values) |row, value| row[index] = value;
            };
            for (rows, selected) |row, value| if (value) s.append(Row, &matched, row);
            s.append(u8, &record, 'r');
        }
        records[g] = record.items;
    }
    counts[8] = s.n(matched.items.len);
    return .{ .matched = matched.items, .counts = counts, .records = records };
}
const OrderedRow = struct { row: Row, position: usize };
const RowOrder = struct { index: usize, descending: bool };
fn lessRow(context: RowOrder, left: OrderedRow, right: OrderedRow) bool {
    const comparison = s.valueCompare(left.row[context.index], right.row[context.index]);
    return if (comparison == 0) left.position < right.position else if (context.descending) comparison > 0 else comparison < 0;
}
fn gcdValue(first: i64, second: i64) i64 {
    var left: i64 = @intCast(@abs(first));
    var right = second;
    while (right != 0) {
        const next = @mod(left, right);
        left = right;
        right = next;
    }
    return left;
}
fn aggregateItem(columns: []const s.Column, item: q.Item, rows: []const OrderedRow, key: Value) []const u8 {
    const op = item.operation;
    if (s.eq(op, "COLUMN")) return s.valueText(columns[item.column.?].kind, key, "NULL");
    if (s.eq(op, "COUNT") and item.column == null) return s.fmt("{d}", .{rows.len});
    const index = item.column.?;
    var values: std.ArrayList(Value) = .empty;
    for (rows) |row| if (row.row[index] != .null_value) s.append(Value, &values, row.row[index]);
    if (s.eq(op, "COUNT")) return s.fmt("{d}", .{values.items.len});
    if (s.eq(op, "COUNT_DISTINCT")) {
        std.mem.sort(Value, values.items, {}, struct {
            fn less(_: void, left: Value, right: Value) bool {
                return s.valueCompare(left, right) < 0;
            }
        }.less);
        var count: usize = 0;
        for (values.items, 0..) |value, i| if (i == 0 or !s.valueEqual(value, values.items[i - 1])) {
            count += 1;
        };
        return s.fmt("{d}", .{count});
    }
    if (values.items.len == 0) return "NULL";
    if (s.eq(op, "SUM") or s.eq(op, "AVG")) {
        var total: i64 = 0;
        for (values.items) |value| total += value.integer;
        if (s.eq(op, "SUM")) return s.fmt("{d}", .{total});
        const divisor = gcdValue(total, s.n(values.items.len));
        const numerator = @divTrunc(total, divisor);
        const denominator = @divTrunc(s.n(values.items.len), divisor);
        return if (denominator == 1) s.fmt("{d}", .{numerator}) else s.fmt("{d}/{d}", .{ numerator, denominator });
    }
    var selected = values.items[0];
    for (values.items[1..]) |value| {
        const comparison = s.valueCompare(value, selected);
        if ((s.eq(op, "MIN") and comparison < 0) or (s.eq(op, "MAX") and comparison > 0)) selected = value;
    }
    return s.valueText(columns[index].kind, selected, "NULL");
}
const Result = struct { kind: []const u8, matched: usize, output: s.Lines = .{} };
fn aggregateRow(result: *Result, columns: []const s.Column, query: *const q.Query, rows: []const OrderedRow,
     key: Value) void {
    var values: std.ArrayList([]const u8) = .empty;
    for (query.items.items) |item| s.append([]const u8, &values, aggregateItem(columns, item, rows, key));
    result.output.add("{s}", .{s.join(values.items, ",")});
}
fn buildResult(columns: []const s.Column, query: *const q.Query, matched: Table) Result {
    const ordered = s.alloc(OrderedRow, matched.len);
    for (matched, ordered, 0..) |row, *value, i| value.* = .{ .row = row, .position = i };
    var result: Result = .{ .kind = "rows", .matched = matched.len };
    if (!query.aggregate) {
        if (query.order) |index| std.mem.sort(OrderedRow, ordered, RowOrder{ .index = index,
             .descending = query.descending }, lessRow);
        for (ordered) |row| {
            var values: std.ArrayList([]const u8) = .empty;
            for (query.items.items) |item| s.append([]const u8, &values, s.valueText(columns[item.column.?].kind,
                 row.row[item.column.?], "NULL"));
            result.output.add("{s}", .{s.join(values.items, ",")});
        }
    } else if (query.group) |index| {
        result.kind = "grouped";
        std.mem.sort(OrderedRow, ordered, RowOrder{ .index = index, .descending = false }, lessRow);
        var start: usize = 0;
        while (start < ordered.len) {
            const key = ordered[start].row[index];
            var end = start + 1;
            while (end < ordered.len and s.valueEqual(key, ordered[end].row[index])) end += 1;
            aggregateRow(&result, columns, query, ordered[start..end], key);
            start = end;
        }
    } else {
        result.kind = "aggregate";
        aggregateRow(&result, columns, query, ordered, .null_value);
    }
    if (query.limit) |limit| if (result.output.data.items.len > limit) {
        result.output.data.items.len = limit;
    };
    return result;
}
fn resultEqual(left: Result, right: Result) bool {
    if (!s.eq(left.kind, right.kind) or left.matched != right.matched or left.output.data.items.len != right.output.data.items.len) return false;
    for (left.output.data.items, right.output.data.items) |a, other| if (!s.eq(a, other)) return false;
    return true;
}
fn countsText(counts: Counts) []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    for (scan_names, counts) |name, value| s.append([]const u8, &parts, s.fmt("{s} {d}", .{ name, value }));
    return s.join(parts.items, " ");
}
fn executeQueries(file: *const File, originals: Table, queries: s.Names, work_allocator: std.mem.Allocator) struct { results: s.Lines,
     statistics: s.Lines } {
    var results: s.Lines = .{};
    var statistics_lines: s.Lines = .{};
    var totals: Counts = @splat(0);
    var errors: usize = 0;
    var checks_ok: usize = 0;
    for (queries, 1..) |source, number| {
        const persistent = s.allocator;
        var work: std.heap.ArenaAllocator = .init(work_allocator);
        defer work.deinit();
        s.allocator = work.allocator();
        var query = q.parse(source);
        const failure = checkQuery(&query, file.columns);
        if (failure) |reason| {
            s.allocator = persistent;
            results.add("query {d} error {s}", .{ number, reason });
            statistics_lines.add("query {d} error {s}", .{ number, reason });
            errors += 1;
            continue;
        }
        const scanned = scan(file, &query);
        const result = buildResult(file.columns, &query, scanned.matched);
        var reference: std.ArrayList(Row) = .empty;
        for (originals) |row| if (evaluate(query.condition, row) == .true_value) s.append(Row, &reference, row);
        const correct = resultEqual(result, buildResult(file.columns, &query, reference.items));
        checks_ok += @intFromBool(correct);
        s.allocator = persistent;
        results.add("query {d} {s} matched {d} output {d}", .{ number, result.kind, result.matched,
             result.output.data.items.len });
        results.add("columns {s}", .{s.join(query.headers, ",")});
        results.extend(result.output);
        var needed: std.ArrayList([]const u8) = .empty;
        for (file.columns, 0..) |column, i| if (query.needed & columnBit(i) != 0) s.append([]const u8,
             &needed, column.name);
        statistics_lines.add("query {d} columns {s} {s} check {s}", .{ number, if (needed.items.len == 0) "-" else s.join(needed.items,
             ","), countsText(scanned.counts), if (correct) "ok" else "mismatch" });
        for (scanned.records, 0..) |record, g| statistics_lines.add("query {d} row_group {d} {s}",
             .{ number, g, if (record) |value| s.fmt("pages {s}", .{value}) else "skipped" });
        for (scanned.counts, 0..) |value, i| totals[i] += value;
    }
    statistics_lines.add("total queries {d} errors {d} {s} checks_ok {d}", .{ queries.len,
         errors, countsText(totals), checks_ok });
    return .{ .results = results, .statistics = statistics_lines };
}
fn recover(data: []const u8) struct { recovery: s.Lines, recovered: s.Lines } {
    const file = parseFile(data);
    const rows = s.alloc([]Value, file.rows);
    for (rows) |*row| row.* = s.zero(Value, file.columns.len, .unknown);
    var lines: s.Lines = .{};
    lines.add("file bytes {d} rows {d} columns {d} row_groups {d}", .{ data.len, file.rows,
         file.columns.len, file.groups.len });
    for (file.columns, 0..) |column, i| lines.add("{s}", .{columnLine(i, column)});
    var examined: usize = 0;
    var damaged_count: usize = 0;
    var lost_pages: usize = 0;
    var lost_cells: usize = 0;
    for (file.groups, 0..) |group, g| for (group.chunks, file.columns, 0..) |chunk, column, index| {
        var dictionary: Values = &.{};
        var dictionary_damaged = false;
        var row = group.first_row;
        for (0..chunk.pages.len + @intFromBool(chunk.has_dictionary)) |ordinal| {
            const is_dictionary = chunk.has_dictionary and ordinal == 0;
            const number = if (is_dictionary) 0 else ordinal - @intFromBool(chunk.has_dictionary);
            const page = if (is_dictionary) chunk.dictionary.? else chunk.pages[number];
            examined += 1;
            const checksum = b.adler32(pageBody(&file, page));
            const damaged = checksum != page.checksum;
            if (damaged) {
                damaged_count += 1;
                lines.add("damaged {d} {s} {s} offset {d} stored {s} computed {s}", .{ g, column.name,
                     if (is_dictionary) "dict" else s.fmt("{d}", .{number}), page.offset, b.checksumText(page.checksum),
                     b.checksumText(checksum) });
            }
            if (is_dictionary) {
                dictionary_damaged = damaged;
                if (!damaged) dictionary = decodeDictionary(&file, column, page);
                continue;
            }
            const reason: ?[]const u8 = if (damaged) "checksum" else if (page.method == .dictionary and dictionary_damaged) "dictionary" else null;
            if (reason) |failure| {
                lost_pages += 1;
                lost_cells += page.count;
                lines.add("lost {d} {s} {d} rows {d} reason {s}", .{ g, column.name, number, page.count, failure });
            } else {
                const values = decodePage(&file, column, page, dictionary);
                for (values, 0..) |value, offset| rows[row + offset][index] = value;
            }
            row += page.count;
        }
    };
    lines.add("summary pages {d} damaged {d} lost_pages {d} lost_cells {d} recovered_cells {d}",
         .{ examined, damaged_count, lost_pages, lost_cells, file.rows * file.columns.len - lost_cells });
    var recovered: s.Lines = .{};
    var names: std.ArrayList([]const u8) = .empty;
    for (file.columns) |column| s.append([]const u8, &names, column.name);
    recovered.add("{s}", .{s.join(names.items, ",")});
    for (rows) |row| {
        var values: std.ArrayList([]const u8) = .empty;
        for (file.columns, row) |column, value| s.append([]const u8, &values, s.valueText(column.kind, value, ""));
        recovered.add("{s}", .{s.join(values.items, ",")});
    }
    return .{ .recovery = lines, .recovered = recovered };
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    s.allocator = arena.allocator();
    const inputs = try s.readInputs(init.io);
    const built = buildFile(inputs, init.gpa);
    const file = parseFile(built.data);
    const metadata = verifyAndDescribe(&file, inputs.rows);
    const queries = executeQueries(&file, inputs.rows, inputs.queries, init.gpa);
    const recovery = recover(inputs.damaged);
    var hex_lines: s.Lines = .{};
    var start: usize = 0;
    while (start < built.data.len) : (start += 32) hex_lines.add("{s}", .{b.hexadecimal(built.data[start..@min(start + 32,
         built.data.len)])});
    try s.writeLines(init.io, "file.hex", hex_lines);
    try s.writeLines(init.io, "metadata.txt", metadata);
    try s.writeLines(init.io, "encoding_report.csv", built.report);
    try s.writeLines(init.io, "query_results.txt", queries.results);
    try s.writeLines(init.io, "query_stats.txt", queries.statistics);
    try s.writeLines(init.io, "recovery.txt", recovery.recovery);
    try s.writeLines(init.io, "recovered.csv", recovery.recovered);
}
