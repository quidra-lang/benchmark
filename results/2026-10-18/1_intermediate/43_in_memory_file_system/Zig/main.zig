const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Text = []const u8;
const Error = Allocator.Error || Writer.Error;
const Lines = std.ArrayList(*Line);
const Nodes = std.ArrayList(*Node);
const Kind = enum { directory, file, link };
const Verb = enum { pwd, cd, mkdir, touch, echo, cat, ls, stat, rm, rmdir, mv, cp, ln, readlink, realpath, find, du, tree, wc, head, tail, grep, sort, uniq };

const Line = struct {
    references: usize = 1,
    text: Text,

    fn create(gpa: Allocator, text: Text) Allocator.Error!*Line {
        const result = try gpa.create(Line);
        errdefer gpa.destroy(result);
        result.* = .{ .text = try gpa.dupe(u8, text) };
        return result;
    }
    fn release(line: *Line, gpa: Allocator) void {
        line.references -= 1;
        if (line.references == 0) {
            gpa.free(line.text);
            gpa.destroy(line);
        }
    }
};
fn releaseLines(items: []const *Line, gpa: Allocator) void {
    for (items) |item| item.release(gpa);
}
const Content = union(Kind) { directory: Nodes, file: Lines, link: Text };
const Node = struct {
    inode: usize,
    modified: usize,
    parent: *Node,
    name: Text = "",
    content: Content,

    fn kind(node: *const Node) Kind { return std.meta.activeTag(node.content); }
    fn tag(node: *const Node) u8 {
        return switch (node.content) { .directory => 'd', .file => '-', .link => 'l' };
    }
    fn size(node: *const Node) u64 {
        return switch (node.content) {
            .directory => |children| children.items.len,
            .link => |target| target.len,
            .file => |lines| blk: {
                var bytes: u64 = 0;
                for (lines.items) |line| bytes += line.text.len + 1;
                break :blk bytes;
            },
        };
    }
    fn links(node: *const Node) usize {
        if (node.kind() != .directory) return 1;
        var count: usize = 2;
        for (node.content.directory.items) |entry| count += @intFromBool(entry.kind() == .directory);
        return count;
    }
    fn child(node: *const Node, name: Text) ?*Node {
        for (node.content.directory.items) |item| if (equal(item.name, name)) return item;
        return null;
    }
    fn destroy(node: *Node, gpa: Allocator) void {
        switch (node.content) {
            .directory => |*children| {
                for (children.items) |item| item.destroy(gpa);
                children.deinit(gpa);
            },
            .file => |*lines| {
                releaseLines(lines.items, gpa);
                lines.deinit(gpa);
            },
            .link => |target| gpa.free(target),
        }
        gpa.free(node.name);
        gpa.destroy(node);
    }
};
const Failure = enum {
    none, missing, not_directory, loop,
    fn reason(failure: Failure) Text {
        return switch (failure) {
            .none => "",
            .missing => "No such file or directory",
            .not_directory => "Not a directory",
            .loop => "Too many levels of symbolic links",
        };
    }
};
const Resolution = struct {
    node: ?*Node = null,
    failure: Failure = .none,
    parent: ?*Node = null,
    name: Text = "",
    fn absent(result: Resolution) bool { return result.parent != null; }
};
const Options = struct {
    flags: [26]bool = @splat(false),
    args: []const Text,
    fn has(opts: Options, flag: u8) bool { return opts.flags[flag - 'a']; }
};
fn options(args: []const Text) Options {
    var result: Options = .{ .args = args };
    var at: usize = 0;
    while (at < args.len and args[at][0] == '-') : (at += 1) {
        for (args[at][1..]) |flag| result.flags[flag - 'a'] = true;
    }
    result.args = args[at..];
    return result;
}
fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn lastComponent(path: Text) Text {
    const at = std.mem.findLast(u8, path, "/") orelse return path;
    return path[at + 1 ..];
}
fn invalidSource(path: Text) bool {
    const name = lastComponent(path);
    return name.len == 0 or equal(name, ".") or equal(name, "..");
}
fn descendant(node: *Node, ancestor: *Node) bool {
    var current = node;
    while (true) {
        if (current == ancestor) return true;
        if (current.parent == current) return false;
        current = current.parent;
    }
}
fn joined(gpa: Allocator, path: Text, name: Text) Allocator.Error!Text {
    return if (equal(path, "/")) std.fmt.allocPrint(gpa, "/{s}", .{name})
        else std.fmt.allocPrint(gpa, "{s}/{s}", .{ path, name });
}
const Output = struct {
    shell: *Shell,
    lines: ?*Lines = null,

    fn text(output: Output, value: Text) Error!void {
        if (output.lines) |lines| {
            const owned = try Line.create(output.shell.gpa, value);
            errdefer owned.release(output.shell.gpa);
            try lines.append(output.shell.scratch, owned);
        } else {
            try output.shell.terminal.writeAll(value);
            try output.shell.terminal.writeByte('\n');
        }
    }
    fn line(output: Output, value: *Line) Error!void {
        if (output.lines) |lines| {
            try lines.append(output.shell.scratch, value);
            value.references += 1;
        } else {
            try output.text(value.text);
        }
    }
    fn print(output: Output, comptime format: Text, args: anytype) Error!void {
        try output.text(try std.fmt.allocPrint(output.shell.scratch, format, args));
    }
};

