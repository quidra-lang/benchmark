#include "analyzer.h"
static const double pi = 3.141592653589793;
int pow2(int value) {
    int out = 1;
    while (out < value)
        out *= 2;
    return out;
}
bool power_of_two(int value) {
    return (value & (value - 1)) == 0;
}
Complex rot(double angle) {
    return cos(angle) - I * sin(angle);
}
double norm(Complex value) {
    return creal(value) * creal(value) + cimag(value) * cimag(value);
}
Complexes radix2(Complexes source, bool inverse) {
    int count = source.count;
    Complexes values = complex_new(count);
    memcpy(values.data, source.data, count * sizeof(Complex));
    int bits = 0;
    for (int value = count; value > 1; value /= 2)
        ++bits;
    for (int n = 1; n < count; ++n) {
        int reversed = 0, value = n;
        for (int bit = 0; bit < bits; ++bit) {
            reversed = 2 * reversed + value % 2;
            value /= 2;
        }
        if (n < reversed) {
            Complex swap = values.data[n];
            values.data[n] = values.data[reversed];
            values.data[reversed] = swap;
        }
    }
    Complex *twiddle = allocate(count / 2, sizeof(Complex));
    for (int k = 0; k < count / 2; ++k) {
        twiddle[k] = rot(2 * pi * k / count);
        if (inverse)
            twiddle[k] = conj(twiddle[k]);
    }
    for (int size = 2; size <= count; size *= 2) {
        int half = size / 2, stride = count / size;
        for (int start = 0; start < count; start += size)
            for (int j = 0; j < half; ++j) {
                Complex t = twiddle[j * stride] * values.data[start + j + half], u = values.data[start + j];
                values.data[start + j] = u + t;
                values.data[start + j + half] = u - t;
            }
    }
    if (inverse)
        for (int i = 0; i < count; ++i)
            values.data[i] /= count;
    release_one(twiddle);
    return values;
}
static Complexes bluestein(Complexes values) {
    int m = values.count, q = pow2(2 * m - 1);
    Complexes chirp = complex_new(m), a = complex_new(q), b = complex_new(q);
    for (int n = 0; n < m; ++n) {
        chirp.data[n] = rot(pi * ((n * n) % (2 * m)) / m);
        a.data[n] = values.data[n] * chirp.data[n];
        b.data[n] = conj(chirp.data[n]);
        if (n)
            b.data[q - n] = b.data[n];
    }
    Complexes af = radix2(a, false), bf = radix2(b, false);
    release_one(a.data);
    release_one(b.data);
    for (int k = 0; k < q; ++k)
        af.data[k] *= bf.data[k];
    Complexes g = radix2(af, true);
    release_one(af.data);
    release_one(bf.data);
    Complexes out = complex_new(m);
    for (int k = 0; k < m; ++k)
        out.data[k] = chirp.data[k] * g.data[k];
    release_one(chirp.data);
    release_one(g.data);
    return out;
}
Complexes dft(Complexes values) {
    return power_of_two(values.count) ? radix2(values, false) : bluestein(values);
}
Complexes idft(Complexes values) {
    if (power_of_two(values.count))
        return radix2(values, true);
    Complexes conjugates = complex_new(values.count);
    for (int i = 0; i < values.count; ++i)
        conjugates.data[i] = conj(values.data[i]);
    Complexes out = bluestein(conjugates);
    release_one(conjugates.data);
    for (int i = 0; i < out.count; ++i)
        out.data[i] = conj(out.data[i]) / values.count;
    return out;
}
Complexes packed_real(Values values) {
    int q = values.count, half = q / 2;
    Complexes z = complex_new(half);
    for (int j = 0; j < half; ++j)
        z.data[j] = values.data[2 * j] + I * values.data[2 * j + 1];
    Complexes transformed = radix2(z, false);
    release_one(z.data);
    Complexes out = complex_new(half + 1);
    for (int k = 0; k <= half; ++k) {
        Complex a = transformed.data[k % half], b = conj(transformed.data[(half - k) % half]),
                even = (a + b) / 2, odd = (a - b) / (2 * I);
        out.data[k] = even + rot(2 * pi * k / q) * odd;
    }
    release_one(transformed.data);
    return out;
}
Values convolution(Values a, Values b) {
    int length = a.count + b.count - 1, q = pow2(length);
    Complexes ac = complex_values(a, q), bc = complex_values(b, q), af = radix2(ac, false),
              bf = radix2(bc, false);
    release_one(ac.data);
    release_one(bc.data);
    for (int k = 0; k < q; ++k)
        af.data[k] *= bf.data[k];
    Complexes result = radix2(af, true);
    release_one(af.data);
    release_one(bf.data);
    Values out = values_new(length);
    for (int i = 0; i < length; ++i)
        out.data[i] = creal(result.data[i]);
    release_one(result.data);
    return out;
}
Complexes chirp_z(Values windowed, int fs, int low, int high, int points) {
    int m = windowed.count, q = pow2(m + points - 1);
    double step = (double)(high - low) / (points - 1);
    Complexes a = complex_new(q), b = complex_new(q);
    for (int n = 0; n < m; ++n)
        a.data[n] = windowed.data[n] * rot(2 * pi * low * n / fs) * rot(pi * step * n * n / fs);
    for (int offset = -(m - 1); offset < points; ++offset)
        b.data[offset < 0 ? offset + q : offset] = conj(rot(pi * step * offset * offset / fs));
    Complexes af = radix2(a, false), bf = radix2(b, false);
    release_one(a.data);
    release_one(b.data);
    for (int k = 0; k < q; ++k)
        af.data[k] *= bf.data[k];
    Complexes g = radix2(af, true);
    release_one(af.data);
    release_one(bf.data);
    Complexes out = complex_new(points);
    for (int j = 0; j < points; ++j)
        out.data[j] = rot(pi * step * j * j / fs) * g.data[j];
    release_one(g.data);
    return out;
}
