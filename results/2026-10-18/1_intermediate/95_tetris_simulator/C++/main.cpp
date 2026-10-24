#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;

const string KINDS = "IOTSZJL";
const vector<string> MOVEMENTS = {"L", "R", "LL", "RR", "SD", "DD", "CW", "CCW"};
const vector<string> CLEAR_NAMES = {"SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI", "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN", "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE"};
const array<string, 4> STATES = {"0", "R", "2", "L"};
const array<int, 12> INTERVALS = {60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2};

struct EndGame {};

struct Pos {
    int s = 0;
    int x = 0;
    int y = 0;
    bool operator<(const Pos& rhs) const { return tie(s, x, y) < tie(rhs.s, rhs.x, rhs.y); }
    bool operator==(const Pos& rhs) const { return tie(s, x, y) == tie(rhs.s, rhs.x, rhs.y); }
};

struct MoveResult {
    Pos position;
    int test = 0;
};

struct Stat {
    long long drops = 0;
    int holds = 0;
    int operations = 0;
    int faults = 0;
    int perfect = 0;
    int sent = 0;
    int cancelled = 0;
    int received = 0;
    int combo = 0;
    int chain = 0;
    array<int, 7> kinds{};
    array<int, 11> clears{};
};

struct State {
    array<int, 22> board{};
    long long random = 0;
    deque<char> queue;
    char hold = '-';
    bool usedHold = false;
    char kind = 'I';
    Pos position;
    int last = 0;
    int test = 0;
    int keys = 0;
    int drop = 0;
    int fall = 0;
    int ground = 0;
    int resets = 0;
    int lowest = 0;
    int initialLevel = 1;
    int level = 1;
    long long score = 0;
    int lines = 0;
    int pieces = 0;
    int streak = 0;
    int chain = 0;
    deque<int> pending;
    bool ended = false;
    Stat stats;
};

struct Snapshot {
    State state;
    vector<State> history;
    State start;
};

struct Evaluation {
    array<int, 10> heights{};
    int holes = 0;
    int bumpiness = 0;
    int value = 0;
};

struct Placement {
    array<int, 22> board{};
    int lines = 0;
};

struct ClearInfo {
    string name;
    int points = 0;
    int sent = 0;
    int index = -1;
};

struct Route {
    Pos position;
    vector<string> keys;
};

struct Candidate {
    int value = 0;
    char kind = 'I';
    vector<string> keys;
};

long long nextRandom(long long& random) {
    random = random * 48271 % 2147483647;
    return random;
}

int kindIndex(char kind) { return static_cast<int>(KINDS.find(kind)); }

int sumPending(const deque<int>& q) {
    int sum = 0;
    for (int n : q) sum += n;
    return sum;
}

string join(const vector<string>& v, const string& separator) {
    string out;
    for (const string& item : v) {
        if (!out.empty()) out += separator;
        out += item;
    }
    return out;
}

string toRatio(long long numerator, long long denominator) {
    long long value = denominator ? numerator * 100 / denominator : 0;
    return to_string(value / 100) + "." + (value % 100 < 10 ? "0" : "") + to_string(value % 100);
}

vector<pair<int, int>> frame(char kind) {
    vector<string> lines;
    switch (kind) {
        case 'I': lines = {"....", "####", "....", "...."}; break;
        case 'O': lines = {"##", "##"}; break;
        case 'T': lines = {".#.", "###", "..."}; break;
        case 'S': lines = {".##", "##.", "..."}; break;
        case 'Z': lines = {"##.", ".##", "..."}; break;
        case 'J': lines = {"#..", "###", "..."}; break;
        case 'L': lines = {"..#", "###", "..."}; break;
    }
    vector<pair<int, int>> out;
    for (int j = 0; j < static_cast<int>(lines.size()); ++j)
        for (int i = 0; i < static_cast<int>(lines[j].size()); ++i)
            if (lines[j][i] == '#') out.emplace_back(i, j);
    return out;
}

