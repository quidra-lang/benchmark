#include "stereo.h"
Regions truth_regions(PGM truth) {
    int width = truth.width, height = truth.height;
    Regions out = {0};
    for (int r = 0; r < 3; ++r)
        out.region[r].data = allocate((size_t)(width * height), sizeof(int));
    out.occluded.data = allocate((size_t)(width * height), sizeof(int));
    for (int index = 0; index < width * height; ++index) {
        I g = truth.pixels[index];
        if (!g)
            continue;
        out.region[1].data[out.region[1].count++] = index;
        int x = index % width, y = index / width, target = x - (int)g;
        bool occluded = target < 0;
        for (int x2 = 0; !occluded && x2 < width; ++x2)
            occluded =
                truth.pixels[y * width + x2] > g && x2 - truth.pixels[y * width + x2] == target;
        if (occluded)
            out.occluded.data[out.occluded.count++] = index;
        else
            out.region[0].data[out.region[0].count++] = index;
    }
    for (int i = 0; i < out.region[0].count; ++i) {
        int index = out.region[0].data[i], x = index % width, y = index / width;
        bool discontinuity = false;
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx) {
                int xx = x + dx, yy = y + dy;
                if (xx < 0 || xx >= width || yy < 0 || yy >= height)
                    continue;
                I other = truth.pixels[yy * width + xx];
                if (other && llabs(other - truth.pixels[index]) >= 2)
                    discontinuity = true;
            }
        if (discontinuity)
            out.region[2].data[out.region[2].count++] = index;
    }
    return out;
}
Evaluation evaluate(const I *image, const I *truth, Pixels region) {
    Evaluation out = {0};
    out.pixels = region.count;
    for (int i = 0; i < region.count; ++i) {
        int index = region.data[i];
        if (!image[index]) {
            ++out.bad1;
            ++out.bad2;
            continue;
        }
        ++out.valid;
        I difference = llabs(image[index] - truth[index]);
        out.bad1 += difference > 1;
        out.bad2 += difference > 2;
        out.error_sum += difference;
        out.exact += difference == 0;
    }
    return out;
}
static I gcd(I a, I b) {
    while (b) {
        I next = a % b;
        a = b;
        b = next;
    }
    return a;
}
char *ratio(I numerator, I denominator) {
    if (!denominator)
        return "0/1 0.00";
    I divisor = gcd(numerator, denominator);
    return format("%lld/%lld %s", numerator / divisor, denominator / divisor,
                  two_decimals(100 * numerator, denominator));
}
