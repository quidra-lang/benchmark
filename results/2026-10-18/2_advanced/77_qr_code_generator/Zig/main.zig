const std = @import("std");
const b = @import("bitstream.zig");
const rs = @import("reed_solomon.zig");
const matrix = @import("matrix.zig");
const masking = @import("masking.zig");
const render = @import("render.zig");
const Matrix = matrix.Matrix;
const Words = b.Words;
const modes = [_][]const u8{ "NUMERIC", "ALPHANUMERIC", "BYTE" };
const levels = "LMQH";
const error_kinds = [_][]const u8{ "level", "mode", "version", "mask", "text", "charset", "capacity" };
fn countWidth(mode: usize, version: i64) i64 {
    const widths = [2][3]i64{ .{ 10, 9, 8 }, .{ 12, 11, 16 } };
    return widths[@intFromBool(version == 10)][mode];
}
fn dataWidth(mode: usize, count: i64) i64 {
    const remainder = [_]i64{ 0, 4, 7 };
    return if (mode == 0) 10 * @divTrunc(count, 3) + remainder[b.u(@mod(count, 3))] else if (mode == 1) 11 * @divTrunc(count,
         2) + 6 * @mod(count, 2) else 8 * count;
}
fn encodable(mode: usize, character: u8) bool {
    return if (mode == 0) character >= '0' and character <= '9' else if (mode == 1) std.mem.indexOfScalar(u8,
         b.alphanumeric, character) != null else character >= 32 and character <= 126;
}
fn encodableText(mode: usize, source: []const u8) bool {
    for (source) |character| if (!encodable(mode, character)) return false;
    return true;
}
fn segmentWidth(mode: usize, count: i64, version: i64) i64 {
    return 4 + countWidth(mode, version) + dataWidth(mode, count);
}
const Segment = struct { mode: usize, characters: []const u8 };
const Split = struct { segments: []const Segment, bits: i64 };
fn mixedSegments(source: []const u8, version: i64) Split {
    var invalid: [3][401]i64 = std.mem.zeroes([3][401]i64);
    var costs: [401]i64 = @splat(0);
    var starts: [401]usize = @splat(0);
    var choices: [401]usize = @splat(0);
    for (source, 0..) |character, i| for (0..3) |mode| {
        invalid[mode][i + 1] = invalid[mode][i] + @intFromBool(!encodable(mode, character));
    };
    for (1..source.len + 1) |end| {
        costs[end] = 1000000;
        for (0..end) |start| for (0..3) |mode| if (invalid[mode][end] == invalid[mode][start]) {
            const cost = costs[start] + segmentWidth(mode, b.n(end - start), version);
            if (cost < costs[end]) {
                costs[end] = cost;
                starts[end] = start;
                choices[end] = mode;
            }
        };
    }
    var segments: std.ArrayList(Segment) = .empty;
    var end = source.len;
    while (end > 0) {
        b.append(Segment, &segments, .{ .mode = choices[end], .characters = source[starts[end]..end] });
        end = starts[end];
    }
    std.mem.reverse(Segment, segments.items);
    return .{ .segments = segments.items, .bits = costs[source.len] };
}
const Padding = struct { bits: []const u8, terminator: i64, zero_fill: i64, pad_bytes: i64 };
fn padBits(bits: []const u8, capacity: i64) Padding {
    var writer: b.BitWriter = .{};
    writer.data.appendSlice(b.allocator, bits) catch @panic("allocation failed");
    const terminator = @min(@as(i64, 4), capacity - b.n(bits.len));
    writer.write(0, terminator);
    const zero_fill = @mod(8 - @mod(b.n(writer.bits().len), 8), 8);
    writer.write(0, zero_fill);
    const pad_bytes = @divTrunc(capacity - b.n(writer.bits().len), 8);
    for (0..b.u(pad_bytes)) |i| writer.write(if (i % 2 == 0) 0xec else 0x11, 8);
    return .{ .bits = writer.bits(), .terminator = terminator, .zero_fill = zero_fill, .pad_bytes = pad_bytes };
}
const Placement = struct { block: usize, position: usize };
const BlockLayout = struct {
    degree: i64,
    data: i64,
    capacity: i64,
    total: i64,
    lengths: Words,
    placement: []const Placement,
    fn init(degree: i64, b1: i64, k1: i64, b2: i64, k2: i64) BlockLayout {
        var lengths: std.ArrayList(i64) = .empty;
        for (0..b.u(b1)) |_| b.append(i64, &lengths, k1);
        for (0..b.u(b2)) |_| b.append(i64, &lengths, k2);
        var data: i64 = 0;
        var maximum: i64 = 0;
        for (lengths.items) |length| {
            data += length;
            maximum = @max(maximum, length);
        }
        var placement: std.ArrayList(Placement) = .empty;
        for (0..b.u(maximum)) |i| for (lengths.items, 0..) |length, block| if (b.n(i) < length) b.append(Placement,
             &placement, .{ .block = block, .position = i });
        for (0..b.u(degree)) |i| for (lengths.items, 0..) |length, block| b.append(Placement,
             &placement, .{ .block = block, .position = b.u(length) + i });
        return .{ .degree = degree, .data = data, .capacity = 8 * data, .total = data + degree * b.n(lengths.items.len),
             .lengths = lengths.items, .placement = placement.items };
    }
    fn deinterleave(self: BlockLayout, codewords: Words) [][]i64 {
        const blocks = b.alloc([]i64, self.lengths.len);
        for (self.lengths, 0..) |length, i| {
            blocks[i] = b.alloc(i64, b.u(length + self.degree));
            @memset(blocks[i], 0);
        }
        for (self.placement, codewords) |place, value| blocks[place.block][place.position] = value;
        return blocks;
    }
};
const Attempt = struct { lines: b.Lines = .{}, decoded: ?[]const u8 = null, blocks: [3]i64 = @splat(0),
     corrected_positions: i64 = 0 };
