#include <algorithm>
#include <array>
#include <cctype>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using std::array;
using std::map;
using std::optional;
using std::set;
using std::string;
using std::vector;

constexpr array<const char*, 26> ADJACENT_KEYS = {
    "qswz", "ghnv", "dfvx", "cefrsx", "drsw", "cdgrtv", "bfhtvy", "bgjnuy",
    "jkou", "hikmnu", "ijlmo", "kop", "jkn", "bhjm", "iklp", "lo",
    "aw", "deft", "adewxz", "fgry", "hijy", "bcfg", "aeqs", "cdsz", "ghtu", "asx"
};
constexpr array<const char*, 6> COUNTER_NAMES = {
    "checked", "unknown", "case", "capital", "repeats", "corrected"
};

class CommandError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

bool isLetter(char ch) {
    return ('a' <= ch && ch <= 'z') || ('A' <= ch && ch <= 'Z');
}
bool isUpper(char ch) { return 'A' <= ch && ch <= 'Z'; }
bool isLower(char ch) { return 'a' <= ch && ch <= 'z'; }
char toLower(char ch) { return isUpper(ch) ? char(ch - 'A' + 'a') : ch; }
char toUpper(char ch) { return isLower(ch) ? char(ch - 'a' + 'A') : ch; }
string lower(string word) { for (char& ch : word) ch = toLower(ch); return word; }
string upper(string word) { for (char& ch : word) ch = toUpper(ch); return word; }
string capitalized(string word) { word[0] = toUpper(word[0]); return word; }

string wordArgument(const string& text) {
    if (text.empty() || text.size() > 30 || !std::all_of(text.begin(), text.end(), isLetter))
        throw CommandError("BAD WORD " + text);
    return lower(text);
}
int numberArgument(const string& text, int minimum, int maximum) {
    if (text.empty() || text.size() > 7 || !std::all_of(text.begin(), text.end(),
        [](char ch) { return '0' <= ch && ch <= '9'; }))
        throw CommandError("BAD NUMBER " + text);
    int number = std::stoi(text);
    if (number < minimum || number > maximum) throw CommandError("BAD NUMBER " + text);
    return number;
}
string decimalText(long long numerator, long long denominator, int digits) {
    const long long scale = digits == 1 ? 10 : 100;
    const long long rounded = (2 * numerator * scale + denominator) / (2 * denominator);
    string fraction = std::to_string(rounded % scale);
    fraction.insert(fraction.begin(), static_cast<std::size_t>(digits) - fraction.size(), '0');
    return std::to_string(rounded / scale) + "." + fraction;
}
string applyCase(const string& original, const string& word) {
    if (original.size() >= 2 && std::all_of(original.begin(), original.end(), isUpper)) return upper(word);
    if (isUpper(original[0])) return capitalized(word);
    return word;
}

struct Token {
    int number;
    string text, word, gap;
    std::size_t start, end;
    bool sentenceStart, repeated, mixedCase;
};
vector<Token> textTokens(const string& text) {
    vector<Token> result;
    std::size_t position = 0;
    while (position < text.size()) {
        std::size_t start = position;
        while (start < text.size() && !isLetter(text[start])) ++start;
        if (start == text.size()) break;
        std::size_t end = start;
        while (end < text.size() && isLetter(text[end])) ++end;
        string original = text.substr(start, end - start);
        string word = lower(original);
        string gap = text.substr(position, start - position);
        bool sentenceStart = result.empty() || gap.find_first_of(".!?") != string::npos;
        bool repeated = !result.empty() && result.back().word == word &&
                        std::all_of(gap.begin(), gap.end(), [](char ch) { return ch == ' '; });
        bool mixedCase = false, allUpper = std::all_of(original.begin(), original.end(), isUpper);
        for (std::size_t i = 1; i < original.size(); ++i) {
            if (isUpper(original[i]) && !allUpper) mixedCase = true;
        }
        result.push_back({int(result.size() + 1), original, word, gap, start, end,
                          sentenceStart, repeated, mixedCase});
        position = end;
    }
    return result;
}

