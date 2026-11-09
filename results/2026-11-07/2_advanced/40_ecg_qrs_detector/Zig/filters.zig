const c = @import("signal_io.zig");
pub const Signals = struct { lowpass: []i64, bandpass: []i64, derivative: []i64, squared: []i64, integrated: []i64 };
fn at(values: []const i64, index: i64) i64 {
    return if (index < 0) 0 else values[c.u(index)];
}
pub fn filter(ecg: []const i64) Signals {
    const out: Signals = .{ .lowpass = c.alloc(i64, ecg.len), .bandpass = c.alloc(i64, ecg.len), .derivative = c.alloc(i64,
         ecg.len), .squared = c.alloc(i64, ecg.len), .integrated = c.alloc(i64, ecg.len) };
    const carry = c.alloc(i64, ecg.len);
    var highpass_sum: i64 = 0;
    var square_sum: i64 = 0;
    for (ecg, 0..) |value, index| {
        const n = c.n(index);
        carry[index] = 2 * at(carry, n - 1) - at(carry, n - 2) + value - 2 * at(ecg, n - 6) + at(ecg, n - 12);
        out.lowpass[index] = @divFloor(carry[index], 32);
        highpass_sum += out.lowpass[index] - at(out.lowpass, n - 32);
        out.bandpass[index] = at(out.lowpass, n - 16) - @divFloor(highpass_sum, 32);
        out.derivative[index] = @divFloor(2 * out.bandpass[index] + at(out.bandpass, n - 1) - at(out.bandpass,
             n - 3) - 2 * at(out.bandpass, n - 4), 8);
        out.squared[index] = out.derivative[index] * out.derivative[index];
        square_sum += out.squared[index] - at(out.squared, n - 30);
        out.integrated[index] = @divFloor(square_sum, 30);
    }
    return out;
}
