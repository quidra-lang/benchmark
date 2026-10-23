const std = @import("std");

const Allocator = std.mem.Allocator;

const Text = []const u8;

const Error = Allocator.Error || error{Invalid};

const Tree = std.StringHashMapUnmanaged(Text);

const References = std.StringHashMapUnmanaged(*Commit);

const Distances = std.AutoHashMapUnmanaged(*Commit, usize);

const CommitSet = std.AutoHashMapUnmanaged(*Commit, void);
var failure: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    failure = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}

const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};

fn split(gpa: Allocator, text: Text, separator: u8, limit: usize) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    for (text, 0..) |c, i| {
        if (c == separator and (limit == 0 or result.items.len + 1 < limit)) {
            try result.append(gpa, text[start..i]);
            start = i + 1;
        }
    }
    try result.append(gpa, text[start..]);
    return result.items;
}

fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (parts, 0..) |part, i| {
        if (i > 0) try out.add(separator);
        try out.add(part);
    }
    return out.result();
}

fn textLess(_: void, a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn keys(gpa: Allocator, map: anytype) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var iterator = map.keyIterator();
    while (iterator.next()) |key| try result.append(gpa, key.*);
    std.mem.sort(Text, result.items, {}, textLess);
    return result.items;
}

fn paths(gpa: Allocator, trees: []const Tree) Allocator.Error![]Text {
    var all: std.StringHashMapUnmanaged(void) = .empty;
    for (trees) |tree| {
        var iterator = tree.keyIterator();
        while (iterator.next()) |key| try all.put(gpa, key.*, {});
    }
    return keys(gpa, all);
}

fn clone(gpa: Allocator, tree: Tree) Allocator.Error!Tree {
    var result: Tree = .empty;
    var iterator = tree.iterator();
    while (iterator.next()) |entry| try result.put(gpa, entry.key_ptr.*, entry.value_ptr.*);
    return result;
}

fn agree(a: Tree, b: Tree, path: Text) bool {
    const left = a.get(path);
    const right = b.get(path);
    if (left == null or right == null) return left == null and right == null;
    return equal(left.?, right.?);
}

fn differences(gpa: Allocator, a: Tree, b: Tree) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    for (try paths(gpa, &.{ a, b })) |path| if (!agree(a, b, path)) {
        try result.append(gpa, path);
    };
    return result.items;
}

fn same(gpa: Allocator, a: Tree, b: Tree) Allocator.Error!bool {
    return (try differences(gpa, a, b)).len == 0;
}

fn matchPath(gpa: Allocator, target: *Tree, source: Tree, path: Text) Allocator.Error!void {
    if (source.get(path)) |text| try target.put(gpa, path, text) else _ = target.remove(path);
}

const Merged = struct {
    files: Tree,
    conflicts: []Text
};

fn threeWay(gpa: Allocator, base: Tree, ours: Tree, theirs: Tree) Allocator.Error!Merged {
    var result: Tree = .empty;
    var conflicts: std.ArrayList(Text) = .empty;
    for (try paths(gpa, &.{ base, ours, theirs })) |path| {
        if (agree(theirs, base, path) or agree(ours, theirs, path)) try matchPath(gpa, &result, ours, path)
        else if (agree(ours, base, path)) try matchPath(gpa, &result, theirs, path)
        else {
            try conflicts.append(gpa, path);
            try matchPath(gpa, &result, ours, path);
        }
    }
    return .{ .files = result, .conflicts = conflicts.items };
}

const Commit = struct {
    id: Text,
    sequence: usize,
    parents: []const *Commit,
    files: Tree,
    message: Text
};

fn parentTree(commit: *Commit) Tree {
    return if (commit.parents.len == 0) .empty else commit.parents[0].files;
}

fn distances(gpa: Allocator, start: *Commit) Allocator.Error!Distances {
    var result: Distances = .empty;
    try result.put(gpa, start, 0);
    var queue: std.ArrayList(*Commit) = .empty;
    try queue.append(gpa, start);
    var at: usize = 0;
    while (at < queue.items.len) : (at += 1) {
        const current = queue.items[at];
        for (current.parents) |parent| {
            if (!result.contains(parent)) {
                try result.put(gpa, parent, result.get(current).? + 1);
                try queue.append(gpa, parent);
            }
        }
    }
    return result;
}

