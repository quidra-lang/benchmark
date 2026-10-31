#include "stereo.hpp"
I clamped(const Image &image, int width, int height, int x, int y) {
    return image[std::clamp(y, 0, height - 1) * width + std::clamp(x, 0, width - 1)];
}
Image box_sum(const Image &image, int width, int height, int window) {
    int radius = window / 2, pw = width + 2 * radius, ph = height + 2 * radius;
    Image integral((pw + 1) * (ph + 1), 0), out(width * height);
    for (int y = 0; y < ph; ++y) {
        I sum = 0;
        for (int x = 0; x < pw; ++x) {
            sum += clamped(image, width, height, x - radius, y - radius);
            integral[(y + 1) * (pw + 1) + x + 1] = integral[y * (pw + 1) + x + 1] + sum;
        }
    }
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            out[y * width + x] = integral[(y + window) * (pw + 1) + x + window] -
                                 integral[y * (pw + 1) + x + window] -
                                 integral[(y + window) * (pw + 1) + x] + integral[y * (pw + 1) + x];
    return out;
}
Image census(const Image &image, int width, int height) {
    Image out(width * height);
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            I code = 0;
            for (int dy = -2; dy <= 2; ++dy)
                for (int dx = -2; dx <= 2; ++dx)
                    if (dx || dy)
                        code = (code << 1) | (clamped(image, width, height, x + dx, y + dy) <
                                              image[y * width + x]);
            out[y * width + x] = code;
        }
    return out;
}
Image texture(const Image &image, int width, int height, int window) {
    Image gradient(width * height);
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            gradient[y * width + x] = std::llabs(clamped(image, width, height, x + 1, y) -
                                                 clamped(image, width, height, x - 1, y));
    return box_sum(gradient, width, height, window);
}
Volume cost_volume(const PGM &left, const PGM &right, const Image &cl, const Image &cr, int kind,
                   int window, const Params &p) {
    int width = left.width, height = left.height;
    Volume out(width * height, Image(p.maximum - p.minimum + 1));
    for (int disparity = p.minimum; disparity <= p.maximum; ++disparity) {
        Image pixels(width * height);
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                int index = y * width + x, other = y * width + std::max(x - disparity, 0);
                I value;
                if (kind == 2) {
                    I bits = cl[index] ^ cr[other];
                    value = 0;
                    while (bits) {
                        value += bits & 1;
                        bits >>= 1;
                    }
                } else {
                    I difference = left.pixels[index] - right.pixels[other];
                    value = kind == 0 ? std::llabs(difference) : difference * difference;
                }
                pixels[index] = value;
            }
        Image totals = box_sum(pixels, width, height, window);
        for (int index = 0; index < width * height; ++index)
            out[index][disparity - p.minimum] = totals[index];
    }
    return out;
}