int substitutionCost(char first, char second, bool keyboard) {
    if (first == second) return 0;
    if (!keyboard) return 1;
    return std::string_view(ADJACENT_KEYS[first - 'a']).find(second) != std::string_view::npos ? 1 : 2;
}
bool isSwap(const string& a, const string& b, int i, int j) {
    return i >= 2 && j >= 2 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1];
}
vector<vector<int>> distanceTable(const string& first, const string& second, bool keyboard) {
    int m = int(first.size()), n = int(second.size()), gap = keyboard ? 2 : 1;
    vector<vector<int>> dp(m + 1, vector<int>(n + 1, 0));
    for (int i = 0; i <= m; ++i) dp[i][0] = i * gap;
    for (int j = 0; j <= n; ++j) dp[0][j] = j * gap;
    for (int i = 1; i <= m; ++i) {
        for (int j = 1; j <= n; ++j) {
            int best = std::min({dp[i - 1][j] + gap, dp[i][j - 1] + gap,
                                 dp[i - 1][j - 1] + substitutionCost(first[i - 1], second[j - 1], keyboard)});
            if (isSwap(first, second, i, j)) best = std::min(best, dp[i - 2][j - 2] + 1);
            dp[i][j] = best;
        }
    }
    return dp;
}
int editDistance(const string& a, const string& b, bool keyboard) {
    return distanceTable(a, b, keyboard)[a.size()][b.size()];
}
int prefixDistance(const string& a, const string& b, bool keyboard) {
    const auto row = distanceTable(a, b, keyboard)[a.size()];
    return *std::min_element(row.begin(), row.end());
}
std::pair<int, vector<string>> editOperations(const string& first, const string& second, bool keyboard) {
    const auto dp = distanceTable(first, second, keyboard);
    const int gap = keyboard ? 2 : 1;
    int i = int(first.size()), j = int(second.size());
    vector<string> operations;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && dp[i][j] == dp[i - 1][j - 1] +
            substitutionCost(first[i - 1], second[j - 1], keyboard)) {
            if (first[i - 1] != second[j - 1])
                operations.push_back("sub:" + string(1, first[i - 1]) + ">" + string(1, second[j - 1]));
            --i; --j;
        } else if (isSwap(first, second, i, j) && dp[i][j] == dp[i - 2][j - 2] + 1) {
            operations.push_back("swap:" + first.substr(i - 2, 2));
            i -= 2; j -= 2;
        } else if (i > 0 && dp[i][j] == dp[i - 1][j] + gap) {
            operations.push_back("del:" + string(1, first[i - 1]));
            --i;
        } else {
            operations.push_back("ins:" + string(1, second[j - 1]));
            --j;
        }
    }
    std::reverse(operations.begin(), operations.end());
    return {dp[first.size()][second.size()], operations};
}

string soundex(const string& word) {
    static const array<char, 26> digits = [] {
        array<char, 26> values{};
        const array<string, 7> groups = {"bfpv", "cgjkqsxz", "dt", "l", "mn", "r", "aeiouy"};
        for (int i = 0; i < 7; ++i) {
            for (char ch : groups[i]) values[ch - 'a'] = i == 6 ? '0' : char('1' + i);
        }
        return values;
    }();
    string code(1, toUpper(word[0]));
    char previous = word[0] == 'h' || word[0] == 'w' ? '0' : digits[word[0] - 'a'];
    for (std::size_t i = 1; i < word.size(); ++i) {
        char ch = word[i];
        if (ch == 'h' || ch == 'w') continue;
        char digit = digits[ch - 'a'];
        if (digit != '0' && digit != previous) code.push_back(digit);
        previous = digit;
    }
    code.append("000");
    code.resize(4);
    return code;
}

struct Segmentation { long long ways; vector<string> best; };
Segmentation segment(const string& word, const map<string, int>& dictionary) {
    const int length = int(word.size());
    vector<long long> ways(length + 1, 0);
    vector<optional<vector<string>>> best(length + 1);
    ways[length] = 1;
    best[length] = vector<string>{};
    for (int start = length - 1; start >= 0; --start) {
        for (int end = start + 1; end <= length; ++end) {
            string piece = word.substr(start, end - start);
            if (!dictionary.contains(piece) || ways[end] == 0) continue;
            ways[start] += ways[end];
            vector<string> candidate = {piece};
            candidate.insert(candidate.end(), best[end]->begin(), best[end]->end());
            if (!best[start] || candidate.size() < best[start]->size() ||
                (candidate.size() == best[start]->size() && candidate < *best[start])) {
                best[start] = std::move(candidate);
            }
        }
    }
    return {ways[0], best[0].value_or(vector<string>{})};
}

