#include "qr.hpp"
Lines symbol_lines(const Matrix &symbol) {
    Lines lines;
    for (int y = 0; y < symbol.size; ++y) {
        std::string row;
        for (int x = 0; x < symbol.size; ++x)
            row += symbol.cells[y][x] ? '#' : '.';
        lines.push_back(row);
    }
    return lines;
}
std::string pbm_text(const Matrix &symbol, int quiet, int scale) {
    int width = (symbol.size + 2 * quiet) * scale;
    std::ostringstream out;
    out << "P1\n" << width << ' ' << width << '\n';
    for (int py = 0; py < width; ++py) {
        for (int px = 0; px < width; ++px) {
            int x = px / scale - quiet, y = py / scale - quiet;
            out << (x >= 0 && x < symbol.size && y >= 0 && y < symbol.size ? symbol.cells[y][x]
                                                                           : 0);
        }
        out << '\n';
    }
    return out.str();
}
