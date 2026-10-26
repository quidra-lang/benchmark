const std = @import("std");
const Text = []const u8;
const I = i64;
const policy_names = [_]Text{ "FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT" };
fn eq(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn num(a: Text) I {
    return std.fmt.parseInt(I, a, 10) catch unreachable;
}
fn hex(a: Text) I {
    return std.fmt.parseInt(I, a[2..], 16) catch unreachable;
}
fn ix(a: I) usize {
    return @intCast(a);
}
fn lookup(a: Text, names: []const Text) ?usize {
    for (names, 0..) |b, j| if (eq(a, b)) return j;
    return null;
}
const Host = struct {
    gpa: std.mem.Allocator,
    out: *std.Io.Writer,
    fn text(h: Host, comptime f: Text, args: anytype) !Text {
        return std.fmt.allocPrint(h.gpa, f, args);
    }
    fn line(h: Host, comptime f: Text, args: anytype) !void {
        try h.out.print(f ++ "\n", args);
    }
    fn decimal(h: Host, a: I, b: I) !Text {
        const v = if (b == 0) 0 else @divTrunc(a * 100, b);
        return h.text("{d}.{d:0>2}", .{ @divTrunc(v, 100), @mod(v, 100) });
    }
    fn ratio(h: Host, a: I, b: I) !Text {
        return h.text("{s}%", .{try h.decimal(a * 100, b)});
    }
};
const Settings = struct {
    page: I = 256,
    frames: usize = 4,
    tlb: usize = 4,
    sets: usize = 1,
    policy: usize = 0,
    local: bool = false,
    asid: bool = false,
    tick: I = 0,
    tau: I = 8,
    seed: I = 1,
    fn scope(c: Settings) Text {
        return if (c.local) "LOCAL" else "GLOBAL";
    }
};
const ConfigResult = union(enum) { settings: Settings, problem: Text };
fn parseSettings(h: Host, tokens: []const Text) !ConfigResult {
    const keys = [_]Text{ "page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed" };
    const lower = [_]I{ 16, 1, 1, 1, 0, 0, 0, 0, 1, 1 };
    const upper = [_]I{ 4096, 16, 8, 8, 0, 0, 0, 1000, 1000, 2147483646 };
    var c: Settings = .{};
    var seen: [10]bool = @splat(false);
    for (tokens[1..]) |word| {
        var parts = std.mem.splitScalar(u8, word, '=');
        const key = parts.next().?;
        const value = parts.next().?;
        const j = lookup(key, &keys) orelse return .{ .problem = try h.text("unknown key {s}", .{key}) };
        if (seen[j]) return .{ .problem = try h.text("duplicate key {s}", .{key}) };
        seen[j] = true;
        var valid = true;
        if (j == 4) {
            if (lookup(value, &policy_names)) |policy| c.policy = policy else valid = false;
        } else if (j == 5) {
            valid = eq(value, "GLOBAL") or eq(value, "LOCAL");
            c.local = eq(value, "LOCAL");
        } else if (j == 6) {
            valid = eq(value, "ON") or eq(value, "OFF");
            c.asid = eq(value, "ON");
        } else {
            const n = num(value);
            valid = lower[j] <= n and n <= upper[j];
            if (j == 0) valid = valid and n > 0 and (n & (n - 1)) == 0;
            if (valid) switch (j) {
                0 => c.page = n,
                1 => c.frames = ix(n),
                2 => c.tlb = ix(n),
                3 => c.sets = ix(n),
                7 => c.tick = n,
                8 => c.tau = n,
                9 => c.seed = n,
                else => unreachable,
            };
        }
        if (!valid) return .{ .problem = try h.text("invalid {s}", .{key}) };
    }
    if (c.tlb % c.sets != 0) return .{ .problem = "invalid sets" };
    return .{ .settings = c };
}
const Command = struct { words: []const Text = &.{}, access: bool = false, pid: I = 0, op: Text = "R", address: I = 0 };
fn accessCommand(pid: I, op: Text, address: I) Command {
    return .{ .access = true, .pid = pid, .op = op, .address = address };
}
const Page = struct {
    frame: ?usize = null,
    slot: ?usize = null,
    readonly: bool = false,
    locked: bool = false,
    r: I = 0,
    m: I = 0,
    load: I = 0,
    last: I = 0,
    uses: I = 0,
    age: I = 0,
    ever: bool = false,
};
const Process = struct {
    pid: I,
    pages: []Page,
    exited: bool = false,
    accesses: I = 0,
    faults: I = 0,
    writebacks: I = 0,
    segfaults: I = 0,
    protfaults: I = 0,
    peak: I = 0,
    hand: usize = 0,
};
const Reference = struct { process: usize, page: usize };
const Entry = struct { process: usize, page: usize, frame: usize };
const ActionKind = enum { access, exit, clean, lock, unlock };
const Action = struct { kind: ActionKind, pid: I = 0, op: Text = "R", address: I = 0, first: usize = 0, last: usize = 0 };
const AccessRecord = struct { process: usize, page: usize, fault: bool };
const Simulation = struct {
    h: Host,
    c: Settings,
    processes: std.ArrayList(Process) = .empty,
    frames: []?Reference,
    entries: std.ArrayList(Entry) = .empty,
    future: std.ArrayList(Command) = .empty,
    cursor: usize = 0,
    actions: std.ArrayList(Action) = .empty,
    accesses: std.ArrayList(AccessRecord) = .empty,
    fixed_processes: bool = false,
    trace: bool = false,
    silent: bool = false,
    time: I = 0,
    previous: ?usize = null,
    hand: usize = 0,
    random: I,
    faults: I = 0,
    zeros: I = 0,
    swapins: I = 0,
    tlbhits: I = 0,
    writebacks: I = 0,
    switches: I = 0,
    fn init(h: Host, c: Settings) !Simulation {
        const frames = try h.gpa.alloc(?Reference, c.frames);
        @memset(frames, null);
        return .{ .h = h, .c = c, .frames = frames, .random = c.seed };
    }
    fn emit(s: *Simulation, comptime f: Text, args: anytype) !void {
        if (!s.silent) try s.h.line(f, args);
    }
    fn processIndex(s: *Simulation, pid: I) ?usize {
        for (s.processes.items, 0..) |p, j| if (p.pid == pid) return j;
        return null;
    }
    fn live(s: *Simulation, pid: I) !?usize {
        const owner = s.processIndex(pid) orelse {
            try s.emit("ERROR unknown process {d}", .{pid});
            return null;
        };
        if (s.processes.items[owner].exited) {
            try s.emit("ERROR process {d} exited", .{pid});
            return null;
        }
        return owner;
    }
    fn addProcess(s: *Simulation, pid: I, count: usize) !void {
        const pages = try s.h.gpa.alloc(Page, count);
        @memset(pages, .{});
        try s.processes.append(s.h.gpa, .{ .pid = pid, .pages = pages });
    }
    fn page(s: *Simulation, ref: Reference) *Page {
        return &s.processes.items[ref.process].pages[ref.page];
    }
    fn resident(s: *Simulation, owner: usize) I {
        var count: I = 0;
        for (s.frames) |frame| {
            if (frame) |ref| {
                if (ref.process == owner) count += 1;
            }
        }
        return count;
    }
    fn quota(s: *Simulation, owner: usize) I {
        var before: usize = 0;
        for (s.processes.items) |p| if (p.pid < s.processes.items[owner].pid) {
            before += 1;
        };
        const count = s.processes.items.len;
        return @intCast(s.c.frames / count + @intFromBool(before < s.c.frames % count));
    }
    fn invalidate(s: *Simulation, ref: Reference) void {
        var j: usize = 0;
        while (j < s.entries.items.len) {
            const entry = s.entries.items[j];
            if (entry.process == ref.process and entry.page == ref.page) _ = s.entries.orderedRemove(j) else j += 1;
        }
    }
    fn writeBack(s: *Simulation, ref: Reference) void {
        s.processes.items[ref.process].writebacks += 1;
        s.writebacks += 1;
        s.page(ref).m = 0;
        if (s.page(ref).slot != null) return;
        var slot: usize = 0;
        while (true) : (slot += 1) {
            var used = false;
            for (s.processes.items) |p| {
                for (p.pages) |item| {
                    if (item.slot == slot) used = true;
                }
            }
            if (!used) break;
        }
        s.page(ref).slot = slot;
    }
    fn nextUse(s: *Simulation, ref: Reference) usize {
        for (s.cursor..s.future.items.len) |j| {
            const request = s.future.items[j];
            if (request.pid == s.processes.items[ref.process].pid and @divTrunc(request.address, s.c.page) == @as(I, @intCast(ref.page))) return j;
        }
        return s.future.items.len;
    }
    fn choose(s: *Simulation, owner: usize) usize {
        var candidates: [16]usize = undefined;
        var count: usize = 0;
        var unlocked: [16]usize = undefined;
        var unlocked_count: usize = 0;
        for (s.frames, 0..) |maybe_ref, j| if (maybe_ref) |ref| {
            if (!s.c.local or ref.process == owner) {
                candidates[count] = j;
                count += 1;
                if (!s.page(ref).locked) {
                    unlocked[unlocked_count] = j;
                    unlocked_count += 1;
                }
            }
        };
        if (unlocked_count > 0) {
            @memcpy(candidates[0..unlocked_count], unlocked[0..unlocked_count]);
            count = unlocked_count;
        }
        if (s.c.policy == 8) {
            s.random = @mod(48271 * s.random, 2147483647);
            return candidates[ix(@mod(s.random, @as(I, @intCast(count))))];
        }
        if (s.c.policy >= 5 and s.c.policy <= 7) {
            const hand = if (s.c.local) s.processes.items[owner].hand else s.hand;
            var circular: [16]usize = undefined;
            var length: usize = 0;
            for (0..s.c.frames) |distance| {
                const frame = (hand + distance) % s.c.frames;
                for (candidates[0..count]) |candidate| if (candidate == frame) {
                    circular[length] = candidate;
                    length += 1;
                };
            }
            var chosen: ?usize = null;
            if (s.c.policy == 7) {
                for (circular[0..length]) |candidate| {
                    const ref = s.frames[candidate].?;
                    const item = s.page(ref);
                    if (item.r == 1) {
                        item.r = 0;
                        item.last = s.time;
                    } else if (s.time - item.last > s.c.tau) {
                        if (item.m == 0) {
                            chosen = candidate;
                            break;
                        }
                        s.writeBack(ref);
                    }
                }
                if (chosen == null) {
                    for (circular[0..length]) |candidate| if (s.page(s.frames[candidate].?).m == 0) {
                        chosen = candidate;
                        break;
                    };
                }
                if (chosen == null) chosen = circular[0];
            } else {
                while (chosen == null) {
                    if (s.c.policy == 6) {
                        for (circular[0..length]) |candidate| {
                            const item = s.page(s.frames[candidate].?);
                            if (item.r == 0 and item.m == 0) {
                                chosen = candidate;
                                break;
                            }
                        }
                    }
                    if (chosen != null) break;
                    for (circular[0..length]) |candidate| {
                        const item = s.page(s.frames[candidate].?);
                        if (item.r == 0 and (s.c.policy == 5 or item.m == 1)) {
                            chosen = candidate;
                            break;
                        }
                        item.r = 0;
                    }
                }
            }
            const result = chosen.?;
            if (s.c.local) s.processes.items[owner].hand = (result + 1) % s.c.frames else s.hand = (result + 1) % s.c.frames;
            return result;
        }
        var best = candidates[0];
        for (candidates[0..count]) |candidate| {
            const current_ref = s.frames[candidate].?;
            const best_ref = s.frames[best].?;
            const current = s.page(current_ref);
            const previous = s.page(best_ref);
            const better = switch (s.c.policy) {
                0 => current.load < previous.load,
                1 => current.last < previous.last,
                2 => current.uses < previous.uses or (current.uses == previous.uses and current.load < previous.load),
                3 => 2 * current.r + current.m < 2 * previous.r + previous.m,
                4 => current.age < previous.age or (current.age == previous.age and current.load < previous.load),
                9 => s.nextUse(current_ref) > s.nextUse(best_ref),
                else => unreachable,
            };
            if (better) best = candidate;
        }
        return best;
    }
    fn access(s: *Simulation, request: Command) !void {
        s.fixed_processes = true;
        s.cursor += 1;
        const owner = (try s.live(request.pid)) orelse return;
        if (request.address >= @as(I, @intCast(s.processes.items[owner].pages.len)) * s.c.page) {
            s.processes.items[owner].segfaults += 1;
            return s.emit("SEGFAULT P{d} 0x{X}", .{ request.pid, request.address });
        }
        const page_number = ix(@divTrunc(request.address, s.c.page));
        const ref: Reference = .{ .process = owner, .page = page_number };
        if (eq(request.op, "W") and s.page(ref).readonly) {
            s.processes.items[owner].protfaults += 1;
            return s.emit("PROTFAULT P{d} 0x{X}", .{ request.pid, request.address });
        }
        s.time += 1;
        const switched = s.previous != null and s.previous.? != owner;
        if (switched) {
            s.switches += 1;
            if (!s.c.asid) s.entries.clearRetainingCapacity();
        }
        s.previous = owner;
        var hit: ?usize = null;
        for (s.entries.items, 0..) |entry, j| if (entry.process == owner and entry.page == page_number) {
            hit = j;
            break;
        };
        var fault = false;
        var result: Text = "HIT";
        var eviction: Text = "";
        if (hit) |j| {
            s.tlbhits += 1;
            result = "TLBHIT";
            const recent = s.entries.orderedRemove(j);
            try s.entries.append(s.h.gpa, recent);
        } else {
            if (s.page(ref).frame == null) {
                fault = true;
                s.faults += 1;
                s.processes.items[owner].faults += 1;
                const swapped = s.page(ref).slot != null;
                if (swapped) s.swapins += 1 else s.zeros += 1;
                result = if (swapped) "FAULT SWAPIN" else "FAULT ZERO";
                var chosen: ?usize = null;
                if (!s.c.local or s.resident(owner) < s.quota(owner)) {
                    for (s.frames, 0..) |frame, j| if (frame == null) {
                        chosen = j;
                        break;
                    };
                }
                if (chosen == null) {
                    chosen = s.choose(owner);
                    const victim = s.frames[chosen.?].?;
                    const dirty = s.page(victim).m == 1;
                    eviction = try s.h.text(" evict=P{d}:{d}{s}", .{ s.processes.items[victim.process].pid, victim.page, if (dirty) @as(Text, " writeback") else "" });
                    if (dirty) s.writeBack(victim);
                    s.page(victim).frame = null;
                    s.invalidate(victim);
                }
                s.frames[chosen.?] = ref;
                const item = s.page(ref);
                item.frame = chosen;
                item.load = s.time;
                item.uses = 0;
                item.m = 0;
                item.age = 0;
                s.processes.items[owner].peak = @max(s.processes.items[owner].peak, s.resident(owner));
            }
            var count: usize = 0;
            var oldest: ?usize = null;
            for (s.entries.items, 0..) |entry, j| {
                if (entry.page % s.c.sets == page_number % s.c.sets) {
                    if (oldest == null) oldest = j;
                    count += 1;
                }
            }
            if (count == s.c.tlb / s.c.sets) _ = s.entries.orderedRemove(oldest.?);
            try s.entries.append(s.h.gpa, .{ .process = owner, .page = page_number, .frame = s.page(ref).frame.? });
        }
        const item = s.page(ref);
        item.r = 1;
        if (eq(request.op, "W")) item.m = 1;
        item.last = s.time;
        item.uses += 1;
        item.ever = true;
        s.processes.items[owner].accesses += 1;
        try s.accesses.append(s.h.gpa, .{ .process = owner, .page = page_number, .fault = fault });
        if (!s.silent) try s.actions.append(s.h.gpa, .{ .kind = .access, .pid = request.pid, .op = request.op, .address = request.address });
        const timer = s.c.tick > 0 and @mod(s.time, s.c.tick) == 0;
        if (timer) {
            for (s.frames) |frame| if (frame) |loaded| {
                const p = s.page(loaded);
                p.age = @divTrunc(p.age, 2) + 128 * p.r;
                p.r = 0;
            };
        }
        if (s.trace) {
            const physical = @as(I, @intCast(item.frame.?)) * s.c.page + @mod(request.address, s.c.page);
            try s.emit("t={d} P{d} {s} 0x{X} page={d} frame={d} phys=0x{X} {s}{s}{s}", .{ s.time, request.pid, request.op, request.address, page_number, item.frame.?, physical, result, eviction, if (switched) @as(Text, " switch") else "" });
            if (timer) try s.emit("t={d} tick", .{s.time});
        }
    }
    fn exitProcess(s: *Simulation, owner: usize) !void {
        const freed = s.resident(owner);
        var slots: I = 0;
        for (s.processes.items[owner].pages, 0..) |*item, j| {
            if (item.slot != null) slots += 1;
            item.slot = null;
            item.frame = null;
            s.invalidate(.{ .process = owner, .page = j });
        }
        for (s.frames) |*frame| {
            if (frame.*) |ref| {
                if (ref.process == owner) frame.* = null;
            }
        }
        s.processes.items[owner].exited = true;
        const pid = s.processes.items[owner].pid;
        if (!s.silent) try s.actions.append(s.h.gpa, .{ .kind = .exit, .pid = pid });
        try s.emit("EXIT P{d} freed={d} slots={d}", .{ pid, freed, slots });
    }
    fn clean(s: *Simulation) !void {
        var written: I = 0;
        for (s.frames) |frame| {
            if (frame) |ref| {
                if (s.page(ref).m == 1) {
                    s.writeBack(ref);
                    written += 1;
                }
            }
        }
        if (!s.silent) try s.actions.append(s.h.gpa, .{ .kind = .clean });
        try s.emit("CLEAN written={d}", .{written});
    }
    fn rerun(s: *Simulation, policy: usize, frame_count: usize) !Simulation {
        var c = s.c;
        c.policy = policy;
        c.frames = frame_count;
        var replay = try Simulation.init(s.h, c);
        replay.silent = true;
        for (s.processes.items) |p| try replay.addProcess(p.pid, p.pages.len);
        for (s.actions.items) |action| if (action.kind == .access) {
            try replay.future.append(s.h.gpa, accessCommand(action.pid, action.op, action.address));
        };
        for (s.actions.items) |action| switch (action.kind) {
            .access => try replay.access(accessCommand(action.pid, action.op, action.address)),
            .exit => try replay.exitProcess(replay.processIndex(action.pid).?),
            .clean => try replay.clean(),
            .lock, .unlock => {
                const owner = replay.processIndex(action.pid).?;
                for (action.first..action.last + 1) |j| replay.processes.items[owner].pages[j].locked = action.kind == .lock;
            },
        };
        return replay;
    }
    fn command(s: *Simulation, w: []const Text) !void {
        const op = w[0];
        if (eq(op, "PROCESS")) {
            const pid = num(w[1]);
            const count = num(w[2]);
            if (s.fixed_processes) return s.emit("ERROR processes are fixed", .{});
            if (s.processIndex(pid) != null) return s.emit("ERROR duplicate process {d}", .{pid});
            if (count < 1 or count > 256) return s.emit("ERROR invalid page count", .{});
            if (s.processes.items.len == 8 or (s.c.local and s.processes.items.len == s.c.frames)) return s.emit("ERROR too many processes", .{});
            return s.addProcess(pid, ix(count));
        }
        var owner: usize = 0;
        if (lookup(op, &.{ "EXIT", "PROTECT", "LOCK", "UNLOCK", "PAGETABLE", "WSET", "HOT" }) != null) owner = (try s.live(num(w[1]))) orelse return;
        if (eq(op, "EXIT")) return s.exitProcess(owner);
        if (eq(op, "PROTECT") or eq(op, "LOCK") or eq(op, "UNLOCK")) {
            const first = ix(num(w[2]));
            const last = ix(num(w[3]));
            if (first > last or last >= s.processes.items[owner].pages.len) return s.emit("ERROR invalid page range", .{});
            for (first..last + 1) |j| {
                if (eq(op, "PROTECT")) {
                    s.processes.items[owner].pages[j].readonly = eq(w[4], "RO");
                } else {
                    s.processes.items[owner].pages[j].locked = eq(op, "LOCK");
                }
            }
            if (!eq(op, "PROTECT")) try s.actions.append(s.h.gpa, .{ .kind = if (eq(op, "LOCK")) .lock else .unlock, .pid = s.processes.items[owner].pid, .first = first, .last = last });
            return;
        }
        if (eq(op, "TRACE")) {
            s.trace = eq(w[1], "ON");
            return;
        }
        if (eq(op, "CLEAN")) return s.clean();
        if (eq(op, "SUMMARY")) {
            try s.emit("SUMMARY policy={s} scope={s} time={d}", .{ policy_names[s.c.policy], s.c.scope(), s.time });
            var segfaults: I = 0;
            var protfaults: I = 0;
            for (s.processes.items) |p| {
                segfaults += p.segfaults;
                protfaults += p.protfaults;
            }
            try s.emit("total faults={d} zero={d} swapin={d} faultrate={s} tlbhits={d} tlbrate={s} writebacks={d} switches={d} segfaults={d} protfaults={d}", .{ s.faults, s.zeros, s.swapins, try s.h.ratio(s.faults, s.time), s.tlbhits, try s.h.ratio(s.tlbhits, s.time), s.writebacks, s.switches, segfaults, protfaults });
            for (1..100) |pid| if (s.processIndex(@intCast(pid))) |j| {
                const p = s.processes.items[j];
                const quota_text = if (s.c.local) try s.h.text(" quota={d}", .{s.quota(j)}) else "";
                try s.emit("P{d} accesses={d} faults={d} writebacks={d} segfaults={d} protfaults={d} resident={d} peak={d}{s}{s}", .{ pid, p.accesses, p.faults, p.writebacks, p.segfaults, p.protfaults, s.resident(j), p.peak, quota_text, if (p.exited) @as(Text, " exited") else "" });
            };
            return;
        }
        if (eq(op, "FRAMES")) {
            var used: usize = 0;
            for (s.frames) |frame| if (frame != null) {
                used += 1;
            };
            try s.emit("FRAMES used={d}/{d}", .{ used, s.c.frames });
            for (s.frames, 0..) |frame, j| {
                if (frame) |ref| {
                    const p = s.page(ref);
                    try s.emit("{d} P{d}:{d} R={d} M={d} load={d} last={d} uses={d} age={d}{s}", .{ j, s.processes.items[ref.process].pid, ref.page, p.r, p.m, p.load, p.last, p.uses, p.age, if (p.locked) @as(Text, " locked") else "" });
                } else try s.emit("{d} free", .{j});
            }
            if (s.c.policy >= 5 and s.c.policy <= 7) {
                if (!s.c.local) try s.emit("hand={d}", .{s.hand}) else {
                    try s.h.out.writeAll("hand");
                    for (1..100) |pid| if (s.processIndex(@intCast(pid))) |j| {
                        try s.h.out.print(" P{d}={d}", .{ pid, s.processes.items[j].hand });
                    };
                    try s.h.line("", .{});
                }
            }
            return;
        }
        if (eq(op, "PAGETABLE")) {
            const p = s.processes.items[owner];
            try s.emit("PAGETABLE P{d} pages={d} resident={d}", .{ p.pid, p.pages.len, s.resident(owner) });
            for (p.pages, 0..) |item, j| if (item.ever) {
                const status = if (item.frame) |frame| try s.h.text("frame={d} R={d} M={d}", .{ frame, item.r, item.m }) else if (item.slot) |slot| try s.h.text("swap={d}", .{slot}) else "zero";
                try s.emit("{d} {s}{s}{s}", .{ j, status, if (item.readonly) @as(Text, " RO") else "", if (item.locked) @as(Text, " locked") else "" });
            };
            return;
        }
        if (eq(op, "TLB")) {
            try s.emit("TLB used={d}/{d} sets={d}", .{ s.entries.items.len, s.c.tlb, s.c.sets });
            for (0..s.c.sets) |set| {
                try s.h.out.print("set {d}:", .{set});
                var j = s.entries.items.len;
                while (j > 0) {
                    j -= 1;
                    const entry = s.entries.items[j];
                    if (entry.page % s.c.sets == set) {
                        try s.h.out.print(" P{d}:{d}->{d}", .{ s.processes.items[entry.process].pid, entry.page, entry.frame });
                    }
                }
                try s.h.line("", .{});
            }
            return;
        }
        if (eq(op, "SWAP")) {
            var count: usize = 0;
            var end: usize = 0;
            for (s.processes.items) |p| {
                for (p.pages) |item| {
                    if (item.slot) |slot| {
                        count += 1;
                        end = @max(end, slot + 1);
                    }
                }
            }
            try s.emit("SWAP used={d}", .{count});
            for (0..end) |slot| {
                for (s.processes.items) |p| {
                    for (p.pages, 0..) |item, j| {
                        if (item.slot == slot) try s.emit("{d} P{d}:{d}", .{ slot, p.pid, j });
                    }
                }
            }
            return;
        }
        if (eq(op, "COMPARE")) {
            try s.emit("COMPARE accesses={d} frames={d}", .{ s.time, s.c.frames });
            var fault_counts: [10]I = undefined;
            var write_counts: [10]I = undefined;
            var order: [10]usize = undefined;
            for (policy_names, 0..) |name, j| {
                const replay = try s.rerun(j, s.c.frames);
                fault_counts[j] = replay.faults;
                write_counts[j] = replay.writebacks;
                order[j] = j;
                try s.emit("{s} faults={d} writebacks={d} tlbhits={d}", .{ name, replay.faults, replay.writebacks, replay.tlbhits });
            }
            for (1..10) |j| {
                const selected = order[j];
                var at = j;
                while (at > 0 and (fault_counts[selected] < fault_counts[order[at - 1]] or (fault_counts[selected] == fault_counts[order[at - 1]] and write_counts[selected] < write_counts[order[at - 1]]))) : (at -= 1) order[at] = order[at - 1];
                order[at] = selected;
            }
            try s.h.out.writeAll("ranking");
            for (order) |j| try s.h.out.print(" {s}", .{policy_names[j]});
            return s.h.line("", .{});
        }
        if (eq(op, "CURVE")) {
            const policy = lookup(w[1], &policy_names) orelse return s.emit("ERROR unknown policy", .{});
            const lower = ix(num(w[2]));
            const upper = ix(num(w[3]));
            if (lower < 1 or lower > upper or upper > 16 or (s.c.local and lower < s.processes.items.len)) return s.emit("ERROR invalid frame range", .{});
            try s.emit("CURVE {s} frames={d}..{d}", .{ w[1], lower, upper });
            var previous: I = -1;
            for (lower..upper + 1) |count| {
                const replay = try s.rerun(policy, count);
                try s.emit("F={d} faults={d}{s}", .{ count, replay.faults, if (previous >= 0 and replay.faults > previous) @as(Text, " ANOMALY") else "" });
                previous = replay.faults;
            }
            return;
        }
        if (eq(op, "EAT")) {
            if (s.time == 0) return s.emit("EAT accesses=0", .{});
            const total = num(w[1]) * s.time + num(w[2]) * (2 * s.time - s.tlbhits) + num(w[3]) * (s.swapins + s.writebacks);
            return s.emit("EAT accesses={d} total={d} average={s}", .{ s.time, total, try s.h.decimal(total, s.time) });
        }
        if (eq(op, "TIMELINE")) {
            const width = ix(num(w[1]));
            if (width < 1) return s.emit("ERROR invalid window", .{});
            try s.h.out.print("TIMELINE window={d}", .{width});
            var at: usize = 0;
            while (at < s.accesses.items.len) : (at += width) {
                var count: usize = 0;
                for (s.accesses.items[at..@min(at + width, s.accesses.items.len)]) |record| if (record.fault) {
                    count += 1;
                };
                try s.h.out.print(" {d}", .{count});
            }
            return s.h.line("", .{});
        }
        if (eq(op, "WSET")) {
            const width = ix(num(w[2]));
            if (width < 1) return s.emit("ERROR invalid window", .{});
            var seen: [256]bool = @splat(false);
            var remaining = width;
            var j = s.accesses.items.len;
            while (j > 0 and remaining > 0) {
                j -= 1;
                const record = s.accesses.items[j];
                if (record.process == owner) {
                    seen[record.page] = true;
                    remaining -= 1;
                }
            }
            var count: usize = 0;
            for (seen) |value| if (value) {
                count += 1;
            };
            try s.h.out.print("WSET P{d} window={d} size={d}", .{ s.processes.items[owner].pid, width, count });
            for (seen, 0..) |value, p| if (value) {
                try s.h.out.print(" {d}", .{p});
            };
            return s.h.line("", .{});
        }
        if (eq(op, "HOT")) {
            const count = ix(num(w[2]));
            if (count < 1) return s.emit("ERROR invalid count", .{});
            var frequencies: [256]I = @splat(0);
            for (s.accesses.items) |record| if (record.process == owner) {
                frequencies[record.page] += 1;
            };
            try s.h.out.print("HOT P{d}", .{s.processes.items[owner].pid});
            for (0..count) |_| {
                var best: ?usize = null;
                for (frequencies, 0..) |frequency, j| if (frequency > 0 and (best == null or frequency > frequencies[best.?])) {
                    best = j;
                };
                const p = best orelse break;
                try s.h.out.print(" {d}:{d}", .{ p, frequencies[p] });
                frequencies[p] = 0;
            }
            return s.h.line("", .{});
        }
    }
};
fn readLine(r: *std.Io.Reader, a: std.mem.Allocator) !?Text {
    var b: std.Io.Writer.Allocating = .init(a);
    defer b.deinit();
    _ = try r.streamDelimiterEnding(&b.writer, '\n');
    if (r.bufferedLen() == 0 and b.written().len == 0) return null;
    if (r.bufferedLen() > 0) r.toss(1);
    return b.toOwnedSlice();
}
fn words(a: std.mem.Allocator, line: Text) ![]const Text {
    var list: std.ArrayList(Text) = .empty;
    var it = std.mem.splitScalar(u8, std.mem.trim(u8, line, "\r"), ' ');
    while (it.next()) |word| try list.append(a, word);
    return list.toOwnedSlice(a);
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ib: [4096]u8 = undefined;
    var ob: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    const h: Host = .{ .gpa = a, .out = &output.interface };
    const count = num(std.mem.trim(u8, (try readLine(&input.interface, a)).?, "\r"));
    var commands: std.ArrayList(Command) = .empty;
    for (0..ix(count)) |_| {
        const w = try words(a, (try readLine(&input.interface, a)).?);
        if (eq(w[0], "LOOP")) {
            const pid = num(w[1]);
            const start = hex(w[3]);
            const interval = num(w[4]);
            const length = num(w[5]);
            const repeats = num(w[6]);
            for (0..ix(repeats)) |_| {
                for (0..ix(length)) |j| {
                    try commands.append(a, accessCommand(pid, w[2], start + @as(I, @intCast(j)) * interval));
                }
            }
        } else if (eq(w[0], "RAND")) {
            const pid = num(w[1]);
            const lower = hex(w[2]);
            const upper = hex(w[3]);
            const n = num(w[4]);
            var random = num(w[5]);
            const rate = num(w[6]);
            for (0..ix(n)) |_| {
                random = @mod(48271 * random, 2147483647);
                const address = lower + @mod(random, upper - lower);
                random = @mod(48271 * random, 2147483647);
                try commands.append(a, accessCommand(pid, if (@mod(random, 100) < rate) "W" else "R", address));
            }
        } else if (std.ascii.isDigit(w[0][0])) {
            try commands.append(a, accessCommand(num(w[0]), w[1], hex(w[2])));
        } else try commands.append(a, .{ .words = w });
    }
    var simulation: ?Simulation = null;
    for (commands.items, 0..) |command, command_index| {
        if (!command.access and eq(command.words[0], "SYSTEM")) {
            simulation = null;
            switch (try parseSettings(h, command.words)) {
                .problem => |problem| try h.line("ERROR {s}", .{problem}),
                .settings => |c| {
                    simulation = try Simulation.init(h, c);
                    for (commands.items[command_index + 1 ..]) |future| {
                        if (!future.access and eq(future.words[0], "SYSTEM")) break;
                        if (future.access) try simulation.?.future.append(a, future);
                    }
                    try h.line("SYSTEM page={d} frames={d} tlb={d} sets={d} policy={s} scope={s} asid={s} tick={d} tau={d} seed={d}", .{ c.page, c.frames, c.tlb, c.sets, policy_names[c.policy], c.scope(), if (c.asid) @as(Text, "ON") else "OFF", c.tick, c.tau, c.seed });
                },
            }
        } else if (simulation) |*s| {
            if (command.access) try s.access(command) else try s.command(command.words);
        } else try h.line("ERROR no system", .{});
    }
    try output.interface.flush();
}
