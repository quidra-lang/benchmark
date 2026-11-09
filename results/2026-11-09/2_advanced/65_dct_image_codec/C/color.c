#include "codec.h"
I floor_div(I a, I b) {
    I q = a / b, r = a % b;
    return q - (r < 0);
}
I clamp(I value) { return value < 0 ? 0 : value > 255 ? 255 : value; }
Pixel to_ycbcr(Pixel pixel) {
    I r = pixel.values[0], g = pixel.values[1], b = pixel.values[2];
    return (Pixel){{floor_div(19595 * r + 38470 * g + 7471 * b + 32768, 65536),
                    floor_div(-11059 * r - 21709 * g + 32768 * b + 8421375, 65536),
                    floor_div(32768 * r - 27439 * g - 5329 * b + 8421375, 65536)}};
}
Pixel to_rgb(Pixel pixel) {
    I y = pixel.values[0], cb = pixel.values[1], cr = pixel.values[2];
    return (Pixel){{clamp(y + floor_div(91881 * (cr - 128) + 32768, 65536)),
                    clamp(y + floor_div(-22554 * (cb - 128) - 46802 * (cr - 128) + 32768, 65536)),
                    clamp(y + floor_div(116130 * (cb - 128) + 32768, 65536))}};
}
void split_planes(Image image, Plane out[3]) {
    for (int k = 0; k < 3; ++k)
        out[k] = (Plane){image.width, image.height,
                         allocate((size_t)(image.width * image.height), sizeof(I))};
    for (int i = 0; i < image.width * image.height; ++i) {
        Pixel pixel = to_ycbcr(image.pixels[i]);
        for (int k = 0; k < 3; ++k)
            out[k].pixels[i] = pixel.values[k];
    }
}
void component_planes(const Plane planes[3], const Pair factors[3], int mx, int my, Plane out[3]) {
    int hmax = 1, vmax = 1;
    for (int k = 0; k < 3; ++k) {
        if (factors[k].first > hmax)
            hmax = factors[k].first;
        if (factors[k].second > vmax)
            vmax = factors[k].second;
    }
    for (int k = 0; k < 3; ++k) {
        Plane original = planes[k];
        int width = 8 * factors[k].first * mx, height = 8 * factors[k].second * my;
        out[k] = (Plane){width, height, allocate((size_t)(width * height), sizeof(I))};
        int fx = hmax / factors[k].first, fy = vmax / factors[k].second;
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                I sum = 0;
                for (int j = 0; j < fy; ++j)
                    for (int i = 0; i < fx; ++i) {
                        int xx = fx * x + i, yy = fy * y + j;
                        if (xx >= original.width)
                            xx = original.width - 1;
                        if (yy >= original.height)
                            yy = original.height - 1;
                        sum += original.pixels[yy * original.width + xx];
                    }
                out[k].pixels[y * width + x] = sum / (fx * fy);
            }
    }
}
void upsample(const Plane planes[3], const Pair factors[3], int width, int height, Plane out[3]) {
    int hmax = 1, vmax = 1;
    for (int k = 0; k < 3; ++k) {
        if (factors[k].first > hmax)
            hmax = factors[k].first;
        if (factors[k].second > vmax)
            vmax = factors[k].second;
    }
    for (int k = 0; k < 3; ++k) {
        out[k] = (Plane){width, height, allocate((size_t)(width * height), sizeof(I))};
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
                out[k].pixels[y * width + x] =
                    planes[k].pixels[(y * factors[k].second / vmax) * planes[k].width +
                                     x * factors[k].first / hmax];
    }
}
Image combine_rgb(const Plane planes[3]) {
    Image out = {planes[0].width, planes[0].height, NULL};
    out.pixels = allocate((size_t)(out.width * out.height), sizeof(Pixel));
    for (int i = 0; i < out.width * out.height; ++i)
        out.pixels[i] =
            to_rgb((Pixel){{planes[0].pixels[i], planes[1].pixels[i], planes[2].pixels[i]}});
    return out;
}
