#include "qr.h"
static int bit_length(int value) {
    int count = 0;
    while (value) {
        value >>= 1;
        ++count;
    }
    return count;
}
static int remainder(int value, int divisor) {
    int degree = bit_length(divisor);
    while (bit_length(value) >= degree)
        value ^= divisor << (bit_length(value) - degree);
    return value;
}
int format_information(int level, int mask) {
    const int indicators[] = {1, 0, 3, 2};
    int shifted = (8 * indicators[level] + mask) << 10;
    return (shifted + remainder(shifted, 0x537)) ^ 0x5412;
}
int version_information(int version) {
    int shifted = version << 12;
    return shifted + remainder(shifted, 0x1f25);
}
static void position_add(Positions *positions, int x, int y) {
    positions->items[positions->count++] = (Point){x, y};
}
void format_positions(int n, Positions positions[2]) {
    positions[0].count = positions[1].count = 0;
    for (int i = 0; i < 6; ++i)
        position_add(&positions[0], 8, i);
    position_add(&positions[0], 8, 7);
    position_add(&positions[0], 8, 8);
    position_add(&positions[0], 7, 8);
    for (int i = 9; i < 15; ++i)
        position_add(&positions[0], 14 - i, 8);
    for (int i = 0; i < 8; ++i)
        position_add(&positions[1], n - 1 - i, 8);
    for (int i = 8; i < 15; ++i)
        position_add(&positions[1], 8, n - 15 + i);
}
void version_positions(int n, Positions positions[2]) {
    positions[0].count = positions[1].count = 0;
    for (int i = 0; i < 18; ++i) {
        position_add(&positions[0], n - 11 + i % 3, i / 3);
        position_add(&positions[1], i / 3, n - 11 + i % 3);
    }
}
void write_value(Matrix *symbol, const Positions *positions, int value) {
    for (int i = 0; i < positions->count; ++i) {
        Point p = positions->items[i];
        symbol->cells[p.y][p.x] = (unsigned char)((value >> i) & 1);
    }
}
int read_value(const Matrix *symbol, const Positions *positions) {
    int value = 0;
    for (int i = 0; i < positions->count; ++i) {
        Point p = positions->items[i];
        value |= symbol->cells[p.y][p.x] << i;
    }
    return value;
}
Positions reading_order(const Matrix *areas) {
    Positions out = {0};
    int columns[30], count = 0, n = areas->size;
    for (int right = n - 1; right >= 8; right -= 2)
        columns[count++] = right;
    columns[count++] = 5;
    columns[count++] = 3;
    columns[count++] = 1;
    for (int pair = 0; pair < count; ++pair)
        for (int row = 0; row < n; ++row) {
            int y = pair % 2 == 0 ? n - 1 - row : row;
            for (int offset = 0; offset < 2; ++offset) {
                int x = columns[pair] - offset;
                if (areas->cells[y][x] == AREA_DATA)
                    position_add(&out, x, y);
            }
        }
    return out;
}
static void set(Geometry *g, int x, int y, int value, int area) {
    g->symbol.cells[y][x] = (unsigned char)value;
    g->areas.cells[y][x] = (unsigned char)area;
}
static int maximum(int a, int b) { return a > b ? a : b; }
void function_matrix(Geometry *g, int version, const Words *alignments) {
    memset(g, 0, sizeof(*g));
    int n = 17 + 4 * version;
    g->symbol.size = g->areas.size = n;
    Point centers[] = {{3, 3}, {n - 4, 3}, {3, n - 4}};
    for (int c = 0; c < 3; ++c)
        for (int dy = -4; dy <= 4; ++dy)
            for (int dx = -4; dx <= 4; ++dx) {
                int x = centers[c].x + dx, y = centers[c].y + dy, d = maximum(abs(dx), abs(dy));
                if (x >= 0 && x < n && y >= 0 && y < n)
                    set(g, x, y, d == 0 || d == 1 || d == 3, AREA_FUNCTION);
            }
    for (int i = 8; i <= n - 9; ++i) {
        set(g, 6, i, i % 2 == 0, AREA_FUNCTION);
        set(g, i, 6, i % 2 == 0, AREA_FUNCTION);
    }
    if (alignments->count)
        for (int a = 0; a < alignments->count; ++a)
            for (int b = 0; b < alignments->count; ++b) {
                int cx = alignments->items[a], cy = alignments->items[b],
                    first = alignments->items[0], last = alignments->items[alignments->count - 1];
                if ((cx == first && (cy == first || cy == last)) || (cx == last && cy == first))
                    continue;
                for (int dy = -2; dy <= 2; ++dy)
                    for (int dx = -2; dx <= 2; ++dx)
                        set(g, cx + dx, cy + dy, maximum(abs(dx), abs(dy)) != 1, AREA_FUNCTION);
            }
    set(g, 8, n - 8, 1, AREA_FUNCTION);
    Positions positions[2];
    format_positions(n, positions);
    for (int set_index = 0; set_index < 2; ++set_index)
        for (int i = 0; i < positions[set_index].count; ++i) {
            Point p = positions[set_index].items[i];
            set(g, p.x, p.y, 0, AREA_FORMAT);
        }
    if (version >= 7) {
        version_positions(n, positions);
        for (int k = 0; k < 2; ++k) {
            for (int i = 0; i < positions[k].count; ++i) {
                Point p = positions[k].items[i];
                g->areas.cells[p.y][p.x] = AREA_VERSION;
            }
            write_value(&g->symbol, &positions[k], version_information(version));
        }
    }
    g->order = reading_order(&g->areas);
    for (int y = 0; y < 57; ++y)
        for (int x = 0; x < 57; ++x)
            g->indices[y][x] = -1;
    for (int i = 0; i < g->order.count; ++i) {
        Point p = g->order.items[i];
        g->indices[p.y][p.x] = i;
    }
}
