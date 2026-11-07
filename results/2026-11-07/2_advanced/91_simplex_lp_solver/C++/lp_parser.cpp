#include "solver.hpp"
std::string join(const Lines &items, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i)
            out += separator;
        out += items[i];
    }
    return out;
}
void append(Lines &to, const Lines &from) { to.insert(to.end(), from.begin(), from.end()); }
static Lines readLines(const std::string &path) {
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("cannot read " + path);
    Lines out;
    for (std::string line; std::getline(input, line);)
        out.push_back(line);
    return out;
}
static Lines words(const std::string &line) {
    std::istringstream input(line);
    Lines out;
    for (std::string word; input >> word;)
        out.push_back(word);
    return out;
}
static bool name(const std::string &value) {
    if (value.empty() || value[0] < 'a' || value[0] > 'z' || value == "bounds" ||
        value == "integer" || value == "binary" || value == "free" || value == "inf")
        return false;
    return std::all_of(value.begin() + 1, value.end(), [](char c) {
        return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_';
    });
}
static std::optional<Terms> expression(const Lines &items, std::size_t first, std::size_t end) {
    Terms out;
    int sign = 1;
    if (first < end && items[first] == "-") {
        ++first;
        sign = -1;
    }
    while (first < end) {
        std::optional<Rational> coefficient = readNumber(items[first], false);
        std::string variable;
        if (coefficient) {
            if (first + 1 >= end || !name(items[first + 1]))
                return std::nullopt;
            variable = items[first + 1];
            first += 2;
        } else if (name(items[first])) {
            variable = items[first++];
            coefficient = Rational(1);
        } else
            return std::nullopt;
        out.push_back({variable, *coefficient * Rational(sign)});
        if (first == end)
            return out;
        if (items[first] != "+" && items[first] != "-")
            return std::nullopt;
        sign = items[first++] == "-" ? -1 : 1;
    }
    return std::nullopt;
}
static std::optional<std::pair<std::string, Terms>> namedExpression(const Lines &items,
                                                                    std::size_t end) {
    if (end < 2 || items[0].empty() || items[0].back() != ':')
        return std::nullopt;
    std::string label = items[0].substr(0, items[0].size() - 1);
    if (!name(label))
        return std::nullopt;
    std::optional<Terms> terms = expression(items, 1, end);
    if (!terms)
        return std::nullopt;
    return std::make_pair(label, *terms);
}
static std::optional<Constraint> constraint(const Lines &items, int line) {
    std::size_t size = items.size();
    if (size < 4 || (items[size - 2] != "<=" && items[size - 2] != ">=" && items[size - 2] != "="))
        return std::nullopt;
    std::optional<Rational> rhs = readNumber(items.back(), true);
    if (!rhs)
        return std::nullopt;
    auto terms = namedExpression(items, size - 2);
    if (!terms)
        return std::nullopt;
    return Constraint{terms->first, items[size - 2], line, terms->second, *rhs, {}};
}
static std::optional<BoundLine> bound(const Lines &items, int line) {
    std::size_t size = items.size();
    if (size == 2 && name(items[0]) && items[1] == "free")
        return BoundLine{line, items[0], BoundKind::Both, {}, {}};
    if (size == 3 && name(items[0])) {
        Bound value = readNumber(items[2], true);
        if (items[1] == ">=" && (value || items[2] == "-inf"))
            return BoundLine{line, items[0], BoundKind::Lower, value, {}};
        if (items[1] == "<=" && (value || items[2] == "inf"))
            return BoundLine{line, items[0], BoundKind::Upper, {}, value};
        if (items[1] == "=" && value)
            return BoundLine{line, items[0], BoundKind::Both, value, value};
    }
    if (size == 5 && items[1] == "<=" && items[3] == "<=" && name(items[2])) {
        Bound lower = readNumber(items[0], true), upper = readNumber(items[4], true);
        if ((lower || items[0] == "-inf") && (upper || items[4] == "inf"))
            return BoundLine{line, items[2], BoundKind::Both, lower, upper};
    }
    return std::nullopt;
}
static RawModel parseBlock(const std::string &modelName,
                           const std::vector<std::pair<int, std::string>> &body, int endLine) {
    RawModel out;
    out.name = modelName;
    char state = 'A';
    for (const auto &record : body) {
        int line = record.first;
        const std::string &source = record.second;
        Lines items = words(source);
        bool accepted = false;
        if (state == 'A') {
            if (source == "maximize" || source == "minimize") {
                out.direction = source;
                state = 'B';
                accepted = true;
            }
        } else if (state == 'B') {
            auto objective = namedExpression(items, items.size());
            if (objective) {
                out.objective = objective->second;
                state = 'C';
                accepted = true;
            }
        } else if (state == 'C') {
            if (source == "subject to") {
                state = 'D';
                accepted = true;
            }
        } else if (state == 'D' || state == 'E') {
            if (state == 'E' && (source == "bounds" || source == "integer" || source == "binary")) {
                state = source == "bounds" ? 'F' : source == "integer" ? 'G' : 'H';
                accepted = true;
            } else {
                auto row = constraint(items, line);
                if (row) {
                    out.constraints.push_back(std::move(*row));
                    state = 'E';
                    accepted = true;
                }
            }
        } else if (state == 'F') {
            if (source == "integer" || source == "binary") {
                state = source == "integer" ? 'G' : 'H';
                accepted = true;
            } else {
                auto limit = bound(items, line);
                if (limit) {
                    out.bounds.push_back(*limit);
                    accepted = true;
                }
            }
        } else {
            if (state == 'G' && source == "binary") {
                state = 'H';
                accepted = true;
            } else if (std::all_of(items.begin(), items.end(), name)) {
                (state == 'G' ? out.integers : out.binaries).push_back({line, items});
                accepted = true;
            }
        }
        if (!accepted) {
            out.error = ModelError{line, "syntax error"};
            return out;
        }
    }
    if (state <= 'D')
        out.error = ModelError{endLine, "syntax error"};
    return out;
}
std::vector<RawModel> readModels() {
    std::vector<RawModel> out;
    std::string current;
    std::vector<std::pair<int, std::string>> body;
    Lines lines = readLines("input/models.lp");
    for (std::size_t i = 0; i < lines.size(); ++i) {
        const std::string &line = lines[i];
        if (line.empty() || line[0] == '#')
            continue;
        if (current.empty()) {
            current = words(line)[1];
            body.clear();
        } else if (line == "end") {
            out.push_back(parseBlock(current, body, static_cast<int>(i + 1)));
            current.clear();
        } else
            body.emplace_back(static_cast<int>(i + 1), line);
    }
    return out;
}
Settings readSettings() {
    Lines lines = readLines("input/params.txt");
    Settings out;
    out.level = std::stoi(words(lines[0])[1]);
    out.limit = std::stoi(words(lines[1])[1]);
    for (std::size_t i = 2; i < lines.size(); ++i) {
        Lines items = words(lines[i]);
        (items[0] == "log" ? out.logs : out.limits)[items[1]] = std::stoi(items[2]);
    }
    return out;
}