vector<pair<int, int>> cells(char kind, Pos position) {
    int side = kind == 'I' ? 4 : kind == 'O' ? 2 : 3;
    auto blocks = frame(kind);
    for (int state = 0; state < position.s; ++state)
        for (auto& block : blocks) {
            int i = block.first;
            block.first = side - 1 - block.second;
            block.second = i;
        }
    for (auto& block : blocks) {
        block.first += position.x;
        block.second = position.y - block.second;
    }
    return blocks;
}

Pos spawn(char kind) { return {0, kind == 'O' ? 5 : 4, 22}; }

int lowest(char kind, Pos pos) {
    int minRow = 23;
    for (const auto& cell : cells(kind, pos)) minRow = min(minRow, cell.second);
    return minRow;
}

bool fits(const array<int, 22>& board, char kind, Pos pos) {
    for (auto [c, r] : cells(kind, pos)) {
        if (c < 1 || c > 10 || r < 1 || r > 22) return false;
        if ((board[r - 1] & (1 << (c - 1))) != 0) return false;
    }
    return true;
}

const map<string, vector<pair<int, int>>>& kicks(bool isI) {
    static const map<string, vector<pair<int, int>>> normal = {
        {"01", {{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}}},
        {"10", {{0,0},{1,0},{1,-1},{0,2},{1,2}}},
        {"12", {{0,0},{1,0},{1,-1},{0,2},{1,2}}},
        {"21", {{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}}},
        {"23", {{0,0},{1,0},{1,1},{0,-2},{1,-2}}},
        {"32", {{0,0},{-1,0},{-1,-1},{0,2},{-1,2}}},
        {"30", {{0,0},{-1,0},{-1,-1},{0,2},{-1,2}}},
        {"03", {{0,0},{1,0},{1,1},{0,-2},{1,-2}}}
    };
    static const map<string, vector<pair<int, int>>> i = {
        {"01", {{0,0},{-2,0},{1,0},{-2,-1},{1,2}}},
        {"10", {{0,0},{2,0},{-1,0},{2,1},{-1,-2}}},
        {"12", {{0,0},{-1,0},{2,0},{-1,2},{2,-1}}},
        {"21", {{0,0},{1,0},{-2,0},{1,-2},{-2,1}}},
        {"23", {{0,0},{2,0},{-1,0},{2,1},{-1,-2}}},
        {"32", {{0,0},{-2,0},{1,0},{-2,-1},{1,2}}},
        {"30", {{0,0},{1,0},{-2,0},{1,-2},{-2,1}}},
        {"03", {{0,0},{-1,0},{2,0},{-1,2},{2,-1}}}
    };
    return isI ? i : normal;
}

optional<MoveResult> moved(const array<int, 22>& board, char kind, Pos position, const string& action) {
    if (action == "CW" || action == "CCW") {
        int target = (position.s + (action == "CW" ? 1 : 3)) % 4;
        const vector<pair<int, int>> own = {{0,0}};
        const auto& offsets = kind == 'O' ? own : kicks(kind == 'I').at(to_string(position.s) + to_string(target));
        for (size_t i = 0; i < offsets.size(); ++i) {
            Pos candidate = {target, position.x + offsets[i].first, position.y + offsets[i].second};
            if (fits(board, kind, candidate)) return MoveResult{candidate, static_cast<int>(i) + 1};
        }
        return nullopt;
    }
    int dx = action == "L" || action == "LL" ? -1 : action == "R" || action == "RR" ? 1 : 0;
    int dy = dx == 0 ? -1 : 0;
    bool repeat = action == "LL" || action == "RR" || action == "DD";
    Pos current = position;
    bool changed = false;
    do {
        Pos next = {current.s, current.x + dx, current.y + dy};
        if (!fits(board, kind, next)) break;
        current = next;
        changed = true;
    } while (repeat);
    if (!changed) return nullopt;
    return MoveResult{current, 0};
}

Pos landing(const array<int, 22>& board, char kind, Pos pos) {
    auto result = moved(board, kind, pos, "DD");
    return result ? result->position : pos;
}

Placement placed(const array<int, 22>& board, char kind, Pos pos) {
    Placement out;
    out.board = board;
    for (auto [c, r] : cells(kind, pos)) out.board[r - 1] |= 1 << (c - 1);
    array<int, 22> filtered{};
    int next = 0;
    for (int row : out.board) if (row != 1023) filtered[next++] = row;
    out.lines = 22 - next;
    out.board = filtered;
    return out;
}

