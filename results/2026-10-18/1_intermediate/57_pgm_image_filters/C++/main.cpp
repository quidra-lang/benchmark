#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <map>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>
#include <iomanip>

using namespace std;

struct CommandError : runtime_error {
    using runtime_error::runtime_error;
};

void require(bool condition, const string& reason = "bad value") {
    if (!condition) throw CommandError(reason);
}

int clamp(int value, int low, int high) {
    return min(max(value, low), high);
}

int floor_divide(int numerator, int divisor) {
    int q = numerator / divisor;
    return numerator < 0 && numerator % divisor ? q - 1 : q;
}

string number(int n) { return to_string(n); }

bool digit_word(const string& s) {
    return !s.empty() && all_of(s.begin(), s.end(), [](char c) {
        return c >= '0' && c <= '9';
    });
}

bool integer_word(const string& word) {
    if (word == "0") return true;
    size_t start = !word.empty() && word[0] == '-' ? 1 : 0;
    size_t length = word.size() - start;
    if (length == 0 || length > 7 || word[start] == '0') return false;
    return all_of(word.begin() + start, word.end(), [](char c) {
        return c >= '0' && c <= '9';
    });
}

bool name_word(const string& word) {
    return !word.empty() && word.size() <= 8 &&
           all_of(word.begin(), word.end(), [](char c) {
               return c >= 'a' && c <= 'z';
           });
}

bool within_limit(initializer_list<int> values) {
    return all_of(values.begin(), values.end(), [](int x) {
        return x >= -1000 && x <= 1000;
    });
}

struct Point {
    int x, y;
};

const array<Point, 4> directions4 = {{
    {0, -1}, {-1, 0}, {1, 0}, {0, 1}
}};

const array<Point, 8> directions8 = {{
    {-1, -1}, {0, -1}, {1, -1}, {-1, 0},
    {1, 0}, {-1, 1}, {0, 1}, {1, 1}
}};

struct Image {
    int width, height, maxval;
    vector<int> pixels;

    int get(int x, int y) const { return pixels[y * width + x]; }
    bool contains(int x, int y) const {
        return x >= 0 && y >= 0 && x < width && y < height;
    }
    int clamp_pixel(int value) const { return clamp(value, 0, maxval); }

    string summary() const {
        long long checksum = 0;
        for (size_t i = 0; i < pixels.size(); ++i)
            checksum += static_cast<long long>(i + 1) * pixels[i];
        return number(width) + "x" + number(height) + " maxval " +
               number(maxval) + " checksum " + to_string(checksum);
    }

    array<int, 9> neighborhood(int x, int y) const {
        array<int, 9> q;
        int i = 0;
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx)
                q[i++] = get(clamp(x + dx, 0, width - 1),
                             clamp(y + dy, 0, height - 1));
        return q;
    }
};

template <typename F>
Image transformed(const Image& image, int width, int height, F sample) {
    Image result{width, height, image.maxval,
                 vector<int>(static_cast<size_t>(width) * height)};
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x)
            result.pixels[y * width + x] = sample(x, y);
    return result;
}

template <typename F>
Image mapped(const Image& image, F transform) {
    Image result = image;
    for (int& value : result.pixels) value = transform(value);
    return result;
}

Image cropped(const Image& image, int x, int y, int width, int height) {
    return transformed(image, width, height, [&](int i, int j) {
        return image.get(x + i, y + j);
    });
}

Image translated(const Image& image, int width, int height,
                 int dx, int dy, int fill) {
    return transformed(image, width, height, [&](int x, int y) {
        return image.contains(x - dx, y - dy) ? image.get(x - dx, y - dy) : fill;
    });
}

Image convolved(const Image& image, const array<int, 9>& kernel, int divisor) {
    return transformed(image, image.width, image.height, [&](int x, int y) {
        auto q = image.neighborhood(x, y);
        int value = 0;
        for (int i = 0; i < 9; ++i) value += q[i] * kernel[i];
        return image.clamp_pixel(floor_divide(value, divisor));
    });
}

