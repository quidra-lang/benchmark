pub const Key = struct { class: usize, id: usize };
pub const table_keys = [4]Key{ .{ .class = 0, .id = 0 }, .{ .class = 1, .id = 0 }, .{ .class = 0,
     .id = 1 }, .{ .class = 1, .id = 1 } };
pub const table_names = [4][]const u8{ "dc_luma", "ac_luma", "dc_chroma", "ac_chroma" };
pub fn category(value: i64) usize {
    var magnitude = @abs(value);
    var out: usize = 0;
    while (magnitude > 0) : (magnitude >>= 1) out += 1;
    return out;
}
pub const Extra = struct { bits: u32, width: usize };
pub fn extraBits(value: i64) Extra {
    const size = category(value);
    return .{ .bits = @intCast(if (value >= 0) value else value + (@as(i64, 1) << @as(u6, @intCast(size))) - 1),
         .width = size };
}
pub fn amplitude(bits: u32, size: usize) i64 {
    if (size == 0) return 0;
    const value: i64 = @intCast(bits);
    return if (value >= (@as(i64, 1) << @as(u6, @intCast(size - 1)))) value else value - (@as(i64,
         1) << @as(u6, @intCast(size))) + 1;
}
pub const Huffman = struct {
    counts: [16]usize = [_]usize{0} ** 16,
    symbols: [256]u8 = [_]u8{0} ** 256,
    count: usize = 0,
    lengths: [256]usize = [_]usize{0} ** 256,
    codes: [256]u32 = [_]u32{0} ** 256,
    pub fn init(counts: [16]usize, symbols: []const u8) Huffman {
        var out: Huffman = .{ .counts = counts, .count = symbols.len };
        @memcpy(out.symbols[0..symbols.len], symbols);
        var code: u32 = 0;
        var offset: usize = 0;
        for (counts, 1..) |count, length| {
            for (0..count) |_| {
                const symbol = symbols[offset];
                offset += 1;
                out.lengths[symbol] = length;
                out.codes[symbol] = code;
                code += 1;
            }
            code *= 2;
        }
        return out;
    }
};
pub fn optimizedTable(frequencies: [256]i64) Huffman {
    var freq: [257]i64 = [_]i64{0} ** 257;
    @memcpy(freq[0..256], &frequencies);
    freq[256] = 1;
    var sizes: [257]usize = [_]usize{0} ** 257;
    var others: [257]?usize = [_]?usize{null} ** 257;
    while (true) {
        var first: ?usize = null;
        var second: ?usize = null;
        for (freq, 0..) |value, i| {
            if (value > 0 and (first == null or value < freq[first.?] or (value == freq[first.?] and i > first.?))) first = i;
        }
        for (freq, 0..) |value, i| {
            if (i != first.? and value > 0 and (second == null or value < freq[second.?] or (value == freq[second.?] and i > second.?))) second = i;
        }
        if (second == null) break;
        var a = first.?;
        var b = second.?;
        freq[a] += freq[b];
        freq[b] = 0;
        sizes[a] += 1;
        while (others[a]) |next| {
            a = next;
            sizes[a] += 1;
        }
        others[a] = b;
        sizes[b] += 1;
        while (others[b]) |next| {
            b = next;
            sizes[b] += 1;
        }
    }
    var counts: [257]usize = [_]usize{0} ** 257;
    var longest: usize = 0;
    for (sizes) |size| {
        if (size > 0) {
            counts[size] += 1;
            longest = @max(longest, size);
        }
    }
    var length = longest;
    while (length >= 17) : (length -= 1) {
        while (counts[length] > 0) {
            var shorter = length - 2;
            while (counts[shorter] == 0) shorter -= 1;
            counts[length] -= 2;
            counts[length - 1] += 1;
            counts[shorter + 1] += 2;
            counts[shorter] -= 1;
        }
    }
    longest = 16;
    while (counts[longest] == 0) longest -= 1;
    counts[longest] -= 1;
    var symbols: [256]u8 = undefined;
    var count: usize = 0;
    for (1..257) |size| for (0..256) |symbol| {
        if (sizes[symbol] == size) {
            symbols[count] = @intCast(symbol);
            count += 1;
        }
    };
    var result: [16]usize = undefined;
    for (0..16) |i| result[i] = counts[i + 1];
    return Huffman.init(result, symbols[0..count]);
}
