#include "layout.h"
static int maximum(int a, int b) { return a > b ? a : b; }
static int minimum(int a, int b) { return a < b ? a : b; }
static int compare_ints(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}
void orders_free(Orders *orders) {
    for (int i = 0; i < orders->count; ++i)
        int_free(&orders->rows[i]);
    *orders = (Orders){0};
}
Orders orders_copy(const Orders *orders) {
    Orders out = {0};
    out.count = orders->count;
    for (int i = 0; i < out.count; ++i)
        out.rows[i] = int_copy(&orders->rows[i]);
    return out;
}
static bool orders_equal(const Orders *a, const Orders *b) {
    if (a->count != b->count)
        return false;
    for (int i = 0; i < a->count; ++i)
        if (a->rows[i].count != b->rows[i].count ||
            (a->rows[i].count && memcmp(a->rows[i].data, b->rows[i].data,
                                        (size_t)a->rows[i].count * sizeof *a->rows[i].data)))
            return false;
    return true;
}
static void append_owned(TextLines *to, TextLines *from) {
    for (int i = 0; i < from->count; ++i)
        lines_push(to, from->data[i]);
    free(from->data);
    *from = (TextLines){0};
}
static void closure(bool reach[40][40], int count) {
    for (int k = 0; k < count; ++k)
        for (int i = 0; i < count; ++i)
            for (int j = 0; j < count; ++j)
                reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j]);
}
static void graph_analysis(Layout *layout) {
    int incoming[40] = {0}, outgoing[40] = {0};
    Orders weak = {0};
    weak.count = layout->nodes;
    bool reach[40][40] = {0};
    for (int i = 0; i < layout->nodes; ++i)
        reach[i][i] = true;
    for (int i = 0; i < layout->edge_count; ++i) {
        const Edge *edge = &layout->edges[i];
        ++incoming[edge->to];
        ++outgoing[edge->from];
        int_push(&weak.rows[edge->from], edge->to);
        int_push(&weak.rows[edge->to], edge->from);
        reach[edge->from][edge->to] = true;
    }
    for (int i = 0; i < layout->nodes; ++i) {
        if (!incoming[i] && outgoing[i])
            ++layout->sources;
        if (!outgoing[i] && incoming[i])
            ++layout->sinks;
        if (!incoming[i] && !outgoing[i])
            ++layout->isolated;
    }
    bool seen[40] = {0};
    for (int v = 0; v < layout->nodes; ++v)
        if (!seen[v]) {
            ++layout->components;
            IntList queue = {0};
            int_push(&queue, v);
            seen[v] = true;
            for (int head = 0; head < queue.count; ++head) {
                const IntList *neighbors = &weak.rows[queue.data[head]];
                for (int i = 0; i < neighbors->count; ++i)
                    if (!seen[neighbors->data[i]]) {
                        seen[neighbors->data[i]] = true;
                        int_push(&queue, neighbors->data[i]);
                    }
            }
            int_free(&queue);
        }
    closure(reach, layout->nodes);
    memset(seen, 0, sizeof seen);
    for (int v = 0; v < layout->nodes; ++v)
        if (!seen[v]) {
            IntList component = {0};
            for (int next = v; next < layout->nodes; ++next)
                if (reach[v][next] && reach[next][v]) {
                    seen[next] = true;
                    int_push(&component, next);
                }
            if (component.count > 1)
                layout->scc.rows[layout->scc.count++] = component;
            else
                int_free(&component);
        }
    orders_free(&weak);
}
static int node_index(const Block *block, int id) {
    for (int i = 0; i < block->node_count; ++i)
        if (block->nodes[i].id == id)
            return i;
    return -1;
}
static int index_of(const IntList *list, int value) {
    for (int i = 0; i < list->count; ++i)
        if (list->data[i] == value)
            return i;
    return -1;
}
static void visit(Layout *layout, int vertex, bool *visited) {
    if (visited[vertex])
        return;
    visited[vertex] = true;
    int_push(&layout->orders.rows[layout->vertices[vertex].layer], vertex);
    const IntList *next = &layout->vertices[vertex].lower;
    for (int i = 0; i < next->count; ++i)
        visit(layout, next->data[i], visited);
}
static Layout *initialize(const Block *block) {
    Layout *out = allocate(sizeof *out);
    out->block = block;
    out->nodes = out->vertex_count = block->node_count;
    out->edge_count = block->edge_count;
    for (int i = 0; i < out->nodes; ++i) {
        Vertex *vertex = &out->vertices[i];
        snprintf(vertex->name, sizeof vertex->name, "%d", block->nodes[i].id);
        vertex->width = (int)strlen(block->nodes[i].label) + 2;
        if (vertical(block->settings.direction)) {
            vertex->left = (vertex->width - 1) / 2;
            vertex->right = vertex->width - 1 - vertex->left;
        }
    }
    for (int i = 0; i < out->edge_count; ++i) {
        out->edges[i].from = node_index(block, block->edges[i].from);
        out->edges[i].to = node_index(block, block->edges[i].to);
    }
    graph_analysis(out);
    out->acyclic = acyclic(out->nodes, out->edges, out->edge_count);
    int rank[40] = {0};
    for (int i = 0; i < out->nodes; ++i)
        rank[out->acyclic.data[i]] = i;
    Orders all_successors = {0};
    all_successors.count = out->nodes;
    bool reach[40][40] = {0};
    for (int i = 0; i < out->nodes; ++i)
        reach[i][i] = true;
    for (int i = 0; i < out->edge_count; ++i) {
        Edge *edge = &out->edges[i];
        edge->reversed = rank[edge->from] > rank[edge->to];
        edge->upper = edge->reversed ? edge->to : edge->from;
        edge->lower = edge->reversed ? edge->from : edge->to;
        int_push(&all_successors.rows[edge->upper], edge->lower);
        reach[edge->upper][edge->lower] = true;
    }
    closure(reach, out->nodes);
    if (block->settings.reduce)
        for (int i = 0; i < out->edge_count; ++i) {
            Edge *edge = &out->edges[i];
            if (edge->reversed)
                continue;
            const IntList *next = &all_successors.rows[edge->upper];
            for (int j = 0; j < next->count; ++j)
                if (next->data[j] != edge->lower && reach[next->data[j]][edge->lower]) {
                    edge->transitive = true;
                    break;
                }
        }
    Orders pre = {0}, succ = {0};
    pre.count = succ.count = out->nodes;
    for (int i = 0; i < out->edge_count; ++i) {
        const Edge *edge = &out->edges[i];
        if (!edge->transitive) {
            int_push(&pre.rows[edge->lower], edge->upper);
            int_push(&succ.rows[edge->upper], edge->lower);
        }
    }
    for (int i = 0; i < out->nodes; ++i) {
        if (pre.rows[i].count > 1)
            qsort(pre.rows[i].data, (size_t)pre.rows[i].count, sizeof *pre.rows[i].data,
                  compare_ints);
        if (succ.rows[i].count > 1)
            qsort(succ.rows[i].data, (size_t)succ.rows[i].count, sizeof *succ.rows[i].data,
                  compare_ints);
    }
    out->layering = assign_layers(&pre, &succ, block->settings);
    orders_free(&pre);
    orders_free(&succ);
    orders_free(&all_successors);
    int highest = 0;
    for (int i = 0; i < out->nodes; ++i)
        highest = maximum(highest, out->layering.height[i]);
    IntList levels = {0};
    for (int i = 0; i < out->nodes; ++i)
        int_add(&levels, highest - out->layering.height[i]);
    for (int i = 0; i < out->edge_count; ++i) {
        const Edge *edge = &out->edges[i];
        if (!edge->transitive)
            for (int level = highest - out->layering.height[edge->upper] + 1;
                 level < highest - out->layering.height[edge->lower]; ++level)
                int_add(&levels, level);
    }
    if (levels.count > 1)
        qsort(levels.data, (size_t)levels.count, sizeof *levels.data, compare_ints);
    out->orders.count = levels.count;
    out->gaps.count = levels.count - 1;
    for (int i = 0; i < out->nodes; ++i)
        out->vertices[i].layer = index_of(&levels, highest - out->layering.height[i]);
    int_free(&levels);
    for (int index = 0; index < out->edge_count; ++index) {
        Edge *edge = &out->edges[index];
        if (edge->transitive)
            continue;
        int upper = out->vertices[edge->upper].layer, lower = out->vertices[edge->lower].layer;
        edge->span = lower - upper;
        int_push(&edge->chain, edge->upper);
        for (int layer = upper + 1; layer < lower; ++layer) {
            int number = out->vertex_count++;
            Vertex *vertex = &out->vertices[number];
            snprintf(vertex->name, sizeof vertex->name, "d%d", number - out->nodes + 1);
            vertex->width = 1;
            vertex->layer = layer;
            int_push(&edge->chain, number);
        }
        int_push(&edge->chain, edge->lower);
        for (int i = 0; i + 1 < edge->chain.count; ++i) {
            int u = edge->chain.data[i], v = edge->chain.data[i + 1], gap = out->vertices[u].layer,
                number = out->segment_count++;
            out->segments[number] = (Segment){u, v, index, gap, 0};
            int_push(&edge->segments, number);
            int_push(&out->gaps.rows[gap], number);
            int_push(&out->vertices[u].lower, v);
            int_push(&out->vertices[v].upper, u);
        }
    }
    bool visited[600] = {0};
    for (int v = 0; v < out->nodes; ++v)
        visit(out, v, visited);
    return out;
}
static void reorder_layer(const Layout *layout, Orders *orders, int layer, bool down) {
    int pos[600] = {0}, numerator[600] = {0}, denominator[600] = {0};
    positions(orders, pos);
    IntList slots = {0}, vertices = {0};
    const IntList *row = &orders->rows[layer];
    for (int i = 0; i < row->count; ++i) {
        int v = row->data[i];
        const IntList *reference = down ? &layout->vertices[v].upper : &layout->vertices[v].lower;
        if (!reference->count)
            continue;
        int_push(&slots, i);
        int_push(&vertices, v);
        IntList values = {0};
        int sum = 0;
        for (int j = 0; j < reference->count; ++j) {
            int value = pos[reference->data[j]];
            int_push(&values, value);
            sum += value;
        }
        numerator[v] = sum;
        denominator[v] = reference->count;
        if (layout->block->settings.median) {
            if (values.count > 1)
                qsort(values.data, (size_t)values.count, sizeof *values.data, compare_ints);
            numerator[v] = values.data[(values.count - 1) / 2] + values.data[values.count / 2];
            denominator[v] = 1;
        }
        int_free(&values);
    }
    for (int i = 1; i < vertices.count; ++i) {
        int value = vertices.data[i], j = i;
        while (j && numerator[value] * denominator[vertices.data[j - 1]] <
                        numerator[vertices.data[j - 1]] * denominator[value]) {
            vertices.data[j] = vertices.data[j - 1];
            --j;
        }
        vertices.data[j] = value;
    }
    for (int i = 0; i < slots.count; ++i)
        orders->rows[layer].data[slots.data[i]] = vertices.data[i];
    int_free(&slots);
    int_free(&vertices);
}
static int adjacent_exchanges(const Layout *layout, Orders *orders) {
    int swaps = 0, pos[600] = {0};
    positions(orders, pos);
    for (;;) {
        bool changed = false;
        for (int layer = 0; layer < orders->count; ++layer) {
            IntList *row = &orders->rows[layer];
            for (int j = 0; j + 1 < row->count; ++j) {
                int v = row->data[j], w = row->data[j + 1];
                if (adjacent_cost(layout, v, w, pos) > adjacent_cost(layout, w, v, pos)) {
                    row->data[j] = w;
                    row->data[j + 1] = v;
                    pos[v] = j + 1;
                    pos[w] = j;
                    ++swaps;
                    changed = true;
                }
            }
        }
        if (!changed)
            return swaps;
    }
}
static IntList inserted(const IntList *row, int at, int vertex) {
    IntList out = {0};
    for (int i = 0; i <= row->count; ++i) {
        if (i == at)
            int_push(&out, vertex);
        if (i < row->count)
            int_push(&out, row->data[i]);
    }
    return out;
}
static void sift_push(Layout *layout, Sift value) {
    if (layout->sift_count == layout->sift_capacity) {
        layout->sift_capacity = layout->sift_capacity ? layout->sift_capacity * 2 : 8;
        layout->sifts =
            resize(layout->sifts, (size_t)layout->sift_capacity * sizeof *layout->sifts);
    }
    layout->sifts[layout->sift_count++] = value;
}
static void reduce_crossings(Layout *layout) {
    Orders initial = orders_copy(&layout->orders), adopted = {0};
    int64_t random = layout->block->settings.seed;
    int best_crossings = -1;
    for (int run = 0; run <= layout->block->settings.restarts; ++run) {
        Orders orders = orders_copy(&initial);
        if (run)
            for (int layer = 0; layer < orders.count; ++layer) {
                IntList *row = &orders.rows[layer];
                for (int j = row->count - 1; j >= 1; --j) {
                    random = 48271 * random % 2147483647;
                    int k = (int)(random % (j + 1)), value = row->data[j];
                    row->data[j] = row->data[k];
                    row->data[k] = value;
                }
            }
        int crossings = total_crossings(layout, &orders), run_best = crossings, run_sweep = 0;
        layout->sweeps[layout->sweep_count++] = (Sweep){run, 0, 0, 0, crossings};
        if (!run)
            layout->initial_crossings = crossings;
        Orders run_order = orders_copy(&orders), history[3] = {0};
        history[0] = orders_copy(&orders);
        for (int sweep = 1;; ++sweep) {
            if (!crossings || sweep - 1 == layout->block->settings.sweeps ||
                (sweep - 1 >= 2 && orders_equal(&orders, &history[(sweep - 3) % 3])))
                break;
            int old_pos[600] = {0}, new_pos[600] = {0};
            positions(&orders, old_pos);
            bool down = sweep % 2;
            if (down) {
                for (int layer = 1; layer < orders.count; ++layer)
                    reorder_layer(layout, &orders, layer, true);
            } else {
                for (int layer = orders.count - 2; layer >= 0; --layer)
                    reorder_layer(layout, &orders, layer, false);
            }
            positions(&orders, new_pos);
            int moved = 0;
            for (int v = 0; v < layout->vertex_count; ++v)
                if (old_pos[v] != new_pos[v])
                    ++moved;
            int swaps = adjacent_exchanges(layout, &orders);
            crossings = total_crossings(layout, &orders);
            layout->sweeps[layout->sweep_count++] = (Sweep){run, sweep, moved, swaps, crossings};
            orders_free(&history[sweep % 3]);
            history[sweep % 3] = orders_copy(&orders);
            if (crossings < run_best) {
                run_best = crossings;
                run_sweep = sweep;
                orders_free(&run_order);
                run_order = orders_copy(&orders);
            }
        }
        for (int i = 0; i < 3; ++i)
            orders_free(&history[i]);
        orders_free(&orders);
        if (best_crossings < 0 || run_best < best_crossings) {
            best_crossings = run_best;
            layout->best_run = run;
            layout->best_sweep = run_sweep;
            orders_free(&adopted);
            adopted = run_order;
            run_order = (Orders){0};
        }
        orders_free(&run_order);
    }
    orders_free(&initial);
    orders_free(&layout->orders);
    layout->orders = adopted;
    layout->adopted_crossings = best_crossings;
    if (layout->block->settings.sifting)
        for (int round = 1;; ++round) {
            int moves = 0;
            for (int v = 0; v < layout->vertex_count; ++v) {
                int layer = layout->vertices[v].layer,
                    original = index_of(&layout->orders.rows[layer], v);
                IntList without = {0};
                const IntList *row = &layout->orders.rows[layer];
                for (int i = 0; i < row->count; ++i)
                    if (i != original)
                        int_push(&without, row->data[i]);
                int best = 0, minimum_cost = INT_MAX, original_cost = 0;
                for (int at = 0; at <= without.count; ++at) {
                    IntList candidate = inserted(&without, at, v);
                    Orders trial = layout->orders;
                    trial.rows[layer] = candidate;
                    int pos[600] = {0}, cost = 0;
                    positions(&trial, pos);
                    if (layer)
                        cost += gap_crossings(layout->segments, &layout->gaps.rows[layer - 1], pos,
                                              trial.rows[layer].count);
                    if (layer + 1 < trial.count)
                        cost += gap_crossings(layout->segments, &layout->gaps.rows[layer], pos,
                                              trial.rows[layer + 1].count);
                    if (at == original)
                        original_cost = cost;
                    if (cost < minimum_cost) {
                        minimum_cost = cost;
                        best = at;
                    }
                    int_free(&candidate);
                }
                if (original_cost == minimum_cost)
                    best = original;
                int_free(&layout->orders.rows[layer]);
                layout->orders.rows[layer] = inserted(&without, best, v);
                int_free(&without);
                if (best != original)
                    ++moves;
            }
            sift_push(layout, (Sift){round, moves, total_crossings(layout, &layout->orders)});
            if (!moves)
                break;
        }
    layout->final_crossings = total_crossings(layout, &layout->orders);
    layout->brute = brute_crossings(layout, &layout->orders, true);
}
typedef struct {
    bool upper;
    int vertex, low, high, track;
    IntList segments;
} Bus;
static bool bus_before(const Layout *layout, const Bus *a, const Bus *b) {
    if (a->low != b->low)
        return a->low < b->low;
    if (a->high != b->high)
        return a->high < b->high;
    if (a->upper != b->upper)
        return a->upper;
    return layout->vertices[a->vertex].x < layout->vertices[b->vertex].x;
}
static void cell_push(CellList *list, Cell cell) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->data = resize(list->data, (size_t)list->capacity * sizeof *list->data);
    }
    list->data[list->count++] = cell;
}
static void geometry(Layout *layout) {
    int layers = layout->orders.count;
    for (int gap = 0; gap < layers - 1; ++gap) {
        const IntList *indices = &layout->gaps.rows[gap];
        int counts[600] = {0};
        for (int i = 0; i < indices->count; ++i) {
            const Segment *segment = &layout->segments[indices->data[i]];
            if (layout->vertices[segment->upper].x != layout->vertices[segment->lower].x)
                ++counts[segment->upper];
        }
        Bus buses[120] = {0};
        int bus_count = 0;
        for (int i = 0; i < indices->count; ++i) {
            int index = indices->data[i];
            const Segment *segment = &layout->segments[index];
            int upper = layout->vertices[segment->upper].x,
                lower = layout->vertices[segment->lower].x;
            if (upper == lower)
                continue;
            bool upper_bus = counts[segment->upper] >= 2;
            int vertex = upper_bus ? segment->upper : segment->lower, bus = -1;
            for (int j = 0; j < bus_count; ++j)
                if (buses[j].upper == upper_bus && buses[j].vertex == vertex) {
                    bus = j;
                    break;
                }
            if (bus < 0) {
                bus = bus_count++;
                buses[bus] =
                    (Bus){upper_bus, vertex, minimum(upper, lower), maximum(upper, lower), 0, {0}};
            }
            buses[bus].low = minimum(buses[bus].low, minimum(upper, lower));
            buses[bus].high = maximum(buses[bus].high, maximum(upper, lower));
            int_push(&buses[bus].segments, index);
        }
        for (int i = 1; i < bus_count; ++i) {
            Bus value = buses[i];
            int j = i;
            while (j && bus_before(layout, &value, &buses[j - 1])) {
                buses[j] = buses[j - 1];
                --j;
            }
            buses[j] = value;
        }
        int ends[120] = {0}, track_count = 0;
        for (int i = 0; i < bus_count; ++i) {
            Bus *bus = &buses[i];
            int track = -1;
            for (int t = 0; t < track_count; ++t)
                if (ends[t] + 1 < bus->low) {
                    track = t;
                    break;
                }
            if (track < 0)
                track = track_count++;
            ends[track] = bus->high;
            bus->track = track + 1;
        }
        layout->tracks[gap] = track_count;
        layout->gap_widths[gap] = maximum(layout->block->settings.layer_gap, track_count + 2);
        for (int i = 0; i < bus_count; ++i) {
            int offset = buses[i].track + (layout->gap_widths[gap] - 2 - track_count) / 2;
            for (int j = 0; j < buses[i].segments.count; ++j)
                layout->segments[buses[i].segments.data[j]].offset = offset;
            int_free(&buses[i].segments);
        }
    }
    bool is_vertical = vertical(layout->block->settings.direction);
    for (int i = 0; i < layers; ++i) {
        layout->thickness[i] = 1;
        if (!is_vertical)
            for (int j = 0; j < layout->orders.rows[i].count; ++j)
                layout->thickness[i] = maximum(
                    layout->thickness[i], layout->vertices[layout->orders.rows[i].data[j]].width);
        if (i)
            layout->band_starts[i] =
                layout->band_starts[i - 1] + layout->thickness[i - 1] + layout->gap_widths[i - 1];
    }
    layout->main_length = layout->band_starts[layers - 1] + layout->thickness[layers - 1];
    for (int i = 0; i < layout->vertex_count; ++i)
        layout->secondary_length = maximum(layout->secondary_length,
                                           layout->vertices[i].x + layout->vertices[i].right + 1);
    layout->canvas = canvas_create(layout->main_length, layout->secondary_length,
                                   layout->block->settings.direction);
    for (int i = 0; i < layout->edge_count; ++i) {
        Edge *edge = &layout->edges[i];
        if (edge->transitive)
            continue;
        const Vertex *upper = &layout->vertices[edge->upper],
                     *lower = &layout->vertices[edge->lower];
        cell_push(&edge->route,
                  canvas_map(&layout->canvas,
                             layout->band_starts[upper->layer] + (is_vertical ? 1 : upper->width),
                             upper->x));
        for (int j = 0; j < edge->segments.count; ++j) {
            const Segment *segment = &layout->segments[edge->segments.data[j]];
            int x = layout->vertices[segment->upper].x, y = layout->vertices[segment->lower].x;
            if (x != y) {
                int main = layout->band_starts[segment->gap] + layout->thickness[segment->gap] +
                           segment->offset;
                cell_push(&edge->route, canvas_map(&layout->canvas, main, x));
                cell_push(&edge->route, canvas_map(&layout->canvas, main, y));
                edge->bends += 2;
            }
        }
        cell_push(&edge->route,
                  canvas_map(&layout->canvas, layout->band_starts[lower->layer] - 1, lower->x));
        if (edge->reversed)
            for (int j = 0; j < edge->route.count / 2; ++j) {
                Cell value = edge->route.data[j];
                edge->route.data[j] = edge->route.data[edge->route.count - 1 - j];
                edge->route.data[edge->route.count - 1 - j] = value;
            }
        edge->length = 1;
        for (int j = 0; j + 1 < edge->route.count; ++j)
            edge->length += abs(edge->route.data[j].row - edge->route.data[j + 1].row) +
                            abs(edge->route.data[j].column - edge->route.data[j + 1].column);
    }
    if (layout->block->has_path) {
        int from = node_index(layout->block, layout->block->path_from),
            to = node_index(layout->block, layout->block->path_to);
        bool adjacent[40][40] = {0};
        for (int i = 0; i < layout->edge_count; ++i)
            if (!layout->edges[i].transitive)
                adjacent[layout->edges[i].from][layout->edges[i].to] = true;
        int parent[40];
        for (int i = 0; i < layout->nodes; ++i)
            parent[i] = -2;
        parent[from] = -1;
        IntList queue = {0};
        int_push(&queue, from);
        for (int head = 0; head < queue.count; ++head)
            for (int next = 0; next < layout->nodes; ++next)
                if (adjacent[queue.data[head]][next] && parent[next] == -2) {
                    parent[next] = queue.data[head];
                    int_push(&queue, next);
                }
        if (parent[to] != -2) {
            for (int v = to; v >= 0; v = parent[v])
                int_push(&layout->path, v);
            for (int i = 0; i < layout->path.count / 2; ++i) {
                int value = layout->path.data[i];
                layout->path.data[i] = layout->path.data[layout->path.count - 1 - i];
                layout->path.data[layout->path.count - 1 - i] = value;
            }
        }
        int_free(&queue);
    }
}
static void draw(Layout *layout) {
    Canvas *canvas = &layout->canvas;
    for (int i = 0; i < layout->vertex_count; ++i) {
        const Vertex *vertex = &layout->vertices[i];
        if (i >= layout->nodes) {
            for (int j = 0; j < layout->thickness[vertex->layer]; ++j)
                canvas_main_line(canvas, layout->band_starts[vertex->layer] + j, vertex->x);
        } else if (!vertical(canvas->direction) && vertex->lower.count) {
            for (int j = vertex->width; j < layout->thickness[vertex->layer]; ++j)
                canvas_main_line(canvas, layout->band_starts[vertex->layer] + j, vertex->x);
        }
    }
    for (int i = 0; i < layout->segment_count; ++i) {
        const Segment *segment = &layout->segments[i];
        canvas_segment(canvas, layout->band_starts[segment->gap] + layout->thickness[segment->gap],
                       layout->gap_widths[segment->gap], layout->vertices[segment->upper].x,
                       layout->vertices[segment->lower].x, segment->offset);
    }
    static const char arrows[4][2] = {{'v', '^'}, {'^', 'v'}, {'>', '<'}, {'<', '>'}};
    for (int i = 0; i < layout->edge_count; ++i) {
        const Edge *edge = &layout->edges[i];
        if (!edge->transitive)
            canvas_at(canvas, edge->route.data[edge->route.count - 1])->arrow =
                arrows[canvas->direction][edge->reversed ? 1 : 0];
    }
    bool path_nodes[40] = {0}, path_edges[40][40] = {0};
    for (int i = 0; i < layout->path.count; ++i) {
        path_nodes[layout->path.data[i]] = true;
        if (i)
            path_edges[layout->path.data[i - 1]][layout->path.data[i]] = true;
    }
    for (int i = 0; i < layout->edge_count; ++i) {
        const Edge *edge = &layout->edges[i];
        if (!edge->transitive && path_edges[edge->from][edge->to])
            for (int j = 0; j + 1 < edge->route.count; ++j)
                canvas_highlight(canvas, edge->route.data[j], edge->route.data[j + 1]);
    }
    for (int i = 0; i < layout->nodes; ++i) {
        const Vertex *vertex = &layout->vertices[i];
        char *box = format_text("%c%s%c", path_nodes[i] ? '{' : '[', layout->block->nodes[i].label,
                                path_nodes[i] ? '}' : ']');
        Cell start;
        if (vertical(canvas->direction))
            start =
                canvas_map(canvas, layout->band_starts[vertex->layer], vertex->x - vertex->left);
        else
            start = (Cell){vertex->x, canvas->direction == DIR_LR
                                          ? layout->band_starts[vertex->layer]
                                          : layout->main_length -
                                                layout->band_starts[vertex->layer] - vertex->width};
        for (int j = 0; box[j]; ++j)
            canvas_at(canvas, (Cell){start.row, start.column + j})->box = box[j];
        free(box);
    }
}
static char *display_names(const Layout *layout, const IntList *vertices) {
    TextLines names = {0};
    for (int i = 0; i < vertices->count; ++i)
        lines_add(&names, layout->vertices[vertices->data[i]].name);
    char *out = join_texts(&names, " ");
    lines_free(&names);
    return out;
}
static char *edge_name(const Layout *layout, const Edge *edge) {
    return format_text("%s->%s", layout->vertices[edge->from].name,
                       layout->vertices[edge->to].name);
}
static TextLines layout_lines(const Layout *layout) {
    const Block *block = layout->block;
    TextLines out = {0}, settings = {0}, values = settings_values(block->settings);
    for (int i = 0; i < 13; ++i)
        lines_push(&settings, format_text("%s=%s", setting_names[i], values.data[i]));
    char *joined = join_texts(&settings, " "), *names = display_names(layout, &layout->acyclic);
    lines_push(&out, format_text("graph %s", block->name));
    lines_push(&out, format_text("settings %s", joined));
    lines_push(&out, format_text("acyclic %s", names));
    free(joined);
    free(names);
    lines_free(&settings);
    lines_free(&values);
    if (block->settings.coffman) {
        TextLines labels = {0};
        for (int i = 0; i < layout->nodes; ++i)
            lines_push(&labels,
                       format_text("%s:%d", layout->vertices[i].name, layout->layering.labels[i]));
        joined = join_texts(&labels, " ");
        lines_push(&out, format_text("labels %s", joined));
        free(joined);
        lines_free(&labels);
    }
    for (int i = 0; i < layout->layering.promotion_count; ++i) {
        const Promotion *promotion = &layout->layering.promotions[i];
        lines_push(&out,
                   format_text("promote %d %s %d", promotion->round,
                               layout->vertices[promotion->node].name, promotion->difference));
    }
    for (int i = 0; i < layout->sweep_count; ++i) {
        const Sweep *sweep = &layout->sweeps[i];
        if (!sweep->number)
            lines_push(
                &out, format_text("sweep %d 0 initial crossings %d", sweep->run, sweep->crossings));
        else
            lines_push(&out,
                       format_text("sweep %d %d %s moved %d swaps %d crossings %d", sweep->run,
                                   sweep->number, sweep->number % 2 ? "down" : "up", sweep->moved,
                                   sweep->swaps, sweep->crossings));
    }
    lines_push(&out, format_text("best run %d sweep %d crossings %d", layout->best_run,
                                 layout->best_sweep, layout->adopted_crossings));
    for (int i = 0; i < layout->sift_count; ++i)
        lines_push(&out, format_text("sift %d moves %d crossings %d", layout->sifts[i].round,
                                     layout->sifts[i].moves, layout->sifts[i].crossings));
    for (int layer = 0; layer < layout->orders.count; ++layer) {
        int start = layout->band_starts[layer], end = start + layout->thickness[layer] - 1;
        if (block->settings.direction == DIR_BT || block->settings.direction == DIR_RL) {
            int old = start;
            start = layout->main_length - 1 - end;
            end = layout->main_length - 1 - old;
        }
        TextLines vertices = {0};
        int low = 0, high = 0;
        const IntList *row = &layout->orders.rows[layer];
        for (int i = 0; i < row->count; ++i) {
            const Vertex *vertex = &layout->vertices[row->data[i]];
            if (!i || vertex->x - vertex->left < low)
                low = vertex->x - vertex->left;
            if (!i || vertex->x + vertex->right > high)
                high = vertex->x + vertex->right;
            lines_push(&vertices, format_text("%s@%d", vertex->name, vertex->x));
        }
        joined = join_texts(&vertices, " ");
        lines_push(&out, format_text("layer %d band %d %d extent %d %d : %s", layer, start, end,
                                     low, high, joined));
        free(joined);
        lines_free(&vertices);
    }
    int pos[600] = {0};
    positions(&layout->orders, pos);
    for (int gap = 0; gap < layout->gaps.count; ++gap)
        lines_push(&out, format_text("between %d %d segments %d crossings %d tracks %d gap %d", gap,
                                     gap + 1, layout->gaps.rows[gap].count,
                                     gap_crossings(layout->segments, &layout->gaps.rows[gap], pos,
                                                   layout->orders.rows[gap + 1].count),
                                     layout->tracks[gap], layout->gap_widths[gap]));
    TextLines variants = {0};
    for (int i = 0; i < 4; ++i)
        lines_push(&variants,
                   format_text("%s=%d/%d", variant_names[i], layout->coordinates.variants[i].blocks,
                               layout->coordinates.variants[i].width));
    joined = join_texts(&variants, " ");
    lines_push(&out, format_text("bk conflicts %d %s smallest %s", layout->coordinates.conflicts,
                                 joined, variant_names[layout->coordinates.smallest]));
    free(joined);
    lines_free(&variants);
    for (int layer = 0; layer < layout->orders.count; ++layer)
        for (int at = 0; at < layout->orders.rows[layer].count; ++at) {
            int v = layout->orders.rows[layer].data[at];
            const BKVariant *variants = layout->coordinates.variants;
            lines_push(&out,
                       format_text("vertex %s layer %d pos %d ul %d ur %d dl %d dr %d x %d",
                                   layout->vertices[v].name, layer, at, variants[0].aligned[v],
                                   variants[1].aligned[v], variants[2].aligned[v],
                                   variants[3].aligned[v], layout->vertices[v].x));
        }
    for (int i = 0; i < layout->edge_count; ++i) {
        const Edge *edge = &layout->edges[i];
        char *prefix = format_text("edge %s %s%s", layout->vertices[edge->from].name,
                                   layout->vertices[edge->to].name,
                                   edge->reversed && !edge->transitive ? " reversed" : "");
        if (edge->transitive) {
            lines_push(&out, format_text("%s transitive", prefix));
            free(prefix);
            continue;
        }
        TextLines chain = {0}, route = {0};
        for (int at = 0; at < edge->chain.count; ++at) {
            int index = edge->chain.data[edge->reversed ? edge->chain.count - 1 - at : at];
            lines_push(&chain, format_text("%d", layout->vertices[index].x));
        }
        for (int at = 0; at < edge->route.count; ++at)
            lines_push(&route,
                       format_text("%d,%d", edge->route.data[at].row, edge->route.data[at].column));
        char *path = join_texts(&chain, " "), *points = join_texts(&route, " ");
        lines_push(&out, format_text("%s span %d crossings %d bends %d path %s route %s", prefix,
                                     edge->span, edge->crossings, edge->bends, path, points));
        free(prefix);
        free(path);
        free(points);
        lines_free(&chain);
        lines_free(&route);
    }
    lines_add(&out, "end");
    return out;
}
static TextLines stats_lines(const Layout *layout) {
    const Block *block = layout->block;
    TextLines out = {0};
    lines_push(&out, format_text("graph %s", block->name));
    lines_push(&out, format_text("nodes %d edges %d self_loops %d duplicates %d", layout->nodes,
                                 layout->edge_count, block->self_loops, block->duplicates));
    lines_push(&out, format_text("sources %d sinks %d isolated %d components %d", layout->sources,
                                 layout->sinks, layout->isolated, layout->components));
    for (int i = 0; i < layout->scc.count; ++i) {
        char *names = display_names(layout, &layout->scc.rows[i]);
        lines_push(&out, format_text("scc %s", names));
        free(names);
    }
    TextLines reversed = {0}, transitive = {0};
    int span_counts[600] = {0}, span_total = 0, span_max = 0, long_edges = 0, vertical_edges = 0,
        route_length = 0, bends = 0, longest = -1;
    for (int i = 0; i < layout->edge_count; ++i) {
        const Edge *edge = &layout->edges[i];
        if (edge->reversed)
            lines_push(&reversed, edge_name(layout, edge));
        if (edge->transitive) {
            lines_push(&transitive, edge_name(layout, edge));
            continue;
        }
        ++span_counts[edge->span];
        span_total += edge->span;
        span_max = maximum(span_max, edge->span);
        if (edge->span >= 2) {
            ++long_edges;
            bool same = true;
            int x = layout->vertices[edge->chain.data[1]].x;
            for (int at = 1; at + 1 < edge->chain.count; ++at)
                if (layout->vertices[edge->chain.data[at]].x != x)
                    same = false;
            if (same)
                ++vertical_edges;
        }
        route_length += edge->length;
        bends += edge->bends;
        if (longest < 0 || edge->length > layout->edges[longest].length)
            longest = i;
    }
    char *names = join_texts(&reversed, " ");
    lines_push(&out,
               format_text("reversed %d%s%s", reversed.count, reversed.count ? " " : "", names));
    free(names);
    names = join_texts(&transitive, " ");
    lines_push(&out, format_text("transitive %d%s%s", transitive.count, transitive.count ? " " : "",
                                 names));
    free(names);
    lines_free(&reversed);
    lines_free(&transitive);
    int max_nodes = 0, max_vertices = 0;
    for (int i = 0; i < layout->orders.count; ++i) {
        int count = 0;
        const IntList *row = &layout->orders.rows[i];
        for (int j = 0; j < row->count; ++j)
            if (row->data[j] < layout->nodes)
                ++count;
        max_nodes = maximum(max_nodes, count);
        max_vertices = maximum(max_vertices, row->count);
    }
    lines_push(&out, format_text("layers %d max_nodes %d max_vertices %d", layout->orders.count,
                                 max_nodes, max_vertices));
    if (block->settings.promotion)
        lines_push(&out, format_text("promotion rounds %d accepted %d dummies_before %d",
                                     layout->layering.rounds, layout->layering.promotion_count,
                                     layout->layering.dummies_before));
    else
        lines_add(&out, "promotion off");
    lines_push(&out, format_text("dummies %d span_total %d span_max %d",
                                 layout->vertex_count - layout->nodes, span_total, span_max));
    TextLines spans = {0};
    for (int i = 1; i < 600; ++i)
        if (span_counts[i])
            lines_push(&spans, format_text("%d:%d", i, span_counts[i]));
    names = join_texts(&spans, " ");
    lines_push(&out, format_text("spans %s", spans.count ? names : "none"));
    free(names);
    lines_free(&spans);
    lines_push(&out, format_text("long_edges %d vertical %d", long_edges, vertical_edges));
    lines_push(
        &out,
        format_text("crossings initial %d swept %d best_run %d best_sweep %d final %d brute %d",
                    layout->initial_crossings, layout->adopted_crossings, layout->best_run,
                    layout->best_sweep, layout->final_crossings, layout->brute));
    int straight = 0, offset = 0;
    for (int i = 0; i < layout->segment_count; ++i) {
        int a = layout->vertices[layout->segments[i].upper].x,
            b = layout->vertices[layout->segments[i].lower].x;
        if (a == b)
            ++straight;
        offset += abs(a - b);
    }
    lines_push(&out, format_text("segments %d straight %d bent %d offset %d", layout->segment_count,
                                 straight, layout->segment_count - straight, offset));
    if (longest >= 0) {
        char *name = edge_name(layout, &layout->edges[longest]);
        lines_push(&out, format_text("routes length %d bends %d longest %s %d", route_length, bends,
                                     name, layout->edges[longest].length));
        free(name);
    } else
        lines_push(&out, format_text("routes length %d bends %d", route_length, bends));
    lines_push(&out,
               format_text("canvas width %d height %d crossing_cells %d", layout->canvas.columns,
                           layout->canvas.rows, canvas_crossing_cells(&layout->canvas)));
    if (block->has_path) {
        if (!layout->path.count)
            lines_push(&out, format_text("path %d %d none", block->path_from, block->path_to));
        else {
            char *names = display_names(layout, &layout->path);
            lines_push(&out, format_text("path %d %d hops %d : %s", block->path_from,
                                         block->path_to, layout->path.count - 1, names));
            free(names);
        }
    }
    lines_add(&out, "end");
    return out;
}
static void layout_free(Layout *layout) {
    for (int i = 0; i < layout->vertex_count; ++i) {
        int_free(&layout->vertices[i].upper);
        int_free(&layout->vertices[i].lower);
    }
    for (int i = 0; i < layout->edge_count; ++i) {
        int_free(&layout->edges[i].chain);
        int_free(&layout->edges[i].segments);
        free(layout->edges[i].route.data);
    }
    orders_free(&layout->gaps);
    orders_free(&layout->orders);
    orders_free(&layout->scc);
    int_free(&layout->acyclic);
    int_free(&layout->path);
    free(layout->layering.promotions);
    free(layout->coordinates.marked);
    free(layout->sifts);
    free(layout->canvas.cells);
    free(layout);
}
static void write_lines(const char *name, const TextLines *lines) {
    char *path = format_text("output/%s", name);
    FILE *output = fopen(path, "wb");
    free(path);
    if (!output)
        exit(EXIT_FAILURE);
    for (int i = 0; i < lines->count; ++i)
        if (fputs(lines->data[i], output) == EOF || fputc('\n', output) == EOF)
            exit(EXIT_FAILURE);
    if (fclose(output))
        exit(EXIT_FAILURE);
}
int main(void) {
    int block_count;
    Block *blocks = read_blocks(&block_count);
    TextLines layout = {0}, stats = {0}, drawings = {0}, crossings = {0};
    lines_add(&crossings, "graph,run,sweep,crossings");
    int laid_out = 0, errors = 0, nodes = 0, edges = 0, dummies = 0, initial = 0, final = 0;
    for (int i = 0; i < block_count; ++i) {
        const Block *block = &blocks[i];
        if (i)
            lines_add(&drawings, "");
        if (block->error) {
            ++errors;
            TextLines error_lines = {0};
            lines_push(&error_lines, format_text("graph %s", block->name));
            lines_push(&error_lines,
                       format_text("error %s line %d", block->error, block->error_line));
            lines_add(&error_lines, "end");
            lines_append(&layout, &error_lines);
            append_owned(&stats, &error_lines);
            lines_push(&drawings, format_text("graph %s error %s", block->name, block->error));
            continue;
        }
        Layout *current = initialize(block);
        reduce_crossings(current);
        current->coordinates = coordinates(current);
        geometry(current);
        draw(current);
        TextLines details = layout_lines(current);
        append_owned(&layout, &details);
        details = stats_lines(current);
        append_owned(&stats, &details);
        details = canvas_drawing(&current->canvas, block->name);
        append_owned(&drawings, &details);
        for (int j = 0; j < current->sweep_count; ++j)
            lines_push(&crossings,
                       format_text("%s,%d,%d,%d", block->name, current->sweeps[j].run,
                                   current->sweeps[j].number, current->sweeps[j].crossings));
        ++laid_out;
        nodes += current->nodes;
        edges += current->edge_count;
        dummies += current->vertex_count - current->nodes;
        initial += current->initial_crossings;
        final += current->final_crossings;
        layout_free(current);
    }
    lines_push(
        &stats,
        format_text(
            "summary graphs %d laid_out %d errors %d nodes %d edges %d dummies %d crossings_initial %d crossings_final %d",
            block_count, laid_out, errors, nodes, edges, dummies, initial, final));
    mkdir("output", 0755);
    write_lines("layout.txt", &layout);
    write_lines("stats.txt", &stats);
    write_lines("crossings.csv", &crossings);
    write_lines("drawings.txt", &drawings);
    lines_free(&layout);
    lines_free(&stats);
    lines_free(&drawings);
    lines_free(&crossings);
    free(blocks);
    return 0;
}
