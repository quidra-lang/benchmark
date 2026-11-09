#include "detector.hpp"
I floor_div(I a, I b) {
    return a / b - (a % b < 0);
}
I clamped(const Image &image, I x, I y) {
    x = std::max<I>(0, std::min<I>(image.width - 1, x));
    y = std::max<I>(0, std::min<I>(image.height - 1, y));
    return image.at({x, y});
}
Image smooth(const Image &image, const Params &p) {
    Image out(image.width, image.height);
    const I half = (p.ks - 1) / 2;
    for (int y = 0; y < image.height; ++y)
        for (int x = 0; x < image.width; ++x) {
            I sum = 0;
            for (I j = 0; j < p.ks; ++j)
                for (I i = 0; i < p.ks; ++i)
                    sum += p.kernel[j * p.ks + i] * clamped(image, x + i - half, y + j - half);
            out.at({x, y}) = floor_div(sum, p.divisor);
        }
    return out;
}
Gradient gradient(const Image &image) {
    Gradient out{Image(image.width, image.height), Image(image.width, image.height),
                 Image(image.width, image.height)};
    for (int y = 0; y < image.height; ++y)
        for (int x = 0; x < image.width; ++x) {
            I q[9];
            for (int j = -1; j <= 1; ++j)
                for (int i = -1; i <= 1; ++i)
                    q[(j + 1) * 3 + i + 1] = clamped(image, x + i, y + j);
            const I gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6],
                    gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
            out.gx.at({x, y}) = gx;
            out.gy.at({x, y}) = gy;
            out.magnitude.at({x, y}) = std::abs(gx) + std::abs(gy);
        }
    return out;
}
