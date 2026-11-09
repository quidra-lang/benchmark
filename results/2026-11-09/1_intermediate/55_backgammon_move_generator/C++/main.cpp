#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

constexpr int Off = 0;
constexpr int Bar = 25;
const std::array<std::string, 2> colors = {"W", "B"};
const std::array<std::string, 4> resultNames = {"single", "gammon", "backgammon", "drop"};
using Move = std::pair<int, int>;

struct CommandError : std::runtime_error {
    using std::runtime_error::runtime_error;
};

void require(bool condition, const std::string &reason = "bad arguments") {
    if (!condition)
        throw CommandError("ERROR " + reason);
}

[[noreturn]] void illegal(const std::string &reason) {
    throw CommandError("ILLEGAL " + reason);
}

std::vector<std::string> words(const std::string &line) {
    std::istringstream input(line);
    std::vector<std::string> result;
    for (std::string word; input >> word;)
        result.push_back(word);
    return result;
}

std::vector<std::string> split(const std::string &text, char delimiter) {
    std::vector<std::string> result;
    std::size_t start = 0;
    while (true) {
        const std::size_t end = text.find(delimiter, start);
        result.push_back(text.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            return result;
        start = end + 1;
    }
}

std::int64_t argument(const std::string &text, std::int64_t low, std::int64_t high,
                      const std::string &reason = "bad arguments") {
    require(
        !text.empty() && text.size() <= 10 &&
            std::all_of(text.begin(), text.end(), [](char ch) { return ch >= '0' && ch <= '9'; }),
        reason);
    const std::int64_t value = std::stoll(text);
    require(low <= value && value <= high, reason);
    return value;
}

std::string pointName(int point) {
    return point == Bar ? "bar" : point == Off ? "off" : std::to_string(point);
}

struct Position {
    std::array<std::array<int, 26>, 2> checkers{};

    static Position starting() {
        Position position;
        for (int color = 0; color < 2; ++color) {
            position.checkers[color][24] = 2;
            position.checkers[color][13] = 5;
            position.checkers[color][8] = 3;
            position.checkers[color][6] = 5;
        }
        return position;
    }

    bool operator<(const Position &other) const {
        return checkers < other.checkers;
    }
    bool operator==(const Position &other) const {
        return checkers == other.checkers;
    }
    int opposing(int color, int point) const {
        return checkers[1 - color][25 - point];
    }
    int boardValue(int point) const {
        return checkers[0][point] - checkers[1][25 - point];
    }
    bool finished(int color) const {
        return checkers[color][Off] == 15;
    }

    bool allHome(int color) const {
        for (int point = 7; point <= Bar; ++point)
            if (checkers[color][point] != 0)
                return false;
        return true;
    }

    int pips(int color) const {
        int count = 0;
        for (int point = 1; point <= Bar; ++point)
            count += point * checkers[color][point];
        return count;
    }

    int keith(int color) const {
        const std::array<int, 26> &mine = checkers[color];
        int count = pips(color) + 2 * std::max(mine[1] - 1, 0) + std::max(mine[2] - 1, 0) +
                    std::max(mine[3] - 3, 0);
        for (int point = 4; point <= 6; ++point)
            if (mine[point] == 0)
                ++count;
        return count;
    }

    int rearmost(int color) const {
        for (int point = Bar; point >= 1; --point)
            if (checkers[color][point] != 0)
                return point;
        return 0;
    }

    bool contact() const {
        return rearmost(0) + rearmost(1) > 25;
    }
};

struct State {
    Position position = Position::starting();
    int side = 0;
    int cube = 1;
    int owner = -1;
    bool pending = false;
    bool over = false;
    std::array<int, 2> score{};

    std::string ownerName() const {
        return owner < 0 ? "center" : colors[owner];
    }
};

struct Evaluation {
    int pips = 0, blots = 0, home = 0, prime = 0, anchors = 0, bar = 0;
    int value() const {
        return 2 * pips - blots + 4 * home + 3 * prime + 3 * anchors + 6 * bar;
    }
};

Evaluation evaluate(const Position &position, int color) {
    Evaluation terms;
    const std::array<int, 26> &mine = position.checkers[color];
    terms.pips = position.pips(1 - color) - position.pips(color);
    for (int point = 1; point <= 24; ++point) {
        if (mine[point] != 1)
            continue;
        std::array<bool, 26> distance{};
        for (int target = 0; target < point; ++target) {
            if (position.opposing(color, target) > 0)
                distance[point - target] = true;
        }
        for (int first = 1; first <= 6; ++first) {
            for (int second = 1; second <= 6; ++second) {
                if (distance[first] || distance[second] || distance[first + second] ||
                    (first == second && (distance[3 * first] || distance[4 * first])))
                    ++terms.blots;
            }
        }
    }
    int run = 0;
    for (int point = 1; point <= 24; ++point) {
        if (mine[point] >= 2) {
            ++run;
            terms.prime = std::max(terms.prime, run);
            if (point <= 6)
                ++terms.home;
            if (point >= 19)
                ++terms.anchors;
        } else
            run = 0;
    }
    terms.bar = position.checkers[1 - color][Bar] - mine[Bar];
    return terms;
}

std::vector<Move> canonicalKey(std::vector<Move> pairs, const std::set<int> &hits) {
    const auto sortPairs = [&pairs]() {
        std::sort(pairs.begin(), pairs.end(), std::greater<Move>());
    };
    sortPairs();
    while (true) {
        bool merged = false;
        for (std::size_t a = 0; a < pairs.size() && !merged; ++a) {
            const int middle = pairs[a].second;
            if (middle < 1 || hits.count(middle) != 0)
                continue;
            for (std::size_t b = 0; b < pairs.size(); ++b) {
                if (pairs[b].first != middle)
                    continue;
                const Move combined{pairs[a].first, pairs[b].second};
                pairs.erase(pairs.begin() + std::max(a, b));
                pairs.erase(pairs.begin() + std::min(a, b));
                pairs.push_back(combined);
                sortPairs();
                merged = true;
                break;
            }
        }
        if (!merged)
            return pairs;
    }
}

std::string notation(const std::vector<Move> &pairs, const std::set<int> &hits) {
    if (pairs.empty())
        return "none";
    std::string text;
    std::set<int> starred;
    for (std::size_t i = 0; i < pairs.size();) {
        std::size_t end = i + 1;
        while (end < pairs.size() && pairs[end] == pairs[i])
            ++end;
        if (!text.empty())
            text += ' ';
        text += pointName(pairs[i].first) + '/' + pointName(pairs[i].second);
        if (hits.count(pairs[i].second) != 0 && starred.insert(pairs[i].second).second)
            text += '*';
        if (end - i >= 2)
            text += '(' + std::to_string(end - i) + ')';
        i = end;
    }
    return text;
}

struct Play {
    Position position;
    std::vector<Move> key;
    std::string text;
};

struct Candidate {
    Position position;
    std::vector<Move> moves;
    std::set<int> hits;
    int firstDie;
};

class Generator {
    int color;
    std::vector<Candidate> candidates;

    void explore(const Position &position, std::array<int, 7> &remaining, std::vector<Move> &moves,
                 const std::set<int> &hits, int firstDie) {
        const auto found = shortest.find(position);
        if (found == shortest.end() || moves.size() < found->second)
            shortest[position] = moves.size();
        if (moves.size() > maximum) {
            maximum = moves.size();
            candidates.clear();
        }
        if (moves.size() == maximum)
            candidates.push_back({position, moves, hits, firstDie});
        for (int die = 1; die <= 6; ++die) {
            if (remaining[die] == 0)
                continue;
            --remaining[die];
            for (int start = Bar; start >= 1; --start) {
                if (position.checkers[color][start] == 0)
                    continue;
                if (position.checkers[color][Bar] > 0 && start != Bar)
                    continue;
                int destination = start - die;
                bool hit = false;
                if (destination >= 1) {
                    if (position.opposing(color, destination) >= 2)
                        continue;
                    hit = position.opposing(color, destination) == 1;
                } else {
                    if (!position.allHome(color))
                        continue;
                    bool farther = false;
                    if (destination < 0) {
                        for (int point = start + 1; point <= 6; ++point)
                            farther = farther || position.checkers[color][point] > 0;
                    }
                    if (farther)
                        continue;
                    destination = Off;
                }
                Position after = position;
                --after.checkers[color][start];
                ++after.checkers[color][destination];
                std::set<int> nextHits = hits;
                if (hit) {
                    --after.checkers[1 - color][25 - destination];
                    ++after.checkers[1 - color][Bar];
                    nextHits.insert(destination);
                }
                moves.push_back({start, destination});
                explore(after, remaining, moves, nextHits, firstDie == 0 ? die : firstDie);
                moves.pop_back();
            }
            ++remaining[die];
        }
    }

  public:
    std::size_t maximum = 0;
    std::map<Position, std::size_t> shortest;
    std::vector<Play> plays;

    Generator(const Position &position, int side, int first, int second) : color(side) {
        std::array<int, 7> remaining{};
        if (first == second)
            remaining[first] = 4;
        else {
            remaining[first] = 1;
            remaining[second] = 1;
        }
        std::vector<Move> moves;
        explore(position, remaining, moves, {}, 0);
        bool largerRequired = false;
        if (maximum == 1 && first != second) {
            for (const Candidate &candidate : candidates)
                if (candidate.firstDie == std::max(first, second))
                    largerRequired = true;
        }
        std::set<Position> seen;
        for (const Candidate &candidate : candidates) {
            if (largerRequired && candidate.firstDie != std::max(first, second))
                continue;
            if (!seen.insert(candidate.position).second)
                continue;
            const std::vector<Move> key = canonicalKey(candidate.moves, candidate.hits);
            plays.push_back({candidate.position, key, notation(key, candidate.hits)});
        }
        std::sort(plays.begin(), plays.end(),
                  [](const Play &a, const Play &b) { return a.key > b.key; });
    }
};

int bestIndex(const std::vector<Play> &plays, int side) {
    int best = 0;
    int value = evaluate(plays[0].position, side).value();
    for (std::size_t i = 1; i < plays.size(); ++i) {
        const int next = evaluate(plays[i].position, side).value();
        if (next > value) {
            best = static_cast<int>(i);
            value = next;
        }
    }
    return best;
}

std::optional<std::vector<Move>> parsePlay(const std::vector<std::string> &elements) {
    if (elements.size() == 1 && elements[0] == "none")
        return std::vector<Move>{};
    std::vector<Move> moves;
    for (std::string element : elements) {
        int repetitions = 1;
        if (element.size() >= 3 && element[element.size() - 3] == '(' && element.back() == ')' &&
            element[element.size() - 2] >= '2' && element[element.size() - 2] <= '4') {
            repetitions = element[element.size() - 2] - '0';
            element.resize(element.size() - 3);
        }
        const std::vector<std::string> path = split(element, '/');
        if (path.size() < 2)
            return std::nullopt;
        std::vector<int> points;
        for (std::size_t i = 0; i < path.size(); ++i) {
            std::string point = path[i];
            int value;
            if (i == 0 && point == "bar")
                value = Bar;
            else if (i > 0 && point == "off")
                value = Off;
            else {
                if (i > 0 && !point.empty() && point.back() == '*')
                    point.pop_back();
                if (point.empty() || point.size() > 2 || point[0] < '1' || point[0] > '9' ||
                    !std::all_of(point.begin(), point.end(),
                                 [](char ch) { return ch >= '0' && ch <= '9'; }))
                    return std::nullopt;
                value = std::stoi(point);
                if (value > 24)
                    return std::nullopt;
            }
            if (!points.empty() && points.back() <= value)
                return std::nullopt;
            points.push_back(value);
        }
        for (std::size_t i = 1; i < points.size(); ++i) {
            for (int repeat = 0; repeat < repetitions; ++repeat)
                moves.push_back({points[i - 1], points[i]});
        }
    }
    return moves;
}

const Play &validatePlay(const Position &position, int color, const std::vector<Move> &moves,
                         const Generator &generator) {
    Position final = position;
    std::set<int> destinations;
    for (Move move : moves) {
        --final.checkers[color][move.first];
        ++final.checkers[color][move.second];
        if (move.second >= 1)
            destinations.insert(move.second);
    }
    for (int destination : destinations) {
        if (position.opposing(color, destination) == 1) {
            --final.checkers[1 - color][25 - destination];
            ++final.checkers[1 - color][Bar];
        }
    }
    for (int point = 1; point <= Bar; ++point)
        if (final.checkers[color][point] < 0)
            illegal("no checker");
    if (final.checkers[color][Bar] > 0) {
        for (Move move : moves)
            if (move.first != Bar)
                illegal("bar");
    }
    for (Move move : moves)
        if (move.second >= 1 && position.opposing(color, move.second) >= 2)
            illegal("blocked");
    for (Move move : moves)
        if (move.second == Off && !final.allHome(color))
            illegal("bear-off");
    for (const Play &play : generator.plays)
        if (play.position == final)
            return play;
    const auto possible = generator.shortest.find(final);
    if (possible != generator.shortest.end())
        illegal(possible->second < generator.maximum ? "too few dice" : "larger die required");
    illegal("impossible");
}

int multiplier(const std::string &result) {
    if (result == "single" || result == "drop")
        return 1;
    return result == "gammon" ? 2 : 3;
}

std::string naturalResult(const Position &position, int winner) {
    const std::array<int, 26> &loser = position.checkers[1 - winner];
    if (loser[Off] > 0)
        return "single";
    if (loser[Bar] > 0)
        return "backgammon";
    for (int point = 19; point <= 24; ++point)
        if (loser[point] > 0)
            return "backgammon";
    return "gammon";
}

std::string cubeDecision(const State &state, bool prohibited = false) {
    const int side = state.side, other = 1 - side;
    if (state.owner == other || state.cube == 64 || prohibited)
        return "unavailable";
    if (state.position.contact()) {
        const int value = evaluate(state.position, side).value();
        if (value < 60)
            return "no double";
        return value <= 100 ? "double take" : "double drop";
    }
    const int value = 8 * state.position.keith(side) - 7 * state.position.keith(other);
    const int limit = state.owner < 0 ? 28 : 21;
    if (value > limit)
        return "no double";
    return value >= 14 ? "double take" : "double drop";
}

struct Result {
    int winner;
    std::string kind;
    int points;
};

Result finish(State &state, int winner, const std::string &kind) {
    const int points = multiplier(kind) * state.cube;
    state.over = true;
    state.pending = false;
    state.score[winner] += points;
    return {winner, kind, points};
}

void printResult(const Result &result) {
    std::cout << "result " << colors[result.winner] << ' ' << result.kind << ' ' << result.points
              << '\n';
}

struct HistoryEntry {
    std::string record;
    State before, after;
};

std::optional<Result> commitPlay(State &state, const Play &play, int first, int second,
                                 std::vector<HistoryEntry> &history,
                                 std::vector<HistoryEntry> &redo) {
    const State before = state;
    const int color = state.side;
    state.position = play.position;
    std::optional<Result> result;
    if (state.position.finished(color))
        result = finish(state, color, naturalResult(state.position, color));
    else
        state.side = 1 - color;
    const std::string record = colors[color] + ' ' + std::to_string(first) + '-' +
                               std::to_string(second) + ' ' + play.text;
    history.push_back({record, before, state});
    redo.clear();
    return result;
}

class Dice {
    std::int64_t value;

  public:
    explicit Dice(std::int64_t seed) : value(seed) {
    }
    std::int64_t next() {
        value = 48271 * value % 2147483647;
        return value;
    }
    int roll() {
        return static_cast<int>(next() % 6 + 1);
    }
};

struct GameRecord {
    Result result;
    int plays;
    std::vector<std::string> lines;
};

GameRecord playGame(State state, const std::array<std::string, 2> &strategies, Dice &dice,
                    std::optional<std::pair<int, int>> opening = std::nullopt, int target = 0,
                    std::array<int, 2> points = {}, bool crawford = false) {
    GameRecord record{{0, "", 0}, 0, {}};
    for (int turn = 1;; ++turn) {
        const int side = state.side, other = 1 - side;
        int first, second;
        const std::string prefix = std::to_string(turn) + ' ';
        if (turn == 1 && opening.has_value()) {
            first = opening->first;
            second = opening->second;
        } else {
            const bool prohibited = target > 0 && (crawford || points[side] + state.cube >= target);
            const std::string decision = cubeDecision(state, prohibited);
            if (decision == "double take" || decision == "double drop")
                record.lines.push_back(prefix + colors[side] + " doubles " +
                                       std::to_string(2 * state.cube));
            if (decision == "double drop") {
                record.lines.push_back(prefix + colors[other] + " drops");
                record.result = {side, "drop", state.cube};
                return record;
            }
            if (decision == "double take") {
                record.lines.push_back(prefix + colors[other] + " takes");
                state.cube *= 2;
                state.owner = other;
            }
            first = dice.roll();
            second = dice.roll();
        }
        const Generator generator(state.position, side, first, second);
        std::size_t index = 0;
        if (strategies[side] == "BEST")
            index = bestIndex(generator.plays, side);
        else if (strategies[side] == "RANDOM")
            index = dice.next() % generator.plays.size();
        const Play &play = generator.plays[index];
        state.position = play.position;
        ++record.plays;
        record.lines.push_back(prefix + colors[side] + ' ' + std::to_string(first) + '-' +
                               std::to_string(second) + ' ' + play.text);
        if (state.position.finished(side)) {
            const std::string kind = naturalResult(state.position, side);
            record.result = {side, kind, multiplier(kind) * state.cube};
            return record;
        }
        state.side = other;
    }
}

std::pair<State, std::pair<int, int>> openingGame(Dice &dice) {
    int white, black;
    do {
        white = dice.roll();
        black = dice.roll();
    } while (white == black);
    State state;
    state.side = white > black ? 0 : 1;
    return {state, {white, black}};
}

State parsePosition(const std::vector<std::string> &args, std::array<int, 2> score) {
    require(args.size() == 4, "bad position");
    const std::vector<std::string> values = split(args[0], ',');
    require(values.size() == 24 && (args[3] == "W" || args[3] == "B"), "bad position");
    State state;
    state.position = Position{};
    state.side = args[3] == "W" ? 0 : 1;
    state.score = score;
    for (int point = 1; point <= 24; ++point) {
        const std::string &text = values[point - 1];
        const bool negative = !text.empty() && text[0] == '-';
        const int value =
            static_cast<int>(argument(negative ? text.substr(1) : text, 0, 15, "bad position"));
        if (negative)
            state.position.checkers[1][25 - point] = value;
        else
            state.position.checkers[0][point] = value;
    }
    state.position.checkers[0][Bar] = static_cast<int>(argument(args[1], 0, 15, "bad position"));
    state.position.checkers[1][Bar] = static_cast<int>(argument(args[2], 0, 15, "bad position"));
    for (int color = 0; color < 2; ++color) {
        int total = 0;
        for (int point = 1; point <= Bar; ++point)
            total += state.position.checkers[color][point];
        require(total >= 1 && total <= 15, "bad position");
        state.position.checkers[color][Off] = 15 - total;
    }
    return state;
}

void show(const State &state) {
    std::cout << "POS ";
    for (int point = 1; point <= 24; ++point) {
        if (point > 1)
            std::cout << ',';
        std::cout << state.position.boardValue(point);
    }
    std::cout << ' ' << state.position.checkers[0][Bar] << ' ' << state.position.checkers[1][Bar]
              << ' ' << colors[state.side] << '\n';
}

void boardLine(const State &state, bool upper, int row) {
    for (int i = 0; i < 12; ++i) {
        if (i == 6)
            std::cout << " |";
        const int point = upper ? 13 + i : 12 - i;
        std::string field;
        if (row == 0)
            field = std::to_string(point);
        else {
            const int value = state.position.boardValue(point);
            const int count = std::abs(value);
            if (count < row)
                field = ".";
            else if (row == 5 && count > 5)
                field = std::to_string(count);
            else
                field = value > 0 ? "W" : "B";
        }
        std::cout << std::setw(3) << field;
    }
    std::cout << '\n';
}

void board(const State &state) {
    boardLine(state, true, 0);
    for (int row = 1; row <= 5; ++row)
        boardLine(state, true, row);
    std::cout << "bar W" << state.position.checkers[0][Bar] << " B"
              << state.position.checkers[1][Bar] << " | off W" << state.position.checkers[0][Off]
              << " B" << state.position.checkers[1][Off] << " | cube " << state.cube << ' '
              << state.ownerName() << " | ";
    if (state.over)
        std::cout << "game over";
    else
        std::cout << colors[state.side] << (state.pending ? " doubles" : " to move");
    std::cout << '\n';
    for (int row = 5; row >= 1; --row)
        boardLine(state, false, row);
    boardLine(state, false, 0);
}

void shots(const State &state) {
    std::vector<int> blots;
    std::array<int, 26> weights{};
    for (int point = 24; point >= 1; --point)
        if (state.position.checkers[state.side][point] == 1)
            blots.push_back(point);
    int total = 0;
    std::string rolls;
    for (int first = 6; first >= 1; --first) {
        for (int second = first; second >= 1; --second) {
            const Generator generator(state.position, 1 - state.side, first, second);
            std::set<int> hit;
            for (const Play &play : generator.plays) {
                for (int point : blots)
                    if (play.position.checkers[state.side][point] == 0)
                        hit.insert(point);
            }
            if (hit.empty())
                continue;
            const int weight = first == second ? 1 : 2;
            total += weight;
            rolls += ' ' + std::to_string(first) + '-' + std::to_string(second);
            for (int point : hit)
                weights[point] += weight;
        }
    }
    std::cout << "shots " << total << "/36" << rolls << '\n';
    for (int point : blots)
        std::cout << "blot " << point << ' ' << weights[point] << "/36\n";
}

bool contains(const std::set<std::string> &names, const std::string &name) {
    return names.count(name) != 0;
}

void validateArguments(const std::string &op, const std::vector<std::string> &args) {
    const std::set<std::string> noArgs = {"NEW",  "SHOW",  "BOARD",  "PIPS",   "RACE",
                                          "EVAL", "SHOTS", "CUBE",   "DOUBLE", "TAKE",
                                          "DROP", "SCORE", "HISTORY"};
    if (contains(noArgs, op)) {
        require(args.empty());
        return;
    }
    if (op == "MOVES" || op == "AUTO" || op == "HINT" || op == "PLAY") {
        if (op == "HINT")
            require(args.size() == 3);
        else if (op == "PLAY")
            require(args.size() >= 3);
        else
            require(args.size() == 2);
        argument(args[0], 1, 6);
        argument(args[1], 1, 6);
        if (op == "HINT")
            argument(args[2], 1, 1000);
    } else if (op == "UNDO" || op == "REDO") {
        require(args.size() == 1);
        argument(args[0], 1, 1000);
    } else if (op == "RESIGN") {
        require(args.size() == 1);
        require(args[0] == "single" || args[0] == "gammon" || args[0] == "backgammon");
    } else if (op == "GAME") {
        require(args.size() == 3);
        argument(args[0], 1, 2147483646);
        const std::set<std::string> strategies = {"BEST", "FIRST", "RANDOM"};
        require(contains(strategies, args[1]) && contains(strategies, args[2]));
    } else if (op == "MATCH" || op == "STATS") {
        require(args.size() == 2);
        argument(args[0], 1, op == "MATCH" ? 15 : 50);
        argument(args[1], 1, 2147483646);
    }
}

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::string line;
    if (!std::getline(std::cin, line))
        return 0;
    const int commands = std::stoi(line);
    State state;
    std::vector<HistoryEntry> history, redo;
    const std::set<std::string> known = {"NEW",     "POS",    "SHOW", "BOARD", "PIPS",   "RACE",
                                         "MOVES",   "PLAY",   "AUTO", "HINT",  "EVAL",   "SHOTS",
                                         "CUBE",    "DOUBLE", "TAKE", "DROP",  "RESIGN", "SCORE",
                                         "HISTORY", "UNDO",   "REDO", "GAME",  "MATCH",  "STATS"};
    const std::set<std::string> needsGame = {"RACE", "MOVES",  "PLAY", "AUTO",   "HINT",
                                             "EVAL", "SHOTS",  "CUBE", "DOUBLE", "TAKE",
                                             "DROP", "RESIGN", "GAME"};
    const std::set<std::string> noPending = {"PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME"};
    for (int i = 0; i < commands && std::getline(std::cin, line); ++i) {
        const std::vector<std::string> tokens = words(line);
        const std::string &op = tokens[0];
        const std::vector<std::string> args(tokens.begin() + 1, tokens.end());
        try {
            require(contains(known, op), "unknown command");
            if (op == "POS") {
                State replacement = parsePosition(args, state.score);
                state = std::move(replacement);
                history.clear();
                redo.clear();
                std::cout << "OK\n";
                std::cout.flush();
                continue;
            }
            validateArguments(op, args);
            require(!contains(needsGame, op) || !state.over, "game over");
            require(!contains(noPending, op) || !state.pending, "double pending");
            if (op == "NEW") {
                const std::array<int, 2> score = state.score;
                state = State{};
                state.score = score;
                history.clear();
                redo.clear();
                std::cout << "OK\n";
            } else if (op == "SHOW")
                show(state);
            else if (op == "BOARD")
                board(state);
            else if (op == "PIPS")
                std::cout << "pips W " << state.position.pips(0) << " B " << state.position.pips(1)
                          << '\n';
            else if (op == "RACE") {
                if (state.position.contact())
                    std::cout << "contact\n";
                else
                    std::cout << "race W " << state.position.keith(0) << " B "
                              << state.position.keith(1) << '\n';
            } else if (op == "MOVES" || op == "PLAY" || op == "AUTO" || op == "HINT") {
                const int first = std::stoi(args[0]), second = std::stoi(args[1]);
                std::optional<std::vector<Move>> requested;
                if (op == "PLAY") {
                    requested = parsePlay(std::vector<std::string>(args.begin() + 2, args.end()));
                    if (!requested.has_value())
                        illegal("syntax");
                }
                const Generator generator(state.position, state.side, first, second);
                if (op == "MOVES") {
                    for (const Play &play : generator.plays)
                        std::cout << play.text << '\n';
                    std::cout << "total " << generator.plays.size() << '\n';
                } else if (op == "HINT") {
                    std::vector<std::pair<int, std::size_t>> ranked;
                    for (std::size_t index = 0; index < generator.plays.size(); ++index)
                        ranked.push_back(
                            {evaluate(generator.plays[index].position, state.side).value(), index});
                    std::stable_sort(
                        ranked.begin(), ranked.end(),
                        [](const auto &a, const auto &b) { return a.first > b.first; });
                    const std::size_t count =
                        std::min(static_cast<std::size_t>(std::stoi(args[2])), ranked.size());
                    for (std::size_t index = 0; index < count; ++index)
                        std::cout << ranked[index].first << ' '
                                  << generator.plays[ranked[index].second].text << '\n';
                } else {
                    const Play &play =
                        op == "PLAY"
                            ? validatePlay(state.position, state.side, *requested, generator)
                            : generator.plays[bestIndex(generator.plays, state.side)];
                    const int value = evaluate(play.position, state.side).value();
                    const std::optional<Result> result =
                        commitPlay(state, play, first, second, history, redo);
                    std::cout << "OK " << play.text;
                    if (op == "AUTO")
                        std::cout << " eval " << value;
                    std::cout << '\n';
                    if (result.has_value())
                        printResult(*result);
                }
            } else if (op == "EVAL") {
                const Evaluation terms = evaluate(state.position, state.side);
                std::cout << "eval " << terms.value() << " pips " << terms.pips << " blots "
                          << terms.blots << " home " << terms.home << " prime " << terms.prime
                          << " anchors " << terms.anchors << " bar " << terms.bar << '\n';
            } else if (op == "SHOTS")
                shots(state);
            else if (op == "CUBE")
                std::cout << "cube " << cubeDecision(state) << '\n';
            else if (op == "DOUBLE") {
                require(state.owner != 1 - state.side && state.cube != 64, "cube unavailable");
                state.pending = true;
                redo.clear();
                std::cout << "OK double " << 2 * state.cube << '\n';
            } else if (op == "TAKE") {
                require(state.pending, "no double");
                state.pending = false;
                state.cube *= 2;
                state.owner = 1 - state.side;
                redo.clear();
                std::cout << "OK take " << state.cube << ' ' << state.ownerName() << '\n';
            } else if (op == "DROP" || op == "RESIGN") {
                if (op == "DROP")
                    require(state.pending, "no double");
                const int winner = op == "DROP" ? state.side : 1 - state.side;
                const Result result = finish(state, winner, op == "DROP" ? "drop" : args[0]);
                redo.clear();
                std::cout << (op == "DROP" ? "OK drop\n" : "OK resign\n");
                printResult(result);
            } else if (op == "SCORE")
                std::cout << "score W " << state.score[0] << " B " << state.score[1] << '\n';
            else if (op == "HISTORY") {
                std::cout << "history " << history.size() << '\n';
                for (std::size_t index = 0; index < history.size(); ++index)
                    std::cout << index + 1 << ' ' << history[index].record << '\n';
            } else if (op == "UNDO") {
                const std::size_t count = std::stoi(args[0]);
                require(count <= history.size(), "cannot undo");
                const std::size_t start = history.size() - count;
                state = history[start].before;
                redo.insert(redo.begin(), history.begin() + start, history.end());
                history.erase(history.begin() + start, history.end());
                std::cout << "OK\n";
            } else if (op == "REDO") {
                const std::size_t count = std::stoi(args[0]);
                require(count <= redo.size(), "cannot redo");
                state = redo[count - 1].after;
                history.insert(history.end(), redo.begin(), redo.begin() + count);
                redo.erase(redo.begin(), redo.begin() + count);
                std::cout << "OK\n";
            } else if (op == "GAME") {
                Dice dice(std::stoll(args[0]));
                const GameRecord game = playGame(state, {args[1], args[2]}, dice);
                for (const std::string &output : game.lines)
                    std::cout << output << '\n';
                printResult(game.result);
            } else if (op == "MATCH") {
                const int target = std::stoi(args[0]);
                Dice dice(std::stoll(args[1]));
                std::array<int, 2> points{};
                bool crawfordPlayed = false;
                int gameNumber = 0;
                while (points[0] < target && points[1] < target) {
                    ++gameNumber;
                    const bool crawford =
                        !crawfordPlayed && std::max(points[0], points[1]) == target - 1;
                    if (crawford)
                        crawfordPlayed = true;
                    const auto opening = openingGame(dice);
                    const GameRecord game = playGame(opening.first, {"BEST", "BEST"}, dice,
                                                     opening.second, target, points, crawford);
                    points[game.result.winner] += game.result.points;
                    std::cout << "game " << gameNumber;
                    if (crawford)
                        std::cout << " crawford";
                    std::cout << " start " << colors[opening.first.side] << " turns " << game.plays
                              << " result " << colors[game.result.winner] << ' ' << game.result.kind
                              << ' ' << game.result.points << " score " << points[0] << '-'
                              << points[1] << '\n';
                }
                std::cout << "match " << colors[points[0] >= target ? 0 : 1] << ' ' << points[0]
                          << '-' << points[1] << '\n';
            } else if (op == "STATS") {
                const int count = std::stoi(args[0]);
                Dice dice(std::stoll(args[1]));
                std::array<std::array<int, 2>, 4> counts{};
                std::array<int, 2> points{};
                int turns = 0;
                for (int gameNumber = 0; gameNumber < count; ++gameNumber) {
                    const auto opening = openingGame(dice);
                    const GameRecord game =
                        playGame(opening.first, {"BEST", "BEST"}, dice, opening.second);
                    const std::size_t kind =
                        std::find(resultNames.begin(), resultNames.end(), game.result.kind) -
                        resultNames.begin();
                    ++counts[kind][game.result.winner];
                    points[game.result.winner] += game.result.points;
                    turns += game.plays;
                }
                for (std::size_t kind = 0; kind < counts.size(); ++kind)
                    std::cout << resultNames[kind] << " W " << counts[kind][0] << " B "
                              << counts[kind][1] << '\n';
                std::cout << "points W " << points[0] << " B " << points[1] << "\nturns " << turns
                          << '\n';
            }
        } catch (const CommandError &error) {
            std::cout << error.what() << '\n';
        }
        std::cout.flush();
    }
}
