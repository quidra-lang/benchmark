#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using std::string;
using std::vector;
using Integer = std::int64_t;
struct Cue {
    Integer index, start, end;
    vector<string> text;
};
struct Record {
    string command;
    vector<Cue> cues;
};
struct Arguments {
    string name;
    vector<string> raw;
    vector<Integer> values;
    Integer denominator = 1;
};
struct Markup {
    int kind;
    string text;
    int digit;
};
vector<Cue> cues;
vector<Record> history;

[[noreturn]] void fail(const string &message) { throw std::runtime_error(message); }
vector<string> split(const string &s, char delimiter, int limit = 0) {
    vector<string> result;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || (s[i] == delimiter && (!limit || int(result.size()) + 1 < limit))) {
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
bool begins(const string &s, const string &prefix) { return s.compare(0, prefix.size(), prefix) == 0; }
string trim(const string &s) {
    std::size_t first = s.find_first_not_of(' ');
    return first == string::npos ? "" : s.substr(first, s.find_last_not_of(' ') - first + 1);
}
bool unsignedValue(const string &s, Integer &value) {
    if (s.empty() || s.size() > 9) return false;
    value = 0;
    for (char c : s) {
        if (c < '0' || c > '9') return false;
        value = value * 10 + c - '0';
    }
    return true;
}
bool timeValue(const string &s, Integer &value) {
    if (s.size() != 12 || s[2] != ':' || s[5] != ':' || s[8] != ',') return false;
    for (int i = 0; i < 12; ++i) {
        if (i != 2 && i != 5 && i != 8 && (s[i] < '0' || s[i] > '9')) return false;
    }
    Integer h = std::stoll(s.substr(0, 2)), m = std::stoll(s.substr(3, 2));
    Integer sec = std::stoll(s.substr(6, 2)), ms = std::stoll(s.substr(9));
    value = h * 3600000 + m * 60000 + sec * 1000 + ms;
    return m <= 59 && sec <= 59;
}
string timeText(Integer t, int kind = 0) {
    std::ostringstream out;
    out << std::setfill('0');
    if (kind == 2) {
        Integer c = (t + 5) / 10;
        out << c / 360000 << ':' << std::setw(2) << c / 6000 % 60 << ':'
            << std::setw(2) << c / 100 % 60 << '.' << std::setw(2) << c % 100;
    } else {
        out << std::setw(2) << t / 3600000 << ':' << std::setw(2) << t / 60000 % 60 << ':'
            << std::setw(2) << t / 1000 % 60 << (kind == 1 ? '.' : ',') << std::setw(3) << t % 1000;
    }
    return out.str();
}
string decimal(Integer value) {
    return std::to_string(value / 100) + "." + (value % 100 < 10 ? "0" : "") + std::to_string(value % 100);
}
Integer floorRatio(Integer a, Integer b) {
    if (b < 0) {
        a = -a;
        b = -b;
    }
    Integer q = a / b;
    if (a % b < 0) --q;
    return q;
}
Integer halfUp(Integer a, Integer b) {
    if (b < 0) {
        a = -a;
        b = -b;
    }
    return floorRatio(2 * a + b, 2 * b);
}
Integer countChars(const Cue &cue) {
    return std::accumulate(cue.text.begin(), cue.text.end(), Integer(0),
        [](Integer total, const string &line) { return total + Integer(line.size()); });
}
bool dialogue(const Cue &cue) {
    return std::any_of(cue.text.begin(), cue.text.end(), [](const string &line) { return begins(line, "- "); });
}
vector<string> words(const vector<string> &lines) {
    vector<string> result;
    for (const string &line : lines) {
        for (const string &word : split(line, ' ')) if (!word.empty()) result.push_back(word);
    }
    return result;
}
vector<string> wrap(const vector<string> &lines, int width) {
    vector<string> result;
    for (const string &word : words(lines)) {
        if (result.empty() || int(result.back().size() + 1 + word.size()) > width) result.push_back(word);
        else result.back() += " " + word;
    }
    return result;
}
vector<Markup> scanMarkup(const string &line) {
    const vector<string> tags = {"<i>", "</i>", "<b>", "</b>", "<u>", "</u>"};
    vector<Markup> result;
    for (std::size_t p = 0; p < line.size();) {
        int size = 1, kind = 0, digit = 0;
        for (const string &tag : tags) {
            if (line.compare(p, tag.size(), tag) == 0) {
                size = int(tag.size());
                kind = 1;
                break;
            }
        }
        if (!kind && line.compare(p, 7, "</font>") == 0) {
            size = 7;
            kind = 2;
        }
        if (!kind && line.compare(p, 5, "<font") == 0 && p + 5 < line.size() && (line[p + 5] == ' ' || line[p + 5] == '>')) {
            std::size_t end = line.find('>', p + 5);
            if (end != string::npos) {
                size = int(end - p + 1);
                kind = 2;
            }
        }
        if (!kind && p + 6 <= line.size() && line.compare(p, 4, "{\\an") == 0 && line[p + 4] >= '1' && line[p + 4] <= '9' && line[p + 5] == '}') {
            size = 6;
            kind = 3;
            digit = line[p + 4] - '0';
        }
        result.push_back({kind, line.substr(p, size), digit});
        p += size;
    }
    return result;
}
vector<string> converted(const vector<string> &lines, int mode, int &first, int &removed) {
    vector<string> result;
    first = removed = 0;
    const vector<string> tags = {"<i>", "</i>", "<b>", "</b>", "<u>", "</u>"};
    const vector<string> ass = {"{\\i1}", "{\\i0}", "{\\b1}", "{\\b0}", "{\\u1}", "{\\u0}"};
    for (const string &line : lines) {
        string output;
        for (const Markup &m : scanMarkup(line)) {
            if (m.kind == 3 && !first) first = m.digit;
            if (mode == 0) {
                if (!m.kind) output += m.text;
                else ++removed;
            } else if (mode == 1) {
                if (m.kind == 1) output += m.text;
                if (!m.kind) {
                    if (m.text == "&") output += "&amp;";
                    else if (m.text == "<") output += "&lt;";
                    else if (m.text == ">") output += "&gt;";
                    else output += m.text;
                }
            } else {
                if (m.kind == 1) output += ass[std::find(tags.begin(), tags.end(), m.text) - tags.begin()];
                if (m.kind == 0 || m.kind == 3) output += m.text;
            }
        }
        if (mode != 2) output = trim(output);
        if (mode == 2 || !output.empty()) result.push_back(output);
    }
    return result;
}
string normalize(const string &line) { return join(words(vector<string>{line}), " "); }
string cleanHI(const string &line, int &segments, int &labels) {
    string output;
    segments = labels = 0;
    for (std::size_t p = 0; p < line.size();) {
        std::size_t end = string::npos;
        if (line[p] == '[') end = line.find(']', p + 1);
        if (line[p] == '(') end = line.find(')', p + 1);
        if (end != string::npos) {
            ++segments;
            p = end + 1;
        }
        else output += line[p++];
    }
    string text = normalize(output), prefix, body = text;
    if (begins(body, "- ")) {
        prefix = "- ";
        body = body.substr(2);
    }
    std::size_t colon = body.find(':');
    if (colon != string::npos && colon > 0) {
        string label = body.substr(0, colon);
        bool valid = label[0] >= 'A' && label[0] <= 'Z';
        for (char c : label) {
            if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == ' ')) valid = false;
        }
        if (valid) {
            labels = 1;
            text = normalize(prefix + body.substr(colon + 1));
        }
    }
    return text;
}
Arguments parseArguments(const string &line) {
    const vector<string> names = {"LIST", "VALIDATE", "SEARCH", "AT", "GAPS", "STATS", "PRINT", "TOVTT", "TOASS", "FRAMES", "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP", "FIXOVERLAP", "EXTEND", "TIME", "SORT", "RENUMBER", "MERGE", "SPLIT", "INSERT", "DELETE", "TEXT", "BALANCE", "STRIP", "CLEANHI", "REPLACE", "UNDO"};
    const vector<string> schemas = {"", "", "S", "T", "U", "", "", "", "", "F", "I", "PI", "UU", "PTPT", "F", "U", "U", "PTT", "", "", "U", "U", "PTTX", "P", "PX", "", "", "", "R", ""};
    std::size_t space = line.find(' ');
    string name = line.substr(0, space);
    vector<string>::const_iterator found = std::find(names.begin(), names.end(), name);
    if (found == names.end()) fail("unknown command");
    string schema = schemas[found - names.begin()];
    Arguments a;
    a.name = name;
    if (space != string::npos) a.raw = split(line.substr(space + 1), ' ', schema.find_first_of("SXR") != string::npos ? int(schema.size()) : 0);
    if (name == "DELETE" && a.raw.size() == 2) schema = "PP";
    if (a.raw.size() != schema.size()) fail("bad arguments");
    a.values.resize(a.raw.size());
    for (int i = 0; i < int(schema.size()); ++i) {
        string s = a.raw[i];
        bool valid = true;
        Integer value = 0;
        char kind = schema[i];
        if (kind == 'P' || kind == 'U') {
            valid = unsignedValue(s, value);
            if (kind == 'P' && value == 0) valid = false;
        } else if (kind == 'I') {
            bool negative = begins(s, "-");
            valid = unsignedValue(negative ? s.substr(1) : s, value);
            if (negative) value = -value;
        } else if (kind == 'T') valid = timeValue(s, value);
        else if (kind == 'F') {
            vector<string> parts = split(s, '/');
            if (parts.size() > 2) valid = false;
            else {
                valid = unsignedValue(parts[0], value);
                if (parts.size() == 2) valid = unsignedValue(parts[1], a.denominator) && valid;
                valid = valid && value >= 1 && value <= 100000 && a.denominator >= 1 && a.denominator <= 100000;
            }
        } else if (kind == 'X') {
            for (const string &part : split(s, '|')) if (part.empty()) valid = false;
        } else if (kind == 'R') {
            vector<string> parts = split(s, '|');
            valid = parts.size() == 2 && !parts[0].empty() && !parts[1].empty();
        } else if (kind == 'S') valid = !s.empty();
        if (!valid) fail("bad arguments");
        a.values[i] = value;
    }
    const vector<Integer> &v = a.values;
    if (name == "SCALE" && (v[0] < 1 || v[0] > 100000 || v[1] < 1 || v[1] > 100000)) fail("bad arguments");
    if (name == "GAPS" || name == "FIXOVERLAP" || name == "MERGE" || name == "EXTEND") {
        if (v[0] < (name == "EXTEND" ? 1 : 0) || v[0] > 60000) fail("bad arguments");
    }
    if (name == "SPLIT" && (v[0] < 10 || v[0] > 80)) fail("bad arguments");
    if (name == "DELETE" && v.size() == 2 && v[1] < v[0]) fail("bad arguments");
    Integer limit = Integer(cues.size()) + (name == "INSERT" ? 1 : 0);
    for (int i = 0; i < int(schema.size()); ++i) {
        if (schema[i] == 'P' && v[i] > limit) fail("no cue " + std::to_string(v[i]));
    }
    return a;
}
string cueLine(int position, const Cue &c) {
    return std::to_string(position) + " " + std::to_string(c.index) + " " + timeText(c.start) + " " + timeText(c.end) + " " + join(c.text, "|");
}
template <typename... Values> string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
vector<string> execute(const string &line) {
    Arguments a = parseArguments(line);
    const string &name = a.name;
    const vector<Integer> &v = a.values;
    int n = int(cues.size());
    vector<string> out;
    if (name == "UNDO") {
        if (history.empty()) fail("nothing to undo");
        Record previous = std::move(history.back());
        history.pop_back();
        cues = std::move(previous.cues);
        return {"UNDO command=" + previous.command};
    }
    if (name == "SYNC" && cues[v[0] - 1].start == cues[v[2] - 1].start) fail("sync points coincide");
    const string modifying = " SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE ";
    if (modifying.find(" " + name + " ") != string::npos) history.push_back({name, cues});
    if (name == "LIST" || name == "AT") {
        int matches = 0;
        for (int i = 0; i < n; ++i) {
            if (name == "LIST" || (cues[i].start <= v[0] && v[0] < cues[i].end)) {
                out.push_back(cueLine(i + 1, cues[i]));
                ++matches;
            }
        }
        if (name == "AT") out.push_back(text("AT active=", matches));
    } else if (name == "VALIDATE") {
        for (int i = 0; i < n; ++i) {
            const Cue &c = cues[i];
            string prefix = text("cue ", i + 1, ": ");
            Integer d = c.end - c.start;
            if (c.index != i + 1) out.push_back(text(prefix, "index ", c.index, " (expected ", i + 1, ")"));
            if (d <= 0) out.push_back(prefix + "end not after start");
            if (i && c.start < cues[i - 1].end) out.push_back(text(prefix, "overlaps previous by ", cues[i - 1].end - c.start, " ms"));
            if (d >= 1 && d < 700) out.push_back(text(prefix, "too short (", d, " ms)"));
            if (d > 7000) out.push_back(text(prefix, "too long (", d, " ms)"));
            for (int j = 0; j < int(c.text.size()); ++j) {
                if (c.text[j].size() > 42) out.push_back(text(prefix, "line ", j + 1, " too long (", c.text[j].size(), " chars)"));
            }
            if (c.text.size() >= 3) out.push_back(text(prefix, "too many lines (", c.text.size(), ")"));
            Integer chars = countChars(c);
            if (d >= 1 && chars * 1000 > 21 * d) out.push_back(prefix + "too fast (" + decimal(chars * 100000 / d) + " cps)");
        }
        out.push_back(text("VALIDATE problems=", out.size()));
    } else if (name == "SEARCH") {
        for (int i = 0; i < n; ++i) {
            for (const string &line : cues[i].text) {
                if (line.find(a.raw[0]) != string::npos) {
                    out.push_back(text(i + 1, " ", timeText(cues[i].start), " ", line));
                    break;
                }
            }
        }
        out.push_back(text("SEARCH found=", out.size()));
    } else if (name == "GAPS") {
        for (int i = 0; i + 1 < n; ++i) {
            Integer gap = cues[i + 1].start - cues[i].end;
            if (gap < v[0]) out.push_back(text(i + 1, " ", i + 2, " ", gap));
        }
        out.push_back(text("GAPS count=", out.size()));
    } else if (name == "STATS") {
        out.push_back(text("STATS cues=", n));
        if (!n) return out;
        Integer total = 0, chars = 0, longest = 0;
        int longestPosition = 1;
        for (int i = 0; i < n; ++i) {
            Integer d = std::max(Integer(0), cues[i].end - cues[i].start);
            total += d;
            if (d) chars += countChars(cues[i]);
            if (d > longest) {
                longest = d;
                longestPosition = i + 1;
            }
        }
        out.push_back("duration total=" + timeText(total) + " mean=" + timeText(total / n));
        out.push_back("speed " + (total ? decimal(chars * 100000 / total) : "-"));
        out.push_back(text("longest cue=", longestPosition, " duration=", timeText(longest)));
        if (n == 1) out.push_back("gap none");
        else {
            int position = 1;
            Integer gap = cues[1].start - cues[0].end;
            for (int i = 1; i + 1 < n; ++i) {
                Integer candidate = cues[i + 1].start - cues[i].end;
                if (candidate > gap) {
                    gap = candidate;
                    position = i + 1;
                }
            }
            out.push_back(text("gap cue=", position, " ms=", gap));
        }
    } else if (name == "PRINT" || name == "TOVTT") {
        if (name == "TOVTT") out.insert(out.end(), {"WEBVTT", ""});
        for (const Cue &c : cues) {
            int code = 0, removed = 0, kind = name == "TOVTT" ? 1 : 0;
            vector<string> convertedLines;
            if (kind) convertedLines = converted(c.text, 1, code, removed);
            const vector<string> &lines = kind ? convertedLines : c.text;
            if (lines.empty()) continue;
            string setting;
            if (code >= 7) setting = " line:0";
            else if (code >= 4) setting = " line:50%";
            if (code && code % 3 == 1) setting += " align:start";
            if (code && code % 3 == 0) setting += " align:end";
            out.push_back(std::to_string(c.index));
            out.push_back(timeText(c.start, kind) + " --> " + timeText(c.end, kind) + setting);
            out.insert(out.end(), lines.begin(), lines.end());
            out.push_back("");
        }
    } else if (name == "TOASS") {
        out = {"[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"};
        for (const Cue &c : cues) {
            int code, removed;
            vector<string> lines = converted(c.text, 2, code, removed);
            out.push_back("Dialogue: 0," + timeText(c.start, 2) + "," + timeText(c.end, 2) + ",Default,,0,0,0,," + join(lines, "\\N"));
        }
    } else if (name == "FRAMES") {
        for (int i = 0; i < n; ++i) out.push_back(text(i + 1, " ", cues[i].start * v[0] / (1000 * a.denominator), " ", cues[i].end * v[0] / (1000 * a.denominator)));
    } else if (name == "SHIFT" || name == "SHIFTFROM" || name == "SYNC" || name == "SCALE" || name == "SNAP") {
        int start = name == "SHIFTFROM" ? int(v[0] - 1) : 0;
        Integer shift = name == "SHIFT" ? v[0] : name == "SHIFTFROM" ? v[1] : 0;
        Integer s1 = 0, s2 = 0;
        if (name == "SYNC") {
            s1 = cues[v[0] - 1].start;
            s2 = cues[v[2] - 1].start;
        }
        int clamped = 0, changed = 0;
        for (int i = start; i < n; ++i) {
            bool cueClamped = false;
            for (Integer *t : {&cues[i].start, &cues[i].end}) {
                Integer old = *t, value = old;
                if (name == "SHIFT" || name == "SHIFTFROM") value += shift;
                if (name == "SCALE") value = halfUp(value * v[0], v[1]);
                if (name == "SYNC") value = halfUp(v[1] * (s2 - s1) + (value - s1) * (v[3] - v[1]), s2 - s1);
                if (name == "SNAP") {
                    Integer frame = halfUp(value * v[0], 1000 * a.denominator);
                    value = halfUp(frame * 1000 * a.denominator, v[0]);
                }
                if (value < 0) {
                    value = 0;
                    cueClamped = true;
                }
                if (old != value) ++changed;
                *t = value;
            }
            if (cueClamped) ++clamped;
        }
        if (name == "SNAP") out.push_back(text("SNAP changed=", changed));
        else if (name == "SCALE") out.push_back(text("SCALE cues=", n));
        else out.push_back(text(name, " cues=", n - start, " clamped=", clamped));
    } else if (name == "FIXOVERLAP") {
        int fixed = 0, failed = 0;
        for (int i = 0; i + 1 < n; ++i) {
            Integer candidate = cues[i + 1].start - v[0];
            if (cues[i].end > candidate) {
                if (candidate > cues[i].start) {
                    cues[i].end = candidate;
                    ++fixed;
                } else {
                    ++failed;
                    out.push_back(text("cue ", i + 1, ": cannot fix"));
                }
            }
        }
        out.push_back(text("FIXOVERLAP fixed=", fixed, " failed=", failed));
    } else if (name == "EXTEND") {
        int extended = 0, shortCount = 0;
        for (int i = 0; i < n; ++i) {
            if (cues[i].end - cues[i].start < v[0]) {
                Integer candidate = cues[i].start + v[0];
                if (i + 1 < n) candidate = std::min(candidate, cues[i + 1].start);
                if (candidate > cues[i].end) {
                    cues[i].end = candidate;
                    ++extended;
                }
            }
            if (cues[i].end - cues[i].start < v[0]) ++shortCount;
        }
        out.push_back(text("EXTEND extended=", extended, " short=", shortCount));
    } else if (name == "TIME") {
        cues[v[0] - 1].start = v[1];
        cues[v[0] - 1].end = v[2];
        out.push_back(text("TIME cue=", v[0]));
    } else if (name == "SORT") {
        vector<int> order(n);
        std::iota(order.begin(), order.end(), 0);
        std::stable_sort(order.begin(), order.end(), [](int i, int j) {
            if (cues[i].start != cues[j].start) return cues[i].start < cues[j].start;
            return cues[i].end < cues[j].end;
        });
        vector<Cue> sorted;
        int moved = 0;
        for (int i = 0; i < n; ++i) {
            sorted.push_back(std::move(cues[order[i]]));
            if (i != order[i]) ++moved;
        }
        cues = std::move(sorted);
        out.push_back(text("SORT moved=", moved));
    } else if (name == "RENUMBER") {
        int changed = 0;
        for (int i = 0; i < n; ++i) {
            if (cues[i].index != i + 1) ++changed;
            cues[i].index = i + 1;
        }
        out.push_back(text("RENUMBER changed=", changed));
    } else if (name == "MERGE") {
        vector<Cue> result;
        int merged = 0;
        for (Cue &c : cues) {
            if (!result.empty()) {
                Cue &previous = result.back();
                if (c.start - previous.end < v[0] && !dialogue(previous) && !dialogue(c)) {
                    vector<string> lines = previous.text;
                    lines.insert(lines.end(), c.text.begin(), c.text.end());
                    vector<string> wrapped = wrap(lines, 42);
                    if (wrapped.size() <= 2) {
                        previous.end = std::max(previous.end, c.end);
                        previous.text = std::move(wrapped);
                        ++merged;
                        continue;
                    }
                }
            }
            result.push_back(std::move(c));
        }
        cues = std::move(result);
        out.push_back(text("MERGE merged=", merged, " cues=", cues.size()));
    } else if (name == "SPLIT") {
        vector<Cue> result;
        int splitCount = 0;
        for (Cue &c : cues) {
            Integer d = c.end - c.start;
            if (d < 1 || dialogue(c)) {
                result.push_back(std::move(c));
                continue;
            }
            vector<string> wrapped = wrap(c.text, int(v[0]));
            if (wrapped.size() <= 2) {
                c.text = std::move(wrapped);
                result.push_back(std::move(c));
                continue;
            }
            ++splitCount;
            vector<Cue> parts;
            Integer total = 0;
            for (int i = 0; i < int(wrapped.size()); i += 2) {
                Cue part{c.index, 0, 0, {wrapped[i]}};
                if (i + 1 < int(wrapped.size())) part.text.push_back(wrapped[i + 1]);
                total += countChars(part);
                parts.push_back(std::move(part));
            }
            vector<Integer> lengths(parts.size()), remainders(parts.size());
            vector<int> order(parts.size());
            Integer remaining = d;
            for (int i = 0; i < int(parts.size()); ++i) {
                Integer product = d * countChars(parts[i]);
                lengths[i] = product / total;
                remainders[i] = product % total;
                remaining -= lengths[i];
                order[i] = i;
            }
            std::stable_sort(order.begin(), order.end(), [&](int i, int j) { return remainders[i] > remainders[j]; });
            for (int i = 0; i < remaining; ++i) ++lengths[order[i]];
            Integer start = c.start;
            for (int i = 0; i < int(parts.size()); ++i) {
                parts[i].start = start;
                parts[i].end = start + lengths[i];
                start += lengths[i];
                result.push_back(std::move(parts[i]));
            }
        }
        cues = std::move(result);
        out.push_back(text("SPLIT split=", splitCount, " cues=", cues.size()));
    } else if (name == "INSERT") {
        cues.insert(cues.begin() + v[0] - 1, Cue{v[0], v[1], v[2], split(a.raw[3], '|')});
        out.push_back(text("INSERT cue=", v[0], " cues=", cues.size()));
    } else if (name == "DELETE") {
        int p = int(v[0] - 1), q = int(v.size() == 2 ? v[1] : v[0]);
        cues.erase(cues.begin() + p, cues.begin() + q);
        out.push_back(text("DELETE removed=", q - p, " cues=", cues.size()));
    } else if (name == "TEXT") {
        cues[v[0] - 1].text = split(a.raw[1], '|');
        out.push_back(text("TEXT cue=", v[0], " lines=", cues[v[0] - 1].text.size()));
    } else if (name == "BALANCE") {
        int changed = 0, skipped = 0, dialogues = 0;
        for (Cue &c : cues) {
            if (dialogue(c)) {
                ++dialogues;
                continue;
            }
            vector<string> w = words(c.text), candidate;
            string all = join(w, " ");
            if (all.size() <= 42) candidate.push_back(all);
            else if (all.size() <= 85) {
                int bestDifference = 1000000, bestFirst = 1000000;
                for (int j = 1; j < int(w.size()); ++j) {
                    string first = join(vector<string>(w.begin(), w.begin() + j), " ");
                    string second = join(vector<string>(w.begin() + j, w.end()), " ");
                    int difference = std::abs(int(first.size()) - int(second.size()));
                    if (first.size() <= 42 && second.size() <= 42 && (difference < bestDifference || (difference == bestDifference && int(first.size()) < bestFirst))) {
                        candidate = {first, second};
                        bestDifference = difference;
                        bestFirst = int(first.size());
                    }
                }
            }
            if (candidate.empty()) ++skipped;
            else {
                if (candidate != c.text) ++changed;
                c.text = std::move(candidate);
            }
        }
        out.push_back(text("BALANCE changed=", changed, " skipped=", skipped, " dialogue=", dialogues));
    } else if (name == "STRIP" || name == "CLEANHI") {
        int removedItems = 0, labels = 0, removedLines = 0, removedCues = 0;
        vector<Cue> result;
        for (Cue &c : cues) {
            vector<string> lines;
            if (name == "STRIP") {
                int first, tags;
                lines = converted(c.text, 0, first, tags);
                removedItems += tags;
                removedLines += int(c.text.size() - lines.size());
            } else {
                for (const string &line : c.text) {
                    int segments, names;
                    string cleaned = cleanHI(line, segments, names);
                    removedItems += segments;
                    labels += names;
                    if (cleaned.empty() || cleaned == "-") ++removedLines;
                    else lines.push_back(cleaned);
                }
            }
            if (lines.empty()) ++removedCues;
            else {
                c.text = std::move(lines);
                result.push_back(std::move(c));
            }
        }
        cues = std::move(result);
        if (name == "STRIP") out.push_back(text("STRIP tags=", removedItems, " removed_lines=", removedLines, " removed_cues=", removedCues));
        else out.push_back(text("CLEANHI segments=", removedItems, " labels=", labels, " removed_lines=", removedLines, " removed_cues=", removedCues));
    } else if (name == "REPLACE") {
        vector<string> parts = split(a.raw[0], '|');
        int count = 0, matchingCues = 0;
        for (Cue &c : cues) {
            int matches = 0;
            for (string &line : c.text) {
                string result;
                std::size_t p = 0, found;
                while ((found = line.find(parts[0], p)) != string::npos) {
                    result += line.substr(p, found - p) + parts[1];
                    p = found + parts[0].size();
                    ++matches;
                }
                line = result + line.substr(p);
            }
            count += matches;
            if (matches) ++matchingCues;
        }
        out.push_back(text("REPLACE count=", count, " cues=", matchingCues));
    }
    return out;
}
string loadBlock(const vector<string> &block, int position) {
    Integer index, start = 0, end = 0;
    if (!unsignedValue(block[0], index) || block[0].size() > 6) return text("BAD CUE ", position, ": index");
    bool valid = block.size() >= 2 && block[1].size() == 29 && block[1].substr(12, 5) == " --> ";
    if (valid) valid = timeValue(block[1].substr(0, 12), start) && timeValue(block[1].substr(17), end);
    if (!valid) return text("BAD CUE ", position, ": time");
    if (block.size() < 3) return text("BAD CUE ", position, ": no text");
    cues.push_back({index, start, end, vector<string>(block.begin() + 2, block.end())});
    return "";
}
int main() {
    string line;
    vector<string> block;
    int blocks = 0, bad = 0;
    while (std::getline(std::cin, line)) {
        if (line.empty() || line == "###") {
            if (!block.empty()) {
                string message = loadBlock(block, ++blocks);
                if (!message.empty()) {
                    std::cout << message << '\n';
                    ++bad;
                }
                block.clear();
            }
            if (line == "###") break;
        } else block.push_back(line);
    }
    std::cout << "LOAD cues=" << cues.size() << " bad=" << bad << '\n';
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            vector<string> output = execute(line);
            for (const string &result : output) std::cout << result << '\n';
        } catch (const std::runtime_error &error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
