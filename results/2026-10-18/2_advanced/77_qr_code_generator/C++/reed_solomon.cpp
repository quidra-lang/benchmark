#include "qr.hpp"
ReedSolomon::ReedSolomon() {
    exp[0] = 1;
    for (int i = 1; i < 255; ++i) {
        int doubled = exp[i - 1] * 2;
        exp[i] = doubled >= 256 ? doubled ^ 285 : doubled;
    }
    for (int i = 0; i < 255; ++i)
        log[exp[i]] = i;
}
int ReedSolomon::multiply(int a, int b) const { return a && b ? exp[(log[a] + log[b]) % 255] : 0; }
int ReedSolomon::divide(int a, int b) const { return a ? exp[(log[a] - log[b] + 255) % 255] : 0; }
Words ReedSolomon::generator(int degree) const {
    Words coefficients{1};
    for (int exponent = 0; exponent < degree; ++exponent) {
        Words product(coefficients.size() + 1);
        for (int i = 0; i < int(coefficients.size()); ++i) {
            product[i] ^= coefficients[i];
            product[i + 1] ^= multiply(coefficients[i], exp[exponent]);
        }
        coefficients = std::move(product);
    }
    return coefficients;
}
Words ReedSolomon::parity(const Words &data, int degree) const {
    Words polynomial = generator(degree), remainder = data;
    remainder.resize(data.size() + degree);
    for (int i = 0; i < int(data.size()); ++i) {
        int leading = remainder[i];
        if (leading)
            for (int j = 0; j <= degree; ++j)
                remainder[i + j] ^= multiply(leading, polynomial[j]);
    }
    return Words(remainder.end() - degree, remainder.end());
}
Words ReedSolomon::syndromes(const Words &words, int degree) const {
    Words out;
    for (int j = 0; j < degree; ++j) {
        int value = 0;
        for (int word : words)
            value = multiply(value, exp[j]) ^ word;
        out.push_back(value);
    }
    return out;
}
int ReedSolomon::polynomial(const Words &coefficients, int argument) const {
    int value = 0;
    for (auto i = coefficients.rbegin(); i != coefficients.rend(); ++i)
        value = multiply(value, argument) ^ *i;
    return value;
}
Correction ReedSolomon::correct(const Words &received, int degree) const {
    Correction out;
    out.syndromes = syndromes(received, degree);
    out.corrected = received;
    if (std::all_of(out.syndromes.begin(), out.syndromes.end(), [](int v) { return v == 0; }))
        return out;
    Words locator(degree + 1), previous(degree + 1);
    locator[0] = previous[0] = 1;
    int length = 0, shift = 1, beta = 1;
    for (int q = 0; q < degree; ++q) {
        int delta = out.syndromes[q];
        for (int i = 1; i <= length; ++i)
            delta ^= multiply(locator[i], out.syndromes[q - i]);
        if (!delta) {
            ++shift;
            continue;
        }
        Words saved = locator;
        int multiplier = divide(delta, beta);
        for (int i = 0; i < degree + 1 - shift; ++i)
            locator[i + shift] ^= multiply(multiplier, previous[i]);
        if (2 * length <= q) {
            length = q + 1 - length;
            previous = std::move(saved);
            beta = delta;
            shift = 1;
        } else
            ++shift;
    }
    if (length > degree / 2) {
        out.success = false;
        return out;
    }
    locator.resize(length + 1);
    Words positions;
    int count = int(received.size());
    for (int i = 0; i < count; ++i)
        if (!polynomial(locator, exp[(255 - (count - 1 - i)) % 255]))
            positions.push_back(i);
    if (int(positions.size()) != length) {
        out.success = false;
        return out;
    }
    Words omega(degree), derivative(length);
    for (int i = 0; i < degree; ++i)
        for (int j = 0; j <= std::min(length, degree - 1 - i); ++j)
            omega[i + j] ^= multiply(out.syndromes[i], locator[j]);
    for (int i = 1; i <= length; i += 2)
        derivative[i - 1] = locator[i];
    for (int i : positions) {
        int location = exp[(count - 1 - i) % 255], inverse = exp[(255 - (count - 1 - i)) % 255],
            denominator = polynomial(derivative, inverse);
        if (!denominator) {
            out.success = false;
            return out;
        }
        out.corrected[i] ^= multiply(location, divide(polynomial(omega, inverse), denominator));
    }
    Words checked = syndromes(out.corrected, degree);
    if (std::any_of(checked.begin(), checked.end(), [](int v) { return v != 0; })) {
        out.success = false;
        return out;
    }
    for (int i : positions)
        if (out.corrected[i] != received[i])
            out.positions.push_back(i);
    return out;
}
