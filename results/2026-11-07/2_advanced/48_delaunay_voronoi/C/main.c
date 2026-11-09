#include "geometry.h"
static const char *section_names[] = {
    "input",         "summary", "insertions", "triangles",     "edges",         "hull",
    "convex_layers", "quality", "vertices",   "voronoi_edges", "cells",         "nearest",
    "components",    "mst",     "proximity",  "degrees",       "empty_circle",  "extent",
    "spanner",       "alpha",   "sites",      "queries",       "delaunay_plot", "voronoi_plot"};
enum {
    SINPUT,
    SUMMARY,
    INSERTIONS,
    TRIANGLES,
    EDGES,
    HULL,
    LAYERS,
    QUALITY,
    VERTICES,
    VORONOI_EDGES,
    CELLS,
    NEAREST,
    COMPONENTS,
    MST,
    PROXIMITY,
    DEGREES,
    EMPTY_CIRCLE,
    EXTENT,
    SPANNER,
    ALPHA,
    SITES,
    QUERIES,
    DELAUNAY_PLOT,
    VORONOI_PLOT
};
static void append_format(Text *out, const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    const int needed = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    const size_t size = out->size + (size_t)needed + 1;
    if (size > out->capacity) {
        out->capacity = size * 2;
        out->data = realloc(out->data, out->capacity);
    }
    vsnprintf(out->data + out->size, out->capacity - out->size, format, args);
    out->size += (size_t)needed;
}
void add(Text *out, const char *format, ...) {
    va_list args;
    va_start(args, format);
    append_format(out, format, args);
    va_end(args);
}
void line(Text *out, const char *format, ...) {
    va_list args;
    va_start(args, format);
    append_format(out, format, args);
    va_end(args);
    add(out, "\n");
}
static const char *real(double value) {
    static char buffers[128][96];
    static unsigned next;
    char *out = buffers[next++ % 128];
    if (fabs(value) < 0.0005)
        value = 0;
    snprintf(out, 96, "%.3f", value);
    return out;
}
static const char *ids(Ints values) {
    static char buffers[16][9600];
    static unsigned next;
    char *out = buffers[next++ % 16];
    size_t length = 0;
    out[0] = 0;
    for (int i = 0; i < values.n; ++i)
        length += (size_t)snprintf(out + length, 9600 - length, "%s%d", i ? " " : "", values.v[i] + 1);
    return out;
}
static const char *triangle_text(Triangle t) {
    static char buffers[32][48];
    static unsigned next;
    char *out = buffers[next++ % 32];
    snprintf(out, 48, "%d %d %d", t.a + 1, t.b + 1, t.c + 1);
    return out;
}
static const char *optional_id(int value) {
    static char buffers[32][24];
    static unsigned next;
    if (value < 0)
        return "-";
    char *out = buffers[next++ % 32];
    snprintf(out, 24, "%d", value + 1);
    return out;
}
typedef struct {
    int n;
    char *v[64];
} Words;
static Words words(char *text) {
    Words out = {0};
    char *word = strtok(text, " ");
    while (word) {
        out.v[out.n++] = word;
        word = strtok(NULL, " ");
    }
    return out;
}
static bool integer_word(const char *word) {
    int begin = word[0] == '-' ? 1 : 0;
    if (!word[begin])
        return false;
    for (int i = begin; word[i]; ++i)
        if (word[i] < '0' || word[i] > '9')
            return false;
    return true;
}
typedef struct {
    char **v;
    int n;
} Strings;
static void strings_add(Strings *values, const char *text) {
    const size_t length = strlen(text) + 1;
    char *copy = malloc(length);
    memcpy(copy, text, length);
    values->v = realloc(values->v, (size_t)(values->n + 1) * sizeof *values->v);
    values->v[values->n++] = copy;
}
static Ints hull_of(const Point *points, Ints sites) {
    if (sites.n < 3)
        return sites;
    for (int i = 1; i < sites.n; ++i) {
        const int value = sites.v[i];
        int position = i;
        while (position > 0) {
            const Point a = points[value], b = points[sites.v[position - 1]];
            if (!(a.x < b.x || (a.x == b.x && a.y < b.y)))
                break;
            sites.v[position] = sites.v[position - 1];
            --position;
        }
        sites.v[position] = value;
    }
    Ints lower = {0}, upper = {0};
    for (int i = 0; i < sites.n; ++i) {
        const int site = sites.v[i];
        while (lower.n >= 2 &&
               orient(points[lower.v[lower.n - 2]], points[lower.v[lower.n - 1]], points[site]) <= 0)
            --lower.n;
        lower.v[lower.n++] = site;
    }
    for (int i = sites.n - 1; i >= 0; --i) {
        const int site = sites.v[i];
        while (upper.n >= 2 &&
               orient(points[upper.v[upper.n - 2]], points[upper.v[upper.n - 1]], points[site]) <= 0)
            --upper.n;
        upper.v[upper.n++] = site;
    }
    --lower.n;
    --upper.n;
    for (int i = 0; i < upper.n; ++i)
        lower.v[lower.n++] = upper.v[i];
    int smallest = 0;
    for (int i = 1; i < lower.n; ++i)
        if (lower.v[i] < lower.v[smallest])
            smallest = i;
    Ints out = {.n = lower.n};
    for (int i = 0; i < lower.n; ++i)
        out.v[i] = lower.v[(smallest + i) % lower.n];
    return out;
}
typedef struct {
    int n, v[3];
} Circle;
static bool contains(Circle circle, const Point *points, int site) {
    if (!circle.n)
        return false;
    if (circle.n == 1)
        return points[site].x == points[circle.v[0]].x && points[site].y == points[circle.v[0]].y;
    if (circle.n == 2)
        return dot(points[site], points[circle.v[0]], points[circle.v[1]]) <= 0;
    return incircle(points[circle.v[0]], points[circle.v[1]], points[circle.v[2]], points[site]) >= 0;
}
static Circle triple(const Point *points, int a, int b, int c) {
    if (orient(points[a], points[b], points[c]) < 0) {
        const int temporary = b;
        b = c;
        c = temporary;
    }
    return (Circle){.n = 3, .v = {a, b, c}};
}
static Circle enclosing(const Point *points, Ints hull) {
    Circle out = {0};
    for (int i = 0; i < hull.n; ++i)
        if (!contains(out, points, hull.v[i])) {
            out = (Circle){.n = 1, .v = {hull.v[i]}};
            for (int j = 0; j < i; ++j)
                if (!contains(out, points, hull.v[j])) {
                    out = (Circle){.n = 2, .v = {hull.v[i], hull.v[j]}};
                    for (int k = 0; k < j; ++k)
                        if (!contains(out, points, hull.v[k]))
                            out = triple(points, hull.v[i], hull.v[j], hull.v[k]);
                }
        }
    return out;
}
static bool on_circle(Circle circle, const Point *points, int site) {
    if (circle.n == 2)
        return dot(points[site], points[circle.v[0]], points[circle.v[1]]) == 0;
    if (circle.n == 3)
        return incircle(points[circle.v[0]], points[circle.v[1]], points[circle.v[2]], points[site]) == 0;
    return contains(circle, points, site);
}
static double route_length(const Point *points, Ints route) {
    double out = 0;
    for (int i = 1; i < route.n; ++i)
        out += sqrt((double)d2(points[route.v[i - 1]], points[route.v[i]]));
    return out;
}
static const char *dual(Edge edge, const Point *points) {
    static char buffers[32][128];
    static unsigned next;
    char *out = buffers[next++ % 32];
    if (edge.left >= 0 && edge.right >= 0)
        snprintf(out, 128, "segment %d %d", edge.left + 1, edge.right + 1);
    else {
        const bool left = edge.left >= 0;
        const Point normal = outward(points[left ? edge.a : edge.b], points[left ? edge.b : edge.a]);
        snprintf(out, 128, "ray %d %lld %lld", (left ? edge.left : edge.right) + 1, (long long)normal.x,
                 (long long)normal.y);
    }
    return out;
}
int main(void) {
    mkdir("output", 0777);
    Point points[400];
    int n = 0, line_count = 0, nrejected = 0;
    Text rejected = {0};
    FILE *file = fopen("input/points.txt", "r");
    char text[2048];
    while (fgets(text, sizeof text, file)) {
        ++line_count;
        text[strcspn(text, "\n")] = 0;
        if (!text[0] || text[0] == '#')
            continue;
        Words fields = words(text);
        if (fields.n != 2 || !integer_word(fields.v[0]) || !integer_word(fields.v[1])) {
            line(&rejected, "reject %d format", line_count);
            ++nrejected;
            continue;
        }
        const Integer x = strtoll(fields.v[0], NULL, 10), y = strtoll(fields.v[1], NULL, 10);
        if (x < 0 || x > 1000 || y < 0 || y > 1000) {
            line(&rejected, "reject %d range", line_count);
            ++nrejected;
            continue;
        }
        int duplicate = -1;
        for (int i = 0; i < n; ++i)
            if (points[i].x == x && points[i].y == y)
                duplicate = i;
        if (duplicate >= 0) {
            line(&rejected, "reject %d duplicate %d", line_count, duplicate + 1);
            ++nrejected;
            continue;
        }
        points[n++] = (Point){x, y};
    }
    fclose(file);
    int width = 61, height = 31;
    Strings plot_layers = {0}, requested = {0}, queries = {0};
    strings_add(&plot_layers, "edges");
    strings_add(&plot_layers, "hull");
    strings_add(&plot_layers, "sites");
    strings_add(&requested, "summary");
    Integer alphas[10];
    int nalphas = 0;
    file = fopen("input/params.txt", "r");
    while (fgets(text, sizeof text, file)) {
        text[strcspn(text, "\n")] = 0;
        if (!text[0] || text[0] == '#')
            continue;
        if (strncmp(text, "query ", 6) == 0) {
            strings_add(&queries, text + 6);
            continue;
        }
        Words fields = words(text);
        if (strcmp(fields.v[0], "plot") == 0) {
            width = atoi(fields.v[1]);
            height = atoi(fields.v[2]);
        } else if (strcmp(fields.v[0], "plot_layers") == 0) {
            for (int i = 0; i < plot_layers.n; ++i)
                free(plot_layers.v[i]);
            free(plot_layers.v);
            plot_layers = (Strings){0};
            for (int i = 1; i < fields.n; ++i)
                strings_add(&plot_layers, fields.v[i]);
        } else if (strcmp(fields.v[0], "sections") == 0) {
            for (int i = 0; i < requested.n; ++i)
                free(requested.v[i]);
            free(requested.v);
            requested = (Strings){0};
            for (int i = 1; i < fields.n; ++i)
                strings_add(&requested, fields.v[i]);
        } else if (strcmp(fields.v[0], "alpha") == 0)
            for (int i = 1; i < fields.n; ++i)
                alphas[nalphas++] = strtoll(fields.v[i], NULL, 10);
    }
    fclose(file);
    Triangulation *t = initialize(points, n);
    const Triangle initial = triangles(t).v[0];
    Insertion insertions[397];
    int ninsertions = 0;
    for (int s = 3; s < n; ++s)
        insertions[ninsertions++] = insert_site(t, points, s);
    const Triangles tris = triangles(t);
    const int count = tris.n;
    int (*triangle_id)[400] = malloc(400 * sizeof *triangle_id),
        (*edge_id)[400] = malloc(400 * sizeof *edge_id);
    for (int a = 0; a < 400; ++a)
        for (int b = 0; b < 400; ++b)
            triangle_id[a][b] = edge_id[a][b] = -1;
    for (int i = 0; i < count; ++i) {
        const Triangle tri = tris.v[i];
        triangle_id[tri.a][tri.b] = triangle_id[tri.b][tri.c] = triangle_id[tri.c][tri.a] = i;
    }
    Edges *edges = calloc(1, sizeof *edges);
    Neighbors *neighbors = calloc(1, sizeof *neighbors),
              *ordered_neighbors = calloc(1, sizeof *ordered_neighbors);
    for (int a = 0; a < n; ++a)
        for (int b = a + 1; b < n; ++b)
            if (third(t, a, b) >= 0 || third(t, b, a) >= 0) {
                edge_id[a][b] = edge_id[b][a] = edges->n;
                edges->v[edges->n++] = (Edge){.a = a,
                                              .b = b,
                                              .left = triangle_id[a][b],
                                              .right = triangle_id[b][a],
                                              .length2 = d2(points[a], points[b])};
                neighbors->v[a].v[neighbors->v[a].n++] = b;
                neighbors->v[b].v[neighbors->v[b].n++] = a;
            }
    int next[400], previous[400];
    for (int s = 0; s < n; ++s)
        next[s] = previous[s] = -1;
    const HullEdges hull_edges_ = hull_edges(t);
    for (int i = 0; i < hull_edges_.n; ++i) {
        const Pair edge = hull_edges_.v[i];
        next[edge.a] = edge.b;
        previous[edge.b] = edge.a;
    }
    int start = 0;
    while (next[start] < 0)
        ++start;
    Ints hull = {0};
    int current = start;
    do {
        hull.v[hull.n++] = current;
        current = next[current];
    } while (current != start);
    for (int s = 0; s < n; ++s)
        ordered_neighbors->v[s] = neighbor_order(t, s, neighbors->v[s], next[s]);
    Center vertices[800];
    double radii[800], minimum_angles[800], maximum_angles[800];
    const char *positions[800], *kinds[800];
    Integer areas[800];
    int acute = 0, right = 0, obtuse = 0, angle_bins[6] = {0};
    for (int i = 0; i < count; ++i) {
        const Triangle tri = tris.v[i];
        const Point a = points[tri.a], b = points[tri.b], c = points[tri.c];
        areas[i] = orient(a, b, c);
        const Integer products[] = {dot(a, b, c), dot(b, c, a), dot(c, a, b)};
        bool zero = false, negative = false;
        for (int k = 0; k < 3; ++k) {
            zero = zero || products[k] == 0;
            negative = negative || products[k] < 0;
        }
        kinds[i] = zero ? "right" : negative ? "obtuse" : "acute";
        acute += strcmp(kinds[i], "acute") == 0;
        right += strcmp(kinds[i], "right") == 0;
        obtuse += strcmp(kinds[i], "obtuse") == 0;
        minimum_angles[i] = INFINITY;
        maximum_angles[i] = 0;
        for (int k = 0; k < 3; ++k) {
            const double angle = atan2((double)areas[i], (double)products[k]) * 180 / acos(-1.0);
            minimum_angles[i] = fmin(minimum_angles[i], angle);
            maximum_angles[i] = fmax(maximum_angles[i], angle);
        }
        ++angle_bins[(int)floor(minimum_angles[i] / 10)];
        vertices[i] = center(a, b, c);
        radii[i] = radius2(a, b, c);
        positions[i] = position(vertices[i], points, hull);
    }
    Ints *cell_vertices = calloc((size_t)n, sizeof *cell_vertices);
    double cell_areas[400] = {0}, clips[400], total_area = 0, clip_total = 0;
    int largest = -1;
    for (int s = 0; s < n; ++s) {
        const Ints order = ordered_neighbors->v[s];
        for (int k = 0; k < order.n; ++k)
            if (triangle_id[s][order.v[k]] >= 0)
                cell_vertices[s].v[cell_vertices[s].n++] = triangle_id[s][order.v[k]];
        if (next[s] < 0) {
            cell_areas[s] = cell_area(points[s], vertices, cell_vertices[s]);
            total_area += cell_areas[s];
            if (largest < 0 || cell_areas[s] > cell_areas[largest])
                largest = s;
        }
        clips[s] = clipped_area(points, s, order);
        clip_total += clips[s];
    }
    const Ints nn = nearest(points, neighbors, n);
    Disjoint nn_sets = disjoint(n);
    int mutual = 0;
    for (int s = 0; s < n; ++s) {
        join(&nn_sets, s, nn.v[s]);
        mutual += s < nn.v[s] && nn.v[nn.v[s]] == s;
    }
    int component_ids[400], component[400];
    for (int s = 0; s < n; ++s)
        component_ids[s] = -1;
    Ints *components = calloc((size_t)n, sizeof *components);
    int ncomponents = 0;
    for (int s = 0; s < n; ++s) {
        const int root = find(&nn_sets, s);
        if (component_ids[root] < 0)
            component_ids[root] = ncomponents++;
        component[s] = component_ids[root];
        components[component[s]].v[components[component[s]].n++] = s;
    }
    const Ints mst = kruskal(edges, n);
    double mst_length = 0;
    for (int i = 0; i < mst.n; ++i)
        mst_length += sqrt((double)edges->v[mst.v[i]].length2);
    int gg = 0, rng = 0, gg_degree[400] = {0}, rng_degree[400] = {0}, mst_degree[400] = {0};
    for (int i = 0; i < edges->n; ++i) {
        Edge *edge = &edges->v[i];
        edge->gabriel = gabriel(points, t, edge->a, edge->b);
        edge->rng = relative_neighborhood(points, n, edge->a, edge->b);
        gg += edge->gabriel;
        rng += edge->rng;
        const int sites[] = {edge->a, edge->b};
        for (int k = 0; k < 2; ++k) {
            const int s = sites[k];
            gg_degree[s] += edge->gabriel;
            rng_degree[s] += edge->rng;
            mst_degree[s] += edge->mst;
        }
    }
    int empty = -1, candidates = 0;
    for (int i = 0; i < count; ++i)
        if (strcmp(positions[i], "inside") == 0) {
            ++candidates;
            if (empty < 0 || radii[i] > radii[empty])
                empty = i;
        }
    Pair diameter = {0, 1};
    Integer diameter2 = d2(points[0], points[1]);
    for (int a = 0; a < n - 1; ++a)
        for (int b = a + 1; b < n; ++b)
            if (d2(points[a], points[b]) > diameter2) {
                diameter = (Pair){a, b};
                diameter2 = d2(points[a], points[b]);
            }
    double width_value = INFINITY;
    int width_edge = 0;
    for (int k = 0; k < hull.n; ++k) {
        Integer maximum = 0;
        for (int i = 0; i < hull.n; ++i) {
            const Integer value =
                orient(points[hull.v[k]], points[hull.v[(k + 1) % hull.n]], points[hull.v[i]]);
            if (value > maximum)
                maximum = value;
        }
        const double value =
            (double)maximum / sqrt((double)d2(points[hull.v[k]], points[hull.v[(k + 1) % hull.n]]));
        if (value < width_value) {
            width_value = value;
            width_edge = k;
        }
    }
    const Circle enclosing_circle = enclosing(points, hull);
    Ints enclosing_sites = {0};
    for (int s = 0; s < n; ++s)
        if (on_circle(enclosing_circle, points, s))
            enclosing_sites.v[enclosing_sites.n++] = s;
    Pair diameter_support = {-1, -1};
    for (int a = 0; a < enclosing_sites.n - 1; ++a)
        for (int b = a + 1; b < enclosing_sites.n; ++b) {
            bool all = true;
            for (int k = 0; k < enclosing_sites.n; ++k)
                all = all && dot(points[enclosing_sites.v[k]], points[enclosing_sites.v[a]],
                                 points[enclosing_sites.v[b]]) == 0;
            if (all && diameter_support.a < 0)
                diameter_support = (Pair){enclosing_sites.v[a], enclosing_sites.v[b]};
        }
    Center enclosing_center;
    double enclosing_radius2;
    if (diameter_support.a >= 0) {
        const Point a = points[diameter_support.a], b = points[diameter_support.b];
        enclosing_center = (Center){a.x + b.x, a.y + b.y, 2};
        enclosing_radius2 = (double)d2(a, b) / 4;
    } else {
        const Circle support =
            triple(points, enclosing_sites.v[0], enclosing_sites.v[1], enclosing_sites.v[2]);
        const Point a = points[support.v[0]], b = points[support.v[1]], c = points[support.v[2]];
        enclosing_center = center(a, b, c);
        enclosing_radius2 = radius2(a, b, c);
    }
    Ints *convex_layers = calloc((size_t)n, sizeof *convex_layers);
    int nlayers = 0, depth[400] = {0};
    Ints remaining = {.n = n};
    for (int s = 0; s < n; ++s)
        remaining.v[s] = s;
    while (remaining.n) {
        const Ints layer = hull_of(points, remaining);
        convex_layers[nlayers++] = layer;
        for (int k = 0; k < layer.n; ++k)
            depth[layer.v[k]] = nlayers;
        Ints rest = {0};
        for (int k = 0; k < remaining.n; ++k)
            if (!depth[remaining.v[k]])
                rest.v[rest.n++] = remaining.v[k];
        remaining = rest;
    }
    Paths *paths = malloc((size_t)n * sizeof *paths);
    for (int s = 0; s < n; ++s)
        paths[s] = dijkstra(points, neighbors, n, s);
    double stretch_sum = 0, max_stretch = -1;
    Pair stretch_pair = {0, 1};
    for (int a = 0; a < n - 1; ++a)
        for (int b = a + 1; b < n; ++b) {
            const double value = paths[a].distance[b] / sqrt((double)d2(points[a], points[b]));
            stretch_sum += value;
            if (value > max_stretch) {
                max_stretch = value;
                stretch_pair = (Pair){a, b};
            }
        }
    Text sections[24] = {0};
    Text *out = &sections[SINPUT];
    line(out, "lines %d", line_count);
    line(out, "accepted %d", n);
    line(out, "rejected %d", nrejected);
    if (rejected.data)
        add(out, "%s", rejected.data);
    out = &sections[SUMMARY];
    int flips = 0, outside = 0, maximum_insertion = -1;
    for (int i = 0; i < ninsertions; ++i) {
        flips += insertions[i].flips;
        outside += !insertions[i].inside;
        if (maximum_insertion < 0 || insertions[i].flips > insertions[maximum_insertion].flips)
            maximum_insertion = i;
    }
    line(out, "sites %d", n);
    line(out, "triangles %d", count);
    line(out, "edges %d", edges->n);
    line(out, "hull_vertices %d", hull.n);
    line(out, "interior_sites %d", n - hull.n);
    line(out, "euler %d", n - edges->n + count);
    line(out, "flips %d", flips);
    line(out, "outside_insertions %d", outside);
    if (maximum_insertion < 0)
        line(out, "max_flips none");
    else
        line(out, "max_flips %d %d", insertions[maximum_insertion].site + 1,
             insertions[maximum_insertion].flips);
    line(out, "acute %d", acute);
    line(out, "right %d", right);
    line(out, "obtuse %d", obtuse);
    out = &sections[INSERTIONS];
    line(out, "init %s", triangle_text(initial));
    for (int i = 0; i < ninsertions; ++i) {
        const Insertion insertion = insertions[i];
        add(out, "insert %d ", insertion.site + 1);
        if (insertion.inside)
            add(out, "inside %s", triangle_text(insertion.containing));
        else
            add(out, "outside %d", insertion.visible);
        line(out, " flips %d triangles %d hull %d", insertion.flips, insertion.triangles, insertion.hull);
    }
    out = &sections[TRIANGLES];
    for (int i = 0; i < count; ++i) {
        const Triangle tri = tris.v[i];
        line(out, "tri %d %s area2 %lld %s adj %s %s %s", i + 1, triangle_text(tri), (long long)areas[i],
             kinds[i], optional_id(triangle_id[tri.c][tri.b]), optional_id(triangle_id[tri.a][tri.c]),
             optional_id(triangle_id[tri.b][tri.a]));
    }
    out = &sections[EDGES];
    for (int i = 0; i < edges->n; ++i) {
        const Edge edge = edges->v[i];
        line(out, "edge %d %d %s len2 %lld left %s right %s", edge.a + 1, edge.b + 1,
             edge.left >= 0 && edge.right >= 0 ? "inner" : "hull", (long long)edge.length2,
             optional_id(edge.left), optional_id(edge.right));
    }
    out = &sections[HULL];
    double perimeter = 0;
    Integer hull_area = 0;
    for (int k = 0; k < hull.n; ++k) {
        const Point a = points[hull.v[k]], b = points[hull.v[(k + 1) % hull.n]];
        perimeter += sqrt((double)d2(a, b));
        hull_area += a.x * b.y - b.x * a.y;
    }
    line(out, "hull_vertices %d", hull.n);
    line(out, "order %s", ids(hull));
    line(out, "perimeter %s", real(perimeter));
    line(out, "area2 %lld", (long long)hull_area);
    out = &sections[LAYERS];
    line(out, "layers %d", nlayers);
    for (int i = 0; i < nlayers; ++i)
        line(out, "layer %d size %d sites %s", i + 1, convex_layers[i].n, ids(convex_layers[i]));
    out = &sections[QUALITY];
    int min_triangle = 0, max_triangle = 0;
    double minimum_sum = 0;
    for (int i = 0; i < count; ++i) {
        if (minimum_angles[i] < minimum_angles[min_triangle])
            min_triangle = i;
        if (maximum_angles[i] > maximum_angles[max_triangle])
            max_triangle = i;
        minimum_sum += minimum_angles[i];
    }
    line(out, "min_angle %s tri %d", real(minimum_angles[min_triangle]), min_triangle + 1);
    line(out, "max_angle %s tri %d", real(maximum_angles[max_triangle]), max_triangle + 1);
    line(out, "mean_min_angle %s", real(minimum_sum / count));
    for (int bin = 0; bin < 6; ++bin)
        line(out, "bin %d %d %d", bin * 10, (bin + 1) * 10, angle_bins[bin]);
    out = &sections[VERTICES];
    const char *position_names[] = {"inside", "on", "outside"};
    for (int kind = 0; kind < 3; ++kind) {
        int total = 0;
        for (int i = 0; i < count; ++i)
            total += strcmp(positions[i], position_names[kind]) == 0;
        line(out, "%s %d", position_names[kind], total);
    }
    for (int i = 0; i < count; ++i)
        line(out, "v %d %s %s r %s %s", i + 1, fraction(vertices[i].x, vertices[i].d),
             fraction(vertices[i].y, vertices[i].d), real(sqrt(radii[i])), positions[i]);
    out = &sections[VORONOI_EDGES];
    line(out, "segments %d", edges->n - hull.n);
    line(out, "rays %d", hull.n);
    for (int i = 0; i < edges->n; ++i)
        line(out, "ve %d %d %s", edges->v[i].a + 1, edges->v[i].b + 1, dual(edges->v[i], points));
    out = &sections[CELLS];
    line(out, "bounded %d", n - hull.n);
    line(out, "unbounded %d", hull.n);
    line(out, "total_area %s", real(total_area));
    line(out, "clip_total %s", real(clip_total));
    if (largest < 0)
        line(out, "largest none");
    else
        line(out, "largest %d area %s", largest + 1, real(cell_areas[largest]));
    for (int s = 0; s < n; ++s) {
        if (next[s] < 0)
            line(out, "cell %d bounded %d area %s clip %s vertices %s", s + 1, cell_vertices[s].n,
                 real(cell_areas[s]), real(clips[s]), ids(cell_vertices[s]));
        else {
            const Point incoming = outward(points[s], points[next[s]]),
                        outgoing = outward(points[previous[s]], points[s]);
            line(out, "cell %d unbounded %d clip %s from %lld %lld vertices %s to %lld %lld", s + 1,
                 cell_vertices[s].n, real(clips[s]), (long long)incoming.x, (long long)incoming.y,
                 ids(cell_vertices[s]), (long long)outgoing.x, (long long)outgoing.y);
        }
    }
    out = &sections[NEAREST];
    int closest = 0;
    for (int i = 1; i < edges->n; ++i)
        if (edges->v[i].length2 < edges->v[closest].length2)
            closest = i;
    line(out, "mutual_pairs %d", mutual);
    line(out, "closest_pair %d %d d2 %lld", edges->v[closest].a + 1, edges->v[closest].b + 1,
         (long long)edges->v[closest].length2);
    for (int s = 0; s < n; ++s)
        line(out, "nn %d %d d2 %lld %s", s + 1, nn.v[s] + 1, (long long)d2(points[s], points[nn.v[s]]),
             nn.v[nn.v[s]] == s ? "mutual" : "-");
    out = &sections[COMPONENTS];
    line(out, "components %d", ncomponents);
    for (int i = 0; i < ncomponents; ++i) {
        Pair pair = {0, 0};
        for (int k = 0; k < components[i].n; ++k) {
            const int s = components[i].v[k];
            if (s < nn.v[s] && nn.v[nn.v[s]] == s)
                pair = (Pair){s, nn.v[s]};
        }
        line(out, "component %d size %d pair %d %d sites %s", i + 1, components[i].n, pair.a + 1, pair.b + 1,
             ids(components[i]));
    }
    out = &sections[MST];
    const Edge longest = edges->v[mst.v[mst.n - 1]];
    line(out, "edges %d", mst.n);
    line(out, "total_length %s", real(mst_length));
    line(out, "longest %d %d len2 %lld", longest.a + 1, longest.b + 1, (long long)longest.length2);
    for (int k = 0; k < mst.n; ++k) {
        const Edge edge = edges->v[mst.v[k]];
        line(out, "mst %d %d len2 %lld", edge.a + 1, edge.b + 1, (long long)edge.length2);
    }
    out = &sections[PROXIMITY];
    line(out, "delaunay %d", edges->n);
    line(out, "gabriel %d", gg);
    line(out, "rng %d", rng);
    line(out, "mst %d", mst.n);
    line(out, "nn %d", n - mutual);
    for (int i = 0; i < edges->n; ++i) {
        const Edge edge = edges->v[i];
        if (edge.rng && !edge.mst)
            line(out, "rng_extra %d %d len2 %lld", edge.a + 1, edge.b + 1, (long long)edge.length2);
    }
    out = &sections[DEGREES];
    int degree_counts[400] = {0}, mindegree = neighbors->v[0].n, maxdegree = mindegree;
    for (int s = 0; s < n; ++s) {
        const int degree = neighbors->v[s].n;
        ++degree_counts[degree];
        if (degree < mindegree)
            mindegree = degree;
        if (degree > maxdegree)
            maxdegree = degree;
    }
    line(out, "min %d", mindegree);
    line(out, "max %d", maxdegree);
    for (int degree = mindegree; degree <= maxdegree; ++degree)
        if (degree_counts[degree])
            line(out, "degree %d count %d", degree, degree_counts[degree]);
    out = &sections[EMPTY_CIRCLE];
    line(out, "candidates %d", candidates);
    if (empty < 0)
        line(out, "none");
    else {
        line(out, "vertex %d", empty + 1);
        line(out, "center %s %s", fraction(vertices[empty].x, vertices[empty].d),
             fraction(vertices[empty].y, vertices[empty].d));
        line(out, "radius %s", real(sqrt(radii[empty])));
        line(out, "sites %s", triangle_text(tris.v[empty]));
    }
    out = &sections[EXTENT];
    line(out, "diameter %d %d d2 %lld", diameter.a + 1, diameter.b + 1, (long long)diameter2);
    line(out, "width %s edge %d %d", real(width_value), hull.v[width_edge] + 1,
         hull.v[(width_edge + 1) % hull.n] + 1);
    line(out, "enclosing_center %s %s", fraction(enclosing_center.x, enclosing_center.d),
         fraction(enclosing_center.y, enclosing_center.d));
    line(out, "enclosing_radius %s", real(sqrt(enclosing_radius2)));
    line(out, "enclosing_sites %s", ids(enclosing_sites));
    out = &sections[SPANNER];
    line(out, "pairs %d", n * (n - 1) / 2);
    line(out, "max_stretch %s pair %d %d length %s distance %s", real(max_stretch), stretch_pair.a + 1,
         stretch_pair.b + 1, real(paths[stretch_pair.a].distance[stretch_pair.b]),
         real(sqrt((double)d2(points[stretch_pair.a], points[stretch_pair.b]))));
    line(out, "mean_stretch %s", real(stretch_sum / (n * (n - 1) / 2)));
    out = &sections[ALPHA];
    for (int k = 0; k < nalphas; ++k) {
        const Integer alpha = alphas[k];
        bool selected[800] = {0}, active[400] = {0};
        int faces = 0, selected_edges = 0, boundary = 0, dangling = 0, components_count = n;
        Integer area = 0;
        for (int i = 0; i < count; ++i)
            if (radii[i] <= alpha) {
                selected[i] = true;
                ++faces;
                area += areas[i];
            }
        Disjoint sets = disjoint(n);
        for (int i = 0; i < edges->n; ++i) {
            const Edge edge = edges->v[i];
            const int adjacent =
                (edge.left >= 0 && selected[edge.left]) + (edge.right >= 0 && selected[edge.right]);
            if (!adjacent && !(edge.gabriel && edge.length2 <= 4 * alpha))
                continue;
            ++selected_edges;
            boundary += adjacent == 1;
            dangling += adjacent == 0;
            active[edge.a] = active[edge.b] = true;
            components_count -= join(&sets, edge.a, edge.b);
        }
        int isolated = 0;
        for (int s = 0; s < n; ++s)
            isolated += !active[s];
        line(
            out,
            "alpha %lld triangles %d edges %d boundary %d dangling %d isolated %d components %d holes %d area2 %lld",
            (long long)alpha, faces, selected_edges, boundary, dangling, isolated, components_count,
            components_count - (n - selected_edges + faces), (long long)area);
    }
    out = &sections[SITES];
    for (int s = 0; s < n; ++s)
        line(out, "site %d %lld %lld %s dt %d gg %d rng %d mst %d nn %d comp %d depth %d", s + 1,
             (long long)points[s].x, (long long)points[s].y, next[s] >= 0 ? "hull" : "inner",
             neighbors->v[s].n, gg_degree[s], rng_degree[s], mst_degree[s], nn.v[s] + 1, component[s] + 1,
             depth[s]);
    out = &sections[QUERIES];
    for (int query = 0; query < queries.n; ++query) {
        const char *original = queries.v[query];
        char buffer[2048];
        strcpy(buffer, original);
        const Words fields = words(buffer);
        const char *kind = fields.v[0];
        add(out, "%s ", original);
        if (strcmp(kind, "locate") == 0 || strcmp(kind, "walk") == 0 || strcmp(kind, "natural") == 0) {
            const Point q = {strtoll(fields.v[1], NULL, 10), strtoll(fields.v[2], NULL, 10)};
            if (strcmp(kind, "locate") == 0) {
                Text place = {0};
                bool found = false;
                for (int s = 0; s < n; ++s)
                    if (d2(points[s], q) == 0) {
                        add(&place, "vertex %d", s + 1);
                        found = true;
                        break;
                    }
                if (!found)
                    for (int i = 0; i < edges->n; ++i) {
                        const Edge edge = edges->v[i];
                        if (orient(points[edge.a], points[edge.b], q) == 0 &&
                            dot(q, points[edge.a], points[edge.b]) < 0) {
                            add(&place, "edge %d %d", edge.a + 1, edge.b + 1);
                            found = true;
                            break;
                        }
                    }
                if (!found)
                    for (int i = 0; i < count; ++i) {
                        const Triangle tri = tris.v[i];
                        if (orient(points[tri.a], points[tri.b], q) > 0 &&
                            orient(points[tri.b], points[tri.c], q) > 0 &&
                            orient(points[tri.c], points[tri.a], q) > 0) {
                            add(&place, "triangle %s", triangle_text(tri));
                            found = true;
                            break;
                        }
                    }
                if (!found)
                    add(&place, "outside");
                int nearest_ = 0;
                for (int s = 1; s < n; ++s)
                    if (d2(points[s], q) < d2(points[nearest_], q))
                        nearest_ = s;
                add(out, "%s nearest %d d2 %lld", place.data, nearest_ + 1,
                    (long long)d2(points[nearest_], q));
                free(place.data);
            } else if (strcmp(kind, "walk") == 0) {
                const Walk walk = visibility_walk(t, points, q);
                add(out, "steps %d ", walk.path.n - 1);
                if (walk.outside)
                    add(out, "outside %d %d", walk.edge.a + 1, walk.edge.b + 1);
                else
                    add(out, "triangle %d", walk.path.v[walk.path.n - 1] + 1);
                add(out, " path %s", ids(walk.path));
            } else {
                int triangle_count = 0;
                bool present[400] = {0};
                for (int i = 0; i < count; ++i) {
                    const Triangle tri = tris.v[i];
                    if (incircle(points[tri.a], points[tri.b], points[tri.c], q) > 0) {
                        ++triangle_count;
                        present[tri.a] = present[tri.b] = present[tri.c] = true;
                    }
                }
                Ints sites = {0};
                for (int s = 0; s < n; ++s)
                    if (present[s])
                        sites.v[sites.n++] = s;
                add(out, "triangles %d sites %s", triangle_count, sites.n ? ids(sites) : "-");
            }
        } else {
            const int a = atoi(fields.v[1]) - 1,
                      b = strcmp(kind, "neighbors") == 0 ? a : atoi(fields.v[2]) - 1;
            if (a < 0 || a >= n || b < 0 || b >= n)
                add(out, "error unknown_site");
            else if (strcmp(kind, "neighbors") == 0)
                add(out, "degree %d sites %s", neighbors->v[a].n, ids(ordered_neighbors->v[a]));
            else if (strcmp(kind, "route") == 0) {
                const Ints route = greedy_route(points, neighbors, a, b);
                add(out, "hops %d length %s path %s", route.n - 1, real(route_length(points, route)),
                    ids(route));
            } else if (strcmp(kind, "path") == 0) {
                Ints route = {0};
                int cursor = b;
                while (cursor >= 0) {
                    route.v[route.n++] = cursor;
                    if (cursor == a)
                        break;
                    cursor = paths[a].previous[cursor];
                }
                for (int i = 0; i < route.n / 2; ++i) {
                    const int temporary = route.v[i];
                    route.v[i] = route.v[route.n - 1 - i];
                    route.v[route.n - 1 - i] = temporary;
                }
                add(out, "length %s stretch %s hops %d sites %s", real(paths[a].distance[b]),
                    a == b ? "-" : real(paths[a].distance[b] / sqrt((double)d2(points[a], points[b]))),
                    route.n - 1, ids(route));
            } else if (a == b)
                add(out, "error same_site");
            else if (edge_id[a][b] >= 0) {
                const Edge edge = edges->v[edge_id[a][b]];
                add(out, "delaunay len2 %lld gabriel %s rng %s mst %s dual %s", (long long)edge.length2,
                    edge.gabriel ? "yes" : "no", edge.rng ? "yes" : "no", edge.mst ? "yes" : "no",
                    dual(edge, points));
            } else {
                int crossings[1200], ncrossings = 0;
                for (int i = 0; i < edges->n; ++i) {
                    const Edge edge = edges->v[i];
                    if (orient(points[a], points[b], points[edge.a]) *
                                orient(points[a], points[b], points[edge.b]) <
                            0 &&
                        orient(points[edge.a], points[edge.b], points[a]) *
                                orient(points[edge.a], points[edge.b], points[b]) <
                            0)
                        crossings[ncrossings++] = i;
                }
                add(out, "missing crossings %d", ncrossings);
                for (int i = 0; i < ncrossings; ++i) {
                    const Edge edge = edges->v[crossings[i]];
                    add(out, " %d-%d", edge.a + 1, edge.b + 1);
                }
            }
        }
        line(out, "");
    }
    Grid delaunay = canvas(width, height);
    for (int layer = 0; layer < plot_layers.n; ++layer) {
        const char *name = plot_layers.v[layer];
        if (strcmp(name, "edges") == 0) {
            for (int i = 0; i < edges->n; ++i) {
                const Edge edge = edges->v[i];
                draw_line(&delaunay, map_point(points[edge.a], width, height),
                          map_point(points[edge.b], width, height), '.');
            }
        } else if (strcmp(name, "mst") == 0) {
            for (int i = 0; i < mst.n; ++i) {
                const Edge edge = edges->v[mst.v[i]];
                draw_line(&delaunay, map_point(points[edge.a], width, height),
                          map_point(points[edge.b], width, height), '*');
            }
        } else if (strcmp(name, "hull") == 0) {
            for (int i = 0; i < hull.n; ++i)
                draw_line(&delaunay, map_point(points[hull.v[i]], width, height),
                          map_point(points[hull.v[(i + 1) % hull.n]], width, height), '#');
        } else if (strcmp(name, "sites") == 0) {
            for (int s = 0; s < n; ++s) {
                const Pair cell = map_point(points[s], width, height);
                delaunay.cells[cell.b][cell.a] = 'o';
            }
        } else if (strcmp(name, "circle") == 0 && empty >= 0) {
            const Pair cell = map_center(vertices[empty], width, height);
            delaunay.cells[cell.b][cell.a] = '@';
        }
    }
    framed(&sections[DELAUNAY_PLOT], &delaunay);
    const Grid voronoi = voronoi_plot(points, n, width, height);
    framed(&sections[VORONOI_PLOT], &voronoi);
    const char *paths_[] = {"output/triangulation.txt", "output/voronoi.txt", "output/derived.txt",
                            "output/plot.txt"};
    FILE *files[4];
    for (int i = 0; i < 4; ++i)
        files[i] = fopen(paths_[i], "wb");
    for (int k = 0; k < requested.n; ++k) {
        int section = 0;
        while (strcmp(section_names[section], requested.v[k]) != 0)
            ++section;
        const int target = section <= QUALITY ? 0 : section <= CELLS ? 1 : section >= DELAUNAY_PLOT ? 3 : 2;
        fprintf(files[target], "[%s]\n", section_names[section]);
        if (sections[section].size)
            fwrite(sections[section].data, 1, sections[section].size, files[target]);
    }
    for (int i = 0; i < 4; ++i)
        fclose(files[i]);
    for (int i = 0; i < 24; ++i)
        free(sections[i].data);
    for (int i = 0; i < plot_layers.n; ++i)
        free(plot_layers.v[i]);
    free(plot_layers.v);
    for (int i = 0; i < requested.n; ++i)
        free(requested.v[i]);
    free(requested.v);
    for (int i = 0; i < queries.n; ++i)
        free(queries.v[i]);
    free(queries.v);
    free(rejected.data);
    free(t);
    free(triangle_id);
    free(edge_id);
    free(edges);
    free(neighbors);
    free(ordered_neighbors);
    free(cell_vertices);
    free(components);
    free(convex_layers);
    free(paths);
    return 0;
}
