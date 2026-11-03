#include "geometry.h"
#include <errno.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void *resize(void *pointer, size_t size) {
    void *result = realloc(pointer, size ? size : 1);
    if (!result) {
        fputs("allocation failed\n", stderr);
        exit(EXIT_FAILURE);
    }
    return result;
}
void *allocate(size_t size) { return resize(NULL, size); }
char *copy_text(const char *value) {
    char *result = allocate(strlen(value) + 1);
    strcpy(result, value);
    return result;
}
static char *format_arguments(const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (length < 0)
        exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, format, args);
    return result;
}
char *format_text(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *result = format_arguments(format, args);
    va_end(args);
    return result;
}
void text_add(Text *text, const char *part) {
    size_t length = strlen(part), needed = text->count + length + 1;
    if (needed > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 128;
        while (capacity < needed)
            capacity *= 2;
        text->data = resize(text->data, capacity);
        text->capacity = capacity;
    }
    memcpy(text->data + text->count, part, length + 1);
    text->count += length;
}
void text_format(Text *text, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *part = format_arguments(format, args);
    va_end(args);
    text_add(text, part);
    free(part);
}
char *text_take(Text *text) {
    char *result = text->data ? text->data : copy_text("");
    *text = (Text){0};
    return result;
}
void lines_add(Lines *lines, char *value) {
    if (lines->count == lines->capacity) {
        lines->capacity = lines->capacity ? 2 * lines->capacity : 64;
        lines->items = resize(lines->items, lines->capacity * sizeof(char *));
    }
    lines->items[lines->count++] = value;
}
void line(Lines *lines, const char *format, ...) {
    va_list args;
    va_start(args, format);
    lines_add(lines, format_arguments(format, args));
    va_end(args);
}
void lines_take(Lines *out, Lines input) {
    for (size_t i = 0; i < input.count; ++i)
        lines_add(out, input.items[i]);
    free(input.items);
}
void lines_free(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
    *lines = (Lines){0};
}
Words words(const char *text) {
    Words result = {.storage = copy_text(text)};
    char *part = result.storage;
    for (;;) {
        result.items = resize(result.items, (result.count + 1) * sizeof(char *));
        result.items[result.count++] = part;
        char *space = strchr(part, ' ');
        if (!space)
            break;
        *space = 0;
        part = space + 1;
    }
    return result;
}
void words_free(Words *words) {
    free(words->items);
    free(words->storage);
}
static FILE *open_file(const char *path, const char *mode) {
    FILE *file = fopen(path, mode);
    if (!file) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    return file;
}
Lines read_lines(const char *path) {
    Lines result = {0};
    FILE *file = open_file(path, "r");
    for (;;) {
        Text text = {0};
        int c;
        while ((c = fgetc(file)) != EOF && c != '\n') {
            char part[2] = {(char)c, 0};
            text_add(&text, part);
        }
        if (c == EOF && !text.count) {
            free(text.data);
            break;
        }
        lines_add(&result, text_take(&text));
    }
    fclose(file);
    return result;
}
void write_lines(const char *name, const Lines *lines) {
    char *path = format_text("output/%s", name);
    FILE *file = open_file(path, "w");
    free(path);
    for (size_t i = 0; i < lines->count; ++i)
        fprintf(file, "%s\n", lines->items[i]);
    fclose(file);
}
static const char *const kinds[] = {"UNION",  "INTERSECTION", "DIFFERENCE", "XOR",
                                    "CLIP",   "AREA",         "MOVE",       "ROTATE",
                                    "MIRROR", "SNAP",         "LOCATE",     "RENDER"};
