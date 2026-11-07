#include "raster.hpp"
#include <algorithm>

int floorDiv(int numerator, int denominator) { int quotient = numerator / denominator; return quotient - (numerator % denominator < 0 ? 1 : 0); }
int roundRatio(int numerator, int denominator) { if (denominator < 0) { numerator = -numerator; denominator = -denominator; } return floorDiv(2 * numerator + denominator,2 * denominator); }
int effectiveAlpha(int alpha, int opacity) { return roundRatio(alpha * opacity,255); }
Layer::Layer(int width, int height, int opacity, std::string mode) : width(width), height(height), opacity(opacity), mode(std::move(mode)), colors(width * height), lines(width * height) {}
void Layer::paint(Point point, Color color, int line) { colors[point.y * width + point.x] = color; lines[point.y * width + point.x] = line; }
bool Layer::erase(Point point) { auto& color = colors[point.y * width + point.x]; bool painted = color.has_value(); color.reset(); return painted; }
const std::optional<Color>& Layer::colorAt(Point point) const { return colors[point.y * width + point.x]; }
int Layer::lineAt(Point point) const { return lines[point.y * width + point.x]; }
int Layer::alphaAt(Point point) const { const auto& color = colorAt(point); return color ? effectiveAlpha((*color)[3],opacity) : 0; }
Rgb Layer::blend(Point point, Rgb current) const {
    const auto& color = colorAt(point); if (!color) return current; int alpha = effectiveAlpha((*color)[3],opacity);
    for (int channel = 0; channel < 3; ++channel) { int source = (*color)[channel], value = current[channel]; if (mode == "multiply") source = roundRatio(source * value,255); else if (mode == "screen") source = 255 - roundRatio((255 - source) * (255 - value),255); current[channel] = roundRatio(alpha * source + (255 - alpha) * value,255); } return current;
}
Image composite(const std::vector<Layer>& layers, Color background, int width, int height) {
    Image image(height,std::vector<Rgb>(width)); for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) { Rgb color{background[0],background[1],background[2]}; for (const Layer& layer : layers) color = layer.blend({x,y},color); image[y][x] = color; } return image;
}
