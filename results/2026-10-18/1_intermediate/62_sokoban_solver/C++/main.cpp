#include <algorithm>
#include <array>
#include <cctype>
#include <iostream>
#include <iterator>
#include <map>
#include <numeric>
#include <optional>
#include <queue>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace {

enum class Kind { Number, Steps, Direction, Name, Transform, Text };

using Boxes = std::vector<int>;
using Arguments = std::vector<std::string>;

const std::string DIRECTIONS = "udlr";
const std::array<std::pair<int, int>, 4> DELTAS = {{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}};
const std::map<std::string, std::string> TURNS = {
    {"ROT90", "rlud"}, {"ROT180", "durl"}, {"ROT270", "lrdu"},
    {"FLIPH", "udrl"}, {"FLIPV", "dulr"},
};
const std::string STEP_LETTERS = "udlrUDLR";
const std::string LEVEL_CHARACTERS = "#-.$*@+";
constexpr std::size_t MAX_SIDE = 10;
constexpr int MAX_LIMIT = 100000;
constexpr int UNDEFINED = -1;
const std::regex NUMBER_WORD("0|[1-9][0-9]{0,5}");
const std::regex NAME_WORD("[a-z]{1,8}");
const std::map<std::string, std::vector<Kind>> COMMANDS = {
    {"IMPORT", {Kind::Text}},
    {"VALID", {}},
    {"INFO", {}},
    {"SHOW", {}},
    {"EXPORT", {}},
    {"MOVE", {Kind::Steps}},
    {"PUSH", {Kind::Number, Kind::Number, Kind::Direction}},
    {"BRING", {Kind::Number, Kind::Number, Kind::Number, Kind::Number}},
    {"PATH", {Kind::Number, Kind::Number}},
    {"UNDO", {Kind::Number}},
    {"REDO", {Kind::Number}},
    {"RESET", {}},
    {"STATUS", {}},
    {"HISTORY", {}},
    {"BOXES", {}},
    {"REACH", {}},
    {"DEADSQUARES", {}},
    {"DEADLOCK", {}},
    {"BOUND", {}},
    {"SAVE", {Kind::Name}},
    {"RESTORE", {Kind::Name}},
    {"CHECK", {Kind::Steps}},
    {"SOLVE", {Kind::Number}},
    {"HINT", {Kind::Number}},
    {"PLAY", {}},
    {"TRANSFORM", {Kind::Transform}},
};
const std::map<std::string, int> CELL_COUNTS = {{"PATH", 1}, {"PUSH", 1}, {"BRING", 2}};
const std::set<std::string> LEVEL_FREE_COMMANDS = {"IMPORT", "VALID"};

struct CommandError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

struct StepFailure : std::runtime_error {
    using std::runtime_error::runtime_error;
};

struct Position {
    int player = 0;
    Boxes boxes;

    bool same(const Position& other) const {
        return player == other.player && boxes == other.boxes;
    }
};

struct Simulation {
    Position position;
    std::string letters;
    std::optional<std::string> failure;
};

struct Push {
    int box;
    char direction;
};

struct SearchNode {
    Boxes boxes;
    int representative;
    std::optional<std::size_t> parent;
    Push push;
};

struct SearchResult {
    std::string outcome;
    std::size_t expanded;
    std::size_t states;
    std::string notation;
};

struct Assignment {
    std::vector<int> order;
    std::vector<int> pushes;
    int total;
};

template <typename First, typename... Rest>
void emit(const First& first, const Rest&... rest) {
    std::cout << first;
    ((std::cout << ' ' << rest), ...);
    std::cout << '\n';
}

bool isPush(char letter) {
    return std::isupper(static_cast<unsigned char>(letter)) != 0;
}

char toLower(char letter) {
    return static_cast<char>(std::tolower(static_cast<unsigned char>(letter)));
}

char toUpper(char letter) {
    return static_cast<char>(std::toupper(static_cast<unsigned char>(letter)));
}

std::string lowered(std::string text) {
    std::transform(text.begin(), text.end(), text.begin(), toLower);
    return text;
}

bool includes(const std::vector<int>& cells, int cell) {
    return std::find(cells.begin(), cells.end(), cell) != cells.end();
}

int countTrue(const std::vector<bool>& flags) {
    return static_cast<int>(std::count(flags.begin(), flags.end(), true));
}

int firstTrue(const std::vector<bool>& flags) {
    return static_cast<int>(std::find(flags.begin(), flags.end(), true) - flags.begin());
}

std::string dimensions(int height, int width) {
    return std::to_string(height) + "x" + std::to_string(width);
}

std::vector<std::string> split(const std::string& text, char separator) {
    std::vector<std::string> parts;
    std::size_t start = 0;
    while (true) {
        std::size_t end = text.find(separator, start);
        if (end == std::string::npos) {
            parts.push_back(text.substr(start));
            return parts;
        }
        parts.push_back(text.substr(start, end - start));
        start = end + 1;
    }
}

