#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Dice = std::array<int, 5>;
using Holds = std::array<bool, 5>;
using Counts = std::array<int, 6>;

enum Category {
    Ones, Twos, Threes, Fours, Fives, Sixes, ThreeKind, FourKind,
    FullHouse, Small, Large, Yahtzee, Chance, CategoryCount
};
enum class Strategy { Kind, Straight, High, Upper };
enum class Joker { Forced, Free, Off };

const std::array<std::string, CategoryCount> categoryNames = {
    "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
    "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"
};
const std::array<std::string, 4> strategyNames = {"KIND", "STRAIGHT", "HIGH", "UPPER"};
constexpr std::array<Integer, 6> powersOfSix = {1, 6, 36, 216, 1296, 7776};
constexpr std::array<int, 6> factorial = {1, 1, 2, 6, 24, 120};

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };

Integer integerWord(const std::string& word, Integer minimum, Integer maximum) {
    std::size_t first = word[0] == '-' ? 1 : 0;
    if (first == word.size() || word == "-0" ||
        (word.size() - first > 1 && word[first] == '0')) {
        throw CommandError("bad value " + word);
    }
    Integer value = 0;
    for (std::size_t i = first; i < word.size(); ++i) {
        if (word[i] < '0' || word[i] > '9') throw CommandError("bad value " + word);
        value = value * 10 + word[i] - '0';
    }
    if (first != 0) value = -value;
    if (value < minimum || value > maximum) throw CommandError("bad value " + word);
    return value;
}

void playerName(const std::string& word) {
    if (word.size() > 8 || !std::all_of(word.begin(), word.end(), [](char c) { return c >= 'A' && c <= 'Z'; })) {
        throw CommandError("bad name " + word);
    }
}

Holds holdPattern(const std::string& word) {
    if (word.size() != 5 || !std::all_of(word.begin(), word.end(), [](char c) { return c == '0' || c == '1'; })) {
        throw CommandError("bad pattern " + word);
    }
    Holds holds{};
    for (int i = 0; i < 5; ++i) holds[i] = word[i] == '1';
    return holds;
}

Category categoryWord(const std::string& word) {
    for (int i = 0; i < CategoryCount; ++i) if (categoryNames[i] == word) return static_cast<Category>(i);
    throw CommandError("bad category " + word);
}

Strategy strategyWord(const std::string& word) {
    for (int i = 0; i < 4; ++i) if (strategyNames[i] == word) return static_cast<Strategy>(i);
    throw CommandError("bad strategy " + word);
}

std::string fraction(Integer numerator, Integer denominator) {
    Integer divisor = std::gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;
    return std::to_string(numerator) + (denominator == 1 ? "" : "/" + std::to_string(denominator));
}

std::string average(Integer sum, Integer count) {
    Integer hundredths = count == 0 ? 0 : 100 * sum / count;
    std::ostringstream text;
    text << hundredths / 100 << '.' << std::setfill('0') << std::setw(2) << hundredths % 100;
    return text.str();
}

std::string patternText(const Holds& holds) {
    std::string text;
    for (bool held : holds) text += held ? '1' : '0';
    return text;
}

std::string facesText(const Dice& dice, const Holds& selected = {true, true, true, true, true}) {
    std::string text;
    for (int i = 0; i < 5; ++i) {
        if (!selected[i]) continue;
        if (!text.empty()) text += ' ';
        text += std::to_string(dice[i]);
    }
    return text.empty() ? "-" : text;
}

Counts faceCounts(const Dice& dice, const Holds& selected = {true, true, true, true, true}) {
    Counts counts{};
    for (int i = 0; i < 5; ++i) if (selected[i]) ++counts[dice[i] - 1];
    return counts;
}

int mostFrequent(const Counts& counts) {
    int best = 0;
    for (int face = 1; face < 6; ++face) if (counts[face] >= counts[best]) best = face;
    return best;
}

bool isYahtzee(const Counts& counts) { return *std::max_element(counts.begin(), counts.end()) == 5; }