Evaluation evaluate(const array<int, 22>& board, int cleared) {
    Evaluation result;
    for (int col = 0; col < 10; ++col) {
        for (int r = 21; r >= 0; --r) if (board[r] & (1 << col)) {
            result.heights[col] = r + 1;
            break;
        }
        for (int r = 0; r < result.heights[col]; ++r)
            if (!(board[r] & (1 << col))) result.holes++;
    }
    int sum = 0;
    for (int col = 0; col < 10; ++col) {
        sum += result.heights[col];
        if (col < 9) result.bumpiness += abs(result.heights[col] - result.heights[col + 1]);
    }
    result.value = 76 * cleared - 51 * sum - 36 * result.holes - 18 * result.bumpiness;
    return result;
}

vector<Route> routes(const array<int, 22>& board, char kind, Pos start, optional<Pos> target = nullopt) {
    vector<Route> queue;
    if (!fits(board, kind, start)) return queue;
    set<Pos> visited = {start};
    queue.push_back({start, {}});
    for (size_t index = 0; index < queue.size(); ++index) {
        const Route& entry = queue[index];
        Pos position = entry.position;
        if (target && landing(board, kind, position) == *target) return {entry};
        vector<string> keys = entry.keys;
        for (const string& action : MOVEMENTS) {
            auto next = moved(board, kind, position, action);
            if (next && visited.insert(next->position).second) {
                auto path = keys;
                path.push_back(action);
                queue.push_back({next->position, move(path)});
            }
        }
    }
    return target ? vector<Route>() : queue;
}

string spinType(const array<int, 22>& board, Pos pos, int test) {
    const int x = pos.x, y = pos.y;
    const array<pair<int, int>, 4> corners = {{{x,y},{x+2,y},{x+2,y-2},{x,y-2}}};
    array<bool, 4> occupied{};
    int count = 0;
    for (int i = 0; i < 4; ++i) {
        auto [col, row] = corners[i];
        occupied[i] = col < 1 || col > 10 || row < 1 || row > 22 || (board[row - 1] & (1 << (col - 1)));
        if (occupied[i]) count++;
    }
    if (count < 3) return "";
    return (occupied[pos.s] && occupied[(pos.s + 1) % 4]) || test == 5 ? "full" : "mini";
}

ClearInfo clearInfo(const string& spin, int lines) {
    if (spin == "full") {
        const array<int, 4> points = {400, 800, 1200, 1600};
        const array<int, 4> sent = {0, 2, 4, 6};
        return {CLEAR_NAMES[7 + lines], points[lines], sent[lines], 7 + lines};
    }
    if (spin == "mini") {
        const array<int, 3> points = {100, 200, 400};
        const array<int, 3> sent = {0, 0, 1};
        return {CLEAR_NAMES[4 + lines], points[lines], sent[lines], 4 + lines};
    }
    if (lines == 0) return {};
    const array<int, 5> points = {0, 100, 300, 500, 800};
    const array<int, 5> sent = {0, 0, 1, 2, 4};
    return {CLEAR_NAMES[lines - 1], points[lines], sent[lines], lines - 1};
}

class Game {
public:
    int serial = 0;
    State state;
    vector<State> history;
    State start;
    map<string, Snapshot> saves;

    Game(int number, long long seed, int level) : serial(number) {
        state.random = seed;
        state.initialLevel = level;
        state.level = level;
        addBag();
        spawnPiece(takeNext());
        start = state;
    }

    void emit(const string& text) { cout << text << '\n'; }

    void addBag() {
        vector<char> pieces(KINDS.begin(), KINDS.end());
        for (int i = 6; i >= 1; --i) {
            int j = static_cast<int>(nextRandom(state.random) % (i + 1));
            swap(pieces[i], pieces[j]);
        }
        for (char p : pieces) state.queue.push_back(p);
    }

    char takeNext() {
        char result = state.queue.front();
        state.queue.pop_front();
        if (state.queue.size() < 5) addBag();
        return result;
    }

