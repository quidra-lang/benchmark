using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Spectral {
    public record Spectrum(double[] u, Fft.Complex[] transform, double[] amplitude, Windows.Window window) {
    }
    public record Interpolation(double position, double value) {
    }
    public record Welch(double[] psd, double[] coherence, Fft.Complex[] transfer, int segments,
                        double error) {
    }
    public record Frames(double[][] magnitude, double maximum, double error) {
    }
    public static Spectrum Amplitude(double[] signal, int length, string window, int fs) {
        Windows.Window w = Windows.Create(window, length, fs);
        double[] u = new double[length];
        for (int n = 0; n < length; n++)
            u[n] = signal[n] * w.values[n];
        Fft.Complex[] x = Fft.Transform(Fft.Real(u, length), false);
        double[] a = new double[length / 2 + 1];
        for (int k = 0; k < a.Length; k++)
            a[k] = (k == 0 || 2 * k == length ? 1 : 2) * x[k].Abs() / w.s1;
        return new Spectrum(u, x, a, w);
    }
    public static double Median(double[] values) {
        double[] sorted = values.ToArray();
        Array.Sort(sorted);
        int n = sorted.Length;
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }
    public static bool Local(double[] values, int k) {
        return k > 0 && k + 1 < values.Length && values[k] > values[k - 1] && values[k] > values[k + 1];
    }
    public static Interpolation Interpolate(double[] values, int k, bool logarithmic) {
        if (!Local(values, k))
            return new Interpolation(k, values[k]);
        double alpha = values[k - 1], beta = values[k], gamma = values[k + 1];
        if (logarithmic) {
            alpha = Math.Log(alpha);
            beta = Math.Log(beta);
            gamma = Math.Log(gamma);
        }
        double delta = (alpha - gamma) / (2 * (alpha - 2 * beta + gamma)),
               value = beta - (alpha - gamma) * delta / 4;
        return new Interpolation(k + delta, logarithmic ? Math.Exp(value) : value);
    }
    public static double[] Segment(double[] signal, double[] window, int start) {
        double[] result = new double[window.Length];
        for (int n = 0; n < window.Length; n++)
            result[n] = signal[start + n] * window[n];
        return result;
    }
    public static double PackingError(double[] signal, Fft.Complex[] packed) {
        Fft.Complex[] full = Fft.Radix2(Fft.Real(signal, signal.Length), false);
        double error = 0;
        for (int k = 0; k < packed.Length; k++)
            error = Math.Max(error, packed[k].Subtract(full[k]).Abs());
        return error;
    }
    public static Welch ComputeWelch(double[] x, double[] y, int length, string window, int fs) {
        Windows.Window w = Windows.Create(window, length, fs);
        int count = (x.Length - length) / (length / 2) + 1, bins = length / 2 + 1;
        double[] xx = new double[bins], yy = new double[bins];
        Fft.Complex[] xy = Fft.Zeros(bins);
        double error = 0;
        for (int j = 0; j < count; j++) {
            double[] sx = Segment(x, w.values, j * length / 2), sy = Segment(y, w.values, j * length / 2);
            Fft.Complex[] fx = Fft.Packed(sx), fy = Fft.Packed(sy);
            error = Math.Max(error, PackingError(sx, fx));
            error = Math.Max(error, PackingError(sy, fy));
            for (int k = 0; k < bins; k++) {
                double ax = fx[k].Abs(), ay = fy[k].Abs();
                xx[k] += ax * ax;
                yy[k] += ay * ay;
                xy[k] = xy[k].Add(fx[k].Conjugate().Multiply(fy[k]));
            }
        }
        double[] psd = new double[bins], coherence = new double[bins];
        Fft.Complex[] transfer = new Fft.Complex[bins];
        for (int k = 0; k < bins; k++) {
            psd[k] = (k == 0 || k == length / 2 ? 1 : 2) * xx[k] / (count * fs * w.s2);
            double abs = xy[k].Abs();
            coherence[k] = abs * abs / (xx[k] * yy[k]);
            transfer[k] = xy[k].Divide(xx[k]);
        }
        return new Welch(psd, coherence, transfer, count, error);
    }
    public static Frames ComputeFrames(double[] signal, int length, int hop, string window, int fs) {
        double[] w = Windows.Create(window, length, fs).values;
        int count = (signal.Length - length) / hop + 1;
        double[][] magnitude = Enumerable.Range(0, count)
                                   .Select(
                                       _ => new double[length / 2 + 1])
                                   .ToArray();
        double maximum = 0, error = 0;
        for (int t = 0; t < count; t++) {
            double[] segment = Segment(signal, w, t * hop);
            Fft.Complex[] spectrum = Fft.Packed(segment);
            error = Math.Max(error, PackingError(segment, spectrum));
            for (int k = 0; k < spectrum.Length; k++) {
                magnitude[t][k] = spectrum[k].Abs();
                maximum = Math.Max(maximum, magnitude[t][k]);
            }
        }
        return new Frames(magnitude, maximum, error);
    }
}
