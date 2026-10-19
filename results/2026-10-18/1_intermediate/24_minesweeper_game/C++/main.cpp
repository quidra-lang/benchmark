#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <iterator>
#include <map>
#include <numeric>
#include <optional>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

using std::string;
using std::vector;

enum class State { Ready, Playing, Won, Lost };
enum class Mark { None, Flag, Question };

struct CommandError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

[[noreturn]] void fail(const string& message) { throw CommandError(message); }

string stateName(State state) {
    switch (state) {
        case State::Ready: return "ready";
        case State::Playing: return "playing";
        case State::Won: return "won";
        case State::Lost: return "lost";
    }
    throw std::logic_error("Invalid state");
}

string markName(Mark mark) {
    return mark == Mark::Flag ? "flag" : mark == Mark::Question ? "question" : "none";
}

struct Move { string kind; int cell; };
struct Snapshot {
    string command;
    vector<bool> visible;
    vector<Mark> marks;
    std::size_t moveCount;
};
struct Constraint { int source; vector<int> cells; int remaining; };
struct Component { vector<int> cells; vector<Constraint> constraints; };
struct Deduction { std::map<int, string> safe, mines; };
struct Totals { int rounds = 0, flagged = 0, opened = 0, guesses = 0; };
struct Configurations {
    int count = 0, minimum = 0, maximum = 0;
    vector<int> frequencies;
};

Configurations countConfigurations(const Component& component) {
    const int size = static_cast<int>(component.cells.size());
    const int count = static_cast<int>(component.constraints.size());
    Configurations result{0, size, 0, vector<int>(size)};
    std::unordered_map<int, int> positions;
    for (int i = 0; i < size; ++i) positions[component.cells[i]] = i;
    vector<vector<int>> incidence(size);
    vector<int> assigned(count), unassigned(count), target(count);
    for (int i = 0; i < count; ++i) {
        const Constraint& constraint = component.constraints[i];
        target[i] = constraint.remaining;
        unassigned[i] = static_cast<int>(constraint.cells.size());
        if (target[i] < 0 || target[i] > unassigned[i]) return result;
        for (int cell : constraint.cells) incidence[positions.at(cell)].push_back(i);
    }
    vector<int> order(size), values(size);
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return incidence[a].size() != incidence[b].size() ? incidence[a].size() > incidence[b].size() : a < b;
    });
    std::function<void(int, int)> search = [&](int depth, int mines) {
        if (depth == size) {
            ++result.count;
            result.minimum = std::min(result.minimum, mines);
            result.maximum = std::max(result.maximum, mines);
            for (int i = 0; i < size; ++i) result.frequencies[i] += values[i];
            return;
        }
        const int cell = order[depth];
        for (int value = 0; value <= 1; ++value) {
            values[cell] = value;
            bool possible = true;
            for (int index : incidence[cell]) {
                assigned[index] += value;
                --unassigned[index];
                if (assigned[index] > target[index] || assigned[index] + unassigned[index] < target[index]) possible = false;
            }
            if (possible) search(depth + 1, mines + value);
            for (int index : incidence[cell]) {
                assigned[index] -= value;
                ++unassigned[index];
            }
        }
        values[cell] = 0;
    };
    search(0, 0);
    return result;
}

struct Board {
    int width, height, mineCount, size;
    std::int64_t seed;
    vector<bool> mines, visible;
    vector<int> numbers;
    vector<vector<int>> neighbors;
    vector<Mark> marks;
    vector<Move> moves;
    vector<Snapshot> undo;
    State state = State::Ready;
    int exploded = -1;

