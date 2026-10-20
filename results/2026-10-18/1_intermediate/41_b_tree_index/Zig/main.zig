const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Command = enum { CREATE, LOAD, INSERT, BULKLOAD, DELETE, DELRANGE, GET, RANGE, COUNT, MIN, MAX, FLOOR, CEIL, RANK, SELECT, SEEK, NEXT, PREV, PRINT, PAGES, DUMP, HEIGHT, STATS, VERIFY, REBUILD, COMPACT, SAVE, RESTORE, TRACE };

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn integer(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }

const Value = struct {
    bytes: [12]u8 = undefined,
    len: usize,
    fn init(source: []const u8) Value {
        var value: Value = .{ .len = source.len };
        @memcpy(value.bytes[0..source.len], source);
        return value;
    }
    fn text(value: *const Value) []const u8 { return value.bytes[0..value.len]; }
    pub fn format(value: Value, out: *Writer) Writer.Error!void { try out.writeAll(value.text()); }
};
const Entry = struct {
    key: i64,
    value: Value,
    fn eql(a: Entry, b: Entry) bool { return a.key == b.key and equal(a.value.text(), b.value.text()); }
    pub fn format(entry: Entry, out: *Writer) Writer.Error!void { try out.print("{d}={f}", .{ entry.key, entry.value }); }
};
const Node = struct {
    entries: std.ArrayList(Entry) = .empty,
    children: std.ArrayList(usize) = .empty,
    fn leaf(node: *const Node) bool { return node.children.items.len == 0; }
    fn position(node: *const Node, key: i64) usize {
        for (node.entries.items, 0..) |entry, i| if (key <= entry.key) return i;
        return node.entries.items.len;
    }
    fn destroy(node: *Node, gpa: Allocator) void {
        node.entries.deinit(gpa);
        node.children.deinit(gpa);
        gpa.destroy(node);
    }
    fn clone(node: *const Node, gpa: Allocator) Allocator.Error!*Node {
        const result = try gpa.create(Node);
        result.* = .{};
        errdefer result.destroy(gpa);
        result.entries = try node.entries.clone(gpa);
        result.children = try node.children.clone(gpa);
        return result;
    }
    fn sameContent(a: *const Node, b: *const Node) bool {
        if (a.entries.items.len != b.entries.items.len or !std.mem.eql(usize, a.children.items, b.children.items)) return false;
        for (a.entries.items, b.entries.items) |left, right| if (!left.eql(right)) return false;
        return true;
    }
    pub fn format(node: Node, out: *Writer) Writer.Error!void {
        try out.writeByte('[');
        for (node.entries.items, 0..) |entry, i| {
            if (i > 0) try out.writeByte(' ');
            try out.print("{d}", .{entry.key});
        }
        try out.writeByte(']');
    }
};
const Search = struct { page: ?usize = null, position: usize = 0, path: [12]usize = undefined, len: usize = 0 };
const Bound = struct {
    value: ?i64,
    lower: bool,
    pub fn format(bound: Bound, out: *Writer) Writer.Error!void {
        if (bound.value) |value| try out.print("{d}", .{value}) else try out.writeAll(if (bound.lower) "-inf" else "+inf");
    }
};
const Trace = struct {
    gpa: Allocator,
    out: *Writer,
    enabled: bool,
    cases: std.ArrayList([]const u8) = .empty,
    fn emit(trace: *Trace, comptime fmt: []const u8, args: anytype) Writer.Error!void {
        if (trace.enabled) try line(trace.out, fmt, args);
    }
    fn record(trace: *Trace, name: []const u8) Allocator.Error!void { try trace.cases.append(trace.gpa, name); }
};

