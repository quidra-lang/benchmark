#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <iostream>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
using namespace std;
const string FILES = "abcdefgh", RANKS = "12345678",
             INITIAL = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
const vector<pair<int, int>> ROOK = {{0, 1}, {0, -1}, {-1, 0}, {1, 0}},
                             BISHOP = {{1, 1}, {-1, 1}, {1, -1}, {-1, -1}},
                             KING = {{0, 1}, {0, -1}, {-1, 0}, {1, 0},
                                     {1, 1}, {-1, 1}, {1, -1}, {-1, -1}},
                             KNIGHT = {{1, 2},   {2, 1},   {2, -1}, {1, -2},
                                       {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
struct CastleRule {
    int king, rook, target, rookTarget;
    vector<int> path;
};
const map<char, CastleRule> RULES = {{'K', {4, 7, 6, 5, {5, 6}}},
                                     {'Q', {4, 0, 2, 3, {1, 2, 3}}},
                                     {'k', {60, 63, 62, 61, {61, 62}}},
                                     {'q', {60, 56, 58, 59, {57, 58, 59}}}};
struct Move {
    int source, target;
    char promotion = 0;
};
struct Record {
    string san, uci;
    char captured;
};
void fail(const string &reason) {
    throw runtime_error(reason);
}
char upper(char p) {
    return char(toupper(static_cast<unsigned char>(p)));
}
char lower(char p) {
    return char(tolower(static_cast<unsigned char>(p)));
}
char color(char p) {
    return p == upper(p) ? 'w' : 'b';
}
char opposite(char c) {
    return c == 'w' ? 'b' : 'w';
}
char colored(char p, char c) {
    return c == 'w' ? p : lower(p);
}
int step(char c) {
    return c == 'w' ? 8 : -8;
}
int square(const string &s) {
    return s.size() == 2 && s[0] >= 'a' && s[0] <= 'h' && s[1] >= '1' && s[1] <= '8'
               ? s[0] - 'a' + 8 * (s[1] - '1')
               : -1;
}
string name(int s) {
    return string(1, FILES[s % 8]) + RANKS[s / 8];
}
int number(const string &s, int lo, int hi) {
    if (s.empty() || (s.size() > 1 && s[0] == '0') || s.size() > 9)
        return -1;
    int v = 0;
    for (char c : s) {
        if (c < '0' || c > '9')
            return -1;
        v = v * 10 + c - '0';
    }
    return v >= lo && v <= hi ? v : -1;
}
int shift(int s, int dx, int dy) {
    int x = s % 8 + dx, y = s / 8 + dy;
    return x >= 0 && x < 8 && y >= 0 && y < 8 ? 8 * y + x : -1;
}
vector<string> words(const string &s) {
    istringstream in(s);
    vector<string> a;
    string x;
    while (in >> x)
        a.push_back(x);
    return a;
}
string join(const vector<string> &a, const string &sep = " ") {
    string s;
    for (const string &x : a) {
        if (!s.empty())
            s += sep;
        s += x;
    }
    return s;
}
vector<int> targets(const array<char, 64> &board, int s) {
    char piece = board[s], kind = upper(piece);
    vector<int> result;
    if (kind == 'P' || kind == 'N' || kind == 'K') {
        vector<pair<int, int>> dirs =
            kind == 'P'   ? vector<pair<int, int>>{{-1, color(piece) == 'w' ? 1 : -1},
                                                   {1, color(piece) == 'w' ? 1 : -1}}
            : kind == 'N' ? KNIGHT
                          : KING;
        for (auto [dx, dy] : dirs) {
            int t = shift(s, dx, dy);
            if (t >= 0)
                result.push_back(t);
        }
        return result;
    }
    const vector<pair<int, int>> &dirs = kind == 'Q' ? KING : kind == 'R' ? ROOK : BISHOP;
    for (auto [dx, dy] : dirs)
        for (int t = shift(s, dx, dy); t >= 0; t = shift(t, dx, dy)) {
            result.push_back(t);
            if (board[t] != '.')
                break;
        }
    return result;
}
vector<int> attackers(const array<char, 64> &board, int t, char c) {
    vector<int> a;
    for (int s = 0; s < 64; s++)
        if (board[s] != '.' && color(board[s]) == c) {
            vector<int> b = targets(board, s);
            if (find(b.begin(), b.end(), t) != b.end())
                a.push_back(s);
        }
    return a;
}
struct Position {
    array<char, 64> board;
    char side;
    string rights;
    int ep, half, full;
    bool check(char c) const {
        int k = int(find(board.begin(), board.end(), colored('K', c)) - board.begin());
        return !attackers(board, k, opposite(c)).empty();
    }
    bool check() const {
        return check(side);
    }
    bool castle(Move m) const {
        return upper(board[m.source]) == 'K' && abs(m.target - m.source) == 2;
    }
    bool enpassant(Move m) const {
        return upper(board[m.source]) == 'P' && m.source % 8 != m.target % 8 &&
               board[m.target] == '.';
    }
    bool capture(Move m) const {
        return board[m.target] != '.' || enpassant(m);
    }
    char captured(Move m) const {
        return board[m.target] != '.' ? lower(board[m.target]) : enpassant(m) ? 'p' : '-';
    }
    Position play(Move m) const {
        Position q = *this;
        char piece = board[m.source], kind = upper(piece);
        if (enpassant(m))
            q.board[m.target - step(side)] = '.';
        if (castle(m)) {
            const CastleRule &r = RULES.at(colored(m.target > m.source ? 'K' : 'Q', side));
            q.board[r.rookTarget] = q.board[r.rook];
            q.board[r.rook] = '.';
        }
        q.board[m.target] = m.promotion ? colored(m.promotion, side) : piece;
        q.board[m.source] = '.';
        q.rights.clear();
        for (char r : rights)
            if ((kind != 'K' || color(r) != side) && RULES.at(r).rook != m.source &&
                RULES.at(r).rook != m.target)
                q.rights += r;
        q.ep = kind == 'P' && abs(m.target - m.source) == 16 ? (m.source + m.target) / 2 : -1;
        q.half = kind == 'P' || capture(m) ? 0 : half + 1;
        q.full = full + (side == 'b');
        q.side = opposite(side);
        return q;
    }
    vector<Move> pseudo() const {
        vector<Move> result;
        for (int s = 0; s < 64; s++) {
            char p = board[s];
            if (p == '.' || color(p) != side)
                continue;
            bool pawn = upper(p) == 'P';
            vector<int> a;
            if (pawn) {
                int d = step(side);
                if (board[s + d] == '.') {
                    a.push_back(s + d);
                    if (s / 8 == (side == 'w' ? 1 : 6) && board[s + 2 * d] == '.')
                        a.push_back(s + 2 * d);
                }
                for (int t : targets(board, s))
                    if ((board[t] != '.' && color(board[t]) != side) || t == ep)
                        a.push_back(t);
            } else
                for (int t : targets(board, s))
                    if (board[t] == '.' || color(board[t]) != side)
                        a.push_back(t);
            for (int t : a)
                if (pawn && t / 8 == (side == 'w' ? 7 : 0)) {
                    for (char p : string("QRBN"))
                        result.push_back({s, t, p});
                } else
                    result.push_back({s, t, 0});
        }
        return result;
    }
    Move castlingMove(bool kingside) const {
        const CastleRule &r = RULES.at(colored(kingside ? 'K' : 'Q', side));
        return {r.king, r.target, 0};
    }
    string castlingProblem(bool kingside) const {
        char right = colored(kingside ? 'K' : 'Q', side);
        const CastleRule &r = RULES.at(right);
        if (rights.find(right) == string::npos)
            return "no castling right";
        for (int s : r.path)
            if (board[s] != '.')
                return "path blocked";
        if (check())
            return "in check";
        if (!attackers(board, r.rookTarget, opposite(side)).empty())
            return "through check";
        if (play(castlingMove(kingside)).check(side))
            return "into check";
        return "";
    }
    vector<Move> legal() const {
        vector<Move> a;
        for (Move m : pseudo())
            if (!play(m).check(side))
                a.push_back(m);
        for (bool k : {true, false})
            if (castlingProblem(k).empty())
                a.push_back(castlingMove(k));
        return a;
    }
    string mark(Move m) const {
        Position q = play(m);
        return q.check() ? (q.legal().empty() ? "#" : "+") : "";
    }
    string disambiguation(Move m) const {
        vector<int> a;
        for (Move x : legal())
            if (!castle(x) && x.target == m.target && x.source != m.source &&
                board[x.source] == board[m.source])
                a.push_back(x.source);
        if (a.empty())
            return "";
        bool differentFile = true, differentRank = true;
        for (int s : a) {
            differentFile &= s % 8 != m.source % 8;
            differentRank &= s / 8 != m.source / 8;
        }
        if (differentFile)
            return string(1, FILES[m.source % 8]);
        if (differentRank)
            return string(1, RANKS[m.source / 8]);
        return name(m.source);
    }
    string san(Move m) const {
        string text;
        char kind = upper(board[m.source]);
        if (castle(m))
            text = m.target > m.source ? "O-O" : "O-O-O";
        else if (kind == 'P')
            text = (capture(m) ? string(1, FILES[m.source % 8]) + "x" : "") + name(m.target) +
                   (m.promotion ? "=" + string(1, m.promotion) : "");
        else
            text = string(1, kind) + disambiguation(m) + (capture(m) ? "x" : "") + name(m.target);
        return text + mark(m);
    }
    string key() const {
        int target = -1;
        if (ep >= 0)
            for (Move m : legal())
                if (enpassant(m)) {
                    target = ep;
                    break;
                }
        return string(board.begin(), board.end()) + side + rights + " " + to_string(target);
    }
    string state() const {
        bool any = !legal().empty();
        return check() ? (any ? "check" : "checkmate") : (any ? "normal" : "stalemate");
    }
    bool insufficient() const {
        vector<int> a;
        for (int s = 0; s < 64; s++)
            if (board[s] != '.' && upper(board[s]) != 'K') {
                if (string("PRQ").find(upper(board[s])) != string::npos)
                    return false;
                a.push_back(s);
            }
        if (a.size() <= 1)
            return true;
        int shade = (a[0] % 8 + a[0] / 8) % 2;
        for (int s : a)
            if (upper(board[s]) != 'B' || (s % 8 + s / 8) % 2 != shade)
                return false;
        return true;
    }
    vector<pair<int, int>> pins() const {
        int king = int(find(board.begin(), board.end(), colored('K', side)) - board.begin());
        vector<pair<int, int>> result;
        for (auto [dx, dy] : KING) {
            int first = -1;
            for (int t = shift(king, dx, dy); t >= 0; t = shift(t, dx, dy)) {
                char p = board[t];
                if (p == '.')
                    continue;
                if (first < 0) {
                    if (color(p) != side)
                        break;
                    first = t;
                } else {
                    if (color(p) != side &&
                        (upper(p) == 'Q' || upper(p) == (dx == 0 || dy == 0 ? 'R' : 'B')))
                        result.push_back({first, t});
                    break;
                }
            }
        }
        sort(result.begin(), result.end());
        return result;
    }
    string fen() const {
        vector<string> rows;
        for (int r = 7; r >= 0; r--) {
            string row;
            int empty = 0;
            for (int f = 0; f < 8; f++) {
                char p = board[r * 8 + f];
                if (p == '.')
                    empty++;
                else {
                    if (empty)
                        row += to_string(empty);
                    empty = 0;
                    row += p;
                }
            }
            if (empty)
                row += to_string(empty);
            rows.push_back(row);
        }
        return join(rows, "/") + " " + side + " " + (rights.empty() ? "-" : rights) + " " +
               (ep < 0 ? "-" : name(ep)) + " " + to_string(half) + " " + to_string(full);
    }
};
Position parseFen(const vector<string> &a) {
    if (a.size() != 6)
        fail("fields");
    vector<string> ranks;
    size_t start = 0;
    for (size_t i = 0; i <= a[0].size(); i++)
        if (i == a[0].size() || a[0][i] == '/') {
            ranks.push_back(a[0].substr(start, i - start));
            start = i + 1;
        }
    if (ranks.size() != 8)
        fail("placement");
    Position p{};
    p.board.fill('.');
    for (int i = 0; i < 8; i++) {
        int f = 0;
        bool digit = false;
        for (char c : ranks[i])
            if (c >= '1' && c <= '8') {
                if (digit)
                    fail("placement");
                f += c - '0';
                digit = true;
            } else {
                if (string("KQRBNPkqrbnp").find(c) == string::npos || f >= 8)
                    fail("placement");
                p.board[(7 - i) * 8 + f++] = c;
                digit = false;
            }
        if (f != 8)
            fail("placement");
    }
    if (count(p.board.begin(), p.board.end(), 'K') != 1 ||
        count(p.board.begin(), p.board.end(), 'k') != 1)
        fail("kings");
    for (int i = 0; i < 8; i++)
        if (upper(p.board[i]) == 'P' || upper(p.board[56 + i]) == 'P')
            fail("pawns");
    if (a[1] != "w" && a[1] != "b")
        fail("side");
    p.side = a[1][0];
    if (a[2] != "-" && (!regex_match(a[2], regex("K?Q?k?q?")) || a[2].empty()))
        fail("castling");
    p.rights = a[2] == "-" ? "" : a[2];
    for (char r : p.rights) {
        const CastleRule &rule = RULES.at(r);
        if (p.board[rule.king] != colored('K', color(r)) ||
            p.board[rule.rook] != colored('R', color(r)))
            fail("castling");
    }
    p.ep = -1;
    if (a[3] != "-") {
        p.ep = square(a[3]);
        int d = step(p.side);
        if (p.ep < 0 || p.ep / 8 != (p.side == 'w' ? 5 : 2) || p.board[p.ep] != '.' ||
            p.board[p.ep + d] != '.' || p.board[p.ep - d] != colored('P', opposite(p.side)))
            fail("en passant");
    }
    p.half = number(a[4], 0, 999);
    p.full = number(a[5], 1, 999);
    if (p.half < 0 || p.full < 0 || (p.ep >= 0 && p.half != 0))
        fail("clocks");
    if (p.check(opposite(p.side)))
        fail("check");
    return p;
}
Move readSan(const Position &p, const string &text) {
    string body = text, mark;
    if (!body.empty() && (body.back() == '+' || body.back() == '#')) {
        mark = body.back();
        body.pop_back();
    }
    bool castling = body == "O-O" || body == "O-O-O", capture = false;
    char promotion = 0, kind = 'P';
    string file, rank;
    int target = -1;
    if (!castling) {
        if (body.size() >= 2 && body[body.size() - 2] == '=') {
            promotion = body.back();
            if (string("QRBN").find(promotion) == string::npos)
                fail("syntax");
            body.resize(body.size() - 2);
        }
        if (body.size() < 2)
            fail("syntax");
        target = square(body.substr(body.size() - 2));
        if (target < 0)
            fail("syntax");
        body.resize(body.size() - 2);
        if (!body.empty() && body.back() == 'x') {
            capture = true;
            body.pop_back();
        }
        if (!body.empty() && string("KQRBN").find(body[0]) != string::npos) {
            kind = body[0];
            body.erase(0, 1);
            smatch m;
            if (promotion || !regex_match(body, m, regex("([a-h]?)([1-8]?)")))
                fail("syntax");
            file = m[1];
            rank = m[2];
        } else {
            if (!regex_match(body, regex(capture ? "[a-h]" : "")))
                fail("syntax");
            file = body;
        }
    }
    vector<Move> legal = p.legal();
    if (legal.empty())
        fail("game over");
    Move move{};
    if (castling) {
        bool k = body == "O-O";
        string problem = p.castlingProblem(k);
        if (!problem.empty())
            fail(problem);
        move = p.castlingMove(k);
    } else {
        auto matches = [&](Move m) {
            return upper(p.board[m.source]) == kind && m.target == target && !p.castle(m) &&
                   (file.empty() || FILES[m.source % 8] == file[0]) &&
                   (rank.empty() || RANKS[m.source / 8] == rank[0]) &&
                   (kind != 'P' || (m.source % 8 != m.target % 8) == capture);
        };
        vector<Move> a;
        for (Move m : legal)
            if (matches(m))
                a.push_back(m);
        if (a.empty()) {
            for (Move m : p.pseudo())
                if (matches(m))
                    fail("leaves king in check");
            fail("no such move");
        }
        for (Move m : a)
            if (m.source != a[0].source)
                fail("ambiguous");
        move = a[0];
        if (p.capture(move) != capture)
            fail("capture mark");
        if (move.promotion && !promotion)
            fail("missing promotion");
        if (promotion && !move.promotion)
            fail("invalid promotion");
        if (kind != 'P' && file + rank != p.disambiguation(move))
            fail("disambiguation");
        move.promotion = promotion;
    }
    if (p.mark(move) != mark)
        fail("check mark");
    return move;
}
Move readUci(const Position &p, const string &text) {
    if (!regex_match(text, regex("[a-h][1-8][a-h][1-8][qrbn]?")))
        fail("syntax");
    int s = square(text.substr(0, 2)), t = square(text.substr(2, 2));
    char promotion = text.size() == 5 ? upper(text[4]) : 0;
    vector<Move> legal = p.legal();
    if (legal.empty())
        fail("game over");
    if (p.board[s] == '.' || color(p.board[s]) != p.side)
        fail("no piece");
    for (Move m : legal)
        if (m.source == s && m.target == t) {
            if (m.promotion && !promotion)
                fail("missing promotion");
            if (promotion && !m.promotion)
                fail("invalid promotion");
            return {s, t, promotion};
        }
    for (Move m : p.pseudo())
        if (m.source == s && m.target == t)
            fail("leaves king in check");
    fail("no such move");
    return {};
}
long long perft(const Position &p, int d, array<long long, 7> *stats = nullptr) {
    if (!d)
        return 1;
    long long total = 0;
    for (Move m : p.legal()) {
        Position q = p.play(m);
        total += perft(q, d - 1, stats);
        if (d == 1 && stats) {
            (*stats)[0]++;
            (*stats)[1] += p.capture(m);
            (*stats)[2] += p.enpassant(m);
            (*stats)[3] += p.castle(m);
            (*stats)[4] += m.promotion != 0;
            if (q.check()) {
                (*stats)[5]++;
                (*stats)[6] += q.legal().empty();
            }
        }
    }
    return total;
}
struct Game {
    vector<Position> positions;
    vector<Record> records;
    bool loaded;
    Game(Position p = parseFen(words(INITIAL)), bool load = false) : positions{p}, loaded(load) {
    }
    const Position &current() const {
        return positions.back();
    }
    void play(Move m) {
        const Position &p = current();
        records.push_back(
            {p.san(m),
             name(m.source) + name(m.target) + (m.promotion ? string(1, lower(m.promotion)) : ""),
             p.captured(m)});
        Position q = p.play(m);
        positions.push_back(q);
    }
    int repetition() const {
        string key = current().key();
        int n = 0;
        for (const Position &p : positions)
            n += p.key() == key;
        return n;
    }
    vector<string> draws() const {
        vector<string> a;
        if (current().half >= 100)
            a.push_back("fifty");
        if (repetition() >= 3)
            a.push_back("threefold");
        if (current().insufficient())
            a.push_back("insufficient");
        return a;
    }
    string result() const {
        string s = current().state();
        if (s == "checkmate")
            return current().side == 'b' ? "1-0" : "0-1";
        return s == "stalemate" || !draws().empty() ? "1/2-1/2" : "*";
    }
};
void execute(Game &g, const string &line) {
    vector<string> w = words(line);
    string cmd = w[0];
    vector<string> a(w.begin() + 1, w.end());
    const set<string> commands = {"NEW",    "LOAD",    "FEN",    "BOARD",   "MOVE",
                                  "UCI",    "LEGAL",   "STATUS", "UNDO",    "PERFT",
                                  "DIVIDE", "ATTACKS", "PINS",   "HISTORY", "PGN"};
    if (!commands.count(cmd)) {
        cout << "ERROR unknown command\n";
        return;
    }
    const set<string> noargs = {"NEW", "FEN", "BOARD", "STATUS", "PINS", "HISTORY", "PGN"};
    bool bad = noargs.count(cmd) && !a.empty();
    if (cmd == "MOVE" || cmd == "UCI")
        bad = a.empty();
    if (cmd == "LEGAL")
        bad = a.size() > 1 || (a.size() == 1 && square(a[0]) < 0);
    if (cmd == "ATTACKS")
        bad = a.size() != 1 || (a.size() == 1 && square(a[0]) < 0);
    int n = -1;
    if (cmd == "UNDO" || cmd == "PERFT" || cmd == "DIVIDE") {
        n = a.size() == 1 ? number(a[0], 1, cmd == "UNDO" ? 9999 : 3) : -1;
        bad = n < 0;
    }
    if (bad) {
        cout << "ERROR bad arguments\n";
        return;
    }
    const Position p = g.current();
    if (cmd == "NEW") {
        g = Game();
        cout << "OK\n";
    } else if (cmd == "LOAD") {
        try {
            Position q = parseFen(a);
            g = Game(q, true);
            cout << "OK\n";
        } catch (const runtime_error &e) {
            cout << "ERROR bad fen (" << e.what() << ")\n";
        }
    } else if (cmd == "FEN")
        cout << p.fen() << '\n';
    else if (cmd == "BOARD") {
        for (int r = 7; r >= 0; r--) {
            cout << r + 1;
            for (int f = 0; f < 8; f++)
                cout << ' ' << p.board[r * 8 + f];
            cout << '\n';
        }
        cout << "  a b c d e f g h\n";
    } else if (cmd == "MOVE" || cmd == "UCI") {
        vector<string> played;
        string failure;
        for (size_t i = 0; i < a.size(); i++) {
            try {
                Move m = cmd == "MOVE" ? readSan(g.current(), a[i]) : readUci(g.current(), a[i]);
                g.play(m);
                played.push_back(g.records.back().san);
            } catch (const runtime_error &e) {
                failure = "ILLEGAL move " + to_string(i + 1) + ": " + a[i] + " (" + e.what() + ")";
                break;
            }
        }
        if (cmd == "UCI" && !played.empty())
            cout << "san " << join(played) << '\n';
        if (!failure.empty())
            cout << failure << '\n';
        else if (cmd == "MOVE")
            cout << "OK\n";
    } else if (cmd == "LEGAL") {
        vector<string> list;
        for (Move m : p.legal())
            if (a.empty() || m.source == square(a[0]))
                list.push_back(p.san(m));
        sort(list.begin(), list.end());
        cout << "legal " << list.size();
        for (const string &s : list)
            cout << ' ' << s;
        cout << '\n';
    } else if (cmd == "STATUS") {
        cout << "status " << (p.side == 'w' ? "white" : "black") << ' ' << p.state() << " rep "
             << g.repetition();
        for (const string &s : g.draws())
            cout << ' ' << s;
        cout << '\n';
    } else if (cmd == "UNDO") {
        if (size_t(n) > g.records.size())
            cout << "ERROR cannot undo\n";
        else {
            g.records.resize(g.records.size() - n);
            g.positions.resize(g.positions.size() - n);
            cout << "OK\n";
        }
    } else if (cmd == "PERFT") {
        array<long long, 7> stats{};
        perft(p, n, &stats);
        cout << "perft " << n;
        vector<string> fields = {"nodes",      "captures", "ep",   "castles",
                                 "promotions", "checks",   "mates"};
        for (int i = 0; i < 7; i++)
            cout << ' ' << fields[i] << ' ' << stats[i];
        cout << '\n';
    } else if (cmd == "DIVIDE") {
        vector<pair<string, long long>> rows;
        long long total = 0;
        for (Move m : p.legal()) {
            long long v = perft(p.play(m), n - 1);
            rows.push_back({p.san(m), v});
            total += v;
        }
        sort(rows.begin(), rows.end());
        for (const auto &row : rows)
            cout << row.first << ' ' << row.second << '\n';
        cout << "total " << total << '\n';
    } else if (cmd == "ATTACKS") {
        cout << "attacks " << a[0];
        for (char c : {'w', 'b'}) {
            vector<int> found = attackers(p.board, square(a[0]), c);
            cout << ' ' << (c == 'w' ? "white" : "black") << ' ' << found.size();
            for (int s : found)
                cout << ' ' << name(s);
        }
        cout << '\n';
    } else if (cmd == "PINS") {
        vector<pair<int, int>> pins = p.pins();
        cout << "pins " << pins.size();
        for (auto [s, t] : pins)
            cout << ' ' << name(s) << '-' << name(t);
        cout << '\n';
    } else if (cmd == "HISTORY") {
        cout << "history " << g.records.size() << '\n';
        for (size_t i = 0; i < g.records.size(); i++) {
            const Record &r = g.records[i];
            cout << i + 1 << ' ' << r.uci << ' ' << r.san << ' ' << r.captured << '\n';
        }
    } else if (cmd == "PGN") {
        string result = g.result();
        cout << "[Result \"" << result << "\"]\n";
        if (g.loaded)
            cout << "[SetUp \"1\"]\n[FEN \"" << g.positions[0].fen() << "\"]\n";
        vector<string> text;
        for (size_t i = 0; i < g.records.size(); i++) {
            const Position &q = g.positions[i];
            if (q.side == 'w')
                text.push_back(to_string(q.full) + ".");
            else if (i == 0)
                text.push_back(to_string(q.full) + "...");
            text.push_back(g.records[i].san);
        }
        text.push_back(result);
        cout << join(text) << '\n';
    }
}
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    string line;
    getline(cin, line);
    Game game;
    while (n-- && getline(cin, line))
        execute(game, line);
}
