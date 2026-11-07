#include "spatial.hpp"
int destination(const QuadNode &node, Point point) {
    const Integer half = node.size / 2;
    return (point.y >= node.y + half ? 2 : 0) + (point.x >= node.x + half ? 1 : 0);
}
void quad_insert(QuadNode &node, Point point, int bucket) {
    if (!node.leaf()) {
        quad_insert(*node.children[destination(node, point)], point, bucket);
        return;
    }
    const auto position = std::lower_bound(node.points.begin(), node.points.end(), point.id,
                                           [](Point value, int id) { return value.id < id; });
    node.points.insert(position, point);
    if (int(node.points.size()) <= bucket)
        return;
    const Integer half = node.size / 2;
    for (int i = 0; i < 4; ++i) {
        node.children[i] = std::make_unique<QuadNode>();
        node.children[i]->x = node.x + (i % 2) * half;
        node.children[i]->y = node.y + (i / 2) * half;
        node.children[i]->size = half;
    }
    const std::vector<Point> previous = std::move(node.points);
    node.points.clear();
    for (Point value : previous)
        quad_insert(node, value, bucket);
}
void quad_delete(QuadNode &node, Point point, int bucket) {
    if (node.leaf()) {
        node.points.erase(std::find_if(node.points.begin(), node.points.end(),
                                       [&](Point value) { return value.id == point.id; }));
        return;
    }
    quad_delete(*node.children[destination(node, point)], point, bucket);
    std::size_t count = 0;
    for (const auto &child : node.children) {
        if (!child->leaf())
            return;
        count += child->points.size();
    }
    if (int(count) > bucket)
        return;
    for (auto &child : node.children) {
        node.points.insert(node.points.end(), child->points.begin(), child->points.end());
        child.reset();
    }
    std::sort(node.points.begin(), node.points.end(), [](Point a, Point b) { return a.id < b.id; });
}
