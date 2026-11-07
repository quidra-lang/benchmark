#include "stereo.hpp"
Regions truth_regions(const PGM &truth) {
    int width = truth.width, height = truth.height;
    Regions out;
    std::vector<bool> hidden(truth.pixels.size());
    for (int index = 0; index < width * height; ++index) {
        I g = truth.pixels[index];
        if (!g)
            continue;
        out.region[1].push_back(index);
        int x = index % width, y = index / width, target = x - int(g);
        bool occluded = target < 0;
        for (int x2 = 0; !occluded && x2 < width; ++x2)
            occluded =
                truth.pixels[y * width + x2] > g && x2 - truth.pixels[y * width + x2] == target;
        if (occluded) {
            hidden[index] = true;
            out.occluded.push_back(index);
        } else
            out.region[0].push_back(index);
    }
    for (int index : out.region[0]) {
        int x = index % width, y = index / width;
        bool discontinuity = false;
        for (int yy = std::max(0, y - 1); yy <= std::min(height - 1, y + 1); ++yy)
            for (int xx = std::max(0, x - 1); xx <= std::min(width - 1, x + 1); ++xx) {
                I other = truth.pixels[yy * width + xx];
                if (other && std::llabs(other - truth.pixels[index]) >= 2)
                    discontinuity = true;
            }
        if (discontinuity)
            out.region[2].push_back(index);
    }
    return out;
}
Evaluation evaluate(const Image &image, const Image &truth, const Pixels &region) {
    Evaluation out;
    out.pixels = I(region.size());
    for (int index : region) {
        if (!image[index]) {
            ++out.bad1;
            ++out.bad2;
            continue;
        }
        ++out.valid;
        I difference = std::llabs(image[index] - truth[index]);
        out.bad1 += difference > 1;
        out.bad2 += difference > 2;
        out.error_sum += difference;
        out.exact += difference == 0;
    }
    return out;
}
std::string ratio(I numerator, I denominator) {
    if (!denominator)
        return "0/1 0.00";
    I divisor = std::gcd(numerator, denominator);
    return std::to_string(numerator / divisor) + "/" + std::to_string(denominator / divisor) + " " +
           two_decimals(100 * numerator, denominator);
}
