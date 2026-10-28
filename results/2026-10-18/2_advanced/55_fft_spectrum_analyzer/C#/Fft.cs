using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Fft {
    public static readonly double PI = 3.141592653589793;
    public readonly record struct Complex(double re, double im) {
        public Complex Add(Complex z) {
            return new Complex(re + z.re, im + z.im);
        }
        public Complex Subtract(Complex z) {
            return new Complex(re - z.re, im - z.im);
        }
        public Complex Multiply(Complex z) {
            return new Complex(re * z.re - im * z.im, re * z.im + im * z.re);
        }
        public Complex Scale(double x) {
            return new Complex(re * x, im * x);
        }
        public Complex Divide(double x) {
            return new Complex(re / x, im / x);
        }
        public Complex Conjugate() {
            return new Complex(re, -im);
        }
        public double Abs() {
            return Math.Sqrt(re * re + im * im);
        }
        public double Argument() {
            return Math.Atan2(im, re);
        }
    }
    public static Complex Rotation(double angle) {
        return new Complex(Math.Cos(angle), -Math.Sin(angle));
    }
    public static int Pow2(int n) {
        int q = 1;
        while (q < n)
            q *= 2;
        return q;
    }
    public static bool PowerOfTwo(int n) {
        return (n & (n - 1)) == 0;
    }
    public static Complex[] Zeros(int length) {
        Complex[] result = new Complex[length];
        Array.Fill(result, new Complex(0, 0));
        return result;
    }
    public static Complex[] Real(double[] values, int length) {
        Complex[] result = Zeros(length);
        for (int i = 0; i < values.Length; i++)
            result[i] = new Complex(values[i], 0);
        return result;
    }
    public static Complex[] Radix2(Complex[] input, bool inverse) {
        int q = input.Length;
        Complex[] a = input.ToArray();
        int bits = 0;
        for (int n = q; n > 1; n /= 2)
            bits++;
        for (int n = 1; n < q; n++) {
            int r = 0, value = n;
            for (int b = 0; b < bits; b++) {
                r = 2 * r + (value & 1);
                value >>= 1;
            }
            if (n < r) {
                Complex swap = a[n];
                a[n] = a[r];
                a[r] = swap;
            }
        }
        Complex[] w = new Complex[q / 2];
        for (int k = 0; k < w.Length; k++) {
            w[k] = Rotation(2 * PI * k / q);
            if (inverse)
                w[k] = w[k].Conjugate();
        }
        for (int s = 2; s <= q; s *= 2)
            for (int b = 0; b < q; b += s)
                for (int j = 0; j < s / 2; j++) {
                    Complex t = w[j * (q / s)].Multiply(a[b + j + s / 2]), u = a[b + j];
                    a[b + j] = u.Add(t);
                    a[b + j + s / 2] = u.Subtract(t);
                }
        if (inverse)
            for (int n = 0; n < q; n++)
                a[n] = a[n].Divide(q);
        return a;
    }
    public static Complex[] Bluestein(Complex[] v) {
        int m = v.Length, q = Pow2(2 * m - 1);
        Complex[] w = new Complex[m], a = Zeros(q), b = Zeros(q);
        for (int n = 0; n < m; n++) {
            w[n] = Rotation(PI * ((n * n) % (2 * m)) / m);
            a[n] = v[n].Multiply(w[n]);
            if (n == 0)
                b[0] = w[0].Conjugate();
            else {
                b[n] = w[n].Conjugate();
                b[q - n] = w[n].Conjugate();
            }
        }
        Complex[] g = Convolution(a, b);
        Complex[] result = new Complex[m];
        for (int k = 0; k < m; k++)
            result[k] = w[k].Multiply(g[k]);
        return result;
    }
    public static Complex[] Transform(Complex[] input, bool inverse) {
        if (PowerOfTwo(input.Length))
            return Radix2(input, inverse);
        if (!inverse)
            return Bluestein(input);
        Complex[] conjugates = new Complex[input.Length];
        for (int i = 0; i < input.Length; i++)
            conjugates[i] = input[i].Conjugate();
        Complex[] output = Bluestein(conjugates);
        for (int i = 0; i < output.Length; i++)
            output[i] = output[i].Conjugate().Divide(output.Length);
        return output;
    }
    public static Complex[] Packed(double[] values) {
        int q = values.Length, h = q / 2;
        Complex[] z = new Complex[h];
        for (int j = 0; j < h; j++)
            z[j] = new Complex(values[2 * j], values[2 * j + 1]);
        Complex[] spectrum = Radix2(z, false), result = new Complex[h + 1];
        for (int k = 0; k <= h; k++) {
            Complex a = spectrum[k % h], b = spectrum[(h - k) % h].Conjugate(), even = a.Add(b).Divide(2),
                    difference = a.Subtract(b), odd = new Complex(difference.im / 2, -difference.re / 2);
            result[k] = even.Add(Rotation(2 * PI * k / q).Multiply(odd));
        }
        return result;
    }
    public static Complex[] Convolution(Complex[] a, Complex[] b) {
        Complex[] fa = Radix2(a, false), fb = Radix2(b, false);
        for (int k = 0; k < fa.Length; k++)
            fa[k] = fa[k].Multiply(fb[k]);
        return Radix2(fa, true);
    }
    public static double[] Convolve(double[] a, double[] b) {
        int length = a.Length + b.Length - 1, q = Pow2(length);
        Complex[] result = Convolution(Real(a, q), Real(b, q));
        double[] output = new double[length];
        for (int n = 0; n < length; n++)
            output[n] = result[n].re;
        return output;
    }
    public static Complex[] ChirpZ(double[] u, double z1, double dz, int points, int fs) {
        int m = u.Length, q = Pow2(m + points - 1);
        Complex[] a = Zeros(q), b = Zeros(q);
        for (int n = 0; n < m; n++)
            a[n] = new Complex(u[n], 0)
                       .Multiply(Rotation(2 * PI * z1 * n / fs))
                       .Multiply(Rotation(PI * dz * n * n / fs));
        for (int n = -(m - 1); n < points; n++)
            b[n < 0 ? n + q : n] = Rotation(PI * dz * n * n / fs).Conjugate();
        Complex[] g = Convolution(a, b), result = new Complex[points];
        for (int j = 0; j < points; j++)
            result[j] = Rotation(PI * dz * j * j / fs).Multiply(g[j]);
        return result;
    }
}
