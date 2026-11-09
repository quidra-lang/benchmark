#include "geometry.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
Ring *ring_new(void) {
    Ring *ring = allocate(sizeof(*ring));
    *ring = (Ring){.references = 1};
    return ring;
}
void ring_point(Ring *ring, Point p) {
    if (ring->count == ring->point_capacity) {
        ring->point_capacity = ring->point_capacity ? 2 * ring->point_capacity : 16;
        ring->points = resize(ring->points, ring->point_capacity * sizeof(Point));
    }
    ring->points[ring->count++] = p;
}
void ring_edge(Ring *ring, OriginalLine line) {
    if (ring->edge_count == ring->edge_capacity) {
        ring->edge_capacity = ring->edge_capacity ? 2 * ring->edge_capacity : 16;
        ring->edges = resize(ring->edges, ring->edge_capacity * sizeof(OriginalLine));
    }
    ring->edges[ring->edge_count++] = line;
}
void ring_complete_integer(Ring *ring) {
    for (size_t i = 0; i < ring->count; ++i)
        ring_edge(ring, original_line(ring->points[i], ring->points[(i + 1) % ring->count]));
}
Ring *ring_retain(Ring *ring) {
    if (ring)
        ++ring->references;
    return ring;
}
void ring_release(Ring *ring) {
    if (ring && !--ring->references) {
        free(ring->points);
        free(ring->edges);
        free(ring);
    }
}
void rings_add(Rings *rings, Ring *ring) {
    if (rings->count == rings->capacity) {
        rings->capacity = rings->capacity ? 2 * rings->capacity : 8;
        rings->items = resize(rings->items, rings->capacity * sizeof(Ring *));
    }
    rings->items[rings->count++] = ring;
}
void rings_free(Rings *rings) {
    for (size_t i = 0; i < rings->count; ++i)
        ring_release(rings->items[i]);
    free(rings->items);
    *rings = (Rings){0};
}
Rings rings_copy(const Rings *rings) {
    Rings result = {0};
    for (size_t i = 0; i < rings->count; ++i)
        rings_add(&result, ring_retain(rings->items[i]));
    return result;
}
Polygon *polygon_retain(Polygon *polygon) {
    if (polygon)
        ++polygon->references;
    return polygon;
}
void polygon_release(Polygon *polygon) {
    if (polygon && !--polygon->references) {
        rings_free(&polygon->input);
        rings_free(&polygon->rings);
        free(polygon);
    }
}
void polygon_list_add(PolygonList *list, Polygon *polygon) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 8;
        list->items = resize(list->items, list->capacity * sizeof(Polygon *));
    }
    list->items[list->count++] = polygon;
}
void polygon_list_free(PolygonList *list) {
    for (size_t i = 0; i < list->count; ++i)
        polygon_release(list->items[i]);
    free(list->items);
    *list = (PolygonList){0};
}
void result_free(Result *result) {
    polygon_list_free(&result->polygons);
    polygon_release(result->a);
    polygon_release(result->b);
    *result = (Result){0};
}
Result result_copy(const Result *result) {
    Result out = {.a = polygon_retain(result->a), .b = polygon_retain(result->b)};
    for (size_t i = 0; i < result->polygons.count; ++i)
        polygon_list_add(&out.polygons, polygon_retain(result->polygons.items[i]));
    return out;
}
bool inside_ring(Point p, const Ring *ring) {
    bool inside = false;
    for (size_t i = 0; i < ring->count; ++i) {
        Point a = ring->points[i], b = ring->points[(i + 1) % ring->count];
        if ((fraction_compare(point_y(a), point_y(p)) > 0) ==
            (fraction_compare(point_y(b), point_y(p)) > 0))
            continue;
        Integer value = line_cross(ring->edges[i], p);
        if (fraction_compare(point_y(a), point_y(b)) > 0)
            value = -value;
        if (value > 0)
            inside = !inside;
    }
    return inside;
}
bool interior(Point p, const Rings *rings) {
    bool inside = false;
    for (size_t i = 0; i < rings->count; ++i)
        if (inside_ring(p, rings->items[i]))
            inside = !inside;
    return inside;
}
bool boundary(Point p, const Ring *ring) {
    for (size_t i = 0; i < ring->count; ++i)
        if (on_edge(p, ring, i))
            return true;
    return false;
}
Ring *rotate_ring(const Ring *ring) {
    size_t first = 0;
    for (size_t i = 1; i < ring->count; ++i)
        if (point_less(ring->points[i], ring->points[first]))
            first = i;
    Ring *out = ring_new();
    for (size_t i = 0; i < ring->count; ++i) {
        size_t at = (first + i) % ring->count;
        ring_point(out, ring->points[at]);
        ring_edge(out, ring->edges[at]);
    }
    return out;
}
bool counterclockwise(const Ring *ring) {
    return direction_cross(ring->edges[ring->count - 1], ring->edges[0]) > 0;
}
Ring *reverse_ring(const Ring *ring) {
    Ring *out = ring_new();
    ring_point(out, ring->points[0]);
    for (size_t i = 1; i < ring->count; ++i)
        ring_point(out, ring->points[ring->count - i]);
    for (size_t i = 0; i < ring->count; ++i)
        ring_edge(out, reverse_line(ring->edges[ring->count - i - 1]));
    return out;
}
static int ring_compare(const void *left, const void *right) {
    const Ring *a = *(Ring *const *)left, *b = *(Ring *const *)right;
    return point_less(a->points[0], b->points[0])   ? -1
           : point_less(b->points[0], a->points[0]) ? 1
                                                    : 0;
}
Polygon *canonical(const Rings *input) {
    Polygon *polygon = allocate(sizeof(*polygon));
    *polygon = (Polygon){.references = 1, .input = rings_copy(input)};
    for (size_t i = 0; i < input->count; ++i) {
        Ring *ring = rotate_ring(input->items[i]);
        if (counterclockwise(ring) != (i == 0)) {
            Ring *reversed = reverse_ring(ring);
            ring_release(ring);
            ring = reversed;
        }
        rings_add(&polygon->rings, ring);
    }
    if (polygon->rings.count > 1)
        qsort(polygon->rings.items + 1, polygon->rings.count - 1, sizeof(Ring *), ring_compare);
    return polygon;
}
static int polygon_compare(const void *left, const void *right) {
    const Polygon *a = *(Polygon *const *)left, *b = *(Polygon *const *)right;
    Point first = a->rings.items[0]->points[0], second = b->rings.items[0]->points[0];
    return point_less(first, second) ? -1 : point_less(second, first) ? 1 : 0;
}
PolygonList assemble(const Rings *input) {
    Rings rings = {0};
    int *depth = allocate(input->count * sizeof(int));
    memset(depth, 0, input->count * sizeof(int));
    for (size_t i = 0; i < input->count; ++i)
        rings_add(&rings, rotate_ring(input->items[i]));
    for (size_t i = 0; i < rings.count; ++i) {
        for (size_t j = 0; j < rings.count; ++j)
            if (i != j && inside_ring(rings.items[i]->points[0], rings.items[j]))
                ++depth[i];
        if (counterclockwise(rings.items[i]) != (depth[i] % 2 == 0)) {
            Ring *reversed = reverse_ring(rings.items[i]);
            ring_release(rings.items[i]);
            rings.items[i] = reversed;
        }
    }
    PolygonList result = {0};
    for (size_t i = 0; i < rings.count; ++i)
        if (depth[i] % 2 == 0) {
            Polygon *polygon = allocate(sizeof(*polygon));
            *polygon = (Polygon){.references = 1};
            rings_add(&polygon->rings, ring_retain(rings.items[i]));
            Rings holes = {0};
            for (size_t j = 0; j < rings.count; ++j)
                if (depth[j] == depth[i] + 1 &&
                    inside_ring(rings.items[j]->points[0], rings.items[i]))
                    rings_add(&holes, ring_retain(rings.items[j]));
            if (holes.count)
                qsort(holes.items, holes.count, sizeof(Ring *), ring_compare);
            for (size_t j = 0; j < holes.count; ++j)
                rings_add(&polygon->rings, holes.items[j]);
            free(holes.items);
            polygon_list_add(&result, polygon);
        }
    if (result.count)
        qsort(result.items, result.count, sizeof(Polygon *), polygon_compare);
    rings_free(&rings);
    free(depth);
    return result;
}
double ring_area(const Ring *ring) {
    double sum = 0.0;
    for (size_t i = 0; i < ring->count; ++i) {
        Point a = ring->points[i], b = ring->points[(i + 1) % ring->count];
        sum += fraction_real(point_x(a)) * fraction_real(point_y(b)) -
               fraction_real(point_x(b)) * fraction_real(point_y(a));
    }
    return sum / 2.0;
}
double ring_perimeter(const Ring *ring) {
    double sum = 0.0;
    for (size_t i = 0; i < ring->count; ++i) {
        Point a = ring->points[i], b = ring->points[(i + 1) % ring->count];
        double dx = fraction_real(point_x(b)) - fraction_real(point_x(a)),
               dy = fraction_real(point_y(b)) - fraction_real(point_y(a));
        sum += sqrt(dx * dx + dy * dy);
    }
    return sum;
}
Rings flatten(const PolygonList *polygons) {
    Rings result = {0};
    for (size_t i = 0; i < polygons->count; ++i) {
        const Rings *rings = &polygons->items[i]->rings;
        for (size_t j = 0; j < rings->count; ++j)
            rings_add(&result, ring_retain(rings->items[j]));
    }
    return result;
}
double total_area(const PolygonList *polygons) {
    double sum = 0.0;
    for (size_t i = 0; i < polygons->count; ++i)
        for (size_t j = 0; j < polygons->items[i]->rings.count; ++j)
            sum += ring_area(polygons->items[i]->rings.items[j]);
    return sum;
}