    Board(int width, int height, int mineCount, std::int64_t seed)
        : width(width), height(height), mineCount(mineCount), size(width * height), seed(seed),
          numbers(size), neighbors(size) {
        for (int cell = 0; cell < size; ++cell) {
            const int x = cell % width, y = cell / width;
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    if ((dx == 0 && dy == 0) || x + dx < 0 || x + dx >= width || y + dy < 0 || y + dy >= height) continue;
                    neighbors[cell].push_back((y + dy) * width + x + dx);
                }
            }
        }
        restart();
    }

    void restart() {
        visible.assign(size, false);
        marks.assign(size, Mark::None);
        moves.clear();
        undo.clear();
        exploded = -1;
        state = mines.empty() ? State::Ready : State::Playing;
    }

    string coordinate(int cell) const { return std::to_string(cell % width) + "," + std::to_string(cell / width); }
    bool finished() const { return state == State::Won || state == State::Lost; }
    int safeCount() const { return size - mineCount; }
    int revealedCount() const { return static_cast<int>(std::count(visible.begin(), visible.end(), true)); }
    int remaining() const { return mineCount - static_cast<int>(std::count(marks.begin(), marks.end(), Mark::Flag)); }
    bool unknown(int cell) const { return !visible[cell] && marks[cell] != Mark::Flag; }

    void determine(vector<bool> placement) {
        mines = std::move(placement);
        std::fill(numbers.begin(), numbers.end(), 0);
        for (int cell = 0; cell < size; ++cell) {
            for (int next : neighbors[cell]) numbers[cell] += mines[next];
        }
        state = State::Playing;
    }

    void place(int first, const string& safety) {
        vector<int> candidates;
        const int x = first % width, y = first / width;
        for (int cell = 0; cell < size; ++cell) {
            if (safety == "none" || (safety == "cell" && cell != first) ||
                (safety == "block" && (std::abs(cell % width - x) >= 2 || std::abs(cell / width - y) >= 2))) candidates.push_back(cell);
        }
        vector<bool> placement(size);
        std::int64_t random = seed;
        for (int i = 0; i < mineCount; ++i) {
            random = 48271 * random % 2147483647;
            const std::size_t index = static_cast<std::size_t>(random) % candidates.size();
            placement[candidates[index]] = true;
            candidates.erase(candidates.begin() + static_cast<std::ptrdiff_t>(index));
        }
        determine(std::move(placement));
    }

    int reveal(int cell, const string& safety) {
        if (mines.empty()) place(cell, safety);
        if (mines[cell]) {
            state = State::Lost;
            exploded = cell;
            return 0;
        }
        vector<int> queue{cell};
        visible[cell] = true;
        marks[cell] = Mark::None;
        for (std::size_t head = 0; head < queue.size(); ++head) {
            if (numbers[queue[head]] != 0) continue;
            for (int next : neighbors[queue[head]]) {
                if (!unknown(next)) continue;
                visible[next] = true;
                marks[next] = Mark::None;
                queue.push_back(next);
            }
        }
        return static_cast<int>(queue.size());
    }

    int chord(int cell, const string& safety) {
        int opened = 0;
        for (int next : neighbors[cell]) {
            if (unknown(next)) opened += reveal(next, safety);
            if (state == State::Lost) break;
        }
        return opened;
    }

    void checkWin() {
        if (state != State::Playing || revealedCount() != safeCount()) return;
        state = State::Won;
        for (int cell = 0; cell < size; ++cell) if (mines[cell]) marks[cell] = Mark::Flag;
    }

    vector<string> display() const {
        vector<string> rows(height, string(width, '#'));
        for (int cell = 0; cell < size; ++cell) {
            char character = marks[cell] == Mark::Flag ? 'F' : marks[cell] == Mark::Question ? '?' : '#';
            if (visible[cell]) character = numbers[cell] == 0 ? '.' : static_cast<char>('0' + numbers[cell]);
            if (state == State::Lost) {
                if (mines[cell]) character = cell == exploded ? '!' : marks[cell] == Mark::Flag ? 'F' : '*';
                else if (marks[cell] == Mark::Flag) character = 'X';
            }
            rows[cell / width][cell % width] = character;
        }
        return rows;
    }

    void appendFinish(vector<string>& output) const {
        if (state == State::Lost) {
            output.push_back("boom " + coordinate(exploded));
            const vector<string> rows = display();
            output.insert(output.end(), rows.begin(), rows.end());
        } else if (state == State::Won) output.push_back("win moves " + std::to_string(moves.size()));
    }

    vector<Constraint> constraints() const {
        vector<Constraint> result;
        for (int cell = 0; cell < size; ++cell) {
            if (!visible[cell] || numbers[cell] == 0) continue;
            Constraint constraint{cell, {}, numbers[cell]};
            for (int next : neighbors[cell]) {
                if (unknown(next)) constraint.cells.push_back(next);
                if (marks[next] == Mark::Flag) --constraint.remaining;
            }
            if (!constraint.cells.empty()) result.push_back(std::move(constraint));
        }
        return result;
    }

    vector<Component> frontier() const {
        const vector<Constraint> rules = constraints();
        vector<int> parent(size);
        std::iota(parent.begin(), parent.end(), 0);
        const auto root = [&](int cell) {
            while (parent[cell] != cell) {
                parent[cell] = parent[parent[cell]];
                cell = parent[cell];
            }
            return cell;
        };
        vector<bool> present(size);
        for (const Constraint& c : rules) {
            for (int cell : c.cells) {
                present[cell] = true;
                parent[root(cell)] = root(c.cells.front());
            }
        }
        std::unordered_map<int, std::size_t> groups;
        vector<Component> result;
        for (int cell = 0; cell < size; ++cell) {
            if (!present[cell]) continue;
            const int representative = root(cell);
            if (groups.find(representative) == groups.end()) {
                groups[representative] = result.size();
                result.push_back({{}, {}});
            }
            result[groups.at(representative)].cells.push_back(cell);
        }
        for (const Constraint& c : rules) result[groups.at(root(c.cells.front()))].constraints.push_back(c);
        return result;
    }

    Totals automatic(const string& safety) {
        Totals totals;
        while (state == State::Playing) {
            const Deduction deduction = deduce();
            if (deduction.safe.empty() && deduction.mines.empty()) break;
            ++totals.rounds;
            for (const auto& [cell, reason] : deduction.safe) {
                if (visible[cell]) continue;
                moves.push_back({"auto-reveal", cell});
                totals.opened += reveal(cell, safety);
                checkWin();
                if (finished()) return totals;
            }
            for (const auto& [cell, reason] : deduction.mines) {
                if (!unknown(cell)) continue;
                marks[cell] = Mark::Flag;
                ++totals.flagged;
                moves.push_back({"auto-flag", cell});
            }
        }
        return totals;
    }

    Totals solve(const string& safety) {
        Totals totals;
        while (!finished()) {
            const Totals step = automatic(safety);
            totals.rounds += step.rounds;
            totals.flagged += step.flagged;
            totals.opened += step.opened;
            if (finished()) break;
            vector<bool> onFrontier(size);
            vector<int> numerator(size), denominator(size);
            for (const Component& component : frontier()) {
                const Configurations counts = countConfigurations(component);
                for (std::size_t i = 0; i < component.cells.size(); ++i) {
                    const int cell = component.cells[i];
                    onFrontier[cell] = true;
                    numerator[cell] = counts.frequencies[i];
                    denominator[cell] = counts.count;
                }
            }
            int unknownCount = 0;
            for (int cell = 0; cell < size; ++cell) if (unknown(cell)) ++unknownCount;
            const int unconstrainedNumerator = std::max(remaining(), 0);
            int chosen = -1, bestNumerator = 0, bestDenominator = 1;
            for (int cell = 0; cell < size; ++cell) {
                if (!unknown(cell)) continue;
                const int a = onFrontier[cell] ? numerator[cell] : unconstrainedNumerator;
                const int b = onFrontier[cell] ? denominator[cell] : unknownCount;
                if (b == 0) continue;
                if (chosen == -1 || a * bestDenominator < bestNumerator * b) {
                    chosen = cell;
                    bestNumerator = a;
                    bestDenominator = b;
                }
            }
            if (chosen == -1) break;
            ++totals.guesses;
            moves.push_back({"guess", chosen});
            totals.opened += reveal(chosen, safety);
            checkWin();
        }
        return totals;
    }

    vector<string> replay(std::size_t count, const string& safety) const {
        Board copy = *this;
        copy.restart();
        for (std::size_t i = 0; i < count; ++i) {
            const Move& move = moves[i];
            if (move.kind == "reveal" || move.kind == "auto-reveal" || move.kind == "guess") copy.reveal(move.cell, safety);
            else if (move.kind == "chord") copy.chord(move.cell, safety);
            else if (move.kind == "flag" || move.kind == "auto-flag") copy.marks[move.cell] = Mark::Flag;
            else if (move.kind == "unflag") copy.marks[move.cell] = Mark::None;
            else copy.marks[move.cell] = copy.marks[move.cell] == Mark::Question ? Mark::None : Mark::Question;
            copy.checkWin();
        }
        return copy.display();
    }

    string boardInfo() const {
        vector<bool> visited(size);
        int openings = 0, largest = 0, isolated = 0;
        for (int cell = 0; cell < size; ++cell) {
            if (mines[cell]) continue;
            if (numbers[cell] != 0) {
                if (std::none_of(neighbors[cell].begin(), neighbors[cell].end(), [&](int next) {
                    return !mines[next] && numbers[next] == 0;
                })) ++isolated;
                continue;
            }
            if (visited[cell]) continue;
            ++openings;
            vector<int> queue{cell};
            std::set<int> opening{cell};
            visited[cell] = true;
            for (std::size_t head = 0; head < queue.size(); ++head) {
                for (int next : neighbors[queue[head]]) {
                    opening.insert(next);
                    if (!mines[next] && numbers[next] == 0 && !visited[next]) {
                        visited[next] = true;
                        queue.push_back(next);
                    }
                }
            }
            largest = std::max(largest, static_cast<int>(opening.size()));
        }
        return "3bv " + std::to_string(openings + isolated) + " openings " + std::to_string(openings) +
            " largest " + std::to_string(largest) + " mines " + std::to_string(mineCount) + " safe " + std::to_string(safeCount());
    }

    Deduction deduce() const {
        const vector<Constraint> rules = constraints();
        Deduction result;
        for (const Constraint& c : rules) {
            if (c.remaining == 0) for (int cell : c.cells) result.safe.emplace(cell, "single " + coordinate(c.source));
        }
        if (!result.safe.empty()) return result;
        for (const Constraint& c : rules) {
            if (c.remaining == static_cast<int>(c.cells.size())) {
                for (int cell : c.cells) result.mines.emplace(cell, "single " + coordinate(c.source));
            }
        }
        if (!result.mines.empty()) return result;
        for (const Constraint& a : rules) {
            for (const Constraint& b : rules) {
                if (a.cells.size() >= b.cells.size() || !std::includes(b.cells.begin(), b.cells.end(), a.cells.begin(), a.cells.end())) continue;
                vector<int> difference;
                std::set_difference(b.cells.begin(), b.cells.end(), a.cells.begin(), a.cells.end(), std::back_inserter(difference));
                const int remaining = b.remaining - a.remaining;
                const string reason = "subset " + coordinate(a.source) + " " + coordinate(b.source);
                for (int cell : difference) {
                    if (remaining == 0) result.safe.emplace(cell, reason);
                    if (remaining == static_cast<int>(difference.size())) result.mines.emplace(cell, reason);
                }
            }
        }
        if (result.safe.empty() && result.mines.empty() && state == State::Playing && remaining() == 0) {
            for (int cell = 0; cell < size; ++cell) if (unknown(cell)) result.safe.emplace(cell, "count");
        }
        return result;
    }
};

