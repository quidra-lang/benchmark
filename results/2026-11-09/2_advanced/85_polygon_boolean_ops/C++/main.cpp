#include "geometry.hpp"
#include <algorithm>
#include <fstream>
#include <filesystem>
#include <iomanip>
#include <map>
#include <set>
#include <stdexcept>

std::vector<std::string> readLines(const std::string &name) {
    std::ifstream file(name);
    if (!file)
        throw std::runtime_error("cannot read " + name);
    std::vector<std::string> result;
    std::string line;
    while (std::getline(file, line))
        result.push_back(line);
    return result;
}
std::vector<std::string> words(const std::string &value) {
    std::istringstream input(value);
    std::vector<std::string> result;
    std::string word;
    while (input >> word)
        result.push_back(word);
    return result;
}
std::string join(const std::vector<std::string> &parts, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i)
            result += separator;
        result += parts[i];
    }
    return result;
}
std::string fixed(double value, int digits) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(digits) << value;
    return out.str();
}
void writeLines(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream file("output/" + name);
    if (!file)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        file << line << '\n';
}
static const std::vector<std::string> kinds = {"UNION",  "INTERSECTION", "DIFFERENCE", "XOR",
                                               "CLIP",   "AREA",         "MOVE",       "ROTATE",
                                               "MIRROR", "SNAP",         "LOCATE",     "RENDER"};
