#include "spatial.hpp"
bool key_less(Point a, Point b, int axis) {
    return axis == 0 ? std::tie(a.x, a.y, a.id) < std::tie(b.x, b.y, b.id)
                     : std::tie(a.y, a.x, a.id) < std::tie(b.y, b.x, b.id);
}
std::unique_ptr<KDNode> kd_build(std::vector<Point> points, int depth) {
    if (points.empty())
        return {};
    const int axis = depth % 2;
    std::sort(points.begin(), points.end(), [&](Point a, Point b) { return key_less(a, b, axis); });
    const std::size_t middle = points.size() / 2;
    auto out = std::make_unique<KDNode>();
    out->point = points[middle];
    out->depth = depth;
    out->left = kd_build({points.begin(), points.begin() + middle}, depth + 1);
    out->right = kd_build({points.begin() + middle + 1, points.end()}, depth + 1);
    return out;
}
void kd_insert(std::unique_ptr<KDNode> &node, Point point, int depth) {
    if (!node) {
        node = std::make_unique<KDNode>();
        node->point = point;
        node->depth = depth;
        return;
    }
    kd_insert(key_less(point, node->point, node->depth % 2) ? node->left : node->right, point,
              node->depth + 1);
}
Point kd_minimum(const KDNode &node, int axis) {
    if (node.depth % 2 == axis)
        return node.left ? kd_minimum(*node.left, axis) : node.point;
    Point out = node.point;
    if (node.left) {
        const Point candidate = kd_minimum(*node.left, axis);
        if (key_less(candidate, out, axis))
            out = candidate;
    }
    if (node.right) {
        const Point candidate = kd_minimum(*node.right, axis);
        if (key_less(candidate, out, axis))
            out = candidate;
    }
    return out;
}
void kd_delete(std::unique_ptr<KDNode> &node, Point point) {
    if (!node)
        return;
    const int axis = node->depth % 2;
    if (node->point.id == point.id) {
        if (node->right) {
            const Point replacement = kd_minimum(*node->right, axis);
            node->point = replacement;
            kd_delete(node->right, replacement);
        } else if (node->left) {
            const Point replacement = kd_minimum(*node->left, axis);
            node->point = replacement;
            kd_delete(node->left, replacement);
            node->right = std::move(node->left);
        } else
            node.reset();
    } else
        kd_delete(key_less(point, node->point, axis) ? node->left : node->right, point);
}
