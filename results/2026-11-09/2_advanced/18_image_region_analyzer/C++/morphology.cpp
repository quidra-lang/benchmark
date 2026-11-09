#include "regions.hpp"
#include <array>

Mask erode(const Mask& mask, const Pixels& offsets) {
    Mask result(mask.width, mask.height);
    for (int y = 0; y < mask.height; ++y) for (int x = 0; x < mask.width; ++x) {
        bool value = true;
        for (const Pixel& offset : offsets) if (!mask.at(x + offset.first, y + offset.second)) value = false;
        result.set(x, y, value);
    }
    return result;
}
Mask dilate(const Mask& mask, const Pixels& offsets) {
    Mask result(mask.width, mask.height);
    for (int y = 0; y < mask.height; ++y) for (int x = 0; x < mask.width; ++x) {
        bool value = false;
        for (const Pixel& offset : offsets) if (mask.at(x - offset.first, y - offset.second)) value = true;
        result.set(x, y, value);
    }
    return result;
}
Mask opening(const Mask& mask, const Pixels& offsets) { return dilate(erode(mask, offsets), offsets); }
Mask closing(const Mask& mask, const Pixels& offsets) { return erode(dilate(mask, offsets), offsets); }
static const Pixels neighborhood{{0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}};
static std::array<int, 8> neighborBits(const PixelSet& pixels, Pixel point) {
    std::array<int, 8> bits{};
    for (std::size_t i = 0; i < 8; ++i) bits[i] = pixels.count({point.first + neighborhood[i].first, point.second + neighborhood[i].second}) != 0;
    return bits;
}
static int transitions(const std::array<int, 8>& bits) { int count = 0; for (std::size_t i = 0; i < 8; ++i) count += !bits[i] && bits[(i + 1) % 8]; return count; }
int crossingNumber(const PixelSet& pixels, Pixel point) { return transitions(neighborBits(pixels, point)); }
static int thinningStep(PixelSet& skeleton, bool first) {
    Pixels removed;
    for (const Pixel& pixel : skeleton) {
        std::array<int, 8> bits = neighborBits(skeleton, pixel);
        int count = std::accumulate(bits.begin(), bits.end(), 0);
        if (count < 2 || count > 6 || transitions(bits) != 1) continue;
        bool a = first ? bits[0] && bits[2] && bits[4] : bits[0] && bits[2] && bits[6];
        bool b = first ? bits[2] && bits[4] && bits[6] : bits[0] && bits[4] && bits[6];
        if (!a && !b) removed.push_back(pixel);
    }
    for (const Pixel& pixel : removed) skeleton.erase(pixel);
    return static_cast<int>(removed.size());
}
PixelSet thin(const Pixels& pixels) {
    PixelSet skeleton(pixels.begin(), pixels.end());
    while (true) { int first = thinningStep(skeleton, true), second = thinningStep(skeleton, false); if (!first && !second) return skeleton; }
}
