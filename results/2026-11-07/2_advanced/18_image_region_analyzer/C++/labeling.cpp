#include "regions.hpp"

static int find(std::vector<int>& parents, int label) {
    while (parents[label] != label) { parents[label] = parents[parents[label]]; label = parents[label]; }
    return label;
}
Labeling labelComponents(const Mask& mask, int connectivity) {
    Labeling result{mask.width, mask.height, 0, 0, std::vector<int>(mask.pixels.size())};
    std::vector<int> parents{0}, provisional(mask.pixels.size());
    Pixels previous = connectivity == 4 ? Pixels{{-1, 0}, {0, -1}} : Pixels{{-1, 0}, {-1, -1}, {0, -1}, {1, -1}};
    for (int y = 0; y < mask.height; ++y) for (int x = 0; x < mask.width; ++x) {
        if (!mask.at(x, y)) continue;
        std::vector<int> neighbors;
        for (const Pixel& offset : previous) { int nx = x + offset.first, ny = y + offset.second; if (mask.at(nx, ny)) neighbors.push_back(provisional[static_cast<std::size_t>(ny * mask.width + nx)]); }
        int label;
        if (neighbors.empty()) { label = static_cast<int>(parents.size()); parents.push_back(label); }
        else {
            label = neighbors.front();
            for (int other : neighbors) { int firstRoot = find(parents, label), secondRoot = find(parents, other); parents[std::max(firstRoot, secondRoot)] = std::min(firstRoot, secondRoot); }
        }
        provisional[static_cast<std::size_t>(y * mask.width + x)] = label;
    }
    std::vector<int> numbers(parents.size());
    for (std::size_t i = 0; i < provisional.size(); ++i) if (provisional[i]) { int root = find(parents, provisional[i]); if (!numbers[root]) numbers[root] = ++result.count; result.labels[i] = numbers[root]; }
    result.provisional = static_cast<int>(parents.size() - 1);
    return result;
}
int bitQuadEuler(const Mask& mask, int connectivity) {
    int singles = 0, triples = 0, diagonals = 0;
    for (int y = -1; y < mask.height; ++y) for (int x = -1; x < mask.width; ++x) {
        bool a = mask.at(x, y), b = mask.at(x + 1, y), c = mask.at(x, y + 1), d = mask.at(x + 1, y + 1);
        int count = static_cast<int>(a) + static_cast<int>(b) + static_cast<int>(c) + static_cast<int>(d);
        singles += count == 1; triples += count == 3; diagonals += count == 2 && ((a && d) || (b && c));
    }
    return (singles - triples + (connectivity == 8 ? -2 : 2) * diagonals) / 4;
}