static bool ignored(const std::string &line) { return line.empty() || line[0] == '#'; }
static bool unsignedWord(const std::string &value) {
    return !value.empty() && value.size() <= 9 &&
           std::all_of(value.begin(), value.end(), [](char c) { return c >= '0' && c <= '9'; });
}
static bool integerWord(const std::string &value) {
    return unsignedWord(!value.empty() && value[0] == '-' ? value.substr(1) : value);
}
static bool nameWord(const std::string &value) {
    return !value.empty() && value.size() <= 16 &&
           std::all_of(value.begin(), value.end(), [](char c) {
               return c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_';
           });
}
static bool inRange(Point p) {
    return p.xValue().compare(Fraction(0)) >= 0 && p.xValue().compare(Fraction(1000)) <= 0 &&
           p.yValue().compare(Fraction(0)) >= 0 && p.yValue().compare(Fraction(1000)) <= 0;
}
struct SourceLine {
    int number;
    std::string text;
};
static std::pair<Rings, int> parseBlock(const std::vector<SourceLine> &content, int end) {
    Rings rings;
    std::size_t at = 0;
    while (at < content.size()) {
        const SourceLine &header = content[at];
        std::vector<std::string> a = words(header.text);
        if (a.size() != 2 || (a[0] != "OUTER" && a[0] != "HOLE") || !unsignedWord(a[1]) ||
            std::stoll(a[1]) < 1 || (a[0] == "OUTER" && !rings.empty()) ||
            (a[0] == "HOLE" && rings.empty()))
            return {{}, header.number};
        Integer count = std::stoll(a[1]);
        ++at;
        std::vector<Point> points;
        for (Integer i = 0; i < count; ++i) {
            if (at == content.size())
                return {{}, end};
            const SourceLine &source = content[at++];
            a = words(source.text);
            if (a.size() != 2 || !integerWord(a[0]) || !integerWord(a[1]))
                return {{}, source.number};
            points.emplace_back(std::stoll(a[0]), std::stoll(a[1]));
        }
        rings.push_back(integerRing(std::move(points)));
    }
    return rings.empty() ? std::make_pair(Rings{}, end) : std::make_pair(std::move(rings), 0);
}
static std::string checkPolygon(const Rings &rings) {
    for (std::size_t k = 0; k < rings.size(); ++k) {
        const Ring &ring = rings[k];
        std::size_t n = ring.points.size();
        if (n < 3)
            return text("too_few_vertices ring ", k + 1);
        for (Point p : ring.points)
            if (!inRange(p))
                return text("out_of_range ring ", k + 1, " ", p);
        for (std::size_t j = 0; j < n; ++j)
            for (std::size_t i = 0; i < j; ++i)
                if (ring.points[j] == ring.points[i])
                    return text("duplicate_vertex ring ", k + 1, " ", ring.points[j]);
        for (std::size_t i = 0; i < n; ++i)
            if (integerCross(ring.points[(i + n - 1) % n], ring.points[i],
                             ring.points[(i + 1) % n]) == 0)
                return text("collinear ring ", k + 1, " ", ring.points[i]);
        for (std::size_t i = 0; i < n; ++i)
            for (std::size_t j = i + 1; j < n; ++j) {
                if (j == i + 1 || (i == 0 && j == n - 1))
                    continue;
                if (touching(ring.points[i], ring.points[(i + 1) % n], ring.points[j],
                             ring.points[(j + 1) % n]))
                    return text("self_intersection ring ", k + 1, " ",
                                segmentText(ring.points[i], ring.points[(i + 1) % n]), " ",
                                segmentText(ring.points[j], ring.points[(j + 1) % n]));
            }
    }
    for (std::size_t i = 0; i < rings.size(); ++i)
        for (std::size_t j = i + 1; j < rings.size(); ++j)
            for (std::size_t e = 0; e < rings[i].points.size(); ++e)
                for (std::size_t f = 0; f < rings[j].points.size(); ++f) {
                    Point a = rings[i].points[e],
                          b = rings[i].points[(e + 1) % rings[i].points.size()],
                          c = rings[j].points[f],
                          d = rings[j].points[(f + 1) % rings[j].points.size()];
                    if (touching(a, b, c, d))
                        return text("rings_touch rings ", i + 1, " ", j + 1, " ", segmentText(a, b),
                                    " ", segmentText(c, d));
                }
    for (std::size_t k = 1; k < rings.size(); ++k)
        if (!insideRing(rings[k].points[0], rings[0]))
            return text("hole_outside ring ", k + 1, " ", rings[k].points[0]);
    for (std::size_t i = 1; i < rings.size(); ++i)
        for (std::size_t j = i + 1; j < rings.size(); ++j) {
            if (insideRing(rings[j].points[0], rings[i]))
                return text("hole_in_hole rings ", i + 1, " ", j + 1, " ", rings[j].points[0]);
            if (insideRing(rings[i].points[0], rings[j]))
                return text("hole_in_hole rings ", i + 1, " ", j + 1, " ", rings[i].points[0]);
        }
    return "";
}
static std::string generalPosition(const Polygon &a, const Polygon &b, const std::string &aName,
                                   const std::string &bName) {
    for (const Ring &first : a.rings)
        for (Point p : first.points)
            for (const Ring &second : b.rings)
                for (Point q : second.points)
                    if (p == q)
                        return text("shared_vertex ", p);
    for (const Ring &first : a.rings)
        for (std::size_t e = 0; e < first.points.size(); ++e)
            for (const Ring &second : b.rings)
                for (std::size_t f = 0; f < second.points.size(); ++f) {
                    Point p = first.points[e], q = first.points[(e + 1) % first.points.size()],
                          r = second.points[f], s = second.points[(f + 1) % second.points.size()];
                    if (overlapping(p, q, r, s))
                        return text("overlapping_edges ", segmentText(p, q), " ",
                                    segmentText(r, s));
                }
    for (int side = 0; side < 2; ++side) {
        const Polygon &first = side ? b : a, &second = side ? a : b;
        for (const Ring &ring : first.rings)
            for (Point p : ring.points)
                for (const Ring &other : second.rings)
                    for (std::size_t e = 0; e < other.points.size(); ++e)
                        if (onEdge(p, other, e))
                            return text("vertex_on_edge ", side ? bName : aName, " ", p, " ",
                                        side ? aName : bName, " ",
                                        segmentText(other.points[e],
                                                    other.points[(e + 1) % other.points.size()]));
    }
    return "";
}
static bool numeric(const std::string &value, Integer low, Integer high) {
    return integerWord(value) && std::stoll(value) >= low && std::stoll(value) <= high;
}
static bool validArguments(const std::vector<std::string> &a) {
    const std::string &kind = a[0];
    std::size_t required = kind == "AREA"                       ? 2
                           : kind == "LOCATE"                   ? 4
                           : kind == "MOVE" || kind == "MIRROR" ? 5
                           : kind == "ROTATE"                   ? 6
                           : kind == "RENDER"                   ? 8
                                                                : 3;
    if (a.size() != required)
        return false;
    if (kind == "LOCATE")
        return numeric(a[2], 0, 1000) && numeric(a[3], 0, 1000);
    if (kind == "MOVE")
        return numeric(a[2], -1000, 1000) && numeric(a[3], -1000, 1000) && nameWord(a[4]);
    if (kind == "ROTATE")
        return numeric(a[2], 0, 1000) && numeric(a[3], 0, 1000) && numeric(a[4], 1, 3) &&
               nameWord(a[5]);
    if (kind == "MIRROR")
        return (a[2] == "x" || a[2] == "y") && numeric(a[3], 0, 1000) && nameWord(a[4]);
    if (kind == "SNAP")
        return nameWord(a[2]);
    if (kind == "RENDER") {
        for (int i = 2; i < 8; ++i) {
            Integer low = i >= 4 ? 1 : 0, high = i == 7 ? 60 : i >= 4 ? 100 : 1000;
            if (!numeric(a[i], low, high))
                return false;
        }
        return std::stoll(a[2]) + std::stoll(a[4]) * std::stoll(a[6]) <= 1000 &&
               std::stoll(a[3]) + std::stoll(a[5]) * std::stoll(a[7]) <= 1000;
    }
    return true;
}
static bool convex(const Polygon &polygon) {
    if (polygon.rings.size() != 1)
        return false;
    const Ring &ring = polygon.rings[0];
    for (std::size_t i = 0; i < ring.points.size(); ++i)
        if (integerCross(ring.points[(i + ring.points.size() - 1) % ring.points.size()],
                         ring.points[i], ring.points[(i + 1) % ring.points.size()]) <= 0)
            return false;
    return true;
}
static Rings transformed(const Polygon &polygon, const std::vector<std::string> &a) {
    Rings result;
    for (const Ring &ring : polygon.input) {
        std::vector<Point> points;
        for (Point p : ring.points) {
            Integer x = p.x, y = p.y;
            if (a[0] == "MOVE") {
                x += std::stoll(a[2]);
                y += std::stoll(a[3]);
            } else if (a[0] == "ROTATE") {
                Integer cx = std::stoll(a[2]), cy = std::stoll(a[3]);
                for (int i = 0; i < std::stoi(a[4]); ++i) {
                    Integer nx = cx - (y - cy);
                    y = cy + (x - cx);
                    x = nx;
                }
            } else if (a[2] == "x")
                x = 2 * std::stoll(a[3]) - x;
            else
                y = 2 * std::stoll(a[3]) - y;
            points.emplace_back(x, y);
        }
        result.push_back(integerRing(std::move(points)));
    }
    return result;
}
static bool cyclicEqual(const Ring &a, const Ring &b) {
    if (a.points.size() != b.points.size())
        return false;
    for (std::size_t offset = 0; offset < b.points.size(); ++offset) {
        bool same = true;
        for (std::size_t i = 0; i < a.points.size(); ++i)
            if (!(a.points[i] == b.points[(offset + i) % b.points.size()])) {
                same = false;
                break;
            }
        if (same)
            return true;
    }
    return false;
}
struct Crosscheck {
    bool match;
    int rings, vertices;
};
static Crosscheck sutherland(const Polygon &subject, const Polygon &window,
                             const PolygonList &result) {
    Rings clipped;
    for (const Ring &ring : subject.rings) {
        Ring list = ring;
        for (OriginalLine clip : window.rings[0].edges) {
            Ring next;
            std::vector<OriginalLine> incoming;
            for (std::size_t i = 0; i < list.points.size(); ++i) {
                std::size_t previous = (i + list.points.size() - 1) % list.points.size();
                Point prev = list.points[previous], cur = list.points[i];
                OriginalLine edge = list.edges[previous];
                bool insidePrev = lineCross(clip, prev) > 0, insideCur = lineCross(clip, cur) > 0;
                if (insidePrev != insideCur) {
                    next.points.push_back(lineIntersection(edge, clip));
                    incoming.push_back(insidePrev ? edge : clip);
                }
                if (insideCur) {
                    next.points.push_back(cur);
                    incoming.push_back(edge);
                }
            }
            for (std::size_t i = 0; i < incoming.size(); ++i)
                next.edges.push_back(incoming[(i + 1) % incoming.size()]);
            list = std::move(next);
        }
        std::vector<std::size_t> kept;
        for (std::size_t i = 0; i < list.points.size(); ++i)
            if (!(list.points[i] == list.points[(i + list.points.size() - 1) % list.points.size()]))
                kept.push_back(i);
        if (kept.size() >= 3) {
            Ring deduplicated;
            for (std::size_t i = 0; i < kept.size(); ++i) {
                deduplicated.points.push_back(list.points[kept[i]]);
                std::size_t next = kept[(i + 1) % kept.size()];
                deduplicated.edges.push_back(
                    list.edges[(next + list.points.size() - 1) % list.points.size()]);
            }
            clipped.push_back(std::move(deduplicated));
        }
    }
    int vertices = 0;
    for (const Ring &ring : clipped)
        vertices += static_cast<int>(ring.points.size());
    Rings rings = flatten(result);
    bool match = rings.size() == clipped.size();
    if (match)
        for (const Ring &ring : rings) {
            bool found = false;
            for (const Ring &other : clipped)
                if (cyclicEqual(ring, other)) {
                    found = true;
                    break;
                }
            if (!found) {
                match = false;
                break;
            }
        }
    return {match, static_cast<int>(clipped.size()), vertices};
}
static std::string location(const Result &result, Point p) {
    for (std::size_t k = 0; k < result.polygons.size(); ++k)
        for (std::size_t j = 0; j < result.polygons[k]->rings.size(); ++j)
            if (boundary(p, result.polygons[k]->rings[j]))
                return j == 0 ? text("boundary outer ", k + 1)
                              : text("boundary hole ", k + 1, " ", j);
    for (std::size_t k = 0; k < result.polygons.size(); ++k) {
        const Rings &rings = result.polygons[k]->rings;
        if (!insideRing(p, rings[0]))
            continue;
        bool hole = false;
        for (std::size_t j = 1; j < rings.size(); ++j)
            hole = hole || insideRing(p, rings[j]);
        if (!hole)
            return text("inside polygon ", k + 1);
    }
    return "outside";
}
static std::string operandLocation(Point p, const Polygon &polygon) {
    for (const Ring &ring : polygon.rings)
        if (boundary(p, ring))
            return "boundary";
    return interior(p, polygon.rings) ? "inside" : "outside";
}
static Integer twiceArea(const Ring &ring) {
    Integer sum = 0;
    for (std::size_t i = 0; i < ring.points.size(); ++i) {
        Point a = ring.points[i], b = ring.points[(i + 1) % ring.points.size()];
        sum += a.x * b.y - b.x * a.y;
    }
    return sum;
}
static Ring hull(const Ring &ring) {
    std::vector<Point> sorted = ring.points;
    std::sort(sorted.begin(), sorted.end(),
              [](Point a, Point b) { return a.x != b.x ? a.x < b.x : a.y < b.y; });
    std::vector<Point> lower, upper;
    for (Point p : sorted) {
        while (lower.size() >= 2 && integerCross(lower[lower.size() - 2], lower.back(), p) <= 0)
            lower.pop_back();
        lower.push_back(p);
    }
    for (auto p = sorted.rbegin(); p != sorted.rend(); ++p) {
        while (upper.size() >= 2 && integerCross(upper[upper.size() - 2], upper.back(), *p) <= 0)
            upper.pop_back();
        upper.push_back(*p);
    }
    lower.pop_back();
    upper.pop_back();
    lower.insert(lower.end(), upper.begin(), upper.end());
    return integerRing(std::move(lower));
}
class Laboratory {
    std::set<std::string> used;
    std::map<std::string, PolygonPtr> polygons;
    std::map<int, Result> results;
    std::vector<std::string> output, areas = {"operation,rings,holes,vertices,area"}, rendered,
                                     polygonErrors, operationErrors;
    int blocks = 0, valid = 0, defined = 0, operationCount = 0, succeeded = 0, crossingCount = 0;
    std::map<std::string, int> counts, accepted;
    void readPolygons() {
        std::vector<std::string> source = readLines("input/polygons.txt");
        for (std::size_t i = 0; i < source.size(); ++i) {
            if (ignored(source[i]))
                continue;
            int start = static_cast<int>(i) + 1;
            std::string name = words(source[i])[1];
            std::vector<SourceLine> content;
            ++i;
            for (; source[i] != "END"; ++i)
                if (!ignored(source[i]))
                    content.push_back({static_cast<int>(i) + 1, source[i]});
            int end = static_cast<int>(i) + 1;
            ++blocks;
            std::string reason;
            if (used.count(name))
                reason = text("duplicate_name line ", start);
            else {
                used.insert(name);
                auto parsed = parseBlock(content, end);
                if (parsed.second)
                    reason = text("format line ", parsed.second);
                else {
                    reason = checkPolygon(parsed.first);
                    if (reason.empty()) {
                        polygons[name] = canonical(parsed.first);
                        ++valid;
                    }
                }
            }
            if (!reason.empty())
                polygonErrors.push_back("polygon " + name + " " + reason);
        }
    }
    std::pair<PolygonPtr, std::string> polygon(const std::string &name) const {
        if (!used.count(name))
            return {{}, "unknown_polygon " + name};
        auto found = polygons.find(name);
        if (found == polygons.end())
            return {{}, "invalid_polygon " + name};
        return {found->second, ""};
    }
    std::pair<Result, std::string> target(const std::string &name) const {
        if (!name.empty() && name[0] == '@') {
            std::string number = name.substr(1);
            if (unsignedWord(number)) {
                auto found = results.find(std::stoi(number));
                if (found != results.end())
                    return {found->second, ""};
            }
            return {{}, "bad_target " + name};
        }
        auto resolved = polygon(name);
        if (!resolved.second.empty())
            return {{}, resolved.second};
        return {Result{{resolved.first}, {}, {}}, ""};
    }
    void reportRegion(int number, const std::vector<std::string> &a, const std::string &source,
                      const Result &result, PolygonPtr originA, PolygonPtr originB,
                      PolygonPtr property, const GhGraph *graph) {
        output.push_back(text("op ", number, " ", source));
        if (graph) {
            std::string relation = "overlap";
            if (graph->crossings.empty()) {
                if (graph->na == static_cast<int>(graph->rings[0].size()) && graph->nb == 0)
                    relation = "within";
                else if (graph->nb == static_cast<int>(graph->rings[1].size()) && graph->na == 0)
                    relation = "contains";
                else if (graph->na == 0 && graph->nb == 0)
                    relation = "disjoint";
            }
            PolygonList intersection = assemble(graph->traverse(false, false)),
                        united = assemble(graph->traverse(true, true));
            output.push_back(text("relation ", relation, " iou ",
                                  fixed(totalArea(intersection) / totalArea(united), 6)));
            output.push_back(text("crossings ", graph->crossings.size()));
            for (const Crossing *crossing : graph->crossings)
                output.push_back(text("crossing ", crossing->point, " ",
                                      crossing->first->entering ? "in" : "out"));
            crossingCount += static_cast<int>(graph->crossings.size());
        }
        Rings rings = flatten(result.polygons);
        std::size_t vertices = 0;
        for (const Ring &ring : rings)
            vertices += ring.points.size();
        std::size_t holes = rings.size() - result.polygons.size();
        double area = totalArea(result.polygons);
        output.push_back(text("polygons ", result.polygons.size(), " rings ", rings.size(),
                              " holes ", holes, " vertices ", vertices, " area ", fixed(area, 3)));
        for (std::size_t k = 0; k < result.polygons.size(); ++k)
            for (std::size_t j = 0; j < result.polygons[k]->rings.size(); ++j) {
                const Ring &ring = result.polygons[k]->rings[j];
                std::string value = j ? text("hole ", k + 1, " ", j) : text("outer ", k + 1);
                value += text(" ", ring.points.size(), " ", fixed(ringArea(ring), 3));
                for (Point p : ring.points)
                    value += text(" ", p);
                output.push_back(value);
            }
        double perimeter = 0.0, sx = 0.0, sy = 0.0;
        Fraction lowX, lowY, highX, highY;
        bool hasPoint = false;
        for (const Ring &ring : rings) {
            perimeter += ringPerimeter(ring);
            for (std::size_t i = 0; i < ring.points.size(); ++i) {
                Point p = ring.points[i], q = ring.points[(i + 1) % ring.points.size()];
                Fraction x = p.xValue(), y = p.yValue();
                if (!hasPoint) {
                    lowX = highX = x;
                    lowY = highY = y;
                    hasPoint = true;
                }
                if (x.compare(lowX) < 0)
                    lowX = x;
                if (y.compare(lowY) < 0)
                    lowY = y;
                if (x.compare(highX) > 0)
                    highX = x;
                if (y.compare(highY) > 0)
                    highY = y;
                double x1 = x.real(), y1 = y.real(), x2 = q.xValue().real(), y2 = q.yValue().real(),
                       c = x1 * y2 - x2 * y1;
                sx += (x1 + x2) * c;
                sy += (y1 + y2) * c;
            }
        }
        if (hasPoint) {
            output.push_back(text("bbox (", lowX, ",", lowY, ") (", highX, ",", highY, ")"));
            output.push_back(text("centroid (", fixed(sx / (6.0 * area), 3), ",",
                                  fixed(sy / (6.0 * area), 3), ")"));
        } else {
            output.push_back("bbox none");
            output.push_back("centroid none");
        }
        output.push_back("perimeter " + fixed(perimeter, 3));
        int aCount = 0, bCount = 0, cCount = 0;
        const auto has = [&](PolygonPtr polygon, Point p) {
            if (polygon)
                for (const Ring &ring : polygon->rings)
                    for (Point q : ring.points)
                        if (p == q)
                            return true;
            return false;
        };
        for (const Ring &ring : rings)
            for (Point p : ring.points) {
                if (has(originA, p))
                    ++aCount;
                else if (has(originB, p))
                    ++bCount;
                else
                    ++cCount;
            }
        output.push_back(text("origins a ", aCount, " b ", bCount, " crossing ", cCount));
        if (property) {
            std::vector<std::string> orientations;
            for (const Ring &ring : property->input)
                orientations.push_back(twiceArea(ring) > 0 ? "ccw" : "cw");
            int reflex = 0;
            for (const Ring &ring : property->rings)
                for (std::size_t i = 0; i < ring.points.size(); ++i)
                    if (integerCross(ring.points[(i + ring.points.size() - 1) % ring.points.size()],
                                     ring.points[i], ring.points[(i + 1) % ring.points.size()]) < 0)
                        ++reflex;
            Ring convexHull = hull(property->rings[0]);
            double hullArea = static_cast<double>(twiceArea(convexHull)) / 2.0;
            output.push_back("input " + join(orientations, " "));
            output.push_back(text("reflex ", reflex));
            output.push_back(text("hull ", convexHull.points.size(), " ", fixed(hullArea, 3),
                                  " solidity ", fixed(area / hullArea, 6)));
        }
        if (a[0] == "CLIP") {
            Crosscheck check = sutherland(*result.a, *result.b, result.polygons);
            output.push_back(text("crosscheck ", check.match ? "match" : "mismatch", " rings ",
                                  check.rings, " vertices ", check.vertices));
        }
        areas.push_back(text(number, ":", join(a, ":"), ",", rings.size(), ",", holes, ",",
                             vertices, ",", fixed(area, 3)));
    }
    std::string operation(int number, const std::string &source) {
        std::vector<std::string> a = words(source);
        const std::string &kind = a[0];
        if (std::find(kinds.begin(), kinds.end(), kind) == kinds.end())
            return "unknown_operation " + kind;
        if (!validArguments(a))
            return "bad_arguments";
        bool binary = kind == "UNION" || kind == "INTERSECTION" || kind == "DIFFERENCE" ||
                      kind == "XOR" || kind == "CLIP",
             definition = kind == "MOVE" || kind == "ROTATE" || kind == "MIRROR" || kind == "SNAP";
        PolygonPtr first, second, property;
        Result resolved;
        if (binary || kind == "AREA" || kind == "MOVE" || kind == "ROTATE" || kind == "MIRROR") {
            auto p = polygon(a[1]);
            if (!p.second.empty())
                return p.second;
            first = p.first;
            if (binary) {
                p = polygon(a[2]);
                if (!p.second.empty())
                    return p.second;
                second = p.first;
            }
        } else {
            auto t = target(a[1]);
            if (!t.second.empty())
                return t.second;
            resolved = std::move(t.first);
        }
        std::string newName = definition ? a.back() : "";
        if (definition && used.count(newName))
            return "duplicate_name " + newName;
        if (kind == "SNAP" && resolved.polygons.size() != 1)
            return "not_single " + a[1];
        if (kind == "CLIP" && !convex(*second))
            return "not_convex " + a[2];
        if (binary) {
            std::string error = generalPosition(*first, *second, a[1], a[2]);
            if (!error.empty())
                return error;
        }
        if (definition) {
            Rings input;
            if (kind == "SNAP") {
                for (const Ring &ring : resolved.polygons[0]->rings) {
                    std::vector<Point> points;
                    for (Point p : ring.points)
                        points.emplace_back(p.xValue().rounded(), p.yValue().rounded());
                    input.push_back(integerRing(std::move(points)));
                }
                std::string error = checkPolygon(input);
                if (!error.empty())
                    return "invalid_result " + error;
            } else {
                input = transformed(*first, a);
                for (const Ring &ring : input)
                    for (Point p : ring.points)
                        if (!inRange(p))
                            return "out_of_range " + newName;
            }
            property = canonical(input);
            used.insert(newName);
            polygons[newName] = property;
            ++defined;
        }
        ++succeeded;
        ++accepted[kind];
        if (kind == "LOCATE") {
            Point p(std::stoll(a[2]), std::stoll(a[3]));
            output.push_back(text("op ", number, " ", source));
            output.push_back("location " + location(resolved, p));
            if (resolved.a && resolved.b)
                output.push_back("operands a " + operandLocation(p, *resolved.a) + " b " +
                                 operandLocation(p, *resolved.b));
            return "";
        }
        if (kind == "RENDER") {
            Rendered picture = render(resolved, std::stoi(a[2]), std::stoi(a[3]), std::stoi(a[4]),
                                      std::stoi(a[5]), std::stoi(a[6]), std::stoi(a[7]));
            rendered.push_back(text("render ", number, " ", a[1], " cols ", std::stoi(a[6]),
                                    " rows ", std::stoi(a[7]), " result ", picture.result, " a ",
                                    picture.a, " b ", picture.b, " both ", picture.both));
            rendered.insert(rendered.end(), picture.rows.begin(), picture.rows.end());
            return "";
        }
        Result result;
        std::unique_ptr<GhGraph> graph;
        PolygonPtr originA = first, originB = second;
        if (binary) {
            graph = std::make_unique<GhGraph>(first->rings, second->rings);
            if (kind == "UNION")
                result.polygons = assemble(graph->traverse(true, true));
            else if (kind == "DIFFERENCE" || kind == "XOR") {
                result.polygons = assemble(graph->traverse(true, false));
                if (kind == "XOR") {
                    GhGraph other(second->rings, first->rings);
                    PolygonList extra = assemble(other.traverse(true, false));
                    result.polygons.insert(result.polygons.end(), extra.begin(), extra.end());
                    std::sort(result.polygons.begin(), result.polygons.end(),
                              [](const PolygonPtr &a, const PolygonPtr &b) {
                                  return pointLess(a->rings[0].points[0], b->rings[0].points[0]);
                              });
                }
            } else
                result.polygons = assemble(graph->traverse(false, false));
            result.a = first;
            result.b = second;
        } else {
            if (!definition)
                property = first;
            originA = property;
            originB.reset();
            result.polygons = {property};
        }
        results[number] = result;
        reportRegion(number, a, source, result, originA, originB, property, graph.get());
        return "";
    }

