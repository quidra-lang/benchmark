#include <algorithm>
#include <array>
#include <iostream>
#include <iterator>
#include <map>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;
using i64 = long long;

struct Rect {
    string name, layer;
    int x1, y1, x2, y2;
    int width() const {
        return x2 - x1;
    }
    int height() const {
        return y2 - y1;
    }
    i64 area() const {
        return i64(width()) * height();
    }
    string text() const {
        return "(" + to_string(x1) + "," + to_string(y1) + ")-(" +
               to_string(x2) + "," + to_string(y2) + ")";
    }
};

string point(int x, int y) {
    return "(" + to_string(x) + "," + to_string(y) + ")";
}
string joined(const vector<string>& values, const string& separator = " ") {
    string result;
    for (const auto& value : values) {
        if (!result.empty()) result += separator;
        result += value;
    }
    return result;
}
string decimal(i64 numerator, i64 denominator) {
    i64 hundredths = 100 * numerator / denominator;
    return to_string(hundredths / 100) + "." +
           (hundredths % 100 < 10 ? "0" : "") + to_string(hundredths % 100);
}
void require(bool condition, const string& message) {
    if (!condition) throw runtime_error(message);
}
void bounded(const Rect& r) {
    require(r.x1 >= -10000 && r.y1 >= -10000 && r.x2 <= 10000 && r.y2 <= 10000,
            "out of bounds");
}
Rect common(const Rect& a, const Rect& b) {
    return {"", "", max(a.x1, b.x1), max(a.y1, b.y1), min(a.x2, b.x2), min(a.y2, b.y2)};
}
int relation(const Rect& a, const Rect& b) {
    Rect r = common(a, b);
    if (r.width() < 0 || r.height() < 0) return 3;
    if (r.width() == 0 && r.height() == 0) return 2;
    if (r.width() == 0 || r.height() == 0) return 1;
    return 0;
}
int gap(const Rect& a, const Rect& b) {
    Rect r = common(a, b);
    return max({0, -r.width(), -r.height()});
}
array<int, 4> margins(const Rect& outer, const Rect& inner) {
    return {inner.x1 - outer.x1, inner.y1 - outer.y1,
            outer.x2 - inner.x2, outer.y2 - inner.y2};
}
int min_margin(const Rect& outer, const Rect& inner) {
    auto values = margins(outer, inner);
    return *min_element(values.begin(), values.end());
}

