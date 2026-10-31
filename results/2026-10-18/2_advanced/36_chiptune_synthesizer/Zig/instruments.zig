const d = @import("song_parser.zig");
const frequencies = [12]i64{ 26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388 };
pub fn waveName(wave: d.Wave) []const u8 {
    return switch (wave) {
        .pulse => "PULSE",
        .triangle => "TRIANGLE",
        .saw => "SAW",
        .noise => "NOISE",
        .table => "TABLE",
    };
}
pub fn frequency(note: i64) i64 {
    const octave = @divTrunc(note, 12);
    const base = frequencies[d.u(@mod(note, 12))];
    return if (octave >= 4) base * (@as(i64, 1) << @as(u6, @intCast(octave - 4))) else @divFloor(base,
         @as(i64, 1) << @as(u6, @intCast(4 - octave)));
}
pub fn transpose(value: i64, semitones: i64) i64 {
    return @divFloor(value * frequencies[d.u(@mod(semitones, 12))], frequencies[0]) * (@as(i64, 1) << @as(u6,
         @intCast(@divTrunc(semitones, 12))));
}
pub fn oscillation(position: i64, depth: i64, divisor: i64) i64 {
    const sine = [32]i64{ 0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
         255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24 };
    const q = @divFloor(sine[d.u(@mod(position, 32))] * depth, divisor);
    return if (position < 32) q else -q;
}
pub fn envelope(instrument: d.Instrument, age: i64, released: bool, release_age: i64, release_value: i64) i64 {
    if (released) {
        const w = age - release_age;
        return if (w < instrument.release) @divFloor(release_value * (instrument.release - 1 - w), instrument.release) else 0;
    }
    if (age < instrument.attack) return @divFloor(15 * (age + 1), instrument.attack);
    if (age < instrument.attack + instrument.decay) return 15 - @divFloor((15 - instrument.sustain) * (age - instrument.attack + 1),
         instrument.decay);
    return instrument.sustain;
}
pub fn waveform(instrument: d.Instrument, mode: usize, phase: i64, noise: i64) i64 {
    return switch (instrument.wave) {
        .pulse => if (@divTrunc(phase, 8192) < ([4]i64{ 1, 2, 4, 6 })[mode]) @as(i64, 15) else 0,
        .triangle => if (@divTrunc(phase, 2048) < 16) 15 - @divTrunc(phase, 2048) else @divTrunc(phase, 2048) - 16,
        .saw => @divTrunc(phase, 4096),
        .table => instrument.table[d.u(@divTrunc(phase, 2048))],
        .noise => if (@mod(noise, 2) == 0) @as(i64, 15) else 0,
    };
}
pub fn clockNoise(noise: *i64, mode: usize) void {
    const bit = (noise.* & 1) ^ ((noise.* >> (if (mode == 0) @as(u6, 1) else 6)) & 1);
    noise.* = @divTrunc(noise.*, 2) + bit * 16384;
}