Image rank_filtered(const Image& image, int rank) {
    return transformed(image, image.width, image.height, [&](int x, int y) {
        auto q = image.neighborhood(x, y);
        sort(q.begin(), q.end());
        return q[rank];
    });
}

Image sobel(const Image& image) {
    return transformed(image, image.width, image.height, [&](int x, int y) {
        auto q = image.neighborhood(x, y);
        int gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
        int gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
        return image.clamp_pixel(abs(gx) + abs(gy));
    });
}

vector<Point> line_points(int x0, int y0, int x1, int y1) {
    int dx = abs(x1 - x0), dy = -abs(y1 - y0);
    int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    int error = dx + dy, x = x0, y = y0;
    vector<Point> result;
    while (true) {
        result.push_back({x, y});
        if (x == x1 && y == y1) break;
        int twice = 2 * error;
        if (twice >= dy) { error += dy; x += sx; }
        if (twice <= dx) { error += dx; y += sy; }
    }
    return result;
}

vector<Point> rectangle_points(const Image& image, int left, int top,
                               int width, int height, bool fill) {
    int right = left + width - 1, bottom = top + height - 1;
    vector<Point> points;
    for (int y = max(0, top); y <= min(bottom, image.height - 1); ++y)
        for (int x = max(0, left); x <= min(right, image.width - 1); ++x)
            if (fill || x == left || x == right || y == top || y == bottom)
                points.push_back({x, y});
    return points;
}

vector<Point> circle_points(int cx, int cy, int radius) {
    int a = radius, b = 0, error = 1 - radius;
    vector<Point> points;
    while (a >= b) {
        points.insert(points.end(), {
            {cx + a, cy + b}, {cx + b, cy + a},
            {cx - b, cy + a}, {cx - a, cy + b},
            {cx - a, cy - b}, {cx - b, cy - a},
            {cx + b, cy - a}, {cx + a, cy - b}
        });
        ++b;
        if (error < 0) error += 2 * b + 1;
        else { --a; error += 2 * (b - a) + 1; }
    }
    return points;
}

vector<Point> disc_points(const Image& image, const vector<Point>& outline) {
    map<int, pair<int, int>> rows;
    for (auto [x, y] : outline) {
        auto found = rows.find(y);
        if (found == rows.end()) rows.emplace(y, make_pair(x, x));
        else {
            found->second.first = min(found->second.first, x);
            found->second.second = max(found->second.second, x);
        }
    }
    vector<Point> result;
    for (const auto& [y, limits] : rows) {
        if (y < 0 || y >= image.height) continue;
        for (int x = max(0, limits.first);
             x <= min(image.width - 1, limits.second); ++x)
            result.push_back({x, y});
    }
    return result;
}

vector<Point> flood_points(const Image& image, int x, int y) {
    int target = image.get(x, y);
    vector<Point> stack = {{x, y}}, result;
    vector<bool> seen(image.pixels.size());
    seen[y * image.width + x] = true;
    while (!stack.empty()) {
        Point p = stack.back();
        stack.pop_back();
        result.push_back(p);
        for (Point d : directions4) {
            int nx = p.x + d.x, ny = p.y + d.y;
            if (!image.contains(nx, ny) || image.get(nx, ny) != target) continue;
            int index = ny * image.width + nx;
            if (!seen[index]) {
                seen[index] = true;
                stack.push_back({nx, ny});
            }
        }
    }
    return result;
}

Image equalized(const Image& image) {
    vector<int> counts(image.maxval + 1);
    for (int value : image.pixels) ++counts[value];
    vector<int> cdf(counts.size());
    partial_sum(counts.begin(), counts.end(), cdf.begin());
    int first = cdf[*min_element(image.pixels.begin(), image.pixels.end())];
    int total = static_cast<int>(image.pixels.size());
    if (first == total) return image;
    int span = total - first;
    return mapped(image, [&](int p) {
        return (2 * (cdf[p] - first) * image.maxval + span) / (2 * span);
    });
}

