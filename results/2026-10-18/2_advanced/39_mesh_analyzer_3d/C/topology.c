#include "mesh.h"
typedef struct {
    int a, b, face;
} Occurrence;
static int occurrence_compare(const void *left, const void *right) {
    const Occurrence *a = left, *b = right;
    if (a->a != b->a)
        return (a->a > b->a) - (a->a < b->a);
    if (a->b != b->b)
        return (a->b > b->b) - (a->b < b->b);
    return (a->face > b->face) - (a->face < b->face);
}
int edge_index(const Topology *topology, int a, int b) {
    if (a > b) {
        int temporary = a;
        a = b;
        b = temporary;
    }
    int low = 0, high = topology->edge_count;
    while (low < high) {
        int middle = low + (high - low) / 2;
        const Edge *edge = &topology->edges[middle];
        if (edge->a < a || (edge->a == a && edge->b < b))
            low = middle + 1;
        else
            high = middle;
    }
    return low < topology->edge_count && topology->edges[low].a == a && topology->edges[low].b == b ? low
                                                                                                    : -1;
}
Topology analyze(const Faces *faces, int vertices) {
    Topology out = {.vertices = vertices, .face_count = faces->count};
    out.vertex_faces = calloc((size_t)vertices + 1, sizeof(IntList));
    out.vertex_edges = calloc((size_t)vertices + 1, sizeof(IntList));
    out.neighbors = calloc((size_t)vertices + 1, sizeof(IntList));
    out.fan_components = calloc((size_t)vertices + 1, sizeof(IntList));
    out.fans = calloc((size_t)vertices + 1, sizeof(int));
    out.face_component = resize(NULL, (size_t)faces->count * sizeof(int));
    Occurrence *occurrences = resize(NULL, (size_t)faces->count * 3 * sizeof(Occurrence));
    for (int f = 0; f < faces->count; ++f) {
        out.face_component[f] = -1;
        for (int i = 0; i < 3; ++i) {
            int a = faces->data[f].v[i], b = faces->data[f].v[(i + 1) % 3];
            int_push(&out.vertex_faces[a], f);
            occurrences[3 * f + i] = (Occurrence){a < b ? a : b, a < b ? b : a, f};
        }
    }
    qsort(occurrences, (size_t)faces->count * 3, sizeof(Occurrence), occurrence_compare);
    out.edges = calloc((size_t)faces->count * 3, sizeof(Edge));
    for (int i = 0; i < faces->count * 3; ++i) {
        Occurrence occurrence = occurrences[i];
        if (!out.edge_count || out.edges[out.edge_count - 1].a != occurrence.a ||
            out.edges[out.edge_count - 1].b != occurrence.b) {
            int e = out.edge_count++;
            out.edges[e].a = occurrence.a;
            out.edges[e].b = occurrence.b;
            int_push(&out.vertex_edges[occurrence.a], e);
            int_push(&out.vertex_edges[occurrence.b], e);
            int_push(&out.neighbors[occurrence.a], occurrence.b);
            int_push(&out.neighbors[occurrence.b], occurrence.a);
        }
        int_push(&out.edges[out.edge_count - 1].faces, occurrence.face);
    }
    free(occurrences);
    for (int v = 1; v <= vertices; ++v)
        int_sort(&out.neighbors[v]);
    out.component_faces = calloc((size_t)faces->count, sizeof(IntList));
    out.component_vertices = calloc((size_t)faces->count, sizeof(IntList));
    out.component_edges = calloc((size_t)faces->count, sizeof(IntList));
    out.component_nonmanifold_vertices = calloc((size_t)faces->count, sizeof(IntList));
    for (int first = 0; first < faces->count; ++first)
        if (out.face_component[first] < 0) {
            int component = out.component_count++;
            IntList *queue = &out.component_faces[component];
            int_push(queue, first);
            out.face_component[first] = component;
            for (int position = 0; position < queue->count; ++position) {
                const Face *face = &faces->data[queue->data[position]];
                for (int i = 0; i < 3; ++i) {
                    const Edge *edge = &out.edges[edge_index(&out, face->v[i], face->v[(i + 1) % 3])];
                    for (int j = 0; j < edge->faces.count; ++j) {
                        int next = edge->faces.data[j];
                        if (out.face_component[next] < 0) {
                            out.face_component[next] = component;
                            int_push(queue, next);
                        }
                    }
                }
            }
            int_sort(queue);
            bool *used = calloc((size_t)vertices + 1, sizeof(bool));
            for (int i = 0; i < queue->count; ++i)
                for (int j = 0; j < 3; ++j)
                    used[faces->data[queue->data[i]].v[j]] = true;
            for (int v = 1; v <= vertices; ++v)
                if (used[v])
                    int_push(&out.component_vertices[component], v);
            free(used);
        }
    for (int e = 0; e < out.edge_count; ++e)
        int_push(&out.component_edges[out.face_component[out.edges[e].faces.data[0]]], e);
    for (int vertex = 1; vertex <= vertices; ++vertex) {
        bool *visited = calloc((size_t)faces->count, sizeof(bool));
        int *per_component = calloc((size_t)out.component_count, sizeof(int));
        for (int i = 0; i < out.vertex_faces[vertex].count; ++i) {
            int first = out.vertex_faces[vertex].data[i];
            if (visited[first])
                continue;
            IntList queue = {0};
            int_push(&queue, first);
            visited[first] = true;
            for (int position = 0; position < queue.count; ++position)
                for (int j = 0; j < out.vertex_edges[vertex].count; ++j) {
                    const Edge *edge = &out.edges[out.vertex_edges[vertex].data[j]];
                    if (!int_contains(&edge->faces, queue.data[position]))
                        continue;
                    for (int k = 0; k < edge->faces.count; ++k) {
                        int next = edge->faces.data[k];
                        if (!visited[next]) {
                            visited[next] = true;
                            int_push(&queue, next);
                        }
                    }
                }
            ++out.fans[vertex];
            ++per_component[out.face_component[first]];
            int_free(&queue);
        }
        for (int c = 0; c < out.component_count; ++c) {
            if (per_component[c])
                int_push(&out.fan_components[vertex], c);
            if (per_component[c] >= 2)
                int_push(&out.component_nonmanifold_vertices[c], vertex);
        }
        free(visited);
        free(per_component);
    }
    return out;
}
void topology_free(Topology *topology) {
    for (int e = 0; e < topology->edge_count; ++e)
        int_free(&topology->edges[e].faces);
    for (int v = 0; v <= topology->vertices; ++v) {
        int_free(&topology->vertex_faces[v]);
        int_free(&topology->vertex_edges[v]);
        int_free(&topology->neighbors[v]);
        int_free(&topology->fan_components[v]);
    }
    for (int c = 0; c < topology->component_count; ++c) {
        int_free(&topology->component_faces[c]);
        int_free(&topology->component_vertices[c]);
        int_free(&topology->component_edges[c]);
        int_free(&topology->component_nonmanifold_vertices[c]);
    }
    free(topology->edges);
    free(topology->face_component);
    free(topology->fans);
    free(topology->component_faces);
    free(topology->component_vertices);
    free(topology->component_edges);
    free(topology->component_nonmanifold_vertices);
    free(topology->vertex_faces);
    free(topology->vertex_edges);
    free(topology->neighbors);
    free(topology->fan_components);
    *topology = (Topology){0};
}
int loop_length(const Loop *loop) {
    return loop->vertices.count - (loop->closed ? 0 : 1);
}
Loops trace_loops(const Topology *topology) {
    Loops loops = {0};
    bool *used = calloc((size_t)topology->edge_count, sizeof(bool));
    for (int component = 0; component < topology->component_count; ++component)
        for (int i = 0; i < topology->component_edges[component].count; ++i) {
            int first = topology->component_edges[component].data[i];
            const Edge *edge = &topology->edges[first];
            if (edge->faces.count != 1 || used[first])
                continue;
            used[first] = true;
            Loop loop = {.component = component, .kind = "open"};
            int_push(&loop.vertices, edge->a);
            int_push(&loop.vertices, edge->b);
            while (loop.vertices.data[loop.vertices.count - 1] != edge->a) {
                int x = loop.vertices.data[loop.vertices.count - 1], selected = -1, other = 0;
                for (int j = 0; j < topology->vertex_edges[x].count; ++j) {
                    int e = topology->vertex_edges[x].data[j];
                    const Edge *candidate = &topology->edges[e];
                    if (used[e] || candidate->faces.count != 1 ||
                        topology->face_component[candidate->faces.data[0]] != component)
                        continue;
                    int y = candidate->a == x ? candidate->b : candidate->a;
                    if (selected < 0 || y < other) {
                        selected = e;
                        other = y;
                    }
                }
                if (selected < 0)
                    break;
                used[selected] = true;
                int_push(&loop.vertices, other);
            }
            loop.closed = loop.vertices.data[loop.vertices.count - 1] == edge->a;
            if (loop.closed)
                --loop.vertices.count;
            if (loops.count == loops.capacity) {
                loops.capacity = loops.capacity ? 2 * loops.capacity : 8;
                loops.data = resize(loops.data, (size_t)loops.capacity * sizeof(Loop));
            }
            loops.data[loops.count++] = loop;
        }
    free(used);
    return loops;
}
void loops_free(Loops *loops) {
    for (int i = 0; i < loops->count; ++i)
        int_free(&loops->data[i].vertices);
    free(loops->data);
    *loops = (Loops){0};
}
