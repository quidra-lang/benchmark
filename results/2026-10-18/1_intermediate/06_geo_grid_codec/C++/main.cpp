#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

using Integer = std::int64_t;
using std::string;
using std::vector;
struct Invalid {};
struct Grid {
    int precision;
    Integer width, height;
};
struct Cell {
    int precision;
    Integer x, y;
    bool operator<(const Cell &other) const { return std::tie(precision, x, y) < std::tie(other.precision, other.x, other.y); }
    bool operator==(const Cell &other) const { return precision == other.precision && x == other.x && y == other.y; }
};
const vector<string> systems = {"GEOHASH", "MAIDENHEAD", "PLUSCODE", "GARS", "GEOREF", "MESH"};
const string hashAlphabet = "0123456789bcdefghjkmnpqrstuvwxyz";
const string plusAlphabet = "23456789CFGHJMPQRVWX";
const string letters24 = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const string osLetters = "ABCDEFGHJKLMNOPQRSTUVWXYZ";
const string bands = "CDEFGHJKLMNPQRSTUVWX";
const string mgrsRows = "ABCDEFGHJKLMNPQRSTUV";
const std::array<Integer, 6> meshScale = {1, 8, 80, 160, 320, 640};
std::array<vector<Grid>, 6> grids;

void require(bool condition) {
    if (!condition) throw Invalid{};
}
Integer floorRatio(Integer a, Integer b) {
    Integer q = a / b;
    if (a % b < 0) --q;
    return q;
}
Integer modulo(Integer a, Integer b) { return a - floorRatio(a, b) * b; }
Integer absolute(Integer a) { return a < 0 ? -a : a; }
vector<string> split(const string &s, char delimiter = ' ') {
    vector<string> result;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || s[i] == delimiter) {
            result.push_back(s.substr(start, i - start));
            start = i + 1;
        }
    }
    return result;
}
string join(const vector<string> &items, const string &separator = " ") {
    string result;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) result += separator;
        result += items[i];
    }
    return result;
}
string padded(Integer value, int width) {
    string s = std::to_string(value);
    return string(std::max(0, width - int(s.size())), '0') + s;
}
string coordinate(Integer value) {
    Integer magnitude = absolute(value);
    return string(value < 0 ? "-" : "") + std::to_string(magnitude / 1000000) + "." + padded(magnitude % 1000000, 6);
}
bool digits(const string &s, int minimum, int maximum) {
    return int(s.size()) >= minimum && int(s.size()) <= maximum && std::all_of(s.begin(), s.end(), [](char c) { return c >= '0' && c <= '9'; });
}
Integer integer(const string &s, Integer minimum, Integer maximum) {
    bool negative = !s.empty() && s[0] == '-';
    string body = negative ? s.substr(1) : s;
    require(digits(body, 1, 9));
    Integer value = 0;
    for (char c : body) value = value * 10 + c - '0';
    if (negative) value = -value;
    require(value >= minimum && value <= maximum);
    return value;
}
Integer location(const string &s, bool latitude) {
    bool negative = !s.empty() && s[0] == '-';
    string body = negative ? s.substr(1) : s;
    vector<string> parts = split(body, '.');
    require(parts.size() == 1 || parts.size() == 2);
    require(digits(parts[0], 1, 3));
    string fraction = parts.size() == 2 ? parts[1] : "";
    if (parts.size() == 2) require(digits(fraction, 1, 6));
    Integer value = 0;
    for (char c : parts[0]) value = value * 10 + c - '0';
    value *= 1000000;
    fraction += string(6 - fraction.size(), '0');
    Integer tail = 0;
    for (char c : fraction) tail = tail * 10 + c - '0';
    value += tail;
    if (negative) value = -value;
    require(latitude ? value >= -90000000 && value <= 90000000 : value >= -180000000 && value < 180000000);
    return value;
}
int systemId(const string &s) {
    vector<string>::const_iterator it = std::find(systems.begin(), systems.end(), s);
    require(it != systems.end());
    return int(it - systems.begin());
}
void initialize() {
    for (int p = 1; p <= 9; ++p) grids[0].push_back({p, Integer(1) << ((5 * p + 1) / 2), Integer(1) << (5 * p / 2)});
    grids[1] = {{2,18,18}, {4,180,180}, {6,4320,4320}, {8,43200,43200}};
    grids[2] = {{2,18,9}, {4,360,180}, {6,7200,3600}, {8,144000,72000}, {10,2880000,1440000}, {11,11520000,7200000}};
    grids[3] = {{5,720,360}, {6,1440,720}, {7,4320,2160}};
    grids[4] = {{2,24,12}, {4,360,180}, {8,21600,10800}, {10,216000,108000}, {12,2160000,1080000}};
    grids[5] = {{4,360,270}, {6,2880,2160}, {8,28800,21600}, {9,57600,43200}, {10,115200,86400}, {11,230400,172800}};
}
int precisionId(int system, Integer p) {
    for (int i = 0; i < int(grids[system].size()); ++i) if (grids[system][i].precision == p) return i;
    throw Invalid{};
}
int precisionArgument(int system, const string &s) { return precisionId(system, integer(s, 0, 999999999)); }
int digit(const string &alphabet, char c) {
    std::size_t result = alphabet.find(c);
    require(result != string::npos);
    return int(result);
}
Cell point(int system, int precision, Integer latitude, Integer longitude) {
    const Grid &g = grids[system][precision];
    return {precision, (longitude + 180000000) * g.width / 360000000, std::min((latitude + 90000000) * g.height / 180000000, g.height - 1)};
}
Cell ancestor(int system, const Cell &c, int precision) {
    const Grid &g = grids[system][c.precision], &parent = grids[system][precision];
    return {precision, c.x * parent.width / g.width, c.y * parent.height / g.height};
}
string encode(int system, Cell c) {
    const Grid &g = grids[system][c.precision];
    int p = g.precision;
    Integer x = c.x, y = c.y;
    string result;
    if (system == 0) {
        int a = (5 * p + 1) / 2, b = 5 * p / 2, value = 0;
        for (int i = 0; i < 5 * p; ++i) {
            int bit = i % 2 == 0 ? int(x >> (a - 1 - i / 2) & 1) : int(y >> (b - 1 - i / 2) & 1);
            value = value * 2 + bit;
            if (i % 5 == 4) {
                result += hashAlphabet[value];
                value = 0;
            }
        }
    } else if (system == 1 || system == 2) {
        int count = system == 1 ? p / 2 : std::min(p, 10) / 2;
        int tail = -1;
        if (system == 2 && p == 11) {
            tail = int(4 * (y % 5) + x % 4);
            x /= 4;
            y /= 5;
        }
        vector<int> xd(count), yd(count);
        const vector<string> alphabets = {"ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789"};
        for (int i = count - 1; i >= 0; --i) {
            int rx = system == 1 ? int(alphabets[i].size()) : i == 0 ? 18 : 20;
            int ry = system == 1 ? rx : i == 0 ? 9 : 20;
            xd[i] = int(x % rx);
            yd[i] = int(y % ry);
            x /= rx;
            y /= ry;
        }
        for (int i = 0; i < count; ++i) {
            if (system == 1) {
                result += alphabets[i][xd[i]];
                result += alphabets[i][yd[i]];
            } else {
                result += plusAlphabet[yd[i]];
                result += plusAlphabet[xd[i]];
            }
        }
        if (tail >= 0) result += plusAlphabet[tail];
        if (system == 2) {
            if (p < 8) result += string(8 - p, '0');
            result.insert(8, "+");
        }
    } else if (system == 3) {
        Integer scale = p == 5 ? 1 : p == 6 ? 2 : 6;
        Integer baseY = y / scale;
        result = padded(x / scale + 1, 3) + letters24[baseY / 24] + letters24[baseY % 24];
        if (p >= 6) {
            Integer xx = p == 7 ? x / 3 : x, yy = p == 7 ? y / 3 : y;
            result += char('1' + xx % 2 + 2 * (1 - yy % 2));
        }
        if (p == 7) result += char('1' + x % 3 + 3 * (2 - y % 3));
    } else if (system == 4) {
        int m = (p - 4) / 2;
        Integer scale = p < 8 ? 1 : m == 2 ? 60 : m == 3 ? 600 : 6000;
        Integer xx = x / scale, yy = y / scale;
        if (p == 2) return string(1, letters24[x]) + letters24[y];
        result = string(1, letters24[xx / 15]) + letters24[yy / 15] + letters24[xx % 15] + letters24[yy % 15];
        if (p >= 8) result += padded(x % scale, m) + padded(y % scale, m);
    } else {
        Integer scale = meshScale[c.precision];
        x -= 280 * scale;
        y -= 135 * scale;
        if (x < 0 || x >= 80 * scale || y < 0 || y >= 100 * scale) return "";
        int count = c.precision + 1;
        const int radices[] = {0, 8, 10, 2, 2, 2};
        vector<int> xd(count), yd(count);
        for (int i = count - 1; i >= 1; --i) {
            xd[i] = int(x % radices[i]);
            yd[i] = int(y % radices[i]);
            x /= radices[i];
            y /= radices[i];
        }
        result = padded(y, 2) + padded(x, 2);
        for (int i = 1; i < count; ++i) {
            if (i <= 2) {
                result += char('0' + yd[i]);
                result += char('0' + xd[i]);
            } else result += char('1' + xd[i] + 2 * yd[i]);
        }
    }
    return result;
}
Cell decode(int system, const string &code) {
    int p = int(code.size());
    Integer x = 0, y = 0;
    if (system == 0) {
        require(p >= 1 && p <= 9);
        int position = 0;
        for (char c : code) {
            int value = digit(hashAlphabet, c);
            for (int bit = 4; bit >= 0; --bit) {
                if (position++ % 2 == 0) x = x * 2 + (value >> bit & 1);
                else y = y * 2 + (value >> bit & 1);
            }
        }
    } else if (system == 1) {
        precisionId(system, p);
        const vector<string> alphabets = {"ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789"};
        for (int i = 0; i < p / 2; ++i) {
            x = x * Integer(alphabets[i].size()) + digit(alphabets[i], code[2 * i]);
            y = y * Integer(alphabets[i].size()) + digit(alphabets[i], code[2 * i + 1]);
        }
    } else if (system == 2) {
        require(p >= 9 && code[8] == '+' && std::count(code.begin(), code.end(), '+') == 1);
        int prefix = 0;
        while (prefix < 8 && code[prefix] != '0') {
            digit(plusAlphabet, code[prefix]);
            ++prefix;
        }
        require(prefix == 2 || prefix == 4 || prefix == 6 || prefix == 8);
        for (int i = prefix; i < 8; ++i) require(code[i] == '0');
        int suffix = p - 9;
        require(prefix == 8 ? suffix == 0 || suffix == 2 || suffix == 3 : suffix == 0);
        require(digit(plusAlphabet, code[0]) <= 8 && digit(plusAlphabet, code[1]) <= 17);
        string sequence = code.substr(0, prefix) + code.substr(9);
        p = int(sequence.size());
        for (int i = 0; i < std::min(p, 10) / 2; ++i) {
            y = y * (i == 0 ? 9 : 20) + digit(plusAlphabet, sequence[2 * i]);
            x = x * (i == 0 ? 18 : 20) + digit(plusAlphabet, sequence[2 * i + 1]);
        }
        if (p == 11) {
            int tail = digit(plusAlphabet, sequence[10]);
            x = x * 4 + tail % 4;
            y = y * 5 + tail / 4;
        }
    } else if (system == 3) {
        require(p >= 5 && p <= 7 && digits(code.substr(0, 3), 3, 3));
        x = integer(code.substr(0, 3), 1, 720) - 1;
        int a = digit(letters24, code[3]), b = digit(letters24, code[4]);
        require(a < 15);
        y = 24 * a + b;
        if (p >= 6) {
            require(code[5] >= '1' && code[5] <= '4');
            int q = code[5] - '1';
            x = 2 * x + q % 2;
            y = 2 * y + 1 - q / 2;
        }
        if (p == 7) {
            require(code[6] >= '1' && code[6] <= '9');
            int q = code[6] - '1';
            x = 3 * x + q % 3;
            y = 3 * y + 2 - q / 3;
        }
    } else if (system == 4) {
        precisionId(system, p);
        x = digit(letters24, code[0]);
        y = digit(letters24, code[1]);
        require(y < 12);
        if (p >= 4) {
            int a = digit(letters24, code[2]), b = digit(letters24, code[3]);
            require(a < 15 && b < 15);
            x = 15 * x + a;
            y = 15 * y + b;
        }
        if (p >= 8) {
            int m = (p - 4) / 2;
            Integer scale = m == 2 ? 60 : m == 3 ? 600 : 6000;
            require(digits(code.substr(4, m), m, m) && digits(code.substr(4 + m), m, m));
            x = x * scale + integer(code.substr(4, m), 0, scale - 1);
            y = y * scale + integer(code.substr(4 + m), 0, scale - 1);
        }
    } else {
        int precision = precisionId(system, p);
        require(digits(code, p, p));
        y = integer(code.substr(0, 2), 0, 99);
        x = integer(code.substr(2, 2), 0, 79);
        if (p >= 6) {
            require(code[4] <= '7' && code[5] <= '7');
            y = y * 8 + code[4] - '0';
            x = x * 8 + code[5] - '0';
        }
        if (p >= 8) {
            y = y * 10 + code[6] - '0';
            x = x * 10 + code[7] - '0';
        }
        for (int i = 8; i < p; ++i) {
            require(code[i] >= '1' && code[i] <= '4');
            int q = code[i] - '1';
            x = x * 2 + q % 2;
            y = y * 2 + q / 2;
        }
        x += 280 * meshScale[precision];
        y += 135 * meshScale[precision];
    }
    return {precisionId(system, p), x, y};
}
string display(int system, Cell c) {
    string code = encode(system, c);
    return code.empty() ? "-" : code;
}
Integer centerNumerator(Integer position, Integer divisions, Integer span) { return span * (2 * position + 1 - divisions); }
int compare(Integer a, Integer b, Integer c, Integer d) {
    Integer left = a * d, right = c * b;
    return left < right ? -1 : left > right ? 1 : 0;
}
string relation(int firstSystem, Cell a, int secondSystem, Cell b) {
    const Grid &ga = grids[firstSystem][a.precision], &gb = grids[secondSystem][b.precision];
    int west = compare(a.x, ga.width, b.x, gb.width), east = compare(a.x + 1, ga.width, b.x + 1, gb.width);
    int south = compare(a.y, ga.height, b.y, gb.height), north = compare(a.y + 1, ga.height, b.y + 1, gb.height);
    if (!west && !east && !south && !north) return "EQUAL";
    if (west >= 0 && east <= 0 && south >= 0 && north <= 0) return "INSIDE";
    if (west <= 0 && east >= 0 && south <= 0 && north >= 0) return "CONTAINS";
    int xy1 = compare(a.x, ga.width, b.x + 1, gb.width), xy2 = compare(b.x, gb.width, a.x + 1, ga.width);
    int yy1 = compare(a.y, ga.height, b.y + 1, gb.height), yy2 = compare(b.y, gb.height, a.y + 1, ga.height);
    if (xy1 < 0 && xy2 < 0 && yy1 < 0 && yy2 < 0) return "OVERLAP";
    bool wrap = a.x == 0 && b.x + 1 == gb.width || b.x == 0 && a.x + 1 == ga.width;
    if (yy1 <= 0 && yy2 <= 0 && (xy1 <= 0 && xy2 <= 0 || wrap)) return "TOUCH";
    return "DISJOINT";
}
void prune(int system, std::set<Cell> &cells) {
    vector<Cell> removed;
    for (Cell c : cells) {
        for (Cell other : cells) {
            if (other.precision < c.precision && ancestor(system, c, other.precision) == other) {
                removed.push_back(c);
                break;
            }
        }
    }
    for (Cell c : removed) cells.erase(c);
}
string compact(int system, const vector<string> &codes) {
    std::set<Cell> cells;
    for (const string &code : codes) cells.insert(decode(system, code));
    prune(system, cells);
    for (;;) {
        bool changed = false;
        for (Cell c : cells) {
            if (!c.precision) continue;
            Cell parent = ancestor(system, c, c.precision - 1);
            const Grid &g = grids[system][c.precision], &pg = grids[system][parent.precision];
            Integer needed = (g.width / pg.width) * (g.height / pg.height);
            if (needed > Integer(cells.size())) continue;
            vector<Cell> children;
            for (Cell other : cells) if (other.precision == c.precision && ancestor(system, other, parent.precision) == parent) children.push_back(other);
            if (Integer(children.size()) != needed) continue;
            for (Cell child : children) cells.erase(child);
            cells.insert(parent);
            prune(system, cells);
            changed = true;
            break;
        }
        if (!changed) break;
    }
    vector<Cell> ordered(cells.begin(), cells.end());
    std::sort(ordered.begin(), ordered.end(), [](Cell a, Cell b) {
        if (a.precision != b.precision) return a.precision < b.precision;
        if (a.y != b.y) return a.y > b.y;
        return a.x < b.x;
    });
    vector<string> result;
    for (Cell c : ordered) result.push_back(encode(system, c));
    return join(result);
}
string mgrsColumns(Integer zone) { return zone % 3 == 1 ? "ABCDEFGH" : zone % 3 == 2 ? "JKLMNPQR" : "STUVWXYZ"; }
Integer squareDigits(const vector<string> &a, int start, Integer &e, Integer &n) {
    if (int(a.size()) == start) return 100000;
    require(digits(a[start], 1, 5) && digits(a[start + 1], 1, 5) && a[start].size() == a[start + 1].size());
    Integer scale = 1;
    for (int i = int(a[start].size()); i < 5; ++i) scale *= 10;
    e += integer(a[start], 0, 99999) * scale;
    n += integer(a[start + 1], 0, 99999) * scale;
    return scale;
}
string execute(const vector<string> &a) {
    const vector<string> names = {
        "ENCODE", "DECODE", "NEIGHBORS", "PARENT", "CHILDREN", "COMMON",
        "COMPACT", "CONTAINS", "COVER", "CONVERT", "STEPS", "PATH", "RELATE",
        "SIZE", "SHORTEN", "RECOVER", "UTMZONE", "OSGB", "UNOSGB", "MGRS",
        "UNMGRS", "QUADKEY", "UNQUADKEY"
    };
    vector<string>::const_iterator found = std::find(names.begin(), names.end(), a[0]);
    require(found != names.end());
    int command = int(found - names.begin());
    const int lengths[] = {5,3,3,3,3,4,0,5,7,6,4,4,5,3,4,4,3,4,0,6,0,4,2};
    if (command == 6) require(a.size() >= 3 && a.size() <= 102);
    else if (command == 18) require(a.size() == 2 || a.size() == 4);
    else if (command == 20) require(a.size() == 3 || a.size() == 5);
    else require(int(a.size()) == lengths[command]);
    if (command <= 13) {
        int system = systemId(a[1]);
        if (command == 0) {
            Integer lat = location(a[2], true), lon = location(a[3], false);
            int precision = precisionArgument(system, a[4]);
            string code = encode(system, point(system, precision, lat, lon));
            return code.empty() ? "OUT OF AREA" : code;
        }
        if (command == 8) {
            int precision = precisionArgument(system, a[2]);
            Integer lat1 = location(a[3], true), lon1 = location(a[4], false), lat2 = location(a[5], true), lon2 = location(a[6], false);
            require(lat1 <= lat2);
            Cell first = point(system, precision, lat1, lon1), last = point(system, precision, lat2, lon2);
            const Grid &g = grids[system][precision];
            Integer columns = lon1 <= lon2 ? last.x - first.x + 1 : std::min(g.width, last.x - first.x + 1 + g.width);
            if ((last.y - first.y + 1) * columns > 100) return "TOO MANY";
            vector<string> result;
            for (Integer y = last.y; y >= first.y; --y) {
                for (Integer i = 0; i < columns; ++i) result.push_back(display(system, {precision, (first.x + i) % g.width, y}));
            }
            return join(result);
        }
        if (command == 13) {
            int precision = precisionArgument(system, a[2]);
            const Grid &g = grids[system][precision];
            Integer count = system == 5 ? 8000 * meshScale[precision] * meshScale[precision] : g.width * g.height;
            return "w=" + coordinate(360000000 / g.width) + " h=" + coordinate(180000000 / g.height) + " cells=" + std::to_string(count);
        }
        if (command == 6) return compact(system, vector<string>(a.begin() + 2, a.end()));
        Cell c = decode(system, a[2]);
        const Grid &g = grids[system][c.precision];
        if (command == 1) {
            Integer south = -90000000 + 180000000 * c.y / g.height, west = -180000000 + 360000000 * c.x / g.width;
            Integer north = -90000000 + 180000000 * (c.y + 1) / g.height, east = -180000000 + 360000000 * (c.x + 1) / g.width;
            Integer cy = floorRatio(centerNumerator(c.y, g.height, 180000000), 2 * g.height), cx = floorRatio(centerNumerator(c.x, g.width, 360000000), 2 * g.width);
            return "sw=" + coordinate(south) + "," + coordinate(west) + " ne=" + coordinate(north) + "," + coordinate(east) + " c=" + coordinate(cy) + "," + coordinate(cx);
        }
        if (command == 2) {
            const int dx[] = {0,1,1,1,0,-1,-1,-1}, dy[] = {1,1,0,-1,-1,-1,0,1};
            vector<string> result;
            for (int i = 0; i < 8; ++i) result.push_back(c.y + dy[i] < 0 || c.y + dy[i] >= g.height ? "-" : display(system, {c.precision, modulo(c.x + dx[i], g.width), c.y + dy[i]}));
            return join(result);
        }
        if (command == 3) return c.precision == 0 ? "NONE" : encode(system, ancestor(system, c, c.precision - 1));
        if (command == 4) {
            if (c.precision + 1 == int(grids[system].size())) return "NONE";
            const Grid &next = grids[system][c.precision + 1];
            Integer rx = next.width / g.width, ry = next.height / g.height;
            if (rx * ry > 100) return "TOO MANY";
            vector<string> result;
            for (Integer j = ry - 1; j >= 0; --j) {
                for (Integer i = 0; i < rx; ++i) result.push_back(display(system, {c.precision + 1, rx * c.x + i, ry * c.y + j}));
            }
            return join(result);
        }
        if (command == 7) {
            Integer lat = location(a[3], true), lon = location(a[4], false);
            return point(system, c.precision, lat, lon) == c ? "YES" : "NO";
        }
        if (command == 9) {
            require(a[3] == "TO");
            int destination = systemId(a[4]), precision = precisionArgument(destination, a[5]);
            const Grid &next = grids[destination][precision];
            string code = encode(destination, {precision, (2 * c.x + 1) * next.width / (2 * g.width), (2 * c.y + 1) * next.height / (2 * g.height)});
            return code.empty() ? "OUT OF AREA" : code;
        }
        if (command == 12) return relation(system, c, systemId(a[3]), decode(systemId(a[3]), a[4]));
        Cell other = decode(system, a[3]);
        if (command == 5) {
            for (int precision = std::min(c.precision, other.precision); precision >= 0; --precision) {
                Cell parent = ancestor(system, c, precision);
                if (parent == ancestor(system, other, precision)) return encode(system, parent);
            }
            return "NONE";
        }
        if (c.precision != other.precision) return "MISMATCH";
        Integer dx = modulo(other.x - c.x, g.width), dy = other.y - c.y;
        if (dx > g.width / 2) dx -= g.width;
        if (command == 10) return "dx=" + std::to_string(dx) + " dy=" + std::to_string(dy);
        Integer n = std::max(absolute(dx), absolute(dy));
        if (n + 1 > 100) return "TOO MANY";
        vector<string> result;
        for (Integer i = 0; i <= n; ++i) {
            Integer x = c.x + (n ? floorRatio(2 * i * dx + n, 2 * n) : 0), y = c.y + (n ? floorRatio(2 * i * dy + n, 2 * n) : 0);
            result.push_back(display(system, {c.precision, modulo(x, g.width), y}));
        }
        return join(result);
    }
    if (command == 14 || command == 15) {
        Integer lat = location(a[2], true), lon = location(a[3], false);
        string full = a[1];
        int removed = 0;
        if (command == 15) {
            std::size_t plus = full.find('+');
            require((plus == 2 || plus == 4) && std::count(full.begin(), full.end(), '+') == 1);
            int suffix = int(full.size() - plus - 1);
            require(suffix == 0 || suffix == 2 || suffix == 3);
            for (char c : full) if (c != '+') digit(plusAlphabet, c);
            removed = 8 - int(plus);
            full = encode(2, point(2, precisionId(2, 10), lat, lon)).substr(0, removed) + full;
        }
        Cell c = decode(2, full);
        const Grid &g = grids[2][c.precision];
        require(g.precision >= 8);
        Integer cy = centerNumerator(c.y, g.height, 180000000), cx = centerNumerator(c.x, g.width, 360000000);
        Integer yd = 2 * g.height, xd = 2 * g.width;
        if (command == 14) {
            if (absolute(cy - lat * yd) < 15000 * yd && absolute(cx - lon * xd) < 15000 * xd) return full.substr(6);
            if (absolute(cy - lat * yd) < 300000 * yd && absolute(cx - lon * xd) < 300000 * xd) return full.substr(4);
            return full;
        }
        Integer distance = removed == 4 ? 1000000 : 50000;
        Integer my = distance * g.height / 180000000, mx = distance * g.width / 360000000;
        if ((lat + distance / 2) * yd < cy && cy - distance * yd >= -90000000 * yd) c.y -= my;
        else if ((lat - distance / 2) * yd > cy && cy + distance * yd <= 90000000 * yd) c.y += my;
        if ((lon + distance / 2) * xd < cx) c.x = modulo(c.x - mx, g.width);
        else if ((lon - distance / 2) * xd > cx) c.x = modulo(c.x + mx, g.width);
        return encode(2, c);
    }
    if (command == 16) {
        Integer lat = location(a[1], true), lon = location(a[2], false);
        if (lat < -80000000 || lat >= 84000000) return "NONE";
        char band = bands[std::min((lat + 80000000) / 8000000, Integer(19))];
        Integer zone = (lon + 180000000) / 6000000 + 1;
        if (band == 'V' && lon >= 3000000 && lon < 12000000) zone = 32;
        if (band == 'X' && lon >= 0 && lon < 42000000) zone = lon < 9000000 ? 31 : lon < 21000000 ? 33 : lon < 33000000 ? 35 : 37;
        return std::to_string(zone) + band;
    }
    if (command == 17 || command == 19) {
        Integer zone = 0, e, n;
        int d;
        string prefix;
        if (command == 17) {
            e = integer(a[1], 0, 699999);
            n = integer(a[2], 0, 1299999);
            d = int(integer(a[3], 0, 5));
            prefix = string(1, osLetters[5 * (3 - n / 500000) + 2 + e / 500000]) + osLetters[5 * (4 - n / 100000 % 5) + e / 100000 % 5];
        } else {
            zone = integer(a[1], 1, 60);
            require(a[2].size() == 1);
            digit(bands, a[2][0]);
            e = integer(a[3], 100000, 899999);
            n = integer(a[4], 0, 9999999);
            d = int(integer(a[5], 0, 5));
            prefix = std::to_string(zone) + a[2] + " " + mgrsColumns(zone)[e / 100000 - 1] + mgrsRows[(n / 100000 + (zone % 2 == 0 ? 5 : 0)) % 20];
        }
        if (d) prefix += " " + padded(e % 100000, 5).substr(0, d) + " " + padded(n % 100000, 5).substr(0, d);
        return prefix;
    }
    if (command == 18 || command == 20) {
        Integer e, n, scale;
        string prefix;
        if (command == 18) {
            require(a[1].size() == 2);
            int first = digit(osLetters, a[1][0]), second = digit(osLetters, a[1][1]);
            e = 500000 * (first % 5 - 2) + 100000 * (second % 5);
            n = 500000 * (3 - first / 5) + 100000 * (4 - second / 5);
            require(e >= 0 && e < 700000 && n >= 0 && n < 1300000);
            scale = squareDigits(a, 2, e, n);
        } else {
            require(a[1].size() == 2 || a[1].size() == 3);
            string zoneText = a[1].substr(0, a[1].size() - 1);
            require(digits(zoneText, 1, 2) && zoneText[0] != '0');
            Integer zone = integer(zoneText, 1, 60);
            digit(bands, a[1].back());
            require(a[2].size() == 2);
            e = 100000 * (digit(mgrsColumns(zone), a[2][0]) + 1);
            n = 100000 * modulo(digit(mgrsRows, a[2][1]) - (zone % 2 == 0 ? 5 : 0), 20);
            scale = squareDigits(a, 3, e, n);
            prefix = a[1] + " ";
        }
        return prefix + "sw=" + std::to_string(e) + "," + std::to_string(n) + " size=" + std::to_string(scale);
    }
    if (command == 21) {
        int z = int(integer(a[3], 1, 23));
        Integer x = integer(a[1], 0, (Integer(1) << z) - 1), y = integer(a[2], 0, (Integer(1) << z) - 1);
        string key;
        for (int i = z - 1; i >= 0; --i) key += char('0' + (x >> i & 1) + 2 * (y >> i & 1));
        return key;
    }
    require(a[1].size() >= 1 && a[1].size() <= 23);
    Integer x = 0, y = 0;
    for (char c : a[1]) {
        require(c >= '0' && c <= '3');
        int q = c - '0';
        x = x * 2 + q % 2;
        y = y * 2 + q / 2;
    }
    return "x=" + std::to_string(x) + " y=" + std::to_string(y) + " z=" + std::to_string(a[1].size());
}
int main() {
    initialize();
    string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            std::cout << execute(split(line)) << '\n';
        } catch (const Invalid &) {
            std::cout << "INVALID\n";
        }
    }
}