int normalScore(Category category, const Counts& counts) {
    if (category <= Sixes) return (category + 1) * counts[category];
    int sum = 0;
    int largest = *std::max_element(counts.begin(), counts.end());
    for (int face = 0; face < 6; ++face) sum += (face + 1) * counts[face];
    switch (category) {
        case ThreeKind: return largest >= 3 ? sum : 0;
        case FourKind: return largest >= 4 ? sum : 0;
        case FullHouse:
            return std::find(counts.begin(), counts.end(), 3) != counts.end() &&
                   std::find(counts.begin(), counts.end(), 2) != counts.end() ? 25 : 0;
        case Small:
        case Large: {
            int length = category == Small ? 4 : 5;
            for (int start = 0; start <= 6 - length; ++start) {
                bool present = true;
                for (int offset = 0; offset < length; ++offset) present = present && counts[start + offset] > 0;
                if (present) return category == Small ? 30 : 40;
            }
            return 0;
        }
        case Yahtzee: return largest == 5 ? 50 : 0;
        default: return sum;
    }
}

struct Rules { int rolls = 3; Joker joker = Joker::Forced; };

struct Player {
    std::string name;
    Strategy strategy = Strategy::Kind;
    std::array<std::optional<int>, CategoryCount> boxes{};
    int yahtzeeBonus = 0;

    int upper() const {
        int sum = 0;
        for (int i = Ones; i <= Sixes; ++i) sum += boxes[i].value_or(0);
        return sum;
    }
    int upperBonus() const { return upper() >= 63 ? 35 : 0; }
    int total() const {
        int sum = upperBonus() + yahtzeeBonus;
        for (const std::optional<int>& box : boxes) sum += box.value_or(0);
        return sum;
    }
    int round() const {
        return 1 + static_cast<int>(std::count_if(boxes.begin(), boxes.end(), [](const std::optional<int>& box) { return box.has_value(); }));
    }
};

struct Candidates {
    std::array<bool, CategoryCount> allowed{};
    std::array<int, CategoryCount> points{};
    Category best = Ones;
    bool joker = false;
    std::string requirement;
};

Candidates candidates(const Player& player, const Counts& counts, Joker rule) {
    Candidates result;
    for (int i = 0; i < CategoryCount; ++i) result.allowed[i] = !player.boxes[i].has_value();
    result.joker = rule != Joker::Off && isYahtzee(counts) && player.boxes[Yahtzee].has_value();
    if (result.joker && rule == Joker::Forced) {
        int face = mostFrequent(counts);
        if (!player.boxes[face].has_value()) {
            result.allowed.fill(false);
            result.allowed[face] = true;
            result.requirement = categoryNames[face];
        } else {
            bool lowerOpen = false;
            for (int i = ThreeKind; i < CategoryCount; ++i) lowerOpen = lowerOpen || result.allowed[i];
            if (lowerOpen) {
                for (int i = Ones; i <= Sixes; ++i) result.allowed[i] = false;
                result.requirement = "lower box";
            }
        }
    }
    int bestScore = -1;
    for (int i = 0; i < CategoryCount; ++i) {
        if (!result.allowed[i]) continue;
        Category category = static_cast<Category>(i);
        int points = normalScore(category, counts);
        if (result.joker) {
            if (category == FullHouse) points = 25;
            if (category == Small) points = 30;
            if (category == Large) points = 40;
        }
        result.points[i] = points;
        if (points > bestScore) { bestScore = points; result.best = category; }
    }
    return result;
}

Holds botHolds(Strategy strategy, const Dice& dice) {
    Holds holds{};
    Counts counts = faceCounts(dice);
    if (strategy == Strategy::High) {
        for (int i = 0; i < 5; ++i) holds[i] = dice[i] >= 5;
        return holds;
    }
    if (strategy == Strategy::Straight) {
        int bestStart = 0, bestLength = 0;
        for (int start = 0; start < 6; ++start) {
            int length = 0;
            while (start + length < 6 && counts[start + length] > 0) ++length;
            if (length >= bestLength) { bestStart = start; bestLength = length; }
        }
        if (bestLength >= 3) {
            for (int face = bestStart + 1; face <= bestStart + bestLength; ++face) {
                for (int i = 0; i < 5; ++i) if (dice[i] == face) { holds[i] = true; break; }
            }
            return holds;
        }
    }
    int target = mostFrequent(counts) + 1;
    for (int i = 0; i < 5; ++i) holds[i] = dice[i] == target;
    return holds;
}

