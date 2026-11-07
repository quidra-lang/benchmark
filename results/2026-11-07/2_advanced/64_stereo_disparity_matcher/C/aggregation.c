#include "stereo.h"
const Point directions[8] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {-1, 1}, {1, -1}};
Volume path_costs(Volume base, PGM left, Point direction, const Params *p) {
    int width = left.width, height = left.height, count = base.disparities;
    Volume out = {allocate((size_t)(base.pixels * count), sizeof(I)), base.pixels, count};
    for (int iy = 0; iy < height; ++iy) {
        int y = direction.y >= 0 ? iy : height - 1 - iy;
        for (int ix = 0; ix < width; ++ix) {
            int x = direction.x >= 0 ? ix : width - 1 - ix, index = y * width + x,
                qx = x - direction.x, qy = y - direction.y;
            if (qx < 0 || qx >= width || qy < 0 || qy >= height) {
                memcpy(out.values + index * count, base.values + index * count,
                       (size_t)count * sizeof(I));
                continue;
            }
            int previous = qy * width + qx;
            I minimum = out.values[previous * count];
            for (int d = 1; d < count; ++d)
                if (out.values[previous * count + d] < minimum)
                    minimum = out.values[previous * count + d];
            I penalty =
                p->p2 * p->gamma / (p->gamma + llabs(left.pixels[index] - left.pixels[previous]));
            if (penalty < p->p1)
                penalty = p->p1;
            for (int d = 0; d < count; ++d) {
                I best = out.values[previous * count + d];
                if (minimum + penalty < best)
                    best = minimum + penalty;
                if (d > 0 && out.values[previous * count + d - 1] + p->p1 < best)
                    best = out.values[previous * count + d - 1] + p->p1;
                if (d + 1 < count && out.values[previous * count + d + 1] + p->p1 < best)
                    best = out.values[previous * count + d + 1] + p->p1;
                out.values[index * count + d] = base.values[index * count + d] + best - minimum;
            }
        }
    }
    return out;
}
Volume *cumulative_costs(Volume base, PGM left, const Params *p) {
    Volume *out = allocate((size_t)p->paths, sizeof(Volume));
    I *total = allocate((size_t)(base.pixels * base.disparities), sizeof(I));
    for (int i = 0; i < p->paths; ++i) {
        Volume path = path_costs(base, left, directions[i], p);
        out[i] = (Volume){allocate((size_t)(base.pixels * base.disparities), sizeof(I)),
                          base.pixels, base.disparities};
        for (int index = 0; index < base.pixels * base.disparities; ++index) {
            total[index] += path.values[index];
            out[i].values[index] = total[index];
        }
    }
    return out;
}
