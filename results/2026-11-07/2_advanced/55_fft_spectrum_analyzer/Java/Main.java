import java.util.*;
import java.io.IOException;

public final class Main {
    record Statistics(double[] detrended, double mean, double slope, double rms, double minimum,
                      double maximum, double crest, double skewness, double kurtosis, double squares) {}
    static final class Peak {
        int bin;
        Spectral.Interpolation interpolation;
        double level, phase, bandwidth, snr, coherence;
        String label;
    }
    static final class Filtered {
        double[] bandpass, notched, smoothed, envelope;
        Fft.Complex[] analytic;
        int kept, removed, envelopeBin;
        double envelopeMean, envelopeFrequency, envelopeAmplitude, depth, instantMean, instantStd, firDc,
            firGain;
    }
    static int fs, n, m, k, l, frameLength, hop;
    static SignalIo.Params params;
    static Statistics first, second;
    static double[] x, y, a, harmonicAmplitude, harmonicPosition, power, flux, kurtosis;
    static int[] harmonicBins, dominant;
    static List<Peak> peaks = new ArrayList<>();
    static Spectral.Spectrum main;
    static Spectral.Welch welch;
    static Spectral.Frames frames;
    static Filtered filtered;
    static double floor, maximum, onsetThreshold;
    static List<Integer> onsets = new ArrayList<>();
    static int kurtosisBin;
    static String f(double value) {
        return Report.f(value);
    }
    static double db20(double value) {
        return 20 * Math.log10(value);
    }
    static double db10(double value) {
        return 10 * Math.log10(value);
    }
    static double squares(double[] values, int length) {
        double sum = 0;
        for (int i = 0; i < length; i++)
            sum += values[i] * values[i];
        return sum;
    }
    static double rms(double[] values, int length) {
        return Math.sqrt(squares(values, length) / length);
    }
    static double[] real(Fft.Complex[] values) {
        double[] result = new double[values.length];
        for (int i = 0; i < values.length; i++)
            result[i] = values[i].re();
        return result;
    }
    static Statistics preprocess(double[] signal) {
        int n = signal.length;
        double sum = 0, minimum = signal[0], maximum = signal[0];
        for (double value : signal) {
            sum += value;
            minimum = Math.min(minimum, value);
            maximum = Math.max(maximum, value);
        }
        double mean = sum / n, center = (n - 1) / 2.0, numerator = 0, denominator = 0;
        for (int i = 0; i < n; i++) {
            numerator += (i - center) * (signal[i] - mean);
            denominator += (i - center) * (i - center);
        }
        double slope = numerator / denominator;
        double[] d = new double[n];
        double square = 0, cube = 0, fourth = 0, peak = 0;
        for (int i = 0; i < n; i++) {
            d[i] = signal[i] - mean - slope * (i - center);
            square += d[i] * d[i];
            cube += d[i] * d[i] * d[i];
            fourth += d[i] * d[i] * d[i] * d[i];
            peak = Math.max(peak, Math.abs(d[i]));
        }
        double rms = Math.sqrt(square / n);
        return new Statistics(d, mean, slope * fs, rms, minimum, maximum, peak / rms,
                              (cube / n) / (rms * rms * rms), (fourth / n) / (rms * rms * rms * rms), square);
    }
    static List<Integer> maxima(double[] values, int limit) {
        List<Integer> result = new ArrayList<>();
        for (int j = 1; j + 1 < values.length; j++)
            if (Spectral.local(values, j))
                result.add(j);
        result.sort((p, q) -> {
            int c = Double.compare(values[q], values[p]);
            return c != 0 ? c : Integer.compare(p, q);
        });
        return new ArrayList<>(result.subList(0, Math.min(limit, result.size())));
    }
    static int largest(double[] values, int first, int last) {
        int best = first;
        for (int j = first + 1; j <= last; j++)
            if (values[j] > values[best])
                best = j;
        return best;
    }
    static int harmonicBin(double[] values, int h) {
        double center = h * params.get("fundamental") * m / fs;
        int best = -1;
        for (int bin = 1; bin < k; bin++)
            if (Math.abs(bin - center) <= params.integer("fundamental", 1) &&
                (best < 0 || values[bin] > values[best]))
                best = bin;
        return best;
    }
    static void peaks() {
        maximum = a[0];
        for (double value : a)
            maximum = Math.max(maximum, value);
        floor = Spectral.median(Arrays.copyOfRange(a, 1, k));
        List<Integer> bins = new ArrayList<>();
        for (int bin = 1; bin < k; bin++)
            if (Spectral.local(a, bin) && db20(a[bin] / maximum) >= params.get("peak_threshold_db"))
                bins.add(bin);
        bins.sort((p, q) -> {
            int c = Double.compare(a[q], a[p]);
            return c != 0 ? c : Integer.compare(p, q);
        });
        for (int rank = 0; rank < Math.min(bins.size(), params.integer("peak_count")); rank++) {
            int bin = bins.get(rank);
            Peak peak = new Peak();
            peak.bin = bin;
            peak.interpolation = Spectral.interpolate(a, bin, true);
            peak.level = db20(a[bin] / maximum);
            peak.phase = main.transform()[bin].argument() * 180 / Fft.PI;
            peak.snr = db20(a[bin] / floor);
            peak.coherence = welch.coherence()[(2 * bin * l + m) / (2 * m)];
            double lambda = a[bin] / Math.sqrt(2), left = 0, right = k;
            for (int j = bin + 1; j <= k; j++)
                if (a[j] <= lambda) {
                    right = j - 1 + (a[j - 1] - lambda) / (a[j - 1] - a[j]);
                    break;
                }
            for (int j = bin - 1; j >= 0; j--)
                if (a[j] <= lambda) {
                    left = j + 1 - (a[j + 1] - lambda) / (a[j + 1] - a[j]);
                    break;
                }
            peak.bandwidth = (right - left) * fs / m;
            peaks.add(peak);
        }
        for (Peak peak : peaks) {
            peak.label = "other";
            double q = peak.interpolation.position(), f0 = params.get("fundamental");
            boolean labeled = false;
            for (int h = 1; h <= 10; h++)
                if (Math.abs(q - h * f0 * m / fs) <= params.integer("fundamental", 1)) {
                    peak.label = "h" + h;
                    labeled = true;
                    break;
                }
            if (labeled)
                continue;
            double frequency = q * fs / m;
            int j = (int)Math.floor(frequency / params.integer("notch") + 0.5);
            if (j >= 1 && Math.abs(frequency - j * params.integer("notch")) <= params.integer("notch", 1)) {
                peak.label = "mains";
                continue;
            }
            for (int p = 0; p < peaks.size() && !labeled; p++) {
                Peak center = peaks.get(p);
                if (center == peak)
                    continue;
                for (Peak other : peaks)
                    if (other != peak && other != center && a[center.bin] > a[peak.bin] &&
                        a[center.bin] > a[other.bin] &&
                        Math.abs(q + other.interpolation.position() - 2 * center.interpolation.position()) <=
                            1) {
                        peak.label = "sideband" + (p + 1);
                        labeled = true;
                        break;
                    }
            }
        }
    }
    static void harmonics() {
        harmonicBins = new int[10];
        harmonicAmplitude = new double[10];
        harmonicPosition = new double[10];
        for (int h = 1; h <= 10; h++) {
            int bin = harmonicBin(a, h);
            Spectral.Interpolation interpolation = Spectral.interpolate(a, bin, true);
            harmonicBins[h - 1] = bin;
            harmonicPosition[h - 1] = interpolation.position();
            harmonicAmplitude[h - 1] = interpolation.value();
        }
        power = new double[k + 1];
        for (int bin = 0; bin <= k; bin++)
            power[bin] = a[bin] * a[bin] / 2;
    }
    static void spectrogram() {
        double[][] g = frames.magnitude();
        int count = g.length;
        dominant = new int[count];
        flux = new double[count];
        for (int t = 0; t < count; t++) {
            dominant[t] = largest(g[t], 1, frameLength / 2 - 1);
            if (t > 0)
                for (int bin = 0; bin < g[t].length; bin++)
                    flux[t] += Math.max(0, g[t][bin] - g[t - 1][bin]);
        }
        onsetThreshold = params.get("onset_factor") * Spectral.median(Arrays.copyOfRange(flux, 1, count));
        for (int t = 1; t < count; t++)
            if (flux[t] > onsetThreshold && flux[t] > flux[t - 1] &&
                (t == count - 1 || flux[t] > flux[t + 1]))
                onsets.add(t);
        kurtosis = new double[frameLength / 2 + 1];
        for (int bin = 0; bin < kurtosis.length; bin++) {
            double second = 0, fourth = 0;
            for (int t = 0; t < count; t++) {
                double value = g[t][bin];
                second += value * value;
                fourth += value * value * value * value;
            }
            kurtosis[bin] = count * fourth / (second * second) - 2;
        }
        kurtosisBin = largest(kurtosis, 1, frameLength / 2 - 1);
    }
    static void filters() {
        filtered = new Filtered();
        Fft.Complex[] spectrum = Fft.transform(Fft.real(x, n), false), bandpass = Fft.zeros(n),
                      notched = Fft.zeros(n), analytic = Fft.zeros(n);
        int b1 = params.integer("bandpass"), b2 = params.integer("bandpass", 1), fn = params.integer("notch"),
            wn = params.integer("notch", 1), e1 = params.integer("envelope_band"),
            e2 = params.integer("envelope_band", 1);
        for (int bin = 0; bin < n; bin++) {
            int g = Math.min(bin, n - bin) * fs;
            if (b1 * n <= g && g <= b2 * n) {
                bandpass[bin] = spectrum[bin];
                filtered.kept++;
            }
            int j = (2 * g + fn * n) / (2 * fn * n);
            if (j >= 1 && Math.abs(g - j * fn * n) <= wn * n)
                filtered.removed++;
            else
                notched[bin] = spectrum[bin];
            if (bin >= 1 && bin <= (n - 1) / 2 && e1 * n <= bin * fs && bin * fs <= e2 * n)
                analytic[bin] = spectrum[bin].scale(2);
        }
        filtered.bandpass = real(Fft.transform(bandpass, true));
        filtered.notched = real(Fft.transform(notched, true));
        filtered.analytic = Fft.transform(analytic, true);
        filtered.envelope = new double[n];
        double sum = 0;
        for (int i = 0; i < n; i++) {
            filtered.envelope[i] = filtered.analytic[i].abs();
            sum += filtered.envelope[i];
        }
        filtered.envelopeMean = sum / n;
        double[] centered = new double[n];
        for (int i = 0; i < n; i++)
            centered[i] = filtered.envelope[i] - filtered.envelopeMean;
        Fft.Complex[] envelopeSpectrum = Fft.transform(Fft.real(centered, n), false);
        double[] be = new double[n];
        for (int bin = 0; bin < n; bin++)
            be[bin] = 2 * envelopeSpectrum[bin].abs() / n;
        filtered.envelopeBin = largest(be, 1, (e2 - e1) * n / (2 * fs));
        Spectral.Interpolation interpolation = Spectral.interpolate(be, filtered.envelopeBin, true);
        filtered.envelopeFrequency = interpolation.position() * fs / n;
        filtered.envelopeAmplitude = interpolation.value();
        filtered.depth = filtered.envelopeAmplitude / filtered.envelopeMean;
        double[] frequency = new double[n - 1];
        sum = 0;
        for (int i = 1; i < n; i++) {
            double delta = filtered.analytic[i].argument() - filtered.analytic[i - 1].argument();
            if (delta <= -Fft.PI)
                delta += 2 * Fft.PI;
            if (delta > Fft.PI)
                delta -= 2 * Fft.PI;
            frequency[i - 1] = delta * fs / (2 * Fft.PI);
            sum += frequency[i - 1];
        }
        filtered.instantMean = sum / (n - 1);
        sum = 0;
        for (double value : frequency)
            sum += (value - filtered.instantMean) * (value - filtered.instantMean);
        filtered.instantStd = Math.sqrt(sum / (n - 1));
        double[] fir = params.row("fir");
        filtered.smoothed = Fft.convolve(y, fir);
        Fft.Complex gain = new Fft.Complex(0, 0);
        for (int j = 0; j < fir.length; j++) {
            filtered.firDc += fir[j];
            gain = gain.add(Fft.rotation(2 * Fft.PI * params.get("fundamental") * j / fs).scale(fir[j]));
        }
        filtered.firGain = db20(gain.abs());
    }
    static List<String> spectrumReport() {
        List<String> out = new ArrayList<>(List.of("frequency,amplitude"));
        for (int bin = 0; bin <= k; bin++)
            out.add(f((double)bin * fs / m) + "," + f(a[bin]));
        return out;
    }
    static List<String> peakReport() {
        List<String> out = new ArrayList<>(List.of(
            "length=" + m + " window=" + params.word("main_window") + " resolution=" + f((double)fs / m) +
                " threshold_db=" + f(params.get("peak_threshold_db")),
            "max_amplitude=" + f(maximum) + " noise_floor=" + f(floor) + " noise_floor_db=" + f(db20(floor)),
            "peaks=" + peaks.size()));
        for (int rank = 0; rank < peaks.size(); rank++) {
            Peak p = peaks.get(rank);
            out.add((rank + 1) + " bin=" + p.bin + " frequency=" + f((double)p.bin * fs / m) + " refined=" +
                    f(p.interpolation.position() * fs / m) + " amplitude=" + f(p.interpolation.value()) +
                    " level_db=" + f(p.level) + " phase=" + f(p.phase) + " bandwidth=" + f(p.bandwidth) +
                    " snr_db=" + f(p.snr) + " coherence=" + f(p.coherence) + " label=" + p.label);
        }
        return out;
    }
    static List<String> welchReport() {
        List<String> out = new ArrayList<>(List.of("frequency,psd_db"));
        for (int bin = 0; bin < welch.psd().length; bin++)
            out.add(f((double)bin * fs / l) + "," + f(db10(welch.psd()[bin])));
        return out;
    }
    static List<String> spectrogramReport() {
        List<String> out = new ArrayList<>();
        int count = frames.magnitude().length;
        out.add("frames=" + count + " bins=" + (frameLength / 2 + 1) + " frame_length=" + frameLength +
                " hop=" + hop + " window=" + params.word("spectrogram", 3) +
                " band_db=" + params.integer("spectrogram", 2) + " max_db=" + f(db20(frames.maximum())));
        out.addAll(Report.shades(frames, fs, frameLength, params.integer("spectrogram", 2)));
        out.add("track");
        for (int t = 0; t < count; t++)
            out.add("frame=" + t + " time=" + f((double)t * hop / fs) +
                    " frequency=" + f((double)dominant[t] * fs / frameLength) +
                    " level_db=" + f(db20(frames.magnitude()[t][dominant[t]] / frames.maximum())));
        out.add("onsets=" + onsets.size() + " threshold=" + f(onsetThreshold));
        for (int t : onsets)
            out.add("frame=" + t + " time=" + f((double)t * hop / fs) + " flux=" + f(flux[t]));
        out.add("kurtosis bin=" + kurtosisBin + " frequency=" + f((double)kurtosisBin * fs / frameLength) +
                " value=" + f(kurtosis[kurtosisBin]));
        return out;
    }
    static List<String> filteredReport() {
        List<String> out = new ArrayList<>(List.of("index,bandpass,notched,smoothed,envelope"));
        for (int i = 0; i < n; i++)
            out.add(i + "," + f(filtered.bandpass[i]) + "," + f(filtered.notched[i]) + "," +
                    f(filtered.smoothed[i]) + "," + f(filtered.envelope[i]));
        return out;
    }