struct Outcome { Counts counts; int weight; };

class Rerolls {
    void enumerate(int remaining, int face, int total, Counts& counts) {
        if (face == 5) {
            counts[face] = remaining;
            int divisor = 1;
            for (int count : counts) divisor *= factorial[count];
            outcomes[total].push_back({counts, factorial[total] / divisor});
            return;
        }
        for (int count = 0; count <= remaining; ++count) {
            counts[face] = count;
            enumerate(remaining - count, face + 1, total, counts);
        }
    }
public:
    std::array<std::vector<Outcome>, 6> outcomes;
    Rerolls() {
        Counts counts{};
        for (int total = 0; total <= 5; ++total) enumerate(total, 0, total, counts);
    }
};

Counts combined(const Counts& held, const Counts& rolled) {
    Counts result{};
    for (int i = 0; i < 6; ++i) result[i] = held[i] + rolled[i];
    return result;
}

struct Advice { Holds holds; Integer numerator; Integer denominator; };

Advice advise(const Player& player, const Dice& dice, int rollsLeft, Joker joker, const Rerolls& rerolls) {
    std::map<Counts, Integer> values;
    for (const Outcome& outcome : rerolls.outcomes[5]) {
        Candidates scores = candidates(player, outcome.counts, joker);
        values[outcome.counts] = scores.points[scores.best];
    }
    Integer denominator = 1;
    std::map<Counts, Integer> expectations;
    for (int depth = 1; depth <= rollsLeft; ++depth) {
        expectations.clear();
        for (int kept = 0; kept <= 5; ++kept) {
            int rolled = 5 - kept;
            for (const Outcome& held : rerolls.outcomes[kept]) {
                Integer sum = 0;
                for (const Outcome& outcome : rerolls.outcomes[rolled]) {
                    sum += outcome.weight * values.at(combined(held.counts, outcome.counts));
                }
                expectations[held.counts] = sum * (powersOfSix[5] / powersOfSix[rolled]);
            }
        }
        denominator *= powersOfSix[5];
        if (depth == rollsLeft) break;
        for (auto& [counts, value] : values) {
            Integer best = 0;
            for (const auto& [held, expected] : expectations) {
                bool available = true;
                for (int face = 0; face < 6; ++face) available = available && held[face] <= counts[face];
                if (available) best = std::max(best, expected);
            }
            value = best;
        }
    }
    Advice best{{}, -1, denominator};
    for (int mask = 0; mask < 32; ++mask) {
        Holds holds{};
        for (int i = 0; i < 5; ++i) holds[i] = (mask & (1 << (4 - i))) != 0;
        Integer expected = expectations.at(faceCounts(dice, holds));
        if (expected > best.numerator) best = {holds, expected, denominator};
    }
    return best;
}

struct Turn {
    int player = 0;
    int rolls = 0;
    Dice dice{};
    Holds holds{};
};

struct ScoreEntry {
    Turn turn;
    Category category;
    int points;
    int yahtzeeBonus;
    bool joker;
};

struct RedoEntry { std::optional<Turn> resume; ScoreEntry score; };

class Game {
    std::vector<std::string>* output;

    void emit(const std::string& line) { if (output != nullptr) output->push_back(line); }
    int rollDie() {
        int face;
        if (!loaded.empty()) { face = loaded.front(); loaded.pop_front(); }
        else { state = 48271 * state % 2147483647; face = static_cast<int>(state % 6) + 1; }
        ++faceTotals[face - 1];
        return face;
    }
public:
    Rules rules;
    Integer state;
    std::vector<Player> players;
    std::deque<int> loaded;
    std::array<Integer, 6> faceTotals{};
    std::optional<Turn> turn = Turn{};
    std::vector<ScoreEntry> entries;
    std::vector<RedoEntry> redo;