string join(const vector<string>& parts, const string& separator = " ") {
    string result;
    for (const string& part : parts) {
        if (!result.empty()) result += separator;
        result += part;
    }
    return result;
}

struct Candidate {
    string word;
    int distance, frequency;
};
struct Snapshot {
    string name;
    map<string, int> dictionary;
    set<string> ignored;
    map<string, string> rules;
};

class SpellChecker {
    map<string, int> dictionary;
    set<string> ignored;
    map<string, string> rules;
    bool keyboard = false;
    int baseLimit = 2, suggestionCount = 5;
    vector<Snapshot> undoHistory;
    map<string, int> unknownLog, correctionLog;
    map<string, int> counters;
    vector<string> output;

    void emit(const string& text) { output.push_back(text); }
    void emit(const vector<string>& parts) { output.push_back(join(parts)); }
    int limit() const { return keyboard ? 2 * baseLimit : baseLimit; }
    bool isKnown(const string& word) const { return dictionary.contains(word) || ignored.contains(word); }

    vector<string> frequencyOrder() const {
        vector<string> words;
        for (const auto& [word, frequency] : dictionary) words.push_back(word);
        std::sort(words.begin(), words.end(), [this](const string& a, const string& b) {
            int af = dictionary.at(a), bf = dictionary.at(b);
            return af == bf ? a < b : af > bf;
        });
        return words;
    }

    int requireEntry(const string& word) const {
        auto found = dictionary.find(word);
        if (found == dictionary.end()) throw CommandError("NOT FOUND " + word);
        return found->second;
    }

    vector<Candidate> candidates(const string& word) const {
        vector<Candidate> found;
        int maximum = limit(), gap = keyboard ? 2 : 1;
        for (const auto& [other, frequency] : dictionary) {
            if (other == word || std::abs(int(other.size()) - int(word.size())) * gap > maximum) continue;
            int distance = editDistance(word, other, keyboard);
            if (distance <= maximum) found.push_back({other, distance, frequency});
        }
        std::sort(found.begin(), found.end(), [](const Candidate& a, const Candidate& b) {
            if (a.distance != b.distance) return a.distance < b.distance;
            if (a.frequency != b.frequency) return a.frequency > b.frequency;
            return a.word < b.word;
        });
        return found;
    }

    optional<string> correction(const string& word) const {
        if (isKnown(word)) return std::nullopt;
        if (auto iter = rules.find(word); iter != rules.end()) return iter->second;
        auto found = candidates(word);
        if (found.empty()) return std::nullopt;
        return found.front().word;
    }

    void recordUndo(const string& command) {
        undoHistory.push_back({command, dictionary, ignored, rules});
    }
    void logCorrection(const string& word, const string& replacement) {
        ++correctionLog[word + ">" + replacement];
        ++counters["corrected"];
    }

    string unknownFinding(const Token& token) const {
        string prefix = "UNKNOWN " + std::to_string(token.number) + " " + token.text;
        if (auto iter = rules.find(token.word); iter != rules.end())
            return prefix + " RULE " + iter->second;
        auto found = candidates(token.word);
        if (found.empty()) return prefix + " NONE";
        prefix += " SUGGEST";
        for (int i = 0; i < std::min(int(found.size()), suggestionCount); ++i)
            prefix += " " + found[i].word;
        return prefix;
    }

