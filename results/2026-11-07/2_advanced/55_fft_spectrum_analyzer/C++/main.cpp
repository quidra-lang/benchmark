#include "analyzer.hpp"
#include <filesystem>
template <typename... T> static void line(Lines &out, const T &...values) {
    std::ostringstream text;
    (text << ... << values);
    out.push_back(text.str());
}
static double squares(const Values &values, int count = -1) {
    if (count < 0)
        count = values.size();
    double sum = 0;
    for (int i = 0; i < count; ++i)
        sum += values[i] * values[i];
    return sum;
}
static double rms(const Values &values, int count = -1) {
    if (count < 0)
        count = values.size();
    return std::sqrt(squares(values, count) / count);
}
static Complexes complex_values(const Values &values, int length = -1) {
    if (length < 0)
        length = values.size();
    Complexes out(length);
    for (int i = 0; i < int(values.size()); ++i)
        out[i] = values[i];
    return out;
}
static Values real_parts(const Complexes &values) {
    Values out;
    for (Complex value : values)
        out.push_back(value.real());
    return out;
}
struct Statistics {
    Values detrended;
    double mean = 0, slope = 0, rms = 0, minimum = 0, maximum = 0, crest = 0, skewness = 0, kurtosis = 0;
};
static Statistics preprocess(const Values &values, int fs) {
    Statistics out;
    const int n = values.size();
    const double center = (n - 1) / 2.0;
    for (double value : values)
        out.mean += value;
    out.mean /= n;
    double numerator = 0, denominator = 0;
    for (int i = 0; i < n; ++i) {
        numerator += (i - center) * (values[i] - out.mean);
        denominator += (i - center) * (i - center);
    }
    const double slope = numerator / denominator;
    out.slope = slope * fs;
    double maximum = 0, third = 0, fourth = 0;
    for (int i = 0; i < n; ++i) {
        const double value = values[i] - out.mean - slope * (i - center);
        out.detrended.push_back(value);
        maximum = std::max(maximum, std::abs(value));
        third += value * value * value;
        fourth += value * value * value * value;
    }
    out.rms = rms(out.detrended);
    out.minimum = *std::min_element(values.begin(), values.end());
    out.maximum = *std::max_element(values.begin(), values.end());
    out.crest = maximum / out.rms;
    out.skewness = (third / n) / (out.rms * out.rms * out.rms);
    out.kurtosis = (fourth / n) / (out.rms * out.rms * out.rms * out.rms);
    return out;
}
static Ids peak_indices(const Values &values, int limit) {
    Ids out;
    for (int k = 1; k + 1 < int(values.size()); ++k)
        if (local_maximum(values, k))
            out.push_back(k);
    std::sort(out.begin(), out.end(),
              [&](int a, int b) { return values[a] != values[b] ? values[a] > values[b] : a < b; });
    if (out.size() > std::size_t(limit))
        out.resize(limit);
    return out;
}
static int harmonic_bin(const Values &amplitudes, double target, int width) {
    int best = -1;
    for (int k = 1; k + 1 < int(amplitudes.size()); ++k)
        if (std::abs(k - target) <= width && (best < 0 || amplitudes[k] > amplitudes[best]))
            best = k;
    return best;
}
struct Peak {
    int bin;
    Interpolation refined;
    double level, phase, bandwidth, snr, coherence;
    std::string label;
};
static double bandwidth(const Values &values, int k) {
    const double threshold = values[k] / std::sqrt(2.0);
    const int last = values.size() - 1;
    double left = 0, right = last;
    for (int j = k + 1; j <= last; ++j)
        if (values[j] <= threshold) {
            right = j - 1 + (values[j - 1] - threshold) / (values[j - 1] - values[j]);
            break;
        }
    for (int j = k - 1; j >= 0; --j)
        if (values[j] <= threshold) {
            left = j + 1 - (values[j + 1] - threshold) / (values[j + 1] - values[j]);
            break;
        }
    return right - left;
}
static int lag_index(int lag, int size) {
    return lag < 0 ? lag + size : lag;
}
static int best_lag(const Values &values, int maximum) {
    int best = -maximum;
    for (int lag = -maximum; lag <= maximum; ++lag) {
        const double value = values[lag_index(lag, values.size())],
                     current = values[lag_index(best, values.size())];
        if (value > current ||
            (value == current && std::make_pair(std::abs(lag), lag) < std::make_pair(std::abs(best), best)))
            best = lag;
    }
    return best;
}
static double refined_lag(const Values &values, int lag) {
    const int size = values.size();
    const Values neighbors{values[lag_index(lag - 1, size)], values[lag_index(lag, size)],
                           values[lag_index(lag + 1, size)]};
    return lag + interpolate(neighbors, 1, false).position - 1;
}
int main() {
    std::filesystem::create_directories("output");
    const Input input = load();
    const Params &p = input.params;
    const int fs = input.fs, n = input.signal[0].size(), m = p.main_length, kmax = m / 2;
    const std::array<Statistics, 2> statistics{preprocess(input.signal[0], fs),
                                               preprocess(input.signal[1], fs)};
    const Values &x = statistics[0].detrended;
    const Values &y = statistics[1].detrended;
    const Spectrum main_spectrum = spectrum(x, m, p.main_window, fs);
    const Values &a = main_spectrum.amplitude;
    const double amax = *std::max_element(a.begin(), a.end()),
                 floor = median(Values(a.begin() + 1, a.end() - 1)), enbw = main_spectrum.figures.enbw;
    const Welch welch_data = welch(x, y, p, fs);
    const Frames frame_data = frames(x, p);
    std::vector<Peak> peaks;
    Ids candidates;
    for (int k = 1; k < kmax; ++k)
        if (local_maximum(a, k) && 20 * std::log10(a[k] / amax) >= p.peak_threshold)
            candidates.push_back(k);
    std::sort(candidates.begin(), candidates.end(), [&](int first, int second) {
        return a[first] != a[second] ? a[first] > a[second] : first < second;
    });
    if (candidates.size() > std::size_t(p.peak_count))
        candidates.resize(p.peak_count);
    for (int k : candidates)
        peaks.push_back({k, interpolate(a, k), 20 * std::log10(a[k] / amax),
                         std::arg(main_spectrum.transformed[k]) * 180 / pi, bandwidth(a, k) * fs / m,
                         20 * std::log10(a[k] / floor),
                         welch_data.coherence[(2 * k * p.welch_length + m) / (2 * m)], ""});
    for (int index = 0; index < int(peaks.size()); ++index) {
        Peak &peak = peaks[index];
        for (int h = 1; h <= 10; ++h)
            if (std::abs(peak.refined.position - h * p.fundamental * m / fs) <= p.search) {
                peak.label = "h" + std::to_string(h);
                break;
            }
        const double frequency = peak.refined.position * fs / m;
        const int mains = int(std::floor(frequency / p.notch_frequency + 0.5));
        if (peak.label.empty() && mains >= 1 &&
            std::abs(frequency - mains * p.notch_frequency) <= p.notch_width)
            peak.label = "mains";
        if (peak.label.empty())
            for (int center = 0; center < int(peaks.size()) && peak.label.empty(); ++center)
                for (int other = 0; other < int(peaks.size()); ++other) {
                    if (center == index || other == index || center == other)
                        continue;
                    if (a[peaks[center].bin] > a[peak.bin] && a[peaks[center].bin] > a[peaks[other].bin] &&
                        std::abs(peak.refined.position + peaks[other].refined.position -
                                 2 * peaks[center].refined.position) <= 1) {
                        peak.label = "sideband" + std::to_string(center + 1);
                        break;
                    }
                }
        if (peak.label.empty())
            peak.label = "other";
    }
    std::array<int, 10> harmonic_bins{};
    std::array<Interpolation, 10> harmonics;
    Values harmonic_levels(10);
    for (int h = 1; h <= 10; ++h) {
        harmonic_bins[h - 1] = harmonic_bin(a, h * p.fundamental * m / fs, p.search);
        harmonics[h - 1] = interpolate(a, harmonic_bins[h - 1]);
        harmonic_levels[h - 1] = 20 * std::log10(harmonics[h - 1].value / harmonics[0].value);
    }
    double harmonic_power = 0;
    for (int h = 1; h < 10; ++h)
        harmonic_power += harmonics[h].value * harmonics[h].value;
    const double thd = std::sqrt(harmonic_power) / harmonics[0].value;
    Values power(a.size());
    for (int k = 0; k <= kmax; ++k)
        power[k] = a[k] * a[k] / 2;
    double power_sum = 0, fundamental_power = 0, weighted = 0, log_power = 0;
    for (int k = 1; k < kmax; ++k) {
        power_sum += power[k];
        if (std::abs(k - harmonic_bins[0]) <= p.search)
            fundamental_power += power[k];
        weighted += (double(k) * fs / m) * power[k];
        log_power += std::log(power[k]);
    }
    const double total_power = power_sum / enbw, p1 = fundamental_power / enbw,
                 thdn = std::sqrt((total_power - p1) / p1), centroid = weighted / power_sum,
                 flatness = 10 * std::log10(std::exp(log_power / (kmax - 1)) / (power_sum / (kmax - 1)));
    double variance = 0, running = 0, rolloff = 0;
    bool rolled = false;
    for (int k = 1; k < kmax; ++k) {
        const double frequency = double(k) * fs / m;
        variance += (frequency - centroid) * (frequency - centroid) * power[k];
        running += power[k];
        if (!rolled && running >= 0.85 * power_sum) {
            rolloff = frequency;
            rolled = true;
        }
    }
    const double spread = std::sqrt(variance / power_sum);
    const Complexes xf = dft(complex_values(x));
    Complexes pass(n), notch = xf, analytic(n);
    int kept = 0, removed = 0;
    for (int k = 0; k < n; ++k) {
        const I g = I(std::min(k, n - k)) * fs;
        if (I(p.band_low) * n <= g && g <= I(p.band_high) * n) {
            pass[k] = xf[k];
            ++kept;
        }
        const I harmonic = (2 * g + I(p.notch_frequency) * n) / (2 * I(p.notch_frequency) * n);
        if (harmonic >= 1 && std::abs(g - harmonic * p.notch_frequency * n) <= I(p.notch_width) * n) {
            notch[k] = 0;
            ++removed;
        }
        if (k >= 1 && k <= (n - 1) / 2 && I(p.envelope_low) * n <= I(k) * fs &&
            I(k) * fs <= I(p.envelope_high) * n)
            analytic[k] = 2.0 * xf[k];
    }
    const Values bandpassed = real_parts(idft(pass)), notched = real_parts(idft(notch));
    const Complexes z = idft(analytic);
    Values envelope(n), phases(n), centered(n);
    double envelope_mean = 0;
    for (int i = 0; i < n; ++i) {
        envelope[i] = std::abs(z[i]);
        phases[i] = std::arg(z[i]);
        envelope_mean += envelope[i];
    }
    envelope_mean /= n;
    for (int i = 0; i < n; ++i)
        centered[i] = envelope[i] - envelope_mean;
    const Complexes ev = dft(complex_values(centered));
    Values be(n);
    for (int k = 0; k < n; ++k)
        be[k] = 2 * std::abs(ev[k]) / n;
    int envelope_bin = 1;
    const int envelope_limit = (p.envelope_high - p.envelope_low) * n / (2 * fs);
    for (int k = 2; k <= envelope_limit; ++k)
        if (be[k] > be[envelope_bin])
            envelope_bin = k;
    const Interpolation envelope_peak = interpolate(be, envelope_bin);
    const double envelope_depth = envelope_peak.value / envelope_mean;
    Values instantaneous;
    double instantaneous_mean = 0;
    for (int i = 1; i < n; ++i) {
        double difference = phases[i] - phases[i - 1];
        if (difference <= -pi)
            difference += 2 * pi;
        if (difference > pi)
            difference -= 2 * pi;
        const double value = difference * fs / (2 * pi);
        instantaneous.push_back(value);
        instantaneous_mean += value;
    }
    instantaneous_mean /= n - 1;
    double instantaneous_variance = 0;
    for (double value : instantaneous)
        instantaneous_variance += (value - instantaneous_mean) * (value - instantaneous_mean);
    const double instantaneous_std = std::sqrt(instantaneous_variance / (n - 1));
    const Values smoothed = convolution(y, p.fir);
    double dc_gain = 0;
    Complex fundamental_gain{};
    for (int j = 0; j < int(p.fir.size()); ++j) {
        dc_gain += p.fir[j];
        fundamental_gain += p.fir[j] * rot(2 * pi * p.fundamental * j / fs);
    }
    int hps_bin = -1;
    double hps_maximum = -std::numeric_limits<double>::infinity();
    for (int k = 1; k < kmax && 5 * k <= kmax; ++k)
        if (I(p.pitch_low) * m <= I(k) * fs && I(k) * fs <= I(p.pitch_high) * m) {
            double value = 0;
            for (int order = 1; order <= 5; ++order)
                value += std::log(a[order * k]);
            if (value > hps_maximum) {
                hps_maximum = value;
                hps_bin = k;
            }
        }
    const int lag_low = (fs + p.pitch_high - 1) / p.pitch_high, lag_high = fs / p.pitch_low,
              q = pow2(2 * n - 1);
    Complexes bq = radix2(complex_values(bandpassed, q));
    for (Complex &value : bq)
        value = {std::norm(value), 0};
    const Values autocorrelation = real_parts(radix2(std::move(bq), true));
    int period_bin = lag_low;
    for (int lag = lag_low + 1; lag <= lag_high; ++lag)
        if (autocorrelation[lag] > autocorrelation[period_bin])
            period_bin = lag;
    const Interpolation period = interpolate(autocorrelation, period_bin, false);
    int crossings = 0;
    for (int i = 1; i < n; ++i)
        crossings += bandpassed[i - 1] < 0 && bandpassed[i] >= 0;
    const Complexes zoom = chirp_z(main_spectrum.windowed, fs, p.zoom_low, p.zoom_high, p.zoom_points);
    Values zoom_amplitude;
    for (Complex value : zoom)
        zoom_amplitude.push_back(2 * std::abs(value) / main_spectrum.figures.s1);
    const Ids zoom_peaks = peak_indices(zoom_amplitude, 3);
    const double zoom_step = double(p.zoom_high - p.zoom_low) / (p.zoom_points - 1);
    Complexes cross_x = radix2(complex_values(x, q)), cross_y = radix2(complex_values(y, q)), phat(q);
    for (int k = 0; k < q; ++k) {
        cross_x[k] = std::conj(cross_x[k]) * cross_y[k];
        phat[k] = cross_x[k] / std::abs(cross_x[k]);
    }
    const Values correlation = real_parts(radix2(std::move(cross_x), true)),
                 phat_correlation = real_parts(radix2(std::move(phat), true));
    const int lag = best_lag(correlation, p.max_lag), phat_lag = best_lag(phat_correlation, p.max_lag);
    const double refined = refined_lag(correlation, lag),
                 phat_refined = refined_lag(phat_correlation, phat_lag),
                 coefficient = correlation[lag_index(lag, q)] / std::sqrt(squares(x) * squares(y));
    const int frame_count = frame_data.magnitudes.size(), frame_bins = p.frame_length / 2 + 1;
    double gmax = 0;
    for (const Values &row : frame_data.magnitudes)
        for (double value : row)
            gmax = std::max(gmax, value);
    Ids dominant(frame_count);
    Values flux(frame_count), kurtosis(frame_bins);
    for (int t = 0; t < frame_count; ++t) {
        dominant[t] = 1;
        for (int k = 2; k < frame_bins - 1; ++k)
            if (frame_data.magnitudes[t][k] > frame_data.magnitudes[t][dominant[t]])
                dominant[t] = k;
        if (t)
            for (int k = 0; k < frame_bins; ++k)
                flux[t] += std::max(0.0, frame_data.magnitudes[t][k] - frame_data.magnitudes[t - 1][k]);
    }
    const double onset_threshold = p.onset_factor * median(Values(flux.begin() + 1, flux.end()));
    Ids onsets;
    for (int t = 1; t < frame_count; ++t)
        if (flux[t] > onset_threshold && flux[t] > flux[t - 1] &&
            (t == frame_count - 1 || flux[t] > flux[t + 1]))
            onsets.push_back(t);
    for (int k = 0; k < frame_bins; ++k) {
        double second = 0, fourth = 0;
        for (const Values &row : frame_data.magnitudes) {
            const double square = row[k] * row[k];
            second += square;
            fourth += square * square;
        }
        kurtosis[k] = frame_count * fourth / (second * second) - 2;
    }
    int kurtosis_bin = 1;
    for (int k = 2; k < frame_bins - 1; ++k)
        if (kurtosis[k] > kurtosis[kurtosis_bin])
            kurtosis_bin = k;
    double roundtrip_error = 0;
    const Complexes inverse = idft(main_spectrum.transformed);
    for (int i = 0; i < m; ++i)
        roundtrip_error = std::max(roundtrip_error, std::abs(inverse[i] - main_spectrum.windowed[i]));
    double frequency_energy = 0;
    for (Complex value : main_spectrum.transformed)
        frequency_energy += std::norm(value);
    const double time_energy = squares(main_spectrum.windowed),
                 parseval_error = std::abs(time_energy - frequency_energy / m) / time_energy;
    double fir_error = 0;
    for (int index = 0; index < int(smoothed.size()); ++index) {
        double direct = 0;
        for (int j = std::max(0, index - int(p.fir.size()) + 1); j <= std::min(n - 1, index); ++j)
            direct += y[j] * p.fir[index - j];
        fir_error = std::max(fir_error, std::abs(smoothed[index] - direct));
    }
    double spot_error = 0;
    for (const Peak &peak : peaks) {
        Complex direct{};
        for (int i = 0; i < m; ++i)
            direct += main_spectrum.windowed[i] * rot(2 * pi * ((peak.bin * i) % m) / m);
        spot_error = std::max(spot_error, std::abs(direct - main_spectrum.transformed[peak.bin]));
    }
    const double packing_error = std::max(welch_data.packing_error, frame_data.packing_error);
    Lines spectrum_file, peak_file, welch_file, spectrogram_file, filtered_file, report;
    line(spectrum_file, "frequency,amplitude");
    for (int k = 0; k <= kmax; ++k)
        line(spectrum_file, real(double(k) * fs / m), ",", real(a[k]));
    line(peak_file, "length=", m, " window=", p.main_window, " resolution=", real(double(fs) / m),
         " threshold_db=", real(p.peak_threshold));
    line(peak_file, "max_amplitude=", real(amax), " noise_floor=", real(floor),
         " noise_floor_db=", real(20 * std::log10(floor)));
    line(peak_file, "peaks=", peaks.size());
    for (int rank = 0; rank < int(peaks.size()); ++rank) {
        const Peak &peak = peaks[rank];
        line(peak_file, rank + 1, " bin=", peak.bin, " frequency=", real(double(peak.bin) * fs / m),
             " refined=", real(peak.refined.position * fs / m), " amplitude=", real(peak.refined.value),
             " level_db=", real(peak.level), " phase=", real(peak.phase), " bandwidth=", real(peak.bandwidth),
             " snr_db=", real(peak.snr), " coherence=", real(peak.coherence), " label=", peak.label);
    }
    line(welch_file, "frequency,psd_db");
    for (int k = 0; k <= p.welch_length / 2; ++k)
        line(welch_file, real(double(k) * fs / p.welch_length), ",",
             real(10 * std::log10(welch_data.psd[k])));
    line(spectrogram_file, "frames=", frame_count, " bins=", frame_bins, " frame_length=", p.frame_length,
         " hop=", p.hop, " window=", p.frame_window, " band_db=", p.shade,
         " max_db=", real(20 * std::log10(gmax)));
    for (int k = frame_bins - 1; k >= 0; --k)
        line(spectrogram_file,
             shade_line(double(k) * fs / p.frame_length, frame_data.magnitudes, k, gmax, p.shade));
    line(spectrogram_file, "track");
    for (int t = 0; t < frame_count; ++t)
        line(spectrogram_file, "frame=", t, " time=", real(double(t) * p.hop / fs),
             " frequency=", real(double(dominant[t]) * fs / p.frame_length),
             " level_db=", real(20 * std::log10(frame_data.magnitudes[t][dominant[t]] / gmax)));
    line(spectrogram_file, "onsets=", onsets.size(), " threshold=", real(onset_threshold));
    for (int t : onsets)
        line(spectrogram_file, "frame=", t, " time=", real(double(t) * p.hop / fs), " flux=", real(flux[t]));
    line(spectrogram_file, "kurtosis bin=", kurtosis_bin,
         " frequency=", real(double(kurtosis_bin) * fs / p.frame_length),
         " value=", real(kurtosis[kurtosis_bin]));
    line(filtered_file, "index,bandpass,notched,smoothed,envelope");
    for (int i = 0; i < n; ++i)
        line(filtered_file, i, ",", real(bandpassed[i]), ",", real(notched[i]), ",", real(smoothed[i]), ",",
             real(envelope[i]));
    line(report, "[signal]");
    line(report, "sample_rate=", fs, " samples=", n, " duration=", real(double(n) / fs));
    for (int channel = 0; channel < 2; ++channel) {
        const Statistics &s = statistics[channel];
        line(report, "channel=", channel + 1, " mean=", real(s.mean), " slope=", real(s.slope),
             " rms=", real(s.rms), " min=", real(s.minimum), " max=", real(s.maximum),
             " crest=", real(s.crest), " skewness=", real(s.skewness), " kurtosis=", real(s.kurtosis));
    }
    line(report, "[levels]");
    const int blocks = n / p.block_length;
    std::vector<std::array<double, 3>> levels;
    int loudest = 0;
    for (int block = 0; block < blocks; ++block) {
        double first = 0, second = 0, peak = 0;
        for (int i = block * p.block_length; i < (block + 1) * p.block_length; ++i) {
            first += x[i] * x[i];
            second += y[i] * y[i];
            peak = std::max(peak, std::abs(x[i]));
        }
        levels.push_back({std::sqrt(first / p.block_length), std::sqrt(second / p.block_length), peak});
        if (levels.back()[0] > levels[loudest][0])
            loudest = block;
    }
    line(report, "block_length=", p.block_length, " blocks=", blocks, " loudest=", loudest);
    for (int block = 0; block < blocks; ++block)
        line(report, "block=", block, " time=", real(double(block) * p.block_length / fs),
             " rms1=", real(levels[block][0]), " rms2=", real(levels[block][1]),
             " peak1=", real(levels[block][2]));
    line(report, "[windows]");
    for (const std::string name : {"rectangular", "hann", "hamming", "blackman", "flattop"}) {
        const Spectrum value = spectrum(x, m, name, fs);
        const WindowFigures &f = value.figures;
        const int bin = harmonic_bin(value.amplitude, p.fundamental * m / fs, p.search);
        line(report, "name=", name, " coherent_gain=", real(f.coherent), " enbw_bins=", real(f.enbw),
             " enbw_hz=", real(f.enbw_hz), " scalloping_db=", real(f.scalloping), " fundamental_bin=", bin,
             " bin_amplitude=", real(value.amplitude[bin]),
             " refined_amplitude=", real(interpolate(value.amplitude, bin).value), " floor_db=",
             real(20 * std::log10(median(Values(value.amplitude.begin() + 1, value.amplitude.end() - 1)))));
    }
    line(report, "[main]");
    line(report, "length=", m, " window=", p.main_window,
         " method=", power_of_two(m) ? "radix2" : "bluestein",
         " transform_size=", power_of_two(m) ? m : pow2(2 * m - 1), " resolution=", real(double(fs) / m));
    line(report, "total_power=", real(total_power), " centroid=", real(centroid), " spread=", real(spread),
         " rolloff=", real(rolloff), " flatness_db=", real(flatness));
    line(report, "[bands]");
    for (int band = 0; band + 1 < int(p.bands.size()); ++band) {
        double power = 0;
        for (int k = 1; k < kmax; ++k)
            if (I(p.bands[band]) * m <= I(k) * fs && I(k) * fs < I(p.bands[band + 1]) * m)
                power += a[k] * a[k] / 2;
        power /= enbw;
        line(report, "range=", p.bands[band], "-", p.bands[band + 1], " power=", real(power),
             " percent=", real(100 * power / total_power));
    }
    line(report, "[third_octave]");
    for (int band = p.third_low; band <= p.third_high; ++band) {
        const double center = 1000 * std::pow(2, band / 3.0),
                     lower = 1000 * std::pow(2, (2 * band - 1) / 6.0),
                     upper = 1000 * std::pow(2, (2 * band + 1) / 6.0);
        double sum = 0;
        int bins = 0;
        for (int k = 1; k < kmax; ++k) {
            const double frequency = double(k) * fs / m;
            if (lower <= frequency && frequency < upper) {
                ++bins;
                sum += power[k];
            }
        }
        line(report, "band=", band, " center=", real(center), " lower=", real(lower), " upper=", real(upper),
             " bins=", bins, " level_db=", real(10 * std::log10(sum / enbw)));
    }
    line(report, "[harmonics]");
    line(report, "fundamental=", real(p.fundamental), " search=", p.search);
    for (int h = 1; h <= 10; ++h)
        line(report, "h=", h, " target=", real(h * p.fundamental), " bin=", harmonic_bins[h - 1],
             " refined=", real(harmonics[h - 1].position * fs / m),
             " amplitude=", real(harmonics[h - 1].value), " level_db=", real(harmonic_levels[h - 1]));
    line(report, "thd_percent=", real(100 * thd), " thd_db=", real(20 * std::log10(thd)));
    line(report, "thdn_percent=", real(100 * thdn), " thdn_db=", real(20 * std::log10(thdn)));
    line(report, "[pitch]");
    line(report, "range=", p.pitch_low, "-", p.pitch_high, " lags=", lag_low, "-", lag_high);
    line(report, "hps bin=", hps_bin, " order=5 frequency=", real(double(hps_bin) * fs / m));
    line(report, "autocorrelation lag=", period_bin, " period=", real(period.position),
         " frequency=", real(fs / period.position), " strength=", real(period.value / autocorrelation[0]));
    line(report, "zero_crossing count=", crossings, " frequency=", real(double(crossings) * fs / n));
    line(report, "[zoom]");
    line(report, "band=", p.zoom_low, "-", p.zoom_high, " points=", p.zoom_points, " step=", real(zoom_step));
    for (int rank = 0; rank < int(zoom_peaks.size()); ++rank) {
        const Interpolation value = interpolate(zoom_amplitude, zoom_peaks[rank]);
        line(report, "peak=", rank + 1, " frequency=", real(p.zoom_low + value.position * zoom_step),
             " amplitude=", real(value.value));
    }
    line(report, "[welch]");
    line(report, "segment_length=", p.welch_length, " segments=", welch_data.segments,
         " window=", p.welch_window, " resolution=", real(double(fs) / p.welch_length));
    double integrated = 0;
    for (double value : welch_data.psd)
        integrated += value;
    integrated = integrated * fs / p.welch_length;
    const double signal_variance = statistics[0].rms * statistics[0].rms;
    line(report, "integrated_power=", real(integrated), " variance=", real(signal_variance),
         " ratio=", real(integrated / signal_variance));
    const Ids welch_peaks = peak_indices(welch_data.psd, 5);
    for (int rank = 0; rank < int(welch_peaks.size()); ++rank) {
        const int k = welch_peaks[rank];
        line(report, "peak=", rank + 1, " frequency=", real(double(k) * fs / p.welch_length),
             " psd_db=", real(10 * std::log10(welch_data.psd[k])),
             " coherence=", real(welch_data.coherence[k]), " gain=", real(std::abs(welch_data.transfer[k])),
             " phase=", real(std::arg(welch_data.transfer[k]) * 180 / pi));
    }
    line(report, "[filter]");
    line(report, "bandpass=", p.band_low, "-", p.band_high, " bins_kept=", kept,
         " rms=", real(rms(bandpassed)), " energy_ratio=", real(squares(bandpassed) / squares(x)));
    line(report, "notch=", p.notch_frequency, " width=", p.notch_width, " bins_removed=", removed,
         " rms=", real(rms(notched)));
    line(report, "fir_taps=", p.fir.size(), " dc_gain=", real(dc_gain),
         " gain_at_fundamental_db=", real(20 * std::log10(std::abs(fundamental_gain))),
         " rms=", real(rms(smoothed, n)));
    line(report, "[envelope]");
    line(report, "band=", p.envelope_low, "-", p.envelope_high, " mean=", real(envelope_mean),
         " bin=", envelope_bin, " frequency=", real(envelope_peak.position * fs / n),
         " amplitude=", real(envelope_peak.value), " depth=", real(envelope_depth));
    line(report, "instantaneous_frequency mean=", real(instantaneous_mean), " std=", real(instantaneous_std));
    line(report, "[correlation]");
    line(report, "max_lag=", p.max_lag, " lag=", lag, " refined_lag=", real(refined),
         " delay_ms=", real(1000 * refined / fs), " coefficient=", real(coefficient));
    line(report, "phat_lag=", phat_lag, " refined_lag=", real(phat_refined),
         " delay_ms=", real(1000 * phat_refined / fs));
    line(report, "[checks]");
    line(report, "inverse_roundtrip=", roundtrip_error <= 1e-6 ? "ok" : "failed");
    line(report, "parseval=", parseval_error <= 1e-6 ? "ok" : "failed");
    line(report, "real_packing=", packing_error <= 1e-6 ? "ok" : "failed",
         " transforms=", 2 * welch_data.segments + frame_count);
    line(report, "fir_fft_vs_direct=", fir_error <= 1e-6 ? "ok" : "failed");
    line(report, "dft_spot_check=", spot_error <= 1e-6 ? "ok" : "failed", " bins=", peaks.size());
    const double harmonic_ratio = harmonics[1].value / harmonics[0].value;
    int loose = 0;
    for (int h = 2; h < 10; ++h)
        loose += harmonic_levels[h] >= -30;
    bool electrical = false;
    std::string mains_level = "none";
    for (const Peak &peak : peaks)
        if (peak.label == "mains") {
            mains_level = real(peak.level);
            electrical = peak.level >= -20;
            break;
        }
    const bool misalignment = harmonic_ratio >= 0.5, looseness = loose >= 3, bearing = envelope_depth >= 0.2,
               transient = !onsets.empty();
    const int findings = int(misalignment) + int(looseness) + int(bearing) + int(electrical) + int(transient);
    line(report, "[diagnosis]");
    line(report, "misalignment=", misalignment ? "yes" : "no", " ratio=", real(harmonic_ratio));
    line(report, "looseness=", looseness ? "yes" : "no", " harmonics=", loose);
    line(report, "bearing=", bearing ? "yes" : "no", " depth=", real(envelope_depth));
    line(report, "electrical=", electrical ? "yes" : "no", " level_db=", mains_level);
    line(report, "transient=", transient ? "yes" : "no", " onsets=", onsets.size());
    line(report, "status=",
         findings == 0   ? "normal"
         : findings == 1 ? "warning"
                         : "alarm",
         " findings=", findings);
    save("spectrum.csv", spectrum_file);
    save("peaks.txt", peak_file);
    save("welch_psd.csv", welch_file);
    save("spectrogram.txt", spectrogram_file);
    save("filtered.csv", filtered_file);
    save("report.txt", report);
}
