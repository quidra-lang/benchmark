#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using std::array;
using std::string;
using std::vector;
using Integer = std::int64_t;

const array<string, 5> shipNames{"CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER"};
const array<int, 5> shipLengths{5, 4, 3, 3, 2};
const array<char, 5> symbols{'C', 'B', 'R', 'S', 'D'};
const array<string, 4> strategyNames{"HUNT", "PROB", "RANDOM", "HUMAN"};
enum class Strategy { Hunt, Prob, Random, Human };
enum class Phase { Setup, Battle, Over };
enum class View { Reef, Unattacked, Miss, Hit, Sunk };
enum class OutputMode { Normal, Match, Quiet };

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const string& message) { throw CommandError(message); }
Integer advance(Integer state) { return 48271 * state % 2147483647; }
string coordinate(int cell) { return string(1, static_cast<char>('A' + cell / 10)) + std::to_string(cell % 10 + 1); }
int parseCell(const string& word) { return (word[0] - 'A') * 10 + std::stoi(word.substr(1)) - 1; }
string shipRange(const vector<int>& cells) { return coordinate(cells.front()) + "-" + coordinate(cells.back()); }
string switchName(bool value) { return value ? "ON" : "OFF"; }
Strategy parseStrategy(const string& word) {
    return static_cast<Strategy>(std::find(strategyNames.begin(), strategyNames.end(), word) - strategyNames.begin());
}
int shipIndex(const string& word) { return static_cast<int>(std::find(shipNames.begin(), shipNames.end(), word) - shipNames.begin()); }

int step(int cell, int dr, int dc) {
    const int row = cell / 10 + dr, column = cell % 10 + dc;
    return row >= 0 && row < 10 && column >= 0 && column < 10 ? row * 10 + column : -1;
}

bool touching(int a, int b) { return std::abs(a / 10 - b / 10) <= 1 && std::abs(a % 10 - b % 10) <= 1; }

vector<int> footprint(int start, char direction, int length) {
    if ((direction == 'H' ? start % 10 : start / 10) + length > 10) return {};
    vector<int> cells;
    for (int i = 0; i < length; ++i) cells.push_back(start + i * (direction == 'H' ? 1 : 10));
    return cells;
}

struct Player {
    array<vector<int>, 5> fleet;
    array<bool, 100> attacked{};
    vector<int> candidates;
    Integer random, wins;
    Strategy controller = Strategy::Human;
    bool torpedo = false, sonar = false;
    Integer shots = 0, hits = 0, sinks = 0, turns = 0, streak = 0, bestStreak = 0;

    explicit Player(Integer seed = 1, Integer wins = 0) : random(seed), wins(wins) {}
    int shipAt(int cell) const {
        for (int ship = 0; ship < 5; ++ship) {
            if (std::find(fleet[ship].begin(), fleet[ship].end(), cell) != fleet[ship].end()) return ship;
        }
        return -1;
    }
    bool sunk(int ship) const {
        return !fleet[ship].empty() && std::all_of(fleet[ship].begin(), fleet[ship].end(), [&](int cell) { return attacked[cell]; });
    }
    int placed() const {
        return static_cast<int>(std::count_if(fleet.begin(), fleet.end(), [](const vector<int>& cells) { return !cells.empty(); }));
    }
    int afloat() const {
        int count = 0;
        for (int ship = 0; ship < 5; ++ship) if (!fleet[ship].empty() && !sunk(ship)) ++count;
        return count;
    }
    bool defeated() const {
        for (int ship = 0; ship < 5; ++ship) if (!sunk(ship)) return false;
        return true;
    }
};

struct Choice { int cell; string info; };
struct Shot { string text = "ALREADY"; bool hit = false; int sunk = -1; };

struct Game {
    Phase phase = Phase::Setup;
    int current = 0, winner = -1;
    bool salvo = false, chain = false, touch = false;
    array<bool, 100> reefs{};
    array<Player, 2> players;

    explicit Game(array<Integer, 2> wins = {0, 0}) : players{Player(1, wins[0]), Player(2, wins[1])} {}

