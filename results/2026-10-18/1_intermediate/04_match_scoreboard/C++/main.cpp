#include <algorithm>
#include <array>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

using std::string;
using std::vector;
using Pair = std::array<int, 2>;
enum Sport { Tennis, TableTennis, Badminton, Volleyball, Bowling, Darts };
struct Segment { int a = 0, b = 0, kind = 0, loser = 0; };
struct Rally {
    Pair points{}, games{}, sets{}, substitutions{}, timeouts{};
    std::array<std::array<int, 10>, 2> stats{};
    std::array<std::array<int, 6>, 2> lineup{};
    std::array<Segment, 7> segments{};
    int segmentCount = 0, server = 0, winner = -1;
};
struct BowlingState { std::array<int, 21> rolls{}; int count = 0; };
struct DartsState {
    Pair remaining{}, legs{}, sets{};
    std::array<std::array<int, 8>, 2> stats{};
    std::array<Pair, 9> segments{};
    std::array<int, 3> turn{};
    int segmentCount = 0, server = 0, turnStart = 0, turnCount = 0, turnScore = 0, legNumber = 1, winner = -1;
};
using State = std::variant<Rally, BowlingState, DartsState>;
struct Match {
    string id;
    std::array<string, 2> names;
    Sport sport;
    int first = 0, sets = 3, games = 5, final = 0, start = 501, legs = 1;
    bool noAd = false;
    std::array<std::array<int, 6>, 2> initialLineup{};
    State state;
    vector<State> history;
};
struct BowlingInfo {
    std::array<int, 10> start{}, count{}, score{};
    std::array<bool, 10> closed{}, final{};
    std::array<char, 21> marks{};
    int standing = 10, frame = 0;
    bool fresh = true, finished = false;
};
struct Dart { string name; int value; bool isDouble; };
vector<Dart> darts;
std::map<string, Match> matches;