    void gameOver(const string& reason) {
        emit("game over " + reason);
        summary();
        state.ended = true;
        throw EndGame{};
    }

    void spawnPiece(char kind) {
        auto& s = state;
        s.kind = kind;
        s.position = spawn(kind);
        s.last = 0;
        s.test = 0;
        s.keys = s.drop = s.fall = s.ground = s.resets = 0;
        s.lowest = lowest(kind, s.position);
        if (!fits(s.board, kind, s.position)) gameOver("block out");
    }

    void updatePosition(Pos pos, int last, int test = 0) {
        auto& s = state;
        s.position = pos;
        s.last = last;
        s.test = test;
        int current = lowest(s.kind, pos);
        if (current < s.lowest) {
            s.lowest = current;
            s.resets = 0;
        }
    }

    bool grounded() const {
        return !moved(state.board, state.kind, state.position, "SD");
    }

    void drops(int count) {
        state.score += count;
        state.drop += count;
        state.stats.drops += count;
    }

    void garbage(int count, int hole) {
        auto& s = state;
        for (int i = 22 - count; i < 22; ++i)
            if (s.board[i]) gameOver("top out");
        for (int i = 21; i >= count; --i) s.board[i] = s.board[i - count];
        for (int i = 0; i < count; ++i) s.board[i] = 1023 ^ (1 << (hole - 1));
    }

    void operation(const string& action) {
        auto& s = state;
        if (find(MOVEMENTS.begin(), MOVEMENTS.end(), action) != MOVEMENTS.end()) {
            s.keys++;
            auto result = moved(s.board, s.kind, s.position, action);
            if (!result) { emit("fail " + action); return; }
            if (action == "SD" || action == "DD") {
                drops(s.position.y - result->position.y);
                updatePosition(result->position, 1);
                s.fall = s.ground = 0;
            } else {
                bool rotation = action == "CW" || action == "CCW";
                updatePosition(result->position, rotation ? 2 : 1, result->test);
                if (s.ground > 0 && s.resets < 15) {
                    s.ground = 0;
                    s.resets++;
                }
            }
            return;
        }
        if (action == "HD") {
            Pos to = landing(s.board, s.kind, s.position);
            int rows = s.position.y - to.y;
            drops(2 * rows);
            if (rows) updatePosition(to, 1);
            lock();
        } else if (action == "LOCK") {
            if (grounded()) lock();
            else emit("fail LOCK");
        } else if (action == "HOLD") {
            if (s.usedHold) { emit("fail HOLD"); return; }
            s.usedHold = true;
            s.stats.holds++;
            char current = s.kind;
            char next = s.hold == '-' ? takeNext() : s.hold;
            s.hold = current;
            spawnPiece(next);
        }
    }

    void tick() {
        auto& s = state;
        if (!grounded()) {
            s.ground = 0;
            s.fall++;
            int g = s.level >= 13 ? 1 : INTERVALS[s.level - 1];
            if (s.fall >= g) {
                updatePosition({s.position.s, s.position.x, s.position.y - 1}, 1);
                s.fall = 0;
            }
        } else {
            s.ground++;
            if (s.ground >= 30) lock();
        }
    }

