#include "detector.hpp"
#include <filesystem>
struct Circle {
    CirclePeak peak;
    I gap = 0, arcs = 0;
};
struct Segment {
    Point start, end;
    I length, pixels, theta;
    int line;
};
struct Line {
    LinePeak peak;
    std::vector<int> segments;
};
struct Junction {
    Point point;
    int a_end, b_end;
};
struct Polygon {
    std::vector<int> segments;
    Points vertices;
    std::vector<I> angles, lengths, support;
    std::vector<int> corners;
    I sigma = 0;
    std::string kind;
};
struct Shape {
    bool polygon;
    int index;
    Points representatives;
    I pixels = 0, mean = 0, contrast = 0;
    int parent = -1;
};
static Point difference(Point a, Point b) {
    return {a.x - b.x, a.y - b.y};
}
static I cross(Point a, Point b) {
    return a.x * b.y - a.y * b.x;
}
static I dot(Point a, Point b) {
    return a.x * b.x + a.y * b.y;
}
static I chebyshev(Point a, Point b) {
    return std::max(std::abs(a.x - b.x), std::abs(a.y - b.y));
}
static I angle(I a, I b) {
    const I d = std::abs(a - b);
    return std::min(d, 180 - d);
}
static I rounded(I n, I d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    return floor_div(2 * n + d, 2 * d);
}
static Points bresenham(Point start, Point end) {
    Points out;
    I x = start.x, y = start.y, dx = std::abs(end.x - x), dy = -std::abs(end.y - y), sx = x < end.x ? 1 : -1,
      sy = y < end.y ? 1 : -1, error = dx + dy;
    while (true) {
        out.push_back({x, y});
        if (x == end.x && y == end.y)
            break;
        const I twice = 2 * error;
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
static bool circumference(Point point, const Circle &circle) {
    const Point delta = difference(point, circle.peak.center);
    const I d2 = dot(delta, delta), r = circle.peak.radius;
    return (r - 1) * (r - 1) <= d2 && d2 <= (r + 1) * (r + 1);
}
static bool near_edge(const Image &edges, Point point) {
    for (I dy = -1; dy <= 1; ++dy)
        for (I dx = -1; dx <= 1; ++dx) {
            Point next{point.x + dx, point.y + dy};
            if (edges.inside(next) && edges.at(next))
                return true;
        }
    return false;
}
static std::string shape_name(int index, const std::vector<Shape> &shapes) {
    if (index < 0)
        return "none";
    const Shape &shape = shapes[index];
    return std::string(shape.polygon ? "polygon " : "circle ") + std::to_string(shape.index + 1);
}
static bool inside(Point point, const Shape &shape, const std::vector<Polygon> &polygons,
                   const std::vector<Circle> &circles) {
    if (!shape.polygon) {
        const CirclePeak &circle = circles[shape.index].peak;
        const Point delta = difference(point, circle.center);
        return dot(delta, delta) <= circle.radius * circle.radius;
    }
    const Polygon &polygon = polygons[shape.index];
    for (int i = 0; i < int(polygon.vertices.size()); ++i) {
        const Point a = polygon.vertices[i], b = polygon.vertices[(i + 1) % polygon.vertices.size()];
        const I value = cross(difference(b, a), difference(point, a));
        if (value != 0 && ((value > 0) != (polygon.sigma > 0)))
            return false;
    }
    return true;
}
static int junction_end(const Junction &junction, int id, int other) {
    return id < other ? junction.a_end : junction.b_end;
}
static const Junction *lookup(const std::map<std::pair<int, int>, Junction> &junctions, int a, int b) {
    const auto found = junctions.find(std::minmax(a, b));
    return found == junctions.end() ? nullptr : &found->second;
}
int main() {
    std::filesystem::create_directories("output");
    const Input input = load();
    const Image &image = input.image;
    const Params &p = input.params;
    const Gradient g = gradient(smooth(image, p));
    const Canny edges = canny(g, p);
    auto circle_data = circle_votes(edges.edges, p);
    std::vector<Circle> circles;
    for (int index = 0; index < std::min<int>(p.circle_count, circle_data.peaks.size()); ++index) {
        Circle circle{circle_data.peaks[index]};
        Points offsets = circle_data.offsets[circle.peak.radius - p.r_min];
        std::sort(offsets.begin(), offsets.end(), [](Point a, Point b) {
            auto half = [](Point point) { return point.y > 0 || (point.y == 0 && point.x > 0) ? 0 : 1; };
            if (half(a) != half(b))
                return half(a) < half(b);
            return cross(a, b) > 0;
        });
        std::vector<bool> hit;
        for (Point offset : offsets) {
            const Point point{circle.peak.center.x + offset.x, circle.peak.center.y + offset.y};
            hit.push_back(image.inside(point) && edges.edges.at(point));
        }
        const int n = hit.size();
        bool all = true;
        for (bool value : hit)
            all = all && value;
        if (all)
            circle.arcs = 1;
        else
            for (int i = 0; i < n; ++i)
                if (hit[i] && !hit[(i + n - 1) % n])
                    ++circle.arcs;
        I run = 0;
        for (int i = 0; i < 2 * n; ++i) {
            if (hit[i % n])
                run = 0;
            else
                ++run;
            circle.gap = std::max(circle.gap, std::min<I>(n, run));
        }
        circles.push_back(circle);
    }
    Image line_edges = edges.edges;
    I circle_edge_pixels = 0;
    for (int y = 0; y < image.height; ++y)
        for (int x = 0; x < image.width; ++x)
            if (edges.edges.at({x, y})) {
                for (const Circle &circle : circles)
                    if (circumference({x, y}, circle)) {
                        line_edges.at({x, y}) = 0;
                        ++circle_edge_pixels;
                        break;
                    }
            }
    const LineVotes line_data = line_votes(line_edges, input.trig, p);
    std::vector<Line> lines;
    std::vector<Segment> segments;
    Image claimed(image.width, image.height);
    for (const LinePeak &peak : line_data.peaks) {
        if (lines.size() >= std::size_t(p.line_count))
            break;
        Points selected;
        for (int y = 0; y < image.height; ++y)
            for (int x = 0; x < image.width; ++x) {
                const Point point{x, y};
                if (line_edges.at(point) && !claimed.at(point) &&
                    std::abs(rho(point, peak.theta, input.trig, p) - peak.rho) <= p.tolerance)
                    selected.push_back(point);
            }
        auto position = [&](Point point) {
            return point.y * input.trig[peak.theta][0] - point.x * input.trig[peak.theta][1];
        };
        std::sort(selected.begin(), selected.end(), [&](Point a, Point b) {
            const I u = position(a), v = position(b);
            return std::tie(u, a.x, a.y) < std::tie(v, b.x, b.y);
        });
        Line line{peak, {}};
        for (int begin = 0; begin < int(selected.size());) {
            int end = begin + 1;
            while (end < int(selected.size()) &&
                   position(selected[end]) - position(selected[end - 1]) <= p.max_gap * 16384)
                ++end;
            const Point start = selected[begin], last = selected[end - 1];
            const I length = chebyshev(start, last) + 1;
            if (length >= p.min_length) {
                line.segments.push_back(segments.size());
                segments.push_back({start, last, length, end - begin, peak.theta, int(lines.size())});
                for (int i = begin; i < end; ++i)
                    claimed.at(selected[i]) = 1;
            }
            begin = end;
        }
        if (!line.segments.empty())
            lines.push_back(std::move(line));
    }
    std::map<std::pair<int, int>, Junction> junctions;
    std::vector<std::vector<int>> adjacency(segments.size());
    for (int a = 0; a < int(segments.size()); ++a)
        for (int b = a + 1; b < int(segments.size()); ++b) {
            const Segment &first = segments[a];
            const Segment &second = segments[b];
            if (angle(first.theta, second.theta) < p.junction_angle)
                continue;
            const Point da = difference(first.end, first.start), db = difference(second.end, second.start);
            const I den = cross(da, db);
            if (den == 0)
                continue;
            const I lambda = cross(difference(second.start, first.start), db);
            const Point point{rounded(first.start.x * den + lambda * da.x, den),
                              rounded(first.start.y * den + lambda * da.y, den)};
            const I a_start = chebyshev(first.start, point), a_end = chebyshev(first.end, point),
                    b_start = chebyshev(second.start, point), b_end = chebyshev(second.end, point);
            if (std::min(a_start, a_end) > p.junction_distance ||
                std::min(b_start, b_end) > p.junction_distance)
                continue;
            junctions[{a, b}] = {point, a_start <= a_end ? 0 : 1, b_start <= b_end ? 0 : 1};
            adjacency[a].push_back(b);
            adjacency[b].push_back(a);
        }
    for (auto &neighbors : adjacency)
        std::sort(neighbors.begin(), neighbors.end());
    std::vector<Polygon> polygons;
    for (int size : {3, 4})
        for (int start = 0; start < int(segments.size()); ++start) {
            std::vector<int> path{start};
            std::function<void()> visit = [&]() {
                if (int(path.size()) == size) {
                    if (path[1] >= path.back() || !lookup(junctions, path.back(), path.front()))
                        return;
                    Polygon polygon;
                    polygon.segments = path;
                    for (int i = 0; i < size; ++i) {
                        const int previous = path[(i + size - 1) % size], current = path[i],
                                  next = path[(i + 1) % size];
                        const Junction *left = lookup(junctions, previous, current);
                        const Junction *right = lookup(junctions, current, next);
                        if (junction_end(*left, current, previous) == junction_end(*right, current, next))
                            return;
                        polygon.vertices.push_back(left->point);
                    }
                    I sign = 0;
                    for (int i = 0; i < size; ++i) {
                        const I z = cross(
                            difference(polygon.vertices[(i + 1) % size], polygon.vertices[i]),
                            difference(polygon.vertices[(i + 2) % size], polygon.vertices[(i + 1) % size]));
                        if (z == 0 || (sign != 0 && ((z > 0) != (sign > 0))))
                            return;
                        sign = z;
                    }
                    for (int i = 0; i < size; ++i) {
                        const Point a = polygon.vertices[i], b = polygon.vertices[(i + 1) % size],
                                    previous = polygon.vertices[(i + size - 1) % size];
                        polygon.sigma += cross(a, b);
                        const I phi =
                            angle(segments[path[(i + size - 1) % size]].theta, segments[path[i]].theta);
                        polygon.angles.push_back(
                            dot(difference(previous, a), difference(b, a)) < 0 ? 180 - phi : phi);
                        const Point side = difference(b, a);
                        polygon.lengths.push_back(dot(side, side));
                        const Points points = bresenham(a, b);
                        I supported = 0;
                        for (Point point : points)
                            supported += near_edge(edges.edges, point);
                        polygon.support.push_back(floor_div(100 * supported, points.size()));
                        polygon.corners.push_back(-1);
                    }
                    auto all_angles = [&](I target) {
                        for (I value : polygon.angles)
                            if (std::abs(value - target) > p.angle_tolerance)
                                return false;
                        return true;
                    };
                    if (size == 3) {
                        bool right = false;
                        for (I value : polygon.angles)
                            right = right || std::abs(value - 90) <= p.angle_tolerance;
                        polygon.kind = all_angles(60) ? "equilateral_triangle"
                                       : right        ? "right_triangle"
                                                      : "triangle";
                    } else {
                        const bool a = angle(segments[path[0]].theta, segments[path[2]].theta) <=
                                       p.angle_tolerance,
                                   b = angle(segments[path[1]].theta, segments[path[3]].theta) <=
                                       p.angle_tolerance;
                        const I largest = *std::max_element(polygon.lengths.begin(), polygon.lengths.end()),
                                smallest = *std::min_element(polygon.lengths.begin(), polygon.lengths.end());
                        polygon.kind = !a && !b          ? "quadrilateral"
                                       : a != b          ? "trapezoid"
                                       : !all_angles(90) ? "parallelogram"
                                       : 100 * (largest - smallest) <= p.square_tolerance * largest
                                           ? "square"
                                           : "rectangle";
                    }
                    polygons.push_back(std::move(polygon));
                    return;
                }
                for (int next : adjacency[path.back()]) {
                    if (next <= start || std::find(path.begin(), path.end(), next) != path.end())
                        continue;
                    path.push_back(next);
                    visit();
                    path.pop_back();
                }
            };
            visit();
        }
    std::vector<Shape> shapes;
    for (int i = 0; i < int(polygons.size()); ++i)
        shapes.push_back({true, i, polygons[i].vertices});
    for (int i = 0; i < int(circles.size()); ++i) {
        const auto &circle = circles[i].peak;
        const I x = circle.center.x, y = circle.center.y, r = circle.radius;
        shapes.push_back({false, i, {{x + r, y}, {x, y + r}, {x - r, y}, {x, y - r}}});
    }
    for (Shape &shape : shapes) {
        I x0 = shape.representatives.front().x, y0 = shape.representatives.front().y;
        I x1 = x0, y1 = y0;
        for (Point point : shape.representatives) {
            x0 = std::min(x0, point.x);
            x1 = std::max(x1, point.x);
            y0 = std::min(y0, point.y);
            y1 = std::max(y1, point.y);
        }
        x0 = std::max<I>(0, x0 - p.margin);
        y0 = std::max<I>(0, y0 - p.margin);
        x1 = std::min<I>(image.width - 1, x1 + p.margin);
        y1 = std::min<I>(image.height - 1, y1 + p.margin);
        I inner = 0, outer = 0, outer_count = 0;
        for (I y = y0; y <= y1; ++y)
            for (I x = x0; x <= x1; ++x) {
                if (inside({x, y}, shape, polygons, circles)) {
                    ++shape.pixels;
                    inner += image.at({x, y});
                } else {
                    ++outer_count;
                    outer += image.at({x, y});
                }
            }
        shape.mean = shape.pixels ? floor_div(inner, shape.pixels) : 0;
        shape.contrast = shape.mean - (outer_count ? floor_div(outer, outer_count) : 0);
    }
    for (int i = 0; i < int(shapes.size()); ++i)
        for (int j = 0; j < int(shapes.size()); ++j) {
            if (i == j || shapes[j].pixels <= shapes[i].pixels)
                continue;
            bool contains = true;
            for (Point point : shapes[i].representatives)
                contains = contains && inside(point, shapes[j], polygons, circles);
            if (contains && (shapes[i].parent < 0 || shapes[j].pixels < shapes[shapes[i].parent].pixels))
                shapes[i].parent = j;
        }
    const Corners corner_data = corners(g, p);
    std::vector<std::string> corner_matches;
    I corner_vertices = 0, corner_segments = 0, vertices_with_corner = 0;
    for (const Corner &corner : corner_data.values) {
        I best = p.match_distance + 1;
        std::string match = "none";
        for (int polygon = 0; polygon < int(polygons.size()); ++polygon)
            for (int vertex = 0; vertex < int(polygons[polygon].vertices.size()); ++vertex) {
                const I d = chebyshev(corner.point, polygons[polygon].vertices[vertex]);
                if (d <= p.match_distance && d < best) {
                    best = d;
                    match =
                        "polygon " + std::to_string(polygon + 1) + " vertex " + std::to_string(vertex + 1);
                }
            }
        if (match != "none")
            ++corner_vertices;
        else {
            best = p.match_distance + 1;
            for (int id = 0; id < int(segments.size()); ++id)
                for (int end = 0; end < 2; ++end) {
                    const I d = chebyshev(corner.point, end ? segments[id].end : segments[id].start);
                    if (d <= p.match_distance && d < best) {
                        best = d;
                        match = "segment " + std::to_string(id + 1) + (end ? " end" : " start");
                    }
                }
            if (match != "none")
                ++corner_segments;
        }
        corner_matches.push_back(match);
    }
    for (Polygon &polygon : polygons)
        for (int vertex = 0; vertex < int(polygon.vertices.size()); ++vertex) {
            I best = p.match_distance + 1;
            for (int corner = 0; corner < int(corner_data.values.size()); ++corner) {
                const I d = chebyshev(polygon.vertices[vertex], corner_data.values[corner].point);
                if (d <= p.match_distance && d < best) {
                    best = d;
                    polygon.corners[vertex] = corner;
                }
            }
            vertices_with_corner += polygon.corners[vertex] >= 0;
        }
    std::vector<int> component_shapes(edges.components.size(), -1);
    std::vector<I> explained_counts(edges.components.size());
    for (int shape = 0; shape < int(shapes.size()); ++shape) {
        Image explained(image.width, image.height);
        if (shapes[shape].polygon) {
            const Polygon &polygon = polygons[shapes[shape].index];
            for (int i = 0; i < int(polygon.vertices.size()); ++i)
                for (Point point :
                     bresenham(polygon.vertices[i], polygon.vertices[(i + 1) % polygon.vertices.size()]))
                    for (I dy = -1; dy <= 1; ++dy)
                        for (I dx = -1; dx <= 1; ++dx) {
                            const Point next{point.x + dx, point.y + dy};
                            if (image.inside(next))
                                explained.at(next) = 1;
                        }
        }
        for (int component = 0; component < int(edges.components.size()); ++component) {
            I count = 0;
            for (Point point : edges.components[component])
                count += shapes[shape].polygon ? explained.at(point)
                                               : circumference(point, circles[shapes[shape].index]);
            if (count > explained_counts[component]) {
                explained_counts[component] = count;
                component_shapes[component] = shape;
            }
        }
    }
    Image overlay = image, edge_image = edges.edges, hough_image = line_data.votes;
    for (I &value : overlay.data)
        value = floor_div(value, p.overlay_divisor);
    for (I &value : edge_image.data)
        value *= 255;
    for (I &value : hough_image.data)
        value = line_data.maximum ? floor_div(255 * value, line_data.maximum) : 0;
    auto paint = [&](Point point) {
        if (image.inside(point))
            overlay.at(point) = 255;
    };
    for (const Segment &segment : segments)
        for (Point point : bresenham(segment.start, segment.end))
            paint(point);
    for (const Circle &circle : circles)
        for (Point offset : circle_data.offsets[circle.peak.radius - p.r_min])
            paint({circle.peak.center.x + offset.x, circle.peak.center.y + offset.y});
    for (const Corner &corner : corner_data.values)
        for (I e = -2; e <= 2; ++e) {
            paint({corner.point.x + e, corner.point.y});
            paint({corner.point.x, corner.point.y + e});
        }
    write_pgm("edges.pgm", edge_image);
    write_pgm("hough.pgm", hough_image);
    write_pgm("overlay.pgm", overlay);
    std::ofstream line_file("output/lines.txt"), circle_file("output/circles.txt"),
        polygon_file("output/polygons.txt"), corner_file("output/corners.txt"),
        component_file("output/components.txt"), report("output/report.txt");
    line_file << "lines " << lines.size() << '\n';
    for (int i = 0; i < int(lines.size()); ++i) {
        const Line &line = lines[i];
        line_file << "line " << i + 1 << " theta " << line.peak.theta << " rho " << line.peak.rho << " votes "
                  << line.peak.votes << " segments " << line.segments.size() << '\n';
        for (int id : line.segments) {
            const Segment &segment = segments[id];
            line_file << "segment " << id + 1 << " start " << segment.start.x << ' ' << segment.start.y
                      << " end " << segment.end.x << ' ' << segment.end.y << " length " << segment.length
                      << " pixels " << segment.pixels << '\n';
        }
    }
    circle_file << "circles " << circles.size() << '\n';
    for (int i = 0; i < int(circles.size()); ++i) {
        const Circle &circle = circles[i];
        const Shape &shape = shapes[polygons.size() + i];
        circle_file << "circle " << i + 1 << " center " << circle.peak.center.x << ' ' << circle.peak.center.y
                    << " radius " << circle.peak.radius << " votes " << circle.peak.votes << " points "
                    << circle.peak.points << " gap " << circle.gap << " arcs " << circle.arcs << " pixels "
                    << shape.pixels << " mean " << shape.mean << " contrast " << shape.contrast << " inside "
                    << shape_name(shape.parent, shapes) << '\n';
    }
    polygon_file << "polygons " << polygons.size() << '\n';
    for (int i = 0; i < int(polygons.size()); ++i) {
        const Polygon &polygon = polygons[i];
        const Shape &shape = shapes[i];
        polygon_file << "polygon " << i + 1 << ' ' << polygon.kind << " segments";
        for (int id : polygon.segments)
            polygon_file << ' ' << id + 1;
        const I area = std::abs(polygon.sigma);
        polygon_file << " area " << area / 2 << '.' << (area % 2 ? 5 : 0) << " pixels " << shape.pixels
                     << " mean " << shape.mean << " contrast " << shape.contrast << " inside "
                     << shape_name(shape.parent, shapes) << '\n';
        for (int vertex = 0; vertex < int(polygon.vertices.size()); ++vertex)
            polygon_file << "vertex " << vertex + 1 << ' ' << polygon.vertices[vertex].x << ' '
                         << polygon.vertices[vertex].y << " angle " << polygon.angles[vertex] << " corner "
                         << (polygon.corners[vertex] < 0 ? "none"
                                                         : std::to_string(polygon.corners[vertex] + 1))
                         << '\n';
        for (int side = 0; side < int(polygon.segments.size()); ++side)
            polygon_file << "side " << side + 1 << " segment " << polygon.segments[side] + 1 << " length2 "
                         << polygon.lengths[side] << " support " << polygon.support[side] << '\n';
    }
    corner_file << "corners " << corner_data.values.size() << '\n';
    for (int i = 0; i < int(corner_data.values.size()); ++i) {
        const Corner &corner = corner_data.values[i];
        corner_file << "corner " << i + 1 << ' ' << corner.point.x << ' ' << corner.point.y << " response "
                    << corner.response << " match " << corner_matches[i] << '\n';
    }
    component_file << "components " << edges.components.size() << '\n';
    for (int i = 0; i < int(edges.components.size()); ++i) {
        const Points &component = edges.components[i];
        I x0 = image.width - 1, y0 = image.height - 1, x1 = 0, y1 = 0, ends = 0, strength = 0;
        std::array<I, 4> directions{};
        for (Point point : component) {
            x0 = std::min(x0, point.x);
            y0 = std::min(y0, point.y);
            x1 = std::max(x1, point.x);
            y1 = std::max(y1, point.y);
            I neighbors = 0;
            for (I dy = -1; dy <= 1; ++dy)
                for (I dx = -1; dx <= 1; ++dx) {
                    const Point next{point.x + dx, point.y + dy};
                    if ((dx || dy) && image.inside(next) && edges.edges.at(next))
                        ++neighbors;
                }
            ends += neighbors == 1;
            strength += g.magnitude.at(point);
            ++directions[edges.direction.at(point) / 45];
        }
        int direction = 0;
        for (int j = 1; j < 4; ++j)
            if (directions[j] > directions[direction])
                direction = j;
        component_file << "component " << i + 1 << " pixels " << component.size() << " box " << x0 << ' '
                       << y0 << ' ' << x1 << ' ' << y1 << " ends " << ends << " strength "
                       << floor_div(strength, component.size()) << " direction " << 45 * direction
                       << " shape " << shape_name(component_shapes[i], shapes) << " explained "
                       << explained_counts[i] << '\n';
    }
    std::map<std::string, I> counts;
    for (int i = 0; i < int(image.data.size()); ++i) {
        counts["gradient_nonzero"] += g.magnitude.data[i] > 0;
        counts["gradient_max"] = std::max(counts["gradient_max"], g.magnitude.data[i]);
        counts["nms_kept"] += edges.nms.data[i] > 0;
        counts["edges"] += edges.edges.data[i];
        counts["weak_kept"] +=
            edges.edges.data[i] && edges.nms.data[i] >= p.low && edges.nms.data[i] < p.high;
        counts["claimed_pixels"] += claimed.data[i];
        if (edges.edges.data[i])
            ++counts["direction_" + std::to_string(edges.direction.data[i])];
    }
    counts["strong"] = edges.strong;
    counts["weak"] = edges.weak;
    counts["weak_dropped"] = edges.weak - counts["weak_kept"];
    counts["edge_components"] = edges.components.size();
    counts["circle_candidates"] = circle_data.candidates;
    counts["circle_peaks"] = circle_data.peaks.size();
    counts["circles"] = circles.size();
    counts["circle_edge_pixels"] = circle_edge_pixels;
    counts["line_edge_pixels"] = counts["edges"] - circle_edge_pixels;
    counts["hough_max_votes"] = line_data.maximum;
    counts["hough_peaks"] = line_data.peaks.size();
    counts["lines"] = lines.size();
    counts["segments"] = segments.size();
    counts["junctions"] = junctions.size();
    counts["polygons"] = polygons.size();
    for (const Polygon &polygon : polygons)
        ++counts[polygon.kind];
    counts["corner_candidates"] = corner_data.candidates;
    counts["corners"] = corner_data.values.size();
    counts["corners_on_vertices"] = corner_vertices;
    counts["corners_on_segments"] = corner_segments;
    counts["corners_unmatched"] = corner_data.values.size() - corner_vertices - corner_segments;
    counts["vertices_with_corner"] = vertices_with_corner;
    report << "image " << image.width << ' ' << image.height << '\n';
    for (const std::string name : {"gradient_nonzero",
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
                                   "vertices_with_corner"})
        report << name << ' ' << counts[name] << '\n';
}
