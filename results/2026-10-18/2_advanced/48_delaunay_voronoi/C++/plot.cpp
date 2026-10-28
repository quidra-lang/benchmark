#include "geometry.hpp"
Grid canvas(int width, int height) {
    return Grid(height, std::string(width, ' '));
}
Pair map_point(Point point, int width, int height) {
    return {int((2 * point.x * (width - 1) + 1000) / 2000),
            height - 1 - int((2 * point.y * (height - 1) + 1000) / 2000)};
}
Pair map_center(Center point, int width, int height) {
    return {int((2 * point.x * (width - 1) + 1000 * point.d) / (2000 * point.d)),
            height - 1 - int((2 * point.y * (height - 1) + 1000 * point.d) / (2000 * point.d))};
}
void draw_line(Grid &grid, Pair start, Pair end, char character) {
    int x = start.first, y = start.second;
    const int dx = std::abs(end.first - x), dy = -std::abs(end.second - y), sx = x < end.first ? 1 : -1,
              sy = y < end.second ? 1 : -1;
    int e = dx + dy;
    while (true) {
        grid[y][x] = character;
        if (x == end.first && y == end.second)
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
Grid voronoi_plot(const std::vector<Point> &points, int width, int height) {
    Grid out = canvas(width, height);
    std::vector<Ints> owners(height, Ints(width));
    for (int r = 0; r < height; ++r)
        for (int c = 0; c < width; ++c) {
            Integer best = 0;
            int owner = 0;
            for (std::size_t s = 0; s < points.size(); ++s) {
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
                out[r][c] = '#';
    for (Point point : points) {
        const Pair cell = map_point(point, width, height);
        out[cell.second][cell.first] = 'o';
    }
    return out;
}
Lines framed(const Grid &grid) {
    const std::string border = "+" + std::string(grid[0].size(), '-') + "+";
    Lines out{border};
    for (const std::string &row : grid)
        out.push_back("|" + row + "|");
    out.push_back(border);
    return out;
}
