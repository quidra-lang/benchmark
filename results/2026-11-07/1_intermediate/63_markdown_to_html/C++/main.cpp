#include <algorithm>
#include <cctype>
#include <iostream>
#include <map>
#include <optional>
#include <regex>
#include <set>
#include <string>
#include <utility>
#include <vector>

using std::string;
using Strings = std::vector<string>;

const string whitespace = " \n";
const string punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
const string tocMarker = "\001toc\002";

bool contains(const string& text, char ch) { return text.find(ch) != string::npos; }
bool starts(const string& text, const string& prefix, std::size_t at = 0) {
    return text.compare(at, prefix.size(), prefix) == 0;
}
bool alphanumeric(char ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9');
}
bool labelCharacter(char ch) { return alphanumeric(ch) || ch == '-' || ch == '_'; }
string lower(string text) {
    for (char& ch : text) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    return text;
}
string trim(const string& text) {
    std::size_t first = text.find_first_not_of(' ');
    if (first == string::npos) return "";
    return text.substr(first, text.find_last_not_of(' ') - first + 1);
}
string leftTrim(const string& text) {
    std::size_t first = text.find_first_not_of(' ');
    return first == string::npos ? "" : text.substr(first);
}
string join(const Strings& values, const string& separator) {
    string result;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i) result += separator;
        result += values[i];
    }
    return result;
}
string escapeHtml(const string& text) {
    string html;
    for (char ch : text) {
        switch (ch) {
            case '&': html += "&amp;"; break;
            case '<': html += "&lt;"; break;
            case '>': html += "&gt;"; break;
            case '"': html += "&quot;"; break;
            default: html += ch;
        }
    }
    return html;
}
string stripTags(const string& text) {
    static const std::regex tag("<[^>]*>");
    return std::regex_replace(text, tag, "");
}
string normalize(const string& text) {
    string result;
    bool space = false;
    for (char ch : lower(text)) {
        if (contains(whitespace, ch)) {
            space = !result.empty();
        } else {
            if (space) result += ' ';
            result += ch;
            space = false;
        }
    }
    return result;
}
std::size_t skipSpace(const string& text, std::size_t at) {
    while (at < text.size() && contains(whitespace, text[at])) ++at;
    return at;
}
std::pair<string, std::size_t> escapedRead(const string& text, std::size_t at, const string& stops) {
    string result;
    while (at < text.size() && !contains(stops, text[at])) {
        if (text[at] == '\\' && at + 1 < text.size() && contains(punctuation, text[at + 1])) ++at;
        result += text[at++];
    }
    return {result, at};
}

enum class Kind { Heading, Paragraph, Rule, Code, Quote, Alert, List, Table, Toc };

struct Block {
    Kind kind;
    string text;
    int number = 0;
    bool ordered = false;
    Strings lines;
    std::vector<Block> children;
    std::vector<std::vector<Block>> items;
    Strings alignments;
    std::vector<Strings> rows;

    explicit Block(Kind kind, string text = "", int number = 0)
        : kind(kind), text(std::move(text)), number(number) {}
};

struct Reference {
    string url;
    std::optional<string> title;
};
struct ListMarker {
    char marker;
    bool ordered;
    int number;
    string content;
};