const Shell = struct {
    gpa: Allocator,
    scratch: Allocator = undefined,
    terminal: *Writer,
    root: *Node,
    current: *Node,
    previous: ?Text = null,
    clock: usize = 0,
    next_inode: usize = 2,
    garbage: Nodes = .empty,

    fn init(gpa: Allocator, terminal: *Writer) Allocator.Error!Shell {
        const root = try gpa.create(Node);
        root.* = .{ .inode = 1, .modified = 0, .parent = root, .content = .{ .directory = .empty } };
        return .{ .gpa = gpa, .terminal = terminal, .root = root, .current = root };
    }
    fn deinit(shell: *Shell) void {
        shell.root.destroy(shell.gpa);
        if (shell.previous) |path| shell.gpa.free(path);
    }
    fn say(shell: *Shell, comptime format: Text, args: anytype) Error!void {
        try (Output{ .shell = shell }).print(format, args);
    }
    fn absolute(shell: *Shell, node: *Node) Error!Text {
        var parts: std.ArrayList(Text) = .empty;
        var current = node;
        while (current != shell.root) : (current = current.parent) try parts.append(shell.scratch, current.name);
        var result: Writer.Allocating = .init(shell.scratch);
        for (0..parts.items.len) |i| try result.writer.print("/{s}", .{parts.items[parts.items.len - 1 - i]});
        if (parts.items.len == 0) try result.writer.writeByte('/');
        return try result.toOwnedSlice();
    }
    fn add(shell: *Shell, parent: *Node, name: Text, node: *Node) Allocator.Error!void {
        const copied_name = try shell.gpa.dupe(u8, name);
        errdefer shell.gpa.free(copied_name);
        var at: usize = 0;
        while (at < parent.content.directory.items.len and
            std.mem.order(u8, parent.content.directory.items[at].name, name) == .lt) : (at += 1) {}
        try parent.content.directory.insert(shell.gpa, at, node);
        shell.gpa.free(node.name);
        node.name = copied_name;
        node.parent = parent;
        parent.modified = shell.clock;
    }
    fn create(shell: *Shell, parent: *Node, name: Text, content: Content) Allocator.Error!*Node {
        const node = try shell.gpa.create(Node);
        node.* = .{ .inode = shell.next_inode, .modified = shell.clock, .parent = parent, .content = content };
        shell.next_inode += 1;
        try shell.add(parent, name, node);
        return node;
    }
    fn detach(shell: *Shell, node: *Node) void {
        const parent = node.parent;
        for (parent.content.directory.items, 0..) |child, i| {
            if (child == node) {
                _ = parent.content.directory.orderedRemove(i);
                break;
            }
        }
        parent.modified = shell.clock;
    }
    fn remove(shell: *Shell, node: *Node) Allocator.Error!void {
        try shell.garbage.append(shell.scratch, node);
        shell.detach(node);
    }
    fn writeFile(shell: *Shell, file: *Node, items: []const *Line, append: bool) Allocator.Error!void {
        const lines = &file.content.file;
        if (!append) {
            releaseLines(lines.items, shell.gpa);
            lines.clearRetainingCapacity();
        }
        for (items) |item| {
            try lines.append(shell.gpa, item);
            item.references += 1;
        }
        file.modified = shell.clock;
    }
    fn clone(shell: *Shell, source: *Node, parent: *Node, name: Text) Error!void {
        switch (source.content) {
            .file => |lines| {
                const file = try shell.create(parent, name, .{ .file = .empty });
                try shell.writeFile(file, lines.items, false);
            },
            .link => |target| { _ = try shell.create(parent, name, .{ .link = try shell.gpa.dupe(u8, target) }); },
            .directory => |children| {
                const directory = try shell.create(parent, name, .{ .directory = .empty });
                for (children.items) |child| try shell.clone(child, directory, child.name);
            },
        }
    }
    fn resolve(shell: *Shell, path: Text, follow: bool, parents: bool) Allocator.Error!Resolution {
        var expansions: usize = 0;
        return shell.resolveFrom(path, shell.current, follow, parents, true, &expansions);
    }
    fn resolveFrom(shell: *Shell, path: Text, base: *Node, follow: bool, parents: bool,
        original: bool, expansions: *usize) Allocator.Error!Resolution {
        var node = if (path[0] == '/') shell.root else base;
        var parts = std.mem.tokenizeScalar(u8, path, '/');
        while (parts.next()) |part| {
            if (node.kind() != .directory) return .{ .failure = .not_directory };
            if (equal(part, ".")) continue;
            if (equal(part, "..")) { node = node.parent; continue; }
            const last = parts.peek() == null;
            const child = node.child(part) orelse blk: {
                if (original and last) return .{ .failure = .missing, .parent = node, .name = part };
                if (!original or !parents) return .{ .failure = .missing };
                break :blk try shell.create(node, part, .{ .directory = .empty });
            };
            if (child.kind() == .link and (!last or follow)) {
                expansions.* += 1;
                if (expansions.* > 8) return .{ .failure = .loop };
                const result = try shell.resolveFrom(child.content.link, node, true, false, false, expansions);
                node = result.node orelse return result;
            } else node = child;
        }
        return .{ .node = node };
    }
    fn move(shell: *Shell, source_path: Text, destination: Text) Error!void {
        if (invalidSource(source_path)) return shell.say("mv: cannot move '{s}' to '{s}': Invalid argument", .{ source_path, destination });
        const source_result = try shell.resolve(source_path, false, false);
        const source = source_result.node orelse return shell.say("mv: cannot stat '{s}': {s}", .{ source_path, source_result.failure.reason() });
        var parent: *Node = undefined;
        var name: Text = undefined;
        var display = destination;
        const destination_result = try shell.resolve(destination, true, false);
        if (destination_result.node != null and destination_result.node.?.kind() == .directory) {
            parent = destination_result.node.?;
            name = lastComponent(source_path);
            display = try joined(shell.scratch, destination, name);
        } else {
            const result = try shell.resolve(destination, false, false);
            if (result.absent()) {
                parent = result.parent.?;
                name = result.name;
            } else if (result.node) |node| {
                parent = node.parent;
                name = node.name;
            } else return shell.say("mv: cannot move '{s}' to '{s}': {s}", .{ source_path, destination, result.failure.reason() });
        }
        const existing = parent.child(name);
        if (source.kind() == .directory and descendant(parent, source))
            return shell.say("mv: cannot move '{s}' to a subdirectory of itself, '{s}'", .{ source_path, display });
        if (existing == source) return shell.say("mv: '{s}' and '{s}' are the same file", .{ source_path, display });
        if (existing) |node| {
            if (source.kind() == .directory and node.kind() != .directory)
                return shell.say("mv: cannot overwrite non-directory '{s}' with directory '{s}'", .{ display, source_path });
            if (source.kind() != .directory and node.kind() == .directory)
                return shell.say("mv: cannot overwrite directory '{s}' with non-directory '{s}'", .{ display, source_path });
            if (node.kind() == .directory and node.content.directory.items.len != 0)
                return shell.say("mv: cannot move '{s}' to '{s}': Directory not empty", .{ source_path, display });
            if (node == shell.current)
                return shell.say("mv: cannot move '{s}' to '{s}': Device or resource busy", .{ source_path, display });
            try shell.remove(node);
        }
        shell.detach(source);
        try shell.add(parent, name, source);
    }
    fn copy(shell: *Shell, source_path: Text, destination: Text, recursive: bool) Error!void {
        if (invalidSource(source_path)) return shell.say("cp: cannot copy '{s}' to '{s}': Invalid argument", .{ source_path, destination });
        const source_result = try shell.resolve(source_path, true, false);
        const source = source_result.node orelse return shell.say("cp: cannot stat '{s}': {s}", .{ source_path, source_result.failure.reason() });
        if (source.kind() == .directory and !recursive) return shell.say("cp: -r not specified; omitting directory '{s}'", .{source_path});
        const destination_result = try shell.resolve(destination, true, false);
        if (destination_result.node == null and !destination_result.absent())
            return shell.say("cp: cannot copy '{s}' to '{s}': {s}", .{ source_path, destination, destination_result.failure.reason() });
        const display = if (destination_result.node != null and destination_result.node.?.kind() == .directory)
            try joined(shell.scratch, destination, lastComponent(source_path)) else destination;
        const target = try shell.resolve(display, source.kind() != .directory, false);
        if (source.kind() == .directory) {
            if (target.node != null) return shell.say("cp: cannot copy '{s}' to '{s}': File exists", .{ source_path, display });
            if (descendant(target.parent.?, source)) return shell.say("cp: cannot copy a directory, '{s}', into itself, '{s}'", .{ source_path, display });
            try shell.clone(source, target.parent.?, target.name);
        } else if (target.absent()) {
            try shell.clone(source, target.parent.?, target.name);
        } else if (target.node) |node| {
            if (node == source) return shell.say("cp: '{s}' and '{s}' are the same file", .{ source_path, display });
            if (node.kind() == .directory) return shell.say("cp: cannot overwrite directory '{s}' with non-directory '{s}'", .{ display, source_path });
            try shell.writeFile(node, source.content.file.items, false);
        } else try shell.say("cp: cannot copy '{s}' to '{s}': {s}", .{ source_path, display, target.failure.reason() });
    }

    fn list(shell: *Shell, args: []const Text, output: Output) Error!void {
        const opts = options(args);
        const paths = if (opts.args.len == 0) &[_]Text{"."} else opts.args;
        const Entry = struct {
            name: Text,
            node: *Node,
            fn newer(_: void, a: @This(), b: @This()) bool { return a.node.modified > b.node.modified; }
        };
        for (paths) |path| {
            const result = try shell.resolve(path, !opts.has('l'), false);
            const node = result.node orelse {
                try shell.say("ls: cannot access '{s}': {s}", .{ path, result.failure.reason() });
                continue;
            };
            var entries: std.ArrayList(Entry) = .empty;
            if (node.kind() == .directory) {
                if (paths.len >= 2) try output.print("{s}:", .{path});
                if (opts.has('a')) {
                    try entries.append(shell.scratch, .{ .name = ".", .node = node });
                    try entries.append(shell.scratch, .{ .name = "..", .node = node.parent });
                }
                for (node.content.directory.items) |child| {
                    if (opts.has('a') or child.name[0] != '.')
                        try entries.append(shell.scratch, .{ .name = child.name, .node = child });
                }
            } else try entries.append(shell.scratch, .{ .name = path, .node = node });
            if (opts.has('t')) std.sort.insertion(Entry, entries.items, {}, Entry.newer);
            var widths: [3]usize = @splat(0);
            for (entries.items) |entry| {
                const numbers = [3]u64{ entry.node.links(), entry.node.size(), entry.node.modified };
                for (numbers, 0..) |value, i| widths[i] = @max(widths[i], digits(value));
            }
            for (0..entries.items.len) |index| {
                const entry = entries.items[if (opts.has('r')) entries.items.len - 1 - index else index];
                if (!opts.has('l')) {
                    try output.text(entry.name);
                    continue;
                }
                var row: Writer.Allocating = .init(shell.scratch);
                try row.writer.print("{c}", .{entry.node.tag()});
                const numbers = [3]u64{ entry.node.links(), entry.node.size(), entry.node.modified };
                for (numbers, 0..) |value, i| {
                    try row.writer.splatByteAll(' ', widths[i] - digits(value) + 1);
                    try row.writer.print("{d}", .{value});
                }
                try row.writer.print(" {s}", .{entry.name});
                if (entry.node.kind() == .link) try row.writer.print(" -> {s}", .{entry.node.content.link});
                try output.text(row.written());
            }
        }
    }
    fn find(shell: *Shell, args: []const Text, output: Output) Error!void {
        var at: usize = 0;
        const path = if (args.len != 0 and args[0][0] != '-') blk: {
            at = 1;
            break :blk args[0];
        } else ".";
        var filter: Find = .{};
        while (at < args.len) : (at += 2) {
            if (equal(args[at], "-name")) filter.pattern = args[at + 1]
            else if (equal(args[at], "-type")) filter.kind = args[at + 1][0]
            else filter.depth = std.fmt.parseInt(usize, args[at + 1], 10) catch unreachable;
        }
        const result = try shell.resolve(path, true, false);
        const node = result.node orelse return shell.say("find: '{s}': {s}", .{ path, result.failure.reason() });
        try shell.findNode(node, path, if (equal(path, "/")) "/" else lastComponent(path), 0, filter, output);
    }
    fn findNode(shell: *Shell, node: *Node, path: Text, name: Text, depth: usize, filter: Find, output: Output) Error!void {
        const tag: u8 = if (node.kind() == .file) 'f' else node.tag();
        const matched = if (filter.pattern) |pattern| globMatch(pattern, name) else true;
        if (matched and (filter.kind == null or filter.kind.? == tag)) try output.text(path);
        if (node.kind() == .directory and (filter.depth == null or depth < filter.depth.?)) {
            for (node.content.directory.items) |child|
                try shell.findNode(child, try joined(shell.scratch, path, child.name), child.name, depth + 1, filter, output);
        }
    }
    fn diskUsage(shell: *Shell, args: []const Text, output: Output) Error!void {
        const opts = options(args);
        const paths = if (opts.args.len == 0) &[_]Text{"."} else opts.args;
        for (paths) |path| {
            const result = try shell.resolve(path, true, false);
            const node = result.node orelse {
                try shell.say("du: cannot access '{s}': {s}", .{ path, result.failure.reason() });
                continue;
            };
            _ = try shell.usage(node, path, opts, true, output);
        }
    }
    fn usage(shell: *Shell, node: *Node, path: Text, opts: Options, show: bool, output: Output) Error!u64 {
        var total: u64 = if (node.kind() == .directory) 0 else node.size();
        if (node.kind() == .directory) {
            for (node.content.directory.items) |child| {
                total += try shell.usage(child, try joined(shell.scratch, path, child.name), opts,
                    !opts.has('s') and (child.kind() == .directory or opts.has('a')), output);
            }
        }
        if (show) try output.print("{d} {s}", .{ total, path });
        return total;
    }
    fn tree(shell: *Shell, args: []const Text, output: Output) Error!void {
        const opts = options(args);
        const path = if (opts.args.len == 0) "." else opts.args[0];
        const result = try shell.resolve(path, true, false);
        const node = result.node orelse return shell.say("tree: {s}: {s}", .{ path, result.failure.reason() });
        if (node.kind() != .directory) return shell.say("tree: {s}: Not a directory", .{path});
        try output.text(path);
        var counts = [2]usize{ 0, 0 };
        try shell.draw(node, "", opts.has('a'), &counts, output);
        try output.print("{d} {s}, {d} {s}", .{
            counts[0], if (counts[0] == 1) @as(Text, "directory") else "directories",
            counts[1], if (counts[1] == 1) @as(Text, "file") else "files",
        });
    }
    fn draw(shell: *Shell, directory: *Node, prefix: Text, hidden: bool, counts: *[2]usize, output: Output) Error!void {
        var children: Nodes = .empty;
        for (directory.content.directory.items) |child| {
            if (hidden or child.name[0] != '.') try children.append(shell.scratch, child);
        }
        for (children.items, 0..) |child, i| {
            const last = i + 1 == children.items.len;
            const branch: Text = if (last) "`-- " else "|-- ";
            const suffix = if (child.kind() == .link) try std.fmt.allocPrint(shell.scratch, " -> {s}", .{child.content.link}) else "";
            try output.print("{s}{s}{s}{s}", .{ prefix, branch, child.name, suffix });
            if (child.kind() == .directory) {
                counts[0] += 1;
                try shell.draw(child, try std.fmt.allocPrint(shell.scratch, "{s}{s}", .{ prefix, if (last) @as(Text, "    ") else "|   " }), hidden, counts, output);
            } else counts[1] += 1;
        }
    }
    fn wordCount(shell: *Shell, args: []const Text, input: []const *Line, output: Output) Error!void {
        var opts = options(args);
        if (!opts.has('l') and !opts.has('w') and !opts.has('c')) {
            for ("lwc") |flag| opts.flags[flag - 'a'] = true;
        }
        var reader: Inputs = .{ .shell = shell, .command = "wc", .paths = opts.args, .input = input };
        var totals: [3]u64 = @splat(0);
        while (try reader.next()) |part| {
            var counts = [3]u64{ part.lines.len, 0, 0 };
            for (part.lines) |line| {
                var inside = false;
                for (line.text) |character| {
                    if (character != ' ' and !inside) counts[1] += 1;
                    inside = character != ' ';
                }
                counts[2] += line.text.len + 1;
            }
            for (&totals, counts) |*total, count| total.* += count;
            try shell.countReport(counts, opts, part.name, output);
        }
        if (opts.args.len >= 2) try shell.countReport(totals, opts, "total", output);
    }
    fn countReport(shell: *Shell, counts: [3]u64, opts: Options, name: ?Text, output: Output) Error!void {
        var row: Writer.Allocating = .init(shell.scratch);
        for (counts, "lwc") |count, flag| {
            if (opts.has(flag)) {
                if (row.written().len != 0) try row.writer.writeByte(' ');
                try row.writer.print("{d}", .{count});
            }
        }
        if (name) |path| try row.writer.print(" {s}", .{path});
        try output.text(row.written());
    }
    fn ends(shell: *Shell, verb: Verb, args: []const Text, input: []const *Line, output: Output) Error!void {
        const explicit = args.len != 0 and equal(args[0], "-n");
        const count: Text = if (explicit) args[1] else "10";
        const special = count[0] == '-' or count[0] == '+';
        const amount = std.fmt.parseInt(usize, if (special) count[1..] else count, 10) catch unreachable;
        var reader: Inputs = .{ .shell = shell, .command = @tagName(verb), .paths = args[(if (explicit) @as(usize, 2) else 0)..], .input = input };
        while (try reader.next()) |part| {
            var first: usize = 0;
            var end = part.lines.len;
            if (verb == .head) {
                end = if (special) end -| amount else @min(end, amount);
            } else first = if (special) @min(end, amount -| 1) else end -| amount;
            for (part.lines[first..end]) |line| try output.line(line);
        }
    }
    fn grep(shell: *Shell, args: []const Text, input: []const *Line, output: Output) Error!void {
        const opts = options(args);
        const paths = opts.args[1..];
        const filter: Grep = .{ .options = opts, .pattern = opts.args[0], .prefix = opts.has('r') or paths.len >= 2 };
        if (!opts.has('r')) {
            var reader: Inputs = .{ .shell = shell, .command = "grep", .paths = paths, .input = input };
            while (try reader.next()) |part| try filter.consume(part, output);
        } else {
            for (if (paths.len == 0) &[_]Text{"."} else paths) |path| {
                const result = try shell.resolve(path, true, false);
                const node = result.node orelse {
                    try shell.say("grep: {s}: {s}", .{ path, result.failure.reason() });
                    continue;
                };
                try shell.grepNode(node, path, filter, output);
            }
        }
    }
    fn grepNode(shell: *Shell, node: *Node, path: Text, filter: Grep, output: Output) Error!void {
        switch (node.content) {
            .file => |lines| try filter.consume(.{ .lines = lines.items, .name = path }, output),
            .directory => |children| for (children.items) |child|
                try shell.grepNode(child, try joined(shell.scratch, path, child.name), filter, output),
            .link => {},
        }
    }
    fn sortLines(shell: *Shell, args: []const Text, input: []const *Line, output: Output) Error!void {
        const opts = options(args);
        var reader: Inputs = .{ .shell = shell, .command = "sort", .paths = opts.args, .input = input };
        var lines: Lines = .empty;
        while (try reader.next()) |part| try lines.appendSlice(shell.scratch, part.lines);
        std.sort.heap(*Line, lines.items, opts.has('n'), struct {
            fn less(numeric: bool, a: *Line, b: *Line) bool {
                if (numeric) {
                    const x = numericPrefix(a.text);
                    const y = numericPrefix(b.text);
                    if (x != y) return x < y;
                }
                return std.mem.order(u8, a.text, b.text) == .lt;
            }
        }.less);
        for (0..lines.items.len) |i| try output.line(lines.items[if (opts.has('r')) lines.items.len - 1 - i else i]);
    }
    fn unique(shell: *Shell, args: []const Text, input: []const *Line, output: Output) Error!void {
        const opts = options(args);
        var reader: Inputs = .{ .shell = shell, .command = "uniq", .paths = opts.args, .input = input };
        while (try reader.next()) |part| {
            var first: usize = 0;
            while (first < part.lines.len) {
                var end = first + 1;
                while (end < part.lines.len and equal(part.lines[first].text, part.lines[end].text)) : (end += 1) {}
                if (opts.has('c')) try output.print("{d} {s}", .{ end - first, part.lines[first].text })
                else try output.line(part.lines[first]);
                first = end;
            }
        }
    }

    fn execute(shell: *Shell, text: Text, input: []const *Line, output: Output) Error!void {
        var words: std.ArrayList(Text) = .empty;
        var tokens = std.mem.tokenizeScalar(u8, text, ' ');
        while (tokens.next()) |word| try words.append(shell.scratch, word);
        const verb = std.meta.stringToEnum(Verb, words.items[0]) orelse
            return shell.say("{s}: command not found", .{words.items[0]});
        const args = words.items[1..];
        switch (verb) {
            .pwd => try output.text(try shell.absolute(shell.current)),
            .echo => try output.text(text[5..]),
            .cd => {
                const back = args.len != 0 and equal(args[0], "-");
                if (back and shell.previous == null) return shell.say("cd: OLDPWD not set", .{});
                const path = if (back) shell.previous.? else if (args.len == 0) "/" else args[0];
                const result = try shell.resolve(path, true, false);
                const node = result.node orelse return shell.say("cd: {s}: {s}", .{ path, result.failure.reason() });
                if (node.kind() != .directory) return shell.say("cd: {s}: Not a directory", .{path});
                const previous = try shell.gpa.dupe(u8, try shell.absolute(shell.current));
                if (shell.previous) |old| shell.gpa.free(old);
                shell.previous = previous;
                shell.current = node;
                if (back) try output.text(try shell.absolute(node));
            },
            .mkdir => {
                const opts = options(args);
                for (opts.args) |path| {
                    const result = try shell.resolve(path, false, opts.has('p'));
                    if (result.absent()) {
                        _ = try shell.create(result.parent.?, result.name, .{ .directory = .empty });
                    } else if (result.node == null) {
                        try shell.say("mkdir: cannot create directory '{s}': {s}", .{ path, result.failure.reason() });
                    } else {
                        if (opts.has('p')) {
                            const followed = try shell.resolve(path, true, false);
                            if (followed.node != null and followed.node.?.kind() == .directory) continue;
                        }
                        try shell.say("mkdir: cannot create directory '{s}': File exists", .{path});
                    }
                }
            },
            .touch => for (args) |path| {
                const result = try shell.resolve(path, true, false);
                if (result.absent()) {
                    _ = try shell.create(result.parent.?, result.name, .{ .file = .empty });
                } else if (result.node) |node| {
                    node.modified = shell.clock;
                } else try shell.say("touch: cannot touch '{s}': {s}", .{ path, result.failure.reason() });
            },
            .cat => {
                var reader: Inputs = .{ .shell = shell, .command = "cat", .paths = args, .input = input };
                while (try reader.next()) |part| for (part.lines) |line| try output.line(line);
            },
            .ls => try shell.list(args, output),
            .stat => for (args) |path| {
                const result = try shell.resolve(path, false, false);
                const node = result.node orelse {
                    try shell.say("stat: cannot stat '{s}': {s}", .{ path, result.failure.reason() });
                    continue;
                };
                const kind: Text = switch (node.content) {
                    .directory => "directory",
                    .link => "symbolic link",
                    .file => |lines| if (lines.items.len == 0) "regular empty file" else "regular file",
                };
                try output.print("{s}: {s}, size {d}, inode {d}, links {d}, modified {d}",
                    .{ path, kind, node.size(), node.inode, node.links(), node.modified });
            },
            .rm, .rmdir => {
                const opts = if (verb == .rm) options(args) else Options{ .args = args };
                for (opts.args) |path| {
                    const last = lastComponent(path);
                    if (equal(last, ".") or equal(last, "..")) {
                        if (verb == .rm) try shell.say("rm: refusing to remove '.' or '..' directory: skipping '{s}'", .{path})
                        else try shell.say("rmdir: failed to remove '{s}': Invalid argument", .{path});
                        continue;
                    }
                    const result = try shell.resolve(path, false, false);
                    var reason: ?Text = null;
                    if (result.node) |node| {
                        if (verb == .rm and node.kind() == .directory and !opts.has('r')) {
                            reason = "Is a directory";
                        } else if (verb == .rmdir and node.kind() != .directory) {
                            reason = "Not a directory";
                        } else if (descendant(shell.current, node)) {
                            reason = "Device or resource busy";
                        } else if (verb == .rmdir and node.content.directory.items.len != 0) {
                            reason = "Directory not empty";
                        }
                        if (reason == null) try shell.remove(node);
                    } else if (!(verb == .rm and opts.has('f') and result.failure == .missing)) {
                        reason = result.failure.reason();
                    }
                    if (reason) |message| {
                        if (verb == .rm) try shell.say("rm: cannot remove '{s}': {s}", .{ path, message })
                        else try shell.say("rmdir: failed to remove '{s}': {s}", .{ path, message });
                    }
                }
            },
            .mv, .cp => {
                const opts = if (verb == .cp) options(args) else Options{ .args = args };
                const destination = opts.args[opts.args.len - 1];
                const sources = opts.args[0 .. opts.args.len - 1];
                if (sources.len >= 2) {
                    const result = try shell.resolve(destination, true, false);
                    if (result.node == null or result.node.?.kind() != .directory)
                        return shell.say("{s}: target '{s}' is not a directory", .{ @tagName(verb), destination });
                }
                for (sources) |source| {
                    if (verb == .mv) try shell.move(source, destination)
                    else try shell.copy(source, destination, opts.has('r'));
                }
            },
            .ln => {
                const target = args[1];
                const path = args[2];
                const result = try shell.resolve(path, false, false);
                if (result.absent()) {
                    _ = try shell.create(result.parent.?, result.name, .{ .link = try shell.gpa.dupe(u8, target) });
                } else try shell.say("ln: failed to create symbolic link '{s}': {s}",
                    .{ path, if (result.node != null) @as(Text, "File exists") else result.failure.reason() });
            },
            .readlink, .realpath => {
                const path = args[0];
                const result = try shell.resolve(path, verb == .realpath, false);
                const node = result.node orelse return shell.say("{s}: {s}: {s}", .{ @tagName(verb), path, result.failure.reason() });
                if (verb == .realpath) try output.text(try shell.absolute(node))
                else if (node.kind() == .link) try output.text(node.content.link)
                else try shell.say("readlink: {s}: Invalid argument", .{path});
            },
            .find => try shell.find(args, output),
            .du => try shell.diskUsage(args, output),
            .tree => try shell.tree(args, output),
            .wc => try shell.wordCount(args, input, output),
            .head, .tail => try shell.ends(verb, args, input, output),
            .grep => try shell.grep(args, input, output),
            .sort => try shell.sortLines(args, input, output),
            .uniq => try shell.unique(args, input, output),
        }
    }
    fn process(shell: *Shell, source: Text, scratch: Allocator) Error!void {
        shell.scratch = scratch;
        shell.garbage = .empty;
        defer for (shell.garbage.items) |node| node.destroy(shell.gpa);
        shell.clock += 1;
        try shell.say("{s}$ {s}", .{ try shell.absolute(shell.current), source });
        var pipeline = source;
        var redirect: ?*Node = null;
        if (std.mem.find(u8, source, " >")) |at| {
            pipeline = source[0..at];
            const append = source[at + 2] == '>';
            const path = source[at + (if (append) @as(usize, 4) else 3) ..];
            const result = try shell.resolve(path, true, false);
            if (result.absent()) {
                redirect = try shell.create(result.parent.?, result.name, .{ .file = .empty });
            } else if (result.node != null and result.node.?.kind() == .file) {
                redirect = result.node;
                if (!append) try shell.writeFile(redirect.?, &.{}, false);
            } else {
                const reason: Text = if (result.node != null) "Is a directory" else result.failure.reason();
                return shell.say("sh: {s}: {s}", .{ path, reason });
            }
        }
        var input: []const *Line = &.{};
        defer releaseLines(input, shell.gpa);
        var commands = std.mem.splitSequence(u8, pipeline, " | ");
        while (commands.next()) |command| {
            var lines: Lines = .empty;
            const output: Output = .{ .shell = shell, .lines = if (commands.peek() == null and redirect == null) null else &lines };
            try shell.execute(command, input, output);
            releaseLines(input, shell.gpa);
            input = lines.items;
        }
        if (redirect != null and input.len != 0) try shell.writeFile(redirect.?, input, true);
    }
};