    void checkText(const string& text) {
        vector<Token> tokens = textTokens(text);
        vector<string> findings;
        map<string, int> counts;
        for (const Token& token : tokens) {
            if (!isKnown(token.word)) {
                findings.push_back(unknownFinding(token));
                ++unknownLog[token.word];
                ++counts["unknown"];
            }
            if (token.mixedCase) {
                findings.push_back("CASE " + std::to_string(token.number) + " " + token.text);
                ++counts["case"];
            }
            if (token.sentenceStart && isLower(token.text.front())) {
                findings.push_back("CAPITAL " + std::to_string(token.number) + " " + token.text);
                ++counts["capital"];
            }
            if (token.repeated) {
                findings.push_back("REPEAT " + std::to_string(token.number) + " " + token.text);
                ++counts["repeats"];
            }
        }
        counters["checked"] += int(tokens.size());
        string heading = "CHECK words=" + std::to_string(tokens.size());
        for (const string kind : {"unknown", "case", "capital", "repeats"}) {
            heading += " " + kind + "=" + std::to_string(counts[kind]);
            counters[kind] += counts[kind];
        }
        emit(heading);
        output.insert(output.end(), findings.begin(), findings.end());
    }

    void correctText(const string& text) {
        string result;
        std::size_t position = 0;
        int changed = 0;
        for (const Token& token : textTokens(text)) {
            result += token.gap;
            if (auto replacement = correction(token.word)) {
                result += applyCase(token.text, *replacement);
                logCorrection(token.word, *replacement);
                ++changed;
            } else {
                result += token.text;
            }
            position = token.end;
        }
        result += text.substr(position);
        emit("CORRECT changed=" + std::to_string(changed) + ": " + result);
    }

    void fixText(const string& text) {
        string result;
        std::size_t position = 0;
        int removed = 0, replaced = 0, recased = 0;
        for (const Token& token : textTokens(text)) {
            position = token.end;
            if (token.repeated) { ++removed; continue; }
            auto replacement = correction(token.word);
            string revised = applyCase(token.text, replacement.value_or(token.word));
            if (token.sentenceStart && isLower(revised.front())) revised = capitalized(revised);
            if (replacement) {
                logCorrection(token.word, *replacement);
                ++replaced;
            } else if (revised != token.text) {
                ++recased;
            }
            result += token.gap + revised;
        }
        result += text.substr(position);
        emit("FIX removed=" + std::to_string(removed) + " replaced=" +
             std::to_string(replaced) + " recased=" + std::to_string(recased) + ": " + result);
    }

    void profile(const string& text) {
        auto tokens = textTokens(text);
        set<string> distinct;
        int unknown = 0, sentences = 0, characters = 0;
        string longest = "-";
        for (const Token& token : tokens) {
            distinct.insert(token.word);
            if (!isKnown(token.word)) ++unknown;
            if (token.sentenceStart) ++sentences;
            characters += int(token.text.size());
            if (longest == "-" || token.text.size() > longest.size()) longest = token.word;
        }
        int n = int(tokens.size());
        string rate = n == 0 ? "0.0" : decimalText(100LL * unknown, n, 1);
        string average = n == 0 ? "0.00" : decimalText(characters, n, 2);
        emit("PROFILE words=" + std::to_string(n) + " distinct=" + std::to_string(distinct.size()) +
             " unknown=" + std::to_string(unknown) + " rate=" + rate + " avglen=" + average +
             " longest=" + longest + " sentences=" + std::to_string(sentences));
    }

    void learn(const string& text) {
        recordUndo("LEARN");
        int updated = 0, added = 0, skipped = 0;
        for (const Token& token : textTokens(text)) {
            if (token.word.size() > 30) {
                ++skipped;
            } else if (dictionary.contains(token.word)) {
                ++dictionary[token.word];
                ++updated;
            } else {
                dictionary[token.word] = 1;
                ignored.erase(token.word);
                ++added;
            }
        }
        emit("LEARN updated=" + std::to_string(updated) + " added=" +
             std::to_string(added) + " skipped=" + std::to_string(skipped));
    }

    void suggest(const vector<string>& args) {
        string word = wordArgument(args[0]);
        if (isKnown(word)) { emit("SUGGEST " + word + " KNOWN"); return; }
        if (auto iter = rules.find(word); iter != rules.end()) {
            emit("SUGGEST " + word + " RULE " + iter->second);
            return;
        }
        vector<Candidate> found = candidates(word);
        string result = "SUGGEST " + word + " found=" + std::to_string(found.size());
        for (int i = 0; i < std::min(int(found.size()), suggestionCount); ++i)
            result += " " + found[i].word + ":" + std::to_string(found[i].distance);
        emit(result);
    }

