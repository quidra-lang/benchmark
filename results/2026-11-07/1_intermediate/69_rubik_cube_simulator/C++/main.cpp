#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

const std::string faces = "URFDLB", colors = "WRGYOB";
const std::string letters = "UDFBLRMESudfblrxyz";
using State = std::string;
using Permutation = std::array<int, 54>;

struct Move {
    char letter;
    int amount;
    bool operator==(const Move& other) const { return letter == other.letter && amount == other.amount; }
    std::string text() const {
        return std::string(1, letter) + (amount == 2 ? "2" : amount == 3 ? "'" : "");
    }
};
using Sequence = std::vector<Move>;

Sequence inverse(Sequence sequence) {
    std::reverse(sequence.begin(), sequence.end());
    for (Move& move : sequence) move.amount = 4 - move.amount;
    return sequence;
}

void append(Sequence& target, const Sequence& source) { target.insert(target.end(), source.begin(), source.end()); }

std::string moves_text(const Sequence& sequence) {
    std::string result;
    for (const Move& move : sequence) result += " " + move.text();
    return result;
}

std::string sequence_text(const Sequence& sequence) { return std::to_string(sequence.size()) + moves_text(sequence); }

char axis(char letter) {
    if (std::string("RLMrlx").find(letter) != std::string::npos) return 'x';
    if (std::string("UDEudy").find(letter) != std::string::npos) return 'y';
    return 'z';
}

bool rotation(char letter) { return letter == 'x' || letter == 'y' || letter == 'z'; }
bool outer(char letter) { return faces.find(letter) != std::string::npos; }
bool wide(char letter) { return std::string("udfblr").find(letter) != std::string::npos; }

Sequence simplify(Sequence sequence) {
    while (true) {
        Sequence result;
        std::size_t position = 0;
        while (position < sequence.size()) {
            char current_axis = axis(sequence[position].letter);
            std::vector<char> order;
            std::map<char, int> amounts;
            while (position < sequence.size() && axis(sequence[position].letter) == current_axis) {
                const Move& move = sequence[position++];
                if (!amounts.count(move.letter)) order.push_back(move.letter);
                amounts[move.letter] = (amounts[move.letter] + move.amount) % 4;
            }
            for (char letter : order) if (amounts[letter]) result.push_back({letter, amounts[letter]});
        }
        if (result == sequence) return result;
        sequence = std::move(result);
    }
}

Permutation identity() {
    Permutation result;
    std::iota(result.begin(), result.end(), 0);
    return result;
}

Permutation compose(const Permutation& first, const Permutation& second) {
    Permutation result;
    for (int i = 0; i < 54; ++i) result[i] = second[first[i]];
    return result;
}

Permutation inverse_effect(const Permutation& permutation) {
    Permutation result;
    for (int i = 0; i < 54; ++i) result[permutation[i]] = i;
    return result;
}

State apply_effect(const State& state, const Permutation& permutation) {
    State result(54, ' ');
    for (int i = 0; i < 54; ++i) result[permutation[i]] = state[i];
    return result;
}

int sticker(char face, int row, int column) { return static_cast<int>(faces.find(face)) * 9 + row * 3 + column; }

State solved_state() {
    State state;
    for (char color : colors) state.append(9, color);
    return state;
}

int mismatches(const State& state) {
    int count = 0;
    for (int f = 0; f < 6; ++f) for (int i = 0; i < 9; ++i) if (state[f * 9 + i] != state[f * 9 + 4]) ++count;
    return count;
}

class Geometry {
    std::map<char, std::array<Permutation, 4>> moves;

    void define(char letter, Permutation quarter) {
        moves[letter][0] = identity();
        moves[letter][1] = std::move(quarter);
        moves[letter][2] = compose(moves[letter][1], moves[letter][1]);
        moves[letter][3] = compose(moves[letter][2], moves[letter][1]);
    }
public:
    std::vector<Sequence> rotations;