const Tree = struct {
    gpa: Allocator,
    degree: usize,
    root: usize = 0,
    pages: std.ArrayList(?*Node) = .empty,
    splits: usize = 0,
    merges: usize = 0,
    borrows: usize = 0,

    fn init(gpa: Allocator, degree: usize) Allocator.Error!Tree {
        var tree: Tree = .{ .gpa = gpa, .degree = degree };
        errdefer tree.deinit();
        tree.root = try tree.newPage();
        return tree;
    }
    fn deinit(tree: *Tree) void {
        for (tree.pages.items) |slot| if (slot) |item| item.destroy(tree.gpa);
        tree.pages.deinit(tree.gpa);
    }
    fn node(tree: *const Tree, page: usize) *Node { return tree.pages.items[page].?; }
    fn newPage(tree: *Tree) Allocator.Error!usize {
        const result = try tree.gpa.create(Node);
        result.* = .{};
        errdefer result.destroy(tree.gpa);
        for (tree.pages.items, 0..) |slot, page| if (slot == null) {
            tree.pages.items[page] = result;
            return page;
        };
        try tree.pages.append(tree.gpa, result);
        return tree.pages.items.len - 1;
    }
    fn freePage(tree: *Tree, page: usize) void {
        tree.node(page).destroy(tree.gpa);
        tree.pages.items[page] = null;
    }
    fn clone(tree: *const Tree) Allocator.Error!Tree {
        var result: Tree = .{ .gpa = tree.gpa, .degree = tree.degree, .root = tree.root,
            .splits = tree.splits, .merges = tree.merges, .borrows = tree.borrows };
        errdefer result.deinit();
        try result.pages.ensureTotalCapacity(tree.gpa, tree.pages.items.len);
        for (tree.pages.items) |slot| result.pages.appendAssumeCapacity(if (slot) |item| try item.clone(tree.gpa) else null);
        return result;
    }
    fn countNodes(tree: *const Tree) usize {
        var count: usize = 0;
        for (tree.pages.items) |slot| if (slot != null) { count += 1; };
        return count;
    }
    fn countEntries(tree: *const Tree) usize {
        var count: usize = 0;
        for (tree.pages.items) |slot| if (slot) |item| { count += item.entries.items.len; };
        return count;
    }
    fn changes(tree: *const Tree, before: *const Tree) struct { writes: usize, frees: usize } {
        var writes: usize = 0;
        var frees: usize = 0;
        for (tree.pages.items, 0..) |slot, page| if (slot) |item| {
            const old = if (page < before.pages.items.len) before.pages.items[page] else null;
            if (old == null or !item.sameContent(old.?)) writes += 1;
        };
        for (before.pages.items, 0..) |slot, page| if (slot != null and (page >= tree.pages.items.len or tree.pages.items[page] == null)) { frees += 1; };
        return .{ .writes = writes, .frees = frees };
    }
    fn height(tree: *const Tree) usize {
        var page = tree.root;
        var depth: usize = 0;
        while (!tree.node(page).leaf()) : (depth += 1) page = tree.node(page).children.items[0];
        return depth;
    }
    fn collect(tree: *const Tree, page: usize, gpa: Allocator, result: *std.ArrayList(Entry)) Allocator.Error!void {
        const item = tree.node(page);
        if (!item.leaf()) try tree.collect(item.children.items[0], gpa, result);
        for (item.entries.items, 0..) |entry, i| {
            try result.append(gpa, entry);
            if (!item.leaf()) try tree.collect(item.children.items[i + 1], gpa, result);
        }
    }
    fn entries(tree: *const Tree, gpa: Allocator) Allocator.Error![]const Entry {
        var result: std.ArrayList(Entry) = .empty;
        try tree.collect(tree.root, gpa, &result);
        return result.toOwnedSlice(gpa);
    }
    fn search(tree: *const Tree, key: i64) Search {
        var result: Search = .{};
        var page = tree.root;
        while (true) {
            const item = tree.node(page);
            const position = item.position(key);
            result.path[result.len] = page;
            result.len += 1;
            if (position < item.entries.items.len and item.entries.items[position].key == key) {
                result.page = page;
                result.position = position;
                return result;
            }
            if (item.leaf()) return result;
            page = item.children.items[position];
        }
    }
    fn checkNode(tree: *const Tree, page: usize, location: []const u8, depth: usize, low: ?i64, high: ?i64,
        expected: *?usize, gpa: Allocator) Allocator.Error!?[]const u8 {
        const item = tree.node(page);
        const count = item.entries.items.len;
        const minimum = if (page == tree.root) @as(usize, if (item.leaf()) 0 else 1) else tree.degree - 1;
        const maximum = 2 * tree.degree - 1;
        if (count < minimum or count > maximum) return try std.fmt.allocPrint(gpa,
            "COUNT at={s} node={f} keys={d} allowed={d}..{d}", .{ location, item.*, count, minimum, maximum });
        for (item.entries.items, 0..) |entry, i| {
            if (i + 1 < count and entry.key >= item.entries.items[i + 1].key) return try std.fmt.allocPrint(gpa,
                "ORDER at={s} node={f} {d}>={d}", .{ location, item.*, entry.key, item.entries.items[i + 1].key });
        }
        for (item.entries.items) |entry| {
            if ((low != null and entry.key <= low.?) or (high != null and entry.key >= high.?)) return try std.fmt.allocPrint(gpa,
                "RANGE at={s} node={f} key={d} low={f} high={f}", .{ location, item.*, entry.key, Bound{ .value = low, .lower = true }, Bound{ .value = high, .lower = false } });
        }
        if (item.leaf()) {
            if (expected.*) |reference| {
                if (depth != reference) return try std.fmt.allocPrint(gpa, "DEPTH at={s} node={f} depth={d} expected={d}", .{ location, item.*, depth, reference });
            } else expected.* = depth;
        }
        for (item.children.items, 0..) |child, i| {
            const path = try std.fmt.allocPrint(gpa, "{s}.{d}", .{ location, i });
            if (try tree.checkNode(child, path, depth + 1, if (i == 0) low else item.entries.items[i - 1].key,
                if (i == count) high else item.entries.items[i].key, expected, gpa)) |problem| return problem;
        }
        return null;
    }
    fn violation(tree: *const Tree, gpa: Allocator) Allocator.Error!?[]const u8 {
        var expected: ?usize = null;
        return tree.checkNode(tree.root, "root", 0, null, null, &expected, gpa);
    }
    fn splitChild(tree: *Tree, parent_page: usize, position: usize, trace: *Trace) Error!void {
        const parent = tree.node(parent_page);
        const child_page = parent.children.items[position];
        const child = tree.node(child_page);
        const middle = child.entries.items[tree.degree - 1];
        const right_page = try tree.newPage();
        const right = tree.node(right_page);
        try trace.emit("STEP split page={d} keys={f} up={d} new={d}", .{ child_page, child.*, middle.key, right_page });
        try right.entries.appendSlice(tree.gpa, child.entries.items[tree.degree..]);
        if (!child.leaf()) try right.children.appendSlice(tree.gpa, child.children.items[tree.degree..]);
        child.entries.shrinkRetainingCapacity(tree.degree - 1);
        if (!child.leaf()) child.children.shrinkRetainingCapacity(tree.degree);
        try parent.entries.insert(tree.gpa, position, middle);
        try parent.children.insert(tree.gpa, position + 1, right_page);
        tree.splits += 1;
    }
    fn upsert(tree: *Tree, key: i64, value: Value, trace: *Trace) Error!?Value {
        const found = tree.search(key);
        if (found.page) |page| {
            const item = tree.node(page);
            const old = item.entries.items[found.position].value;
            item.entries.items[found.position] = .{ .key = key, .value = value };
            return old;
        }
        if (tree.node(tree.root).entries.items.len == 2 * tree.degree - 1) {
            const previous = tree.root;
            tree.root = try tree.newPage();
            try tree.node(tree.root).children.append(tree.gpa, previous);
            try trace.emit("STEP grow page={d}", .{tree.root});
            try tree.splitChild(tree.root, 0, trace);
        }
        var page = tree.root;
        while (!tree.node(page).leaf()) {
            const item = tree.node(page);
            var position = item.position(key);
            if (tree.node(item.children.items[position]).entries.items.len == 2 * tree.degree - 1) {
                try tree.splitChild(page, position, trace);
                if (key > item.entries.items[position].key) position += 1;
            }
            page = item.children.items[position];
        }
        const leaf = tree.node(page);
        try leaf.entries.insert(tree.gpa, leaf.position(key), .{ .key = key, .value = value });
        try trace.emit("STEP place page={d} keys={f}", .{ page, leaf.* });
        return null;
    }
    fn merge(tree: *Tree, parent_page: usize, position: usize, case_name: []const u8, trace: *Trace) Error!usize {
        const parent = tree.node(parent_page);
        const left_page = parent.children.items[position];
        const right_page = parent.children.items[position + 1];
        const left = tree.node(left_page);
        const right = tree.node(right_page);
        try left.entries.append(tree.gpa, parent.entries.orderedRemove(position));
        try left.entries.appendSlice(tree.gpa, right.entries.items);
        try left.children.appendSlice(tree.gpa, right.children.items);
        _ = parent.children.orderedRemove(position + 1);
        tree.freePage(right_page);
        tree.merges += 1;
        try trace.emit("STEP {s} page={d} merge={d}+{d} keys={f}", .{ case_name, parent_page, left_page, right_page, left.* });
        if (parent_page == tree.root and parent.entries.items.len == 0) {
            tree.root = left_page;
            tree.freePage(parent_page);
            try trace.emit("STEP shrink page={d}", .{tree.root});
        }
        return left_page;
    }
    fn removeAt(tree: *Tree, page: usize, key: i64, trace: *Trace) Error!void {
        const item = tree.node(page);
        const position = item.position(key);
        if (position < item.entries.items.len and item.entries.items[position].key == key) {
            if (item.leaf()) {
                try trace.record("1");
                _ = item.entries.orderedRemove(position);
                try trace.emit("STEP 1 page={d} keys={f}", .{ page, item.* });
                return;
            }
            const left = item.children.items[position];
            const right = item.children.items[position + 1];
            if (tree.node(left).entries.items.len >= tree.degree) {
                var last = left;
                while (!tree.node(last).leaf()) {
                    const children = tree.node(last).children.items;
                    last = children[children.len - 1];
                }
                const rows = tree.node(last).entries.items;
                const predecessor = rows[rows.len - 1];
                try trace.record("2a");
                try trace.emit("STEP 2a page={d} pred={d}", .{ page, predecessor.key });
                try tree.removeAt(left, predecessor.key, trace);
                item.entries.items[position] = predecessor;
            } else if (tree.node(right).entries.items.len >= tree.degree) {
                var first = right;
                while (!tree.node(first).leaf()) first = tree.node(first).children.items[0];
                const successor = tree.node(first).entries.items[0];
                try trace.record("2b");
                try trace.emit("STEP 2b page={d} succ={d}", .{ page, successor.key });
                try tree.removeAt(right, successor.key, trace);
                item.entries.items[position] = successor;
            } else {
                try trace.record("2c");
                const child = try tree.merge(page, position, "2c", trace);
                try tree.removeAt(child, key, trace);
            }
            return;
        }
        var child_page = item.children.items[position];
        const child = tree.node(child_page);
        if (child.entries.items.len == tree.degree - 1) {
            const left_page: ?usize = if (position > 0) item.children.items[position - 1] else null;
            const right_page: ?usize = if (position < item.entries.items.len) item.children.items[position + 1] else null;
            if (left_page != null and tree.node(left_page.?).entries.items.len >= tree.degree) {
                const sibling = tree.node(left_page.?);
                try trace.record("3a-left");
                try child.entries.insert(tree.gpa, 0, item.entries.items[position - 1]);
                item.entries.items[position - 1] = sibling.entries.pop().?;
                if (!sibling.leaf()) try child.children.insert(tree.gpa, 0, sibling.children.pop().?);
                tree.borrows += 1;
                try trace.emit("STEP 3a-left page={d} child={d} from={d} keys={f}", .{ page, child_page, left_page.?, child.* });
            } else if (right_page != null and tree.node(right_page.?).entries.items.len >= tree.degree) {
                const sibling = tree.node(right_page.?);
                try trace.record("3a-right");
                try child.entries.append(tree.gpa, item.entries.items[position]);
                item.entries.items[position] = sibling.entries.orderedRemove(0);
                if (!sibling.leaf()) try child.children.append(tree.gpa, sibling.children.orderedRemove(0));
                tree.borrows += 1;
                try trace.emit("STEP 3a-right page={d} child={d} from={d} keys={f}", .{ page, child_page, right_page.?, child.* });
            } else if (left_page != null) {
                try trace.record("3b-left");
                child_page = try tree.merge(page, position - 1, "3b-left", trace);
            } else {
                try trace.record("3b-right");
                child_page = try tree.merge(page, position, "3b-right", trace);
            }
        }
        try tree.removeAt(child_page, key, trace);
    }
    fn remove(tree: *Tree, key: i64, trace: *Trace) Error!void {
        trace.cases.clearRetainingCapacity();
        try tree.removeAt(tree.root, key, trace);
    }
    fn scanNode(tree: *const Tree, page: usize, low: i64, high: i64, gpa: Allocator,
        result: *std.ArrayList(Entry), visited: *usize) Allocator.Error!void {
        visited.* += 1;
        const item = tree.node(page);
        const count = item.entries.items.len;
        for (0..count + 1) |i| {
            if (!item.leaf() and (i == 0 or item.entries.items[i - 1].key < high) and (i == count or item.entries.items[i].key > low)) {
                try tree.scanNode(item.children.items[i], low, high, gpa, result, visited);
            }
            if (i < count and low <= item.entries.items[i].key and item.entries.items[i].key <= high) try result.append(gpa, item.entries.items[i]);
        }
    }
    fn dumpNode(tree: *const Tree, page: usize, out: *Writer) Writer.Error!void {
        const item = tree.node(page);
        try out.writeByte('(');
        if (!item.leaf()) { try out.writeByte(' '); try tree.dumpNode(item.children.items[0], out); }
        for (item.entries.items, 0..) |entry, i| {
            try out.print(" {f}", .{entry});
            if (!item.leaf()) { try out.writeByte(' '); try tree.dumpNode(item.children.items[i + 1], out); }
        }
        try out.writeAll(" )");
    }
    const Group = struct { rows: []const Entry, children: []const usize };
    fn copyGroup(tree: *Tree, groups: []const Group, old_page: usize) Allocator.Error!usize {
        const page = try tree.newPage();
        const item = tree.node(page);
        const old = groups[old_page];
        try item.entries.appendSlice(tree.gpa, old.rows);
        for (old.children) |child| {
            const new_child = try tree.copyGroup(groups, child);
            try item.children.append(tree.gpa, new_child);
        }
        return page;
    }
    fn compact(tree: *Tree, scratch: Allocator) Allocator.Error!void {
        var source = try tree.entries(scratch);
        var children: []const usize = &.{};
        var built: std.ArrayList(Group) = .empty;
        var old_root: usize = undefined;
        while (true) {
            const groups = (source.len + 2 * tree.degree) / (2 * tree.degree);
            const count = source.len - (groups - 1);
            const size = count / groups;
            const extra = count % groups;
            var entry_index: usize = 0;
            var child_index: usize = 0;
            var nodes: std.ArrayList(usize) = .empty;
            var separators: std.ArrayList(Entry) = .empty;
            for (0..groups) |group| {
                const length = size + @intFromBool(group < extra);
                try nodes.append(scratch, built.items.len);
                try built.append(scratch, .{ .rows = source[entry_index..][0..length],
                    .children = if (children.len == 0) &.{} else children[child_index..][0..length + 1] });
                entry_index += length;
                child_index += length + 1;
                if (group + 1 < groups) {
                    try separators.append(scratch, source[entry_index]);
                    entry_index += 1;
                }
            }
            if (groups == 1) { old_root = nodes.items[0]; break; }
            source = separators.items;
            children = nodes.items;
        }
        var replacement: Tree = .{ .gpa = tree.gpa, .degree = tree.degree };
        errdefer replacement.deinit();
        replacement.root = try replacement.copyGroup(built.items, old_root);
        tree.deinit();
        tree.* = replacement;
    }
};

