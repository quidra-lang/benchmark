#include "qr.h"
bool mask_condition(int mask, int x, int y) {
    switch (mask) {
    case 0:
        return (x + y) % 2 == 0;
    case 1:
        return y % 2 == 0;
    case 2:
        return x % 3 == 0;
    case 3:
        return (x + y) % 3 == 0;
    case 4:
        return (y / 2 + x / 3) % 2 == 0;
    case 5:
        return (x * y) % 2 + (x * y) % 3 == 0;
    case 6:
        return ((x * y) % 2 + (x * y) % 3) % 2 == 0;
    default:
        return ((x + y) % 2 + (x * y) % 3) % 2 == 0;
    }
}
Matrix apply_mask(Matrix symbol, const Positions *positions, int mask) {
    for (int i = 0; i < positions->count; ++i) {
        Point p = positions->items[i];
        if (mask_condition(mask, p.x, p.y))
            symbol.cells[p.y][p.x] ^= 1;
    }
    return symbol;
}
int penalty_total(Penalty p) { return p.n1 + p.n2 + p.n3 + p.n4; }
Penalty penalties(const Matrix *symbol) {
    Penalty out = {0};
    int n = symbol->size;
    for (int orientation = 0; orientation < 2; ++orientation)
        for (int fixed = 0; fixed < n; ++fixed) {
            int row[57];
            for (int i = 0; i < n; ++i)
                row[i] = orientation == 0 ? symbol->cells[fixed][i] : symbol->cells[i][fixed];
            int run = 1;
            for (int i = 1; i < n; ++i)
                if (row[i] == row[i - 1])
                    ++run;
                else {
                    if (run >= 5)
                        out.n1 += run - 2;
                    run = 1;
                }
            if (run >= 5)
                out.n1 += run - 2;
            for (int i = 0; i <= n - 11; ++i) {
                int pattern = 0;
                for (int j = 0; j < 11; ++j)
                    pattern = 2 * pattern + row[i + j];
                if (pattern == 0x5d0 || pattern == 0x05d)
                    out.n3 += 40;
            }
        }
    int dark = 0;
    for (int y = 0; y < n; ++y)
        for (int x = 0; x < n; ++x) {
            int value = symbol->cells[y][x];
            dark += value;
            if (x + 1 < n && y + 1 < n && value == symbol->cells[y][x + 1] &&
                value == symbol->cells[y + 1][x] && value == symbol->cells[y + 1][x + 1])
                out.n2 += 3;
        }
    out.n4 = 10 * (abs(20 * dark - 10 * n * n) / (n * n));
    return out;
}
