#include "stereo.h"
I clamped(const I *image, int width, int height, int x, int y) {
    x = x < 0 ? 0 : x >= width ? width - 1 : x;
    y = y < 0 ? 0 : y >= height ? height - 1 : y;
    return image[y * width + x];
}
I *box_sum(const I *image, int width, int height, int window) {
    int radius = window / 2, pw = width + 2 * radius, ph = height + 2 * radius;
    I *integral = allocate((size_t)((pw + 1) * (ph + 1)), sizeof(I)),
      *out = allocate((size_t)(width * height), sizeof(I));
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
I *census(const I *image, int width, int height) {
    I *out = allocate((size_t)(width * height), sizeof(I));
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
I *texture(const I *image, int width, int height, int window) {
    I *gradient = allocate((size_t)(width * height), sizeof(I));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            gradient[y * width + x] = llabs(clamped(image, width, height, x + 1, y) -
                                            clamped(image, width, height, x - 1, y));
    return box_sum(gradient, width, height, window);
}
Volume cost_volume(PGM left, PGM right, const I *cl, const I *cr, int kind, int window,
                   const Params *p) {
    int width = left.width, height = left.height, count = p->maximum - p->minimum + 1;
    Volume out = {allocate((size_t)(width * height * count), sizeof(I)), width * height, count};
    for (int disparity = p->minimum; disparity <= p->maximum; ++disparity) {
        I *pixels = allocate((size_t)(width * height), sizeof(I));
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                int index = y * width + x, other = y * width + (x > disparity ? x - disparity : 0);
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
                    value = kind == 0 ? llabs(difference) : difference * difference;
                }
                pixels[index] = value;
            }
        I *totals = box_sum(pixels, width, height, window);
        for (int index = 0; index < width * height; ++index)
            out.values[index * count + disparity - p->minimum] = totals[index];
    }
    return out;
}
