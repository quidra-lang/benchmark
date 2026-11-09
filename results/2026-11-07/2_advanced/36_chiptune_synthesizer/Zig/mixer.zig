const std = @import("std");
const d = @import("song_parser.zig");
const instruments = @import("instruments.zig");
pub const Audio = struct {
    samples: []i64,
    lanes: [4][]i64,
    count: usize = 0,
    clipped: i64 = 0,
    pub fn init(maximum: usize) Audio {
        var audio: Audio = .{ .samples = d.alloc(i64, maximum), .lanes = undefined };
        for (&audio.lanes) |*lane| lane.* = d.alloc(i64, maximum);
        return audio;
    }
};
pub fn generate(song: *const d.Song, channels: anytype, count: usize, muted: [4]bool, audio: *Audio) void {
    for (0..count) |_| {
        var mixed: i64 = 0;
        for (channels, 0..) |*channel, k| {
            var value: i64 = 0;
            if (channel.sounding) {
                const instrument = song.instruments[channel.instrument.?].?;
                const level = instruments.waveform(instrument, channel.mode, channel.phase, channel.noise);
                value = (2 * level - 15) * channel.amplitude;
                channel.phase += channel.increment;
                if (channel.phase >= 65536) {
                    channel.phase -= 65536;
                    if (instrument.wave == .noise) instruments.clockNoise(&channel.noise, channel.mode);
                }
            }
            audio.lanes[k][audio.count] = value;
            if (!muted[k]) mixed += value;
        }
        const sample = 128 + @divFloor(song.gain * mixed, 4096);
        if (sample < 0 or sample > 255) audio.clipped += 1;
        audio.samples[audio.count] = std.math.clamp(sample, 0, 255);
        audio.count += 1;
    }
}
pub fn fade(audio: *Audio, count: usize) void {
    const n = audio.count;
    const m = @min(count, n);
    for (n - m..n) |i| audio.samples[i] = 128 + @divFloor((audio.samples[i] - 128) * d.n(n - 1 - i), d.n(m));
}
