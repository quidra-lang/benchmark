#include "mesh.h"
bool directed(const Face *face, int a, int b) {
    for (int i = 0; i < 3; ++i)
        if (face->v[i] == a && face->v[(i + 1) % 3] == b)
            return true;
    return false;
}
void flip(Face *face) {
    int temporary = face->v[1];
    face->v[1] = face->v[2];
    face->v[2] = temporary;
}
void orient_faces(Faces *faces, const Topology *topology) {
    bool *visited = calloc((size_t)faces->count, sizeof(bool));
    for (int first = 0; first < faces->count; ++first)
        if (!visited[first]) {
            IntList queue = {0};
            int_push(&queue, first);
            visited[first] = true;
            for (int position = 0; position < queue.count; ++position) {
                int f = queue.data[position];
                Face face = faces->data[f];
                for (int i = 0; i < 3; ++i) {
                    int a = face.v[i], b = face.v[(i + 1) % 3];
                    const Edge *edge = &topology->edges[edge_index(topology, a, b)];
                    if (edge->faces.count != 2)
                        continue;
                    int other = edge->faces.data[0] == f ? edge->faces.data[1] : edge->faces.data[0];
                    if (visited[other])
                        continue;
                    if (directed(&faces->data[other], a, b))
                        flip(&faces->data[other]);
                    visited[other] = true;
                    int_push(&queue, other);
                }
            }
            int_free(&queue);
        }
    free(visited);
}
IntList inconsistent_edges(const Faces *faces, const Topology *topology) {
    IntList out = {0};
    for (int e = 0; e < topology->edge_count; ++e) {
        const Edge *edge = &topology->edges[e];
        if (edge->faces.count == 2 && directed(&faces->data[edge->faces.data[0]], edge->a, edge->b) ==
                                          directed(&faces->data[edge->faces.data[1]], edge->a, edge->b))
            int_push(&out, e);
    }
    return out;
}