    std::optional<string> placementProblem(const Player& player, const vector<int>& cells) const {
        if (cells.empty()) return "out of bounds";
        for (int cell : cells) if (reefs[cell]) return "on reef";
        for (int ship = 0; ship < 5; ++ship) {
            for (int cell : cells) {
                if (std::find(player.fleet[ship].begin(), player.fleet[ship].end(), cell) != player.fleet[ship].end()) return "overlaps " + shipNames[ship];
            }
        }
        if (!touch) {
            for (int ship = 0; ship < 5; ++ship) {
                for (int cell : cells) {
                    for (int other : player.fleet[ship]) if (touching(cell, other)) return "touches " + shipNames[ship];
                }
            }
        }
        return std::nullopt;
    }

    vector<string> placementOutput(int p) const {
        vector<string> output;
        for (int ship = 0; ship < 5; ++ship) output.push_back("PLACED " + std::to_string(p + 1) + " " + shipNames[ship] + " " + shipRange(players[p].fleet[ship]));
        return output;
    }

    Integer autoPlace(int p, Integer seed) {
        Player& player = players[p];
        player.random = seed;
        for (vector<int>& cells : player.fleet) cells.clear();
        Integer attempts = 0;
        for (int ship = 0; ship < 5; ++ship) {
            while (player.fleet[ship].empty()) {
                ++attempts;
                player.random = advance(player.random);
                const char direction = player.random % 2 == 0 ? 'H' : 'V';
                player.random = advance(player.random);
                const int span = 11 - shipLengths[ship];
                const int index = static_cast<int>(player.random % (10 * span));
                const int start = direction == 'H' ? index / span * 10 + index % span : index;
                vector<int> cells = footprint(start, direction, shipLengths[ship]);
                if (!placementProblem(player, cells)) player.fleet[ship] = std::move(cells);
            }
        }
        return attempts;
    }

    array<View, 100> view(int p) const {
        const Player& opponent = players[1 - p];
        array<View, 100> result{};
        for (int cell = 0; cell < 100; ++cell) {
            if (reefs[cell]) result[cell] = View::Reef;
            else if (!opponent.attacked[cell]) result[cell] = View::Unattacked;
            else {
                const int ship = opponent.shipAt(cell);
                result[cell] = ship == -1 ? View::Miss : opponent.sunk(ship) ? View::Sunk : View::Hit;
            }
        }
        return result;
    }

