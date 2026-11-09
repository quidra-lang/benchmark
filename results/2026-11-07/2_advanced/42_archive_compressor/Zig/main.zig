const std = @import("std");
const c = @import("bitio.zig");
const lzw = @import("lzw.zig");
const lz77 = @import("lz77.zig");
const huffman = @import("huffman.zig");
const arith = @import("arith_coder.zig");
const methods = [_][]const u8{ "STORE", "LZW", "LZ77", "LZH", "ARITH" };
fn readBytes(io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, c.allocator, .unlimited);
}
fn textLines(bytes: []const u8) c.Lines {
    var out: c.Lines = .{};
    var first: usize = 0;
    for (bytes, 0..) |byte, i| if (byte == 10) {
        out.add("{s}", .{bytes[first..i]});
        first = i + 1;
    };
    return out;
}
fn write(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
fn hex8(value: u32) []const u8 {
    return c.fmt("{x:0>8}", .{value});
}
fn hexLines(bytes: []const u8) c.Lines {
    var out: c.Lines = .{};
    var first: usize = 0;
    while (first < bytes.len) : (first += 32) {
        var line: c.Text = .{};
        for (bytes[first..@min(first + 32, bytes.len)]) |byte| line.add("{x:0>2}", .{byte});
        out.add("{s}", .{line.value()});
    }
    return out;
}
fn adler(bytes: []const u8) u32 {
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (bytes) |byte| {
        s1 = (s1 + byte) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return s2 * 65536 + s1;
}
fn ratio(original: usize, compressed: usize) []const u8 {
    return if (original > 0) c.fmt("{d}", .{1000 * compressed / original}) else "-";
}
fn methodName(method: usize) []const u8 {
    return if (method < 5) methods[method] else c.fmt("#{d}", .{method});
}
fn writeTable(writer: *c.Writer, lengths: []const usize) void {
    var position: usize = 0;
    while (position < lengths.len) {
        if (lengths[position] > 0) {
            writer.write(@intCast(lengths[position]), 4);
            position += 1;
        } else {
            var count: usize = 1;
            while (count < 256 and position + count < lengths.len and lengths[position + count] == 0) count += 1;
            writer.write(0, 4);
            writer.write(@intCast(count - 1), 8);
            position += count;
        }
    }
}
fn readTable(reader: *c.Reader, symbols: usize) c.DecodeError![]const usize {
    const lengths = c.alloc(usize, symbols);
    var position: usize = 0;
    while (position < symbols) {
        const value = try reader.read(4);
        if (value > 0) {
            lengths[position] = value;
            position += 1;
        } else {
            const count = @as(usize, try reader.read(8)) + 1;
            if (position + count > symbols) return error.bad_table;
            @memset(lengths[position .. position + count], 0);
            position += count;
        }
    }
    var used: usize = 0;
    var only: usize = 0;
    var sum: usize = 0;
    for (lengths) |length| if (length > 0) {
        used += 1;
        only = length;
        sum += @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(15 - length));
    };
    if ((used == 1 and only != 1) or (used >= 2 and sum != (1 << 15))) return error.bad_table;
    return lengths;
}
fn fixedLengths(symbols: usize) []const usize {
    const width = c.bits(symbols - 1);
    const shorter = (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(width))) - symbols;
    const lengths = c.alloc(usize, symbols);
    for (lengths, 0..) |*length, symbol| length.* = if (symbol < shorter) width - 1 else width;
    return lengths;
}
fn readSymbol(reader: *c.Reader, lengths: []const usize, codes: []const u32) c.DecodeError!usize {
    const maximum = std.mem.max(usize, lengths);
    if (maximum == 0) return error.bad_code;
    var code: u32 = 0;
    for (1..maximum + 1) |width| {
        code = 2 * code + try reader.read(1);
        for (lengths, codes, 0..) |length, value, symbol| if (length == width and value == code) return symbol;
    }
    return error.bad_code;
}
fn tokenPart(writer: *c.Writer, tokens: []const lz77.Token, lengths: []const usize, distances: []const usize) void {
    const codes = huffman.canonicalCodes(lengths);
    const offset_codes = huffman.canonicalCodes(distances);
    for (tokens) |token| {
        const symbol = if (token.length > 0) 256 + token.length - 3 else token.literal;
        writer.write(codes[symbol], lengths[symbol]);
        if (token.length > 0) {
            const u = token.distance - 1;
            const slot = c.bits(u);
            writer.write(offset_codes[slot], distances[slot]);
            if (slot >= 2) writer.write(@intCast(u - (@as(usize, 1) << @as(std.math.Log2Int(usize),
                 @intCast(slot - 1)))), slot - 1);
        }
    }
}
const LzhStats = struct { dynamic: bool = false, fixed_bits: usize = 0, table_bits: usize = 0, code_bits: usize = 0,
     halvings: usize = 0, litlen_used: usize = 0, litlen_max: usize = 0, offset_used: usize = 0, offset_max: usize = 0,
     slots: []usize = &.{} };
