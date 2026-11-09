#include "geometry.hpp"
#include <filesystem>
static std::string real(double value) {
    if (std::abs(value) < 0.0005)
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(3) << value;
    return out.str();
}
static Lines words(const std::string &line) {
    std::istringstream stream(line);
    Lines out;
    std::string word;
    while (stream >> word)
        out.push_back(word);
    return out;
}
static bool integer_word(const std::string &word) {
    const std::size_t begin = word[0] == '-' ? 1 : 0;
    if (begin == word.size())
        return false;
    for (std::size_t i = begin; i < word.size(); ++i)
        if (word[i] < '0' || word[i] > '9')
            return false;
    return true;
}
static std::string ids(const Ints &values) {
    std::string out;
    for (int value : values)
        out += (out.empty() ? "" : " ") + std::to_string(value + 1);
    return out;
}
static std::string triangle_text(Triangle t) {
    return std::to_string(t[0] + 1) + " " + std::to_string(t[1] + 1) + " " + std::to_string(t[2] + 1);
}
static std::string optional_id(int value) {
    return value < 0 ? "-" : std::to_string(value + 1);
}
static Ints hull_of(const std::vector<Point> &points, Ints sites) {
    if (sites.size() < 3) {
        std::sort(sites.begin(), sites.end());
        return sites;
    }
    std::sort(sites.begin(), sites.end(), [&](int a, int b) {
        return points[a].x != points[b].x ? points[a].x < points[b].x : points[a].y < points[b].y;
    });
    Ints lower, upper;
    for (int site : sites) {
        while (lower.size() >= 2 &&
               orient(points[lower[lower.size() - 2]], points[lower.back()], points[site]) <= 0)
            lower.pop_back();
        lower.push_back(site);
    }
    for (auto it = sites.rbegin(); it != sites.rend(); ++it) {
        while (upper.size() >= 2 &&
               orient(points[upper[upper.size() - 2]], points[upper.back()], points[*it]) <= 0)
            upper.pop_back();
        upper.push_back(*it);
    }
    lower.pop_back();
    upper.pop_back();
    lower.insert(lower.end(), upper.begin(), upper.end());
    std::rotate(lower.begin(), std::min_element(lower.begin(), lower.end()), lower.end());
    return lower;
}
struct Circle {
    Ints support;
};
static bool contains(const Circle &circle, const std::vector<Point> &points, int site) {
    if (circle.support.empty())
        return false;
    if (circle.support.size() == 1)
        return points[site].x == points[circle.support[0]].x && points[site].y == points[circle.support[0]].y;
    if (circle.support.size() == 2)
        return dot(points[site], points[circle.support[0]], points[circle.support[1]]) <= 0;
    return incircle(points[circle.support[0]], points[circle.support[1]], points[circle.support[2]],
                    points[site]) >= 0;
}
static Circle triple(const std::vector<Point> &points, int a, int b, int c) {
    if (orient(points[a], points[b], points[c]) < 0)
        std::swap(b, c);
    return {{a, b, c}};
}
static Circle enclosing(const std::vector<Point> &points, const Ints &hull) {
    Circle out;
    for (std::size_t i = 0; i < hull.size(); ++i)
        if (!contains(out, points, hull[i])) {
            out.support = {hull[i]};
            for (std::size_t j = 0; j < i; ++j)
                if (!contains(out, points, hull[j])) {
                    out.support = {hull[i], hull[j]};
                    for (std::size_t k = 0; k < j; ++k)
                        if (!contains(out, points, hull[k]))
                            out = triple(points, hull[i], hull[j], hull[k]);
                }
        }
    return out;
}
static bool on_circle(const Circle &circle, const std::vector<Point> &points, int site) {
    if (circle.support.size() == 2)
        return dot(points[site], points[circle.support[0]], points[circle.support[1]]) == 0;
    if (circle.support.size() == 3)
        return incircle(points[circle.support[0]], points[circle.support[1]], points[circle.support[2]],
                        points[site]) == 0;
    return contains(circle, points, site);
}
static double route_length(const std::vector<Point> &points, const Ints &route) {
    double out = 0;
    for (std::size_t i = 1; i < route.size(); ++i)
        out += std::sqrt(double(d2(points[route[i - 1]], points[route[i]])));
    return out;
}
static void store(std::map<std::string, Lines> &sections, const std::string &name,
                  const std::ostringstream &stream) {
    std::istringstream input(stream.str());
    std::string line;
    while (std::getline(input, line))
        sections[name].push_back(line);
}
int main() {
    std::filesystem::create_directories("output");
    std::vector<Point> points;
    Lines rejected;
    std::ifstream point_file("input/points.txt");
    std::string line;
    int line_count = 0;
    while (std::getline(point_file, line)) {
        ++line_count;
        if (line.empty() || line[0] == '#')
            continue;
        const Lines fields = words(line);
        const std::string prefix = "reject " + std::to_string(line_count) + " ";
        if (fields.size() != 2 || !integer_word(fields[0]) || !integer_word(fields[1])) {
            rejected.push_back(prefix + "format");
            continue;
        }
        const Integer x = std::stoll(fields[0]), y = std::stoll(fields[1]);
        if (x < 0 || x > 1000 || y < 0 || y > 1000) {
            rejected.push_back(prefix + "range");
            continue;
        }
        int duplicate = -1;
        for (std::size_t i = 0; i < points.size(); ++i)
            if (points[i].x == x && points[i].y == y)
                duplicate = i;
        if (duplicate >= 0) {
            rejected.push_back(prefix + "duplicate " + std::to_string(duplicate + 1));
            continue;
        }
        points.push_back({x, y});
    }
    int width = 61, height = 31;
    Lines layers = {"edges", "hull", "sites"}, requested = {"summary"};
    std::vector<Integer> alphas;
    Lines queries;
    std::ifstream params("input/params.txt");
    while (std::getline(params, line)) {
        if (line.empty() || line[0] == '#')
            continue;
        const Lines fields = words(line);
        if (fields[0] == "plot") {
            width = std::stoi(fields[1]);
            height = std::stoi(fields[2]);
        } else if (fields[0] == "plot_layers")
            layers.assign(fields.begin() + 1, fields.end());
        else if (fields[0] == "sections")
            requested.assign(fields.begin() + 1, fields.end());
        else if (fields[0] == "alpha")
            for (std::size_t i = 1; i < fields.size(); ++i)
                alphas.push_back(std::stoll(fields[i]));
        else
            queries.push_back(line.substr(6));
    }
    const int n = points.size();
    Triangulation triangulation = initialize(points);
    const Triangle initial = triangulation.triangles()[0];
    std::vector<Insertion> insertions;
    for (int site = 3; site < n; ++site)
        insertions.push_back(triangulation.insert(points, site));
    const auto triangles = triangulation.triangles();
    const int count = triangles.size();
    std::map<Pair, int> triangle_id;
    for (int t = 0; t < count; ++t)
        for (int k = 0; k < 3; ++k)
            triangle_id[{triangles[t][k], triangles[t][(k + 1) % 3]}] = t;
    auto tid = [&](int a, int b) {
        const auto found = triangle_id.find({a, b});
        return found == triangle_id.end() ? -1 : found->second;
    };
    std::vector<Edge> edges;
    std::map<Pair, int> edge_id;
    for (const auto &entry : triangulation.directed) {
        const auto key = std::minmax(entry.first.first, entry.first.second);
        edge_id[key] = 0;
    }
    std::vector<Ints> neighbors(n);
    for (auto &entry : edge_id) {
        const int a = entry.first.first, b = entry.first.second;
        entry.second = edges.size();
        edges.push_back({a, b, tid(a, b), tid(b, a), d2(points[a], points[b])});
        neighbors[a].push_back(b);
        neighbors[b].push_back(a);
    }
    for (Ints &values : neighbors)
        std::sort(values.begin(), values.end());
    Ints next(n, -1), previous(n, -1);
    for (Pair edge : triangulation.hull_edges()) {
        next[edge.first] = edge.second;
        previous[edge.second] = edge.first;
    }
    int start = 0;
    while (next[start] < 0)
        ++start;
    Ints hull;
    int current = start;
    do {
        hull.push_back(current);
        current = next[current];
    } while (current != start);
    std::vector<Ints> ordered_neighbors(n);
    for (int s = 0; s < n; ++s)
        ordered_neighbors[s] = neighbor_order(triangulation, s, neighbors[s], next[s]);
    std::vector<Center> vertices;
    std::vector<double> radii, minimum_angles, maximum_angles;
    Lines positions, kinds;
    std::vector<Integer> areas;
    int acute = 0, right = 0, obtuse = 0;
    std::array<int, 6> angle_bins{};
    for (const Triangle &t : triangles) {
        const Point a = points[t[0]], b = points[t[1]], c = points[t[2]];
        areas.push_back(orient(a, b, c));
        const std::array<Integer, 3> products = {dot(a, b, c), dot(b, c, a), dot(c, a, b)};
        const std::string kind = std::find(products.begin(), products.end(), 0) != products.end() ? "right"
                                 : *std::min_element(products.begin(), products.end()) < 0        ? "obtuse"
                                                                                                  : "acute";
        kinds.push_back(kind);
        acute += kind == "acute";
        right += kind == "right";
        obtuse += kind == "obtuse";
        std::array<double, 3> angles;
        for (int k = 0; k < 3; ++k)
            angles[k] = std::atan2(double(areas.back()), double(products[k])) * 180 / std::acos(-1.0);
        minimum_angles.push_back(*std::min_element(angles.begin(), angles.end()));
        maximum_angles.push_back(*std::max_element(angles.begin(), angles.end()));
        ++angle_bins[int(std::floor(minimum_angles.back() / 10))];
        vertices.push_back(center(a, b, c));
        radii.push_back(radius2(a, b, c));
        positions.push_back(position(vertices.back(), points, hull));
    }
    std::vector<Ints> cell_vertices(n);
    std::vector<double> cell_areas(n), clips(n);
    double total_area = 0, clip_total = 0;
    int largest = -1;
    for (int s = 0; s < n; ++s) {
        for (int neighbor : ordered_neighbors[s])
            if (tid(s, neighbor) >= 0)
                cell_vertices[s].push_back(tid(s, neighbor));
        if (next[s] < 0) {
            cell_areas[s] = cell_area(points[s], vertices, cell_vertices[s]);
            total_area += cell_areas[s];
            if (largest < 0 || cell_areas[s] > cell_areas[largest])
                largest = s;
        }
        clips[s] = clipped_area(points, s, ordered_neighbors[s]);
        clip_total += clips[s];
    }
    const Ints nn = nearest(points, neighbors);
    Disjoint nn_sets(n);
    int mutual = 0;
    for (int s = 0; s < n; ++s) {
        nn_sets.join(s, nn[s]);
        mutual += s < nn[s] && nn[nn[s]] == s;
    }
    std::map<int, int> component_ids;
    std::vector<Ints> components;
    Ints component(n);
    for (int s = 0; s < n; ++s) {
        const int root = nn_sets.find(s);
        if (!component_ids.count(root)) {
            component_ids[root] = components.size();
            components.push_back({});
        }
        component[s] = component_ids[root];
        components[component[s]].push_back(s);
    }
    const Ints mst = kruskal(edges, n);
    double mst_length = 0;
    for (int index : mst)
        mst_length += std::sqrt(double(edges[index].length2));
    int gg = 0, rng = 0;
    Ints gg_degree(n), rng_degree(n), mst_degree(n);
    for (Edge &edge : edges) {
        edge.gabriel = gabriel(points, triangulation, edge.a, edge.b);
        edge.rng = relative_neighborhood(points, edge.a, edge.b);
        gg += edge.gabriel;
        rng += edge.rng;
        for (int s : Ints{edge.a, edge.b}) {
            gg_degree[s] += edge.gabriel;
            rng_degree[s] += edge.rng;
            mst_degree[s] += edge.mst;
        }
    }
    int empty = -1, candidates = 0;
    for (int t = 0; t < count; ++t)
        if (positions[t] == "inside") {
            ++candidates;
            if (empty < 0 || radii[t] > radii[empty])
                empty = t;
        }
    Pair diameter{0, 1};
    Integer diameter2 = d2(points[0], points[1]);
    for (int a = 0; a < n - 1; ++a)
        for (int b = a + 1; b < n; ++b)
            if (d2(points[a], points[b]) > diameter2) {
                diameter = {a, b};
                diameter2 = d2(points[a], points[b]);
            }
    double width_value = std::numeric_limits<double>::infinity();
    int width_edge = 0;
    for (std::size_t k = 0; k < hull.size(); ++k) {
        Integer maximum = 0;
        for (int s : hull)
            maximum =
                std::max(maximum, orient(points[hull[k]], points[hull[(k + 1) % hull.size()]], points[s]));
        const double value =
            double(maximum) / std::sqrt(double(d2(points[hull[k]], points[hull[(k + 1) % hull.size()]])));
        if (value < width_value) {
            width_value = value;
            width_edge = k;
        }
    }
    const Circle enclosing_circle = enclosing(points, hull);
    Ints enclosing_sites;
    for (int s = 0; s < n; ++s)
        if (on_circle(enclosing_circle, points, s))
            enclosing_sites.push_back(s);
    Pair diameter_support{-1, -1};
    for (std::size_t a = 0; a + 1 < enclosing_sites.size(); ++a)
        for (std::size_t b = a + 1; b < enclosing_sites.size(); ++b) {
            bool all = true;
            for (int s : enclosing_sites)
                all = all && dot(points[s], points[enclosing_sites[a]], points[enclosing_sites[b]]) == 0;
            if (all && diameter_support.first < 0)
                diameter_support = {enclosing_sites[a], enclosing_sites[b]};
        }
    Center enclosing_center;
    double enclosing_radius2;
    if (diameter_support.first >= 0) {
        const Point a = points[diameter_support.first], b = points[diameter_support.second];
        enclosing_center = {a.x + b.x, a.y + b.y, 2};
        enclosing_radius2 = double(d2(a, b)) / 4;
    } else {
        Triangle t{enclosing_sites[0], enclosing_sites[1], enclosing_sites[2]};
        if (orient(points[t[0]], points[t[1]], points[t[2]]) < 0)
            std::swap(t[1], t[2]);
        enclosing_center = center(points[t[0]], points[t[1]], points[t[2]]);
        enclosing_radius2 = radius2(points[t[0]], points[t[1]], points[t[2]]);
    }
    std::vector<Ints> convex_layers;
    Ints remaining(n), depth(n);
    std::iota(remaining.begin(), remaining.end(), 0);
    while (!remaining.empty()) {
        const Ints layer = hull_of(points, remaining);
        convex_layers.push_back(layer);
        for (int s : layer)
            depth[s] = convex_layers.size();
        Ints rest;
        for (int s : remaining)
            if (!depth[s])
                rest.push_back(s);
        remaining = std::move(rest);
    }
    std::vector<Paths> paths;
    for (int s = 0; s < n; ++s)
        paths.push_back(dijkstra(points, neighbors, s));
    double stretch_sum = 0, max_stretch = -1;
    Pair stretch_pair;
    for (int a = 0; a < n - 1; ++a)
        for (int b = a + 1; b < n; ++b) {
            const double value = paths[a].distance[b] / std::sqrt(double(d2(points[a], points[b])));
            stretch_sum += value;
            if (value > max_stretch) {
                max_stretch = value;
                stretch_pair = {a, b};
            }
        }
    auto dual = [&](const Edge &edge) {
        if (edge.left >= 0 && edge.right >= 0)
            return std::string("segment ") + std::to_string(edge.left + 1) + " " +
                   std::to_string(edge.right + 1);
        const bool left = edge.left >= 0;
        const Point normal = outward(points[left ? edge.a : edge.b], points[left ? edge.b : edge.a]);
        return std::string("ray ") + std::to_string((left ? edge.left : edge.right) + 1) + " " +
               std::to_string(normal.x) + " " + std::to_string(normal.y);
    };
    std::map<std::string, Lines> sections;
    std::ostringstream out;
    out << "lines " << line_count << "\naccepted " << n << "\nrejected " << rejected.size() << '\n';
    for (const std::string &value : rejected)
        out << value << '\n';
    store(sections, "input", out);
    out.str("");
    out.clear();
    int flips = 0, outside = 0, maximum_insertion = -1;
    for (std::size_t i = 0; i < insertions.size(); ++i) {
        flips += insertions[i].flips;
        outside += !insertions[i].inside;
        if (maximum_insertion < 0 || insertions[i].flips > insertions[maximum_insertion].flips)
            maximum_insertion = i;
    }
    out << "sites " << n << "\ntriangles " << count << "\nedges " << edges.size() << "\nhull_vertices "
        << hull.size() << "\ninterior_sites " << n - hull.size() << "\neuler "
        << n - int(edges.size()) + count << "\nflips " << flips << "\noutside_insertions " << outside
        << "\nmax_flips ";
    if (maximum_insertion < 0)
        out << "none\n";
    else
        out << insertions[maximum_insertion].site + 1 << ' ' << insertions[maximum_insertion].flips << '\n';
    out << "acute " << acute << "\nright " << right << "\nobtuse " << obtuse << '\n';
    store(sections, "summary", out);
    out.str("");
    out.clear();
    out << "init " << triangle_text(initial) << '\n';
    for (const Insertion &insertion : insertions) {
        out << "insert " << insertion.site + 1;
        if (insertion.inside)
            out << " inside " << triangle_text(insertion.containing);
        else
            out << " outside " << insertion.visible;
        out << " flips " << insertion.flips << " triangles " << insertion.triangles << " hull "
            << insertion.hull << '\n';
    }
    store(sections, "insertions", out);
    out.str("");
    out.clear();
    for (int t = 0; t < count; ++t) {
        const Triangle triangle = triangles[t];
        out << "tri " << t + 1 << ' ' << triangle_text(triangle) << " area2 " << areas[t] << ' ' << kinds[t]
            << " adj " << optional_id(tid(triangle[2], triangle[1])) << ' '
            << optional_id(tid(triangle[0], triangle[2])) << ' ' << optional_id(tid(triangle[1], triangle[0]))
            << '\n';
    }
    store(sections, "triangles", out);
    out.str("");
    out.clear();
    for (const Edge &edge : edges)
        out << "edge " << edge.a + 1 << ' ' << edge.b + 1 << ' '
            << (edge.left >= 0 && edge.right >= 0 ? "inner" : "hull") << " len2 " << edge.length2 << " left "
            << optional_id(edge.left) << " right " << optional_id(edge.right) << '\n';
    store(sections, "edges", out);
    out.str("");
    out.clear();
    double perimeter = 0;
    Integer hull_area = 0;
    for (std::size_t k = 0; k < hull.size(); ++k) {
        const Point a = points[hull[k]], b = points[hull[(k + 1) % hull.size()]];
        perimeter += std::sqrt(double(d2(a, b)));
        hull_area += a.x * b.y - b.x * a.y;
    }
    out << "hull_vertices " << hull.size() << "\norder " << ids(hull) << "\nperimeter " << real(perimeter)
        << "\narea2 " << hull_area << '\n';
    store(sections, "hull", out);
    out.str("");
    out.clear();
    out << "layers " << convex_layers.size() << '\n';
    for (std::size_t k = 0; k < convex_layers.size(); ++k)
        out << "layer " << k + 1 << " size " << convex_layers[k].size() << " sites " << ids(convex_layers[k])
            << '\n';
    store(sections, "convex_layers", out);
    out.str("");
    out.clear();
    const int min_triangle =
                  std::min_element(minimum_angles.begin(), minimum_angles.end()) - minimum_angles.begin(),
              max_triangle =
                  std::max_element(maximum_angles.begin(), maximum_angles.end()) - maximum_angles.begin();
    double minimum_sum = 0;
    for (double value : minimum_angles)
        minimum_sum += value;
    out << "min_angle " << real(minimum_angles[min_triangle]) << " tri " << min_triangle + 1 << "\nmax_angle "
        << real(maximum_angles[max_triangle]) << " tri " << max_triangle + 1 << "\nmean_min_angle "
        << real(minimum_sum / count) << '\n';
    for (int bin = 0; bin < 6; ++bin)
        out << "bin " << bin * 10 << ' ' << (bin + 1) * 10 << ' ' << angle_bins[bin] << '\n';
    store(sections, "quality", out);
    out.str("");
    out.clear();
    for (const std::string &kind : Lines{"inside", "on", "outside"})
        out << kind << ' ' << std::count(positions.begin(), positions.end(), kind) << '\n';
    for (int t = 0; t < count; ++t)
        out << "v " << t + 1 << ' ' << fraction(vertices[t].x, vertices[t].d) << ' '
            << fraction(vertices[t].y, vertices[t].d) << " r " << real(std::sqrt(radii[t])) << ' '
            << positions[t] << '\n';
    store(sections, "vertices", out);
    out.str("");
    out.clear();
    out << "segments " << edges.size() - hull.size() << "\nrays " << hull.size() << '\n';
    for (const Edge &edge : edges)
        out << "ve " << edge.a + 1 << ' ' << edge.b + 1 << ' ' << dual(edge) << '\n';
    store(sections, "voronoi_edges", out);
    out.str("");
    out.clear();
    out << "bounded " << n - hull.size() << "\nunbounded " << hull.size() << "\ntotal_area "
        << real(total_area) << "\nclip_total " << real(clip_total) << "\nlargest ";
    if (largest < 0)
        out << "none\n";
    else
        out << largest + 1 << " area " << real(cell_areas[largest]) << '\n';
    for (int s = 0; s < n; ++s) {
        out << "cell " << s + 1;
        if (next[s] < 0)
            out << " bounded " << cell_vertices[s].size() << " area " << real(cell_areas[s]) << " clip "
                << real(clips[s]) << " vertices " << ids(cell_vertices[s]);
        else {
            const Point incoming = outward(points[s], points[next[s]]),
                        outgoing = outward(points[previous[s]], points[s]);
            out << " unbounded " << cell_vertices[s].size() << " clip " << real(clips[s]) << " from "
                << incoming.x << ' ' << incoming.y << " vertices " << ids(cell_vertices[s]) << " to "
                << outgoing.x << ' ' << outgoing.y;
        }
        out << '\n';
    }
    store(sections, "cells", out);
    out.str("");
    out.clear();
    const auto closest = std::min_element(edges.begin(), edges.end(),
                                          [](const Edge &a, const Edge &b) { return a.length2 < b.length2; });
    out << "mutual_pairs " << mutual << "\nclosest_pair " << closest->a + 1 << ' ' << closest->b + 1 << " d2 "
        << closest->length2 << '\n';
    for (int s = 0; s < n; ++s)
        out << "nn " << s + 1 << ' ' << nn[s] + 1 << " d2 " << d2(points[s], points[nn[s]]) << ' '
            << (nn[nn[s]] == s ? "mutual" : "-") << '\n';
    store(sections, "nearest", out);
    out.str("");
    out.clear();
    out << "components " << components.size() << '\n';
    for (std::size_t k = 0; k < components.size(); ++k) {
        Pair pair;
        for (int s : components[k])
            if (s < nn[s] && nn[nn[s]] == s)
                pair = {s, nn[s]};
        out << "component " << k + 1 << " size " << components[k].size() << " pair " << pair.first + 1 << ' '
            << pair.second + 1 << " sites " << ids(components[k]) << '\n';
    }
    store(sections, "components", out);
    out.str("");
    out.clear();
    const Edge &longest = edges[mst.back()];
    out << "edges " << mst.size() << "\ntotal_length " << real(mst_length) << "\nlongest " << longest.a + 1
        << ' ' << longest.b + 1 << " len2 " << longest.length2 << '\n';
    for (int index : mst) {
        const Edge &edge = edges[index];
        out << "mst " << edge.a + 1 << ' ' << edge.b + 1 << " len2 " << edge.length2 << '\n';
    }
    store(sections, "mst", out);
    out.str("");
    out.clear();
    out << "delaunay " << edges.size() << "\ngabriel " << gg << "\nrng " << rng << "\nmst " << mst.size()
        << "\nnn " << n - mutual << '\n';
    for (const Edge &edge : edges)
        if (edge.rng && !edge.mst)
            out << "rng_extra " << edge.a + 1 << ' ' << edge.b + 1 << " len2 " << edge.length2 << '\n';
    store(sections, "proximity", out);
    out.str("");
    out.clear();
    std::map<int, int> degree_counts;
    for (const Ints &values : neighbors)
        ++degree_counts[values.size()];
    out << "min " << degree_counts.begin()->first << "\nmax " << degree_counts.rbegin()->first << '\n';
    for (const auto &entry : degree_counts)
        out << "degree " << entry.first << " count " << entry.second << '\n';
    store(sections, "degrees", out);
    out.str("");
    out.clear();
    out << "candidates " << candidates << '\n';
    if (empty < 0)
        out << "none\n";
    else
        out << "vertex " << empty + 1 << "\ncenter " << fraction(vertices[empty].x, vertices[empty].d) << ' '
            << fraction(vertices[empty].y, vertices[empty].d) << "\nradius " << real(std::sqrt(radii[empty]))
            << "\nsites " << triangle_text(triangles[empty]) << '\n';
    store(sections, "empty_circle", out);
    out.str("");
    out.clear();
    out << "diameter " << diameter.first + 1 << ' ' << diameter.second + 1 << " d2 " << diameter2
        << "\nwidth " << real(width_value) << " edge " << hull[width_edge] + 1 << ' '
        << hull[(width_edge + 1) % hull.size()] + 1 << "\nenclosing_center "
        << fraction(enclosing_center.x, enclosing_center.d) << ' '
        << fraction(enclosing_center.y, enclosing_center.d) << "\nenclosing_radius "
        << real(std::sqrt(enclosing_radius2)) << "\nenclosing_sites " << ids(enclosing_sites) << '\n';
    store(sections, "extent", out);
    out.str("");
    out.clear();
    out << "pairs " << n * (n - 1) / 2 << "\nmax_stretch " << real(max_stretch) << " pair "
        << stretch_pair.first + 1 << ' ' << stretch_pair.second + 1 << " length "
        << real(paths[stretch_pair.first].distance[stretch_pair.second]) << " distance "
        << real(std::sqrt(double(d2(points[stretch_pair.first], points[stretch_pair.second]))))
        << "\nmean_stretch " << real(stretch_sum / (n * (n - 1) / 2)) << '\n';
    store(sections, "spanner", out);
    out.str("");
    out.clear();
    for (Integer alpha : alphas) {
        std::vector<bool> selected(count), active(n);
        int faces = 0, selected_edges = 0, boundary = 0, dangling = 0, components_count = n;
        Integer area = 0;
        for (int t = 0; t < count; ++t)
            if (radii[t] <= alpha) {
                selected[t] = true;
                ++faces;
                area += areas[t];
            }
        Disjoint sets(n);
        for (const Edge &edge : edges) {
            const int adjacent =
                (edge.left >= 0 && selected[edge.left]) + (edge.right >= 0 && selected[edge.right]);
            if (!adjacent && !(edge.gabriel && edge.length2 <= 4 * alpha))
                continue;
            ++selected_edges;
            boundary += adjacent == 1;
            dangling += adjacent == 0;
            active[edge.a] = active[edge.b] = true;
            components_count -= sets.join(edge.a, edge.b);
        }
        const int isolated = std::count(active.begin(), active.end(), false);
        out << "alpha " << alpha << " triangles " << faces << " edges " << selected_edges << " boundary "
            << boundary << " dangling " << dangling << " isolated " << isolated << " components "
            << components_count << " holes " << components_count - (n - selected_edges + faces) << " area2 "
            << area << '\n';
    }
    store(sections, "alpha", out);
    out.str("");
    out.clear();
    for (int s = 0; s < n; ++s)
        out << "site " << s + 1 << ' ' << points[s].x << ' ' << points[s].y << ' '
            << (next[s] >= 0 ? "hull" : "inner") << " dt " << neighbors[s].size() << " gg " << gg_degree[s]
            << " rng " << rng_degree[s] << " mst " << mst_degree[s] << " nn " << nn[s] + 1 << " comp "
            << component[s] + 1 << " depth " << depth[s] << '\n';
    store(sections, "sites", out);
    out.str("");
    out.clear();
    for (const std::string &query : queries) {
        const Lines fields = words(query);
        const std::string &kind = fields[0];
        out << query << ' ';
        if (kind == "locate" || kind == "walk" || kind == "natural") {
            const Point q{std::stoll(fields[1]), std::stoll(fields[2])};
            if (kind == "locate") {
                std::string place = "outside";
                bool found = false;
                for (int s = 0; s < n; ++s)
                    if (d2(points[s], q) == 0) {
                        place = "vertex " + std::to_string(s + 1);
                        found = true;
                        break;
                    }
                if (!found)
                    for (const Edge &edge : edges)
                        if (orient(points[edge.a], points[edge.b], q) == 0 &&
                            dot(q, points[edge.a], points[edge.b]) < 0) {
                            place = "edge " + std::to_string(edge.a + 1) + " " + std::to_string(edge.b + 1);
                            found = true;
                            break;
                        }
                if (!found)
                    for (const Triangle &t : triangles)
                        if (orient(points[t[0]], points[t[1]], q) > 0 &&
                            orient(points[t[1]], points[t[2]], q) > 0 &&
                            orient(points[t[2]], points[t[0]], q) > 0) {
                            place = "triangle " + triangle_text(t);
                            break;
                        }
                int nearest = 0;
                for (int s = 1; s < n; ++s)
                    if (d2(points[s], q) < d2(points[nearest], q))
                        nearest = s;
                out << place << " nearest " << nearest + 1 << " d2 " << d2(points[nearest], q);
            } else if (kind == "walk") {
                const Walk walk = triangulation.walk(points, q);
                out << "steps " << walk.path.size() - 1;
                if (walk.outside)
                    out << " outside " << walk.edge.first + 1 << ' ' << walk.edge.second + 1;
                else
                    out << " triangle " << walk.path.back() + 1;
                out << " path " << ids(walk.path);
            } else {
                int triangles_count = 0;
                std::set<int> sites;
                for (const Triangle &t : triangles)
                    if (incircle(points[t[0]], points[t[1]], points[t[2]], q) > 0) {
                        ++triangles_count;
                        sites.insert(t.begin(), t.end());
                    }
                const Ints sequence(sites.begin(), sites.end());
                out << "triangles " << triangles_count << " sites "
                    << (sequence.empty() ? "-" : ids(sequence));
            }
        } else {
            const int a = std::stoi(fields[1]) - 1, b = kind == "neighbors" ? a : std::stoi(fields[2]) - 1;
            if (a < 0 || a >= n || b < 0 || b >= n)
                out << "error unknown_site";
            else if (kind == "neighbors")
                out << "degree " << neighbors[a].size() << " sites " << ids(ordered_neighbors[a]);
            else if (kind == "route") {
                const Ints route = greedy_route(points, neighbors, a, b);
                out << "hops " << route.size() - 1 << " length " << real(route_length(points, route))
                    << " path " << ids(route);
            } else if (kind == "path") {
                Ints route;
                int cursor = b;
                while (cursor >= 0) {
                    route.push_back(cursor);
                    if (cursor == a)
                        break;
                    cursor = paths[a].previous[cursor];
                }
                std::reverse(route.begin(), route.end());
                out << "length " << real(paths[a].distance[b]) << " stretch "
                    << (a == b ? "-"
                               : real(paths[a].distance[b] / std::sqrt(double(d2(points[a], points[b])))))
                    << " hops " << route.size() - 1 << " sites " << ids(route);
            } else if (a == b)
                out << "error same_site";
            else {
                const auto found = edge_id.find(std::minmax(a, b));
                if (found != edge_id.end()) {
                    const Edge &edge = edges[found->second];
                    out << "delaunay len2 " << edge.length2 << " gabriel " << (edge.gabriel ? "yes" : "no")
                        << " rng " << (edge.rng ? "yes" : "no") << " mst " << (edge.mst ? "yes" : "no")
                        << " dual " << dual(edge);
                } else {
                    std::vector<Pair> crossings;
                    for (const Edge &edge : edges)
                        if (orient(points[a], points[b], points[edge.a]) *
                                    orient(points[a], points[b], points[edge.b]) <
                                0 &&
                            orient(points[edge.a], points[edge.b], points[a]) *
                                    orient(points[edge.a], points[edge.b], points[b]) <
                                0)
                            crossings.push_back({edge.a, edge.b});
                    out << "missing crossings " << crossings.size();
                    for (Pair edge : crossings)
                        out << ' ' << edge.first + 1 << '-' << edge.second + 1;
                }
            }
        }
        out << '\n';
    }
    store(sections, "queries", out);
    Grid delaunay = canvas(width, height);
    for (const std::string &layer : layers) {
        if (layer == "edges")
            for (const Edge &edge : edges)
                draw_line(delaunay, map_point(points[edge.a], width, height),
                          map_point(points[edge.b], width, height), '.');
        else if (layer == "mst")
            for (int index : mst)
                draw_line(delaunay, map_point(points[edges[index].a], width, height),
                          map_point(points[edges[index].b], width, height), '*');
        else if (layer == "hull")
            for (std::size_t k = 0; k < hull.size(); ++k)
                draw_line(delaunay, map_point(points[hull[k]], width, height),
                          map_point(points[hull[(k + 1) % hull.size()]], width, height), '#');
        else if (layer == "sites")
            for (Point point : points) {
                const Pair cell = map_point(point, width, height);
                delaunay[cell.second][cell.first] = 'o';
            }
        else if (layer == "circle" && empty >= 0) {
            const Pair cell = map_center(vertices[empty], width, height);
            delaunay[cell.second][cell.first] = '@';
        }
    }
    sections["delaunay_plot"] = framed(delaunay);
    sections["voronoi_plot"] = framed(voronoi_plot(points, width, height));
    const std::set<std::string> tri_sections = {"input", "summary", "insertions",    "triangles",
                                                "edges", "hull",    "convex_layers", "quality"},
                                vor_sections = {"vertices", "voronoi_edges", "cells"},
                                plot_sections = {"delaunay_plot", "voronoi_plot"};
    std::array<std::ofstream, 4> files{std::ofstream("output/triangulation.txt", std::ios::binary),
                                       std::ofstream("output/voronoi.txt", std::ios::binary),
                                       std::ofstream("output/derived.txt", std::ios::binary),
                                       std::ofstream("output/plot.txt", std::ios::binary)};
    for (const std::string &section : requested) {
        const int file = tri_sections.count(section)    ? 0
                         : vor_sections.count(section)  ? 1
                         : plot_sections.count(section) ? 3
                                                        : 2;
        files[file] << '[' << section << "]\n";
        for (const std::string &value : sections[section])
            files[file] << value << '\n';
    }
}