    Geometry() {
        for (char face : std::string("URFDLBMES")) {
            Permutation p = identity();
            if (outer(face)) for (int row = 0; row < 3; ++row) for (int column = 0; column < 3; ++column)
                p[sticker(face, row, column)] = sticker(face, column, 2 - row);
            auto cycle = [&](std::array<int, 4> positions) {
                for (int i = 0; i < 4; ++i) p[positions[i]] = positions[(i + 1) % 4];
            };
            for (int i = 0; i < 3; ++i) {
                if (face == 'U') cycle({sticker('F', 0, i), sticker('L', 0, i), sticker('B', 0, i), sticker('R', 0, i)});
                if (face == 'R') cycle({sticker('F', i, 2), sticker('U', i, 2), sticker('B', 2 - i, 0), sticker('D', i, 2)});
                if (face == 'F') cycle({sticker('U', 2, i), sticker('R', i, 0), sticker('D', 0, 2 - i), sticker('L', 2 - i, 2)});
                if (face == 'D') cycle({sticker('F', 2, i), sticker('R', 2, i), sticker('B', 2, i), sticker('L', 2, i)});
                if (face == 'L') cycle({sticker('U', i, 0), sticker('F', i, 0), sticker('D', i, 0), sticker('B', 2 - i, 2)});
                if (face == 'B') cycle({sticker('U', 0, i), sticker('L', 2 - i, 0), sticker('D', 2, 2 - i), sticker('R', i, 2)});
                if (face == 'M') cycle({sticker('U', i, 1), sticker('F', i, 1), sticker('D', i, 1), sticker('B', 2 - i, 1)});
                if (face == 'E') cycle({sticker('F', 1, i), sticker('R', 1, i), sticker('B', 1, i), sticker('L', 1, i)});
                if (face == 'S') cycle({sticker('U', 1, i), sticker('R', i, 1), sticker('D', 1, 2 - i), sticker('L', 2 - i, 1)});
            }
            define(face, std::move(p));
        }
        const std::vector<std::pair<char, Sequence>> composites{
            {'r', {{'R', 1}, {'M', 3}}}, {'l', {{'L', 1}, {'M', 1}}},
            {'u', {{'U', 1}, {'E', 3}}}, {'d', {{'D', 1}, {'E', 1}}},
            {'f', {{'F', 1}, {'S', 1}}}, {'b', {{'B', 1}, {'S', 3}}},
            {'x', {{'R', 1}, {'M', 3}, {'L', 3}}}, {'y', {{'U', 1}, {'E', 3}, {'D', 3}}},
            {'z', {{'F', 1}, {'S', 1}, {'B', 3}}}
        };
        for (const auto& composite : composites) define(composite.first, effect(composite.second));
        const std::vector<Sequence> bases{{}, {{'x', 1}}, {{'x', 2}}, {{'x', 3}}, {{'z', 1}}, {{'z', 3}}};
        for (const Sequence& base : bases) for (int amount = 0; amount < 4; ++amount) {
            Sequence sequence = base;
            if (amount) sequence.push_back({'y', amount});
            rotations.push_back(std::move(sequence));
        }
    }

    const Permutation& effect(Move move) const { return moves.at(move.letter)[move.amount]; }
    Permutation effect(const Sequence& sequence) const {
        Permutation result = identity();
        for (Move move : sequence) result = compose(result, effect(move));
        return result;
    }
    State apply(const State& state, const Sequence& sequence) const { return apply_effect(state, effect(sequence)); }
    Move matching(const Permutation& effect_to_find, bool only_outer = false) const {
        for (char letter : letters) if (!only_outer || outer(letter))
            for (int amount = 1; amount <= 3; ++amount)
                if (effect({letter, amount}) == effect_to_find) return {letter, amount};
        throw std::logic_error("unrepresentable move");
    }
    std::optional<std::pair<State, Sequence>> normalize(const State& state) const {
        for (const Sequence& sequence : rotations) {
            State candidate = apply(state, sequence);
            bool standard = true;
            for (int f = 0; f < 6; ++f) if (candidate[f * 9 + 4] != colors[f]) standard = false;
            if (standard) return std::make_pair(std::move(candidate), sequence);
        }
        return std::nullopt;
    }
};

struct Piece {
    std::string name, colors;
    std::vector<int> stickers;
    Piece(std::string name, std::vector<std::string> positions) : name(std::move(name)) {
        for (char face : this->name) colors += ::colors[faces.find(face)];
        for (const std::string& position : positions)
            stickers.push_back(static_cast<int>(faces.find(position[0])) * 9 + position[1] - '1');
    }
};

