#include "mesh.hpp"
#include <filesystem>
std::string list(const std::vector<int> &values, int offset) {
    if (values.empty())
        return "-";
    std::string out;
    for (int value : values) {
        if (!out.empty())
            out += " ";
        out += std::to_string(value + offset);
    }
    return out;
}
static std::string yes(bool value) {
    return value ? "yes" : "no";
}
static Options read_options() {
    Options options;
    for (const std::string &line : read_lines("input/params.txt")) {
        if (line.empty() || line[0] == '#')
            continue;
        const Lines tokens = words(line);
        const std::string &name = tokens[0];
        if (name == "snap")
            options.snap = std::stoi(tokens[1]);
        else if (name == "fill_holes")
            options.fill_holes = std::stoi(tokens[1]);
        else if (name == "sections")
            options.sections = Lines(tokens.begin() + 1, tokens.end());
        else if (name == "query")
            options.queries.push_back(Lines(tokens.begin() + 1, tokens.end()));
        else {
            const bool enabled = tokens[1] == "on";
            if (name == "merge")
                options.merge = enabled;
            else if (name == "degenerate")
                options.degenerate = enabled;
            else if (name == "duplicates")
                options.duplicates = enabled;
            else if (name == "orient")
                options.orient = enabled;
            else if (name == "outward")
                options.outward = enabled;
            else if (name == "keep_unused")
                options.keep_unused = enabled;
        }
    }
    return options;
}
struct Properties {
    int boundary = 0, nonmanifold = 0, loops = 0, inconsistent = 0;
    bool closed = false, manifold = false, consistent = false, solid = false, orientable = false;
    int euler = 0, genus = 0, crosscaps = 0;
    Integer volume6 = 0;
    Point normal_sum{}, minimum{}, maximum{};
    std::vector<int> inside;
};
static std::vector<Properties> properties(const std::vector<Face> &faces, const std::vector<Point> &points,
                                          const Topology &topology) {
    std::vector<Properties> out(topology.component_faces.size());
    const auto inconsistent = inconsistent_edges(faces, topology);
    for (int e : inconsistent)
        ++out[topology.face_component[topology.edges[e].faces[0]]].inconsistent;
    for (const Loop &loop : trace_loops(topology))
        ++out[loop.component].loops;
    for (std::size_t c = 0; c < out.size(); ++c) {
        Properties &prop = out[c];
        for (int e : topology.component_edges[c]) {
            if (topology.edges[e].faces.size() == 1)
                ++prop.boundary;
            else if (topology.edges[e].faces.size() >= 3)
                ++prop.nonmanifold;
        }
        prop.closed = prop.boundary == 0;
        prop.manifold = prop.nonmanifold == 0 && topology.component_nonmanifold_vertices[c].empty();
        prop.consistent = prop.inconsistent == 0;
        prop.solid = prop.closed && prop.manifold && prop.consistent;
        prop.euler = int(topology.component_vertices[c].size()) - int(topology.component_edges[c].size()) +
                     int(topology.component_faces[c].size());
        prop.minimum = prop.maximum = points[topology.component_vertices[c][0]];
        for (int v : topology.component_vertices[c])
            for (int axis = 0; axis < 3; ++axis) {
                prop.minimum[axis] = std::min(prop.minimum[axis], points[v][axis]);
                prop.maximum[axis] = std::max(prop.maximum[axis], points[v][axis]);
            }
        for (int f : topology.component_faces[c]) {
            prop.volume6 += determinant(faces[f], points);
            const Point n = normal(faces[f], points);
            for (int axis = 0; axis < 3; ++axis)
                prop.normal_sum[axis] += n[axis];
        }
    }
    return out;
}
static std::string edge_shape(const Edge &edge, const std::vector<Face> &faces,
                              const std::vector<Point> &points) {
    if (edge.faces.size() != 2)
        return "-";
    const Face &f = faces[edge.faces[0]], &g = faces[edge.faces[1]];
    if (directed(f, edge.a, edge.b) == directed(g, edge.a, edge.b))
        return "inconsistent";
    int d = 0;
    for (int vertex : g.vertices)
        if (vertex != edge.a && vertex != edge.b)
            d = vertex;
    const Integer side = dot(difference(points[d], points[f.vertices[0]]), normal(f, points));
    return side < 0 ? "convex" : side > 0 ? "concave" : "flat";
}
static Integer length2(const Edge &edge, const std::vector<Point> &points) {
    const Point d = difference(points[edge.a], points[edge.b]);
    return dot(d, d);
}
static Lines boundaries(std::vector<Loop> &loops, const Topology &topology, const std::vector<Face> &faces,
                        const Options &options) {
    const auto inconsistent = inconsistent_edges(faces, topology);
    std::vector<bool> bad(topology.component_faces.size());
    for (const Edge &edge : topology.edges)
        if (edge.faces.size() >= 3)
            bad[topology.face_component[edge.faces[0]]] = true;
    for (int e : inconsistent)
        bad[topology.face_component[topology.edges[e].faces[0]]] = true;
    for (Loop &loop : loops) {
        if (loop.closed) {
            int forwards = 0;
            for (std::size_t i = 0; i < loop.vertices.size(); ++i) {
                const int a = loop.vertices[i], b = loop.vertices[(i + 1) % loop.vertices.size()];
                const Edge &edge = topology.edges[edge_index(topology, a, b)];
                forwards += directed(faces[edge.faces[0]], a, b);
            }
            if (forwards == 0 || forwards == int(loop.vertices.size())) {
                loop.kind = "coherent";
                if (forwards == 0)
                    std::reverse(loop.vertices.begin() + 1, loop.vertices.end());
            } else
                loop.kind = "mixed";
        }
        const std::set<int> distinct(loop.vertices.begin(), loop.vertices.end());
        loop.filled = loop.kind == "coherent" && loop.length() >= 3 && loop.length() <= options.fill_holes &&
                      distinct.size() == loop.vertices.size() && !bad[loop.component];
    }
    Lines lines = {"loops " + std::to_string(loops.size())};
    for (std::size_t i = 0; i < loops.size(); ++i) {
        const Loop &loop = loops[i];
        lines.push_back("loop " + std::to_string(i + 1) + " component " + std::to_string(loop.component + 1) +
                        " length " + std::to_string(loop.length()) + " " + loop.kind + " " +
                        (loop.filled ? "filled" : "kept") + " vertices " + list(loop.vertices));
    }
    int nonmanifold = 0;
    for (const Edge &edge : topology.edges)
        if (edge.faces.size() >= 3)
            ++nonmanifold;
    lines.push_back("nonmanifold_edges " + std::to_string(nonmanifold));
    for (const Edge &edge : topology.edges)
        if (edge.faces.size() >= 3)
            lines.push_back("edge " + std::to_string(edge.a) + " " + std::to_string(edge.b) + " faces " +
                            list(edge.faces, 1));
    int vertices = 0;
    for (int fans : topology.fans)
        if (fans >= 2)
            ++vertices;
    lines.push_back("nonmanifold_vertices " + std::to_string(vertices));
    for (std::size_t v = 1; v < topology.fans.size(); ++v)
        if (topology.fans[v] >= 2)
            lines.push_back("vertex " + std::to_string(v) + " fans " + std::to_string(topology.fans[v]) +
                            " components " + list(topology.fan_components[v], 1));
    lines.push_back("inconsistent_edges " + std::to_string(inconsistent.size()));
    for (int e : inconsistent) {
        const Edge &edge = topology.edges[e];
        lines.push_back("edge " + std::to_string(edge.a) + " " + std::to_string(edge.b) + " faces " +
                        list(edge.faces, 1));
    }
    return lines;
}
static std::vector<bool> nonplanar(const Object &object, const Cleanup &clean) {
    std::vector<bool> out;
    for (const Polygon &polygon : object.polygons) {
        Point sum{};
        const Point first = clean.snapped[polygon.vertices[0]];
        for (std::size_t i = 1; i + 1 < polygon.vertices.size(); ++i) {
            const Point term = cross(difference(clean.snapped[polygon.vertices[i]], first),
                                     difference(clean.snapped[polygon.vertices[i + 1]], first));
            for (int axis = 0; axis < 3; ++axis)
                sum[axis] += term[axis];
        }
        bool bad = false;
        for (int v : polygon.vertices)
            if (dot(difference(clean.snapped[v], first), sum) != 0)
                bad = true;
        out.push_back(bad);
    }
    return out;
}
static std::vector<int> group_numbers(const std::vector<int> &face_ids, const std::vector<Face> &faces) {
    std::set<int> groups;
    for (int f : face_ids)
        groups.insert(faces[f].group);
    return {groups.begin(), groups.end()};
}
static std::string group_names(const std::vector<int> &ids, const Lines &groups) {
    if (ids.empty())
        return "-";
    std::string out;
    for (int id : ids) {
        if (!out.empty())
            out += " ";
        out += groups[id];
    }
    return out;
}
static std::string query_answer(const Lines &query, const std::vector<Face> &faces,
                                const std::vector<Point> &points, const Topology &topology,
                                const std::vector<Properties> &props, const Lines &groups) {
    const std::string &kind = query[0];
    std::vector<Integer> args;
    for (std::size_t i = 1; i < query.size(); ++i)
        args.push_back(std::stoll(query[i]));
    if (kind == "vertex") {
        const Integer v = args[0];
        const std::string prefix = "vertex " + std::to_string(v);
        if (v < 1 || v >= Integer(points.size()))
            return prefix + " invalid";
        bool boundary = false;
        for (int e : topology.vertex_edges[v])
            if (topology.edges[e].faces.size() == 1)
                boundary = true;
        return prefix + " at " + point_text(points[v]) + " faces " +
               std::to_string(topology.vertex_faces[v].size()) + " valence " +
               std::to_string(topology.vertex_edges[v].size()) + " fans " + std::to_string(topology.fans[v]) +
               " boundary " + yes(boundary) + " components " + list(topology.fan_components[v], 1);
    }
    if (kind == "face") {
        const Integer f = args[0];
        const std::string prefix = "face " + std::to_string(f);
        if (f < 1 || f > Integer(faces.size()))
            return prefix + " invalid";
        const Face &face = faces[f - 1];
        std::string neighbors;
        for (int i = 0; i < 3; ++i) {
            const Edge &edge =
                topology.edges[edge_index(topology, face.vertices[i], face.vertices[(i + 1) % 3])];
            if (i)
                neighbors += " ";
            neighbors += edge.faces.size() == 1 ? "-"
                         : edge.faces.size() >= 3
                             ? "*"
                             : std::to_string((edge.faces[0] == f - 1 ? edge.faces[1] : edge.faces[0]) + 1);
        }
        const Point n = normal(face, points);
        return prefix + " vertices " + std::to_string(face.vertices[0]) + " " +
               std::to_string(face.vertices[1]) + " " + std::to_string(face.vertices[2]) + " group " +
               groups[face.group] + " polygon " + (face.polygon ? std::to_string(face.polygon) : "-") +
               " line " + (face.line ? std::to_string(face.line) : "-") + " component " +
               std::to_string(topology.face_component[f - 1] + 1) + " normal " + point_text(n) + " area " +
               real(std::sqrt(double(dot(n, n))) / 2) + " neighbors " + neighbors;
    }
    if (kind == "edge") {
        const int a = int(std::min(args[0], args[1])), b = int(std::max(args[0], args[1]));
        const std::string prefix = "edge " + std::to_string(a) + " " + std::to_string(b);
        const int index = edge_index(topology, a, b);
        if (index < 0)
            return prefix + " none";
        const Edge &edge = topology.edges[index];
        return prefix + " faces " + list(edge.faces, 1) + " kind " +
               (edge.faces.size() == 1   ? "boundary"
                : edge.faces.size() == 2 ? "manifold"
                                         : "nonmanifold") +
               " shape " + edge_shape(edge, faces, points) + " len2 " + std::to_string(length2(edge, points));
    }
    if (kind == "point") {
        const Point point = {args[0], args[1], args[2]};
        std::vector<int> inside;
        int sum = 0;
        for (std::size_t component = 0; component < props.size(); ++component)
            if (props[component].solid) {
                const int w = winding(point, topology.component_faces[component], faces, points);
                if (w) {
                    inside.push_back(component + 1);
                    sum += w;
                }
            }
        return "point " + point_text(point) + " inside " + list(inside) + " winding " + std::to_string(sum);
    }
    if (kind == "path") {
        const int u = int(args[0]), v = int(args[1]);
        const std::string prefix = "path " + std::to_string(u) + " " + std::to_string(v);
        if (u < 1 || u >= int(points.size()) || v < 1 || v >= int(points.size()))
            return prefix + " invalid";
        std::vector<int> parents(points.size(), -1), queue = {u};
        parents[u] = u;
        for (std::size_t position = 0; position < queue.size(); ++position)
            for (int next : topology.neighbors[queue[position]])
                if (parents[next] < 0) {
                    parents[next] = queue[position];
                    queue.push_back(next);
                }
        if (parents[v] < 0)
            return prefix + " none";
        std::vector<int> path;
        int at = v;
        while (at != u) {
            path.push_back(at);
            at = parents[at];
        }
        path.push_back(u);
        std::reverse(path.begin(), path.end());
        return prefix + " hops " + std::to_string(path.size() - 1) + " vertices " + list(path);
    }
    const Point direction = {args[0], args[1], args[2]};
    std::vector<Integer> signs;
    int front = 0, back = 0, side = 0, silhouette = 0;
    for (const Face &face : faces) {
        const Integer sign = dot(normal(face, points), direction);
        signs.push_back(sign);
        front += sign > 0;
        back += sign < 0;
        side += sign == 0;
    }
    for (const Edge &edge : topology.edges)
        if (edge.faces.size() == 2 && ((signs[edge.faces[0]] > 0 && signs[edge.faces[1]] < 0) ||
                                       (signs[edge.faces[0]] < 0 && signs[edge.faces[1]] > 0)))
            ++silhouette;
    return "view " + point_text(direction) + " front " + std::to_string(front) + " back " +
           std::to_string(back) + " side " + std::to_string(side) + " silhouette " +
           std::to_string(silhouette);
}
int main() {
    std::filesystem::create_directories("output");
    const Options options = read_options();
    const Object object = read_object();
    Cleanup clean = cleanup(object, options);
    const std::vector<Face> initial = clean.faces;
    Topology before = analyze(clean.faces, int(clean.points.size() - 1));
    const int inconsistent_before = inconsistent_edges(clean.faces, before).size();
    if (options.orient)
        orient_faces(clean.faces, before);
    std::vector<Loop> loops = trace_loops(before);
    write_lines("boundaries.txt", boundaries(loops, before, clean.faces, options));
    Lines groups = object.groups;
    int holes = 0;
    for (const Loop &loop : loops)
        if (loop.filled) {
            ++holes;
            std::vector<Face> added = fill_faces(loop, int(object.groups.size()));
            clean.faces.insert(clean.faces.end(), added.begin(), added.end());
        }
    if (holes)
        groups.push_back("fill");
    const int fill_count = int(clean.faces.size() - initial.size());
    const Topology topology = analyze(clean.faces, int(clean.points.size() - 1));
    std::vector<Properties> props = properties(clean.faces, clean.points, topology);
    for (std::size_t c = 0; c < props.size(); ++c)
        if (props[c].solid)
            for (std::size_t d = 0; d < props.size(); ++d)
                if (c != d && props[d].solid) {
                    int vertex = 0;
                    for (int v : topology.component_vertices[c])
                        if (!std::binary_search(topology.component_vertices[d].begin(),
                                                topology.component_vertices[d].end(), v)) {
                            vertex = v;
                            break;
                        }
                    if (vertex && winding(clean.points[vertex], topology.component_faces[d], clean.faces,
                                          clean.points) != 0)
                        props[c].inside.push_back(d + 1);
                }
    int outward = 0;
    for (std::size_t c = 0; c < props.size(); ++c)
        if (options.outward && props[c].solid && props[c].volume6 != 0 &&
            ((props[c].inside.size() % 2 == 0 && props[c].volume6 < 0) ||
             (props[c].inside.size() % 2 == 1 && props[c].volume6 > 0))) {
            ++outward;
            for (int f : topology.component_faces[c])
                flip(clean.faces[f]);
        }
    const auto saved = props;
    props = properties(clean.faces, clean.points, topology);
    for (std::size_t c = 0; c < props.size(); ++c)
        props[c].inside = saved[c].inside;
    auto copy = clean.faces;
    orient_faces(copy, topology);
    std::vector<bool> nonorientable(props.size());
    for (int e : inconsistent_edges(copy, topology))
        nonorientable[topology.face_component[topology.edges[e].faces[0]]] = true;
    for (std::size_t c = 0; c < props.size(); ++c) {
        props[c].orientable = !nonorientable[c];
        props[c].crosscaps = 2 - props[c].euler - props[c].loops;
        props[c].genus = props[c].crosscaps / 2;
    }
    int flipped = 0;
    for (std::size_t f = 0; f < initial.size(); ++f)
        flipped += initial[f].vertices != clean.faces[f].vertices;
    const auto nonplanar_polygons = nonplanar(object, clean);
    int nonplanar_count = std::count(nonplanar_polygons.begin(), nonplanar_polygons.end(), true);
    std::vector<int> all_faces(clean.faces.size());
    std::iota(all_faces.begin(), all_faces.end(), 0);
    Integer total_volume = 0;
    int solids = 0;
    for (const Properties &prop : props)
        if (prop.solid) {
            ++solids;
            total_volume += prop.volume6;
        }
    Lines report;
    for (const std::string &section : options.sections) {
        if (section == "summary") {
            report.push_back("[summary]");
            const std::vector<std::pair<std::string, Integer>> counts = {
                {"lines", object.lines},
                {"vertices", Integer(object.vertices.size() - 1)},
                {"polygons", Integer(object.polygons.size())},
                {"errors", Integer(object.errors.size())},
                {"ignored", object.ignored},
                {"nonplanar_polygons", nonplanar_count}};
            for (const auto &entry : counts)
                report.push_back(entry.first + " " + std::to_string(entry.second));
            std::map<int, int> sizes;
            for (const Polygon &polygon : object.polygons)
                ++sizes[polygon.vertices.size()];
            for (const auto &entry : sizes)
                report.push_back("polygon_size " + std::to_string(entry.first) + " " +
                                 std::to_string(entry.second));
            std::map<std::string, int> removed;
            for (const Removed &item : clean.removed)
                ++removed[item.reason];
            const std::vector<std::pair<std::string, Integer>> rest = {
                {"triangles", clean.triangles},
                {"snapped", clean.snapped_count},
                {"merged", clean.merged_count},
                {"removed_repeated", removed["repeated"]},
                {"removed_zero_area", removed["zero_area"]},
                {"removed_duplicate", removed["duplicate"]},
                {"faces", Integer(initial.size())},
                {"inconsistent_before", inconsistent_before},
                {"flipped_faces", flipped},
                {"outward_components", outward},
                {"boundary_loops", Integer(loops.size())},
                {"holes_filled", holes},
                {"fill_faces", fill_count},
                {"final_vertices", Integer(clean.points.size() - 1)},
                {"final_faces", Integer(clean.faces.size())},
                {"components", Integer(props.size())},
                {"solids", solids}};
            for (const auto &entry : rest)
                report.push_back(entry.first + " " + std::to_string(entry.second));
            report.push_back("total_area " + real(area(all_faces, clean.faces, clean.points)));
            report.push_back("total_volume " + fraction(total_volume, 6));
        } else if (section == "warnings") {
            report.push_back("[warnings]");
            for (const InputError &error : object.errors)
                report.push_back("line " + std::to_string(error.line) + " " + error.kind);
        } else if (section == "cleanup") {
            report.push_back("[cleanup]");
            report.push_back("snapped " + std::to_string(clean.snapped_count));
            for (std::size_t v = 1; v < object.vertices.size(); ++v)
                if (object.vertices[v] != clean.snapped[v])
                    report.push_back("snap " + std::to_string(v) + " " + point_text(object.vertices[v]) +
                                     " to " + point_text(clean.snapped[v]));
            report.push_back("merged " + std::to_string(clean.merged_count));
            for (std::size_t representative = 1; representative < clean.representative.size();
                 ++representative)
                if (clean.representative[representative] == int(representative)) {
                    std::vector<int> members;
                    for (std::size_t v = 1; v < clean.representative.size(); ++v)
                        if (clean.representative[v] == int(representative))
                            members.push_back(v);
                    if (members.size() > 1)
                        report.push_back("merge " +
                                         (clean.new_number[representative]
                                              ? std::to_string(clean.new_number[representative])
                                              : "-") +
                                         " " + list(members));
                }
            report.push_back("removed " + std::to_string(clean.removed.size()));
            for (const Removed &removed : clean.removed)
                report.push_back("remove " + std::to_string(removed.triangle) + " polygon " +
                                 std::to_string(removed.polygon) + " line " + std::to_string(removed.line) +
                                 " " + removed.reason);
        } else if (section == "components")
            for (std::size_t c = 0; c < props.size(); ++c) {
                const Properties &prop = props[c];
                report.push_back("[component " + std::to_string(c + 1) + "]");
                report.push_back(
                    "groups " + group_names(group_numbers(topology.component_faces[c], clean.faces), groups));
                for (const auto &entry : std::vector<std::pair<std::string, Integer>>{
                         {"faces", Integer(topology.component_faces[c].size())},
                         {"vertices", Integer(topology.component_vertices[c].size())},
                         {"edges", Integer(topology.component_edges[c].size())},
                         {"boundary_edges", prop.boundary},
                         {"nonmanifold_edges", prop.nonmanifold},
                         {"nonmanifold_vertices", Integer(topology.component_nonmanifold_vertices[c].size())},
                         {"boundary_loops", prop.loops}})
                    report.push_back(entry.first + " " + std::to_string(entry.second));
                for (const auto &entry :
                     std::vector<std::pair<std::string, bool>>{{"closed", prop.closed},
                                                               {"manifold", prop.manifold},
                                                               {"orientable", prop.orientable},
                                                               {"consistent", prop.consistent},
                                                               {"solid", prop.solid}})
                    report.push_back(entry.first + " " + yes(entry.second));
                report.push_back("euler " + std::to_string(prop.euler));
                report.push_back(!prop.manifold    ? "genus -"
                                 : prop.orientable ? "genus " + std::to_string(prop.genus)
                                                   : "crosscaps " + std::to_string(prop.crosscaps));
                report.push_back("volume " + (prop.solid ? fraction(prop.volume6, 6) : "-"));
                report.push_back("area " +
                                 real(area(topology.component_faces[c], clean.faces, clean.points)));
                report.push_back("normal_sum " + point_text(prop.normal_sum));
                report.push_back("bbox " + point_text(prop.minimum) + " " + point_text(prop.maximum));
                report.push_back("inside " + (prop.solid ? list(prop.inside) : "-"));
                report.push_back("centroid " + (prop.solid && prop.volume6
                                                    ? centroid(topology.component_faces[c], clean.faces,
                                                               clean.points, prop.volume6)
                                                    : "-"));
                std::map<std::string, int> shapes, angles;
                Integer shortest = -1, longest = 0;
                for (int e : topology.component_edges[c]) {
                    const Edge &edge = topology.edges[e];
                    ++shapes[edge_shape(edge, clean.faces, clean.points)];
                    const Integer length = length2(edge, clean.points);
                    if (shortest < 0 || length < shortest)
                        shortest = length;
                    longest = std::max(longest, length);
                }
                for (int f : topology.component_faces[c])
                    ++angles[triangle_angle(clean.faces[f], clean.points)];
                for (const std::string name : {"convex", "concave", "flat"})
                    report.push_back(name + " " + std::to_string(shapes[name]));
                for (const std::string name : {"acute", "right", "obtuse"})
                    report.push_back(name + " " + std::to_string(angles[name]));
                report.push_back("edge_len2 " + std::to_string(shortest) + " " + std::to_string(longest));
                std::map<int, int> degrees;
                for (int e : topology.component_edges[c]) {
                    ++degrees[topology.edges[e].a];
                    ++degrees[topology.edges[e].b];
                }
                int low = int(topology.edges.size()), high = 0;
                for (int v : topology.component_vertices[c]) {
                    low = std::min(low, degrees[v]);
                    high = std::max(high, degrees[v]);
                }
                report.push_back("valence " + std::to_string(low) + " " + std::to_string(high));
            }
        else if (section == "groups")
            for (std::size_t g = 0; g < groups.size(); ++g) {
                std::vector<int> group_faces;
                std::set<int> components;
                int polygons = 0, triangles = 0, nonplanar_group = 0;
                for (std::size_t p = 0; p < object.polygons.size(); ++p)
                    if (object.polygons[p].group == int(g)) {
                        ++polygons;
                        triangles += object.polygons[p].vertices.size() - 2;
                        nonplanar_group += nonplanar_polygons[p];
                    }
                for (std::size_t f = 0; f < clean.faces.size(); ++f)
                    if (clean.faces[f].group == int(g)) {
                        group_faces.push_back(f);
                        components.insert(topology.face_component[f] + 1);
                    }
                report.push_back("[group " + groups[g] + "]");
                report.push_back("polygons " + std::to_string(polygons));
                report.push_back("triangles " + std::to_string(triangles));
                report.push_back("nonplanar " + std::to_string(nonplanar_group));
                report.push_back("faces " + std::to_string(group_faces.size()));
                report.push_back("area " + real(area(group_faces, clean.faces, clean.points)));
                report.push_back("components " + list({components.begin(), components.end()}));
            }
        else if (section == "contacts") {
            report.push_back("[contacts]");
            for (std::size_t c = 0; c < props.size(); ++c)
                for (std::size_t d = c + 1; d < props.size(); ++d) {
                    bool intersects = true;
                    for (int axis = 0; axis < 3; ++axis)
                        if (props[c].minimum[axis] > props[d].maximum[axis] ||
                            props[d].minimum[axis] > props[c].maximum[axis])
                            intersects = false;
                    if (!intersects)
                        continue;
                    int shared = 0;
                    Integer gap = -1;
                    for (int u : topology.component_vertices[c]) {
                        if (std::binary_search(topology.component_vertices[d].begin(),
                                               topology.component_vertices[d].end(), u))
                            ++shared;
                        for (int v : topology.component_vertices[d])
                            if (u != v) {
                                const Point difference_ = difference(clean.points[u], clean.points[v]);
                                const Integer distance = dot(difference_, difference_);
                                if (gap < 0 || distance < gap)
                                    gap = distance;
                            }
                    }
                    report.push_back("contact " + std::to_string(c + 1) + " " + std::to_string(d + 1) +
                                     " shared " + std::to_string(shared) + " gap2 " + std::to_string(gap));
                }
        } else if (section == "edges") {
            report.push_back("[edges]");
            std::map<std::string, int> counts;
            int max_faces = 0, shortest = 0, longest = 0;
            for (std::size_t e = 0; e < topology.edges.size(); ++e) {
                const Edge &edge = topology.edges[e];
                ++counts[edge.faces.size() == 1   ? "boundary"
                         : edge.faces.size() == 2 ? "manifold"
                                                  : "nonmanifold"];
                ++counts[edge_shape(edge, clean.faces, clean.points)];
                max_faces = std::max(max_faces, int(edge.faces.size()));
                if (length2(edge, clean.points) < length2(topology.edges[shortest], clean.points))
                    shortest = e;
                if (length2(edge, clean.points) > length2(topology.edges[longest], clean.points))
                    longest = e;
            }
            report.push_back("edges " + std::to_string(topology.edges.size()));
            for (const std::string name : {"boundary", "manifold", "nonmanifold"})
                report.push_back(name + " " + std::to_string(counts[name]));
            report.push_back("max_faces " + std::to_string(max_faces));
            for (const std::string name : {"convex", "concave", "flat", "inconsistent"})
                report.push_back(name + " " + std::to_string(counts[name]));
            for (const auto &entry :
                 std::vector<std::pair<std::string, int>>{{"shortest", shortest}, {"longest", longest}}) {
                const Edge &edge = topology.edges[entry.second];
                report.push_back(entry.first + " " + std::to_string(edge.a) + " " + std::to_string(edge.b) +
                                 " len2 " + std::to_string(length2(edge, clean.points)));
            }
        } else if (section == "valence") {
            report.push_back("[valence]");
            std::map<int, int> degrees;
            int used = 0;
            Integer sum = 0;
            for (std::size_t v = 1; v < topology.vertex_edges.size(); ++v)
                if (!topology.vertex_edges[v].empty()) {
                    const int degree = topology.vertex_edges[v].size();
                    ++degrees[degree];
                    ++used;
                    sum += degree;
                }
            report.push_back("used " + std::to_string(used));
            report.push_back("isolated " + std::to_string(clean.points.size() - 1 - used));
            report.push_back("min " + std::to_string(degrees.begin()->first));
            report.push_back("max " + std::to_string(degrees.rbegin()->first));
            report.push_back("mean " + fraction(sum, used));
            for (const auto &entry : degrees)
                report.push_back("degree " + std::to_string(entry.first) + " " +
                                 std::to_string(entry.second));
        } else if (section == "queries") {
            report.push_back("[queries]");
            for (const Lines &query : options.queries)
                report.push_back(query_answer(query, clean.faces, clean.points, topology, props, groups));
        }
    }
    write_lines("report.txt", report);
    Lines csv = {"component,faces,vertices,closed,euler,genus,volume6,area"};
    for (std::size_t c = 0; c < props.size(); ++c) {
        const Properties &prop = props[c];
        csv.push_back(std::to_string(c + 1) + "," + std::to_string(topology.component_faces[c].size()) + "," +
                      std::to_string(topology.component_vertices[c].size()) + "," + yes(prop.closed) + "," +
                      std::to_string(prop.euler) + "," +
                      (prop.manifold && prop.orientable ? std::to_string(prop.genus) : "-") + "," +
                      (prop.solid ? std::to_string(prop.volume6) : "-") + "," +
                      real(area(topology.component_faces[c], clean.faces, clean.points)));
    }
    write_lines("components.csv", csv);
    write_object(clean.points, clean.faces, groups);
}
