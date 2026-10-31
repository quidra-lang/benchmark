using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public record Statistics(double[] detrended, double mean, double slope, double rms, double minimum,
                             double maximum, double crest, double skewness, double kurtosis, double squares) {
    }
    public sealed class Peak {
        public int bin;
        public Spectral.Interpolation interpolation;
        public double level, phase, bandwidth, snr, coherence;
        public string label;
    }
    public sealed class Filtered {
        public double[] bandpass, notched, smoothed, envelope;
        public Fft.Complex[] analytic;
        public int kept, removed, envelopeBin;
        public double envelopeMean, envelopeFrequency, envelopeAmplitude, depth, instantMean, instantStd,
            firDc, firGain;
    }
    public static int fs, n, m, k, l, frameLength, hop;
    public static SignalIo.Params settings;
    public static Statistics first, second;
    public static double[] x, y, a, harmonicAmplitude, harmonicPosition, power, flux, kurtosis;
    public static int[] harmonicBins, dominant;
    public static List<Peak> peaks = new();
    public static Spectral.Spectrum main;
    public static Spectral.Welch welch;
    public static Spectral.Frames frames;
    public static Filtered filtered;
    public static double floor, maximum, onsetThreshold;
    public static List<int> onsets = new();
    public static int kurtosisBin;
    public static string F(double value) {
        return Report.F(value);
    }
    public static double Db20(double value) {
        return 20 * Math.Log10(value);
    }
    public static double Db10(double value) {
        return 10 * Math.Log10(value);
    }
    public static double Squares(double[] values, int length) {
        double sum = 0;
        for (int i = 0; i < length; i++)
            sum += values[i] * values[i];
        return sum;
    }
    public static double Rms(double[] values, int length) {
        return Math.Sqrt(Squares(values, length) / length);
    }
    public static double[] Real(Fft.Complex[] values) {
        double[] result = new double[values.Length];
        for (int i = 0; i < values.Length; i++)
            result[i] = values[i].re;
        return result;
    }
    public static Statistics Preprocess(double[] signal) {
        int n = signal.Length;
        double sum = 0, minimum = signal[0], maximum = signal[0];
        foreach (double value in signal) {
            sum += value;
            minimum = Math.Min(minimum, value);
            maximum = Math.Max(maximum, value);
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
            peak = Math.Max(peak, Math.Abs(d[i]));
        }
        double rms = Math.Sqrt(square / n);
        return new Statistics(d, mean, slope * fs, rms, minimum, maximum, peak / rms,
                              (cube / n) / (rms * rms * rms), (fourth / n) / (rms * rms * rms * rms), square);
    }
    public static List<int> Maxima(double[] values, int limit) {
        List<int> result = new();
        for (int j = 1; j + 1 < values.Length; j++)
            if (Spectral.Local(values, j))
                result.Add(j);
        result.Sort((p, q) => {
            int c = (values[q]).CompareTo(values[p]);
            return c != 0 ? c : (p).CompareTo(q);
        });
        return new(result.GetRange(0, Math.Min(limit, result.Count) - (0)));
    }
    public static int Largest(double[] values, int first, int last) {
        int best = first;
        for (int j = first + 1; j <= last; j++)
            if (values[j] > values[best])
                best = j;
        return best;
    }
    public static int HarmonicBin(double[] values, int h) {
        double center = h * settings.Get("fundamental") * m / fs;
        int best = -1;
        for (int bin = 1; bin < k; bin++)
            if (Math.Abs(bin - center) <= settings.Integer("fundamental", 1) &&
                (best < 0 || values[bin] > values[best]))
                best = bin;
        return best;
    }
    public static void Peaks() {
        maximum = a[0];
        foreach (double value in a)
            maximum = Math.Max(maximum, value);
        floor = Spectral.Median(a.Skip(1).Take(k - (1)).ToArray());
        List<int> bins = new();
        for (int bin = 1; bin < k; bin++)
            if (Spectral.Local(a, bin) && Db20(a[bin] / maximum) >= settings.Get("peak_threshold_db"))
                bins.Add(bin);
        bins.Sort((p, q) => {
            int c = (a[q]).CompareTo(a[p]);
            return c != 0 ? c : (p).CompareTo(q);
        });
        for (int rank = 0; rank < Math.Min(bins.Count, settings.Integer("peak_count")); rank++) {
            int bin = bins[rank];
            Peak peak = new Peak();
            peak.bin = bin;
            peak.interpolation = Spectral.Interpolate(a, bin, true);
            peak.level = Db20(a[bin] / maximum);
            peak.phase = main.transform[bin].Argument() * 180 / Fft.PI;
            peak.snr = Db20(a[bin] / floor);
            peak.coherence = welch.coherence[(2 * bin * l + m) / (2 * m)];
            double lambda = a[bin] / Math.Sqrt(2), left = 0, right = k;
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
            peaks.Add(peak);
        }
        foreach (Peak peak in peaks) {
            peak.label = "other";
            double q = peak.interpolation.position, f0 = settings.Get("fundamental");
            bool labeled = false;
            for (int h = 1; h <= 10; h++)
                if (Math.Abs(q - h * f0 * m / fs) <= settings.Integer("fundamental", 1)) {
                    peak.label = "h" + h;
                    labeled = true;
                    break;
                }
            if (labeled)
                continue;
            double frequency = q * fs / m;
            int j = (int)Math.Floor(frequency / settings.Integer("notch") + 0.5);
            if (j >= 1 &&
                Math.Abs(frequency - j * settings.Integer("notch")) <= settings.Integer("notch", 1)) {
                peak.label = "mains";
                continue;
            }
            for (int p = 0; p < peaks.Count && !labeled; p++) {
                Peak center = peaks[p];
                if (center == peak)
                    continue;
                foreach (Peak other in peaks)
                    if (other != peak && other != center && a[center.bin] > a[peak.bin] &&
                        a[center.bin] > a[other.bin] &&
                        Math.Abs(q + other.interpolation.position - 2 * center.interpolation.position) <= 1) {
                        peak.label = "sideband" + (p + 1);
                        labeled = true;
                        break;
                    }
            }
        }
    }
    public static void Harmonics() {
        harmonicBins = new int[10];
        harmonicAmplitude = new double[10];
        harmonicPosition = new double[10];
        for (int h = 1; h <= 10; h++) {
            int bin = HarmonicBin(a, h);
            Spectral.Interpolation interpolation = Spectral.Interpolate(a, bin, true);
            harmonicBins[h - 1] = bin;
            harmonicPosition[h - 1] = interpolation.position;
            harmonicAmplitude[h - 1] = interpolation.value;
        }
        power = new double[k + 1];
        for (int bin = 0; bin <= k; bin++)
            power[bin] = a[bin] * a[bin] / 2;
    }
    public static void Spectrogram() {
        double[][] g = frames.magnitude;
        int count = g.Length;
        dominant = new int[count];
        flux = new double[count];
        for (int t = 0; t < count; t++) {
            dominant[t] = Largest(g[t], 1, frameLength / 2 - 1);
            if (t > 0)
                for (int bin = 0; bin < g[t].Length; bin++)
                    flux[t] += Math.Max(0, g[t][bin] - g[t - 1][bin]);
        }
        onsetThreshold =
            settings.Get("onset_factor") * Spectral.Median(flux.Skip(1).Take(count - (1)).ToArray());
        for (int t = 1; t < count; t++)
            if (flux[t] > onsetThreshold && flux[t] > flux[t - 1] &&
                (t == count - 1 || flux[t] > flux[t + 1]))
                onsets.Add(t);
        kurtosis = new double[frameLength / 2 + 1];
        for (int bin = 0; bin < kurtosis.Length; bin++) {
            double second = 0, fourth = 0;
            for (int t = 0; t < count; t++) {
                double value = g[t][bin];
                second += value * value;
                fourth += value * value * value * value;
            }
            kurtosis[bin] = count * fourth / (second * second) - 2;
        }
        kurtosisBin = Largest(kurtosis, 1, frameLength / 2 - 1);
    }
    public static void Filters() {
        filtered = new Filtered();
        Fft.Complex[] spectrum = Fft.Transform(Fft.Real(x, n), false), bandpass = Fft.Zeros(n),
                      notched = Fft.Zeros(n), analytic = Fft.Zeros(n);
        int b1 = settings.Integer("bandpass"), b2 = settings.Integer("bandpass", 1),
            fn = settings.Integer("notch"), wn = settings.Integer("notch", 1),
            e1 = settings.Integer("envelope_band"), e2 = settings.Integer("envelope_band", 1);
        for (int bin = 0; bin < n; bin++) {
            int g = Math.Min(bin, n - bin) * fs;
            if (b1 * n <= g && g <= b2 * n) {
                bandpass[bin] = spectrum[bin];
                filtered.kept++;
            }
            int j = (2 * g + fn * n) / (2 * fn * n);
            if (j >= 1 && Math.Abs(g - j * fn * n) <= wn * n)
                filtered.removed++;
            else
                notched[bin] = spectrum[bin];
            if (bin >= 1 && bin <= (n - 1) / 2 && e1 * n <= bin * fs && bin * fs <= e2 * n)
                analytic[bin] = spectrum[bin].Scale(2);
        }
        filtered.bandpass = Real(Fft.Transform(bandpass, true));
        filtered.notched = Real(Fft.Transform(notched, true));
        filtered.analytic = Fft.Transform(analytic, true);
        filtered.envelope = new double[n];
        double sum = 0;
        for (int i = 0; i < n; i++) {
            filtered.envelope[i] = filtered.analytic[i].Abs();
            sum += filtered.envelope[i];
        }
        filtered.envelopeMean = sum / n;
        double[] centered = new double[n];
        for (int i = 0; i < n; i++)
            centered[i] = filtered.envelope[i] - filtered.envelopeMean;
        Fft.Complex[] envelopeSpectrum = Fft.Transform(Fft.Real(centered, n), false);
        double[] be = new double[n];
        for (int bin = 0; bin < n; bin++)
            be[bin] = 2 * envelopeSpectrum[bin].Abs() / n;
        filtered.envelopeBin = Largest(be, 1, (e2 - e1) * n / (2 * fs));
        Spectral.Interpolation interpolation = Spectral.Interpolate(be, filtered.envelopeBin, true);
        filtered.envelopeFrequency = interpolation.position * fs / n;
        filtered.envelopeAmplitude = interpolation.value;
        filtered.depth = filtered.envelopeAmplitude / filtered.envelopeMean;
        double[] frequency = new double[n - 1];
        sum = 0;
        for (int i = 1; i < n; i++) {
            double delta = filtered.analytic[i].Argument() - filtered.analytic[i - 1].Argument();
            if (delta <= -Fft.PI)
                delta += 2 * Fft.PI;
            if (delta > Fft.PI)
                delta -= 2 * Fft.PI;
            frequency[i - 1] = delta * fs / (2 * Fft.PI);
            sum += frequency[i - 1];
        }
        filtered.instantMean = sum / (n - 1);
        sum = 0;
        foreach (double value in frequency)
            sum += (value - filtered.instantMean) * (value - filtered.instantMean);
        filtered.instantStd = Math.Sqrt(sum / (n - 1));
        double[] fir = settings.Row("fir");
        filtered.smoothed = Fft.Convolve(y, fir);
        Fft.Complex gain = new Fft.Complex(0, 0);
        for (int j = 0; j < fir.Length; j++) {
            filtered.firDc += fir[j];
            gain = gain.Add(Fft.Rotation(2 * Fft.PI * settings.Get("fundamental") * j / fs).Scale(fir[j]));
        }
        filtered.firGain = Db20(gain.Abs());
    }
    public static List<string> SpectrumReport() {
        List<string> output = new(["frequency,amplitude"]);
        for (int bin = 0; bin <= k; bin++)
            output.Add(F((double)bin * fs / m) + "," + F(a[bin]));
        return output;
    }
    public static List<string> PeakReport() {
        List<string> output = new([
            "length=" + m + " window=" + settings.Word("main_window") + " resolution=" + F((double)fs / m) +
                " threshold_db=" + F(settings.Get("peak_threshold_db")),
            "max_amplitude=" + F(maximum) + " noise_floor=" + F(floor) + " noise_floor_db=" + F(Db20(floor)),
            "peaks=" + peaks.Count
        ]);
        for (int rank = 0; rank < peaks.Count; rank++) {
            Peak p = peaks[rank];
            output.Add((rank + 1) + " bin=" + p.bin + " frequency=" + F((double)p.bin * fs / m) +
                       " refined=" + F(p.interpolation.position * fs / m) +
                       " amplitude=" + F(p.interpolation.value) + " level_db=" + F(p.level) +
                       " phase=" + F(p.phase) + " bandwidth=" + F(p.bandwidth) + " snr_db=" + F(p.snr) +
                       " coherence=" + F(p.coherence) + " label=" + p.label);
        }
        return output;
    }
    public static List<string> WelchReport() {
        List<string> output = new(["frequency,psd_db"]);
        for (int bin = 0; bin < welch.psd.Length; bin++)
            output.Add(F((double)bin * fs / l) + "," + F(Db10(welch.psd[bin])));
        return output;
    }
    public static List<string> SpectrogramReport() {
        List<string> output = new();
        int count = frames.magnitude.Length;
        output.Add("frames=" + count + " bins=" + (frameLength / 2 + 1) + " frame_length=" + frameLength +
                   " hop=" + hop + " window=" + settings.Word("spectrogram", 3) +
                   " band_db=" + settings.Integer("spectrogram", 2) + " max_db=" + F(Db20(frames.maximum)));
        output.AddRange(Report.Shades(frames, fs, frameLength, settings.Integer("spectrogram", 2)));
        output.Add("track");
        for (int t = 0; t < count; t++)
            output.Add("frame=" + t + " time=" + F((double)t * hop / fs) +
                       " frequency=" + F((double)dominant[t] * fs / frameLength) +
                       " level_db=" + F(Db20(frames.magnitude[t][dominant[t]] / frames.maximum)));
        output.Add("onsets=" + onsets.Count + " threshold=" + F(onsetThreshold));
        foreach (int t in onsets)
            output.Add("frame=" + t + " time=" + F((double)t * hop / fs) + " flux=" + F(flux[t]));
        output.Add("kurtosis bin=" + kurtosisBin + " frequency=" + F((double)kurtosisBin * fs / frameLength) +
                   " value=" + F(kurtosis[kurtosisBin]));
        return output;
    }
    public static List<string> FilteredReport() {
        List<string> output = new(["index,bandpass,notched,smoothed,envelope"]);
        for (int i = 0; i < n; i++)
            output.Add(i + "," + F(filtered.bandpass[i]) + "," + F(filtered.notched[i]) + "," +
                       F(filtered.smoothed[i]) + "," + F(filtered.envelope[i]));
        return output;
    }

    public static string Yes(bool value) {
        return value ? "yes" : "no";
    }
    public static string Check(double error) {
        return error <= 1e-6 ? "ok" : "failed";
    }
    public static string FormatStatistics(int channel, Statistics s) {
        return "channel=" + channel + " mean=" + F(s.mean) + " slope=" + F(s.slope) + " rms=" + F(s.rms) +
               " min=" + F(s.minimum) + " max=" + F(s.maximum) + " crest=" + F(s.crest) +
               " skewness=" + F(s.skewness) + " kurtosis=" + F(s.kurtosis);
    }
    public static int Lag(double[] values, int maximum) {
        int q = values.Length, best = -maximum;
        double value = values[q - maximum];
        for (int ell = -maximum; ell <= maximum; ell++) {
            double current = values[ell < 0 ? ell + q : ell];
            if (current > value || current == value && (Math.Abs(ell) < Math.Abs(best) ||
                                                        Math.Abs(ell) == Math.Abs(best) && ell < best)) {
                best = ell;
                value = current;
            }
        }
        return best;
    }
    public static double RefinedLag(double[] values, int lag) {
        int q = values.Length;
        double[] triple = { values[lag - 1 < 0 ? lag - 1 + q : lag - 1], values[lag < 0 ? lag + q : lag],
                            values[lag + 1 < 0 ? lag + 1 + q : lag + 1] };
        return lag + (Spectral.Interpolate(triple, 1, false).position - 1);
    }
    public static List<string> Report() {
        List<string> output = new();
        output.Add("[signal]");
        output.Add("sample_rate=" + fs + " samples=" + n + " duration=" + F((double)n / fs));
        output.Add(FormatStatistics(1, first));
        output.Add(FormatStatistics(2, second));
        output.Add("[levels]");
        int block = settings.Integer("block_length"), blocks = n / block, loudest = 0;
        double[] rms1 = new double[blocks], rms2 = new double[blocks], peak1 = new double[blocks];
        for (int g = 0; g < blocks; g++) {
            double sx = 0, sy = 0;
            for (int i = g * block; i < (g + 1) * block; i++) {
                sx += x[i] * x[i];
                sy += y[i] * y[i];
                peak1[g] = Math.Max(peak1[g], Math.Abs(x[i]));
            }
            rms1[g] = Math.Sqrt(sx / block);
            rms2[g] = Math.Sqrt(sy / block);
            if (rms1[g] > rms1[loudest])
                loudest = g;
        }
        output.Add("block_length=" + block + " blocks=" + blocks + " loudest=" + loudest);
        for (int g = 0; g < blocks; g++)
            output.Add("block=" + g + " time=" + F((double)g * block / fs) + " rms1=" + F(rms1[g]) +
                       " rms2=" + F(rms2[g]) + " peak1=" + F(peak1[g]));
        output.Add("[windows]");
        foreach (string name in Windows.NAMES) {
            Spectral.Spectrum spectrum = Spectral.Amplitude(x, m, name, fs);
            Windows.Window w = spectrum.window;
            int bin = HarmonicBin(spectrum.amplitude, 1);
            double med = Spectral.Median(spectrum.amplitude.Skip(1).Take(k - (1)).ToArray());
            output.Add("name=" + name + " coherent_gain=" + F(w.gain) + " enbw_bins=" + F(w.bins) +
                       " enbw_hz=" + F(w.hz) + " scalloping_db=" + F(w.scalloping) +
                       " fundamental_bin=" + bin + " bin_amplitude=" + F(spectrum.amplitude[bin]) +
                       " refined_amplitude=" + F(Spectral.Interpolate(spectrum.amplitude, bin, true).value) +
                       " floor_db=" + F(Db20(med)));
        }
        double sum = 0, weighted = 0, logs = 0;
        for (int bin = 1; bin < k; bin++) {
            sum += power[bin];
            weighted += (double)bin * fs / m * power[bin];
            logs += Math.Log(power[bin]);
        }
        double totalPower = sum / main.window.bins, centroid = weighted / sum, spread = 0, cumulative = 0,
               rolloff = 0;
        bool rolled = false;
        for (int bin = 1; bin < k; bin++) {
            double frequency = (double)bin * fs / m;
            spread += (frequency - centroid) * (frequency - centroid) * power[bin];
            cumulative += power[bin];
            if (!rolled && cumulative >= 0.85 * sum) {
                rolloff = frequency;
                rolled = true;
            }
        }
        spread = Math.Sqrt(spread / sum);
        double flatness = Db10(Math.Exp(logs / (k - 1)) / (sum / (k - 1)));
        output.Add("[main]");
        output.Add("length=" + m + " window=" + settings.Word("main_window") +
                   " method=" + (Fft.PowerOfTwo(m) ? "radix2" : "bluestein") + " transform_size=" +
                   (Fft.PowerOfTwo(m) ? m : Fft.Pow2(2 * m - 1)) + " resolution=" + F((double)fs / m));
        output.Add("total_power=" + F(totalPower) + " centroid=" + F(centroid) + " spread=" + F(spread) +
                   " rolloff=" + F(rolloff) + " flatness_db=" + F(flatness));
        output.Add("[bands]");
        int bandCount = settings.values["bands"].Length - 1;
        for (int band = 0; band < bandCount; band++) {
            int low = settings.Integer("bands", band), high = settings.Integer("bands", band + 1);
            double value = 0;
            for (int bin = 1; bin < k; bin++)
                if (low * m <= bin * fs && bin * fs < high * m)
                    value += power[bin];
            value /= main.window.bins;
            output.Add("range=" + low + "-" + high + " power=" + F(value) +
                       " percent=" + F(100 * value / totalPower));
        }
        output.Add("[third_octave]");
        for (int b = settings.Integer("third_octave"); b <= settings.Integer("third_octave", 1); b++) {
            double center = 1000 * Math.Pow(2, b / 3.0), lower = 1000 * Math.Pow(2, (2 * b - 1) / 6.0),
                   upper = 1000 * Math.Pow(2, (2 * b + 1) / 6.0), value = 0;
            int bins = 0;
            for (int bin = 1; bin < k; bin++) {
                double frequency = (double)bin * fs / m;
                if (lower <= frequency && frequency < upper) {
                    bins++;
                    value += power[bin];
                }
            }
            value /= main.window.bins;
            output.Add("band=" + b + " center=" + F(center) + " lower=" + F(lower) + " upper=" + F(upper) +
                       " bins=" + bins + " level_db=" + F(Db10(value)));
        }
        output.Add("[harmonics]");
        output.Add("fundamental=" + F(settings.Get("fundamental")) +
                   " search=" + settings.Integer("fundamental", 1));
        for (int h = 1; h <= 10; h++)
            output.Add("h=" + h + " target=" + F(h * settings.Get("fundamental")) +
                       " bin=" + harmonicBins[h - 1] + " refined=" + F(harmonicPosition[h - 1] * fs / m) +
                       " amplitude=" + F(harmonicAmplitude[h - 1]) +
                       " level_db=" + F(Db20(harmonicAmplitude[h - 1] / harmonicAmplitude[0])));
        double distortion = 0, fundamentalPower = 0;
        for (int h = 1; h < 10; h++)
            distortion += harmonicAmplitude[h] * harmonicAmplitude[h];
        double thd = Math.Sqrt(distortion) / harmonicAmplitude[0];
        for (int bin = 1; bin < k; bin++)
            if (Math.Abs(bin - harmonicBins[0]) <= settings.Integer("fundamental", 1))
                fundamentalPower += power[bin];
        fundamentalPower /= main.window.bins;
        double thdn = Math.Sqrt((totalPower - fundamentalPower) / fundamentalPower);
        output.Add("thd_percent=" + F(100 * thd) + " thd_db=" + F(Db20(thd)));
        output.Add("thdn_percent=" + F(100 * thdn) + " thdn_db=" + F(Db20(thdn)));
        int p1 = settings.Integer("pitch_range"), p2 = settings.Integer("pitch_range", 1),
            lam1 = (fs + p2 - 1) / p2, lam2 = fs / p1, hpsBin = -1;
        double best = double.NegativeInfinity;
        for (int bin = 1; 5 * bin <= k; bin++)
            if (p1 * m <= bin * fs && bin * fs <= p2 * m) {
                double value = 0;
                for (int r = 1; r <= 5; r++)
                    value += Math.Log(a[r * bin]);
                if (value > best) {
                    best = value;
                    hpsBin = bin;
                }
            }
        int q = Fft.Pow2(2 * n - 1);
        Fft.Complex[] bp = Fft.Radix2(Fft.Real(filtered.bandpass, q), false);
        for (int bin = 0; bin < q; bin++) {
            double abs = bp[bin].Abs();
            bp[bin] = new Fft.Complex(abs * abs, 0);
        }
        double[] rho = Real(Fft.Radix2(bp, true));
        int ell = Largest(rho, lam1, lam2);
        Spectral.Interpolation period = Spectral.Interpolate(rho, ell, false);
        int crossings = 0;
        for (int i = 1; i < n; i++)
            if (filtered.bandpass[i - 1] < 0 && filtered.bandpass[i] >= 0)
                crossings++;
        output.Add("[pitch]");
        output.Add("range=" + p1 + "-" + p2 + " lags=" + lam1 + "-" + lam2);
        output.Add("hps bin=" + hpsBin + " order=5 frequency=" + F((double)hpsBin * fs / m));
        output.Add("autocorrelation lag=" + ell + " period=" + F(period.position) +
                   " frequency=" + F(fs / period.position) + " strength=" + F(period.value / rho[0]));
        output.Add("zero_crossing count=" + crossings + " frequency=" + F((double)crossings * fs / n));
        int z1 = settings.Integer("zoom"), z2 = settings.Integer("zoom", 1),
            jCount = settings.Integer("zoom", 2);
        double dz = (double)(z2 - z1) / (jCount - 1);
        Fft.Complex[] zoom = Fft.ChirpZ(main.u, z1, dz, jCount, fs);
        double[] zoomAmplitude = new double[jCount];
        for (int j = 0; j < jCount; j++)
            zoomAmplitude[j] = 2 * zoom[j].Abs() / main.window.s1;
        List<int> zoomPeaks = Maxima(zoomAmplitude, 3);
        output.Add("[zoom]");
        output.Add("band=" + z1 + "-" + z2 + " points=" + jCount + " step=" + F(dz));
        for (int rank = 0; rank < zoomPeaks.Count; rank++) {
            Spectral.Interpolation interpolation = Spectral.Interpolate(zoomAmplitude, zoomPeaks[rank], true);
            output.Add("peak=" + (rank + 1) + " frequency=" + F(z1 + interpolation.position * dz) +
                       " amplitude=" + F(interpolation.value));
        }
        output.Add("[welch]");
        output.Add("segment_length=" + l + " segments=" + welch.segments +
                   " window=" + settings.Word("welch", 1) + " resolution=" + F((double)fs / l));
        double integrated = 0;
        foreach (double value in welch.psd)
            integrated += value;
        integrated = integrated * fs / l;
        double variance = first.rms * first.rms;
        output.Add("integrated_power=" + F(integrated) + " variance=" + F(variance) +
                   " ratio=" + F(integrated / variance));
        List<int> welchPeaks = Maxima(welch.psd, 5);
        for (int rank = 0; rank < welchPeaks.Count; rank++) {
            int bin = welchPeaks[rank];
            output.Add("peak=" + (rank + 1) + " frequency=" + F((double)bin * fs / l) +
                       " psd_db=" + F(Db10(welch.psd[bin])) + " coherence=" + F(welch.coherence[bin]) +
                       " gain=" + F(welch.transfer[bin].Abs()) +
                       " phase=" + F(welch.transfer[bin].Argument() * 180 / Fft.PI));
        }
        output.Add("[filter]");
        output.Add("bandpass=" + settings.Integer("bandpass") + "-" + settings.Integer("bandpass", 1) +
                   " bins_kept=" + filtered.kept + " rms=" + F(Rms(filtered.bandpass, n)) +
                   " energy_ratio=" + F(Squares(filtered.bandpass, n) / first.squares));
        output.Add("notch=" + settings.Integer("notch") + " width=" + settings.Integer("notch", 1) +
                   " bins_removed=" + filtered.removed + " rms=" + F(Rms(filtered.notched, n)));
        output.Add("fir_taps=" + settings.Row("fir").Length + " dc_gain=" + F(filtered.firDc) +
                   " gain_at_fundamental_db=" + F(filtered.firGain) + " rms=" + F(Rms(filtered.smoothed, n)));
        output.Add("[envelope]");
        output.Add("band=" + settings.Integer("envelope_band") + "-" + settings.Integer("envelope_band", 1) +
                   " mean=" + F(filtered.envelopeMean) + " bin=" + filtered.envelopeBin +
                   " frequency=" + F(filtered.envelopeFrequency) +
                   " amplitude=" + F(filtered.envelopeAmplitude) + " depth=" + F(filtered.depth));
        output.Add("instantaneous_frequency mean=" + F(filtered.instantMean) +
                   " std=" + F(filtered.instantStd));
        Fft.Complex[] fx = Fft.Radix2(Fft.Real(x, q), false), fy = Fft.Radix2(Fft.Real(y, q), false),
                      cross = new Fft.Complex[q], phat = new Fft.Complex[q];
        for (int bin = 0; bin < q; bin++) {
            cross[bin] = fx[bin].Conjugate().Multiply(fy[bin]);
            phat[bin] = cross[bin].Divide(cross[bin].Abs());
        }
        double[] correlation = Real(Fft.Radix2(cross, true)), phatCorrelation = Real(Fft.Radix2(phat, true));
        int maxLag = settings.Integer("max_lag"), lag = Lag(correlation, maxLag),
            phatLag = Lag(phatCorrelation, maxLag);
        double refined = RefinedLag(correlation, lag), phatRefined = RefinedLag(phatCorrelation, phatLag);
        output.Add("[correlation]");
        output.Add("max_lag=" + maxLag + " lag=" + lag + " refined_lag=" + F(refined) +
                   " delay_ms=" + F(1000 * refined / fs) + " coefficient=" +
                   F(correlation[lag < 0 ? lag + q : lag] / Math.Sqrt(first.squares * second.squares)));
        output.Add("phat_lag=" + phatLag + " refined_lag=" + F(phatRefined) +
                   " delay_ms=" + F(1000 * phatRefined / fs));
        Fft.Complex[] inverse = Fft.Transform(main.transform, true);
        double inverseError = 0, frequencyPower = 0;
        for (int i = 0; i < m; i++) {
            inverseError = Math.Max(inverseError, inverse[i].Subtract(new Fft.Complex(main.u[i], 0)).Abs());
            double abs = main.transform[i].Abs();
            frequencyPower += abs * abs;
        }
        double timePower = Squares(main.u, m),
               parseval = Math.Abs(timePower - frequencyPower / m) / timePower, firError = 0, spotError = 0;
        double[] fir = settings.Row("fir");
        for (int i = 0; i < filtered.smoothed.Length; i++) {
            double direct = 0;
            for (int j = Math.Max(0, i - fir.Length + 1); j <= Math.Min(n - 1, i); j++)
                direct += y[j] * fir[i - j];
            firError = Math.Max(firError, Math.Abs(filtered.smoothed[i] - direct));
        }
        foreach (Peak peak in peaks) {
            Fft.Complex direct = new Fft.Complex(0, 0);
            for (int i = 0; i < m; i++)
                direct = direct.Add(Fft.Rotation(2 * Fft.PI * ((peak.bin * i) % m) / m).Scale(main.u[i]));
            spotError = Math.Max(spotError, direct.Subtract(main.transform[peak.bin]).Abs());
        }
        output.Add("[checks]");
        output.Add("inverse_roundtrip=" + Check(inverseError));
        output.Add("parseval=" + Check(parseval));
        output.Add("real_packing=" + Check(Math.Max(welch.error, frames.error)) +
                   " transforms=" + (2 * welch.segments + frames.magnitude.Length));
        output.Add("fir_fft_vs_direct=" + Check(firError));
        output.Add("dft_spot_check=" + Check(spotError) + " bins=" + peaks.Count);
        double ratio = harmonicAmplitude[1] / harmonicAmplitude[0];
        int harmonics = 0;
        for (int h = 2; h < 10; h++)
            if (Db20(harmonicAmplitude[h] / harmonicAmplitude[0]) >= -30)
                harmonics++;
        double? electricalLevel = null;
        foreach (Peak peak in peaks)
            if (peak.label.Equals("mains")) {
                electricalLevel = peak.level;
                break;
            }
        bool misalignment = ratio >= 0.5, looseness = harmonics >= 3, bearing = filtered.depth >= 0.2,
             electrical = electricalLevel != null && electricalLevel.Value >= -20,
             transientFinding = onsets.Count != 0;
        int findings = (misalignment ? 1 : 0) + (looseness ? 1 : 0) + (bearing ? 1 : 0) +
                       (electrical ? 1 : 0) + (transientFinding ? 1 : 0);
        output.Add("[diagnosis]");
        output.Add("misalignment=" + Yes(misalignment) + " ratio=" + F(ratio));
        output.Add("looseness=" + Yes(looseness) + " harmonics=" + harmonics);
        output.Add("bearing=" + Yes(bearing) + " depth=" + F(filtered.depth));
        output.Add("electrical=" + Yes(electrical) +
                   " level_db=" + (electricalLevel == null ? "none" : F(electricalLevel.Value)));
        output.Add("transient=" + Yes(transientFinding) + " onsets=" + onsets.Count);
        output.Add("status=" +
                   (findings == 0   ? "normal"
                    : findings == 1 ? "warning"
                                    : "alarm") +
                   " findings=" + findings);
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        SignalIo.Data data = SignalIo.Read();
        fs = data.fs;
        settings = data.settings;
        n = data.first.Length;
        m = settings.Integer("main_length");
        k = m / 2;
        l = settings.Integer("welch");
        frameLength = settings.Integer("spectrogram");
        hop = settings.Integer("spectrogram", 1);
        first = Preprocess(data.first);
        second = Preprocess(data.second);
        x = first.detrended;
        y = second.detrended;
        main = Spectral.Amplitude(x, m, settings.Word("main_window"), fs);
        a = main.amplitude;
        welch = Spectral.ComputeWelch(x, y, l, settings.Word("welch", 1), fs);
        frames = Spectral.ComputeFrames(x, frameLength, hop, settings.Word("spectrogram", 3), fs);
        Peaks();
        Harmonics();
        Spectrogram();
        Filters();
        Report.Write("spectrum.csv", SpectrumReport());
        Report.Write("peaks.txt", PeakReport());
        Report.Write("welch_psd.csv", WelchReport());
        Report.Write("spectrogram.txt", SpectrogramReport());
        Report.Write("filtered.csv", FilteredReport());
        Report.Write("report.txt", Report());
    }
}
