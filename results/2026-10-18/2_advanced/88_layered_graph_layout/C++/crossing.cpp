#include "layout.hpp"
Order positions(const Orders &orders, int count) {
    Order out(count);
    for (const Order &row : orders)
        for (std::size_t i = 0; i < row.size(); ++i)
            out[row[i]] = static_cast<int>(i);
    return out;
}
int gapCrossings(const std::vector<Segment> &segments, const Order &indices, const Order &pos,
                 int width) {
    std::vector<std::pair<int, int>> pairs;
    for (int index : indices) {
        const Segment &segment = segments[index];
        pairs.emplace_back(pos[segment.upper], pos[segment.lower]);
    }
    std::sort(pairs.begin(), pairs.end());
    int capacity = 1;
    while (capacity < width)
        capacity *= 2;
    Order tree(2 * capacity - 1);
    int out = 0;
    for (const auto &pair : pairs) {
        int at = pair.second + capacity - 1;
        ++tree[at];
        while (at) {
            if (at % 2)
                out += tree[at + 1];
            at = (at - 1) / 2;
            ++tree[at];
        }
    }
    return out;
}
int totalCrossings(const Layout &layout, const Orders &orders) {
    Order pos = positions(orders, static_cast<int>(layout.vertices.size()));
    int out = 0;
    for (std::size_t i = 0; i < layout.gaps.size(); ++i)
        out += gapCrossings(layout.segments, layout.gaps[i], pos,
                            static_cast<int>(orders[i + 1].size()));
    return out;
}
int bruteCrossings(Layout &layout, const Orders &orders, bool countEdges) {
    Order pos = positions(orders, static_cast<int>(layout.vertices.size()));
    int out = 0;
    for (const Order &indices : layout.gaps)
        for (std::size_t i = 0; i < indices.size(); ++i)
            for (std::size_t j = i + 1; j < indices.size(); ++j) {
                const Segment &a = layout.segments[indices[i]], &b = layout.segments[indices[j]];
                if ((pos[a.upper] - pos[b.upper]) * (pos[a.lower] - pos[b.lower]) < 0) {
                    ++out;
                    if (countEdges) {
                        ++layout.edges[a.edge].crossings;
                        ++layout.edges[b.edge].crossings;
                    }
                }
            }
    return out;
}
int adjacentCost(const Layout &layout, int left, int right, const Order &pos) {
    int out = 0;
    const Vertex &a = layout.vertices[left], &b = layout.vertices[right];
    for (int u : a.upper)
        for (int v : b.upper)
            if (pos[u] > pos[v])
                ++out;
    for (int u : a.lower)
        for (int v : b.lower)
            if (pos[u] > pos[v])
                ++out;
    return out;
}