    void lock() {
        auto& s = state;
        char kind = s.kind;
        Pos pos = s.position;
        auto oldCells = cells(kind, pos);
        auto shortest = routes(s.board, kind, spawn(kind), pos);
        string spin = kind == 'T' && s.last == 2 ? spinType(s.board, pos, s.test) : "";
        auto place = placed(s.board, kind, pos);
        s.board = place.board;
        int lines = place.lines;
        history.push_back(start);
        s.pieces++;
        s.stats.kinds[kindIndex(kind)]++;
        s.stats.operations += s.keys;
        auto info = clearInfo(spin, lines);
        int level = s.level;
        int points = info.points * level, sent = info.sent;
        bool b2b = false;
        if (lines) {
            s.streak++;
            if (lines == 4 || !spin.empty()) {
                s.chain++;
                b2b = s.chain >= 2;
            } else s.chain = 0;
        } else s.streak = 0;
        if (b2b) { points = points * 3 / 2; sent++; }
        int combo = s.streak - 1;
        int comboPoints = combo >= 1 ? 50 * combo * level : 0;
        const array<int, 11> comboSent = {0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5};
        if (combo >= 0) sent += comboSent[min(combo, 10)];
        bool perfect = lines > 0 && all_of(s.board.begin(), s.board.end(), [](int row) { return row == 0; });
        int perfectPoints = 0;
        if (perfect) {
            const array<int, 4> full = {800, 1200, 1800, 2000};
            perfectPoints = (lines == 4 && b2b ? 3200 : full[lines - 1]) * level;
            sent += 10;
            s.stats.perfect++;
        }
        int gained = points + comboPoints + perfectPoints;
        s.score += gained;
        s.lines += lines;
        s.stats.sent += sent;
        s.stats.combo = max(s.stats.combo, combo);
        s.stats.chain = max(s.stats.chain, s.chain);
        string length = shortest.empty() ? "-" : to_string(shortest[0].keys.size());
        emit("lock " + to_string(s.pieces) + " " + kind + " " + STATES[pos.s] + " " + to_string(pos.x) + " " + to_string(pos.y) +
             " keys " + to_string(s.keys) + " " + length + " drop " + to_string(s.drop) + " lines " + to_string(lines) +
             " sent " + to_string(sent) + " +" + to_string(gained) + " total " + to_string(s.score));
        if (!shortest.empty() && s.keys > static_cast<int>(shortest[0].keys.size())) {
            s.stats.faults++;
            string sequence = shortest[0].keys.empty() ? "none" : join(shortest[0].keys, " ");
            emit("finesse " + sequence);
        }
        if (info.index >= 0) {
            s.stats.clears[info.index]++;
            string report = "clear " + info.name + " " + to_string(points);
            if (b2b) report += " b2b";
            if (combo >= 1) report += " combo " + to_string(combo) + " " + to_string(comboPoints);
            if (perfect) report += " perfect " + to_string(perfectPoints);
            emit(report);
        }
        int nextLevel = s.initialLevel + s.lines / 10;
        if (nextLevel > level) {
            s.level = nextLevel;
            emit("level " + to_string(s.level));
        }
        if (all_of(oldCells.begin(), oldCells.end(), [](auto cell) { return cell.second >= 21; })) gameOver("lock out");
        int cancelled = min(sent, sumPending(s.pending));
        int remaining = cancelled;
        while (remaining > 0) {
            int count = min(remaining, s.pending.front());
            s.pending.front() -= count;
            remaining -= count;
            if (!s.pending.front()) s.pending.pop_front();
        }
        if (cancelled) {
            s.stats.cancelled += cancelled;
            emit("cancel " + to_string(cancelled) + " pending " + to_string(sumPending(s.pending)));
        }
        if (lines == 0) {
            int risen = 0;
            while (!s.pending.empty() && risen < 8) {
                int count = min(s.pending.front(), 8 - risen);
                int hole = static_cast<int>(nextRandom(s.random) % 10) + 1;
                garbage(count, hole);
                s.stats.received += count;
                risen += count;
                s.pending.front() -= count;
                if (!s.pending.front()) s.pending.pop_front();
                emit("rise " + to_string(count) + " hole " + to_string(hole) + " pending " + to_string(sumPending(s.pending)));
            }
        }
        s.usedHold = false;
        spawnPiece(takeNext());
        start = s;
    }

