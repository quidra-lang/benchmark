const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn number(word: []const u8) i64 { return std.fmt.parseInt(i64, word, 10) catch unreachable; }
pub fn integer(word: []const u8) usize { return @intCast(number(word)); }
pub fn decimal(word: []const u8) f64 { return std.fmt.parseFloat(f64, word) catch unreachable; }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn real(value: anytype) f64 { return @floatFromInt(value); }
pub fn abs(value: i64) i64 { return if (value < 0) -value else value; }
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub fn textLess(_: void, first: []const u8, second: []const u8) bool { return std.mem.order(u8, first, second) == .lt; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, source: []const u8) void { self.data.appendSlice(allocator, source) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, source: []const u8) void { append([]const u8, &self.data, source); }
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void { self.write(fmt(pattern, args)); }
    pub fn extend(self: *Lines, other: Lines) void { self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed"); }
    pub fn blank(self: *Lines) void { self.write(""); }
};
pub const Page = struct { id: usize, host: []const u8, title: []const u8, words: Strings };
pub const Record = struct { line: usize, source: usize, target: usize };
pub const Query = struct { words: Strings, seeds: []usize };
pub const Settings = struct { damping: f64, iterations: usize, tolerance: f64, sweep: []f64, trusted: []usize, spam_top: usize, spam_threshold: f64, hits_iterations: usize, top_k: usize, root_limit: usize, neighbor_limit: usize };
pub const Input = struct { pages: []Page, records: []Record, queries: []Query, settings: Settings };
fn pageLess(_: void, first: Page, second: Page) bool { return first.id < second.id; }
pub fn load(io: std.Io) !Input {
    const directory = std.Io.Dir.cwd();
    const page_lines = lines(try directory.readFileAlloc(io, "input/pages.csv", allocator, .unlimited))[1..];
    const pages = alloc(Page, page_lines.len);
    for (page_lines, pages) |line, *page| {
        const fields = split(line, ',');
        page.* = .{ .id = integer(fields[0]), .host = fields[1], .title = fields[2], .words = split(fields[2], ' ') };
    }
    std.mem.sort(Page, pages, {}, pageLess);
    const link_lines = lines(try directory.readFileAlloc(io, "input/links.csv", allocator, .unlimited))[1..];
    const records = alloc(Record, link_lines.len);
    for (link_lines, records, 2..) |line, *record, i| {
        const fields = split(line, ',');
        record.* = .{ .line = i, .source = integer(fields[0]), .target = integer(fields[1]) };
    }
    const query_lines = lines(try directory.readFileAlloc(io, "input/queries.txt", allocator, .unlimited));
    const queries = alloc(Query, query_lines.len);
    for (query_lines, queries) |line, *query| {
        const bar = std.mem.indexOf(u8, line, " | ").?;
        const fields = split(line[bar + 3 ..], ' ');
        const seeds = alloc(usize, fields.len);
        for (fields, seeds) |field, *seed| seed.* = integer(field);
        query.* = .{ .words = split(line[0..bar], ' '), .seeds = seeds };
    }
    const parameters = lines(try directory.readFileAlloc(io, "input/params.txt", allocator, .unlimited));
    var values: [11]Strings = undefined;
    for (parameters, &values) |line, *fields| fields.* = split(line, ' ')[1..];
    const sweep = alloc(f64, values[3].len);
    for (values[3], sweep) |word, *value| value.* = decimal(word);
    const trusted = alloc(usize, values[4].len);
    for (values[4], trusted) |word, *value| value.* = integer(word);
    return .{ .pages = pages, .records = records, .queries = queries, .settings = .{ .damping = decimal(values[0][0]), .iterations = integer(values[1][0]), .tolerance = decimal(values[2][0]), .sweep = sweep, .trusted = trusted, .spam_top = integer(values[5][0]), .spam_threshold = decimal(values[6][0]), .hits_iterations = integer(values[7][0]), .top_k = integer(values[8][0]), .root_limit = integer(values[9][0]), .neighbor_limit = integer(values[10][0]) } };
}
pub const Graph = struct {
    count: usize, weights: []usize, out: [][]usize, in: [][]usize,
    pub fn init(count: usize, weights: []usize) Graph {
        const out = alloc([]usize, count);
        const incoming = alloc([]usize, count);
        var out_counts = [_]usize{0} ** 500;
        var in_counts = [_]usize{0} ** 500;
        for (0..count) |u| { for (0..count) |v| { if (weights[u * count + v] > 0) { out_counts[u] += 1; in_counts[v] += 1; } } }
        for (0..count) |u| { out[u] = alloc(usize, out_counts[u]); incoming[u] = alloc(usize, in_counts[u]); }
        @memset(&out_counts, 0);
        @memset(&in_counts, 0);
        for (0..count) |u| {
            for (0..count) |v| {
                if (weights[u * count + v] == 0) continue;
                out[u][out_counts[u]] = v;
                incoming[v][in_counts[v]] = u;
                out_counts[u] += 1;
                in_counts[v] += 1;
            }
        }
        return .{ .count = count, .weights = weights, .out = out, .in = incoming };
    }
};
