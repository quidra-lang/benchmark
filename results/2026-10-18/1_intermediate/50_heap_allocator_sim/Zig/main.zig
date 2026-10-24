const std = @import("std");
const Text = []const u8;
const I = i64;
fn eq(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn num(a: Text) I { return std.fmt.parseInt(I, a, 10) catch unreachable; }
fn ix(a: I) usize { return @intCast(a); }
fn powerTwo(a: I) bool { return a > 0 and (a & (a - 1)) == 0; }
fn sizeClass(a: I) I {
    var value = a; var result: I = 0;
    while (value >= 2) : (result += 1) value = @divTrunc(value, 2);
    return result;
}
const Host = struct {
    gpa: std.mem.Allocator, out: *std.Io.Writer,
    fn text(h: Host, comptime f: Text, args: anytype) !Text { return std.fmt.allocPrint(h.gpa, f, args); }
    fn line(h: Host, comptime f: Text, args: anytype) !void { try h.out.print(f ++ "\n", args); }
};
const Block = struct { address: I, size: I, owner: ?usize = null, age: I = 0 };
const Identity = struct {
    name: Text, state: u8 = 0, requested: I = 0, contents: []I = &.{}, root: bool = false,
    history: std.ArrayList(Text) = .empty,
};
const Link = struct { source: usize, target: usize };
const Freed = struct { address: I, size: I, merges: I };
const Heap = struct {
    h: Host, size: I = 0, mode: Text = "FIRST",
    blocks: std.ArrayList(Block) = .empty, identities: std.ArrayList(Identity) = .empty, links: std.ArrayList(Link) = .empty,
    serial: I = 0, rover: I = 0, peak: I = 0, counters: [6]I = @splat(0),
    fn init(h: Host, size: I, mode: Text) !Heap {
        var result: Heap = .{ .h = h, .size = size, .mode = mode };
        if (size > 0) try result.blocks.append(h.gpa, result.freeBlock(0, size));
        return result;
    }
    fn identity(s: *Heap, name: Text) !usize {
        for (s.identities.items, 0..) |id, j| if (eq(id.name, name)) return j;
        try s.identities.append(s.h.gpa, .{ .name = name });
        return s.identities.items.len - 1;
    }
    fn at(s: *Heap, address: I) ?usize {
        for (s.blocks.items, 0..) |block, j| if (block.address == address) return j;
        return null;
    }
    fn owned(s: *Heap, owner: usize) usize {
        for (s.blocks.items, 0..) |block, j| if (block.owner == owner) return j;
        unreachable;
    }
    fn required(s: *Heap, requested: I) I {
        const needed = @divTrunc(requested + 7, 8) * 8 + 8;
        if (!eq(s.mode, "BUDDY")) return needed;
        var result: I = 32;
        while (result < needed) result *= 2;
        return result;
    }
    fn freeBlock(s: *Heap, address: I, size: I) Block {
        s.serial += 1;
        return .{ .address = address, .size = size, .age = s.serial };
    }
    fn usedBytes(s: *Heap) I {
        var total: I = 0;
        for (s.blocks.items) |block| {
            if (block.owner != null) total += block.size;
        }
        return total;
    }
    fn fragmentation(s: *Heap) I {
        var total: I = 0; var largest: I = 0;
        for (s.blocks.items) |block| {
            if (block.owner == null) {
                total += block.size;
                largest = @max(largest, block.size);
            }
        }
        return if (total == 0) 0 else @divTrunc((total - largest) * 100, total);
    }
    fn allocate(s: *Heap, owner: usize, needed: I, alignment: I) !?I {
        var chosen: ?usize = null; var placement: I = 0; var start: usize = 0;
        if (eq(s.mode, "NEXT")) {
            for (s.blocks.items, 0..) |block, j| if (block.address <= s.rover and s.rover < block.address + block.size) { start = j; break; };
        }
        for (0..s.blocks.items.len) |turn| {
            const candidate = if (eq(s.mode, "NEXT")) (start + turn) % s.blocks.items.len else turn;
            const block = s.blocks.items[candidate];
            if (block.owner != null) continue;
            var location = @divTrunc(block.address + 8 + alignment - 1, alignment) * alignment - 8;
            if (location > block.address and location - block.address < 16) location += alignment;
            if (location + needed > block.address + block.size) continue;
            var better = chosen == null;
            if (chosen) |previous_index| {
                const previous = s.blocks.items[previous_index];
                if (eq(s.mode, "BEST") or eq(s.mode, "BUDDY")) {
                    better = block.size < previous.size;
                } else if (eq(s.mode, "WORST")) {
                    better = block.size > previous.size;
                } else if (eq(s.mode, "SEGFIT")) {
                    better = sizeClass(block.size) < sizeClass(previous.size) or
                        (sizeClass(block.size) == sizeClass(previous.size) and block.age > previous.age);
                }
            }
            if (better) {
                chosen = candidate;
                placement = location;
            }
            if (eq(s.mode, "FIRST") or eq(s.mode, "NEXT")) break;
        }
        var offset = chosen orelse return null;
        const target = s.blocks.orderedRemove(offset);
        if (eq(s.mode, "BUDDY")) {
            var remaining = target.size;
            while (remaining > needed) {
                remaining = @divTrunc(remaining, 2);
                const upper = s.freeBlock(target.address + remaining, remaining);
                try s.blocks.insert(s.h.gpa, offset, upper);
            }
            try s.blocks.insert(s.h.gpa, offset, .{ .address = target.address, .size = needed, .owner = owner });
            return target.address;
        }
        if (placement > target.address) {
            const leading = s.freeBlock(target.address, placement - target.address);
            try s.blocks.insert(s.h.gpa, offset, leading); offset += 1;
        }
        const available = target.address + target.size - placement;
        const used_size = if (available - needed >= 16) needed else available;
        try s.blocks.insert(s.h.gpa, offset, .{ .address = placement, .size = used_size, .owner = owner });
        if (available - needed >= 16) {
            const trailing = s.freeBlock(placement + needed, available - needed);
            try s.blocks.insert(s.h.gpa, offset + 1, trailing);
        }
        if (eq(s.mode, "NEXT")) s.rover = @mod(placement + used_size, s.size);
        return placement;
    }
    fn release(s: *Heap, address: I) Freed {
        var at_index = s.at(address).?; var merges: I = 0;
        s.blocks.items[at_index].owner = null;
        if (eq(s.mode, "BUDDY")) {
            while (s.blocks.items[at_index].size < s.size) {
                const block = s.blocks.items[at_index];
                const buddy = if (@mod(block.address, 2 * block.size) == 0) block.address + block.size else block.address - block.size;
                const partner = s.at(buddy) orelse break;
                if (s.blocks.items[partner].owner != null or s.blocks.items[partner].size != block.size) break;
                const low = @min(at_index, partner);
                _ = s.blocks.orderedRemove(@max(at_index, partner));
                s.blocks.items[low].address = @min(block.address, buddy);
                s.blocks.items[low].size = block.size * 2;
                at_index = low; merges += 1;
            }
        } else {
            if (at_index + 1 < s.blocks.items.len and s.blocks.items[at_index + 1].owner == null) {
                s.blocks.items[at_index].size += s.blocks.items[at_index + 1].size;
                _ = s.blocks.orderedRemove(at_index + 1); merges += 1;
            }
            if (at_index > 0 and s.blocks.items[at_index - 1].owner == null) {
                s.blocks.items[at_index - 1].size += s.blocks.items[at_index].size;
                _ = s.blocks.orderedRemove(at_index); at_index -= 1; merges += 1;
            }
        }
        const block = s.blocks.items[at_index];
        s.blocks.items[at_index] = s.freeBlock(block.address, block.size);
        return .{ .address = block.address, .size = block.size, .merges = merges };
    }
    fn live(s: *Heap, name: Text) !?usize {
        const owner = try s.identity(name); const state = s.identities.items[owner].state;
        if (state == 1) return owner;
        try s.h.line("ERROR {s} {s}", .{ if (state == 2) @as(Text, "USE AFTER FREE") else "UNKNOWN ID", name });
        return null;
    }
    fn remember(s: *Heap, owner: usize, line: Text) !void {
        try s.identities.items[owner].history.append(s.h.gpa, line);
        try s.h.line("{s}", .{line});
    }
    fn forget(s: *Heap, owner: usize) void {
        s.identities.items[owner].state = 2;
        s.identities.items[owner].root = false;
        var j: usize = 0;
        while (j < s.links.items.len) {
            const edge = s.links.items[j];
            if (edge.source == owner or edge.target == owner) _ = s.links.orderedRemove(j) else j += 1;
        }
    }
    fn freeId(s: *Heap, owner: usize, label: Text) !void {
        const id = s.identities.items[owner];
        if (id.state != 1) return s.h.line("ERROR {s} {s}", .{ if (id.state == 2) @as(Text, "DOUBLE FREE") else "UNKNOWN ID", id.name });
        const block = s.blocks.items[s.owned(owner)];
        const result = s.release(block.address);
        s.forget(owner);
        if (eq(label, "FREE")) s.counters[1] += 1;
        try s.remember(owner, try s.h.text("{s} {s} block={d} merges={d} free={d}+{d}", .{ label, id.name, block.size, result.merges, result.address, result.size }));
    }
    fn reachable(s: *Heap) ![]bool {
        const marked = try s.h.gpa.alloc(bool, s.identities.items.len);
        for (s.identities.items, 0..) |id, j| marked[j] = id.state == 1 and id.root;
        var changed = true;
        while (changed) {
            changed = false;
            for (s.links.items) |edge| {
                if (marked[edge.source] and !marked[edge.target]) {
                    marked[edge.target] = true;
                    changed = true;
                }
            }
        }
        return marked;
    }
    fn tree(s: *Heap, address: I, length: I, depth: usize) anyerror!void {
        try s.h.out.splatByteAll(' ', depth * 2);
        try s.h.out.print("{d}+{d}", .{ address, length });
        if (s.at(address)) |j| {
            if (s.blocks.items[j].size == length) {
                if (s.blocks.items[j].owner) |owner| {
                    try s.h.line(" USED {s}", .{s.identities.items[owner].name});
                } else {
                    try s.h.line(" FREE", .{});
                }
                return;
            }
        }
        try s.h.line(" split", .{});
        try s.tree(address, @divTrunc(length, 2), depth + 1);
        try s.tree(address + @divTrunc(length, 2), @divTrunc(length, 2), depth + 1);
    }
    fn allocation(s: *Heap, w: []const Text) !void {
        const op = w[0]; var alignment: I = 8;
        if (eq(op, "MEMALIGN")) {
            if (eq(s.mode, "BUDDY")) return s.h.line("ERROR UNSUPPORTED IN BUDDY MODE", .{});
            alignment = num(w[2]);
            if (alignment < 8 or alignment > 4096 or !powerTwo(alignment)) return s.h.line("ERROR BAD ALIGNMENT", .{});
        }
        var requested = num(w[if (eq(op, "MEMALIGN")) 3 else 2]);
        if (eq(op, "CALLOC")) requested *= num(w[3]);
        const owner = try s.identity(w[1]); const state = s.identities.items[owner].state;
        if (eq(op, "REALLOC") and requested == 0) return s.freeId(owner, "FREE");
        if (requested == 0) return s.h.line("ERROR BAD SIZE", .{});
        if (eq(op, "REALLOC") and state == 2) return s.h.line("ERROR USE AFTER FREE {s}", .{w[1]});
        const reallocating = eq(op, "REALLOC") and state == 1;
        if (!reallocating and state == 1) return s.h.line("ERROR DUPLICATE ID {s}", .{w[1]});
        const needed = s.required(requested); var address: ?I = null; var original: I = -1; var kind: Text = "kept";
        const old_contents = s.identities.items[owner].contents;
        if (reallocating) {
            const at_index = s.owned(owner); const old = s.blocks.items[at_index];
            original = old.address; address = original;
            if (needed <= old.size) {
                if (eq(s.mode, "BUDDY")) {
                    while (s.blocks.items[at_index].size > needed) {
                        s.blocks.items[at_index].size = @divTrunc(s.blocks.items[at_index].size, 2);
                        const half = s.blocks.items[at_index].size;
                        const upper = s.freeBlock(original + half, half);
                        try s.blocks.insert(s.h.gpa, at_index + 1, upper); kind = "shrunk";
                    }
                } else if (old.size - needed >= 16) {
                    s.blocks.items[at_index].size = needed;
                    try s.blocks.insert(s.h.gpa, at_index + 1, .{ .address = original + needed, .size = old.size - needed });
                    _ = s.release(original + needed); kind = "shrunk";
                }
            } else if (!eq(s.mode, "BUDDY") and at_index + 1 < s.blocks.items.len and s.blocks.items[at_index + 1].owner == null and old.size + s.blocks.items[at_index + 1].size >= needed) {
                const total = old.size + s.blocks.orderedRemove(at_index + 1).size;
                s.blocks.items[at_index].size = if (total - needed >= 16) needed else total;
                if (total - needed >= 16) {
                    const trailing = s.freeBlock(original + needed, total - needed);
                    try s.blocks.insert(s.h.gpa, at_index + 1, trailing);
                }
                kind = "grown";
            } else {
                var can_grow = eq(s.mode, "BUDDY"); var length = old.size;
                while (can_grow and length < needed) {
                    const partner = s.at(original + length);
                    can_grow = @mod(original, 2 * length) == 0 and partner != null and s.blocks.items[partner.?].owner == null and s.blocks.items[partner.?].size == length;
                    length *= 2;
                }
                if (can_grow) {
                    length = old.size;
                    while (length < needed) : (length *= 2) _ = s.blocks.orderedRemove(s.at(original + length).?);
                    s.blocks.items[at_index].size = needed; kind = "grown";
                } else {
                    address = try s.allocate(owner, needed, 8);
                    if (address != null) {
                        _ = s.release(original);
                        kind = "moved";
                    }
                }
            }
        } else address = try s.allocate(owner, needed, alignment);
        const final_address = address orelse {
            s.counters[4] += 1; return s.h.line("ERROR OUT OF MEMORY {s}", .{w[1]});
        };
        const id = &s.identities.items[owner]; id.state = 1; id.requested = requested;
        id.contents = try s.h.gpa.alloc(I, ix(requested));
        @memset(id.contents, if (eq(op, "CALLOC")) @as(I, 0) else -1);
        if (reallocating) {
            @memcpy(id.contents[0..@min(old_contents.len, id.contents.len)], old_contents[0..@min(old_contents.len, id.contents.len)]);
            s.counters[2] += 1;
            if (eq(kind, "moved")) s.counters[3] += 1;
        } else s.counters[0] += 1;
        const block = s.blocks.items[s.at(final_address).?];
        const label = if (eq(op, "REALLOC") and !reallocating) "MALLOC" else op;
        const suffix = if (!reallocating) "" else if (eq(kind, "moved")) try s.h.text(" moved from={d}", .{original + 8}) else try s.h.text(" {s}", .{kind});
        try s.remember(owner, try s.h.text("{s} {s} addr={d} block={d}{s}", .{ label, w[1], final_address + 8, block.size, suffix }));
    }
    fn bench(s: *Heap, w: []const Text) !void {
        const size = num(w[1]); const seed = num(w[2]); const steps = num(w[3]); const maxreq = num(w[4]);
        if (size < 32 or size > 65536 or !powerTwo(size)) return s.h.line("ERROR BAD HEAP SIZE", .{});
        try s.h.line("BENCH heap={d} seed={d} ops={d} maxreq={d}", .{ size, seed, steps, maxreq });
        for ([_]Text{ "FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY" }) |mode| {
            var experiment = try Heap.init(s.h, size, mode); var random = seed; var active: std.ArrayList(I) = .empty;
            var ok: I = 0; var failures: I = 0;
            for (0..ix(steps)) |_| {
                random = @mod(48271 * random, 2147483647);
                const allocating = active.items.len == 0 or @mod(random, 3) != 0;
                random = @mod(48271 * random, 2147483647);
                if (allocating) {
                    const requested = 1 + @mod(random, maxreq);
                    if (try experiment.allocate(0, experiment.required(requested), 8)) |address| {
                        ok += 1; try active.append(s.h.gpa, address);
                    } else failures += 1;
                } else {
                    const chosen = ix(@mod(random, @as(I, @intCast(active.items.len))));
                    _ = experiment.release(active.orderedRemove(chosen));
                }
                experiment.peak = @max(experiment.peak, experiment.usedBytes());
            }
            try s.h.line("BENCH {s} ok={d} fail={d} peak={d} used={d} frag={d} blocks={d}", .{ mode, ok, failures, experiment.peak, experiment.usedBytes(), experiment.fragmentation(), experiment.blocks.items.len });
        }
    }
    fn command(s: *Heap, w: []const Text) !void {
        const op = w[0];
        if (eq(op, "HEAP")) {
            const size = num(w[1]);
            if (size < 32 or size > 65536 or @mod(size, 8) != 0 or (eq(w[2], "BUDDY") and !powerTwo(size))) return s.h.line("ERROR BAD HEAP SIZE", .{});
            s.* = try Heap.init(s.h, size, w[2]);
            return s.h.line("HEAP size={d} mode={s}", .{ size, w[2] });
        }
        if (eq(op, "BENCH")) return s.bench(w);
        if (s.size == 0) return s.h.line("ERROR NO HEAP", .{});
        if (eq(op, "MALLOC") or eq(op, "CALLOC") or eq(op, "MEMALIGN") or eq(op, "REALLOC")) return s.allocation(w);
        if (eq(op, "FREE")) return s.freeId(try s.identity(w[1]), "FREE");
        if (eq(op, "FILL") or eq(op, "READ") or eq(op, "COPY")) {
            const owner = (try s.live(w[1])) orelse return;
            const offset = num(w[2]); const length = num(w[if (eq(op, "COPY")) 5 else 3]);
            if (offset + length > s.identities.items[owner].requested) return s.h.line("ERROR OUT OF BOUNDS {s}", .{w[1]});
            if (eq(op, "COPY")) {
                const source = (try s.live(w[3])) orelse return; const source_offset = num(w[4]);
                if (source_offset + length > s.identities.items[source].requested) return s.h.line("ERROR OUT OF BOUNDS {s}", .{w[3]});
                const copied = try s.h.gpa.dupe(I, s.identities.items[source].contents[ix(source_offset)..ix(source_offset + length)]);
                @memcpy(s.identities.items[owner].contents[ix(offset)..ix(offset + length)], copied);
                return s.h.line("COPY {s} {d}+{d} from {s} {d}", .{ w[1], offset, length, w[3], source_offset });
            }
            if (eq(op, "FILL")) {
                @memset(s.identities.items[owner].contents[ix(offset)..ix(offset + length)], num(w[4]));
                return s.h.line("FILL {s} {d}+{d} = {d}", .{ w[1], offset, length, num(w[4]) });
            }
            try s.h.out.print("READ {s} {d}+{d} =", .{ w[1], offset, length });
            for (s.identities.items[owner].contents[ix(offset)..ix(offset + length)]) |value| {
                if (value < 0) try s.h.out.writeAll(" ?") else try s.h.out.print(" {d}", .{value});
            }
            return s.h.line("", .{});
        }
        if (eq(op, "ROOT") or eq(op, "UNROOT")) {
            const owner = (try s.live(w[1])) orelse return;
            if (eq(op, "UNROOT") and !s.identities.items[owner].root) return s.h.line("ERROR NOT ROOT {s}", .{w[1]});
            s.identities.items[owner].root = eq(op, "ROOT"); return s.h.line("{s} {s}", .{ op, w[1] });
        }
        if (eq(op, "LINK") or eq(op, "UNLINK")) {
            const source = (try s.live(w[1])) orelse return; const target = (try s.live(w[2])) orelse return;
            var found: ?usize = null;
            for (s.links.items, 0..) |edge, j| if (edge.source == source and edge.target == target) { found = j; break; };
            if (eq(op, "UNLINK") and found == null) return s.h.line("ERROR NO LINK {s} {s}", .{ w[1], w[2] });
            if (eq(op, "LINK") and found == null) {
                try s.links.append(s.h.gpa, .{ .source = source, .target = target });
            } else if (eq(op, "UNLINK")) {
                _ = s.links.orderedRemove(found.?);
            }
            return s.h.line("{s} {s} {s}", .{ op, w[1], w[2] });
        }
        if (eq(op, "GC")) {
            const marked = try s.reachable(); var victims: std.ArrayList(usize) = .empty; var total: I = 0;
            for (s.blocks.items) |block| {
                if (block.owner) |owner| {
                    if (!marked[owner]) {
                        try victims.append(s.h.gpa, owner);
                        total += block.size;
                    }
                }
            }
            try s.h.line("GC collected={d} bytes={d}", .{ victims.items.len, total });
            for (victims.items) |owner| try s.freeId(owner, "COLLECT");
            s.counters[5] += @intCast(victims.items.len); return;
        }
        if (eq(op, "SBRK")) {
            const amount = num(w[1]);
            const valid = if (eq(s.mode, "BUDDY")) amount == s.size and s.size * 2 <= 65536 else amount >= 16 and @mod(amount, 8) == 0 and s.size + amount <= 65536;
            if (!valid) return s.h.line("ERROR BAD SBRK SIZE", .{});
            const old = s.size; s.size += amount; try s.blocks.append(s.h.gpa, .{ .address = old, .size = amount });
            const result = s.release(old); return s.h.line("SBRK heap={d} free={d}+{d}", .{ s.size, result.address, result.size });
        }
        if (eq(op, "TRIM")) {
            const old = s.size;
            while (s.blocks.items.len > 1) {
                const last = s.blocks.items[s.blocks.items.len - 1];
                if (last.owner != null or (eq(s.mode, "BUDDY") and last.size != @divTrunc(s.size, 2))) break;
                s.size = last.address; _ = s.blocks.orderedRemove(s.blocks.items.len - 1);
                if (!eq(s.mode, "BUDDY")) break;
            }
            if (s.rover >= s.size) s.rover = 0;
            return s.h.line("TRIM heap={d} released={d}", .{ s.size, old - s.size });
        }
        if (eq(op, "COMPACT")) {
            if (eq(s.mode, "BUDDY")) return s.h.line("ERROR UNSUPPORTED IN BUDDY MODE", .{});
            var compacted: std.ArrayList(Block) = .empty; var moves: std.ArrayList(Text) = .empty; var address: I = 0;
            for (s.blocks.items) |block| if (block.owner) |owner| {
                if (block.address != address) {
                    const line = try s.h.text("MOVE {s} {d} -> {d}", .{ s.identities.items[owner].name, block.address + 8, address + 8 });
                    try moves.append(s.h.gpa, line); try s.identities.items[owner].history.append(s.h.gpa, line);
                }
                try compacted.append(s.h.gpa, .{ .address = address, .size = block.size, .owner = owner }); address += block.size;
            };
            if (address < s.size) {
                const remainder = s.freeBlock(address, s.size - address);
                try compacted.append(s.h.gpa, remainder);
            }
            s.blocks = compacted;
            s.rover = 0;
            s.counters[3] += @intCast(moves.items.len);
            const free_text = if (address == s.size) "none" else try s.h.text("{d}+{d}", .{ address, s.size - address });
            try s.h.line("COMPACT moved={d} free={s}", .{ moves.items.len, free_text });
            for (moves.items) |line| try s.h.line("{s}", .{line}); return;
        }
        if (eq(op, "WHO")) {
            const address = num(w[1]);
            if (address >= s.size) return s.h.line("WHO {d} outside", .{address});
            for (s.blocks.items) |block| if (block.address <= address and address < block.address + block.size) {
                const owner = block.owner orelse return s.h.line("WHO {d} free {d}+{d}", .{ address, block.address, block.size });
                const id = s.identities.items[owner];
                if (address < block.address + 8) return s.h.line("WHO {d} header {s}", .{ address, id.name });
                const offset = address - block.address - 8;
                return s.h.line("WHO {d} {s} {s}+{d}", .{ address, if (offset < id.requested) @as(Text, "data") else "slack", id.name, offset });
            };
        }
        if (eq(op, "DUMP")) {
            const suffix = if (eq(s.mode, "NEXT")) try s.h.text(" rover={d}", .{s.rover}) else "";
            try s.h.line("DUMP mode={s} heap={d} blocks={d}{s}", .{ s.mode, s.size, s.blocks.items.len, suffix });
            for (s.blocks.items) |block| {
                if (block.owner) |owner| {
                    try s.h.line("{d} {d} USED {s} req={d}", .{
                        block.address, block.size,
                        s.identities.items[owner].name, s.identities.items[owner].requested,
                    });
                } else {
                    try s.h.line("{d} {d} FREE", .{ block.address, block.size });
                }
            }
            return;
        }
        if (eq(op, "MAP")) {
            const units = try s.h.gpa.alloc(u8, ix(@divTrunc(s.size, 8)));
            for (s.blocks.items) |block| {
                const start = ix(@divTrunc(block.address, 8)); units[start] = if (block.owner == null) 'F' else 'H';
                for (1..ix(@divTrunc(block.size, 8))) |j| units[start + j] = if (block.owner == null) '.' else if (@as(I, @intCast((j - 1) * 8)) < s.identities.items[block.owner.?].requested) '#' else '-';
            }
            try s.h.line("MAP heap={d}", .{s.size}); var start: usize = 0;
            while (start < units.len) : (start += 64) try s.h.line("{d:0>5} {s}", .{ start * 8, units[start..@min(start + 64, units.len)] }); return;
        }
        if (eq(op, "FREELIST")) {
            var ordered: std.ArrayList(usize) = .empty;
            for (s.blocks.items, 0..) |block, j| if (block.owner == null) { try ordered.append(s.h.gpa, j); };
            if (eq(s.mode, "SEGFIT")) {
                for (0..ordered.items.len) |j| {
                    const selected = ordered.items[j]; var at_index = j;
                    while (at_index > 0 and s.blocks.items[ordered.items[at_index - 1]].age < s.blocks.items[selected].age) : (at_index -= 1) ordered.items[at_index] = ordered.items[at_index - 1];
                    ordered.items[at_index] = selected;
                }
            }
            try s.h.line("FREELIST count={d}", .{ordered.items.len});
            for (4..17) |category| {
                var first = true;
                for (ordered.items) |j| {
                    const block = s.blocks.items[j]; if (sizeClass(block.size) != @as(I, @intCast(category))) continue;
                    if (first) { const lower = @as(I, 1) << @intCast(category); try s.h.out.print("{d}-{d}:", .{ lower, lower * 2 - 1 }); first = false; }
                    try s.h.out.print(" {d}+{d}", .{ block.address, block.size });
                }
                if (!first) try s.h.line("", .{});
            }
            return;
        }
        if (eq(op, "TREE")) {
            if (!eq(s.mode, "BUDDY")) return s.h.line("ERROR REQUIRES BUDDY MODE", .{});
            try s.h.line("TREE heap={d}", .{s.size}); return s.tree(0, s.size, 0);
        }
        if (eq(op, "STATS")) {
            var used_count: I = 0; var free_count: I = 0; var largest: I = 0; var requested: I = 0;
            for (s.blocks.items) |block| {
                if (block.owner) |owner| {
                    used_count += 1;
                    requested += s.identities.items[owner].requested;
                } else {
                    free_count += 1;
                    largest = @max(largest, block.size);
                }
            }
            const used = s.usedBytes();
            try s.h.line("STATS used={d} used_blocks={d} free={d} free_blocks={d} largest={d} frag={d} requested={d} peak={d}", .{ used, used_count, s.size - used, free_count, largest, s.fragmentation(), requested, s.peak });
            return s.h.line("OPS allocs={d} frees={d} reallocs={d} moves={d} failures={d} collected={d}", .{ s.counters[0], s.counters[1], s.counters[2], s.counters[3], s.counters[4], s.counters[5] });
        }
        if (eq(op, "LEAKS")) {
            const marked = try s.reachable(); var names: std.ArrayList(Text) = .empty; var requested: I = 0; var lost: I = 0;
            for (s.identities.items, 0..) |id, j| {
                if (id.state == 1) {
                    try names.append(s.h.gpa, id.name);
                    requested += id.requested;
                    if (!marked[j]) lost += 1;
                }
            }
            std.mem.sort(Text, names.items, {}, struct { fn less(_: void, a: Text, b: Text) bool { return std.mem.lessThan(u8, a, b); } }.less);
            try s.h.line("LEAKS count={d} requested={d} lost={d}", .{ names.items.len, requested, lost });
            for (names.items) |name| {
                const owner = try s.identity(name); const block = s.blocks.items[s.owned(owner)];
                try s.h.line("LEAK {s} addr={d} block={d} req={d} {s}", .{ name, block.address + 8, block.size, s.identities.items[owner].requested, if (marked[owner]) @as(Text, "reachable") else "lost" });
            }
            return;
        }
        const owner = try s.identity(w[1]); const history = s.identities.items[owner].history.items;
        try s.h.line("HISTORY {s} events={d}", .{ w[1], history.len });
        for (history) |line| try s.h.line("{s}", .{line});
    }
};
fn readLine(r: *std.Io.Reader, a: std.mem.Allocator) !?Text {
    var b: std.Io.Writer.Allocating = .init(a); defer b.deinit();
    _ = try r.streamDelimiterEnding(&b.writer, '\n');
    if (r.bufferedLen() == 0 and b.written().len == 0) return null;
    if (r.bufferedLen() > 0) r.toss(1);
    return b.toOwnedSlice();
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator); defer arena.deinit();
    const a = arena.allocator(); var ib: [4096]u8 = undefined; var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib); var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var heap = try Heap.init(.{ .gpa = a, .out = &output.interface }, 0, "FIRST");
    const count = num(std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"));
    for (0..ix(count)) |_| {
        const line = std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"); var w: std.ArrayList(Text) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |word| try w.append(a, word);
        try heap.command(w.items); heap.peak = @max(heap.peak, heap.usedBytes());
    }
    try output.interface.flush();
}
