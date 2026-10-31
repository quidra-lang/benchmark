const std = @import("std");
const d = @import("sequence_io.zig");
pub fn ratio(numerator: i64, denominator: i64) []const u8 {
    if (denominator == 0) return "-";
    const scaled = @divTrunc(10000 * numerator + @divTrunc(denominator, 2), denominator);
    return d.fmt("{d}.{d:0>4}", .{ @divTrunc(scaled, 10000), @mod(scaled, 10000) });
}
pub fn header(references: []const d.Reference) d.Lines {
    var out: d.Lines = .{};
    out.add("@HD\tVN:1.6\tSO:unsorted", .{});
    for (references) |reference| out.add("@SQ\tSN:{s}\tLN:{d}", .{ reference.name, reference.bases.len });
    out.add("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0", .{});
    return out;
}
pub fn record(result: d.Result, references: []const d.Reference, maximum_alternatives: usize) []const u8 {
    const read = result.read;
    if (!result.mapped) return d.fmt("{s}\t4\t*\t0\t0\t*\t*\t0\t0\t{s}\t{s}\tYM:Z:{s}", .{ read.name,
         read.bases, read.quality, result.reason });
    const alignment = result.primary;
    const reverse = alignment.strand == 1;
    const quality = d.alloc(u8, read.quality.len);
    for (quality, 0..) |*character, i| character.* = read.quality[if (reverse) read.quality.len - i - 1 else i];
    var out: d.Text = .{};
    out.add("{s}\t{d}\t{s}\t{d}\t{d}\t{s}\t*\t0\t0\t{s}\t{s}\tNM:i:{d}\tMD:Z:{s}\tAS:i:{d}\tX0:i:{d}\tX1:i:{d}\tYM:Z:{s}",
         .{ read.name, if (reverse) @as(usize, 16) else 0, references[alignment.reference].name,
         alignment.position + 1, result.mapq, alignment.cigar, if (reverse) d.reverseComplement(read.bases) else read.bases,
         quality, alignment.nm, alignment.md, result.score, result.x0, result.x1, result.method });
    if (result.other_count >= 1 and result.other_count <= maximum_alternatives) {
        out.add("\tXA:Z:", .{});
        for (result.others) |other| out.add("{s},{c}{d},{s},{d};", .{ references[other.reference].name,
             if (other.strand == 0) @as(u8, '+') else '-', other.position + 1, other.cigar,
             other.nm });
    }
    return out.value();
}
pub fn save(io: std.Io, name: []const u8, lines: d.Lines) !void {
    var text: d.Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = d.fmt("output/{s}", .{name}), .data = text.value() });
}
