#include <algorithm>
#include <array>
#include <functional>
#include <iostream>
#include <map>
#include <optional>
#include <regex>
#include <set>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;
using Fields = map<string, string>;
enum class Style { APA, IEEE, Chicago, MLA };

const map<string, vector<string>> requiredFields = {
    {"article", {"author", "title", "journal", "year"}},
    {"book", {"author", "title", "publisher", "year"}},
    {"inproceedings", {"author", "title", "booktitle", "year"}},
    {"incollection", {"author", "title", "booktitle", "publisher", "year"}},
    {"techreport", {"author", "title", "institution", "year"}},
    {"phdthesis", {"author", "title", "school", "year"}},
    {"misc", {"author", "title", "year"}}
};
const vector<string> fieldOrder = {"author", "editor", "title", "journal", "booktitle", "edition",
    "volume", "number", "pages", "publisher", "institution", "school", "address", "howpublished",
    "month", "year", "doi", "note"};
const set<string> knownFields(fieldOrder.begin(), fieldOrder.end());
const set<string> smallWords = {"a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into",
    "nor", "of", "on", "or", "over", "per", "so", "the", "to", "up", "via", "with", "yet"};
const array<string, 12> monthNames = {"January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"};
const array<string, 12> monthAbbreviations = {"Jan.", "Feb.", "Mar.", "Apr.", "May", "June",
    "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec."};