std::optional<std::pair<string, string>> openingFence(const string& line) {
    if (line.empty() || (line[0] != '`' && line[0] != '~')) return std::nullopt;
    std::size_t end = line.find_first_not_of(line[0]);
    if (end == string::npos) end = line.size();
    if (end < 3) return std::nullopt;
    string info = trim(line.substr(end));
    if (line[0] == '`' && contains(info, '`')) return std::nullopt;
    return std::make_pair(line.substr(0, end), info);
}
std::optional<Block> atxHeading(const string& line) {
    std::size_t n = 0;
    while (n < line.size() && line[n] == '#') ++n;
    if (n < 1 || n > 6 || (n < line.size() && line[n] != ' ')) return std::nullopt;
    string text = trim(line.substr(n));
    std::size_t last = text.find_last_not_of('#');
    if (last == string::npos) text.clear();
    else if (text[last] == ' ') text = trim(text.substr(0, last + 1));
    return Block(Kind::Heading, text, static_cast<int>(n));
}
bool isRule(const string& line) {
    string compact;
    for (char ch : line) if (ch != ' ') compact += ch;
    return compact.size() >= 3 && contains("-*_", compact[0])
        && compact.find_first_not_of(compact[0]) == string::npos;
}
std::optional<ListMarker> listMarker(const string& line) {
    if (isRule(line)) return std::nullopt;
    static const std::regex item(R"((?:([-*+])|([0-9]{1,9})([.)])) +)");
    std::smatch match;
    if (!std::regex_search(line, match, item, std::regex_constants::match_continuous)) return std::nullopt;
    bool ordered = match[2].matched;
    return ListMarker{ordered ? match.str(3)[0] : match.str(1)[0], ordered,
                      ordered ? std::stoi(match.str(2)) : 1, line.substr(match.length())};
}
bool interruptsParagraph(const string& line) {
    return !line.empty() && line[0] != ' ' &&
        (openingFence(line).has_value() || atxHeading(line).has_value() || isRule(line)
         || line[0] == '>' || listMarker(line).has_value());
}
Strings splitCells(const string& line) {
    string text = trim(line);
    std::size_t at = !text.empty() && text[0] == '|' ? 1 : 0;
    Strings cells(1);
    bool finalSeparator = false;
    while (at < text.size()) {
        char ch = text[at++];
        finalSeparator = false;
        if (ch == '\\' && at < text.size()) {
            if (text[at] != '|') cells.back() += '\\';
            cells.back() += text[at++];
        } else if (ch == '|') {
            cells.emplace_back();
            finalSeparator = true;
        } else cells.back() += ch;
    }
    if (finalSeparator) cells.pop_back();
    for (string& cell : cells) cell = trim(cell);
    return cells;
}

class BlockParser {
public:
    std::map<string, Reference> references;
    std::map<string, string> footnotes;

