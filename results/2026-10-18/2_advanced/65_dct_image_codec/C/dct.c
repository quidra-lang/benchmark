#include "codec.h"
void zigzag_order(Pair out[64]) {
    int index = 0;
    for (int sum = 0; sum <= 14; ++sum) {
        if (sum % 2) {
            for (int u = 0; u < 8; ++u)
                if (sum - u >= 0 && sum - u < 8)
                    out[index++] = (Pair){u, sum - u};
        } else {
            for (int u = 7; u >= 0; --u)
                if (sum - u >= 0 && sum - u < 8)
                    out[index++] = (Pair){u, sum - u};
        }
    }
}
static I rnd(I value, int shift) { return floor_div(value + ((I)1 << (shift - 1)), (I)1 << shift); }
Matrix forward(Matrix block, Matrix transform) {
    Matrix temporary = {0}, out = {0};
    for (int u = 0; u < 8; ++u)
        for (int x = 0; x < 8; ++x) {
            I sum = 0;
            for (int y = 0; y < 8; ++y)
                sum += transform.values[u][y] * (block.values[y][x] - 128);
            temporary.values[u][x] = rnd(sum, 11);
        }
    for (int u = 0; u < 8; ++u)
        for (int v = 0; v < 8; ++v) {
            I sum = 0;
            for (int x = 0; x < 8; ++x)
                sum += temporary.values[u][x] * transform.values[v][x];
            out.values[u][v] = rnd(sum, 15);
        }
    return out;
}
Matrix inverse_dct(Matrix coefficients, Matrix transform) {
    Matrix temporary = {0}, out = {0};
    for (int y = 0; y < 8; ++y)
        for (int v = 0; v < 8; ++v) {
            I sum = 0;
            for (int u = 0; u < 8; ++u)
                sum += transform.values[u][y] * coefficients.values[u][v];
            temporary.values[y][v] = rnd(sum, 11);
        }
    for (int y = 0; y < 8; ++y)
        for (int x = 0; x < 8; ++x) {
            I sum = 0;
            for (int v = 0; v < 8; ++v)
                sum += temporary.values[y][v] * transform.values[v][x];
            out.values[y][x] = clamp(rnd(sum, 15) + 128);
        }
    return out;
}
Quantization quantization_tables(const Matrix basic[2], int quality) {
    I scale = quality < 50 ? 5000 / quality : 200 - 2 * quality;
    Quantization out = {0};
    for (int t = 0; t < 2; ++t) {
        out.defined[t] = true;
        for (int u = 0; u < 8; ++u)
            for (int v = 0; v < 8; ++v) {
                I value = (basic[t].values[u][v] * scale + 50) / 100;
                out.values[t].values[u][v] = value < 1 ? 1 : value > 255 ? 255 : value;
            }
    }
    return out;
}
Matrix quantize(Matrix values, Matrix table) {
    Matrix out = {0};
    for (int u = 0; u < 8; ++u)
        for (int v = 0; v < 8; ++v) {
            I magnitude =
                (llabs(values.values[u][v]) + table.values[u][v] / 2) / table.values[u][v];
            out.values[u][v] = values.values[u][v] >= 0 ? magnitude : -magnitude;
        }
    return out;
}
Sequence zigzag(Matrix values) {
    Sequence out = {0};
    Pair order[64];
    zigzag_order(order);
    for (int k = 0; k < 64; ++k)
        out.values[k] = values.values[order[k].first][order[k].second];
    return out;
}
Matrix dequantize(Sequence sequence, Matrix table, int keep) {
    Matrix out = {0};
    Pair order[64];
    zigzag_order(order);
    for (int k = 0; k < keep; ++k) {
        int u = order[k].first, v = order[k].second;
        out.values[u][v] = sequence.values[k] * table.values[u][v];
    }
    return out;
}