vector<vector<Point>> components(const Image& image, int threshold) {
    vector<bool> visited(image.pixels.size());
    vector<vector<Point>> groups;
    for (int start = 0; start < static_cast<int>(image.pixels.size()); ++start) {
        if (visited[start] || image.pixels[start] < threshold) continue;
        visited[start] = true;
        vector<Point> stack = {{start % image.width, start / image.width}};
        vector<Point> group;
        while (!stack.empty()) {
            Point p = stack.back();
            stack.pop_back();
            group.push_back(p);
            for (Point d : directions8) {
                int nx = p.x + d.x, ny = p.y + d.y;
                if (!image.contains(nx, ny)) continue;
                int index = ny * image.width + nx;
                if (!visited[index] && image.pixels[index] >= threshold) {
                    visited[index] = true;
                    stack.push_back({nx, ny});
                }
            }
        }
        groups.push_back(move(group));
    }
    return groups;
}

string component_text(const Image& image, int threshold, const vector<Point>& group) {
    int left = group[0].x, right = group[0].x;
    int top = group[0].y, bottom = group[0].y;
    int sum_x = 0, sum_y = 0, perimeter = 0;
    for (Point p : group) {
        left = min(left, p.x); right = max(right, p.x);
        top = min(top, p.y); bottom = max(bottom, p.y);
        sum_x += p.x; sum_y += p.y;
        for (Point d : directions4)
            if (!image.contains(p.x + d.x, p.y + d.y) ||
                image.get(p.x + d.x, p.y + d.y) < threshold) {
                ++perimeter;
                break;
            }
    }
    int area = static_cast<int>(group.size());
    return "area " + number(area) + " perimeter " + number(perimeter) +
           " box " + number(left) + " " + number(top) + " " +
           number(right) + " " + number(bottom) + " center " +
           number(sum_x / area) + " " + number(sum_y / area);
}

Image distance_map(const Image& image, int threshold) {
    if (all_of(image.pixels.begin(), image.pixels.end(),
               [&](int p) { return p >= threshold; })) {
        Image result = image;
        fill(result.pixels.begin(), result.pixels.end(), image.maxval);
        return result;
    }
    int width = image.width, height = image.height;
    vector<int> distances(image.pixels.size());
    for (size_t i = 0; i < distances.size(); ++i)
        distances[i] = image.pixels[i] < threshold ? 0 : width + height;

    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            if (x > 0) distances[index] = min(distances[index], distances[index - 1] + 1);
            if (y > 0) distances[index] = min(distances[index], distances[index - width] + 1);
        }

    for (int y = height - 1; y >= 0; --y)
        for (int x = width - 1; x >= 0; --x) {
            int index = y * width + x;
            if (x < width - 1) distances[index] = min(distances[index], distances[index + 1] + 1);
            if (y < height - 1) distances[index] = min(distances[index], distances[index + width] + 1);
        }

    Image result = image;
    for (size_t i = 0; i < distances.size(); ++i)
        result.pixels[i] = min(distances[i], image.maxval);
    return result;
}

string statistics(const vector<int>& values, int maxval) {
    vector<int> sorted = values;
    sort(sorted.begin(), sorted.end());
    vector<int> counts(maxval + 1);
    long long sum = 0;
    for (int value : values) { ++counts[value]; sum += value; }
    int mode = 0;
    for (int i = 1; i <= maxval; ++i)
        if (counts[i] > counts[mode]) mode = i;
    int size = static_cast<int>(values.size());
    return "min " + number(sorted.front()) + " max " + number(sorted.back()) +
           " mean " + number(static_cast<int>(sum / size)) +
           " median " + number(sorted[(size - 1) / 2]) +
           " mode " + number(mode);
}

