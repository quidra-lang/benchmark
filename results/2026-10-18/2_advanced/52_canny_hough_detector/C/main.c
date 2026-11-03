#include "detector.h"
typedef struct {
    CirclePeak peak;
    I gap, arcs;
} Circle;
typedef struct {
    Point start, end;
    I length, pixels, theta;
    int line;
} Segment;
typedef struct {
    Segment *data;
    int count, capacity;
} Segments;
typedef struct {
    LinePeak peak;
    Ids segments;
} Line;
typedef struct {
    int a, b;
    Point point;
    int a_end, b_end;
} Junction;
typedef struct {
    Junction *data;
    int count, capacity;
} Junctions;
typedef struct {
    int segments[4], count;
    Point vertices[4];
    I angles[4], lengths[4], support[4], sigma;
    int corners[4];
    const char *kind;
} Polygon;
typedef struct {
    Polygon *data;
    int count, capacity;
} Polygons;
typedef struct {
    bool polygon;
    int index;
    Point representatives[4];
    int count;
    I pixels, mean, contrast;
    int parent;
} Shape;
typedef struct {
    Point point;
    I position;
} Projected;
static Point difference(Point a, Point b) {
    return (Point){a.x - b.x, a.y - b.y};
}
static I cross(Point a, Point b) {
    return a.x * b.y - a.y * b.x;
}
static I dot(Point a, Point b) {
    return a.x * b.x + a.y * b.y;
}
static I minimum(I a, I b) {
    return a < b ? a : b;
}
static I maximum(I a, I b) {
    return a > b ? a : b;
}
static I chebyshev(Point a, Point b) {
    return maximum(absolute(a.x - b.x), absolute(a.y - b.y));
}
static I angle(I a, I b) {
    I d = absolute(a - b);
    return minimum(d, 180 - d);
}
static I rounded(I n, I d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    return floor_div(2 * n + d, 2 * d);
}
static Points bresenham(Point start, Point end) {
    Points out = {0};
    I x = start.x, y = start.y, dx = absolute(end.x - x), dy = -absolute(end.y - y), sx = x < end.x ? 1 : -1,
      sy = y < end.y ? 1 : -1, error = dx + dy;
    for (;;) {
        point_push(&out, (Point){x, y});
        if (x == end.x && y == end.y)
            break;
        I twice = 2 * error;
        if (twice >= dy) {
            error += dy;
            x += sx;
        }
        if (twice <= dx) {
            error += dx;
            y += sy;
        }
    }
    return out;
}
static bool circumference(Point point, Circle circle) {
    Point delta = difference(point, circle.peak.center);
    I d2 = dot(delta, delta), r = circle.peak.radius;
    return (r - 1) * (r - 1) <= d2 && d2 <= (r + 1) * (r + 1);
}
static bool near_edge(Image edges, Point point) {
    for (I dy = -1; dy <= 1; ++dy)
        for (I dx = -1; dx <= 1; ++dx) {
            Point next = {point.x + dx, point.y + dy};
            if (image_inside(edges, next) && image_at(edges, next))
                return true;
        }
    return false;
}
static char *shape_name(int index, const Shape *shapes) {
    if (index < 0)
        return "none";
    return format("%s %d", shapes[index].polygon ? "polygon" : "circle", shapes[index].index + 1);
}
static bool inside(Point point, Shape shape, const Polygon *polygons, const Circle *circles) {
    if (!shape.polygon) {
        CirclePeak circle = circles[shape.index].peak;
        Point delta = difference(point, circle.center);
        return dot(delta, delta) <= circle.radius * circle.radius;
    }
    Polygon polygon = polygons[shape.index];
    for (int i = 0; i < polygon.count; ++i) {
        Point a = polygon.vertices[i], b = polygon.vertices[(i + 1) % polygon.count];
        I value = cross(difference(b, a), difference(point, a));
        if (value != 0 && ((value > 0) != (polygon.sigma > 0)))
            return false;
    }
    return true;
}
static void segment_push(Segments *list, Segment value) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 16;
        Segment *data = allocate(capacity, sizeof(Segment));
        if (list->count)
            memcpy(data, list->data, list->count * sizeof(Segment));
        list->data = data;
        list->capacity = capacity;
    }
    list->data[list->count++] = value;
}
static void junction_push(Junctions *list, Junction value) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 32;
        Junction *data = allocate(capacity, sizeof(Junction));
        if (list->count)
            memcpy(data, list->data, list->count * sizeof(Junction));
        list->data = data;
        list->capacity = capacity;
    }
    list->data[list->count++] = value;
}
static void polygon_push(Polygons *list, Polygon value) {
    if (list->count == list->capacity) {
        int capacity = list->capacity ? list->capacity * 2 : 16;
        Polygon *data = allocate(capacity, sizeof(Polygon));
        if (list->count)
            memcpy(data, list->data, list->count * sizeof(Polygon));
        list->data = data;
        list->capacity = capacity;
    }
    list->data[list->count++] = value;
}
static const Junction *lookup(Junctions junctions, int a, int b) {
    if (a > b) {
        int swap = a;
        a = b;
        b = swap;
    }
    int low = 0, high = junctions.count;
    while (low < high) {
        int middle = low + (high - low) / 2;
        Junction *value = &junctions.data[middle];
        if (value->a < a || (value->a == a && value->b < b))
            low = middle + 1;
        else
            high = middle;
    }
    return low < junctions.count && junctions.data[low].a == a && junctions.data[low].b == b
               ? &junctions.data[low]
               : NULL;
}
static int junction_end(const Junction *junction, int id, int other) {
    return id < other ? junction->a_end : junction->b_end;
}
static int angular_compare(const void *left, const void *right) {
    Point a = *(const Point *)left, b = *(const Point *)right;
    int ah = a.y > 0 || (a.y == 0 && a.x > 0) ? 0 : 1, bh = b.y > 0 || (b.y == 0 && b.x > 0) ? 0 : 1;
    if (ah != bh)
        return ah < bh ? -1 : 1;
    I value = cross(a, b);
    return value > 0 ? -1 : value < 0 ? 1 : 0;
}
static int projected_compare(const void *left, const void *right) {
    const Projected *a = left;
    const Projected *b = right;
    if (a->position != b->position)
        return a->position < b->position ? -1 : 1;
    if (a->point.x != b->point.x)
        return a->point.x < b->point.x ? -1 : 1;
    return (a->point.y > b->point.y) - (a->point.y < b->point.y);
}
static int integer_compare(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}
static bool all_angles(Polygon polygon, I target, const Params *p) {
    for (int i = 0; i < polygon.count; ++i)
        if (absolute(polygon.angles[i] - target) > p->angle_tolerance)
            return false;
    return true;
}
typedef struct {
    int size, start, path[4];
    const Segment *segments;
    Junctions junctions;
    Ids *adjacency;
    Image edges;
    const Params *params;
    Polygons *polygons;
} Search;
static void visit(Search *search, int count) {
    int *path = search->path;
    int size = search->size;
    const Params *p = search->params;
    if (count == size) {
        if (path[1] >= path[size - 1] || !lookup(search->junctions, path[size - 1], path[0]))
            return;
        Polygon polygon = {.count = size};
        for (int i = 0; i < size; ++i) {
            polygon.segments[i] = path[i];
            polygon.corners[i] = -1;
            int previous = path[(i + size - 1) % size], current = path[i], next = path[(i + 1) % size];
            const Junction *left = lookup(search->junctions, previous, current);
            const Junction *right = lookup(search->junctions, current, next);
            if (junction_end(left, current, previous) == junction_end(right, current, next))
                return;
            polygon.vertices[i] = left->point;
        }
        I sign = 0;
        for (int i = 0; i < size; ++i) {
            I z = cross(difference(polygon.vertices[(i + 1) % size], polygon.vertices[i]),
                        difference(polygon.vertices[(i + 2) % size], polygon.vertices[(i + 1) % size]));
            if (z == 0 || (sign != 0 && ((z > 0) != (sign > 0))))
                return;
            sign = z;
        }
        for (int i = 0; i < size; ++i) {
            Point a = polygon.vertices[i], b = polygon.vertices[(i + 1) % size],
                  previous = polygon.vertices[(i + size - 1) % size];
            polygon.sigma += cross(a, b);
            I phi =
                angle(search->segments[path[(i + size - 1) % size]].theta, search->segments[path[i]].theta);
            polygon.angles[i] = dot(difference(previous, a), difference(b, a)) < 0 ? 180 - phi : phi;
            Point side = difference(b, a);
            polygon.lengths[i] = dot(side, side);
            Points points = bresenham(a, b);
            I supported = 0;
            for (int j = 0; j < points.count; ++j)
                supported += near_edge(search->edges, points.data[j]);
            polygon.support[i] = floor_div(100 * supported, points.count);
        }
        if (size == 3) {
            bool right = false;
            for (int i = 0; i < size; ++i)
                right = right || absolute(polygon.angles[i] - 90) <= p->angle_tolerance;
            polygon.kind = all_angles(polygon, 60, p) ? "equilateral_triangle"
                           : right                    ? "right_triangle"
                                                      : "triangle";
        } else {
            bool a = angle(search->segments[path[0]].theta, search->segments[path[2]].theta) <=
                     p->angle_tolerance,
                 b = angle(search->segments[path[1]].theta, search->segments[path[3]].theta) <=
                     p->angle_tolerance;
            I largest = polygon.lengths[0], smallest = largest;
            for (int i = 1; i < size; ++i) {
                largest = maximum(largest, polygon.lengths[i]);
                smallest = minimum(smallest, polygon.lengths[i]);
            }
            polygon.kind = !a && !b                                                      ? "quadrilateral"
                           : a != b                                                      ? "trapezoid"
                           : !all_angles(polygon, 90, p)                                 ? "parallelogram"
                           : 100 * (largest - smallest) <= p->square_tolerance * largest ? "square"
                                                                                         : "rectangle";
        }
        polygon_push(search->polygons, polygon);
        return;
    }
    Ids neighbors = search->adjacency[path[count - 1]];
    for (int i = 0; i < neighbors.count; ++i) {
        int next = neighbors.data[i];
        if (next <= search->start)
            continue;
        bool seen = false;
        for (int j = 0; j < count; ++j)
            seen = seen || path[j] == next;
        if (seen)
            continue;
        path[count] = next;
        visit(search, count + 1);
    }
}
static void paint(Image overlay, Point point) {
    if (image_inside(overlay, point))
        image_set(overlay, point, 255);
}
int main(void) {
    mkdir("output", 0777);
    Input input = load();
    Image image = input.image;
    Params p = input.params;
    Gradient g = gradient(smooth(image, &p));
    Canny edges = canny(g, &p);
    CircleVotes circle_data = circle_votes(edges.edges, &p);
    int circle_count = (int)minimum(p.circle_count, circle_data.peak_count);
    Circle *circles = allocate(circle_count, sizeof(Circle));
    for (int i = 0; i < circle_count; ++i) {
        Circle *circle = &circles[i];
        circle->peak = circle_data.peaks[i];
        Points offsets = circle_data.offsets[circle->peak.radius - p.r_min];
        Point *ordered = allocate(offsets.count, sizeof(Point));
        memcpy(ordered, offsets.data, offsets.count * sizeof(Point));
        qsort(ordered, offsets.count, sizeof(Point), angular_compare);
        bool *hit = allocate(offsets.count, sizeof(bool));
        bool all = true;
        for (int j = 0; j < offsets.count; ++j) {
            Point point = {circle->peak.center.x + ordered[j].x, circle->peak.center.y + ordered[j].y};
            hit[j] = image_inside(image, point) && image_at(edges.edges, point);
            all = all && hit[j];
        }
        int n = offsets.count;
        if (all)
            circle->arcs = 1;
        else
            for (int j = 0; j < n; ++j)
                circle->arcs += hit[j] && !hit[(j + n - 1) % n];
        I run = 0;
        for (int j = 0; j < 2 * n; ++j) {
            if (hit[j % n])
                run = 0;
            else
                ++run;
            circle->gap = maximum(circle->gap, minimum(n, run));
        }
    }
    Image line_edges = image_new(image.width, image.height);
    memcpy(line_edges.data, edges.edges.data, (size_t)image.width * image.height * sizeof(I));
    I circle_edge_pixels = 0;
    for (int y = 0; y < image.height; ++y)
        for (int x = 0; x < image.width; ++x)
            if (image_at(edges.edges, (Point){x, y}))
                for (int i = 0; i < circle_count; ++i)
                    if (circumference((Point){x, y}, circles[i])) {
                        image_set(line_edges, (Point){x, y}, 0);
                        ++circle_edge_pixels;
                        break;
                    }
    LineVotes line_data = line_votes(line_edges, &input.trig, &p);
    Line *lines = allocate(p.line_count, sizeof(Line));
    int line_count = 0;
    Segments segments = {0};
    Image claimed = image_new(image.width, image.height);
    Projected *selected = allocate((size_t)image.width * image.height, sizeof(Projected));
    for (int pi = 0; pi < line_data.peak_count; ++pi) {
        if (line_count >= p.line_count)
            break;
        LinePeak peak = line_data.peaks[pi];
        int count = 0;
        for (int y = 0; y < image.height; ++y)
            for (int x = 0; x < image.width; ++x) {
                Point point = {x, y};
                if (image_at(line_edges, point) && !image_at(claimed, point) &&
                    absolute(rho(point, peak.theta, &input.trig, &p) - peak.rho) <= p.tolerance)
                    selected[count++] = (Projected){point, point.y * input.trig.data[peak.theta][0] -
                                                               point.x * input.trig.data[peak.theta][1]};
            }
        if (count > 1)
            qsort(selected, count, sizeof(Projected), projected_compare);
        Line line = {.peak = peak};
        for (int begin = 0; begin < count;) {
            int end = begin + 1;
            while (end < count && selected[end].position - selected[end - 1].position <= p.max_gap * 16384)
                ++end;
            Point start = selected[begin].point, last = selected[end - 1].point;
            I length = chebyshev(start, last) + 1;
            if (length >= p.min_length) {
                id_push(&line.segments, segments.count);
                segment_push(&segments, (Segment){start, last, length, end - begin, peak.theta, line_count});
                for (int i = begin; i < end; ++i)
                    image_set(claimed, selected[i].point, 1);
            }
            begin = end;
        }
        if (line.segments.count)
            lines[line_count++] = line;
    }
    Junctions junctions = {0};
    Ids *adjacency = allocate(segments.count, sizeof(Ids));
    for (int a = 0; a < segments.count; ++a)
        for (int b = a + 1; b < segments.count; ++b) {
            Segment first = segments.data[a], second = segments.data[b];
            if (angle(first.theta, second.theta) < p.junction_angle)
                continue;
            Point da = difference(first.end, first.start), db = difference(second.end, second.start);
            I den = cross(da, db);
            if (!den)
                continue;
            I lambda = cross(difference(second.start, first.start), db);
            Point point = {rounded(first.start.x * den + lambda * da.x, den),
                           rounded(first.start.y * den + lambda * da.y, den)};
            I a_start = chebyshev(first.start, point), a_end = chebyshev(first.end, point),
              b_start = chebyshev(second.start, point), b_end = chebyshev(second.end, point);
            if (minimum(a_start, a_end) > p.junction_distance ||
                minimum(b_start, b_end) > p.junction_distance)
                continue;
            junction_push(&junctions,
                          (Junction){a, b, point, a_start <= a_end ? 0 : 1, b_start <= b_end ? 0 : 1});
            id_push(&adjacency[a], b);
            id_push(&adjacency[b], a);
        }
    for (int i = 0; i < segments.count; ++i)
        if (adjacency[i].count > 1)
            qsort(adjacency[i].data, adjacency[i].count, sizeof(int), integer_compare);
    Polygons polygons = {0};
    for (int size = 3; size <= 4; ++size)
        for (int start = 0; start < segments.count; ++start) {
            Search search = {.size = size,
                             .start = start,
                             .path = {start},
                             .segments = segments.data,
                             .junctions = junctions,
                             .adjacency = adjacency,
                             .edges = edges.edges,
                             .params = &p,
                             .polygons = &polygons};
            visit(&search, 1);
        }
    int shape_count = polygons.count + circle_count;
    Shape *shapes = allocate(shape_count, sizeof(Shape));
    for (int i = 0; i < polygons.count; ++i) {
        shapes[i] = (Shape){.polygon = true, .index = i, .count = polygons.data[i].count, .parent = -1};
        memcpy(shapes[i].representatives, polygons.data[i].vertices, polygons.data[i].count * sizeof(Point));
    }
    for (int i = 0; i < circle_count; ++i) {
        CirclePeak circle = circles[i].peak;
        I x = circle.center.x, y = circle.center.y, r = circle.radius;
        shapes[polygons.count + i] =
            (Shape){.index = i,
                    .representatives = {{x + r, y}, {x, y + r}, {x - r, y}, {x, y - r}},
                    .count = 4,
                    .parent = -1};
    }
    for (int si = 0; si < shape_count; ++si) {
        Shape *shape = &shapes[si];
        I x0 = shape->representatives[0].x, y0 = shape->representatives[0].y, x1 = x0, y1 = y0;
        for (int i = 0; i < shape->count; ++i) {
            Point point = shape->representatives[i];
            x0 = minimum(x0, point.x);
            x1 = maximum(x1, point.x);
            y0 = minimum(y0, point.y);
            y1 = maximum(y1, point.y);
        }
        x0 = maximum(0, x0 - p.margin);
        y0 = maximum(0, y0 - p.margin);
        x1 = minimum(image.width - 1, x1 + p.margin);
        y1 = minimum(image.height - 1, y1 + p.margin);
        I inner = 0, outer = 0, outer_count = 0;
        for (I y = y0; y <= y1; ++y)
            for (I x = x0; x <= x1; ++x) {
                if (inside((Point){x, y}, *shape, polygons.data, circles)) {
                    ++shape->pixels;
                    inner += image_at(image, (Point){x, y});
                } else {
                    ++outer_count;
                    outer += image_at(image, (Point){x, y});
                }
            }
        shape->mean = shape->pixels ? floor_div(inner, shape->pixels) : 0;
        shape->contrast = shape->mean - (outer_count ? floor_div(outer, outer_count) : 0);
    }
    for (int i = 0; i < shape_count; ++i)
        for (int j = 0; j < shape_count; ++j) {
            if (i == j || shapes[j].pixels <= shapes[i].pixels)
                continue;
            bool contains = true;
            for (int k = 0; k < shapes[i].count; ++k)
                contains =
                    contains && inside(shapes[i].representatives[k], shapes[j], polygons.data, circles);
            if (contains && (shapes[i].parent < 0 || shapes[j].pixels < shapes[shapes[i].parent].pixels))
                shapes[i].parent = j;
        }
    Corners corner_data = corners(g, &p);
    char **corner_matches = allocate(corner_data.count, sizeof(char *));
    I corner_vertices = 0, corner_segments = 0, vertices_with_corner = 0;
    for (int ci = 0; ci < corner_data.count; ++ci) {
        Corner corner = corner_data.values[ci];
        I best = p.match_distance + 1;
        char *match = "none";
        for (int polygon = 0; polygon < polygons.count; ++polygon)
            for (int vertex = 0; vertex < polygons.data[polygon].count; ++vertex) {
                I d = chebyshev(corner.point, polygons.data[polygon].vertices[vertex]);
                if (d <= p.match_distance && d < best) {
                    best = d;
                    match = format("polygon %d vertex %d", polygon + 1, vertex + 1);
                }
            }
        if (strcmp(match, "none"))
            ++corner_vertices;
        else {
            best = p.match_distance + 1;
            for (int id = 0; id < segments.count; ++id)
                for (int end = 0; end < 2; ++end) {
                    I d = chebyshev(corner.point, end ? segments.data[id].end : segments.data[id].start);
                    if (d <= p.match_distance && d < best) {
                        best = d;
                        match = format("segment %d %s", id + 1, end ? "end" : "start");
                    }
                }
            if (strcmp(match, "none"))
                ++corner_segments;
        }
        corner_matches[ci] = match;
    }
    for (int pi = 0; pi < polygons.count; ++pi) {
        Polygon *polygon = &polygons.data[pi];
        for (int vertex = 0; vertex < polygon->count; ++vertex) {
            I best = p.match_distance + 1;
            for (int corner = 0; corner < corner_data.count; ++corner) {
                I d = chebyshev(polygon->vertices[vertex], corner_data.values[corner].point);
                if (d <= p.match_distance && d < best) {
                    best = d;
                    polygon->corners[vertex] = corner;
                }
            }
            vertices_with_corner += polygon->corners[vertex] >= 0;
        }
    }
    int *component_shapes = allocate(edges.count, sizeof(int));
    I *explained_counts = allocate(edges.count, sizeof(I));
    for (int i = 0; i < edges.count; ++i)
        component_shapes[i] = -1;
    for (int si = 0; si < shape_count; ++si) {
        Image explained = image_new(image.width, image.height);
        if (shapes[si].polygon) {
            Polygon polygon = polygons.data[shapes[si].index];
            for (int i = 0; i < polygon.count; ++i) {
                Points points = bresenham(polygon.vertices[i], polygon.vertices[(i + 1) % polygon.count]);
                for (int j = 0; j < points.count; ++j) {
                    Point point = points.data[j];
                    for (I dy = -1; dy <= 1; ++dy)
                        for (I dx = -1; dx <= 1; ++dx) {
                            Point next = {point.x + dx, point.y + dy};
                            if (image_inside(image, next))
                                image_set(explained, next, 1);
                        }
                }
            }
        }
        for (int component = 0; component < edges.count; ++component) {
            I count = 0;
            Points points = edges.components[component];
            for (int i = 0; i < points.count; ++i)
                count += shapes[si].polygon ? image_at(explained, points.data[i])
                                            : circumference(points.data[i], circles[shapes[si].index]);
            if (count > explained_counts[component]) {
                explained_counts[component] = count;
                component_shapes[component] = si;
            }
        }
        release_one(explained.data);
    }
    Image overlay = image_new(image.width, image.height), edge_image = image_new(image.width, image.height),
          hough_image = image_new(line_data.votes.width, line_data.votes.height);
    for (int i = 0; i < image.width * image.height; ++i) {
        overlay.data[i] = floor_div(image.data[i], p.overlay_divisor);
        edge_image.data[i] = 255 * edges.edges.data[i];
    }
    for (int i = 0; i < hough_image.width * hough_image.height; ++i)
        hough_image.data[i] =
            line_data.maximum ? floor_div(255 * line_data.votes.data[i], line_data.maximum) : 0;
    for (int i = 0; i < segments.count; ++i) {
        Points points = bresenham(segments.data[i].start, segments.data[i].end);
        for (int j = 0; j < points.count; ++j)
            paint(overlay, points.data[j]);
    }
    for (int i = 0; i < circle_count; ++i) {
        Circle circle = circles[i];
        Points offsets = circle_data.offsets[circle.peak.radius - p.r_min];
        for (int j = 0; j < offsets.count; ++j)
            paint(overlay, (Point){circle.peak.center.x + offsets.data[j].x,
                                   circle.peak.center.y + offsets.data[j].y});
    }
    for (int i = 0; i < corner_data.count; ++i) {
        Corner corner = corner_data.values[i];
        for (I e = -2; e <= 2; ++e) {
            paint(overlay, (Point){corner.point.x + e, corner.point.y});
            paint(overlay, (Point){corner.point.x, corner.point.y + e});
        }
    }
    write_pgm("edges.pgm", edge_image);
    write_pgm("hough.pgm", hough_image);
    write_pgm("overlay.pgm", overlay);
    FILE *line_file = fopen("output/lines.txt", "w");
    FILE *circle_file = fopen("output/circles.txt", "w");
    FILE *polygon_file = fopen("output/polygons.txt", "w");
    FILE *corner_file = fopen("output/corners.txt", "w");
    FILE *component_file = fopen("output/components.txt", "w");
    FILE *report = fopen("output/report.txt", "w");
    fprintf(line_file, "lines %d\n", line_count);
    for (int i = 0; i < line_count; ++i) {
        Line line = lines[i];
        fprintf(line_file, "line %d theta %" PRId64 " rho %" PRId64 " votes %" PRId64 " segments %d\n", i + 1,
                line.peak.theta, line.peak.rho, line.peak.votes, line.segments.count);
        for (int j = 0; j < line.segments.count; ++j) {
            int id = line.segments.data[j];
            Segment segment = segments.data[id];
            fprintf(line_file,
                    "segment %d start %" PRId64 " %" PRId64 " end %" PRId64 " %" PRId64 " length %" PRId64
                    " pixels %" PRId64 "\n",
                    id + 1, segment.start.x, segment.start.y, segment.end.x, segment.end.y, segment.length,
                    segment.pixels);
        }
    }
    fprintf(circle_file, "circles %d\n", circle_count);
    for (int i = 0; i < circle_count; ++i) {
        Circle circle = circles[i];
        Shape shape = shapes[polygons.count + i];
        fprintf(circle_file,
                "circle %d center %" PRId64 " %" PRId64 " radius %" PRId64 " votes %" PRId64
                " points %" PRId64 " gap %" PRId64 " arcs %" PRId64 " pixels %" PRId64 " mean %" PRId64
                " contrast %" PRId64 " inside %s\n",
                i + 1, circle.peak.center.x, circle.peak.center.y, circle.peak.radius, circle.peak.votes,
                circle.peak.points, circle.gap, circle.arcs, shape.pixels, shape.mean, shape.contrast,
                shape_name(shape.parent, shapes));
    }
    fprintf(polygon_file, "polygons %d\n", polygons.count);
    for (int i = 0; i < polygons.count; ++i) {
        Polygon polygon = polygons.data[i];
        Shape shape = shapes[i];
        fprintf(polygon_file, "polygon %d %s segments", i + 1, polygon.kind);
        for (int j = 0; j < polygon.count; ++j)
            fprintf(polygon_file, " %d", polygon.segments[j] + 1);
        I area = absolute(polygon.sigma);
        fprintf(polygon_file,
                " area %" PRId64 ".%d pixels %" PRId64 " mean %" PRId64 " contrast %" PRId64 " inside %s\n",
                area / 2, area % 2 ? 5 : 0, shape.pixels, shape.mean, shape.contrast,
                shape_name(shape.parent, shapes));
        for (int v = 0; v < polygon.count; ++v)
            fprintf(polygon_file, "vertex %d %" PRId64 " %" PRId64 " angle %" PRId64 " corner %s\n", v + 1,
                    polygon.vertices[v].x, polygon.vertices[v].y, polygon.angles[v],
                    polygon.corners[v] < 0 ? "none" : format("%d", polygon.corners[v] + 1));
        for (int side = 0; side < polygon.count; ++side)
            fprintf(polygon_file, "side %d segment %d length2 %" PRId64 " support %" PRId64 "\n", side + 1,
                    polygon.segments[side] + 1, polygon.lengths[side], polygon.support[side]);
    }
    fprintf(corner_file, "corners %d\n", corner_data.count);
    for (int i = 0; i < corner_data.count; ++i) {
        Corner corner = corner_data.values[i];
        fprintf(corner_file, "corner %d %" PRId64 " %" PRId64 " response %" PRId64 " match %s\n", i + 1,
                corner.point.x, corner.point.y, corner.response, corner_matches[i]);
    }
    fprintf(component_file, "components %d\n", edges.count);
    for (int i = 0; i < edges.count; ++i) {
        Points component = edges.components[i];
        I x0 = image.width - 1, y0 = image.height - 1, x1 = 0, y1 = 0, ends = 0, strength = 0,
          directions[4] = {0};
        for (int j = 0; j < component.count; ++j) {
            Point point = component.data[j];
            x0 = minimum(x0, point.x);
            y0 = minimum(y0, point.y);
            x1 = maximum(x1, point.x);
            y1 = maximum(y1, point.y);
            I neighbors = 0;
            for (I dy = -1; dy <= 1; ++dy)
                for (I dx = -1; dx <= 1; ++dx) {
                    Point next = {point.x + dx, point.y + dy};
                    if ((dx || dy) && image_inside(image, next) && image_at(edges.edges, next))
                        ++neighbors;
                }
            ends += neighbors == 1;
            strength += image_at(g.magnitude, point);
            ++directions[image_at(edges.direction, point) / 45];
        }
        int direction = 0;
        for (int j = 1; j < 4; ++j)
            if (directions[j] > directions[direction])
                direction = j;
        fprintf(component_file,
                "component %d pixels %d box %" PRId64 " %" PRId64 " %" PRId64 " %" PRId64 " ends %" PRId64
                " strength %" PRId64 " direction %d shape %s explained %" PRId64 "\n",
                i + 1, component.count, x0, y0, x1, y1, ends, floor_div(strength, component.count),
                45 * direction, shape_name(component_shapes[i], shapes), explained_counts[i]);
    }
    const char *names[] = {"gradient_nonzero",
                           "gradient_max",
                           "nms_kept",
                           "strong",
                           "weak",
                           "edges",
                           "weak_kept",
                           "weak_dropped",
                           "edge_components",
                           "direction_0",
                           "direction_45",
                           "direction_90",
                           "direction_135",
                           "circle_candidates",
                           "circle_peaks",
                           "circles",
                           "circle_edge_pixels",
                           "line_edge_pixels",
                           "hough_max_votes",
                           "hough_peaks",
                           "lines",
                           "segments",
                           "claimed_pixels",
                           "junctions",
                           "polygons",
                           "equilateral_triangle",
                           "right_triangle",
                           "triangle",
                           "square",
                           "rectangle",
                           "parallelogram",
                           "trapezoid",
                           "quadrilateral",
                           "corner_candidates",
                           "corners",
                           "corners_on_vertices",
                           "corners_on_segments",
                           "corners_unmatched",
                           "vertices_with_corner"};
    I counts[39] = {0};
    for (int i = 0; i < image.width * image.height; ++i) {
        counts[0] += g.magnitude.data[i] > 0;
        counts[1] = maximum(counts[1], g.magnitude.data[i]);
        counts[2] += edges.nms.data[i] > 0;
        counts[5] += edges.edges.data[i];
        counts[6] += edges.edges.data[i] && edges.nms.data[i] >= p.low && edges.nms.data[i] < p.high;
        counts[22] += claimed.data[i];
        if (edges.edges.data[i])
            ++counts[9 + edges.direction.data[i] / 45];
    }
    counts[3] = edges.strong;
    counts[4] = edges.weak;
    counts[7] = edges.weak - counts[6];
    counts[8] = edges.count;
    counts[13] = circle_data.candidates;
    counts[14] = circle_data.peak_count;
    counts[15] = circle_count;
    counts[16] = circle_edge_pixels;
    counts[17] = counts[5] - circle_edge_pixels;
    counts[18] = line_data.maximum;
    counts[19] = line_data.peak_count;
    counts[20] = line_count;
    counts[21] = segments.count;
    counts[23] = junctions.count;
    counts[24] = polygons.count;
    for (int i = 0; i < polygons.count; ++i)
        for (int kind = 25; kind <= 32; ++kind)
            if (!strcmp(polygons.data[i].kind, names[kind]))
                ++counts[kind];
    counts[33] = corner_data.candidates;
    counts[34] = corner_data.count;
    counts[35] = corner_vertices;
    counts[36] = corner_segments;
    counts[37] = corner_data.count - corner_vertices - corner_segments;
    counts[38] = vertices_with_corner;
    fprintf(report, "image %d %d\n", image.width, image.height);
    for (int i = 0; i < 39; ++i)
        fprintf(report, "%s %" PRId64 "\n", names[i], counts[i]);
    fclose(line_file);
    fclose(circle_file);
    fclose(polygon_file);
    fclose(corner_file);
    fclose(component_file);
    fclose(report);
    release_all();
    return 0;
}
