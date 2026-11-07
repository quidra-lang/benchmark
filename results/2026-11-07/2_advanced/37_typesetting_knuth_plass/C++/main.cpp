#include "typesetting.hpp"
Lines read_lines(const std::string &path) {
    std::ifstream in(path);
    Lines out;
    std::string line;
    while (std::getline(in, line))
        out.push_back(line);
    return out;
}
Lines split(const std::string &text, char delimiter) {
    Lines out;
    std::size_t first = 0;
    for (std::size_t i = 0; i <= text.size(); ++i)
        if (i == text.size() || text[i] == delimiter) {
            out.push_back(text.substr(first, i - first));
            first = i + 1;
        }
    return out;
}
Lines words(const std::string &text) {
    Lines out;
    for (const std::string &word : split(text, ' '))
        if (!word.empty())
            out.push_back(word);
    return out;
}
std::string join(const Lines &values, const std::string &delimiter) {
    std::string result;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            result += delimiter;
        result += values[i];
    }
    return result;
}
std::string number(Integer value) {
    return std::to_string(value);
}
std::string lower(std::string value) {
    for (char &c : value)
        if (c >= 'A' && c <= 'Z')
            c = char(c - 'A' + 'a');
    return value;
}
std::string upper(std::string value) {
    for (char &c : value)
        if (c >= 'a' && c <= 'z')
            c = char(c - 'a' + 'A');
    return value;
}
std::string rtrim(std::string value) {
    while (!value.empty() && value.back() == ' ')
        value.pop_back();
    return value;
}
std::string trim(std::string value) {
    value = rtrim(value);
    const auto first = value.find_first_not_of(' ');
    return first == std::string::npos ? "" : value.substr(first);
}
bool letter(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}
struct Context {
    Document document;
    Params params;
    Dictionary dictionary;
    std::map<std::string, int> labels, bib_keys;
    std::vector<int> bib_order;
    Lines footnotes, index_phrases;
};
static void remove_label(std::string &text, std::string &label) {
    if (text.empty() || text.back() != '}')
        return;
    const auto position = text.rfind(" {#");
    if (position == std::string::npos)
        return;
    label = text.substr(position + 3, text.size() - position - 4);
    text.erase(position);
}
static Lines author_parts(const std::string &author) {
    Lines out;
    std::size_t first = 0;
    while (true) {
        const auto next = author.find(" and ", first);
        out.push_back(author.substr(first, next == std::string::npos ? next : next - first));
        if (next == std::string::npos)
            break;
        first = next + 5;
    }
    return out;
}
static void prepare(Context &context) {
    Document &document = context.document;
    int chapter = 0, section = 0, table = 0, body = 0;
    for (std::size_t i = 0; i < document.blocks.size(); ++i) {
        Block &block = document.blocks[i];
        if (block.kind == Kind::h1 || block.kind == Kind::h2) {
            remove_label(block.text, block.label);
            if (block.kind == Kind::h1) {
                ++chapter;
                section = 0;
                block.number = number(chapter);
                if (i)
                    block.page_break = true;
            } else {
                ++section;
                block.number = number(chapter) + "." + number(section);
            }
        } else if (block.kind == Kind::table) {
            remove_label(block.caption, block.label);
            if (!block.caption.empty())
                block.number = number(++table);
        } else if (block.kind == Kind::enumeration)
            block.number = number(i && document.blocks[i - 1].kind == Kind::enumeration
                                      ? std::stoi(document.blocks[i - 1].number) + 1
                                      : 1);
        if (!block.label.empty()) {
            if (context.labels.count(block.label)) {
                document.warnings.push_back({block.line, "duplicate label " + block.label});
                block.label.clear();
            } else
                context.labels[block.label] = i;
        }
        if (block.kind == Kind::paragraph && i &&
            (document.blocks[i - 1].kind == Kind::h1 || document.blocks[i - 1].kind == Kind::h2))
            block.indent = 0;
        if (body_kind(block.kind))
            block.body_number = ++body;
    }
    std::vector<Bib> entries;
    for (const Bib &entry : document.bibliography) {
        if (context.bib_keys.count(entry.key))
            document.warnings.push_back({entry.line, "duplicate bibliography key " + entry.key});
        else {
            context.bib_keys[entry.key] = entries.size();
            entries.push_back(entry);
        }
    }
    document.bibliography = std::move(entries);
    for (Block &block : document.blocks) {
        if (block.kind == Kind::table) {
            for (const SourceLine &line : block.inner) {
                Lines cells = split(line.text, '|');
                for (std::string &cell : cells)
                    cell = trim(cell);
                if (cells.size() != block.columns.size())
                    document.warnings.push_back({line.line, "table row has " + number(cells.size()) +
                                                                " cells, expected " +
                                                                number(block.columns.size())});
                cells.resize(block.columns.size(), "");
                block.cells.push_back(cells);
            }
            std::size_t width = 0;
            for (const std::string &line : render_table(block))
                width = std::max(width, line.size());
            if (width > std::size_t(block.width))
                document.warnings.push_back({block.line, "table too wide by " + number(width - block.width)});
        } else if (block.kind == Kind::verbatim) {
            for (const SourceLine &line : block.inner)
                if (line.text.size() > std::size_t(block.width))
                    document.warnings.push_back(
                        {line.line, "verbatim line too long by " + number(line.text.size() - block.width)});
        } else if (body_kind(block.kind)) {
            for (std::size_t l = 0; l < block.body.size(); ++l) {
                if (l)
                    block.tokens.push_back({"text", " ", -1});
                const SourceLine &source = block.body[l];
                const std::string &text = source.text;
                std::size_t start = 0;
                while (start < text.size()) {
                    const auto brace = text.find('{', start);
                    if (brace == std::string::npos) {
                        block.tokens.push_back({"text", text.substr(start), -1});
                        break;
                    }
                    block.tokens.push_back({"text", text.substr(start, brace - start), -1});
                    const auto close = text.find('}', brace + 1);
                    if (close == std::string::npos) {
                        document.warnings.push_back({source.line, "unclosed brace"});
                        block.tokens.push_back({"text", text.substr(brace), -1});
                        break;
                    }
                    const std::string content = text.substr(brace + 1, close - brace - 1);
                    const auto colon = content.find(':');
                    const std::string command = content.substr(0, colon),
                                      argument = colon == std::string::npos ? "" : content.substr(colon + 1);
                    if (colon == std::string::npos || argument.empty() ||
                        (command != "ref" && command != "page" && command != "fn" && command != "idx" &&
                         command != "cite"))
                        document.warnings.push_back({source.line, "bad command {" + content + "}"});
                    else {
                        Inline token{command, argument, -1};
                        if (command == "ref" || command == "page") {
                            if (!context.labels.count(argument))
                                document.warnings.push_back({source.line, "undefined label " + argument});
                        } else if (command == "cite") {
                            for (const std::string &key : split(argument, ',')) {
                                const auto found = context.bib_keys.find(key);
                                if (found == context.bib_keys.end())
                                    document.warnings.push_back({source.line, "undefined citation " + key});
                                else
                                    document.bibliography[found->second].cited = true;
                            }
                        } else if (command == "fn") {
                            token.id = context.footnotes.size();
                            context.footnotes.push_back(argument);
                        } else {
                            token.id = context.index_phrases.size();
                            context.index_phrases.push_back(argument);
                        }
                        block.tokens.push_back(std::move(token));
                    }
                    start = close + 1;
                }
            }
        }
    }
    for (Bib &entry : document.bibliography) {
        if (!entry.cited) {
            document.warnings.push_back({entry.line, "unused bibliography entry " + entry.key});
            continue;
        }
        const Lines surnames = author_parts(entry.author);
        if (surnames.size() == 1)
            entry.base = surnames[0].substr(0, 3);
        else {
            for (std::size_t i = 0; i < std::min<std::size_t>(surnames.size(), surnames.size() >= 5 ? 3 : 4);
                 ++i)
                entry.base += surnames[i][0];
            if (surnames.size() >= 5)
                entry.base += '+';
        }
        entry.base += entry.year.substr(2);
        context.bib_order.push_back(&entry - document.bibliography.data());
    }
    std::sort(context.bib_order.begin(), context.bib_order.end(), [&](int a, int b) {
        const Bib &x = document.bibliography[a], &y = document.bibliography[b];
        return std::tie(x.base, x.author, x.title, x.key) < std::tie(y.base, y.author, y.title, y.key);
    });
    for (std::size_t i = 0; i < context.bib_order.size();) {
        std::size_t end = i + 1;
        while (end < context.bib_order.size() && document.bibliography[context.bib_order[end]].base ==
                                                     document.bibliography[context.bib_order[i]].base)
            ++end;
        for (std::size_t j = i; j < end; ++j) {
            Bib &entry = document.bibliography[context.bib_order[j]];
            entry.label = entry.base + (end - i > 1 ? std::string(1, char('a' + j - i)) : "");
        }
        i = end;
    }
    std::stable_sort(document.warnings.begin(), document.warnings.end(),
                     [](const Warning &a, const Warning &b) { return a.line < b.line; });
}
struct Mark {
    int word, position, id;
    bool footnote;
};
struct BreakPosition {
    int word, position;
    bool after = false, mid = false, hyphen = false;
};
struct TextData {
    Lines words;
    std::vector<Mark> marks;
    std::vector<BreakPosition> breaks;
    std::vector<int> prefix;
};
static TextData text_data(const Lines &word_values, const std::vector<Mark> &marks, const Context &context) {
    TextData out;
    out.words = word_values;
    out.marks = marks;
    out.breaks.push_back({0, 0, false, false, false});
    out.prefix.push_back(0);
    for (std::size_t i = 0; i < word_values.size(); ++i) {
        for (const SplitPoint &point : split_points(context.dictionary, word_values[i], context.params))
            out.breaks.push_back({int(i), point.position, false, true, point.hyphen});
        out.breaks.push_back({int(i), int(word_values[i].size()), true, false, false});
        out.prefix.push_back(out.prefix.back() + word_values[i].size());
    }
    return out;
}
static TextData expand(const Block &block, const Context &context,
                       const std::map<std::string, std::string> &page_values) {
    std::string expanded;
    struct RawMark {
        int offset, id;
        bool footnote;
    };
    std::vector<RawMark> marks;
    for (const Inline &token : block.tokens) {
        if (token.kind == "text")
            expanded += token.text;
        else if (token.kind == "ref" || token.kind == "page") {
            const auto found = context.labels.find(token.text);
            expanded += found == context.labels.end() ? "??"
                        : token.kind == "ref"         ? context.document.blocks[found->second].number
                                                      : page_values.at(token.text);
        } else if (token.kind == "fn") {
            marks.push_back({int(expanded.size()), token.id, true});
            expanded += "[" + number(token.id + 1) + "]";
        } else if (token.kind == "idx")
            marks.push_back({int(expanded.size()) - 1, token.id, false});
        else {
            std::set<std::string> labels;
            bool missing = false;
            for (const std::string &key : split(token.text, ',')) {
                const auto found = context.bib_keys.find(key);
                if (found == context.bib_keys.end())
                    missing = true;
                else
                    labels.insert(context.document.bibliography[found->second].label);
            }
            Lines values(labels.begin(), labels.end());
            if (missing)
                values.push_back("?");
            expanded += "[" + join(values, ", ") + "]";
        }
    }
    Lines word_values;
    std::vector<int> starts;
    for (std::size_t i = 0; i < expanded.size();) {
        if (expanded[i] == ' ') {
            ++i;
            continue;
        }
        const std::size_t start = i;
        while (i < expanded.size() && expanded[i] != ' ')
            ++i;
        starts.push_back(start);
        word_values.push_back(expanded.substr(start, i - start));
    }
    std::vector<Mark> located;
    for (const RawMark &mark : marks) {
        const int word =
            int(std::upper_bound(starts.begin(), starts.end(), mark.offset) - starts.begin()) - 1;
        located.push_back({word, mark.offset - starts[word], mark.id, mark.footnote});
    }
    return text_data(word_values, located, context);
}
static std::pair<int, int> start_position(const TextData &text, int a) {
    const BreakPosition &point = text.breaks[a];
    return point.after ? std::make_pair(point.word + 1, 0) : std::make_pair(point.word, point.position);
}
static Measure measure_line(const TextData &text, int a, int b, int first, int later) {
    const auto start = start_position(text, a);
    const BreakPosition &end = text.breaks[b];
    const int gaps = end.word - start.first, length = text.prefix[end.word] - text.prefix[start.first] -
                                                      start.second + end.position + gaps +
                                                      (end.hyphen ? 1 : 0);
    return {length,  (a == 0 ? first : later) - length, gaps,
            end.mid, b == int(text.breaks.size()) - 1,  text.breaks[a].mid};
}
static std::vector<Piece> pieces(const TextData &text, int a, int b) {
    const auto start = start_position(text, a);
    const BreakPosition &end = text.breaks[b];
    std::vector<Piece> out;
    for (int word = start.first; word <= end.word; ++word) {
        const int first = word == start.first ? start.second : 0,
                  last = word == end.word ? end.position : int(text.words[word].size());
        std::string value = text.words[word].substr(first, last - first);
        std::replace(value.begin(), value.end(), '~', ' ');
        if (word == end.word && end.hyphen)
            value += '-';
        out.push_back({word, first, last, value});
    }
    return out;
}
struct TextResult {
    std::vector<LayoutLine> lines;
    std::vector<Measure> measures;
    Integer cost = 0;
};
static TextResult layout_text(const Context &context, const TextData &text, int first, int later,
                              const std::string &alignment, const std::string &first_prefix,
                              const std::string &later_prefix, bool greedy) {
    const int count = int(text.breaks.size()) - 1;
    const MeasureLine measure = [&](int a, int b) { return measure_line(text, a, b, first, later); };
    const Breaking breaking = break_lines(count, measure, context.params, greedy);
    TextResult out;
    out.cost = breaking.cost;
    int a = 0;
    for (int b : breaking.ends) {
        const Measure line = measure(a, b);
        const std::vector<Piece> parts = pieces(text, a, b);
        LayoutLine displayed;
        displayed.text = (a == 0 ? first_prefix : later_prefix) + render_line(parts, line, alignment);
        for (const Mark &mark : text.marks)
            for (const Piece &piece : parts)
                if (mark.word == piece.word && piece.first <= mark.position && mark.position < piece.last) {
                    if (mark.footnote)
                        displayed.footnotes.push_back(mark.id);
                    else
                        displayed.indices.push_back(mark.id);
                }
        out.lines.push_back(std::move(displayed));
        out.measures.push_back(line);
        a = b;
    }
    return out;
}
struct BrokenReport {
    std::string name, alignment;
    bool body;
    std::vector<Measure> lines;
};
struct BodyStat {
    int lines = 0;
    Integer cost = 0;
};
struct Layout {
    std::vector<Page> pages;
    std::vector<Lines> footnotes;
    std::vector<int> block_pages, index_pages;
    std::vector<BodyStat> stats;
    std::vector<BrokenReport> reports;
    int front = 0, hyphenated = 0;
};
static std::string roman(int value) {
    const std::array<std::string, 10> small = {"", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"};
    return std::string(value / 10, 'x') + small[value % 10];
}
static std::string page_list(const std::set<int> &pages) {
    std::vector<int> values(pages.begin(), pages.end());
    Lines out;
    for (std::size_t i = 0; i < values.size();) {
        std::size_t end = i + 1;
        while (end < values.size() && values[end] == values[end - 1] + 1)
            ++end;
        if (end - i >= 3)
            out.push_back(number(values[i]) + "-" + number(values[end - 1]));
        else
            for (std::size_t j = i; j < end; ++j)
                out.push_back(number(values[j]));
        i = end;
    }
    return join(out, ", ");
}
struct IndexEntry {
    std::set<int> pages;
    std::set<std::string> references;
    std::map<std::pair<std::string, std::string>, IndexEntry> children;
};
static Lines index_lines(const Context &context, const std::vector<int> &pages) {
    std::map<std::pair<std::string, std::string>, IndexEntry> parents;
    for (std::size_t i = 0; i < context.index_phrases.size(); ++i) {
        const std::string &phrase = context.index_phrases[i];
        const auto bar = phrase.find('|');
        const std::string entry = phrase.substr(0, bar),
                          reference = bar == std::string::npos ? "" : phrase.substr(bar + 1);
        const auto bang = entry.find('!');
        const std::string parent = entry.substr(0, bang),
                          child = bang == std::string::npos ? "" : entry.substr(bang + 1);
        IndexEntry *node = &parents[{lower(parent), parent}];
        if (bang != std::string::npos)
            node = &node->children[{lower(child), child}];
        if (bar == std::string::npos)
            node->pages.insert(pages[i]);
        else
            node->references.insert(reference);
    }
    Lines out;
    std::string previous;
    auto line = [](const std::string &name, const IndexEntry &entry) {
        std::string text = name;
        if (!entry.pages.empty())
            text += ", " + page_list(entry.pages);
        if (!entry.references.empty())
            text += ", see " + join(Lines(entry.references.begin(), entry.references.end()), ", ");
        return text;
    };
    for (const auto &entry : parents) {
        const std::string &name = entry.first.second;
        const std::string group = letter(name[0]) ? upper(name.substr(0, 1)) : "Symbols";
        if (group != previous) {
            out.push_back(group);
            previous = group;
        }
        out.push_back(line(name, entry.second));
        for (const auto &child : entry.second.children)
            out.push_back(line("  " + child.first.second, child.second));
    }
    return out;
}
static std::string entry_line(const Block &target, int width, const std::string &page) {
    const std::string left = target.kind == Kind::table
                                 ? "Table " + target.number + ". " + target.caption
                                 : (target.kind == Kind::h2 ? "  " : "") + target.number + " " + target.text;
    return left + " " + std::string(width - int(left.size()) - int(page.size()) - 2, '.') + " " + page;
}
static std::vector<LayoutLine> plain_lines(const Lines &lines) {
    std::vector<LayoutLine> out;
    for (const std::string &line : lines)
        out.push_back({line});
    return out;
}
static Layout layout_once(const Context &context, const std::map<std::string, std::string> &page_values,
                          bool greedy) {
    const Document &document = context.document;
    Layout out;
    std::vector<BrokenReport> footnote_reports;
    for (std::size_t i = 0; i < context.footnotes.size(); ++i) {
        const std::string prefix = "[" + number(i + 1) + "] ";
        const TextData data = text_data(words(context.footnotes[i]), {}, context);
        const TextResult text =
            layout_text(context, data, document.width - prefix.size(), document.width - prefix.size(), "left",
                        prefix, std::string(prefix.size(), ' '), greedy);
        Lines lines;
        for (const LayoutLine &line : text.lines)
            lines.push_back(line.text);
        out.footnotes.push_back(lines);
        footnote_reports.push_back({"footnote " + number(i + 1), "left", false, text.measures});
    }
    int body_count = 0;
    for (const Block &block : document.blocks)
        body_count = std::max(body_count, block.body_number);
    out.stats.resize(body_count);
    std::vector<LayoutBlock> layout_blocks;
    std::vector<int> unknown_index_pages(context.index_phrases.size());
    const Lines index = index_lines(context, unknown_index_pages);
    std::size_t bibliography_prefix = 0;
    for (int id : context.bib_order)
        bibliography_prefix = std::max(bibliography_prefix, document.bibliography[id].label.size() + 3);
    for (std::size_t b = 0; b < document.blocks.size(); ++b) {
        const Block &block = document.blocks[b];
        bool first = true;
        auto add = [&](std::vector<LayoutLine> lines, LayoutType type, bool list = false) {
            LayoutBlock result{std::move(lines), type, list, first && block.page_break};
            if (first && !result.lines.empty())
                result.lines[0].first_block = b;
            layout_blocks.push_back(std::move(result));
            first = false;
        };
        if (body_kind(block.kind)) {
            int first_capacity = block.width, later_capacity = block.width;
            std::string first_prefix, later_prefix;
            if (block.kind == Kind::paragraph) {
                first_capacity -= block.indent;
                first_prefix = std::string(block.indent, ' ');
            } else if (block.kind == Kind::item) {
                first_capacity -= 2;
                later_capacity -= 2;
                first_prefix = "- ";
                later_prefix = "  ";
            } else if (block.kind == Kind::enumeration) {
                first_capacity -= 4;
                later_capacity -= 4;
                first_prefix = std::string(2 - block.number.size(), ' ') + block.number + ". ";
                later_prefix = "    ";
            } else if (block.kind == Kind::quote) {
                first_capacity -= 8;
                later_capacity -= 8;
                first_prefix = later_prefix = "    ";
            } else {
                first_capacity -= 12;
                later_capacity -= 12;
                first_prefix = block.term.size() <= 10 ? block.term + std::string(12 - block.term.size(), ' ')
                                                       : std::string(12, ' ');
                later_prefix = std::string(12, ' ');
            }
            const TextResult result =
                layout_text(context, expand(block, context, page_values), first_capacity, later_capacity,
                            block.align, first_prefix, later_prefix, greedy);
            std::vector<LayoutLine> lines = result.lines;
            if (block.kind == Kind::term && block.term.size() >= 11)
                lines.insert(lines.begin(), {block.term});
            add(std::move(lines), LayoutType::flow,
                block.kind == Kind::item || block.kind == Kind::enumeration || block.kind == Kind::term);
            out.reports.push_back(
                {"paragraph " + number(block.body_number), block.align, true, result.measures});
            out.stats[block.body_number - 1] = {int(result.measures.size()), result.cost};
            for (const Measure &line : result.measures)
                if (line.mid)
                    ++out.hyphenated;
        } else if (block.kind == Kind::title || block.kind == Kind::author) {
            const std::string text = block.kind == Kind::title ? upper(block.text) : block.text;
            add(plain_lines({std::string((block.width - text.size()) / 2, ' ') + text}), LayoutType::heading);
        } else if (block.kind == Kind::h1 || block.kind == Kind::h2) {
            const std::string text =
                block.number + " " + (block.kind == Kind::h1 ? upper(block.text) : block.text);
            add(plain_lines({text, std::string(text.size(), block.kind == Kind::h1 ? '=' : '-')}),
                LayoutType::heading);
        } else if (block.kind == Kind::table)
            add(plain_lines(render_table(block)), LayoutType::solid);
        else if (block.kind == Kind::verbatim) {
            Lines lines;
            for (const SourceLine &line : block.inner)
                lines.push_back(line.text);
            add(plain_lines(lines), LayoutType::flow);
        } else if (block.kind == Kind::toc || block.kind == Kind::lot) {
            add(plain_lines(block.kind == Kind::toc ? Lines{"CONTENTS", "========"}
                                                    : Lines{"TABLES", "======"}),
                LayoutType::heading);
            std::vector<LayoutLine> lines;
            for (std::size_t target = 0; target < document.blocks.size(); ++target) {
                const Block &entry = document.blocks[target];
                if (block.kind == Kind::toc ? entry.kind == Kind::h1 || entry.kind == Kind::h2
                                            : entry.kind == Kind::table && !entry.caption.empty()) {
                    LayoutLine line;
                    line.text = entry_line(entry, block.width, "??");
                    line.toc_target = target;
                    line.dynamic_width = block.width;
                    lines.push_back(std::move(line));
                }
            }
            add(std::move(lines), LayoutType::flow);
        } else if (block.kind == Kind::index) {
            add(plain_lines({"INDEX", "====="}), LayoutType::heading);
            std::vector<LayoutLine> lines;
            for (std::size_t i = 0; i < index.size(); ++i) {
                LayoutLine line;
                line.text = index[i];
                line.index_entry = i;
                lines.push_back(std::move(line));
            }
            add(std::move(lines), LayoutType::flow);
        } else {
            add(plain_lines({"REFERENCES", "=========="}), LayoutType::heading);
            for (int id : context.bib_order) {
                const Bib &entry = document.bibliography[id];
                const std::string label = "[" + entry.label + "]";
                const TextData data =
                    text_data(words(entry.author + ". " + entry.year + ". " + entry.title), {}, context);
                const TextResult result = layout_text(
                    context, data, block.width - bibliography_prefix, block.width - bibliography_prefix,
                    "left", label + std::string(bibliography_prefix - label.size(), ' '),
                    std::string(bibliography_prefix, ' '), greedy);
                add(result.lines, LayoutType::flow, true);
                out.reports.push_back({"reference " + entry.label, "left", false, result.measures});
            }
        }
    }
    const std::vector<Page> raw = build_pages(layout_blocks, out.footnotes, context.params, document.height);
    for (const Page &page : raw) {
        const bool chapter = !page.content.empty() && page.content[0].first_block >= 0 &&
                             document.blocks[page.content[0].first_block].kind == Kind::h1;
        if (chapter && (out.pages.size() + 1) % 2 == 0) {
            Page blank;
            blank.blank = true;
            out.pages.push_back(blank);
        }
        out.pages.push_back(page);
    }
    out.block_pages.assign(document.blocks.size(), 0);
    for (std::size_t page = 0; page < out.pages.size(); ++page)
        for (const LayoutLine &line : out.pages[page].content)
            if (line.first_block >= 0)
                out.block_pages[line.first_block] = page + 1;
    for (std::size_t b = 0; b < document.blocks.size(); ++b)
        if (document.blocks[b].kind == Kind::h1) {
            out.front = out.block_pages[b] - 1;
            break;
        }
    for (std::size_t page = 0; page < out.pages.size(); ++page) {
        Page &result = out.pages[page];
        result.body_number = int(page + 1) - out.front;
        result.display = int(page + 1) <= out.front ? roman(page + 1) : number(result.body_number);
    }
    out.index_pages.assign(context.index_phrases.size(), 0);
    for (const Page &page : out.pages)
        for (const LayoutLine &line : page.content)
            for (int id : line.indices)
                out.index_pages[id] = page.body_number;
    out.reports.insert(out.reports.end(), footnote_reports.begin(), footnote_reports.end());
    return out;
}
static Layout layout(const Context &context, bool greedy) {
    std::map<std::string, std::string> values;
    for (const auto &label : context.labels)
        values[label.first] = "??";
    Layout result;
    while (true) {
        result = layout_once(context, values, greedy);
        std::map<std::string, std::string> computed;
        for (const auto &label : context.labels)
            computed[label.first] = result.pages[result.block_pages[label.second] - 1].display;
        if (computed == values)
            break;
        values = std::move(computed);
    }
    const Lines index = index_lines(context, result.index_pages);
    for (Page &page : result.pages)
        for (LayoutLine &line : page.content) {
            if (line.toc_target >= 0) {
                const int target = line.toc_target;
                line.text = entry_line(context.document.blocks[target], line.dynamic_width,
                                       result.pages[result.block_pages[target] - 1].display);
            }
            if (line.index_entry >= 0)
                line.text = index[line.index_entry];
        }
    return result;
}
static Lines layout_warnings(const Context &context, const Layout &layout, const std::string &method) {
    Lines out;
    const std::string prefix = method + ": ";
    for (const BrokenReport &report : layout.reports)
        for (std::size_t i = 0; i < report.lines.size(); ++i) {
            const Measure &line = report.lines[i];
            const std::string start = prefix + report.name + " line " + number(i + 1) + ": ";
            if (line.slack < 0)
                out.push_back(start + "overfull by " + number(-line.slack));
            else if (report.body && report.alignment == "justify" && !line.last &&
                     line.slack >= context.params.at("underfull_slack"))
                out.push_back(start + "underfull, slack " + number(line.slack));
        }
    for (std::size_t i = 0; i < layout.pages.size(); ++i) {
        const Page &page = layout.pages[i];
        const int empty = context.document.height - page.height;
        if (!page.blank && !page.forced && empty >= context.params.at("underfull_page"))
            out.push_back(prefix + "page " + number(i + 1) + ": underfull, " + number(empty) +
                          " empty lines");
    }
    out.push_back(prefix + number(layout.pages.size()) + " pages, " + number(layout.hyphenated) +
                  " hyphenated lines");
    return out;
}
static void write(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
int main() {
    Context context;
    for (const std::string &line : read_lines("input/params.txt")) {
        const Lines fields = split(line, ' ');
        context.params[fields[0]] = std::stoll(fields[1]);
    }
    context.document = parse_document(read_lines("input/document.txt"));
    for (const std::string &word : read_lines("input/hyphenation.txt"))
        register_word(context.dictionary, word);
    for (const std::string &word : context.document.additions)
        register_word(context.dictionary, word);
    prepare(context);
    const Layout kp = layout(context, false), greedy = layout(context, true);
    write("pages.txt", render_pages(kp.pages, kp.footnotes, context.document, kp.block_pages, kp.front));
    write("greedy_pages.txt",
          render_pages(greedy.pages, greedy.footnotes, context.document, greedy.block_pages, greedy.front));
    Lines stats = {"paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"};
    std::array<Integer, 4> totals{};
    for (std::size_t i = 0; i < kp.stats.size(); ++i) {
        const BodyStat &a = kp.stats[i], &b = greedy.stats[i];
        stats.push_back(number(i + 1) + "," + number(a.lines) + "," + number(a.cost) + "," + number(b.lines) +
                        "," + number(b.cost));
        totals[0] += a.lines;
        totals[1] += a.cost;
        totals[2] += b.lines;
        totals[3] += b.cost;
    }
    stats.push_back("total," + number(totals[0]) + "," + number(totals[1]) + "," + number(totals[2]) + "," +
                    number(totals[3]));
    write("stats.csv", stats);
    Lines logs;
    for (const Warning &warning : context.document.warnings)
        logs.push_back("line " + number(warning.line) + ": " + warning.message);
    for (const std::string &warning : layout_warnings(context, kp, "kp"))
        logs.push_back(warning);
    for (const std::string &warning : layout_warnings(context, greedy, "greedy"))
        logs.push_back(warning);
    write("log.txt", logs);
}
