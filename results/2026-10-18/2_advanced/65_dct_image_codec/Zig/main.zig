const std = @import("std");
const d = @import("image_io.zig");
const color = @import("color.zig");
const transform = @import("dct.zig");
const entropy = @import("entropy.zig");
const bits = @import("bitstream.zig");
const Component = struct { identifier: usize, h: usize, v: usize, tq: usize, td: usize, ta: usize };
const Block = struct { mcu: usize, component: usize, bx: usize, by: usize };
const Interval = struct { first: usize, count: usize };
const Layout = struct {
    width: usize,
    height: usize,
    restart: usize,
    hmax: usize = 0,
    vmax: usize = 0,
    mx: usize = 0,
    my: usize = 0,
    mcus: usize = 0,
    blocks_per_mcu: usize = 0,
    components: [3]Component,
    factors: [3]d.Factor = undefined,
    blocks: []const Block = &.{},
    intervals: []const Interval = &.{},
    fn init(width: usize, height: usize, components: [3]Component, restart: usize) Layout {
        var out: Layout = .{ .width = width, .height = height, .components = components, .restart = restart };
        for (components, 0..) |component, k| {
            out.factors[k] = .{ .h = component.h, .v = component.v };
            out.hmax = @max(out.hmax, component.h);
            out.vmax = @max(out.vmax, component.v);
            out.blocks_per_mcu += component.h * component.v;
        }
        out.mx = (width + 8 * out.hmax - 1) / (8 * out.hmax);
        out.my = (height + 8 * out.vmax - 1) / (8 * out.vmax);
        out.mcus = out.mx * out.my;
        var blocks: std.ArrayList(Block) = .empty;
        for (0..out.mcus) |mcu| for (components, 0..) |component, k| {
            for (0..component.v) |v| for (0..component.h) |h| {
                d.append(Block, &blocks, .{ .mcu = mcu, .component = k, .bx = component.h * (mcu % out.mx) + h,
                     .by = component.v * (mcu / out.mx) + v });
            };
        };
        out.blocks = blocks.items;
        const step = if (restart > 0) restart else out.mcus;
        var intervals: std.ArrayList(Interval) = .empty;
        var first: usize = 0;
        while (first < out.mcus) : (first += step) d.append(Interval, &intervals, .{ .first = first,
             .count = @min(step, out.mcus - first) });
        out.intervals = intervals.items;
        return out;
    }
    fn standard(width: usize, height: usize, h: usize, v: usize, restart: usize) Layout {
        return init(width, height, .{ .{ .identifier = 1, .h = h, .v = v, .tq = 0, .td = 0,
             .ta = 0 }, .{ .identifier = 2, .h = 1, .v = 1, .tq = 1, .td = 1, .ta = 1 }, .{ .identifier = 3,
             .h = 1, .v = 1, .tq = 1, .td = 1, .ta = 1 } }, restart);
    }
};
const Prepared = struct { layout: Layout, planes: [3]d.Plane = undefined, quantization: d.Quantization,
     coefficients: []const d.Sequence };
const Symbol = struct { table: entropy.Key, value: u8, extra: u32, width: usize };
const Encoded = struct { prepared: *const Prepared, tables: d.Tables = [_][16]?entropy.Huffman{[_]?entropy.Huffman{null} ** 16} ** 2,
     frequencies: [2][16][256]i64 = std.mem.zeroes([2][16][256]i64), differences: []i64 = &.{},
     block_bits: []usize = &.{}, intervals: [][4]usize = &.{}, data: []const u8 = &.{}, header_bytes: usize = 0,
     scan_bytes: usize = 0, padding: usize = 0, stuffed: usize = 0 };
const Segment = struct { position: usize, name: []const u8, length: usize };
const Decoded = struct { layout: Layout = undefined, quantization: d.Quantization = [_]?d.Matrix{null} ** 4,
     tables: d.Tables = [_][16]?entropy.Huffman{[_]?entropy.Huffman{null} ** 16} ** 2, coefficients: []d.Sequence = &.{},
     planes: [3]d.Plane = undefined, full_planes: [3]d.Plane = undefined, image: d.Image = undefined,
     segments: std.ArrayList(Segment) = .empty, states: [][]const u8 = &.{}, scan_start: usize = 0,
     scan_bytes: usize = 0 };