    std::vector<Block> parse(const Strings& lines) {
        std::vector<Block> blocks;
        std::size_t at = 0;
        while (at < lines.size()) {
            const string& line = lines[at];
            if (line.empty()) { ++at; continue; }
            if (starts(line, "    ")) {
                Block code(Kind::Code);
                std::size_t end = at;
                while (end < lines.size() && (lines[end].empty() || starts(lines[end], "    "))) ++end;
                while (end > at && lines[end - 1].empty()) --end;
                while (at < end) {
                    code.lines.push_back(lines[at].empty() ? "" : lines[at].substr(4));
                    ++at;
                }
                blocks.push_back(std::move(code));
                continue;
            }
            if (line[0] != ' ') {
                if (std::optional<std::pair<string, string>> fence = openingFence(line)) {
                    Block code(Kind::Code, fence->second.substr(0, fence->second.find(' ')));
                    ++at;
                    while (at < lines.size()) {
                        const string& row = lines[at++];
                        if (row.size() >= fence->first.size() && row.find_first_not_of(fence->first[0]) == string::npos) break;
                        code.lines.push_back(row);
                    }
                    blocks.push_back(std::move(code));
                    continue;
                }
                if (std::optional<Block> heading = atxHeading(line)) {
                    blocks.push_back(std::move(*heading)); ++at; continue;
                }
                if (isRule(line)) { blocks.emplace_back(Kind::Rule); ++at; continue; }
                if (line[0] == '>') {
                    Strings content;
                    while (at < lines.size() && starts(lines[at], ">")) {
                        string row = lines[at++].substr(1);
                        if (starts(row, " ")) row.erase(0, 1);
                        content.push_back(std::move(row));
                    }
                    static const std::regex alert(R"(\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\])");
                    std::smatch match;
                    Block quote(Kind::Quote);
                    if (std::regex_match(content.front(), match, alert)) {
                        quote.kind = Kind::Alert;
                        quote.text = match.str(1);
                        content.erase(content.begin());
                    }
                    quote.children = parse(content);
                    blocks.push_back(std::move(quote));
                    continue;
                }
                if (std::optional<ListMarker> marker = listMarker(line)) {
                    Block list(Kind::List, "", marker->number);
                    list.ordered = marker->ordered;
                    const char kind = marker->marker;
                    while (true) {
                        Strings content{marker->content};
                        ++at;
                        while (at < lines.size() && starts(lines[at], "  ")) content.push_back(lines[at++].substr(2));
                        list.items.push_back(parse(content));
                        std::size_t next = at;
                        while (next < lines.size() && lines[next].empty()) ++next;
                        marker = next < lines.size() ? listMarker(lines[next]) : std::nullopt;
                        if (!marker || marker->marker != kind || marker->ordered != list.ordered) break;
                        at = next;
                    }
                    blocks.push_back(std::move(list));
                    continue;
                }
                if (definition(line)) { ++at; continue; }
                if (at + 1 < lines.size() && contains(line, '|') && contains(lines[at + 1], '|')) {
                    Strings header = splitCells(line), delimiters = splitCells(lines[at + 1]);
                    static const std::regex delimiter(R"(:?-+:?)");
                    if (header.size() == delimiters.size() && std::all_of(delimiters.begin(), delimiters.end(),
                        [&](const string& cell) { return std::regex_match(cell, delimiter); })) {
                        Block table(Kind::Table);
                        table.lines = std::move(header);
                        for (const string& cell : delimiters) {
                            bool left = cell.front() == ':', right = cell.back() == ':';
                            table.alignments.push_back(left ? (right ? "center" : "left") : (right ? "right" : ""));
                        }
                        at += 2;
                        while (at < lines.size() && contains(lines[at], '|')) {
                            Strings row = splitCells(lines[at++]);
                            row.resize(delimiters.size());
                            table.rows.push_back(std::move(row));
                        }
                        blocks.push_back(std::move(table));
                        continue;
                    }
                }
            }
            Strings text{leftTrim(line)};
            ++at;
            int level = 0;
            while (at < lines.size() && !lines[at].empty()) {
                const string& row = lines[at];
                if (row.size() >= 3 && (row[0] == '=' || row[0] == '-') && row.find_first_not_of(row[0]) == string::npos) {
                    level = row[0] == '=' ? 1 : 2;
                    ++at;
                    break;
                }
                if (interruptsParagraph(row)) break;
                text.push_back(leftTrim(row));
                ++at;
            }
            string combined = join(text, "\n");
            blocks.emplace_back(level ? Kind::Heading : (combined == "[TOC]" ? Kind::Toc : Kind::Paragraph), combined, level);
        }
        return blocks;
    }

private:
    bool definition(const string& line) {
        static const std::regex footnote(R"(\[\^([A-Za-z0-9_-]+)\]:(.*))");
        std::smatch match;
        if (std::regex_match(line, match, footnote) && !trim(match.str(2)).empty()) {
            footnotes.emplace(lower(match.str(1)), trim(match.str(2)));
            return true;
        }
        if (line[0] != '[') return false;
        std::size_t close = line.find(']');
        if (close == string::npos || close + 1 >= line.size() || line[close + 1] != ':') return false;
        string label = line.substr(1, close - 1);
        if (contains(label, '[') || trim(label).empty() || label[0] == '^') return false;
        std::pair<string, std::size_t> url = escapedRead(line, skipSpace(line, close + 2), " ");
        if (url.first.empty()) return false;
        std::size_t at = skipSpace(line, url.second);
        std::optional<string> title;
        if (at < line.size()) {
            if (at == url.second || !contains("\"'", line[at])) return false;
            std::pair<string, std::size_t> quoted = escapedRead(line, at + 1, string(1, line[at]));
            if (quoted.second != line.size() - 1) return false;
            title = quoted.first;
        }
        references.emplace(normalize(label), Reference{url.first, title});
        return true;
    }
};