const Loader = struct {
    tree: *Tree,
    tokens: []const []const u8,
    position: usize = 0,
    fn entry(loader: *Loader) error{Invalid}!Entry {
        if (loader.position == loader.tokens.len) return error.Invalid;
        const token = loader.tokens[loader.position];
        if (equal(token, "(") or equal(token, ")")) return error.Invalid;
        const split = std.mem.findScalar(u8, token, '=').?;
        loader.position += 1;
        return .{ .key = integer(token[0..split]), .value = Value.init(token[split + 1..]) };
    }
    fn parseNode(loader: *Loader) (Allocator.Error || error{Invalid})!usize {
        if (loader.position == loader.tokens.len or !equal(loader.tokens[loader.position], "(")) return error.Invalid;
        loader.position += 1;
        const page = try loader.tree.newPage();
        const item = loader.tree.node(page);
        if (loader.position < loader.tokens.len and equal(loader.tokens[loader.position], "(")) {
            try item.children.append(loader.tree.gpa, try loader.parseNode());
            while (loader.position == loader.tokens.len or !equal(loader.tokens[loader.position], ")")) {
                try item.entries.append(loader.tree.gpa, try loader.entry());
                try item.children.append(loader.tree.gpa, try loader.parseNode());
            }
        } else {
            while (loader.position == loader.tokens.len or !equal(loader.tokens[loader.position], ")")) {
                try item.entries.append(loader.tree.gpa, try loader.entry());
            }
        }
        loader.position += 1;
        return page;
    }
};
const Cursor = union(enum) { unset, key: i64, begin, end };
const Workbench = struct {
    gpa: Allocator,
    index: ?Tree = null,
    saved: ?Tree = null,
    cursor: Cursor = .unset,
    trace: bool = false,
    fn deinit(lab: *Workbench) void {
        if (lab.index) |*tree| tree.deinit();
        if (lab.saved) |*tree| tree.deinit();
    }
    fn replace(lab: *Workbench, next: Tree) void {
        if (lab.index) |*tree| tree.deinit();
        lab.index = next;
    }
};
const Relation = enum { all, less, greater, at_most, at_least };
fn candidate(rows: []const Entry, key: i64, relation: Relation, last: bool) ?Entry {
    var result: ?Entry = null;
    for (rows) |entry| {
        const matches = switch (relation) {
            .all => true, .less => entry.key < key, .greater => entry.key > key,
            .at_most => entry.key <= key, .at_least => entry.key >= key,
        };
        if (!matches) continue;
        result = entry;
        if (!last) break;
    }
    return result;
}
const Session = struct {
    gpa: Allocator,
    out: *Writer,
    lab: *Workbench,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error!void {
        session.problem = try std.fmt.allocPrint(session.gpa, fmt, args);
        return error.Invalid;
    }
    fn summary(session: *Session, prefix: []const u8, tree: *const Tree) Error!void {
        try line(session.out, "{s} nodes={d} keys={d} {s}", .{ prefix, tree.countNodes(), tree.countEntries(),
            if (try tree.violation(session.gpa) == null) "OK" else "DAMAGED" });
    }
    fn execute(session: *Session, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]).?;
        const out = session.out;
        const lab = session.lab;
        if (command == .TRACE) {
            lab.trace = equal(words[1], "ON");
            return line(out, "TRACE {s}", .{words[1]});
        }
        const first = if (words.len > 1) integer(words[1]) else 0;
        const ranged = command == .DELRANGE or command == .RANGE or command == .COUNT;
        const second = if (ranged) integer(words[2]) else 0;
        if (command == .CREATE or command == .LOAD) {
            if (first < 2 or first > 5) return session.fail("BAD DEGREE {d}", .{first});
            const degree: usize = @intCast(first);
            var replacement: Tree = .{ .gpa = lab.gpa, .degree = degree };
            errdefer replacement.deinit();
            if (command == .CREATE) {
                replacement.root = try replacement.newPage();
            } else {
                var loader: Loader = .{ .tree = &replacement, .tokens = words[2..] };
                replacement.root = loader.parseNode() catch |err| switch (err) {
                    error.Invalid => return session.fail("SYNTAX {d}", .{loader.position + 1}),
                    else => return err,
                };
                if (loader.position != loader.tokens.len) return session.fail("SYNTAX {d}", .{loader.position + 1});
            }
            if (command == .CREATE) {
                try line(out, "CREATE t={d}", .{first});
            } else {
                try session.summary(try std.fmt.allocPrint(session.gpa, "LOAD t={d}", .{first}), &replacement);
            }
            lab.replace(replacement);
            lab.cursor = .unset;
            return;
        }
        const tree = if (lab.index) |*value| value else return session.fail("NO INDEX", .{});
        const needs_valid = switch (command) {
            .INSERT, .BULKLOAD, .DELETE, .DELRANGE, .RANGE, .COUNT, .MIN, .MAX, .FLOOR, .CEIL,
            .RANK, .SELECT, .SEEK, .NEXT, .PREV, .HEIGHT, .COMPACT => true,
            else => false,
        };
        if (needs_valid and try tree.violation(session.gpa) != null) return session.fail("DAMAGED", .{});
        const rows = try tree.entries(session.gpa);
        if (ranged and first > second) return session.fail("BAD RANGE {d} {d}", .{ first, second });
        if (command == .SELECT and (first < 1 or first > @as(i64, @intCast(rows.len)))) return session.fail("BAD POSITION {d}", .{first});
        if (command == .NEXT or command == .PREV) switch (lab.cursor) {
            .unset => return session.fail("NO CURSOR", .{}),
            else => {},
        };
        if (command == .RESTORE and lab.saved == null) return session.fail("NO SAVE", .{});
        var trace: Trace = .{ .gpa = session.gpa, .out = out, .enabled = lab.trace and (command == .INSERT or command == .DELETE) };
        switch (command) {
            .INSERT => {
                var before = try tree.clone();
                defer before.deinit();
                const splits = tree.splits;
                const old = try tree.upsert(first, Value.init(words[2]), &trace);
                const writes = tree.changes(&before).writes;
                if (old) |value| {
                    try line(out, "INSERT {d} UPDATED old={f} writes={d}", .{ first, value, writes });
                } else try line(out, "INSERT {d} NEW splits={d} height={d} writes={d}", .{ first, tree.splits - splits, tree.height(), writes });
            },
            .BULKLOAD => {
                var before = try tree.clone();
                defer before.deinit();
                const splits = tree.splits;
                var inserted: usize = 0;
                var updated: usize = 0;
                var i: usize = 1;
                while (i < words.len) : (i += 2) {
                    if (try tree.upsert(integer(words[i]), Value.init(words[i + 1]), &trace) == null) inserted += 1 else updated += 1;
                }
                try line(out, "BULKLOAD pairs={d} new={d} updated={d} splits={d} height={d} writes={d}",
                    .{ (words.len - 1) / 2, inserted, updated, tree.splits - splits, tree.height(), tree.changes(&before).writes });
            },
            .DELETE => {
                const found = tree.search(first);
                if (found.page) |page| {
                    const value = tree.node(page).entries.items[found.position].value;
                    var before = try tree.clone();
                    defer before.deinit();
                    try tree.remove(first, &trace);
                    const changes = tree.changes(&before);
                    try out.print("DELETE {d} REMOVED value={f} cases=", .{ first, value });
                    for (trace.cases.items, 0..) |name, i| {
                        if (i > 0) try out.writeByte(',');
                        try out.writeAll(name);
                    }
                    try line(out, " height={d} writes={d} frees={d}", .{ tree.height(), changes.writes, changes.frees });
                } else try line(out, "DELETE {d} NOT FOUND", .{first});
            },
            .DELRANGE => {
                var before = try tree.clone();
                defer before.deinit();
                const merges = tree.merges;
                const borrows = tree.borrows;
                var removed: usize = 0;
                for (rows) |entry| if (first <= entry.key and entry.key <= second) {
                    try tree.remove(entry.key, &trace);
                    removed += 1;
                };
                const changes = tree.changes(&before);
                try line(out, "DELRANGE {d} {d} removed={d} merges={d} borrows={d} height={d} writes={d} frees={d}",
                    .{ first, second, removed, tree.merges - merges, tree.borrows - borrows, tree.height(), changes.writes, changes.frees });
            },
            .GET => {
                const found = tree.search(first);
                try out.print("GET {d} ", .{first});
                if (found.page) |page| {
                    try out.print("FOUND value={f}", .{tree.node(page).entries.items[found.position].value});
                } else try out.writeAll("NOT FOUND");
                try out.writeAll(" path=");
                for (found.path[0..found.len], 0..) |page, i| {
                    if (i > 0) try out.writeAll(" -> ");
                    try out.print("{f}", .{tree.node(page).*});
                }
                try out.writeByte('\n');
            },
            .RANGE, .COUNT => {
                var result: std.ArrayList(Entry) = .empty;
                var visited: usize = 0;
                try tree.scanNode(tree.root, first, second, session.gpa, &result, &visited);
                try out.print("{s} {d} {d} count={d} visited={d}", .{ words[0], first, second, result.items.len, visited });
                if (command == .RANGE) for (result.items) |entry| { try out.print(" {f}", .{entry}); };
                try out.writeByte('\n');
            },
            .MIN, .MAX => {
                try out.print("{s} ", .{words[0]});
                if (rows.len == 0) try line(out, "EMPTY", .{}) else try line(out, "{f}", .{rows[if (command == .MIN) 0 else rows.len - 1]});
            },
            .FLOOR, .CEIL => {
                const entry = candidate(rows, first, if (command == .FLOOR) .at_most else .at_least, command == .FLOOR);
                try out.print("{s} {d} ", .{ words[0], first });
                if (entry) |value| try line(out, "{f}", .{value}) else try line(out, "NONE", .{});
            },
            .RANK => {
                var rank: usize = 0;
                for (rows) |entry| if (entry.key < first) { rank += 1; };
                try line(out, "RANK {d} {d}", .{ first, rank });
            },
            .SELECT => try line(out, "SELECT {d} {f}", .{ first, rows[@intCast(first - 1)] }),
            .SEEK => {
                const entry = candidate(rows, first, .at_least, false);
                lab.cursor = if (entry) |value| .{ .key = value.key } else .end;
                try out.print("SEEK {d} ", .{first});
                if (entry) |value| try line(out, "{f}", .{value}) else try line(out, "END", .{});
            },
            .NEXT, .PREV => {
                const entry = if (command == .NEXT) switch (lab.cursor) {
                    .begin => candidate(rows, 0, .all, false), .key => |key| candidate(rows, key, .greater, false),
                    .end => null, .unset => unreachable,
                } else switch (lab.cursor) {
                    .end => candidate(rows, 0, .all, true), .key => |key| candidate(rows, key, .less, true),
                    .begin => null, .unset => unreachable,
                };
                lab.cursor = if (entry) |value| .{ .key = value.key } else if (command == .NEXT) .end else .begin;
                try out.print("{s} ", .{words[0]});
                if (entry) |value| try line(out, "{f}", .{value}) else try line(out, "{s}", .{if (command == .NEXT) "END" else "BEGIN"});
            },
            .PRINT => {
                var level: std.ArrayList(usize) = .empty;
                try level.append(session.gpa, tree.root);
                var depth: usize = 0;
                while (level.items.len > 0) : (depth += 1) {
                    var next: std.ArrayList(usize) = .empty;
                    try out.print("LEVEL {d}", .{depth});
                    for (level.items) |page| {
                        const item = tree.node(page);
                        try out.print(" {f}", .{item.*});
                        try next.appendSlice(session.gpa, item.children.items);
                    }
                    try out.writeByte('\n');
                    level = next;
                }
            },
            .PAGES => {
                for (tree.pages.items, 0..) |slot, page| if (slot) |item| {
                    try out.print("PAGE {d} {f} kids=", .{ page, item.* });
                    if (item.leaf()) try out.writeByte('-') else for (item.children.items, 0..) |child, i| {
                        if (i > 0) try out.writeByte(',');
                        try out.print("{d}", .{child});
                    };
                    try out.writeByte('\n');
                };
            },
            .DUMP => {
                try out.print("DUMP {d} ", .{tree.degree});
                try tree.dumpNode(tree.root, out);
                try out.writeByte('\n');
            },
            .HEIGHT => try line(out, "HEIGHT {d}", .{tree.height()}),
            .STATS => {
                var leaves: usize = 0;
                for (tree.pages.items) |slot| if (slot) |item| { if (item.leaf()) leaves += 1; };
                const nodes = tree.countNodes();
                const fill = 100 * rows.len / ((2 * tree.degree - 1) * nodes);
                try line(out, "STATS t={d} nodes={d} leaves={d} keys={d} fill={d}% splits={d} merges={d} borrows={d}",
                    .{ tree.degree, nodes, leaves, rows.len, fill, tree.splits, tree.merges, tree.borrows });
            },
            .VERIFY => {
                if (try tree.violation(session.gpa)) |problem| try line(out, "VERIFY FAIL {s}", .{problem}) else try line(out, "VERIFY OK", .{});
            },
            .REBUILD => {
                var replacement = try Tree.init(lab.gpa, tree.degree);
                errdefer replacement.deinit();
                for (rows) |entry| _ = try replacement.upsert(entry.key, entry.value, &trace);
                try line(out, "REBUILD entries={d} keys={d} nodes={d} splits={d} height={d}",
                    .{ rows.len, replacement.countEntries(), replacement.countNodes(), replacement.splits, replacement.height() });
                lab.replace(replacement);
            },
            .COMPACT => {
                const nodes = tree.countNodes();
                try tree.compact(session.gpa);
                try line(out, "COMPACT nodes={d}->{d} height={d}", .{ nodes, tree.countNodes(), tree.height() });
            },
            .SAVE => {
                const replacement = try tree.clone();
                if (lab.saved) |*old| old.deinit();
                lab.saved = replacement;
                try session.summary("SAVE", tree);
            },
            .RESTORE => {
                const replacement = try lab.saved.?.clone();
                lab.replace(replacement);
                try session.summary("RESTORE", &lab.index.?);
            },
            .CREATE, .LOAD, .TRACE => unreachable,
        }
    }
};