    void dist(const vector<string>& args) {
        string first = wordArgument(args[0]), second = wordArgument(args[1]);
        auto [distance, operations] = editOperations(first, second, keyboard);
        string result = "DIST " + first + " " + second + " " + std::to_string(distance);
        for (const string& operation : operations) result += " " + operation;
        emit(result);
    }

    void sounds(const vector<string>& args) {
        string word = wordArgument(args[0]), code = soundex(word);
        vector<string> matches;
        for (const string& other : frequencyOrder()) {
            if (other != word && soundex(other) == code) matches.push_back(other);
        }
        string result = "SOUNDS " + word + " " + code + " count=" + std::to_string(matches.size());
        for (int i = 0; i < std::min(int(matches.size()), 10); ++i) result += " " + matches[i];
        emit(result);
    }

    void split(const vector<string>& args) {
        string word = wordArgument(args[0]);
        auto [ways, best] = segment(word, dictionary);
        string result = "SPLIT " + word + " ways=" + std::to_string(ways) + " ->";
        if (ways == 0) result += " NONE";
        else for (const string& piece : best) result += " " + piece;
        emit(result);
    }

    void prefix(const vector<string>& args) {
        string word = wordArgument(args[0]);
        int count = numberArgument(args[1], 1, 20);
        vector<string> matches;
        for (const string& other : frequencyOrder()) {
            if (other.starts_with(word)) matches.push_back(other);
        }
        string result = "PREFIX " + word + " count=" + std::to_string(matches.size());
        for (int i = 0; i < std::min(int(matches.size()), count); ++i) {
            result += " " + matches[i] + ":" + std::to_string(dictionary[matches[i]]);
        }
        emit(result);
    }

    void complete(const vector<string>& args) {
        string word = wordArgument(args[0]);
        int count = numberArgument(args[1], 1, 20), threshold = limit() / 2;
        vector<Candidate> found;
        for (const auto& [other, frequency] : dictionary) {
            int distance = prefixDistance(word, other, keyboard);
            if (distance <= threshold) found.push_back({other, distance, frequency});
        }
        std::sort(found.begin(), found.end(), [](const Candidate& a, const Candidate& b) {
            if (a.distance != b.distance) return a.distance < b.distance;
            if (a.frequency != b.frequency) return a.frequency > b.frequency;
            return a.word < b.word;
        });
        string result = "COMPLETE " + word + " count=" + std::to_string(found.size());
        for (int i = 0; i < std::min(int(found.size()), count); ++i) {
            result += " " + found[i].word + ":" + std::to_string(found[i].distance);
        }
        emit(result);
    }

    void listWords(const vector<string>& args) {
        string word = wordArgument(args[0]);
        int count = numberArgument(args[1], 1, 20);
        vector<string> matches;
        for (auto iter = dictionary.lower_bound(word); iter != dictionary.end(); ++iter)
            matches.push_back(iter->first);
        string result = "LIST " + word + " count=" + std::to_string(matches.size());
        for (int i = 0; i < std::min(int(matches.size()), count); ++i)
            result += " " + matches[i] + ":" + std::to_string(dictionary.at(matches[i]));
        emit(result);
    }

    void wordInfo(const vector<string>& args) {
        string word = wordArgument(args[0]);
        int frequency = requireEntry(word);
        auto words = frequencyOrder();
        int rank = int(std::find(words.begin(), words.end(), word) - words.begin()) + 1;
        emit("WORD " + word + " freq=" + std::to_string(frequency) + " rank=" +
             std::to_string(rank) + " soundex=" + soundex(word) +
             " neighbors=" + std::to_string(candidates(word).size()));
    }

    void add(const vector<string>& args) {
        string word = wordArgument(args[0]);
        int frequency = numberArgument(args[1], 1, 1000000);
        if (dictionary.contains(word)) throw CommandError("DUPLICATE " + word);
        recordUndo("ADD");
        dictionary[word] = frequency;
        ignored.erase(word);
        emit("ADD " + word + " " + std::to_string(frequency));
    }

    void remove(const vector<string>& args) {
        string word = wordArgument(args[0]);
        int frequency = requireEntry(word);
        recordUndo("REMOVE");
        dictionary.erase(word);
        emit("REMOVE " + word + " " + std::to_string(frequency));
    }

