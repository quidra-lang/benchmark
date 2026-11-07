#include "layout.hpp"
static void transitiveClosure(std::array<std::array<bool, 40>, 40> &reach, int count) {
    for (int k = 0; k < count; ++k)
        for (int i = 0; i < count; ++i)
            for (int j = 0; j < count; ++j)
                reach[i][j] = reach[i][j] || (reach[i][k] && reach[k][j]);
}
static void graphAnalysis(Layout &layout) {
    Order incoming(layout.nodes), outgoing(layout.nodes);
    Orders weak(layout.nodes);
    std::array<std::array<bool, 40>, 40> reach{};
    for (int v = 0; v < layout.nodes; ++v)
        reach[v][v] = true;
    for (const Edge &edge : layout.edges) {
        ++incoming[edge.to];
        ++outgoing[edge.from];
        weak[edge.from].push_back(edge.to);
        weak[edge.to].push_back(edge.from);
        reach[edge.from][edge.to] = true;
    }
    for (int v = 0; v < layout.nodes; ++v) {
        if (!incoming[v] && outgoing[v])
            ++layout.sources;
        if (!outgoing[v] && incoming[v])
            ++layout.sinks;
        if (!incoming[v] && !outgoing[v])
            ++layout.isolated;
    }
    std::vector<bool> seen(layout.nodes);
    for (int v = 0; v < layout.nodes; ++v)
        if (!seen[v]) {
            ++layout.components;
            Order queue{v};
            seen[v] = true;
            for (std::size_t head = 0; head < queue.size(); ++head)
                for (int next : weak[queue[head]])
                    if (!seen[next]) {
                        seen[next] = true;
                        queue.push_back(next);
                    }
        }
    transitiveClosure(reach, layout.nodes);
    std::fill(seen.begin(), seen.end(), false);
    for (int v = 0; v < layout.nodes; ++v)
        if (!seen[v]) {
            Order component;
            for (int next = v; next < layout.nodes; ++next)
                if (reach[v][next] && reach[next][v]) {
                    seen[next] = true;
                    component.push_back(next);
                }
            if (component.size() > 1)
                layout.scc.push_back(std::move(component));
        }
}
static Layout initialize(const Block &block) {
    Layout out;
    out.block = &block;
    out.nodes = static_cast<int>(block.nodes.size());
    out.vertices.reserve(600);
    std::map<int, int> index;
    for (int i = 0; i < out.nodes; ++i) {
        const NodeData &node = block.nodes[i];
        index[node.id] = i;
        Vertex vertex;
        vertex.name = std::to_string(node.id);
        vertex.width = static_cast<int>(node.label.size()) + 2;
        if (vertical(block.settings.direction)) {
            vertex.left = (vertex.width - 1) / 2;
            vertex.right = vertex.width - 1 - vertex.left;
        }
        out.vertices.push_back(std::move(vertex));
    }
    for (const RawEdge &raw : block.edges) {
        Edge edge;
        edge.from = index.at(raw.from);
        edge.to = index.at(raw.to);
        out.edges.push_back(std::move(edge));
    }
    graphAnalysis(out);
    out.acyclic = acyclic(out.nodes, out.edges);
    Order rank(out.nodes);
    for (int i = 0; i < out.nodes; ++i)
        rank[out.acyclic[i]] = i;
    Orders allSuccessors(out.nodes);
    std::array<std::array<bool, 40>, 40> reach{};
    for (int i = 0; i < out.nodes; ++i)
        reach[i][i] = true;
    for (Edge &edge : out.edges) {
        edge.reversed = rank[edge.from] > rank[edge.to];
        edge.upper = edge.reversed ? edge.to : edge.from;
        edge.lower = edge.reversed ? edge.from : edge.to;
        allSuccessors[edge.upper].push_back(edge.lower);
        reach[edge.upper][edge.lower] = true;
    }
    transitiveClosure(reach, out.nodes);
    if (block.settings.reduce)
        for (Edge &edge : out.edges)
            if (!edge.reversed)
                for (int next : allSuccessors[edge.upper])
                    if (next != edge.lower && reach[next][edge.lower]) {
                        edge.transitive = true;
                        break;
                    }
    Orders pre(out.nodes), succ(out.nodes);
    for (const Edge &edge : out.edges)
        if (!edge.transitive) {
            pre[edge.lower].push_back(edge.upper);
            succ[edge.upper].push_back(edge.lower);
        }
    for (int i = 0; i < out.nodes; ++i) {
        std::sort(pre[i].begin(), pre[i].end());
        std::sort(succ[i].begin(), succ[i].end());
    }
    out.layering = assignLayers(pre, succ, block.settings);
    int maximum = *std::max_element(out.layering.height.begin(), out.layering.height.end());
    std::set<int> used;
    for (int height : out.layering.height)
        used.insert(maximum - height);
    for (const Edge &edge : out.edges)
        if (!edge.transitive)
            for (int level = maximum - out.layering.height[edge.upper] + 1;
                 level < maximum - out.layering.height[edge.lower]; ++level)
                used.insert(level);
    std::map<int, int> renumber;
    int levelCount = 0;
    for (int level : used)
        renumber[level] = levelCount++;
    out.orders.resize(levelCount);
    out.gaps.resize(levelCount - 1);
    for (int i = 0; i < out.nodes; ++i)
        out.vertices[i].layer = renumber.at(maximum - out.layering.height[i]);
    for (std::size_t index = 0; index < out.edges.size(); ++index) {
        Edge &edge = out.edges[index];
        if (edge.transitive)
            continue;
        int upper = out.vertices[edge.upper].layer, lower = out.vertices[edge.lower].layer;
        edge.span = lower - upper;
        edge.chain.push_back(edge.upper);
        for (int layer = upper + 1; layer < lower; ++layer) {
            int number = static_cast<int>(out.vertices.size());
            Vertex vertex;
            vertex.name = text("d", number - out.nodes + 1);
            vertex.layer = layer;
            out.vertices.push_back(std::move(vertex));
            edge.chain.push_back(number);
        }
        edge.chain.push_back(edge.lower);
        for (std::size_t i = 0; i + 1 < edge.chain.size(); ++i) {
            int u = edge.chain[i], v = edge.chain[i + 1], gap = out.vertices[u].layer,
                number = static_cast<int>(out.segments.size());
            out.segments.push_back({u, v, static_cast<int>(index), gap, 0});
            edge.segments.push_back(number);
            out.gaps[gap].push_back(number);
            out.vertices[u].lower.push_back(v);
            out.vertices[v].upper.push_back(u);
        }
    }
    std::vector<bool> visited(out.vertices.size());
    std::function<void(int)> visit = [&](int v) {
        if (visited[v])
            return;
        visited[v] = true;
        out.orders[out.vertices[v].layer].push_back(v);
        for (int next : out.vertices[v].lower)
            visit(next);
    };
    for (int v = 0; v < out.nodes; ++v)
        visit(v);
    return out;
}
static void reorderLayer(const Layout &layout, Orders &orders, int layer, bool down) {
    Order pos = positions(orders, static_cast<int>(layout.vertices.size())), slots, vertices;
    std::vector<std::pair<int, int>> keys(layout.vertices.size());
    for (std::size_t i = 0; i < orders[layer].size(); ++i) {
        int v = orders[layer][i];
        const Order &reference = down ? layout.vertices[v].upper : layout.vertices[v].lower;
        if (reference.empty())
            continue;
        slots.push_back(static_cast<int>(i));
        vertices.push_back(v);
        Order values;
        int sum = 0;
        for (int u : reference) {
            values.push_back(pos[u]);
            sum += pos[u];
        }
        keys[v] = {sum, static_cast<int>(reference.size())};
        if (layout.block->settings.median) {
            std::sort(values.begin(), values.end());
            keys[v] = {values[(values.size() - 1) / 2] + values[values.size() / 2], 1};
        }
    }
    std::stable_sort(vertices.begin(), vertices.end(), [&](int a, int b) {
        return keys[a].first * keys[b].second < keys[b].first * keys[a].second;
    });
    for (std::size_t i = 0; i < slots.size(); ++i)
        orders[layer][slots[i]] = vertices[i];
}
static int adjacentExchanges(const Layout &layout, Orders &orders) {
    int swaps = 0;
    Order pos = positions(orders, static_cast<int>(layout.vertices.size()));
    for (;;) {
        bool changed = false;
        for (Order &row : orders)
            for (std::size_t j = 0; j + 1 < row.size(); ++j) {
                int v = row[j], w = row[j + 1];
                if (adjacentCost(layout, v, w, pos) > adjacentCost(layout, w, v, pos)) {
                    std::swap(row[j], row[j + 1]);
                    pos[v] = static_cast<int>(j + 1);
                    pos[w] = static_cast<int>(j);
                    ++swaps;
                    changed = true;
                }
            }
        if (!changed)
            return swaps;
    }
}
static void reduceCrossings(Layout &layout) {
    const Orders initial = layout.orders;
    std::int64_t random = layout.block->settings.seed;
    int bestCrossings = -1;
    Orders adopted;
    for (int run = 0; run <= layout.block->settings.restarts; ++run) {
        Orders orders = initial;
        if (run)
            for (Order &row : orders)
                for (int j = static_cast<int>(row.size()) - 1; j >= 1; --j) {
                    random = 48271 * random % 2147483647;
                    int k = static_cast<int>(random % (j + 1));
                    std::swap(row[j], row[k]);
                }
        int crossings = totalCrossings(layout, orders);
        layout.sweeps.push_back({run, 0, 0, 0, crossings});
        if (!run)
            layout.initialCrossings = crossings;
        int runBest = crossings, runSweep = 0;
        Orders runOrder = orders;
        std::vector<Orders> history{orders};
        for (int sweep = 1;; ++sweep) {
            if (!crossings || sweep - 1 == layout.block->settings.sweeps ||
                (sweep - 1 >= 2 && history.back() == history[history.size() - 3]))
                break;
            Order oldPos = positions(orders, static_cast<int>(layout.vertices.size()));
            bool down = sweep % 2;
            if (down)
                for (int layer = 1; layer < static_cast<int>(orders.size()); ++layer)
                    reorderLayer(layout, orders, layer, true);
            else
                for (int layer = static_cast<int>(orders.size()) - 2; layer >= 0; --layer)
                    reorderLayer(layout, orders, layer, false);
            Order newPos = positions(orders, static_cast<int>(layout.vertices.size()));
            int moved = 0;
            for (std::size_t v = 0; v < oldPos.size(); ++v)
                if (oldPos[v] != newPos[v])
                    ++moved;
            int swaps = adjacentExchanges(layout, orders);
            crossings = totalCrossings(layout, orders);
            layout.sweeps.push_back({run, sweep, moved, swaps, crossings});
            history.push_back(orders);
            if (crossings < runBest) {
                runBest = crossings;
                runSweep = sweep;
                runOrder = orders;
            }
        }
        if (bestCrossings < 0 || runBest < bestCrossings) {
            bestCrossings = runBest;
            layout.bestRun = run;
            layout.bestSweep = runSweep;
            adopted = std::move(runOrder);
        }
    }
    layout.adoptedCrossings = bestCrossings;
    layout.orders = std::move(adopted);
    if (layout.block->settings.sifting)
        for (int round = 1;; ++round) {
            int moves = 0;
            for (int v = 0; v < static_cast<int>(layout.vertices.size()); ++v) {
                int layer = layout.vertices[v].layer;
                Order row = layout.orders[layer];
                int original = static_cast<int>(std::find(row.begin(), row.end(), v) - row.begin());
                row.erase(row.begin() + original);
                int minimum = std::numeric_limits<int>::max(), best = 0, originalCost = 0;
                for (int p = 0; p <= static_cast<int>(row.size()); ++p) {
                    Order inserted = row;
                    inserted.insert(inserted.begin() + p, v);
                    Orders trial = layout.orders;
                    trial[layer] = std::move(inserted);
                    Order pos = positions(trial, static_cast<int>(layout.vertices.size()));
                    int cost = 0;
                    if (layer)
                        cost += gapCrossings(layout.segments, layout.gaps[layer - 1], pos,
                                             static_cast<int>(trial[layer].size()));
                    if (layer + 1 < static_cast<int>(trial.size()))
                        cost += gapCrossings(layout.segments, layout.gaps[layer], pos,
                                             static_cast<int>(trial[layer + 1].size()));
                    if (p == original)
                        originalCost = cost;
                    if (cost < minimum) {
                        minimum = cost;
                        best = p;
                    }
                }
                if (originalCost == minimum)
                    best = original;
                row.insert(row.begin() + best, v);
                layout.orders[layer] = std::move(row);
                if (best != original)
                    ++moves;
            }
            layout.sifts.push_back({round, moves, totalCrossings(layout, layout.orders)});
            if (!moves)
                break;
        }
    layout.finalCrossings = totalCrossings(layout, layout.orders);
    layout.brute = bruteCrossings(layout, layout.orders, true);
}
struct Bus {
    bool upper;
    int vertex, low, high, track = 0;
    Order segments;
};
static void geometry(Layout &layout) {
    int layers = static_cast<int>(layout.orders.size());
    layout.tracks.resize(layers - 1);
    layout.gapWidths.resize(layers - 1);
    for (int gap = 0; gap < layers - 1; ++gap) {
        const Order &indices = layout.gaps[gap];
        Order counts(layout.vertices.size());
        for (int index : indices) {
            const Segment &segment = layout.segments[index];
            if (layout.vertices[segment.upper].x != layout.vertices[segment.lower].x)
                ++counts[segment.upper];
        }
        std::map<std::pair<bool, int>, int> byKey;
        std::vector<Bus> buses;
        for (int index : indices) {
            const Segment &segment = layout.segments[index];
            int upper = layout.vertices[segment.upper].x, lower = layout.vertices[segment.lower].x;
            if (upper == lower)
                continue;
            bool upperBus = counts[segment.upper] >= 2;
            int vertex = upperBus ? segment.upper : segment.lower;
            std::pair<bool, int> key{upperBus, vertex};
            auto found = byKey.find(key);
            int bus;
            if (found == byKey.end()) {
                bus = static_cast<int>(buses.size());
                byKey[key] = bus;
                buses.push_back(
                    {upperBus, vertex, std::min(upper, lower), std::max(upper, lower), 0, {}});
            } else
                bus = found->second;
            buses[bus].low = std::min(buses[bus].low, std::min(upper, lower));
            buses[bus].high = std::max(buses[bus].high, std::max(upper, lower));
            buses[bus].segments.push_back(index);
        }
        std::sort(buses.begin(), buses.end(), [&](const Bus &a, const Bus &b) {
            return std::make_tuple(a.low, a.high, !a.upper, layout.vertices[a.vertex].x) <
                   std::make_tuple(b.low, b.high, !b.upper, layout.vertices[b.vertex].x);
        });
        Order ends;
        for (Bus &bus : buses) {
            int track = -1;
            for (int t = 0; t < static_cast<int>(ends.size()); ++t)
                if (ends[t] + 1 < bus.low) {
                    track = t;
                    break;
                }
            if (track < 0) {
                track = static_cast<int>(ends.size());
                ends.push_back(bus.high);
            } else
                ends[track] = bus.high;
            bus.track = track + 1;
        }
        layout.tracks[gap] = static_cast<int>(ends.size());
        layout.gapWidths[gap] = std::max(layout.block->settings.layerGap, layout.tracks[gap] + 2);
        for (const Bus &bus : buses) {
            int offset = bus.track + (layout.gapWidths[gap] - 2 - layout.tracks[gap]) / 2;
            for (int index : bus.segments)
                layout.segments[index].offset = offset;
        }
    }
    layout.thickness.resize(layers, 1);
    layout.bandStarts.resize(layers);
    bool isVertical = vertical(layout.block->settings.direction);
    for (int i = 0; i < layers; ++i) {
        if (!isVertical)
            for (int v : layout.orders[i])
                layout.thickness[i] = std::max(layout.thickness[i], layout.vertices[v].width);
        if (i)
            layout.bandStarts[i] =
                layout.bandStarts[i - 1] + layout.thickness[i - 1] + layout.gapWidths[i - 1];
    }
    layout.mainLength = layout.bandStarts.back() + layout.thickness.back();
    for (const Vertex &vertex : layout.vertices)
        layout.secondaryLength = std::max(layout.secondaryLength, vertex.x + vertex.right + 1);
    layout.canvas =
        Canvas(layout.mainLength, layout.secondaryLength, layout.block->settings.direction);
    for (Edge &edge : layout.edges)
        if (!edge.transitive) {
            const Vertex &upper = layout.vertices[edge.upper], &lower = layout.vertices[edge.lower];
            edge.route.push_back(layout.canvas.map(
                layout.bandStarts[upper.layer] + (isVertical ? 1 : upper.width), upper.x));
            for (int index : edge.segments) {
                const Segment &segment = layout.segments[index];
                int x = layout.vertices[segment.upper].x, y = layout.vertices[segment.lower].x;
                if (x != y) {
                    int main = layout.bandStarts[segment.gap] + layout.thickness[segment.gap] +
                               segment.offset;
                    edge.route.push_back(layout.canvas.map(main, x));
                    edge.route.push_back(layout.canvas.map(main, y));
                    edge.bends += 2;
                }
            }
            edge.route.push_back(layout.canvas.map(layout.bandStarts[lower.layer] - 1, lower.x));
            if (edge.reversed)
                std::reverse(edge.route.begin(), edge.route.end());
            edge.length = 1;
            for (std::size_t i = 0; i + 1 < edge.route.size(); ++i)
                edge.length += std::abs(edge.route[i].row - edge.route[i + 1].row) +
                               std::abs(edge.route[i].column - edge.route[i + 1].column);
        }
    if (layout.block->hasPath) {
        int from = 0, to = 0;
        for (int i = 0; i < layout.nodes; ++i) {
            if (layout.block->nodes[i].id == layout.block->pathFrom)
                from = i;
            if (layout.block->nodes[i].id == layout.block->pathTo)
                to = i;
        }
        Orders adjacent(layout.nodes);
        for (const Edge &edge : layout.edges)
            if (!edge.transitive)
                adjacent[edge.from].push_back(edge.to);
        for (Order &row : adjacent)
            std::sort(row.begin(), row.end());
        Order parent(layout.nodes, -2), queue{from};
        parent[from] = -1;
        for (std::size_t head = 0; head < queue.size(); ++head)
            for (int next : adjacent[queue[head]])
                if (parent[next] == -2) {
                    parent[next] = queue[head];
                    queue.push_back(next);
                }
        if (parent[to] != -2) {
            for (int v = to; v >= 0; v = parent[v])
                layout.path.push_back(v);
            std::reverse(layout.path.begin(), layout.path.end());
        }
    }
}
static void draw(Layout &layout) {
    Canvas &canvas = layout.canvas;
    for (int i = 0; i < static_cast<int>(layout.vertices.size()); ++i) {
        const Vertex &vertex = layout.vertices[i];
        if (i >= layout.nodes)
            for (int j = 0; j < layout.thickness[vertex.layer]; ++j)
                canvas.mainLine(layout.bandStarts[vertex.layer] + j, vertex.x);
        else if (!vertical(canvas.direction) && !vertex.lower.empty())
            for (int j = vertex.width; j < layout.thickness[vertex.layer]; ++j)
                canvas.mainLine(layout.bandStarts[vertex.layer] + j, vertex.x);
    }
    for (const Segment &segment : layout.segments)
        canvas.segment(layout.bandStarts[segment.gap] + layout.thickness[segment.gap],
                       layout.gapWidths[segment.gap], layout.vertices[segment.upper].x,
                       layout.vertices[segment.lower].x, segment.offset);
    const std::array<std::array<char, 2>, 4> arrows{
        {{{'v', '^'}}, {{'^', 'v'}}, {{'>', '<'}}, {{'<', '>'}}}};
    for (const Edge &edge : layout.edges)
        if (!edge.transitive)
            canvas.at(edge.route.back()).arrow =
                arrows[static_cast<int>(canvas.direction)][edge.reversed ? 1 : 0];
    std::set<int> pathNodes(layout.path.begin(), layout.path.end());
    std::set<std::pair<int, int>> pathEdges;
    for (std::size_t i = 1; i < layout.path.size(); ++i)
        pathEdges.insert({layout.path[i - 1], layout.path[i]});
    for (const Edge &edge : layout.edges)
        if (!edge.transitive && pathEdges.count({edge.from, edge.to}))
            for (std::size_t i = 0; i + 1 < edge.route.size(); ++i)
                canvas.highlight(edge.route[i], edge.route[i + 1]);
    for (int i = 0; i < layout.nodes; ++i) {
        const Vertex &vertex = layout.vertices[i];
        std::string box = pathNodes.count(i) ? "{" + layout.block->nodes[i].label + "}"
                                             : "[" + layout.block->nodes[i].label + "]";
        Cell start;
        if (vertical(canvas.direction))
            start = canvas.map(layout.bandStarts[vertex.layer], vertex.x - vertex.left);
        else
            start = {vertex.x,
                     canvas.direction == Direction::LR
                         ? layout.bandStarts[vertex.layer]
                         : layout.mainLength - layout.bandStarts[vertex.layer] - vertex.width};
        for (std::size_t j = 0; j < box.size(); ++j)
            canvas.at({start.row, start.column + static_cast<int>(j)}).box = box[j];
    }
}
static Lines displayNames(const Layout &layout, const Order &vertices) {
    Lines out;
    for (int v : vertices)
        out.push_back(layout.vertices[v].name);
    return out;
}
static std::string edgeName(const Layout &layout, const Edge &edge) {
    return layout.vertices[edge.from].name + "->" + layout.vertices[edge.to].name;
}
static Lines layoutLines(const Layout &layout) {
    const Block &block = *layout.block;
    Lines settings, values = block.settings.values();
    for (std::size_t i = 0; i < settingNames.size(); ++i)
        settings.push_back(settingNames[i] + "=" + values[i]);
    Lines out{"graph " + block.name, "settings " + join(settings),
              "acyclic " + join(displayNames(layout, layout.acyclic))};
    if (block.settings.coffman) {
        Lines labels;
        for (int i = 0; i < layout.nodes; ++i)
            labels.push_back(text(layout.vertices[i].name, ":", layout.layering.labels[i]));
        out.push_back("labels " + join(labels));
    }
    for (const Promotion &promotion : layout.layering.promotions)
        out.push_back(text("promote ", promotion.round, " ", layout.vertices[promotion.node].name,
                           " ", promotion.difference));
    for (const Sweep &sweep : layout.sweeps) {
        if (!sweep.number)
            out.push_back(text("sweep ", sweep.run, " 0 initial crossings ", sweep.crossings));
        else
            out.push_back(text("sweep ", sweep.run, " ", sweep.number,
                               sweep.number % 2 ? " down moved " : " up moved ", sweep.moved,
                               " swaps ", sweep.swaps, " crossings ", sweep.crossings));
    }
    out.push_back(text("best run ", layout.bestRun, " sweep ", layout.bestSweep, " crossings ",
                       layout.adoptedCrossings));
    for (const Sift &sift : layout.sifts)
        out.push_back(
            text("sift ", sift.round, " moves ", sift.moves, " crossings ", sift.crossings));
    for (int layer = 0; layer < static_cast<int>(layout.orders.size()); ++layer) {
        int start = layout.bandStarts[layer], end = start + layout.thickness[layer] - 1;
        if (block.settings.direction == Direction::BT ||
            block.settings.direction == Direction::RL) {
            int oldStart = start;
            start = layout.mainLength - 1 - end;
            end = layout.mainLength - 1 - oldStart;
        }
        int low = 0, high = 0;
        Lines vertices;
        for (int v : layout.orders[layer]) {
            const Vertex &vertex = layout.vertices[v];
            if (vertices.empty() || vertex.x - vertex.left < low)
                low = vertex.x - vertex.left;
            if (vertices.empty() || vertex.x + vertex.right > high)
                high = vertex.x + vertex.right;
            vertices.push_back(text(vertex.name, "@", vertex.x));
        }
        out.push_back(text("layer ", layer, " band ", start, " ", end, " extent ", low, " ", high,
                           " : ", join(vertices)));
    }
    Order pos = positions(layout.orders, static_cast<int>(layout.vertices.size()));
    for (int gap = 0; gap < static_cast<int>(layout.gaps.size()); ++gap)
        out.push_back(text("between ", gap, " ", gap + 1, " segments ", layout.gaps[gap].size(),
                           " crossings ",
                           gapCrossings(layout.segments, layout.gaps[gap], pos,
                                        static_cast<int>(layout.orders[gap + 1].size())),
                           " tracks ", layout.tracks[gap], " gap ", layout.gapWidths[gap]));
    Lines variants;
    for (int i = 0; i < 4; ++i)
        variants.push_back(text(variantNames[i], "=", layout.coordinates.variants[i].blocks, "/",
                                layout.coordinates.variants[i].width));
    out.push_back(text("bk conflicts ", layout.coordinates.marked.size(), " ", join(variants),
                       " smallest ", variantNames[layout.coordinates.smallest]));
    for (int layer = 0; layer < static_cast<int>(layout.orders.size()); ++layer)
        for (std::size_t at = 0; at < layout.orders[layer].size(); ++at) {
            int v = layout.orders[layer][at];
            const auto &variants = layout.coordinates.variants;
            out.push_back(text("vertex ", layout.vertices[v].name, " layer ", layer, " pos ", at,
                               " ul ", variants[0].aligned[v], " ur ", variants[1].aligned[v],
                               " dl ", variants[2].aligned[v], " dr ", variants[3].aligned[v],
                               " x ", layout.vertices[v].x));
        }
    for (const Edge &edge : layout.edges) {
        std::string prefix =
            text("edge ", layout.vertices[edge.from].name, " ", layout.vertices[edge.to].name);
        if (edge.transitive) {
            out.push_back(prefix + " transitive");
            continue;
        }
        if (edge.reversed)
            prefix += " reversed";
        Order chain = edge.chain;
        if (edge.reversed)
            std::reverse(chain.begin(), chain.end());
        Lines values, route;
        for (int v : chain)
            values.push_back(std::to_string(layout.vertices[v].x));
        for (Cell cell : edge.route)
            route.push_back(text(cell.row, ",", cell.column));
        out.push_back(text(prefix, " span ", edge.span, " crossings ", edge.crossings, " bends ",
                           edge.bends, " path ", join(values), " route ", join(route)));
    }
    out.push_back("end");
    return out;
}
static Lines statsLines(const Layout &layout) {
    const Block &block = *layout.block;
    Lines out{"graph " + block.name,
              text("nodes ", layout.nodes, " edges ", layout.edges.size(), " self_loops ",
                   block.selfLoops, " duplicates ", block.duplicates),
              text("sources ", layout.sources, " sinks ", layout.sinks, " isolated ",
                   layout.isolated, " components ", layout.components)};
    for (const Order &component : layout.scc)
        out.push_back("scc " + join(displayNames(layout, component)));
    Lines reversed, transitive;
    std::map<int, int> spanCounts;
    int spanTotal = 0, spanMax = 0, longEdges = 0, verticalEdges = 0, routeLength = 0, bends = 0,
        longest = -1;
    for (int i = 0; i < static_cast<int>(layout.edges.size()); ++i) {
        const Edge &edge = layout.edges[i];
        if (edge.reversed)
            reversed.push_back(edgeName(layout, edge));
        if (edge.transitive) {
            transitive.push_back(edgeName(layout, edge));
            continue;
        }
        ++spanCounts[edge.span];
        spanTotal += edge.span;
        spanMax = std::max(spanMax, edge.span);
        if (edge.span >= 2) {
            ++longEdges;
            bool same = true;
            int x = layout.vertices[edge.chain[1]].x;
            for (std::size_t at = 1; at + 1 < edge.chain.size(); ++at)
                if (layout.vertices[edge.chain[at]].x != x)
                    same = false;
            if (same)
                ++verticalEdges;
        }
        routeLength += edge.length;
        bends += edge.bends;
        if (longest < 0 || edge.length > layout.edges[longest].length)
            longest = i;
    }
    out.push_back(text("reversed ", reversed.size(), reversed.empty() ? "" : " " + join(reversed)));
    out.push_back(
        text("transitive ", transitive.size(), transitive.empty() ? "" : " " + join(transitive)));
    int maxNodes = 0, maxVertices = 0;
    for (const Order &row : layout.orders) {
        int nodes = 0;
        for (int v : row)
            if (v < layout.nodes)
                ++nodes;
        maxNodes = std::max(maxNodes, nodes);
        maxVertices = std::max(maxVertices, static_cast<int>(row.size()));
    }
    out.push_back(text("layers ", layout.orders.size(), " max_nodes ", maxNodes, " max_vertices ",
                       maxVertices));
    out.push_back(block.settings.promotion ? text("promotion rounds ", layout.layering.rounds,
                                                  " accepted ", layout.layering.promotions.size(),
                                                  " dummies_before ", layout.layering.dummiesBefore)
                                           : "promotion off");
    out.push_back(text("dummies ", layout.vertices.size() - layout.nodes, " span_total ", spanTotal,
                       " span_max ", spanMax));
    Lines spans;
    for (const auto &entry : spanCounts)
        spans.push_back(text(entry.first, ":", entry.second));
    out.push_back(spans.empty() ? "spans none" : "spans " + join(spans));
    out.push_back(text("long_edges ", longEdges, " vertical ", verticalEdges));
    out.push_back(text("crossings initial ", layout.initialCrossings, " swept ",
                       layout.adoptedCrossings, " best_run ", layout.bestRun, " best_sweep ",
                       layout.bestSweep, " final ", layout.finalCrossings, " brute ",
                       layout.brute));
    int straight = 0, offset = 0;
    for (const Segment &segment : layout.segments) {
        int a = layout.vertices[segment.upper].x, b = layout.vertices[segment.lower].x;
        if (a == b)
            ++straight;
        offset += std::abs(a - b);
    }
    out.push_back(text("segments ", layout.segments.size(), " straight ", straight, " bent ",
                       layout.segments.size() - straight, " offset ", offset));
    std::string routes = text("routes length ", routeLength, " bends ", bends);
    if (longest >= 0)
        routes += text(" longest ", edgeName(layout, layout.edges[longest]), " ",
                       layout.edges[longest].length);
    out.push_back(routes);
    out.push_back(text("canvas width ", layout.canvas.columns, " height ", layout.canvas.rows,
                       " crossing_cells ", layout.canvas.crossingCells()));
    if (block.hasPath)
        out.push_back(layout.path.empty()
                          ? text("path ", block.pathFrom, " ", block.pathTo, " none")
                          : text("path ", block.pathFrom, " ", block.pathTo, " hops ",
                                 layout.path.size() - 1, " : ",
                                 join(displayNames(layout, layout.path))));
    out.push_back("end");
    return out;
}
static void writeLines(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    if (!output)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        output << line << '\n';
    if (!output)
        throw std::runtime_error("cannot write " + name);
}
int main() {
    std::vector<Block> blocks = readBlocks();
    Lines layout, stats, drawings, crossings{"graph,run,sweep,crossings"};
    int laidOut = 0, errors = 0, nodes = 0, edges = 0, dummies = 0, initial = 0, final = 0;
    for (std::size_t i = 0; i < blocks.size(); ++i) {
        const Block &block = blocks[i];
        if (i)
            drawings.push_back("");
        if (!block.error.empty()) {
            ++errors;
            Lines errorLines{"graph " + block.name,
                             text("error ", block.error, " line ", block.errorLine), "end"};
            append(layout, errorLines);
            append(stats, errorLines);
            drawings.push_back("graph " + block.name + " error " + block.error);
            continue;
        }
        Layout current = initialize(block);
        reduceCrossings(current);
        current.coordinates = coordinates(current);
        geometry(current);
        draw(current);
        append(layout, layoutLines(current));
        append(stats, statsLines(current));
        append(drawings, current.canvas.drawing(block.name));
        for (const Sweep &sweep : current.sweeps)
            crossings.push_back(
                text(block.name, ",", sweep.run, ",", sweep.number, ",", sweep.crossings));
        ++laidOut;
        nodes += current.nodes;
        edges += static_cast<int>(current.edges.size());
        dummies += static_cast<int>(current.vertices.size()) - current.nodes;
        initial += current.initialCrossings;
        final += current.finalCrossings;
    }
    stats.push_back(text("summary graphs ", blocks.size(), " laid_out ", laidOut, " errors ",
                         errors, " nodes ", nodes, " edges ", edges, " dummies ", dummies,
                         " crossings_initial ", initial, " crossings_final ", final));
    std::filesystem::create_directories("output");
    writeLines("layout.txt", layout);
    writeLines("stats.txt", stats);
    writeLines("crossings.csv", crossings);
    writeLines("drawings.txt", drawings);
}
