const std = @import("std");
const c = @import("trace_io.zig");
const h = @import("hazards.zig");
const pipeline = @import("pipeline.zig");
const predictors = @import("predictors.zig");
const r = @import("report.zig");
const Rejection = struct { line: usize, reason: []const u8 };
const Gap = struct { line: usize, expected: i64, found: i64 };
const Static = struct { first: usize, indices: std.ArrayList(usize) = .empty, taken: i64 = 0,
     stalls: [4]i64 = .{ 0, 0, 0, 0 } };
const Trace = struct {
    instructions: std.ArrayList(c.Instruction) = .empty,
    statics: std.ArrayList(Static) = .empty,
    first: std.AutoHashMapUnmanaged(i64, usize) = .empty,
    rejected: std.ArrayList(Rejection) = .empty,
    gaps: std.ArrayList(Gap) = .empty,
};
const Checked = union(enum) { valid: c.Instruction, invalid: []const u8 };
fn check(text: []const u8, trace: *const Trace) Checked {
    const fields = c.split(text, ' ');
    if (fields.len != 8) return .{ .invalid = "fields" };
    for (fields) |field| if (field.len == 0) return .{ .invalid = "fields" };
    const pc = c.parseHex(fields[0]) orelse return .{ .invalid = "pc" };
    if (@mod(pc, 4) != 0) return .{ .invalid = "pc" };
    var kind: ?c.Class = null;
    for (c.classes, 0..) |name, i| if (c.eq(name, fields[1])) {
        kind = @enumFromInt(i);
    };
    if (kind == null) return .{ .invalid = "class" };
    const registers = [_]i64{ c.parseRegister(fields[2]), c.parseRegister(fields[3]), c.parseRegister(fields[4]) };
    for (registers) |value| if (value == -2) return .{ .invalid = "register" };
    const usage = [_][3]i8{ .{ 1, 1, 0 }, .{ 1, 1, 1 }, .{ 1, 1, -1 }, .{ -1, 1, 1 }, .{ -1,
         1, 0 }, .{ 0, 0, -1 }, .{ -1, -1, -1 } };
    for (usage[@intFromEnum(kind.?)], registers) |need, value| if ((need == 1 and value < 0) or (need == -1 and value >= 0)) return .{ .invalid = "operands" };
    var out: c.Instruction = .{ .pc = pc, .kind = kind.?, .rd = registers[0], .rs1 = registers[1],
         .rs2 = registers[2] };
    if (if (out.kind == .branch) !c.eq(fields[5], "T") and !c.eq(fields[5], "N") else !c.eq(fields[5],
         if (out.kind == .jump) "T" else "-")) return .{ .invalid = "taken" };
    out.taken = c.eq(fields[5], "T");
    if (out.control()) {
        out.target = c.parseHex(fields[6]) orelse return .{ .invalid = "target" };
        if (@mod(out.target, 4) != 0 or out.target == out.pc + 4) return .{ .invalid = "target" };
    } else if (!c.eq(fields[6], "-")) return .{ .invalid = "target" };
    if (out.kind == .load or out.kind == .store) {
        out.address = c.parseHex(fields[7]) orelse return .{ .invalid = "address" };
        if (@mod(out.address, 4) != 0) return .{ .invalid = "address" };
    } else if (!c.eq(fields[7], "-")) return .{ .invalid = "address" };
    if (trace.first.get(out.pc)) |id| {
        const old = trace.instructions.items[trace.statics.items[id].first];
        if (out.kind != old.kind or out.rd != old.rd or out.rs1 != old.rs1 or out.rs2 != old.rs2 or ((out.kind == .branch or (out.kind == .jump and out.rs1 < 0)) and out.target != old.target)) return .{ .invalid = "conflict" };
    }
    out.next = if (out.taken) out.target else out.pc + 4;
    return .{ .valid = out };
}
fn validate(lines: []const []const u8) Trace {
    var out: Trace = .{};
    for (lines, 0..) |line, index| switch (check(line, &out)) {
        .invalid => |reason| c.append(Rejection, &out.rejected, .{ .line = index + 1, .reason = reason }),
        .valid => |value| {
            var instruction = value;
            instruction.line = index + 1;
            if (out.instructions.items.len > 0) {
                const previous = out.instructions.items[out.instructions.items.len - 1];
                if (previous.next != instruction.pc) c.append(Gap, &out.gaps, .{ .line = index + 1,
                     .expected = previous.next, .found = instruction.pc });
            }
            const entry = out.first.getOrPut(c.allocator, instruction.pc) catch @panic("allocation failed");
            if (!entry.found_existing) {
                entry.value_ptr.* = out.statics.items.len;
                c.append(Static, &out.statics, .{ .first = out.instructions.items.len });
            }
            instruction.static_id = entry.value_ptr.*;
            const group = &out.statics.items[instruction.static_id];
            c.append(usize, &group.indices, out.instructions.items.len);
            group.taken += @intFromBool(instruction.taken);
            c.append(c.Instruction, &out.instructions, instruction);
        },
    };
    return out;
}
const Detail = struct { predicted: i64 = 0, miss: ?usize = null };
const Prediction = struct {
    details: []Detail,
    flags: []bool,
    bits: usize,
    control: i64 = 0,
    total_misses: i64 = 0,
    hits: i64 = 0,
    calls: i64 = 0,
    returns: i64 = 0,
    ras_predictions: i64 = 0,
    ras_correct: i64 = 0,
    count: [2]i64 = .{ 0, 0 },
    wrong: [2]i64 = .{ 0, 0 },
    kinds: [3]i64 = .{ 0, 0, 0 },
};
fn predict(instructions: []const c.Instruction, definition: c.Predictor, config: c.Config) Prediction {
    var btb = predictors.BTB.init(config.btb);
    var ras: predictors.RAS = .{ .depth = config.ras };
    var direction = predictors.Direction.init(definition);
    var out: Prediction = .{ .details = c.alloc(Detail, instructions.len), .flags = c.alloc(bool,
         instructions.len), .bits = direction.bits() };
    @memset(out.details, .{});
    @memset(out.flags, false);
    for (instructions, 0..) |instruction, index| {
        if (!instruction.control()) continue;
        var candidate = btb.lookup(instruction.pc);
        out.control += 1;
        out.hits += @intFromBool(candidate != null);
        const call = instruction.kind == .jump and instruction.rd == 31;
        const ret = instruction.kind == .jump and instruction.rd < 0 and instruction.rs1 == 31;
        out.calls += @intFromBool(call);
        out.returns += @intFromBool(ret);
        if (ret) if (ras.pop()) |address| {
            candidate = address;
            out.ras_predictions += 1;
            out.ras_correct += @intFromBool(address == instruction.target);
        };
        if (call) ras.push(instruction.pc + 4);
        const taken = if (instruction.kind == .branch) direction.prediction(instruction.pc,
             instruction.target) else true;
        const next = if (c.eq(definition.scheme, "PERFECT")) instruction.next else if ((instruction.kind == .jump or taken) and candidate != null) candidate.? else instruction.pc + 4;
        out.details[index].predicted = next;
        if (next != instruction.next) {
            const miss: usize = if (instruction.kind == .branch and taken != instruction.taken) 0 else if (candidate == null) 1 else 2;
            out.details[index].miss = miss;
            out.kinds[miss] += 1;
            out.total_misses += 1;
            out.flags[index] = true;
        }
        const kind: usize = if (instruction.kind == .branch) 0 else 1;
        out.count[kind] += 1;
        out.wrong[kind] += @intFromBool(out.flags[index]);
        if (instruction.kind == .branch) direction.update(instruction.pc, instruction.taken);
        if (instruction.taken) btb.insert(instruction.pc, instruction.target);
    }
    return out;
}
const CellSegment = struct { first: i64, last: i64, mark: u8, stage: ?usize };
const Diagram = struct {
    lines: c.Lines = .{},
    occupancy: [5][2]i64 = [_][2]i64{.{ 0, 0 }} ** 5,
    flushed: i64 = 0,
    rows: i64 = 0,
    stall_cells: i64 = 0,
    flushed_cells: i64 = 0,
    completed: i64 = 0,
    contents: [][5][]const u8,
    fn add(self: *Diagram, config: c.Config, number: ?usize, pc: i64, kind: []const u8, segments: []const CellSegment,
         annotation: []const u8) void {
        const cells = c.alloc(u8, c.u(config.end - config.start + 1));
        @memset(cells, '.');
        var present = false;
        for (segments) |segment| {
            if (segment.last < segment.first) continue;
            if (segment.stage) |stage| self.occupancy[stage][@intFromBool(number == null)] += segment.last - segment.first + 1;
            var cycle = @max(config.start, segment.first);
            while (cycle <= @min(config.end, segment.last)) : (cycle += 1) {
                cells[c.u(cycle - config.start)] = segment.mark;
                present = true;
                self.stall_cells += @intFromBool(segment.mark == '*');
                self.flushed_cells += @intFromBool(segment.mark == 'x');
                if (segment.stage) |stage| self.contents[c.u(cycle - config.start)][stage] = if (number) |value| c.fmt("{d}",
                     .{value}) else "w";
            }
        }
        if (present) {
            self.lines.add("{s}", .{r.diagramRow(number, pc, kind, cells, annotation)});
            self.rows += 1;
        }
    }
};
fn diagram(instructions: []const c.Instruction, run: pipeline.Run, variant: c.Variant, prediction: Prediction,
     config: c.Config) Diagram {
    var out: Diagram = .{ .contents = c.alloc([5][]const u8, c.u(config.end - config.start + 1)) };
    for (out.contents) |*row| row.* = .{ ".", ".", ".", ".", "." };
    out.lines.add("pipeline variant={s} predictor={s} cycles {d}-{d}", .{ variant.name, config.primary_predictor,
         config.start, config.end });
    out.lines.add("{s}", .{r.cycleHeading(config.start, config.end)});
    const annotations = c.alloc(c.Text, instructions.len);
    @memset(annotations, .{});
    for (run.records) |record| if (record.waiting) |waiting| annotations[waiting].add(" {s} {d}",
         .{ c.causes[record.cause], record.cycles });
    for (instructions, run.timings, 0..) |instruction, t, i| {
        if (prediction.flags[i]) annotations[i].add(" mispredict {s}", .{c.miss_names[prediction.details[i].miss.?]});
        out.add(config, i + 1, instruction.pc, c.classes[@intFromEnum(instruction.kind)], &.{
            .{ .first = t.f, .last = t.f, .mark = 'F', .stage = 0 },     .{ .first = t.f + 1,
                 .last = t.d - 1, .mark = '*', .stage = 0 },
            .{ .first = t.d, .last = t.d, .mark = 'D', .stage = 1 },     .{ .first = t.d + 1,
                 .last = t.x - 1, .mark = '*', .stage = 1 },
            .{ .first = t.x, .last = t.m - 1, .mark = 'X', .stage = 2 }, .{ .first = t.m, .last = t.m,
                 .mark = 'M', .stage = 3 },
            .{ .first = t.w, .last = t.w, .mark = 'W', .stage = 4 },
        }, annotations[i].value());
        out.completed += @intFromBool(t.w >= config.start and t.w <= config.end);
        if (!prediction.flags[i]) continue;
        const early = h.idResolved(instruction, variant);
        const pc = prediction.details[i].predicted;
        const first = [_]CellSegment{
            .{ .first = t.d, .last = t.d, .mark = 'F', .stage = 0 },                                          .{ .first = t.d + 1,
                 .last = t.x - 1, .mark = '*', .stage = 0 },
            .{ .first = t.x, .last = t.x, .mark = if (early) 'x' else 'D', .stage = if (early) null else 1 },
                 .{ .first = t.x + 1, .last = t.x + 1, .mark = 'x', .stage = null },
        };
        out.add(config, null, pc, "FLUSH", first[0..if (early) @as(usize, 3) else 4], "");
        out.flushed += 1;
        if (!early) {
            out.add(config, null, pc + 4, "FLUSH", &.{ .{ .first = t.x, .last = t.x, .mark = 'F',
                 .stage = 0 }, .{ .first = t.x + 1, .last = t.x + 1, .mark = 'x', .stage = null } },
                 "");
            out.flushed += 1;
        }
    }
    out.lines.add("rows {d} completed {d} stall_cells {d} flushed {d}", .{ out.rows, out.completed,
         out.stall_cells, out.flushed_cells });
    out.lines.add("", .{});
    out.lines.add("stages", .{});
    out.lines.add("cycle IF ID EX MEM WB", .{});
    for (out.contents, 0..) |row, i| out.lines.add("{d} {s} {s} {s} {s} {s}", .{ config.start + c.n(i),
         row[0], row[1], row[2], row[3], row[4] });
    return out;
}
const Combination = struct { variant: usize, predictor: usize, cycles: i64, stalls: [4]i64 };
const Summary = struct { cycles: i64, stalls: [4]i64 };
fn scratchSummary(backing: std.mem.Allocator, instructions: []const c.Instruction, sources: []const h.Sources,
     variant: c.Variant, flags: []const bool) Summary {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const previous = c.allocator;
    c.allocator = scratch.allocator();
    defer c.allocator = previous;
    const run = pipeline.simulate(instructions, sources, variant, flags);
    return .{ .cycles = run.cycles, .stalls = run.stalls };
}
const StaticRef = struct {
    pc: i64,
    id: usize,
    fn less(_: void, a: StaticRef, b: StaticRef) bool {
        return a.pc < b.pc;
    }
};
const Hotspot = struct {
    pc: i64,
    total: i64,
    stalls: [4]i64,
    kind: c.Class,
    fn less(_: void, a: Hotspot, b: Hotspot) bool {
        return if (a.total != b.total) a.total > b.total else a.pc < b.pc;
    }
};
const Dependency = struct {
    producer: i64,
    waiting: i64,
    cause: usize,
    cycles: i64,
    events: i64,
    producer_kind: c.Class,
    waiting_kind: c.Class,
    fn keyLess(_: void, a: Dependency, b: Dependency) bool {
        if (a.producer != b.producer) return a.producer < b.producer;
        if (a.waiting != b.waiting) return a.waiting < b.waiting;
        return a.cause < b.cause;
    }
    fn less(_: void, a: Dependency, b: Dependency) bool {
        return if (a.cycles != b.cycles) a.cycles > b.cycles else keyLess({}, a, b);
    }
    fn equal(a: Dependency, b: Dependency) bool {
        return a.producer == b.producer and a.waiting == b.waiting and a.cause == b.cause;
    }
};
const ProfileSegment = struct {
    pc: i64 = 0,
    instances: i64 = 0,
    instructions: i64 = 0,
    cycles: i64 = 0,
    fn less(_: void, a: ProfileSegment, b: ProfileSegment) bool {
        return if (a.cycles != b.cycles) a.cycles > b.cycles else a.pc < b.pc;
    }
};
const Target = struct {
    target: i64,
    count: i64,
    fn less(_: void, a: Target, b: Target) bool {
        return if (a.count != b.count) a.count > b.count else a.target < b.target;
    }
};
fn sum4(values: [4]i64) i64 {
    return values[0] + values[1] + values[2] + values[3];
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    const io = init.io;
    try std.Io.Dir.cwd().createDirPath(io, "output");
    const input = try c.load(io);
    const config = input.config;
    const trace = validate(input.trace);
    const instructions = trace.instructions.items;
    const n = instructions.len;
    const sources = h.dependencies(instructions);
    const predictions = c.alloc(Prediction, config.predictors.items.len);
    var primary_predictor: usize = 0;
    var primary_variant: usize = 0;
    for (config.predictors.items, 0..) |definition, p| {
        predictions[p] = predict(instructions, definition, config);
        if (c.eq(definition.name, config.primary_predictor)) primary_predictor = p;
    }
    for (config.variants.items, 0..) |variant, v| if (c.eq(variant.name, config.primary_variant)) {
        primary_variant = v;
    };
    var combinations: std.ArrayList(Combination) = .empty;
    var table = [_][8]i64{[_]i64{0} ** 8} ** 8;
    var primary: pipeline.Run = undefined;
    for (config.variants.items, 0..) |variant, v| for (predictions, 0..) |prediction, p| {
        var summary: Summary = undefined;
        if (v == primary_variant and p == primary_predictor) {
            primary = pipeline.simulate(instructions, sources, variant, prediction.flags);
            summary = .{ .cycles = primary.cycles, .stalls = primary.stalls };
        } else summary = scratchSummary(init.gpa, instructions, sources, variant, prediction.flags);
        table[v][p] = summary.cycles;
        c.append(Combination, &combinations, .{ .variant = v, .predictor = p, .cycles = summary.cycles,
             .stalls = summary.stalls });
    };
    const variant = config.variants.items[primary_variant];
    const prediction = predictions[primary_predictor];
    const cycles = primary.cycles;
    const picture = diagram(instructions, primary, variant, prediction, config);
    try r.save(io, "pipeline.txt", picture.lines);
    var mix = [_]i64{0} ** 7;
    var class_stalls = [_]i64{0} ** 7;
    var distances = [_]i64{0} ** 5;
    var lengths = [_]i64{0} ** 5;
    var paths = [_]i64{0} ** 3;
    var taken: i64 = 0;
    var backward: i64 = 0;
    var indirect: i64 = 0;
    var link: i64 = 0;
    var operands: i64 = 0;
    var produced: i64 = 0;
    var height: i64 = 0;
    var addresses: std.AutoHashMapUnmanaged(i64, void) = .empty;
    const finish = c.alloc(i64, n);
    for (instructions, 0..) |instruction, i| {
        mix[@intFromEnum(instruction.kind)] += 1;
        if (instruction.kind == .branch) {
            taken += @intFromBool(instruction.taken);
            backward += @intFromBool(instruction.target < instruction.pc);
        }
        if (instruction.kind == .jump) {
            indirect += @intFromBool(instruction.rs1 >= 0);
            link += @intFromBool(instruction.rd >= 0);
        }
        if (instruction.kind == .load or instruction.kind == .store) addresses.put(c.allocator,
             instruction.address, {}) catch @panic("allocation failed");
        const registers = [_]i64{ instruction.rs1, instruction.rs2 };
        var start: i64 = 0;
        for (registers, 0..) |register, j| if (register > 0) {
            operands += 1;
            const p = sources[i][j];
            if (p) |producer| {
                produced += 1;
                distances[@min(5, i - producer) - 1] += 1;
                start = @max(start, finish[producer]);
            }
            paths[h.forwardingPath(instruction, if (p) |producer| primary.timings[producer] else null,
                 primary.timings[i], variant)] += 1;
        };
        finish[i] = start + (if (instruction.kind == .load) @as(i64, 2) else if (instruction.kind == .multiply) variant.latency else 1);
        height = @max(height, finish[i]);
        if (i > 0) {
            const delay = primary.timings[i].x - primary.timings[i - 1].x - 1;
            if (delay > 0) lengths[c.u(@min(5, delay) - 1)] += 1;
        }
    }
    var dependencies_rank: std.ArrayList(Dependency) = .empty;
    for (primary.records) |record| {
        const responsible = instructions[record.responsible];
        class_stalls[@intFromEnum(responsible.kind)] += record.cycles;
        trace.statics.items[responsible.static_id].stalls[record.cause] += record.cycles;
        if (record.cause >= 2) {
            const producer = instructions[record.producer.?];
            const waiting = instructions[record.waiting.?];
            c.append(Dependency, &dependencies_rank, .{ .producer = producer.pc, .waiting = waiting.pc,
                 .cause = record.cause, .cycles = record.cycles, .events = 1, .producer_kind = producer.kind,
                 .waiting_kind = waiting.kind });
        }
    }
    std.mem.sort(Dependency, dependencies_rank.items, {}, Dependency.keyLess);
    var grouped: usize = 0;
    for (0..dependencies_rank.items.len) |i| {
        const value = dependencies_rank.items[i];
        if (grouped > 0 and Dependency.equal(dependencies_rank.items[grouped - 1], value)) {
            dependencies_rank.items[grouped - 1].cycles += value.cycles;
            dependencies_rank.items[grouped - 1].events += value.events;
        } else {
            dependencies_rank.items[grouped] = value;
            grouped += 1;
        }
    }
    dependencies_rank.items = dependencies_rank.items[0..grouped];
    std.mem.sort(Dependency, dependencies_rank.items, {}, Dependency.less);
    const statics = c.alloc(StaticRef, trace.statics.items.len);
    var hotspots: std.ArrayList(Hotspot) = .empty;
    var static_branches: i64 = 0;
    var static_jumps: i64 = 0;
    for (trace.statics.items, 0..) |group, id| {
        const instruction = instructions[group.first];
        statics[id] = .{ .pc = instruction.pc, .id = id };
        static_branches += @intFromBool(instruction.kind == .branch);
        static_jumps += @intFromBool(instruction.kind == .jump);
        if (sum4(group.stalls) > 0) c.append(Hotspot, &hotspots, .{ .pc = instruction.pc, .total = sum4(group.stalls),
             .stalls = group.stalls, .kind = instruction.kind });
    }
    std.mem.sort(StaticRef, statics, {}, StaticRef.less);
    std.mem.sort(Hotspot, hotspots.items, {}, Hotspot.less);
    var stats: c.Lines = .{};
    stats.add("input lines {d} accepted {d} rejected {d} gaps {d}", .{ input.trace.len, n,
         trace.rejected.items.len, trace.gaps.items.len });
    for (trace.rejected.items) |value| stats.add("reject line {d} {s}", .{ value.line, value.reason });
    for (trace.gaps.items) |value| stats.add("gap line {d} expected {s} found {s}", .{ value.line,
         r.hexadecimal(value.expected), r.hexadecimal(value.found) });
    stats.add("", .{});
    stats.add("trace", .{});
    stats.add("instructions {d}", .{n});
    stats.add("static_instructions {d}", .{statics.len});
    var mix_line: c.Text = .{};
    mix_line.add("mix", .{});
    for (c.classes, mix) |name, value| mix_line.add(" {s} {d}", .{ name, value });
    stats.add("{s}", .{mix_line.value()});
    stats.add("branches {d} taken {d} backward {d}", .{ mix[4], taken, backward });
    stats.add("jumps {d} indirect {d} link {d}", .{ mix[5], indirect, link });
    stats.add("static_control branches {d} jumps {d}", .{ static_branches, static_jumps });
    stats.add("memory loads {d} stores {d} distinct_addresses {d}", .{ mix[2], mix[3], addresses.count() });
    stats.add("operands {d} with_producer {d} distance 1 {d} 2 {d} 3 {d} 4 {d} 5+ {d}", .{ operands,
         produced, distances[0], distances[1], distances[2], distances[3], distances[4] });
    stats.add("", .{});
    stats.add("prediction", .{});
    for (predictions, config.predictors.items) |value, definition| stats.add("{s} {s} bits {d} control {d} mispredicted {d} accuracy {s} branches {s} jumps {s} direction {d} btb_miss {d} wrong_target {d}",
         .{ definition.name, definition.scheme, value.bits, value.control, value.total_misses,
         r.percentage(value.control - value.total_misses, value.control), r.percentage(value.count[0] - value.wrong[0],
         value.count[0]), r.percentage(value.count[1] - value.wrong[1], value.count[1]), value.kinds[0],
         value.kinds[1], value.kinds[2] });
    stats.add("btb entries {d} lookups {d} hits {d} misses {d}", .{ config.btb, prediction.control,
         prediction.hits, prediction.control - prediction.hits });
    stats.add("ras depth {d} calls {d} returns {d} predicted {d} correct {d}", .{ config.ras,
         prediction.calls, prediction.returns, prediction.ras_predictions, prediction.ras_correct });
    stats.add("", .{});
    stats.add("timing variant={s} predictor={s}", .{ variant.name, config.primary_predictor });
    stats.add("forwarding {s} branch_stage {s} mul_latency {d}", .{ if (variant.forwarding) "on" else "off",
         if (variant.id) "ID" else "EX", variant.latency });
    stats.add("cycles {d}", .{cycles});
    stats.add("cpi {s} {s}", .{ r.fraction(cycles, c.n(n)), r.decimal(cycles, c.n(n)) });
    stats.add("ipc {s}", .{r.decimal(c.n(n), cycles)});
    const total_stalls = sum4(primary.stalls);
    stats.add("stall_cycles total {d} control {d} structural {d} load_use {d} raw {d}", .{ total_stalls,
         primary.stalls[0], primary.stalls[1], primary.stalls[2], primary.stalls[3] });
    stats.add("stall_events control {d} structural {d} load_use {d} raw {d}", .{ primary.events[0],
         primary.events[1], primary.events[2], primary.events[3] });
    stats.add("flushed {d}", .{picture.flushed});
    stats.add("cycle_check {d} + 4 + {d} = {d}", .{ n, total_stalls, c.n(n) + 4 + total_stalls });
    stats.add("cpi_stack base 1.0000 fill {s} control {s} structural {s} load_use {s} raw {s}",
         .{ r.decimal(4, c.n(n)), r.decimal(primary.stalls[0], c.n(n)), r.decimal(primary.stalls[1],
         c.n(n)), r.decimal(primary.stalls[2], c.n(n)), r.decimal(primary.stalls[3], c.n(n)) });
    stats.add("stall_lengths 1 {d} 2 {d} 3 {d} 4 {d} 5+ {d}", .{ lengths[0], lengths[1], lengths[2],
         lengths[3], lengths[4] });
    stats.add("dataflow height {d} ilp {s}", .{ height, r.decimal(c.n(n), height) });
    stats.add("", .{});
    stats.add("whatif", .{});
    const perfect = c.alloc(bool, n);
    @memset(perfect, false);
    for (0..4) |change| {
        var modified = variant;
        var flags: []const bool = prediction.flags;
        var name: []const u8 = undefined;
        if (change == 0) {
            name = "perfect_prediction";
            flags = perfect;
        } else if (change == 1) {
            name = "single_cycle_mul";
            modified.latency = 1;
        } else if (change == 2) {
            name = if (variant.forwarding) "forwarding_off" else "forwarding_on";
            modified.forwarding = !variant.forwarding;
        } else {
            name = if (variant.id) "branch_stage_EX" else "branch_stage_ID";
            modified.id = !variant.id;
        }
        const summary = scratchSummary(init.gpa, instructions, sources, modified, flags);
        stats.add("{s} cycles {d} saved {d} speedup {s}", .{ name, summary.cycles, cycles - summary.cycles,
             r.decimal(cycles, summary.cycles) });
    }
    stats.add("", .{});
    stats.add("classes", .{});
    for (c.classes, 0..) |name, i| stats.add("{s} count {d} stall_cycles {d} per_instruction {s}",
         .{ name, mix[i], class_stalls[i], if (mix[i] > 0) r.decimal(class_stalls[i], mix[i]) else "-" });
    stats.add("", .{});
    stats.add("forwarding regfile {d} ex_mem {d} mem_wb {d}", .{ paths[0], paths[1], paths[2] });
    stats.add("", .{});
    stats.add("occupancy cycles {d}", .{cycles});
    for (c.stages, picture.occupancy) |name, value| stats.add("{s} correct {d} wrong {d} idle {d} busy {s}",
         .{ name, value[0], value[1], cycles - value[0] - value[1], r.percentage(value[0] + value[1],
         cycles) });
    stats.add("", .{});
    stats.add("hotspots", .{});
    for (hotspots.items[0..@min(config.top, hotspots.items.len)], 0..) |value, i| stats.add("{d} {s} {s} stall_cycles {d} control {d} structural {d} load_use {d} raw {d}",
         .{ i + 1, r.hexadecimal(value.pc), c.classes[@intFromEnum(value.kind)], value.total,
         value.stalls[0], value.stalls[1], value.stalls[2], value.stalls[3] });
    stats.add("", .{});
    stats.add("dependencies total {d}", .{dependencies_rank.items.len});
    for (dependencies_rank.items[0..@min(config.top, dependencies_rank.items.len)], 0..) |value,
         i| stats.add("{d} {s} {s} -> {s} {s} {s} stall_cycles {d} events {d}", .{ i + 1, r.hexadecimal(value.producer),
         c.classes[@intFromEnum(value.producer_kind)], r.hexadecimal(value.waiting), c.classes[@intFromEnum(value.waiting_kind)],
         c.causes[value.cause], value.cycles, value.events });
    stats.add("", .{});
    stats.add("intervals size {d}", .{config.interval});
    var a: usize = 0;
    while (a < n) : (a += config.interval) {
        const b = @min(n, a + config.interval) - 1;
        const count = primary.timings[b].w - (if (a > 0) primary.timings[a - 1].w else @as(i64, 0));
        stats.add("{d}-{d} cycles {d} cpi {s}", .{ a + 1, b + 1, count, r.decimal(count, c.n(b - a + 1)) });
    }
    stats.add("", .{});
    var heading: c.Text = .{};
    heading.add("cycles_table", .{});
    for (config.predictors.items) |definition| heading.add(" {s}", .{definition.name});
    stats.add("{s}", .{heading.value()});
    for (config.variants.items, 0..) |definition, v| {
        var row: c.Text = .{};
        row.add("{s}", .{definition.name});
        for (table[v][0..predictions.len]) |value| row.add(" {d}", .{value});
        stats.add("{s}", .{row.value()});
    }
    try r.save(io, "stats.txt", stats);
    var branches: c.Lines = .{};
    branches.add("predictor,pc,class,executions,taken,mispredictions,accuracy", .{});
    for (predictions, config.predictors.items) |value, definition| for (statics) |reference| {
        const group = trace.statics.items[reference.id];
        const instruction = instructions[group.first];
        if (!instruction.control()) continue;
        var wrong: i64 = 0;
        for (group.indices.items) |i| {
            wrong += @intFromBool(value.flags[i]);
        }
        branches.add("{s},{s},{s},{d},{d},{d},{s}", .{ definition.name, r.hexadecimal(instruction.pc),
             c.classes[@intFromEnum(instruction.kind)], group.indices.items.len, group.taken,
             wrong, r.percentage(c.n(group.indices.items.len) - wrong, c.n(group.indices.items.len)) });
    };
    try r.save(io, "branches.csv", branches);
    const Compare = struct {
        fn less(ctx: c.Config, x: Combination, y: Combination) bool {
            if (x.cycles != y.cycles) return x.cycles < y.cycles;
            const order = std.mem.order(u8, ctx.variants.items[x.variant].name, ctx.variants.items[y.variant].name);
            return if (order != .eq) order == .lt else std.mem.lessThan(u8, ctx.predictors.items[x.predictor].name,
                 ctx.predictors.items[y.predictor].name);
        }
    };
    std.mem.sort(Combination, combinations.items, config, Compare.less);
    var comparison: c.Lines = .{};
    comparison.add("rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw",
         .{});
    for (combinations.items, 0..) |value, i| {
        const p = predictions[value.predictor];
        comparison.add("{d},{s},{s},{d},{s},{s},{s},{d},{d},{d},{d},{d}", .{ i + 1, config.variants.items[value.variant].name,
             config.predictors.items[value.predictor].name, value.cycles, r.decimal(value.cycles,
             c.n(n)), r.decimal(cycles, value.cycles), r.percentage(p.control - p.total_misses,
             p.control), p.total_misses, value.stalls[0], value.stalls[1], value.stalls[2],
             value.stalls[3] });
    }
    try r.save(io, "comparison.csv", comparison);
    var profile: c.Lines = .{};
    profile.add("branches", .{});
    for (statics) |reference| {
        const group = trace.statics.items[reference.id];
        const instruction = instructions[group.first];
        if (instruction.kind != .branch) continue;
        var transitions: i64 = 0;
        var run_length: i64 = 0;
        var longest = [_]i64{ 0, 0 };
        var previous = false;
        for (group.indices.items) |i| {
            const value = instructions[i].taken;
            if (run_length > 0 and value != previous) {
                transitions += 1;
                run_length = 0;
            }
            run_length += 1;
            longest[@intFromBool(value)] = @max(longest[@intFromBool(value)], run_length);
            previous = value;
        }
        var best_misses = c.n(group.indices.items.len) + 1;
        var best: usize = 0;
        for (predictions, config.predictors.items, 0..) |value, definition, p| if (!c.eq(definition.scheme,
             "PERFECT")) {
            var wrong: i64 = 0;
            for (group.indices.items) |i| {
                wrong += @intFromBool(value.flags[i]);
            }
            if (wrong < best_misses) {
                best_misses = wrong;
                best = p;
            }
        };
        profile.add("{s} {s} executions {d} taken {d} transitions {d} longest_taken {d} longest_not_taken {d} best {s} {d}",
             .{ r.hexadecimal(instruction.pc), if (instruction.target < instruction.pc) "backward" else "forward",
             group.indices.items.len, group.taken, transitions, longest[1], longest[0], config.predictors.items[best].name,
             best_misses });
    }
    profile.add("", .{});
    profile.add("loops", .{});
    for (statics) |reference| {
        const group = trace.statics.items[reference.id];
        const instruction = instructions[group.first];
        if (instruction.kind != .branch or instruction.target >= instruction.pc) continue;
        var entries: i64 = 0;
        var longest: i64 = 0;
        var length: i64 = 0;
        for (group.indices.items) |i| {
            length += 1;
            if (!instructions[i].taken) {
                entries += 1;
                longest = @max(longest, length);
                length = 0;
            }
        }
        if (length > 0) {
            entries += 1;
            longest = @max(longest, length);
        }
        profile.add("{s}-{s} body {d} entries {d} iterations {d} avg_trip {s} max_trip {d}",
             .{ r.hexadecimal(instruction.target), r.hexadecimal(instruction.pc), @divTrunc(instruction.pc - instruction.target,
             4) + 1, entries, group.indices.items.len, r.decimal(c.n(group.indices.items.len),
             entries), longest });
    }
    const segment_groups = c.alloc(ProfileSegment, statics.len);
    @memset(segment_groups, .{});
    a = 0;
    while (a < n) {
        var b = a;
        while (b < n - 1 and !instructions[b].control()) : (b += 1) {}
        const group = &segment_groups[instructions[a].static_id];
        group.pc = instructions[a].pc;
        group.instances += 1;
        group.instructions += c.n(b - a + 1);
        group.cycles += primary.timings[b].w - (if (a > 0) primary.timings[a - 1].w else @as(i64, 0));
        a = b + 1;
    }
    var segments_rank: std.ArrayList(ProfileSegment) = .empty;
    for (segment_groups) |group| if (group.instances > 0) c.append(ProfileSegment, &segments_rank, group);
    std.mem.sort(ProfileSegment, segments_rank.items, {}, ProfileSegment.less);
    profile.add("", .{});
    profile.add("segments total {d}", .{segments_rank.items.len});
    for (segments_rank.items[0..@min(config.top, segments_rank.items.len)], 0..) |value, i| profile.add("{d} {s} instances {d} instructions {d} cycles {d} cpi {s}",
         .{ i + 1, r.hexadecimal(value.pc), value.instances, value.instructions, value.cycles,
         r.decimal(value.cycles, value.instructions) });
    profile.add("", .{});
    profile.add("indirect", .{});
    for (statics) |reference| {
        const group = trace.statics.items[reference.id];
        const instruction = instructions[group.first];
        if (instruction.kind != .jump or instruction.rs1 < 0) continue;
        const values = c.alloc(i64, group.indices.items.len);
        for (group.indices.items, values) |i, *value| value.* = instructions[i].target;
        std.mem.sort(i64, values, {}, std.sort.asc(i64));
        var targets: std.ArrayList(Target) = .empty;
        for (values, 0..) |value, i| {
            if (i == 0 or value != values[i - 1]) c.append(Target, &targets, .{ .target = value,
                 .count = 1 }) else targets.items[targets.items.len - 1].count += 1;
        }
        std.mem.sort(Target, targets.items, {}, Target.less);
        var tail: c.Text = .{};
        for (targets.items) |value| tail.add(" {s}:{d}", .{ r.hexadecimal(value.target), value.count });
        profile.add("{s} executions {d} distinct {d} targets{s}", .{ r.hexadecimal(instruction.pc),
             group.indices.items.len, targets.items.len, tail.value() });
    }
    profile.add("", .{});
    profile.add("instructions", .{});
    for (statics) |reference| {
        const group = trace.statics.items[reference.id];
        const instruction = instructions[group.first];
        profile.add("{s} {s} {s} {s} {s} executions {d} stall_cycles {d}", .{ r.hexadecimal(instruction.pc),
             c.classes[@intFromEnum(instruction.kind)], r.register(instruction.rd), r.register(instruction.rs1),
             r.register(instruction.rs2), group.indices.items.len, sum4(group.stalls) });
    }
    try r.save(io, "profile.txt", profile);
}