fn readLine(reader: *std.Io.Reader, gpa: Allocator) !?[]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = reader.streamDelimiterEnding(&buffer.writer, '\n') catch |err| switch (err) {
        error.EndOfStream => {
            if (buffer.written().len == 0) return null;
            return try buffer.toOwnedSlice();
        },
        else => return err,
    };
    reader.toss(1);
    return try buffer.toOwnedSlice();
}
fn readWords(gpa: Allocator, source: []const u8) Allocator.Error![]const []const u8 {
    var words: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.tokenizeAny(u8, source, " \r");
    while (tokens.next()) |word| try words.append(gpa, word);
    return words.toOwnedSlice(gpa);
}
pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var first_arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer first_arena.deinit();
    const count: usize = @intCast(integer(std.mem.trim(u8, (try readLine(&input.interface, first_arena.allocator())).?, "\r")));
    var lab: Workbench = .{ .gpa = std.heap.smp_allocator };
    defer lab.deinit();
    for (0..count) |_| {
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const words = try readWords(gpa, (try readLine(&input.interface, gpa)).?);
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = gpa, .out = &response.writer, .lab = &lab };
        session.execute(words) catch |err| switch (err) {
            error.Invalid => {
                try line(&output.interface, "ERROR {s}", .{session.problem});
                try output.interface.flush();
                continue;
            },
            else => return err,
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