    static String yes(boolean value) {
        return value ? "yes" : "no";
    }
    static String check(double error) {
        return error <= 1e-6 ? "ok" : "failed";
    }
    static String statistics(int channel, Statistics s) {
        return "channel=" + channel + " mean=" + f(s.mean()) + " slope=" + f(s.slope()) +
            " rms=" + f(s.rms()) + " min=" + f(s.minimum()) + " max=" + f(s.maximum()) +
            " crest=" + f(s.crest()) + " skewness=" + f(s.skewness()) + " kurtosis=" + f(s.kurtosis());
    }
    static int lag(double[] values, int maximum) {
        int q = values.length, best = -maximum;
        double value = values[q - maximum];
        for (int ell = -maximum; ell <= maximum; ell++) {
            double current = values[ell < 0 ? ell + q : ell];
            if (current > value || current == value && (Math.abs(ell) < Math.abs(best) ||
                                                        Math.abs(ell) == Math.abs(best) && ell < best)) {
                best = ell;
                value = current;
            }
        }
        return best;
    }
    static double refinedLag(double[] values, int lag) {
        int q = values.length;
        double[] triple = {values[lag - 1 < 0 ? lag - 1 + q : lag - 1], values[lag < 0 ? lag + q : lag],
                           values[lag + 1 < 0 ? lag + 1 + q : lag + 1]};
        return lag + (Spectral.interpolate(triple, 1, false).position() - 1);
    }
    static List<String> report() {
        List<String> out = new ArrayList<>();
        out.add("[signal]");
        out.add("sample_rate=" + fs + " samples=" + n + " duration=" + f((double)n / fs));
        out.add(statistics(1, first));
        out.add(statistics(2, second));
        out.add("[levels]");
        int block = params.integer("block_length"), blocks = n / block, loudest = 0;
        double[] rms1 = new double[blocks], rms2 = new double[blocks], peak1 = new double[blocks];
        for (int g = 0; g < blocks; g++) {
            double sx = 0, sy = 0;
            for (int i = g * block; i < (g + 1) * block; i++) {
                sx += x[i] * x[i];
                sy += y[i] * y[i];
                peak1[g] = Math.max(peak1[g], Math.abs(x[i]));
            }
            rms1[g] = Math.sqrt(sx / block);
            rms2[g] = Math.sqrt(sy / block);
            if (rms1[g] > rms1[loudest])
                loudest = g;
        }
        out.add("block_length=" + block + " blocks=" + blocks + " loudest=" + loudest);
        for (int g = 0; g < blocks; g++)
            out.add("block=" + g + " time=" + f((double)g * block / fs) + " rms1=" + f(rms1[g]) +
                    " rms2=" + f(rms2[g]) + " peak1=" + f(peak1[g]));
        out.add("[windows]");
        for (String name : Windows.NAMES) {
            Spectral.Spectrum spectrum = Spectral.amplitude(x, m, name, fs);
            Windows.Window w = spectrum.window();
            int bin = harmonicBin(spectrum.amplitude(), 1);
            double med = Spectral.median(Arrays.copyOfRange(spectrum.amplitude(), 1, k));
            out.add("name=" + name + " coherent_gain=" + f(w.gain()) + " enbw_bins=" + f(w.bins()) +
                    " enbw_hz=" + f(w.hz()) + " scalloping_db=" + f(w.scalloping()) +
                    " fundamental_bin=" + bin + " bin_amplitude=" + f(spectrum.amplitude()[bin]) +
                    " refined_amplitude=" + f(Spectral.interpolate(spectrum.amplitude(), bin, true).value()) +
                    " floor_db=" + f(db20(med)));
        }
        double sum = 0, weighted = 0, logs = 0;
        for (int bin = 1; bin < k; bin++) {
            sum += power[bin];
            weighted += (double)bin * fs / m * power[bin];
            logs += Math.log(power[bin]);
        }
        double totalPower = sum / main.window().bins(), centroid = weighted / sum, spread = 0, cumulative = 0,
               rolloff = 0;
        boolean rolled = false;
        for (int bin = 1; bin < k; bin++) {
            double frequency = (double)bin * fs / m;
            spread += (frequency - centroid) * (frequency - centroid) * power[bin];
            cumulative += power[bin];
            if (!rolled && cumulative >= 0.85 * sum) {
                rolloff = frequency;
                rolled = true;
            }
        }
        spread = Math.sqrt(spread / sum);
        double flatness = db10(Math.exp(logs / (k - 1)) / (sum / (k - 1)));
        out.add("[main]");
        out.add("length=" + m + " window=" + params.word("main_window") +
                " method=" + (Fft.powerOfTwo(m) ? "radix2" : "bluestein") + " transform_size=" +
                (Fft.powerOfTwo(m) ? m : Fft.pow2(2 * m - 1)) + " resolution=" + f((double)fs / m));
        out.add("total_power=" + f(totalPower) + " centroid=" + f(centroid) + " spread=" + f(spread) +
                " rolloff=" + f(rolloff) + " flatness_db=" + f(flatness));
        out.add("[bands]");
        int bandCount = params.values.get("bands").length - 1;
        for (int band = 0; band < bandCount; band++) {
            int low = params.integer("bands", band), high = params.integer("bands", band + 1);
            double value = 0;
            for (int bin = 1; bin < k; bin++)
                if (low * m <= bin * fs && bin * fs < high * m)
                    value += power[bin];
            value /= main.window().bins();
            out.add("range=" + low + "-" + high + " power=" + f(value) +
                    " percent=" + f(100 * value / totalPower));
        }
        out.add("[third_octave]");
        for (int b = params.integer("third_octave"); b <= params.integer("third_octave", 1); b++) {
            double center = 1000 * Math.pow(2, b / 3.0), lower = 1000 * Math.pow(2, (2 * b - 1) / 6.0),
                   upper = 1000 * Math.pow(2, (2 * b + 1) / 6.0), value = 0;
            int bins = 0;
            for (int bin = 1; bin < k; bin++) {
                double frequency = (double)bin * fs / m;
                if (lower <= frequency && frequency < upper) {
                    bins++;
                    value += power[bin];
                }
            }
            value /= main.window().bins();
            out.add("band=" + b + " center=" + f(center) + " lower=" + f(lower) + " upper=" + f(upper) +
                    " bins=" + bins + " level_db=" + f(db10(value)));
        }
        out.add("[harmonics]");
        out.add("fundamental=" + f(params.get("fundamental")) +
                " search=" + params.integer("fundamental", 1));
        for (int h = 1; h <= 10; h++)
            out.add("h=" + h + " target=" + f(h * params.get("fundamental")) + " bin=" + harmonicBins[h - 1] +
                    " refined=" + f(harmonicPosition[h - 1] * fs / m) +
                    " amplitude=" + f(harmonicAmplitude[h - 1]) +
                    " level_db=" + f(db20(harmonicAmplitude[h - 1] / harmonicAmplitude[0])));
        double distortion = 0, fundamentalPower = 0;
        for (int h = 1; h < 10; h++)
            distortion += harmonicAmplitude[h] * harmonicAmplitude[h];
        double thd = Math.sqrt(distortion) / harmonicAmplitude[0];
        for (int bin = 1; bin < k; bin++)
            if (Math.abs(bin - harmonicBins[0]) <= params.integer("fundamental", 1))
                fundamentalPower += power[bin];
        fundamentalPower /= main.window().bins();
        double thdn = Math.sqrt((totalPower - fundamentalPower) / fundamentalPower);
        out.add("thd_percent=" + f(100 * thd) + " thd_db=" + f(db20(thd)));
        out.add("thdn_percent=" + f(100 * thdn) + " thdn_db=" + f(db20(thdn)));
        int p1 = params.integer("pitch_range"), p2 = params.integer("pitch_range", 1),
            lam1 = (fs + p2 - 1) / p2, lam2 = fs / p1, hpsBin = -1;
        double best = Double.NEGATIVE_INFINITY;
        for (int bin = 1; 5 * bin <= k; bin++)
            if (p1 * m <= bin * fs && bin * fs <= p2 * m) {
                double value = 0;
                for (int r = 1; r <= 5; r++)
                    value += Math.log(a[r * bin]);
                if (value > best) {
                    best = value;
                    hpsBin = bin;
                }
            }
        int q = Fft.pow2(2 * n - 1);
        Fft.Complex[] bp = Fft.radix2(Fft.real(filtered.bandpass, q), false);
        for (int bin = 0; bin < q; bin++) {
            double abs = bp[bin].abs();
            bp[bin] = new Fft.Complex(abs * abs, 0);
        }
        double[] rho = real(Fft.radix2(bp, true));
        int ell = largest(rho, lam1, lam2);
        Spectral.Interpolation period = Spectral.interpolate(rho, ell, false);
        int crossings = 0;
        for (int i = 1; i < n; i++)
            if (filtered.bandpass[i - 1] < 0 && filtered.bandpass[i] >= 0)
                crossings++;
        out.add("[pitch]");
        out.add("range=" + p1 + "-" + p2 + " lags=" + lam1 + "-" + lam2);
        out.add("hps bin=" + hpsBin + " order=5 frequency=" + f((double)hpsBin * fs / m));
        out.add("autocorrelation lag=" + ell + " period=" + f(period.position()) +
                " frequency=" + f(fs / period.position()) + " strength=" + f(period.value() / rho[0]));
        out.add("zero_crossing count=" + crossings + " frequency=" + f((double)crossings * fs / n));
        int z1 = params.integer("zoom"), z2 = params.integer("zoom", 1), jCount = params.integer("zoom", 2);
        double dz = (double)(z2 - z1) / (jCount - 1);
        Fft.Complex[] zoom = Fft.chirpZ(main.u(), z1, dz, jCount, fs);
        double[] zoomAmplitude = new double[jCount];
        for (int j = 0; j < jCount; j++)
            zoomAmplitude[j] = 2 * zoom[j].abs() / main.window().s1();
        List<Integer> zoomPeaks = maxima(zoomAmplitude, 3);
        out.add("[zoom]");
        out.add("band=" + z1 + "-" + z2 + " points=" + jCount + " step=" + f(dz));
        for (int rank = 0; rank < zoomPeaks.size(); rank++) {
            Spectral.Interpolation interpolation =
                Spectral.interpolate(zoomAmplitude, zoomPeaks.get(rank), true);
            out.add("peak=" + (rank + 1) + " frequency=" + f(z1 + interpolation.position() * dz) +
                    " amplitude=" + f(interpolation.value()));
        }
        out.add("[welch]");
        out.add("segment_length=" + l + " segments=" + welch.segments() +
                " window=" + params.word("welch", 1) + " resolution=" + f((double)fs / l));
        double integrated = 0;
        for (double value : welch.psd())
            integrated += value;
        integrated = integrated * fs / l;
        double variance = first.rms() * first.rms();
        out.add("integrated_power=" + f(integrated) + " variance=" + f(variance) +
                " ratio=" + f(integrated / variance));
        List<Integer> welchPeaks = maxima(welch.psd(), 5);
        for (int rank = 0; rank < welchPeaks.size(); rank++) {
            int bin = welchPeaks.get(rank);
            out.add("peak=" + (rank + 1) + " frequency=" + f((double)bin * fs / l) +
                    " psd_db=" + f(db10(welch.psd()[bin])) + " coherence=" + f(welch.coherence()[bin]) +
                    " gain=" + f(welch.transfer()[bin].abs()) +
                    " phase=" + f(welch.transfer()[bin].argument() * 180 / Fft.PI));
        }
        out.add("[filter]");
        out.add("bandpass=" + params.integer("bandpass") + "-" + params.integer("bandpass", 1) +
                " bins_kept=" + filtered.kept + " rms=" + f(rms(filtered.bandpass, n)) +
                " energy_ratio=" + f(squares(filtered.bandpass, n) / first.squares()));
        out.add("notch=" + params.integer("notch") + " width=" + params.integer("notch", 1) +
                " bins_removed=" + filtered.removed + " rms=" + f(rms(filtered.notched, n)));
        out.add("fir_taps=" + params.row("fir").length + " dc_gain=" + f(filtered.firDc) +
                " gain_at_fundamental_db=" + f(filtered.firGain) + " rms=" + f(rms(filtered.smoothed, n)));
        out.add("[envelope]");
        out.add("band=" + params.integer("envelope_band") + "-" + params.integer("envelope_band", 1) +
                " mean=" + f(filtered.envelopeMean) + " bin=" + filtered.envelopeBin +
                " frequency=" + f(filtered.envelopeFrequency) +
                " amplitude=" + f(filtered.envelopeAmplitude) + " depth=" + f(filtered.depth));
        out.add("instantaneous_frequency mean=" + f(filtered.instantMean) + " std=" + f(filtered.instantStd));
        Fft.Complex[] fx = Fft.radix2(Fft.real(x, q), false), fy = Fft.radix2(Fft.real(y, q), false),
                      cross = new Fft.Complex[q], phat = new Fft.Complex[q];
        for (int bin = 0; bin < q; bin++) {
            cross[bin] = fx[bin].conjugate().multiply(fy[bin]);
            phat[bin] = cross[bin].divide(cross[bin].abs());
        }
        double[] correlation = real(Fft.radix2(cross, true)), phatCorrelation = real(Fft.radix2(phat, true));
        int maxLag = params.integer("max_lag"), lag = lag(correlation, maxLag),
            phatLag = lag(phatCorrelation, maxLag);
        double refined = refinedLag(correlation, lag), phatRefined = refinedLag(phatCorrelation, phatLag);
        out.add("[correlation]");
        out.add("max_lag=" + maxLag + " lag=" + lag + " refined_lag=" + f(refined) +
                " delay_ms=" + f(1000 * refined / fs) + " coefficient=" +
                f(correlation[lag < 0 ? lag + q : lag] / Math.sqrt(first.squares() * second.squares())));
        out.add("phat_lag=" + phatLag + " refined_lag=" + f(phatRefined) +
                " delay_ms=" + f(1000 * phatRefined / fs));
        Fft.Complex[] inverse = Fft.transform(main.transform(), true);
        double inverseError = 0, frequencyPower = 0;
        for (int i = 0; i < m; i++) {
            inverseError = Math.max(inverseError, inverse[i].subtract(new Fft.Complex(main.u()[i], 0)).abs());
            double abs = main.transform()[i].abs();
            frequencyPower += abs * abs;
        }
        double timePower = squares(main.u(), m),
               parseval = Math.abs(timePower - frequencyPower / m) / timePower, firError = 0, spotError = 0;
        double[] fir = params.row("fir");
        for (int i = 0; i < filtered.smoothed.length; i++) {
            double direct = 0;
            for (int j = Math.max(0, i - fir.length + 1); j <= Math.min(n - 1, i); j++)
                direct += y[j] * fir[i - j];
            firError = Math.max(firError, Math.abs(filtered.smoothed[i] - direct));
        }
        for (Peak peak : peaks) {
            Fft.Complex direct = new Fft.Complex(0, 0);
            for (int i = 0; i < m; i++)
                direct = direct.add(Fft.rotation(2 * Fft.PI * ((peak.bin * i) % m) / m).scale(main.u()[i]));
            spotError = Math.max(spotError, direct.subtract(main.transform()[peak.bin]).abs());
        }
        out.add("[checks]");
        out.add("inverse_roundtrip=" + check(inverseError));
        out.add("parseval=" + check(parseval));
        out.add("real_packing=" + check(Math.max(welch.error(), frames.error())) +
                " transforms=" + (2 * welch.segments() + frames.magnitude().length));
        out.add("fir_fft_vs_direct=" + check(firError));
        out.add("dft_spot_check=" + check(spotError) + " bins=" + peaks.size());
        double ratio = harmonicAmplitude[1] / harmonicAmplitude[0];
        int harmonics = 0;
        for (int h = 2; h < 10; h++)
            if (db20(harmonicAmplitude[h] / harmonicAmplitude[0]) >= -30)
                harmonics++;
        Double electricalLevel = null;
        for (Peak peak : peaks)
            if (peak.label.equals("mains")) {
                electricalLevel = peak.level;
                break;
            }
        boolean misalignment = ratio >= 0.5, looseness = harmonics >= 3, bearing = filtered.depth >= 0.2,
                electrical = electricalLevel != null && electricalLevel >= -20,
                transientFinding = !onsets.isEmpty();
        int findings = (misalignment ? 1 : 0) + (looseness ? 1 : 0) + (bearing ? 1 : 0) +
                       (electrical ? 1 : 0) + (transientFinding ? 1 : 0);
        out.add("[diagnosis]");
        out.add("misalignment=" + yes(misalignment) + " ratio=" + f(ratio));
        out.add("looseness=" + yes(looseness) + " harmonics=" + harmonics);
        out.add("bearing=" + yes(bearing) + " depth=" + f(filtered.depth));
        out.add("electrical=" + yes(electrical) +
                " level_db=" + (electricalLevel == null ? "none" : f(electricalLevel)));
        out.add("transient=" + yes(transientFinding) + " onsets=" + onsets.size());
        out.add("status=" +
                (findings == 0   ? "normal"
                 : findings == 1 ? "warning"
                                 : "alarm") +
                " findings=" + findings);
        return out;
    }
    public static void main(String[] args) throws IOException {
        SignalIo.Data data = SignalIo.read();
        fs = data.fs();
        params = data.params();
        n = data.first().length;
        m = params.integer("main_length");
        k = m / 2;
        l = params.integer("welch");
        frameLength = params.integer("spectrogram");
        hop = params.integer("spectrogram", 1);
        first = preprocess(data.first());
        second = preprocess(data.second());
        x = first.detrended();
        y = second.detrended();
        main = Spectral.amplitude(x, m, params.word("main_window"), fs);
        a = main.amplitude();
        welch = Spectral.welch(x, y, l, params.word("welch", 1), fs);
        frames = Spectral.frames(x, frameLength, hop, params.word("spectrogram", 3), fs);
        peaks();
        harmonics();
        spectrogram();
        filters();
        Report.write("spectrum.csv", spectrumReport());
        Report.write("peaks.txt", peakReport());
        Report.write("welch_psd.csv", welchReport());
        Report.write("spectrogram.txt", spectrogramReport());
        Report.write("filtered.csv", filteredReport());
        Report.write("report.txt", report());
    }
}
