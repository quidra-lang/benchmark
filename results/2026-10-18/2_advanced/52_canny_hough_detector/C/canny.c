#include "detector.h"
Canny canny(Gradient g, const Params *p) {
    int w = g.gx.width, h = g.gx.height;
    Canny out = {.direction = image_new(w, h),
                 .nms = image_new(w, h),
                 .edges = image_new(w, h),
                 .components = allocate(w * h, sizeof(Points))};
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            Point point = {x, y};
            I gx = image_at(g.gx, point), gy = image_at(g.gy, point), ax = absolute(gx), ay = absolute(gy);
            I direction = 29 * ay <= 12 * ax ? 0 : 29 * ay >= 70 * ax ? 90 : gx * gy < 0 ? 45 : 135;
            image_set(out.direction, point, direction);
            if (x == 0 || y == 0 || x == w - 1 || y == h - 1)
                continue;
            Point a, b;
            if (direction == 0) {
                a = (Point){x - 1, y};
                b = (Point){x + 1, y};
            } else if (direction == 45) {
                a = (Point){x + 1, y - 1};
                b = (Point){x - 1, y + 1};
            } else if (direction == 90) {
                a = (Point){x, y - 1};
                b = (Point){x, y + 1};
            } else {
                a = (Point){x - 1, y - 1};
                b = (Point){x + 1, y + 1};
            }
            I m = image_at(g.magnitude, point);
            if (m > image_at(g.magnitude, a) && m >= image_at(g.magnitude, b))
                image_set(out.nms, point, m);
        }
    Points queue = {0};
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            Point point = {x, y};
            I value = image_at(out.nms, point);
            if (value >= p->high) {
                ++out.strong;
                image_set(out.edges, point, 1);
                point_push(&queue, point);
            } else if (value >= p->low)
                ++out.weak;
        }
    for (int head = 0; head < queue.count; ++head) {
        Point point = queue.data[head];
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx) {
                Point next = {point.x + dx, point.y + dy};
                if (image_inside(out.edges, next) && !image_at(out.edges, next) &&
                    image_at(out.nms, next) >= p->low) {
                    image_set(out.edges, next, 1);
                    point_push(&queue, next);
                }
            }
    }
    Image visited = image_new(w, h);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            Point first = {x, y};
            if (!image_at(out.edges, first) || image_at(visited, first))
                continue;
            Points component = {0};
            point_push(&component, first);
            image_set(visited, first, 1);
            for (int head = 0; head < component.count; ++head) {
                Point point = component.data[head];
                for (int dy = -1; dy <= 1; ++dy)
                    for (int dx = -1; dx <= 1; ++dx) {
                        Point next = {point.x + dx, point.y + dy};
                        if (image_inside(out.edges, next) && image_at(out.edges, next) &&
                            !image_at(visited, next)) {
                            image_set(visited, next, 1);
                            point_push(&component, next);
                        }
                    }
            }
            out.components[out.count++] = component;
        }
    return out;
}
