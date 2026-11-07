#include "qr.h"
void init_reed_solomon(ReedSolomon *rs) {
    rs->exp[0] = 1;
    for (int i = 1; i < 255; ++i) {
        int doubled = 2 * rs->exp[i - 1];
        rs->exp[i] = doubled >= 256 ? doubled ^ 285 : doubled;
    }
    for (int i = 0; i < 255; ++i)
        rs->log[rs->exp[i]] = i;
}
int gf_multiply(const ReedSolomon *rs, int a, int b) {
    return a && b ? rs->exp[(rs->log[a] + rs->log[b]) % 255] : 0;
}
int gf_divide(const ReedSolomon *rs, int a, int b) {
    return a ? rs->exp[(rs->log[a] - rs->log[b] + 255) % 255] : 0;
}
static Words generator(const ReedSolomon *rs, int degree) {
    Words coefficients = {.items = {1}, .count = 1};
    for (int exponent = 0; exponent < degree; ++exponent) {
        Words product = {.count = coefficients.count + 1};
        for (int i = 0; i < coefficients.count; ++i) {
            product.items[i] ^= coefficients.items[i];
            product.items[i + 1] ^= gf_multiply(rs, coefficients.items[i], rs->exp[exponent]);
        }
        coefficients = product;
    }
    return coefficients;
}
Words parity(const ReedSolomon *rs, const Words *data, int degree) {
    Words polynomial = generator(rs, degree), remainder = *data;
    for (int i = 0; i < degree; ++i)
        word_add(&remainder, 0);
    for (int i = 0; i < data->count; ++i) {
        int leading = remainder.items[i];
        if (leading)
            for (int j = 0; j <= degree; ++j)
                remainder.items[i + j] ^= gf_multiply(rs, leading, polynomial.items[j]);
    }
    Words out = {0};
    for (int i = data->count; i < remainder.count; ++i)
        word_add(&out, remainder.items[i]);
    return out;
}
Words syndromes(const ReedSolomon *rs, const Words *words, int degree) {
    Words out = {0};
    for (int j = 0; j < degree; ++j) {
        int value = 0;
        for (int i = 0; i < words->count; ++i)
            value = gf_multiply(rs, value, rs->exp[j]) ^ words->items[i];
        word_add(&out, value);
    }
    return out;
}
static int polynomial(const ReedSolomon *rs, const Words *coefficients, int argument) {
    int value = 0;
    for (int i = coefficients->count - 1; i >= 0; --i)
        value = gf_multiply(rs, value, argument) ^ coefficients->items[i];
    return value;
}
static bool all_zero(const Words *words) {
    for (int i = 0; i < words->count; ++i)
        if (words->items[i])
            return false;
    return true;
}
Correction correct(const ReedSolomon *rs, const Words *received, int degree) {
    Correction out = {
        .syndromes = syndromes(rs, received, degree), .corrected = *received, .success = true};
    if (all_zero(&out.syndromes))
        return out;
    Words locator = {.items = {1}, .count = degree + 1}, previous = locator;
    int length = 0, shift = 1, beta = 1;
    for (int q = 0; q < degree; ++q) {
        int delta = out.syndromes.items[q];
        for (int i = 1; i <= length; ++i)
            delta ^= gf_multiply(rs, locator.items[i], out.syndromes.items[q - i]);
        if (!delta) {
            ++shift;
            continue;
        }
        Words saved = locator;
        int multiplier = gf_divide(rs, delta, beta);
        for (int i = 0; i < degree + 1 - shift; ++i)
            locator.items[i + shift] ^= gf_multiply(rs, multiplier, previous.items[i]);
        if (2 * length <= q) {
            length = q + 1 - length;
            previous = saved;
            beta = delta;
            shift = 1;
        } else
            ++shift;
    }
    if (length > degree / 2) {
        out.success = false;
        return out;
    }
    locator.count = length + 1;
    Words positions = {0};
    int count = received->count;
    for (int i = 0; i < count; ++i)
        if (!polynomial(rs, &locator, rs->exp[(255 - (count - 1 - i)) % 255]))
            word_add(&positions, i);
    if (positions.count != length) {
        out.success = false;
        return out;
    }
    Words omega = {.count = degree}, derivative = {.count = length};
    for (int i = 0; i < degree; ++i)
        for (int j = 0; j <= length && i + j < degree; ++j)
            omega.items[i + j] ^= gf_multiply(rs, out.syndromes.items[i], locator.items[j]);
    for (int i = 1; i <= length; i += 2)
        derivative.items[i - 1] = locator.items[i];
    for (int p = 0; p < positions.count; ++p) {
        int i = positions.items[p], location = rs->exp[(count - 1 - i) % 255],
            inverse = rs->exp[(255 - (count - 1 - i)) % 255],
            denominator = polynomial(rs, &derivative, inverse);
        if (!denominator) {
            out.success = false;
            return out;
        }
        out.corrected.items[i] ^=
            gf_multiply(rs, location, gf_divide(rs, polynomial(rs, &omega, inverse), denominator));
    }
    Words checked = syndromes(rs, &out.corrected, degree);
    if (!all_zero(&checked)) {
        out.success = false;
        return out;
    }
    for (int p = 0; p < positions.count; ++p) {
        int i = positions.items[p];
        if (out.corrected.items[i] != received->items[i])
            word_add(&out.positions, i);
    }
    return out;
}