fn lzhEncode(tokens: []const lz77.Token, b: usize, k: usize, maximum: usize, stats: *LzhStats) []const u8 {
    const symbols = 256 + (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k)));
    const frequency = c.alloc(usize, symbols);
    const offset_frequency = c.alloc(usize, b + 1);
    @memset(frequency, 0);
    @memset(offset_frequency, 0);
    stats.slots = c.alloc(usize, b + 1);
    @memset(stats.slots, 0);
    for (tokens) |token| {
        frequency[if (token.length > 0) 256 + token.length - 3 else token.literal] += 1;
        if (token.length > 0) {
            const slot = c.bits(token.distance - 1);
            offset_frequency[slot] += 1;
            stats.slots[slot] += 1;
        }
    }
    const literal = huffman.lengths(frequency, maximum);
    const distance = huffman.lengths(offset_frequency, maximum);
    stats.halvings = literal.halvings + distance.halvings;
    for (literal.lengths) |length| {
        stats.litlen_used += @intFromBool(length > 0);
        stats.litlen_max = @max(stats.litlen_max, length);
    }
    for (distance.lengths) |length| {
        stats.offset_used += @intFromBool(length > 0);
        stats.offset_max = @max(stats.offset_max, length);
    }
    var tables: c.Writer = .{};
    var dynamic: c.Writer = .{};
    var fixed: c.Writer = .{};
    writeTable(&tables, literal.lengths);
    writeTable(&tables, distance.lengths);
    tokenPart(&dynamic, tokens, literal.lengths, distance.lengths);
    const fixed_literal = fixedLengths(symbols);
    const fixed_distance = fixedLengths(b + 1);
    tokenPart(&fixed, tokens, fixed_literal, fixed_distance);
    stats.fixed_bits = fixed.count;
    stats.table_bits = tables.count;
    stats.code_bits = dynamic.count;
    stats.dynamic = stats.fixed_bits > stats.table_bits + stats.code_bits;
    var writer: c.Writer = .{};
    writer.write(@intFromBool(stats.dynamic), 1);
    if (stats.dynamic) {
        writeTable(&writer, literal.lengths);
        writeTable(&writer, distance.lengths);
        tokenPart(&writer, tokens, literal.lengths, distance.lengths);
    } else tokenPart(&writer, tokens, fixed_literal, fixed_distance);
    return writer.bytes.items;
}
fn lz77Encode(tokens: []const lz77.Token, b: usize, k: usize) []const u8 {
    var writer: c.Writer = .{};
    for (tokens) |token| {
        writer.write(@intFromBool(token.length > 0), 1);
        if (token.length > 0) {
            writer.write(@intCast(token.distance - 1), b);
            writer.write(@intCast(token.length - 3), k);
        } else writer.write(token.literal, 8);
    }
    return writer.bytes.items;
}
fn decode(method: usize, payload: []const u8, original: usize, b: usize, k: usize, output: *c.Bytes) c.DecodeError!void {
    if (method == 0) {
        for (payload) |byte| {
            if (output.items.len == original) return;
            c.append(u8, output, byte);
        }
        if (output.items.len < original) return error.end_of_data;
        return;
    }
    if (method == 1) return lzw.decode(payload, original, output);
    if (method == 4) return arith.decode(payload, original, output);
    var reader: c.Reader = .{ .bytes = payload };
    if (method == 2) {
        while (output.items.len < original) {
            if (try reader.read(1) == 0) c.append(u8, output, @intCast(try reader.read(8))) else {
                const distance = @as(usize, try reader.read(b)) + 1;
                const length = @as(usize, try reader.read(k)) + 3;
                try lz77.outputMatch(output, original, distance, length);
            }
        }
        return;
    }
    const dynamic = try reader.read(1) != 0;
    const symbols = 256 + (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k)));
    const lengths = if (dynamic) try readTable(&reader, symbols) else fixedLengths(symbols);
    const offsets = if (dynamic) try readTable(&reader, b + 1) else fixedLengths(b + 1);
    const codes = huffman.canonicalCodes(lengths);
    const offset_codes = huffman.canonicalCodes(offsets);
    while (output.items.len < original) {
        const symbol = try readSymbol(&reader, lengths, codes);
        if (symbol < 256) c.append(u8, output, @intCast(symbol)) else {
            const length = symbol - 253;
            const slot = try readSymbol(&reader, offsets, offset_codes);
            const u = if (slot >= 2) (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(slot - 1))) + @as(usize,
                 try reader.read(slot - 1)) else slot;
            try lz77.outputMatch(output, original, u + 1, length);
        }
    }
}
const Encoded = struct { payloads: [5][]const u8 = undefined, best: usize = 0, tokens: []const lz77.Token,
     lzw_stats: lzw.Statistics = .{}, lzh: LzhStats = .{}, arith_stats: arith.Statistics = .{} };