fn append(out: *std.ArrayList(u8), values: []const u8) void {
    out.appendSlice(d.allocator, values) catch @panic("allocation failed");
}
fn word(out: *std.ArrayList(u8), value: usize) void {
    d.append(u8, out, @intCast(value / 256));
    d.append(u8, out, @intCast(value % 256));
}
fn readWord(bytes: []const u8, position: usize) usize {
    return 256 * @as(usize, bytes[position]) + bytes[position + 1];
}
fn segment(marker: u8, contents: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    append(&out, &.{ 255, marker });
    word(&out, contents.len + 2);
    append(&out, contents);
    return out.items;
}
fn readSymbol(reader: *bits.Reader, table: entropy.Huffman) bits.DecodeError!u8 {
    var code: u32 = 0;
    for (1..17) |length| {
        code = 2 * code + try reader.bit();
        for (table.symbols[0..table.count]) |symbol| {
            if (table.lengths[symbol] == length and table.codes[symbol] == code) return symbol;
        }
    }
    return error.Code;
}
fn decodeBlock(reader: *bits.Reader, index: usize, component: Component, tables: *const d.Tables,
     predictors: *[3]i64) bits.DecodeError!d.Sequence {
    var out: d.Sequence = [_]i64{0} ** 64;
    const size = try readSymbol(reader, tables[0][component.td].?);
    const difference = entropy.amplitude(try reader.read(size), size);
    predictors[index] += difference;
    out[0] = predictors[index];
    var i: usize = 1;
    while (i <= 63) {
        const symbol = try readSymbol(reader, tables[1][component.ta].?);
        if (symbol == 0) break;
        const run = symbol / 16;
        const width = symbol % 16;
        i += run;
        if (i > 63) return error.Index;
        if (width > 0) out[i] = entropy.amplitude(try reader.read(width), width);
        i += 1;
    }
    return out;
}
fn decodeInterval(reader: *bits.Reader, layout: Layout, tables: *const d.Tables, j: usize,
     mcu: *usize, temporary: []d.Sequence) bits.DecodeError!void {
    const interval = layout.intervals[j];
    const first = interval.first * layout.blocks_per_mcu;
    const last = (interval.first + interval.count) * layout.blocks_per_mcu;
    var predictors: [3]i64 = .{ 0, 0, 0 };
    for (first..last) |number| {
        const block = layout.blocks[number];
        mcu.* = block.mcu;
        temporary[number - first] = try decodeBlock(reader, block.component, layout.components[block.component],
             tables, &predictors);
    }
    reader.discard();
    const expected: u8 = if (j + 1 < layout.intervals.len) @intCast(0xd0 + j % 8) else 0xd9;
    if (reader.data[reader.position] != 255 or reader.data[reader.position + 1] != expected) {
        mcu.* = interval.first + interval.count - 1;
        return error.Sync;
    }
}
const Codec = struct {
    source: *const d.SourceTables,
    fn header(_: Codec, prepared: *const Prepared, tables: *const d.Tables) []const u8 {
        const layout = prepared.layout;
        var out: std.ArrayList(u8) = .empty;
        var contents: std.ArrayList(u8) = .empty;
        append(&out, &.{ 255, 0xd8 });
        for (0..2) |id| {
            d.append(u8, &contents, @intCast(id));
            for (transform.zigzag(prepared.quantization[id].?)) |value| d.append(u8, &contents, @intCast(value));
        }
        append(&out, segment(0xdb, contents.items));
        contents = .empty;
        d.append(u8, &contents, 8);
        word(&contents, layout.height);
        word(&contents, layout.width);
        d.append(u8, &contents, 3);
        for (layout.components) |component| append(&contents, &.{ @intCast(component.identifier),
             @intCast(16 * component.h + component.v), @intCast(component.tq) });
        append(&out, segment(0xc0, contents.items));
        contents = .empty;
        for (entropy.table_keys) |key| {
            const table = tables[key.class][key.id].?;
            d.append(u8, &contents, @intCast(16 * key.class + key.id));
            for (table.counts) |count| d.append(u8, &contents, @intCast(count));
            append(&contents, table.symbols[0..table.count]);
        }
        append(&out, segment(0xc4, contents.items));
        if (layout.restart > 0) {
            contents = .empty;
            word(&contents, layout.restart);
            append(&out, segment(0xdd, contents.items));
        }
        contents = .empty;
        d.append(u8, &contents, 3);
        for (layout.components) |component| append(&contents, &.{ @intCast(component.identifier),
             @intCast(16 * component.td + component.ta) });
        append(&contents, &.{ 0, 63, 0 });
        append(&out, segment(0xda, contents.items));
        return out.items;
    }
    fn restore(self: Codec, decoded: *Decoded) void {
        const layout = decoded.layout;
        for (0..3) |k| {
            const width = 8 * layout.components[k].h * layout.mx;
            const height = 8 * layout.components[k].v * layout.my;
            decoded.planes[k] = .{ .width = width, .height = height, .pixels = d.alloc(i64, width * height) };
        }
        for (layout.blocks, 0..) |block, number| {
            const values = transform.inverse(transform.dequantize(decoded.coefficients[number],
                 decoded.quantization[layout.components[block.component].tq].?, 64), self.source.transform);
            const plane = decoded.planes[block.component];
            for (0..8) |y| for (0..8) |x| {
                plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x] = values[y][x];
            };
        }
        decoded.full_planes = color.upsample(decoded.planes, layout.factors, layout.width, layout.height);
        decoded.image = color.combineRGB(decoded.full_planes);
    }
    fn prepare(self: Codec, image: d.Image, quality: usize, sampling: usize, restart: usize) *Prepared {
        const h: usize = if (sampling == 444) 1 else 2;
        const v: usize = if (sampling == 420) 2 else 1;
        const layout = Layout.standard(image.width, image.height, h, v, restart);
        const planes = color.componentPlanes(color.splitPlanes(image), layout.factors, layout.mx, layout.my);
        const quantization = transform.quantizationTables(self.source.basic, quality);
        const coefficients = d.alloc(d.Sequence, layout.blocks.len);
        for (layout.blocks, 0..) |block, number| {
            const plane = planes[block.component];
            var values: d.Matrix = undefined;
            for (0..8) |y| for (0..8) |x| {
                values[y][x] = plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
            };
            coefficients[number] = transform.zigzag(transform.quantize(transform.forward(values,
                 self.source.transform), quantization[if (block.component == 0) @as(usize,
                 0) else 1].?));
        }
        return d.create(Prepared, .{ .layout = layout, .planes = planes, .quantization = quantization,
             .coefficients = coefficients });
    }
    fn encodePrepared(self: Codec, prepared: *const Prepared, optimized: bool) *Encoded {
        const out = d.create(Encoded, .{ .prepared = prepared });
        const layout = prepared.layout;
        const symbols = d.alloc(std.ArrayList(Symbol), layout.blocks.len);
        for (symbols) |*list| list.* = .empty;
        out.differences = d.alloc(i64, layout.blocks.len);
        for (layout.intervals) |interval| {
            var predictors: [3]i64 = .{ 0, 0, 0 };
            for (interval.first * layout.blocks_per_mcu..(interval.first + interval.count) * layout.blocks_per_mcu) |number| {
                const block = layout.blocks[number];
                const component = layout.components[block.component];
                const sequence = prepared.coefficients[number];
                const difference = sequence[0] - predictors[block.component];
                predictors[block.component] = sequence[0];
                out.differences[number] = difference;
                var extra = entropy.extraBits(difference);
                const block_symbols = &symbols[number];
                d.append(Symbol, block_symbols, .{ .table = .{ .class = 0, .id = component.td },
                     .value = @intCast(extra.width), .extra = extra.bits, .width = extra.width });
                var run: usize = 0;
                for (sequence[1..]) |value| {
                    if (value == 0) {
                        run += 1;
                        continue;
                    }
                    while (run >= 16) {
                        d.append(Symbol, block_symbols, .{ .table = .{ .class = 1, .id = component.ta },
                             .value = 0xf0, .extra = 0, .width = 0 });
                        run -= 16;
                    }
                    extra = entropy.extraBits(value);
                    d.append(Symbol, block_symbols, .{ .table = .{ .class = 1, .id = component.ta },
                         .value = @intCast(16 * run + extra.width), .extra = extra.bits, .width = extra.width });
                    run = 0;
                }
                if (run > 0) d.append(Symbol, block_symbols, .{ .table = .{ .class = 1, .id = component.ta },
                     .value = 0, .extra = 0, .width = 0 });
                for (block_symbols.items) |symbol| out.frequencies[symbol.table.class][symbol.table.id][symbol.value] += 1;
            }
        }
        for (entropy.table_keys) |key| out.tables[key.class][key.id] = if (optimized) entropy.optimizedTable(out.frequencies[key.class][key.id]) else self.source.huffman[key.class][key.id];
        const header_bytes = self.header(prepared, &out.tables);
        var writer: bits.Writer = .{};
        out.block_bits = d.alloc(usize, layout.blocks.len);
        @memset(out.block_bits, 0);
        out.intervals = d.alloc([4]usize, layout.intervals.len);
        for (layout.intervals, 0..) |interval, j| {
            if (j > 0) writer.restart(j - 1);
            const start = writer.data.items.len;
            for (interval.first * layout.blocks_per_mcu..(interval.first + interval.count) * layout.blocks_per_mcu) |number| {
                for (symbols[number].items) |symbol| {
                    const table = out.tables[symbol.table.class][symbol.table.id].?;
                    writer.write(table.codes[symbol.value], table.lengths[symbol.value]);
                    writer.write(symbol.extra, symbol.width);
                    out.block_bits[number] += table.lengths[symbol.value] + symbol.width;
                }
            }
            writer.pad();
            out.intervals[j] = .{ interval.first, interval.count, header_bytes.len + start,
                 writer.data.items.len - start };
        }
        out.header_bytes = header_bytes.len;
        out.scan_bytes = writer.data.items.len;
        out.padding = writer.padding;
        out.stuffed = writer.stuffed;
        var data: std.ArrayList(u8) = .empty;
        append(&data, header_bytes);
        append(&data, writer.data.items);
        append(&data, &.{ 255, 0xd9 });
        out.data = data.items;
        return out;
    }
    fn encode(self: Codec, image: d.Image, quality: usize, sampling: usize, optimized: bool, restart: usize) *Encoded {
        return self.encodePrepared(self.prepare(image, quality, sampling, restart), optimized);
    }
    fn decode(self: Codec, data: []const u8) *Decoded {
        const out = d.create(Decoded, .{});
        var position: usize = 2;
        var width: usize = 0;
        var height: usize = 0;
        var restart: usize = 0;
        var components: [3]Component = undefined;
        d.append(Segment, &out.segments, .{ .position = 0, .name = "SOI", .length = 0 });
        while (true) {
            const marker = data[position + 1];
            const length = readWord(data, position + 2);
            const start = position + 4;
            const end = position + length + 2;
            const name: []const u8 = if (marker >= 0xe0 and marker <= 0xef) d.fmt("APP{d}",
                 .{marker - 0xe0}) else switch (marker) {
                0xc0 => "SOF0",
                0xc4 => "DHT",
                0xdb => "DQT",
                0xdd => "DRI",
                0xda => "SOS",
                else => "COM",
            };
            d.append(Segment, &out.segments, .{ .position = position, .name = name, .length = length });
            if (marker == 0xdb) {
                var p = start;
                while (p < end) : (p += 65) {
                    const id = data[p];
                    var table: d.Matrix = undefined;
                    for (transform.zigzagOrder(), 0..) |point, i| table[point.u][point.v] = data[p + 1 + i];
                    out.quantization[id] = table;
                }
            } else if (marker == 0xc4) {
                var p = start;
                while (p < end) {
                    const identifier = data[p];
                    p += 1;
                    var counts: [16]usize = undefined;
                    var total: usize = 0;
                    for (&counts) |*count| {
                        count.* = data[p];
                        p += 1;
                        total += count.*;
                    }
                    out.tables[identifier / 16][identifier % 16] = entropy.Huffman.init(counts, data[p .. p + total]);
                    p += total;
                }
            } else if (marker == 0xc0) {
                height = readWord(data, start + 1);
                width = readWord(data, start + 3);
                for (0..3) |k| {
                    const p = start + 6 + 3 * k;
                    components[k] = .{ .identifier = data[p], .h = data[p + 1] / 16, .v = data[p + 1] % 16,
                         .tq = data[p + 2], .td = 0, .ta = 0 };
                }
            } else if (marker == 0xdd) restart = readWord(data, start) else if (marker == 0xda) {
                for (0..3) |k| {
                    const p = start + 1 + 2 * k;
                    components[k].td = data[p + 1] / 16;
                    components[k].ta = data[p + 1] % 16;
                }
            }
            position = end;
            if (marker == 0xda) break;
        }
        out.scan_start = position;
        out.scan_bytes = data.len - 2 - position;
        d.append(Segment, &out.segments, .{ .position = data.len - 2, .name = "EOI", .length = 0 });
        out.layout = Layout.init(width, height, components, restart);
        const layout = out.layout;
        out.coefficients = d.alloc(d.Sequence, layout.blocks.len);
        for (out.coefficients) |*sequence| @memset(sequence, 0);
        out.states = d.alloc([]const u8, layout.intervals.len);
        @memset(out.states, "lost");
        var reader: bits.Reader = .{ .data = data, .position = position };
        var j: usize = 0;
        while (j < layout.intervals.len) {
            const interval = layout.intervals[j];
            const first = interval.first * layout.blocks_per_mcu;
            const last = (interval.first + interval.count) * layout.blocks_per_mcu;
            var mcu = interval.first;
            const temporary = d.alloc(d.Sequence, last - first);
            decodeInterval(&reader, layout, &out.tables, j, &mcu, temporary) catch |decode_error| {
                const offset = reader.position;
                reader.discard();
                const resync = bits.findResync(data, offset);
                const kind: []const u8 = switch (decode_error) {
                    error.Marker => "marker",
                    error.Code => "code",
                    error.Index => "index",
                    error.Sync => "sync",
                };
                out.states[j] = d.fmt("damaged {s} mcu {d} offset {d} resync {d}", .{ kind, mcu, offset, resync });
                if (data[resync + 1] == 0xd9) break;
                const marker = @as(i64, data[resync + 1]) - 0xd0;
                const next = j + 1 + d.u(@mod(marker - d.n(j), 8));
                reader.position = resync + 2;
                j = next;
                continue;
            };
            @memcpy(out.coefficients[first..last], temporary);
            out.states[j] = "ok";
            reader.position += 2;
            j += 1;
        }
        self.restore(out);
        return out;
    }
};
fn psnr(a: []const i64, b: []const i64) []const u8 {
    var sum: i64 = 0;
    for (a, b) |x, y| {
        const difference = x - y;
        sum += difference * difference;
    }
    if (sum == 0) return "inf";
    const value = 10 * @log10(65025.0 * @as(f64, @floatFromInt(a.len)) / @as(f64, @floatFromInt(sum)));
    return d.fmt("{d:.2}", .{value});
}
fn channels(image: d.Image) []const i64 {
    const out = d.alloc(i64, 3 * image.pixels.len);
    for (image.pixels, 0..) |pixel, i| for (pixel, 0..) |value, c| {
        out[3 * i + c] = value;
    };
    return out;
}
const Quality = struct { planes: [3][]const u8, rgb: []const u8, maximum: i64 = 0 };
fn quality(original: d.Image, decoded: *const Decoded) Quality {
    var out: Quality = undefined;
    out.maximum = 0;
    const planes = color.splitPlanes(original);
    for (0..3) |k| out.planes[k] = psnr(planes[k].pixels, decoded.full_planes[k].pixels);
    const before = channels(original);
    const after = channels(decoded.image);
    out.rgb = psnr(before, after);
    for (before, after) |x, y| out.maximum = @max(out.maximum, @as(i64, @intCast(@abs(x - y))));
    return out;
}
fn fraction(a: i64, b: i64) []const u8 {
    var x = a;
    var y = b;
    while (y != 0) {
        const next = @mod(x, y);
        x = y;
        y = next;
    }
    return d.fmt("{d}/{d}", .{ @divTrunc(a, x), @divTrunc(b, x) });
}
fn blockValues(plane: d.Plane, block: Block) d.Matrix {
    var out: d.Matrix = undefined;
    for (0..8) |y| for (0..8) |x| {
        out[y][x] = plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x];
    };
    return out;
}
fn blockErrors(encoded: *const Encoded, decoded: *const Decoded) []const i64 {
    const out = d.alloc(i64, encoded.prepared.layout.blocks.len);
    @memset(out, 0);
    for (encoded.prepared.layout.blocks, 0..) |block, number| {
        const a = blockValues(encoded.prepared.planes[block.component], block);
        const b = blockValues(decoded.planes[block.component], block);
        for (0..8) |y| for (0..8) |x| {
            const difference = a[y][x] - b[y][x];
            out[number] += difference * difference;
        };
    }
    return out;
}
fn thumbnail(decoded: *const Decoded) d.Image {
    const layout = decoded.layout;
    const width = (layout.width + 7) / 8;
    const height = (layout.height + 7) / 8;
    const pixels = d.alloc(d.Pixel, width * height);
    var dc: [3][8][8]i64 = std.mem.zeroes([3][8][8]i64);
    for (layout.blocks, 0..) |block, i| dc[block.component][block.by][block.bx] = decoded.coefficients[i][0];
    for (0..height) |y| for (0..width) |x| {
        var pixel: d.Pixel = undefined;
        for (layout.components, 0..) |component, k| {
            const bx = x * component.h / layout.hmax;
            const by = y * component.v / layout.vmax;
            const value = dc[k][by][bx];
            const divisor = decoded.quantization[component.tq].?[0][0];
            pixel[k] = color.clamp(@divFloor(value * divisor + 4, 8) + 128);
        }
        pixels[y * width + x] = color.toRGB(pixel);
    };
    return .{ .width = width, .height = height, .pixels = pixels };
}
fn huffmanReport(encoded: *const Encoded) d.Lines {
    var out: d.Lines = .{};
    const digits = "0123456789abcdef";
    for (entropy.table_keys, 0..) |key, index| {
        const table = encoded.tables[key.class][key.id].?;
        const frequencies = encoded.frequencies[key.class][key.id];
        var coded: i64 = 0;
        var code_bits: i64 = 0;
        for (table.symbols[0..table.count]) |symbol| {
            coded += frequencies[symbol];
            code_bits += frequencies[symbol] * d.n(table.lengths[symbol]);
        }
        out.add("table {s} class {d} id {d} symbols {d} coded {d} bits {d}", .{ entropy.table_names[index],
             key.class, key.id, table.count, coded, code_bits });
        var row: d.Text = .{};
        row.add("counts", .{});
        for (table.counts) |count| row.add(" {d}", .{count});
        out.add("{s}", .{row.value()});
        for (table.symbols[0..table.count]) |symbol| {
            const length = table.lengths[symbol];
            const code = d.alloc(u8, length);
            for (0..length) |i| code[i] = if (((table.codes[symbol] >> @as(u5, @intCast(length - 1 - i))) & 1) != 0) '1' else '0';
            out.add("symbol {c}{c} length {d} code {s} count {d}", .{ digits[symbol / 16],
                 digits[symbol % 16], length, code, frequencies[symbol] });
        }
    }
    return out;
}
const component_names = [3][]const u8{ "Y", "Cb", "Cr" };
fn blocksReport(encoded: *const Encoded, errors: []const i64) d.Lines {
    var out: d.Lines = .{};
    const layout = encoded.prepared.layout;
    out.add("blocks {d}", .{layout.blocks.len});
    for (layout.blocks, 0..) |block, number| {
        const sequence = encoded.prepared.coefficients[number];
        var nonzero: usize = 0;
        var last: usize = 0;
        for (1..64) |i| {
            if (sequence[i] != 0) {
                nonzero += 1;
                last = i;
            }
        }
        out.add("block {d} {s} {d} {d} dc {d} diff {d} nonzero {d} last {d} bits {d} sse {d}",
             .{ number, component_names[block.component], block.bx, block.by, sequence[0],
             encoded.differences[number], nonzero, last, encoded.block_bits[number], errors[number] });
    }
    return out;
}
fn referenceReport(encoded: *const Encoded, sampling: usize, quality_value: usize, optimized: bool,
     errors: []const i64) d.Lines {
    const layout = encoded.prepared.layout;
    var out: d.Lines = .{};
    out.add("image {d} {d}", .{ layout.width, layout.height });
    out.add("sampling {d} mcu {d} {d} grid {d} {d}", .{ sampling, 8 * layout.hmax, 8 * layout.vmax,
         layout.mx, layout.my });
    out.add("padded {d} {d}", .{ 8 * layout.hmax * layout.mx, 8 * layout.vmax * layout.my });
    var counts: [3]i64 = .{ 0, 0, 0 };
    var code_bits: [3]i64 = .{ 0, 0, 0 };
    var nonzero: [3]i64 = .{ 0, 0, 0 };
    var sse: [3]i64 = .{ 0, 0, 0 };
    var frequency: [64]i64 = [_]i64{0} ** 64;
    var zero_ac: i64 = 0;
    for (layout.blocks, 0..) |block, number| {
        counts[block.component] += 1;
        code_bits[block.component] += d.n(encoded.block_bits[number]);
        sse[block.component] += errors[number];
        var any = false;
        for (encoded.prepared.coefficients[number], 0..) |value, i| {
            if (value != 0) {
                nonzero[block.component] += 1;
                frequency[i] += 1;
                if (i > 0) any = true;
            }
        }
        zero_ac += @intFromBool(!any);
    }
    out.add("blocks {d} {d} {d}", .{ counts[0], counts[1], counts[2] });
    out.add("restart_interval {d} markers {d}", .{ layout.restart, layout.intervals.len - 1 });
    out.add("huffman {s}", .{if (optimized) "optimized" else "standard"});
    out.add("quality {d}", .{quality_value});
    for (0..2) |id| {
        var row: d.Text = .{};
        row.add("quant {d}", .{id});
        for (transform.zigzag(encoded.prepared.quantization[id].?)) |value| row.add(" {d}", .{value});
        out.add("{s}", .{row.value()});
    }
    var symbols: d.Text = .{};
    symbols.add("symbols", .{});
    var eob: i64 = 0;
    var zrl: i64 = 0;
    for (entropy.table_keys) |key| {
        const values = encoded.frequencies[key.class][key.id];
        var count: i64 = 0;
        for (values) |value| count += value;
        symbols.add(" {d}", .{count});
        if (key.class == 1) {
            eob += values[0];
            zrl += values[0xf0];
        }
    }
    out.add("{s}", .{symbols.value()});
    out.add("eob {d} zrl {d}", .{ eob, zrl });
    out.add("zero_ac_blocks {d}", .{zero_ac});
    var row: d.Text = .{};
    row.add("nonzero", .{});
    for (frequency) |value| row.add(" {d}", .{value});
    out.add("{s}", .{row.value()});
    for (0..3) |k| out.add("component {s} bits {d} nonzero {d} sse {d}", .{ component_names[k],
         code_bits[k], nonzero[k], sse[k] });
    out.add("padding_bits {d}", .{encoded.padding});
    out.add("stuffed_bytes {d}", .{encoded.stuffed});
    out.add("header_bytes {d}", .{encoded.header_bytes});
    out.add("scan_bytes {d}", .{encoded.scan_bytes});
    out.add("total_bytes {d}", .{encoded.data.len});
    for (encoded.intervals, 0..) |interval, j| out.add("interval {d} {d} {d} {d} {d}", .{ j,
         interval[0], interval[1], interval[2], interval[3] });
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    const io = init.io;
    const image = try d.readPPM(io, "input/image.ppm");
    const p = try d.readParams(io);
    const source = try d.readTables(io);
    const codec: Codec = .{ .source = source };
    var rates: d.Lines = .{};
    rates.add("quality,bytes_standard,bytes_optimized,bpp,psnr_y,psnr_cb,psnr_cr,psnr_rgb,max_error", .{});
    var reference: *Encoded = undefined;
    var reference_decoded: *Decoded = undefined;
    for (p.qualities, 0..) |q, index| {
        const prepared = codec.prepare(image, q, p.sampling, p.restart);
        const standard = codec.encodePrepared(prepared, false);
        const optimized = codec.encodePrepared(prepared, true);
        const selected = if (p.optimized) optimized else standard;
        const decoded = codec.decode(selected.data);
        const result = quality(image, decoded);
        rates.add("{d},{d},{d},{s},{s},{s},{s},{s},{d}", .{ q, standard.data.len, optimized.data.len,
             fraction(8 * d.n(selected.data.len), d.n(image.width * image.height)), result.planes[0],
             result.planes[1], result.planes[2], result.rgb, result.maximum });
        if (index == 0) {
            reference = selected;
            reference_decoded = decoded;
        }
    }
    const errors = blockErrors(reference, reference_decoded);
    var report = referenceReport(reference, p.sampling, p.qualities[0], p.optimized, errors);
    var histogram: [8]i64 = [_]i64{0} ** 8;
    const before = channels(image);
    const after = channels(reference_decoded.image);
    for (before, after) |a, b| {
        const difference = @abs(a - b);
        const bin: usize = if (difference == 0) 0 else if (difference == 1) 1 else if (difference < 4) 2 else if (difference < 8) 3 else if (difference < 16) 4 else if (difference < 32) 5 else if (difference < 64) 6 else 7;
        histogram[bin] += 1;
    }
    var histogram_line: d.Text = .{};
    histogram_line.add("error_histogram", .{});
    for (histogram) |value| histogram_line.add(" {d}", .{value});
    report.add("{s}", .{histogram_line.value()});
    const original_planes = color.splitPlanes(image);
    for (p.truncate) |keep| {
        var plane = reference_decoded.planes[0];
        plane.pixels = d.alloc(i64, plane.width * plane.height);
        @memset(plane.pixels, 0);
        for (reference_decoded.layout.blocks, 0..) |block, number| {
            if (block.component != 0) continue;
            const values = transform.inverse(transform.dequantize(reference_decoded.coefficients[number],
                 reference_decoded.quantization[reference_decoded.layout.components[0].tq].?,
                 keep), source.transform);
            for (0..8) |y| for (0..8) |x| {
                plane.pixels[(8 * block.by + y) * plane.width + 8 * block.bx + x] = values[y][x];
            };
        }
        const cropped = d.alloc(i64, image.width * image.height);
        for (0..image.height) |y| for (0..image.width) |x| {
            cropped[y * image.width + x] = plane.pixels[y * plane.width + x];
        };
        report.add("truncate {d} {s}", .{ keep, psnr(original_planes[0].pixels, cropped) });
    }
    for ([3]usize{ 444, 422, 420 }) |sampling| {
        const encoded = codec.encode(image, p.qualities[0], sampling, p.optimized, p.restart);
        const result = quality(image, codec.decode(encoded.data));
        report.add("sampling_compare {d} {d} {s} {s} {s}", .{ sampling, encoded.data.len, result.planes[1],
             result.planes[2], result.rgb });
    }
    var previous = image;
    for (1..p.generations + 1) |generation| {
        const encoded = codec.encode(previous, p.qualities[0], p.sampling, p.optimized, p.restart);
        const decoded = codec.decode(encoded.data);
        var changed: usize = 0;
        for (previous.pixels, decoded.image.pixels) |a, b| {
            var different = false;
            for (a, b) |x, y| different = different or x != y;
            changed += @intFromBool(different);
        }
        report.add("generation {d} {d} {s} {d}", .{ generation, encoded.data.len, psnr(before,
             channels(decoded.image)), changed });
        previous = decoded.image;
    }
    var lo: usize = 1;
    var hi: usize = 100;
    while (lo < hi) {
        const mid = (lo + hi + 1) / 2;
        const encoded = codec.encode(image, mid, p.sampling, p.optimized, p.restart);
        report.add("rate_control_step {d} {d}", .{ mid, encoded.data.len });
        if (encoded.data.len <= p.target) lo = mid else hi = mid - 1;
    }
    const controlled = codec.encode(image, lo, p.sampling, p.optimized, p.restart);
    report.add("rate_control {d} {d} {s} {s}", .{ lo, controlled.data.len, if (controlled.data.len <= p.target) "yes" else "no",
         quality(image, codec.decode(controlled.data)).rgb });
    const stream = try d.readHex(io, "input/stream.hex");
    const damaged = codec.decode(stream);
    for (damaged.segments.items) |part| report.add("stream_segment {d} {s} {d}", .{ part.position,
         part.name, part.length });
    report.add("stream_image {d} {d}", .{ damaged.layout.width, damaged.layout.height });
    for (damaged.layout.components) |component| report.add("stream_component {d} {d} {d} {d} {d} {d}",
         .{ component.identifier, component.h, component.v, component.tq, component.td, component.ta });
    for (damaged.quantization, 0..) |maybe_table, id| {
        if (maybe_table) |table| {
            var row: d.Text = .{};
            row.add("stream_quant {d}", .{id});
            for (transform.zigzag(table)) |value| row.add(" {d}", .{value});
            report.add("{s}", .{row.value()});
        }
    }
    for (damaged.tables, 0..) |tables, kind| for (tables, 0..) |maybe_table, id| {
        if (maybe_table) |table| {
            var longest: usize = 0;
            for (table.counts, 1..) |count, length| {
                if (count > 0) longest = length;
            }
            report.add("stream_huffman {d} {d} symbols {d} longest {d}", .{ kind, id, table.count, longest });
        }
    };
    var ok: usize = 0;
    var damaged_count: usize = 0;
    var lost: usize = 0;
    for (damaged.states) |state| {
        ok += @intFromBool(d.eq(state, "ok"));
        lost += @intFromBool(d.eq(state, "lost"));
        damaged_count += @intFromBool(std.mem.startsWith(u8, state, "damaged "));
    }
    report.add("stream_restart {d} intervals {d} ok {d} damaged {d} lost {d}", .{ damaged.layout.restart,
         damaged.layout.intervals.len, ok, damaged_count, lost });
    for (damaged.layout.intervals, 0..) |interval, j| report.add("stream_interval {d} {d} {d} {s}",
         .{ j, interval.first, interval.count, damaged.states[j] });
    report.add("stream_scan_bytes {d}", .{damaged.scan_bytes});
    var repair_quantization: d.Quantization = [_]?d.Matrix{null} ** 4;
    repair_quantization[0] = damaged.quantization[damaged.layout.components[0].tq];
    repair_quantization[1] = damaged.quantization[damaged.layout.components[1].tq];
    const repair = d.create(Prepared, .{ .layout = Layout.standard(damaged.layout.width, damaged.layout.height,
         damaged.layout.components[0].h, damaged.layout.components[0].v, damaged.layout.restart),
         .quantization = repair_quantization, .coefficients = damaged.coefficients });
    const repaired = codec.encodePrepared(repair, true);
    const repaired_decoded = codec.decode(repaired.data);
    var identical = true;
    for (repaired_decoded.image.pixels, damaged.image.pixels) |a, b| for (a, b) |x, y| {
        identical = identical and x == y;
    };
    report.add("repair {d} {d} {d} identical {s}", .{ repaired.data.len, repaired.header_bytes,
         repaired.scan_bytes, if (identical) "yes" else "no" });
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try d.save(io, "rate_distortion.csv", rates);
    try d.writePPM(io, "decoded.ppm", reference_decoded.image);
    try d.writeHex(io, "bitstream.hex", reference.data);
    try d.writePPM(io, "thumbnail.ppm", thumbnail(reference_decoded));
    try d.save(io, "huffman_tables.txt", huffmanReport(reference));
    try d.save(io, "blocks.txt", blocksReport(reference, errors));
    try d.writePPM(io, "stream_decoded.ppm", damaged.image);
    try d.writeHex(io, "repaired.hex", repaired.data);
    try d.save(io, "report.txt", report);
}