const std::vector<Piece> corners{
    {"URF", {"U9", "R1", "F3"}}, {"UFL", {"U7", "F1", "L3"}},
    {"ULB", {"U1", "L1", "B3"}}, {"UBR", {"U3", "B1", "R3"}},
    {"DFR", {"D3", "F9", "R7"}}, {"DLF", {"D1", "L9", "F7"}},
    {"DBL", {"D7", "B9", "L7"}}, {"DRB", {"D9", "R9", "B7"}}
};
const std::vector<Piece> edges{
    {"UR", {"U6", "R2"}}, {"UF", {"U8", "F2"}}, {"UL", {"U4", "L2"}}, {"UB", {"U2", "B2"}},
    {"DR", {"D6", "R8"}}, {"DF", {"D2", "F8"}}, {"DL", {"D4", "L8"}}, {"DB", {"D8", "B8"}},
    {"FR", {"F6", "R4"}}, {"FL", {"F4", "L6"}}, {"BL", {"B6", "L4"}}, {"BR", {"B4", "R6"}}
};
const std::vector<Piece> centers{
    {"U", {"U5"}}, {"R", {"R5"}}, {"F", {"F5"}}, {"D", {"D5"}}, {"L", {"L5"}}, {"B", {"B5"}}
};

struct Placement { int piece = -1, orientation = 0; };
std::vector<Placement> identify(const State& state, const std::vector<Piece>& pieces) {
    std::vector<Placement> result(pieces.size());
    for (std::size_t q = 0; q < pieces.size(); ++q) {
        std::size_t width = pieces[q].stickers.size();
        for (std::size_t p = 0; p < pieces.size(); ++p) for (std::size_t t = 0; t < width; ++t) {
            bool match = true;
            for (std::size_t k = 0; k < width; ++k)
                if (state[pieces[q].stickers[(t + k) % width]] != pieces[p].colors[k]) match = false;
            if (match) result[q] = {static_cast<int>(p), static_cast<int>(t)};
        }
    }
    return result;
}

std::string cycles(const State& state, const std::vector<Piece>& pieces) {
    std::vector<Placement> placements = identify(state, pieces);
    std::vector<int> destination(pieces.size()), orientation(pieces.size());
    for (std::size_t q = 0; q < pieces.size(); ++q) {
        destination[placements[q].piece] = static_cast<int>(q);
        orientation[placements[q].piece] = placements[q].orientation;
    }
    std::vector<bool> seen(pieces.size());
    std::vector<std::string> result;
    for (std::size_t start = 0; start < pieces.size(); ++start) {
        if (seen[start]) continue;
        std::vector<std::string> names;
        int sum = 0, position = static_cast<int>(start);
        do {
            seen[position] = true;
            names.push_back(pieces[position].name);
            sum += orientation[position];
            position = destination[position];
        } while (position != static_cast<int>(start));
        int remainder = sum % static_cast<int>(pieces.front().stickers.size());
        std::string mark = remainder == 0 ? "" : remainder == 1 ? "+" : "-";
        if (names.size() < 2 && mark.empty()) continue;
        std::string text = "(";
        for (std::size_t i = 0; i < names.size(); ++i) {
            if (i) text += ' ';
            text += names[i];
        }
        result.push_back(text + ")" + mark);
    }
    if (result.empty()) return "none";
    std::string text;
    for (std::size_t i = 0; i < result.size(); ++i) {
        if (i) text += ' ';
        text += result[i];
    }
    return text;
}

int parity(const std::vector<Placement>& placements) {
    int inversions = 0;
    for (std::size_t i = 0; i < placements.size(); ++i)
        for (std::size_t j = i + 1; j < placements.size(); ++j)
            if (placements[i].piece > placements[j].piece) ++inversions;
    return inversions % 2;
}