fn ancestor(gpa: Allocator, a: *Commit, b: *Commit) Allocator.Error!bool {
    return (try distances(gpa, b)).contains(a);
}

fn mergeBase(gpa: Allocator, a: *Commit, b: *Commit) Allocator.Error!*Commit {
    const da = try distances(gpa, a);
    const db = try distances(gpa, b);
    var common: CommitSet = .empty;
    var excluded: CommitSet = .empty;
    var distance_iterator = da.keyIterator();
    while (distance_iterator.next()) |c| if (db.contains(c.*)) {
        try common.put(gpa, c.*, {});
    };
    var common_iterator = common.keyIterator();
    while (common_iterator.next()) |c| for (c.*.parents) |parent| {
        try excluded.put(gpa, parent, {});
    };
    var best: ?*Commit = null;
    var best_distance: usize = 0;
    common_iterator = common.keyIterator();
    while (common_iterator.next()) |key| {
        const c = key.*;
        if (excluded.contains(c)) continue;
        const distance = @max(da.get(c).?, db.get(c).?);
        if (best == null or distance < best_distance or (distance == best_distance and c.sequence > best.?.sequence)) {
            best = c;
            best_distance = distance;
        }
    }
    return best.?;
}

fn reachable(gpa: Allocator, roots: []const *Commit) Allocator.Error!CommitSet {
    var result: CommitSet = .empty;
    for (roots) |root| {
        const all = try distances(gpa, root);
        var iterator = all.keyIterator();
        while (iterator.next()) |c| try result.put(gpa, c.*, {});
    }
    return result;
}

fn glob(gpa: Allocator, pattern: Text, path: Text) Allocator.Error!bool {
    var previous = try gpa.alloc(bool, path.len + 1);
    @memset(previous, false);
    previous[0] = true;
    for (pattern) |c| {
        const current = try gpa.alloc(bool, path.len + 1);
        @memset(current, false);
        if (c == '*') current[0] = previous[0];
        for (1..path.len + 1) |j| current[j] = if (c == '*') previous[j] or current[j - 1] else previous[j - 1] and (c == '?' or c == path[j - 1]);
        previous = current;
    }
    return previous[path.len];
}

const Operation = struct {
    kind: Text,
    target: *Commit
};

const StashEntry = struct {
    label: Text,
    base: *Commit,
    files: Tree
};

