const std = @import("std");
const c = @import("signal_io.zig");
const fft = @import("fft.zig");
const windows = @import("windows.zig");
const spectral = @import("spectral.zig");
const report = @import("report.zig");
fn r(value: f64) []const u8 {
    return report.real(value);
}
fn squares(values: []const f64) f64 {
    var sum: f64 = 0;
    for (values) |value| sum += value * value;
    return sum;
}
fn rms(values: []const f64) f64 {
    return @sqrt(squares(values) / c.f(values.len));
}
const Statistics = struct { detrended: []f64, mean: f64 = 0, slope: f64 = 0, rms: f64 = 0, minimum: f64 = 0,
     maximum: f64 = 0, crest: f64 = 0, skewness: f64 = 0, kurtosis: f64 = 0 };
fn preprocess(values: []const f64, fs: i64) Statistics {
    var out: Statistics = .{ .detrended = c.alloc(f64, values.len) };
    const n = values.len;
    const center = c.f(n - 1) / 2;
    for (values) |value| out.mean += value;
    out.mean /= c.f(n);
    var numerator: f64 = 0;
    var denominator: f64 = 0;
    for (values, 0..) |value, i| {
        numerator += (c.f(i) - center) * (value - out.mean);
        denominator += (c.f(i) - center) * (c.f(i) - center);
    }
    const slope = numerator / denominator;
    out.slope = slope * c.f(fs);
    var maximum: f64 = 0;
    var third: f64 = 0;
    var fourth: f64 = 0;
    out.minimum = values[0];
    out.maximum = values[0];
    for (values, out.detrended, 0..) |sample, *value, i| {
        value.* = sample - out.mean - slope * (c.f(i) - center);
        maximum = @max(maximum, @abs(value.*));
        const d = value.*;
        third += d * d * d;
        fourth += d * d * d * d;
        out.minimum = @min(out.minimum, sample);
        out.maximum = @max(out.maximum, sample);
    }
    out.rms = rms(out.detrended);
    out.crest = maximum / out.rms;
    out.skewness = (third / c.f(n)) / (out.rms * out.rms * out.rms);
    out.kurtosis = (fourth / c.f(n)) / (out.rms * out.rms * out.rms * out.rms);
    return out;
}
fn peakLess(values: []const f64, a: usize, b: usize) bool {
    return if (values[a] != values[b]) values[a] > values[b] else a < b;
}
fn peakIndices(values: []const f64, limit: usize) []const usize {
    var out: std.ArrayList(usize) = .empty;
    for (1..values.len - 1) |k| if (spectral.localMaximum(values, k)) c.append(usize, &out, k);
    std.mem.sort(usize, out.items, values, peakLess);
    return out.items[0..@min(out.items.len, limit)];
}
fn harmonicBin(amplitudes: []const f64, target: f64, width: usize) usize {
    var best: ?usize = null;
    for (1..amplitudes.len - 1) |k| if (@abs(c.f(k) - target) <= c.f(width) and (best == null or amplitudes[k] > amplitudes[best.?])) {
        best = k;
    };
    return best.?;
}
const Peak = struct { bin: usize, refined: spectral.Interpolation, level: f64, phase: f64, bandwidth: f64,
     snr: f64, coherence: f64, label: []const u8 = "" };