    Game(Integer seed, const std::vector<std::string>& names, Rules gameRules, std::vector<std::string>* lines = nullptr)
        : output(lines), rules(gameRules), state(seed) {
        for (const std::string& name : names) players.push_back(Player{name});
    }

    void turnCheck() const { if (!turn.has_value()) throw CommandError("game over"); }
    void rolledCheck() const {
        turnCheck();
        if (turn->rolls == 0) throw CommandError("not rolled");
    }
    void rollsLeftCheck() const {
        rolledCheck();
        if (turn->rolls == rules.rolls) throw CommandError("no rolls left");
    }
    std::vector<int> ranking() const {
        std::vector<int> seats(players.size());
        std::iota(seats.begin(), seats.end(), 0);
        std::stable_sort(seats.begin(), seats.end(), [&](int a, int b) { return players[a].total() > players[b].total(); });
        return seats;
    }
    std::string nextTurnText() const {
        if (!turn.has_value()) return "game over";
        const Player& player = players[turn->player];
        return "turn " + std::to_string(player.round()) + " " + player.name;
    }
    void roll() {
        redo.clear();
        for (int i = 0; i < 5; ++i) if (turn->rolls == 0 || !turn->holds[i]) turn->dice[i] = rollDie();
        ++turn->rolls;
        emit(players[turn->player].name + " roll " + std::to_string(turn->rolls) + ": " + facesText(turn->dice));
    }
    void hold(const Holds& holds) {
        redo.clear();
        turn->holds = holds;
        emit(players[turn->player].name + " holds " + patternText(holds) + ": " + facesText(turn->dice, holds));
    }
    ScoreEntry scoreDetails(Category category) const {
        const Player& player = players[turn->player];
        Counts counts = faceCounts(turn->dice);
        Candidates scores = candidates(player, counts, rules.joker);
        int bonus = isYahtzee(counts) && player.boxes[Yahtzee] == 50 ? 100 : 0;
        return {*turn, category, scores.points[category], bonus, scores.joker};
    }
    ScoreEntry checkedScore(Category category) const {
        rolledCheck();
        const Player& player = players[turn->player];
        if (player.boxes[category].has_value()) throw CommandError(categoryNames[category] + " already used");
        Candidates scores = candidates(player, faceCounts(turn->dice), rules.joker);
        if (!scores.allowed[category]) throw CommandError("joker requires " + scores.requirement);
        return scoreDetails(category);
    }
    std::string scoreText(const ScoreEntry& entry, bool hypothetical) const {
        const Player& player = players[entry.turn.player];
        int upperAfter = player.upper() + (entry.category <= Sixes ? entry.points : 0);
        int addedUpper = upperAfter >= 63 && player.upperBonus() == 0 ? 35 : 0;
        std::string line = player.name + (hypothetical ? " would score " : " scores ") + std::to_string(entry.points) + " in " + categoryNames[entry.category];
        if (entry.joker) line += " joker";
        if (entry.yahtzeeBonus != 0) line += " ybonus 100";
        if (addedUpper != 0) line += " ubonus 35";
        return line + " total " + std::to_string(player.total() + entry.points + entry.yahtzeeBonus + addedUpper);
    }
    void score(Category category) {
        ScoreEntry entry = scoreDetails(category);
        std::string line = scoreText(entry, false);
        Player& player = players[entry.turn.player];
        player.boxes[category] = entry.points;
        player.yahtzeeBonus += entry.yahtzeeBonus;
        entries.push_back(entry);
        redo.clear();
        if (entries.size() == 13 * players.size()) turn.reset();
        else turn = Turn{(entry.turn.player + 1) % static_cast<int>(players.size())};
        emit(line);
        emit(nextTurnText());
    }
    void botTurn() {
        if (turn->rolls == 0) roll();
        Strategy strategy = players[turn->player].strategy;
        while (turn->rolls < rules.rolls) {
            Holds holds = botHolds(strategy, turn->dice);
            if (std::all_of(holds.begin(), holds.end(), [](bool held) { return held; })) break;
            hold(holds);
            roll();
        }
        Counts counts = faceCounts(turn->dice);
        Candidates scores = candidates(players[turn->player], counts, rules.joker);
        Category category = scores.best;
        int face = mostFrequent(counts);
        if (strategy == Strategy::Upper && counts[face] >= 3 && scores.allowed[face]) category = static_cast<Category>(face);
        score(category);
    }
    void undoScore() {
        if (entries.empty()) throw CommandError("nothing to undo");
        ScoreEntry entry = entries.back();
        entries.pop_back();
        players[entry.turn.player].boxes[entry.category].reset();
        players[entry.turn.player].yahtzeeBonus -= entry.yahtzeeBonus;
        redo.push_back({turn, entry});
        turn = entry.turn;
        emit("undo " + players[entry.turn.player].name + " " + categoryNames[entry.category] + " " + std::to_string(entry.points));
    }
    void redoScore() {
        if (redo.empty()) throw CommandError("nothing to redo");
        RedoEntry saved = redo.back();
        redo.pop_back();
        const ScoreEntry& entry = saved.score;
        players[entry.turn.player].boxes[entry.category] = entry.points;
        players[entry.turn.player].yahtzeeBonus += entry.yahtzeeBonus;
        entries.push_back(entry);
        turn = saved.resume;
        emit("redo " + players[entry.turn.player].name + " " + categoryNames[entry.category] + " " + std::to_string(entry.points));
    }
};

