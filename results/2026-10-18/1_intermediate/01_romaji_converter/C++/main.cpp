#include <algorithm>
#include <array>
#include <iostream>
#include <stdexcept>
#include <utility>
#include <string>
#include <vector>

using std::string;
using std::vector;

struct Mora {
    string id, row, dan;
    std::array<string, 5> spelling;
    int base, voice;
};
struct Token { int id, col; };
struct Word {
    string original;
    int start, end, section, pattern;
    vector<Token> tokens;
};
struct Element { int id, voice, size; };
const vector<string> systems = {"HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO"};
const vector<string> rows = {"a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa", "ga", "za", "da", "ba", "pa"};
vector<Mora> table;
int longMode = 0, caseMode = 0, orderMode = 0;
const int N = 108, Q = 109, L = 110;

bool letter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool vowel(char c) { return c != '\0' && string("aiueo").find(c) != string::npos; }
bool wordChar(char c) { return letter(c) || c == '\'' || c == '-'; }
char lower(char c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }
char upper(char c) { return c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c; }
string lowerText(string s) {
    for (char &c : s) c = lower(c);
    return s;
}
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
int lookup(const vector<string> &items, const string &s) {
    vector<string>::const_iterator it = std::find(items.begin(), items.end(), s);
    return it == items.end() ? -1 : int(it - items.begin());
}
int moraId(const string &s) {
    for (int i = 0; i < int(table.size()); ++i) {
        if (table[i].id == s) return i;
    }
    return N;
}
void initialize() {
    const vector<string> base = {
        "a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
        "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo",
        "ra ri ru re ro", "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo",
        "da di du de do", "ba bi bu be bo", "pa pi pu pe po"
    };
    const int baseRows[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3, 5, 5};
    for (int r = 0; r < 15; ++r) {
        for (const string &id : split(base[r])) {
            table.push_back({id, rows[r], string(1, id.back()), {}, baseRows[r], r >= 10 ? (r == 14 ? 2 : 1) : 0});
        }
    }
    const int contractedRows[] = {1, 2, 3, 4, 5, 6, 8, 10, 11, 12, 13, 14};
    for (int r : contractedRows) {
        for (const string &dan : vector<string>{"ya", "yu", "yo"}) {
            string id = rows[r].substr(0, 1) + dan;
            table.push_back({id, rows[r], dan, {}, baseRows[r], r >= 10 ? (r == 14 ? 2 : 1) : 0});
        }
    }
    const vector<string> special = {"si", "ti", "tu", "hu", "zi", "di", "du", "wi", "we", "wo"};
    const vector<string> hepburn = {"shi", "chi", "tsu", "fu", "ji", "ji", "zu", "i", "e", "o"};
    for (Mora &m : table) {
        for (int s = 0; s < 5; ++s) {
            string spelling = m.id;
            int k = lookup(special, m.id);
            if (s <= 1 && k >= 0) spelling = hepburn[k];
            if (s == 4 && k >= 0 && k < 5) spelling = hepburn[k];
            if (s == 2) {
                const vector<string> from = {"di", "du", "wi", "we", "wo", "dya", "dyu", "dyo"};
                const vector<string> to = {"zi", "zu", "i", "e", "o", "zya", "zyu", "zyo"};
                k = lookup(from, m.id);
                if (k >= 0) spelling = to[k];
            }
            if (m.dan.size() == 2 && (s <= 1 || s == 4)) {
                string prefix = m.id.substr(0, 2);
                if (prefix == "sy") spelling = "sh" + m.id.substr(2);
                if (prefix == "ty") spelling = "ch" + m.id.substr(2);
                if (prefix == "zy" || (prefix == "dy" && s <= 1)) spelling = "j" + m.id.substr(2);
            }
            m.spelling[s] = spelling;
        }
    }
}
[[noreturn]] void fail(const string &message) { throw std::runtime_error(message); }
[[noreturn]] void columnError(int col, const string &message) {
    fail("col " + std::to_string(col) + ": " + message);
}
vector<Word> lex(const string &text) {
    vector<Word> words;
    int section = 0;
    for (int i = 0; i < int(text.size());) {
        if (!wordChar(text[i])) {
            if (text[i] == '/') ++section;
            ++i;
            continue;
        }
        int start = i;
        while (i < int(text.size()) && wordChar(text[i])) ++i;
        words.push_back({text.substr(start, i - start), start, i, section, 0, {}});
    }
    return words;
}
void checkCase(Word &w) {
    bool allLower = true, allUpper = true, title = w.original[0] >= 'A' && w.original[0] <= 'Z';
    int letters = 0;
    for (int i = 0; i < int(w.original.size()); ++i) {
        char c = w.original[i];
        if (!letter(c)) continue;
        ++letters;
        if (c != lower(c)) allLower = false;
        if (c != upper(c)) allUpper = false;
        if (i > 0 && c != lower(c)) title = false;
    }
    if (allLower) w.pattern = 0;
    else if (title) w.pattern = 1;
    else if (letters >= 2 && allUpper) w.pattern = 2;
    else columnError(w.start + 1, "mixed case");
}
std::pair<int, int> match(const string &s, int pos, int system) {
    int id = -1, length = 0;
    for (int i = 0; i < 108; ++i) {
        for (int t = 0; t < 5; ++t) {
            if (system >= 0 && t != system) continue;
            const string &p = table[i].spelling[t];
            if (int(p.size()) > length && s.compare(pos, p.size(), p) == 0) {
                id = i;
                length = int(p.size());
            }
        }
    }
    return {id, length};
}
void parse(Word &w, int system) {
    w.tokens.clear();
    string s = lowerText(w.original);
    for (int p = 0; p < int(s.size());) {
        char c = s[p], c2 = p + 1 < int(s.size()) ? s[p + 1] : '\0';
        int id = -1, advance = 1;
        if (c == '-') {
            if (w.tokens.empty() || w.tokens.back().id >= N) columnError(w.start + p + 1, "misplaced long mark");
            id = L;
        } else if (c == '\'') {
            columnError(w.start + p + 1, "misplaced apostrophe");
        } else {
            std::pair<int, int> found = match(s, p, system);
            if (found.first >= 0) {
                id = found.first;
                advance = found.second;
            } else if ((system == 4 || system < 0) && s.compare(p, 3, "xtu") == 0) {
                id = Q;
                advance = 3;
            } else if (c == 'n') {
                id = N;
                if (system < 0) {
                    char c3 = p + 2 < int(s.size()) ? s[p + 2] : '\0';
                    if (c2 == '\'' || (c2 == 'n' && !vowel(c3) && c3 != 'y' && c3 != '\'')) advance = 2;
                } else if ((system == 4 && c2 == 'n') || (system != 4 && c2 == '\'')) advance = 2;
            } else if ((system == 1 || system < 0) && c == 'm' && c2 && string("bmp").find(c2) != string::npos) {
                id = N;
            } else if (letter(c) && !vowel(c) && c != 'n' && c2 == c && match(s, p + 1, system).first >= 0) {
                id = Q;
            } else if ((system <= 1 || system < 0) && c == 't' && s.compare(p + 1, 2, "ch") == 0 && match(s, p + 1, system).first >= 0) {
                id = Q;
            } else columnError(w.start + p + 1, "unknown syllable");
        }
        w.tokens.push_back({id, w.start + p + 1});
        p += advance;
    }
}
vector<bool> pairs(const vector<Token> &tokens) {
    vector<bool> result(tokens.size(), false);
    for (int i = 0; i + 1 < int(tokens.size());) {
        int a = tokens[i].id, b = tokens[i + 1].id;
        if (a < N && b < 5) {
            char x = table[a].id.back(), y = table[b].id[0];
            if (x == y || (x == 'o' && y == 'u') || (x == 'e' && y == 'i')) {
                result[i + 1] = true;
                i += 2;
                continue;
            }
        }
        ++i;
    }
    return result;
}
vector<bool> longs(const vector<Token> &tokens) {
    vector<bool> result = pairs(tokens);
    for (int i = 0; i < int(tokens.size()); ++i) {
        if (tokens[i].id == L) result[i] = true;
        else if (result[i]) {
            char x = table[tokens[i - 1].id].id.back(), y = table[tokens[i].id].id[0];
            result[i] = (x == 'o' && (y == 'o' || y == 'u')) || (x == 'u' && y == 'u');
        }
    }
    return result;
}
vector<string> parts(const Word &w, int system, int mode) {
    vector<bool> longElements = longs(w.tokens);
    vector<string> result;
    for (int i = 0; i < int(w.tokens.size()); ++i) {
        int id = w.tokens[i].id;
        int nextId = i + 1 < int(w.tokens.size()) ? w.tokens[i + 1].id : -1;
        string next = nextId >= 0 && nextId < N ? table[nextId].spelling[system] : "";
        char first = next.empty() ? '\0' : next[0];
        string s;
        if (longElements[i]) {
            char v = table[w.tokens[i - 1].id].id.back();
            if (mode == 0) s = id == L ? "-" : table[id].spelling[system];
            if (mode == 2 && v == 'o' && !vowel(first)) s = "h";
            if (mode == 3) s = "-";
            if (mode == 4) s = string(1, v);
        } else if (id < N) s = table[id].spelling[system];
        else if (id == N) {
            if (system == 4) s = nextId == N || vowel(first) || first == 'y' || first == 'n' ? "nn" : "n";
            else if (system == 1 && first && string("bmp").find(first) != string::npos) s = "m";
            else s = vowel(first) || first == 'y' ? "n'" : "n";
        } else if (id == Q) {
            if (first && !vowel(first) && first != 'n') s = system <= 1 && next.compare(0, 2, "ch") == 0 ? "t" : string(1, first);
            else if (system == 4) s = "xtu";
            else columnError(w.tokens[i].col, "small tsu cannot be written");
        }
        result.push_back(s);
    }
    return result;
}
string write(const Word &w, int system, bool canonical = false) {
    string result = join(parts(w, system, canonical ? 0 : longMode), "");
    int pattern = canonical || caseMode == 0 ? w.pattern : caseMode == 1 ? 0 : caseMode == 2 ? 2 : 1;
    if (pattern == 1 && !result.empty()) result[0] = upper(result[0]);
    if (pattern == 2) for (char &c : result) c = upper(c);
    return result;
}
vector<int> sequence(const Word &w, bool loose = false) {
    vector<bool> omit = longs(w.tokens);
    vector<int> result;
    for (int i = 0; i < int(w.tokens.size()); ++i) {
        if (!loose || !omit[i]) result.push_back(w.tokens[i].id);
    }
    return result;
}
vector<Element> elements(const Word &w) {
    vector<Element> result;
    for (Token t : w.tokens) {
        if (t.id == L) continue;
        if (t.id == N) result.push_back({N, 0, 0});
        else if (t.id == Q) result.push_back({moraId("tu"), 0, 1});
        else {
            const Mora &m = table[t.id];
            string base = m.id;
            if (m.voice) base[0] = string("ksthh")[lookup(vector<string>{"ga", "za", "da", "ba", "pa"}, m.row)];
            if (m.dan.size() == 2) {
                result.push_back({moraId(base.substr(0, 1) + "i"), m.voice, 0});
                result.push_back({moraId(m.dan), 0, 1});
            } else result.push_back({moraId(base), m.voice, 0});
        }
    }
    return result;
}
vector<vector<int>> key(const Word &w) {
    string order = orderMode == 0
        ? "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N"
        : "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N";
    vector<string> rank = split(order);
    vector<vector<int>> result(4);
    for (Element e : elements(w)) {
        result[0].push_back(lookup(rank, e.id == N ? "N" : table[e.id].id));
        result[1].push_back(e.voice);
        result[2].push_back(e.size);
    }
    for (Token t : w.tokens) result[3].push_back(t.id == L ? 1 : 0);
    return result;
}
vector<int> patternTokens(const string &pattern, int system) {
    vector<int> result;
    string fragment;
    for (int i = 0; i <= int(pattern.size()); ++i) {
        char c = i == int(pattern.size()) ? '\0' : pattern[i];
        if (!c || c == '?' || c == '*') {
            if (!fragment.empty()) {
                Word w{fragment, 0, int(fragment.size()), 0, 0, {}};
                try { parse(w, system); }
                catch (const std::runtime_error &) { fail("invalid pattern"); }
                for (Token t : w.tokens) result.push_back(t.id);
                fragment.clear();
            }
            if (c) result.push_back(c == '?' ? -1 : -2);
        } else {
            if (!((c >= 'a' && c <= 'z') || c == '\'' || c == '-')) fail("invalid pattern");
            fragment += c;
        }
    }
    return result;
}
bool glob(const vector<int> &pattern, const Word &w) {
    vector<bool> dp(w.tokens.size() + 1, false);
    dp[0] = true;
    for (int p : pattern) {
        vector<bool> next(dp.size(), false);
        if (p == -2) {
            next[0] = dp[0];
            for (int j = 1; j < int(dp.size()); ++j) next[j] = dp[j] || next[j - 1];
        } else {
            for (int j = 1; j < int(dp.size()); ++j) next[j] = dp[j - 1] && (p == -1 || p == w.tokens[j - 1].id);
        }
        dp = next;
    }
    return dp.back();
}
string process(const string &line) {
    const vector<string> names = {"SET", "TABLE", "CONVERT", "NORMALIZE", "REVERSE", "VALID", "DETECT", "DIFF", "SAME", "MORAE", "SYLLABLES", "ROW", "STATS", "SORT", "INDEX", "FIND", "HAIKU", "KAIBUN", "SHIRITORI"};
    const int fixed[] = {2, 2, 2, 0, 1, 1, 0, 2, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1};
    std::size_t firstSpace = line.find(' ');
    string command = line.substr(0, firstSpace);
    int cmd = lookup(names, command);
    if (cmd < 0) fail("unknown command " + command);
    vector<string> args;
    string text;
    if (cmd <= 1) {
        vector<string> fields = split(line);
        if (fields.size() < 3) fail("missing argument");
        if (fields.size() > 3) fail("too many arguments");
        args.assign(fields.begin() + 1, fields.end());
    } else {
        std::size_t pos = 0;
        for (int i = 0; i <= fixed[cmd]; ++i) {
            std::size_t end = line.find(' ', pos);
            if (end == string::npos) fail("missing argument");
            if (i > 0) args.push_back(line.substr(pos, end - pos));
            pos = end + 1;
        }
        text = line.substr(pos);
    }
    if (cmd == 0) {
        int option = lookup(vector<string>{"LONG", "CASE", "ORDER"}, args[0]);
        if (option < 0) fail("unknown option " + args[0]);
        const vector<vector<string>> values = {{"KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"}, {"KEEP", "LOWER", "UPPER", "TITLE"}, {"GOJUON", "IROHA"}};
        int value = lookup(values[option], args[1]);
        if (value < 0) fail("unknown value " + args[1]);
        if (option == 0) longMode = value;
        if (option == 1) caseMode = value;
        if (option == 2) orderMode = value;
        return args[0] + "=" + args[1];
    }
    int systemCount = cmd == 3 || cmd == 6 ? 0 : cmd == 2 || cmd == 7 || cmd == 8 ? 2 : 1;
    vector<int> sys;
    for (int i = 0; i < systemCount; ++i) {
        int s = lookup(systems, args[i]);
        if (s < 0) fail("unknown system " + args[i]);
        sys.push_back(s);
    }
    int source = sys.empty() ? -1 : sys[0];
    if (cmd == 1) {
        if (lookup(rows, args[1]) < 0) fail("unknown row " + args[1]);
        vector<string> result;
        for (const Mora &m : table) if (m.row == args[1]) result.push_back(m.spelling[source]);
        return join(result, " ");
    }
    vector<int> pattern;
    if (cmd == 15) pattern = patternTokens(args[1], source);
    bool slash = cmd == 8 || cmd == 16;
    for (int i = 0; i < int(text.size()); ++i) {
        char c = text[i];
        if (!wordChar(c) && !(c >= '0' && c <= '9') && string(" .,!?;:()\"").find(c) == string::npos && !(slash && c == '/')) columnError(i + 1, "invalid character");
    }
    vector<Word> words = lex(text);
    int sections = int(std::count(text.begin(), text.end(), '/')) + 1;
    vector<int> counts(sections, 0);
    for (const Word &w : words) ++counts[w.section];
    if (cmd == 8 && (sections != 2 || counts[0] == 0 || counts[1] == 0)) fail("expected two texts");
    if (cmd == 16 && ((sections != 3 && sections != 5) || std::find(counts.begin(), counts.end(), 0) != counts.end())) fail("expected 3 or 5 lines");
    if (words.empty()) fail("no words");
    for (Word &w : words) checkCase(w);
    if (cmd == 6) {
        vector<string> verdicts;
        for (int s = 0; s < 5; ++s) {
            string verdict = "canonical";
            try {
                vector<Word> parsed = words;
                for (Word &w : parsed) parse(w, s);
                for (const Word &w : parsed) if (write(w, s, true) != w.original) verdict = "readable";
            } catch (const std::runtime_error &) { verdict = "error"; }
            verdicts.push_back(systems[s] + "=" + verdict);
        }
        return join(verdicts, " ");
    }
    for (Word &w : words) parse(w, cmd == 8 && w.section == 1 ? sys[1] : source);
    if (cmd == 2 || cmd == 3 || cmd == 4) {
        string result;
        int pos = 0;
        for (Word w : words) {
            result += text.substr(pos, w.start - pos);
            if (cmd == 4) {
                for (int i = 0; i < int(w.tokens.size()); ++i) {
                    if (w.tokens[i].id == L) w.tokens[i].id = moraId(string(1, table[w.tokens[i - 1].id].id.back()));
                }
                std::reverse(w.tokens.begin(), w.tokens.end());
            }
            result += write(w, cmd == 2 ? sys[1] : cmd == 3 ? 0 : source);
            pos = w.end;
        }
        return result + text.substr(pos);
    }
    if (cmd == 5) {
        for (const Word &w : words) {
            string canonical = write(w, source, true);
            if (canonical != w.original) {
                int i = 0;
                while (i < int(canonical.size()) && i < int(w.original.size()) && canonical[i] == w.original[i]) ++i;
                return "INVALID col " + std::to_string(w.start + i + 1) + ": expected " + canonical;
            }
        }
        return "VALID";
    }
    if (cmd == 7 || cmd == 15) {
        vector<string> selected;
        for (const Word &w : words) {
            if (cmd == 7) {
                string a = write(w, source), b = write(w, sys[1]);
                if (a != b) selected.push_back(a + ">" + b);
            } else if (glob(pattern, w)) selected.push_back(w.original);
        }
        string result = std::to_string(selected.size()) + " of " + std::to_string(words.size());
        if (!selected.empty()) result += ": " + join(selected, " ");
        return result;
    }
    if (cmd == 8) {
        vector<Word> left, right;
        for (const Word &w : words) (w.section == 0 ? left : right).push_back(w);
        bool exact = true;
        for (int i = 0; i < int(std::min(left.size(), right.size())); ++i) {
            if (sequence(left[i], true) != sequence(right[i], true)) return "DIFFERENT at word " + std::to_string(i + 1);
            if (sequence(left[i]) != sequence(right[i])) exact = false;
        }
        if (left.size() != right.size()) return "DIFFERENT at word " + std::to_string(std::min(left.size(), right.size()) + 1);
        return exact ? "EXACT" : "LOOSE";
    }
    if (cmd == 9 || cmd == 10) {
        vector<string> output;
        int total = 0;
        for (const Word &w : words) {
            vector<string> pieces;
            if (cmd == 9) {
                for (Token t : w.tokens) pieces.push_back(t.id < N ? table[t.id].spelling[source] : t.id == N ? "N" : t.id == Q ? "Q" : "-");
            } else {
                vector<string> canonical = parts(w, source, 0);
                vector<bool> paired = pairs(w.tokens);
                for (int i = 0; i < int(w.tokens.size()); ++i) {
                    if (i > 0 && (w.tokens[i].id >= N || paired[i])) pieces.back() += canonical[i];
                    else pieces.push_back(canonical[i]);
                }
            }
            total += int(pieces.size());
            output.push_back(join(pieces, "."));
        }
        return std::to_string(total) + ": " + join(output, " ");
    }
    if (cmd == 11) {
        vector<string> output;
        for (const Word &w : words) {
            for (Token t : w.tokens) {
                if (t.id < N) {
                    const Mora &m = table[t.id];
                    output.push_back(m.spelling[source] + ": " + m.row + " " + m.dan);
                } else output.push_back(string(t.id == N ? "N" : t.id == Q ? "Q" : "-") + ": special");
            }
        }
        return join(output, ", ");
    }
    if (cmd == 12) {
        std::array<int, 10> rowCounts{};
        std::array<int, 6> other{};
        int total = 0;
        for (const Word &w : words) {
            for (Token t : w.tokens) {
                ++total;
                if (t.id < N) {
                    const Mora &m = table[t.id];
                    ++rowCounts[m.base];
                    if (m.voice) ++other[m.voice - 1];
                    if (m.dan.size() == 2) ++other[2];
                } else ++other[t.id - N + 3];
            }
        }
        vector<string> output = {"morae=" + std::to_string(total)};
        for (int r = 0; r < 10; ++r) if (rowCounts[r]) output.push_back(rows[r] + "=" + std::to_string(rowCounts[r]));
        vector<string> labels = {"voiced", "semivoiced", "contracted", "N", "Q", "L"};
        for (int i = 0; i < 6; ++i) output.push_back(labels[i] + "=" + std::to_string(other[i]));
        return join(output, " ");
    }
    if (cmd == 13 || cmd == 14) {
        std::stable_sort(words.begin(), words.end(), [](const Word &a, const Word &b) { return key(a) < key(b); });
        vector<string> output;
        string previous;
        for (const Word &w : words) {
            if (cmd == 13) output.push_back(w.original);
            else {
                int id = elements(w)[0].id;
                string heading = id == N ? "N" : orderMode == 1 ? table[id].id : table[id].row;
                if (heading == previous) output.back() += " " + w.original;
                else output.push_back(heading + ": " + w.original);
                previous = heading;
            }
        }
        return join(output, cmd == 13 ? " " : "; ");
    }
    if (cmd == 16) {
        vector<int> counts(sections, 0);
        for (const Word &w : words) counts[w.section] += int(w.tokens.size());
        vector<int> expected = sections == 3 ? vector<int>{5, 7, 5} : vector<int>{5, 7, 5, 7, 7};
        vector<string> numbers;
        for (int c : counts) numbers.push_back(std::to_string(c));
        return string(counts == expected ? "OK " : "NG ") + (sections == 3 ? "haiku " : "tanka ") + join(numbers, "-");
    }
    if (cmd == 17) {
        vector<int> kana;
        vector<string> output;
        for (const Word &w : words) {
            for (Element e : elements(w)) {
                kana.push_back(e.id);
                output.push_back(e.id == N ? "N" : table[e.id].id);
            }
        }
        vector<int> reversed = kana;
        std::reverse(reversed.begin(), reversed.end());
        return string(kana == reversed ? "YES " : "NO ") + join(output, ".");
    }
    int previousTail = -1;
    for (int i = 0; i < int(words.size()); ++i) {
        const Word &w = words[i];
        vector<Element> e = elements(w);
        string prefix = "NG " + std::to_string(i + 1) + ": " + w.original;
        if (i && e[0].id != previousTail) return prefix + " must start with " + table[previousTail].spelling[source];
        for (int j = 0; j < i; ++j) if (sequence(w) == sequence(words[j])) return prefix + " is repeated";
        previousTail = e.back().id;
        if (previousTail == N) return prefix + " ends with N";
    }
    return "OK " + std::to_string(words.size());
}
int main() {
    initialize();
    string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        try { std::cout << process(line) << '\n'; }
        catch (const std::runtime_error &error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