// Each compressed cell is a whole rectangular block of equally covered unit squares.
struct Grid {
    vector<int> xs, ys;
    vector<vector<int>> counts;
    explicit Grid(const vector<Rect>& rectangles) {
        for (const Rect& r : rectangles) {
            xs.push_back(r.x1);
            xs.push_back(r.x2);
            ys.push_back(r.y1);
            ys.push_back(r.y2);
        }
        for (auto* axis : {&xs, &ys}) {
            sort(axis->begin(), axis->end());
            axis->erase(unique(axis->begin(), axis->end()), axis->end());
        }
        if (rectangles.empty()) return;
        counts.assign(ys.size() - 1, vector<int>(xs.size() - 1));
        for (const Rect& r : rectangles) {
            int l = lower_bound(xs.begin(), xs.end(), r.x1) - xs.begin();
            int e = lower_bound(xs.begin(), xs.end(), r.x2) - xs.begin();
            int b = lower_bound(ys.begin(), ys.end(), r.y1) - ys.begin();
            int t = lower_bound(ys.begin(), ys.end(), r.y2) - ys.begin();
            for (int j = b; j < t; ++j)
                for (int i = l; i < e; ++i) ++counts[j][i];
        }
    }
    int rows() const {
        return counts.size();
    }
    int columns() const {
        return counts.empty() ? 0 : counts[0].size();
    }
    Rect bounds() const {
        return {"", "", xs.front(), ys.front(), xs.back(), ys.back()};
    }
    i64 area(int threshold = 1) const {
        i64 result = 0;
        for (int j = 0; j < rows(); ++j)
            for (int i = 0; i < columns(); ++i)
                if (counts[j][i] >= threshold)
                    result += i64(xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
        return result;
    }
    i64 clipped_area(const Rect& window) const {
        i64 result = 0;
        for (int j = 0; j < rows(); ++j)
            for (int i = 0; i < columns(); ++i) if (counts[j][i]) {
                int w = min(xs[i + 1], window.x2) - max(xs[i], window.x1);
                int h = min(ys[j + 1], window.y2) - max(ys[j], window.y1);
                if (w > 0 && h > 0) result += i64(w) * h;
            }
        return result;
    }
    i64 perimeter() const {
        i64 result = 0;
        for (int j = 0; j < rows(); ++j)
            for (int i = 0; i < columns(); ++i) if (counts[j][i]) {
                if (i == 0 || !counts[j][i - 1]) result += ys[j + 1] - ys[j];
                if (i + 1 == columns() || !counts[j][i + 1]) result += ys[j + 1] - ys[j];
                if (j == 0 || !counts[j - 1][i]) result += xs[i + 1] - xs[i];
                if (j + 1 == rows() || !counts[j + 1][i]) result += xs[i + 1] - xs[i];
            }
        return result;
    }
    void empty_rectangle(const string& layer) const {
        Rect best{};
        i64 best_area = 0;
        for (int l = 0; l < columns(); ++l) {
            vector<bool> blocked(rows());
            for (int e = l + 1; e <= columns(); ++e) {
                for (int j = 0; j < rows(); ++j) blocked[j] = blocked[j] || counts[j][e - 1];
                for (int j = 0; j < rows();) {
                    if (blocked[j]) {
                        ++j;
                        continue;
                    }
                    int b = j;
                    while (j < rows() && !blocked[j]) ++j;
                    Rect candidate{"", "", xs[l], ys[b], xs[e], ys[j]};
                    if (candidate.area() > best_area ||
                        (candidate.area() == best_area &&
                         make_tuple(candidate.x1, candidate.y1, candidate.width()) <
                         make_tuple(best.x1, best.y1, best.width()))) {
                        best = candidate;
                        best_area = best.area();
                    }
                }
            }
        }
        cout << "empty " << layer << ": ";
        if (!best_area) cout << "none\n";
        else cout << best.text() << " area " << best_area << '\n';
    }
    void holes(const string& layer) const {
        struct Hole {
            int anchor_x, anchor_y;
            i64 area;
            Rect box;
        };
        vector<Hole> holes;
        vector<vector<bool>> seen(rows(), vector<bool>(columns()));
        constexpr int dx[] = {1, -1, 0, 0}, dy[] = {0, 0, 1, -1};
        for (int j = 0; j < rows(); ++j) for (int i = 0; i < columns(); ++i) {
            if (counts[j][i] || seen[j][i]) continue;
            Hole hole{xs[i], ys[j], 0, {"", "", xs[i], ys[j], xs[i + 1], ys[j + 1]}};
            bool outside = false;
            queue<pair<int, int>> pending;
            pending.push({i, j});
            seen[j][i] = true;
            while (!pending.empty()) {
                auto [x, y] = pending.front();
                pending.pop();
                outside = outside || x == 0 || y == 0 || x + 1 == columns() || y + 1 == rows();
                hole.area += i64(xs[x + 1] - xs[x]) * (ys[y + 1] - ys[y]);
                hole.box.x1 = min(hole.box.x1, xs[x]);
                hole.box.y1 = min(hole.box.y1, ys[y]);
                hole.box.x2 = max(hole.box.x2, xs[x + 1]);
                hole.box.y2 = max(hole.box.y2, ys[y + 1]);
                if (make_pair(ys[y], xs[x]) < make_pair(hole.anchor_y, hole.anchor_x)) {
                    hole.anchor_x = xs[x];
                    hole.anchor_y = ys[y];
                }
                for (int d = 0; d < 4; ++d) {
                    int nx = x + dx[d], ny = y + dy[d];
                    if (nx >= 0 && nx < columns() && ny >= 0 && ny < rows() &&
                        !counts[ny][nx] && !seen[ny][nx]) {
                        seen[ny][nx] = true;
                        pending.push({nx, ny});
                    }
                }
            }
            if (!outside) holes.push_back(hole);
        }
        sort(holes.begin(), holes.end(), [](const Hole& a, const Hole& b) {
            return tie(a.anchor_y, a.anchor_x) < tie(b.anchor_y, b.anchor_x);
        });
        cout << "holes " << layer << ": " << holes.size() << '\n';
        for (size_t i = 0; i < holes.size(); ++i)
            cout << "hole " << i + 1 << ": area " << holes[i].area << ", bbox " << holes[i].box.text() << '\n';
    }
    void merge(const string& layer) const {
        map<pair<int, int>, int> active;
        vector<Rect> pieces;
        for (int j = 0; j <= rows(); ++j) {
            set<pair<int, int>> runs;
            if (j < rows()) for (int i = 0; i < columns();) {
                if (!counts[j][i]) {
                    ++i;
                    continue;
                }
                int l = i;
                while (i < columns() && counts[j][i]) ++i;
                runs.insert({xs[l], xs[i]});
            }
            for (auto it = active.begin(); it != active.end();) {
                if (!runs.count(it->first)) {
                    pieces.push_back({"", "", it->first.first, it->second, it->first.second, ys[j]});
                    it = active.erase(it);
                } else ++it;
            }
            for (const auto& run : runs) if (!active.count(run)) active[run] = ys[j];
        }
        sort(pieces.begin(), pieces.end(), [](const Rect& a, const Rect& b) {
            return tie(a.y1, a.x1) < tie(b.y1, b.x1);
        });
        cout << "merge " << layer << ": " << pieces.size() << " pieces\n";
        for (const auto& r : pieces) cout << r.text() << '\n';
    }
};

vector<vector<Rect>> nets(const vector<Rect>& rectangles) {
    vector<vector<Rect>> result;
    vector<bool> seen(rectangles.size());
    for (size_t start = 0; start < rectangles.size(); ++start) if (!seen[start]) {
        vector<Rect> component;
        queue<size_t> pending;
        pending.push(start);
        seen[start] = true;
        while (!pending.empty()) {
            size_t u = pending.front();
            pending.pop();
            component.push_back(rectangles[u]);
            for (size_t v = 0; v < rectangles.size(); ++v)
                if (!seen[v] && relation(rectangles[u], rectangles[v]) <= 1) {
                    seen[v] = true;
                    pending.push(v);
                }
        }
        sort(component.begin(), component.end(), [](const Rect& a, const Rect& b) {
            return a.name < b.name;
        });
        result.push_back(component);
    }
    return result;
}
vector<string> spacing(const vector<Rect>& rectangles, int distance) {
    vector<tuple<int, string, string, string>> violations;
    for (size_t i = 0; i < rectangles.size(); ++i) for (size_t j = i + 1; j < rectangles.size(); ++j) {
        const auto& a = rectangles[i];
        const auto& b = rectangles[j];
        int kind = relation(a, b), g = gap(a, b);
        if (kind != 2 && !(kind == 3 && g < distance)) continue;
        Rect r = common(a, b);
        string direction = kind == 2 ? "corner" : r.width() < 0 && r.height() < 0 ?
                           "diagonal" : r.width() < 0 ? "x" : "y";
        violations.emplace_back(g, a.name, b.name, direction);
    }
    sort(violations.begin(), violations.end());
    vector<string> result;
    for (const auto& [g, a, b, d] : violations) result.push_back(a + " " + b + " gap " + to_string(g) + " " + d);
    return result;
}

class Layout {
    map<string, Rect> rectangles;
    vector<pair<map<string, Rect>, string>> history;
    map<tuple<int, string, string>, int> rules;