Image dithered(const Image& image) {
    vector<int> errors = image.pixels, pixels(errors.size());
    const array<array<int, 3>, 4> neighbors = {{
        {{1, 0, 7}}, {{-1, 1, 3}}, {{0, 1, 5}}, {{1, 1, 1}}
    }};
    for (int y = 0; y < image.height; ++y) {
        for (int x = 0; x < image.width; ++x) {
            int index = y * image.width + x;
            int old = errors[index];
            int value = 2 * old >= image.maxval ? image.maxval : 0;
            pixels[index] = value;
            int error = old - value;
            for (const auto& n : neighbors) {
                int nx = x + n[0], ny = y + n[1];
                if (image.contains(nx, ny))
                    errors[ny * image.width + nx] += floor_divide(error * n[2], 16);
            }
        }
    }
    Image result = image;
    result.pixels = move(pixels);
    return result;
}

Image parse_pgm(const vector<string>& lines) {
    vector<string> words;
    for (const string& line : lines) {
        istringstream input(line.substr(0, line.find('#')));
        string word;
        while (input >> word) words.push_back(word);
    }
    require(!words.empty() && words[0] == "P2", "bad magic");

    auto header = [&](int position, int limit, const string& reason) {
        require(position < static_cast<int>(words.size()), "truncated header");
        require(digit_word(words[position]), "bad number");
        int value = stoi(words[position]);
        require(value >= 1 && value <= limit, reason);
        return value;
    };

    int width = header(1, 64, "bad size");
    int height = header(2, 64, "bad size");
    int maxval = header(3, 255, "bad maxval");
    int count = static_cast<int>(words.size()) - 4;
    vector<int> pixels;
    pixels.reserve(width * height);
    for (int i = 0; i < width * height; ++i) {
        int x = i % width, y = i / width;
        require(i < count, "too few pixels (" + number(count) +
                           " of " + number(width * height) + ")");
        const string& word = words[i + 4];
        require(digit_word(word), "bad pixel at " + number(x) + "," + number(y));
        int value = stoi(word);
        require(value <= maxval, "pixel out of range at " + number(x) + "," + number(y));
        pixels.push_back(value);
    }
    require(count <= width * height, "too many pixels (" + number(count) +
                                    " of " + number(width * height) + ")");
    return {width, height, maxval, move(pixels)};
}

struct Command {
    string name;
    vector<int> arguments;
    string slot;
    bool fill;
};

class Editor {
    const unordered_map<string, string> patterns = {
        {"NEW", "iiii"}, {"OUTPUT", ""}, {"INVERT", ""},
        {"BRIGHTNESS", "i"}, {"CONTRAST", "ii"}, {"THRESHOLD", "i"},
        {"LEVELS", "ii"}, {"POSTERIZE", "i"}, {"MAXVAL", "i"},
        {"FLIPH", ""}, {"FLIPV", ""}, {"ROTATE", "i"},
        {"CROP", "iiii"}, {"PAD", "ii"}, {"SCALE", "ii"},
        {"SHIFT", "iii"}, {"TILE", "ii"}, {"BLUR", ""},
        {"GAUSS", ""}, {"SHARPEN", ""}, {"CONVOLVE", "iiiiiiiiii"},
        {"SOBEL", ""}, {"MEDIAN", ""}, {"ERODE", ""}, {"DILATE", ""},
        {"OPEN", ""}, {"CLOSE", ""}, {"GRADIENT", ""},
        {"LINE", "iiiii"}, {"RECT", "iiiii"}, {"CIRCLE", "iiii"},
        {"FLOOD", "iii"}, {"HISTOGRAM", ""}, {"EQUALIZE", ""},
        {"LABEL", "i"}, {"DISTANCE", "i"}, {"STATS", ""},
        {"REGION", "iiii"}, {"DITHER", ""}, {"ASCIIART", ""},
        {"STORE", "n"}, {"RECALL", "n"}, {"DROP", "n"},
        {"BLEND", "nii"}, {"DIFF", "n"}, {"PASTE", "nii"},
        {"SLOTS", ""}, {"INFO", ""}, {"UNDO", ""}, {"REDO", ""}
    };
    const unordered_set<string> imageless = {
        "NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO"
    };
    const unordered_set<string> needs_slot = {
        "RECALL", "DROP", "BLEND", "DIFF", "PASTE"
    };
    const unordered_map<string, pair<array<int, 9>, int>> kernels = {
        {"BLUR", {{{1, 1, 1, 1, 1, 1, 1, 1, 1}}, 9}},
        {"GAUSS", {{{1, 2, 1, 2, 4, 2, 1, 2, 1}}, 16}},
        {"SHARPEN", {{{0, -1, 0, -1, 5, -1, 0, -1, 0}}, 1}}
    };