fn encode(data: []const u8, b: usize, k: usize, maximum: usize) Encoded {
    var out: Encoded = .{ .tokens = lz77.tokenize(data, b, k) };
    out.payloads[0] = data;
    out.payloads[1] = lzw.encode(data, &out.lzw_stats);
    out.payloads[2] = lz77Encode(out.tokens, b, k);
    out.payloads[3] = lzhEncode(out.tokens, b, k, maximum, &out.lzh);
    out.payloads[4] = arith.encode(data, &out.arith_stats);
    for (1..5) |method| if (out.payloads[method].len < out.payloads[out.best].len) {
        out.best = method;
    };
    return out;
}
const File = struct { name: []const u8, data: []const u8, payload: []const u8 = &.{}, method: usize = 0 };
fn bigEndian(bytes: *c.Bytes, value: u32, count: usize) void {
    var remaining = count;
    while (remaining > 0) {
        remaining -= 1;
        c.append(u8, bytes, @intCast((value >> @as(u5, @intCast(8 * remaining))) & 255));
    }
}
fn readInteger(bytes: []const u8, first: usize, count: usize) u32 {
    var value: u32 = 0;
    for (bytes[first .. first + count]) |byte| value = (value << 8) | byte;
    return value;
}
fn buildArchive(files: []const File, b: usize, k: usize) []const u8 {
    var archive: c.Bytes = .empty;
    for ("TXAR") |byte| c.append(u8, &archive, byte);
    c.append(u8, &archive, @intCast(b));
    c.append(u8, &archive, @intCast(k));
    bigEndian(&archive, @intCast(files.len), 2);
    for (files) |file| {
        const first = archive.items.len;
        c.append(u8, &archive, @intCast(file.name.len));
        for (file.name) |byte| c.append(u8, &archive, byte);
        c.append(u8, &archive, @intCast(file.method));
        bigEndian(&archive, @intCast(file.data.len), 4);
        bigEndian(&archive, @intCast(file.payload.len), 4);
        bigEndian(&archive, adler(file.data), 4);
        var sum: usize = 0;
        for (archive.items[first..]) |byte| sum += byte;
        c.append(u8, &archive, @intCast(sum % 256));
        for (file.payload) |byte| c.append(u8, &archive, byte);
    }
    return archive.items;
}
const Status = enum { ok, repaired, checksum, failed, unsupported, truncated, bad_header };
fn statusName(status: Status) []const u8 {
    return if (status == .failed) "error" else @tagName(status);
}
const Entry = struct { number: usize, method: usize = 0, position: usize, start: usize = 0, original: usize = 0,
     compressed: usize = 0, stored: u32 = 0, computed: u32 = 0, name: []const u8 = "", status: Status = .truncated,
     error_reason: []const u8 = "", valid: bool = false, header_cut: bool = false, output: c.Bytes = .empty,
     error_position: usize = 0, repair_position: usize = 0, repair_from: u8 = 0, repair_to: u8 = 0 };