std::optional<std::string> decode(const std::string& text, const std::string& allowed) {
    std::string result;
    std::size_t index = 0;
    while (index < text.size()) {
        std::size_t start = index;
        while (index < text.size() && std::isdigit(static_cast<unsigned char>(text[index]))) {
            ++index;
        }
        std::string count = text.substr(start, index - start);
        if (count.size() > 2 || (!count.empty() && count[0] == '0') || index == text.size()) {
            return std::nullopt;
        }
        if (allowed.find(text[index]) == std::string::npos) {
            return std::nullopt;
        }
        result.append(count.empty() ? 1 : std::stoi(count), text[index]);
        ++index;
    }
    return result;
}

std::string encode(const std::string& text) {
    std::string result;
    std::size_t start = 0;
    while (start < text.size()) {
        std::size_t end = start;
        while (end < text.size() && text[end] == text[start]) {
            ++end;
        }
        std::size_t run = end - start;
        if (run > 1) {
            result += std::to_string(run);
        }
        result += text[start];
        start = end;
    }
    return result;
}

std::string stepSequence(const std::string& word) {
    return lowered(*decode(word, STEP_LETTERS));
}

bool validArgument(Kind kind, const std::string& text) {
    switch (kind) {
    case Kind::Number:
        return std::regex_match(text, NUMBER_WORD);
    case Kind::Steps:
        return decode(text, STEP_LETTERS).has_value();
    case Kind::Direction:
        return text.size() == 1 && DIRECTIONS.find(text[0]) != std::string::npos;
    case Kind::Name:
        return std::regex_match(text, NAME_WORD);
    case Kind::Transform:
        return TURNS.count(text) > 0;
    case Kind::Text:
        break;
    }
    return true;
}

int pushCount(const std::string& letters) {
    return static_cast<int>(std::count_if(letters.begin(), letters.end(), isPush));
}

std::string turnLetters(const std::string& letters, const std::string& kind) {
    const std::string& turn = TURNS.at(kind);
    std::string turned;
    for (char letter : letters) {
        char direction = turn[DIRECTIONS.find(toLower(letter))];
        turned += isPush(letter) ? toUpper(direction) : direction;
    }
    return turned;
}

Boxes moveBox(Boxes boxes, int source, int destination) {
    std::replace(boxes.begin(), boxes.end(), source, destination);
    std::sort(boxes.begin(), boxes.end());
    return boxes;
}

std::string counted(const std::string& label, const std::string& letters) {
    if (letters.empty()) {
        return label + " 0";
    }
    return label + " " + std::to_string(letters.size()) + " " + letters;
}

std::vector<bool> findInterior(int height, int width, const std::vector<bool>& walls, int start) {
    std::vector<bool> interior(height * width, false);
    interior[start] = true;
    std::vector<int> stack = {start};
    while (!stack.empty()) {
        int cell = stack.back();
        stack.pop_back();
        int row = cell / width;
        int column = cell % width;
        for (const auto& [dRow, dColumn] : DELTAS) {
            int nextRow = row + dRow;
            int nextColumn = column + dColumn;
            if (nextRow >= 0 && nextRow < height && nextColumn >= 0 && nextColumn < width) {
                int neighbor = nextRow * width + nextColumn;
                if (!walls[neighbor] && !interior[neighbor]) {
                    interior[neighbor] = true;
                    stack.push_back(neighbor);
                }
            }
        }
    }
    return interior;
}

struct Level {
    int height = 0;
    int width = 0;
    int size = 0;
    std::vector<bool> walls;
    std::vector<bool> goals;
    std::vector<bool> interior;
    std::array<int, 4> offsets{};
    std::vector<int> goalCells;
    std::optional<std::string> reason;
    std::vector<std::vector<int>> distances;
    std::vector<bool> dead;

    Level() = default;

    Level(int height, int width, std::vector<bool> walls, std::vector<bool> goals,
          std::vector<bool> interior)
        : height(height), width(width), size(height * width), walls(std::move(walls)),
          goals(std::move(goals)), interior(std::move(interior)), dead(size, false) {
        for (std::size_t index = 0; index < DELTAS.size(); ++index) {
            offsets[index] = DELTAS[index].first * width + DELTAS[index].second;
        }
        for (int cell = 0; cell < size; ++cell) {
            if (this->goals[cell]) {
                goalCells.push_back(cell);
            }
        }
    }

    int offsetOf(char direction) const {
        return offsets[DIRECTIONS.find(direction)];
    }

    std::string cellText(int cell) const {
        return std::to_string(cell / width + 1) + " " + std::to_string(cell % width + 1);
    }

    int cellAt(int row, int column) const {
        return (row - 1) * width + column - 1;
    }

    bool contains(int row, int column) const {
        return 1 <= row && row <= height && 1 <= column && column <= width;
    }

