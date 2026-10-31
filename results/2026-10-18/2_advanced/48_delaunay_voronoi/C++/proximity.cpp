#include "geometry.hpp"
Disjoint::Disjoint(int n) : parent(n) {
    std::iota(parent.begin(), parent.end(), 0);
}
int Disjoint::find(int value) {
    if (parent[value] != value)
        parent[value] = find(parent[value]);
    return parent[value];
}
bool Disjoint::join(int a, int b) {
    a = find(a);
    b = find(b);
    if (a == b)
        return false;
    parent[b] = a;
    return true;
}
Ints nearest(const std::vector<Point> &points, const std::vector<Ints> &neighbors) {
    Ints out(points.size());
    for (std::size_t s = 0; s < points.size(); ++s) {
        int best = neighbors[s][0];
        for (int t : neighbors[s])
            if (d2(points[s], points[t]) < d2(points[s], points[best]) ||
                (d2(points[s], points[t]) == d2(points[s], points[best]) && t < best))
                best = t;
        out[s] = best;
    }
    return out;
}
Ints kruskal(std::vector<Edge> &edges, int sites) {
    Ints order(edges.size()), out;
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return edges[a].length2 != edges[b].length2 ? edges[a].length2 < edges[b].length2 : a < b;
    });
    Disjoint sets(sites);
    for (int index : order)
        if (sets.join(edges[index].a, edges[index].b)) {
            edges[index].mst = true;
            out.push_back(index);
        }
    return out;
}
bool gabriel(const std::vector<Point> &points, const Triangulation &triangulation, int a, int b) {
    for (Pair edge : {Pair{a, b}, Pair{b, a}}) {
        const int q = triangulation.third(edge.first, edge.second);
        if (q >= 0 && dot(points[q], points[a], points[b]) <= 0)
            return false;
    }
    return true;
}
bool relative_neighborhood(const std::vector<Point> &points, int a, int b) {
    const Integer length = d2(points[a], points[b]);
    for (Point point : points)
        if (d2(points[a], point) < length && d2(points[b], point) < length)
            return false;
    return true;
}
Ints greedy_route(const std::vector<Point> &points, const std::vector<Ints> &neighbors, int source,
                  int target) {
    Ints out{source};
    int current = source;
    while (current != target) {
        int best = neighbors[current][0];
        for (int next : neighbors[current])
            if (d2(points[next], points[target]) < d2(points[best], points[target]) ||
                (d2(points[next], points[target]) == d2(points[best], points[target]) && next < best))
                best = next;
        current = best;
        out.push_back(current);
    }
    return out;
}
Paths dijkstra(const std::vector<Point> &points, const std::vector<Ints> &neighbors, int source) {
    Paths out;
    out.distance = std::vector<double>(points.size(), std::numeric_limits<double>::infinity());
    out.previous = Ints(points.size(), -1);
    std::vector<bool> visited(points.size());
    out.distance[source] = 0;
    for (std::size_t iteration = 0; iteration < points.size(); ++iteration) {
        int current = -1;
        for (std::size_t v = 0; v < points.size(); ++v)
            if (!visited[v] && (current < 0 || out.distance[v] < out.distance[current]))
                current = v;
        visited[current] = true;
        for (int next : neighbors[current]) {
            const double value = out.distance[current] + std::sqrt(double(d2(points[current], points[next])));
            if (value < out.distance[next]) {
                out.distance[next] = value;
                out.previous[next] = current;
            }
        }
    }
    return out;
}
