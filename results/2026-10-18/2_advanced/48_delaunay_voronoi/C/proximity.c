#include "geometry.h"
Disjoint disjoint(int n) {
    Disjoint out;
    for (int i = 0; i < n; ++i)
        out.parent[i] = i;
    return out;
}
int find(Disjoint *sets, int value) {
    if (sets->parent[value] != value)
        sets->parent[value] = find(sets, sets->parent[value]);
    return sets->parent[value];
}
bool join(Disjoint *sets, int a, int b) {
    a = find(sets, a);
    b = find(sets, b);
    if (a == b)
        return false;
    sets->parent[b] = a;
    return true;
}
Ints nearest(const Point *points, const Neighbors *neighbors, int n) {
    Ints out = {.n = n};
    for (int s = 0; s < n; ++s) {
        const Ints values = neighbors->v[s];
        int best = values.v[0];
        for (int i = 0; i < values.n; ++i) {
            const int t = values.v[i];
            if (d2(points[s], points[t]) < d2(points[s], points[best]) ||
                (d2(points[s], points[t]) == d2(points[s], points[best]) && t < best))
                best = t;
        }
        out.v[s] = best;
    }
    return out;
}
Ints kruskal(Edges *edges, int sites) {
    int order[1200];
    for (int i = 0; i < edges->n; ++i) {
        int position = i;
        while (position > 0 && edges->v[i].length2 < edges->v[order[position - 1]].length2) {
            order[position] = order[position - 1];
            --position;
        }
        order[position] = i;
    }
    Disjoint sets = disjoint(sites);
    Ints out = {0};
    for (int i = 0; i < edges->n; ++i) {
        const int index = order[i];
        Edge *edge = &edges->v[index];
        if (join(&sets, edge->a, edge->b)) {
            edge->mst = true;
            out.v[out.n++] = index;
        }
    }
    return out;
}
bool gabriel(const Point *points, const Triangulation *t, int a, int b) {
    const int left = third(t, a, b), right = third(t, b, a);
    if (left >= 0 && dot(points[left], points[a], points[b]) <= 0)
        return false;
    if (right >= 0 && dot(points[right], points[a], points[b]) <= 0)
        return false;
    return true;
}
bool relative_neighborhood(const Point *points, int n, int a, int b) {
    const Integer length = d2(points[a], points[b]);
    for (int i = 0; i < n; ++i)
        if (d2(points[a], points[i]) < length && d2(points[b], points[i]) < length)
            return false;
    return true;
}
Ints greedy_route(const Point *points, const Neighbors *neighbors, int source, int target) {
    Ints out = {.n = 1, .v = {source}};
    int current = source;
    while (current != target) {
        const Ints values = neighbors->v[current];
        int best = values.v[0];
        for (int i = 0; i < values.n; ++i) {
            const int next = values.v[i];
            if (d2(points[next], points[target]) < d2(points[best], points[target]) ||
                (d2(points[next], points[target]) == d2(points[best], points[target]) && next < best))
                best = next;
        }
        current = best;
        out.v[out.n++] = current;
    }
    return out;
}
Paths dijkstra(const Point *points, const Neighbors *neighbors, int n, int source) {
    Paths out;
    bool visited[400] = {0};
    for (int i = 0; i < n; ++i) {
        out.distance[i] = INFINITY;
        out.previous[i] = -1;
    }
    out.distance[source] = 0;
    for (int iteration = 0; iteration < n; ++iteration) {
        int current = -1;
        for (int v = 0; v < n; ++v)
            if (!visited[v] && (current < 0 || out.distance[v] < out.distance[current]))
                current = v;
        visited[current] = true;
        const Ints values = neighbors->v[current];
        for (int i = 0; i < values.n; ++i) {
            const int next = values.v[i];
            const double value = out.distance[current] + sqrt((double)d2(points[current], points[next]));
            if (value < out.distance[next]) {
                out.distance[next] = value;
                out.previous[next] = current;
            }
        }
    }
    return out;
}
