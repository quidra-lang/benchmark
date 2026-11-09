#include "geometry.h"
Grid canvas(int width, int height) {
    Grid out = {.width = width, .height = height};
    for (int r = 0; r < height; ++r)
        memset(out.cells[r], ' ', (size_t)width);
    return out;
}
Pair map_point(Point point, int width, int height) {
    return (Pair){(int)((2 * point.x * (width - 1) + 1000) / 2000),
                  height - 1 - (int)((2 * point.y * (height - 1) + 1000) / 2000)};
}
Pair map_center(Center point, int width, int height) {
    return (Pair){(int)((2 * point.x * (width - 1) + 1000 * point.d) / (2000 * point.d)),
                  height - 1 - (int)((2 * point.y * (height - 1) + 1000 * point.d) / (2000 * point.d))};
}
void draw_line(Grid *grid, Pair start, Pair end, char character) {
    int x = start.a, y = start.b;
    const int dx = abs(end.a - x), dy = -abs(end.b - y), sx = x < end.a ? 1 : -1, sy = y < end.b ? 1 : -1;
    int e = dx + dy;
    while (true) {
        grid->cells[y][x] = character;
        if (x == end.a && y == end.b)
            break;
        const int e2 = 2 * e;
        if (e2 >= dy) {
            e += dy;
            x += sx;
        }
        if (e2 <= dx) {
            e += dx;
            y += sy;
        }
    }
}
Grid voronoi_plot(const Point *points, int n, int width, int height) {
    Grid out = canvas(width, height);
    int owners[60][120];
    for (int r = 0; r < height; ++r)
        for (int c = 0; c < width; ++c) {
            Integer best = 0;
            int owner = 0;
            for (int s = 0; s < n; ++s) {
                const Integer x = (c * 1000 - points[s].x * (width - 1)) * (height - 1),
                              y = ((height - 1 - r) * 1000 - points[s].y * (height - 1)) * (width - 1),
                              value = x * x + y * y;
                if (s == 0 || value < best) {
                    best = value;
                    owner = s;
                }
            }
            owners[r][c] = owner;
        }
    for (int r = 0; r < height; ++r)
        for (int c = 0; c < width; ++c)
            if ((c + 1 < width && owners[r][c] != owners[r][c + 1]) ||
                (r + 1 < height && owners[r][c] != owners[r + 1][c]))
                out.cells[r][c] = '#';
    for (int s = 0; s < n; ++s) {
        const Pair cell = map_point(points[s], width, height);
        out.cells[cell.b][cell.a] = 'o';
    }
    return out;
}
void framed(Text *out, const Grid *grid) {
    add(out, "+");
    for (int c = 0; c < grid->width; ++c)
        add(out, "-");
    line(out, "+");
    for (int r = 0; r < grid->height; ++r) {
        add(out, "|");
        for (int c = 0; c < grid->width; ++c)
            add(out, "%c", grid->cells[r][c]);
        line(out, "|");
    }
    add(out, "+");
    for (int c = 0; c < grid->width; ++c)
        add(out, "-");
    line(out, "+");
}
