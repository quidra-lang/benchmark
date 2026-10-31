#include "analyzer.hpp"
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
    return {std::cos(angle), -std::sin(angle)};
}
Complexes radix2(Complexes values, bool inverse) {
    const int count = values.size();
    int bits = 0;
    for (int value = count; value > 1; value /= 2)
        ++bits;
    for (int n = 1; n < count; ++n) {
        int reversed = 0, value = n;
        for (int bit = 0; bit < bits; ++bit) {
            reversed = 2 * reversed + value % 2;
            value /= 2;
        }
        if (n < reversed)
            std::swap(values[n], values[reversed]);
    }
    Complexes twiddle(count / 2);
    for (int k = 0; k < count / 2; ++k) {
        twiddle[k] = rot(2 * pi * k / count);
        if (inverse)
            twiddle[k] = std::conj(twiddle[k]);
    }
    for (int size = 2; size <= count; size *= 2) {
        const int half = size / 2, stride = count / size;
        for (int start = 0; start < count; start += size)
            for (int j = 0; j < half; ++j) {
                const Complex t = twiddle[j * stride] * values[start + j + half], u = values[start + j];
                values[start + j] = u + t;
                values[start + j + half] = u - t;
            }
    }
    if (inverse)
        for (Complex &value : values)
            value /= count;
    return values;
}
static Complexes bluestein(const Complexes &values) {
    const int m = values.size(), q = pow2(2 * m - 1);
    Complexes chirp(m), a(q), b(q);
    for (int n = 0; n < m; ++n) {
        chirp[n] = rot(pi * ((n * n) % (2 * m)) / m);
        a[n] = values[n] * chirp[n];
        b[n] = std::conj(chirp[n]);
        if (n)
            b[q - n] = b[n];
    }
    a = radix2(std::move(a));
    b = radix2(std::move(b));
    for (int k = 0; k < q; ++k)
        a[k] *= b[k];
    a = radix2(std::move(a), true);
    Complexes out(m);
    for (int k = 0; k < m; ++k)
        out[k] = chirp[k] * a[k];
    return out;
}
Complexes dft(const Complexes &values) {
    return power_of_two(values.size()) ? radix2(values) : bluestein(values);
}
Complexes idft(const Complexes &values) {
    if (power_of_two(values.size()))
        return radix2(values, true);
    Complexes conjugates = values;
    for (Complex &value : conjugates)
        value = std::conj(value);
    Complexes out = bluestein(conjugates);
    for (Complex &value : out)
        value = std::conj(value) / double(values.size());
    return out;
}
Complexes packed_real(const Values &values) {
    const int q = values.size(), half = q / 2;
    Complexes z(half);
    for (int j = 0; j < half; ++j)
        z[j] = {values[2 * j], values[2 * j + 1]};
    z = radix2(std::move(z));
    Complexes out(half + 1);
    for (int k = 0; k <= half; ++k) {
        const Complex a = z[k % half], b = std::conj(z[(half - k) % half]), even = (a + b) / 2.0,
                      odd = (a - b) / Complex(0, 2);
        out[k] = even + rot(2 * pi * k / q) * odd;
    }
    return out;
}
Values convolution(const Values &a, const Values &b) {
    const int length = a.size() + b.size() - 1, q = pow2(length);
    Complexes af(q), bf(q);
    for (int i = 0; i < int(a.size()); ++i)
        af[i] = a[i];
    for (int i = 0; i < int(b.size()); ++i)
        bf[i] = b[i];
    af = radix2(std::move(af));
    bf = radix2(std::move(bf));
    for (int i = 0; i < q; ++i)
        af[i] *= bf[i];
    af = radix2(std::move(af), true);
    Values out(length);
    for (int i = 0; i < length; ++i)
        out[i] = af[i].real();
    return out;
}
Complexes chirp_z(const Values &windowed, int fs, int low, int high, int points) {
    const int m = windowed.size(), q = pow2(m + points - 1);
    const double step = double(high - low) / (points - 1);
    Complexes a(q), b(q);
    for (int n = 0; n < m; ++n)
        a[n] = windowed[n] * rot(2 * pi * low * n / fs) * rot(pi * step * n * n / fs);
    for (int offset = -(m - 1); offset < points; ++offset)
        b[offset < 0 ? offset + q : offset] = std::conj(rot(pi * step * offset * offset / fs));
    a = radix2(std::move(a));
    b = radix2(std::move(b));
    for (int i = 0; i < q; ++i)
        a[i] *= b[i];
    a = radix2(std::move(a), true);
    Complexes out(points);
    for (int j = 0; j < points; ++j)
        out[j] = rot(pi * step * j * j / fs) * a[j];
    return out;
}