struct Record { Integer games = 0, wins = 0, sum = 0; int best = 0; };
struct SimulationTotal { Integer wins = 0, sum = 0, bonus = 0, yahtzee = 0; int best = 0; };

class Program {
    Rules rules;
    Rerolls rerolls;
    std::unique_ptr<Game> game;
    std::map<std::string, Record> records;
    std::vector<std::string> output;

    template<class... Values> void emit(const Values&... values) {
        std::ostringstream line;
        bool first = true;
        ((line << (first ? "" : " ") << values, first = false), ...);
        output.push_back(line.str());
    }

    Game& requireGame() {
        if (game == nullptr) throw CommandError("no game");
        return *game;
    }

    void odds(Game& table, const Holds& holds) {
        const Turn& turn = *table.turn;
        const Player& player = table.players[turn.player];
        Counts held = faceCounts(turn.dice, holds);
        int rolled = 5 - std::accumulate(held.begin(), held.end(), 0);
        Integer outcomes = powersOfSix[rolled];
        std::array<Integer, CategoryCount> sums{}, positive{};
        Integer bestSum = 0;
        for (const Outcome& outcome : rerolls.outcomes[rolled]) {
            Candidates scores = candidates(player, combined(held, outcome.counts), rules.joker);
            for (int i = 0; i < CategoryCount; ++i) {
                sums[i] += outcome.weight * scores.points[i];
                if (scores.points[i] > 0) positive[i] += outcome.weight;
            }
            bestSum += outcome.weight * scores.points[scores.best];
        }
        emit("odds", patternText(holds), "outcomes", outcomes);
        for (int i = 0; i < CategoryCount; ++i) {
            if (!player.boxes[i].has_value()) emit(categoryNames[i], "expect", fraction(sums[i], outcomes), "chance", fraction(positive[i], outcomes));
        }
        emit("best expect", fraction(bestSum, outcomes));
    }