std::size_t runEnd(const string& text, std::size_t at) {
    char ch = text[at++];
    while (at < text.size() && text[at] == ch) ++at;
    return at;
}
std::size_t backtickCloser(const string& text, std::size_t at, std::size_t length) {
    while ((at = text.find('`', at)) != string::npos) {
        std::size_t end = runEnd(text, at);
        if (end - at == length) return at;
        at = end;
    }
    return string::npos;
}
std::size_t closingBracket(const string& text, std::size_t at) {
    int depth = 0;
    while (at < text.size()) {
        char ch = text[at];
        if (ch == '\\') { at += 2; continue; }
        if (ch == '`') {
            std::size_t end = runEnd(text, at), close = backtickCloser(text, end, end - at);
            at = close == string::npos ? end : close + end - at;
            continue;
        }
        if (ch == '[') ++depth;
        if (ch == ']' && --depth == 0) return at;
        ++at;
    }
    return string::npos;
}

struct Piece {
    string html;
    char delimiter = 0;
    std::size_t length = 0;
    bool canOpen = false, canClose = false;
};
string emphasis(const std::vector<Piece>& pieces, std::size_t begin, std::size_t end) {
    string html;
    for (std::size_t at = begin; at < end; ++at) {
        const Piece& piece = pieces[at];
        if (!piece.delimiter) { html += piece.html; continue; }
        std::size_t close = at + 1;
        if (piece.canOpen) {
            while (close < end && !(pieces[close].delimiter == piece.delimiter &&
                   pieces[close].length == piece.length && pieces[close].canClose)) ++close;
        } else close = end;
        if (close == end) { html += string(piece.length, piece.delimiter); continue; }
        string opening, closing;
        if (piece.delimiter == '~') { opening = "<del>"; closing = "</del>"; }
        else if (piece.length == 1) { opening = "<em>"; closing = "</em>"; }
        else if (piece.length == 2) { opening = "<strong>"; closing = "</strong>"; }
        else { opening = "<em><strong>"; closing = "</strong></em>"; }
        html += opening + emphasis(pieces, at + 1, close) + closing;
        at = close;
    }
    return html;
}

struct Destination { Reference reference; std::size_t end; };
struct HeadingEntry { int level; string id, label; std::vector<std::size_t> children; };

class Renderer {
    const std::map<string, Reference>& references;
    const std::map<string, string>& footnotes;
    std::set<string> usedIds;
    std::vector<HeadingEntry> headings;
    std::map<string, std::size_t> footnoteNumbers;
    Strings footnoteNames;
    std::vector<int> footnoteCounts;

public:
    Renderer(const std::map<string, Reference>& references, const std::map<string, string>& footnotes)
        : references(references), footnotes(footnotes) {}