fn bandwidth(values: []const f64, k: usize) f64 {
    const threshold = values[k] / @sqrt(@as(f64, 2));
    const last = values.len - 1;
    var left: f64 = 0;
    var right = c.f(last);
    for (k + 1..last + 1) |j| if (values[j] <= threshold) {
        right = c.f(j - 1) + (values[j - 1] - threshold) / (values[j - 1] - values[j]);
        break;
    };
    var remaining = k;
    while (remaining > 0) {
        remaining -= 1;
        const j = remaining;
        if (values[j] <= threshold) {
            left = c.f(j + 1) - (values[j + 1] - threshold) / (values[j + 1] - values[j]);
            break;
        }
    }
    return right - left;
}
fn absolute(value: i64) i64 {
    return if (value < 0) -value else value;
}
fn lagIndex(lag: i64, size: usize) usize {
    return c.u(if (lag < 0) lag + c.n(size) else lag);
}
fn bestLag(values: []const f64, maximum: usize) i64 {
    var best = -c.n(maximum);
    var lag = -c.n(maximum);
    while (lag <= c.n(maximum)) : (lag += 1) {
        const value = values[lagIndex(lag, values.len)];
        const current = values[lagIndex(best, values.len)];
        if (value > current or (value == current and (absolute(lag) < absolute(best) or (absolute(lag) == absolute(best) and lag < best)))) best = lag;
    }
    return best;
}
fn refinedLag(values: []const f64, lag: i64) f64 {
    const neighbors = [_]f64{ values[lagIndex(lag - 1, values.len)], values[lagIndex(lag, values.len)],
         values[lagIndex(lag + 1, values.len)] };
    return c.f(lag) + spectral.interpolate(&neighbors, 1, false).position - 1;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    c.allocator = arena.allocator();
    c.backing_allocator = init.gpa;
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    const input = try c.load(init.io);
    const p = input.params;
    const fs = input.fs;
    const n = input.signal[0].len;
    const m = p.main_length;
    const kmax = m / 2;
    const statistics = [_]Statistics{ preprocess(input.signal[0], fs), preprocess(input.signal[1], fs) };
    const x = statistics[0].detrended;
    const y = statistics[1].detrended;
    const main_spectrum = spectral.spectrum(x, m, p.main_window, fs);
    const a = main_spectrum.amplitude;
    var amax = a[0];
    for (a) |value| amax = @max(amax, value);
    const noise_floor = spectral.median(a[1 .. a.len - 1]);
    const enbw = main_spectrum.figures.enbw;
    const welch_data = spectral.welch(x, y, p, fs);
    const frame_data = spectral.frames(x, p);
    var candidates: std.ArrayList(usize) = .empty;
    for (1..kmax) |k| if (spectral.localMaximum(a, k) and 20 * @log10(a[k] / amax) >= p.peak_threshold) c.append(usize,
         &candidates, k);
    std.mem.sort(usize, candidates.items, @as([]const f64, a), peakLess);
    const peaks = c.alloc(Peak, @min(candidates.items.len, p.peak_count));
    for (peaks, candidates.items[0..peaks.len]) |*peak, k| peak.* = .{ .bin = k, .refined = spectral.interpolate(a,
         k, true), .level = 20 * @log10(a[k] / amax), .phase = main_spectrum.transformed[k].argument() * 180 / fft.pi,
         .bandwidth = bandwidth(a, k) * c.f(fs) / c.f(m), .snr = 20 * @log10(a[k] / noise_floor),
         .coherence = welch_data.coherence[(2 * k * p.welch_length + m) / (2 * m)] };
    for (peaks, 0..) |*peak, index| {
        for (1..11) |h| if (@abs(peak.refined.position - c.f(h) * p.fundamental * c.f(m) / c.f(fs)) <= c.f(p.search)) {
            peak.label = c.fmt("h{d}", .{h});
            break;
        };
        const frequency = peak.refined.position * c.f(fs) / c.f(m);
        const mains: i64 = @intFromFloat(@floor(frequency / c.f(p.notch_frequency) + 0.5));
        if (peak.label.len == 0 and mains >= 1 and @abs(frequency - c.f(mains * p.notch_frequency)) <= c.f(p.notch_width)) peak.label = "mains";
        if (peak.label.len == 0) {
            for (peaks, 0..) |center, center_index| {
                if (peak.label.len > 0) break;
                for (peaks, 0..) |other, other_index| {
                    if (center_index == index or other_index == index or center_index == other_index) continue;
                    if (a[center.bin] > a[peak.bin] and a[center.bin] > a[other.bin] and @abs(peak.refined.position + other.refined.position - 2 * center.refined.position) <= 1) {
                        peak.label = c.fmt("sideband{d}", .{center_index + 1});
                        break;
                    }
                }
            }
        }
        if (peak.label.len == 0) peak.label = "other";
    }
    var harmonic_bins: [10]usize = undefined;
    var harmonics: [10]spectral.Interpolation = undefined;
    var harmonic_levels: [10]f64 = undefined;
    for (1..11) |h| {
        harmonic_bins[h - 1] = harmonicBin(a, c.f(h) * p.fundamental * c.f(m) / c.f(fs), p.search);
        harmonics[h - 1] = spectral.interpolate(a, harmonic_bins[h - 1], true);
        harmonic_levels[h - 1] = 20 * @log10(harmonics[h - 1].value / harmonics[0].value);
    }
    var harmonic_power: f64 = 0;
    for (harmonics[1..]) |harmonic| harmonic_power += harmonic.value * harmonic.value;
    const thd = @sqrt(harmonic_power) / harmonics[0].value;
    const power = c.alloc(f64, a.len);
    for (a, power) |value, *target| target.* = value * value / 2;
    var power_sum: f64 = 0;
    var fundamental_power: f64 = 0;
    var weighted: f64 = 0;
    var log_power: f64 = 0;
    for (1..kmax) |k| {
        power_sum += power[k];
        if (absolute(c.n(k) - c.n(harmonic_bins[0])) <= c.n(p.search)) fundamental_power += power[k];
        weighted += (c.f(k) * c.f(fs) / c.f(m)) * power[k];
        log_power += @log(power[k]);
    }
    const total_power = power_sum / enbw;
    const p1 = fundamental_power / enbw;
    const thdn = @sqrt((total_power - p1) / p1);
    const centroid = weighted / power_sum;
    const flatness = 10 * @log10(@exp(log_power / c.f(kmax - 1)) / (power_sum / c.f(kmax - 1)));
    var variance: f64 = 0;
    var running: f64 = 0;
    var rolloff: f64 = 0;
    var rolled = false;
    for (1..kmax) |k| {
        const frequency = c.f(k) * c.f(fs) / c.f(m);
        variance += (frequency - centroid) * (frequency - centroid) * power[k];
        running += power[k];
        if (!rolled and running >= 0.85 * power_sum) {
            rolloff = frequency;
            rolled = true;
        }
    }
    const spread = @sqrt(variance / power_sum);
    const xf = fft.dft(fft.complexValues(x, n));
    const pass = c.alloc(fft.Complex, n);
    @memset(pass, .{});
    const notch = c.dupe(fft.Complex, xf);
    const analytic = c.alloc(fft.Complex, n);
    @memset(analytic, .{});
    var kept: usize = 0;
    var removed: usize = 0;
    for (0..n) |k| {
        const g = c.n(@min(k, n - k)) * fs;
        if (p.band_low * c.n(n) <= g and g <= p.band_high * c.n(n)) {
            pass[k] = xf[k];
            kept += 1;
        }
        const harmonic = @divTrunc(2 * g + p.notch_frequency * c.n(n), 2 * p.notch_frequency * c.n(n));
        if (harmonic >= 1 and absolute(g - harmonic * p.notch_frequency * c.n(n)) <= p.notch_width * c.n(n)) {
            notch[k] = .{};
            removed += 1;
        }
        if (k >= 1 and k <= (n - 1) / 2 and p.envelope_low * c.n(n) <= c.n(k) * fs and c.n(k) * fs <= p.envelope_high * c.n(n)) analytic[k] = xf[k].scale(2);
    }
    const bandpassed = fft.realParts(fft.idft(pass));
    const notched = fft.realParts(fft.idft(notch));
    const z = fft.idft(analytic);
    const envelope = c.alloc(f64, n);
    const phases = c.alloc(f64, n);
    const centered = c.alloc(f64, n);
    var envelope_mean: f64 = 0;
    for (z, envelope, phases) |value, *amplitude, *phase| {
        amplitude.* = value.absolute();
        phase.* = value.argument();
        envelope_mean += amplitude.*;
    }
    envelope_mean /= c.f(n);
    for (envelope, centered) |value, *target| target.* = value - envelope_mean;
    const ev = fft.dft(fft.complexValues(centered, n));
    const be = c.alloc(f64, n);
    for (ev, be) |value, *target| target.* = 2 * value.absolute() / c.f(n);
    var envelope_bin: usize = 1;
    const envelope_limit = c.u(@divTrunc((p.envelope_high - p.envelope_low) * c.n(n), 2 * fs));
    for (2..envelope_limit + 1) |k| if (be[k] > be[envelope_bin]) {
        envelope_bin = k;
    };
    const envelope_peak = spectral.interpolate(be, envelope_bin, true);
    const envelope_depth = envelope_peak.value / envelope_mean;
    const instantaneous = c.alloc(f64, n - 1);
    var instantaneous_mean: f64 = 0;
    for (1..n) |i| {
        var difference = phases[i] - phases[i - 1];
        if (difference <= -fft.pi) difference += 2 * fft.pi;
        if (difference > fft.pi) difference -= 2 * fft.pi;
        const value = difference * c.f(fs) / (2 * fft.pi);
        instantaneous[i - 1] = value;
        instantaneous_mean += value;
    }
    instantaneous_mean /= c.f(n - 1);
    var instantaneous_variance: f64 = 0;
    for (instantaneous) |value| instantaneous_variance += (value - instantaneous_mean) * (value - instantaneous_mean);
    const instantaneous_std = @sqrt(instantaneous_variance / c.f(n - 1));
    const smoothed = fft.convolution(y, p.fir);
    var dc_gain: f64 = 0;
    var fundamental_gain: fft.Complex = .{};
    for (p.fir, 0..) |value, j| {
        dc_gain += value;
        fundamental_gain = fundamental_gain.add(fft.rot(2 * fft.pi * p.fundamental * c.f(j) / c.f(fs)).scale(value));
    }
    var hps_bin: ?usize = null;
    var hps_maximum = -std.math.inf(f64);
    for (1..kmax) |k| if (5 * k <= kmax and p.pitch_low * c.n(m) <= c.n(k) * fs and c.n(k) * fs <= p.pitch_high * c.n(m)) {
        var value: f64 = 0;
        for (1..6) |order| value += @log(a[order * k]);
        if (value > hps_maximum) {
            hps_maximum = value;
            hps_bin = k;
        }
    };
    const lag_low = c.u(@divTrunc(fs + p.pitch_high - 1, p.pitch_high));
    const lag_high = c.u(@divTrunc(fs, p.pitch_low));
    const q = fft.pow2(2 * n - 1);
    const bq = fft.radix2(fft.complexValues(bandpassed, q), false);
    for (bq) |*value| value.* = .{ .re = value.norm() };
    const autocorrelation = fft.realParts(fft.radix2(bq, true));
    var period_bin = lag_low;
    for (lag_low + 1..lag_high + 1) |lag| if (autocorrelation[lag] > autocorrelation[period_bin]) {
        period_bin = lag;
    };
    const period = spectral.interpolate(autocorrelation, period_bin, false);
    var crossings: usize = 0;
    for (1..n) |i| crossings += @intFromBool(bandpassed[i - 1] < 0 and bandpassed[i] >= 0);
    const zoom = fft.chirpZ(main_spectrum.windowed, fs, p.zoom_low, p.zoom_high, p.zoom_points);
    const zoom_amplitude = c.alloc(f64, zoom.len);
    for (zoom, zoom_amplitude) |value, *target| target.* = 2 * value.absolute() / main_spectrum.figures.s1;
    const zoom_peaks = peakIndices(zoom_amplitude, 3);
    const zoom_step = c.f(p.zoom_high - p.zoom_low) / c.f(p.zoom_points - 1);
    const cross_x = fft.radix2(fft.complexValues(x, q), false);
    const cross_y = fft.radix2(fft.complexValues(y, q), false);
    const phat = c.alloc(fft.Complex, q);
    for (cross_x, cross_y, phat) |*first, second, *normalized| {
        first.* = first.conjugate().mul(second);
        normalized.* = first.divide(first.absolute());
    }
    const correlation = fft.realParts(fft.radix2(cross_x, true));
    const phat_correlation = fft.realParts(fft.radix2(phat, true));
    const lag = bestLag(correlation, p.max_lag);
    const phat_lag = bestLag(phat_correlation, p.max_lag);
    const refined = refinedLag(correlation, lag);
    const phat_refined = refinedLag(phat_correlation, phat_lag);
    const coefficient = correlation[lagIndex(lag, q)] / @sqrt(squares(x) * squares(y));
    const frame_count = frame_data.magnitudes.len;
    const frame_bins = p.frame_length / 2 + 1;
    var gmax: f64 = 0;
    for (frame_data.magnitudes) |row| for (row) |value| {
        gmax = @max(gmax, value);
    };
    const dominant = c.alloc(usize, frame_count);
    const flux = c.alloc(f64, frame_count);
    @memset(flux, 0);
    const kurtosis = c.alloc(f64, frame_bins);
    for (frame_data.magnitudes, 0..) |row, t| {
        dominant[t] = 1;
        for (2..frame_bins - 1) |k| if (row[k] > row[dominant[t]]) {
            dominant[t] = k;
        };
        if (t > 0) for (0..frame_bins) |k| {
            flux[t] += @max(0, row[k] - frame_data.magnitudes[t - 1][k]);
        };
    }
    const onset_threshold = p.onset_factor * spectral.median(flux[1..]);
    var onsets: std.ArrayList(usize) = .empty;
    for (1..frame_count) |t| if (flux[t] > onset_threshold and flux[t] > flux[t - 1] and (t == frame_count - 1 or flux[t] > flux[t + 1])) c.append(usize,
         &onsets, t);
    for (0..frame_bins) |k| {
        var second: f64 = 0;
        var fourth: f64 = 0;
        for (frame_data.magnitudes) |row| {
            const square = row[k] * row[k];
            second += square;
            fourth += square * square;
        }
        kurtosis[k] = c.f(frame_count) * fourth / (second * second) - 2;
    }
    var kurtosis_bin: usize = 1;
    for (2..frame_bins - 1) |k| if (kurtosis[k] > kurtosis[kurtosis_bin]) {
        kurtosis_bin = k;
    };
    var roundtrip_error: f64 = 0;
    const inverse = fft.idft(main_spectrum.transformed);
    for (inverse, main_spectrum.windowed) |value, sample| roundtrip_error = @max(roundtrip_error,
         value.sub(.{ .re = sample }).absolute());
    var frequency_energy: f64 = 0;
    for (main_spectrum.transformed) |value| frequency_energy += value.norm();
    const time_energy = squares(main_spectrum.windowed);
    const parseval_error = @abs(time_energy - frequency_energy / c.f(m)) / time_energy;
    var fir_error: f64 = 0;
    for (smoothed, 0..) |sample, index| {
        var direct: f64 = 0;
        const first = if (index + 1 > p.fir.len) index - p.fir.len + 1 else 0;
        const last = @min(n - 1, index);
        for (first..last + 1) |j| direct += y[j] * p.fir[index - j];
        fir_error = @max(fir_error, @abs(sample - direct));
    }
    var spot_error: f64 = 0;
    for (peaks) |peak| {
        var direct: fft.Complex = .{};
        for (main_spectrum.windowed, 0..) |sample, i| direct = direct.add(fft.rot(2 * fft.pi * c.f((peak.bin * i) % m) / c.f(m)).scale(sample));
        spot_error = @max(spot_error, direct.sub(main_spectrum.transformed[peak.bin]).absolute());
    }
    const packing_error = @max(welch_data.packing_error, frame_data.packing_error);
    var spectrum_file: c.Lines = .{};
    var peak_file: c.Lines = .{};
    var welch_file: c.Lines = .{};
    var spectrogram_file: c.Lines = .{};
    var filtered_file: c.Lines = .{};
    var report_file: c.Lines = .{};
    spectrum_file.add("frequency,amplitude", .{});
    for (a, 0..) |amplitude, k| spectrum_file.add("{s},{s}", .{ r(c.f(k) * c.f(fs) / c.f(m)), r(amplitude) });
    peak_file.add("length={d} window={s} resolution={s} threshold_db={s}", .{ m, p.main_window, r(c.f(fs) / c.f(m)),
         r(p.peak_threshold) });
    peak_file.add("max_amplitude={s} noise_floor={s} noise_floor_db={s}", .{ r(amax), r(noise_floor),
         r(20 * @log10(noise_floor)) });
    peak_file.add("peaks={d}", .{peaks.len});
    for (peaks, 1..) |peak, rank| peak_file.add("{d} bin={d} frequency={s} refined={s} amplitude={s} level_db={s} phase={s} bandwidth={s} snr_db={s} coherence={s} label={s}",
         .{ rank, peak.bin, r(c.f(peak.bin) * c.f(fs) / c.f(m)), r(peak.refined.position * c.f(fs) / c.f(m)),
         r(peak.refined.value), r(peak.level), r(peak.phase), r(peak.bandwidth), r(peak.snr), r(peak.coherence),
         peak.label });
    welch_file.add("frequency,psd_db", .{});
    for (welch_data.psd, 0..) |value, k| welch_file.add("{s},{s}", .{ r(c.f(k) * c.f(fs) / c.f(p.welch_length)),
         r(10 * @log10(value)) });
    spectrogram_file.add("frames={d} bins={d} frame_length={d} hop={d} window={s} band_db={d} max_db={s}",
         .{ frame_count, frame_bins, p.frame_length, p.hop, p.frame_window, p.shade, r(20 * @log10(gmax)) });
    var remaining = frame_bins;
    while (remaining > 0) {
        remaining -= 1;
        spectrogram_file.add("{s}", .{report.shadeLine(c.f(remaining) * c.f(fs) / c.f(p.frame_length),
             frame_data.magnitudes, remaining, gmax, p.shade)});
    }
    spectrogram_file.add("track", .{});
    for (0..frame_count) |t| spectrogram_file.add("frame={d} time={s} frequency={s} level_db={s}",
         .{ t, r(c.f(t) * c.f(p.hop) / c.f(fs)), r(c.f(dominant[t]) * c.f(fs) / c.f(p.frame_length)),
         r(20 * @log10(frame_data.magnitudes[t][dominant[t]] / gmax)) });
    spectrogram_file.add("onsets={d} threshold={s}", .{ onsets.items.len, r(onset_threshold) });
    for (onsets.items) |t| spectrogram_file.add("frame={d} time={s} flux={s}", .{ t, r(c.f(t) * c.f(p.hop) / c.f(fs)),
         r(flux[t]) });
    spectrogram_file.add("kurtosis bin={d} frequency={s} value={s}", .{ kurtosis_bin, r(c.f(kurtosis_bin) * c.f(fs) / c.f(p.frame_length)),
         r(kurtosis[kurtosis_bin]) });
    filtered_file.add("index,bandpass,notched,smoothed,envelope", .{});
    for (0..n) |i| filtered_file.add("{d},{s},{s},{s},{s}", .{ i, r(bandpassed[i]), r(notched[i]),
         r(smoothed[i]), r(envelope[i]) });
    report_file.add("[signal]", .{});
    report_file.add("sample_rate={d} samples={d} duration={s}", .{ fs, n, r(c.f(n) / c.f(fs)) });
    for (statistics, 1..) |s, channel| report_file.add("channel={d} mean={s} slope={s} rms={s} min={s} max={s} crest={s} skewness={s} kurtosis={s}",
         .{ channel, r(s.mean), r(s.slope), r(s.rms), r(s.minimum), r(s.maximum), r(s.crest), r(s.skewness),
         r(s.kurtosis) });
    report_file.add("[levels]", .{});
    const blocks = n / p.block_length;
    const levels = c.alloc([3]f64, blocks);
    var loudest: usize = 0;
    for (levels, 0..) |*level, block| {
        var first: f64 = 0;
        var second: f64 = 0;
        var peak: f64 = 0;
        for (block * p.block_length..(block + 1) * p.block_length) |i| {
            first += x[i] * x[i];
            second += y[i] * y[i];
            peak = @max(peak, @abs(x[i]));
        }
        level.* = .{ @sqrt(first / c.f(p.block_length)), @sqrt(second / c.f(p.block_length)), peak };
        if (level[0] > levels[loudest][0]) loudest = block;
    }
    report_file.add("block_length={d} blocks={d} loudest={d}", .{ p.block_length, blocks, loudest });
    for (levels, 0..) |level, block| report_file.add("block={d} time={s} rms1={s} rms2={s} peak1={s}",
         .{ block, r(c.f(block) * c.f(p.block_length) / c.f(fs)), r(level[0]), r(level[1]), r(level[2]) });
    report_file.add("[windows]", .{});
    for (windows.names) |name| {
        const value = spectral.spectrum(x, m, name, fs);
        const figures = value.figures;
        const bin = harmonicBin(value.amplitude, p.fundamental * c.f(m) / c.f(fs), p.search);
        report_file.add("name={s} coherent_gain={s} enbw_bins={s} enbw_hz={s} scalloping_db={s} fundamental_bin={d} bin_amplitude={s} refined_amplitude={s} floor_db={s}",
             .{ name, r(figures.coherent), r(figures.enbw), r(figures.enbw_hz), r(figures.scalloping),
             bin, r(value.amplitude[bin]), r(spectral.interpolate(value.amplitude, bin, true).value),
             r(20 * @log10(spectral.median(value.amplitude[1 .. value.amplitude.len - 1]))) });
    }
    report_file.add("[main]", .{});
    report_file.add("length={d} window={s} method={s} transform_size={d} resolution={s}", .{ m, p.main_window,
         if (fft.powerOfTwo(m)) "radix2" else "bluestein", if (fft.powerOfTwo(m)) m else fft.pow2(2 * m - 1),
         r(c.f(fs) / c.f(m)) });
    report_file.add("total_power={s} centroid={s} spread={s} rolloff={s} flatness_db={s}", .{ r(total_power),
         r(centroid), r(spread), r(rolloff), r(flatness) });
    report_file.add("[bands]", .{});
    for (0..p.bands.len - 1) |band| {
        var sum: f64 = 0;
        for (1..kmax) |k| if (p.bands[band] * c.n(m) <= c.n(k) * fs and c.n(k) * fs < p.bands[band + 1] * c.n(m)) {
            sum += power[k];
        };
        sum /= enbw;
        report_file.add("range={d}-{d} power={s} percent={s}", .{ p.bands[band], p.bands[band + 1],
             r(sum), r(100 * sum / total_power) });
    }
    report_file.add("[third_octave]", .{});
    var band = p.third_low;
    while (band <= p.third_high) : (band += 1) {
        const center = 1000 * std.math.pow(f64, 2, c.f(band) / 3);
        const lower = 1000 * std.math.pow(f64, 2, c.f(2 * band - 1) / 6);
        const upper = 1000 * std.math.pow(f64, 2, c.f(2 * band + 1) / 6);
        var sum: f64 = 0;
        var bins: usize = 0;
        for (1..kmax) |k| {
            const frequency = c.f(k) * c.f(fs) / c.f(m);
            if (lower <= frequency and frequency < upper) {
                bins += 1;
                sum += power[k];
            }
        }
        report_file.add("band={d} center={s} lower={s} upper={s} bins={d} level_db={s}", .{ band,
             r(center), r(lower), r(upper), bins, r(10 * @log10(sum / enbw)) });
    }
    report_file.add("[harmonics]", .{});
    report_file.add("fundamental={s} search={d}", .{ r(p.fundamental), p.search });
    for (harmonics, harmonic_bins, harmonic_levels, 1..) |harmonic, bin, level, h| report_file.add("h={d} target={s} bin={d} refined={s} amplitude={s} level_db={s}",
         .{ h, r(c.f(h) * p.fundamental), bin, r(harmonic.position * c.f(fs) / c.f(m)), r(harmonic.value),
         r(level) });
    report_file.add("thd_percent={s} thd_db={s}", .{ r(100 * thd), r(20 * @log10(thd)) });
    report_file.add("thdn_percent={s} thdn_db={s}", .{ r(100 * thdn), r(20 * @log10(thdn)) });
    report_file.add("[pitch]", .{});
    report_file.add("range={d}-{d} lags={d}-{d}", .{ p.pitch_low, p.pitch_high, lag_low, lag_high });
    report_file.add("hps bin={d} order=5 frequency={s}", .{ hps_bin.?, r(c.f(hps_bin.?) * c.f(fs) / c.f(m)) });
    report_file.add("autocorrelation lag={d} period={s} frequency={s} strength={s}", .{ period_bin,
         r(period.position), r(c.f(fs) / period.position), r(period.value / autocorrelation[0]) });
    report_file.add("zero_crossing count={d} frequency={s}", .{ crossings, r(c.f(crossings) * c.f(fs) / c.f(n)) });
    report_file.add("[zoom]", .{});
    report_file.add("band={d}-{d} points={d} step={s}", .{ p.zoom_low, p.zoom_high, p.zoom_points, r(zoom_step) });
    for (zoom_peaks, 1..) |index, rank| {
        const value = spectral.interpolate(zoom_amplitude, index, true);
        report_file.add("peak={d} frequency={s} amplitude={s}", .{ rank, r(c.f(p.zoom_low) + value.position * zoom_step),
             r(value.value) });
    }
    report_file.add("[welch]", .{});
    report_file.add("segment_length={d} segments={d} window={s} resolution={s}", .{ p.welch_length,
         welch_data.segments, p.welch_window, r(c.f(fs) / c.f(p.welch_length)) });
    var integrated: f64 = 0;
    for (welch_data.psd) |value| integrated += value;
    integrated = integrated * c.f(fs) / c.f(p.welch_length);
    const signal_variance = statistics[0].rms * statistics[0].rms;
    report_file.add("integrated_power={s} variance={s} ratio={s}", .{ r(integrated), r(signal_variance),
         r(integrated / signal_variance) });
    for (peakIndices(welch_data.psd, 5), 1..) |k, rank| report_file.add("peak={d} frequency={s} psd_db={s} coherence={s} gain={s} phase={s}",
         .{ rank, r(c.f(k) * c.f(fs) / c.f(p.welch_length)), r(10 * @log10(welch_data.psd[k])), r(welch_data.coherence[k]),
         r(welch_data.transfer[k].absolute()), r(welch_data.transfer[k].argument() * 180 / fft.pi) });
    report_file.add("[filter]", .{});
    report_file.add("bandpass={d}-{d} bins_kept={d} rms={s} energy_ratio={s}", .{ p.band_low, p.band_high,
         kept, r(rms(bandpassed)), r(squares(bandpassed) / squares(x)) });
    report_file.add("notch={d} width={d} bins_removed={d} rms={s}", .{ p.notch_frequency, p.notch_width,
         removed, r(rms(notched)) });
    report_file.add("fir_taps={d} dc_gain={s} gain_at_fundamental_db={s} rms={s}", .{ p.fir.len, r(dc_gain),
         r(20 * @log10(fundamental_gain.absolute())), r(rms(smoothed[0..n])) });
    report_file.add("[envelope]", .{});
    report_file.add("band={d}-{d} mean={s} bin={d} frequency={s} amplitude={s} depth={s}", .{ p.envelope_low,
         p.envelope_high, r(envelope_mean), envelope_bin, r(envelope_peak.position * c.f(fs) / c.f(n)),
         r(envelope_peak.value), r(envelope_depth) });
    report_file.add("instantaneous_frequency mean={s} std={s}", .{ r(instantaneous_mean), r(instantaneous_std) });
    report_file.add("[correlation]", .{});
    report_file.add("max_lag={d} lag={d} refined_lag={s} delay_ms={s} coefficient={s}", .{ p.max_lag,
         lag, r(refined), r(1000 * refined / c.f(fs)), r(coefficient) });
    report_file.add("phat_lag={d} refined_lag={s} delay_ms={s}", .{ phat_lag, r(phat_refined), r(1000 * phat_refined / c.f(fs)) });
    report_file.add("[checks]", .{});
    report_file.add("inverse_roundtrip={s}", .{if (roundtrip_error <= 1e-6) "ok" else "failed"});
    report_file.add("parseval={s}", .{if (parseval_error <= 1e-6) "ok" else "failed"});
    report_file.add("real_packing={s} transforms={d}", .{ if (packing_error <= 1e-6) "ok" else "failed",
         2 * welch_data.segments + frame_count });
    report_file.add("fir_fft_vs_direct={s}", .{if (fir_error <= 1e-6) "ok" else "failed"});
    report_file.add("dft_spot_check={s} bins={d}", .{ if (spot_error <= 1e-6) "ok" else "failed", peaks.len });
    const harmonic_ratio = harmonics[1].value / harmonics[0].value;
    var loose: usize = 0;
    for (harmonic_levels[2..]) |level| loose += @intFromBool(level >= -30);
    var electrical = false;
    var mains_level: []const u8 = "none";
    for (peaks) |peak| if (c.eq(peak.label, "mains")) {
        mains_level = r(peak.level);
        electrical = peak.level >= -20;
        break;
    };
    const misalignment = harmonic_ratio >= 0.5;
    const looseness = loose >= 3;
    const bearing = envelope_depth >= 0.2;
    const transient = onsets.items.len > 0;
    const findings = @as(usize, @intFromBool(misalignment)) + @intFromBool(looseness) + @intFromBool(bearing) + @intFromBool(electrical) + @intFromBool(transient);
    report_file.add("[diagnosis]", .{});
    report_file.add("misalignment={s} ratio={s}", .{ if (misalignment) "yes" else "no", r(harmonic_ratio) });
    report_file.add("looseness={s} harmonics={d}", .{ if (looseness) "yes" else "no", loose });
    report_file.add("bearing={s} depth={s}", .{ if (bearing) "yes" else "no", r(envelope_depth) });
    report_file.add("electrical={s} level_db={s}", .{ if (electrical) "yes" else "no", mains_level });
    report_file.add("transient={s} onsets={d}", .{ if (transient) "yes" else "no", onsets.items.len });
    report_file.add("status={s} findings={d}", .{ if (findings == 0) "normal" else if (findings == 1) "warning" else "alarm",
         findings });
    try report.save(init.io, "spectrum.csv", spectrum_file);
    try report.save(init.io, "peaks.txt", peak_file);
    try report.save(init.io, "welch_psd.csv", welch_file);
    try report.save(init.io, "spectrogram.txt", spectrogram_file);
    try report.save(init.io, "filtered.csv", filtered_file);
    try report.save(init.io, "report.txt", report_file);
}