    bool onBorder(int cell) const {
        int row = cell / width;
        int column = cell % width;
        return row == 0 || row == height - 1 || column == 0 || column == width - 1;
    }

    std::optional<std::string> invalidity(int players, const Boxes& boxes) const {
        if (players != 1) {
            return "players " + std::to_string(players);
        }
        if (boxes.empty()) {
            return "no boxes";
        }
        if (boxes.size() != goalCells.size()) {
            return "boxes " + std::to_string(boxes.size()) + " goals " +
                   std::to_string(goalCells.size());
        }
        for (int cell = 0; cell < size; ++cell) {
            if (interior[cell] && onBorder(cell)) {
                return "open " + cellText(cell);
            }
        }
        for (int cell = 0; cell < size; ++cell) {
            if ((goals[cell] || includes(boxes, cell)) && !interior[cell]) {
                return "outside " + cellText(cell);
            }
        }
        return std::nullopt;
    }

    void analyze() {
        distances.clear();
        for (int goal : goalCells) {
            distances.push_back(pushDistances(goal));
        }
        for (int cell = 0; cell < size; ++cell) {
            dead[cell] = interior[cell] && !goalDistance(cell);
        }
    }

    std::vector<int> pushDistances(int goal) const {
        std::vector<int> distance(size, UNDEFINED);
        distance[goal] = 0;
        std::queue<int> queue;
        queue.push(goal);
        while (!queue.empty()) {
            int cell = queue.front();
            queue.pop();
            for (int offset : offsets) {
                int box = cell - offset;
                if (interior[box] && interior[box - offset] && distance[box] == UNDEFINED) {
                    distance[box] = distance[cell] + 1;
                    queue.push(box);
                }
            }
        }
        return distance;
    }

    std::optional<int> goalDistance(int cell) const {
        std::optional<int> best;
        for (const std::vector<int>& distance : distances) {
            if (distance[cell] != UNDEFINED && (!best || distance[cell] < *best)) {
                best = distance[cell];
            }
        }
        return best;
    }

    int boxesOnGoals(const Boxes& boxes) const {
        return static_cast<int>(
            std::count_if(boxes.begin(), boxes.end(), [this](int box) { return goals[box]; }));
    }

    bool solved(const Boxes& boxes) const {
        return boxesOnGoals(boxes) == static_cast<int>(boxes.size());
    }

    std::vector<bool> reachable(int player, const Boxes& boxes) const {
        std::vector<bool> seen(size, false);
        seen[player] = true;
        std::vector<int> stack = {player};
        while (!stack.empty()) {
            int cell = stack.back();
            stack.pop_back();
            for (int offset : offsets) {
                int neighbor = cell + offset;
                if (interior[neighbor] && !seen[neighbor] && !includes(boxes, neighbor)) {
                    seen[neighbor] = true;
                    stack.push_back(neighbor);
                }
            }
        }
        return seen;
    }

    int representative(int player, const Boxes& boxes) const {
        return firstTrue(reachable(player, boxes));
    }

    std::string walkPath(int start, int target, const Boxes& boxes) const {
        std::vector<std::optional<std::pair<int, char>>> cameFrom(size);
        std::queue<int> queue;
        queue.push(start);
        while (!queue.empty()) {
            int cell = queue.front();
            queue.pop();
            for (char direction : DIRECTIONS) {
                int neighbor = cell + offsetOf(direction);
                if (interior[neighbor] && !includes(boxes, neighbor) && neighbor != start &&
                    !cameFrom[neighbor]) {
                    cameFrom[neighbor] = std::make_pair(cell, direction);
                    queue.push(neighbor);
                }
            }
        }
        std::string directions;
        int cell = target;
        while (cell != start) {
            auto [previous, direction] = *cameFrom[cell];
            directions += direction;
            cell = previous;
        }
        std::reverse(directions.begin(), directions.end());
        return directions;
    }

    std::pair<Position, char> step(const Position& position, char direction) const {
        int offset = offsetOf(direction);
        int target = position.player + offset;
        if (walls[target]) {
            throw StepFailure("wall");
        }
        if (!includes(position.boxes, target)) {
            return {Position{target, position.boxes}, direction};
        }
        int beyond = target + offset;
        if (walls[beyond] || includes(position.boxes, beyond)) {
            throw StepFailure("blocked");
        }
        return {Position{target, moveBox(position.boxes, target, beyond)}, toUpper(direction)};
    }

    bool pushable(int box, char direction, const Boxes& boxes,
                  const std::vector<bool>& reachableCells) const {
        int offset = offsetOf(direction);
        int destination = box + offset;
        return reachableCells[box - offset] && interior[destination] &&
               !includes(boxes, destination);
    }