    array<bool, 100> excluded(const array<View, 100>& view) const {
        array<bool, 100> result{};
        if (touch) return result;
        for (int cell = 0; cell < 100; ++cell) {
            if (view[cell] != View::Sunk) continue;
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    const int next = step(cell, dr, dc);
                    if (next != -1) result[next] = true;
                }
            }
        }
        return result;
    }

    array<int, 100> density(int p, const array<View, 100>& view, const array<bool, 100>& excluded) const {
        array<int, 100> scores{};
        for (int ship = 0; ship < 5; ++ship) {
            if (players[1 - p].sunk(ship)) continue;
            for (int start = 0; start < 100; ++start) {
                for (char direction : {'H', 'V'}) {
                    const vector<int> cells = footprint(start, direction, shipLengths[ship]);
                    if (cells.empty()) continue;
                    bool possible = true;
                    int hits = 0;
                    for (int cell : cells) {
                        if (excluded[cell] || (view[cell] != View::Unattacked && view[cell] != View::Hit)) possible = false;
                        hits += view[cell] == View::Hit;
                    }
                    if (possible) for (int cell : cells) scores[cell] += 1 + 10 * hits;
                }
            }
        }
        return scores;
    }

    Choice choose(int p, Strategy strategy, bool mutate = true) {
        Player& player = players[p];
        const array<View, 100> cells = view(p);
        const array<bool, 100> blocked = excluded(cells);
        const auto candidate = [&](int cell) { return cell >= 0 && cell < 100 && cells[cell] == View::Unattacked && !blocked[cell]; };
        if (strategy == Strategy::Prob) {
            const array<int, 100> scores = density(p, cells, blocked);
            int chosen = -1;
            for (int cell = 0; cell < 100; ++cell) {
                if (cells[cell] == View::Unattacked && (chosen == -1 || scores[cell] > scores[chosen])) chosen = cell;
            }
            return {chosen, std::to_string(scores[chosen])};
        }
        if (strategy == Strategy::Random) {
            vector<int> choices;
            for (int cell = 0; cell < 100; ++cell) if (candidate(cell)) choices.push_back(cell);
            const Integer random = advance(player.random);
            if (mutate) player.random = random;
            return {choices[static_cast<std::size_t>(random) % choices.size()], std::to_string(choices.size())};
        }
        const array<std::pair<int, int>, 2> directions{{{0, 1}, {1, 0}}};
        for (int cell = 0; cell < 100; ++cell) {
            if (cells[cell] != View::Hit) continue;
            for (const auto& [dr, dc] : directions) {
                const int neighbor = step(cell, dr, dc);
                if (neighbor == -1 || cells[neighbor] != View::Hit) continue;
                int front = neighbor;
                while (front != -1 && cells[front] == View::Hit) front = step(front, dr, dc);
                const int back = step(cell, -dr, -dc);
                if (candidate(front)) return {front, "LINE"};
                if (candidate(back)) return {back, "LINE"};
            }
        }
        for (auto i = player.candidates.rbegin(); i != player.candidates.rend(); ++i) {
            if (candidate(*i)) return {*i, "STACK"};
        }
        int shortest = 10;
        for (int ship = 0; ship < 5; ++ship) if (!players[1 - p].sunk(ship)) shortest = std::min(shortest, shipLengths[ship]);
        for (int cell = 0; cell < 100; ++cell) {
            if (candidate(cell) && (cell / 10 + cell % 10) % shortest == 0) return {cell, "PARITY"};
        }
        throw std::logic_error("No strategy candidate");
    }

    Shot shoot(int p, int cell) {
        Player& player = players[p];
        Player& opponent = players[1 - p];
        Shot result;
        if (!opponent.attacked[cell]) {
            opponent.attacked[cell] = true;
            const int ship = opponent.shipAt(cell);
            if (ship == -1) result.text = "MISS";
            else {
                result.hit = true;
                if (opponent.sunk(ship)) {
                    result.text = "SUNK " + shipNames[ship];
                    result.sunk = ship;
                } else {
                    result.text = "HIT";
                    const array<std::pair<int, int>, 4> directions{{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}};
                    for (const auto& [dr, dc] : directions) {
                        const int next = step(cell, dr, dc);
                        if (next != -1) player.candidates.push_back(next);
                    }
                }
            }
        }
        ++player.shots;
        if (result.hit) {
            ++player.hits;
            ++player.streak;
            player.bestStreak = std::max(player.bestStreak, player.streak);
        } else player.streak = 0;
        if (result.sunk != -1) ++player.sinks;
        return result;
    }

    int allowance(int p) const { return salvo ? players[p].afloat() : 1; }

    void finishTurn(int p, bool hit, vector<string>& output, OutputMode mode) {
        ++players[p].turns;
        if (players[1 - p].defeated()) {
            phase = Phase::Over;
            winner = p;
            ++players[p].wins;
            if (mode == OutputMode::Normal) output.push_back("WINNER " + std::to_string(p + 1));
        } else current = chain && hit ? p : 1 - p;
    }

    void shootingTurn(int p, std::optional<Strategy> strategy, const vector<int>& cells, vector<string>& output, OutputMode mode = OutputMode::Normal) {
        phase = Phase::Battle;
        const int count = allowance(p);
        bool hit = false;
        for (int i = 0; i < count; ++i) {
            const int cell = strategy ? choose(p, *strategy).cell : cells[i];
            const Shot result = shoot(p, cell);
            hit = hit || result.hit;
            if (mode == OutputMode::Normal) output.push_back("SHOT " + std::to_string(p + 1) + " " + coordinate(cell) + " " + result.text);
            if (mode == OutputMode::Match && result.sunk != -1) output.push_back("SINK " + std::to_string(p + 1) + " " + shipNames[result.sunk] + " " + std::to_string(players[p].shots));
            if (players[1 - p].defeated()) break;
        }
        finishTurn(p, hit, output, mode);
    }

    void checkTurn(int p) const {
        if (phase == Phase::Over) fail("game over");
        if (phase == Phase::Setup && (players[0].placed() != 5 || players[1].placed() != 5)) fail("fleets not ready");
        if (p != current) fail("not your turn");
    }

    void specialTurn(int p, const string& command, const vector<string>& args, vector<string>& output) {
        phase = Phase::Battle;
        Player& player = players[p];
        Player& opponent = players[1 - p];
        bool hit = false;
        if (command == "SONAR") {
            player.sonar = true;
            const int center = parseCell(args[0]);
            int count = 0;
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    const int cell = step(center, dr, dc);
                    if (cell != -1 && !opponent.attacked[cell] && opponent.shipAt(cell) != -1) ++count;
                }
            }
            output.push_back("SONAR " + std::to_string(p + 1) + " " + args[0] + " " + std::to_string(count));
        } else {
            player.torpedo = true;
            const int row = args[0][0] - 'A';
            string result = "MISS";
            bool shotAtShip = false;
            for (int index = 0; index < 10; ++index) {
                const int cell = row * 10 + (args[1] == "W" ? index : 9 - index);
                if (reefs[cell]) {
                    result = "REEF " + coordinate(cell);
                    break;
                }
                if (opponent.shipAt(cell) != -1) {
                    const Shot shot = shoot(p, cell);
                    result = shot.text + " " + coordinate(cell);
                    hit = shot.hit;
                    shotAtShip = true;
                    break;
                }
                opponent.attacked[cell] = true;
            }
            if (!shotAtShip) { ++player.shots; player.streak = 0; }
            output.push_back("TORPEDO " + std::to_string(p + 1) + " " + args[0] + " " + args[1] + " " + result);
        }
        finishTurn(p, hit, output, OutputMode::Normal);
    }

    void automatic(vector<string>& output) {
        while (phase == Phase::Battle && players[current].controller != Strategy::Human) {
            const int p = current;
            shootingTurn(p, players[p].controller, {}, output);
        }
    }

    Game match(Integer seed1, Integer seed2, Strategy first, Strategy second, vector<string>* output = nullptr) const {
        Game game;
        game.salvo = salvo; game.chain = chain; game.touch = touch; game.reefs = reefs;
        game.autoPlace(0, seed1);
        game.autoPlace(1, seed2);
        game.phase = Phase::Battle;
        const array<Strategy, 2> choices{first, second};
        vector<string> discarded;
        vector<string>& lines = output ? *output : discarded;
        while (game.phase != Phase::Over) game.shootingTurn(game.current, choices[game.current], {}, lines, output ? OutputMode::Match : OutputMode::Quiet);
        return game;
    }

    vector<string> layout(int p, const string& text) {
        string grid;
        for (char character : text) if (character != '/') grid += character;
        array<vector<int>, 5> fleet;
        for (int ship = 0; ship < 5; ++ship) {
            for (int cell = 0; cell < 100; ++cell) if (grid[cell] == symbols[ship]) fleet[ship].push_back(cell);
            const vector<int>& cells = fleet[ship];
            if (cells.size() != static_cast<std::size_t>(shipLengths[ship])) fail(shipNames[ship] + " has " + std::to_string(cells.size()) + " cells");
            bool horizontal = true, vertical = true;
            for (int index = 0; index < shipLengths[ship]; ++index) {
                horizontal = horizontal && cells[index] == cells[0] + index && cells[index] / 10 == cells[0] / 10;
                vertical = vertical && cells[index] == cells[0] + 10 * index;
            }
            if (!horizontal && !vertical) fail(shipNames[ship] + " not straight");
            for (int cell : cells) if (reefs[cell]) fail(shipNames[ship] + " on reef");
        }
        if (!touch) {
            for (int first = 0; first < 5; ++first) {
                for (int second = first + 1; second < 5; ++second) {
                    for (int cell : fleet[first]) {
                        for (int other : fleet[second]) if (touching(cell, other)) fail(shipNames[first] + " touches " + shipNames[second]);
                    }
                }
            }
        }
        players[p].fleet = std::move(fleet);
        vector<string> output = placementOutput(p);
        output.insert(output.begin(), "LAYOUT " + std::to_string(p + 1));
        return output;
    }

    vector<string> boardOutput(int p, bool radar) const {
        const Player& player = players[p];
        const array<View, 100> opponentView = view(p);
        const array<char, 5> viewSymbols{'~', '.', 'o', 'x', '#'};
        vector<string> output{string(radar ? "RADAR " : "BOARD ") + std::to_string(p + 1), "  1 2 3 4 5 6 7 8 9 10"};
        for (int row = 0; row < 10; ++row) {
            string text(1, static_cast<char>('A' + row));
            for (int column = 0; column < 10; ++column) {
                const int cell = row * 10 + column;
                char symbol;
                if (radar) symbol = viewSymbols[static_cast<std::size_t>(opponentView[cell])];
                else if (reefs[cell]) symbol = '~';
                else {
                    const int ship = player.shipAt(cell);
                    if (ship == -1) symbol = player.attacked[cell] ? 'o' : '.';
                    else symbol = player.attacked[cell] ? static_cast<char>(std::tolower(symbols[ship])) : symbols[ship];
                }
                text += ' ';
                text += symbol;
            }
            output.push_back(text);
        }
        return output;
    }

    vector<string> densityOutput(int p) const {
        const array<View, 100> cells = view(p);
        const array<int, 100> scores = density(p, cells, excluded(cells));
        vector<string> output{"DENSITY " + std::to_string(p + 1)};
        std::ostringstream header;
        header << ' ';
        for (int column = 1; column <= 10; ++column) header << std::setw(5) << column;
        output.push_back(header.str());
        int best = -1;
        for (int row = 0; row < 10; ++row) {
            std::ostringstream text;
            text << static_cast<char>('A' + row);
            for (int column = 0; column < 10; ++column) {
                const int cell = row * 10 + column;
                const string value = cells[cell] == View::Unattacked ? std::to_string(scores[cell]) : cells[cell] == View::Reef ? "~" : "-";
                text << std::setw(5) << value;
                if (cells[cell] == View::Unattacked && (best == -1 || scores[cell] > scores[best])) best = cell;
            }
            output.push_back(text.str());
        }
        output.push_back("BEST " + coordinate(best) + " " + std::to_string(scores[best]));
        return output;
    }

    string exportFleet(int p) const {
        string grid(100, '.');
        for (int ship = 0; ship < 5; ++ship) for (int cell : players[p].fleet[ship]) grid[cell] = symbols[ship];
        string output;
        for (int row = 0; row < 10; ++row) {
            if (row != 0) output += '/';
            output += grid.substr(row * 10, 10);
        }
        return output;
    }

    vector<string> fleetOutput(int p) const {
        const Player& player = players[p];
        vector<string> output{"FLEET " + std::to_string(p + 1) + " afloat " + std::to_string(player.afloat())};
        for (int ship = 0; ship < 5; ++ship) {
            const vector<int>& cells = player.fleet[ship];
            if (cells.empty()) output.push_back(shipNames[ship] + " unplaced");
            else {
                const int attacked = static_cast<int>(std::count_if(cells.begin(), cells.end(), [&](int cell) { return player.attacked[cell]; }));
                output.push_back(shipNames[ship] + " " + shipRange(cells) + " " + std::to_string(attacked) + "/" + std::to_string(shipLengths[ship]) + (player.sunk(ship) ? " SUNK" : " AFLOAT"));
            }
        }
        return output;
    }

    string status() const {
        std::ostringstream output;
        output << "STATUS " << (phase == Phase::Setup ? "SETUP" : phase == Phase::Battle ? "BATTLE" : "OVER")
               << " salvo " << switchName(salvo) << " chain " << switchName(chain) << " touch " << switchName(touch)
               << " reefs " << std::count(reefs.begin(), reefs.end(), true);
        if (phase == Phase::Setup) output << " placed " << players[0].placed() << ' ' << players[1].placed();
        else {
            if (phase == Phase::Battle) output << " turn " << current + 1 << " shots " << allowance(current);
            else output << " winner " << winner + 1;
            output << " afloat " << players[0].afloat() << ' ' << players[1].afloat();
        }
        return output.str();
    }

    vector<string> statistics() const {
        vector<string> output;
        for (int p = 0; p < 2; ++p) {
            const Player& player = players[p];
            const string accuracy = player.shots == 0 ? "-" : std::to_string(player.hits * 100 / player.shots) + "%";
            std::ostringstream line;
            line << "STATS " << p + 1 << " shots " << player.shots << " hits " << player.hits << " sunk " << player.sinks
                 << " turns " << player.turns << " streak " << player.bestStreak << " accuracy " << accuracy << " wins " << player.wins;
            output.push_back(line.str());
        }
        return output;
    }
};