const Input = struct { lines: []const *Line, name: ?Text = null };
const Inputs = struct {
    shell: *Shell,
    command: Text,
    paths: []const Text,
    input: []const *Line,
    at: usize = 0,

    fn next(inputs: *Inputs) Error!?Input {
        if (inputs.paths.len == 0) {
            if (inputs.at != 0) return null;
            inputs.at = 1;
            return .{ .lines = inputs.input };
        }
        while (inputs.at < inputs.paths.len) {
            const path = inputs.paths[inputs.at];
            inputs.at += 1;
            const result = try inputs.shell.resolve(path, true, false);
            const node = result.node orelse {
                try inputs.shell.say("{s}: {s}: {s}", .{ inputs.command, path, result.failure.reason() });
                continue;
            };
            if (node.kind() == .directory) {
                try inputs.shell.say("{s}: {s}: Is a directory", .{ inputs.command, path });
                continue;
            }
            return .{ .lines = node.content.file.items, .name = path };
        }
        return null;
    }
};
const Find = struct { pattern: ?Text = null, kind: ?u8 = null, depth: ?usize = null };
const Grep = struct {
    options: Options,
    pattern: Text,
    prefix: bool,

    fn consume(filter: Grep, part: Input, output: Output) Error!void {
        const prefix = if (filter.prefix) try std.fmt.allocPrint(output.shell.scratch, "{s}:", .{part.name.?}) else "";
        var selected: usize = 0;
        for (part.lines, 0..) |line, i| {
            if (contains(line.text, filter.pattern, filter.options.has('i')) == filter.options.has('v')) continue;
            selected += 1;
            if (!filter.options.has('c')) {
                if (filter.options.has('n')) try output.print("{s}{d}:{s}", .{ prefix, i + 1, line.text })
                else if (prefix.len != 0) try output.print("{s}{s}", .{ prefix, line.text })
                else try output.line(line);
            }
        }
        if (filter.options.has('c')) try output.print("{s}{d}", .{ prefix, selected });
    }
};
fn digits(value: u64) usize {
    var count: usize = 1;
    var remaining = value;
    while (remaining >= 10) : (remaining /= 10) count += 1;
    return count;
}
fn lower(c: u8) u8 { return if (c >= 'A' and c <= 'Z') c - 'A' + 'a' else c; }
fn contains(text: Text, pattern: Text, ignore_case: bool) bool {
    if (!ignore_case) return std.mem.find(u8, text, pattern) != null;
    if (pattern.len > text.len) return false;
    for (0..text.len - pattern.len + 1) |i| {
        var matched = true;
        for (pattern, text[i .. i + pattern.len]) |a, b| {
            if (lower(a) != lower(b)) { matched = false; break; }
        }
        if (matched) return true;
    }
    return false;
}
fn globMatch(pattern: Text, text: Text) bool {
    var previous: [17]bool = @splat(false);
    previous[0] = true;
    for (pattern) |character| {
        var next: [17]bool = @splat(false);
        next[0] = character == '*' and previous[0];
        for (1..text.len + 1) |i| {
            next[i] = if (character == '*') previous[i] or next[i - 1]
                else previous[i - 1] and (character == '?' or character == text[i - 1]);
        }
        previous = next;
    }
    return previous[text.len];
}
fn numericPrefix(text: Text) i64 {
    var at: usize = if (text.len != 0 and text[0] == '-') 1 else 0;
    const negative = at == 1;
    var value: i64 = 0;
    while (at < text.len and text[at] >= '0' and text[at] <= '9') : (at += 1) value = value * 10 + text[at] - '0';
    return if (negative) -value else value;
}
fn readLine(reader: *std.Io.Reader, gpa: Allocator) !?Text {
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
pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.smp_allocator;
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var shell = try Shell.init(gpa, &output.interface);
    defer shell.deinit();
    while (true) {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const scratch = arena.allocator();
        const source = std.mem.trim(u8, (try readLine(&input.interface, scratch)) orelse break, "\r");
        if (equal(source, "exit")) break;
        try shell.process(source, scratch);
        try output.interface.flush();
    }
}