  public:
    void run() {
        readPolygons();
        for (const std::string &source : readLines("input/operations.txt")) {
            if (ignored(source))
                continue;
            ++operationCount;
            ++counts[words(source)[0]];
            std::string reason = operation(operationCount, source);
            if (!reason.empty())
                operationErrors.push_back(text("op ", operationCount, " ", reason));
        }
        output.push_back(text("summary polygons ", blocks, " valid ", valid, " invalid ",
                              blocks - valid, " defined ", defined));
        output.push_back(text("summary operations ", operationCount, " succeeded ", succeeded,
                              " rejected ", operationErrors.size()));
        output.push_back(text("summary crossings ", crossingCount));
        for (const std::string &kind : kinds)
            output.push_back(text("kind ", kind, " ", counts[kind], " ", accepted[kind]));
        std::vector<std::string> rejections = {
            text("rejections ", polygonErrors.size() + operationErrors.size())};
        rejections.insert(rejections.end(), polygonErrors.begin(), polygonErrors.end());
        rejections.insert(rejections.end(), operationErrors.begin(), operationErrors.end());
        std::filesystem::create_directories("output");
        writeLines("results.txt", output);
        writeLines("areas.csv", areas);
        writeLines("render.txt", rendered);
        writeLines("rejections.txt", rejections);
    }
};
int main() {
    Laboratory laboratory;
    laboratory.run();
}