const std::set<string> setupCommands{"PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH"};
const std::set<string> turnCommands{"FIRE", "AI", "TORPEDO", "SONAR"};

struct Program {
    Game game;

    vector<string> execute(const vector<string>& words) {
        const string& command = words[0];
        if (command == "NEW") {
            game = Game({game.players[0].wins, game.players[1].wins});
            return {"NEW"};
        }
        if (setupCommands.count(command)) {
            if (game.phase != Phase::Setup) fail("setup closed");
            if (command == "SALVO" || command == "CHAIN" || command == "TOUCH") {
                const bool enabled = words[1] == "ON";
                if (command == "SALVO") game.salvo = enabled;
                else if (command == "CHAIN") game.chain = enabled;
                else game.touch = enabled;
                return {command + " " + words[1]};
            }
            if (command == "REEF") {
                const int cell = parseCell(words[1]);
                if (game.reefs[cell]) fail("reef exists at " + coordinate(cell));
                for (int owner = 0; owner < 2; ++owner) {
                    const int ship = game.players[owner].shipAt(cell);
                    if (ship != -1) fail(coordinate(cell) + " occupied by " + std::to_string(owner + 1) + " " + shipNames[ship]);
                }
                game.reefs[cell] = true;
                return {"REEF " + coordinate(cell)};
            }
            const int p = std::stoi(words[1]) - 1;
            if (command == "PLACE" || command == "REMOVE") {
                Player& player = game.players[p];
                const int ship = shipIndex(words[2]);
                if (command == "REMOVE") {
                    if (player.fleet[ship].empty()) fail(shipNames[ship] + " not placed");
                    player.fleet[ship].clear();
                    return {"REMOVED " + std::to_string(p + 1) + " " + shipNames[ship]};
                }
                if (!player.fleet[ship].empty()) fail(shipNames[ship] + " already placed");
                vector<int> cells = footprint(parseCell(words[3]), words[4][0], shipLengths[ship]);
                const std::optional<string> problem = game.placementProblem(player, cells);
                if (problem) fail(*problem);
                player.fleet[ship] = std::move(cells);
                return {"PLACED " + std::to_string(p + 1) + " " + shipNames[ship] + " " + shipRange(player.fleet[ship])};
            }
            if (command == "AUTOPLACE") {
                const Integer attempts = game.autoPlace(p, std::stoll(words[2]));
                vector<string> output = game.placementOutput(p);
                output.insert(output.begin(), "AUTOPLACE " + std::to_string(p + 1) + " attempts " + std::to_string(attempts));
                return output;
            }
            return game.layout(p, words[2]);
        }
        if (turnCommands.count(command)) {
            const int p = std::stoi(words[1]) - 1;
            game.checkTurn(p);
            vector<string> output;
            if (command == "FIRE") {
                const int allowance = game.allowance(p);
                if (words.size() - 2 != static_cast<std::size_t>(allowance)) fail("expected " + std::to_string(allowance) + " shots");
                vector<int> cells;
                for (std::size_t i = 2; i < words.size(); ++i) {
                    const int cell = parseCell(words[i]);
                    if (game.reefs[cell]) fail("reef at " + coordinate(cell));
                    cells.push_back(cell);
                }
                game.shootingTurn(p, std::nullopt, cells, output);
            } else if (command == "AI") game.shootingTurn(p, parseStrategy(words[2]), {}, output);
            else {
                if (command == "TORPEDO" && game.players[p].torpedo) fail("torpedo used");
                if (command == "SONAR" && game.players[p].sonar) fail("sonar used");
                game.specialTurn(p, command, vector<string>(words.begin() + 2, words.end()), output);
            }
            game.automatic(output);
            return output;
        }
        if (command == "STATUS") return {game.status()};
        if (command == "STATS") return game.statistics();
        if (command == "MATCH" || command == "SERIES" || command == "TOURNEY") return simulation(words);
        const int p = std::stoi(words[1]) - 1;
        if (command == "RESIGN") {
            if (game.phase != Phase::Battle) fail("not in battle");
            game.phase = Phase::Over;
            game.winner = 1 - p;
            ++game.players[1 - p].wins;
            return {"RESIGN " + std::to_string(p + 1), "WINNER " + std::to_string(2 - p)};
        }
        if (command == "CONTROL") {
            game.players[p].controller = parseStrategy(words[2]);
            return {"CONTROL " + std::to_string(p + 1) + " " + words[2]};
        }
        if (command == "SEED") {
            game.players[p].random = std::stoll(words[2]);
            return {"SEED " + std::to_string(p + 1) + " " + std::to_string(game.players[p].random)};
        }
        if (command == "HINT") {
            if (game.phase == Phase::Over) fail("game over");
            const Choice choice = game.choose(p, parseStrategy(words[2]), false);
            return {"HINT " + std::to_string(p + 1) + " " + words[2] + " " + coordinate(choice.cell) + " " + choice.info};
        }
        if (command == "DENSITY") {
            if (game.phase == Phase::Over) fail("game over");
            return game.densityOutput(p);
        }
        if (command == "SHOW" || command == "RADAR") return game.boardOutput(p, command == "RADAR");
        if (command == "EXPORT") return {"EXPORT " + std::to_string(p + 1) + " " + game.exportFleet(p)};
        if (command == "FLEET") return game.fleetOutput(p);
        throw std::logic_error("Unknown command");
    }