    string document(const std::vector<Block>& blocks) {
        string html = renderBlocks(blocks);
        string contents = tableOfContents();
        std::size_t at = 0;
        while ((at = html.find(tocMarker, at)) != string::npos) {
            html.replace(at, tocMarker.size(), contents);
            at += contents.size();
        }
        if (!footnoteNames.empty()) html += footnoteList();
        return html;
    }

private:
    string inlineHtml(const string& text, bool links = true, bool notes = true) {
        std::vector<Piece> pieces;
        std::size_t at = 0;
        while (at < text.size()) {
            char ch = text[at];
            if (ch == '\\') {
                if (at + 1 < text.size() && contains(punctuation, text[at + 1])) {
                    pieces.push_back(Piece{escapeHtml(text.substr(at + 1, 1))}); at += 2;
                } else if (at + 1 < text.size() && text[at + 1] == '\n') {
                    pieces.push_back(Piece{"<br />\n"}); at += 2;
                } else { pieces.push_back(Piece{"\\"}); ++at; }
                continue;
            }
            if (ch == '`') {
                std::size_t end = runEnd(text, at), close = backtickCloser(text, end, end - at);
                if (close == string::npos) { pieces.push_back(Piece{text.substr(at, end - at)}); at = end; }
                else {
                    string code = text.substr(end, close - end);
                    std::replace(code.begin(), code.end(), '\n', ' ');
                    if (!code.empty() && code.front() == ' ' && code.back() == ' ' && code.find_first_not_of(' ') != string::npos)
                        code = code.substr(1, code.size() - 2);
                    pieces.push_back(Piece{"<code>" + escapeHtml(code) + "</code>"});
                    at = close + end - at;
                }
                continue;
            }
            if (links && ch == '<') {
                std::size_t close = text.find('>', at + 1);
                if (close != string::npos) {
                    string target = text.substr(at + 1, close - at - 1), href;
                    bool clean = target.find_first_of(" \n<") == string::npos;
                    if (clean && ((starts(target, "http://") && target.size() > 7) ||
                                  (starts(target, "https://") && target.size() > 8))) href = target;
                    static const std::regex email(R"([A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)");
                    if (href.empty() && std::regex_match(target, email)) href = "mailto:" + target;
                    if (!href.empty()) {
                        pieces.push_back(Piece{"<a href=\"" + escapeHtml(href) + "\">" + escapeHtml(target) + "</a>"});
                        at = close + 1; continue;
                    }
                }
            }
            if (links && (starts(text, "http://", at) || starts(text, "https://", at)) &&
                (at == 0 || contains(" \n*_~(", text[at - 1]))) {
                std::size_t end = text.find_first_of(" \n<", at);
                if (end == string::npos) end = text.size();
                while (end > at && contains(".,:;!?*_~)", text[end - 1])) --end;
                string url = text.substr(at, end - at);
                if (url != "http://" && url != "https://") {
                    string escaped = escapeHtml(url);
                    pieces.push_back(Piece{"<a href=\"" + escaped + "\">" + escaped + "</a>"});
                    at = end; continue;
                }
            }
            if (ch == '[' || (ch == '!' && at + 1 < text.size() && text[at + 1] == '[')) {
                if (links && notes && starts(text, "[^", at)) {
                    std::size_t close = text.find(']', at + 2);
                    if (close != string::npos) {
                        string name = lower(text.substr(at + 2, close - at - 2));
                        if (footnotes.count(name)) {
                            pieces.push_back(Piece{footnoteReference(name)}); at = close + 1; continue;
                        }
                    }
                }
                bool image = ch == '!';
                std::size_t opening = at + (image ? 1 : 0), close = closingBracket(text, opening);
                if ((image || links) && close != string::npos) {
                    string label = text.substr(opening + 1, close - opening - 1);
                    if (std::optional<Destination> dest = destination(text, close + 1, label)) {
                        string content = inlineHtml(label, false, false);
                        string url = escapeHtml(dest->reference.url);
                        string title = dest->reference.title ? " title=\"" + escapeHtml(*dest->reference.title) + "\"" : "";
                        string html = image ? "<img src=\"" + url + "\" alt=\"" + stripTags(content) + "\"" + title + " />"
                                            : "<a href=\"" + url + "\"" + title + ">" + content + "</a>";
                        pieces.push_back(Piece{html}); at = dest->end; continue;
                    }
                }
            }
            if (contains("*_~", ch)) {
                std::size_t end = runEnd(text, at), length = end - at;
                char before = at ? text[at - 1] : ' ', after = end < text.size() ? text[end] : ' ';
                bool open = !contains(whitespace, after), close = !contains(whitespace, before);
                if (ch == '_' && alphanumeric(before) && alphanumeric(after)) open = close = false;
                if ((ch != '~' && length <= 3) || (ch == '~' && length == 2))
                    pieces.push_back(Piece{"", ch, length, open, close});
                else pieces.push_back(Piece{string(length, ch)});
                at = end; continue;
            }
            pieces.push_back(Piece{escapeHtml(string(1, ch))});
            ++at;
        }
        return emphasis(pieces, 0, pieces.size());
    }