    vector<Candidate> candidates(char kind, Pos first, vector<string> prefix) const {
        vector<Candidate> out;
        set<array<int,4>> seen;
        auto consider = [&](Pos at, const vector<string>& turns, const vector<string>& shifts) {
            Pos down = landing(state.board, kind, at);
            array<int,4> id{};
            int i = 0;
            for (auto [c,r] : cells(kind, down)) id[i++] = (r - 1) * 10 + c - 1;
            sort(id.begin(), id.end());
            if (!seen.insert(id).second) return;
            auto placement = placed(state.board, kind, down);
            vector<string> sequence = prefix;
            sequence.insert(sequence.end(), turns.begin(), turns.end());
            sequence.insert(sequence.end(), shifts.begin(), shifts.end());
            sequence.push_back("HD");
            out.push_back({evaluate(placement.board, placement.lines).value, kind, move(sequence)});
        };
        const vector<vector<string>> orientations = {{}, {"CW"}, {"CW", "CW"}, {"CCW"}};
        for (const auto& turns : orientations) {
            Pos pos = first;
            bool valid = true;
            for (const string& turn : turns) {
                auto next = moved(state.board, kind, pos, turn);
                if (!next) { valid = false; break; }
                pos = next->position;
            }
            if (!valid) continue;
            consider(pos, turns, {});
            for (const string& direction : {string("L"), string("R")}) {
                Pos shifted = pos;
                vector<string> shifts;
                while (true) {
                    auto next = moved(state.board, kind, shifted, direction);
                    if (!next) break;
                    shifted = next->position;
                    shifts.push_back(direction);
                    consider(shifted, turns, shifts);
                }
            }
        }
        return out;
    }

    vector<Candidate> ranked() const {
        vector<Candidate> out = candidates(state.kind, state.position, {});
        char held = state.hold == '-' ? state.queue.front() : state.hold;
        if (!state.usedHold && fits(state.board, held, spawn(held))) {
            auto more = candidates(held, spawn(held), {"HOLD"});
            out.insert(out.end(), more.begin(), more.end());
        }
        stable_sort(out.begin(), out.end(), [](const Candidate& a, const Candidate& b) { return a.value > b.value; });
        return out;
    }

    void spins() {
        if (state.kind != 'T') { emit("spins 0"); return; }
        map<Pos, string> found;
        for (const Route& route : routes(state.board, 'T', state.position)) {
            for (const string& turn : {string("CW"), string("CCW")}) {
                auto next = moved(state.board, 'T', route.position, turn);
                if (!next || moved(state.board, 'T', next->position, "SD")) continue;
                string spin = spinType(state.board, next->position, next->test);
                if (!spin.empty() && (found.find(next->position) == found.end() || spin == "full"))
                    found[next->position] = spin;
            }
        }
        vector<pair<Pos,string>> result(found.begin(), found.end());
        sort(result.begin(), result.end(), [](const auto& a, const auto& b) {
            return tie(a.first.y, a.first.x, a.first.s) < tie(b.first.y, b.first.x, b.first.s);
        });
        for (const auto& [pos,spin] : result) {
            int cleared = placed(state.board, 'T', pos).lines;
            emit("spin " + STATES[pos.s] + " " + to_string(pos.x) + " " + to_string(pos.y) + " " + clearInfo(spin, cleared).name);
        }
        emit("spins " + to_string(result.size()));
    }

    void summary() const {
        const State& s = state;
        const Stat& st = s.stats;
        const auto& k = st.kinds;
        const auto& c = st.clears;
        cout << "summary game " << serial << " score " << s.score << " level " << s.level << " lines " << s.lines << " pieces " << s.pieces << '\n';
        cout << "clears single " << c[0] << " double " << c[1] << " triple " << c[2] << " tetris " << c[3] << " perfect " << st.perfect << '\n';
        cout << "tspins mini " << c[4] << " mini_single " << c[5] << " mini_double " << c[6] << " zero " << c[7]
             << " single " << c[8] << " double " << c[9] << " triple " << c[10] << '\n';
        cout << "pieces I " << k[0] << " O " << k[1] << " T " << k[2] << " S " << k[3] << " Z " << k[4] << " J " << k[5] << " L " << k[6] << '\n';
        cout << "best combo " << st.combo << " chain " << st.chain << " holds " << st.holds << " drops " << st.drops << " faults " << st.faults << '\n';
        cout << "garbage sent " << st.sent << " cancelled " << st.cancelled << " received " << st.received << '\n';
        cout << "rates app " << toRatio(st.sent, s.pieces) << " apl " << toRatio(st.sent, s.lines) << " kpp " << toRatio(st.operations, s.pieces) << '\n';
    }

