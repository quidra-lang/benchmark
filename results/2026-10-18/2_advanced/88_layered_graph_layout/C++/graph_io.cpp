#include "layout.hpp"
const Lines settingNames{"layering", "width",     "promotion", "heuristic", "sweeps",
                         "node_sep", "dummy_sep", "layer_gap", "direction", "sifting",
                         "reduce",   "restarts",  "seed"};
const char *directionName(Direction direction) {
    return std::array<const char *, 4>{"TB", "BT", "LR", "RL"}[static_cast<int>(direction)];
}
bool vertical(Direction direction) {
    return direction == Direction::TB || direction == Direction::BT;
}
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
Lines readLines(const std::string &path) {
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("cannot read " + path);
    Lines out;
    for (std::string line; std::getline(input, line);)
        out.push_back(line);
    return out;
}
Lines words(const std::string &line) {
    std::istringstream input(line);
    Lines out;
    for (std::string word; input >> word;)
        out.push_back(word);
    return out;
}
Lines Settings::values() const {
    return {coffman ? "coffman" : "longest",
            std::to_string(width),
            promotion ? "on" : "off",
            median ? "median" : "barycenter",
            std::to_string(sweeps),
            std::to_string(nodeSep),
            std::to_string(dummySep),
            std::to_string(layerGap),
            directionName(direction),
            sifting ? "on" : "off",
            reduce ? "on" : "off",
            std::to_string(restarts),
            std::to_string(seed)};
}
bool Settings::set(const std::string &name, const std::string &value) {
    if (name == "layering") {
        if (value != "longest" && value != "coffman")
            return false;
        coffman = value == "coffman";
        return true;
    }
    if (name == "heuristic") {
        if (value != "barycenter" && value != "median")
            return false;
        median = value == "median";
        return true;
    }
    if (name == "direction") {
        for (int i = 0; i < 4; ++i)
            if (value == directionName(static_cast<Direction>(i))) {
                direction = static_cast<Direction>(i);
                return true;
            }
        return false;
    }
    if (name == "promotion" || name == "sifting" || name == "reduce") {
        if (value != "on" && value != "off")
            return false;
        if (name == "promotion")
            promotion = value == "on";
        else if (name == "sifting")
            sifting = value == "on";
        else
            reduce = value == "on";
        return true;
    }
    const std::map<std::string, std::pair<std::int64_t, std::int64_t>> ranges{
        {"width", {1, 40}},       {"sweeps", {0, 50}},   {"node_sep", {1, 9}},
        {"dummy_sep", {1, 9}},    {"layer_gap", {2, 9}}, {"restarts", {0, 9}},
        {"seed", {1, 2147483646}}};
    auto bounds = ranges.find(name);
    if (bounds == ranges.end() || value.empty() || value.size() > 10 ||
        !std::all_of(value.begin(), value.end(), [](char c) { return c >= '0' && c <= '9'; }))
        return false;
    std::int64_t number = std::stoll(value);
    if (number < bounds->second.first || number > bounds->second.second)
        return false;
    if (name == "width")
        width = static_cast<int>(number);
    else if (name == "sweeps")
        sweeps = static_cast<int>(number);
    else if (name == "node_sep")
        nodeSep = static_cast<int>(number);
    else if (name == "dummy_sep")
        dummySep = static_cast<int>(number);
    else if (name == "layer_gap")
        layerGap = static_cast<int>(number);
    else if (name == "restarts")
        restarts = static_cast<int>(number);
    else
        seed = number;
    return true;
}
std::vector<Block> readBlocks() {
    Settings defaults;
    for (const std::string &line : readLines("input/params.txt")) {
        if (line.empty() || line[0] == '#')
            continue;
        Lines items = words(line);
        defaults.set(items[0], items[1]);
    }
    std::vector<Block> out;
    std::set<int> declared;
    std::set<std::pair<int, int>> accepted;
    Lines lines = readLines("input/graphs.txt");
    for (std::size_t i = 0; i < lines.size(); ++i) {
        const std::string &line = lines[i];
        if (line.empty() || line[0] == '#')
            continue;
        Lines items = words(line);
        if (items[0] == "GRAPH") {
            Block block;
            block.name = items[1];
            block.settings = defaults;
            out.push_back(std::move(block));
            declared.clear();
            accepted.clear();
            continue;
        }
        Block &block = out.back();
        if (!block.error.empty())
            continue;
        std::string reason;
        if (items[0] == "OPTION") {
            if (!block.settings.set(items[1], items[2]))
                reason = "bad_option";
        } else if (items[0] == "NODE") {
            int id = std::stoi(items[1]);
            if (declared.count(id))
                reason = "duplicate_node";
            else if (block.nodes.size() == 40)
                reason = "too_many_nodes";
            else {
                declared.insert(id);
                block.nodes.push_back({id, items[2]});
            }
        } else if (items[0] == "EDGE" || items[0] == "PATH") {
            int from = std::stoi(items[1]), to = std::stoi(items[2]);
            if (!declared.count(from) || !declared.count(to))
                reason = "unknown_node";
            else if (items[0] == "PATH") {
                block.hasPath = true;
                block.pathFrom = from;
                block.pathTo = to;
            } else if (from == to)
                ++block.selfLoops;
            else if (!accepted.insert({from, to}).second)
                ++block.duplicates;
            else
                block.edges.push_back({from, to});
        } else if (items[0] == "END" && block.nodes.empty())
            reason = "no_nodes";
        if (!reason.empty()) {
            block.error = reason;
            block.errorLine = static_cast<int>(i + 1);
        }
    }
    for (Block &block : out)
        std::sort(block.nodes.begin(), block.nodes.end(),
                  [](const NodeData &a, const NodeData &b) { return a.id < b.id; });
    return out;
}