    bool sideBlocked(int box, const std::array<int, 2>& sides, const Boxes& boxes,
                     const std::vector<int>& assumed) const {
        if (std::any_of(sides.begin(), sides.end(),
                        [&](int side) { return walls[side] || includes(assumed, side); })) {
            return true;
        }
        if (dead[sides[0]] && dead[sides[1]]) {
            return true;
        }
        std::vector<int> extended = assumed;
        extended.push_back(box);
        return std::any_of(sides.begin(), sides.end(), [&](int side) {
            return includes(boxes, side) && frozen(side, boxes, extended);
        });
    }

    bool frozen(int box, const Boxes& boxes, const std::vector<int>& assumed) const {
        std::array<int, 2> horizontal = {box + offsetOf('l'), box + offsetOf('r')};
        std::array<int, 2> vertical = {box + offsetOf('u'), box + offsetOf('d')};
        return sideBlocked(box, horizontal, boxes, assumed) &&
               sideBlocked(box, vertical, boxes, assumed);
    }

    bool hasFrozenBox(const Boxes& boxes) const {
        return std::any_of(boxes.begin(), boxes.end(),
                           [&](int box) { return !goals[box] && frozen(box, boxes, {}); });
    }

    std::vector<std::string> splitRows(const std::string& symbols) const {
        std::vector<std::string> rows;
        for (int start = 0; start < size; start += width) {
            rows.push_back(symbols.substr(start, width));
        }
        return rows;
    }

    char symbol(int cell, const Position& position) const {
        if (walls[cell]) {
            return '#';
        }
        if (cell == position.player) {
            return goals[cell] ? '+' : '@';
        }
        if (includes(position.boxes, cell)) {
            return goals[cell] ? '*' : '$';
        }
        return goals[cell] ? '.' : '-';
    }

    std::vector<std::string> render(const Position& position) const {
        std::string symbols;
        for (int cell = 0; cell < size; ++cell) {
            symbols += symbol(cell, position);
        }
        return splitRows(symbols);
    }

    char deadSymbol(int cell) const {
        if (walls[cell]) {
            return '#';
        }
        if (goals[cell]) {
            return '.';
        }
        return dead[cell] ? 'x' : '-';
    }

    std::vector<std::string> deadMap() const {
        std::string symbols;
        for (int cell = 0; cell < size; ++cell) {
            symbols += deadSymbol(cell);
        }
        return splitRows(symbols);
    }

    int mapCell(const std::string& kind, int cell) const {
        int row = cell / width;
        int column = cell % width;
        int lastRow = height - 1;
        int lastColumn = width - 1;
        if (kind == "ROT90") {
            return column * height + lastRow - row;
        }
        if (kind == "ROT180") {
            return (lastRow - row) * width + lastColumn - column;
        }
        if (kind == "ROT270") {
            return (lastColumn - column) * height + row;
        }
        if (kind == "FLIPH") {
            return row * width + lastColumn - column;
        }
        return (lastRow - row) * width + column;
    }

    Position mapPosition(const std::string& kind, const Position& position) const {
        Boxes boxes;
        for (int box : position.boxes) {
            boxes.push_back(mapCell(kind, box));
        }
        std::sort(boxes.begin(), boxes.end());
        return {mapCell(kind, position.player), boxes};
    }

    Level transformed(const std::string& kind) const {
        bool rotated = kind == "ROT90" || kind == "ROT270";
        std::vector<bool> movedWalls(size, false);
        std::vector<bool> movedGoals(size, false);
        std::vector<bool> movedInterior(size, false);
        for (int cell = 0; cell < size; ++cell) {
            int moved = mapCell(kind, cell);
            movedWalls[moved] = walls[cell];
            movedGoals[moved] = goals[cell];
            movedInterior[moved] = interior[cell];
        }
        Level level(rotated ? width : height, rotated ? height : width, movedWalls, movedGoals,
                    movedInterior);
        level.analyze();
        return level;
    }
};

std::pair<Level, Position> buildLevel(const std::vector<std::string>& rows) {
    int height = static_cast<int>(rows.size());
    int width = static_cast<int>(rows[0].size());
    std::string cells;
    for (const std::string& row : rows) {
        cells += row;
    }
    std::vector<bool> walls;
    std::vector<bool> goals;
    std::vector<int> players;
    Boxes boxes;
    for (int cell = 0; cell < static_cast<int>(cells.size()); ++cell) {
        char symbol = cells[cell];
        walls.push_back(symbol == '#');
        goals.push_back(symbol == '.' || symbol == '*' || symbol == '+');
        if (symbol == '@' || symbol == '+') {
            players.push_back(cell);
        }
        if (symbol == '$' || symbol == '*') {
            boxes.push_back(cell);
        }
    }
    std::vector<bool> interior = players.size() == 1
                                     ? findInterior(height, width, walls, players[0])
                                     : std::vector<bool>(cells.size(), false);
    Level level(height, width, walls, goals, interior);
    level.reason = level.invalidity(static_cast<int>(players.size()), boxes);
    if (!level.reason) {
        level.analyze();
    }
    int player = players.empty() ? -1 : players[0];
    return {level, Position{player, boxes}};
}

