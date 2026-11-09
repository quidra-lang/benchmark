#include "spatial.h"
static const char *structures[] = {"kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect"},
                  *search_names[] = {"RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"},
                  *quadrants[] = {"NW", "NE", "SW", "SE"};
typedef struct View {
    Box region;
    Objects objects;
    struct View **children;
    int nchildren, capacity, depth;
    Integer count;
    const char *mark;
    const KDNode *kd;
    const QuadNode *quad;
    const RNode *rtree;
} View;
static View *new_view(void) {
    return calloc(1, sizeof(View));
}
static void child_add(View *node, View *child) {
    if (node->nchildren == node->capacity) {
        node->capacity = node->capacity ? node->capacity * 2 : 4;
        node->children = realloc(node->children, (size_t)node->capacity * sizeof *node->children);
    }
    node->children[node->nchildren++] = child;
    node->count += child->count;
}
static View *kd_view(const KDNode *node, Box region, const char *mark) {
    View *out = new_view();
    out->region = region;
    out->depth = node->depth;
    out->mark = mark;
    out->kd = node;
    objects_push(&out->objects, (Object){node->point.id, point_box(node->point)});
    out->count = 1;
    if (node->left) {
        Box left = region;
        if (node->depth % 2 == 0)
            left.x2 = node->point.x;
        else
            left.y2 = node->point.y;
        child_add(out, kd_view(node->left, left, "L"));
    }
    if (node->right) {
        Box right = region;
        if (node->depth % 2 == 0)
            right.x1 = node->point.x;
        else
            right.y1 = node->point.y;
        child_add(out, kd_view(node->right, right, "R"));
    }
    return out;
}
static View *quad_view(const QuadNode *node, int depth, const char *mark) {
    View *out = new_view();
    out->region = (Box){node->x, node->y, node->x + node->size - 1, node->y + node->size - 1};
    out->depth = depth;
    out->mark = mark;
    out->quad = node;
    if (!node->children[0]) {
        for (int i = 0; i < node->points.n; ++i) {
            const Point point = node->points.v[i];
            objects_push(&out->objects, (Object){point.id, point_box(point)});
        }
        out->count = out->objects.n;
    } else
        for (int i = 0; i < 4; ++i)
            child_add(out, quad_view(node->children[i], depth + 1, quadrants[i]));
    return out;
}
static View *r_view(const RNode *node, int depth) {
    View *out = new_view();
    out->region = node_box(node);
    out->depth = depth;
    out->rtree = node;
    if (node->level == 0) {
        for (int i = 0; i < node->n; ++i)
            objects_push(&out->objects, (Object){node->entries[i].id, node->entries[i].box});
        out->count = out->objects.n;
    } else
        for (int i = 0; i < node->n; ++i)
            child_add(out, r_view(node->entries[i].child, depth + 1));
    return out;
}
static View *grid_view(const Grid *grid) {
    View *out = new_view();
    out->region = (Box){0, 0, grid->world - 1, grid->world - 1};
    for (int j = 0; j < grid->dimension; ++j)
        for (int i = 0; i < grid->dimension; ++i) {
            View *cell = new_view();
            cell->region = (Box){i * grid->side, j * grid->side, i * grid->side + grid->side - 1,
                                 j * grid->side + grid->side - 1};
            cell->depth = 1;
            const Points *points = &grid->cells[j * grid->dimension + i];
            for (int k = 0; k < points->n; ++k)
                objects_push(&cell->objects, (Object){points->v[k].id, point_box(points->v[k])});
            cell->count = cell->objects.n;
            child_add(out, cell);
        }
    return out;
}
static void views(View **roots, const KDNode *kd, const QuadNode *quad, const RTree *rtree, const RTree *str,
                  const Grid *grid, const RTree *rect, const RTree *str_rect, int world) {
    roots[0] = kd_view(kd, (Box){0, 0, world - 1, world - 1}, "root");
    roots[1] = quad_view(quad, 0, "root");
    roots[2] = r_view(rtree->root, 0);
    roots[3] = r_view(str->root, 0);
    roots[4] = grid_view(grid);
    roots[5] = r_view(rect->root, 0);
    roots[6] = r_view(str_rect->root, 0);
}
static void view_free(View *node) {
    for (int i = 0; i < node->nchildren; ++i)
        view_free(node->children[i]);
    free(node->children);
    free(node->objects.v);
    free(node);
}
typedef struct {
    Integer nodes, tests;
} Visit;
typedef struct {
    int id;
    Integer value;
} Pair;
typedef struct {
    Pair *v;
    int n, capacity;
    Integer count;
} Answer;
static void answer_add(Answer *out, int id, Integer value) {
    if (out->n == out->capacity) {
        out->capacity = out->capacity ? out->capacity * 2 : 16;
        out->v = realloc(out->v, (size_t)out->capacity * sizeof *out->v);
    }
    out->v[out->n++] = (Pair){id, value};
}
static int compare_pairs(const void *left, const void *right) {
    const Pair *a = left, *b = right;
    if (a->id != b->id)
        return (a->id > b->id) - (a->id < b->id);
    return (a->value > b->value) - (a->value < b->value);
}
static int compare_nearest(const void *left, const void *right) {
    const Pair *a = left, *b = right;
    if (a->value != b->value)
        return (a->value > b->value) - (a->value < b->value);
    return (a->id > b->id) - (a->id < b->id);
}
static bool answer_equal(Answer a, Answer b) {
    if (a.count != b.count || a.n != b.n)
        return false;
    for (int i = 0; i < a.n; ++i)
        if (a.v[i].id != b.v[i].id || a.v[i].value != b.v[i].value)
            return false;
    return true;
}
static Box command_box(const Command *command) {
    return (Box){command->values[0], command->values[1], command->values[2], command->values[3]};
}
static bool region_condition(const Command *command, Box region) {
    if (strcmp(command->name, "RANGE") == 0 || strcmp(command->name, "WINDOWCOUNT") == 0)
        return intersects(region, command_box(command));
    if (strcmp(command->name, "CONTAINS") == 0)
        return contains(
            region, (Box){command->values[0], command->values[1], command->values[0], command->values[1]});
    return distance(command->values[0], command->values[1], region) <=
           command->values[2] * command->values[2];
}
static bool object_condition(const Command *command, Object object) {
    if (strcmp(command->name, "RANGE") == 0 || strcmp(command->name, "WINDOWCOUNT") == 0)
        return contains(command_box(command), object.box);
    if (strcmp(command->name, "CONTAINS") == 0)
        return contains(object.box, (Box){command->values[0], command->values[1], command->values[0],
                                          command->values[1]});
    return distance(command->values[0], command->values[1], object.box) <=
           command->values[2] * command->values[2];
}
static void condition_search(const View *node, const Command *command, Visit *visit, Answer *answer) {
    ++visit->nodes;
    if (strcmp(command->name, "WINDOWCOUNT") == 0 && contains(command_box(command), node->region)) {
        answer->count += node->count;
        return;
    }
    visit->tests += node->objects.n;
    for (int i = 0; i < node->objects.n; ++i) {
        const Object object = node->objects.v[i];
        if (object_condition(command, object)) {
            if (strcmp(command->name, "WINDOWCOUNT") == 0)
                ++answer->count;
            else
                answer_add(answer, object.id, 0);
        }
    }
    for (int i = 0; i < node->nchildren; ++i)
        if (region_condition(command, node->children[i]->region))
            condition_search(node->children[i], command, visit, answer);
}
typedef struct {
    Integer distance, tie;
    int kind;
    const View *node;
    Object object;
} QueueElement;
typedef struct {
    QueueElement *v;
    int n, capacity;
} Queue;
static bool earlier(QueueElement a, QueueElement b) {
    return a.distance < b.distance ||
           (a.distance == b.distance && (a.kind < b.kind || (a.kind == b.kind && a.tie < b.tie)));
}
static void queue_push(Queue *q, QueueElement value) {
    if (q->n == q->capacity) {
        q->capacity = q->capacity ? q->capacity * 2 : 32;
        q->v = realloc(q->v, (size_t)q->capacity * sizeof *q->v);
    }
    int i = q->n++;
    while (i > 0) {
        const int parent = (i - 1) / 2;
        if (!earlier(value, q->v[parent]))
            break;
        q->v[i] = q->v[parent];
        i = parent;
    }
    q->v[i] = value;
}
static QueueElement queue_pop(Queue *q) {
    const QueueElement out = q->v[0], value = q->v[--q->n];
    if (!q->n)
        return out;
    int i = 0;
    while (2 * i + 1 < q->n) {
        int child = 2 * i + 1;
        if (child + 1 < q->n && earlier(q->v[child + 1], q->v[child]))
            ++child;
        if (!earlier(q->v[child], value))
            break;
        q->v[i] = q->v[child];
        i = child;
    }
    q->v[i] = value;
    return out;
}
static Answer best_first(const View *root, const Command *command, Visit *visit) {
    Answer out = {0};
    Queue queue = {0};
    Integer serial = 0;
    const Integer x = command->values[0], y = command->values[1], k = command->values[2];
    queue_push(&queue,
               (QueueElement){.distance = distance(x, y, root->region), .tie = serial++, .node = root});
    while (queue.n) {
        const QueueElement element = queue_pop(&queue);
        if (element.kind == 1) {
            answer_add(&out, element.object.id, element.distance);
            if (out.n == k)
                break;
        } else {
            const View *node = element.node;
            ++visit->nodes;
            visit->tests += node->objects.n;
            for (int i = 0; i < node->objects.n; ++i) {
                const Object object = node->objects.v[i];
                queue_push(&queue, (QueueElement){.distance = distance(x, y, object.box),
                                                  .tie = object.id,
                                                  .kind = 1,
                                                  .object = object});
            }
            for (int i = 0; i < node->nchildren; ++i) {
                const View *child = node->children[i];
                queue_push(&queue, (QueueElement){.distance = distance(x, y, child->region),
                                                  .tie = serial++,
                                                  .node = child});
            }
        }
    }
    out.count = out.n;
    free(queue.v);
    return out;
}
static Answer search(const View *root, const Command *command, Visit *visit) {
    if (strcmp(command->name, "KNN") == 0 || strcmp(command->name, "NEAREST") == 0)
        return best_first(root, command, visit);
    Answer out = {0};
    condition_search(root, command, visit, &out);
    if (strcmp(command->name, "WINDOWCOUNT") != 0) {
        if (out.n > 1)
            qsort(out.v, (size_t)out.n, sizeof *out.v, compare_pairs);
        out.count = out.n;
    }
    return out;
}
static void spatial_join(const View *a, const View *b, Visit *visit, Answer *answer) {
    ++visit->nodes;
    const bool al = a->nchildren == 0, bl = b->nchildren == 0;
    if (al && bl) {
        visit->tests += (Integer)a->objects.n * b->objects.n;
        for (int i = 0; i < a->objects.n; ++i)
            for (int j = 0; j < b->objects.n; ++j) {
                const Object point = a->objects.v[i], rect = b->objects.v[j];
                if (contains(rect.box, point.box))
                    answer_add(answer, rect.id, point.id);
            }
    } else if (al) {
        for (int i = 0; i < b->nchildren; ++i)
            if (intersects(a->region, b->children[i]->region))
                spatial_join(a, b->children[i], visit, answer);
    } else if (bl) {
        for (int i = 0; i < a->nchildren; ++i)
            if (intersects(a->children[i]->region, b->region))
                spatial_join(a->children[i], b, visit, answer);
    } else
        for (int i = 0; i < a->nchildren; ++i)
            for (int j = 0; j < b->nchildren; ++j)
                if (intersects(a->children[i]->region, b->children[j]->region))
                    spatial_join(a->children[i], b->children[j], visit, answer);
}
static Answer brute(const Command *command, Points points, Objects rectangles) {
    Answer out = {0};
    if (strcmp(command->name, "JOIN") == 0) {
        for (int i = 0; i < rectangles.n; ++i)
            for (int j = 0; j < points.n; ++j)
                if (contains(rectangles.v[i].box, point_box(points.v[j])))
                    answer_add(&out, rectangles.v[i].id, points.v[j].id);
        if (out.n > 1)
            qsort(out.v, (size_t)out.n, sizeof *out.v, compare_pairs);
        out.count = out.n;
        return out;
    }
    Objects objects = {0};
    if (strcmp(command->name, "CONTAINS") == 0 || strcmp(command->name, "NEAREST") == 0)
        objects = rectangles;
    else
        for (int i = 0; i < points.n; ++i)
            objects_push(&objects, (Object){points.v[i].id, point_box(points.v[i])});
    const bool nearest = strcmp(command->name, "KNN") == 0 || strcmp(command->name, "NEAREST") == 0;
    if (nearest) {
        for (int i = 0; i < objects.n; ++i)
            answer_add(&out, objects.v[i].id,
                       distance(command->values[0], command->values[1], objects.v[i].box));
        if (out.n > 1)
            qsort(out.v, (size_t)out.n, sizeof *out.v, compare_nearest);
        out.n = (int)command->values[2];
    } else
        for (int i = 0; i < objects.n; ++i)
            if (object_condition(command, objects.v[i])) {
                if (strcmp(command->name, "WINDOWCOUNT") == 0)
                    ++out.count;
                else
                    answer_add(&out, objects.v[i].id, 0);
            }
    if (strcmp(command->name, "WINDOWCOUNT") != 0) {
        if (!nearest)
            if (out.n > 1)
                qsort(out.v, (size_t)out.n, sizeof *out.v, compare_pairs);
        out.count = out.n;
    }
    if (objects.v != rectangles.v)
        free(objects.v);
    return out;
}
static const char *box_text(Box box) {
    static char buffers[64][96];
    static unsigned next;
    char *out = buffers[next++ % 64];
    snprintf(out, 96, "%lld %lld %lld %lld", (long long)box.x1, (long long)box.y1, (long long)box.x2,
             (long long)box.y2);
    return out;
}
static void dump(Text *out, const View *node) {
    add(out, "%*s", 2 * (node->depth + 1), "");
    if (node->kd) {
        const Point point = node->kd->point;
        line(out, "%s %s %d %lld %lld box %s", node->mark, node->depth % 2 ? "y" : "x", point.id,
             (long long)point.x, (long long)point.y, box_text(node->region));
    } else if (node->quad) {
        add(out, "%s %lld %lld %lld", node->mark, (long long)node->quad->x, (long long)node->quad->y,
            (long long)node->quad->size);
        if (!node->quad->children[0]) {
            int *values = malloc((size_t)node->objects.n * sizeof *values);
            for (int i = 0; i < node->objects.n; ++i)
                values[i] = node->objects.v[i].id;
            line(out, " leaf %s", ids(values, node->objects.n));
            free(values);
        } else
            line(out, " node count %lld", (long long)node->count);
    } else if (node->rtree) {
        if (!node->rtree->level) {
            int *values = malloc((size_t)node->objects.n * sizeof *values);
            for (int i = 0; i < node->objects.n; ++i)
                values[i] = node->objects.v[i].id;
            line(out, "leaf %s ids %s", box_text(node->region), ids(values, node->objects.n));
            free(values);
        } else
            line(out, "node %d %s entries %d", node->rtree->level, box_text(node->region), node->rtree->n);
    }
    for (int i = 0; i < node->nchildren; ++i)
        dump(out, node->children[i]);
}
typedef struct {
    const View **v;
    int n, capacity;
} Views;
static void flatten(const View *node, Views *out) {
    if (out->n == out->capacity) {
        out->capacity = out->capacity ? out->capacity * 2 : 32;
        out->v = realloc(out->v, (size_t)out->capacity * sizeof *out->v);
    }
    out->v[out->n++] = node;
    for (int i = 0; i < node->nchildren; ++i)
        flatten(node->children[i], out);
}
static void kd_stats(Text *out, const View *root) {
    Views nodes = {0};
    flatten(root, &nodes);
    int height = 0, ideal = 0;
    Integer leaves = 0, one = 0, depth_sum = 0;
    for (int i = 0; i < nodes.n; ++i) {
        const View *node = nodes.v[i];
        if (node->depth + 1 > height)
            height = node->depth + 1;
        leaves += node->nchildren == 0;
        one += node->nchildren == 1;
        depth_sum += node->depth;
    }
    Integer(*levels)[3] = calloc((size_t)height, sizeof *levels);
    for (int i = 0; i < nodes.n; ++i) {
        const View *node = nodes.v[i];
        ++levels[node->depth][0];
        levels[node->depth][1] += node->nchildren == 0;
        levels[node->depth][2] += node->nchildren == 1;
    }
    Integer capacity = 0;
    while (capacity < nodes.n) {
        capacity = 2 * capacity + 1;
        ++ideal;
    }
    line(out, "kdtree height %d ideal %d nodes %d leaves %lld one_child %lld depth_sum %lld avg_depth %s",
         height, ideal, nodes.n, (long long)leaves, (long long)one, (long long)depth_sum,
         fraction(depth_sum, nodes.n));
    for (int depth = 0; depth < height; ++depth)
        line(out, "  depth %d nodes %lld leaves %lld one_child %lld", depth, (long long)levels[depth][0],
             (long long)levels[depth][1], (long long)levels[depth][2]);
    free(levels);
    free(nodes.v);
}
static void quad_stats(Text *out, const View *root, int bucket) {
    Views nodes = {0};
    flatten(root, &nodes);
    int height = 0;
    Integer internal = 0, leaves = 0, empty = 0, maximum = 0;
    for (int i = 0; i < nodes.n; ++i)
        if (nodes.v[i]->depth + 1 > height)
            height = nodes.v[i]->depth + 1;
    Integer(*levels)[3] = calloc((size_t)height, sizeof *levels);
    for (int i = 0; i < nodes.n; ++i) {
        const View *node = nodes.v[i];
        if (!node->nchildren) {
            ++leaves;
            empty += node->objects.n == 0;
            if (node->objects.n > maximum)
                maximum = node->objects.n;
            ++levels[node->depth][1];
            levels[node->depth][2] += node->objects.n;
        } else {
            ++internal;
            ++levels[node->depth][0];
        }
    }
    line(out, "quadtree height %d internal %lld leaves %lld empty %lld max_leaf %lld fill %s", height,
         (long long)internal, (long long)leaves, (long long)empty, (long long)maximum,
         fraction(root->count, leaves * bucket));
    for (int depth = 0; depth < height; ++depth)
        line(out, "  depth %d internal %lld leaves %lld points %lld", depth, (long long)levels[depth][0],
             (long long)levels[depth][1], (long long)levels[depth][2]);
    free(levels);
    free(nodes.v);
}
static void r_stats(Text *out, const View *root, const char *name, int maximum, int minimum) {
    Views nodes = {0};
    flatten(root, &nodes);
    Integer leaves = 0, entries = 0;
    for (int i = 0; i < nodes.n; ++i) {
        leaves += nodes.v[i]->rtree->level == 0;
        entries += nodes.v[i]->rtree->n;
    }
    line(out, "%s height %d nodes %d leaves %lld entries %lld fill %s", name, root->rtree->level + 1, nodes.n,
         (long long)leaves, (long long)entries, fraction(entries, (Integer)nodes.n * maximum));
    for (int level = root->rtree->level; level >= 0; --level) {
        Integer count = 0, low = 65, high = 0, under = 0, total_area = 0, total_overlap = 0;
        int nlevel = 0;
        for (int i = 0; i < nodes.n; ++i) {
            const View *node = nodes.v[i];
            if (node->rtree->level != level)
                continue;
            ++nlevel;
            const int n = node->rtree->n;
            count += n;
            if (n < low)
                low = n;
            if (n > high)
                high = n;
            under += n < minimum;
            total_area += area(node->region);
            for (int j = i + 1; j < nodes.n; ++j)
                if (nodes.v[j]->rtree->level == level)
                    total_overlap += overlap(node->region, nodes.v[j]->region);
        }
        line(out, "  level %d nodes %d entries %lld min %lld max %lld under %lld area %lld overlap %lld",
             level, nlevel, (long long)count, (long long)low, (long long)high, (long long)under,
             (long long)total_area, (long long)total_overlap);
    }
    free(nodes.v);
}
static void grid_stats(Text *out, const Grid *grid) {
    Integer used = 0;
    int maximum = 0;
    const int n = grid->dimension * grid->dimension;
    for (int i = 0; i < n; ++i) {
        used += grid->cells[i].n > 0;
        if (grid->cells[i].n > maximum)
            maximum = grid->cells[i].n;
    }
    int *counts = calloc((size_t)maximum + 1, sizeof *counts);
    for (int i = 0; i < n; ++i)
        ++counts[grid->cells[i].n];
    line(out, "grid cells %d used %lld max %d", n, (long long)used, maximum);
    add(out, "  occupancy");
    for (int k = 0; k <= maximum; ++k)
        if (counts[k])
            add(out, " %d:%d", k, counts[k]);
    line(out, "");
    free(counts);
}
typedef struct {
    int v[64], n;
} Location;
static bool r_location(const RNode *node, Point point, Location *path) {
    for (int i = 0; i < node->n; ++i) {
        const Entry entry = node->entries[i];
        if (!node->level) {
            if (entry.id == point.id) {
                path->v[path->n++] = i + 1;
                return true;
            }
        } else if (contains(entry.box, point_box(point))) {
            path->v[path->n++] = i + 1;
            if (r_location(entry.child, point, path))
                return true;
            --path->n;
        }
    }
    return false;
}
static const char *path_text(Location path) {
    static char buffers[8][512];
    static unsigned next;
    char *out = buffers[next++ % 8];
    size_t length = 0;
    out[0] = 0;
    for (int i = 0; i < path.n; ++i)
        length += (size_t)snprintf(out + length, 512 - length, "%s%d", i ? "/" : "", path.v[i]);
    return out;
}
static void record_snapshot(int snapshot, int query, Points points, Objects rectangles, const Params *p,
                            const KDNode *kd, const QuadNode *quad, const RTree *rtree, const RTree *str,
                            const Grid *grid, const RTree *rect, const RTree *str_rect, Text *structures_file,
                            Text *stats) {
    if (snapshot) {
        line(structures_file, "");
        line(stats, "");
    }
    line(structures_file, "snapshot %d query %d points %d rects %d", snapshot, query, points.n, rectangles.n);
    line(stats, "snapshot %d query %d points %d rects %d", snapshot, query, points.n, rectangles.n);
    View *roots[7];
    views(roots, kd, quad, rtree, str, grid, rect, str_rect, p->world);
    for (int structure = 0; structure < 7; ++structure)
        if (structure != 4) {
            line(structures_file, "%s", structures[structure]);
            dump(structures_file, roots[structure]);
        }
    kd_stats(stats, roots[0]);
    quad_stats(stats, roots[1], p->bucket);
    const int rtrees[] = {2, 3, 5, 6};
    for (int i = 0; i < 4; ++i)
        r_stats(stats, roots[rtrees[i]], structures[rtrees[i]], p->maximum, p->minimum);
    grid_stats(stats, grid);
    for (int i = 0; i < 7; ++i)
        view_free(roots[i]);
}
typedef struct {
    Integer queries, nodes, tests, maximum;
} Aggregate;
int main(void) {
    mkdir("output", 0777);
    Input input = read_input();
    const Params *p = &input.params;
    Points points = {0};
    for (int i = 0; i < input.points.n; ++i)
        points_insert(&points, input.points.v[i]);
    KDNode *kd = kd_build(input.points.v, input.points.n, 0);
    QuadNode *quad = calloc(1, sizeof *quad);
    quad->size = p->world;
    Grid grid = grid_new(p->world, p->grid);
    RTree rtree = rtree_new(p->maximum, p->minimum), str = rtree_new(p->maximum, p->minimum),
          rect = rtree_new(p->maximum, p->minimum), str_rect = rtree_new(p->maximum, p->minimum);
    Entry *point_entries = malloc((size_t)input.points.n * sizeof *point_entries),
          *rect_entries = malloc((size_t)input.rectangles.n * sizeof *rect_entries);
    for (int i = 0; i < input.points.n; ++i) {
        const Point point = input.points.v[i];
        quad_insert(quad, point, p->bucket);
        grid_insert(&grid, point);
        point_entries[i] = (Entry){.box = point_box(point), .id = point.id, .number = point.id};
        rtree_insert(&rtree, point_entries[i], 0);
    }
    for (int i = 0; i < input.rectangles.n; ++i) {
        const Object object = input.rectangles.v[i];
        rect_entries[i] = (Entry){.box = object.box, .id = object.id, .number = object.id};
        rtree_insert(&rect, rect_entries[i], 0);
    }
    rtree_bulk(&str, point_entries, input.points.n);
    rtree_bulk(&str_rect, rect_entries, input.rectangles.n);
    free(point_entries);
    free(rect_entries);
    Text answers = {0}, visits = {0}, join_file = {0}, structures_file = {0}, stats = {0};
    line(&visits, "query,command,structure,nodes,tests");
    line(&join_file, "query,rect,point");
    Aggregate aggregates[7][7] = {0};
    int snapshot = 0;
    record_snapshot(0, 0, points, input.rectangles, p, kd, quad, &rtree, &str, &grid, &rect, &str_rect,
                    &structures_file, &stats);
    for (int index = 0; index < input.ncommands; ++index) {
        const Command *command = &input.commands[index];
        const char *name = command->name;
        const int query = index + 1;
        add(&answers, "%d %s", query, name);
        if (strcmp(name, "INSERT") == 0) {
            const Point point = {(int)command->values[0], command->values[1], command->values[2]};
            points_insert(&points, point);
            kd_insert(&kd, point, 0);
            quad_insert(quad, point, p->bucket);
            grid_insert(&grid, point);
            const Entry entry = {.box = point_box(point), .id = point.id, .number = point.id};
            rtree_insert(&rtree, entry, 0);
            rtree_insert(&str, entry, 0);
            line(&answers, " %d inserted points %d", point.id, points.n);
        } else if (strcmp(name, "DELETE") == 0) {
            const int id = (int)command->values[0];
            int found = -1;
            for (int i = 0; i < points.n; ++i)
                if (points.v[i].id == id)
                    found = i;
            if (found < 0)
                line(&answers, " %d missing points %d", id, points.n);
            else {
                const Point point = points.v[found];
                kd_delete(&kd, point);
                quad_delete(quad, point, p->bucket);
                rtree_delete(&rtree, point);
                rtree_delete(&str, point);
                grid_delete(&grid, point);
                points_remove(&points, id);
                line(&answers, " %d deleted points %d", id, points.n);
            }
        } else if (strcmp(name, "DUMP") == 0) {
            ++snapshot;
            record_snapshot(snapshot, query, points, input.rectangles, p, kd, quad, &rtree, &str, &grid,
                            &rect, &str_rect, &structures_file, &stats);
            line(&answers, " snapshot %d", snapshot);
        } else if (strcmp(name, "LOCATE") == 0) {
            const int id = (int)command->values[0];
            int found = -1;
            for (int i = 0; i < points.n; ++i)
                if (points.v[i].id == id)
                    found = i;
            add(&answers, " %d", id);
            if (found < 0)
                line(&answers, " missing");
            else {
                const Point point = points.v[found];
                Text kd_path = {0}, quad_path = {0};
                const KDNode *node = kd;
                while (node->point.id != id) {
                    const bool left = key_less(point, node->point, node->depth % 2);
                    add(&kd_path, "%c", left ? 'L' : 'R');
                    node = left ? node->left : node->right;
                }
                const QuadNode *q = quad;
                while (q->children[0]) {
                    const int child = destination(q, point);
                    add(&quad_path, "%s%s", quad_path.size ? "/" : "", quadrants[child]);
                    q = q->children[child];
                }
                Location a = {0}, b = {0};
                r_location(rtree.root, point, &a);
                r_location(str.root, point, &b);
                line(&answers, " kdtree %s quadtree %s rtree %s str %s grid %lld %lld",
                     kd_path.size ? kd_path.data : "-", quad_path.size ? quad_path.data : "-", path_text(a),
                     path_text(b), (long long)(point.x / p->grid), (long long)(point.y / p->grid));
                free(kd_path.data);
                free(quad_path.data);
            }
        } else {
            int type = 0;
            while (strcmp(search_names[type], name) != 0)
                ++type;
            View *roots[7];
            views(roots, kd, quad, &rtree, &str, &grid, &rect, &str_rect, p->world);
            Answer expected = brute(command, points, input.rectangles);
            int selected[5], nselected;
            if (strcmp(name, "CONTAINS") == 0 || strcmp(name, "NEAREST") == 0) {
                selected[0] = 5;
                selected[1] = 6;
                nselected = 2;
            } else if (strcmp(name, "JOIN") == 0) {
                selected[0] = 2;
                selected[1] = 3;
                nselected = 2;
            } else {
                nselected = 5;
                for (int i = 0; i < 5; ++i)
                    selected[i] = i;
            }
            int mismatches[5], nmismatches = 0;
            for (int i = 0; i < nselected; ++i) {
                const int structure = selected[i];
                Visit visit = {0};
                Answer actual = {0};
                if (strcmp(name, "JOIN") == 0) {
                    spatial_join(roots[structure], roots[structure == 2 ? 5 : 6], &visit, &actual);
                    if (actual.n > 1)
                        qsort(actual.v, (size_t)actual.n, sizeof *actual.v, compare_pairs);
                    actual.count = actual.n;
                } else
                    actual = search(roots[structure], command, &visit);
                if (!answer_equal(actual, expected))
                    mismatches[nmismatches++] = structure;
                line(&visits, "%d,%s,%s,%lld,%lld", query, name, structures[structure],
                     (long long)visit.nodes, (long long)visit.tests);
                Aggregate *aggregate = &aggregates[type][structure];
                ++aggregate->queries;
                aggregate->nodes += visit.nodes;
                aggregate->tests += visit.tests;
                if (visit.nodes > aggregate->maximum)
                    aggregate->maximum = visit.nodes;
                free(actual.v);
            }
            add(&answers, " count %lld", (long long)expected.count);
            if (strcmp(name, "RANGE") == 0 || strcmp(name, "RADIUS") == 0 || strcmp(name, "CONTAINS") == 0) {
                int *values = malloc((size_t)expected.n * sizeof *values);
                for (int i = 0; i < expected.n; ++i)
                    values[i] = expected.v[i].id;
                add(&answers, " ids %s", ids(values, expected.n));
                free(values);
            } else if (strcmp(name, "KNN") == 0 || strcmp(name, "NEAREST") == 0) {
                add(&answers, " ids");
                for (int i = 0; i < expected.n; ++i)
                    add(&answers, " %d:%lld", expected.v[i].id, (long long)expected.v[i].value);
            } else if (strcmp(name, "JOIN") == 0)
                for (int i = 0; i < expected.n; ++i)
                    line(&join_file, "%d,%d,%lld", query, expected.v[i].id, (long long)expected.v[i].value);
            add(&answers, " check %s", nmismatches ? "mismatch" : "ok");
            for (int i = 0; i < nmismatches; ++i)
                add(&answers, " %s", structures[mismatches[i]]);
            line(&answers, "");
            free(expected.v);
            for (int i = 0; i < 7; ++i)
                view_free(roots[i]);
        }
    }
    line(&stats, "");
    line(&stats, "visits");
    for (int type = 0; type < 7; ++type) {
        int selected[7], nselected = 0;
        for (int structure = 0; structure < 7; ++structure) {
            const Aggregate value = aggregates[type][structure];
            if (!value.queries)
                continue;
            selected[nselected++] = structure;
            line(&stats, "%s %s queries %lld nodes %lld tests %lld max_nodes %lld mean_nodes %s",
                 search_names[type], structures[structure], (long long)value.queries, (long long)value.nodes,
                 (long long)value.tests, (long long)value.maximum, fraction(value.nodes, value.queries));
        }
        if (!nselected)
            continue;
        for (int i = 1; i < nselected; ++i) {
            const int value = selected[i];
            int position = i;
            while (position > 0) {
                const int previous = selected[position - 1];
                const Aggregate a = aggregates[type][value], b = aggregates[type][previous];
                const bool before =
                    a.nodes < b.nodes ||
                    (a.nodes == b.nodes && (a.tests < b.tests || (a.tests == b.tests && value < previous)));
                if (!before)
                    break;
                selected[position] = previous;
                --position;
            }
            selected[position] = value;
        }
        add(&stats, "rank %s", search_names[type]);
        for (int i = 0; i < nselected; ++i)
            add(&stats, " %s", structures[selected[i]]);
        line(&stats, "");
    }
    write_report("answers.txt", answers);
    write_report("visits.csv", visits);
    write_report("join.csv", join_file);
    write_report("structures.txt", structures_file);
    write_report("stats.txt", stats);
    free(answers.data);
    free(visits.data);
    free(join_file.data);
    free(structures_file.data);
    free(stats.data);
    free(input.points.v);
    free(input.rectangles.v);
    free(input.commands);
    free(points.v);
    kd_free(kd);
    quad_free(quad);
    rtree_free(rtree.root);
    rtree_free(str.root);
    rtree_free(rect.root);
    rtree_free(str_rect.root);
    for (int i = 0; i < grid.dimension * grid.dimension; ++i)
        free(grid.cells[i].v);
    free(grid.cells);
    return 0;
}