    void card(const Game& table) {
        for (int row = -1; row < CategoryCount + 4; ++row) {
            std::string heading = row == -1 ? "CATEGORY" : row < CategoryCount ? categoryNames[row] :
                std::array<std::string, 4>{"UPPER", "BONUS", "YBONUS", "TOTAL"}[row - CategoryCount];
            std::ostringstream line;
            line << std::left << std::setw(9) << heading;
            for (const Player& player : table.players) {
                std::string value;
                if (row == -1) value = player.name;
                else if (row < CategoryCount) value = player.boxes[row].has_value() ? std::to_string(*player.boxes[row]) : "-";
                else {
                    std::array<int, 4> values = {player.upper(), player.upperBonus(), player.yahtzeeBonus, player.total()};
                    value = std::to_string(values[row - CategoryCount]);
                }
                line << ' ' << std::right << std::setw(std::max(4, static_cast<int>(player.name.size()))) << value;
            }
            emit(line.str());
        }
    }

    void statistics(const Game& table) {
        for (int seat = 0; seat < static_cast<int>(table.players.size()); ++seat) {
            Integer turns = 0, rolls = 0, zeros = 0, yahtzees = 0, sum = 0;
            for (const ScoreEntry& entry : table.entries) {
                if (entry.turn.player != seat) continue;
                ++turns;
                rolls += entry.turn.rolls;
                zeros += entry.points == 0;
                yahtzees += isYahtzee(faceCounts(entry.turn.dice));
                sum += entry.points;
            }
            emit("stats", table.players[seat].name, "turns", turns, "rolls", rolls, "zeros", zeros,
                 "yahtzees", yahtzees, "average", average(sum, turns));
        }
    }

    void simulate(Integer seed, int count, const std::vector<Strategy>& strategies) {
        std::vector<SimulationTotal> totals(strategies.size());
        std::vector<std::string> names;
        for (int seat = 0; seat < static_cast<int>(strategies.size()); ++seat) names.emplace_back(1, static_cast<char>('A' + seat));
        Integer state = seed;
        for (int round = 0; round < count; ++round) {
            Game simulation(state, names, rules);
            for (std::size_t seat = 0; seat < strategies.size(); ++seat) simulation.players[seat].strategy = strategies[seat];
            while (simulation.turn.has_value()) simulation.botTurn();
            state = simulation.state;
            ++totals[simulation.ranking()[0]].wins;
            for (std::size_t seat = 0; seat < strategies.size(); ++seat) {
                const Player& player = simulation.players[seat];
                SimulationTotal& total = totals[seat];
                total.sum += player.total();
                total.best = std::max(total.best, player.total());
                total.bonus += player.upperBonus() == 35;
                total.yahtzee += player.boxes[Yahtzee] == 50;
            }
        }
        emit("sim seed", seed, "games", count, "players", strategies.size());
        for (std::size_t seat = 0; seat < strategies.size(); ++seat) {
            const SimulationTotal& total = totals[seat];
            emit("seat", seat + 1, strategyNames[static_cast<int>(strategies[seat])], "wins", total.wins,
                 "average", average(total.sum, count), "best", total.best, "bonus", total.bonus, "yahtzee", total.yahtzee);
        }
    }

