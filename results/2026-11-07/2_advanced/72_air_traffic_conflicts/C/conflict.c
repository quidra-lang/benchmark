#include "airspace.h"
bool loss_interval(Point relative, Point velocity, double first, double last, double horizontal,
                   double vertical, Loss *out) {
    const double *p = relative.v, *w = velocity.v;
    double qa = w[0] * w[0] + w[1] * w[1], qb = 2 * (p[0] * w[0] + p[1] * w[1]),
           qc = (p[0] * p[0] + p[1] * p[1]) - horizontal * horizontal, low = first, high = last;
    if (qa < 1e-12) {
        if (qc >= 0)
            return false;
    } else {
        double discriminant = qb * qb - 4 * qa * qc;
        if (discriminant <= 0)
            return false;
        double root = sqrt(discriminant);
        low = fmax(low, first + (-qb - root) / (2 * qa));
        high = fmin(high, first + (-qb + root) / (2 * qa));
    }
    if (w[2] == 0) {
        if (fabs(p[2]) >= vertical)
            return false;
    } else {
        double r1 = (-vertical - p[2]) / w[2], r2 = (vertical - p[2]) / w[2];
        low = fmax(low, first + fmin(r1, r2));
        high = fmin(high, first + fmax(r1, r2));
    }
    if (high - low <= 1e-6)
        return false;
    double time = qa >= 1e-12 ? first + (-qb / (2 * qa)) : first;
    time = fmin(fmax(time, low), high);
    double tau = time - first, ex = p[0] + w[0] * tau, ey = p[1] + w[1] * tau;
    *out = (Loss){low, high, time, sqrt(ex * ex + ey * ey), fabs(p[2] + w[2] * tau)};
    return true;
}
int conflict_compare(const void *left, const void *right) {
    const Conflict *a = left, *b = right;
    if (a->start != b->start)
        return a->start < b->start ? -1 : 1;
    if (a->pair.first != b->pair.first)
        return a->pair.first < b->pair.first ? -1 : 1;
    return (a->pair.second > b->pair.second) - (a->pair.second < b->pair.second);
}
Conflicts pair_conflicts(int first, const Trajectory *ta, int second, const Trajectory *tb,
                         const Params *params) {
    Piece pieces[196];
    int count = 0;
    for (int i = 0; i < ta->count; ++i)
        for (int j = 0; j < tb->count; ++j) {
            const Segment *a = &ta->segments[i], *b = &tb->segments[j];
            double t1 = fmax(a->start_time, b->start_time), t2 = fmin(a->end_time, b->end_time);
            if (t1 >= t2)
                continue;
            Point pa = position(a, t1), pb = position(b, t1), relative, velocity;
            for (int axis = 0; axis < 3; ++axis) {
                relative.v[axis] = pa.v[axis] - pb.v[axis];
                velocity.v[axis] = a->velocity.v[axis] - b->velocity.v[axis];
            }
            Loss loss;
            if (loss_interval(relative, velocity, t1, t2, (double)params->horizontal,
                              (double)params->vertical, &loss)) {
                Piece piece = {i, j, loss};
                int k = count++;
                while (k > 0 && piece.loss.low < pieces[k - 1].loss.low) {
                    pieces[k] = pieces[k - 1];
                    --k;
                }
                pieces[k] = piece;
            }
        }
    Conflicts out = {0};
    for (int i = 0; i < count; ++i) {
        Piece piece = pieces[i];
        if (out.count == 0 || piece.loss.low - out.items[out.count - 1].end > 1e-6) {
            Conflict conflict = {0};
            conflict.pair = (Pair){first, second};
            conflict.start = piece.loss.low;
            conflict.end = piece.loss.high;
            conflict.closest = piece;
            Pieces_append(&conflict.pieces, piece);
            Conflicts_append(&out, conflict);
        } else {
            Conflict *conflict = &out.items[out.count - 1];
            Pieces_append(&conflict->pieces, piece);
            conflict->end = piece.loss.high;
            if (piece.loss.distance < conflict->closest.loss.distance - 1e-9)
                conflict->closest = piece;
        }
    }
    return out;
}
Conflicts all_conflicts(const Trajectory *trajectories, int count, const Params *params) {
    Conflicts out = {0};
    for (int a = 0; a < count; ++a)
        for (int b = a + 1; b < count; ++b) {
            Conflicts pair = pair_conflicts(a, &trajectories[a], b, &trajectories[b], params);
            for (size_t i = 0; i < pair.count; ++i)
                Conflicts_append(&out, pair.items[i]);
            free(pair.items);
        }
    if (out.count > 1)
        qsort(out.items, out.count, sizeof *out.items, conflict_compare);
    return out;
}
void free_conflicts(Conflicts *list) {
    for (size_t i = 0; i < list->count; ++i)
        free(list->items[i].pieces.items);
    free(list->items);
    *list = (Conflicts){0};
}
