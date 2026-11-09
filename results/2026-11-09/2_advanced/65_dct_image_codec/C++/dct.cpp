#include "codec.hpp"
std::array<Key, 64> zigzag_order() {
    std::array<Key, 64> out{};
    int index = 0;
    for (int sum = 0; sum <= 14; ++sum) {
        if (sum % 2) {
            for (int u = 0; u < 8; ++u)
                if (sum - u >= 0 && sum - u < 8)
                    out[index++] = {u, sum - u};
        } else {
            for (int u = 7; u >= 0; --u)
                if (sum - u >= 0 && sum - u < 8)
                    out[index++] = {u, sum - u};
        }
    }
    return out;
}
static I rnd(I value, int shift) { return floor_div(value + (I(1) << (shift - 1)), I(1) << shift); }
Matrix forward(const Matrix &block, const Matrix &transform) {
    Matrix temporary{}, out{};
    for (int u = 0; u < 8; ++u)
        for (int x = 0; x < 8; ++x) {
            I sum = 0;
            for (int y = 0; y < 8; ++y)
                sum += transform[u][y] * (block[y][x] - 128);
            temporary[u][x] = rnd(sum, 11);
        }
    for (int u = 0; u < 8; ++u)
        for (int v = 0; v < 8; ++v) {
            I sum = 0;
            for (int x = 0; x < 8; ++x)
                sum += temporary[u][x] * transform[v][x];
            out[u][v] = rnd(sum, 15);
        }
    return out;
}
Matrix inverse_dct(const Matrix &coefficients, const Matrix &transform) {
    Matrix temporary{}, out{};
    for (int y = 0; y < 8; ++y)
        for (int v = 0; v < 8; ++v) {
            I sum = 0;
            for (int u = 0; u < 8; ++u)
                sum += transform[u][y] * coefficients[u][v];
            temporary[y][v] = rnd(sum, 11);
        }
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x) {
            I sum = 0;
            for (int v = 0; v < 8; ++v)
                sum += temporary[y][v] * transform[v][x];
            out[y][x] = clamp(rnd(sum, 15) + 128);
        }
    return out;
}
Quantization quantization_tables(const std::array<Matrix, 2> &basic, int quality) {
    I scale = quality < 50 ? 5000 / quality : 200 - 2 * quality;
    Quantization out;
    for (int t = 0; t < 2; ++t) {
        Matrix table{};
        for (int u = 0; u < 8; ++u)
            for (int v = 0; v < 8; ++v)
                table[u][v] = std::clamp((basic[t][u][v] * scale + 50) / 100, I(1), I(255));
        out[t] = table;
    }
    return out;
}
Matrix quantize(const Matrix &values, const Matrix &table) {
    Matrix out{};
    for (int u = 0; u < 8; ++u)
        for (int v = 0; v < 8; ++v) {
            I magnitude = (std::llabs(values[u][v]) + table[u][v] / 2) / table[u][v];
            out[u][v] = values[u][v] >= 0 ? magnitude : -magnitude;
        }
    return out;
}
Sequence zigzag(const Matrix &values) {
    Sequence out{};
    const auto order = zigzag_order();
    for (int k = 0; k < 64; ++k)
        out[k] = values[order[k].first][order[k].second];
    return out;
}
Matrix dequantize(const Sequence &sequence, const Matrix &table, int keep) {
    Matrix out{};
    const auto order = zigzag_order();
    for (int k = 0; k < keep; ++k) {
        int u = order[k].first, v = order[k].second;
        out[u][v] = sequence[k] * table[u][v];
    }
    return out;
}