    void ignore(const vector<string>& args) {
        string word = wordArgument(args[0]);
        if (dictionary.contains(word)) throw CommandError("IN DICTIONARY " + word);
        if (ignored.contains(word)) throw CommandError("ALREADY IGNORED " + word);
        recordUndo("IGNORE");
        ignored.insert(word);
        emit("IGNORE " + word);
    }

    void unignore(const vector<string>& args) {
        string word = wordArgument(args[0]);
        if (!ignored.contains(word)) throw CommandError("NOT IGNORED " + word);
        recordUndo("UNIGNORE");
        ignored.erase(word);
        emit("UNIGNORE " + word);
    }

    void rule(const vector<string>& args) {
        string source = wordArgument(args[0]), target = wordArgument(args[1]);
        if (dictionary.contains(source)) throw CommandError("IN DICTIONARY " + source);
        if (!dictionary.contains(target)) throw CommandError("NOT FOUND " + target);
        recordUndo("RULE");
        auto iter = rules.find(source);
        string previous = iter == rules.end() ? "" : iter->second;
        rules[source] = target;
        string result = "RULE " + source + " " + target;
        if (!previous.empty()) result += " REPLACED " + previous;
        emit(result);
    }

    void unrule(const vector<string>& args) {
        string word = wordArgument(args[0]);
        if (!rules.contains(word)) throw CommandError("NO RULE " + word);
        recordUndo("UNRULE");
        string previous = rules.at(word);
        rules.erase(word);
        emit("UNRULE " + word + " " + previous);
    }

    void showRules() {
        string result = "RULES count=" + std::to_string(rules.size());
        for (const auto& [source, target] : rules) result += " " + source + ">" + target;
        emit(result);
    }

    void keyboardMode(const vector<string>& args) {
        string mode = args[0];
        if (mode != "ON" && mode != "OFF") throw CommandError("BAD MODE " + mode);
        keyboard = mode == "ON";
        emit("KEYBOARD " + mode);
    }

    void setOption(const vector<string>& args) {
        string option = args[0];
        if (option != "LIMIT" && option != "SUGGESTIONS") throw CommandError("BAD OPTION " + option);
        int value = numberArgument(args[1], 1, option == "LIMIT" ? 3 : 10);
        if (option == "LIMIT") baseLimit = value;
        else suggestionCount = value;
        emit("SET " + option + " " + std::to_string(value));
    }

    void undo() {
        if (undoHistory.empty()) throw CommandError("NOTHING TO UNDO");
        Snapshot record = std::move(undoHistory.back());
        undoHistory.pop_back();
        dictionary = std::move(record.dictionary);
        ignored = std::move(record.ignored);
        rules = std::move(record.rules);
        emit("UNDO " + record.name);
    }

    void report() {
        vector<std::pair<string, int>> entries(unknownLog.begin(), unknownLog.end());
        std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
            return a.second != b.second ? a.second > b.second : a.first < b.first;
        });
        string result = "REPORT distinct=" + std::to_string(entries.size());
        for (int i = 0; i < std::min(int(entries.size()), 10); ++i)
            result += " " + entries[i].first + ":" + std::to_string(entries[i].second);
        emit(result);
    }

    void history() {
        vector<std::pair<string, int>> entries(correctionLog.begin(), correctionLog.end());
        std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
            return a.second != b.second ? a.second > b.second : a.first < b.first;
        });
        string result = "HISTORY distinct=" + std::to_string(entries.size());
        for (int i = 0; i < std::min(int(entries.size()), 10); ++i)
            result += " " + entries[i].first + ":" + std::to_string(entries[i].second);
        emit(result);
    }

    void stats() {
        auto words = frequencyOrder();
        const string& top = words.front();
        long long total = 0, characters = 0;
        for (const string& word : words) {
            total += dictionary.at(word);
            characters += word.size();
        }
        emit("STATS words=" + std::to_string(words.size()) + " total=" + std::to_string(total) +
             " avglen=" + decimalText(characters, words.size(), 2) +
             " top=" + top + ":" + std::to_string(dictionary.at(top)) +
             " ignored=" + std::to_string(ignored.size()) + " rules=" + std::to_string(rules.size()) +
             " keyboard=" + (keyboard ? "ON" : "OFF") + " limit=" + std::to_string(limit()) +
             " suggestions=" + std::to_string(suggestionCount) +
             " undo=" + std::to_string(undoHistory.size()));
        string session = "SESSION";
        for (const char* name : COUNTER_NAMES)
            session += " " + string(name) + "=" + std::to_string(counters[name]);
        emit(session);
    }

