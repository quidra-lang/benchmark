import java.util.*;

final class Spectral {
    record Spectrum(double[] u, Fft.Complex[] transform, double[] amplitude, Windows.Window window) {}
    record Interpolation(double position, double value) {}
    record Welch(double[] psd, double[] coherence, Fft.Complex[] transfer, int segments, double error) {}
    record Frames(double[][] magnitude, double maximum, double error) {}
    static Spectrum amplitude(double[] signal, int length, String window, int fs) {
        Windows.Window w = Windows.create(window, length, fs);
        double[] u = new double[length];
        for (int n = 0; n < length; n++)
            u[n] = signal[n] * w.values()[n];
        Fft.Complex[] x = Fft.transform(Fft.real(u, length), false);
        double[] a = new double[length / 2 + 1];
        for (int k = 0; k < a.length; k++)
            a[k] = (k == 0 || 2 * k == length ? 1 : 2) * x[k].abs() / w.s1();
        return new Spectrum(u, x, a, w);
    }
    static double median(double[] values) {
        double[] sorted = values.clone();
        Arrays.sort(sorted);
        int n = sorted.length;
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }
    static boolean local(double[] values, int k) {
        return k > 0 && k + 1 < values.length && values[k] > values[k - 1] && values[k] > values[k + 1];
    }
    static Interpolation interpolate(double[] values, int k, boolean logarithmic) {
        if (!local(values, k))
            return new Interpolation(k, values[k]);
        double alpha = values[k - 1], beta = values[k], gamma = values[k + 1];
        if (logarithmic) {
            alpha = Math.log(alpha);
            beta = Math.log(beta);
            gamma = Math.log(gamma);
        }
        double delta = (alpha - gamma) / (2 * (alpha - 2 * beta + gamma)),
               value = beta - (alpha - gamma) * delta / 4;
        return new Interpolation(k + delta, logarithmic ? Math.exp(value) : value);
    }
    static double[] segment(double[] signal, double[] window, int start) {
        double[] result = new double[window.length];
        for (int n = 0; n < window.length; n++)
            result[n] = signal[start + n] * window[n];
        return result;
    }
    static double packingError(double[] signal, Fft.Complex[] packed) {
        Fft.Complex[] full = Fft.radix2(Fft.real(signal, signal.length), false);
        double error = 0;
        for (int k = 0; k < packed.length; k++)
            error = Math.max(error, packed[k].subtract(full[k]).abs());
        return error;
    }
    static Welch welch(double[] x, double[] y, int length, String window, int fs) {
        Windows.Window w = Windows.create(window, length, fs);
        int count = (x.length - length) / (length / 2) + 1, bins = length / 2 + 1;
        double[] xx = new double[bins], yy = new double[bins];
        Fft.Complex[] xy = Fft.zeros(bins);
        double error = 0;
        for (int j = 0; j < count; j++) {
            double[] sx = segment(x, w.values(), j * length / 2), sy = segment(y, w.values(), j * length / 2);
            Fft.Complex[] fx = Fft.packed(sx), fy = Fft.packed(sy);
            error = Math.max(error, packingError(sx, fx));
            error = Math.max(error, packingError(sy, fy));
            for (int k = 0; k < bins; k++) {
                double ax = fx[k].abs(), ay = fy[k].abs();
                xx[k] += ax * ax;
                yy[k] += ay * ay;
                xy[k] = xy[k].add(fx[k].conjugate().multiply(fy[k]));
            }
        }
        double[] psd = new double[bins], coherence = new double[bins];
        Fft.Complex[] transfer = new Fft.Complex[bins];
        for (int k = 0; k < bins; k++) {
            psd[k] = (k == 0 || k == length / 2 ? 1 : 2) * xx[k] / (count * fs * w.s2());
            double abs = xy[k].abs();
            coherence[k] = abs * abs / (xx[k] * yy[k]);
            transfer[k] = xy[k].divide(xx[k]);
        }
        return new Welch(psd, coherence, transfer, count, error);
    }
    static Frames frames(double[] signal, int length, int hop, String window, int fs) {
        double[] w = Windows.create(window, length, fs).values();
        int count = (signal.length - length) / hop + 1;
        double[][] magnitude = new double[count][length / 2 + 1];
        double maximum = 0, error = 0;
        for (int t = 0; t < count; t++) {
            double[] segment = segment(signal, w, t * hop);
            Fft.Complex[] spectrum = Fft.packed(segment);
            error = Math.max(error, packingError(segment, spectrum));
            for (int k = 0; k < spectrum.length; k++) {
                magnitude[t][k] = spectrum[k].abs();
                maximum = Math.max(maximum, magnitude[t][k]);
            }
        }
        return new Frames(magnitude, maximum, error);
    }
}
