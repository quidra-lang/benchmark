#include "geometry.hpp"
void Triangulation::add(int a, int b, int c) {
    directed[{a, b}] = c;
    directed[{b, c}] = a;
    directed[{c, a}] = b;
}
void Triangulation::remove(int a, int b, int c) {
    directed.erase({a, b});
    directed.erase({b, c});
    directed.erase({c, a});
}
int Triangulation::third(int a, int b) const {
    const auto found = directed.find({a, b});
    return found == directed.end() ? -1 : found->second;
}
std::vector<Triangle> Triangulation::triangles() const {
    std::set<Triangle> out;
    for (const auto &entry : directed)
        out.insert(canonical({entry.first.first, entry.first.second, entry.second}));
    return {out.begin(), out.end()};
}
std::vector<Pair> Triangulation::hull_edges() const {
    std::vector<Pair> out;
    for (const auto &entry : directed)
        if (third(entry.first.second, entry.first.first) < 0)
            out.push_back(entry.first);
    return out;
}
Triangulation initialize(const std::vector<Point> &points) {
    Triangulation out;
    if (orient(points[0], points[1], points[2]) > 0)
        out.add(0, 1, 2);
    else
        out.add(0, 2, 1);
    return out;
}
Insertion Triangulation::insert(const std::vector<Point> &points, int s) {
    Insertion out;
    out.site = s;
    std::set<Pair> pending;
    for (const Triangle &t : triangles())
        if (orient(points[t[0]], points[t[1]], points[s]) > 0 &&
            orient(points[t[1]], points[t[2]], points[s]) > 0 &&
            orient(points[t[2]], points[t[0]], points[s]) > 0) {
            out.inside = true;
            out.containing = t;
            remove(t[0], t[1], t[2]);
            for (int k = 0; k < 3; ++k) {
                const int a = t[k], b = t[(k + 1) % 3];
                add(a, b, s);
                pending.insert({a, b});
            }
            break;
        }
    if (!out.inside)
        for (Pair edge : hull_edges())
            if (orient(points[edge.first], points[edge.second], points[s]) < 0) {
                ++out.visible;
                add(edge.second, edge.first, s);
                pending.insert({edge.second, edge.first});
            }
    while (!pending.empty()) {
        const Pair edge = *pending.begin();
        pending.erase(pending.begin());
        const int a = edge.first, b = edge.second;
        if (third(a, b) != s)
            continue;
        const int q = third(b, a);
        if (q < 0 || incircle(points[a], points[b], points[s], points[q]) <= 0)
            continue;
        remove(a, b, s);
        remove(b, a, q);
        add(a, q, s);
        add(q, b, s);
        pending.insert({a, q});
        pending.insert({q, b});
        ++out.flips;
    }
    out.triangles = directed.size() / 3;
    out.hull = hull_edges().size();
    return out;
}
Walk Triangulation::walk(const std::vector<Point> &points, Point query) const {
    const auto values = triangles();
    std::map<Pair, int> ids;
    for (std::size_t i = 0; i < values.size(); ++i)
        for (int k = 0; k < 3; ++k)
            ids[{values[i][k], values[i][(k + 1) % 3]}] = i;
    Walk out;
    int current = 0;
    out.path.push_back(current);
    while (true) {
        const Triangle &t = values[current];
        bool moved = false;
        for (int k = 0; k < 3; ++k) {
            const int a = t[k], b = t[(k + 1) % 3];
            if (orient(points[a], points[b], query) >= 0)
                continue;
            const auto found = ids.find({b, a});
            if (found == ids.end()) {
                out.outside = true;
                out.edge = std::minmax(a, b);
                return out;
            }
            current = found->second;
            out.path.push_back(current);
            moved = true;
            break;
        }
        if (!moved)
            return out;
    }
}
