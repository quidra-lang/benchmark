#include "raster.hpp"
#include <fstream>

void writePpm(const std::string& path, const Image& image) {
    std::ofstream output(path); output << "P3\n" << image[0].size() << ' ' << image.size() << "\n255\n";
    for (const auto& row : image) { bool first = true; for (const Rgb& color : row) for (int value : color) { if (!first) output << ' '; first = false; output << value; } output << '\n'; }
}
void writePreview(const std::string& path, const Image& image) {
    const std::string ramp = "@%#*+=-:,."; std::ofstream output(path);
    for (int top = 0; top < static_cast<int>(image.size()); top += 4) { for (int left = 0; left < static_cast<int>(image[0].size()); left += 2) { int total = 0; for (int y = top; y < top + 4; ++y) for (int x = left; x < left + 2; ++x) { const Rgb& color = image[y][x]; total += 299 * color[0] + 587 * color[1] + 114 * color[2]; } output << ramp[(total / 8000) * 10 / 256]; } output << '\n'; }
}