    vector<string> simulation(const vector<string>& words) const {
        const string& command = words[0];
        if (command == "MATCH") {
            vector<string> output{"MATCH 1 " + words[3] + " 2 " + words[4]};
            const Game match = game.match(std::stoll(words[1]), std::stoll(words[2]), parseStrategy(words[3]), parseStrategy(words[4]), &output);
            std::ostringstream result;
            result << "RESULT winner " << match.winner + 1 << " shots " << match.players[0].shots << ' ' << match.players[1].shots
                   << " hits " << match.players[0].hits << ' ' << match.players[1].hits;
            output.push_back(result.str());
            return output;
        }
        const int count = std::stoi(words[1]);
        Integer random = std::stoll(words[2]);
        if (command == "SERIES") {
            array<Integer, 2> wins{}, shots{};
            array<std::optional<Integer>, 2> fastest{};
            for (int i = 0; i < count; ++i) {
                random = advance(random);
                const Integer first = random;
                random = advance(random);
                const Game match = game.match(first, random, parseStrategy(words[3]), parseStrategy(words[4]));
                ++wins[match.winner];
                for (int seat = 0; seat < 2; ++seat) shots[seat] += match.players[seat].shots;
                const Integer wonShots = match.players[match.winner].shots;
                fastest[match.winner] = std::min(fastest[match.winner].value_or(wonShots), wonShots);
            }
            std::ostringstream output;
            output << "SERIES " << count << " wins " << wins[0] << ' ' << wins[1] << " shots " << shots[0] << ' ' << shots[1]
                   << " fastest " << (fastest[0] ? std::to_string(*fastest[0]) : "-") << ' ' << (fastest[1] ? std::to_string(*fastest[1]) : "-");
            return {output.str()};
        }
        struct Total { int strategy; Integer wins = 0, shots = 0; };
        array<Total, 3> totals{{{0}, {1}, {2}}};
        for (int first = 0; first < 3; ++first) {
            for (int second = 0; second < 3; ++second) {
                if (first == second) continue;
                for (int i = 0; i < count; ++i) {
                    random = advance(random);
                    const Integer seed1 = random;
                    random = advance(random);
                    const Game match = game.match(seed1, random, static_cast<Strategy>(first), static_cast<Strategy>(second));
                    ++totals[match.winner == 0 ? first : second].wins;
                    totals[first].shots += match.players[0].shots;
                    totals[second].shots += match.players[1].shots;
                }
            }
        }
        std::sort(totals.begin(), totals.end(), [](const Total& a, const Total& b) {
            if (a.wins != b.wins) return a.wins > b.wins;
            if (a.shots != b.shots) return a.shots < b.shots;
            return a.strategy < b.strategy;
        });
        vector<string> output{"TOURNEY " + std::to_string(count)};
        for (int rank = 0; rank < 3; ++rank) {
            const Total& total = totals[rank];
            output.push_back(std::to_string(rank + 1) + " " + strategyNames[total.strategy] + " wins " + std::to_string(total.wins) + " shots " + std::to_string(total.shots));
        }
        return output;
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    string line;
    std::getline(std::cin, line);
    const int count = std::stoi(line);
    Program program;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        std::istringstream input(line);
        vector<string> words;
        string word;
        while (input >> word) words.push_back(word);
        try {
            for (const string& output : program.execute(words)) std::cout << output << '\n';
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
        std::cout.flush();
    }
}