    std::optional<Destination> destination(const string& text, std::size_t at, const string& label) const {
        if (at < text.size() && text[at] == '[') {
            std::size_t close = text.find(']', at + 1);
            if (close != string::npos && text.substr(at + 1, close - at - 1).find('[') == string::npos) {
                string key = text.substr(at + 1, close - at - 1);
                key = normalize(key.empty() ? label : key);
                std::map<string, Reference>::const_iterator found = references.find(key);
                if (found == references.end()) return std::nullopt;
                return Destination{found->second, close + 1};
            }
        } else if (at < text.size() && text[at] == '(') {
            std::pair<string, std::size_t> url = escapedRead(text, skipSpace(text, at + 1), " \n)");
            std::size_t next = skipSpace(text, url.second);
            std::optional<string> title;
            bool valid = true;
            if (next > url.second && next < text.size() && contains("\"'", text[next])) {
                std::pair<string, std::size_t> quoted = escapedRead(text, next + 1, string(1, text[next]));
                if (quoted.second == text.size()) valid = false;
                else { title = quoted.first; next = skipSpace(text, quoted.second + 1); }
            }
            if (valid && next < text.size() && text[next] == ')') return Destination{Reference{url.first, title}, next + 1};
        }
        std::map<string, Reference>::const_iterator found = references.find(normalize(label));
        if (found == references.end()) return std::nullopt;
        return Destination{found->second, at};
    }

