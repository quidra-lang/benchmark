#include "codec.hpp"
I floor_div(I a, I b) {
    I q = a / b, r = a % b;
    return q - (r < 0);
}
I clamp(I value) { return std::clamp(value, I(0), I(255)); }
Pixel to_ycbcr(Pixel pixel) {
    I r = pixel[0], g = pixel[1], b = pixel[2];
    return {floor_div(19595 * r + 38470 * g + 7471 * b + 32768, 65536),
            floor_div(-11059 * r - 21709 * g + 32768 * b + 8421375, 65536),
            floor_div(32768 * r - 27439 * g - 5329 * b + 8421375, 65536)};
}
Pixel to_rgb(Pixel pixel) {
    I y = pixel[0], cb = pixel[1], cr = pixel[2];
    return {clamp(y + floor_div(91881 * (cr - 128) + 32768, 65536)),
            clamp(y + floor_div(-22554 * (cb - 128) - 46802 * (cr - 128) + 32768, 65536)),
            clamp(y + floor_div(116130 * (cb - 128) + 32768, 65536))};
}
std::array<Plane, 3> split_planes(const Image &image) {
    std::array<Plane, 3> out;
    for (Plane &plane : out) {
        plane.width = image.width;
        plane.height = image.height;
        plane.pixels.resize(image.pixels.size());
    }
    for (int i = 0; i < int(image.pixels.size()); ++i) {
        Pixel pixel = to_ycbcr(image.pixels[i]);
        for (int k = 0; k < 3; ++k)
            out[k].pixels[i] = pixel[k];
    }
    return out;
}
std::array<Plane, 3> component_planes(const std::array<Plane, 3> &planes,
                                      const std::array<Key, 3> &factors, int mx, int my) {
    int hmax = 1, vmax = 1;
    for (Key factor : factors) {
        hmax = std::max(hmax, factor.first);
        vmax = std::max(vmax, factor.second);
    }
    std::array<Plane, 3> out;
    for (int k = 0; k < 3; ++k) {
        const Plane &original = planes[k];
        Plane &plane = out[k];
        plane.width = 8 * factors[k].first * mx;
        plane.height = 8 * factors[k].second * my;
        plane.pixels.resize(plane.width * plane.height);
        int fx = hmax / factors[k].first, fy = vmax / factors[k].second;
        for (int y = 0; y < plane.height; ++y)
            for (int x = 0; x < plane.width; ++x) {
                I sum = 0;
                for (int j = 0; j < fy; ++j)
                    for (int i = 0; i < fx; ++i)
                        sum +=
                            original
                                .pixels[std::min(fy * y + j, original.height - 1) * original.width +
                                        std::min(fx * x + i, original.width - 1)];
                plane.pixels[y * plane.width + x] = sum / (fx * fy);
            }
    }
    return out;
}
std::array<Plane, 3> upsample(const std::array<Plane, 3> &planes, const std::array<Key, 3> &factors,
                              int width, int height) {
    int hmax = 1, vmax = 1;
    for (Key factor : factors) {
        hmax = std::max(hmax, factor.first);
        vmax = std::max(vmax, factor.second);
    }
    std::array<Plane, 3> out;
    for (int k = 0; k < 3; ++k) {
        out[k] = {width, height, std::vector<I>(width * height)};
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
                out[k].pixels[y * width + x] =
                    planes[k].pixels[(y * factors[k].second / vmax) * planes[k].width +
                                     x * factors[k].first / hmax];
    }
    return out;
}
Image combine_rgb(const std::array<Plane, 3> &planes) {
    Image out{planes[0].width, planes[0].height, {}};
    out.pixels.resize(out.width * out.height);
    for (int i = 0; i < int(out.pixels.size()); ++i)
        out.pixels[i] = to_rgb({planes[0].pixels[i], planes[1].pixels[i], planes[2].pixels[i]});
    return out;
}