    bool has_image = false;
    Image current = {};
    vector<Image> undo, redo;
    map<string, Image> slots;
    vector<string> output;

    void emit(const string& line) { output.push_back(line); }

    Command parse(const vector<string>& words) const {
        const string& name = words[0];
        auto it = patterns.find(name);
        require(it != patterns.end(), "unknown command " + name);
        const string& pattern = it->second;
        vector<string> given(words.begin() + 1, words.end());
        bool fill = (name == "RECT" || name == "CIRCLE") &&
                    given.size() == pattern.size() + 1 && given.back() == "FILL";
        if (fill) given.pop_back();
        require(given.size() == pattern.size(), "bad arguments");
        vector<int> values;
        string slot;
        for (size_t i = 0; i < given.size(); ++i) {
            if (pattern[i] == 'i') {
                require(integer_word(given[i]), "bad arguments");
                values.push_back(stoi(given[i]));
            } else {
                require(name_word(given[i]), "bad arguments");
                slot = given[i];
            }
        }
        return {name, move(values), slot, fill};
    }

    void replace(Image image, const string& label) {
        current = move(image);
        has_image = true;
        undo.clear();
        redo.clear();
        emit(label + " " + current.summary());
    }

    void commit(Image image, int painted = -1) {
        undo.push_back(current);
        redo.clear();
        current = move(image);
        emit("ok " + current.summary() +
             (painted < 0 ? "" : " painted " + number(painted)));
    }

    void paint(const vector<Point>& points, int value) {
        vector<bool> painted(current.pixels.size());
        int count = 0;
        for (Point p : points) {
            if (!current.contains(p.x, p.y)) continue;
            int index = p.y * current.width + p.x;
            if (!painted[index]) { painted[index] = true; ++count; }
        }
        Image result = current;
        for (size_t i = 0; i < painted.size(); ++i)
            if (painted[i]) result.pixels[i] = value;
        commit(move(result), count);
    }

    void checked_crop(const vector<int>& a) const {
        require(a[0] >= 0 && a[1] >= 0 && a[2] >= 1 && a[3] >= 1);
        require(a[0] + a[2] <= current.width && a[1] + a[3] <= current.height);
    }

    const Image& matching_slot(const string& key) const {
        const Image& other = slots.at(key);
        require(other.width == current.width && other.height == current.height,
                "size mismatch");
        require(other.maxval == current.maxval, "maxval mismatch");
        return other;
    }