static int kind_index(const char *name) {
    for (int i = 0; i < 12; ++i)
        if (strcmp(name, kinds[i]) == 0)
            return i;
    return -1;
}
static bool ignored(const char *text) { return !*text || *text == '#'; }
static bool unsigned_word(const char *text) {
    size_t size = strlen(text);
    if (size < 1 || size > 9)
        return false;
    for (; *text; ++text)
        if (*text < '0' || *text > '9')
            return false;
    return true;
}
static bool integer_word(const char *text) { return unsigned_word(*text == '-' ? text + 1 : text); }
static Integer integer(const char *text) { return strtoll(text, NULL, 10); }
static bool name_word(const char *text) {
    size_t size = strlen(text);
    if (size < 1 || size > 16)
        return false;
    for (; *text; ++text)
        if (!((*text >= 'a' && *text <= 'z') || (*text >= '0' && *text <= '9') || *text == '_'))
            return false;
    return true;
}
static bool in_range(Point p) {
    return fraction_compare(point_x(p), fraction(0, 1)) >= 0 &&
           fraction_compare(point_x(p), fraction(1000, 1)) <= 0 &&
           fraction_compare(point_y(p), fraction(0, 1)) >= 0 &&
           fraction_compare(point_y(p), fraction(1000, 1)) <= 0;
}
typedef struct {
    int number;
    const char *text;
} SourceLine;
static Rings parse_block(const SourceLine *content, size_t count, int end, int *error) {
    Rings rings = {0};
    size_t at = 0;
    *error = 0;
    while (at < count) {
        SourceLine header = content[at];
        Words a = words(header.text);
        bool valid = a.count == 2 &&
                     (!strcmp(a.items[0], "OUTER") || !strcmp(a.items[0], "HOLE")) &&
                     unsigned_word(a.items[1]) && integer(a.items[1]) >= 1 &&
                     !(strcmp(a.items[0], "OUTER") == 0 && rings.count) &&
                     !(strcmp(a.items[0], "HOLE") == 0 && !rings.count);
        if (!valid) {
            words_free(&a);
            *error = header.number;
            rings_free(&rings);
            return rings;
        }
        Integer vertices = integer(a.items[1]);
        words_free(&a);
        ++at;
        Ring *ring = ring_new();
        for (Integer i = 0; i < vertices; ++i) {
            if (at == count) {
                *error = end;
                ring_release(ring);
                rings_free(&rings);
                return rings;
            }
            SourceLine source = content[at++];
            a = words(source.text);
            if (a.count != 2 || !integer_word(a.items[0]) || !integer_word(a.items[1])) {
                *error = source.number;
                words_free(&a);
                ring_release(ring);
                rings_free(&rings);
                return rings;
            }
            ring_point(ring, point(integer(a.items[0]), integer(a.items[1]), 1));
            words_free(&a);
        }
        ring_complete_integer(ring);
        rings_add(&rings, ring);
    }
    if (!rings.count)
        *error = end;
    return rings;
}
static char *check_polygon(const Rings *rings) {
    char p[96], first[192], second[192];
    for (size_t k = 0; k < rings->count; ++k) {
        Ring *ring = rings->items[k];
        size_t n = ring->count;
        if (n < 3)
            return format_text("too_few_vertices ring %zu", k + 1);
        for (size_t i = 0; i < n; ++i)
            if (!in_range(ring->points[i]))
                return format_text("out_of_range ring %zu %s", k + 1,
                                   point_text(ring->points[i], p));
        for (size_t j = 0; j < n; ++j)
            for (size_t i = 0; i < j; ++i)
                if (point_equal(ring->points[j], ring->points[i]))
                    return format_text("duplicate_vertex ring %zu %s", k + 1,
                                       point_text(ring->points[j], p));
        for (size_t i = 0; i < n; ++i)
            if (integer_cross(ring->points[(i + n - 1) % n], ring->points[i],
                              ring->points[(i + 1) % n]) == 0)
                return format_text("collinear ring %zu %s", k + 1, point_text(ring->points[i], p));
        for (size_t i = 0; i < n; ++i)
            for (size_t j = i + 1; j < n; ++j) {
                if (j == i + 1 || (i == 0 && j == n - 1))
                    continue;
                if (touching(ring->points[i], ring->points[(i + 1) % n], ring->points[j],
                             ring->points[(j + 1) % n]))
                    return format_text(
                        "self_intersection ring %zu %s %s", k + 1,
                        segment_text(ring->points[i], ring->points[(i + 1) % n], first),
                        segment_text(ring->points[j], ring->points[(j + 1) % n], second));
            }
    }
    for (size_t i = 0; i < rings->count; ++i)
        for (size_t j = i + 1; j < rings->count; ++j) {
            Ring *a = rings->items[i], *b = rings->items[j];
            for (size_t e = 0; e < a->count; ++e)
                for (size_t f = 0; f < b->count; ++f)
                    if (touching(a->points[e], a->points[(e + 1) % a->count], b->points[f],
                                 b->points[(f + 1) % b->count]))
                        return format_text(
                            "rings_touch rings %zu %zu %s %s", i + 1, j + 1,
                            segment_text(a->points[e], a->points[(e + 1) % a->count], first),
                            segment_text(b->points[f], b->points[(f + 1) % b->count], second));
        }
    for (size_t k = 1; k < rings->count; ++k)
        if (!inside_ring(rings->items[k]->points[0], rings->items[0]))
            return format_text("hole_outside ring %zu %s", k + 1,
                               point_text(rings->items[k]->points[0], p));
    for (size_t i = 1; i < rings->count; ++i)
        for (size_t j = i + 1; j < rings->count; ++j) {
            if (inside_ring(rings->items[j]->points[0], rings->items[i]))
                return format_text("hole_in_hole rings %zu %zu %s", i + 1, j + 1,
                                   point_text(rings->items[j]->points[0], p));
            if (inside_ring(rings->items[i]->points[0], rings->items[j]))
                return format_text("hole_in_hole rings %zu %zu %s", i + 1, j + 1,
                                   point_text(rings->items[i]->points[0], p));
        }
    return NULL;
}
static char *general_position(const Polygon *a, const Polygon *b, const char *a_name,
                              const char *b_name) {
    char p[96], first[192], second[192];
    for (size_t i = 0; i < a->rings.count; ++i)
        for (size_t e = 0; e < a->rings.items[i]->count; ++e) {
            Point vertex = a->rings.items[i]->points[e];
            for (size_t j = 0; j < b->rings.count; ++j)
                for (size_t f = 0; f < b->rings.items[j]->count; ++f)
                    if (point_equal(vertex, b->rings.items[j]->points[f]))
                        return format_text("shared_vertex %s", point_text(vertex, p));
        }
    for (size_t i = 0; i < a->rings.count; ++i) {
        Ring *r = a->rings.items[i];
        for (size_t e = 0; e < r->count; ++e)
            for (size_t j = 0; j < b->rings.count; ++j) {
                Ring *s = b->rings.items[j];
                for (size_t f = 0; f < s->count; ++f)
                    if (overlapping(r->points[e], r->points[(e + 1) % r->count], s->points[f],
                                    s->points[(f + 1) % s->count]))
                        return format_text(
                            "overlapping_edges %s %s",
                            segment_text(r->points[e], r->points[(e + 1) % r->count], first),
                            segment_text(s->points[f], s->points[(f + 1) % s->count], second));
            }
    }
    for (int side = 0; side < 2; ++side) {
        const Polygon *one = side ? b : a, *two = side ? a : b;
        for (size_t i = 0; i < one->rings.count; ++i) {
            Ring *r = one->rings.items[i];
            for (size_t v = 0; v < r->count; ++v)
                for (size_t j = 0; j < two->rings.count; ++j) {
                    Ring *s = two->rings.items[j];
                    for (size_t e = 0; e < s->count; ++e)
                        if (on_edge(r->points[v], s, e))
                            return format_text(
                                "vertex_on_edge %s %s %s %s", side ? b_name : a_name,
                                point_text(r->points[v], p), side ? a_name : b_name,
                                segment_text(s->points[e], s->points[(e + 1) % s->count], first));
                }
        }
    }
    return NULL;
}
static bool numeric(const char *text, Integer low, Integer high) {
    return integer_word(text) && integer(text) >= low && integer(text) <= high;
}
static bool valid_arguments(const Words *a, int kind) {
    static const size_t required[] = {3, 3, 3, 3, 3, 2, 5, 6, 5, 3, 4, 8};
    if (a->count != required[kind])
        return false;
    char **v = a->items;
    if (kind == 10)
        return numeric(v[2], 0, 1000) && numeric(v[3], 0, 1000);
    if (kind == 6)
        return numeric(v[2], -1000, 1000) && numeric(v[3], -1000, 1000) && name_word(v[4]);
    if (kind == 7)
        return numeric(v[2], 0, 1000) && numeric(v[3], 0, 1000) && numeric(v[4], 1, 3) &&
               name_word(v[5]);
    if (kind == 8)
        return (!strcmp(v[2], "x") || !strcmp(v[2], "y")) && numeric(v[3], 0, 1000) &&
               name_word(v[4]);
    if (kind == 9)
        return name_word(v[2]);
    if (kind == 11) {
        for (int i = 2; i < 8; ++i)
            if (!numeric(v[i], i >= 4 ? 1 : 0, i == 7 ? 60 : i >= 4 ? 100 : 1000))
                return false;
        return integer(v[2]) + integer(v[4]) * integer(v[6]) <= 1000 &&
               integer(v[3]) + integer(v[5]) * integer(v[7]) <= 1000;
    }
    return true;
}
static bool convex(const Polygon *polygon) {
    if (polygon->rings.count != 1)
        return false;
    Ring *ring = polygon->rings.items[0];
    for (size_t i = 0; i < ring->count; ++i)
        if (integer_cross(ring->points[(i + ring->count - 1) % ring->count], ring->points[i],
                          ring->points[(i + 1) % ring->count]) <= 0)
            return false;
    return true;
}
static Rings transformed(const Polygon *polygon, const Words *a, int kind) {
    Rings result = {0};
    for (size_t i = 0; i < polygon->input.count; ++i) {
        Ring *source = polygon->input.items[i], *ring = ring_new();
        for (size_t j = 0; j < source->count; ++j) {
            Integer x = source->points[j].x, y = source->points[j].y;
            if (kind == 6) {
                x += integer(a->items[2]);
                y += integer(a->items[3]);
            } else if (kind == 7) {
                Integer cx = integer(a->items[2]), cy = integer(a->items[3]);
                for (Integer q = 0; q < integer(a->items[4]); ++q) {
                    Integer nx = cx - (y - cy);
                    y = cy + (x - cx);
                    x = nx;
                }
            } else if (strcmp(a->items[2], "x") == 0)
                x = 2 * integer(a->items[3]) - x;
            else
                y = 2 * integer(a->items[3]) - y;
            ring_point(ring, point(x, y, 1));
        }
        ring_complete_integer(ring);
        rings_add(&result, ring);
    }
    return result;
}
static bool cyclic_equal(const Ring *a, const Ring *b) {
    if (a->count != b->count)
        return false;
    for (size_t offset = 0; offset < b->count; ++offset) {
        bool same = true;
        for (size_t i = 0; i < a->count; ++i)
            if (!point_equal(a->points[i], b->points[(offset + i) % b->count])) {
                same = false;
                break;
            }
        if (same)
            return true;
    }
    return false;
}
typedef struct {
    bool match;
    size_t rings, vertices;
} Crosscheck;
static Crosscheck sutherland(const Polygon *subject, const Polygon *window,
                             const PolygonList *result) {
    Rings clipped = {0};
    Ring *window_ring = window->rings.items[0];
    for (size_t r = 0; r < subject->rings.count; ++r) {
        Ring *list = ring_retain(subject->rings.items[r]);
        for (size_t j = 0; j < window_ring->count; ++j) {
            OriginalLine clip = window_ring->edges[j];
            Ring *next = ring_new();
            for (size_t i = 0; i < list->count; ++i) {
                size_t previous = (i + list->count - 1) % list->count;
                Point prev = list->points[previous], cur = list->points[i];
                OriginalLine edge = list->edges[previous];
                bool inside_prev = line_cross(clip, prev) > 0,
                     inside_cur = line_cross(clip, cur) > 0;
                if (inside_prev != inside_cur) {
                    ring_point(next, line_intersection(edge, clip));
                    ring_edge(next, inside_prev ? edge : clip);
                }
                if (inside_cur) {
                    ring_point(next, cur);
                    ring_edge(next, edge);
                }
            }
            if (next->count) {
                OriginalLine first = next->edges[0];
                memmove(next->edges, next->edges + 1, (next->count - 1) * sizeof(OriginalLine));
                next->edges[next->count - 1] = first;
            }
            ring_release(list);
            list = next;
        }
        size_t *kept = allocate(list->count * sizeof(size_t)), count = 0;
        for (size_t i = 0; i < list->count; ++i)
            if (!point_equal(list->points[i], list->points[(i + list->count - 1) % list->count]))
                kept[count++] = i;
        if (count >= 3) {
            Ring *deduplicated = ring_new();
            for (size_t i = 0; i < count; ++i) {
                ring_point(deduplicated, list->points[kept[i]]);
                size_t next = kept[(i + 1) % count];
                ring_edge(deduplicated, list->edges[(next + list->count - 1) % list->count]);
            }
            rings_add(&clipped, deduplicated);
        }
        free(kept);
        ring_release(list);
    }
    Crosscheck check = {.rings = clipped.count};
    for (size_t i = 0; i < clipped.count; ++i)
        check.vertices += clipped.items[i]->count;
    Rings rings = flatten(result);
    check.match = rings.count == clipped.count;
    if (check.match)
        for (size_t i = 0; i < rings.count; ++i) {
            bool found = false;
            for (size_t j = 0; j < clipped.count; ++j)
                if (cyclic_equal(rings.items[i], clipped.items[j])) {
                    found = true;
                    break;
                }
            if (!found) {
                check.match = false;
                break;
            }
        }
    rings_free(&rings);
    rings_free(&clipped);
    return check;
}
static char *location(const Result *result, Point p) {
    for (size_t k = 0; k < result->polygons.count; ++k) {
        Rings *rings = &result->polygons.items[k]->rings;
        for (size_t j = 0; j < rings->count; ++j)
            if (boundary(p, rings->items[j]))
                return j ? format_text("boundary hole %zu %zu", k + 1, j)
                         : format_text("boundary outer %zu", k + 1);
    }
    for (size_t k = 0; k < result->polygons.count; ++k) {
        Rings *rings = &result->polygons.items[k]->rings;
        if (!inside_ring(p, rings->items[0]))
            continue;
        bool hole = false;
        for (size_t j = 1; j < rings->count; ++j)
            hole = hole || inside_ring(p, rings->items[j]);
        if (!hole)
            return format_text("inside polygon %zu", k + 1);
    }
    return copy_text("outside");
}
static const char *operand_location(Point p, const Polygon *polygon) {
    for (size_t i = 0; i < polygon->rings.count; ++i)
        if (boundary(p, polygon->rings.items[i]))
            return "boundary";
    return interior(p, &polygon->rings) ? "inside" : "outside";
}
static Integer twice_area(const Ring *ring) {
    Integer sum = 0;
    for (size_t i = 0; i < ring->count; ++i) {
        Point a = ring->points[i], b = ring->points[(i + 1) % ring->count];
        sum += a.x * b.y - b.x * a.y;
    }
    return sum;
}
static int hull_compare(const void *left, const void *right) {
    Point a = *(const Point *)left, b = *(const Point *)right;
    if (a.x != b.x)
        return a.x < b.x ? -1 : 1;
    return (a.y > b.y) - (a.y < b.y);
}
static Ring *hull(const Ring *ring) {
    Point *sorted = allocate(ring->count * sizeof(Point)),
          *lower = allocate(ring->count * sizeof(Point)),
          *upper = allocate(ring->count * sizeof(Point));
    memcpy(sorted, ring->points, ring->count * sizeof(Point));
    qsort(sorted, ring->count, sizeof(Point), hull_compare);
    size_t lc = 0, uc = 0;
    for (size_t i = 0; i < ring->count; ++i) {
        Point p = sorted[i];
        while (lc >= 2 && integer_cross(lower[lc - 2], lower[lc - 1], p) <= 0)
            --lc;
        lower[lc++] = p;
    }
    for (size_t i = ring->count; i > 0; --i) {
        Point p = sorted[i - 1];
        while (uc >= 2 && integer_cross(upper[uc - 2], upper[uc - 1], p) <= 0)
            --uc;
        upper[uc++] = p;
    }
    Ring *result = ring_new();
    for (size_t i = 0; i + 1 < lc; ++i)
        ring_point(result, lower[i]);
    for (size_t i = 0; i + 1 < uc; ++i)
        ring_point(result, upper[i]);
    ring_complete_integer(result);
    free(sorted);
    free(lower);
    free(upper);
    return result;
}
typedef struct {
    char name[17];
    Polygon *polygon;
} NamedPolygon;
typedef struct {
    NamedPolygon names[300];
    int name_count;
    Result *results[201];
    Lines output, areas, rendered, polygon_errors, operation_errors;
    int blocks, valid, defined, operation_count, succeeded, crossing_count, counts[12],
        accepted[12];
} Laboratory;
static NamedPolygon *named_polygon(Laboratory *l, const char *name) {
    for (int i = 0; i < l->name_count; ++i)
        if (strcmp(l->names[i].name, name) == 0)
            return &l->names[i];
    return NULL;
}
static NamedPolygon *add_name(Laboratory *l, const char *name, Polygon *polygon) {
    NamedPolygon *entry = &l->names[l->name_count++];
    strcpy(entry->name, name);
    entry->polygon = polygon;
    return entry;
}
static void read_polygons(Laboratory *l) {
    Lines source = read_lines("input/polygons.txt");
    SourceLine *content = allocate(source.count * sizeof(SourceLine));
    for (size_t i = 0; i < source.count; ++i) {
        if (ignored(source.items[i]))
            continue;
        int start = (int)i + 1;
        Words header = words(source.items[i]);
        char name[17];
        strcpy(name, header.items[1]);
        words_free(&header);
        size_t count = 0;
        ++i;
        for (; strcmp(source.items[i], "END"); ++i)
            if (!ignored(source.items[i]))
                content[count++] = (SourceLine){(int)i + 1, source.items[i]};
        int end = (int)i + 1;
        ++l->blocks;
        char *reason = NULL;
        if (named_polygon(l, name))
            reason = format_text("duplicate_name line %d", start);
        else {
            NamedPolygon *entry = add_name(l, name, NULL);
            int error;
            Rings rings = parse_block(content, count, end, &error);
            if (error)
                reason = format_text("format line %d", error);
            else {
                reason = check_polygon(&rings);
                if (!reason) {
                    entry->polygon = canonical(&rings);
                    ++l->valid;
                }
            }
            rings_free(&rings);
        }
        if (reason) {
            line(&l->polygon_errors, "polygon %s %s", name, reason);
            free(reason);
        }
    }
    free(content);
    lines_free(&source);
}
static Polygon *resolve_polygon(Laboratory *l, const char *name, char **reason) {
    NamedPolygon *entry = named_polygon(l, name);
    if (!entry)
        *reason = format_text("unknown_polygon %s", name);
    else if (!entry->polygon)
        *reason = format_text("invalid_polygon %s", name);
    return entry ? entry->polygon : NULL;
}
static Result resolve_target(Laboratory *l, const char *name, char **reason) {
    if (name[0] == '@') {
        if (unsigned_word(name + 1)) {
            Integer number = integer(name + 1);
            if (number >= 1 && number <= 200 && l->results[number])
                return result_copy(l->results[number]);
        }
        *reason = format_text("bad_target %s", name);
        return (Result){0};
    }
    Polygon *polygon = resolve_polygon(l, name, reason);
    Result result = {0};
    if (polygon)
        polygon_list_add(&result.polygons, polygon_retain(polygon));
    return result;
}
static bool has_vertex(const Polygon *polygon, Point p) {
    if (!polygon)
        return false;
    for (size_t i = 0; i < polygon->rings.count; ++i) {
        Ring *ring = polygon->rings.items[i];
        for (size_t j = 0; j < ring->count; ++j)
            if (point_equal(p, ring->points[j]))
                return true;
    }
    return false;
}
static void report_region(Laboratory *l, int number, const Words *a, const char *source,
                          const Result *result, const Polygon *origin_a, const Polygon *origin_b,
                          const Polygon *property, const GhGraph *graph) {
    line(&l->output, "op %d %s", number, source);
    if (graph) {
        const char *relation = "overlap";
        if (!graph->order_count) {
            if (graph->na == (int)graph->rings[0].count && graph->nb == 0)
                relation = "within";
            else if (graph->nb == (int)graph->rings[1].count && graph->na == 0)
                relation = "contains";
            else if (graph->na == 0 && graph->nb == 0)
                relation = "disjoint";
        }
        Rings intersection_rings = traverse(graph, false, false),
              union_rings = traverse(graph, true, true);
        PolygonList intersection = assemble(&intersection_rings), united = assemble(&union_rings);
        line(&l->output, "relation %s iou %.6f", relation,
             total_area(&intersection) / total_area(&united));
        rings_free(&intersection_rings);
        rings_free(&union_rings);
        polygon_list_free(&intersection);
        polygon_list_free(&united);
        line(&l->output, "crossings %zu", graph->order_count);
        for (size_t i = 0; i < graph->order_count; ++i) {
            Crossing *c = graph->crossings[i];
            char p[96];
            line(&l->output, "crossing %s %s", point_text(c->point, p),
                 c->first->entering ? "in" : "out");
        }
        l->crossing_count += (int)graph->order_count;
    }
    Rings rings = flatten(&result->polygons);
    size_t vertices = 0, holes = rings.count - result->polygons.count;
    for (size_t i = 0; i < rings.count; ++i)
        vertices += rings.items[i]->count;
    double area = total_area(&result->polygons);
    line(&l->output, "polygons %zu rings %zu holes %zu vertices %zu area %.3f",
         result->polygons.count, rings.count, holes, vertices, area);
    for (size_t k = 0; k < result->polygons.count; ++k) {
        Rings *sequence = &result->polygons.items[k]->rings;
        for (size_t j = 0; j < sequence->count; ++j) {
            Ring *ring = sequence->items[j];
            Text text = {0};
            if (j)
                text_format(&text, "hole %zu %zu", k + 1, j);
            else
                text_format(&text, "outer %zu", k + 1);
            text_format(&text, " %zu %.3f", ring->count, ring_area(ring));
            for (size_t i = 0; i < ring->count; ++i) {
                char p[96];
                text_format(&text, " %s", point_text(ring->points[i], p));
            }
            lines_add(&l->output, text_take(&text));
        }
    }
    double perimeter = 0.0, sx = 0.0, sy = 0.0;
    Fraction low_x = {0, 1}, low_y = {0, 1}, high_x = {0, 1}, high_y = {0, 1};
    bool has_point = false;
    for (size_t r = 0; r < rings.count; ++r) {
        Ring *ring = rings.items[r];
        perimeter += ring_perimeter(ring);
        for (size_t i = 0; i < ring->count; ++i) {
            Point p = ring->points[i], q = ring->points[(i + 1) % ring->count];
            Fraction x = point_x(p), y = point_y(p);
            if (!has_point) {
                low_x = high_x = x;
                low_y = high_y = y;
                has_point = true;
            }
            if (fraction_compare(x, low_x) < 0)
                low_x = x;
            if (fraction_compare(y, low_y) < 0)
                low_y = y;
            if (fraction_compare(x, high_x) > 0)
                high_x = x;
            if (fraction_compare(y, high_y) > 0)
                high_y = y;
            double x1 = fraction_real(x), y1 = fraction_real(y), x2 = fraction_real(point_x(q)),
                   y2 = fraction_real(point_y(q)), c = x1 * y2 - x2 * y1;
            sx += (x1 + x2) * c;
            sy += (y1 + y2) * c;
        }
    }
    if (has_point) {
        char f[4][64];
        line(&l->output, "bbox (%s,%s) (%s,%s)", fraction_text(low_x, f[0]),
             fraction_text(low_y, f[1]), fraction_text(high_x, f[2]), fraction_text(high_y, f[3]));
        line(&l->output, "centroid (%.3f,%.3f)", sx / (6.0 * area), sy / (6.0 * area));
    } else {
        line(&l->output, "bbox none");
        line(&l->output, "centroid none");
    }
    line(&l->output, "perimeter %.3f", perimeter);
    int ac = 0, bc = 0, cc = 0;
    for (size_t r = 0; r < rings.count; ++r)
        for (size_t i = 0; i < rings.items[r]->count; ++i) {
            Point p = rings.items[r]->points[i];
            if (has_vertex(origin_a, p))
                ++ac;
            else if (has_vertex(origin_b, p))
                ++bc;
            else
                ++cc;
        }
    line(&l->output, "origins a %d b %d crossing %d", ac, bc, cc);
    if (property) {
        Text orientations = {0};
        text_add(&orientations, "input");
        for (size_t i = 0; i < property->input.count; ++i)
            text_format(&orientations, " %s",
                        twice_area(property->input.items[i]) > 0 ? "ccw" : "cw");
        lines_add(&l->output, text_take(&orientations));
        int reflex = 0;
        for (size_t r = 0; r < property->rings.count; ++r) {
            Ring *ring = property->rings.items[r];
            for (size_t i = 0; i < ring->count; ++i)
                if (integer_cross(ring->points[(i + ring->count - 1) % ring->count],
                                  ring->points[i], ring->points[(i + 1) % ring->count]) < 0)
                    ++reflex;
        }
        Ring *convex_hull = hull(property->rings.items[0]);
        double hull_area = (double)twice_area(convex_hull) / 2.0;
        line(&l->output, "reflex %d", reflex);
        line(&l->output, "hull %zu %.3f solidity %.6f", convex_hull->count, hull_area,
             area / hull_area);
        ring_release(convex_hull);
    }
    if (strcmp(a->items[0], "CLIP") == 0) {
        Crosscheck check = sutherland(result->a, result->b, &result->polygons);
        line(&l->output, "crosscheck %s rings %zu vertices %zu", check.match ? "match" : "mismatch",
             check.rings, check.vertices);
    }
    Text label = {0};
    text_format(&label, "%d", number);
    for (size_t i = 0; i < a->count; ++i)
        text_format(&label, ":%s", a->items[i]);
    text_format(&label, ",%zu,%zu,%zu,%.3f", rings.count, holes, vertices, area);
    lines_add(&l->areas, text_take(&label));
    rings_free(&rings);
}
static int polygon_compare(const void *left, const void *right) {
    const Polygon *a = *(Polygon *const *)left, *b = *(Polygon *const *)right;
    Point p = a->rings.items[0]->points[0], q = b->rings.items[0]->points[0];
    return point_less(p, q) ? -1 : point_less(q, p) ? 1 : 0;
}
static char *operation(Laboratory *l, int number, const char *source) {
    Words a = words(source);
    int kind = kind_index(a.items[0]);
    char *reason = NULL;
    if (kind < 0) {
        reason = format_text("unknown_operation %s", a.items[0]);
        words_free(&a);
        return reason;
    }
    if (!valid_arguments(&a, kind)) {
        words_free(&a);
        return copy_text("bad_arguments");
    }
    bool binary = kind <= 4, definition = kind >= 6 && kind <= 9;
    Polygon *first = NULL, *second = NULL, *property = NULL;
    Result target = {0};
    if (binary || kind == 5 || (kind >= 6 && kind <= 8)) {
        first = resolve_polygon(l, a.items[1], &reason);
        if (reason)
            goto finish;
        if (binary) {
            second = resolve_polygon(l, a.items[2], &reason);
            if (reason)
                goto finish;
        }
    } else {
        target = resolve_target(l, a.items[1], &reason);
        if (reason)
            goto finish;
    }
    const char *new_name = definition ? a.items[a.count - 1] : "";
    if (definition && named_polygon(l, new_name)) {
        reason = format_text("duplicate_name %s", new_name);
        goto finish;
    }
    if (kind == 9 && target.polygons.count != 1) {
        reason = format_text("not_single %s", a.items[1]);
        goto finish;
    }
    if (kind == 4 && !convex(second)) {
        reason = format_text("not_convex %s", a.items[2]);
        goto finish;
    }
    if (binary) {
        reason = general_position(first, second, a.items[1], a.items[2]);
        if (reason)
            goto finish;
    }
    if (definition) {
        Rings input = {0};
        if (kind == 9) {
            Rings *sequence = &target.polygons.items[0]->rings;
            for (size_t r = 0; r < sequence->count; ++r) {
                Ring *ring = ring_new(), *old = sequence->items[r];
                for (size_t i = 0; i < old->count; ++i)
                    ring_point(ring, point(fraction_round(point_x(old->points[i])),
                                           fraction_round(point_y(old->points[i])), 1));
                ring_complete_integer(ring);
                rings_add(&input, ring);
            }
            char *error = check_polygon(&input);
            if (error) {
                reason = format_text("invalid_result %s", error);
                free(error);
                rings_free(&input);
                goto finish;
            }
        } else {
            input = transformed(first, &a, kind);
            bool valid = true;
            for (size_t r = 0; r < input.count; ++r)
                for (size_t i = 0; i < input.items[r]->count; ++i)
                    if (!in_range(input.items[r]->points[i]))
                        valid = false;
            if (!valid) {
                reason = format_text("out_of_range %s", new_name);
                rings_free(&input);
                goto finish;
            }
        }
        property = canonical(&input);
        rings_free(&input);
        add_name(l, new_name, property);
        ++l->defined;
    }
    ++l->succeeded;
    ++l->accepted[kind];
    if (kind == 10) {
        Point p = point(integer(a.items[2]), integer(a.items[3]), 1);
        char *where = location(&target, p);
        line(&l->output, "op %d %s", number, source);
        line(&l->output, "location %s", where);
        free(where);
        if (target.a && target.b)
            line(&l->output, "operands a %s b %s", operand_location(p, target.a),
                 operand_location(p, target.b));
        goto finish;
    }
    if (kind == 11) {
        Rendered picture = render(&target, (int)integer(a.items[2]), (int)integer(a.items[3]),
                                  (int)integer(a.items[4]), (int)integer(a.items[5]),
                                  (int)integer(a.items[6]), (int)integer(a.items[7]));
        line(&l->rendered, "render %d %s cols %lld rows %lld result %d a %d b %d both %d", number,
             a.items[1], integer(a.items[6]), integer(a.items[7]), picture.result, picture.a,
             picture.b, picture.both);
        lines_take(&l->rendered, picture.rows);
        goto finish;
    }
    Result *result = allocate(sizeof(*result));
    *result = (Result){0};
    GhGraph *graph = NULL;
    Polygon *origin_a = first, *origin_b = second;
    if (binary) {
        graph = graph_new(&first->rings, &second->rings);
        Rings traversed = traverse(graph, kind == 0 || kind == 2 || kind == 3, kind == 0);
        result->polygons = assemble(&traversed);
        rings_free(&traversed);
        if (kind == 3) {
            GhGraph *other = graph_new(&second->rings, &first->rings);
            traversed = traverse(other, true, false);
            PolygonList extra = assemble(&traversed);
            rings_free(&traversed);
            for (size_t i = 0; i < extra.count; ++i)
                polygon_list_add(&result->polygons, extra.items[i]);
            free(extra.items);
            graph_free(other);
            if (result->polygons.count)
                qsort(result->polygons.items, result->polygons.count, sizeof(Polygon *),
                      polygon_compare);
        }
        result->a = polygon_retain(first);
        result->b = polygon_retain(second);
    } else {
        if (!definition)
            property = first;
        origin_a = property;
        origin_b = NULL;
        polygon_list_add(&result->polygons, polygon_retain(property));
    }
    l->results[number] = result;
    report_region(l, number, &a, source, result, origin_a, origin_b, property, graph);
    if (graph)
        graph_free(graph);
finish:
    result_free(&target);
    words_free(&a);
    return reason;
}
int main(void) {
    Laboratory *l = allocate(sizeof(*l));
    memset(l, 0, sizeof(*l));
    line(&l->areas, "operation,rings,holes,vertices,area");
    read_polygons(l);
    Lines source = read_lines("input/operations.txt");
    for (size_t i = 0; i < source.count; ++i) {
        if (ignored(source.items[i]))
            continue;
        ++l->operation_count;
        Words a = words(source.items[i]);
        int kind = kind_index(a.items[0]);
        if (kind >= 0)
            ++l->counts[kind];
        words_free(&a);
        char *reason = operation(l, l->operation_count, source.items[i]);
        if (reason) {
            line(&l->operation_errors, "op %d %s", l->operation_count, reason);
            free(reason);
        }
    }
    lines_free(&source);
    line(&l->output, "summary polygons %d valid %d invalid %d defined %d", l->blocks, l->valid,
         l->blocks - l->valid, l->defined);
    line(&l->output, "summary operations %d succeeded %d rejected %zu", l->operation_count,
         l->succeeded, l->operation_errors.count);
    line(&l->output, "summary crossings %d", l->crossing_count);
    for (int i = 0; i < 12; ++i)
        line(&l->output, "kind %s %d %d", kinds[i], l->counts[i], l->accepted[i]);
    Lines rejections = {0};
    line(&rejections, "rejections %zu", l->polygon_errors.count + l->operation_errors.count);
    lines_take(&rejections, l->polygon_errors);
    lines_take(&rejections, l->operation_errors);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        exit(EXIT_FAILURE);
    }
    write_lines("results.txt", &l->output);
    write_lines("areas.csv", &l->areas);
    write_lines("render.txt", &l->rendered);
    write_lines("rejections.txt", &rejections);
    lines_free(&l->output);
    lines_free(&l->areas);
    lines_free(&l->rendered);
    lines_free(&rejections);
    for (int i = 0; i < l->name_count; ++i)
        polygon_release(l->names[i].polygon);
    for (int i = 1; i <= 200; ++i)
        if (l->results[i]) {
            result_free(l->results[i]);
            free(l->results[i]);
        }
    free(l);
    return EXIT_SUCCESS;
}