std::vector<Push> solutionPushes(const std::vector<SearchNode>& nodes) {
    std::vector<Push> pushes;
    for (const SearchNode* node = &nodes.back(); node->parent; node = &nodes[*node->parent]) {
        pushes.push_back(node->push);
    }
    std::reverse(pushes.begin(), pushes.end());
    return pushes;
}

std::string solutionNotation(const Level& level, Position position,
                             const std::vector<Push>& pushes) {
    std::string notation;
    for (const Push& push : pushes) {
        int offset = level.offsetOf(push.direction);
        notation += level.walkPath(position.player, push.box - offset, position.boxes);
        notation += toUpper(push.direction);
        position = Position{push.box, moveBox(position.boxes, push.box, push.box + offset)};
    }
    return notation;
}

SearchResult pushSearch(const Level& level, const Position& start, const Boxes& fixed,
                        std::optional<int> target, bool pruning,
                        std::optional<std::size_t> limit) {
    int startRepresentative = level.representative(start.player, start.boxes);
    std::vector<SearchNode> nodes = {{start.boxes, startRepresentative, std::nullopt, Push{}}};
    std::set<std::pair<Boxes, int>> known = {{start.boxes, startRepresentative}};
    std::size_t expanded = 0;
    while (expanded < nodes.size()) {
        if (limit && expanded == *limit) {
            return {"limit", expanded, nodes.size(), ""};
        }
        SearchNode node = nodes[expanded];
        ++expanded;
        std::vector<bool> reachable = level.reachable(node.representative, node.boxes);
        for (int box : node.boxes) {
            if (includes(fixed, box)) {
                continue;
            }
            for (char direction : DIRECTIONS) {
                if (!level.pushable(box, direction, node.boxes, reachable)) {
                    continue;
                }
                int destination = box + level.offsetOf(direction);
                Boxes boxes = moveBox(node.boxes, box, destination);
                if (pruning && (level.dead[destination] || level.hasFrozenBox(boxes))) {
                    continue;
                }
                int representative = level.representative(box, boxes);
                if (!known.insert({boxes, representative}).second) {
                    continue;
                }
                nodes.push_back({boxes, representative, expanded - 1, Push{box, direction}});
                bool reached = target ? destination == *target : level.solved(boxes);
                if (reached) {
                    std::string notation = solutionNotation(level, start, solutionPushes(nodes));
                    return {"found", expanded, nodes.size(), notation};
                }
            }
        }
    }
    return {"no solution", expanded, nodes.size(), ""};
}

class Sokoban {
public:
    explicit Sokoban(const std::vector<std::string>& rows) {
        load(rows);
    }

    void execute(const std::vector<std::string>& words, const std::vector<std::string>& rows) {
        try {
            if (words[0] == "LOAD") {
                loadRows(std::stoi(words[2]), rows);
            } else {
                runCommand(words[0], Arguments(words.begin() + 1, words.end()));
            }
        } catch (const CommandError& error) {
            emit("error:", error.what());
        }
    }

private:
    using Handler = void (Sokoban::*)(const Arguments&);

    struct Snapshot {
        Position position;
        std::string history;
    };

    struct Solution {
        std::string notation;
        Position position;
    };

    Level level;
    Position initial;
    Position current;
    std::string history;
    std::string redoList;
    std::map<std::string, Snapshot> snapshots;
    std::optional<Solution> solution;

    void load(const std::vector<std::string>& rows) {
        std::tie(level, initial) = buildLevel(rows);
        current = initial;
        history.clear();
        redoList.clear();
        snapshots.clear();
        solution.reset();
    }

    int cellArgument(const Arguments& arguments, std::size_t index) const {
        return level.cellAt(std::stoi(arguments[index]), std::stoi(arguments[index + 1]));
    }

    Simulation simulate(const std::string& directions) const {
        Position position = current;
        std::string letters;
        try {
            for (char direction : directions) {
                auto [next, letter] = level.step(position, direction);
                position = next;
                letters += letter;
            }
        } catch (const StepFailure& failure) {
            std::string reason =
                "step " + std::to_string(letters.size() + 1) + " " + failure.what();
            return {position, letters, reason};
        }
        return {position, letters, std::nullopt};
    }

    Simulation takeSteps(const std::string& directions) {
        Simulation simulation = simulate(directions);
        current = simulation.position;
        history += simulation.letters;
        if (!simulation.letters.empty()) {
            redoList.clear();
        }
        return simulation;
    }

    std::string progress(const Boxes& boxes) const {
        int onGoals = level.boxesOnGoals(boxes);
        std::string text = "goals " + std::to_string(onGoals) + "/" + std::to_string(boxes.size());
        return onGoals == static_cast<int>(boxes.size()) ? text + " solved" : text;
    }