const std::map<string, string> formats{
    {"NEW", "nnnn"}, {"PRESET", "pn"}, {"SAFETY", "s"}, {"RESTART", ""},
    {"REVEAL", "nn"}, {"FLAG", "nn"}, {"UNFLAG", "nn"}, {"QUESTION", "nn"}, {"CHORD", "nn"},
    {"UNDO", ""}, {"SHOW", ""}, {"STATUS", ""}, {"CELL", "nn"}, {"HISTORY", "n"}, {"REPLAY", "n"},
    {"HINT", ""}, {"AUTO", ""}, {"ANALYZE", ""}, {"PROB", "nn"}, {"FRONTIER", ""},
    {"SOLVE", ""}, {"BOARDINFO", ""}, {"STATS", ""}
};
const std::map<string, vector<int>> presets{
    {"beginner", {9, 9, 10}}, {"intermediate", {16, 16, 40}}, {"expert", {30, 16, 99}}
};
const std::set<string> cellCommands{"REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "CELL", "PROB"};
const std::set<string> liveCommands{"REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "UNDO", "HINT", "AUTO", "ANALYZE", "PROB", "FRONTIER", "SOLVE"};
const std::set<string> undoCommands{"REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "AUTO", "SOLVE"};

struct Statistics {
    int played = 0, won = 0, lost = 0, streak = 0, best = 0;
    std::optional<std::size_t> fastest;

    void finish(const Board& board) {
        ++played;
        if (board.state == State::Won) {
            ++won;
            ++streak;
            best = std::max(best, streak);
            fastest = std::min(fastest.value_or(board.moves.size()), board.moves.size());
        } else {
            ++lost;
            streak = 0;
        }
    }

    string display() const {
        const string rate = played == 0 ? "-" : std::to_string(won * 100 / played) + "%";
        return "stats played " + std::to_string(played) + " won " + std::to_string(won) +
            " lost " + std::to_string(lost) + " rate " + rate + " streak " + std::to_string(streak) +
            " best " + std::to_string(best) + " fastest " + (fastest ? std::to_string(*fastest) : "-");
    }
};

struct Program {
    std::optional<Board> game;
    string safety = "block";
    Statistics stats;

    vector<string> execute(const vector<string>& words, const vector<string>& rows) {
        const string& command = words.front();
        if (command == "LAYOUT") {
            const int width = std::stoi(words[1]), height = std::stoi(words[2]);
            vector<bool> mines;
            for (std::size_t i = 0; i < rows.size(); ++i) {
                if (rows[i].size() != static_cast<std::size_t>(width) || rows[i].find_first_not_of("*.") != string::npos) {
                    fail("bad row " + std::to_string(i + 1));
                }
                for (char cell : rows[i]) mines.push_back(cell == '*');
            }
            const int count = static_cast<int>(std::count(mines.begin(), mines.end(), true));
            if (count == 0 || count == width * height) fail("bad mine count " + std::to_string(count));
            game.emplace(width, height, count, 1);
            game->determine(std::move(mines));
            return {"layout " + std::to_string(width) + "x" + std::to_string(height) + " mines " + std::to_string(count)};
        }
        const auto format = formats.find(command);
        if (format == formats.end()) fail("unknown command " + command);
        if (words.size() - 1 != format->second.size()) fail("bad arguments");
        static const std::regex numberWord("(0|[1-9][0-9]{0,9})");
        vector<std::int64_t> values(words.size() - 1);
        for (std::size_t i = 1; i < words.size(); ++i) {
            const char kind = format->second[i - 1];
            const bool valid = kind == 'n' ? std::regex_match(words[i], numberWord) : kind == 'p' ?
                presets.count(words[i]) != 0 : words[i] == "block" || words[i] == "cell" || words[i] == "none";
            if (!valid) fail("bad arguments");
            if (kind == 'n') values[i - 1] = std::stoll(words[i]);
        }
        if (command == "NEW" || command == "PRESET") {
            std::int64_t width, height, count, seed;
            if (command == "NEW") {
                width = values[0]; height = values[1]; count = values[2]; seed = values[3];
            } else {
                const vector<int>& preset = presets.at(words[1]);
                width = preset[0]; height = preset[1]; count = preset[2]; seed = values[1];
            }
            if (width < 1 || width > 30 || height < 1 || height > 30 || count < 1 || count > width * height - 9 || seed < 1 || seed > 2147483646) fail("bad value");
            game.emplace(static_cast<int>(width), static_cast<int>(height), static_cast<int>(count), seed);
            return {"new " + std::to_string(width) + "x" + std::to_string(height) + " mines " + std::to_string(count)};
        }
        if (command == "HISTORY" && values[0] == 0) fail("bad value");
        if (command == "SAFETY") {
            safety = words[1];
            return {"safety " + safety};
        }
        if (command == "STATS") return {stats.display()};
        if (!game) fail("no game");
        Board& board = *game;
        int cell = -1;
        if (cellCommands.count(command)) {
            if (values[0] >= board.width || values[1] >= board.height) fail("out of range");
            cell = static_cast<int>(values[1] * board.width + values[0]);
        }
        if (liveCommands.count(command) && board.finished()) fail("game over");
        if ((command == "ANALYZE" || command == "BOARDINFO") && board.state == State::Ready) fail("not started");
        string lowercase = command;
        for (char& character : lowercase) character = static_cast<char>(character - 'A' + 'a');
        std::optional<Snapshot> snapshot;
        if (undoCommands.count(command)) snapshot = Snapshot{lowercase, board.visible, board.marks, board.moves.size()};
        vector<string> output = boardCommand(command, values, cell, board);
        if (snapshot && board.moves.size() > snapshot->moveCount) board.undo.push_back(std::move(*snapshot));
        if ((command == "REVEAL" || command == "CHORD" || command == "AUTO" || command == "SOLVE") && board.finished()) stats.finish(board);
        return output;
    }

    vector<string> boardCommand(const string& command, const vector<std::int64_t>& values, int cell, Board& board) {
        if (command == "RESTART") {
            board.restart();
            return {"restart " + std::to_string(board.width) + "x" + std::to_string(board.height) + " mines " + std::to_string(board.mineCount)};
        }
        if (command == "REVEAL" || command == "FLAG" || command == "UNFLAG" || command == "QUESTION") {
            if (board.visible[cell]) fail("already revealed");
            const Mark mark = board.marks[cell];
            if (command == "REVEAL" && mark == Mark::Flag) fail("flagged");
            if (command == "FLAG" && mark == Mark::Flag) fail("already flagged");
            if (command == "UNFLAG" && mark != Mark::Flag) fail("not flagged");
            string kind = command;
            for (char& character : kind) character = static_cast<char>(character - 'A' + 'a');
            board.moves.push_back({kind, cell});
            vector<string> output;
            if (command == "REVEAL") {
                const int opened = board.reveal(cell, safety);
                if (board.state != State::Lost) {
                    output.push_back("revealed " + std::to_string(opened));
                    board.checkWin();
                }
                board.appendFinish(output);
                return output;
            }
            board.marks[cell] = command == "FLAG" ? Mark::Flag : command == "UNFLAG" || mark == Mark::Question ? Mark::None : Mark::Question;
            const string action = command == "FLAG" ? "flagged" : command == "UNFLAG" ? "unflagged" : mark == Mark::Question ? "unmarked" : "questioned";
            return {action + " " + board.coordinate(cell) + " left " + std::to_string(board.remaining())};
        }
        if (command == "CHORD") {
            if (!board.visible[cell]) fail("not revealed");
            const int number = board.numbers[cell];
            if (number == 0) fail("no number");
            int flags = 0, unknown = 0;
            for (int next : board.neighbors[cell]) {
                flags += board.marks[next] == Mark::Flag;
                unknown += board.unknown(next);
            }
            if (flags != number) fail("flags " + std::to_string(flags) + " of " + std::to_string(number));
            if (unknown == 0) fail("nothing to reveal");
            board.moves.push_back({"chord", cell});
            const int opened = board.chord(cell, safety);
            vector<string> output;
            if (board.state != State::Lost) {
                output.push_back("chorded " + std::to_string(opened));
                board.checkWin();
            }
            board.appendFinish(output);
            return output;
        }
        if (command == "UNDO") {
            if (board.undo.empty()) fail("nothing to undo");
            Snapshot previous = std::move(board.undo.back());
            board.undo.pop_back();
            board.visible = std::move(previous.visible);
            board.marks = std::move(previous.marks);
            board.moves.resize(previous.moveCount);
            return {"undo " + previous.command + " moves " + std::to_string(board.moves.size())};
        }
        if (command == "SHOW") return board.display();
        if (command == "STATUS") return {"status " + stateName(board.state) + " left " + std::to_string(board.remaining()) +
            " moves " + std::to_string(board.moves.size()) + " revealed " + std::to_string(board.revealedCount()) + "/" + std::to_string(board.safeCount())};
        if (command == "CELL") {
            int flags = 0, unknown = 0, opened = 0;
            for (int next : board.neighbors[cell]) {
                flags += board.marks[next] == Mark::Flag;
                unknown += board.unknown(next);
                opened += board.visible[next];
            }
            const string prefix = "cell " + board.coordinate(cell);
            if (!board.visible[cell]) return {prefix + " hidden mark " + markName(board.marks[cell]) + " open " + std::to_string(opened)};
            return {prefix + " number " + std::to_string(board.numbers[cell]) + " flags " + std::to_string(flags) + " unknown " + std::to_string(unknown)};
        }
        if (command == "HISTORY") {
            vector<string> output{"history " + std::to_string(board.moves.size())};
            const std::size_t count = static_cast<std::size_t>(std::min<std::int64_t>(values[0], board.moves.size()));
            for (std::size_t i = board.moves.size() - count; i < board.moves.size(); ++i) {
                output.push_back(std::to_string(i + 1) + " " + board.moves[i].kind + " " + board.coordinate(board.moves[i].cell));
            }
            return output;
        }
        if (command == "REPLAY") {
            if (values[0] > static_cast<std::int64_t>(board.moves.size())) fail("no move " + std::to_string(values[0]));
            vector<string> output{"replay " + std::to_string(values[0]) + "/" + std::to_string(board.moves.size())};
            const vector<string> rows = board.replay(static_cast<std::size_t>(values[0]), safety);
            output.insert(output.end(), rows.begin(), rows.end());
            return output;
        }
        if (command == "HINT") {
            const Deduction deduction = board.deduce();
            const std::map<int, string>& choices = deduction.safe.empty() ? deduction.mines : deduction.safe;
            if (choices.empty()) return {"hint none"};
            const auto& [chosen, reason] = *choices.begin();
            return {string("hint ") + (deduction.safe.empty() ? "mine " : "safe ") + board.coordinate(chosen) + " by " + reason};
        }
        if (command == "AUTO" || command == "SOLVE") {
            const Totals result = command == "AUTO" ? board.automatic(safety) : board.solve(safety);
            const string prefix = command == "AUTO" ? "auto" : "solve guesses " + std::to_string(result.guesses);
            vector<string> output{prefix + " rounds " + std::to_string(result.rounds) + " flagged " + std::to_string(result.flagged) + " revealed " + std::to_string(result.opened)};
            board.appendFinish(output);
            return output;
        }
        if (command == "ANALYZE") {
            Board copy = board;
            copy.undo.clear();
            const Totals result = copy.automatic(safety);
            const string rounds = " rounds " + std::to_string(result.rounds);
            if (copy.state == State::Lost) return {"analyze boom " + copy.coordinate(copy.exploded) + rounds};
            if (copy.state == State::Won) return {"analyze clear" + rounds};
            return {"analyze stuck" + rounds + " revealed " + std::to_string(copy.revealedCount()) + "/" + std::to_string(copy.safeCount())};
        }
        if (command == "PROB") {
            if (board.visible[cell]) fail("already revealed");
            if (board.marks[cell] == Mark::Flag) fail("flagged");
            const string prefix = "prob " + board.coordinate(cell);
            for (const Component& component : board.frontier()) {
                const auto position = std::find(component.cells.begin(), component.cells.end(), cell);
                if (position == component.cells.end()) continue;
                const Configurations counts = countConfigurations(component);
                if (counts.count == 0) return {prefix + " inconsistent"};
                const int numerator = counts.frequencies[static_cast<std::size_t>(position - component.cells.begin())];
                const int divisor = std::gcd(numerator, counts.count);
                return {prefix + " " + std::to_string(numerator / divisor) + "/" + std::to_string(counts.count / divisor) +
                    " size " + std::to_string(component.cells.size()) + " configs " + std::to_string(counts.count)};
            }
            return {prefix + " unconstrained"};
        }
        if (command == "FRONTIER") {
            const vector<Component> components = board.frontier();
            std::size_t total = 0;
            for (const Component& component : components) total += component.cells.size();
            vector<string> output{"frontier " + std::to_string(total) + " components " + std::to_string(components.size())};
            for (const Component& component : components) {
                const Configurations counts = countConfigurations(component);
                const string prefix = "component " + board.coordinate(component.cells.front()) + " size " + std::to_string(component.cells.size());
                output.push_back(counts.count == 0 ? prefix + " inconsistent" : prefix + " configs " + std::to_string(counts.count) +
                    " min " + std::to_string(counts.minimum) + " max " + std::to_string(counts.maximum));
            }
            return output;
        }
        if (command == "BOARDINFO") return {board.boardInfo()};
        throw std::logic_error("Unreachable command");
    }
};

string readLine() {
    string line;
    std::getline(std::cin, line);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    return line;
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    const int commandCount = std::stoi(readLine());
    Program program;
    for (int i = 0; i < commandCount; ++i) {
        std::istringstream input(readLine());
        vector<string> words;
        string word;
        while (input >> word) words.push_back(word);
        vector<string> rows;
        if (words.front() == "LAYOUT") {
            const int height = std::stoi(words[2]);
            for (int y = 0; y < height; ++y) rows.push_back(readLine());
        }
        try {
            for (const string& line : program.execute(words, rows)) std::cout << line << '\n';
        } catch (const CommandError& error) {
            std::cout << "error: " << error.what() << '\n';
        }
        std::cout.flush();
    }
}