std::string invalidity(const State& state, const Geometry& geometry) {
    if (state.size() != 54) return "length " + std::to_string(state.size());
    for (std::size_t i = 0; i < state.size(); ++i)
        if (colors.find(state[i]) == std::string::npos) return "char " + std::to_string(i + 1);
    for (char color : colors) {
        int count = static_cast<int>(std::count(state.begin(), state.end(), color));
        if (count != 9) return "count " + std::string(1, color) + " " + std::to_string(count);
    }
    std::optional<std::pair<State, Sequence>> normalized = geometry.normalize(state);
    if (!normalized) return "centers";
    std::vector<Placement> cp = identify(state, corners), ep = identify(state, edges);
    for (std::size_t i = 0; i < cp.size(); ++i) if (cp[i].piece < 0) return "corner " + corners[i].name;
    for (std::size_t i = 0; i < ep.size(); ++i) if (ep[i].piece < 0) return "edge " + edges[i].name;
    for (std::size_t i = 0; i < corners.size(); ++i)
        if (std::none_of(cp.begin(), cp.end(), [i](Placement p) { return p.piece == static_cast<int>(i); })) return "missing " + corners[i].name;
    for (std::size_t i = 0; i < edges.size(); ++i)
        if (std::none_of(ep.begin(), ep.end(), [i](Placement p) { return p.piece == static_cast<int>(i); })) return "missing " + edges[i].name;
    cp = identify(normalized->first, corners);
    ep = identify(normalized->first, edges);
    int twists = 0, flips = 0;
    for (Placement p : cp) twists += p.orientation;
    for (Placement p : ep) flips += p.orientation;
    if (twists % 3) return "twist";
    if (flips % 2) return "flip";
    if (parity(cp) != parity(ep)) return "parity";
    return "";
}

class SequenceReader {
    const std::string& line;
    std::size_t position;
    const std::map<std::string, Sequence>& macros;
    char peek() const { return position < line.size() ? line[position] : '\0'; }
    void spaces() { while (peek() == ' ') ++position; }
    [[noreturn]] void syntax() const { throw std::runtime_error("syntax at " + std::to_string(std::min(position + 1, line.size() + 1))); }
    Sequence power(const Sequence& sequence) {
        int count = 1;
        if (peek() >= '1' && peek() <= '9') {
            count = peek() - '0';
            ++position;
            if (peek() >= '0' && peek() <= '9') {
                count = 10 * count + peek() - '0';
                ++position;
            }
        }
        bool invert = peek() == '\'';
        if (invert) ++position;
        Sequence result;
        for (int i = 0; i < count; ++i) append(result, sequence);
        return invert ? inverse(std::move(result)) : result;
    }
    Sequence sequence() {
        Sequence result;
        while (true) {
            spaces();
            char c = peek();
            Sequence next;
            if (c != '\0' && letters.find(c) != std::string::npos) {
                ++position;
                int amount = 1;
                if (peek() == '2' || peek() == '\'') {
                    amount = peek() == '2' ? 2 : 3;
                    ++position;
                }
                next.push_back({c, amount});
            } else if (c == '(') {
                ++position;
                Sequence group = sequence();
                spaces();
                if (peek() != ')') syntax();
                ++position;
                next = power(group);
            } else if (c == '[') {
                ++position;
                Sequence a = sequence();
                spaces();
                char separator = peek();
                if (separator != ',' && separator != ':') syntax();
                ++position;
                Sequence b = sequence();
                spaces();
                if (peek() != ']') syntax();
                ++position;
                Sequence group = a;
                append(group, b);
                append(group, inverse(a));
                if (separator == ',') append(group, inverse(b));
                next = power(group);
            } else if (c == '{') {
                ++position;
                std::size_t start = position;
                while (peek() >= 'a' && peek() <= 'z') ++position;
                std::string name = line.substr(start, position - start);
                if (name.empty() || peek() != '}') syntax();
                auto found = macros.find(name);
                if (found == macros.end()) throw std::runtime_error("undefined " + name);
                ++position;
                next = power(found->second);
            } else break;
            append(result, next);
        }
        return result;
    }
public:
    SequenceReader(const std::string& line, std::size_t position, const std::map<std::string, Sequence>& macros)
        : line(line), position(position), macros(macros) {}
    Sequence parse() {
        Sequence result = sequence();
        spaces();
        if (peek() != '\0') syntax();
        if (result.size() > 500) throw std::runtime_error("too long");
        return result;
    }
};