const Repository = struct {
    gpa: Allocator,
    out: Builder,
    commits: References = .empty,
    branches: References = .empty,
    tags: References = .empty,
    attached: ?Text = "main",
    detached: ?*Commit = null,
    work: Tree = .empty,
    index: Tree = .empty,
    conflicts: Tree = .empty,
    pending: ?Operation = null,
    stash: std.ArrayList(StashEntry) = .empty,
    ignores: std.ArrayList(Text) = .empty,
    created: usize = 0,
    fn init(self: *Repository) Error!void {
        const root = try self.create(&.{}, .empty, "init");
        try self.branches.put(self.gpa, "main", root);
    }
    fn head(self: *const Repository) *Commit {
        return if (self.attached) |branch| self.branches.get(branch).? else self.detached.?;
    }
    fn moveHead(self: *Repository, commit: *Commit) Allocator.Error!void {
        if (self.attached) |branch| try self.branches.put(self.gpa, branch, commit) else self.detached = commit;
    }
    fn create(self: *Repository, parents: []const *Commit, files: Tree, message: Text) Error!*Commit {
        var canonical: Builder = .{ .gpa = self.gpa };
        try canonical.line("commit {d}", .{self.created});
        for (parents) |parent| try canonical.line("parent {s}", .{parent.id});
        for (try keys(self.gpa, files)) |path| try canonical.line("file {s} {s}", .{ path, files.get(path).? });
        try canonical.line("message {s}", .{message});
        var hash: u64 = 0;
        for (canonical.result()) |c| hash = (hash * 131 + c) % 2147483647;
        const commit = try self.gpa.create(Commit);
        commit.* = .{ .id = try std.fmt.allocPrint(self.gpa, "{x:0>8}", .{hash}), .sequence = self.created, .parents = try self.gpa.dupe(*Commit, parents), .files = try clone(self.gpa, files), .message = message };
        self.created += 1;
        try self.commits.put(self.gpa, commit.id, commit);
        return commit;
    }
    fn record(self: *Repository, parents: []const *Commit, files: Tree, message: Text) Error!void {
        const commit = try self.create(parents, files, message);
        try self.moveHead(commit);
        var added: usize = 0;
        var modified: usize = 0;
        var deleted: usize = 0;
        const old = parents[0].files;
        for (try differences(self.gpa, old, files)) |path| {
            if (!old.contains(path)) added += 1 else if (!files.contains(path)) deleted += 1 else modified += 1;
        }
        try self.out.line("[{s} {s}] {s} ({d} added, {d} modified, {d} deleted)", .{ self.attached orelse "detached HEAD", commit.id, message, added, modified, deleted });
    }
    fn revision(self: *const Repository, rev: Text) Error!*Commit {
        const at = std.mem.findScalar(u8, rev, '~');
        const anchor = if (at) |i| rev[0..i] else rev;
        var commit: ?*Commit = if (equal(anchor, "HEAD")) self.head() else self.branches.get(anchor) orelse self.tags.get(anchor) orelse self.commits.get(anchor);
        if (at) |i| {
            const n = std.fmt.parseInt(usize, rev[i + 1 ..], 10) catch unreachable;
            for (0..n) |_| if (commit) |c| {
                commit = if (c.parents.len == 0) null else c.parents[0];
            };
        }
        return commit orelse return bad(self.gpa, "unknown revision '{s}'", .{rev});
    }
    fn summary(self: *const Repository, commit: *Commit) Error!Text {
        const gpa = self.gpa;
        var refs: std.ArrayList(Text) = .empty;
        if (self.head() == commit) try refs.append(gpa, if (self.attached) |branch| try std.fmt.allocPrint(gpa, "HEAD -> {s}", .{branch}) else "HEAD");
        for (try keys(gpa, self.branches)) |name| {
            if ((self.attached == null or !equal(name, self.attached.?)) and self.branches.get(name).? == commit) try refs.append(gpa, name);
        }
        for (try keys(gpa, self.tags)) |name| if (self.tags.get(name).? == commit) {
            try refs.append(gpa, try std.fmt.allocPrint(gpa, "tag: {s}", .{name}));
        };
        const references = if (refs.items.len == 0) "" else try std.fmt.allocPrint(gpa, " ({s})", .{try join(gpa, refs.items, ", ")});
        return std.fmt.allocPrint(gpa, "{s}{s} {s}", .{ commit.id, references, commit.message });
    }
    fn changes(self: *Repository, a: Tree, b: Tree) Error!void {
        const changed = try differences(self.gpa, a, b);
        if (changed.len == 0) {
            try self.out.add("(no changes)\n");
            return;
        }
        for (changed) |path| {
            if (!a.contains(path)) try self.out.line("A {s}: {s}", .{ path, b.get(path).? })
            else if (!b.contains(path)) try self.out.line("D {s}: {s}", .{ path, a.get(path).? })
            else try self.out.line("M {s}: {s} -> {s}", .{ path, a.get(path).?, b.get(path).? });
        }
    }
    fn inProgress(self: *const Repository) Error!void {
        if (self.pending) |pending| return bad(self.gpa, "{s} in progress", .{pending.kind});
    }
    fn uncommitted(self: *const Repository) Error!bool {
        if (!try same(self.gpa, self.index, self.head().files)) return true;
        var iterator = self.index.keyIterator();
        while (iterator.next()) |path| if (!agree(self.index, self.work, path.*)) return true;
        return false;
    }
    fn requireClean(self: *const Repository) Error!void {
        if (try self.uncommitted()) return bad(self.gpa, "uncommitted changes", .{});
    }
    fn overwrite(self: *const Repository, selected: []Text) Error!void {
        std.mem.sort(Text, selected, {}, textLess);
        for (selected) |path| if (!agree(self.index, self.head().files, path) or !agree(self.work, self.head().files, path)) return bad(self.gpa, "local changes to '{s}' would be overwritten", .{path});
    }
    fn switchTree(self: *Repository, files: Tree) Error!void {
        const changed = try differences(self.gpa, self.head().files, files);
        try self.overwrite(changed);
        for (changed) |path| {
            try matchPath(self.gpa, &self.index, files, path);
            try matchPath(self.gpa, &self.work, files, path);
        }
    }
    fn ignored(self: *const Repository, path: Text) Error!bool {
        if (self.index.contains(path) or self.conflicts.contains(path)) return false;
        for (self.ignores.items) |pattern| if (try glob(self.gpa, pattern, path)) return true;
        return false;
    }
    fn apply(self: *Repository, base: Tree, theirs: Tree, kind: Text, target: *Commit, message: Text, parents: []const *Commit, base_commit: ?*Commit) Error!void {
        const gpa = self.gpa;
        const merged = try threeWay(gpa, base, self.head().files, theirs);
        const changed = try differences(gpa, self.head().files, merged.files);
        var selected: std.ArrayList(Text) = .empty;
        try selected.appendSlice(gpa, changed);
        try selected.appendSlice(gpa, merged.conflicts);
        try self.overwrite(selected.items);
        if (equal(kind, "merge")) try self.out.line("Merge base {s}", .{base_commit.?.id});
        if (!equal(kind, "merge") and merged.conflicts.len == 0 and try same(gpa, merged.files, self.head().files)) {
            try self.out.add("nothing to commit\n");
            return;
        }
        for (changed) |path| {
            try matchPath(gpa, &self.index, merged.files, path);
            try matchPath(gpa, &self.work, merged.files, path);
        }
        if (merged.conflicts.len == 0) {
            try self.record(parents, merged.files, message);
            return;
        }
        self.conflicts = .empty;
        for (merged.conflicts) |path| {
            const content = try std.fmt.allocPrint(gpa, "<<<<<<< {s} ======= {s} >>>>>>>", .{ self.head().files.get(path) orelse "(deleted)", theirs.get(path) orelse "(deleted)" });
            try self.work.put(gpa, path, content);
            try self.conflicts.put(gpa, path, "");
            try self.out.line("CONFLICT {s}", .{path});
        }
        self.pending = .{ .kind = kind, .target = target };
        if (equal(kind, "merge")) try self.out.add("Automatic merge failed; fix conflicts and then commit the result.\n")
        else if (equal(kind, "revert")) try self.out.line("error: could not revert {s}", .{target.id}) else try self.out.line("error: could not apply {s}", .{target.id});
    }
    fn roots(self: *const Repository, extra: bool) Allocator.Error![]*Commit {
        var result: std.ArrayList(*Commit) = .empty;
        try result.append(self.gpa, self.head());
        var iterator = self.branches.valueIterator();
        while (iterator.next()) |commit| try result.append(self.gpa, commit.*);
        iterator = self.tags.valueIterator();
        while (iterator.next()) |commit| try result.append(self.gpa, commit.*);
        if (extra) {
            for (self.stash.items) |entry| try result.append(self.gpa, entry.base);
            if (self.pending) |pending| try result.append(self.gpa, pending.target);
        }
        return result.items;
    }
    fn command(self: *Repository, line: Text) Error!void {
        const gpa = self.gpa;
        const words = try split(gpa, line, ' ', 0);
        const cmd = words[0];
        const h = self.head();
        if (equal(cmd, "WRITE")) {
            const args = try split(gpa, line, ' ', 3);
            try self.work.put(gpa, args[1], args[2]);
        } else if (equal(cmd, "REMOVE")) {
            if (!self.work.contains(words[1])) return bad(gpa, "no such file '{s}'", .{words[1]});
            _ = self.work.remove(words[1]);
        } else if (equal(cmd, "IGNORE")) try self.ignores.append(gpa, words[1])
        else if (equal(cmd, "ADD")) {
            const path = words[1];
            if (equal(path, "ALL")) {
                for (try paths(gpa, &.{ self.work, self.index })) |p| if (!try self.ignored(p)) {
                    try matchPath(gpa, &self.index, self.work, p);
                };
                self.conflicts = .empty;
            } else {
                if (self.work.contains(path) and try self.ignored(path)) return bad(gpa, "path '{s}' is ignored", .{path});
                if (!self.work.contains(path) and !self.index.contains(path) and !self.conflicts.contains(path)) return bad(gpa, "pathspec '{s}' did not match any files", .{path});
                try matchPath(gpa, &self.index, self.work, path);
                _ = self.conflicts.remove(path);
            }
        } else if (equal(cmd, "RM")) {
            const path = words[1];
            if (!self.index.contains(path)) return bad(gpa, "pathspec '{s}' did not match any files", .{path});
            _ = self.index.remove(path);
            _ = self.work.remove(path);
            _ = self.conflicts.remove(path);
        } else if (equal(cmd, "UNSTAGE")) {
            const path = words[1];
            if (!self.index.contains(path) and !h.files.contains(path)) return bad(gpa, "pathspec '{s}' did not match any files", .{path});
            try matchPath(gpa, &self.index, h.files, path);
        } else if (equal(cmd, "RESTORE") or equal(cmd, "CAT")) {
            const path = words[1];
            var files = if (equal(cmd, "CAT")) self.work else self.index;
            if (words.len == 3) {
                files = (try self.revision(words[2])).files;
                if (!files.contains(path)) return bad(gpa, "path '{s}' does not exist in '{s}'", .{ path, words[2] });
            } else if (!files.contains(path)) {
                if (equal(cmd, "CAT")) return bad(gpa, "no such file '{s}'", .{path});
                return bad(gpa, "pathspec '{s}' did not match any files", .{path});
            }
            if (equal(cmd, "CAT")) try self.out.line("{s}", .{files.get(path).?}) else {
                try self.work.put(gpa, path, files.get(path).?);
                if (words.len == 3) {
                    try self.index.put(gpa, path, files.get(path).?);
                    _ = self.conflicts.remove(path);
                }
            }
        } else if (equal(cmd, "COMMIT")) {
            if (self.conflicts.count() > 0) return bad(gpa, "unresolved conflicts", .{});
            const message = (try split(gpa, line, ' ', 2))[1];
            var parents: std.ArrayList(*Commit) = .empty;
            try parents.append(gpa, h);
            if (self.pending != null and equal(self.pending.?.kind, "merge")) try parents.append(gpa, self.pending.?.target)
            else if (try same(gpa, self.index, h.files)) {
                try self.out.add("nothing to commit\n");
                return;
            }
            try self.record(parents.items, self.index, message);
            self.pending = null;
        } else if (equal(cmd, "AMEND")) {
            try self.inProgress();
            if (h.parents.len == 0) return bad(gpa, "cannot amend the root commit", .{});
            try self.record(h.parents, self.index, (try split(gpa, line, ' ', 2))[1]);
        } else if (equal(cmd, "STATUS")) {
            if (self.attached) |branch| try self.out.line("On branch {s}", .{branch}) else try self.out.line("HEAD detached at {s}", .{h.id});
            if (self.pending) |pending| try self.out.line("{s} {s}", .{ if (equal(pending.kind, "merge")) "Merging" else if (equal(pending.kind, "revert")) "Reverting" else "Cherry-picking", pending.target.id });
            var printed = false;
            for (try paths(gpa, &.{ h.files, self.index, self.work, self.conflicts })) |path| {
                if (self.conflicts.contains(path)) {
                    try self.out.line("UU {s}", .{path});
                    printed = true;
                }
                else if (self.index.contains(path)) {
                    const x: u8 = if (!h.files.contains(path)) 'A' else if (!agree(h.files, self.index, path)) 'M' else '.';
                    const y: u8 = if (!self.work.contains(path)) 'D' else if (!agree(self.work, self.index, path)) 'M' else '.';
                    if (x != '.' or y != '.') {
                        try self.out.line("{c}{c} {s}", .{ x, y, path });
                        printed = true;
                    }
                } else {
                    if (h.files.contains(path)) {
                        try self.out.line("D. {s}", .{path});
                        printed = true;
                    }
                    if (self.work.contains(path) and !try self.ignored(path)) {
                        try self.out.line("?? {s}", .{path});
                        printed = true;
                    }
                }
            }
            if (!printed) try self.out.add("nothing to commit, working tree clean\n");
        } else if (equal(cmd, "LS")) {
            const files = if (words.len == 2) (try self.revision(words[1])).files else self.work;
            const selected = try keys(gpa, files);
            if (selected.len == 0) try self.out.add("(empty)\n");
            for (selected) |path| try self.out.line("{s} {s}", .{ path, files.get(path).? });
        } else if (equal(cmd, "DIFF")) {
            if (words.len == 1) {
                var work: Tree = .empty;
                for (try keys(gpa, self.index)) |path| try matchPath(gpa, &work, self.work, path);
                try self.changes(self.index, work);
            } else if (words.len == 2) try self.changes(h.files, self.index)
            else {
                const a = try self.revision(words[1]);
                const b = try self.revision(words[2]);
                try self.changes(a.files, b.files);
            }
        } else if (equal(cmd, "LOG")) {
            const limit = if (words.len == 2) std.fmt.parseInt(usize, words[1], 10) catch unreachable else self.created;
            var c = h;
            var n: usize = 0;
            while (n < limit) : (n += 1) {
                try self.out.line("{s}", .{try self.summary(c)});
                if (c.parents.len == 0) break;
                c = c.parents[0];
            }
        } else if (equal(cmd, "SHOW")) {
            const c = try self.revision(if (words.len == 2) words[1] else "HEAD");
            try self.out.line("commit {s}", .{try self.summary(c)});
            var parent_ids: std.ArrayList(Text) = .empty;
            for (c.parents) |parent| try parent_ids.append(gpa, parent.id);
            try self.out.line("parents: {s}", .{if (parent_ids.items.len == 0) "none" else try join(gpa, parent_ids.items, " ")});
            try self.changes(parentTree(c), c.files);
        } else if (equal(cmd, "BLAME")) {
            const path = words[1];
            const content = h.files.get(path) orelse return bad(gpa, "path '{s}' does not exist in 'HEAD'", .{path});
            var c = h;
            while (c.parents.len > 0 and agree(c.parents[0].files, h.files, path)) c = c.parents[0];
            try self.out.line("{s} ({s}) {s}", .{ c.id, c.message, content });
        } else if (equal(cmd, "BRANCH") or equal(cmd, "TAG")) {
            const refs = if (equal(cmd, "TAG")) &self.tags else &self.branches;
            const label: Text = if (equal(cmd, "TAG")) "tag" else "branch";
            if (equal(words[1], "-d")) {
                const name = words[2];
                const c = refs.get(name) orelse return bad(gpa, "no such {s} '{s}'", .{ label, name });
                if (equal(cmd, "BRANCH")) {
                    if (self.attached != null and equal(self.attached.?, name)) return bad(gpa, "cannot delete current branch '{s}'", .{name});
                    if (!try ancestor(gpa, c, h)) return bad(gpa, "branch '{s}' is not fully merged", .{name});
                }
                _ = refs.remove(name);
                try self.out.line("Deleted {s} {s} (was {s})", .{ label, name, c.id });
            } else {
                const name = words[1];
                if (refs.contains(name)) return bad(gpa, "{s} '{s}' already exists", .{ label, name });
                const c = try self.revision(if (words.len == 3) words[2] else "HEAD");
                try refs.put(gpa, name, c);
                try self.out.line("Created {s} {s} at {s}", .{ label, name, c.id });
            }
        } else if (equal(cmd, "BRANCHES")) {
            if (self.attached == null) try self.out.line("* (HEAD detached at {s})", .{h.id});
            for (try keys(gpa, self.branches)) |name| {
                const c = self.branches.get(name).?;
                try self.out.line("{s} {s} {s} {s}", .{ if (self.attached != null and equal(name, self.attached.?)) "*" else " ", name, c.id, c.message });
            }
        } else if (equal(cmd, "TAGS")) {
            const names = try keys(gpa, self.tags);
            if (names.len == 0) try self.out.add("(no tags)\n");
            for (names) |name| {
                const c = self.tags.get(name).?;
                try self.out.line("{s} {s} {s}", .{ name, c.id, c.message });
            }
        } else if (equal(cmd, "SWITCH")) {
            const name = words[1];
            const c = self.branches.get(name) orelse return bad(gpa, "no such branch '{s}'", .{name});
            if (self.attached != null and equal(name, self.attached.?)) {
                try self.out.line("Already on '{s}'", .{name});
                return;
            }
            try self.inProgress();
            try self.switchTree(c.files);
            self.attached = name;
            self.detached = null;
            try self.out.line("Switched to branch '{s}'", .{name});
        } else if (equal(cmd, "DETACH")) {
            const c = try self.revision(words[1]);
            try self.inProgress();
            try self.switchTree(c.files);
            self.attached = null;
            self.detached = c;
            try self.out.line("HEAD is now at {s} {s}", .{ c.id, c.message });
        } else if (equal(cmd, "MERGEBASE")) {
            const a = try self.revision(words[1]);
            const b = try self.revision(words[2]);
            try self.out.line("{s}", .{(try mergeBase(gpa, a, b)).id});
        } else if (equal(cmd, "MERGE") or equal(cmd, "REVERT") or equal(cmd, "CHERRYPICK")) {
            const c = try self.revision(words[1]);
            try self.inProgress();
            if (equal(cmd, "MERGE")) {
                if (try ancestor(gpa, c, h)) {
                    try self.out.add("Already up to date\n");
                    return;
                }
                if (try ancestor(gpa, h, c)) {
                    try self.switchTree(c.files);
                    try self.moveHead(c);
                    try self.out.line("Fast-forward {s}..{s}", .{ h.id, c.id });
                    return;
                }
            }
            try self.requireClean();
            if (equal(cmd, "MERGE")) {
                const base = try mergeBase(gpa, h, c);
                try self.apply(base.files, c.files, "merge", c, try std.fmt.allocPrint(gpa, "Merge {s}", .{words[1]}), &.{ h, c }, base);
            }
            else if (equal(cmd, "REVERT")) try self.apply(c.files, parentTree(c), "revert", c, try std.fmt.allocPrint(gpa, "Revert \"{s}\"", .{c.message}), &.{h}, null)
            else try self.apply(parentTree(c), c.files, "cherry-pick", c, c.message, &.{h}, null);
        } else if (equal(cmd, "REBASE")) {
            const upstream = try self.revision(words[1]);
            try self.inProgress();
            if (try ancestor(gpa, upstream, h)) {
                try self.out.add("Already up to date\n");
                return;
            }
            try self.requireClean();
            var list: std.ArrayList(*Commit) = .empty;
            var c = h;
            while (!try ancestor(gpa, c, upstream)) {
                try list.append(gpa, c);
                c = c.parents[0];
            }
            std.mem.reverse(*Commit, list.items);
            var current = upstream.files;
            var picks: std.ArrayList(?Tree) = .empty;
            for (list.items) |old| {
                const merged = try threeWay(gpa, parentTree(old), current, old.files);
                if (merged.conflicts.len > 0) return bad(gpa, "could not rebase {s}: conflict in '{s}'", .{ old.id, merged.conflicts[0] });
                if (try same(gpa, merged.files, current)) try picks.append(gpa, null) else {
                    try picks.append(gpa, merged.files);
                    current = merged.files;
                }
            }
            try self.switchTree(current);
            var tip = upstream;
            for (list.items, picks.items) |old, picked| {
                if (picked) |files| {
                    const next = try self.create(&.{tip}, files, old.message);
                    try self.out.line("pick {s} -> {s} {s}", .{ old.id, next.id, old.message });
                    tip = next;
                }
                else try self.out.line("skip {s} {s}", .{ old.id, old.message });
            }
            try self.moveHead(tip);
            try self.out.line("HEAD is now at {s} {s}", .{ tip.id, tip.message });
        } else if (equal(cmd, "RESET")) {
            const c = try self.revision(words[2]);
            if (equal(words[1], "HARD")) {
                for (try paths(gpa, &.{ self.index, c.files, self.conflicts })) |path| try matchPath(gpa, &self.work, c.files, path);
            }
            if (!equal(words[1], "SOFT")) self.index = try clone(gpa, c.files);
            try self.moveHead(c);
            self.conflicts = .empty;
            self.pending = null;
            try self.out.line("HEAD is now at {s} {s}", .{ c.id, c.message });
        } else if (equal(cmd, "STASH")) {
            const action: Text = if (words.len > 1) words[1] else "";
            if (equal(action, "LIST")) {
                if (self.stash.items.len == 0) try self.out.add("(no stash entries)\n");
                for (self.stash.items, 0..) |entry, i| try self.out.line("stash@{{{d}}}: {s}", .{ i, entry.label });
                return;
            }
            if (action.len > 0 and self.stash.items.len == 0) return bad(gpa, "no stash entries", .{});
            if (equal(action, "DROP")) {
                const entry = self.stash.orderedRemove(0);
                try self.out.line("Dropped stash@{{0}}: {s}", .{entry.label});
                return;
            }
            try self.inProgress();
            if (equal(action, "POP")) {
                try self.requireClean();
                const entry = self.stash.items[0];
                const merged = try threeWay(gpa, entry.base.files, h.files, entry.files);
                if (merged.conflicts.len > 0) return bad(gpa, "stash conflict in '{s}'", .{merged.conflicts[0]});
                const changed = try differences(gpa, h.files, merged.files);
                try self.overwrite(changed);
                for (changed) |path| try matchPath(gpa, &self.work, merged.files, path);
                _ = self.stash.orderedRemove(0);
                try self.out.line("Restored stash@{{0}}: {s}", .{entry.label});
                try self.changes(h.files, merged.files);
            } else {
                if (!try self.uncommitted()) {
                    try self.out.add("No local changes to save\n");
                    return;
                }
                var saved: Tree = .empty;
                for (try paths(gpa, &.{ self.index, h.files })) |path| {
                    try matchPath(gpa, &saved, self.work, path);
                    try matchPath(gpa, &self.work, h.files, path);
                }
                self.index = try clone(gpa, h.files);
                const label = try std.fmt.allocPrint(gpa, "WIP on {s}: {s} {s}", .{ self.attached orelse "(no branch)", h.id, h.message });
                try self.stash.insert(gpa, 0, .{ .label = label, .base = h, .files = saved });
                try self.out.line("Saved stash@{{0}}: {s}", .{label});
            }
        } else if (equal(cmd, "GRAPH")) {
            const all = try reachable(gpa, try self.roots(false));
            var ordered: std.ArrayList(*Commit) = .empty;
            var iterator = all.keyIterator();
            while (iterator.next()) |c| try ordered.append(gpa, c.*);
            std.mem.sort(*Commit, ordered.items, {}, commitLater);
            var lanes: std.ArrayList(*Commit) = .empty;
            for (ordered.items) |c| {
                var at = std.mem.findScalar(*Commit, lanes.items, c);
                if (at == null) {
                    at = lanes.items.len;
                    try lanes.append(gpa, c);
                }
                const position = at.?;
                var symbols: std.ArrayList(Text) = .empty;
                var kept: std.ArrayList(*Commit) = .empty;
                for (lanes.items, 0..) |held, i| {
                    try symbols.append(gpa, if (held == c) (if (i == position) @as(Text, "*") else "/") else "|");
                    if (held != c or i == position) try kept.append(gpa, held);
                }
                try self.out.line("{s} {s}", .{ try join(gpa, symbols.items, " "), try self.summary(c) });
                lanes = kept;
                if (c.parents.len == 0) _ = lanes.orderedRemove(position) else {
                    lanes.items[position] = c.parents[0];
                    if (c.parents.len == 2 and std.mem.findScalar(*Commit, lanes.items, c.parents[1]) == null) try lanes.insert(gpa, position + 1, c.parents[1]);
                }
            }
        } else if (equal(cmd, "DESCRIBE")) {
            const c = try self.revision(if (words.len == 2) words[1] else "HEAD");
            const d = try distances(gpa, c);
            var best: ?Text = null;
            var distance: usize = 0;
            for (try keys(gpa, self.tags)) |name| {
                if (d.get(self.tags.get(name).?)) |n| {
                    if (best == null or n < distance) {
                        best = name;
                        distance = n;
                    }
                }
            }
            const name = best orelse return bad(gpa, "no tag can describe '{s}'", .{c.id});
            if (distance == 0) try self.out.line("{s}", .{name}) else try self.out.line("{s}-{d}-g{s}", .{ name, distance, c.id });
        } else if (equal(cmd, "GC")) {
            const keep = try reachable(gpa, try self.roots(true));
            var removed: usize = 0;
            for (try keys(gpa, self.commits)) |id| if (!keep.contains(self.commits.get(id).?)) {
                _ = self.commits.remove(id);
                removed += 1;
            };
            try self.out.line("Removed unreachable commits: {d}", .{removed});
        }
    }
};

fn commitLater(_: void, a: *Commit, b: *Commit) bool {
    return a.sequence > b.sequence;
}

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var repository: Repository = .{ .gpa = gpa, .out = .{ .gpa = gpa } };
    try repository.init();
    for (try split(gpa, text, '\n', 0)) |line| {
        if (equal(line, "EXIT")) break;
        repository.command(line) catch |err| {
            if (err != error.Invalid) return err;
            try repository.out.line("error: {s}", .{failure});
        };
    }
    try output.interface.writeAll(repository.out.result());
    try output.interface.flush();
}