public:
    explicit SpellChecker(map<string, int> entries) : dictionary(std::move(entries)) {
        for (const char* name : COUNTER_NAMES) counters[name] = 0;
    }

    void execute(const string& line) {
        std::size_t space = line.find(' ');
        string command = space == string::npos ? line : line.substr(0, space);
        string rest = space == string::npos ? "" : line.substr(space + 1);
        try {
            if (command == "CHECK" || command == "CORRECT" || command == "FIX" ||
                command == "PROFILE" || command == "LEARN") {
                if (space == string::npos) throw CommandError("BAD ARGUMENTS " + command);
                if (command == "CHECK") checkText(rest);
                else if (command == "CORRECT") correctText(rest);
                else if (command == "FIX") fixText(rest);
                else if (command == "PROFILE") profile(rest);
                else learn(rest);
                return;
            }
            static const map<string, int> arities = {
                {"SUGGEST", 1}, {"DIST", 2}, {"SOUNDEX", 1}, {"SOUNDS", 1},
                {"SPLIT", 1}, {"PREFIX", 2}, {"COMPLETE", 2}, {"LIST", 2},
                {"WORD", 1}, {"ADD", 2}, {"REMOVE", 1}, {"IGNORE", 1},
                {"UNIGNORE", 1}, {"RULE", 2}, {"UNRULE", 1}, {"RULES", 0},
                {"KEYBOARD", 1}, {"SET", 2}, {"UNDO", 0}, {"REPORT", 0},
                {"HISTORY", 0}, {"STATS", 0}
            };
            auto found = arities.find(command);
            if (found == arities.end()) throw CommandError("UNKNOWN COMMAND " + command);
            vector<string> args;
            if (space != string::npos) {
                std::size_t start = 0;
                while (true) {
                    std::size_t next = rest.find(' ', start);
                    args.push_back(rest.substr(start, next == string::npos ? next : next - start));
                    if (next == string::npos) break;
                    start = next + 1;
                }
            }
            if (int(args.size()) != found->second) throw CommandError("BAD ARGUMENTS " + command);
            if (command == "SUGGEST") suggest(args);
            else if (command == "DIST") dist(args);
            else if (command == "SOUNDEX") {
                string word = wordArgument(args[0]);
                emit("SOUNDEX " + word + " " + soundex(word));
            }
            else if (command == "SOUNDS") sounds(args);
            else if (command == "SPLIT") split(args);
            else if (command == "PREFIX") prefix(args);
            else if (command == "COMPLETE") complete(args);
            else if (command == "LIST") listWords(args);
            else if (command == "WORD") wordInfo(args);
            else if (command == "ADD") add(args);
            else if (command == "REMOVE") remove(args);
            else if (command == "IGNORE") ignore(args);
            else if (command == "UNIGNORE") unignore(args);
            else if (command == "RULE") rule(args);
            else if (command == "UNRULE") unrule(args);
            else if (command == "RULES") showRules();
            else if (command == "KEYBOARD") keyboardMode(args);
            else if (command == "SET") setOption(args);
            else if (command == "UNDO") undo();
            else if (command == "REPORT") report();
            else if (command == "HISTORY") history();
            else if (command == "STATS") stats();
        } catch (const CommandError& error) {
            emit("ERROR " + string(error.what()));
        }
    }

    void print() const {
        for (const string& line : output) std::cout << line << '\n';
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    map<string, int> dictionary;
    for (int i = 0; i < count; ++i) {
        string word;
        int frequency;
        std::cin >> word >> frequency;
        dictionary[word] = frequency;
    }
    SpellChecker checker(std::move(dictionary));
    int commands;
    std::cin >> commands;
    string line;
    std::getline(std::cin, line);
    for (int i = 0; i < commands; ++i) {
        std::getline(std::cin, line);
        checker.execute(line);
    }
    checker.print();
}