    std::pair<std::string, std::optional<std::string>> searchSolution(int limit) const {
        if (level.solved(current.boxes)) {
            return {"already solved", std::nullopt};
        }
        SearchResult result = pushSearch(level, current, {}, std::nullopt, true, limit);
        std::string counts = "expanded " + std::to_string(result.expanded) + " states " +
                             std::to_string(result.states);
        if (result.outcome != "found") {
            return {result.outcome + " " + counts, std::nullopt};
        }
        const std::string& notation = result.notation;
        std::string summary = "solution pushes " + std::to_string(pushCount(notation)) +
                              " moves " + std::to_string(notation.size()) + " " + counts;
        return {summary, notation};
    }

    void loadRows(int width, const std::vector<std::string>& rows) {
        for (std::size_t number = 1; number <= rows.size(); ++number) {
            const std::string& row = rows[number - 1];
            if (static_cast<int>(row.size()) != width ||
                row.find_first_not_of(LEVEL_CHARACTERS) != std::string::npos) {
                throw CommandError("bad row " + std::to_string(number));
            }
        }
        load(rows);
        emit("loaded", dimensions(static_cast<int>(rows.size()), width));
    }

    void importLevel(const Arguments& arguments) {
        std::vector<std::string> rows;
        for (const std::string& part : split(arguments[0], '|')) {
            std::optional<std::string> row = decode(part, LEVEL_CHARACTERS);
            if (!row) {
                throw CommandError("bad level");
            }
            rows.push_back(*row);
        }
        if (rows.size() > MAX_SIDE) {
            throw CommandError("bad level");
        }
        std::size_t width = rows[0].size();
        bool uneven = std::any_of(rows.begin(), rows.end(),
                                  [width](const std::string& row) { return row.size() != width; });
        if (uneven || width < 1 || width > MAX_SIDE) {
            throw CommandError("bad level");
        }
        load(rows);
        emit("loaded", dimensions(static_cast<int>(rows.size()), static_cast<int>(width)));
    }

    void valid(const Arguments&) {
        if (level.reason) {
            emit("invalid", *level.reason);
        } else {
            emit("valid");
        }
    }

    void info(const Arguments&) {
        emit("size", dimensions(level.height, level.width), "walls", countTrue(level.walls),
             "cells", countTrue(level.interior), "boxes", current.boxes.size(), "dead",
             countTrue(level.dead));
    }

    void show(const Arguments&) {
        for (const std::string& row : level.render(current)) {
            emit(row);
        }
    }

    void exportLevel(const Arguments&) {
        std::string text;
        for (const std::string& row : level.render(current)) {
            if (!text.empty()) {
                text += '|';
            }
            text += encode(row);
        }
        emit("level", text);
    }

    void move(const Arguments& arguments) {
        Simulation simulation = takeSteps(stepSequence(arguments[0]));
        if (!simulation.letters.empty()) {
            emit("moved", simulation.letters);
        }
        if (simulation.failure) {
            throw CommandError(*simulation.failure);
        }
    }

    void push(const Arguments& arguments) {
        int box = cellArgument(arguments, 0);
        char direction = arguments[2][0];
        int offset = level.offsetOf(direction);
        if (!includes(current.boxes, box)) {
            throw CommandError("no box");
        }
        int destination = box + offset;
        if (!level.interior[destination] || includes(current.boxes, destination)) {
            throw CommandError("blocked");
        }
        if (!level.reachable(current.player, current.boxes)[box - offset]) {
            throw CommandError("unreachable");
        }
        std::string path = level.walkPath(current.player, box - offset, current.boxes);
        emit("pushed", takeSteps(path + direction).letters);
    }

    void bring(const Arguments& arguments) {
        int source = cellArgument(arguments, 0);
        int target = cellArgument(arguments, 2);
        if (!includes(current.boxes, source)) {
            throw CommandError("no box");
        }
        if (source == target) {
            emit("brought", 0);
            return;
        }
        Boxes fixed;
        std::copy_if(current.boxes.begin(), current.boxes.end(), std::back_inserter(fixed),
                     [source](int box) { return box != source; });
        SearchResult result = pushSearch(level, current, fixed, target, false, std::nullopt);
        if (result.outcome != "found") {
            throw CommandError("no route");
        }
        takeSteps(lowered(result.notation));
        emit("brought", pushCount(result.notation), result.notation);
    }

    void path(const Arguments& arguments) {
        int target = cellArgument(arguments, 0);
        if (!level.reachable(current.player, current.boxes)[target]) {
            throw CommandError("unreachable");
        }
        Simulation simulation = takeSteps(level.walkPath(current.player, target, current.boxes));
        emit(counted("path", simulation.letters));
    }