    void run(const Command& command) {
        const string& name = command.name;
        const vector<int>& a = command.arguments;
        const string& slot = command.slot;
        bool fill = command.fill;

        if (name == "NEW") {
            require(a[0] >= 1 && a[0] <= 64 && a[1] >= 1 && a[1] <= 64);
            require(a[2] >= 1 && a[2] <= 255 && a[3] >= 0 && a[3] <= a[2]);
            replace({a[0], a[1], a[2], vector<int>(a[0] * a[1], a[3])}, "created");
            return;
        }
        if (name == "RECALL") { replace(slots.at(slot), "recalled " + slot); return; }
        if (name == "DROP") { slots.erase(slot); emit("dropped " + slot); return; }
        if (name == "SLOTS") {
            if (slots.empty()) emit("no slots");
            for (const auto& [key, image] : slots) emit(key + " " + image.summary());
            return;
        }
        if (name == "INFO") {
            emit("image " + (has_image ? current.summary() : "none") +
                 " undo " + number(static_cast<int>(undo.size())) +
                 " redo " + number(static_cast<int>(redo.size())) +
                 " slots " + number(static_cast<int>(slots.size())));
            return;
        }
        if (name == "UNDO") {
            require(!undo.empty(), "nothing to undo");
            redo.push_back(current);
            current = move(undo.back());
            undo.pop_back();
            emit("undo " + current.summary());
            return;
        }
        if (name == "REDO") {
            require(!redo.empty(), "nothing to redo");
            undo.push_back(current);
            current = move(redo.back());
            redo.pop_back();
            emit("redo " + current.summary());
            return;
        }

        const Image& image = current;
        int w = image.width, h = image.height, m = image.maxval;
        if (name == "OUTPUT") {
            emit("P2");
            emit(number(w) + " " + number(h));
            emit(number(m));
            for (int y = 0; y < h; ++y) {
                ostringstream line;
                for (int x = 0; x < w; ++x) {
                    if (x) line << ' ';
                    line << image.get(x, y);
                }
                emit(line.str());
            }
        } else if (name == "INVERT") {
            commit(mapped(image, [&](int p) { return m - p; }));
        } else if (name == "BRIGHTNESS") {
            require(a[0] >= -255 && a[0] <= 255);
            commit(mapped(image, [&](int p) { return image.clamp_pixel(p + a[0]); }));
        } else if (name == "CONTRAST") {
            require(a[0] >= 0 && a[0] <= 100 && a[1] >= 1 && a[1] <= 100);
            int center = (m + 1) / 2;
            commit(mapped(image, [&](int p) {
                return image.clamp_pixel(center + floor_divide((p - center) * a[0], a[1]));
            }));
        } else if (name == "THRESHOLD") {
            require(a[0] >= 0 && a[0] <= m);
            commit(mapped(image, [&](int p) { return p >= a[0] ? m : 0; }));
        } else if (name == "LEVELS") {
            require(a[0] >= 0 && a[0] < a[1] && a[1] <= m);
            commit(mapped(image, [&](int p) {
                return image.clamp_pixel(floor_divide((p - a[0]) * m, a[1] - a[0]));
            }));
        } else if (name == "POSTERIZE") {
            require(a[0] >= 2 && a[0] <= m + 1);
            commit(mapped(image, [&](int p) {
                return (p * a[0] / (m + 1)) * m / (a[0] - 1);
            }));
        } else if (name == "MAXVAL") {
            require(a[0] >= 1 && a[0] <= 255);
            Image result = image;
            result.maxval = a[0];
            for (int& p : result.pixels) p = (2 * p * a[0] + m) / (2 * m);
            commit(move(result));
        } else if (name == "FLIPH") {
            commit(transformed(image, w, h, [&](int x, int y) {
                return image.get(w - 1 - x, y);
            }));
        } else if (name == "FLIPV") {
            commit(transformed(image, w, h, [&](int x, int y) {
                return image.get(x, h - 1 - y);
            }));
        } else if (name == "ROTATE") {
            require(a[0] == 90 || a[0] == 180 || a[0] == 270);
            if (a[0] == 90) commit(transformed(image, h, w, [&](int x, int y) {
                return image.get(y, h - 1 - x);
            }));
            else if (a[0] == 180) commit(transformed(image, w, h, [&](int x, int y) {
                return image.get(w - 1 - x, h - 1 - y);
            }));
            else commit(transformed(image, h, w, [&](int x, int y) {
                return image.get(w - 1 - y, x);
            }));
        } else if (name == "CROP") {
            checked_crop(a);
            commit(cropped(image, a[0], a[1], a[2], a[3]));
        } else if (name == "PAD") {
            require(a[0] >= 1 && a[1] >= 0 && a[1] <= m);
            require(w + 2 * a[0] <= 64 && h + 2 * a[0] <= 64, "too large");
            commit(translated(image, w + 2 * a[0], h + 2 * a[0], a[0], a[0], a[1]));
        } else if (name == "SCALE") {
            require(a[0] >= 1 && a[0] <= 16 && a[1] >= 1 && a[1] <= 16);
            int nw = w * a[0] / a[1], nh = h * a[0] / a[1];
            require(nw > 0 && nh > 0, "too small");
            require(nw <= 64 && nh <= 64, "too large");
            commit(transformed(image, nw, nh, [&](int x, int y) {
                return image.get((2 * x + 1) * a[1] / (2 * a[0]),
                                 (2 * y + 1) * a[1] / (2 * a[0]));
            }));
        } else if (name == "SHIFT") {
            require(within_limit({a[0], a[1]}) && a[2] >= 0 && a[2] <= m);
            commit(translated(image, w, h, a[0], a[1], a[2]));
        } else if (name == "TILE") {
            require(a[0] >= 1 && a[1] >= 1);
            require(w * a[0] <= 64 && h * a[1] <= 64, "too large");
            commit(transformed(image, w * a[0], h * a[1], [&](int x, int y) {
                return image.get(x % w, y % h);
            }));
        } else if (name == "BLUR" || name == "GAUSS" || name == "SHARPEN") {
            auto [kernel, divisor] = kernels.at(name);
            commit(convolved(image, kernel, divisor));
        } else if (name == "CONVOLVE") {
            require(all_of(a.begin(), a.begin() + 9, [](int k) { return k >= -16 && k <= 16; })
                    && a[9] >= 1 && a[9] <= 256);
            array<int, 9> kernel;
            copy_n(a.begin(), 9, kernel.begin());
            commit(convolved(image, kernel, a[9]));
        } else if (name == "SOBEL") {
            commit(sobel(image));
        } else if (name == "MEDIAN") {
            commit(rank_filtered(image, 4));
        } else if (name == "ERODE") {
            commit(rank_filtered(image, 0));
        } else if (name == "DILATE") {
            commit(rank_filtered(image, 8));
        } else if (name == "OPEN") {
            commit(rank_filtered(rank_filtered(image, 0), 8));
        } else if (name == "CLOSE") {
            commit(rank_filtered(rank_filtered(image, 8), 0));
        } else if (name == "GRADIENT") {
            vector<int> high = rank_filtered(image, 8).pixels;
            vector<int> low = rank_filtered(image, 0).pixels;
            Image result = image;
            for (size_t i = 0; i < high.size(); ++i) result.pixels[i] = high[i] - low[i];
            commit(move(result));
        } else if (name == "LINE") {
            require(within_limit({a[0], a[1], a[2], a[3]}) && a[4] >= 0 && a[4] <= m);
            paint(line_points(a[0], a[1], a[2], a[3]), a[4]);
        } else if (name == "RECT") {
            require(within_limit({a[0], a[1]}) && a[2] >= 1 && a[2] <= 1000 &&
                    a[3] >= 1 && a[3] <= 1000 && a[4] >= 0 && a[4] <= m);
            paint(rectangle_points(image, a[0], a[1], a[2], a[3], fill), a[4]);
        } else if (name == "CIRCLE") {
            require(within_limit({a[0], a[1]}) && a[2] >= 0 && a[2] <= 1000 &&
                    a[3] >= 0 && a[3] <= m);
            vector<Point> outline = circle_points(a[0], a[1], a[2]);
            paint(fill ? disc_points(image, outline) : outline, a[3]);
        } else if (name == "FLOOD") {
            require(image.contains(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
            paint(flood_points(image, a[0], a[1]), a[2]);
        } else if (name == "HISTOGRAM") {
            array<int, 16> lows, highs{}, counts{};
            lows.fill(-1);
            for (int value = 0; value <= m; ++value) {
                int bin = value * 16 / (m + 1);
                if (lows[bin] < 0) lows[bin] = value;
                highs[bin] = value;
            }
            for (int p : image.pixels) ++counts[p * 16 / (m + 1)];
            int top = *max_element(counts.begin(), counts.end());
            for (int bin = 0; bin < 16; ++bin) {
                if (lows[bin] < 0) continue;
                ostringstream line;
                line << setw(3) << lows[bin] << '-' << setw(3) << highs[bin] <<
                    ' ' << setw(4) << counts[bin] << " |" <<
                    string(counts[bin] * 32 / top, '#');
                emit(line.str());
            }
        } else if (name == "EQUALIZE") {
            commit(equalized(image));
        } else if (name == "LABEL") {
            require(a[0] >= 0 && a[0] <= m);
            auto groups = components(image, a[0]);
            emit("labels " + number(static_cast<int>(groups.size())));
            for (size_t i = 0; i < groups.size(); ++i)
                emit("label " + number(static_cast<int>(i + 1)) + " " +
                     component_text(image, a[0], groups[i]));
        } else if (name == "DISTANCE") {
            require(a[0] >= 0 && a[0] <= m);
            commit(distance_map(image, a[0]));
        } else if (name == "STATS") {
            emit(statistics(image.pixels, m));
        } else if (name == "REGION") {
            checked_crop(a);
            emit(statistics(cropped(image, a[0], a[1], a[2], a[3]).pixels, m));
        } else if (name == "DITHER") {
            commit(dithered(image));
        } else if (name == "ASCIIART") {
            const string shades = "@#*+=~-:,.";
            for (int y = 0; y < h; ++y) {
                string line;
                for (int x = 0; x < w; ++x)
                    line += shades[image.get(x, y) * 10 / (m + 1)];
                emit(line);
            }
        } else if (name == "STORE") {
            slots[slot] = image;
            emit("stored " + slot + " " + image.summary());
        } else if (name == "BLEND") {
            require(a[0] >= 0 && a[0] <= a[1] && a[1] >= 1 && a[1] <= 100);
            const Image& other = matching_slot(slot);
            Image result = image;
            for (size_t i = 0; i < result.pixels.size(); ++i)
                result.pixels[i] = (image.pixels[i] * (a[1] - a[0]) +
                                    other.pixels[i] * a[0]) / a[1];
            commit(move(result));
        } else if (name == "DIFF") {
            const Image& other = matching_slot(slot);
            Image result = image;
            for (size_t i = 0; i < result.pixels.size(); ++i)
                result.pixels[i] = abs(image.pixels[i] - other.pixels[i]);
            commit(move(result));
        } else if (name == "PASTE") {
            require(within_limit({a[0], a[1]}));
            const Image& other = slots.at(slot);
            require(other.maxval == m, "maxval mismatch");
            Image result = image;
            int painted = 0;
            for (int y = 0; y < other.height; ++y)
                for (int x = 0; x < other.width; ++x)
                    if (image.contains(a[0] + x, a[1] + y)) {
                        result.pixels[(a[1] + y) * w + a[0] + x] = other.get(x, y);
                        ++painted;
                    }
            commit(move(result), painted);
        }
    }

public:
    void execute(const vector<string>& words) {
        try {
            Command command = parse(words);
            if (!imageless.count(command.name))
                require(has_image, "no image");
            if (needs_slot.count(command.name))
                require(slots.find(command.slot) != slots.end(), "no slot " + command.slot);
            run(command);
        } catch (const CommandError& error) {
            emit("error: " + string(error.what()));
        }
    }

    void load(const vector<string>& data) {
        try {
            replace(parse_pgm(data), "loaded");
        } catch (const CommandError& error) {
            emit("error: load: " + string(error.what()));
        }
    }

    const vector<string>& lines() const { return output; }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    int commands;
    cin >> commands;
    string line;
    getline(cin, line);
    Editor editor;

    for (int i = 0; i < commands; ++i) {
        getline(cin, line);
        istringstream input(line);
        vector<string> words;
        string word;
        while (input >> word) words.push_back(word);
        if (words[0] == "LOAD") {
            int length = stoi(words[1]);
            vector<string> data;
            for (int j = 0; j < length; ++j) {
                getline(cin, line);
                data.push_back(line);
            }
            editor.load(data);
        } else {
            editor.execute(words);
        }
    }
    for (const string& output : editor.lines())
        cout << output << '\n';
}
