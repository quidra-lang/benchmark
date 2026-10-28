import java.util.*;

final class Fft {
    static final double PI = 3.141592653589793;
    record Complex(double re, double im) {
        Complex add(Complex z) {
            return new Complex(re + z.re, im + z.im);
        }
        Complex subtract(Complex z) {
            return new Complex(re - z.re, im - z.im);
        }
        Complex multiply(Complex z) {
            return new Complex(re * z.re - im * z.im, re * z.im + im * z.re);
        }
        Complex scale(double x) {
            return new Complex(re * x, im * x);
        }
        Complex divide(double x) {
            return new Complex(re / x, im / x);
        }
        Complex conjugate() {
            return new Complex(re, -im);
        }
        double abs() {
            return Math.sqrt(re * re + im * im);
        }
        double argument() {
            return Math.atan2(im, re);
        }
    }
    static Complex rotation(double angle) {
        return new Complex(Math.cos(angle), -Math.sin(angle));
    }
    static int pow2(int n) {
        int q = 1;
        while (q < n)
            q *= 2;
        return q;
    }
    static boolean powerOfTwo(int n) {
        return (n & (n - 1)) == 0;
    }
    static Complex[] zeros(int length) {
        Complex[] result = new Complex[length];
        Arrays.fill(result, new Complex(0, 0));
        return result;
    }
    static Complex[] real(double[] values, int length) {
        Complex[] result = zeros(length);
        for (int i = 0; i < values.length; i++)
            result[i] = new Complex(values[i], 0);
        return result;
    }
    static Complex[] radix2(Complex[] input, boolean inverse) {
        int q = input.length;
        Complex[] a = input.clone();
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
        for (int k = 0; k < w.length; k++) {
            w[k] = rotation(2 * PI * k / q);
            if (inverse)
                w[k] = w[k].conjugate();
        }
        for (int s = 2; s <= q; s *= 2)
            for (int b = 0; b < q; b += s)
                for (int j = 0; j < s / 2; j++) {
                    Complex t = w[j * (q / s)].multiply(a[b + j + s / 2]), u = a[b + j];
                    a[b + j] = u.add(t);
                    a[b + j + s / 2] = u.subtract(t);
                }
        if (inverse)
            for (int n = 0; n < q; n++)
                a[n] = a[n].divide(q);
        return a;
    }
    static Complex[] bluestein(Complex[] v) {
        int m = v.length, q = pow2(2 * m - 1);
        Complex[] w = new Complex[m], a = zeros(q), b = zeros(q);
        for (int n = 0; n < m; n++) {
            w[n] = rotation(PI * ((n * n) % (2 * m)) / m);
            a[n] = v[n].multiply(w[n]);
            if (n == 0)
                b[0] = w[0].conjugate();
            else {
                b[n] = w[n].conjugate();
                b[q - n] = w[n].conjugate();
            }
        }
        Complex[] g = convolution(a, b);
        Complex[] result = new Complex[m];
        for (int k = 0; k < m; k++)
            result[k] = w[k].multiply(g[k]);
        return result;
    }
    static Complex[] transform(Complex[] input, boolean inverse) {
        if (powerOfTwo(input.length))
            return radix2(input, inverse);
        if (!inverse)
            return bluestein(input);
        Complex[] conjugates = new Complex[input.length];
        for (int i = 0; i < input.length; i++)
            conjugates[i] = input[i].conjugate();
        Complex[] output = bluestein(conjugates);
        for (int i = 0; i < output.length; i++)
            output[i] = output[i].conjugate().divide(output.length);
        return output;
    }
    static Complex[] packed(double[] values) {
        int q = values.length, h = q / 2;
        Complex[] z = new Complex[h];
        for (int j = 0; j < h; j++)
            z[j] = new Complex(values[2 * j], values[2 * j + 1]);
        Complex[] spectrum = radix2(z, false), result = new Complex[h + 1];
        for (int k = 0; k <= h; k++) {
            Complex a = spectrum[k % h], b = spectrum[(h - k) % h].conjugate(), even = a.add(b).divide(2),
                    difference = a.subtract(b), odd = new Complex(difference.im() / 2, -difference.re() / 2);
            result[k] = even.add(rotation(2 * PI * k / q).multiply(odd));
        }
        return result;
    }
    static Complex[] convolution(Complex[] a, Complex[] b) {
        Complex[] fa = radix2(a, false), fb = radix2(b, false);
        for (int k = 0; k < fa.length; k++)
            fa[k] = fa[k].multiply(fb[k]);
        return radix2(fa, true);
    }
    static double[] convolve(double[] a, double[] b) {
        int length = a.length + b.length - 1, q = pow2(length);
        Complex[] result = convolution(real(a, q), real(b, q));
        double[] output = new double[length];
        for (int n = 0; n < length; n++)
            output[n] = result[n].re();
        return output;
    }
    static Complex[] chirpZ(double[] u, double z1, double dz, int points, int fs) {
        int m = u.length, q = pow2(m + points - 1);
        Complex[] a = zeros(q), b = zeros(q);
        for (int n = 0; n < m; n++)
            a[n] = new Complex(u[n], 0)
                       .multiply(rotation(2 * PI * z1 * n / fs))
                       .multiply(rotation(PI * dz * n * n / fs));
        for (int n = -(m - 1); n < points; n++)
            b[n < 0 ? n + q : n] = rotation(PI * dz * n * n / fs).conjugate();
        Complex[] g = convolution(a, b), result = new Complex[points];
        for (int j = 0; j < points; j++)
            result[j] = rotation(PI * dz * j * j / fs).multiply(g[j]);
        return result;
    }
}
