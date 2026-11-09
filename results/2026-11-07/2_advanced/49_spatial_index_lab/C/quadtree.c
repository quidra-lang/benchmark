#include "spatial.h"
int destination(const QuadNode *node, Point point) {
    const Integer half = node->size / 2;
    return (point.y >= node->y + half ? 2 : 0) + (point.x >= node->x + half ? 1 : 0);
}
void quad_insert(QuadNode *node, Point point, int bucket) {
    if (node->children[0]) {
        quad_insert(node->children[destination(node, point)], point, bucket);
        return;
    }
    points_insert(&node->points, point);
    if (node->points.n <= bucket)
        return;
    const Integer half = node->size / 2;
    for (int i = 0; i < 4; ++i) {
        node->children[i] = calloc(1, sizeof *node->children[i]);
        node->children[i]->x = node->x + (i % 2) * half;
        node->children[i]->y = node->y + (i / 2) * half;
        node->children[i]->size = half;
    }
    const Points old = node->points;
    node->points = (Points){0};
    for (int i = 0; i < old.n; ++i)
        quad_insert(node, old.v[i], bucket);
    free(old.v);
}
void quad_delete(QuadNode *node, Point point, int bucket) {
    if (!node->children[0]) {
        points_remove(&node->points, point.id);
        return;
    }
    quad_delete(node->children[destination(node, point)], point, bucket);
    int count = 0;
    for (int i = 0; i < 4; ++i) {
        if (node->children[i]->children[0])
            return;
        count += node->children[i]->points.n;
    }
    if (count > bucket)
        return;
    for (int i = 0; i < 4; ++i) {
        QuadNode *child = node->children[i];
        for (int j = 0; j < child->points.n; ++j)
            points_insert(&node->points, child->points.v[j]);
        free(child->points.v);
        free(child);
        node->children[i] = NULL;
    }
}
void quad_free(QuadNode *node) {
    if (!node)
        return;
    for (int i = 0; i < 4; ++i)
        quad_free(node->children[i]);
    free(node->points.v);
    free(node);
}
