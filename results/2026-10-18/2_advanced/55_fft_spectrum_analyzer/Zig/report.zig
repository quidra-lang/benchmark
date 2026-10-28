const std = @import("std");
const c = @import("signal_io.zig");
pub fn real(value: f64) []const u8 {
    const amount: i64 = @intFromFloat(@floor(@abs(value) * 10000 + 0.5));
    return c.fmt("{s}{d}.{d:0>4}", .{ if (value < 0 and amount != 0) "-" else "", @divTrunc(amount,
         10000), @mod(amount, 10000) });
}
pub fn shadeLine(frequency: f64, magnitudes: []const []f64, bin: usize, maximum: f64, band: usize) []const u8 {
    var out: c.Text = .{};
    const frequency_text = real(frequency);
    const spaces = c.alloc(u8, if (frequency_text.len < 9) 9 - frequency_text.len else 0);
    @memset(spaces, ' ');
    out.add("{s}{s} |", .{ spaces, frequency_text });
    const characters = " .:-=+*#%@";
    for (magnitudes) |frame| {
        const db = 20 * @log10(frame[bin] / maximum);
        const level = @max(0, 9 - @as(i64, @intFromFloat(@floor(-db / c.f(band)))));
        out.add("{c}", .{characters[c.u(level)]});
    }
    out.add("|", .{});
    return out.value();
}
pub fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var text_value: c.Text = .{};
    for (lines.data.items) |line| text_value.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = text_value.value() });
}