[[noreturn]] void fail(const string &message) { throw std::runtime_error(message); }
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
string join(const vector<string> &items, const string &separator) {
    string result;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) result += separator;
        result += items[i];
    }
    return result;
}
template <typename... Values> string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
string pairText(const Pair &p, int first = 0) { return text(p[first], "-", p[1 - first]); }
void initializeDarts() {
    for (int multiplier = 1; multiplier <= 3; ++multiplier) {
        int value = multiplier == 2 ? 3 : multiplier == 3 ? 2 : 1;
        char prefix = value == 1 ? 'S' : value == 2 ? 'D' : 'T';
        for (int n = 20; n >= 1; --n) darts.push_back({text(prefix, n), value * n, value == 2});
    }
    darts.push_back({"25", 25, false});
    darts.push_back({"BULL", 50, true});
    darts.push_back({"MISS", 0, false});
}
int doubleDart(int value) {
    if (value == 50) return 61;
    if (value >= 2 && value <= 40 && value % 2 == 0) return 40 + 20 - value / 2;
    return -1;
}
vector<int> checkout(int score, int maximum) {
    int last = doubleDart(score);
    if (last >= 0) return {last};
    if (maximum >= 2) {
        for (int i = 0; i < 62; ++i) {
            last = doubleDart(score - darts[i].value);
            if (last >= 0) return {i, last};
        }
    }
    if (maximum >= 3 && score <= 170) {
        for (int i = 0; i < 62; ++i) {
            for (int j = 0; j < 62; ++j) {
                last = doubleDart(score - darts[i].value - darts[j].value);
                if (last >= 0) return {i, j, last};
            }
        }
    }
    return {};
}
string dartNames(const vector<int> &ids) {
    vector<string> result;
    for (int id : ids) result.push_back(darts[id].name);
    return join(result, " ");
}
BowlingInfo bowlingInfo(const BowlingState &state) {
    BowlingInfo info;
    for (int i = 0; i < state.count; ++i) {
        int frame = info.frame, pins = state.rolls[i];
        if (info.count[frame] == 0) info.start[frame] = i;
        info.marks[i] = info.fresh && pins == 10 ? 'X' : pins == info.standing ? '/' : pins == 0 ? '-' : char('0' + pins);
        ++info.count[frame];
        info.standing -= pins;
        info.fresh = false;
        bool ended = false;
        if (frame < 9) ended = pins == 10 && info.count[frame] == 1 || info.count[frame] == 2;
        else if (info.count[frame] == 2) ended = state.rolls[info.start[frame]] + pins < 10;
        else if (info.count[frame] == 3) ended = true;
        if (ended) {
            info.closed[frame] = true;
            if (frame == 9) info.finished = true;
            else ++info.frame;
            info.standing = 10;
            info.fresh = true;
        } else if (frame == 9 && info.standing == 0) {
            info.standing = 10;
            info.fresh = true;
        }
    }
    for (int frame = 0; frame < 10; ++frame) {
        if (!info.count[frame]) continue;
        int start = info.start[frame];
        if (frame == 9) {
            info.final[frame] = info.closed[frame];
            for (int j = 0; j < info.count[frame]; ++j) info.score[frame] += state.rolls[start + j];
        } else if (state.rolls[start] == 10) {
            info.final[frame] = state.count >= start + 3;
            if (info.final[frame]) info.score[frame] = 10 + state.rolls[start + 1] + state.rolls[start + 2];
        } else if (info.count[frame] >= 2) {
            int total = state.rolls[start] + state.rolls[start + 1];
            info.final[frame] = total < 10 || state.count >= start + 3;
            if (info.final[frame]) info.score[frame] = total + (total == 10 ? state.rolls[start + 2] : 0);
        }
    }
    return info;
}
int bowlingTotal(const BowlingInfo &info) {
    int total = 0;
    for (int score : info.score) total += score;
    return total;
}
bool finalSet(const Match &m, const Rally &s) { return s.sets[0] == m.sets / 2 && s.sets[1] == m.sets / 2; }
int tennisKind(const Match &m, const Rally &s) {
    if (finalSet(m, s) && m.final == 3) return 2;
    if (s.games[0] == 6 && s.games[1] == 6 && !(finalSet(m, s) && m.final == 2)) return 1;
    return 0;
}
int rallyServer(const Match &m, const Rally &s) {
    if (m.sport == Tennis && tennisKind(m, s)) return s.server ^ (((s.points[0] + s.points[1] + 1) / 2) % 2);
    if (m.sport == TableTennis) {
        int first = m.first ^ (s.segmentCount % 2), played = s.points[0] + s.points[1];
        return first ^ (played < 20 ? played / 2 % 2 : played % 2);
    }
    return s.server;
}
bool normalGame(const Match &m, int own, int other) { return own >= 4 && (m.noAd || own - other >= 2); }
void addRally(const Match &m, Rally &s, int side) {
    int other = 1 - side, server = rallyServer(m, s);
    ++s.stats[side][0];
    ++s.stats[server][1];
    if (side == server) ++s.stats[side][2];
    ++s.stats[side][3];
    s.stats[other][3] = 0;
    s.stats[side][4] = std::max(s.stats[side][4], s.stats[side][3]);
    int kind = m.sport == Tennis ? tennisKind(m, s) : 0;
    if (m.sport == Tennis && kind == 0) {
        int receiver = 1 - s.server;
        if (normalGame(m, s.points[receiver] + 1, s.points[s.server])) {
            ++s.stats[receiver][8];
            if (side == receiver) ++s.stats[receiver][9];
        }
    }
    ++s.points[side];
    if (m.sport == Tennis) {
        int target = kind == 2 || kind == 1 && finalSet(m, s) && m.final == 1 ? 10 : 7;
        bool ended = kind ? s.points[side] >= target && s.points[side] - s.points[other] >= 2 : normalGame(m, s.points[side], s.points[other]);
        if (!ended) return;
        Segment segment;
        if (!kind) {
            ++s.stats[s.server][5];
            if (side == s.server) ++s.stats[side][6];
            else ++s.stats[side][7];
        }
        if (kind == 2) segment = {s.points[0], s.points[1], 2, 0};
        else {
            ++s.games[side];
            segment = {s.games[0], s.games[1], kind, kind ? s.points[other] : 0};
        }
        s.server ^= 1;
        s.points = {};
        bool setEnded = kind != 0 || s.games[side] >= 6 && s.games[side] - s.games[other] >= 2;
        if (setEnded) {
            s.segments[s.segmentCount++] = segment;
            ++s.sets[side];
            s.games = {};
            if (s.sets[side] == m.sets / 2 + 1) s.winner = side;
        }
        return;
    }
    if (m.sport == Volleyball && side != s.server) {
        s.server = side;
        std::rotate(s.lineup[side].begin(), s.lineup[side].begin() + 1, s.lineup[side].end());
    }
    if (m.sport == Badminton) s.server = side;
    int target = m.sport == TableTennis ? 11 : m.sport == Badminton ? 21 : s.segmentCount == 4 ? 15 : 25;
    bool ended = s.points[side] >= target && s.points[side] - s.points[other] >= 2;
    if (m.sport == Badminton && s.points[side] == 30) ended = true;
    if (!ended) return;
    s.segments[s.segmentCount++] = {s.points[0], s.points[1], 0, 0};
    ++s.sets[side];
    int needed = m.sport == TableTennis ? m.games / 2 + 1 : m.sport == Badminton ? 2 : 3;
    if (s.sets[side] == needed) s.winner = side;
    else {
        s.points = {};
        if (m.sport == Volleyball) {
            s.lineup = m.initialLineup;
            s.substitutions = {};
            s.timeouts = {};
            s.server = m.first ^ (s.segmentCount % 2);
        }
    }
}
void endDartsTurn(DartsState &s) {
    s.server ^= 1;
    s.turnStart = s.remaining[s.server];
    s.turnCount = s.turnScore = 0;
}
void completedDartsTurn(DartsState &s, int side) {
    s.stats[side][3] = std::max(s.stats[side][3], s.turnScore);
    if (s.turnScore >= 100) ++s.stats[side][4];
    if (s.turnScore == 180) ++s.stats[side][5];
}
void addDart(const Match &m, DartsState &s, int id) {
    int side = s.server, remaining = s.remaining[side];
    const Dart &dart = darts[id];
    ++s.stats[side][0];
    if (remaining == 50 || remaining <= 40 && remaining % 2 == 0) ++s.stats[side][6];
    s.turn[s.turnCount++] = id;
    s.turnScore += dart.value;
    s.stats[side][1] += dart.value;
    int after = remaining - dart.value;
    if (after < 0 || after == 1 || after == 0 && !dart.isDouble) {
        s.stats[side][1] -= s.turnScore;
        ++s.stats[side][2];
        s.remaining[side] = s.turnStart;
        endDartsTurn(s);
        return;
    }
    s.remaining[side] = after;
    if (after == 0) {
        ++s.stats[side][7];
        completedDartsTurn(s, side);
        ++s.legs[side];
        if (s.legs[side] == m.legs) {
            s.segments[s.segmentCount++] = s.legs;
            ++s.sets[side];
            if (s.sets[side] == m.sets) {
                s.winner = side;
                return;
            }
            s.legs = {};
        }
        ++s.legNumber;
        s.remaining = {m.start, m.start};
        s.server = m.first ^ ((s.legNumber - 1) % 2);
        s.turnStart = m.start;
        s.turnCount = s.turnScore = 0;
    } else if (s.turnCount == 3) {
        completedDartsTurn(s, side);
        endDartsTurn(s);
    }
}
bool finished(const Match &m) {
    if (m.sport == Bowling) return bowlingInfo(std::get<BowlingState>(m.state)).finished;
    if (m.sport == Darts) return std::get<DartsState>(m.state).winner >= 0;
    return std::get<Rally>(m.state).winner >= 0;
}
int winner(const Match &m) { return m.sport == Darts ? std::get<DartsState>(m.state).winner : std::get<Rally>(m.state).winner; }
string segmentText(const Segment &s, int first = 0) {
    string result = pairText({s.a, s.b}, first);
    if (s.kind == 1) result += text("(", s.loser, ")");
    if (s.kind == 2) result = "[" + result + "]";
    return result;
}
string situation(const Match &m, const Rally &s, int side) {
    Rally next = s;
    addRally(m, next, side);
    if (next.winner >= 0) return "match point";
    if (next.segmentCount != s.segmentCount) return m.sport == TableTennis || m.sport == Badminton ? "game point" : "set point";
    if (m.sport == Tennis && tennisKind(m, s) == 0 && next.server != s.server) return rallyServer(m, s) == side ? "game point" : "break point";
    return "";
}
string score(const Match &m) {
    if (m.sport == Bowling) {
        const BowlingState &s = std::get<BowlingState>(m.state);
        BowlingInfo info = bowlingInfo(s);
        string result = m.id + ": " + m.names[0];
        int cumulative = 0;
        for (int frame = 0; frame < 10; ++frame) {
            if (!info.count[frame]) continue;
            string display;
            for (int j = 0; j < info.count[frame]; ++j) display += info.marks[info.start[frame] + j];
            cumulative += info.score[frame];
            if (info.final[frame]) display += text("(", cumulative, ")");
            result += " " + display;
        }
        return result;
    }
    int server = m.sport == Darts ? std::get<DartsState>(m.state).server : rallyServer(m, std::get<Rally>(m.state));
    bool over = finished(m);
    string result = m.id + ": " + m.names[0] + (!over && server == 0 ? "*" : "") + " vs " + m.names[1] + (!over && server == 1 ? "*" : "");
    if (m.sport == Darts) {
        const DartsState &s = std::get<DartsState>(m.state);
        result += " sets " + pairText(s.sets) + " legs " + pairText(s.legs) + " score " + pairText(s.remaining);
        if (!over) {
            if (s.turnCount) result += " turn " + dartNames(vector<int>(s.turn.begin(), s.turn.begin() + s.turnCount));
            vector<int> finish = checkout(s.remaining[s.server], 3 - s.turnCount);
            if (!finish.empty()) result += " checkout " + dartNames(finish);
        }
        return result;
    }
    const Rally &s = std::get<Rally>(m.state);
    for (int i = 0; i < s.segmentCount; ++i) result += " " + segmentText(s.segments[i]);
    if (!over) {
        if (m.sport == Tennis) {
            int kind = tennisKind(m, s);
            if (kind == 2) result += " [" + pairText(s.points) + "]";
            else {
                result += " " + pairText(s.games) + " ";
                if (kind) result += pairText(s.points);
                else if (!m.noAd && s.points[0] >= 3 && s.points[1] >= 3) result += s.points[0] == s.points[1] ? "40-40" : s.points[0] > s.points[1] ? "AD-40" : "40-AD";
                else {
                    const string names[] = {"0", "15", "30", "40"};
                    result += names[s.points[0]] + "-" + names[s.points[1]];
                }
            }
        } else {
            result += " " + pairText(s.points);
            if (m.sport == Volleyball) result += text(" server ", s.lineup[s.server][0]);
        }
        for (int side = 0; side < 2; ++side) {
            string label = situation(m, s, side);
            if (!label.empty()) result += " (" + label + " " + m.names[side] + ")";
        }
    }
    return result;
}
vector<string> statistics(const Match &m) {
    if (m.sport == Bowling) {
        BowlingState s = std::get<BowlingState>(m.state);
        BowlingInfo info = bowlingInfo(s);
        int strikes = 0, spares = 0, open = 0;
        for (int i = 0; i < s.count; ++i) {
            strikes += info.marks[i] == 'X';
            spares += info.marks[i] == '/';
        }
        for (int i = 0; i < 10; ++i) {
            int start = info.start[i];
            if (info.count[i] >= 2 && s.rolls[start] != 10 && s.rolls[start] + s.rolls[start + 1] < 10) ++open;
        }
        while (!info.finished) {
            s.rolls[s.count++] = info.standing;
            info = bowlingInfo(s);
        }
        return {text(m.id, " ", m.names[0], ": strikes ", strikes, " spares ", spares, " open ", open, " max ", bowlingTotal(info))};
    }
    vector<string> result;
    for (int side = 0; side < 2; ++side) {
        string line = m.id + " " + m.names[side] + ": ";
        if (m.sport == Darts) {
            const std::array<int, 8> &s = std::get<DartsState>(m.state).stats[side];
            int average = s[0] ? s[1] * 300 / s[0] : 0;
            line += text("darts ", s[0], " average ", average / 100, ".", average % 100 < 10 ? "0" : "", average % 100, " busts ", s[2], " high ", s[3], " tons ", s[4], " 180s ", s[5], " doubles ", s[7], "/", s[6]);
        } else {
            const Rally &r = std::get<Rally>(m.state);
            const std::array<int, 10> &s = r.stats[side];
            line += text("points ", s[0], " serve ", s[2], "/", s[1], " run ", s[4]);
            if (m.sport == Tennis) line += text(" holds ", s[6], "/", s[5], " breaks ", s[7], " break points ", s[9], "/", s[8]);
            if (m.sport == Volleyball) {
                vector<string> lineup;
                for (int number : r.lineup[side]) lineup.push_back(std::to_string(number));
                line += text(" subs ", r.substitutions[side], " timeouts ", r.timeouts[side], " lineup ", join(lineup, ","));
            }
        }
        result.push_back(line);
    }
    return result;
}
string result(const Match &m) {
    if (!finished(m)) fail("match not finished");
    if (m.sport == Bowling) return text(m.id, ": ", m.names[0], " ", bowlingTotal(bowlingInfo(std::get<BowlingState>(m.state))));
    int first = winner(m);
    string line = m.id + ": " + m.names[first] + " def. " + m.names[1 - first];
    if (m.sport == Darts) {
        const DartsState &s = std::get<DartsState>(m.state);
        for (int i = 0; i < s.segmentCount; ++i) line += " " + pairText(s.segments[i], first);
    } else {
        const Rally &s = std::get<Rally>(m.state);
        for (int i = 0; i < s.segmentCount; ++i) line += " " + segmentText(s.segments[i], first);
    }
    return line;
}
void createMatch(const vector<string> &a) {
    if (matches.count(a[1])) fail("duplicate match");
    Match m;
    m.id = a[1];
    const vector<string> sports = {"TENNIS", "TABLETENNIS", "BADMINTON", "VOLLEYBALL", "BOWLING", "DARTS"};
    m.sport = Sport(std::find(sports.begin(), sports.end(), a[2]) - sports.begin());
    m.names[0] = a[3];
    if (m.sport != Bowling) m.names[1] = a[4];
    if (m.sport == Darts) m.sets = 1;
    int optionStart = m.sport == Bowling ? 4 : m.sport == Volleyball ? 7 : 5;
    std::map<string, vector<string>> allowed;
    if (m.sport == Tennis) allowed = {{"SETS", {"3", "5"}}, {"DEUCE", {"AD", "NOAD"}}, {"FINAL", {"TB7", "TB10", "ADV", "SUPER"}}, {"FIRST", {"A", "B"}}};
    if (m.sport == TableTennis) allowed = {{"GAMES", {"5", "7"}}, {"FIRST", {"A", "B"}}};
    if (m.sport == Badminton || m.sport == Volleyball) allowed = {{"FIRST", {"A", "B"}}};
    if (m.sport == Darts) allowed = {{"START", {"301", "501", "701"}}, {"SETS", {"1", "2", "3", "4", "5"}}, {"LEGS", {"1", "2", "3", "4", "5"}}, {"FIRST", {"A", "B"}}};
    std::map<string, bool> seen;
    for (int i = optionStart; i < int(a.size()); ++i) {
        vector<string> option = split(a[i], '=');
        if (option.size() != 2 || !allowed.count(option[0]) || seen[option[0]]) fail("invalid option");
        const vector<string> &values = allowed[option[0]];
        if (std::find(values.begin(), values.end(), option[1]) == values.end()) fail("invalid option");
        seen[option[0]] = true;
        if (option[0] == "FIRST") m.first = option[1] == "B";
        if (option[0] == "SETS") m.sets = std::stoi(option[1]);
        if (option[0] == "GAMES") m.games = std::stoi(option[1]);
        if (option[0] == "START") m.start = std::stoi(option[1]);
        if (option[0] == "LEGS") m.legs = std::stoi(option[1]);
        if (option[0] == "DEUCE") m.noAd = option[1] == "NOAD";
        if (option[0] == "FINAL") m.final = int(std::find(values.begin(), values.end(), option[1]) - values.begin());
    }
    if (m.sport == Bowling) m.state = BowlingState{};
    else if (m.sport == Darts) {
        DartsState s;
        s.remaining = {m.start, m.start};
        s.server = m.first;
        s.turnStart = m.start;
        m.state = s;
    } else {
        Rally s;
        s.server = m.first;
        if (m.sport == Volleyball) {
            for (int side = 0; side < 2; ++side) {
                vector<string> numbers = split(a[5 + side], ',');
                for (int i = 0; i < 6; ++i) m.initialLineup[side][i] = std::stoi(numbers[i]);
            }
            s.lineup = m.initialLineup;
        }
        m.state = s;
    }
    matches.emplace(a[1], std::move(m));
}
vector<string> execute(const vector<string> &a) {
    const string &command = a[0];
    if (command == "MATCH") {
        createMatch(a);
        return {};
    }
    if (command == "CHECKOUT") {
        vector<int> finish = checkout(std::stoi(a[1]), 3);
        return {"checkout " + a[1] + ": " + (finish.empty() ? "none" : dartNames(finish))};
    }
    if (command == "STANDINGS") {
        std::map<string, Pair> totals;
        for (const std::pair<const string, Match> &entry : matches) {
            const Match &m = entry.second;
            if (m.sport == Bowling || !finished(m)) continue;
            int side = winner(m);
            ++totals[m.names[side]][0];
            ++totals[m.names[1 - side]][1];
        }
        struct Standing { string name; int wins, losses; };
        vector<Standing> rows;
        for (const std::pair<const string, Pair> &entry : totals) rows.push_back({entry.first, entry.second[0], entry.second[1]});
        std::sort(rows.begin(), rows.end(), [](const Standing &a, const Standing &b) {
            if (a.wins != b.wins) return a.wins > b.wins;
            if (a.losses != b.losses) return a.losses < b.losses;
            return a.name < b.name;
        });
        vector<string> displays;
        for (const Standing &row : rows) displays.push_back(text(row.name, " ", row.wins, "-", row.losses));
        return {"standings: " + (displays.empty() ? "none" : join(displays, ", "))};
    }
    std::map<string, Match>::iterator found = matches.find(a[1]);
    if (found == matches.end()) fail("unknown match");
    Match &m = found->second;
    if (command == "SCORE") return {score(m)};
    if (command == "STATS") return statistics(m);
    if (command == "RESULT") return {result(m)};
    if (command == "UNDO") {
        if (m.history.empty()) fail("nothing to undo");
        m.state = m.history.back();
        m.history.pop_back();
        return {};
    }
    bool allowed = command == "POINT" && m.sport <= Volleyball || command == "ROLL" && m.sport == Bowling || command == "THROW" && m.sport == Darts || (command == "SUB" || command == "TIMEOUT") && m.sport == Volleyball;
    if (!allowed) fail("wrong event");
    int count = command == "POINT" ? int(a[2].size()) : command == "ROLL" || command == "THROW" ? int(a.size()) - 2 : 1;
    for (int i = 0; i < count; ++i) {
        if (finished(m)) fail("match over");
        int value = 0, position = -1, side = 0;
        if (command == "POINT") value = a[2][i] == 'B';
        if (command == "ROLL") {
            value = std::stoi(a[i + 2]);
            if (value > bowlingInfo(std::get<BowlingState>(m.state)).standing) fail("too many pins");
        }
        if (command == "THROW") {
            value = -1;
            for (int j = 0; j < int(darts.size()); ++j) if (darts[j].name == a[i + 2]) value = j;
            if (value < 0) fail("invalid dart");
        }
        if (command == "SUB" || command == "TIMEOUT") {
            side = a[2] == "B";
            const Rally &s = std::get<Rally>(m.state);
            if (command == "TIMEOUT") {
                if (s.timeouts[side] >= 2) fail("no timeouts left");
            } else {
                int out = std::stoi(a[3]);
                value = std::stoi(a[4]);
                for (int j = 0; j < 6; ++j) if (s.lineup[side][j] == out) position = j;
                if (position < 0) fail("player not on court");
                if (std::find(s.lineup[side].begin(), s.lineup[side].end(), value) != s.lineup[side].end()) fail("player already on court");
                if (s.substitutions[side] >= 6) fail("no substitutions left");
            }
        }
        m.history.push_back(m.state);
        if (command == "POINT") addRally(m, std::get<Rally>(m.state), value);
        if (command == "ROLL") {
            BowlingState &s = std::get<BowlingState>(m.state);
            s.rolls[s.count++] = value;
        }
        if (command == "THROW") addDart(m, std::get<DartsState>(m.state), value);
        if (command == "SUB") {
            Rally &s = std::get<Rally>(m.state);
            s.lineup[side][position] = value;
            ++s.substitutions[side];
        }
        if (command == "TIMEOUT") ++std::get<Rally>(m.state).timeouts[side];
    }
    return {};
}
int main() {
    initializeDarts();
    string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            vector<string> output = execute(split(line));
            for (const string &result : output) std::cout << result << '\n';
        } catch (const std::runtime_error &error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