    void undo(const Arguments& arguments) {
        if (history.empty()) {
            throw CommandError("nothing to undo");
        }
        std::size_t count = std::min<std::size_t>(std::stoi(arguments[0]), history.size());
        for (std::size_t index = 0; index < count; ++index) {
            char letter = history.back();
            history.pop_back();
            char direction = toLower(letter);
            int offset = level.offsetOf(direction);
            int player = current.player;
            Boxes boxes = current.boxes;
            if (isPush(letter)) {
                boxes = moveBox(boxes, player + offset, player);
            }
            current = Position{player - offset, boxes};
            redoList += direction;
        }
        emit("undone", count);
    }

    void redo(const Arguments& arguments) {
        if (redoList.empty()) {
            throw CommandError("nothing to redo");
        }
        std::size_t count = std::min<std::size_t>(std::stoi(arguments[0]), redoList.size());
        for (std::size_t index = 0; index < count; ++index) {
            char direction = redoList.back();
            redoList.pop_back();
            auto [position, letter] = level.step(current, direction);
            current = position;
            history += letter;
        }
        emit("redone", count);
    }

    void reset(const Arguments&) {
        current = initial;
        history.clear();
        redoList.clear();
        emit("reset");
    }

    void status(const Arguments&) {
        emit("moves", history.size(), "pushes", pushCount(history), progress(current.boxes));
    }

    void showHistory(const Arguments&) {
        emit(counted("history", history));
    }

    void showBoxes(const Arguments&) {
        std::vector<bool> reachable = level.reachable(current.player, current.boxes);
        emit("boxes", current.boxes.size());
        for (int box : current.boxes) {
            std::optional<int> distance = level.goalDistance(box);
            std::string directions;
            for (char direction : DIRECTIONS) {
                if (level.pushable(box, direction, current.boxes, reachable)) {
                    directions += direction;
                }
            }
            emit("box", level.cellText(box), distance ? std::to_string(*distance) : "dead",
                 directions.empty() ? "-" : directions);
        }
    }

    void reach(const Arguments&) {
        std::vector<bool> reachable = level.reachable(current.player, current.boxes);
        emit("reach", countTrue(reachable), "first", level.cellText(firstTrue(reachable)));
    }

    void deadSquares(const Arguments&) {
        emit("dead", countTrue(level.dead));
        for (const std::string& row : level.deadMap()) {
            emit(row);
        }
    }

    void deadlock(const Arguments&) {
        for (int box : current.boxes) {
            if (level.dead[box]) {
                emit("deadlock", "dead", level.cellText(box));
                return;
            }
        }
        for (int box : current.boxes) {
            if (!level.goals[box] && level.frozen(box, current.boxes, {})) {
                emit("deadlock", "frozen", level.cellText(box));
                return;
            }
        }
        emit("no deadlock");
    }

    void bound(const Arguments&) {
        const Boxes& boxes = current.boxes;
        std::vector<int> order(level.goalCells.size());
        std::iota(order.begin(), order.end(), 0);
        std::optional<Assignment> best;
        do {
            std::vector<int> pushes;
            for (std::size_t index = 0; index < boxes.size(); ++index) {
                pushes.push_back(level.distances[order[index]][boxes[index]]);
            }
            if (includes(pushes, UNDEFINED)) {
                continue;
            }
            int total = std::accumulate(pushes.begin(), pushes.end(), 0);
            if (!best || total < best->total) {
                best = Assignment{order, pushes, total};
            }
        } while (std::next_permutation(order.begin(), order.end()));
        if (!best) {
            emit("bound", "none");
            return;
        }
        emit("bound", best->total);
        for (std::size_t index = 0; index < boxes.size(); ++index) {
            int goal = level.goalCells[best->order[index]];
            emit("box", level.cellText(boxes[index]), "goal", level.cellText(goal), "pushes",
                 best->pushes[index]);
        }
    }

    void save(const Arguments& arguments) {
        const std::string& name = arguments[0];
        snapshots[name] = Snapshot{current, history};
        emit("saved", name, "moves", history.size());
    }

    void restore(const Arguments& arguments) {
        const std::string& name = arguments[0];
        auto snapshot = snapshots.find(name);
        if (snapshot == snapshots.end()) {
            throw CommandError("no snapshot " + name);
        }
        current = snapshot->second.position;
        history = snapshot->second.history;
        redoList.clear();
        emit("restored", name, "moves", history.size());
    }

    void check(const Arguments& arguments) {
        Simulation simulation = simulate(stepSequence(arguments[0]));
        if (simulation.failure) {
            emit("check", "fail", *simulation.failure);
            return;
        }
        emit("check", "ok", "moves", simulation.letters.size(), "pushes",
             pushCount(simulation.letters), progress(simulation.position.boxes));
    }

    void solve(const Arguments& arguments) {
        auto [summary, notation] = searchSolution(std::stoi(arguments[0]));
        emit(summary);
        solution.reset();
        if (notation) {
            emit(*notation);
            solution = Solution{*notation, current};
        }
    }

