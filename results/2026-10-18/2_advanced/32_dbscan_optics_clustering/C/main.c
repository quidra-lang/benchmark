#include "clustering.h"
static void emit(FILE *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    vfprintf(out, pattern, args);
    va_end(args);
    fputc('\n', out);
}
static char *number(Integer value) {
    return value == DISTANCE_INF ? "-" : format("%" PRId64, value);
}
static char character(int label) {
    return label < 0 ? '.' : label < 26 ? (char)('A' + label) : label < 52 ? (char)('a' + label - 26) : '#';
}
static int cluster_count(const int *labels, int n) {
    int count = 0;
    for (int i = 0; i < n; ++i)
        if (labels[i] + 1 > count)
            count = labels[i] + 1;
    return count;
}
static int noise_count(const int *labels, int n) {
    int count = 0;
    for (int i = 0; i < n; ++i)
        if (labels[i] < 0)
            ++count;
    return count;
}
static IntList *groups(const int *labels, int n) {
    int count = cluster_count(labels, n);
    IntList *result = calloc((size_t)count, sizeof *result);
    for (int i = 0; i < n; ++i)
        if (labels[i] >= 0)
            push(result + labels[i], i);
    return result;
}
static int *extraction(const Optics *ordering, int radius) {
    int *labels = malloc((size_t)ordering->count * sizeof *labels), cluster = -1;
    Integer threshold = (Integer)radius * radius;
    for (int i = 0; i < ordering->count; ++i) {
        int p = ordering->order[i];
        if (ordering->reach[p] > threshold) {
            if (ordering->core[p] <= threshold)
                labels[p] = ++cluster;
            else
                labels[p] = -1;
        } else
            labels[p] = cluster;
    }
    return labels;
}
static int integer_compare(const void *a, const void *b) {
    Integer x = *(const Integer *)a, y = *(const Integer *)b;
    return (x > y) - (x < y);
}
typedef struct {
    Integer distance;
    int point;
} KneePoint;
static int knee_compare(const void *a, const void *b) {
    const KneePoint *x = a, *y = b;
    if (x->distance != y->distance)
        return x->distance > y->distance ? -1 : 1;
    return (x->point > y->point) - (x->point < y->point);
}
typedef struct {
    int rank, point, radius;
    Integer distance, cross;
    int *order;
} Knee;
static Integer neighbor_distance(const Integer *neighbors, int n, int point, int k) {
    return neighbors[(size_t)point * (size_t)(n - 1) + (size_t)(k - 1)];
}
static Knee knee(const Integer *neighbors, int n, int k) {
    KneePoint *values = malloc((size_t)n * sizeof *values);
    for (int i = 0; i < n; ++i)
        values[i] = (KneePoint){neighbor_distance(neighbors, n, i, k), i};
    qsort(values, (size_t)n, sizeof *values, knee_compare);
    Integer first = values[0].distance, last = values[n - 1].distance, greatest = -1;
    int best = 0;
    for (int r = 0; r < n; ++r) {
        Integer value = (Integer)(n - 1) * (values[r].distance - first) - (last - first) * r,
                cross = value < 0 ? -value : value;
        if (cross > greatest) {
            greatest = cross;
            best = r;
        }
    }
    int radius = 1;
    while ((Integer)radius * radius < values[best].distance)
        ++radius;
    Knee result = {best + 1, values[best].point,
                   radius,   values[best].distance,
                   greatest, malloc((size_t)n * sizeof(int))};
    for (int i = 0; i < n; ++i)
        result.order[i] = values[i].point;
    free(values);
    return result;
}
typedef struct {
    bool down;
    int first, last;
} SteepArea;
typedef struct {
    int first, last, label, parent;
} XiCluster;
typedef struct {
    int *labels;
    SteepArea *areas;
    int area_count;
    XiCluster *clusters;
    int cluster_count, capacity;
    Integer *reach;
} XiResult;
typedef struct {
    bool *steep_up, *steep_down, *up, *down;
    int n, min_points;
} SteepFlags;
static bool xle(Integer a, Integer b, Integer alpha, Integer beta) {
    if (b == DISTANCE_INF)
        return true;
    if (a == DISTANCE_INF)
        return false;
    return beta * a <= alpha * b;
}
static int extend_region(SteepFlags flags, int first, bool descending) {
    int end = first, count = 0;
    for (int i = first; i <= flags.n; ++i) {
        if (descending ? flags.steep_down[i] : flags.steep_up[i]) {
            end = i;
            count = 0;
        } else if (descending ? flags.up[i] : flags.down[i])
            break;
        else if (++count > flags.min_points)
            break;
    }
    return end;
}
static void push_cluster(XiResult *result, XiCluster cluster) {
    if (result->cluster_count == result->capacity) {
        result->capacity = result->capacity ? result->capacity * 2 : 16;
        result->clusters = realloc(result->clusters, (size_t)result->capacity * sizeof *result->clusters);
    }
    result->clusters[result->cluster_count++] = cluster;
}
static XiResult xi_extract(const Optics *ordering, const Params *p) {
    int n = ordering->count;
    Integer alpha = (Integer)(p->xi_v - p->xi_u) * (p->xi_v - p->xi_u), beta = (Integer)p->xi_v * p->xi_v;
    XiResult result = {.areas = malloc((size_t)n * sizeof(SteepArea)),
                       .reach = malloc((size_t)(n + 2) * sizeof(Integer))};
    for (int i = 0; i < n + 2; ++i)
        result.reach[i] = DISTANCE_INF;
    for (int i = 1; i <= n; ++i)
        result.reach[i] = ordering->reach[ordering->order[i - 1]];
    Integer *reach = result.reach;
    SteepFlags flags = {calloc((size_t)n + 1, sizeof(bool)),
                        calloc((size_t)n + 1, sizeof(bool)),
                        calloc((size_t)n + 1, sizeof(bool)),
                        calloc((size_t)n + 1, sizeof(bool)),
                        n,
                        p->min_points};
    for (int i = 1; i <= n; ++i) {
        if (reach[i] == DISTANCE_INF && reach[i + 1] == DISTANCE_INF)
            continue;
        flags.steep_up[i] = xle(reach[i], reach[i + 1], alpha, beta);
        flags.steep_down[i] = xle(reach[i + 1], reach[i], alpha, beta);
        flags.up[i] = flags.steep_up[i] || reach[i] < reach[i + 1];
        flags.down[i] = flags.steep_down[i] || reach[i] > reach[i + 1];
    }
    typedef struct {
        int first, last;
        Integer maximum;
    } DownArea;
    DownArea *areas = malloc((size_t)n * sizeof *areas);
    int area_count = 0, index = 1;
    Integer mib = 0;
    XiCluster *candidates = malloc((size_t)n * sizeof *candidates);
    for (int s = 1; s <= n; ++s) {
        if (s < index || (!flags.steep_up[s] && !flags.steep_down[s]))
            continue;
        for (int i = index; i <= s; ++i)
            if (reach[i] > mib)
                mib = reach[i];
        if (mib == DISTANCE_INF)
            area_count = 0;
        else {
            int kept = 0;
            for (int i = 0; i < area_count; ++i)
                if (xle(mib, reach[areas[i].first], alpha, beta)) {
                    DownArea area = areas[i];
                    if (mib > area.maximum)
                        area.maximum = mib;
                    areas[kept++] = area;
                }
            area_count = kept;
        }
        if (flags.steep_down[s]) {
            int end = extend_region(flags, s, true);
            areas[area_count++] = (DownArea){s, end, 0};
            result.areas[result.area_count++] = (SteepArea){true, s, end};
            index = end + 1;
            mib = reach[index];
        } else {
            int end = extend_region(flags, s, false);
            result.areas[result.area_count++] = (SteepArea){false, s, end};
            index = end + 1;
            mib = reach[index];
            int candidate_count = 0;
            for (int i = 0; i < area_count; ++i) {
                DownArea area = areas[i];
                int cs = area.first, ce = end;
                if (!xle(area.maximum, reach[ce + 1], alpha, beta))
                    continue;
                Integer left = reach[area.first];
                if (xle(reach[ce + 1], left, alpha, beta)) {
                    while (cs < area.last && reach[cs + 1] > reach[ce + 1])
                        ++cs;
                } else if (xle(left, reach[ce + 1], alpha, beta)) {
                    while (ce > s && reach[ce - 1] > left)
                        --ce;
                }
                if (ce - cs + 1 >= p->xi_size && cs <= area.last && ce >= s)
                    candidates[candidate_count++] = (XiCluster){cs, ce, -1, -1};
            }
            for (int i = candidate_count - 1; i >= 0; --i)
                push_cluster(&result, candidates[i]);
        }
    }
    int *positions = malloc((size_t)(n + 1) * sizeof *positions), next = 0;
    for (int i = 0; i <= n; ++i)
        positions[i] = -2;
    for (int j = 0; j < result.cluster_count; ++j) {
        XiCluster *cluster = result.clusters + j;
        bool unassigned = true;
        for (int i = cluster->first; i <= cluster->last; ++i)
            if (positions[i] != -2)
                unassigned = false;
        if (unassigned) {
            cluster->label = next;
            for (int i = cluster->first; i <= cluster->last; ++i)
                positions[i] = next;
            ++next;
        }
    }
    result.labels = malloc((size_t)n * sizeof *result.labels);
    for (int i = 1; i <= n; ++i)
        result.labels[ordering->order[i - 1]] = positions[i] < 0 ? -1 : positions[i];
    for (int j = 0; j < result.cluster_count; ++j) {
        XiCluster *cluster = result.clusters + j;
        int size = cluster->last - cluster->first + 1;
        for (int i = 0; i < result.cluster_count; ++i) {
            if (i == j)
                continue;
            XiCluster candidate = result.clusters[i];
            int candidate_size = candidate.last - candidate.first + 1;
            if (candidate.first > cluster->first || candidate.last < cluster->last ||
                !(candidate_size > size || (candidate_size == size && i > j)))
                continue;
            int old_size = cluster->parent < 0 ? INT_MAX
                                               : result.clusters[cluster->parent].last -
                                                     result.clusters[cluster->parent].first + 1;
            if (candidate_size < old_size || (candidate_size == old_size && i < cluster->parent))
                cluster->parent = i;
        }
    }
    free(flags.steep_up);
    free(flags.steep_down);
    free(flags.up);
    free(flags.down);
    free(areas);
    free(candidates);
    free(positions);
    return result;
}
typedef struct {
    char *name;
    int radius;
    int *labels;
    bool *core;
    bool db, extraction;
} Setting;
static Integer turn(Point o, Point a, Point b) {
    return (Integer)(a.x - o.x) * (b.y - o.y) - (Integer)(a.y - o.y) * (b.x - o.x);
}
static bool point_less(Point a, Point b) {
    return a.x < b.x || (a.x == b.x && a.y < b.y);
}
static IntList hull(const Point *points, IntList members) {
    int *ids = malloc((size_t)members.count * sizeof *ids);
    for (int i = 0; i < members.count; ++i) {
        int id = members.values[i], at_ = i;
        while (at_ && point_less(points[id], points[ids[at_ - 1]])) {
            ids[at_] = ids[at_ - 1];
            --at_;
        }
        ids[at_] = id;
    }
    IntList result = {0};
    if (members.count <= 2) {
        for (int i = 0; i < members.count; ++i)
            push(&result, ids[i]);
        free(ids);
        return result;
    }
    IntList lower = {0}, upper = {0};
    for (int i = 0; i < members.count; ++i) {
        int id = ids[i];
        while (lower.count >= 2 && turn(points[lower.values[lower.count - 2]],
                                        points[lower.values[lower.count - 1]], points[id]) <= 0)
            --lower.count;
        push(&lower, id);
    }
    for (int i = members.count - 1; i >= 0; --i) {
        int id = ids[i];
        while (upper.count >= 2 && turn(points[upper.values[upper.count - 2]],
                                        points[upper.values[upper.count - 1]], points[id]) <= 0)
            --upper.count;
        push(&upper, id);
    }
    for (int i = 0; i < lower.count - 1; ++i)
        push(&result, lower.values[i]);
    for (int i = 0; i < upper.count - 1; ++i)
        push(&result, upper.values[i]);
    free(ids);
    free(lower.values);
    free(upper.values);
    return result;
}
typedef struct {
    int a, b;
} LabelPair;
static int pair_compare(const void *a, const void *b) {
    const LabelPair *x = a, *y = b;
    if (x->a != y->a)
        return (x->a > y->a) - (x->a < y->a);
    return (x->b > y->b) - (x->b < y->b);
}
static Integer choose_two(Integer value) {
    return value * (value - 1) / 2;
}
static void ari(const int *a, const int *b, int n, Integer *numerator, Integer *denominator) {
    int ka = cluster_count(a, n), kb = cluster_count(b, n);
    Integer *rows = calloc((size_t)ka + 1, sizeof *rows), *columns = calloc((size_t)kb + 1, sizeof *columns);
    LabelPair *cells = malloc((size_t)n * sizeof *cells);
    for (int i = 0; i < n; ++i) {
        ++rows[a[i] + 1];
        ++columns[b[i] + 1];
        cells[i] = (LabelPair){a[i], b[i]};
    }
    qsort(cells, (size_t)n, sizeof *cells, pair_compare);
    Integer s = 0, x = 0, y = 0;
    for (int first = 0; first < n;) {
        int end = first + 1;
        while (end < n && cells[end].a == cells[first].a && cells[end].b == cells[first].b)
            ++end;
        s += choose_two(end - first);
        first = end;
    }
    for (int i = 0; i <= ka; ++i)
        x += choose_two(rows[i]);
    for (int i = 0; i <= kb; ++i)
        y += choose_two(columns[i]);
    Integer z = choose_two(n);
    *numerator = 2 * (z * s - x * y);
    *denominator = z * (x + y) - 2 * x * y;
    if (!*denominator)
        *numerator = *denominator = 1;
    free(rows);
    free(columns);
    free(cells);
}
static Grid *find_grid(Grid *grids, int count, int radius) {
    for (int i = 0; i < count; ++i)
        if (grids[i].radius == radius)
            return grids + i;
    abort();
}
static void setting_report(FILE *out, const Setting *setting, const Point *points, const Distances *distances,
                           Grid *grids, int grid_count) {
    int n = distances->count, count = cluster_count(setting->labels, n), core_count = 0, border_count = 0;
    IntList *members = groups(setting->labels, n);
    for (int i = 0; i < n; ++i)
        if (setting->labels[i] >= 0) {
            if (setting->core[i])
                ++core_count;
            else
                ++border_count;
        }
    emit(out, "setting %s eps %d clusters %d noise %d core %d border %d", setting->name, setting->radius,
         count, noise_count(setting->labels, n), core_count, border_count);
    for (int label = 0; label < count; ++label) {
        IntList ids = members[label];
        Integer sx = 0, sy = 0;
        int core = 0, xmin = 10001, ymin = 10001, xmax = 0, ymax = 0;
        for (int i = 0; i < ids.count; ++i) {
            int id = ids.values[i];
            sx += points[id].x;
            sy += points[id].y;
            if (setting->core[id])
                ++core;
            if (points[id].x < xmin)
                xmin = points[id].x;
            if (points[id].y < ymin)
                ymin = points[id].y;
            if (points[id].x > xmax)
                xmax = points[id].x;
            if (points[id].y > ymax)
                ymax = points[id].y;
        }
        int medoid = ids.values[0];
        Integer best = DISTANCE_INF;
        for (int i = 0; i < ids.count; ++i) {
            int id = ids.values[i];
            Integer x = (Integer)ids.count * points[id].x - sx, y = (Integer)ids.count * points[id].y - sy,
                    value = x * x + y * y;
            if (value < best) {
                best = value;
                medoid = id;
            }
        }
        IntList vertices = hull(points, ids);
        Integer area2 = 0, diameter = 0;
        for (int i = 0; i < vertices.count; ++i) {
            Point a = points[vertices.values[i]], b = points[vertices.values[(i + 1) % vertices.count]];
            area2 += (Integer)a.x * b.y - (Integer)b.x * a.y;
            for (int j = 0; j < vertices.count; ++j)
                if (at(distances, vertices.values[i], vertices.values[j]) > diameter)
                    diameter = at(distances, vertices.values[i], vertices.values[j]);
        }
        if (area2 < 0)
            area2 = -area2;
        Integer area = (Integer)(xmax - xmin + 1) * (ymax - ymin + 1);
        emit(out, "cluster %d %c size %d core %d border %d centroid %s %s medoid %d", label, character(label),
             ids.count, core, ids.count - core, fraction(sx, ids.count), fraction(sy, ids.count),
             points[medoid].id);
        emit(out, "  bbox %d %d %d %d area %" PRId64 " density %s", xmin, ymin, xmax, ymax, area,
             fraction(ids.count, area));
        emit(out, "  hull %d hull_area %" PRId64 ".%d diameter_sq %" PRId64 " diameter %s", vertices.count,
             area2 / 2, area2 % 2 ? 5 : 0, diameter, root(diameter));
        free(vertices.values);
    }
    if (setting->db) {
        Grid *grid = find_grid(grids, grid_count, setting->radius);
        bool a = true, b = true, c = true;
        int isolated = 0, ambiguous = 0;
        Lines details = {0};
        bool *others = calloc((size_t)count, sizeof *others);
        for (int point = 0; point < n; ++point) {
            if (setting->core[point]) {
                for (int i = 0; i < grid->neighbors[point].count; ++i) {
                    int q = grid->neighbors[point].values[i];
                    if (setting->core[q] && setting->labels[point] != setting->labels[q])
                        a = false;
                }
            } else if (setting->labels[point] >= 0) {
                bool found = false;
                memset(others, 0, (size_t)count * sizeof *others);
                int other_count = 0;
                for (int i = 0; i < grid->neighbors[point].count; ++i) {
                    int q = grid->neighbors[point].values[i];
                    if (!setting->core[q])
                        continue;
                    int label = setting->labels[q];
                    if (label == setting->labels[point])
                        found = true;
                    else if (!others[label]) {
                        others[label] = true;
                        ++other_count;
                    }
                }
                if (!found)
                    b = false;
                if (other_count) {
                    ++ambiguous;
                    char *line = format("  %d cluster %d also", points[point].id, setting->labels[point]);
                    for (int label = 0; label < count; ++label)
                        if (others[label])
                            append_text(&line, " %d", label);
                    add_line(&details, "%s", line);
                    free(line);
                }
            } else {
                if (grid->neighbors[point].count == 1)
                    ++isolated;
                for (int i = 0; i < grid->neighbors[point].count; ++i)
                    if (setting->core[grid->neighbors[point].values[i]])
                        c = false;
            }
        }
        emit(out, "check %s %s %s", a ? "ok" : "fail", b ? "ok" : "fail", c ? "ok" : "fail");
        emit(out, "isolated %d", isolated);
        emit(out, "ambiguous %d", ambiguous);
        write_lines(out, &details);
        free(others);
    }
    for (int i = 0; i < count; ++i)
        free(members[i].values);
    free(members);
}
static char **cluster_map(const Setting *setting, const Point *points, int n, const Params *p, bool kinds) {
    int x0 = 10001, y0 = 10001, x1 = 0, y1 = 0;
    for (int i = 0; i < n; ++i) {
        if (points[i].x < x0)
            x0 = points[i].x;
        if (points[i].y < y0)
            y0 = points[i].y;
        if (points[i].x > x1)
            x1 = points[i].x;
        if (points[i].y > y1)
            y1 = points[i].y;
    }
    int cells = p->width * p->height, *labels = malloc((size_t)cells * sizeof *labels),
        *priority = calloc((size_t)cells, sizeof *priority);
    bool *occupied = calloc((size_t)cells, sizeof *occupied),
         *multiple = calloc((size_t)cells, sizeof *multiple);
    for (int c = 0; c < cells; ++c)
        labels[c] = -1;
    for (int i = 0; i < n; ++i) {
        int column = (points[i].x - x0) * p->width / (x1 - x0 + 1),
            row = (y1 - points[i].y) * p->height / (y1 - y0 + 1), cell = row * p->width + column;
        occupied[cell] = true;
        if (setting->core[i])
            priority[cell] = 2;
        else if (setting->labels[i] >= 0 && priority[cell] < 1)
            priority[cell] = 1;
        if (setting->labels[i] >= 0) {
            if (labels[cell] < 0)
                labels[cell] = setting->labels[i];
            else if (labels[cell] != setting->labels[i])
                multiple[cell] = true;
        }
    }
    char **rows = malloc((size_t)p->height * sizeof *rows);
    for (int r = 0; r < p->height; ++r) {
        rows[r] = malloc((size_t)p->width + 1);
        rows[r][p->width] = 0;
        for (int c = 0; c < p->width; ++c) {
            int cell = r * p->width + c;
            rows[r][c] = !occupied[cell]  ? ' '
                         : kinds          ? (priority[cell] == 2   ? '#'
                                             : priority[cell] == 1 ? '+'
                                                                   : '.')
                         : multiple[cell] ? '*'
                                          : character(labels[cell]);
        }
    }
    free(labels);
    free(priority);
    free(occupied);
    free(multiple);
    return rows;
}
typedef struct {
    int point, nearest;
    Integer distance;
} Outlier;
static int outlier_compare(const void *a, const void *b) {
    const Outlier *x = a, *y = b;
    if (x->distance != y->distance)
        return x->distance > y->distance ? -1 : 1;
    return (x->point > y->point) - (x->point < y->point);
}
int main(void) {
    Input input = read_input();
    Point *points = input.points;
    Params *p = &input.params;
    int n = input.count, k = p->min_points - 1;
    Distances distances = {malloc((size_t)n * (size_t)n * sizeof(Integer)), n};
    Integer *neighbors = malloc((size_t)n * (size_t)(n - 1) * sizeof *neighbors);
    for (int i = 0; i < n; ++i) {
        int next = 0;
        for (int j = 0; j < n; ++j) {
            Integer value = distance(points[i], points[j]);
            distances.values[(size_t)i * (size_t)n + (size_t)j] = value;
            if (i != j)
                neighbors[(size_t)i * (size_t)(n - 1) + (size_t)next++] = value;
        }
        qsort(neighbors + (size_t)i * (size_t)(n - 1), (size_t)n - 1, sizeof *neighbors, integer_compare);
    }
    Knee main_knee = knee(neighbors, n, k);
    int radii[8], radius_count = 0;
    for (int i = 0; i < p->eps.count + 2; ++i) {
        int radius = i < p->eps.count    ? p->eps.values[i]
                     : i == p->eps.count ? main_knee.radius
                                         : p->max_eps,
            at_ = 0;
        while (at_ < radius_count && radii[at_] < radius)
            ++at_;
        if (at_ < radius_count && radii[at_] == radius)
            continue;
        memmove(radii + at_ + 1, radii + at_, (size_t)(radius_count - at_) * sizeof *radii);
        radii[at_] = radius;
        ++radius_count;
    }
    Grid grids[8];
    for (int i = 0; i < radius_count; ++i)
        grids[i] = build_grid(points, &distances, radii[i]);
    Optics ordering = optics(find_grid(grids, radius_count, p->max_eps), &distances, p->min_points);
    XiResult xi = xi_extract(&ordering, p);
    Setting settings[14];
    int setting_count = 0;
    for (int i = 0; i <= p->eps.count; ++i) {
        int radius = i == p->eps.count ? main_knee.radius : p->eps.values[i];
        Grid *grid = find_grid(grids, radius_count, radius);
        bool *core = malloc((size_t)n * sizeof *core);
        for (int point = 0; point < n; ++point)
            core[point] = grid->neighbors[point].count >= p->min_points;
        settings[setting_count++] = (Setting){format("%s%d", i == p->eps.count ? "knee" : "db", radius),
                                              radius,
                                              dbscan(grid, p->min_points),
                                              core,
                                              true,
                                              false};
    }
    int db_count = setting_count, knee_index = db_count - 1;
    for (int i = 0; i < p->extract.count; ++i) {
        int radius = p->extract.values[i];
        bool *core = malloc((size_t)n * sizeof *core);
        for (int point = 0; point < n; ++point)
            core[point] = ordering.core[point] <= (Integer)radius * radius;
        settings[setting_count++] =
            (Setting){format("op%d", radius), radius, extraction(&ordering, radius), core, false, true};
    }
    bool *xi_core = malloc((size_t)n * sizeof *xi_core);
    for (int i = 0; i < n; ++i)
        xi_core[i] = ordering.core[i] != DISTANCE_INF;
    settings[setting_count++] = (Setting){"xi", p->max_eps, xi.labels, xi_core, false, false};
    Setting *knee_setting = settings + knee_index, *xi_setting = settings + setting_count - 1;
    FILE *labels = fopen("output/labels.csv", "w");
    fputs("id", labels);
    for (int s = 0; s < setting_count; ++s)
        fprintf(labels, ",%s", settings[s].name);
    fputc('\n', labels);
    for (int point = 0; point < n; ++point) {
        fprintf(labels, "%d", points[point].id);
        for (int s = 0; s < setting_count; ++s)
            fprintf(labels, ",%d", settings[s].labels[point]);
        fputc('\n', labels);
    }
    fclose(labels);
    FILE *order_file = fopen("output/optics_order.csv", "w");
    emit(order_file, "order,id,core_sq,reach_sq,reach,predecessor");
    for (int i = 0; i < n; ++i) {
        int id = ordering.order[i];
        emit(order_file, "%d,%d,%s,%s,%s,%s", i + 1, points[id].id, number(ordering.core[id]),
             number(ordering.reach[id]), root(ordering.reach[id]),
             ordering.predecessor[id] < 0 ? "-" : format("%d", points[ordering.predecessor[id]].id));
    }
    fclose(order_file);
    FILE *kdist = fopen("output/kdist.txt", "w");
    emit(kdist, "k_distance k %d points %d", k, n);
    emit(kdist, "rank id kdist_sq kdist");
    for (int i = 0; i < n; ++i) {
        int id = main_knee.order[i];
        Integer value = neighbor_distance(neighbors, n, id, k);
        emit(kdist, "%d %d %" PRId64 " %s", i + 1, points[id].id, value, root(value));
    }
    emit(kdist, "\nknee rank %d id %d kdist_sq %" PRId64 " kdist %s cross %" PRId64, main_knee.rank,
         points[main_knee.point].id, main_knee.distance, root(main_knee.distance), main_knee.cross);
    emit(kdist, "suggested_eps %d", main_knee.radius);
    emit(kdist, "\nknee_table");
    for (int j = 1; j <= 2 * p->min_points; ++j) {
        Knee curve = knee(neighbors, n, j);
        emit(kdist, "k %d rank %d id %d kdist_sq %" PRId64 " eps %d", j, curve.rank, points[curve.point].id,
             curve.distance, curve.radius);
        free(curve.order);
    }
    emit(kdist, "\ncore_check");
    for (int s = 0; s < db_count; ++s) {
        Setting setting = settings[s];
        int core = 0, grid_core = 0;
        for (int id = 0; id < n; ++id) {
            if (neighbor_distance(neighbors, n, id, k) <= (Integer)setting.radius * setting.radius)
                ++core;
            if (setting.core[id])
                ++grid_core;
        }
        emit(kdist, "eps %d core %d non_core %d grid_core %d %s", setting.radius, core, n - core, grid_core,
             core == grid_core ? "ok" : "mismatch");
    }
    bool core_ok = true;
    int optics_core = 0;
    for (int id = 0; id < n; ++id)
        if (ordering.core[id] != DISTANCE_INF) {
            ++optics_core;
            if (ordering.core[id] != neighbor_distance(neighbors, n, id, k))
                core_ok = false;
        }
    emit(kdist, "optics max_eps %d core %d %s", p->max_eps, optics_core, core_ok ? "ok" : "mismatch");
    fclose(kdist);
    FILE *out = fopen("output/clusters.txt", "w");
    emit(out, "points %d min_pts %d", n, p->min_points);
    fputs("settings", out);
    for (int s = 0; s < setting_count; ++s)
        fprintf(out, " %s", settings[s].name);
    emit(out, "\n\ngrid");
    for (int i = 0; i < radius_count; ++i) {
        Grid grid = grids[i];
        emit(out,
             "eps %d cells %d busiest %d %d %d candidates %" PRId64 " pairs %" PRId64 " brute_pairs %" PRId64
             " %s",
             grid.radius, grid.cell_count, grid.busiest_x, grid.busiest_y, grid.busiest_count,
             grid.total_candidates, grid.pairs, grid.brute_pairs, grid.correct ? "ok" : "mismatch");
        fputs("  occupancy", out);
        for (int c = 1; c <= n; ++c)
            if (grid.occupancy[c])
                fprintf(out, " %d:%d", c, grid.occupancy[c]);
        fputc('\n', out);
    }
    for (int s = 0; s < setting_count; ++s) {
        fputc('\n', out);
        setting_report(out, settings + s, points, &distances, grids, radius_count);
    }
    emit(out, "\nhierarchy");
    int hierarchy[7];
    for (int i = 0; i < db_count; ++i) {
        int at_ = i;
        while (at_ && settings[i].radius < settings[hierarchy[at_ - 1]].radius) {
            hierarchy[at_] = hierarchy[at_ - 1];
            --at_;
        }
        hierarchy[at_] = i;
    }
    for (int i = 1; i < db_count; ++i) {
        Setting *a = settings + hierarchy[i - 1], *b = settings + hierarchy[i];
        emit(out, "%s -> %s", a->name, b->name);
        int ka = cluster_count(a->labels, n), kb = cluster_count(b->labels, n);
        IntList *source = groups(a->labels, n), *destinations = calloc((size_t)kb, sizeof *destinations);
        for (int label = 0; label < ka; ++label)
            for (int j = 0; j < source[label].count; ++j) {
                int id = source[label].values[j];
                if (a->core[id]) {
                    push(destinations + b->labels[id], label);
                    break;
                }
            }
        for (int label = 0; label < kb; ++label) {
            fprintf(out, "  %d <-", label);
            if (!destinations[label].count)
                fputs(" -", out);
            for (int j = 0; j < destinations[label].count; ++j)
                fprintf(out, " %d", destinations[label].values[j]);
            fputc('\n', out);
        }
        for (int label = 0; label < ka; ++label)
            free(source[label].values);
        for (int label = 0; label < kb; ++label)
            free(destinations[label].values);
        free(source);
        free(destinations);
    }
    emit(out, "\noptics_vs_dbscan");
    for (int s = db_count; s < setting_count - 1; ++s) {
        Setting *a = settings + s, *b = NULL;
        for (int d_ = 0; d_ < db_count; ++d_)
            if (settings[d_].radius == a->radius) {
                b = settings + d_;
                break;
            }
        if (!b)
            continue;
        int ka = cluster_count(a->labels, n), kb = cluster_count(b->labels, n),
            *forward = malloc((size_t)ka * sizeof *forward), *reverse = malloc((size_t)kb * sizeof *reverse),
            border_noise = 0;
        for (int i = 0; i < ka; ++i)
            forward[i] = -2;
        for (int i = 0; i < kb; ++i)
            reverse[i] = -2;
        bool same = true;
        for (int id = 0; id < n; ++id) {
            if (a->core[id]) {
                int x = a->labels[id], y = b->labels[id];
                if (forward[x] != -2 && forward[x] != y)
                    same = false;
                if (reverse[y] != -2 && reverse[y] != x)
                    same = false;
                forward[x] = y;
                reverse[y] = x;
            }
            if (a->labels[id] < 0 && b->labels[id] >= 0)
                ++border_noise;
        }
        for (int i = 0; i < ka; ++i)
            if (forward[i] == -2)
                same = false;
        for (int i = 0; i < kb; ++i)
            if (reverse[i] == -2)
                same = false;
        int moved = 0;
        if (same)
            for (int id = 0; id < n; ++id)
                if (a->labels[id] >= 0 && forward[a->labels[id]] != b->labels[id])
                    ++moved;
        emit(out, "%s %s core_partition %s border_as_noise %d moved %s", a->name, b->name,
             same ? "same" : "different", border_noise, same ? format("%d", moved) : "-");
        free(forward);
        free(reverse);
    }
    int components = 0, singletons = 0, largest = 0, current = 0;
    for (int i = 0; i < n; ++i) {
        int id = ordering.order[i];
        if (ordering.reach[id] == DISTANCE_INF) {
            if (current) {
                if (current == 1)
                    ++singletons;
                if (current > largest)
                    largest = current;
            }
            ++components;
            current = 0;
        }
        ++current;
    }
    if (current) {
        if (current == 1)
            ++singletons;
        if (current > largest)
            largest = current;
    }
    emit(out, "\noptics max_eps %d core %d components %d singletons %d largest %d", p->max_eps, optics_core,
         components, singletons, largest);
    emit(out, "\nsweep max_eps %d", p->max_eps);
    emit(out, "eps clusters noise largest");
    int sweep[201] = {0};
    for (int radius = 1; radius <= p->max_eps; ++radius) {
        int *result = extraction(&ordering, radius), count = cluster_count(result, n), largest_ = 0;
        IntList *members = groups(result, n);
        for (int c = 0; c < count; ++c) {
            if (members[c].count > largest_)
                largest_ = members[c].count;
            free(members[c].values);
        }
        sweep[radius] = count;
        emit(out, "%d %d %d %d", radius, count, noise_count(result, n), largest_);
        free(result);
        free(members);
    }
    int stable_first = 0, stable_last = 0;
    for (int first = 1; first <= p->max_eps;) {
        int last = first;
        while (last < p->max_eps && sweep[last + 1] == sweep[first])
            ++last;
        if (sweep[first] >= 2 && (!stable_first || last - first > stable_last - stable_first)) {
            stable_first = first;
            stable_last = last;
        }
        first = last + 1;
    }
    if (!stable_first)
        emit(out, "stable -");
    else
        emit(out, "stable clusters %d eps %d %d length %d", sweep[stable_first], stable_first, stable_last,
             stable_last - stable_first + 1);
    emit(out, "\nxi %d/%d min_size %d steep_areas %d", p->xi_u, p->xi_v, p->xi_size, xi.area_count);
    for (int i = 0; i < xi.area_count; ++i)
        emit(out, "%s %d %d", xi.areas[i].down ? "down" : "up", xi.areas[i].first, xi.areas[i].last);
    emit(out, "xi_clusters %d", xi.cluster_count);
    for (int i = 0; i < xi.cluster_count; ++i) {
        XiCluster cluster = xi.clusters[i];
        Integer valley = DISTANCE_INF;
        for (int t = cluster.first + 1; t <= cluster.last; ++t)
            if (xi.reach[t] < valley)
                valley = xi.reach[t];
        emit(out, "%d start %d end %d size %d label %s parent %s walls %s %s valley %s", i, cluster.first,
             cluster.last, cluster.last - cluster.first + 1,
             cluster.label < 0 ? "-" : format("%d", cluster.label),
             cluster.parent < 0 ? "-" : format("%d", cluster.parent), root(xi.reach[cluster.first]),
             root(xi.reach[cluster.last + 1]), root(valley));
    }
    Outlier *outliers = malloc((size_t)n * sizeof *outliers);
    int outlier_count = 0;
    for (int id = 0; id < n; ++id)
        if (knee_setting->labels[id] < 0) {
            int nearest = -1;
            Integer best = DISTANCE_INF;
            for (int q = 0; q < n; ++q)
                if (knee_setting->core[q] && at(&distances, id, q) < best) {
                    best = at(&distances, id, q);
                    nearest = q;
                }
            outliers[outlier_count++] = (Outlier){id, nearest, best};
        }
    qsort(outliers, (size_t)outlier_count, sizeof *outliers, outlier_compare);
    emit(out, "\noutliers %s count %d", knee_setting->name, outlier_count);
    for (int i = 0; i < outlier_count; ++i) {
        Outlier item = outliers[i];
        emit(out, "%d nearest_core %d cluster %d dist_sq %" PRId64 " dist %s", points[item.point].id,
             points[item.nearest].id, knee_setting->labels[item.nearest], item.distance, root(item.distance));
    }
    int knee_count = cluster_count(knee_setting->labels, n), xi_count = cluster_count(xi_setting->labels, n);
    IntList *knee_members = groups(knee_setting->labels, n), *xi_members = groups(xi_setting->labels, n);
    emit(out, "\ngaps %s", knee_setting->name);
    for (int a = 0; a < knee_count; ++a)
        for (int b = a + 1; b < knee_count; ++b) {
            Integer best = DISTANCE_INF;
            int first = -1, second = -1;
            for (int i = 0; i < knee_members[a].count; ++i)
                for (int j = 0; j < knee_members[b].count; ++j) {
                    int x = knee_members[a].values[i], y = knee_members[b].values[j];
                    if (at(&distances, x, y) < best) {
                        best = at(&distances, x, y);
                        first = x;
                        second = y;
                    }
                }
            emit(out, "%d %d dist_sq %" PRId64 " dist %s between %d %d", a, b, best, root(best),
                 points[first].id, points[second].id);
        }
    int columns = xi_count + 1;
    int *table = calloc((size_t)(knee_count + 1) * (size_t)columns, sizeof *table);
    for (int id = 0; id < n; ++id)
        ++table[(size_t)(knee_setting->labels[id] + 1) * (size_t)columns +
                (size_t)(xi_setting->labels[id] + 1)];
    emit(out, "\ncontingency %s xi", knee_setting->name);
    fputs("columns", out);
    for (int c = -1; c < xi_count; ++c)
        fprintf(out, " %d", c);
    fputc('\n', out);
    for (int r = -1; r < knee_count; ++r) {
        fprintf(out, "%d", r);
        for (int c = 0; c < columns; ++c)
            fprintf(out, " %d", table[(size_t)(r + 1) * (size_t)columns + (size_t)c]);
        fputc('\n', out);
    }
    for (int c = 0; c < xi_count; ++c) {
        int match = 0;
        for (int r = 1; r < knee_count; ++r)
            if (table[(size_t)(r + 1) * (size_t)columns + (size_t)c + 1] >
                table[(size_t)(match + 1) * (size_t)columns + (size_t)c + 1])
                match = r;
        int shared = table[(size_t)(match + 1) * (size_t)columns + (size_t)c + 1];
        emit(out, "match %d %d shared %d jaccard %s", c, match, shared,
             fraction(shared, (Integer)knee_members[match].count + xi_members[c].count - shared));
    }
    emit(out, "\nari");
    for (int a = 0; a < setting_count; ++a)
        for (int b = a + 1; b < setting_count; ++b) {
            Integer numerator, denominator;
            ari(settings[a].labels, settings[b].labels, n, &numerator, &denominator);
            emit(out, "%s %s %s %s", settings[a].name, settings[b].name, fraction(numerator, denominator),
                 ari_value(numerator, denominator));
        }
    fclose(out);
    FILE *maps = fopen("output/maps.txt", "w");
    for (int s = 0; s < setting_count; ++s) {
        Setting setting = settings[s];
        int count = cluster_count(setting.labels, n);
        IntList *members = groups(setting.labels, n);
        emit(maps, "map %s clusters %d noise %d", setting.name, count, noise_count(setting.labels, n));
        char **rows = cluster_map(&setting, points, n, p, false);
        framed(maps, rows, p->width, p->height);
        fputs("legend", maps);
        if (!count)
            fputs(" -", maps);
        for (int label = 0; label < count; ++label) {
            fprintf(maps, " %c=%d", character(label), members[label].count);
            free(members[label].values);
        }
        fputs("\n\n", maps);
        free(members);
        for (int r = 0; r < p->height; ++r)
            free(rows[r]);
        free(rows);
    }
    emit(maps, "kinds %s", knee_setting->name);
    char **kind_rows = cluster_map(knee_setting, points, n, p, true);
    framed(maps, kind_rows, p->width, p->height);
    fputc('\n', maps);
    Integer maximum = neighbor_distance(neighbors, n, main_knee.order[0], k);
    int heights[100] = {0}, knee_column = 0;
    for (int c = 0; c < p->kwidth; ++c) {
        int first = c * n / p->kwidth, end = (c + 1) * n / p->kwidth;
        Integer value = neighbor_distance(neighbors, n, main_knee.order[first], k);
        while ((Integer)(heights[c] + 1) * (heights[c] + 1) * maximum <=
               (Integer)p->kheight * p->kheight * value)
            ++heights[c];
        if (first < main_knee.rank && main_knee.rank <= end)
            knee_column = c;
    }
    char **curve = malloc((size_t)p->kheight * sizeof *curve);
    for (int r = 0; r < p->kheight; ++r) {
        curve[r] = malloc((size_t)p->kwidth + 1);
        for (int c = 0; c < p->kwidth; ++c)
            curve[r][c] = p->kheight - r <= heights[c] ? '#' : c == knee_column ? ':' : ' ';
        curve[r][p->kwidth] = 0;
    }
    emit(maps, "kdist_plot k %d max %s knee_column %d", k, root(maximum), knee_column + 1);
    framed(maps, curve, p->kwidth, p->kheight);
    Integer reach_top = 0;
    for (int id = 0; id < n; ++id)
        if (ordering.reach[id] != DISTANCE_INF && ordering.reach[id] > reach_top)
            reach_top = ordering.reach[id];
    fprintf(maps, "\nreachability width %d max_reach %s columns", p->rwidth, root(reach_top));
    for (int s = db_count; s < setting_count; ++s)
        fprintf(maps, " %s", settings[s].name);
    fputc('\n', maps);
    for (int i = 0; i < n; ++i) {
        int id = ordering.order[i];
        char marks[15];
        int count = 0;
        for (int s = db_count; s < setting_count; ++s)
            marks[count++] = character(settings[s].labels[id]);
        marks[count] = 0;
        int length = p->rwidth;
        char mark = '-';
        if (ordering.reach[id] != DISTANCE_INF) {
            length = 0;
            mark = '#';
            while ((Integer)(length + 1) * (length + 1) * reach_top <=
                   (Integer)p->rwidth * p->rwidth * ordering.reach[id])
                ++length;
        }
        char bar[101];
        memset(bar, mark, (size_t)length);
        bar[length] = 0;
        emit(maps, "%4d %5d %7s %s |%s", i + 1, points[id].id, root(ordering.reach[id]), marks, bar);
    }
    fclose(maps);
    return 0;
}