    void command(const string& name, const vector<string>& args) {
        auto& s = state;
        if (name == "PRINT") {
            set<int> current, ghost;
            if (!s.ended) {
                for (auto [c,r] : cells(s.kind, s.position)) current.insert(r * 10 + c);
                for (auto [c,r] : cells(s.kind, landing(s.board, s.kind, s.position))) ghost.insert(r * 10 + c);
            }
            for (int r = 22; r >= 1; --r) {
                string text = (r < 10 ? " " : "") + to_string(r) + " ";
                for (int c = 1; c <= 10; ++c) {
                    int id = r * 10 + c;
                    text += (s.board[r-1] & (1 << (c-1))) ? '#' : current.count(id) ? '@' : ghost.count(id) ? '+' : '.';
                }
                emit(text);
            }
        } else if (name == "NEXT") {
            string queue;
            for (int i = 0; i < 5; ++i) queue += s.queue[i];
            emit("hold " + string(1,s.hold) + " next " + queue);
        } else if (name == "PREVIEW") {
            int count = stoi(args[0]);
            auto copy = s.queue;
            long long random = s.random;
            while (static_cast<int>(copy.size()) < count) {
                vector<char> pieces(KINDS.begin(), KINDS.end());
                for (int i = 6; i >= 1; --i) {
                    int j = static_cast<int>(nextRandom(random) % (i+1));
                    swap(pieces[i], pieces[j]);
                }
                for (char kind : pieces) copy.push_back(kind);
            }
            string value;
            for (int i = 0; i < count; ++i) value += copy[i];
            emit("preview " + value);
        } else if (name == "STATUS") {
            emit("score " + to_string(s.score) + " level " + to_string(s.level) + " lines " + to_string(s.lines) + " pieces " + to_string(s.pieces));
            string description = s.ended ? "-" : string(1,s.kind) + " " + STATES[s.position.s] + " " + to_string(s.position.x) + " " + to_string(s.position.y);
            emit("piece " + description + " streak " + to_string(s.streak) + " chain " + to_string(s.chain) + " pending " + to_string(sumPending(s.pending)));
        } else if (name == "ANALYZE") {
            auto value = evaluate(s.board, 0);
            string heights = "heights";
            for (int n : value.heights) heights += " " + to_string(n);
            emit(heights);
            emit("holes " + to_string(value.holes) + " bumpiness " + to_string(value.bumpiness) + " value " + to_string(value.value));
        } else if (name == "ROW") {
            int r = stoi(args[0]);
            const string& pattern = args[1];
            for (auto [c,row] : cells(s.kind, s.position)) if (row == r && pattern[c - 1] == '#') {
                emit("ERROR overlap");
                return;
            }
            int mask = 0;
            for (int i = 0; i < 10; ++i) if (pattern[i] == '#') mask |= 1 << i;
            s.board[r-1] = mask;
            emit("OK");
        } else if (name == "GARBAGE") {
            int n = stoi(args[0]), hole = stoi(args[1]);
            garbage(n, hole);
            for (int j = 0; j <= n; ++j) {
                Pos shifted = {s.position.s,s.position.x,s.position.y+j};
                if (fits(s.board,s.kind,shifted)) {
                    s.position = shifted;
                    emit("OK");
                    return;
                }
            }
            gameOver("top out");
        } else if (name == "ATTACK") {
            s.pending.push_back(stoi(args[0]));
            emit("pending " + to_string(sumPending(s.pending)));
        } else if (name == "TICK") {
            int n = stoi(args[0]);
            for (int i = 0; i < n; ++i) tick();
        } else if (name == "UNDO") {
            if (history.empty()) emit("ERROR nothing to undo");
            else {
                s = history.back();
                history.pop_back();
                start = s;
                emit("undo " + to_string(s.pieces) + " " + s.kind);
            }
        } else if (name == "SAVE") {
            saves[args[0]] = {s, history, start};
            emit("OK");
        } else if (name == "LOAD") {
            auto it = saves.find(args[0]);
            if (it == saves.end()) emit("ERROR unknown save");
            else {
                Snapshot snap = it->second;
                s = snap.state;
                history = move(snap.history);
                start = snap.start;
                emit("load " + to_string(s.pieces) + " " + s.kind);
            }
        } else if (name == "SPINS") {
            spins();
        } else if (name == "HINT") {
            auto choice = ranked();
            int count = min(static_cast<int>(choice.size()), stoi(args[0]));
            for (int i = 0; i < count; ++i) {
                const auto& entry = choice[i];
                emit("hint " + to_string(i+1) + " " + entry.kind + " " + join(entry.keys, " ") + " value " + to_string(entry.value));
            }
        } else if (name == "AUTO") {
            int count = stoi(args[0]);
            for (int i = 0; i < count; ++i) {
                auto choice = ranked();
                if (choice.empty()) break;
                const auto best = choice[0];
                emit("auto " + string(1,best.kind) + " " + join(best.keys," "));
                for (const string& action : best.keys) operation(action);
            }
        }
    }
};

