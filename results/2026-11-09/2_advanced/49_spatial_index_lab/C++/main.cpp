#include "spatial.hpp"
#include <filesystem>
static const Lines structures = {"kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect"},
                   search_names = {"RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"},
                   quadrants = {"NW", "NE", "SW", "SE"};
struct View {
    Box region;
    std::vector<Object> objects;
    std::vector<std::unique_ptr<View>> children;
    Integer count = 0;
    int depth = 0;
    std::string mark;
    const KDNode *kd = nullptr;
    const QuadNode *quad = nullptr;
    const RNode *rtree = nullptr;
};
static std::unique_ptr<View> kd_view(const KDNode &node, Box region, const std::string &mark) {
    auto out = std::make_unique<View>();
    out->region = region;
    out->depth = node.depth;
    out->mark = mark;
    out->kd = &node;
    out->objects.push_back({node.point.id, node.point.box()});
    out->count = 1;
    if (node.left) {
        Box left = region;
        if (node.depth % 2 == 0)
            left.x2 = node.point.x;
        else
            left.y2 = node.point.y;
        out->children.push_back(kd_view(*node.left, left, "L"));
    }
    if (node.right) {
        Box right = region;
        if (node.depth % 2 == 0)
            right.x1 = node.point.x;
        else
            right.y1 = node.point.y;
        out->children.push_back(kd_view(*node.right, right, "R"));
    }
    for (const auto &child : out->children)
        out->count += child->count;
    return out;
}
static std::unique_ptr<View> quad_view(const QuadNode &node, int depth = 0,
                                       const std::string &mark = "root") {
    auto out = std::make_unique<View>();
    out->region = {node.x, node.y, node.x + node.size - 1, node.y + node.size - 1};
    out->depth = depth;
    out->mark = mark;
    out->quad = &node;
    if (node.leaf())
        for (Point point : node.points)
            out->objects.push_back({point.id, point.box()});
    else
        for (int i = 0; i < 4; ++i)
            out->children.push_back(quad_view(*node.children[i], depth + 1, quadrants[i]));
    out->count = out->objects.size();
    for (const auto &child : out->children)
        out->count += child->count;
    return out;
}
static std::unique_ptr<View> r_view(const RNode &node, int depth = 0) {
    auto out = std::make_unique<View>();
    out->region = node.box();
    out->depth = depth;
    out->rtree = &node;
    if (node.level == 0)
        for (const Entry &entry : node.entries)
            out->objects.push_back({entry.id, entry.box});
    else
        for (const Entry &entry : node.entries)
            out->children.push_back(r_view(*entry.child, depth + 1));
    out->count = out->objects.size();
    for (const auto &child : out->children)
        out->count += child->count;
    return out;
}
static std::unique_ptr<View> grid_view(const Grid &grid) {
    auto out = std::make_unique<View>();
    out->region = {0, 0, grid.world - 1, grid.world - 1};
    for (int j = 0; j < grid.dimension; ++j)
        for (int i = 0; i < grid.dimension; ++i) {
            auto cell = std::make_unique<View>();
            cell->region = {i * grid.side, j * grid.side, i * grid.side + grid.side - 1,
                            j * grid.side + grid.side - 1};
            cell->depth = 1;
            for (Point point : grid.cells[j * grid.dimension + i])
                cell->objects.push_back({point.id, point.box()});
            cell->count = cell->objects.size();
            out->count += cell->count;
            out->children.push_back(std::move(cell));
        }
    return out;
}
static std::array<std::unique_ptr<View>, 7> views(const KDNode &kd, const QuadNode &quad, const RTree &rtree,
                                                  const RTree &str, const Grid &grid, const RTree &rect,
                                                  const RTree &str_rect, int world) {
    return {kd_view(kd, {0, 0, world - 1, world - 1}, "root"),
            quad_view(quad),
            r_view(*rtree.root),
            r_view(*str.root),
            grid_view(grid),
            r_view(*rect.root),
            r_view(*str_rect.root)};
}
struct Visit {
    Integer nodes = 0, tests = 0;
};
struct Answer {
    std::vector<std::pair<int, Integer>> values;
    Integer count = 0;
    bool operator==(const Answer &other) const {
        return count == other.count && values == other.values;
    }
};
static Box command_box(const Command &command) {
    return {command.values[0], command.values[1], command.values[2], command.values[3]};
}
static bool region_condition(const Command &command, Box region) {
    if (command.name == "RANGE" || command.name == "WINDOWCOUNT")
        return intersects(region, command_box(command));
    if (command.name == "CONTAINS")
        return contains(region, {command.values[0], command.values[1], command.values[0], command.values[1]});
    return distance(command.values[0], command.values[1], region) <= command.values[2] * command.values[2];
}
static bool object_condition(const Command &command, Object object) {
    if (command.name == "RANGE" || command.name == "WINDOWCOUNT")
        return contains(command_box(command), object.box);
    if (command.name == "CONTAINS")
        return contains(object.box,
                        {command.values[0], command.values[1], command.values[0], command.values[1]});
    return distance(command.values[0], command.values[1], object.box) <=
           command.values[2] * command.values[2];
}
static void condition_search(const View &node, const Command &command, Visit &visit, Answer &answer) {
    ++visit.nodes;
    if (command.name == "WINDOWCOUNT" && contains(command_box(command), node.region)) {
        answer.count += node.count;
        return;
    }
    visit.tests += node.objects.size();
    for (Object object : node.objects)
        if (object_condition(command, object)) {
            if (command.name == "WINDOWCOUNT")
                ++answer.count;
            else
                answer.values.push_back({object.id, 0});
        }
    for (const auto &child : node.children)
        if (region_condition(command, child->region))
            condition_search(*child, command, visit, answer);
}
struct QueueElement {
    Integer distance = 0;
    int kind = 0;
    Integer tie = 0;
    const View *node = nullptr;
    Object object;
};
struct Later {
    bool operator()(const QueueElement &a, const QueueElement &b) const {
        return std::tie(a.distance, a.kind, a.tie) > std::tie(b.distance, b.kind, b.tie);
    }
};
static Answer best_first(const View &root, const Command &command, Visit &visit) {
    Answer out;
    std::priority_queue<QueueElement, std::vector<QueueElement>, Later> queue;
    Integer serial = 0;
    const Integer x = command.values[0], y = command.values[1], k = command.values[2];
    queue.push({distance(x, y, root.region), 0, serial++, &root, {}});
    while (!queue.empty()) {
        const QueueElement element = queue.top();
        queue.pop();
        if (element.kind == 1) {
            out.values.push_back({element.object.id, element.distance});
            if (Integer(out.values.size()) == k)
                break;
        } else {
            const View &node = *element.node;
            ++visit.nodes;
            visit.tests += node.objects.size();
            for (Object object : node.objects)
                queue.push({distance(x, y, object.box), 1, object.id, nullptr, object});
            for (const auto &child : node.children)
                queue.push({distance(x, y, child->region), 0, serial++, child.get(), {}});
        }
    }
    out.count = out.values.size();
    return out;
}
static Answer search(const View &root, const Command &command, Visit &visit) {
    if (command.name == "KNN" || command.name == "NEAREST")
        return best_first(root, command, visit);
    Answer out;
    condition_search(root, command, visit, out);
    if (command.name != "WINDOWCOUNT") {
        std::sort(out.values.begin(), out.values.end());
        out.count = out.values.size();
    }
    return out;
}
static void spatial_join(const View &a, const View &b, Visit &visit, Answer &answer) {
    ++visit.nodes;
    const bool al = a.children.empty(), bl = b.children.empty();
    if (al && bl) {
        visit.tests += a.objects.size() * b.objects.size();
        for (Object point : a.objects)
            for (Object rect : b.objects)
                if (contains(rect.box, point.box))
                    answer.values.push_back({rect.id, point.id});
    } else if (al) {
        for (const auto &child : b.children)
            if (intersects(a.region, child->region))
                spatial_join(a, *child, visit, answer);
    } else if (bl) {
        for (const auto &child : a.children)
            if (intersects(child->region, b.region))
                spatial_join(*child, b, visit, answer);
    } else
        for (const auto &left : a.children)
            for (const auto &right : b.children)
                if (intersects(left->region, right->region))
                    spatial_join(*left, *right, visit, answer);
}
static Answer brute(const Command &command, const std::map<int, Point> &points,
                    const std::vector<Object> &rectangles) {
    Answer out;
    if (command.name == "JOIN") {
        for (Object rect : rectangles)
            for (const auto &entry : points)
                if (contains(rect.box, entry.second.box()))
                    out.values.push_back({rect.id, entry.first});
        std::sort(out.values.begin(), out.values.end());
        out.count = out.values.size();
        return out;
    }
    std::vector<Object> objects;
    if (command.name == "CONTAINS" || command.name == "NEAREST")
        objects = rectangles;
    else
        for (const auto &entry : points)
            objects.push_back({entry.first, entry.second.box()});
    if (command.name == "KNN" || command.name == "NEAREST") {
        for (Object object : objects)
            out.values.push_back({object.id, distance(command.values[0], command.values[1], object.box)});
        std::sort(out.values.begin(), out.values.end(), [](const auto &a, const auto &b) {
            return std::make_pair(a.second, a.first) < std::make_pair(b.second, b.first);
        });
        out.values.resize(command.values[2]);
    } else
        for (Object object : objects)
            if (object_condition(command, object)) {
                if (command.name == "WINDOWCOUNT")
                    ++out.count;
                else
                    out.values.push_back({object.id, 0});
            }
    if (command.name != "WINDOWCOUNT") {
        if (command.name != "KNN" && command.name != "NEAREST")
            std::sort(out.values.begin(), out.values.end());
        out.count = out.values.size();
    }
    return out;
}
static std::string box_text(Box box) {
    return std::to_string(box.x1) + " " + std::to_string(box.y1) + " " + std::to_string(box.x2) + " " +
           std::to_string(box.y2);
}
static void dump(std::ostream &out, const View &node) {
    out << std::string(2 * (node.depth + 1), ' ');
    if (node.kd) {
        const Point point = node.kd->point;
        out << node.mark << ' ' << (node.depth % 2 ? "y" : "x") << ' ' << point.id << ' ' << point.x << ' '
            << point.y << " box " << box_text(node.region);
    } else if (node.quad) {
        out << node.mark << ' ' << node.quad->x << ' ' << node.quad->y << ' ' << node.quad->size;
        if (node.quad->leaf()) {
            std::vector<int> values;
            for (Object object : node.objects)
                values.push_back(object.id);
            out << " leaf " << ids(values);
        } else
            out << " node count " << node.count;
    } else if (node.rtree) {
        if (node.rtree->level == 0) {
            std::vector<int> values;
            for (Object object : node.objects)
                values.push_back(object.id);
            out << "leaf " << box_text(node.region) << " ids " << ids(values);
        } else
            out << "node " << node.rtree->level << ' ' << box_text(node.region) << " entries "
                << node.rtree->entries.size();
    }
    out << '\n';
    for (const auto &child : node.children)
        dump(out, *child);
}
static void flatten(const View &node, std::vector<const View *> &out) {
    out.push_back(&node);
    for (const auto &child : node.children)
        flatten(*child, out);
}
static void kd_stats(std::ostream &out, const View &root) {
    std::vector<const View *> nodes;
    flatten(root, nodes);
    int height = 0, ideal = 0;
    Integer leaves = 0, one = 0, depth_sum = 0;
    std::map<int, std::array<Integer, 3>> levels;
    for (const View *node : nodes) {
        height = std::max(height, node->depth + 1);
        leaves += node->children.empty();
        one += node->children.size() == 1;
        depth_sum += node->depth;
        auto &value = levels[node->depth];
        ++value[0];
        value[1] += node->children.empty();
        value[2] += node->children.size() == 1;
    }
    Integer capacity = 0;
    while (capacity < Integer(nodes.size())) {
        capacity = 2 * capacity + 1;
        ++ideal;
    }
    out << "kdtree height " << height << " ideal " << ideal << " nodes " << nodes.size() << " leaves "
        << leaves << " one_child " << one << " depth_sum " << depth_sum << " avg_depth "
        << fraction(depth_sum, nodes.size()) << '\n';
    for (int depth = 0; depth < height; ++depth) {
        const auto value = levels[depth];
        out << "  depth " << depth << " nodes " << value[0] << " leaves " << value[1] << " one_child "
            << value[2] << '\n';
    }
}
static void quad_stats(std::ostream &out, const View &root, int bucket) {
    std::vector<const View *> nodes;
    flatten(root, nodes);
    int height = 0;
    Integer internal = 0, leaves = 0, empty = 0, maximum = 0;
    std::map<int, std::array<Integer, 3>> levels;
    for (const View *node : nodes) {
        height = std::max(height, node->depth + 1);
        auto &value = levels[node->depth];
        if (node->children.empty()) {
            ++leaves;
            empty += node->objects.empty();
            maximum = std::max(maximum, Integer(node->objects.size()));
            ++value[1];
            value[2] += node->objects.size();
        } else {
            ++internal;
            ++value[0];
        }
    }
    out << "quadtree height " << height << " internal " << internal << " leaves " << leaves << " empty "
        << empty << " max_leaf " << maximum << " fill " << fraction(root.count, leaves * bucket) << '\n';
    for (int depth = 0; depth < height; ++depth) {
        const auto value = levels[depth];
        out << "  depth " << depth << " internal " << value[0] << " leaves " << value[1] << " points "
            << value[2] << '\n';
    }
}
static void r_stats(std::ostream &out, const View &root, const std::string &name, int maximum, int minimum) {
    std::vector<const View *> nodes;
    flatten(root, nodes);
    Integer leaves = 0, entries = 0;
    std::map<int, std::vector<const View *>> levels;
    for (const View *node : nodes) {
        leaves += node->rtree->level == 0;
        entries += node->rtree->entries.size();
        levels[node->rtree->level].push_back(node);
    }
    out << name << " height " << root.rtree->level + 1 << " nodes " << nodes.size() << " leaves " << leaves
        << " entries " << entries << " fill " << fraction(entries, nodes.size() * maximum) << '\n';
    for (int level = root.rtree->level; level >= 0; --level) {
        const auto &values = levels[level];
        Integer count = 0, low = values[0]->rtree->entries.size(), high = low, under = 0, total_area = 0,
                total_overlap = 0;
        for (std::size_t i = 0; i < values.size(); ++i) {
            const Integer n = values[i]->rtree->entries.size();
            count += n;
            low = std::min(low, n);
            high = std::max(high, n);
            under += n < minimum;
            total_area += area(values[i]->region);
            for (std::size_t j = i + 1; j < values.size(); ++j)
                total_overlap += overlap(values[i]->region, values[j]->region);
        }
        out << "  level " << level << " nodes " << values.size() << " entries " << count << " min " << low
            << " max " << high << " under " << under << " area " << total_area << " overlap " << total_overlap
            << '\n';
    }
}
static void grid_stats(std::ostream &out, const Grid &grid) {
    Integer used = 0, maximum = 0;
    std::map<Integer, Integer> counts;
    for (const auto &cell : grid.cells) {
        used += !cell.empty();
        maximum = std::max(maximum, Integer(cell.size()));
        ++counts[cell.size()];
    }
    out << "grid cells " << grid.cells.size() << " used " << used << " max " << maximum << "\n  occupancy";
    for (const auto &entry : counts)
        out << ' ' << entry.first << ':' << entry.second;
    out << '\n';
}
static std::string path_text(const std::vector<int> &values) {
    std::string out;
    for (int value : values)
        out += (out.empty() ? "" : "/") + std::to_string(value);
    return out;
}
static bool r_location(const RNode &node, Point point, std::vector<int> &path) {
    for (std::size_t i = 0; i < node.entries.size(); ++i) {
        const Entry &entry = node.entries[i];
        if (node.level == 0) {
            if (entry.id == point.id) {
                path.push_back(i + 1);
                return true;
            }
        } else if (contains(entry.box, point.box())) {
            path.push_back(i + 1);
            if (r_location(*entry.child, point, path))
                return true;
            path.pop_back();
        }
    }
    return false;
}
static void save(const std::string &name, const std::ostringstream &stream) {
    std::istringstream input(stream.str());
    Lines lines;
    std::string line;
    while (std::getline(input, line))
        lines.push_back(line);
    write_lines(name, lines);
}
struct Aggregate {
    Integer queries = 0, nodes = 0, tests = 0, maximum = 0;
};
int main() {
    std::filesystem::create_directories("output");
    const Input input = read_input();
    const Params &p = input.params;
    std::map<int, Point> points;
    for (Point point : input.points)
        points[point.id] = point;
    auto kd = kd_build(input.points);
    QuadNode quad;
    quad.size = p.world;
    Grid grid(p.world, p.grid);
    RTree rtree(p.maximum, p.minimum), str(p.maximum, p.minimum), rect(p.maximum, p.minimum),
        str_rect(p.maximum, p.minimum);
    std::vector<Entry> point_entries, rect_entries;
    for (Point point : input.points) {
        quad_insert(quad, point, p.bucket);
        grid.insert(point);
        const Entry entry{point.box(), point.id, point.id, {}};
        rtree.insert(entry);
        point_entries.push_back(entry);
    }
    for (Object object : input.rectangles) {
        const Entry entry{object.box, object.id, object.id, {}};
        rect.insert(entry);
        rect_entries.push_back(entry);
    }
    str.bulk(point_entries);
    str_rect.bulk(rect_entries);
    std::ostringstream answers, visits, join_file, structures_file, stats;
    visits << "query,command,structure,nodes,tests\n";
    join_file << "query,rect,point\n";
    std::array<std::array<Aggregate, 7>, 7> aggregates{};
    int snapshot = 0;
    auto record = [&](int query) {
        if (snapshot) {
            structures_file << '\n';
            stats << '\n';
        }
        const std::string heading = "snapshot " + std::to_string(snapshot) + " query " +
                                    std::to_string(query) + " points " + std::to_string(points.size()) +
                                    " rects " + std::to_string(input.rectangles.size());
        structures_file << heading << '\n';
        stats << heading << '\n';
        const auto roots = views(*kd, quad, rtree, str, grid, rect, str_rect, p.world);
        for (int structure : std::vector<int>{0, 1, 2, 3, 5, 6}) {
            structures_file << structures[structure] << '\n';
            dump(structures_file, *roots[structure]);
        }
        kd_stats(stats, *roots[0]);
        quad_stats(stats, *roots[1], p.bucket);
        for (int structure : std::vector<int>{2, 3, 5, 6})
            r_stats(stats, *roots[structure], structures[structure], p.maximum, p.minimum);
        grid_stats(stats, grid);
    };
    record(0);
    for (std::size_t index = 0; index < input.commands.size(); ++index) {
        const Command &command = input.commands[index];
        const std::string &name = command.name;
        const int query = index + 1;
        answers << query << ' ' << name;
        if (name == "INSERT") {
            const Point point{int(command.values[0]), command.values[1], command.values[2]};
            points[point.id] = point;
            kd_insert(kd, point);
            quad_insert(quad, point, p.bucket);
            grid.insert(point);
            const Entry entry{point.box(), point.id, point.id, {}};
            rtree.insert(entry);
            str.insert(entry);
            answers << ' ' << point.id << " inserted points " << points.size() << '\n';
        } else if (name == "DELETE") {
            const int id = command.values[0];
            const auto found = points.find(id);
            if (found == points.end())
                answers << ' ' << id << " missing points " << points.size() << '\n';
            else {
                const Point point = found->second;
                kd_delete(kd, point);
                quad_delete(quad, point, p.bucket);
                rtree.erase(point);
                str.erase(point);
                grid.erase(point);
                points.erase(found);
                answers << ' ' << id << " deleted points " << points.size() << '\n';
            }
        } else if (name == "DUMP") {
            ++snapshot;
            record(query);
            answers << " snapshot " << snapshot << '\n';
        } else if (name == "LOCATE") {
            const int id = command.values[0];
            const auto found = points.find(id);
            answers << ' ' << id;
            if (found == points.end())
                answers << " missing\n";
            else {
                const Point point = found->second;
                std::string kd_path;
                const KDNode *node = kd.get();
                while (node->point.id != id) {
                    const bool left = key_less(point, node->point, node->depth % 2);
                    kd_path += left ? 'L' : 'R';
                    node = left ? node->left.get() : node->right.get();
                }
                std::string quad_path;
                const QuadNode *q = &quad;
                while (!q->leaf()) {
                    const int child = destination(*q, point);
                    quad_path += (quad_path.empty() ? "" : "/") + quadrants[child];
                    q = q->children[child].get();
                }
                std::vector<int> a, b;
                r_location(*rtree.root, point, a);
                r_location(*str.root, point, b);
                answers << " kdtree " << (kd_path.empty() ? "-" : kd_path) << " quadtree "
                        << (quad_path.empty() ? "-" : quad_path) << " rtree " << path_text(a) << " str "
                        << path_text(b) << " grid " << point.x / p.grid << ' ' << point.y / p.grid << '\n';
            }
        } else {
            const int type = std::find(search_names.begin(), search_names.end(), name) - search_names.begin();
            const auto roots = views(*kd, quad, rtree, str, grid, rect, str_rect, p.world);
            const Answer expected = brute(command, points, input.rectangles);
            std::vector<int> selected;
            if (name == "CONTAINS" || name == "NEAREST")
                selected = {5, 6};
            else if (name == "JOIN")
                selected = {2, 3};
            else
                selected = {0, 1, 2, 3, 4};
            Lines mismatches;
            for (int structure : selected) {
                Visit visit;
                Answer actual;
                if (name == "JOIN") {
                    spatial_join(*roots[structure], *roots[structure == 2 ? 5 : 6], visit, actual);
                    std::sort(actual.values.begin(), actual.values.end());
                    actual.count = actual.values.size();
                } else
                    actual = search(*roots[structure], command, visit);
                if (!(actual == expected))
                    mismatches.push_back(structures[structure]);
                visits << query << ',' << name << ',' << structures[structure] << ',' << visit.nodes << ','
                       << visit.tests << '\n';
                Aggregate &aggregate = aggregates[type][structure];
                ++aggregate.queries;
                aggregate.nodes += visit.nodes;
                aggregate.tests += visit.tests;
                aggregate.maximum = std::max(aggregate.maximum, visit.nodes);
            }
            answers << " count " << expected.count;
            if (name == "RANGE" || name == "RADIUS" || name == "CONTAINS") {
                std::vector<int> values;
                for (const auto &entry : expected.values)
                    values.push_back(entry.first);
                answers << " ids " << ids(values);
            } else if (name == "KNN" || name == "NEAREST") {
                answers << " ids";
                for (const auto &entry : expected.values)
                    answers << ' ' << entry.first << ':' << entry.second;
            } else if (name == "JOIN")
                for (const auto &entry : expected.values)
                    join_file << query << ',' << entry.first << ',' << entry.second << '\n';
            answers << " check " << (mismatches.empty() ? "ok" : "mismatch");
            for (const std::string &value : mismatches)
                answers << ' ' << value;
            answers << '\n';
        }
    }
    stats << "\nvisits\n";
    for (int type = 0; type < 7; ++type) {
        std::vector<int> selected;
        for (int structure = 0; structure < 7; ++structure)
            if (aggregates[type][structure].queries) {
                selected.push_back(structure);
                const Aggregate &value = aggregates[type][structure];
                stats << search_names[type] << ' ' << structures[structure] << " queries " << value.queries
                      << " nodes " << value.nodes << " tests " << value.tests << " max_nodes "
                      << value.maximum << " mean_nodes " << fraction(value.nodes, value.queries) << '\n';
            }
        if (selected.empty())
            continue;
        std::sort(selected.begin(), selected.end(), [&](int a, int b) {
            return std::make_tuple(aggregates[type][a].nodes, aggregates[type][a].tests, a) <
                   std::make_tuple(aggregates[type][b].nodes, aggregates[type][b].tests, b);
        });
        stats << "rank " << search_names[type];
        for (int structure : selected)
            stats << ' ' << structures[structure];
        stats << '\n';
    }
    save("answers.txt", answers);
    save("visits.csv", visits);
    save("join.csv", join_file);
    save("structures.txt", structures_file);
    save("stats.txt", stats);
}