fn rotate(symbol: *const Matrix) Matrix {
    var out: Matrix = .{ .size = symbol.size };
    for (0..b.u(out.size)) |y| for (0..b.u(out.size)) |x| out.set(b.n(x), b.n(y), symbol.at(b.n(y),
         out.size - 1 - b.n(x)));
    return out;
}
fn transpose(symbol: *const Matrix) Matrix {
    var out: Matrix = .{ .size = symbol.size };
    for (0..b.u(out.size)) |y| for (0..b.u(out.size)) |x| out.set(b.n(x), b.n(y), symbol.at(b.n(y), b.n(x)));
    return out;
}
fn finderRotation(symbol: *const Matrix) usize {
    const n = symbol.size;
    const corners = [_]matrix.Point{ .{ .x = n - 7, .y = n - 7 }, .{ .x = n - 7, .y = 0 },
         .{ .x = 0, .y = 0 }, .{ .x = 0, .y = n - 7 } };
    var best: i64 = 100;
    var chosen: usize = 0;
    for (corners, 0..) |corner, k| {
        var score: i64 = 0;
        for (0..7) |y| for (0..7) |x| {
            const expected: u8 = @intFromBool(@max(@abs(b.n(x) - 3), @abs(b.n(y) - 3)) != 2);
            score += @intFromBool(symbol.at(corner.x + b.n(x), corner.y + b.n(y)) == expected);
        };
        if (score < best) {
            best = score;
            chosen = k;
        }
    }
    return chosen;
}
fn parseData(attempt: *Attempt, bits: []const u8, version: i64) void {
    var reader: b.BitReader = .{ .bits = bits };
    var decoded: b.Text = .{};
    var end: usize = 0;
    while (reader.remaining() >= 4) {
        const indicator = reader.read(4);
        if (indicator == 0) break;
        const mode: usize = switch (indicator) {
            1 => 0,
            2 => 1,
            4 => 2,
            else => {
                attempt.lines.add("parse failed indicator {s}", .{b.binary(indicator, 4)});
                return;
            },
        };
        const width = countWidth(mode, version);
        if (reader.remaining() < width) {
            attempt.lines.add("parse failed length {s}", .{modes[mode]});
            return;
        }
        const count = reader.read(width);
        if (reader.remaining() < dataWidth(mode, count)) {
            attempt.lines.add("parse failed length {s}", .{modes[mode]});
            return;
        }
        var remaining = count;
        while (remaining > 0) {
            const group = @min(@as(i64, if (mode == 0) 3 else if (mode == 1) 2 else 1), remaining);
            const numeric_width = [_]i64{ 0, 4, 7, 10 };
            const value = reader.read(if (mode == 0) numeric_width[b.u(group)] else if (mode == 1) (if (group == 2) @as(i64,
                 11) else 6) else 8);
            var valid = true;
            if (mode == 0) {
                const maximum: i64 = if (group == 3) 1000 else if (group == 2) 100 else 10;
                if (value >= maximum) valid = false else {
                    const digits = b.fmt("{d}", .{value});
                    decoded.add("{s}{s}", .{ "000"[0 .. b.u(group) - digits.len], digits });
                }
            } else if (mode == 1) {
                if (value >= (if (group == 2) @as(i64, 2025) else 45)) valid = false else {
                    if (group == 2) decoded.add("{c}", .{b.alphanumeric[b.u(@divTrunc(value, 45))]});
                    decoded.add("{c}", .{b.alphanumeric[b.u(@mod(value, 45))]});
                }
            } else {
                if (value < 32 or value > 126) valid = false else decoded.add("{c}", .{@as(u8, @intCast(value))});
            }
            if (!valid) {
                attempt.lines.add("parse failed value {s}", .{modes[mode]});
                return;
            }
            remaining -= group;
        }
        attempt.lines.add("segment {s} {d}", .{ modes[mode], count });
        end = reader.position;
    }
    const expected = padBits(bits[0..end], b.n(bits.len));
    attempt.lines.add("padding {s}", .{if (b.eq(expected.bits, bits)) "ok" else "bad"});
    attempt.decoded = decoded.value();
    attempt.lines.add("text \"{s}\"", .{decoded.value()});
}
fn hamming(value: i64) i64 {
    return @intCast(@popCount(@as(u64, @intCast(value))));
}
const Nearest = struct { distance: i64 = 100, level: usize = 0, mask: i64 = 0 };
fn nearestFormat(value: i64) Nearest {
    var best: Nearest = .{};
    for (0..4) |level| for (0..8) |mask| {
        const distance = hamming(value ^ matrix.formatInformation(level, b.n(mask)));
        if (distance < best.distance) best = .{ .distance = distance, .level = level, .mask = b.n(mask) };
    };
    return best;
}
fn nearestVersion(value: i64) Nearest {
    var best: Nearest = .{};
    for (7..41) |version| {
        const distance = hamming(value ^ matrix.versionInformation(b.n(version)));
        if (distance < best.distance) best = .{ .distance = distance, .level = version };
    }
    return best;
}
const Codec = struct {
    tables: [11][4]BlockLayout = undefined,
    alignments: [11]Words = @splat(&.{}),
    geometries: [11]*matrix.Geometry = undefined,
    field: rs.ReedSolomon = undefined,
    fn attempt(self: *Codec, symbol: *const Matrix) Attempt {
        var out: Attempt = .{};
        const version = @divTrunc(symbol.size - 17, 4);
        const positions = matrix.formatPositions(symbol.size);
        const f1 = matrix.readValue(symbol, positions[0]);
        const f2 = matrix.readValue(symbol, positions[1]);
        const first = nearestFormat(f1);
        const second = nearestFormat(f2);
        const chosen = if (second.distance < first.distance) second else first;
        var prefix = b.fmt("format {s} {s} distance {d} {d}", .{ b.binary(f1, 15), b.binary(f2,
             15), first.distance, second.distance });
        if (chosen.distance > 3) {
            out.lines.add("{s} unreadable", .{prefix});
            return out;
        }
        const level = chosen.level;
        const mask = chosen.mask;
        out.lines.add("{s} level {c} mask {d}", .{ prefix, levels[level], mask });
        if (version >= 7) {
            const version_fields = matrix.versionPositions(symbol.size);
            const g1 = matrix.readValue(symbol, version_fields[0]);
            const g2 = matrix.readValue(symbol, version_fields[1]);
            const left = nearestVersion(g1);
            const right = nearestVersion(g2);
            const selected = if (right.distance < left.distance) right else left;
            prefix = b.fmt("version {s} {s} distance {d} {d}", .{ b.binary(g1, 18), b.binary(g2,
                 18), left.distance, right.distance });
            if (selected.distance > 3) {
                out.lines.add("{s} unreadable", .{prefix});
                return out;
            }
            out.lines.add("{s} decoded {d}", .{ prefix, selected.level });
            if (b.n(selected.level) != version) return out;
        }
        const geometry = self.geometries[b.u(version)];
        const layout = self.tables[b.u(version)][level];
        const unmasked = masking.apply(symbol.*, geometry.order, mask);
        const bits = b.alloc(u8, b.u(8 * layout.total));
        for (bits, geometry.order[0..bits.len]) |*bit, point| bit.* = '0' + unmasked.at(point.x, point.y);
        const blocks = layout.deinterleave(b.toCodewords(bits));
        var failed = false;
        var data: std.ArrayList(i64) = .empty;
        for (blocks, 0..) |received, block| {
            const result = self.field.correct(received, layout.degree);
            prefix = b.fmt("block {d} syndromes {s}", .{ block, b.hexadecimal(result.syndromes) });
            if (!result.success) {
                out.lines.add("{s} failed", .{prefix});
                out.blocks[2] += 1;
                failed = true;
            } else {
                if (result.positions.len == 0) {
                    out.lines.add("{s} ok", .{prefix});
                    out.blocks[0] += 1;
                } else {
                    var position_text: std.ArrayList([]const u8) = .empty;
                    for (result.positions) |position| b.append([]const u8, &position_text, b.fmt("{d}", .{position}));
                    out.lines.add("{s} corrected {s}", .{ prefix, b.join(position_text.items, " ") });
                    out.blocks[1] += 1;
                    out.corrected_positions += b.n(result.positions.len);
                }
                for (result.corrected[0..b.u(layout.lengths[block])]) |value| b.append(i64, &data, value);
            }
        }
        if (!failed) parseData(&out, b.fromCodewords(data.items), version);
        return out;
    }
    fn decode(self: *Codec, symbol: Matrix) Attempt {
        const rotations = finderRotation(&symbol);
        var oriented = symbol;
        for (0..rotations) |_| oriented = rotate(&oriented);
        var adopted = self.attempt(&oriented);
        var mirrored = false;
        if (adopted.decoded == null) {
            const reflected = transpose(&oriented);
            const other = self.attempt(&reflected);
            if (other.decoded != null) {
                adopted = other;
                mirrored = true;
            }
        }
        var lines: b.Lines = .{};
        lines.add("orientation rotations {d} mirrored {s}", .{ rotations, if (mirrored) "yes" else "no" });
        lines.extend(adopted.lines);
        adopted.lines = lines;
        return adopted;
    }
};
const Request = struct {
    identifier: []const u8,
    level_token: []const u8,
    mode_token: []const u8,
    version_token: []const u8,
    mask_token: []const u8,
    characters: []const u8,
    mode: usize = 0,
    version: i64 = 0,
    level: usize = 0,
    bit_count: i64 = 0,
    boosted: bool = false,
    splits: [2]?Split = .{ null, null },
    fn split(self: *Request, version: i64) Split {
        const category: usize = @intFromBool(version == 10);
        if (self.splits[category] == null) {
            if (self.mode == 3) self.splits[category] = mixedSegments(self.characters, version) else {
                const segments = b.alloc(Segment, 1);
                segments[0] = .{ .mode = self.mode, .characters = self.characters };
                self.splits[category] = .{ .segments = segments, .bits = segmentWidth(self.mode,
                     b.n(self.characters.len), version) };
            }
        }
        return self.splits[category].?;
    }
    fn prepare(self: *Request, codec: *Codec) ?[]const u8 {
        const valid_level = self.level_token.len >= 1 and self.level_token.len <= 2 and std.mem.indexOfScalar(u8,
             levels, self.level_token[0]) != null and (self.level_token.len == 1 or self.level_token[1] == '+');
        if (!valid_level) return b.fmt("level {s}", .{self.level_token});
        if (!b.eq(self.mode_token, "NUMERIC") and !b.eq(self.mode_token, "ALPHANUMERIC") and !b.eq(self.mode_token,
             "BYTE") and !b.eq(self.mode_token, "AUTO") and !b.eq(self.mode_token, "MIXED")) return b.fmt("mode {s}",
             .{self.mode_token});
        var valid_version = b.eq(self.version_token, "AUTO");
        for (1..11) |version| {
            valid_version = valid_version or b.eq(self.version_token, b.fmt("{d}", .{version}));
        }
        if (!valid_version) return b.fmt("version {s}", .{self.version_token});
        var valid_mask = b.eq(self.mask_token, "AUTO");
        for (0..8) |mask| {
            valid_mask = valid_mask or b.eq(self.mask_token, b.fmt("{d}", .{mask}));
        }
        if (!valid_mask) return b.fmt("mask {s}", .{self.mask_token});
        if (self.characters.len == 0) return "text";
        self.mode = if (b.eq(self.mode_token, "NUMERIC")) 0 else if (b.eq(self.mode_token,
             "ALPHANUMERIC")) 1 else if (b.eq(self.mode_token, "BYTE")) 2 else 3;
        if (self.mode < 2) for (self.characters, 0..) |character, i| if (!encodable(self.mode,
             character)) return b.fmt("charset position {d}", .{i});
        if (b.eq(self.mode_token, "AUTO")) {
            self.mode = 0;
            while (!encodableText(self.mode, self.characters)) self.mode += 1;
        }
        const base = std.mem.indexOfScalar(u8, levels, self.level_token[0]).?;
        const first = if (b.eq(self.version_token, "AUTO")) @as(i64, 1) else b.number(self.version_token);
        const last = if (b.eq(self.version_token, "AUTO")) @as(i64, 10) else first;
        var version = first;
        var bits: i64 = 0;
        var capacity: i64 = 0;
        while (version <= last) : (version += 1) {
            bits = self.split(version).bits;
            capacity = codec.tables[b.u(version)][base].capacity;
            if (bits <= capacity) {
                self.version = version;
                break;
            }
        }
        if (self.version == 0) return b.fmt("capacity bits {d} capacity {d}", .{ bits, capacity });
        self.bit_count = self.split(self.version).bits;
        self.level = base;
        if (self.level_token.len == 2) for (base..4) |level| if (self.bit_count <= codec.tables[b.u(self.version)][level].capacity) {
            self.level = level;
        };
        self.boosted = self.level != base;
        return null;
    }
};
const Encoding = struct {
    request: *Request,
    geometry: *matrix.Geometry,
    layout: BlockLayout,
    raw_bits: []const u8,
    trace: b.Lines,
    padding: Padding,
    blocks: []const Words,
    codewords: Words,
    scores: [8]masking.Penalty,
    mask: i64 = 0,
    dark: i64 = 0,
    symbol: Matrix = .{},
    fn init(request: *Request, codec: *Codec) Encoding {
        const geometry = codec.geometries[b.u(request.version)];
        const layout = codec.tables[b.u(request.version)][request.level];
        var writer: b.BitWriter = .{};
        var trace: b.Lines = .{};
        const indicators = [_]i64{ 1, 2, 4 };
        const widths = [_]i64{ 0, 4, 7, 10 };
        for (request.split(request.version).segments) |segment| {
            const mode = segment.mode;
            const count = b.n(segment.characters.len);
            const width = countWidth(mode, request.version);
            writer.write(indicators[mode], 4);
            writer.write(count, width);
            trace.add("segment {s} indicator {s} count {d} {s}", .{ modes[mode], b.binary(indicators[mode],
                 4), count, b.binary(count, width) });
            const step: usize = if (mode == 0) 3 else if (mode == 1) 2 else 1;
            var start: usize = 0;
            while (start < segment.characters.len) : (start += step) {
                const characters = segment.characters[start..@min(start + step, segment.characters.len)];
                var value: i64 = undefined;
                var group_width: i64 = undefined;
                if (mode == 0) {
                    value = b.number(characters);
                    group_width = widths[characters.len];
                } else if (mode == 1) {
                    value = b.n(std.mem.indexOfScalar(u8, b.alphanumeric, characters[0]).?);
                    group_width = 6;
                    if (characters.len == 2) {
                        value = 45 * value + b.n(std.mem.indexOfScalar(u8, b.alphanumeric, characters[1]).?);
                        group_width = 11;
                    }
                } else {
                    value = characters[0];
                    group_width = 8;
                }
                writer.write(value, group_width);
                trace.add("group {d} {s} \"{s}\"", .{ value, b.binary(value, group_width), characters });
            }
        }
        const padding = padBits(writer.bits(), layout.capacity);
        const data = b.toCodewords(padding.bits);
        const blocks = b.alloc(Words, layout.lengths.len);
        var start: usize = 0;
        for (layout.lengths, 0..) |length, block| {
            const words = data[start .. start + b.u(length)];
            const ec = codec.field.parity(words, layout.degree);
            const full = b.alloc(i64, words.len + ec.len);
            @memcpy(full[0..words.len], words);
            @memcpy(full[words.len..], ec);
            blocks[block] = full;
            start += b.u(length);
        }
        const codewords = b.alloc(i64, layout.placement.len);
        for (layout.placement, 0..) |place, i| codewords[i] = blocks[place.block][place.position];
        var unmasked = geometry.symbol;
        const bits = b.fromCodewords(codewords);
        for (bits, geometry.order[0..bits.len]) |bit, point| unmasked.set(point.x, point.y, bit - '0');
        var out: Encoding = .{ .request = request, .geometry = geometry, .layout = layout,
             .raw_bits = writer.bits(), .trace = trace, .padding = padding, .blocks = blocks,
             .codewords = codewords, .scores = undefined };
        var best: i64 = 1000000;
        for (0..8) |mask| {
            var candidate = masking.apply(unmasked, geometry.order, b.n(mask));
            for (matrix.formatPositions(candidate.size)) |positions| matrix.writeValue(&candidate,
                 positions, matrix.formatInformation(request.level, b.n(mask)));
            out.scores[mask] = masking.penalties(&candidate);
            const chosen = if (b.eq(request.mask_token, "AUTO")) out.scores[mask].total() < best else b.number(request.mask_token) == b.n(mask);
            if (chosen) {
                best = out.scores[mask].total();
                out.mask = b.n(mask);
                out.symbol = candidate;
            }
        }
        for (0..b.u(out.symbol.size)) |y| for (0..b.u(out.symbol.size)) |x| {
            out.dark += out.symbol.cells[y][x];
        };
        return out;
    }
};
const OperationKind = enum { flip, fill, rotate, mirror };
const Operation = struct { identifier: []const u8, kind: OperationKind, x: i64 = 0, y: i64 = 0,
     width: i64 = 0, height: i64 = 0, color: i64 = 0 };
