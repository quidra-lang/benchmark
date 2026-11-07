#include "detector.h"
static void unique_point(Points *points, Point value) {
    for (int i = 0; i < points->count; ++i)
        if (points->data[i].x == value.x && points->data[i].y == value.y)
            return;
    point_push(points, value);
}
Points circle_points(I radius) {
    Points out = {0};
    I a = radius, b = 0, error = 1 - radius;
    while (a >= b) {
        Point points[] = {{a, b}, {b, a}, {-b, a}, {-a, b}, {-a, -b}, {-b, -a}, {b, -a}, {a, -b}};
        for (int i = 0; i < 8; ++i)
            unique_point(&out, points[i]);
        ++b;
        if (error < 0)
            error += 2 * b + 1;
        else {
            --a;
            error += 2 * (b - a) + 1;
        }
    }
    return out;
}
static int circle_compare(const void *left, const void *right) {
    const CirclePeak *a = left;
    const CirclePeak *b = right;
    I x = a->votes * b->points, y = b->votes * a->points;
    if (x != y)
        return x > y ? -1 : 1;
    if (a->radius != b->radius)
        return a->radius < b->radius ? -1 : 1;
    if (a->center.y != b->center.y)
        return a->center.y < b->center.y ? -1 : 1;
    return (a->center.x > b->center.x) - (a->center.x < b->center.x);
}
CircleVotes circle_votes(Image edges, const Params *p) {
    int radii = (int)(p->r_max - p->r_min + 1), size = edges.width * edges.height;
    CircleVotes out = {.offsets = allocate(radii, sizeof(Points)),
                       .votes = allocate(radii, sizeof(I *)),
                       .peaks = allocate((size_t)radii * size, sizeof(CirclePeak))};
    for (int r = 0; r < radii; ++r) {
        out.offsets[r] = circle_points(r + p->r_min);
        out.votes[r] = allocate(size, sizeof(I));
        for (int y = 0; y < edges.height; ++y)
            for (int x = 0; x < edges.width; ++x)
                if (image_at(edges, (Point){x, y}))
                    for (int i = 0; i < out.offsets[r].count; ++i) {
                        Point o = out.offsets[r].data[i], center = {x + o.x, y + o.y};
                        if (image_inside(edges, center))
                            ++out.votes[r][center.y * edges.width + center.x];
                    }
    }
    for (int r = 0; r < radii; ++r) {
        I count = out.offsets[r].count;
        for (int y = 0; y < edges.height; ++y)
            for (int x = 0; x < edges.width; ++x) {
                I value = out.votes[r][y * edges.width + x];
                if (100 * value < p->circle_percent * count)
                    continue;
                ++out.candidates;
                bool peak = true;
                for (int rr = r - 2; rr <= r + 2 && peak; ++rr) {
                    if (rr < 0 || rr >= radii)
                        continue;
                    for (int yy = y - 2; yy <= y + 2 && peak; ++yy) {
                        if (yy < 0 || yy >= edges.height)
                            continue;
                        for (int xx = x - 2; xx <= x + 2; ++xx) {
                            if (xx < 0 || xx >= edges.width || (rr == r && yy == y && xx == x))
                                continue;
                            I left = value * out.offsets[rr].count,
                              right = out.votes[rr][yy * edges.width + xx] * count;
                            bool earlier = rr < r || (rr == r && (yy < y || (yy == y && xx < x)));
                            if (left < right || (left == right && earlier)) {
                                peak = false;
                                break;
                            }
                        }
                    }
                }
                if (peak)
                    out.peaks[out.peak_count++] = (CirclePeak){r + p->r_min, {x, y}, value, count};
            }
    }
    if (out.peak_count > 1)
        qsort(out.peaks, out.peak_count, sizeof(CirclePeak), circle_compare);
    return out;
}
I rho(Point point, I theta, const Trig *trig, const Params *p) {
    return floor_div(point.x * trig->data[theta][0] + point.y * trig->data[theta][1], 16384 * p->rho_step);
}
static int line_compare(const void *left, const void *right) {
    const LinePeak *a = left;
    const LinePeak *b = right;
    if (a->votes != b->votes)
        return a->votes > b->votes ? -1 : 1;
    if (a->theta != b->theta)
        return a->theta < b->theta ? -1 : 1;
    return (a->rho > b->rho) - (a->rho < b->rho);
}
LineVotes line_votes(Image edges, const Trig *trig, const Params *p) {
    LineVotes out = {0};
    Point corners[] = {
        {0, 0}, {edges.width - 1, 0}, {0, edges.height - 1}, {edges.width - 1, edges.height - 1}};
    for (I t = 0; t < 180; ++t)
        for (int i = 0; i < 4; ++i) {
            I value = rho(corners[i], t, trig, p);
            if (value < out.low)
                out.low = value;
            if (value > out.high)
                out.high = value;
        }
    out.votes = image_new(180, (int)(out.high - out.low + 1));
    out.peaks = allocate((size_t)180 * out.votes.height, sizeof(LinePeak));
    for (int y = 0; y < edges.height; ++y)
        for (int x = 0; x < edges.width; ++x)
            if (image_at(edges, (Point){x, y}))
                for (I t = 0; t < 180; ++t)
                    ++out.votes.data[(rho((Point){x, y}, t, trig, p) - out.low) * 180 + t];
    for (int i = 0; i < 180 * out.votes.height; ++i)
        if (out.votes.data[i] > out.maximum)
            out.maximum = out.votes.data[i];
    for (I t = 0; t < 180; ++t)
        for (I r = out.low; r <= out.high; ++r) {
            I value = image_at(out.votes, (Point){t, r - out.low});
            if (value < p->vote_threshold)
                continue;
            bool peak = true;
            for (I tt = t - 2; tt <= t + 2 && peak; ++tt)
                for (I rr = r - 2; rr <= r + 2; ++rr) {
                    if (tt == t && rr == r)
                        continue;
                    I other = tt >= 0 && tt < 180 && rr >= out.low && rr <= out.high
                                  ? image_at(out.votes, (Point){tt, rr - out.low})
                                  : 0;
                    bool earlier = tt < t || (tt == t && rr < r);
                    if (value < other || (value == other && earlier)) {
                        peak = false;
                        break;
                    }
                }
            if (peak)
                out.peaks[out.peak_count++] = (LinePeak){t, r, value};
        }
    if (out.peak_count > 1)
        qsort(out.peaks, out.peak_count, sizeof(LinePeak), line_compare);
    return out;
}