    Rect get(const string& name) const {
        auto it = rectangles.find(name);
        require(it != rectangles.end(), "unknown rectangle " + name);
        return it->second;
    }
    vector<Rect> on_layer(const string& layer, bool needed = true) const {
        vector<Rect> result;
        for (const auto& [name, r] : rectangles) if (r.layer == layer) result.push_back(r);
        require(!needed || !result.empty(), "no rectangles on " + layer);
        return result;
    }
    void remember(const string& line) {
        history.push_back({rectangles, line});
    }
    static string describe(const Rect& r) {
        return r.name + " " + r.layer + " " + r.text() + " " + to_string(r.width()) + "x" + to_string(r.height());
    }
public:
    void command(const string& line) {
        istringstream input(line);
        string op;
        input >> op;
        if (op == "ADD") {
            Rect r;
            input >> r.name >> r.layer >> r.x1 >> r.y1 >> r.x2 >> r.y2;
            require(!rectangles.count(r.name), "duplicate rectangle " + r.name);
            require(r.x1 < r.x2 && r.y1 < r.y2, "invalid rectangle");
            bounded(r);
            remember(line);
            rectangles[r.name] = r;
            cout << "added " << r.name << ' ' << r.layer << ' ' << r.text() << '\n';
        } else if (op == "COPY" || op == "MOVE" || op == "RESIZE" || op == "SPLIT" || op == "LAYER" || op == "DELETE") {
            string name;
            input >> name;
            Rect r = get(name);
            if (op == "COPY") {
                string target;
                int dx, dy;
                input >> target >> dx >> dy;
                require(!rectangles.count(target), "duplicate rectangle " + target);
                r.name = target;
                r.x1 += dx;
                r.x2 += dx;
                r.y1 += dy;
                r.y2 += dy;
                bounded(r);
                remember(line);
                rectangles[target] = r;
                cout << "copied " << name << " to " << target << ' ' << r.text() << '\n';
            } else if (op == "MOVE" || op == "RESIZE") {
                int a, b;
                input >> a >> b;
                if (op == "MOVE") {
                    r.x1 += a;
                    r.x2 += a;
                    r.y1 += b;
                    r.y2 += b;
                }
                else {
                    require(a > 0 && b > 0, "invalid size");
                    r.x2 = r.x1 + a;
                    r.y2 = r.y1 + b;
                }
                bounded(r);
                remember(line);
                rectangles[name] = r;
                cout << (op == "MOVE" ? "moved " : "resized ") << name << " to " << r.text() << '\n';
            } else if (op == "SPLIT") {
                string axis, target;
                int position;
                input >> axis >> position >> target;
                require(!rectangles.count(target), "duplicate rectangle " + target);
                require(axis == "x" ? r.x1 < position && position < r.x2 : r.y1 < position && position < r.y2,
                        "cut outside " + name);
                Rect other = r;
                other.name = target;
                if (axis == "x") {
                    r.x2 = position;
                    other.x1 = position;
                }
                else {
                    r.y2 = position;
                    other.y1 = position;
                }
                remember(line);
                rectangles[name] = r;
                rectangles[target] = other;
                cout << "split " << name << " at " << axis << '=' << position << ": " << name << ' ' << r.text()
                     << ", " << target << ' ' << other.text() << '\n';
            } else if (op == "LAYER") {
                string layer;
                input >> layer;
                require(r.layer != layer, "already on " + layer);
                string old = r.layer;
                r.layer = layer;
                remember(line);
                rectangles[name] = r;
                cout << "layer " << name << ' ' << old << " -> " << layer << '\n';
            } else {
                remember(line);
                rectangles.erase(name);
                cout << "deleted " << name << '\n';
            }
        } else if (op == "UNDO") {
            require(!history.empty(), "nothing to undo");
            auto previous = move(history.back());
            history.pop_back();
            rectangles = move(previous.first);
            cout << "undo: " << previous.second << '\n';
        } else if (op == "LIST") {
            cout << "rectangles: " << rectangles.size() << '\n';
            for (const auto& [name, r] : rectangles) cout << describe(r) << '\n';
        } else if (op == "INFO") {
            string name;
            input >> name;
            Rect a = get(name);
            cout << describe(a) << " area " << a.area() << '\n';
            array<vector<string>, 5> lists;
            for (const auto& [other, b] : rectangles) if (other != name) {
                int kind = relation(a, b);
                if (a.layer == b.layer && kind < 3) lists[kind].push_back(other);
                if (min_margin(a, b) >= 0) lists[3].push_back(other);
                if (min_margin(b, a) >= 0) lists[4].push_back(other);
            }
            const string labels[] = {"overlaps", "touches", "corners", "encloses", "enclosed by"};
            for (int i = 0; i < 5; ++i) cout << labels[i] << ": " << (lists[i].empty() ? "none" : joined(lists[i])) << '\n';
        } else if (op == "LAYERS") {
            set<string> layers;
            for (const auto& [name, r] : rectangles) layers.insert(r.layer);
            cout << "layers: " << layers.size() << '\n';
            for (const auto& layer : layers) {
                auto values = on_layer(layer);
                cout << layer << ": " << values.size() << " rectangles, area " << Grid(values).area()
                     << ", nets " << nets(values).size() << '\n';
            }
        } else if (op == "OVERLAPS") {
            string layer;
            bool filtered = bool(input >> layer);
            if (filtered) on_layer(layer);
            vector<tuple<string, string, string, Rect>> pairs;
            for (auto a = rectangles.begin(); a != rectangles.end(); ++a)
                for (auto b = next(a); b != rectangles.end(); ++b)
                    if (a->second.layer == b->second.layer && (!filtered || a->second.layer == layer) &&
                        relation(a->second, b->second) == 0)
                        pairs.emplace_back(a->second.layer, a->first, b->first, common(a->second, b->second));
            sort(pairs.begin(), pairs.end(), [](const auto& a, const auto& b) {
                return tie(std::get<0>(a), std::get<1>(a), std::get<2>(a)) < tie(std::get<0>(b), std::get<1>(b), std::get<2>(b));
            });
            cout << "overlaps " << (filtered ? layer : "all layers") << ": " << pairs.size() << '\n';
            for (const auto& [l, a, b, r] : pairs) {
                if (!filtered) cout << l << ' ';
                cout << a << ' ' << b << ' ' << r.text() << " area " << r.area() << '\n';
            }
        } else if (op == "INTERSECT" || op == "ADJACENT" || op == "ENCLOSE" || op == "PATH") {
            string first, second;
            input >> first >> second;
            Rect a = get(first), b = get(second);
            require(first != second, "same rectangle " + first);
            if (op == "PATH") require(a.layer == b.layer, "different layers");
            Rect r = common(a, b);
            int kind = relation(a, b);
            string heading = op == "INTERSECT" ? "intersect" : op == "ADJACENT" ? "adjacent" : op == "ENCLOSE" ? "enclose" : "path";
            cout << heading << ' ' << first << ' ' << second << ": ";
            if (op == "INTERSECT") {
                if (kind == 0) cout << r.text() << " area " << r.area();
                else if (kind == 1) cout << "segment " << r.text() << " length " << r.width() + r.height();
                else if (kind == 2) cout << "point " << point(r.x1, r.y1);
                else cout << "none, gap " << gap(a, b);
            } else if (op == "ADJACENT") {
                if (kind == 0) cout << "overlapping";
                else if (kind == 1) {
                    string direction = r.width() == 0 ? (a.x2 == r.x1 ? "west" : "east") : (a.y2 == r.y1 ? "south" : "north");
                    cout << first << " is " << direction << " of " << second << ", edge " << r.text() << ", length " << r.width() + r.height();
                } else if (kind == 2) cout << "corner only at " << point(r.x1, r.y1);
                else cout << "not adjacent";
            } else if (op == "ENCLOSE") {
                auto m = margins(a, b);
                int least = *min_element(m.begin(), m.end());
                cout << (least >= 0 ? "yes" : "no") << ", margins left " << m[0] << " bottom " << m[1] << " right " << m[2] << " top " << m[3];
                if (least >= 0) cout << ", min " << least;
            } else {
                map<string, string> previous{{first, ""}};
                queue<string> pending;
                pending.push(first);
                auto values = on_layer(a.layer);
                while (!pending.empty() && !previous.count(second)) {
                    string current = pending.front();
                    pending.pop();
                    for (const Rect& neighbor : values)
                        if (!previous.count(neighbor.name) && relation(get(current), neighbor) <= 1) {
                            previous[neighbor.name] = current;
                            pending.push(neighbor.name);
                        }
                }
                if (!previous.count(second)) cout << "none";
                else {
                    vector<string> path;
                    for (string p = second; !p.empty(); p = previous[p]) path.push_back(p);
                    reverse(path.begin(), path.end());
                    cout << joined(path, " -> ") << " (" << path.size() - 1 << " steps)";
                }
            }
            cout << '\n';
        } else if (op == "AT") {
            int x, y;
            input >> x >> y;
            vector<string> found;
            for (const auto& [name, r] : rectangles) if (r.x1 <= x && x <= r.x2 && r.y1 <= y && y <= r.y2) {
                int borders = int(x == r.x1 || x == r.x2) + int(y == r.y1 || y == r.y2);
                found.push_back(name + " " + r.layer + " " + (borders == 2 ? "corner" : borders == 1 ? "edge" : "inside"));
            }
            cout << "at " << point(x, y) << ": " << (found.empty() ? "none" : joined(found, ", ")) << '\n';
        } else if (op == "NEAREST") {
            string name;
            input >> name;
            Rect a = get(name);
            string best;
            int distance = 0;
            for (const auto& [other, b] : rectangles) if (other != name && b.layer == a.layer) {
                int d = gap(a, b);
                if (best.empty() || d < distance) {
                    best = other;
                    distance = d;
                }
            }
            cout << "nearest " << name << ": " << (best.empty() ? "none" : best + " gap " + to_string(distance)) << '\n';
        } else if (op == "RULE") {
            string kind, inner, outer;
            int value;
            input >> kind >> inner;
            if (kind == "ENCLOSE") {
                input >> outer >> value;
                require(inner != outer, "same layer " + inner);
                rules[{0, inner, outer}] = value;
                cout << "rule enclose " << inner << ' ' << outer << ' ' << value << '\n';
            } else {
                input >> value;
                rules[{kind == "SPACING" ? 1 : 2, inner, ""}] = value;
                cout << "rule " << (kind == "SPACING" ? "spacing" : "width") << ' ' << inner << ' ' << value << '\n';
            }
        } else if (op == "CHECK") {
            require(!rules.empty(), "no rules");
            size_t total = 0;
            for (const auto& [key, value] : rules) {
                const auto& [kind, inner, outer] = key;
                vector<string> violations;
                auto values = on_layer(inner, false);
                string heading;
                if (kind == 0) {
                    auto containers = on_layer(outer, false);
                    for (const auto& r : values) {
                        int best = -100000;
                        for (const auto& container : containers) best = max(best, min_margin(container, r));
                        if (containers.empty() || best < value)
                            violations.push_back(r.name + " best margin " + (containers.empty() ? "none" : to_string(best)));
                    }
                    heading = "enclose " + inner + " " + outer;
                } else if (kind == 1) {
                    violations = spacing(values, value);
                    heading = "spacing " + inner;
                } else {
                    for (const auto& r : values) if (min(r.width(), r.height()) < value)
                        violations.push_back(r.name + " width " + to_string(min(r.width(), r.height())));
                    heading = "width " + inner;
                }
                cout << heading << ' ' << value << ": " << violations.size() << " violations\n";
                for (const auto& violation : violations) cout << violation << '\n';
                total += violations.size();
            }
            cout << "check: " << total << " violations in " << rules.size() << " rules\n";
        } else {
            int threshold = 1;
            string layer;
            if (op == "COVER") input >> threshold;
            input >> layer;
            auto values = on_layer(layer);
            Grid grid(values);
            if (op == "AREA" || op == "COVER" || op == "PERIMETER") {
                if (op == "AREA") cout << "area " << layer << ": " << grid.area() << '\n';
                else if (op == "COVER") cout << "cover " << layer << " >= " << threshold << ": " << grid.area(threshold) << '\n';
                else cout << "perimeter " << layer << ": " << grid.perimeter() << '\n';
            } else if (op == "NETS") {
                auto components = nets(values);
                cout << "nets " << layer << ": " << components.size() << '\n';
                for (size_t i = 0; i < components.size(); ++i) {
                    vector<string> names;
                    for (const auto& r : components[i]) names.push_back(r.name);
                    cout << "net " << i + 1 << ": " << joined(names) << " area " << Grid(components[i]).area() << '\n';
                }
            } else if (op == "DRC") {
                int distance;
                input >> distance;
                auto violations = spacing(values, distance);
                cout << "drc " << layer << " spacing " << distance << ": " << violations.size() << " violations\n";
                for (const auto& violation : violations) cout << violation << '\n';
            } else if (op == "BBOX") {
                Rect b = grid.bounds();
                cout << "bbox " << layer << ": " << b.text() << ' ' << b.width() << 'x' << b.height()
                     << ", " << values.size() << " rectangles, density " << decimal(100 * grid.area(), b.area()) << "%\n";
            } else if (op == "DENSITY") {
                int w;
                input >> w;
                Rect b = grid.bounds();
                int c = (b.width() + w - 1) / w, r = (b.height() + w - 1) / w;
                require(c <= 20 && r <= 20, "too many windows");
                vector<vector<i64>> areas(r, vector<i64>(c));
                pair<int, int> least{0, 0}, most{0, 0};
                for (int j = 0; j < r; ++j) for (int i = 0; i < c; ++i) {
                    Rect tile{"", "", b.x1 + i * w, b.y1 + j * w, b.x1 + (i + 1) * w, b.y1 + (j + 1) * w};
                    areas[j][i] = grid.clipped_area(tile);
                    if (areas[j][i] < areas[least.second][least.first]) least = {i, j};
                    if (areas[j][i] > areas[most.second][most.first]) most = {i, j};
                }
                cout << "density " << layer << " window " << w << ": " << c << 'x' << r << '\n';
                for (int j = r - 1; j >= 0; --j) {
                    for (int i = 0; i < c; ++i) cout << (i ? " " : "") << 100 * areas[j][i] / (i64(w) * w);
                    cout << '\n';
                }
                for (const auto& [label, location] : vector<pair<string, pair<int, int>>>{{"min", least}, {"max", most}}) {
                    auto [i, j] = location;
                    cout << label << ' ' << decimal(100 * areas[j][i], i64(w) * w) << "% at " << point(b.x1 + i * w, b.y1 + j * w) << '\n';
                }
            } else if (op == "RENDER") {
                Rect window;
                input >> window.x1 >> window.y1 >> window.x2 >> window.y2;
                require(window.x1 < window.x2 && window.y1 < window.y2, "invalid window");
                require(window.width() <= 60 && window.height() <= 40, "window too large");
                cout << "render " << layer << ' ' << window.text() << '\n';
                for (int y = window.y2 - 1; y >= window.y1; --y) {
                    for (int x = window.x1; x < window.x2; ++x) {
                        int count = 0;
                        for (const auto& r : values) count += r.x1 <= x && x < r.x2 && r.y1 <= y && y < r.y2;
                        cout << (count == 0 ? '.' : count < 10 ? char('0' + count) : '*');
                    }
                    cout << '\n';
                }
            } else if (op == "EMPTY") grid.empty_rectangle(layer);
            else if (op == "HOLES") grid.holes(layer);
            else if (op == "MERGE") grid.merge(layer);
        }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    string line;
    getline(cin, line);
    Layout layout;
    while (n-- && getline(cin, line)) {
        try {
            layout.command(line);
        }
        catch (const runtime_error& error) {
            cout << "error: " << error.what() << '\n';
        }
    }
}
