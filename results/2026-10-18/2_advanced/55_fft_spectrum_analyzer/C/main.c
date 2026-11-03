#include "analyzer.h"
static const double pi = 3.141592653589793;
static double squares(Values values, int count) {
    if (count < 0)
        count = values.count;
    double sum = 0;
    for (int i = 0; i < count; ++i)
        sum += values.data[i] * values.data[i];
    return sum;
}
static double rms(Values values, int count) {
    if (count < 0)
        count = values.count;
    return sqrt(squares(values, count) / count);
}
static Values real_parts(Complexes values) {
    Values out = values_new(values.count);
    for (int i = 0; i < values.count; ++i)
        out.data[i] = creal(values.data[i]);
    return out;
}
static Values inverse_real(Complexes values) {
    Complexes inverse = idft(values);
    Values out = real_parts(inverse);
    release_one(inverse.data);
    return out;
}
typedef struct {
    Values detrended;
    double mean, slope, rms, minimum, maximum, crest, skewness, kurtosis;
} Statistics;
static Statistics preprocess(Values values, int fs) {
    Statistics out = {.detrended = values_new(values.count)};
    int n = values.count;
    double center = (n - 1) / 2.0;
    for (int i = 0; i < n; ++i)
        out.mean += values.data[i];
    out.mean /= n;
    double numerator = 0, denominator = 0;
    for (int i = 0; i < n; ++i) {
        numerator += (i - center) * (values.data[i] - out.mean);
        denominator += (i - center) * (i - center);
    }
    double slope = numerator / denominator;
    out.slope = slope * fs;
    double maximum = 0, third = 0, fourth = 0;
    out.minimum = out.maximum = values.data[0];
    for (int i = 0; i < n; ++i) {
        double value = values.data[i] - out.mean - slope * (i - center);
        out.detrended.data[i] = value;
        maximum = fmax(maximum, fabs(value));
        third += value * value * value;
        fourth += value * value * value * value;
        out.minimum = fmin(out.minimum, values.data[i]);
        out.maximum = fmax(out.maximum, values.data[i]);
    }
    out.rms = rms(out.detrended, -1);
    out.crest = maximum / out.rms;
    out.skewness = (third / n) / (out.rms * out.rms * out.rms);
    out.kurtosis = (fourth / n) / (out.rms * out.rms * out.rms * out.rms);
    return out;
}
static void sort_indices(Ids values, Values metrics) {
    for (int i = 1; i < values.count; ++i) {
        int value = values.data[i], j = i;
        while (j > 0) {
            int previous = values.data[j - 1];
            if (metrics.data[previous] > metrics.data[value] ||
                (metrics.data[previous] == metrics.data[value] && previous < value))
                break;
            values.data[j] = previous;
            --j;
        }
        values.data[j] = value;
    }
}
static Ids peak_indices(Values values, int limit) {
    Ids out = {.data = allocate(values.count, sizeof(int))};
    for (int k = 1; k + 1 < values.count; ++k)
        if (local_maximum(values, k))
            out.data[out.count++] = k;
    sort_indices(out, values);
    if (out.count > limit)
        out.count = limit;
    return out;
}
static int harmonic_bin(Values amplitudes, double target, int width) {
    int best = -1;
    for (int k = 1; k + 1 < amplitudes.count; ++k)
        if (fabs(k - target) <= width && (best < 0 || amplitudes.data[k] > amplitudes.data[best]))
            best = k;
    return best;
}
typedef struct {
    int bin;
    Interpolation refined;
    double level, phase, bandwidth, snr, coherence;
    const char *label;
} Peak;
static double bandwidth(Values values, int k) {
    double threshold = values.data[k] / sqrt(2.0);
    int last = values.count - 1;
    double left = 0, right = last;
    for (int j = k + 1; j <= last; ++j)
        if (values.data[j] <= threshold) {
            right = j - 1 + (values.data[j - 1] - threshold) / (values.data[j - 1] - values.data[j]);
            break;
        }
    for (int j = k - 1; j >= 0; --j)
        if (values.data[j] <= threshold) {
            left = j + 1 - (values.data[j + 1] - threshold) / (values.data[j + 1] - values.data[j]);
            break;
        }
    return right - left;
}
static int lag_index(int lag, int size) {
    return lag < 0 ? lag + size : lag;
}
static int best_lag(Values values, int maximum) {
    int best = -maximum;
    for (int lag = -maximum; lag <= maximum; ++lag) {
        double value = values.data[lag_index(lag, values.count)],
               current = values.data[lag_index(best, values.count)];
        if (value > current ||
            (value == current && (abs(lag) < abs(best) || (abs(lag) == abs(best) && lag < best))))
            best = lag;
    }
    return best;
}
static double refined_lag(Values values, int lag) {
    double data[] = {values.data[lag_index(lag - 1, values.count)], values.data[lag_index(lag, values.count)],
                     values.data[lag_index(lag + 1, values.count)]};
    Interpolation value = interpolate((Values){data, 3}, 1, false);
    return lag + value.position - 1;
}
int main(void) {
    mkdir("output", 0777);
    Input input = load();
    Params p = input.params;
    int fs = input.fs, n = input.signal[0].count, m = p.main_length, kmax = m / 2;
    Statistics statistics[] = {preprocess(input.signal[0], fs), preprocess(input.signal[1], fs)};
    Values x = statistics[0].detrended, y = statistics[1].detrended;
    Spectrum main_spectrum = spectrum(x, m, p.main_window, fs);
    Values a = main_spectrum.amplitude;
    double amax = a.data[0];
    for (int k = 1; k < a.count; ++k)
        amax = fmax(amax, a.data[k]);
    double noise_floor = median((Values){a.data + 1, a.count - 2}), enbw = main_spectrum.figures.enbw;
    Welch welch_data = welch(x, y, &p, fs);
    Frames frame_data = frames(x, &p);
    Peak peaks[20];
    Ids candidates = {.data = allocate(a.count, sizeof(int))};
    for (int k = 1; k < kmax; ++k)
        if (local_maximum(a, k) && 20 * log10(a.data[k] / amax) >= p.peak_threshold)
            candidates.data[candidates.count++] = k;
    sort_indices(candidates, a);
    if (candidates.count > p.peak_count)
        candidates.count = p.peak_count;
    int peak_count = candidates.count;
    for (int i = 0; i < peak_count; ++i) {
        int k = candidates.data[i];
        peaks[i] = (Peak){k,
                          interpolate(a, k, true),
                          20 * log10(a.data[k] / amax),
                          carg(main_spectrum.transformed.data[k]) * 180 / pi,
                          bandwidth(a, k) * fs / m,
                          20 * log10(a.data[k] / noise_floor),
                          welch_data.coherence.data[(2 * k * p.welch_length + m) / (2 * m)],
                          NULL};
    }
    for (int index = 0; index < peak_count; ++index) {
        Peak *peak = &peaks[index];
        for (int h = 1; h <= 10; ++h)
            if (fabs(peak->refined.position - h * p.fundamental * m / fs) <= p.search) {
                peak->label = format("h%d", h);
                break;
            }
        double frequency = peak->refined.position * fs / m;
        int mains = (int)floor(frequency / p.notch_frequency + 0.5);
        if (!peak->label && mains >= 1 && fabs(frequency - mains * p.notch_frequency) <= p.notch_width)
            peak->label = "mains";
        if (!peak->label)
            for (int center = 0; center < peak_count && !peak->label; ++center)
                for (int other = 0; other < peak_count; ++other) {
                    if (center == index || other == index || center == other)
                        continue;
                    if (a.data[peaks[center].bin] > a.data[peak->bin] &&
                        a.data[peaks[center].bin] > a.data[peaks[other].bin] &&
                        fabs(peak->refined.position + peaks[other].refined.position -
                             2 * peaks[center].refined.position) <= 1) {
                        peak->label = format("sideband%d", center + 1);
                        break;
                    }
                }
        if (!peak->label)
            peak->label = "other";
    }
    int harmonic_bins[10];
    Interpolation harmonics[10];
    double harmonic_levels[10];
    for (int h = 1; h <= 10; ++h) {
        harmonic_bins[h - 1] = harmonic_bin(a, h * p.fundamental * m / fs, p.search);
        harmonics[h - 1] = interpolate(a, harmonic_bins[h - 1], true);
        harmonic_levels[h - 1] = 20 * log10(harmonics[h - 1].value / harmonics[0].value);
    }
    double harmonic_power = 0;
    for (int h = 1; h < 10; ++h)
        harmonic_power += harmonics[h].value * harmonics[h].value;
    double thd = sqrt(harmonic_power) / harmonics[0].value;
    Values power = values_new(a.count);
    for (int k = 0; k <= kmax; ++k)
        power.data[k] = a.data[k] * a.data[k] / 2;
    double power_sum = 0, fundamental_power = 0, weighted = 0, log_power = 0;
    for (int k = 1; k < kmax; ++k) {
        power_sum += power.data[k];
        if (abs(k - harmonic_bins[0]) <= p.search)
            fundamental_power += power.data[k];
        weighted += ((double)k * fs / m) * power.data[k];
        log_power += log(power.data[k]);
    }
    double total_power = power_sum / enbw, p1 = fundamental_power / enbw,
           thdn = sqrt((total_power - p1) / p1), centroid = weighted / power_sum,
           flatness = 10 * log10(exp(log_power / (kmax - 1)) / (power_sum / (kmax - 1))), variance = 0,
           running = 0, rolloff = 0;
    bool rolled = false;
    for (int k = 1; k < kmax; ++k) {
        double frequency = (double)k * fs / m;
        variance += (frequency - centroid) * (frequency - centroid) * power.data[k];
        running += power.data[k];
        if (!rolled && running >= 0.85 * power_sum) {
            rolloff = frequency;
            rolled = true;
        }
    }
    double spread = sqrt(variance / power_sum);
    Complexes source = complex_values(x, -1), xf = dft(source);
    release_one(source.data);
    Complexes pass = complex_new(n), notch = complex_new(n), analytic = complex_new(n);
    memcpy(notch.data, xf.data, n * sizeof(Complex));
    int kept = 0, removed = 0;
    for (int k = 0; k < n; ++k) {
        Int g = (Int)(k < n - k ? k : n - k) * fs;
        if ((Int)p.band_low * n <= g && g <= (Int)p.band_high * n) {
            pass.data[k] = xf.data[k];
            ++kept;
        }
        Int harmonic = (2 * g + (Int)p.notch_frequency * n) / (2 * (Int)p.notch_frequency * n),
            difference = g - harmonic * p.notch_frequency * n;
        if (difference < 0)
            difference = -difference;
        if (harmonic >= 1 && difference <= (Int)p.notch_width * n) {
            notch.data[k] = 0;
            ++removed;
        }
        if (k >= 1 && k <= (n - 1) / 2 && (Int)p.envelope_low * n <= (Int)k * fs &&
            (Int)k * fs <= (Int)p.envelope_high * n)
            analytic.data[k] = 2 * xf.data[k];
    }
    Values bandpassed = inverse_real(pass), notched = inverse_real(notch);
    Complexes z = idft(analytic);
    Values envelope = values_new(n), phases = values_new(n), centered = values_new(n);
    double envelope_mean = 0;
    for (int i = 0; i < n; ++i) {
        envelope.data[i] = cabs(z.data[i]);
        phases.data[i] = carg(z.data[i]);
        envelope_mean += envelope.data[i];
    }
    envelope_mean /= n;
    for (int i = 0; i < n; ++i)
        centered.data[i] = envelope.data[i] - envelope_mean;
    source = complex_values(centered, -1);
    Complexes ev = dft(source);
    release_one(source.data);
    Values be = values_new(n);
    for (int k = 0; k < n; ++k)
        be.data[k] = 2 * cabs(ev.data[k]) / n;
    int envelope_bin = 1, envelope_limit = (p.envelope_high - p.envelope_low) * n / (2 * fs);
    for (int k = 2; k <= envelope_limit; ++k)
        if (be.data[k] > be.data[envelope_bin])
            envelope_bin = k;
    Interpolation envelope_peak = interpolate(be, envelope_bin, true);
    double envelope_depth = envelope_peak.value / envelope_mean;
    Values instantaneous = values_new(n - 1);
    double instantaneous_mean = 0;
    for (int i = 1; i < n; ++i) {
        double difference = phases.data[i] - phases.data[i - 1];
        if (difference <= -pi)
            difference += 2 * pi;
        if (difference > pi)
            difference -= 2 * pi;
        double value = difference * fs / (2 * pi);
        instantaneous.data[i - 1] = value;
        instantaneous_mean += value;
    }
    instantaneous_mean /= n - 1;
    double instantaneous_variance = 0;
    for (int i = 0; i < n - 1; ++i)
        instantaneous_variance +=
            (instantaneous.data[i] - instantaneous_mean) * (instantaneous.data[i] - instantaneous_mean);
    double instantaneous_std = sqrt(instantaneous_variance / (n - 1));
    Values smoothed = convolution(y, p.fir);
    double dc_gain = 0;
    Complex fundamental_gain = 0;
    for (int j = 0; j < p.fir.count; ++j) {
        dc_gain += p.fir.data[j];
        fundamental_gain += p.fir.data[j] * rot(2 * pi * p.fundamental * j / fs);
    }
    int hps_bin = -1;
    double hps_maximum = -INFINITY;
    for (int k = 1; k < kmax && 5 * k <= kmax; ++k)
        if ((Int)p.pitch_low * m <= (Int)k * fs && (Int)k * fs <= (Int)p.pitch_high * m) {
            double value = 0;
            for (int order = 1; order <= 5; ++order)
                value += log(a.data[order * k]);
            if (value > hps_maximum) {
                hps_maximum = value;
                hps_bin = k;
            }
        }
    int lag_low = (fs + p.pitch_high - 1) / p.pitch_high, lag_high = fs / p.pitch_low, q = pow2(2 * n - 1);
    source = complex_values(bandpassed, q);
    Complexes bq = radix2(source, false);
    release_one(source.data);
    for (int i = 0; i < q; ++i)
        bq.data[i] = norm(bq.data[i]);
    Complexes autoc = radix2(bq, true);
    Values autocorrelation = real_parts(autoc);
    release_one(autoc.data);
    release_one(bq.data);
    int period_bin = lag_low;
    for (int lag = lag_low + 1; lag <= lag_high; ++lag)
        if (autocorrelation.data[lag] > autocorrelation.data[period_bin])
            period_bin = lag;
    Interpolation period = interpolate(autocorrelation, period_bin, false);
    int crossings = 0;
    for (int i = 1; i < n; ++i)
        crossings += bandpassed.data[i - 1] < 0 && bandpassed.data[i] >= 0;
    Complexes zoom = chirp_z(main_spectrum.windowed, fs, p.zoom_low, p.zoom_high, p.zoom_points);
    Values zoom_amplitude = values_new(zoom.count);
    for (int j = 0; j < zoom.count; ++j)
        zoom_amplitude.data[j] = 2 * cabs(zoom.data[j]) / main_spectrum.figures.s1;
    Ids zoom_peaks = peak_indices(zoom_amplitude, 3);
    double zoom_step = (double)(p.zoom_high - p.zoom_low) / (p.zoom_points - 1);
    source = complex_values(x, q);
    Complexes cross_x = radix2(source, false);
    release_one(source.data);
    source = complex_values(y, q);
    Complexes cross_y = radix2(source, false);
    release_one(source.data);
    Complexes phat = complex_new(q);
    for (int k = 0; k < q; ++k) {
        cross_x.data[k] = conj(cross_x.data[k]) * cross_y.data[k];
        phat.data[k] = cross_x.data[k] / cabs(cross_x.data[k]);
    }
    Complexes rfft = radix2(cross_x, true), pfft = radix2(phat, true);
    Values correlation = real_parts(rfft), phat_correlation = real_parts(pfft);
    release_one(rfft.data);
    release_one(pfft.data);
    release_one(cross_x.data);
    release_one(cross_y.data);
    release_one(phat.data);
    int lag = best_lag(correlation, p.max_lag), phat_lag = best_lag(phat_correlation, p.max_lag);
    double refined = refined_lag(correlation, lag), phat_refined = refined_lag(phat_correlation, phat_lag),
           coefficient = correlation.data[lag_index(lag, q)] / sqrt(squares(x, -1) * squares(y, -1));
    int frame_count = frame_data.count, frame_bins = p.frame_length / 2 + 1;
    double gmax = 0;
    for (int t = 0; t < frame_count; ++t)
        for (int k = 0; k < frame_bins; ++k)
            gmax = fmax(gmax, frame_data.magnitudes[t].data[k]);
    Ids dominant = {allocate(frame_count, sizeof(int)), frame_count};
    Values flux = values_new(frame_count), kurtosis = values_new(frame_bins);
    for (int t = 0; t < frame_count; ++t) {
        dominant.data[t] = 1;
        for (int k = 2; k < frame_bins - 1; ++k)
            if (frame_data.magnitudes[t].data[k] > frame_data.magnitudes[t].data[dominant.data[t]])
                dominant.data[t] = k;
        if (t)
            for (int k = 0; k < frame_bins; ++k)
                flux.data[t] +=
                    fmax(0, frame_data.magnitudes[t].data[k] - frame_data.magnitudes[t - 1].data[k]);
    }
    double onset_threshold = p.onset_factor * median((Values){flux.data + 1, flux.count - 1});
    Ids onsets = {.data = allocate(frame_count, sizeof(int))};
    for (int t = 1; t < frame_count; ++t)
        if (flux.data[t] > onset_threshold && flux.data[t] > flux.data[t - 1] &&
            (t == frame_count - 1 || flux.data[t] > flux.data[t + 1]))
            onsets.data[onsets.count++] = t;
    for (int k = 0; k < frame_bins; ++k) {
        double second = 0, fourth = 0;
        for (int t = 0; t < frame_count; ++t) {
            double square = frame_data.magnitudes[t].data[k] * frame_data.magnitudes[t].data[k];
            second += square;
            fourth += square * square;
        }
        kurtosis.data[k] = frame_count * fourth / (second * second) - 2;
    }
    int kurtosis_bin = 1;
    for (int k = 2; k < frame_bins - 1; ++k)
        if (kurtosis.data[k] > kurtosis.data[kurtosis_bin])
            kurtosis_bin = k;
    double roundtrip_error = 0;
    Complexes inverse = idft(main_spectrum.transformed);
    for (int i = 0; i < m; ++i)
        roundtrip_error = fmax(roundtrip_error, cabs(inverse.data[i] - main_spectrum.windowed.data[i]));
    double frequency_energy = 0;
    for (int k = 0; k < m; ++k)
        frequency_energy += norm(main_spectrum.transformed.data[k]);
    double time_energy = squares(main_spectrum.windowed, -1),
           parseval_error = fabs(time_energy - frequency_energy / m) / time_energy, fir_error = 0;
    for (int index = 0; index < smoothed.count; ++index) {
        double direct = 0;
        int first = index - p.fir.count + 1;
        if (first < 0)
            first = 0;
        int last = index < n - 1 ? index : n - 1;
        for (int j = first; j <= last; ++j)
            direct += y.data[j] * p.fir.data[index - j];
        fir_error = fmax(fir_error, fabs(smoothed.data[index] - direct));
    }
    double spot_error = 0;
    for (int peak = 0; peak < peak_count; ++peak) {
        Complex direct = 0;
        for (int i = 0; i < m; ++i)
            direct += main_spectrum.windowed.data[i] * rot(2 * pi * ((peaks[peak].bin * i) % m) / m);
        spot_error = fmax(spot_error, cabs(direct - main_spectrum.transformed.data[peaks[peak].bin]));
    }
    double packing_error = fmax(welch_data.packing_error, frame_data.packing_error);
    Lines spectrum_file = {0}, peak_file = {0}, welch_file = {0}, spectrogram_file = {0}, filtered_file = {0},
          report = {0};
    line(&spectrum_file, "frequency,amplitude");
    for (int k = 0; k <= kmax; ++k)
        line(&spectrum_file, "%s,%s", real((double)k * fs / m), real(a.data[k]));
    line(&peak_file, "length=%d window=%s resolution=%s threshold_db=%s", m, p.main_window,
         real((double)fs / m), real(p.peak_threshold));
    line(&peak_file, "max_amplitude=%s noise_floor=%s noise_floor_db=%s", real(amax), real(noise_floor),
         real(20 * log10(noise_floor)));
    line(&peak_file, "peaks=%d", peak_count);
    for (int rank = 0; rank < peak_count; ++rank) {
        Peak peak = peaks[rank];
        line(
            &peak_file,
            "%d bin=%d frequency=%s refined=%s amplitude=%s level_db=%s phase=%s bandwidth=%s snr_db=%s coherence=%s label=%s",
            rank + 1, peak.bin, real((double)peak.bin * fs / m), real(peak.refined.position * fs / m),
            real(peak.refined.value), real(peak.level), real(peak.phase), real(peak.bandwidth),
            real(peak.snr), real(peak.coherence), peak.label);
    }
    line(&welch_file, "frequency,psd_db");
    for (int k = 0; k <= p.welch_length / 2; ++k)
        line(&welch_file, "%s,%s", real((double)k * fs / p.welch_length),
             real(10 * log10(welch_data.psd.data[k])));
    line(&spectrogram_file, "frames=%d bins=%d frame_length=%d hop=%d window=%s band_db=%d max_db=%s",
         frame_count, frame_bins, p.frame_length, p.hop, p.frame_window, p.shade, real(20 * log10(gmax)));
    for (int k = frame_bins - 1; k >= 0; --k)
        line(&spectrogram_file, "%s",
             shade_line((double)k * fs / p.frame_length, frame_data, k, gmax, p.shade));
    line(&spectrogram_file, "track");
    for (int t = 0; t < frame_count; ++t)
        line(&spectrogram_file, "frame=%d time=%s frequency=%s level_db=%s", t, real((double)t * p.hop / fs),
             real((double)dominant.data[t] * fs / p.frame_length),
             real(20 * log10(frame_data.magnitudes[t].data[dominant.data[t]] / gmax)));
    line(&spectrogram_file, "onsets=%d threshold=%s", onsets.count, real(onset_threshold));
    for (int i = 0; i < onsets.count; ++i) {
        int t = onsets.data[i];
        line(&spectrogram_file, "frame=%d time=%s flux=%s", t, real((double)t * p.hop / fs),
             real(flux.data[t]));
    }
    line(&spectrogram_file, "kurtosis bin=%d frequency=%s value=%s", kurtosis_bin,
         real((double)kurtosis_bin * fs / p.frame_length), real(kurtosis.data[kurtosis_bin]));
    line(&filtered_file, "index,bandpass,notched,smoothed,envelope");
    for (int i = 0; i < n; ++i)
        line(&filtered_file, "%d,%s,%s,%s,%s", i, real(bandpassed.data[i]), real(notched.data[i]),
             real(smoothed.data[i]), real(envelope.data[i]));
    line(&report, "[signal]");
    line(&report, "sample_rate=%d samples=%d duration=%s", fs, n, real((double)n / fs));
    for (int channel = 0; channel < 2; ++channel) {
        Statistics s = statistics[channel];
        line(&report, "channel=%d mean=%s slope=%s rms=%s min=%s max=%s crest=%s skewness=%s kurtosis=%s",
             channel + 1, real(s.mean), real(s.slope), real(s.rms), real(s.minimum), real(s.maximum),
             real(s.crest), real(s.skewness), real(s.kurtosis));
    }
    line(&report, "[levels]");
    int blocks = n / p.block_length, loudest = 0;
    double (*levels)[3] = allocate(blocks, sizeof(*levels));
    for (int block = 0; block < blocks; ++block) {
        double first = 0, second = 0, peak = 0;
        for (int i = block * p.block_length; i < (block + 1) * p.block_length; ++i) {
            first += x.data[i] * x.data[i];
            second += y.data[i] * y.data[i];
            peak = fmax(peak, fabs(x.data[i]));
        }
        levels[block][0] = sqrt(first / p.block_length);
        levels[block][1] = sqrt(second / p.block_length);
        levels[block][2] = peak;
        if (levels[block][0] > levels[loudest][0])
            loudest = block;
    }
    line(&report, "block_length=%d blocks=%d loudest=%d", p.block_length, blocks, loudest);
    for (int block = 0; block < blocks; ++block)
        line(&report, "block=%d time=%s rms1=%s rms2=%s peak1=%s", block,
             real((double)block * p.block_length / fs), real(levels[block][0]), real(levels[block][1]),
             real(levels[block][2]));
    line(&report, "[windows]");
    const char *names[] = {"rectangular", "hann", "hamming", "blackman", "flattop"};
    for (int i = 0; i < 5; ++i) {
        Spectrum value = spectrum(x, m, names[i], fs);
        WindowFigures f = value.figures;
        int bin = harmonic_bin(value.amplitude, p.fundamental * m / fs, p.search);
        line(
            &report,
            "name=%s coherent_gain=%s enbw_bins=%s enbw_hz=%s scalloping_db=%s fundamental_bin=%d bin_amplitude=%s refined_amplitude=%s floor_db=%s",
            names[i], real(f.coherent), real(f.enbw), real(f.enbw_hz), real(f.scalloping), bin,
            real(value.amplitude.data[bin]), real(interpolate(value.amplitude, bin, true).value),
            real(20 * log10(median((Values){value.amplitude.data + 1, value.amplitude.count - 2}))));
        release_spectrum(value);
    }
    line(&report, "[main]");
    line(&report, "length=%d window=%s method=%s transform_size=%d resolution=%s", m, p.main_window,
         power_of_two(m) ? "radix2" : "bluestein", power_of_two(m) ? m : pow2(2 * m - 1),
         real((double)fs / m));
    line(&report, "total_power=%s centroid=%s spread=%s rolloff=%s flatness_db=%s", real(total_power),
         real(centroid), real(spread), real(rolloff), real(flatness));
    line(&report, "[bands]");
    for (int band = 0; band + 1 < p.bands.count; ++band) {
        double sum = 0;
        for (int k = 1; k < kmax; ++k)
            if ((Int)p.bands.data[band] * m <= (Int)k * fs && (Int)k * fs < (Int)p.bands.data[band + 1] * m)
                sum += power.data[k];
        sum /= enbw;
        line(&report, "range=%d-%d power=%s percent=%s", p.bands.data[band], p.bands.data[band + 1],
             real(sum), real(100 * sum / total_power));
    }
    line(&report, "[third_octave]");
    for (int band = p.third_low; band <= p.third_high; ++band) {
        double center = 1000 * pow(2, band / 3.0), lower = 1000 * pow(2, (2 * band - 1) / 6.0),
               upper = 1000 * pow(2, (2 * band + 1) / 6.0), sum = 0;
        int bins = 0;
        for (int k = 1; k < kmax; ++k) {
            double frequency = (double)k * fs / m;
            if (lower <= frequency && frequency < upper) {
                ++bins;
                sum += power.data[k];
            }
        }
        line(&report, "band=%d center=%s lower=%s upper=%s bins=%d level_db=%s", band, real(center),
             real(lower), real(upper), bins, real(10 * log10(sum / enbw)));
    }
    line(&report, "[harmonics]");
    line(&report, "fundamental=%s search=%d", real(p.fundamental), p.search);
    for (int h = 1; h <= 10; ++h)
        line(&report, "h=%d target=%s bin=%d refined=%s amplitude=%s level_db=%s", h, real(h * p.fundamental),
             harmonic_bins[h - 1], real(harmonics[h - 1].position * fs / m), real(harmonics[h - 1].value),
             real(harmonic_levels[h - 1]));
    line(&report, "thd_percent=%s thd_db=%s", real(100 * thd), real(20 * log10(thd)));
    line(&report, "thdn_percent=%s thdn_db=%s", real(100 * thdn), real(20 * log10(thdn)));
    line(&report, "[pitch]");
    line(&report, "range=%d-%d lags=%d-%d", p.pitch_low, p.pitch_high, lag_low, lag_high);
    line(&report, "hps bin=%d order=5 frequency=%s", hps_bin, real((double)hps_bin * fs / m));
    line(&report, "autocorrelation lag=%d period=%s frequency=%s strength=%s", period_bin,
         real(period.position), real(fs / period.position), real(period.value / autocorrelation.data[0]));
    line(&report, "zero_crossing count=%d frequency=%s", crossings, real((double)crossings * fs / n));
    line(&report, "[zoom]");
    line(&report, "band=%d-%d points=%d step=%s", p.zoom_low, p.zoom_high, p.zoom_points, real(zoom_step));
    for (int rank = 0; rank < zoom_peaks.count; ++rank) {
        Interpolation value = interpolate(zoom_amplitude, zoom_peaks.data[rank], true);
        line(&report, "peak=%d frequency=%s amplitude=%s", rank + 1,
             real(p.zoom_low + value.position * zoom_step), real(value.value));
    }
    line(&report, "[welch]");
    line(&report, "segment_length=%d segments=%d window=%s resolution=%s", p.welch_length,
         welch_data.segments, p.welch_window, real((double)fs / p.welch_length));
    double integrated = 0;
    for (int k = 0; k < welch_data.psd.count; ++k)
        integrated += welch_data.psd.data[k];
    integrated = integrated * fs / p.welch_length;
    double signal_variance = statistics[0].rms * statistics[0].rms;
    line(&report, "integrated_power=%s variance=%s ratio=%s", real(integrated), real(signal_variance),
         real(integrated / signal_variance));
    Ids welch_peaks = peak_indices(welch_data.psd, 5);
    for (int rank = 0; rank < welch_peaks.count; ++rank) {
        int k = welch_peaks.data[rank];
        line(&report, "peak=%d frequency=%s psd_db=%s coherence=%s gain=%s phase=%s", rank + 1,
             real((double)k * fs / p.welch_length), real(10 * log10(welch_data.psd.data[k])),
             real(welch_data.coherence.data[k]), real(cabs(welch_data.transfer.data[k])),
             real(carg(welch_data.transfer.data[k]) * 180 / pi));
    }
    line(&report, "[filter]");
    line(&report, "bandpass=%d-%d bins_kept=%d rms=%s energy_ratio=%s", p.band_low, p.band_high, kept,
         real(rms(bandpassed, -1)), real(squares(bandpassed, -1) / squares(x, -1)));
    line(&report, "notch=%d width=%d bins_removed=%d rms=%s", p.notch_frequency, p.notch_width, removed,
         real(rms(notched, -1)));
    line(&report, "fir_taps=%d dc_gain=%s gain_at_fundamental_db=%s rms=%s", p.fir.count, real(dc_gain),
         real(20 * log10(cabs(fundamental_gain))), real(rms(smoothed, n)));
    line(&report, "[envelope]");
    line(&report, "band=%d-%d mean=%s bin=%d frequency=%s amplitude=%s depth=%s", p.envelope_low,
         p.envelope_high, real(envelope_mean), envelope_bin, real(envelope_peak.position * fs / n),
         real(envelope_peak.value), real(envelope_depth));
    line(&report, "instantaneous_frequency mean=%s std=%s", real(instantaneous_mean),
         real(instantaneous_std));
    line(&report, "[correlation]");
    line(&report, "max_lag=%d lag=%d refined_lag=%s delay_ms=%s coefficient=%s", p.max_lag, lag,
         real(refined), real(1000 * refined / fs), real(coefficient));
    line(&report, "phat_lag=%d refined_lag=%s delay_ms=%s", phat_lag, real(phat_refined),
         real(1000 * phat_refined / fs));
    line(&report, "[checks]");
    line(&report, "inverse_roundtrip=%s", roundtrip_error <= 1e-6 ? "ok" : "failed");
    line(&report, "parseval=%s", parseval_error <= 1e-6 ? "ok" : "failed");
    line(&report, "real_packing=%s transforms=%d", packing_error <= 1e-6 ? "ok" : "failed",
         2 * welch_data.segments + frame_count);
    line(&report, "fir_fft_vs_direct=%s", fir_error <= 1e-6 ? "ok" : "failed");
    line(&report, "dft_spot_check=%s bins=%d", spot_error <= 1e-6 ? "ok" : "failed", peak_count);
    double harmonic_ratio = harmonics[1].value / harmonics[0].value;
    int loose = 0;
    for (int h = 2; h < 10; ++h)
        loose += harmonic_levels[h] >= -30;
    bool electrical = false;
    char *mains_level = "none";
    for (int i = 0; i < peak_count; ++i)
        if (!strcmp(peaks[i].label, "mains")) {
            mains_level = real(peaks[i].level);
            electrical = peaks[i].level >= -20;
            break;
        }
    bool misalignment = harmonic_ratio >= 0.5, looseness = loose >= 3, bearing = envelope_depth >= 0.2,
         transient = onsets.count > 0;
    int findings = misalignment + looseness + bearing + electrical + transient;
    line(&report, "[diagnosis]");
    line(&report, "misalignment=%s ratio=%s", misalignment ? "yes" : "no", real(harmonic_ratio));
    line(&report, "looseness=%s harmonics=%d", looseness ? "yes" : "no", loose);
    line(&report, "bearing=%s depth=%s", bearing ? "yes" : "no", real(envelope_depth));
    line(&report, "electrical=%s level_db=%s", electrical ? "yes" : "no", mains_level);
    line(&report, "transient=%s onsets=%d", transient ? "yes" : "no", onsets.count);
    line(&report, "status=%s findings=%d",
         findings == 0   ? "normal"
         : findings == 1 ? "warning"
                         : "alarm",
         findings);
    save("spectrum.csv", spectrum_file);
    save("peaks.txt", peak_file);
    save("welch_psd.csv", welch_file);
    save("spectrogram.txt", spectrogram_file);
    save("filtered.csv", filtered_file);
    save("report.txt", report);
    release_all();
    return 0;
}