    void execute(const std::vector<std::string>& words) {
        const std::string& command = words[0];
        if (command == "RULE") {
            if (words[1] != "ROLLS" && words[1] != "JOKER") throw CommandError("unknown rule " + words[1]);
            Rules changed = rules;
            if (words[1] == "ROLLS") changed.rolls = static_cast<int>(integerWord(words[2], 1, 4));
            else if (words[2] == "FORCED") changed.joker = Joker::Forced;
            else if (words[2] == "FREE") changed.joker = Joker::Free;
            else if (words[2] == "OFF") changed.joker = Joker::Off;
            else throw CommandError("bad value " + words[2]);
            if (game != nullptr) throw CommandError("game in progress");
            rules = changed;
            emit("rule", words[1], words[2]);
        } else if (command == "GAME") {
            Integer seed = integerWord(words[1], 1, 2147483646);
            std::vector<std::string> names(words.begin() + 2, words.end());
            for (const std::string& name : names) playerName(name);
            if (names.size() > 6) throw CommandError("too many players");
            if (game != nullptr) throw CommandError("game in progress");
            std::set<std::string> seen;
            for (const std::string& name : names) if (!seen.insert(name).second) throw CommandError("duplicate name " + name);
            game = std::make_unique<Game>(seed, names, rules, &output);
            std::string line = "game seed " + std::to_string(seed) + " players";
            for (const std::string& name : names) line += " " + name;
            emit(line);
            emit(game->nextTurnText());
        } else if (command == "BOT") {
            playerName(words[1]);
            Strategy strategy = strategyWord(words[2]);
            Game& table = requireGame();
            auto player = std::find_if(table.players.begin(), table.players.end(), [&](const Player& value) { return value.name == words[1]; });
            if (player == table.players.end()) throw CommandError("no player " + words[1]);
            player->strategy = strategy;
            emit("bot", words[1], words[2]);
        } else if (command == "LOAD" || command == "KEEP") {
            std::vector<int> faces;
            for (std::size_t i = 1; i < words.size(); ++i) faces.push_back(static_cast<int>(integerWord(words[i], 1, 6)));
            Game& table = requireGame();
            if (command == "LOAD") {
                table.loaded.insert(table.loaded.end(), faces.begin(), faces.end());
                emit("loaded", table.loaded.size());
            } else {
                table.rollsLeftCheck();
                Holds holds{};
                for (int face : faces) {
                    int die = 0;
                    while (die < 5 && (holds[die] || table.turn->dice[die] != face)) ++die;
                    if (die == 5) throw CommandError("not showing " + std::to_string(face));
                    holds[die] = true;
                }
                table.hold(holds);
            }
        } else if (command == "ROLL") {
            Game& table = requireGame();
            table.turnCheck();
            if (table.turn->rolls == rules.rolls) throw CommandError("no rolls left");
            if (std::all_of(table.turn->holds.begin(), table.turn->holds.end(), [](bool held) { return held; })) throw CommandError("all dice held");
            table.roll();
        } else if (command == "HOLD" || command == "ODDS") {
            Holds holds = holdPattern(words[1]);
            Game& table = requireGame();
            table.rollsLeftCheck();
            if (command == "HOLD") table.hold(holds);
            else odds(table, holds);
        } else if (command == "SCORE" || command == "WHATIF") {
            Category category = categoryWord(words[1]);
            Game& table = requireGame();
            ScoreEntry entry = table.checkedScore(category);
            if (command == "SCORE") table.score(category);
            else emit(table.scoreText(entry, true));
        } else if (command == "UNDO") {
            requireGame().undoScore();
        } else if (command == "REDO") {
            requireGame().redoScore();
        } else if (command == "SUGGEST") {
            Game& table = requireGame();
            table.rolledCheck();
            const Player& player = table.players[table.turn->player];
            Candidates scores = candidates(player, faceCounts(table.turn->dice), rules.joker);
            std::string line = "suggest";
            for (int i = 0; i < CategoryCount; ++i) {
                if (!player.boxes[i].has_value()) line += " " + categoryNames[i] + " " + std::to_string(scores.points[i]);
            }
            emit(line, "best", categoryNames[scores.best], scores.points[scores.best]);
        } else if (command == "ADVISE") {
            Game& table = requireGame();
            table.rollsLeftCheck();
            const Turn& turn = *table.turn;
            Advice best = advise(table.players[turn.player], turn.dice, rules.rolls - turn.rolls, rules.joker, rerolls);
            emit("advise", patternText(best.holds) + ":", facesText(turn.dice, best.holds), "expect", fraction(best.numerator, best.denominator));
        } else if (command == "AUTO") {
            int count = static_cast<int>(integerWord(words[1], 1, 100));
            Game& table = requireGame();
            table.turnCheck();
            table.redo.clear();
            for (int i = 0; i < count && table.turn.has_value(); ++i) table.botTurn();
        } else if (command == "STATUS") {
            const Game& table = requireGame();
            if (!table.turn.has_value()) emit("status game over");
            else {
                const Turn& turn = *table.turn;
                const Player& player = table.players[turn.player];
                emit("status round", player.round(), "player", player.name, "rolls", turn.rolls,
                     "dice", turn.rolls == 0 ? "-" : facesText(turn.dice), "holds", patternText(turn.holds));
            }
        } else if (command == "CARD") {
            card(requireGame());
        } else if (command == "BONUS") {
            const Game& table = requireGame();
            for (const Player& player : table.players) {
                int upper = player.upper(), maximum = upper;
                for (int i = Ones; i <= Sixes; ++i) if (!player.boxes[i].has_value()) maximum += 5 * (i + 1);
                emit("bonus", player.name, "upper", upper, "need", std::max(63 - upper, 0), "max", maximum,
                     upper >= 63 ? "made" : maximum < 63 ? "lost" : "open");
            }
        } else if (command == "STATS") {
            statistics(requireGame());
        } else if (command == "LOG") {
            const Game& table = requireGame();
            if (table.entries.empty()) emit("no scores");
            for (std::size_t i = 0; i < table.entries.size(); ++i) {
                const ScoreEntry& entry = table.entries[i];
                std::string suffix;
                if (entry.joker) suffix += " joker";
                if (entry.yahtzeeBonus != 0) suffix += " ybonus 100";
                emit("log", i + 1, table.players[entry.turn.player].name, facesText(entry.turn.dice),
                     categoryNames[entry.category], std::to_string(entry.points) + suffix);
            }
        } else if (command == "FACES") {
            const Game& table = requireGame();
            Integer total = 0, squares = 0;
            std::string line = "faces";
            for (Integer count : table.faceTotals) { total += count; squares += count * count; line += " " + std::to_string(count); }
            emit(line, "total", total, "chi2", total == 0 ? "0" : fraction(6 * squares - total * total, total));
        } else if (command == "STANDINGS" || command == "END") {
            const Game& table = requireGame();
            std::vector<int> ranking = table.ranking();
            bool finished = !table.turn.has_value();
            if (command == "END") emit("end", finished ? "final" : "abandoned");
            int best = table.players[ranking[0]].total();
            for (std::size_t rank = 0; rank < ranking.size(); ++rank) {
                const Player& player = table.players[ranking[rank]];
                if (command == "STANDINGS") emit("standing", rank + 1, player.name, player.total(), "behind", best - player.total());
                else {
                    emit("rank", rank + 1, player.name, player.total());
                    if (finished) {
                        Record& record = records[player.name];
                        ++record.games;
                        record.wins += rank == 0;
                        record.sum += player.total();
                        record.best = std::max(record.best, player.total());
                    }
                }
            }
            if (command == "END") game.reset();
        } else if (command == "RECORDS") {
            std::vector<std::string> names;
            for (const auto& [name, record] : records) names.push_back(name);
            std::sort(names.begin(), names.end(), [&](const std::string& a, const std::string& b) {
                const Record& first = records.at(a);
                const Record& second = records.at(b);
                if (first.wins != second.wins) return first.wins > second.wins;
                if (first.best != second.best) return first.best > second.best;
                return a < b;
            });
            if (names.empty()) emit("no records");
            for (const std::string& name : names) {
                const Record& record = records.at(name);
                emit("record", name, "games", record.games, "wins", record.wins, "best", record.best, "average", average(record.sum, record.games));
            }
        } else if (command == "SIM") {
            Integer seed = integerWord(words[1], 1, 2147483646);
            int count = static_cast<int>(integerWord(words[2], 1, 50));
            std::vector<Strategy> strategies;
            for (std::size_t i = 3; i < words.size(); ++i) strategies.push_back(strategyWord(words[i]));
            if (strategies.size() > 6) throw CommandError("too many players");
            simulate(seed, count, strategies);
        } else {
            throw CommandError("unknown command " + command);
        }
    }

public:
    void process(const std::string& line) {
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        try { execute(words); }
        catch (const CommandError& error) { emit("error:", error.what()); }
    }
    void print() const { for (const std::string& line : output) std::cout << line << '\n'; }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Program program;
    for (int i = 0; i < count; ++i) { std::getline(std::cin, line); program.process(line); }
    program.print();
}