bool number(const string& word, long long low, long long high) {
    if (word.empty() || (word.size() > 1 && word[0] == '0')) return false;
    long long value = 0;
    for (char c : word) {
        if (c < '0' || c > '9') return false;
        value = value * 10 + c - '0';
        if (value > high) return false;
    }
    return value >= low;
}

bool argumentsValid(const string& name, const vector<string>& args) {
    if (name == "NEW") return args.size() == 2 && number(args[0],1,2147483646) && number(args[1],1,15);
    if (name == "ROW") {
        if (args.size() != 2 || !number(args[0],1,22) || args[1].size() != 10 || args[1].find('.') == string::npos) return false;
        return all_of(args[1].begin(),args[1].end(),[](char c) { return c == '#' || c == '.'; });
    }
    if (name == "GARBAGE") return args.size() == 2 && number(args[0],1,10) && number(args[1],1,10);
    if (name == "SAVE" || name == "LOAD") return args.size() == 1 && args[0].size() >= 1 && args[0].size() <= 8 && all_of(args[0].begin(),args[0].end(),[](char c) { return c >= 'a' && c <= 'z'; });
    const map<string, int> limits = {{"PREVIEW",14},{"ATTACK",20},{"TICK",1000},{"HINT",10},{"AUTO",50}};
    auto limit = limits.find(name);
    if (limit != limits.end()) return args.size() == 1 && number(args[0],1,limit->second);
    return args.empty();
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const set<string> commands = {"NEW","PRINT","NEXT","PREVIEW","STATUS","ANALYZE","ROW","GARBAGE","ATTACK","TICK","UNDO","SAVE","LOAD","SPINS","HINT","AUTO"};
    const set<string> afterEnd = {"PRINT","NEXT","PREVIEW","STATUS","ANALYZE","LOAD"};
    set<string> operations(MOVEMENTS.begin(), MOVEMENTS.end());
    operations.insert({"HD","LOCK","HOLD"});
    int n = 0;
    if (!(cin >> n)) return 0;
    string line;
    getline(cin,line);
    unique_ptr<Game> game;
    int serial = 0;
    for (int i = 0; i < n && getline(cin,line); ++i) {
        istringstream input(line);
        vector<string> words;
        string word;
        while (input >> word) words.push_back(word);
        if (words.empty()) continue;
        string name = words.front();
        vector<string> args(words.begin()+1,words.end());
        try {
            if (commands.count(name)) {
                if (!argumentsValid(name,args)) cout << "ERROR bad arguments\n";
                else if (name == "NEW") {
                    if (game && !game->state.ended) {
                        game->emit("game stopped");
                        game->summary();
                    }
                    int seed = stoi(args[0]), level = stoi(args[1]);
                    cout << "game " << ++serial << " seed " << seed << " level " << level << '\n';
                    game = make_unique<Game>(serial,seed,level);
                } else if (!game) cout << "ERROR no game\n";
                else if (game->state.ended && !afterEnd.count(name)) cout << "ERROR game over\n";
                else game->command(name,args);
            } else {
                auto bad = find_if(words.begin(),words.end(),[&](const string& op) { return !operations.count(op); });
                if (bad != words.end()) cout << "ERROR unknown " << *bad << '\n';
                else if (!game) cout << "ERROR no game\n";
                else if (game->state.ended) cout << "ERROR game over\n";
                else for (const string& op : words) game->operation(op);
            }
        } catch (const EndGame&) {}
    }
    if (game && !game->state.ended) {
        game->emit("game stopped");
        game->summary();
    }
}