bool isLetter(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
bool isDigit(char c) { return c >= '0' && c <= '9'; }
bool allDigits(const string& s) { return !s.empty() && all_of(s.begin(), s.end(), isDigit); }
char lowerChar(char c) { return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c; }
char upperChar(char c) { return c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c; }
string lower(string s) { transform(s.begin(), s.end(), s.begin(), lowerChar); return s; }
string plain(string s) {
    s.erase(remove_if(s.begin(), s.end(), [](char c) { return c == '{' || c == '}'; }), s.end());
    return s;
}
string letters(const string& s) {
    string result;
    for (char c : s) if (isLetter(c)) result += lowerChar(c);
    return result;
}
string trim(const string& s) {
    auto begin = s.find_first_not_of(' ');
    return begin == string::npos ? "" : s.substr(begin, s.find_last_not_of(' ') - begin + 1);
}
string join(const vector<string>& parts, const string& separator) {
    string result;
    for (size_t i = 0; i < parts.size(); ++i) {
        if (i) result += separator;
        result += parts[i];
    }
    return result;
}
vector<string> split(const string& s, const string& delimiter) {
    vector<string> result;
    size_t start = 0, end;
    while ((end = s.find(delimiter, start)) != string::npos) {
        result.push_back(s.substr(start, end - start));
        start = end + delimiter.size();
    }
    result.push_back(s.substr(start));
    return result;
}
vector<string> splitDepthZero(const string& s, const string& delimiter) {
    vector<string> result;
    int depth = 0;
    size_t start = 0, i = 0;
    while (i < s.size()) {
        if (depth == 0 && s.compare(i, delimiter.size(), delimiter) == 0) {
            result.push_back(s.substr(start, i - start));
            i += delimiter.size();
            start = i;
        } else {
            if (s[i] == '{') ++depth;
            if (s[i] == '}') --depth;
            ++i;
        }
    }
    result.push_back(s.substr(start));
    return result;
}
string joinRange(const vector<string>& words, size_t begin, size_t end) {
    return join(vector<string>(words.begin() + begin, words.begin() + end), " ");
}

struct Accent { char result; size_t length; };
optional<Accent> accentAt(const string& s, size_t i) {
    if (i + 1 >= s.size() || s[i] != '\\') return nullopt;
    if (s[i + 1] == '&') return Accent{'&', 2};
    if (i + 2 < s.size() && string("'\"`^~=.").find(s[i + 1]) != string::npos && isLetter(s[i + 2]))
        return Accent{s[i + 2], 3};
    if (i + 4 < s.size() && string("'\"`^~=.cuvH").find(s[i + 1]) != string::npos &&
        s[i + 2] == '{' && isLetter(s[i + 3]) && s[i + 4] == '}') return Accent{s[i + 3], 5};
    return nullopt;
}
string normalize(const string& s) {
    string accents;
    for (size_t i = 0; i < s.size();) {
        auto enclosed = s[i] == '{' ? accentAt(s, i + 1) : nullopt;
        if (enclosed && i + enclosed->length + 1 < s.size() && s[i + enclosed->length + 1] == '}') {
            accents += enclosed->result;
            i += enclosed->length + 2;
        } else if (auto accent = accentAt(s, i)) {
            accents += accent->result;
            i += accent->length;
        } else accents += s[i++];
    }
    string result;
    bool space = false;
    for (char c : accents) {
        if (c == '~' || c == ' ') space = !result.empty();
        else {
            if (space) result += ' ';
            result += c;
            space = false;
        }
    }
    return result;
}
string evaluateExpression(const string& expression, const Fields& macros) {
    int depth = 0;
    for (char c : expression) {
        if (c == '{') ++depth;
        if (c == '}') --depth;
        if (depth < 0) throw runtime_error("unbalanced braces");
    }
    if (depth != 0) throw runtime_error("unbalanced braces");
    string result;
    for (const string& term : split(expression, " # ")) {
        if (term.front() == '{' || term.front() == '"') result += term.substr(1, term.size() - 2);
        else if (allDigits(term)) result += term;
        else {
            auto found = macros.find(term);
            if (found == macros.end()) throw runtime_error("unknown macro '" + term + "'");
            result += found->second;
        }
    }
    return result;
}

struct Person {
    string first, von, last, jr;

    explicit Person(const string& text) {
        vector<string> parts = splitDepthZero(text, ",");
        for (auto& part : parts) part = trim(part);
        vector<string> words = splitDepthZero(parts[0], " ");
        vector<size_t> lowercase;
        for (size_t i = 0; i + 1 < words.size(); ++i)
            if (!words[i].empty() && words[i][0] >= 'a' && words[i][0] <= 'z') lowercase.push_back(i);
        if (parts.size() == 1) {
            size_t start = lowercase.empty() ? words.size() - 1 : lowercase.front();
            size_t end = lowercase.empty() ? words.size() - 1 : lowercase.back() + 1;
            first = joinRange(words, 0, start);
            von = joinRange(words, start, end);
            last = joinRange(words, end, words.size());
        } else {
            size_t end = lowercase.empty() ? 0 : lowercase.back() + 1;
            von = joinRange(words, 0, end);
            last = joinRange(words, end, words.size());
            first = parts.back();
            if (parts.size() == 3) jr = parts[1];
        }
    }
    bool operator==(const Person& other) const {
        return tie(first, von, last, jr) == tie(other.first, other.von, other.last, other.jr);
    }
    string surname() const { return plain(von.empty() ? last : von + " " + last); }
    string initials() const {
        string given = plain(first);
        if (given.empty()) return "";
        vector<string> words;
        for (const string& word : split(given, " ")) {
            vector<string> pieces;
            for (const string& piece : split(word, "-")) {
                auto letter = find_if(piece.begin(), piece.end(), isLetter);
                pieces.push_back(string(1, upperChar(*letter)) + ".");
            }
            words.push_back(join(pieces, "-"));
        }
        return join(words, " ");
    }
    string format(bool inverted, bool useInitials) const {
        string given = useInitials ? initials() : plain(first), result = surname();
        if (!first.empty()) result = inverted ? result + ", " + given : given + " " + result;
        if (!jr.empty()) result += ", " + plain(jr);
        return result;
    }
};
struct NameList {
    vector<Person> names;
    bool etAl;
    explicit NameList(const string& text) {
        auto parts = splitDepthZero(text, " and ");
        etAl = parts.back() == "others";
        if (etAl) parts.pop_back();
        for (const string& part : parts) names.emplace_back(part);
    }
    bool singular() const { return names.size() == 1 && !etAl; }
    bool operator==(const NameList& other) const { return etAl == other.etAl && names == other.names; }
};
struct Entry {
    string key, type;
    Fields fields;
    optional<NameList> author, editor;
    string sortTitle, suffix;
    Entry(string key, string type, Fields fields) : key(move(key)), type(move(type)), fields(move(fields)) {
        if (this->fields.count("author")) author.emplace(this->fields.at("author"));
        if (this->fields.count("editor")) editor.emplace(this->fields.at("editor"));
        sortTitle = lower(value("title"));
        for (const string& prefix : {"a ", "an ", "the "}) {
            if (sortTitle.compare(0, prefix.size(), prefix) == 0) { sortTitle.erase(0, prefix.size()); break; }
        }
    }
    string value(const string& name) const {
        auto found = fields.find(name);
        return found == fields.end() ? "" : plain(found->second);
    }
    const NameList& primary() const { return author ? *author : *editor; }
    auto sortKey() const { return make_tuple(lower(plain(primary().names[0].last)), value("year"), sortTitle, key); }
    string yearLabel(Style style) const { return value("year") + (style == Style::APA || style == Style::Chicago ? suffix : ""); }
    vector<string> unknownFields() const {
        vector<string> result;
        for (const auto& [name, value] : fields) if (!knownFields.count(name)) result.push_back(name);
        return result;
    }
};
bool bibliographyLess(const Entry* a, const Entry* b) { return a->sortKey() < b->sortKey(); }

class Database {
public:
    vector<Entry> entries;
    map<string, size_t> byKey;
    vector<const Entry*> bibliography;

    Database(const vector<string>& lines, vector<string>& output) {
        Fields macros;
        for (const string& month : monthNames) macros[lower(month.substr(0, 3))] = month;
        int errors = 0;
        auto report = [&](size_t line, const string& name, const string& reason) {
            output.push_back("ERROR line " + to_string(line) + ": " + name + ": " + reason);
            ++errors;
        };
        for (size_t i = 0; i < lines.size(); ++i) {
            const string& line = lines[i];
            if (line.empty() || line.front() == '%') continue;
            if (line.compare(0, 8, "@string{") == 0) {
                size_t equal = line.find(" = ");
                string name = line.substr(8, equal - 8), expression = line.substr(equal + 3, line.size() - equal - 4);
                try {
                    string value = evaluateExpression(expression, macros);
                    if (macros.count(name)) throw runtime_error("duplicate macro");
                    macros[name] = move(value);
                } catch (const runtime_error& error) { report(i + 1, name, error.what()); }
                continue;
            }
            size_t brace = line.find('{');
            string type = line.substr(1, brace - 1), key = line.substr(brace + 1, line.size() - brace - 2);
            Fields fields;
            bool failed = false;
            auto fail = [&](const string& reason) { report(i + 1, key, reason); failed = true; };
            if (!requiredFields.count(type)) fail("unknown type '" + type + "'");
            else if (byKey.count(key)) fail("duplicate key");
            while (lines[++i] != "}") {
                if (failed) continue;
                size_t equal = lines[i].find(" = ");
                string name = lines[i].substr(2, equal - 2), expression = lines[i].substr(equal + 3);
                if (expression.back() == ',') expression.pop_back();
                try {
                    string value = evaluateExpression(expression, macros);
                    if (fields.count(name)) throw runtime_error("duplicate field '" + name + "'");
                    fields[name] = normalize(value);
                } catch (const runtime_error& error) { fail(error.what()); }
            }
            if (failed) continue;
            for (const string& field : requiredFields.at(type)) {
                if (!fields.count(field) && !(type == "book" && field == "author" && fields.count("editor"))) {
                    fail("missing field '" + field + "'");
                    break;
                }
            }
            if (!failed) {
                byKey[key] = entries.size();
                entries.emplace_back(key, type, move(fields));
            }
        }
        output.push_back("LOADED entries=" + to_string(entries.size()) + " macros=" + to_string(macros.size() - 12) + " errors=" + to_string(errors));
        vector<bool> assigned(entries.size(), false);
        for (size_t i = 0; i < entries.size(); ++i) {
            if (assigned[i]) continue;
            vector<size_t> group;
            for (size_t j = i; j < entries.size(); ++j) {
                if (entries[i].primary() == entries[j].primary() && entries[i].fields.at("year") == entries[j].fields.at("year")) {
                    assigned[j] = true;
                    group.push_back(j);
                }
            }
            if (group.size() < 2) continue;
            sort(group.begin(), group.end(), [&](size_t a, size_t b) {
                return tie(entries[a].sortTitle, entries[a].key) < tie(entries[b].sortTitle, entries[b].key);
            });
            for (size_t j = 0; j < group.size(); ++j) entries[group[j]].suffix = string(1, char('a' + j));
        }
        for (const Entry& entry : entries) bibliography.push_back(&entry);
        sort(bibliography.begin(), bibliography.end(), bibliographyLess);
    }
    const Entry* find(const string& key) const {
        auto found = byKey.find(key);
        return found == byKey.end() ? nullptr : &entries[found->second];
    }
};

string listNames(const vector<string>& names, const string& conjunction, bool listB = false) {
    if (names.size() == 1) return names[0];
    if (listB && names.size() == 2) return names[0] + " " + conjunction + " " + names[1];
    return join(vector<string>(names.begin(), names.end() - 1), ", ") + ", " + conjunction + " " + names.back();
}
string authorValue(const Entry& entry, Style style, bool repeated) {
    const NameList& list = entry.primary();
    string result = "---";
    if (!repeated) {
        vector<string> names;
        for (size_t i = 0; i < list.names.size(); ++i) {
            bool inverted = style == Style::APA || (style != Style::IEEE && i == 0);
            names.push_back(list.names[i].format(inverted, style == Style::APA || style == Style::IEEE));
        }
        if (style == Style::APA) {
            if (list.etAl) result = join(names, ", ") + ", et al.";
            else if (names.size() <= 20) result = listNames(names, "&");
            else result = join(vector<string>(names.begin(), names.begin() + 19), ", ") + ", . . . " + names.back();
        } else if (style == Style::IEEE) {
            result = list.etAl || names.size() >= 7 ? names[0] + " et al." : listNames(names, "and", true);
        } else if (style == Style::Chicago && (list.etAl || names.size() >= 11)) {
            names.resize(min<size_t>(7, names.size()));
            result = join(names, ", ") + ", et al.";
        } else if (style == Style::MLA && (list.etAl || names.size() >= 3)) result = names[0] + ", et al.";
        else result = listNames(names, "and");
    }
    if (!entry.author) {
        bool singular = list.singular();
        switch (style) {
            case Style::APA: result += singular ? " (Ed.)" : " (Eds.)"; break;
            case Style::IEEE: result += singular ? ", Ed." : ", Eds."; break;
            case Style::Chicago: result += singular ? ", ed." : ", eds."; break;
            case Style::MLA: result += singular ? ", editor" : ", editors"; break;
        }
    }
    return result;
}
string editorValue(const optional<NameList>& editor, Style style) {
    if (!editor) return "";
    vector<string> names;
    for (const Person& person : editor->names) names.push_back(person.format(false, style == Style::APA || style == Style::IEEE));
    return editor->etAl ? names[0] + " et al." : listNames(names, style == Style::APA ? "&" : "and", true);
}
string titleValue(const string& title, Style style) {
    if (style == Style::IEEE) return plain(title);
    if (style == Style::APA) {
        string result = title;
        int depth = 0;
        for (size_t i = 0; i < title.size(); ++i) {
            if (title[i] == '{') ++depth;
            if (title[i] == '}') --depth;
            if (depth == 0 && isLetter(title[i])) {
                bool capital = i == 0 || (i >= 2 && title.compare(i - 2, 2, ": ") == 0);
                result[i] = capital ? upperChar(title[i]) : lowerChar(title[i]);
            }
        }
        return plain(result);
    }
    vector<string> words = splitDepthZero(title, " "), result;
    for (size_t i = 0; i < words.size(); ++i) {
        string word = words[i];
        if (!word.empty() && word.front() == '{') { result.push_back(word); continue; }
        bool makeLower = i > 0 && i + 1 < words.size() && words[i - 1].back() != ':' && smallWords.count(letters(word));
        int depth = 0;
        bool firstLetter = true;
        for (char& c : word) {
            if (c == '{') ++depth;
            if (c == '}') --depth;
            if (!isLetter(c)) continue;
            if (depth == 0) {
                if (makeLower) c = lowerChar(c);
                else if (firstLetter) c = upperChar(c);
            }
            firstLetter = false;
        }
        result.push_back(word);
    }
    return plain(join(result, " "));
}
string ordinal(const string& value) {
    int number = stoi(value), lastTwo = number % 100;
    string suffix = "th";
    if (lastTwo < 11 || lastTwo > 13) {
        if (number % 10 == 1) suffix = "st";
        if (number % 10 == 2) suffix = "nd";
        if (number % 10 == 3) suffix = "rd";
    }
    return value + suffix;
}
Fields placeholderValues(const Entry& entry, Style style, bool repeated) {
    Fields values;
    for (const auto& [name, value] : entry.fields) values[name] = plain(value);
    values["author"] = authorValue(entry, style, repeated);
    values["editor"] = editorValue(entry.editor, style);
    values["eds"] = entry.editor ? (entry.editor->singular() ? "Ed." : "Eds.") : "";
    values["title"] = titleValue(entry.fields.at("title"), style);
    values["year"] = entry.yearLabel(style);
    values["pages"] = join(split(entry.value("pages"), "--"), "-");
    values["pp"] = entry.fields.count("pages") ? (values["pages"].find('-') == string::npos ? "p. " : "pp. ") + values["pages"] : "";
    string edition = entry.value("edition");
    values["edition"] = entry.fields.count("edition") ? (allDigits(edition) ? ordinal(edition) : edition) + " ed." : "";
    string month = entry.value("month");
    auto found = find(monthNames.begin(), monthNames.end(), month);
    values["mon"] = found == monthNames.end() ? month : monthAbbreviations[found - monthNames.begin()];
    return values;
}

enum class TemplateKind { Literal, Value, Optional };
struct TemplateNode {
    TemplateKind kind;
    string text;
    vector<TemplateNode> children;
};
vector<TemplateNode> parseTemplate(const string& source) {
    size_t position = 0;
    function<vector<TemplateNode>()> sequence = [&]() {
        vector<TemplateNode> nodes;
        while (position < source.size() && source[position] != '>') {
            if (source[position] == '<') {
                ++position;
                nodes.push_back({TemplateKind::Optional, "", sequence()});
                ++position;
            } else if (source[position] == '{') {
                size_t end = source.find('}', position);
                nodes.push_back({TemplateKind::Value, source.substr(position + 1, end - position - 1), {}});
                position = end + 1;
            } else {
                size_t start = position++;
                while (position < source.size() && string("<{>").find(source[position]) == string::npos) ++position;
                nodes.push_back({TemplateKind::Literal, source.substr(start, position - start), {}});
            }
        }
        return nodes;
    };
    return sequence();
}
string renderTemplate(const vector<TemplateNode>& nodes, const Fields& values) {
    string result;
    auto value = [&](const string& name) {
        auto found = values.find(name);
        return found == values.end() ? "" : found->second;
    };
    function<void(const vector<TemplateNode>&)> visit = [&](const vector<TemplateNode>& sequence) {
        for (const TemplateNode& node : sequence) {
            if (node.kind == TemplateKind::Value) result += value(node.text);
            else if (node.kind == TemplateKind::Optional) {
                bool include = all_of(node.children.begin(), node.children.end(), [&](const TemplateNode& child) {
                    return child.kind != TemplateKind::Value || !value(child.text).empty();
                });
                if (include) visit(node.children);
            } else for (char c : node.text) {
                if (c != '.' || result.empty() || string(".?!").find(result.back()) == string::npos) result += c;
            }
        }
    };
    visit(nodes);
    return result;
}
const map<Style, map<string, string>> templateSources = {
    {Style::APA, {
        {"article", "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>"},
        {"book", "{author}. ({year}). {title}< ({edition})>. {publisher}."},
        {"inproceedings", "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>"},
        {"techreport", "{author}. ({year}). {title}< (Report No. {number})>. {institution}."},
        {"phdthesis", "{author}. ({year}). {title} [Doctoral dissertation, {school}]."},
        {"misc", "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"}
    }},
    {Style::IEEE, {
        {"article", "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>."},
        {"book", "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}."},
        {"inproceedings", "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>."},
        {"techreport", "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}."},
        {"phdthesis", "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}."},
        {"misc", "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>"}
    }},
    {Style::Chicago, {
        {"article", "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>"},
        {"book", "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}."},
        {"inproceedings", "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>"},
        {"techreport", "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}."},
        {"phdthesis", "{author}. {year}. \"{title}.\" PhD diss., {school}."},
        {"misc", "{author}. {year}. {title}.< {howpublished}.>< {note}.>"}
    }},
    {Style::MLA, {
        {"article", "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>"},
        {"book", "{author}. {title}.< {edition},> {publisher}, {year}."},
        {"inproceedings", "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>."},
        {"techreport", "{author}. {title}. {institution}, {year}.< Technical Report {number}.>"},
        {"phdthesis", "{author}. {title}. {year}. {school}, PhD dissertation."},
        {"misc", "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"}
    }}
};
const map<Style, map<string, vector<TemplateNode>>> templates = [] {
    map<Style, map<string, vector<TemplateNode>>> result;
    for (const auto& [style, sources] : templateSources)
        for (const auto& [type, source] : sources) result[style][type] = parseTemplate(source);
    return result;
}();

string shortName(const Entry& entry, Style style, bool parenthetical) {
    const NameList& list = entry.primary();
    if (list.etAl || list.names.size() >= (style == Style::Chicago ? 4u : 3u)) return list.names[0].surname() + " et al.";
    vector<string> names;
    for (const Person& person : list.names) names.push_back(person.surname());
    return listNames(names, style == Style::APA && parenthetical ? "&" : "and", true);
}

class Formatter {
    const Database& database;
    vector<string>& output;
    vector<string> citationRecord;
    set<string> cited;

    vector<string> ieeeOrder() const {
        vector<string> result = citationRecord;
        for (const auto& [key, index] : database.byKey) if (!cited.count(key)) result.push_back(key);
        return result;
    }
    map<string, int> ieeeNumbers() const {
        map<string, int> result;
        auto order = ieeeOrder();
        for (size_t i = 0; i < order.size(); ++i) result[order[i]] = int(i) + 1;
        return result;
    }
    string reference(const Entry& entry, Style style, const map<string, int>& numbers, bool repeated = false) const {
        string type = entry.type == "incollection" ? "inproceedings" : entry.type;
        string result = renderTemplate(templates.at(style).at(type), placeholderValues(entry, style, repeated));
        return (style == Style::IEEE ? "[" + to_string(numbers.at(entry.key)) + "] " : "") + result;
    }
    string citationText(const string& kind, vector<const Entry*> entries, Style style, const map<string, int>& numbers) const {
        bool parenthetical = kind == "cite" || kind == "citep";
        auto name = [&](const Entry* entry) { return shortName(*entry, style, parenthetical); };
        vector<string> pieces;
        if (kind == "citeauthor" || kind == "citeyear") {
            for (const Entry* entry : entries) pieces.push_back(kind == "citeauthor" ? name(entry) : entry->yearLabel(style));
            return join(pieces, kind == "citeauthor" ? "; " : ", ");
        }
        if (style == Style::MLA) {
            for (const Entry* entry : entries) pieces.push_back(name(entry));
            string result = join(pieces, "; ");
            return parenthetical ? "(" + result + ")" : result;
        }
        if (style == Style::IEEE) {
            if (!parenthetical) {
                for (const Entry* entry : entries) pieces.push_back(name(entry) + " [" + to_string(numbers.at(entry->key)) + "]");
                return join(pieces, "; ");
            }
            vector<int> sorted;
            for (const Entry* entry : entries) sorted.push_back(numbers.at(entry->key));
            sort(sorted.begin(), sorted.end());
            for (size_t i = 0; i < sorted.size();) {
                size_t end = i + 1;
                while (end < sorted.size() && sorted[end] == sorted[end - 1] + 1) ++end;
                if (end - i >= 3) pieces.push_back("[" + to_string(sorted[i]) + "]-[" + to_string(sorted[end - 1]) + "]");
                else for (size_t j = i; j < end; ++j) pieces.push_back("[" + to_string(sorted[j]) + "]");
                i = end;
            }
            return join(pieces, ", ");
        }
        if (parenthetical) sort(entries.begin(), entries.end(), bibliographyLess);
        vector<pair<string, vector<string>>> groups;
        for (const Entry* entry : entries) {
            string current = name(entry);
            if (groups.empty() || groups.back().first != current) groups.push_back({current, {}});
            groups.back().second.push_back(entry->yearLabel(style));
        }
        for (const auto& [name, years] : groups) {
            if (parenthetical) pieces.push_back(name + (style == Style::APA ? ", " : " ") + join(years, ", "));
            else pieces.push_back(name + " (" + join(years, ", ") + ")");
        }
        string result = join(pieces, "; ");
        return parenthetical ? "(" + result + ")" : result;
    }
    void cite(Style style, const string& text) {
        struct Citation { size_t start, length; string kind; vector<string> keys; };
        static const regex pattern(R"(\\(citeauthor|citeyear|citep|citet|cite)\{([^}]+)\})");
        vector<Citation> citations;
        for (sregex_iterator it(text.begin(), text.end(), pattern), end; it != end; ++it) {
            Citation citation{size_t(it->position()), size_t(it->length()), (*it)[1].str(), {}};
            set<string> seen;
            for (const string& key : split((*it)[2].str(), ",")) if (seen.insert(key).second) citation.keys.push_back(key);
            citations.push_back(move(citation));
        }
        for (const Citation& citation : citations) {
            for (const string& key : citation.keys) {
                if (!database.find(key)) { output.push_back("ERROR unknown key '" + key + "'"); return; }
            }
        }
        for (const Citation& citation : citations)
            for (const string& key : citation.keys) if (cited.insert(key).second) citationRecord.push_back(key);
        auto numbers = ieeeNumbers();
        string result;
        size_t position = 0;
        for (const Citation& citation : citations) {
            result += text.substr(position, citation.start - position);
            vector<const Entry*> entries;
            for (const string& key : citation.keys) entries.push_back(database.find(key));
            result += citationText(citation.kind, move(entries), style, numbers);
            position = citation.start + citation.length;
        }
        output.push_back(result + text.substr(position));
    }
    void keygen() {
        vector<string> bases;
        map<string, size_t> counts, used;
        for (const Entry& entry : database.entries) {
            string base = letters(entry.primary().names[0].last);
            for (char c : entry.fields.at("year")) if (isDigit(c)) base += c;
            for (const string& word : split(entry.value("title"), " ")) {
                string part = letters(word);
                if (!part.empty() && !smallWords.count(part)) { base += part; break; }
            }
            bases.push_back(base);
            ++counts[base];
        }
        for (size_t i = 0; i < bases.size(); ++i) {
            const string& base = bases[i];
            string suffix = counts[base] > 1 ? string(1, char('a' + used[base])) : "";
            ++used[base];
            output.push_back(database.entries[i].key + " -> " + base + suffix);
        }
    }
    void check() {
        int warnings = 0;
        map<string, string> firstTitles;
        for (const Entry& entry : database.entries) {
            auto warn = [&](const string& message) { output.push_back("WARN " + entry.key + ": " + message); ++warnings; };
            string pages = entry.value("pages"), title = entry.value("title");
            if (pages.find('-') != string::npos && pages.find("--") == string::npos) warn("pages use a single hyphen");
            vector<string> parts;
            for (const string& part : split(pages, "-")) if (!part.empty()) parts.push_back(part);
            if (parts.size() == 2 && allDigits(parts[0]) && allDigits(parts[1]) && stoll(parts[0]) > stoll(parts[1])) warn("pages are reversed");
            string year = entry.value("year");
            if (year.size() != 4 || !allDigits(year)) warn("year is not 4 digits");
            bool hasLower = any_of(title.begin(), title.end(), [](char c) { return c >= 'a' && c <= 'z'; });
            auto uppercase = count_if(title.begin(), title.end(), [](char c) { return c >= 'A' && c <= 'Z'; });
            if (!hasLower && uppercase >= 2) warn("title is all caps");
            if (entry.type == "article" && !entry.fields.count("doi")) warn("article has no doi");
            string titleKey = lower(title);
            if (firstTitles.count(titleKey)) warn("same title as " + firstTitles.at(titleKey));
            else firstTitles[titleKey] = entry.key;
            for (const string& field : entry.unknownFields()) warn("unknown field '" + field + "'");
        }
        output.push_back("CHECK warnings=" + to_string(warnings));
    }
    void exportEntry(const string& key) {
        const Entry* entry = database.find(key);
        if (!entry) { output.push_back("ERROR unknown key '" + key + "'"); return; }
        output.push_back("@" + entry->type + "{" + key + ",");
        vector<string> names;
        for (const string& field : fieldOrder) if (entry->fields.count(field)) names.push_back(field);
        auto unknown = entry->unknownFields();
        names.insert(names.end(), unknown.begin(), unknown.end());
        for (size_t i = 0; i < names.size(); ++i)
            output.push_back("  " + names[i] + " = {" + entry->fields.at(names[i]) + "}" + (i + 1 < names.size() ? "," : ""));
        output.push_back("}");
    }
    void stats() {
        map<string, int> types, years;
        set<string> authors;
        map<pair<string, string>, int> pairs;
        for (const Entry& entry : database.entries) {
            ++types[entry.type];
            ++years[entry.value("year")];
            if (!entry.author) continue;
            set<string> distinct;
            for (const Person& person : entry.author->names) distinct.insert(person.format(false, false));
            authors.insert(distinct.begin(), distinct.end());
            vector<string> names(distinct.begin(), distinct.end());
            for (size_t i = 0; i < names.size(); ++i)
                for (size_t j = i + 1; j < names.size(); ++j) ++pairs[{names[i], names[j]}];
        }
        output.push_back("ENTRIES " + to_string(database.entries.size()));
        for (const auto& [type, count] : types) output.push_back("TYPE " + type + " " + to_string(count));
        for (const auto& [year, count] : years) output.push_back("YEAR " + year + " " + to_string(count));
        output.push_back("AUTHORS " + to_string(authors.size()));
        int maximum = 0;
        pair<string, string> best;
        for (const auto& [pair, count] : pairs) if (count > maximum) { best = pair; maximum = count; }
        output.push_back(maximum ? "PAIR " + best.first + " & " + best.second + " " + to_string(maximum) : "PAIR none");
    }

public:
    Formatter(const Database& database, vector<string>& output) : database(database), output(output) {}
    void command(const string& line) {
        static const map<string, int> arity = {{"FORMAT", -1}, {"BIBLIOGRAPHY", 1}, {"CITE", 2},
            {"KEYGEN", 0}, {"CHECK", 0}, {"SEARCH", 2}, {"EXPORT", 1}, {"STATS", 0}};
        static const map<string, Style> styles = {{"APA", Style::APA}, {"IEEE", Style::IEEE},
            {"CHICAGO", Style::Chicago}, {"MLA", Style::MLA}};
        size_t firstSpace = line.find(' ');
        string command = line.substr(0, firstSpace);
        vector<string> parts;
        if (command == "CITE" || command == "SEARCH") {
            parts.push_back(command);
            if (firstSpace != string::npos) {
                size_t secondSpace = line.find(' ', firstSpace + 1);
                parts.push_back(line.substr(firstSpace + 1, secondSpace == string::npos ? string::npos : secondSpace - firstSpace - 1));
                if (secondSpace != string::npos) parts.push_back(line.substr(secondSpace + 1));
            }
        } else parts = split(line, " ");
        vector<string> args(parts.begin() + 1, parts.end());
        if (!arity.count(command)) { output.push_back("ERROR unknown command '" + command + "'"); return; }
        if (command == "FORMAT" ? args.size() < 2 : args.size() != size_t(arity.at(command))) {
            output.push_back("ERROR wrong number of arguments"); return;
        }
        bool hasStyle = command == "FORMAT" || command == "BIBLIOGRAPHY" || command == "CITE";
        if (hasStyle && !styles.count(args[0])) { output.push_back("ERROR unknown style '" + args[0] + "'"); return; }
        Style style = hasStyle ? styles.at(args[0]) : Style::APA;
        if (command == "FORMAT") {
            auto numbers = ieeeNumbers();
            for (size_t i = 1; i < args.size(); ++i) {
                const Entry* entry = database.find(args[i]);
                output.push_back(entry ? reference(*entry, style, numbers) : "ERROR unknown key '" + args[i] + "'");
            }
        } else if (command == "BIBLIOGRAPHY") {
            auto numbers = ieeeNumbers();
            vector<const Entry*> entries = database.bibliography;
            if (style == Style::IEEE) {
                entries.clear();
                for (const string& key : ieeeOrder()) entries.push_back(database.find(key));
            }
            output.push_back(style == Style::MLA ? "Works Cited" : "References");
            const NameList* previous = nullptr;
            for (const Entry* entry : entries) {
                bool repeated = (style == Style::Chicago || style == Style::MLA) && previous && *previous == entry->primary();
                output.push_back(reference(*entry, style, numbers, repeated));
                previous = &entry->primary();
            }
        } else if (command == "CITE") cite(style, args[1]);
        else if (command == "KEYGEN") keygen();
        else if (command == "CHECK") check();
        else if (command == "EXPORT") exportEntry(args[0]);
        else if (command == "STATS") stats();
        else if (command == "SEARCH") {
            vector<string> keys;
            string needle = lower(args[1]);
            for (const Entry& entry : database.entries)
                if (entry.fields.count(args[0]) && lower(entry.value(args[0])).find(needle) != string::npos) keys.push_back(entry.key);
            output.push_back(keys.empty() ? "MATCHES 0" : "MATCHES " + to_string(keys.size()) + ": " + join(keys, " "));
        }
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    vector<string> lines, output;
    string line;
    while (getline(cin, line) && line != "%%") lines.push_back(line);
    Database database(lines, output);
    Formatter formatter(database, output);
    getline(cin, line);
    int commands = stoi(line);
    for (int i = 0; i < commands; ++i) { getline(cin, line); formatter.command(line); }
    for (const string& result : output) cout << result << '\n';
}