std::int64_t order(const Permutation& permutation) {
    std::array<bool, 54> seen{};
    std::int64_t result = 1;
    for (int start = 0; start < 54; ++start) {
        if (seen[start]) continue;
        int position = start, count = 0;
        do {
            seen[position] = true;
            ++count;
            position = permutation[position];
        } while (position != start);
        result = std::lcm(result, static_cast<std::int64_t>(count));
    }
    return result;
}

Sequence unrotate(const Sequence& sequence, const Geometry& geometry) {
    const std::map<char, Sequence> replacements{
        {'M', {{'R', 1}, {'L', 3}, {'x', 3}}}, {'E', {{'U', 1}, {'D', 3}, {'y', 3}}},
        {'S', {{'F', 3}, {'B', 1}, {'z', 1}}}, {'r', {{'L', 1}, {'x', 1}}},
        {'l', {{'R', 1}, {'x', 3}}}, {'u', {{'D', 1}, {'y', 1}}},
        {'d', {{'U', 1}, {'y', 3}}}, {'f', {{'B', 1}, {'z', 1}}}, {'b', {{'F', 1}, {'z', 3}}}
    };
    Sequence expanded;
    for (Move move : sequence) {
        auto replacement = replacements.find(move.letter);
        if (replacement == replacements.end()) expanded.push_back(move);
        else for (Move item : replacement->second) {
            item.amount = item.amount * move.amount % 4;
            if (item.amount) expanded.push_back(item);
        }
    }
    Permutation orientation = identity();
    Sequence result;
    for (Move move : expanded) {
        if (rotation(move.letter)) orientation = compose(orientation, geometry.effect(move));
        else result.push_back(geometry.matching(compose(compose(orientation, geometry.effect(move)), inverse_effect(orientation)), true));
    }
    for (const Sequence& rotation : geometry.rotations) if (geometry.effect(rotation) == orientation) {
        append(result, rotation);
        break;
    }
    return result;
}

std::vector<std::string> split_words(const std::optional<std::string>& text) {
    std::vector<std::string> result;
    if (!text) return result;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= text->size(); ++i) if (i == text->size() || (*text)[i] == ' ') {
        result.push_back(text->substr(start, i - start));
        start = i + 1;
    }
    return result;
}

bool number_word(const std::string& text) {
    return !text.empty() && text.size() <= 10 && (text.size() == 1 || text[0] != '0') &&
           std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}
bool name_word(const std::string& text) {
    return !text.empty() && text.size() <= 8 && std::all_of(text.begin(), text.end(), [](char c) { return c >= 'a' && c <= 'z'; });
}

class Cube {
    Geometry geometry;
    State state = solved_state();
    Sequence history, redo;
    std::map<std::string, Sequence> macros;
    std::map<std::string, std::pair<State, Sequence>> saves;