const Scan = struct { name: []const u8, symbol: Matrix };
const Inputs = struct { requests: std.ArrayList(Request) = .empty, quiet: i64 = 0, scale: i64 = 1,
     damage: std.ArrayList(Operation) = .empty, scans: std.ArrayList(Scan) = .empty };
fn readInputs(io: std.Io, codec: *Codec) !Inputs {
    codec.field = rs.ReedSolomon.init();
    var out: Inputs = .{};
    for (try b.readLines(io, "input/requests.txt")) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':').?;
        const f = b.words(line[0..colon]);
        b.append(Request, &out.requests, .{ .identifier = f[0], .level_token = f[1], .mode_token = f[2],
             .version_token = f[3], .mask_token = f[4], .characters = line[colon + 1 ..] });
    }
    const params = try b.readLines(io, "input/params.txt");
    out.quiet = b.number(b.words(params[0])[1]);
    out.scale = b.number(b.words(params[1])[1]);
    for (try b.readLines(io, "input/tables.txt")) |line| {
        const f = b.words(line);
        const version = b.u(b.number(f[1]));
        if (b.eq(f[0], "block")) {
            const level = std.mem.indexOfScalar(u8, levels, f[2][0]).?;
            codec.tables[version][level] = BlockLayout.init(b.number(f[3]), b.number(f[4]),
                 b.number(f[5]), b.number(f[6]), b.number(f[7]));
        } else {
            const alignments = b.alloc(i64, f.len - 2);
            for (f[2..], alignments) |value, *alignment| alignment.* = b.number(value);
            codec.alignments[version] = alignments;
        }
    }
    for (1..11) |version| codec.geometries[version] = b.create(matrix.Geometry, matrix.functionMatrix(b.n(version),
         codec.alignments[version]));
    for (try b.readLines(io, "input/damage.txt")) |line| {
        const f = b.words(line);
        var op: Operation = .{ .identifier = f[0], .kind = if (b.eq(f[1], "flip")) .flip else if (b.eq(f[1],
             "fill")) .fill else if (b.eq(f[1], "rotate")) .rotate else .mirror };
        if (op.kind == .flip or op.kind == .fill) {
            op.x = b.number(f[2]);
            op.y = b.number(f[3]);
        }
        if (op.kind == .fill) {
            op.width = b.number(f[4]);
            op.height = b.number(f[5]);
            op.color = @intFromBool(b.eq(f[6], "dark"));
        }
        b.append(Operation, &out.damage, op);
    }
    const scans = try b.readLines(io, "input/scans.txt");
    var i: usize = 0;
    while (i < scans.len) {
        const name = b.words(scans[i])[1];
        i += 1;
        var symbol: Matrix = .{ .size = b.n(scans[i].len) };
        for (0..b.u(symbol.size)) |y| {
            for (0..b.u(symbol.size)) |x| symbol.cells[y][x] = @intFromBool(scans[i][x] == '#');
            i += 1;
        }
        b.append(Scan, &out.scans, .{ .name = name, .symbol = symbol });
    }
    return out;
}
fn codesLines(encoding: *Encoding, codec: *Codec) b.Lines {
    const q = encoding.request;
    const g = encoding.geometry;
    const layout = encoding.layout;
    var out: b.Lines = .{};
    out.add("symbol version {d} level {c} mask {d} size {d}", .{ q.version, levels[q.level],
         encoding.mask, g.symbol.size });
    var segments: std.ArrayList([]const u8) = .empty;
    for (q.split(q.version).segments) |segment| b.append([]const u8, &segments, b.fmt("{s}:{d}",
         .{ modes[segment.mode], segment.characters.len }));
    out.add("segments {d} {s}", .{ segments.items.len, b.join(segments.items, " ") });
    var alternatives: std.ArrayList([]const u8) = .empty;
    for (0..3) |mode| b.append([]const u8, &alternatives, b.fmt("{s} {s}", .{ modes[mode],
         if (encodableText(mode, q.characters)) b.fmt("{d}", .{segmentWidth(mode, b.n(q.characters.len),
         q.version)}) else "-" }));
    b.append([]const u8, &alternatives, b.fmt("MIXED {d}", .{if (q.mode == 3) q.bit_count else mixedSegments(q.characters,
         q.version).bits}));
    out.add("bits data {d} capacity {d} alternatives {s}", .{ q.bit_count, layout.capacity,
         b.join(alternatives.items, " ") });
    var fits: std.ArrayList([]const u8) = .empty;
    for (0..4) |level| {
        var fitting: []const u8 = "-";
        for (1..11) |version| if (q.split(b.n(version)).bits <= codec.tables[version][level].capacity) {
            fitting = b.fmt("{d}", .{version});
            break;
        };
        b.append([]const u8, &fits, b.fmt("{c} {s}", .{ levels[level], fitting }));
    }
    out.add("fits {s}", .{b.join(fits.items, " ")});
    out.add("modules function {d} data {d} remainder {d} dark {d}", .{ g.functionModules(),
         g.order.len, b.n(g.order.len) - 8 * layout.total, encoding.dark });
    out.add("format {s} version {s}", .{ b.binary(matrix.formatInformation(q.level, encoding.mask),
         15), if (q.version >= 7) b.binary(matrix.versionInformation(q.version), 18) else "none" });
    for (encoding.scores, 0..) |score, mask| out.add("penalty {d} n1 {d} n2 {d} n3 {d} n4 {d} total {d}",
         .{ mask, score.n1, score.n2, score.n3, score.n4, score.total() });
    out.extend(render.symbolLines(&encoding.symbol));
    return out;
}
fn codewordLines(encoding: *const Encoding) b.Lines {
    const q = encoding.request;
    const layout = encoding.layout;
    var out: b.Lines = .{};
    out.add("request {s} version {d} level {c} blocks {d} data {d} ec_per_block {d} total {d}",
         .{ q.identifier, q.version, levels[q.level], layout.lengths.len, layout.data, layout.degree,
         layout.total });
    for (encoding.blocks, layout.lengths, 0..) |words, length, block| {
        out.add("block {d} data {s}", .{ block, b.hexadecimal(words[0..b.u(length)]) });
        out.add("block {d} ec {s}", .{ block, b.hexadecimal(words[b.u(length)..]) });
    }
    out.add("interleaved {s}", .{b.hexadecimal(encoding.codewords)});
    return out;
}
fn bitstreamLines(encoding: *const Encoding) b.Lines {
    var out: b.Lines = .{};
    out.add("request {s} version {d} bits {d} capacity {d}", .{ encoding.request.identifier,
         encoding.request.version, encoding.request.bit_count, encoding.layout.capacity });
    out.extend(encoding.trace);
    out.add("terminator {d} zero_fill {d} pad_bytes {d}", .{ encoding.padding.terminator, encoding.padding.zero_fill,
         encoding.padding.pad_bytes });
    return out;
}
const Image = struct { symbol: Matrix, description: []const u8 };
fn readImage(io: std.Io, path: []const u8) !Image {
    const lines = try b.readLines(io, path);
    const dimensions = b.words(lines[1]);
    const width = b.number(dimensions[0]);
    const height = b.number(dimensions[1]);
    var left = width;
    var right: i64 = 0;
    var top = height;
    for (0..b.u(height)) |y| for (0..b.u(width)) |x| if (lines[y + 2][x] == '1') {
        left = @min(left, b.n(x));
        right = @max(right, b.n(x));
        top = @min(top, b.n(y));
    };
    var run: i64 = 0;
    while (left + run < width and lines[b.u(top) + 2][b.u(left + run)] == '1') run += 1;
    const unit = @divTrunc(run, 7);
    var symbol: Matrix = .{ .size = @divTrunc(right - left + 1, unit) };
    for (0..b.u(symbol.size)) |y| for (0..b.u(symbol.size)) |x| symbol.cells[y][x] = lines[b.u(top + unit * b.n(y)) + 2][b.u(left + unit * b.n(x))] - '0';
    var well_formed = true;
    for (0..b.u(height)) |y| for (0..b.u(width)) |x| {
        var expected: u8 = 0;
        if (b.n(x) >= left and b.n(x) < left + unit * symbol.size and b.n(y) >= top and b.n(y) < top + unit * symbol.size) expected = symbol.at(@divTrunc(b.n(x) - left,
             unit), @divTrunc(b.n(y) - top, unit));
        well_formed = well_formed and lines[y + 2][x] - '0' == expected;
    };
    return .{ .symbol = symbol, .description = b.fmt("image {d} {d} quiet {d} scale {d} size {d} {s}",
         .{ width, height, @divTrunc(left, unit), unit, symbol.size, if (well_formed) "ok" else "bad" }) };
}
fn damagedSymbol(encoding: *const Encoding, operations: []const Operation) struct { symbol: Matrix, lines: b.Lines } {
    var symbol = encoding.symbol;
    for (operations) |op| switch (op.kind) {
        .flip => symbol.flip(op.x, op.y),
        .fill => {
            for (b.u(op.y)..b.u(op.y + op.height)) |y| for (b.u(op.x)..b.u(op.x + op.width)) |x| symbol.set(b.n(x),
                 b.n(y), op.color);
        },
        else => {},
    };
    var counts: [5]i64 = @splat(0);
    const damaged_words = b.alloc([256]bool, encoding.layout.lengths.len);
    @memset(damaged_words, @splat(false));
    for (0..b.u(symbol.size)) |y| for (0..b.u(symbol.size)) |x| if (symbol.cells[y][x] != encoding.symbol.cells[y][x]) {
        const area = encoding.geometry.areas.cells[y][x];
        if (area != matrix.data) counts[area - 1] += 1 else {
            const index = encoding.geometry.indices[y][x];
            if (index < 8 * encoding.layout.total) {
                counts[3] += 1;
                const place = encoding.layout.placement[b.u(@divTrunc(index, 8))];
                damaged_words[place.block][place.position] = true;
            } else counts[4] += 1;
        }
    };
    for (operations) |op| switch (op.kind) {
        .rotate => symbol = rotate(&symbol),
        .mirror => symbol = transpose(&symbol),
        else => {},
    };
    var changed: i64 = 0;
    for (counts) |count| changed += count;
    var lines: b.Lines = .{};
    lines.add("check damaged operations {d}", .{operations.len});
    lines.add("damage changed {d} function {d} format {d} version {d} data {d} remainder {d}",
         .{ changed, counts[0], counts[1], counts[2], counts[3], counts[4] });
    var errors: std.ArrayList([]const u8) = .empty;
    for (damaged_words) |words| {
        var count: usize = 0;
        for (words) |damaged| if (damaged) {
            count += 1;
        };
        b.append([]const u8, &errors, b.fmt("{d}", .{count}));
    }
    lines.add("errors {s} limit {d}", .{ b.join(errors.items, " "), @divTrunc(encoding.layout.degree, 2) });
    return .{ .symbol = symbol, .lines = lines };
}
fn tolerance(encoding: *const Encoding, codec: *Codec, color: i64, work_allocator: std.mem.Allocator) i64 {
    const n = encoding.symbol.size;
    for (1..b.u(n) + 1) |side| {
        const parent = b.allocator;
        var work: std.heap.ArenaAllocator = .init(work_allocator);
        defer work.deinit();
        b.allocator = work.allocator();
        var symbol = encoding.symbol;
        const start = @divTrunc(n - b.n(side), 2);
        for (b.u(start)..b.u(start) + side) |y| for (b.u(start)..b.u(start) + side) |x| symbol.set(b.n(x),
             b.n(y), color);
        const result = codec.decode(symbol);
        const same = if (result.decoded) |decoded| b.eq(decoded, encoding.request.characters) else false;
        b.allocator = parent;
        if (!same) return b.n(side) - 1;
    }
    return n;
}
const Summary = struct {
    encoded: i64 = 0,
    boosted: i64 = 0,
    segments: i64 = 0,
    data: i64 = 0,
    ec: i64 = 0,
    modules: i64 = 0,
    dark: i64 = 0,
    corrected_positions: i64 = 0,
    errors: [7]i64 = @splat(0),
    mode_counts: [4]i64 = @splat(0),
    level_counts: [4]i64 = @splat(0),
    versions: [11]i64 = @splat(0),
    masks: [8]i64 = @splat(0),
    checks: [3]i64 = @splat(0),
    blocks: [3]i64 = @splat(0),
    scans: [2]i64 = @splat(0),
    fn recordEncoding(self: *Summary, encoding: *const Encoding) void {
        self.encoded += 1;
        self.boosted += @intFromBool(encoding.request.boosted);
        self.mode_counts[encoding.request.mode] += 1;
        self.level_counts[encoding.request.level] += 1;
        self.versions[b.u(encoding.request.version)] += 1;
        self.masks[b.u(encoding.mask)] += 1;
        self.segments += b.n(encoding.request.splits[@intFromBool(encoding.request.version == 10)].?.segments.len);
        self.data += encoding.layout.data;
        self.ec += encoding.layout.degree * b.n(encoding.layout.lengths.len);
        self.modules += encoding.symbol.size * encoding.symbol.size;
        self.dark += encoding.dark;
    }
    fn recordCheck(self: *Summary, attempt: Attempt, expected: []const u8) []const u8 {
        const status: usize = if (attempt.decoded) |decoded| (if (b.eq(decoded, expected)) @as(usize, 0) else 1) else 2;
        self.checks[status] += 1;
        for (attempt.blocks, 0..) |count, i| self.blocks[i] += count;
        self.corrected_positions += attempt.corrected_positions;
        return if (status == 0) "ok" else if (status == 1) "mismatch" else "failed";
    }
    fn report(self: Summary, requests: usize) b.Lines {
        var out: b.Lines = .{};
        var error_count: i64 = 0;
        for (self.errors) |count| error_count += count;
        out.add("requests {d} encoded {d} errors {d}", .{ requests, self.encoded, error_count });
        var parts: std.ArrayList([]const u8) = .empty;
        for (error_kinds, self.errors) |kind, count| b.append([]const u8, &parts, b.fmt("{s} {d}", .{ kind, count }));
        out.add("error_kinds {s}", .{b.join(parts.items, " ")});
        parts = .empty;
        for (self.mode_counts, 0..) |count, mode| b.append([]const u8, &parts, b.fmt("{s} {d}",
             .{ if (mode < 3) modes[mode] else "MIXED", count }));
        out.add("modes {s}", .{b.join(parts.items, " ")});
        parts = .empty;
        for (self.level_counts, levels) |count, level| b.append([]const u8, &parts, b.fmt("{c} {d}",
             .{ level, count }));
        out.add("levels {s} boosted {d}", .{ b.join(parts.items, " "), self.boosted });
        parts = .empty;
        for (self.versions[1..]) |count| b.append([]const u8, &parts, b.fmt("{d}", .{count}));
        out.add("versions {s}", .{b.join(parts.items, " ")});
        parts = .empty;
        for (self.masks) |count| b.append([]const u8, &parts, b.fmt("{d}", .{count}));
        out.add("masks {s}", .{b.join(parts.items, " ")});
        out.add("segments {d} data_codewords {d} ec_codewords {d}", .{ self.segments, self.data, self.ec });
        out.add("modules {d} dark {d}", .{ self.modules, self.dark });
        out.add("checks {d} ok {d} mismatch {d} failed {d}", .{ self.checks[0] + self.checks[1] + self.checks[2],
             self.checks[0], self.checks[1], self.checks[2] });
        out.add("blocks ok {d} corrected {d} failed {d} codewords {d}", .{ self.blocks[0],
             self.blocks[1], self.blocks[2], self.corrected_positions });
        out.add("scans {d} decoded {d} failed {d}", .{ self.scans[0] + self.scans[1], self.scans[0], self.scans[1] });
        return out;
    }
};
fn checkLines(io: std.Io, encoding: *const Encoding, codec: *Codec, inputs: *const Inputs,
     operations: []const Operation, summary: *Summary, work_allocator: std.mem.Allocator) !b.Lines {
    const path = b.fmt("output/qr_{s}.pbm", .{encoding.request.identifier});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = render.pbmText(&encoding.symbol,
         inputs.quiet, inputs.scale) });
    const image = try readImage(io, path);
    var out: b.Lines = .{};
    out.add("request {s}", .{encoding.request.identifier});
    out.add("{s}", .{image.description});
    out.add("check clean", .{});
    const clean = codec.decode(image.symbol);
    out.extend(clean.lines);
    out.add("result {s}", .{summary.recordCheck(clean, encoding.request.characters)});
    if (operations.len > 0) {
        const damage = damagedSymbol(encoding, operations);
        out.extend(damage.lines);
        const result = codec.decode(damage.symbol);
        out.extend(result.lines);
        out.add("result {s}", .{summary.recordCheck(result, encoding.request.characters)});
    }
    const light = tolerance(encoding, codec, 0, work_allocator);
    const dark = tolerance(encoding, codec, 1, work_allocator);
    out.add("tolerance light {d} dark {d}", .{ light, dark });
    return out;
}
fn capacityLines(codec: *Codec) b.Lines {
    var out: b.Lines = .{};
    for (1..11) |version| {
        const geometry = codec.geometries[version];
        const total = codec.tables[version][0].total;
        var alignments: std.ArrayList([]const u8) = .empty;
        for (codec.alignments[version]) |value| b.append([]const u8, &alignments, b.fmt("{d}", .{value}));
        out.add("version {d} size {d} data_modules {d} codewords {d} remainder {d} alignment {s}",
             .{ version, geometry.symbol.size, geometry.order.len, total, b.n(geometry.order.len) - 8 * total,
             if (alignments.items.len == 0) "none" else b.join(alignments.items, " ") });
        for (0..4) |level| {
            const layout = codec.tables[version][level];
            var maxima: [3]i64 = @splat(0);
            for (0..3) |mode| while (segmentWidth(mode, maxima[mode] + 1, b.n(version)) <= layout.capacity) {
                maxima[mode] += 1;
            };
            out.add("level {c} blocks {d} data {d} ec_per_block {d} numeric {d} alphanumeric {d} byte {d}",
                 .{ levels[level], layout.lengths.len, layout.data, layout.degree, maxima[0],
                 maxima[1], maxima[2] });
        }
    }
    return out;
}
fn write(io: std.Io, name: []const u8, lines: b.Lines) !void {
    var data: b.Text = .{};
    for (lines.data.items) |line| data.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = b.fmt("output/{s}.txt", .{name}), .data = data.value() });
}
pub fn main(init: std.process.Init) !void {
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    b.allocator = arena.allocator();
    var codec: Codec = .{};
    const inputs = try readInputs(init.io, &codec);
    var summary: Summary = .{};
    var reports: [5]b.Lines = @splat(.{});
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    for (inputs.requests.items) |*request| {
        const persistent = b.allocator;
        var work: std.heap.ArenaAllocator = .init(init.gpa);
        defer work.deinit();
        b.allocator = work.allocator();
        const failure = request.prepare(&codec);
        b.allocator = persistent;
        reports[0].add("request {s}", .{request.identifier});
        if (failure) |reason| {
            reports[0].add("error {s}", .{reason});
            for (error_kinds, 0..) |kind, i| if (b.eq(reason, kind) or (std.mem.startsWith(u8,
                 reason, kind) and reason.len > kind.len and reason[kind.len] == ' ')) {
                summary.errors[i] += 1;
                break;
            };
        } else {
            b.allocator = work.allocator();
            var encoding = Encoding.init(request, &codec);
            const codes = codesLines(&encoding, &codec);
            const words = codewordLines(&encoding);
            const bits = bitstreamLines(&encoding);
            summary.recordEncoding(&encoding);
            var operations: std.ArrayList(Operation) = .empty;
            for (inputs.damage.items) |op| if (b.eq(op.identifier, request.identifier)) b.append(Operation,
                 &operations, op);
            const checks = try checkLines(init.io, &encoding, &codec, &inputs, operations.items, &summary, init.gpa);
            b.allocator = persistent;
            reports[0].extend(codes);
            reports[1].extend(words);
            reports[2].extend(bits);
            reports[3].extend(checks);
        }
    }
    for (inputs.scans.items) |scan| {
        const persistent = b.allocator;
        var work: std.heap.ArenaAllocator = .init(init.gpa);
        defer work.deinit();
        b.allocator = work.allocator();
        const result = codec.decode(scan.symbol);
        b.allocator = persistent;
        reports[4].add("scan {s} size {d}", .{ scan.name, scan.symbol.size });
        reports[4].extend(result.lines);
        reports[4].add("result {s}", .{if (result.decoded != null) "decoded" else "failed"});
        summary.scans[@intFromBool(result.decoded == null)] += 1;
    }
    for ([_][]const u8{ "codes", "codewords", "bitstream", "selfcheck", "scans" }, reports) |name,
         report| try write(init.io, name, report);
    try write(init.io, "capacity", capacityLines(&codec));
    try write(init.io, "summary", summary.report(inputs.requests.items.len));
}
