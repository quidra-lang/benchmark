using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Windows {
    public static readonly string[] NAMES = { "rectangular", "hann", "hamming", "blackman", "flattop" };
    public record Window(double[] values, double s1, double s2, double gain, double bins, double hz,
                         double scalloping) {
    }
    public static double[] Coefficients(string name) {
        return name switch {
            "rectangular" => new double[] { 1 }, "hann" => new double[] { 0.5, 0.5 },
            "hamming" => new double[] { 0.54, 0.46 }, "blackman" => new double[] { 0.42, 0.5, 0.08 },
            _ => new double[] { 0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368 }
        };
    }
    public static Window Create(string name, int length, int fs) {
        double[] coefficients = Coefficients(name), values = new double[length];
        double s1 = 0, s2 = 0;
        Fft.Complex sum = new Fft.Complex(0, 0);
        for (int n = 0; n < length; n++) {
            double value = 0;
            for (int j = 0; j < coefficients.Length; j++)
                value += (j % 2 == 0 ? 1 : -1) * coefficients[j] * Math.Cos(2 * Fft.PI * j * n / length);
            values[n] = value;
            s1 += value;
            s2 += value * value;
            sum = sum.Add(Fft.Rotation(Fft.PI * n / length).Scale(value));
        }
        double bins = length * s2 / (s1 * s1);
        return new Window(values, s1, s2, s1 / length, bins, bins * fs / length,
                          -20 * Math.Log10(sum.Abs() / s1));
    }
}