const Parsed = struct { error_reason: ?[]const u8 = null, b: usize = 0, k: usize = 0, declared: usize = 0,
     size: usize, trailing: usize = 0, stopped: bool = false, entries: std.ArrayList(Entry) = .empty };
fn powerMod(value_: i64, exponent_: i64) i64 {
    var value = value_;
    var exponent = exponent_;
    var result: i64 = 1;
    while (exponent > 0) {
        if (@mod(exponent, 2) == 1) result = @mod(result * value, 65521);
        value = @mod(value * value, 65521);
        exponent = @divFloor(exponent, 2);
    }
    return result;
}
fn repair(entry: *Entry) bool {
    const delta_a = @mod(c.n(entry.stored % 65536) - c.n(entry.computed % 65536), 65521);
    const delta_b = @mod(c.n(entry.stored / 65536) - c.n(entry.computed / 65536), 65521);
    const delta = if (delta_a >= 1 and delta_a <= 255) delta_a else if (delta_a >= 65266 and delta_a <= 65520) delta_a - 65521 else return false;
    const inverse = powerMod(@mod(delta, 65521), 65519);
    const t = @mod(delta_b * inverse, 65521);
    if (t < 1 or t > c.n(entry.output.items.len)) return false;
    const position = entry.output.items.len - c.u(t);
    const old = entry.output.items[position];
    const value = c.n(old) + delta;
    if (value < 0 or value > 255) return false;
    entry.output.items[position] = @intCast(value);
    if (adler(entry.output.items) != entry.stored) {
        entry.output.items[position] = old;
        return false;
    }
    entry.repair_position = position;
    entry.repair_from = old;
    entry.repair_to = @intCast(value);
    return true;
}
fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len > 32) return false;
    for (name) |char| if (!((char >= 'a' and char <= 'z') or (char >= '0' and char <= '9') or char == '.' or char == '_' or char == '-')) return false;
    return true;
}
fn parse(bytes: []const u8) Parsed {
    var out: Parsed = .{ .size = bytes.len };
    if (bytes.len < 8 or !c.eq(bytes[0..4], "TXAR")) {
        out.error_reason = "bad_magic";
        return out;
    }
    out.b = bytes[4];
    out.k = bytes[5];
    if (out.b < 6 or out.b > 12 or out.k < 2 or out.k > 5) {
        out.error_reason = "bad_params";
        return out;
    }
    out.declared = readInteger(bytes, 6, 2);
    var position: usize = 8;
    for (1..out.declared + 1) |number| {
        var entry: Entry = .{ .number = number, .position = position };
        if (position >= bytes.len or position + 15 + bytes[position] > bytes.len) {
            entry.header_cut = true;
            c.append(Entry, &out.entries, entry);
            out.stopped = true;
            break;
        }
        const length = @as(usize, bytes[position]);
        entry.name = bytes[position + 1 .. position + 1 + length];
        entry.method = bytes[position + 1 + length];
        entry.original = readInteger(bytes, position + 2 + length, 4);
        entry.compressed = readInteger(bytes, position + 6 + length, 4);
        entry.stored = readInteger(bytes, position + 10 + length, 4);
        entry.start = position + 15 + length;
        const next = entry.start + entry.compressed;
        var sum: usize = 0;
        for (bytes[position .. entry.start - 1]) |byte| sum += byte;
        if (sum % 256 != bytes[entry.start - 1] or !validName(entry.name)) {
            entry.status = .bad_header;
            position = next;
            c.append(Entry, &out.entries, entry);
            if (position > bytes.len) {
                out.stopped = true;
                break;
            }
            continue;
        }
        entry.valid = true;
        if (next > bytes.len) {
            entry.status = .truncated;
            c.append(Entry, &out.entries, entry);
            out.stopped = true;
            break;
        }
        if (entry.method >= 5) entry.status = .unsupported else {
            decode(entry.method, bytes[entry.start..next], entry.original, out.b, out.k, &entry.output) catch |err| {
                entry.status = .failed;
                entry.error_reason = @errorName(err);
                entry.error_position = entry.output.items.len;
            };
            if (entry.status != .failed) {
                entry.computed = adler(entry.output.items);
                entry.status = if (entry.computed == entry.stored) .ok else if (repair(&entry)) .repaired else .checksum;
            }
        }
        c.append(Entry, &out.entries, entry);
        position = next;
    }
    if (!out.stopped) out.trailing = bytes.len - position;
    return out;
}
fn verified(parsed: Parsed, files: []const File) usize {
    var count: usize = 0;
    for (parsed.entries.items[0..@min(parsed.entries.items.len, files.len)], files[0..@min(parsed.entries.items.len,
         files.len)]) |entry, file| count += @intFromBool(entry.status == .ok and c.eq(entry.output.items,
         file.data));
    return count;
}
fn listing(parsed: Parsed) c.Lines {
    var out: c.Lines = .{};
    if (parsed.error_reason) |reason| {
        out.add("archive bytes {d} error {s}", .{ parsed.size, reason });
        return out;
    }
    out.add("archive bytes {d} offset_bits {d} length_bits {d} entries {d}", .{ parsed.size, parsed.b,
         parsed.k, parsed.declared });
    var counts = std.mem.zeroes([5]usize);
    var original = std.mem.zeroes([5]usize);
    var compressed = std.mem.zeroes([5]usize);
    var listed: usize = 0;
    for (parsed.entries.items) |entry| {
        if (entry.header_cut) out.add("entry {d} offset {d} truncated header", .{ entry.number, entry.position }) else if (!entry.valid) out.add("entry {d} offset {d} bad_header",
             .{ entry.number, entry.position }) else {
            listed += 1;
            out.add("entry {d} offset {d} method {s} original {d} compressed {d} ratio {s} adler {s} name {s}",
                 .{ entry.number, entry.position, methodName(entry.method), entry.original, entry.compressed,
                 ratio(entry.original, entry.compressed), hex8(entry.stored), entry.name });
            if (entry.method < 5) {
                counts[entry.method] += 1;
                original[entry.method] += entry.original;
                compressed[entry.method] += entry.compressed;
            }
        }
    }
    for (methods, 0..) |name, method| out.add("method {s} entries {d} original {d} compressed {d} ratio {s}",
         .{ name, counts[method], original[method], compressed[method], ratio(original[method], compressed[method]) });
    out.add("end listed {d} of {d} stop {s} trailing {d}", .{ listed, parsed.declared, if (parsed.stopped) "truncated" else "complete",
         parsed.trailing });
    return out;
}
fn compare(out: *c.Lines, name: []const u8, old: c.Lines, fresh: c.Lines) void {
    const old_lines = old.data.items;
    const new_lines = fresh.data.items;
    var first: usize = 0;
    while (first < @min(old_lines.len, new_lines.len) and c.eq(old_lines[first], new_lines[first])) first += 1;
    if (first == old_lines.len and first == new_lines.len) {
        out.add("same {s} lines {d}", .{ name, old_lines.len });
        return;
    }
    const a = old_lines.len;
    const b = new_lines.len;
    const width = b + 1;
    const lcs = c.alloc(u32, (a + 1) * (b + 1));
    @memset(lcs, 0);
    var remaining = a;
    while (remaining > 0) {
        remaining -= 1;
        const i = remaining;
        var columns = b;
        while (columns > 0) {
            columns -= 1;
            const j = columns;
            lcs[i * width + j] = if (c.eq(old_lines[i], new_lines[j])) 1 + lcs[(i + 1) * width + j + 1] else @max(lcs[(i + 1) * width + j],
                 lcs[i * width + j + 1]);
        }
    }
    var edits: c.Lines = .{};
    var i: usize = 0;
    var j: usize = 0;
    var removed: usize = 0;
    var added: usize = 0;
    while (i < a or j < b) {
        if (i < a and j < b and c.eq(old_lines[i], new_lines[j])) {
            i += 1;
            j += 1;
        } else if (j == b or (i < a and lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])) {
            edits.add("-{d}:{s}", .{ i + 1, old_lines[i] });
            i += 1;
            removed += 1;
        } else {
            edits.add("+{d}:{s}", .{ j + 1, new_lines[j] });
            j += 1;
            added += 1;
        }
    }
    out.add("differs {s} first_line {d} archive_lines {d} manifest_lines {d} removed {d} added {d}",
         .{ name, first + 1, a, b, removed, added });
    out.extend(edits);
}
fn parseNumber(line: []const u8) usize {
    const first = std.mem.indexOfScalar(u8, line, ' ').? + 1;
    return std.fmt.parseInt(usize, line[first..], 10) catch unreachable;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const manifest = textLines(try readBytes(init.io, "input/manifest.txt")).data.items;
    const b = parseNumber(manifest[0]);
    const k = parseNumber(manifest[1]);
    const maximum = parseNumber(manifest[2]);
    var files: std.ArrayList(File) = .empty;
    var sizes: c.Lines = .{};
    var analysis: c.Lines = .{};
    sizes.add("params offset_bits {d} length_bits {d} window {d} lookahead {d} max_code_length {d}",
         .{ b, k, @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(b)), (@as(usize, 1) << @as(std.math.Log2Int(usize),
         @intCast(k))) + 2, maximum });
    var original_total: usize = 0;
    var best_total: usize = 0;
    var totals = std.mem.zeroes([5]usize);
    var chosen = std.mem.zeroes([5]usize);
    for (manifest[3..]) |manifest_line| {
        var file: File = .{ .name = manifest_line[5..], .data = try readBytes(init.io, c.fmt("input/files/{s}",
             .{manifest_line[5..]})) };
        const encoded = encode(file.data, b, k, maximum);
        file.method = encoded.best;
        file.payload = encoded.payloads[file.method];
        original_total += file.data.len;
        best_total += file.payload.len;
        chosen[file.method] += 1;
        var line: c.Text = .{};
        line.add("file {s} original {d}", .{ file.name, file.data.len });
        for (methods, 0..) |name, method| {
            totals[method] += encoded.payloads[method].len;
            line.add(" {s} {d} {s}", .{ name, encoded.payloads[method].len, ratio(file.data.len, encoded.payloads[method].len) });
        }
        line.add(" best {s}", .{methods[file.method]});
        sizes.add("{s}", .{line.value()});
        const stats = encoded.lzw_stats;
        analysis.add("lzw {s} codes {d} clears {d} widths {d} {d} {d} {d} longest {d}", .{ file.name,
             stats.codes, stats.clears, stats.widths[0], stats.widths[1], stats.widths[2], stats.widths[3],
             stats.longest });
        var literals: usize = 0;
        var matches: usize = 0;
        var matched: usize = 0;
        var longest: usize = 0;
        var farthest: usize = 0;
        for (encoded.tokens) |token| {
            if (token.length > 0) {
                matches += 1;
                matched += token.length;
                longest = @max(longest, token.length);
                farthest = @max(farthest, token.distance);
            } else literals += 1;
        }
        analysis.add("lz77 {s} tokens {d} literals {d} matches {d} matched {d} longest {d} farthest {d}",
             .{ file.name, encoded.tokens.len, literals, matches, matched, longest, farthest });
        const lzh = encoded.lzh;
        analysis.add("lzh {s} mode {s} fixed_bits {d} table_bits {d} code_bits {d} halvings {d} litlen_used {d} litlen_max {d} offset_used {d} offset_max {d}",
             .{ file.name, if (lzh.dynamic) "dynamic" else "fixed", lzh.fixed_bits, lzh.table_bits,
             lzh.code_bits, lzh.halvings, lzh.litlen_used, lzh.litlen_max, lzh.offset_used, lzh.offset_max });
        var slots: c.Text = .{};
        slots.add("slots {s}", .{file.name});
        for (lzh.slots) |count| slots.add(" {d}", .{count});
        analysis.add("{s}", .{slots.value()});
        analysis.add("arith {s} bits {d} contexts {d} rescales {d}", .{ file.name, encoded.arith_stats.bits,
             encoded.arith_stats.contexts, encoded.arith_stats.rescales });
        c.append(File, &files, file);
    }
    var total: c.Text = .{};
    var choice: c.Text = .{};
    total.add("total original {d}", .{original_total});
    choice.add("chosen", .{});
    for (methods, 0..) |name, method| {
        total.add(" {s} {d} {s}", .{ name, totals[method], ratio(original_total, totals[method]) });
        choice.add(" {s} {d}", .{ name, chosen[method] });
    }
    total.add(" best {d} {s}", .{ best_total, ratio(original_total, best_total) });
    sizes.add("{s}", .{total.value()});
    sizes.add("{s}", .{choice.value()});
    const created = buildArchive(files.items, b, k);
    const verification = parse(created);
    sizes.add("archive bytes {d} entries {d} ratio {s}", .{ created.len, files.items.len, ratio(original_total, created.len) });
    sizes.add("verify entries {d} ok {d}", .{ verification.entries.items.len, verified(verification, files.items) });
    try write(init.io, "sizes.txt", sizes);
    try write(init.io, "analysis.txt", analysis);
    try write(init.io, "archive.hex", hexLines(created));
    var given: c.Bytes = .empty;
    for (textLines(try readBytes(init.io, "input/archive.hex")).data.items) |line| {
        var i: usize = 0;
        while (i < line.len) : (i += 2) c.append(u8, &given, std.fmt.parseInt(u8, line[i .. i + 2], 16) catch unreachable);
    }
    const parsed = parse(given.items);
    try write(init.io, "listing.txt", listing(parsed));
    var tested: c.Lines = .{};
    var extracted: c.Lines = .{};
    var comparison: c.Lines = .{};
    var salvage: std.ArrayList(File) = .empty;
    if (parsed.error_reason) |reason| tested.add("archive error {s}", .{reason}) else {
        const statuses = [_]Status{ .ok, .repaired, .checksum, .failed, .unsupported, .truncated, .bad_header };
        var counts = std.mem.zeroes([7]usize);
        for (parsed.entries.items) |entry| {
            for (statuses, 0..) |status, index| if (entry.status == status) {
                counts[index] += 1;
            };
            if (entry.header_cut) tested.add("entry {d} offset {d} status truncated header", .{ entry.number,
                 entry.position }) else if (!entry.valid) tested.add("entry {d} offset {d} status bad_header",
                 .{ entry.number, entry.position }) else {
                var line: c.Text = .{};
                line.add("entry {d} offset {d} name {s} method {s} status {s}", .{ entry.number, entry.position,
                     entry.name, methodName(entry.method), statusName(entry.status) });
                switch (entry.status) {
                    .repaired => line.add(" byte {d} from {d} to {d}", .{ entry.repair_position, entry.repair_from,
                         entry.repair_to }),
                    .checksum => line.add(" stored {s} computed {s}", .{ hex8(entry.stored), hex8(entry.computed) }),
                    .failed => line.add(" {s} at {d}", .{ entry.error_reason, entry.error_position }),
                    .truncated => line.add(" payload have {d} need {d}", .{ parsed.size - entry.start, entry.compressed }),
                    else => {},
                }
                tested.add("{s}", .{line.value()});
            }
        }
        var summary: c.Text = .{};
        summary.add("summary entries {d} checked {d}", .{ parsed.declared, parsed.entries.items.len });
        for (statuses, counts) |status, count| summary.add(" {s} {d}", .{ statusName(status), count });
        summary.add(" missing {d} trailing {d}", .{ parsed.declared - parsed.entries.items.len, parsed.trailing });
        tested.add("{s}", .{summary.value()});
    }
    const salvage_b = if (parsed.error_reason == null) parsed.b else b;
    const salvage_k = if (parsed.error_reason == null) parsed.k else k;
    var salvage_original: usize = 0;
    for (parsed.entries.items) |entry| if (entry.status == .ok or entry.status == .repaired) {
        const lines = textLines(entry.output.items);
        var word_count: usize = 0;
        var longest: usize = 0;
        for (lines.data.items) |line| {
            longest = @max(longest, line.len);
            var in_word = false;
            for (line) |byte| {
                if (byte == ' ') in_word = false else if (!in_word) {
                    word_count += 1;
                    in_word = true;
                }
            }
        }
        extracted.add("file {s} bytes {d} lines {d} words {d} longest {d}", .{ entry.name, entry.output.items.len,
             lines.data.items.len, word_count, longest });
        extracted.extend(lines);
        var found: ?usize = null;
        for (files.items, 0..) |file, index| if (c.eq(file.name, entry.name)) {
            found = index;
            break;
        };
        if (found) |index| compare(&comparison, entry.name, lines, textLines(files.items[index].data)) else comparison.add("archive_only {s}",
             .{entry.name});
        const encoded = encode(entry.output.items, salvage_b, salvage_k, maximum);
        const file: File = .{ .name = entry.name, .data = entry.output.items, .payload = encoded.payloads[encoded.best],
             .method = encoded.best };
        tested.add("salvage {s} method {s} compressed {d} was {s} {d}", .{ entry.name, methods[file.method],
             file.payload.len, methodName(entry.method), entry.compressed });
        salvage_original += file.data.len;
        c.append(File, &salvage, file);
    };
    for (files.items) |file| {
        var found = false;
        for (salvage.items) |intact_file| if (c.eq(file.name, intact_file.name)) {
            found = true;
        };
        if (!found) comparison.add("new {s}", .{file.name});
    }
    const salvaged = buildArchive(salvage.items, salvage_b, salvage_k);
    tested.add("salvaged entries {d} bytes {d} original {d} verified {d}", .{ salvage.items.len, salvaged.len,
         salvage_original, verified(parse(salvaged), salvage.items) });
    try write(init.io, "test_report.txt", tested);
    try write(init.io, "extracted.txt", extracted);
    try write(init.io, "compare.txt", comparison);
    try write(init.io, "salvaged.hex", hexLines(salvaged));
}