    void hint(const Arguments& arguments) {
        auto [summary, notation] = searchSolution(std::stoi(arguments[0]));
        if (!notation) {
            emit(summary);
            return;
        }
        std::string part(notation->begin(),
                         std::find_if(notation->begin(), notation->end(), isPush) + 1);
        takeSteps(lowered(part));
        emit("hint", part);
    }

    void play(const Arguments&) {
        if (!solution || !solution->position.same(current)) {
            throw CommandError("no solution");
        }
        std::string notation = solution->notation;
        takeSteps(lowered(notation));
        emit("played", "pushes", pushCount(notation), "moves", notation.size());
    }

    void transform(const Arguments& arguments) {
        const std::string& kind = arguments[0];
        Level old = level;
        level = old.transformed(kind);
        initial = old.mapPosition(kind, initial);
        current = old.mapPosition(kind, current);
        history = turnLetters(history, kind);
        redoList = turnLetters(redoList, kind);
        for (auto& entry : snapshots) {
            Snapshot& snapshot = entry.second;
            snapshot = Snapshot{old.mapPosition(kind, snapshot.position),
                                turnLetters(snapshot.history, kind)};
        }
        if (solution) {
            solution = Solution{turnLetters(solution->notation, kind),
                                old.mapPosition(kind, solution->position)};
        }
        emit("transformed", dimensions(level.height, level.width));
    }

    void checkValues(const std::string& name, const Arguments& arguments) const {
        auto cells = CELL_COUNTS.find(name);
        int cellCount = cells == CELL_COUNTS.end() ? 0 : cells->second;
        for (int index = 0; index < 2 * cellCount; index += 2) {
            if (!level.contains(std::stoi(arguments[index]), std::stoi(arguments[index + 1]))) {
                throw CommandError("bad value");
            }
        }
        if ((name == "UNDO" || name == "REDO") && std::stoi(arguments[0]) < 1) {
            throw CommandError("bad value");
        }
        if (name == "SOLVE" || name == "HINT") {
            int limit = std::stoi(arguments[0]);
            if (limit < 1 || limit > MAX_LIMIT) {
                throw CommandError("bad value");
            }
        }
    }

    void runCommand(const std::string& name, const Arguments& arguments) {
        static const std::map<std::string, Handler> handlers = {
            {"IMPORT", &Sokoban::importLevel},
            {"VALID", &Sokoban::valid},
            {"INFO", &Sokoban::info},
            {"SHOW", &Sokoban::show},
            {"EXPORT", &Sokoban::exportLevel},
            {"MOVE", &Sokoban::move},
            {"PUSH", &Sokoban::push},
            {"BRING", &Sokoban::bring},
            {"PATH", &Sokoban::path},
            {"UNDO", &Sokoban::undo},
            {"REDO", &Sokoban::redo},
            {"RESET", &Sokoban::reset},
            {"STATUS", &Sokoban::status},
            {"HISTORY", &Sokoban::showHistory},
            {"BOXES", &Sokoban::showBoxes},
            {"REACH", &Sokoban::reach},
            {"DEADSQUARES", &Sokoban::deadSquares},
            {"DEADLOCK", &Sokoban::deadlock},
            {"BOUND", &Sokoban::bound},
            {"SAVE", &Sokoban::save},
            {"RESTORE", &Sokoban::restore},
            {"CHECK", &Sokoban::check},
            {"SOLVE", &Sokoban::solve},
            {"HINT", &Sokoban::hint},
            {"PLAY", &Sokoban::play},
            {"TRANSFORM", &Sokoban::transform},
        };
        auto command = COMMANDS.find(name);
        if (command == COMMANDS.end()) {
            throw CommandError("unknown command " + name);
        }
        const std::vector<Kind>& kinds = command->second;
        if (arguments.size() != kinds.size() ||
            !std::equal(kinds.begin(), kinds.end(), arguments.begin(), validArgument)) {
            throw CommandError("bad arguments");
        }
        if (LEVEL_FREE_COMMANDS.count(name) == 0) {
            if (level.reason) {
                throw CommandError("invalid level");
            }
            checkValues(name, arguments);
        }
        (this->*handlers.at(name))(arguments);
    }
};

std::vector<std::string> readRows(int count) {
    std::vector<std::string> rows;
    std::string row;
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, row);
        rows.push_back(row);
    }
    return rows;
}

}

int main() {
    std::ios::sync_with_stdio(false);
    std::string line;
    std::getline(std::cin, line);
    int height = std::stoi(split(line, ' ')[0]);
    Sokoban game(readRows(height));
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, line);
        std::vector<std::string> words = split(line, ' ');
        std::vector<std::string> rows;
        if (words[0] == "LOAD") {
            rows = readRows(std::stoi(words[1]));
        }
        game.execute(words, rows);
    }
    return 0;
}
