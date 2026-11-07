#include "geometry.h"
static void edge_set(Triangulation *t, int a, int b, int value) {
    if (t->directed[a][b] < 0)
        ++t->entries;
    t->directed[a][b] = value;
}
void triangle_add(Triangulation *t, int a, int b, int c) {
    edge_set(t, a, b, c);
    edge_set(t, b, c, a);
    edge_set(t, c, a, b);
}
static void edge_remove(Triangulation *t, int a, int b) {
    if (t->directed[a][b] >= 0)
        --t->entries;
    t->directed[a][b] = -1;
}
void triangle_remove(Triangulation *t, int a, int b, int c) {
    edge_remove(t, a, b);
    edge_remove(t, b, c);
    edge_remove(t, c, a);
}
int third(const Triangulation *t, int a, int b) {
    return t->directed[a][b];
}
Triangles triangles(const Triangulation *t) {
    Triangles out = {0};
    for (int a = 0; a < t->size; ++a)
        for (int b = a + 1; b < t->size; ++b) {
            const int c = t->directed[a][b];
            if (c > a)
                out.v[out.n++] = (Triangle){a, b, c};
        }
    return out;
}
HullEdges hull_edges(const Triangulation *t) {
    HullEdges out = {0};
    for (int a = 0; a < t->size; ++a)
        for (int b = 0; b < t->size; ++b)
            if (t->directed[a][b] >= 0 && t->directed[b][a] < 0)
                out.v[out.n++] = (Pair){a, b};
    return out;
}
Triangulation *initialize(const Point *points, int n) {
    Triangulation *out = malloc(sizeof *out);
    out->size = n;
    out->entries = 0;
    for (int a = 0; a < 400; ++a)
        for (int b = 0; b < 400; ++b)
            out->directed[a][b] = -1;
    if (orient(points[0], points[1], points[2]) > 0)
        triangle_add(out, 0, 1, 2);
    else
        triangle_add(out, 0, 2, 1);
    return out;
}
typedef struct {
    Pair *v;
    int n, capacity;
} Pending;
static void pending_add(Pending *p, Pair value) {
    for (int i = 0; i < p->n; ++i)
        if (p->v[i].a == value.a && p->v[i].b == value.b)
            return;
    if (p->n == p->capacity) {
        p->capacity = p->capacity ? p->capacity * 2 : 16;
        p->v = realloc(p->v, (size_t)p->capacity * sizeof *p->v);
    }
    p->v[p->n++] = value;
}
static Pair pending_pop(Pending *p) {
    int smallest = 0;
    for (int i = 1; i < p->n; ++i)
        if (p->v[i].a < p->v[smallest].a || (p->v[i].a == p->v[smallest].a && p->v[i].b < p->v[smallest].b))
            smallest = i;
    const Pair out = p->v[smallest];
    p->v[smallest] = p->v[--p->n];
    return out;
}
Insertion insert_site(Triangulation *t, const Point *points, int s) {
    Insertion out = {.site = s};
    Pending pending = {0};
    const Triangles values = triangles(t);
    for (int i = 0; i < values.n; ++i) {
        const Triangle tri = values.v[i];
        if (orient(points[tri.a], points[tri.b], points[s]) > 0 &&
            orient(points[tri.b], points[tri.c], points[s]) > 0 &&
            orient(points[tri.c], points[tri.a], points[s]) > 0) {
            out.inside = true;
            out.containing = tri;
            triangle_remove(t, tri.a, tri.b, tri.c);
            const int sites[] = {tri.a, tri.b, tri.c};
            for (int k = 0; k < 3; ++k) {
                const int a = sites[k], b = sites[(k + 1) % 3];
                triangle_add(t, a, b, s);
                pending_add(&pending, (Pair){a, b});
            }
            break;
        }
    }
    if (!out.inside) {
        const HullEdges hull = hull_edges(t);
        for (int i = 0; i < hull.n; ++i) {
            const Pair edge = hull.v[i];
            if (orient(points[edge.a], points[edge.b], points[s]) < 0) {
                ++out.visible;
                triangle_add(t, edge.b, edge.a, s);
                pending_add(&pending, (Pair){edge.b, edge.a});
            }
        }
    }
    while (pending.n) {
        const Pair edge = pending_pop(&pending);
        const int a = edge.a, b = edge.b;
        if (third(t, a, b) != s)
            continue;
        const int q = third(t, b, a);
        if (q < 0 || incircle(points[a], points[b], points[s], points[q]) <= 0)
            continue;
        triangle_remove(t, a, b, s);
        triangle_remove(t, b, a, q);
        triangle_add(t, a, q, s);
        triangle_add(t, q, b, s);
        pending_add(&pending, (Pair){a, q});
        pending_add(&pending, (Pair){q, b});
        ++out.flips;
    }
    out.triangles = t->entries / 3;
    out.hull = hull_edges(t).n;
    free(pending.v);
    return out;
}
Walk visibility_walk(const Triangulation *t, const Point *points, Point query) {
    const Triangles values = triangles(t);
    int (*ids)[400] = malloc(400 * sizeof *ids);
    for (int a = 0; a < 400; ++a)
        for (int b = 0; b < 400; ++b)
            ids[a][b] = -1;
    for (int i = 0; i < values.n; ++i) {
        const Triangle tri = values.v[i];
        ids[tri.a][tri.b] = ids[tri.b][tri.c] = ids[tri.c][tri.a] = i;
    }
    Walk out = {0};
    int current = 0;
    out.path.v[out.path.n++] = current;
    while (true) {
        const Triangle tri = values.v[current];
        const int sites[] = {tri.a, tri.b, tri.c};
        bool moved = false;
        for (int k = 0; k < 3; ++k) {
            const int a = sites[k], b = sites[(k + 1) % 3];
            if (orient(points[a], points[b], query) >= 0)
                continue;
            if (ids[b][a] < 0) {
                out.outside = true;
                out.edge = (Pair){a < b ? a : b, a < b ? b : a};
                free(ids);
                return out;
            }
            current = ids[b][a];
            out.path.v[out.path.n++] = current;
            moved = true;
            break;
        }
        if (!moved) {
            free(ids);
            return out;
        }
    }
}