    void apply(const Sequence& sequence) {
        state = geometry.apply(state, sequence);
        append(history, sequence);
        redo.clear();
    }
    bool search(const State& current, int remaining, char previous, Sequence& path) const {
        if (!remaining) return mismatches(current) == 0;
        for (char face : faces) {
            if (face == previous || (previous == 'D' && face == 'U') || (previous == 'L' && face == 'R') ||
                (previous == 'B' && face == 'F')) continue;
            for (int amount = 1; amount <= 3; ++amount) {
                Move move{face, amount};
                path.push_back(move);
                State next = apply_effect(current, geometry.effect(move));
                if (search(next, remaining - 1, face, path)) return true;
                path.pop_back();
            }
        }
        return false;
    }
    Sequence scramble(int count, std::uint64_t seed) const {
        Sequence sequence;
        auto random = [&]() {
            seed = (48271 * seed) % 2147483647;
            return seed;
        };
        for (int i = 0; i < count; ++i) {
            std::string usable;
            for (char face : faces) {
                if (!sequence.empty() && face == sequence.back().letter) continue;
                if (sequence.size() >= 2 && axis(sequence.back().letter) == axis(sequence[sequence.size() - 2].letter) &&
                    axis(face) == axis(sequence.back().letter)) continue;
                usable += face;
            }
            char face = usable[random() % usable.size()];
            std::uint64_t value = random() % 3;
            sequence.push_back({face, value == 0 ? 1 : value == 1 ? 3 : 2});
        }
        return sequence;
    }
    void show() const {
        auto row = [&](const std::vector<char>& row_faces, int r, bool indent) {
            if (indent) std::cout << "      ";
            bool first = true;
            for (char face : row_faces) for (int c = 0; c < 3; ++c) {
                if (!first) std::cout << ' ';
                first = false;
                std::cout << state[sticker(face, r, c)];
            }
            std::cout << '\n';
        };
        for (int r = 0; r < 3; ++r) row({'U'}, r, true);
        for (int r = 0; r < 3; ++r) row({'L', 'F', 'R', 'B'}, r, false);
        for (int r = 0; r < 3; ++r) row({'D'}, r, true);
    }
    void stage(const State& normalized) const {
        std::vector<Placement> cp = identify(normalized, corners), ep = identify(normalized, edges);
        auto fixed = [](const std::vector<Placement>& placements, int index) {
            return placements[index].piece == index && placements[index].orientation == 0;
        };
        int cross = 0, slots = 0, top = 0;
        for (int i = 4; i < 8; ++i) if (fixed(ep, i)) ++cross;
        for (int i = 0; i < 4; ++i) if (fixed(cp, 4 + i) && fixed(ep, 8 + i)) ++slots;
        for (int i = 0; i < 9; ++i) if (normalized[i] == 'W') ++top;
        std::string result = mismatches(normalized) == 0 ? "solved"
                           : cross == 4 && slots == 4 && top == 9 ? "oll"
                           : cross == 4 && slots == 4 ? "f2l" : cross == 4 ? "cross" : "none";
        std::cout << "stage " << result << " cross " << cross << " slots " << slots << " top " << top << '\n';
    }
    void execute(const std::string& line) {
        std::size_t space = line.find(' ');
        std::string command = line.substr(0, space);
        std::optional<std::string> argument;
        if (space != std::string::npos) argument = line.substr(space + 1);
        static const std::set<std::string> no_arguments{
            "RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS"
        };
        static const std::map<std::string, std::size_t> word_commands{
            {"CHECK", 1}, {"LOAD", 1}, {"UNDO", 1}, {"REDO", 1}, {"SEARCH", 1},
            {"WHERE", 1}, {"SAVE", 1}, {"RESTORE", 1}, {"SCRAMBLE", 2}
        };
        static const std::set<std::string> sequence_commands{
            "APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL"
        };
        bool headed = command == "DEFINE" || command == "MIRROR" || command == "ROTATE";
        if (!no_arguments.count(command) && !word_commands.count(command) && !sequence_commands.count(command) && !headed)
            throw std::runtime_error("unknown command " + command);
        if (no_arguments.count(command) && argument) throw std::runtime_error("bad arguments");
        std::vector<std::string> words;
        if (word_commands.count(command)) {
            words = split_words(argument);
            if (words.size() != word_commands.at(command)) throw std::runtime_error("bad arguments");
            if ((command == "UNDO" || command == "REDO" || command == "SEARCH") && !number_word(words[0]))
                throw std::runtime_error("bad arguments");
            if (command == "SCRAMBLE" && (!number_word(words[0]) || !number_word(words[1])))
                throw std::runtime_error("bad arguments");
            if ((command == "SAVE" || command == "RESTORE") && !name_word(words[0])) throw std::runtime_error("bad arguments");
        }
        std::string head;
        std::size_t sequence_start = argument ? space + 1 : line.size();
        if (headed) {
            if (!argument) throw std::runtime_error("bad arguments");
            std::size_t separator = argument->find(' ');
            head = argument->substr(0, separator);
            sequence_start = separator == std::string::npos ? line.size() : space + separator + 2;
            if (command == "DEFINE" && !name_word(head)) throw std::runtime_error("bad arguments");
            if (command == "MIRROR" && head != "LR" && head != "UD" && head != "FB") throw std::runtime_error("bad arguments");
            if (command == "ROTATE" && (head.empty() || !rotation(head[0]) ||
                (head.size() != 1 && (head.size() != 2 || (head[1] != '\'' && head[1] != '2')))))
                throw std::runtime_error("bad arguments");
        }
        Sequence sequence;
        if (headed || sequence_commands.count(command)) sequence = SequenceReader(line, sequence_start, macros).parse();
        std::uint64_t number = 0;
        if (command == "UNDO" || command == "REDO" || command == "SEARCH" || command == "SCRAMBLE") {
            number = std::stoull(words[0]);
            if ((command == "UNDO" || command == "REDO") && number == 0) throw std::runtime_error("bad value");
            if (command == "SEARCH" && number > 4) throw std::runtime_error("bad value");
            if (command == "SCRAMBLE" && (number < 1 || number > 50 || std::stoull(words[1]) < 1 ||
                                          std::stoull(words[1]) > 2147483646)) throw std::runtime_error("bad value");
        }
        if (command == "WHERE") {
            bool found = false;
            for (const Piece& p : corners) if (p.name == words[0]) found = true;
            for (const Piece& p : edges) if (p.name == words[0]) found = true;
            if (!found) throw std::runtime_error("unknown piece " + words[0]);
        }
        if (command == "RESET") {
            state = solved_state();
            history.clear();
            redo.clear();
            std::cout << "reset\n";
        } else if (command == "SHOW") show();
        else if (command == "STATE") std::cout << "state " << state << '\n';
        else if (command == "ISSOLVED") {
            int count = mismatches(state);
            if (count == 0) std::cout << "solved\n";
            else std::cout << "unsolved " << count << '\n';
        } else if (command == "HISTORY") std::cout << "history " << sequence_text(history) << '\n';
        else if (command == "SOLUTION") std::cout << "solution " << sequence_text(simplify(inverse(history))) << '\n';
        else if (command == "ANALYZE" || command == "STAGE" || command == "WHERE") {
            std::pair<State, Sequence> normalized = *geometry.normalize(state);
            if (command == "ANALYZE") {
                std::cout << "rotation" << (normalized.second.empty() ? " none" : moves_text(normalized.second)) << '\n';
                std::cout << "corners " << cycles(normalized.first, corners) << '\n';
                std::cout << "edges " << cycles(normalized.first, edges) << '\n';
            } else if (command == "STAGE") stage(normalized.first);
            else {
                bool corner = std::any_of(corners.begin(), corners.end(), [&](const Piece& p) { return p.name == words[0]; });
                const std::vector<Piece>& pieces = corner ? corners : edges;
                std::vector<Placement> placements = identify(normalized.first, pieces);
                for (std::size_t i = 0; i < placements.size(); ++i) if (pieces[placements[i].piece].name == words[0])
                    std::cout << words[0] << " at " << pieces[i].name << (corner ? " twist " : " flip ") << placements[i].orientation << '\n';
            }
        } else if (command == "MACROS") {
            std::cout << "macros " << macros.size() << '\n';
            for (const auto& macro : macros) std::cout << "macro " << macro.first << ' ' << sequence_text(macro.second) << '\n';
        } else if (command == "CHECK" || command == "LOAD") {
            std::string reason = invalidity(words[0], geometry);
            if (command == "CHECK") std::cout << (reason.empty() ? "valid" : "invalid " + reason) << '\n';
            else {
                if (!reason.empty()) throw std::runtime_error("invalid " + reason);
                state = words[0];
                history.clear();
                redo.clear();
                std::cout << "loaded\n";
            }
        } else if (command == "UNDO" || command == "REDO") {
            Sequence& source = command == "UNDO" ? history : redo;
            Sequence& destination = command == "UNDO" ? redo : history;
            if (source.empty()) throw std::runtime_error(command == "UNDO" ? "nothing to undo" : "nothing to redo");
            std::size_t count = static_cast<std::size_t>(std::min(number, static_cast<std::uint64_t>(source.size())));
            for (std::size_t i = 0; i < count; ++i) {
                Move move = source.back();
                source.pop_back();
                destination.push_back(move);
                if (command == "UNDO") move.amount = 4 - move.amount;
                state = apply_effect(state, geometry.effect(move));
            }
            std::cout << (command == "UNDO" ? "undone " : "redone ") << count << '\n';
        } else if (command == "SEARCH") {
            for (int depth = 0; depth <= static_cast<int>(number); ++depth) {
                Sequence result;
                if (search(state, depth, '\0', result)) {
                    std::cout << "found " << sequence_text(result) << '\n';
                    return;
                }
            }
            std::cout << "not found\n";
        } else if (command == "SAVE") {
            saves[words[0]] = {state, history};
            std::cout << "saved " << words[0] << '\n';
        } else if (command == "RESTORE") {
            auto found = saves.find(words[0]);
            if (found == saves.end()) throw std::runtime_error("no save " + words[0]);
            state = found->second.first;
            history = found->second.second;
            redo.clear();
            std::cout << "restored " << words[0] << '\n';
        } else if (command == "SCRAMBLE") {
            Sequence result = scramble(static_cast<int>(number), std::stoull(words[1]));
            apply(result);
            std::cout << "scramble" << moves_text(result) << '\n';
        } else if (command == "APPLY") {
            apply(sequence);
            std::cout << "applied " << sequence.size() << '\n';
        } else if (command == "INVERT") std::cout << "inverse " << sequence_text(inverse(sequence)) << '\n';
        else if (command == "SIMPLIFY") std::cout << "simplified " << sequence_text(simplify(sequence)) << '\n';
        else if (command == "METRICS") {
            int htm = 0, qtm = 0, stm = 0;
            for (Move move : sequence) if (!rotation(move.letter)) {
                int weight = outer(move.letter) || wide(move.letter) ? 1 : 2;
                htm += weight;
                qtm += weight * (move.amount == 2 ? 2 : 1);
                ++stm;
            }
            std::cout << "metrics htm " << htm << " qtm " << qtm << " stm " << stm << " etm " << sequence.size() << '\n';
        } else if (command == "ORDER") std::cout << "order " << order(geometry.effect(sequence)) << '\n';
        else if (command == "CYCLES") {
            State result = geometry.apply(solved_state(), sequence);
            std::cout << "corners " << cycles(result, corners) << '\n';
            std::cout << "edges " << cycles(result, edges) << '\n';
            std::cout << "centers " << cycles(result, centers) << '\n';
        } else if (command == "UNROTATE") std::cout << "unrotated " << sequence_text(unrotate(sequence, geometry)) << '\n';
        else if (command == "UNTIL") {
            Permutation permutation = geometry.effect(sequence);
            std::int64_t period = order(permutation);
            State candidate = state;
            for (std::int64_t i = 1; i <= period; ++i) {
                candidate = apply_effect(candidate, permutation);
                if (mismatches(candidate) == 0) {
                    std::cout << "until " << i << '\n';
                    return;
                }
            }
            std::cout << "until never\n";
        } else if (command == "DEFINE") {
            macros[head] = sequence;
            std::cout << "defined " << head << ' ' << sequence.size() << '\n';
        } else if (command == "MIRROR") {
            char mirror_axis = head == "LR" ? 'x' : head == "UD" ? 'y' : 'z';
            static const std::string from = "RLrlUDudFBfb", to = "LRlrDUduBFbf";
            for (Move& move : sequence) {
                if (axis(move.letter) == mirror_axis) {
                    if (outer(move.letter) || wide(move.letter)) {
                        move.letter = to[from.find(move.letter)];
                        move.amount = 4 - move.amount;
                    }
                } else move.amount = 4 - move.amount;
            }
            std::cout << "mirror " << sequence_text(sequence) << '\n';
        } else if (command == "ROTATE") {
            Move move{head[0], head.size() == 1 ? 1 : head[1] == '2' ? 2 : 3};
            const Permutation& rho = geometry.effect(move);
            for (Move& item : sequence)
                item = geometry.matching(compose(compose(rho, geometry.effect(item)), inverse_effect(rho)));
            std::cout << "rotated " << sequence_text(sequence) << '\n';
        }
    }
public:
    void command(const std::string& line) {
        try { execute(line); }
        catch (const std::runtime_error& error) { std::cout << "error: " << error.what() << '\n'; }
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Cube cube;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        cube.command(line);
    }
}
