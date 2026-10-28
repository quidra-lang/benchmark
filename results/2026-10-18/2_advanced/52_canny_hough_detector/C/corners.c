#include "detector.h"
static int corner_compare(const void *left, const void *right) {
    const Corner *a = left;
    const Corner *b = right;
    if (a->response != b->response)
        return a->response > b->response ? -1 : 1;
    if (a->point.y != b->point.y)
        return a->point.y < b->point.y ? -1 : 1;
    return (a->point.x > b->point.x) - (a->point.x < b->point.x);
}
Corners corners(Gradient g, const Params *p) {
    Image response = image_new(g.gx.width, g.gx.height);
    I half = (p->harris_window - 1) / 2;
    for (int y = 0; y < response.height; ++y)
        for (int x = 0; x < response.width; ++x) {
            I xx = 0, yy = 0, xy = 0;
            for (I j = -half; j <= half; ++j)
                for (I i = -half; i <= half; ++i) {
                    I gx = clamped(g.gx, x + i, y + j), gy = clamped(g.gy, x + i, y + j);
                    xx += gx * gx;
                    yy += gy * gy;
                    xy += gx * gy;
                }
            image_set(response, (Point){x, y}, xx * yy - xy * xy - floor_div((xx + yy) * (xx + yy), 25));
        }
    Corners out = {.values = allocate((size_t)response.width * response.height, sizeof(Corner))};
    for (int y = 0; y < response.height; ++y)
        for (int x = 0; x < response.width; ++x) {
            Point point = {x, y};
            I value = image_at(response, point);
            if (value < p->harris_threshold)
                continue;
            bool peak = true;
            for (I dy = -1; dy <= 1 && peak; ++dy)
                for (I dx = -1; dx <= 1; ++dx) {
                    Point other = {x + dx, y + dy};
                    if ((dx == 0 && dy == 0) || !image_inside(response, other))
                        continue;
                    I comparison = image_at(response, other);
                    bool earlier = other.y < y || (other.y == y && other.x < x);
                    if (value < comparison || (value == comparison && earlier)) {
                        peak = false;
                        break;
                    }
                }
            if (peak)
                out.values[out.count++] = (Corner){point, value};
        }
    out.candidates = out.count;
    if (out.count > 1)
        qsort(out.values, out.count, sizeof(Corner), corner_compare);
    if (out.count > p->corner_count)
        out.count = (int)p->corner_count;
    return out;
}