    string renderBlocks(const std::vector<Block>& blocks) {
        string html;
        for (const Block& block : blocks) html += render(block) + "\n";
        return html;
    }
    string render(const Block& block) {
        switch (block.kind) {
            case Kind::Heading: return heading(block.number, block.text);
            case Kind::Paragraph: return "<p>" + inlineHtml(block.text) + "</p>";
            case Kind::Rule: return "<hr />";
            case Kind::Code: {
                string html = "<pre><code";
                if (!block.text.empty()) html += " class=\"language-" + escapeHtml(block.text) + "\"";
                html += '>';
                for (const string& line : block.lines) html += escapeHtml(line) + "\n";
                return html + "</code></pre>";
            }
            case Kind::Quote: return "<blockquote>\n" + renderBlocks(block.children) + "</blockquote>";
            case Kind::Alert: {
                string name = lower(block.text), title = name;
                title[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(title[0])));
                return "<div class=\"alert alert-" + name + "\">\n<p class=\"alert-title\">" + title + "</p>\n"
                    + renderBlocks(block.children) + "</div>";
            }
            case Kind::List: {
                string tag = block.ordered ? "ol" : "ul", html = "<" + tag;
                if (block.ordered && block.number != 1) html += " start=\"" + std::to_string(block.number) + "\"";
                html += ">\n";
                for (const std::vector<Block>& item : block.items) html += renderItem(item) + "\n";
                return html + "</" + tag + ">";
            }
            case Kind::Table: {
                string html = "<table>\n<thead>\n<tr>\n" + tableCells("th", block, block.lines) + "</tr>\n</thead>\n";
                if (!block.rows.empty()) {
                    html += "<tbody>\n";
                    for (const Strings& row : block.rows) html += "<tr>\n" + tableCells("td", block, row) + "</tr>\n";
                    html += "</tbody>\n";
                }
                return html + "</table>";
            }
            case Kind::Toc: return tocMarker;
        }
        return "";
    }
    string heading(int level, string text) {
        string id;
        std::size_t explicitId = text.rfind(" {#");
        if (!text.empty() && text.back() == '}' && explicitId != string::npos) {
            string candidate = text.substr(explicitId + 3, text.size() - explicitId - 4);
            if (!candidate.empty() && std::all_of(candidate.begin(), candidate.end(), labelCharacter)) {
                id = candidate;
                text = text.substr(0, explicitId);
                std::size_t last = text.find_last_not_of(' ');
                text = last == string::npos ? "" : text.substr(0, last + 1);
            }
        }
        if (id.empty()) {
            string base;
            for (char ch : lower(text)) {
                if (labelCharacter(ch)) base += ch;
                else if (contains(whitespace, ch)) base += '-';
            }
            if (base.empty()) base = "heading";
            id = base;
            for (int suffix = 1; usedIds.count(id); ++suffix) id = base + "-" + std::to_string(suffix);
        }
        usedIds.insert(id);
        string html = inlineHtml(text), number = std::to_string(level);
        headings.push_back(HeadingEntry{level, id, stripTags(html), {}});
        return "<h" + number + " id=\"" + id + "\">" + html + "</h" + number + ">";
    }
    string renderItem(const std::vector<Block>& blocks) {
        string html = "<li>";
        for (std::size_t i = 0; i < blocks.size(); ++i) {
            const Block& block = blocks[i];
            if (block.kind == Kind::Paragraph) {
                string text = block.text;
                if (i == 0 && text.size() > 4 && (starts(text, "[ ] ") || starts(text, "[x] ") || starts(text, "[X] "))) {
                    html += text[1] == ' ' ? "<input type=\"checkbox\" disabled=\"\" /> "
                                           : "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ";
                    text.erase(0, 4);
                }
                html += inlineHtml(text);
            } else {
                if (html.back() != '\n') html += '\n';
                html += render(block) + "\n";
            }
        }
        return html + "</li>";
    }
    string tableCells(const string& tag, const Block& table, const Strings& cells) {
        string html;
        for (std::size_t i = 0; i < cells.size(); ++i) {
            string style = table.alignments[i].empty() ? "" : " style=\"text-align:" + table.alignments[i] + "\"";
            html += "<" + tag + style + ">" + inlineHtml(cells[i]) + "</" + tag + ">\n";
        }
        return html;
    }
    string tocList(const std::vector<std::size_t>& entries) const {
        string html = "<ul>\n";
        for (std::size_t index : entries) {
            const HeadingEntry& entry = headings[index];
            html += "<li><a href=\"#" + entry.id + "\">" + entry.label + "</a>";
            if (!entry.children.empty()) html += "\n" + tocList(entry.children) + "\n";
            html += "</li>\n";
        }
        return html + "</ul>";
    }
    string tableOfContents() {
        if (headings.empty()) return "<nav class=\"toc\">\n</nav>";
        std::vector<std::size_t> roots, parents;
        for (std::size_t i = 0; i < headings.size(); ++i) {
            while (!parents.empty() && headings[parents.back()].level >= headings[i].level) parents.pop_back();
            if (parents.empty()) roots.push_back(i);
            else headings[parents.back()].children.push_back(i);
            parents.push_back(i);
        }
        return "<nav class=\"toc\">\n" + tocList(roots) + "\n</nav>";
    }
    string referenceId(std::size_t index, int count) const {
        return "fnref-" + std::to_string(index + 1) + (count == 1 ? "" : "-" + std::to_string(count));
    }
    string footnoteReference(const string& name) {
        if (!footnoteNumbers.count(name)) {
            footnoteNumbers[name] = footnoteNames.size();
            footnoteNames.push_back(name);
            footnoteCounts.push_back(0);
        }
        std::size_t index = footnoteNumbers.at(name);
        string id = referenceId(index, ++footnoteCounts[index]), number = std::to_string(index + 1);
        return "<sup id=\"" + id + "\"><a href=\"#fn-" + number + "\">" + number + "</a></sup>";
    }
    string footnoteList() {
        string html = "<section class=\"footnotes\">\n<ol>\n";
        for (std::size_t i = 0; i < footnoteNames.size(); ++i) {
            string body = inlineHtml(footnotes.at(footnoteNames[i]), true, false);
            html += "<li id=\"fn-" + std::to_string(i + 1) + "\">" + body;
            for (int count = 1; count <= footnoteCounts[i]; ++count)
                html += " <a href=\"#" + referenceId(i, count) + "\">&#8617;</a>";
            html += "</li>\n";
        }
        return html + "</ol>\n</section>\n";
    }
};

int main() {
    Strings lines;
    string line;
    while (std::getline(std::cin, line) && line != "@@END@@") lines.push_back(line);
    BlockParser parser;
    std::vector<Block> blocks = parser.parse(lines);
    Renderer renderer(parser.references, parser.footnotes);
    std::cout << renderer.document(blocks);
}
