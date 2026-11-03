#include "clustering.hpp"
template <class... T> static std::string text(const T &...values) {
    std::ostringstream out;
    bool first = true;
    auto put = [&](const auto &value) {
        if (!first)
            out << ' ';
        first = false;
        out << value;
    };
    (put(values), ...);
    return out.str();
}
static std::string number(Integer value) {
    return value == INF ? "-" : std::to_string(value);
}
static char character(int label) {
    return label < 0 ? '.' : label < 26 ? char('A' + label) : label < 52 ? char('a' + label - 26) : '#';
}
static int clusters(const std::vector<int> &labels) {
    return *std::max_element(labels.begin(), labels.end()) + 1;
}
static std::vector<std::vector<int>> groups(const std::vector<int> &labels) {
    std::vector<std::vector<int>> result(clusters(labels));
    for (std::size_t p = 0; p < labels.size(); ++p)
        if (labels[p] >= 0)
            result[labels[p]].push_back(int(p));
    return result;
}
static std::vector<int> extraction(const Optics &optics, int radius) {
    std::vector<int> labels(optics.order.size(), -1);
    int cluster = -1;
    const Integer threshold = Integer(radius) * radius;
    for (int p : optics.order) {
        if (optics.reach[p] > threshold) {
            if (optics.core[p] <= threshold)
                labels[p] = ++cluster;
            else
                labels[p] = -1;
        } else
            labels[p] = cluster;
    }
    return labels;
}
struct Knee {
    int rank, point, radius;
    Integer distance, cross;
    std::vector<int> order;
};
static Knee knee(const std::vector<std::vector<Integer>> &neighbor_distances, int k) {
    const int n = int(neighbor_distances.size());
    std::vector<int> order(n);
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) {
        return neighbor_distances[a][k - 1] > neighbor_distances[b][k - 1];
    });
    const Integer first = neighbor_distances[order[0]][k - 1], last = neighbor_distances[order.back()][k - 1];
    int best = 0;
    Integer greatest = -1;
    for (int r = 0; r < n; ++r) {
        const Integer distance_ = neighbor_distances[order[r]][k - 1],
                      cross = std::abs(Integer(n - 1) * (distance_ - first) - (last - first) * r);
        if (cross > greatest) {
            greatest = cross;
            best = r;
        }
    }
    const Integer value = neighbor_distances[order[best]][k - 1];
    int radius = 1;
    while (Integer(radius) * radius < value)
        ++radius;
    return {best + 1, order[best], radius, value, greatest, order};
}
struct SteepArea {
    bool down;
    int first, last;
};
struct XiCluster {
    int first, last, label = -1, parent = -1;
    int size() const {
        return last - first + 1;
    }
};
struct XiResult {
    std::vector<int> labels;
    std::vector<SteepArea> areas;
    std::vector<XiCluster> clusters;
    std::vector<Integer> reach;
};
static XiResult xi_extract(const Optics &optics, const Params &p) {
    const int n = int(optics.order.size());
    const Integer alpha = Integer(p.xi_v - p.xi_u) * (p.xi_v - p.xi_u), beta = Integer(p.xi_v) * p.xi_v;
    XiResult result;
    result.reach.assign(n + 2, INF);
    for (int i = 1; i <= n; ++i)
        result.reach[i] = optics.reach[optics.order[i - 1]];
    const auto &reach = result.reach;
    auto xle = [&](Integer a, Integer b) {
        if (b == INF)
            return true;
        if (a == INF)
            return false;
        return beta * a <= alpha * b;
    };
    std::vector<bool> steep_up(n + 1), steep_down(n + 1), up(n + 1), down(n + 1);
    for (int i = 1; i <= n; ++i) {
        if (reach[i] == INF && reach[i + 1] == INF)
            continue;
        steep_up[i] = xle(reach[i], reach[i + 1]);
        steep_down[i] = xle(reach[i + 1], reach[i]);
        up[i] = steep_up[i] || reach[i] < reach[i + 1];
        down[i] = steep_down[i] || reach[i] > reach[i + 1];
    }
    auto extend = [&](int first, bool descending) {
        int end = first, count = 0;
        for (int i = first; i <= n; ++i) {
            if (descending ? steep_down[i] : steep_up[i]) {
                end = i;
                count = 0;
            } else if (descending ? up[i] : down[i])
                break;
            else if (++count > p.min_points)
                break;
        }
        return end;
    };
    struct DownArea {
        int first, last;
        Integer maximum;
    };
    std::vector<DownArea> areas;
    int index = 1;
    Integer mib = 0;
    for (int s = 1; s <= n; ++s) {
        if (s < index || (!steep_up[s] && !steep_down[s]))
            continue;
        for (int i = index; i <= s; ++i)
            mib = std::max(mib, reach[i]);
        if (mib == INF)
            areas.clear();
        else {
            areas.erase(std::remove_if(areas.begin(), areas.end(),
                                       [&](const DownArea &area) { return !xle(mib, reach[area.first]); }),
                        areas.end());
            for (DownArea &area : areas)
                area.maximum = std::max(area.maximum, mib);
        }
        if (steep_down[s]) {
            const int end = extend(s, true);
            areas.push_back({s, end, 0});
            result.areas.push_back({true, s, end});
            index = end + 1;
            mib = reach[index];
        } else {
            const int end = extend(s, false);
            result.areas.push_back({false, s, end});
            index = end + 1;
            mib = reach[index];
            std::vector<XiCluster> candidates;
            for (const DownArea &area : areas) {
                int cs = area.first, ce = end;
                if (!xle(area.maximum, reach[ce + 1]))
                    continue;
                const Integer left = reach[area.first];
                if (xle(reach[ce + 1], left)) {
                    while (cs < area.last && reach[cs + 1] > reach[ce + 1])
                        ++cs;
                } else if (xle(left, reach[ce + 1])) {
                    while (ce > s && reach[ce - 1] > left)
                        --ce;
                }
                if (ce - cs + 1 >= p.xi_size && cs <= area.last && ce >= s)
                    candidates.push_back({cs, ce});
            }
            result.clusters.insert(result.clusters.end(), candidates.rbegin(), candidates.rend());
        }
    }
    std::vector<int> positions(n + 1, -2);
    int next = 0;
    for (XiCluster &cluster : result.clusters) {
        bool unassigned = true;
        for (int i = cluster.first; i <= cluster.last; ++i)
            if (positions[i] != -2)
                unassigned = false;
        if (unassigned) {
            cluster.label = next;
            for (int i = cluster.first; i <= cluster.last; ++i)
                positions[i] = next;
            ++next;
        }
    }
    result.labels.assign(n, -1);
    for (int i = 1; i <= n; ++i)
        if (positions[i] >= 0)
            result.labels[optics.order[i - 1]] = positions[i];
    for (std::size_t j = 0; j < result.clusters.size(); ++j) {
        XiCluster &cluster = result.clusters[j];
        for (std::size_t i = 0; i < result.clusters.size(); ++i) {
            if (i == j)
                continue;
            const XiCluster &candidate = result.clusters[i];
            if (candidate.first > cluster.first || candidate.last < cluster.last ||
                !(candidate.size() > cluster.size() || (candidate.size() == cluster.size() && i > j)))
                continue;
            if (cluster.parent < 0 ||
                std::make_pair(candidate.size(), int(i)) <
                    std::make_pair(result.clusters[cluster.parent].size(), cluster.parent))
                cluster.parent = int(i);
        }
    }
    return result;
}
struct Setting {
    std::string name;
    int radius;
    std::vector<int> labels;
    std::vector<bool> core;
    bool db = false, extraction = false;
};
static Integer turn(const Point &o, const Point &a, const Point &b) {
    return Integer(a.x - o.x) * (b.y - o.y) - Integer(a.y - o.y) * (b.x - o.x);
}
static std::vector<int> hull(const std::vector<Point> &points, std::vector<int> ids) {
    std::sort(ids.begin(), ids.end(), [&](int a, int b) {
        return std::tie(points[a].x, points[a].y) < std::tie(points[b].x, points[b].y);
    });
    if (ids.size() <= 2)
        return ids;
    std::vector<int> lower, upper;
    for (int p : ids) {
        while (lower.size() >= 2 &&
               turn(points[lower[lower.size() - 2]], points[lower.back()], points[p]) <= 0)
            lower.pop_back();
        lower.push_back(p);
    }
    for (auto it = ids.rbegin(); it != ids.rend(); ++it) {
        const int p = *it;
        while (upper.size() >= 2 &&
               turn(points[upper[upper.size() - 2]], points[upper.back()], points[p]) <= 0)
            upper.pop_back();
        upper.push_back(p);
    }
    lower.pop_back();
    upper.pop_back();
    lower.insert(lower.end(), upper.begin(), upper.end());
    return lower;
}
static std::pair<Integer, Integer> ari(const std::vector<int> &a, const std::vector<int> &b) {
    std::map<std::pair<int, int>, Integer> cells;
    std::map<int, Integer> rows, columns;
    for (std::size_t i = 0; i < a.size(); ++i) {
        ++cells[{a[i], b[i]}];
        ++rows[a[i]];
        ++columns[b[i]];
    }
    auto c2 = [](Integer value) { return value * (value - 1) / 2; };
    Integer s = 0, x = 0, y = 0;
    for (const auto &item : cells)
        s += c2(item.second);
    for (const auto &item : rows)
        x += c2(item.second);
    for (const auto &item : columns)
        y += c2(item.second);
    const Integer z = c2(Integer(a.size())), numerator = 2 * (z * s - x * y),
                  denominator = z * (x + y) - 2 * x * y;
    return denominator ? std::make_pair(numerator, denominator) : std::make_pair(Integer(1), Integer(1));
}
static void setting_report(std::ostream &out, const Setting &setting, const std::vector<Point> &points,
                           const Distances &distances, const std::map<int, Grid> &grids) {
    const auto members = groups(setting.labels);
    int core_count = 0, border_count = 0;
    for (std::size_t i = 0; i < points.size(); ++i)
        if (setting.labels[i] >= 0) {
            if (setting.core[i])
                ++core_count;
            else
                ++border_count;
        }
    out << text("setting", setting.name, "eps", setting.radius, "clusters", members.size(), "noise",
                std::count(setting.labels.begin(), setting.labels.end(), -1), "core", core_count, "border",
                border_count)
        << '\n';
    for (std::size_t label = 0; label < members.size(); ++label) {
        const auto &ids = members[label];
        Integer sx = 0, sy = 0;
        int core = 0, xmin = 10001, ymin = 10001, xmax = 0, ymax = 0;
        for (int id : ids) {
            sx += points[id].x;
            sy += points[id].y;
            if (setting.core[id])
                ++core;
            xmin = std::min(xmin, points[id].x);
            ymin = std::min(ymin, points[id].y);
            xmax = std::max(xmax, points[id].x);
            ymax = std::max(ymax, points[id].y);
        }
        int medoid = ids[0];
        Integer best = INF;
        for (int id : ids) {
            const Integer x = Integer(ids.size()) * points[id].x - sx,
                          y = Integer(ids.size()) * points[id].y - sy, value = x * x + y * y;
            if (value < best) {
                best = value;
                medoid = id;
            }
        }
        const auto vertices = hull(points, ids);
        Integer area2 = 0, diameter = 0;
        for (std::size_t i = 0; i < vertices.size(); ++i) {
            const Point &a = points[vertices[i]], b = points[vertices[(i + 1) % vertices.size()]];
            area2 += Integer(a.x) * b.y - Integer(b.x) * a.y;
            for (int q : vertices)
                diameter = std::max(diameter, distances[vertices[i]][q]);
        }
        area2 = std::abs(area2);
        const Integer area = Integer(xmax - xmin + 1) * (ymax - ymin + 1);
        out << text("cluster", label, character(int(label)), "size", ids.size(), "core", core, "border",
                    ids.size() - core, "centroid", fraction(sx, ids.size()), fraction(sy, ids.size()),
                    "medoid", points[medoid].id)
            << '\n';
        out << text("  bbox", xmin, ymin, xmax, ymax, "area", area, "density", fraction(ids.size(), area))
            << '\n';
        out << text("  hull", vertices.size(), "hull_area",
                    std::to_string(area2 / 2) + (area2 % 2 ? ".5" : ".0"), "diameter_sq", diameter,
                    "diameter", root(diameter))
            << '\n';
    }
    if (!setting.db)
        return;
    const Grid &grid = grids.at(setting.radius);
    bool a = true, b = true, c = true;
    int isolated = 0;
    std::vector<std::pair<int, std::set<int>>> ambiguous;
    for (std::size_t p = 0; p < points.size(); ++p) {
        if (setting.core[p]) {
            for (int q : grid.neighbors[p])
                if (setting.core[q] && setting.labels[p] != setting.labels[q])
                    a = false;
        } else if (setting.labels[p] >= 0) {
            bool found = false;
            std::set<int> others;
            for (int q : grid.neighbors[p])
                if (setting.core[q]) {
                    if (setting.labels[q] == setting.labels[p])
                        found = true;
                    else
                        others.insert(setting.labels[q]);
                }
            if (!found)
                b = false;
            if (!others.empty())
                ambiguous.push_back({int(p), others});
        } else {
            if (grid.neighbors[p].size() == 1)
                ++isolated;
            for (int q : grid.neighbors[p])
                if (setting.core[q])
                    c = false;
        }
    }
    out << text("check", a ? "ok" : "fail", b ? "ok" : "fail", c ? "ok" : "fail") << '\n'
        << text("isolated", isolated) << '\n'
        << text("ambiguous", ambiguous.size()) << '\n';
    for (const auto &item : ambiguous) {
        out << "  " << points[item.first].id << " cluster " << setting.labels[item.first] << " also";
        for (int label : item.second)
            out << ' ' << label;
        out << '\n';
    }
}
static std::vector<std::string> cluster_map(const Setting &setting, const std::vector<Point> &points,
                                            const Params &p, bool kinds) {
    int x0 = 10001, y0 = 10001, x1 = 0, y1 = 0;
    for (const Point &point : points) {
        x0 = std::min(x0, point.x);
        y0 = std::min(y0, point.y);
        x1 = std::max(x1, point.x);
        y1 = std::max(y1, point.y);
    }
    std::vector<std::vector<int>> cells(p.width * p.height);
    for (std::size_t i = 0; i < points.size(); ++i) {
        const int column = (points[i].x - x0) * p.width / (x1 - x0 + 1),
                  row = (y1 - points[i].y) * p.height / (y1 - y0 + 1);
        cells[row * p.width + column].push_back(int(i));
    }
    std::vector<std::string> rows(p.height, std::string(p.width, ' '));
    for (int r = 0; r < p.height; ++r)
        for (int c = 0; c < p.width; ++c) {
            const auto &ids = cells[r * p.width + c];
            if (ids.empty())
                continue;
            if (kinds) {
                char mark = '.';
                for (int id : ids)
                    if (setting.core[id]) {
                        mark = '#';
                        break;
                    } else if (setting.labels[id] >= 0)
                        mark = '+';
                rows[r][c] = mark;
            } else {
                std::set<int> labels;
                for (int id : ids)
                    if (setting.labels[id] >= 0)
                        labels.insert(setting.labels[id]);
                rows[r][c] = labels.empty() ? '.' : labels.size() > 1 ? '*' : character(*labels.begin());
            }
        }
    return rows;
}
int main() {
    const Input input = read_input();
    const auto &points = input.points;
    const Params &p = input.params;
    const int n = int(points.size()), k = p.min_points - 1;
    Distances distances(n, std::vector<Integer>(n));
    std::vector<std::vector<Integer>> neighbor_distances(n);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            distances[i][j] = distance(points[i], points[j]);
            if (i != j)
                neighbor_distances[i].push_back(distances[i][j]);
        }
        std::sort(neighbor_distances[i].begin(), neighbor_distances[i].end());
    }
    const Knee main_knee = knee(neighbor_distances, k);
    std::set<int> radii(p.eps.begin(), p.eps.end());
    radii.insert(main_knee.radius);
    radii.insert(p.max_eps);
    std::map<int, Grid> grids;
    for (int radius : radii)
        grids.emplace(radius, build_grid(points, distances, radius));
    const Optics ordering = optics(grids.at(p.max_eps), distances, p.min_points);
    const XiResult xi = xi_extract(ordering, p);
    std::vector<Setting> settings;
    for (int index = 0; index <= int(p.eps.size()); ++index) {
        const int radius = index == int(p.eps.size()) ? main_knee.radius : p.eps[index];
        const Grid &grid = grids.at(radius);
        std::vector<bool> core;
        for (const auto &neighbors : grid.neighbors)
            core.push_back(neighbors.size() >= std::size_t(p.min_points));
        settings.push_back({(index == int(p.eps.size()) ? "knee" : "db") + std::to_string(radius), radius,
                            dbscan(grid, p.min_points), core, true, false});
    }
    const int db_count = int(settings.size()), knee_index = db_count - 1;
    for (int radius : p.extract) {
        std::vector<bool> core;
        for (Integer value : ordering.core)
            core.push_back(value <= Integer(radius) * radius);
        settings.push_back(
            {"op" + std::to_string(radius), radius, extraction(ordering, radius), core, false, true});
    }
    std::vector<bool> xi_core;
    for (Integer value : ordering.core)
        xi_core.push_back(value != INF);
    settings.push_back({"xi", p.max_eps, xi.labels, xi_core});
    const Setting &knee_setting = settings[knee_index];
    const Setting &xi_setting = settings.back();
    std::ofstream labels("output/labels.csv");
    labels << "id";
    for (const Setting &setting : settings)
        labels << ',' << setting.name;
    labels << '\n';
    for (int id = 0; id < n; ++id) {
        labels << points[id].id;
        for (const Setting &setting : settings)
            labels << ',' << setting.labels[id];
        labels << '\n';
    }
    std::ofstream order_file("output/optics_order.csv");
    order_file << "order,id,core_sq,reach_sq,reach,predecessor\n";
    for (int i = 0; i < n; ++i) {
        const int id = ordering.order[i];
        order_file << i + 1 << ',' << points[id].id << ',' << number(ordering.core[id]) << ','
                   << number(ordering.reach[id]) << ',' << root(ordering.reach[id]) << ','
                   << (ordering.predecessor[id] < 0 ? "-"
                                                    : std::to_string(points[ordering.predecessor[id]].id))
                   << '\n';
    }
    std::ofstream kdist("output/kdist.txt");
    kdist << text("k_distance k", k, "points", n) << "\nrank id kdist_sq kdist\n";
    for (int i = 0; i < n; ++i) {
        const int id = main_knee.order[i];
        const Integer value = neighbor_distances[id][k - 1];
        kdist << text(i + 1, points[id].id, value, root(value)) << '\n';
    }
    kdist << '\n'
          << text("knee rank", main_knee.rank, "id", points[main_knee.point].id, "kdist_sq",
                  main_knee.distance, "kdist", root(main_knee.distance), "cross", main_knee.cross)
          << '\n'
          << text("suggested_eps", main_knee.radius) << "\n\nknee_table\n";
    for (int neighbor = 1; neighbor <= 2 * p.min_points; ++neighbor) {
        const Knee curve = knee(neighbor_distances, neighbor);
        kdist << text("k", neighbor, "rank", curve.rank, "id", points[curve.point].id, "kdist_sq",
                      curve.distance, "eps", curve.radius)
              << '\n';
    }
    kdist << "\ncore_check\n";
    for (int index = 0; index < db_count; ++index) {
        const Setting &setting = settings[index];
        int core = 0;
        for (int id = 0; id < n; ++id)
            if (neighbor_distances[id][k - 1] <= Integer(setting.radius) * setting.radius)
                ++core;
        const int grid_core = int(std::count(setting.core.begin(), setting.core.end(), true));
        kdist << text("eps", setting.radius, "core", core, "non_core", n - core, "grid_core", grid_core,
                      core == grid_core ? "ok" : "mismatch")
              << '\n';
    }
    bool core_ok = true;
    int optics_core = 0;
    for (int id = 0; id < n; ++id)
        if (ordering.core[id] != INF) {
            ++optics_core;
            if (ordering.core[id] != neighbor_distances[id][k - 1])
                core_ok = false;
        }
    kdist << text("optics max_eps", p.max_eps, "core", optics_core, core_ok ? "ok" : "mismatch") << '\n';
    std::ofstream clusters_file("output/clusters.txt");
    clusters_file << text("points", n, "min_pts", p.min_points) << "\nsettings";
    for (const Setting &setting : settings)
        clusters_file << ' ' << setting.name;
    clusters_file << "\n\ngrid\n";
    for (const auto &item : grids) {
        const Grid &grid = item.second;
        clusters_file << text("eps", item.first, "cells", grid.cells.size(), "busiest", grid.busiest_x,
                              grid.busiest_y, grid.busiest_count, "candidates", grid.total_candidates,
                              "pairs", grid.pairs, "brute_pairs", grid.brute_pairs,
                              grid.correct ? "ok" : "mismatch")
                      << "\n  occupancy";
        for (const auto &occupancy : grid.occupancy)
            clusters_file << ' ' << occupancy.first << ':' << occupancy.second;
        clusters_file << '\n';
    }
    for (const Setting &setting : settings) {
        clusters_file << '\n';
        setting_report(clusters_file, setting, points, distances, grids);
    }
    clusters_file << "\nhierarchy\n";
    std::vector<int> hierarchy(db_count);
    std::iota(hierarchy.begin(), hierarchy.end(), 0);
    std::stable_sort(hierarchy.begin(), hierarchy.end(),
                     [&](int a, int b) { return settings[a].radius < settings[b].radius; });
    for (int i = 1; i < db_count; ++i) {
        const Setting &a = settings[hierarchy[i - 1]], b = settings[hierarchy[i]];
        clusters_file << a.name << " -> " << b.name << '\n';
        std::vector<std::vector<int>> destinations(clusters(b.labels));
        const auto source = groups(a.labels);
        for (std::size_t label = 0; label < source.size(); ++label)
            for (int id : source[label])
                if (a.core[id]) {
                    destinations[b.labels[id]].push_back(int(label));
                    break;
                }
        for (std::size_t label = 0; label < destinations.size(); ++label) {
            clusters_file << "  " << label << " <-";
            if (destinations[label].empty())
                clusters_file << " -";
            else
                for (int source_label : destinations[label])
                    clusters_file << ' ' << source_label;
            clusters_file << '\n';
        }
    }
    clusters_file << "\noptics_vs_dbscan\n";
    for (const Setting &a : settings)
        if (a.extraction) {
            const Setting *b = nullptr;
            for (int index = 0; index < db_count; ++index)
                if (settings[index].radius == a.radius) {
                    b = &settings[index];
                    break;
                }
            if (!b)
                continue;
            std::map<int, std::set<int>> forward, reverse;
            int border_noise = 0;
            for (int id = 0; id < n; ++id) {
                if (a.core[id]) {
                    forward[a.labels[id]].insert(b->labels[id]);
                    reverse[b->labels[id]].insert(a.labels[id]);
                }
                if (a.labels[id] < 0 && b->labels[id] >= 0)
                    ++border_noise;
            }
            bool same = forward.size() == std::size_t(clusters(a.labels)) &&
                        reverse.size() == std::size_t(clusters(b->labels));
            for (const auto &item : forward)
                if (item.second.size() != 1)
                    same = false;
            for (const auto &item : reverse)
                if (item.second.size() != 1)
                    same = false;
            int moved = 0;
            if (same)
                for (int id = 0; id < n; ++id)
                    if (a.labels[id] >= 0 && *forward.at(a.labels[id]).begin() != b->labels[id])
                        ++moved;
            clusters_file << text(a.name, b->name, "core_partition", same ? "same" : "different",
                                  "border_as_noise", border_noise, "moved",
                                  same ? std::to_string(moved) : "-")
                          << '\n';
        }
    int components = 0, singletons = 0, largest = 0, current = 0;
    for (int id : ordering.order) {
        if (ordering.reach[id] == INF) {
            if (current) {
                if (current == 1)
                    ++singletons;
                largest = std::max(largest, current);
            }
            ++components;
            current = 0;
        }
        ++current;
    }
    if (current) {
        if (current == 1)
            ++singletons;
        largest = std::max(largest, current);
    }
    clusters_file << '\n'
                  << text("optics max_eps", p.max_eps, "core", optics_core, "components", components,
                          "singletons", singletons, "largest", largest)
                  << "\n\n"
                  << text("sweep max_eps", p.max_eps) << "\neps clusters noise largest\n";
    std::vector<int> sweep_clusters(p.max_eps + 1);
    for (int radius = 1; radius <= p.max_eps; ++radius) {
        const auto result = extraction(ordering, radius);
        const auto members = groups(result);
        int largest_ = 0;
        for (const auto &group : members)
            largest_ = std::max(largest_, int(group.size()));
        sweep_clusters[radius] = int(members.size());
        clusters_file << text(radius, members.size(), std::count(result.begin(), result.end(), -1), largest_)
                      << '\n';
    }
    int stable_first = 0, stable_last = 0;
    for (int first = 1; first <= p.max_eps;) {
        int last = first;
        while (last < p.max_eps && sweep_clusters[last + 1] == sweep_clusters[first])
            ++last;
        if (sweep_clusters[first] >= 2 && (stable_first == 0 || last - first > stable_last - stable_first)) {
            stable_first = first;
            stable_last = last;
        }
        first = last + 1;
    }
    if (!stable_first)
        clusters_file << "stable -\n";
    else
        clusters_file << text("stable clusters", sweep_clusters[stable_first], "eps", stable_first,
                              stable_last, "length", stable_last - stable_first + 1)
                      << '\n';
    clusters_file << '\n'
                  << text("xi", std::to_string(p.xi_u) + "/" + std::to_string(p.xi_v), "min_size", p.xi_size,
                          "steep_areas", xi.areas.size())
                  << '\n';
    for (const SteepArea &area : xi.areas)
        clusters_file << text(area.down ? "down" : "up", area.first, area.last) << '\n';
    clusters_file << text("xi_clusters", xi.clusters.size()) << '\n';
    for (std::size_t i = 0; i < xi.clusters.size(); ++i) {
        const XiCluster &cluster = xi.clusters[i];
        Integer valley = INF;
        for (int t = cluster.first + 1; t <= cluster.last; ++t)
            valley = std::min(valley, xi.reach[t]);
        clusters_file << text(i, "start", cluster.first, "end", cluster.last, "size", cluster.size(), "label",
                              cluster.label < 0 ? "-" : std::to_string(cluster.label), "parent",
                              cluster.parent < 0 ? "-" : std::to_string(cluster.parent), "walls",
                              root(xi.reach[cluster.first]), root(xi.reach[cluster.last + 1]), "valley",
                              root(valley))
                      << '\n';
    }
    struct Outlier {
        int point, nearest;
        Integer distance;
    };
    std::vector<Outlier> outliers;
    for (int id = 0; id < n; ++id)
        if (knee_setting.labels[id] < 0) {
            int nearest = -1;
            Integer best = INF;
            for (int q = 0; q < n; ++q)
                if (knee_setting.core[q] && distances[id][q] < best) {
                    best = distances[id][q];
                    nearest = q;
                }
            outliers.push_back({id, nearest, best});
        }
    std::sort(outliers.begin(), outliers.end(), [](const Outlier &a, const Outlier &b) {
        return a.distance != b.distance ? a.distance > b.distance : a.point < b.point;
    });
    clusters_file << '\n' << text("outliers", knee_setting.name, "count", outliers.size()) << '\n';
    for (const Outlier &item : outliers)
        clusters_file << text(points[item.point].id, "nearest_core", points[item.nearest].id, "cluster",
                              knee_setting.labels[item.nearest], "dist_sq", item.distance, "dist",
                              root(item.distance))
                      << '\n';
    const auto knee_members = groups(knee_setting.labels), xi_members = groups(xi_setting.labels);
    clusters_file << '\n' << text("gaps", knee_setting.name) << '\n';
    for (std::size_t a = 0; a < knee_members.size(); ++a)
        for (std::size_t b = a + 1; b < knee_members.size(); ++b) {
            Integer best = INF;
            int first = -1, second = -1;
            for (int x : knee_members[a])
                for (int y : knee_members[b])
                    if (distances[x][y] < best) {
                        best = distances[x][y];
                        first = x;
                        second = y;
                    }
            clusters_file << text(a, b, "dist_sq", best, "dist", root(best), "between", points[first].id,
                                  points[second].id)
                          << '\n';
        }
    std::vector<std::vector<int>> table(knee_members.size() + 1, std::vector<int>(xi_members.size() + 1));
    for (int id = 0; id < n; ++id)
        ++table[knee_setting.labels[id] + 1][xi_setting.labels[id] + 1];
    clusters_file << '\n' << text("contingency", knee_setting.name, "xi") << "\ncolumns";
    for (int c = -1; c < int(xi_members.size()); ++c)
        clusters_file << ' ' << c;
    clusters_file << '\n';
    for (int r = -1; r < int(knee_members.size()); ++r) {
        clusters_file << r;
        for (int value : table[r + 1])
            clusters_file << ' ' << value;
        clusters_file << '\n';
    }
    for (std::size_t c = 0; c < xi_members.size(); ++c) {
        int match = 0;
        for (int r = 1; r < int(knee_members.size()); ++r)
            if (table[r + 1][c + 1] > table[match + 1][c + 1])
                match = r;
        const int shared = table[match + 1][c + 1];
        clusters_file << text("match", c, match, "shared", shared, "jaccard",
                              fraction(shared,
                                       Integer(knee_members[match].size() + xi_members[c].size()) - shared))
                      << '\n';
    }
    clusters_file << "\nari\n";
    for (std::size_t a = 0; a < settings.size(); ++a)
        for (std::size_t b = a + 1; b < settings.size(); ++b) {
            const auto value = ari(settings[a].labels, settings[b].labels);
            clusters_file << text(settings[a].name, settings[b].name, fraction(value.first, value.second),
                                  ari_value(value.first, value.second))
                          << '\n';
        }
    std::ofstream maps("output/maps.txt");
    for (const Setting &setting : settings) {
        const auto members = groups(setting.labels);
        maps << text("map", setting.name, "clusters", members.size(), "noise",
                     std::count(setting.labels.begin(), setting.labels.end(), -1))
             << '\n';
        write_lines(maps, framed(cluster_map(setting, points, p, false)));
        maps << "legend";
        if (members.empty())
            maps << " -";
        else
            for (std::size_t label = 0; label < members.size(); ++label)
                maps << ' ' << character(int(label)) << '=' << members[label].size();
        maps << "\n\n";
    }
    maps << text("kinds", knee_setting.name) << '\n';
    write_lines(maps, framed(cluster_map(knee_setting, points, p, true)));
    maps << '\n';
    const Integer maximum = neighbor_distances[main_knee.order[0]][k - 1];
    int knee_column = 0;
    std::vector<int> heights(p.kwidth);
    for (int c = 0; c < p.kwidth; ++c) {
        const int first = c * n / p.kwidth, end = (c + 1) * n / p.kwidth;
        const Integer value = neighbor_distances[main_knee.order[first]][k - 1];
        while (Integer(heights[c] + 1) * (heights[c] + 1) * maximum <= Integer(p.kheight) * p.kheight * value)
            ++heights[c];
        if (first < main_knee.rank && main_knee.rank <= end)
            knee_column = c;
    }
    std::vector<std::string> curve(p.kheight, std::string(p.kwidth, ' '));
    for (int r = 0; r < p.kheight; ++r)
        for (int c = 0; c < p.kwidth; ++c)
            curve[r][c] = p.kheight - r <= heights[c] ? '#' : c == knee_column ? ':' : ' ';
    maps << text("kdist_plot k", k, "max", root(maximum), "knee_column", knee_column + 1) << '\n';
    write_lines(maps, framed(curve));
    Integer reach_top = 0;
    for (Integer value : ordering.reach)
        if (value != INF)
            reach_top = std::max(reach_top, value);
    maps << '\n' << text("reachability width", p.rwidth, "max_reach", root(reach_top), "columns");
    for (std::size_t index = db_count; index < settings.size(); ++index)
        maps << ' ' << settings[index].name;
    maps << '\n';
    for (int i = 0; i < n; ++i) {
        const int id = ordering.order[i];
        std::string marks;
        for (std::size_t index = db_count; index < settings.size(); ++index)
            marks += character(settings[index].labels[id]);
        std::string bar;
        if (ordering.reach[id] == INF)
            bar = std::string(p.rwidth, '-');
        else {
            int length = 0;
            while (Integer(length + 1) * (length + 1) * reach_top <=
                   Integer(p.rwidth) * p.rwidth * ordering.reach[id])
                ++length;
            bar = std::string(length, '#');
        }
        maps << std::setw(4) << i + 1 << ' ' << std::setw(5) << points[id].id << ' ' << std::setw(7)
             << root(ordering.reach[id]) << ' ' << marks << " |" << bar << '\n';
    }
}
