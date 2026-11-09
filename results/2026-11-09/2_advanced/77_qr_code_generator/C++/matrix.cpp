#include "qr.hpp"
static int bit_length(int value) {
    int length = 0;
    while (value) {
        value >>= 1;
        ++length;
    }
    return length;
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
std::array<Positions, 2> format_positions(int n) {
    std::array<Positions, 2> out;
    for (int i = 0; i < 6; ++i)
        out[0].push_back({8, i});
    out[0].push_back({8, 7});
    out[0].push_back({8, 8});
    out[0].push_back({7, 8});
    for (int i = 9; i < 15; ++i)
        out[0].push_back({14 - i, 8});
    for (int i = 0; i < 8; ++i)
        out[1].push_back({n - 1 - i, 8});
    for (int i = 8; i < 15; ++i)
        out[1].push_back({8, n - 15 + i});
    return out;
}
std::array<Positions, 2> version_positions(int n) {
    std::array<Positions, 2> out;
    for (int i = 0; i < 18; ++i) {
        out[0].push_back({n - 11 + i % 3, i / 3});
        out[1].push_back({i / 3, n - 11 + i % 3});
    }
    return out;
}
void write_value(Matrix &symbol, const Positions &positions, int value) {
    for (int i = 0; i < int(positions.size()); ++i)
        symbol.cells[positions[i].y][positions[i].x] = (value >> i) & 1;
}
int read_value(const Matrix &symbol, const Positions &positions) {
    int out = 0;
    for (int i = 0; i < int(positions.size()); ++i)
        out |= symbol.cells[positions[i].y][positions[i].x] << i;
    return out;
}
Positions reading_order(const Matrix &areas) {
    Positions out;
    Words columns;
    int n = areas.size;
    for (int right = n - 1; right >= 8; right -= 2)
        columns.push_back(right);
    columns.insert(columns.end(), {5, 3, 1});
    for (int pair = 0; pair < int(columns.size()); ++pair)
        for (int row = 0; row < n; ++row) {
            int y = pair % 2 == 0 ? n - 1 - row : row;
            for (int x : {columns[pair], columns[pair] - 1})
                if (areas.cells[y][x] == Data)
                    out.push_back({x, y});
        }
    return out;
}
Geometry function_matrix(int version, const Words &alignments) {
    Geometry out;
    int n = 17 + 4 * version;
    out.symbol.size = out.areas.size = n;
    auto set = [&](int x, int y, int value, int area) {
        out.symbol.cells[y][x] = value;
        out.areas.cells[y][x] = area;
    };
    for (Point center : Positions{{3, 3}, {n - 4, 3}, {3, n - 4}})
        for (int dy = -4; dy <= 4; ++dy)
            for (int dx = -4; dx <= 4; ++dx) {
                int x = center.x + dx, y = center.y + dy, d = std::max(std::abs(dx), std::abs(dy));
                if (x >= 0 && x < n && y >= 0 && y < n)
                    set(x, y, d == 0 || d == 1 || d == 3, Function);
            }
    for (int i = 8; i <= n - 9; ++i) {
        set(6, i, i % 2 == 0, Function);
        set(i, 6, i % 2 == 0, Function);
    }
    if (!alignments.empty())
        for (int cy : alignments)
            for (int cx : alignments) {
                int first = alignments.front(), last = alignments.back();
                if ((cx == first && (cy == first || cy == last)) || (cx == last && cy == first))
                    continue;
                for (int dy = -2; dy <= 2; ++dy)
                    for (int dx = -2; dx <= 2; ++dx)
                        set(cx + dx, cy + dy, std::max(std::abs(dx), std::abs(dy)) != 1, Function);
            }
    set(8, n - 8, 1, Function);
    for (const Positions &positions : format_positions(n))
        for (Point p : positions)
            set(p.x, p.y, 0, Format);
    if (version >= 7)
        for (const Positions &positions : version_positions(n)) {
            for (Point p : positions)
                out.areas.cells[p.y][p.x] = Version;
            write_value(out.symbol, positions, version_information(version));
        }
    out.order = reading_order(out.areas);
    for (auto &row : out.indices)
        row.fill(-1);
    for (int i = 0; i < int(out.order.size()); ++i)
        out.indices[out.order[i].y][out.order[i].x] = i;
    return out;
}
int Geometry::function_modules() const { return symbol.size * symbol.size - int(order.size()); }
