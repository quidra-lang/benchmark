#include "spatial.h"
bool key_less(Point a, Point b, int axis) {
    const Integer first_a = axis ? a.y : a.x, first_b = axis ? b.y : b.x, second_a = axis ? a.x : a.y,
                  second_b = axis ? b.x : b.y;
    return first_a < first_b ||
           (first_a == first_b && (second_a < second_b || (second_a == second_b && a.id < b.id)));
}
static int sort_axis;
static int compare_points(const void *a, const void *b) {
    const Point x = *(const Point *)a, y = *(const Point *)b;
    return key_less(x, y, sort_axis) ? -1 : key_less(y, x, sort_axis) ? 1 : 0;
}
KDNode *kd_build(const Point *points, int n, int depth) {
    if (!n)
        return NULL;
    Point *sorted = malloc((size_t)n * sizeof *sorted);
    memcpy(sorted, points, (size_t)n * sizeof *sorted);
    sort_axis = depth % 2;
    qsort(sorted, (size_t)n, sizeof *sorted, compare_points);
    const int middle = n / 2;
    KDNode *out = calloc(1, sizeof *out);
    out->point = sorted[middle];
    out->depth = depth;
    out->left = kd_build(sorted, middle, depth + 1);
    out->right = kd_build(sorted + middle + 1, n - middle - 1, depth + 1);
    free(sorted);
    return out;
}
void kd_insert(KDNode **node, Point point, int depth) {
    if (!*node) {
        *node = calloc(1, sizeof **node);
        (*node)->point = point;
        (*node)->depth = depth;
        return;
    }
    KDNode *current = *node;
    kd_insert(key_less(point, current->point, current->depth % 2) ? &current->left : &current->right, point,
              current->depth + 1);
}
Point kd_minimum(const KDNode *node, int axis) {
    if (node->depth % 2 == axis)
        return node->left ? kd_minimum(node->left, axis) : node->point;
    Point out = node->point;
    if (node->left) {
        const Point candidate = kd_minimum(node->left, axis);
        if (key_less(candidate, out, axis))
            out = candidate;
    }
    if (node->right) {
        const Point candidate = kd_minimum(node->right, axis);
        if (key_less(candidate, out, axis))
            out = candidate;
    }
    return out;
}
void kd_delete(KDNode **node, Point point) {
    if (!*node)
        return;
    KDNode *current = *node;
    const int axis = current->depth % 2;
    if (current->point.id == point.id) {
        if (current->right) {
            const Point replacement = kd_minimum(current->right, axis);
            current->point = replacement;
            kd_delete(&current->right, replacement);
        } else if (current->left) {
            const Point replacement = kd_minimum(current->left, axis);
            current->point = replacement;
            kd_delete(&current->left, replacement);
            current->right = current->left;
            current->left = NULL;
        } else {
            free(current);
            *node = NULL;
        }
    } else
        kd_delete(key_less(point, current->point, axis) ? &current->left : &current->right, point);
}
void kd_free(KDNode *node) {
    if (!node)
        return;
    kd_free(node->left);
    kd_free(node->right);
    free(node);
}
