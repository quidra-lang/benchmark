#include "typesetting.hpp"
bool body_kind(Kind kind) {
    return kind == Kind::paragraph || kind == Kind::item || kind == Kind::enumeration ||
           kind == Kind::quote || kind == Kind::term;
}
static bool digits(const std::string &text, int min_length = 1, int max_length = 9) {
    return int(text.size()) >= min_length && int(text.size()) <= max_length &&
           std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}
static bool dictionary_word(const std::string &word) {
    if (word.empty() || word.front() == '-' || word.back() == '-')
        return false;
    for (std::size_t i = 0; i < word.size(); ++i)
        if (!((word[i] >= 'a' && word[i] <= 'z') || word[i] == '-') ||
            (word[i] == '-' && i && word[i - 1] == '-'))
            return false;
    return true;
}
static bool valid(const std::string &name, const std::string &argument) {
    if (name == "width" || name == "indent" || name == "page") {
        if (!digits(argument))
            return false;
        const int value = std::stoi(argument);
        return name == "width"    ? value >= 20 && value <= 80
               : name == "indent" ? value <= 8
                                  : value >= 10 && value <= 100;
    }
    if (name == "align")
        return argument == "left" || argument == "right" || argument == "center" || argument == "justify";
    if (name == "header" || name == "footer")
        return std::count(argument.begin(), argument.end(), '|') == 2;
    if (name == "newpage" || name == "verbatim" || name == "toc" || name == "lot" || name == "index" ||
        name == "bibliography")
        return argument.empty();
    if (name == "hyphenation") {
        const Lines values = split(argument, ' ');
        return !values.empty() && std::all_of(values.begin(), values.end(), dictionary_word);
    }
    if (name == "bib") {
        const auto first = argument.find(' ');
        if (first == std::string::npos)
            return false;
        const std::string key = argument.substr(0, first);
        const Lines parts = split(argument.substr(first + 1), '|');
        return !key.empty() &&
               std::all_of(key.begin(), key.end(),
                           [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'); }) &&
               parts.size() == 3 && !parts[0].empty() && digits(parts[1], 4, 4) && !parts[2].empty();
    }
    if (name == "term") {
        const auto bar = argument.find('|');
        return bar != std::string::npos && bar > 0 && bar + 1 < argument.size();
    }
    if (name == "table") {
        const std::string columns = argument.substr(0, argument.find(' '));
        return !columns.empty() && std::all_of(columns.begin(), columns.end(),
                                               [](char c) { return c == 'l' || c == 'r' || c == 'c'; });
    }
    return !argument.empty();
}
Document parse_document(const Lines &lines) {
    Document out;
    int width = 60, indent = 0;
    std::string align = "left";
    std::optional<std::size_t> open;
    bool pending = false;
    std::set<std::string> accepted;
    const std::map<std::string, Kind> kinds = {{"title", Kind::title}, {"author", Kind::author},
                                               {"h1", Kind::h1},       {"h2", Kind::h2},
                                               {"item", Kind::item},   {"enum", Kind::enumeration},
                                               {"quote", Kind::quote}, {"term", Kind::term},
                                               {"table", Kind::table}, {"verbatim", Kind::verbatim},
                                               {"toc", Kind::toc},     {"lot", Kind::lot},
                                               {"index", Kind::index}, {"bibliography", Kind::bibliography}};
    const std::set<std::string> settings = {"width",  "indent",  "align",       "page", "header",
                                            "footer", "newpage", "hyphenation", "bib"};
    auto create = [&](Kind kind, int line, const std::string &argument) {
        if (out.blocks.empty())
            out.width = width;
        Block block;
        block.kind = kind;
        block.line = line;
        block.width = width;
        block.indent = indent;
        block.align = align;
        block.text = argument;
        block.page_break = pending;
        pending = false;
        out.blocks.push_back(std::move(block));
        return out.blocks.size() - 1;
    };
    for (std::size_t i = 0; i < lines.size(); ++i) {
        const std::string &line = lines[i];
        if (line.empty()) {
            open.reset();
            continue;
        }
        if (line[0] != '.') {
            if (!open)
                open = create(Kind::paragraph, i + 1, {});
            out.blocks[*open].body.push_back({int(i + 1), line});
            continue;
        }
        open.reset();
        const auto space = line.find(' ');
        const std::string name = line.substr(1, space == std::string::npos ? std::string::npos : space - 1),
                          argument = space == std::string::npos ? "" : line.substr(space + 1);
        std::string warning;
        if (!kinds.count(name) && !settings.count(name))
            warning = "unknown directive ." + name;
        else if (!valid(name, argument))
            warning = "bad argument for ." + name;
        else if ((name == "page" || name == "header" || name == "footer") && !out.blocks.empty())
            warning = "." + name + " ignored after the preamble";
        else if ((name == "page" || name == "header" || name == "footer") && accepted.count(name))
            warning = "duplicate ." + name;
        if (!warning.empty()) {
            out.warnings.push_back({int(i + 1), warning});
            continue;
        }
        if (name == "width")
            width = std::stoi(argument);
        else if (name == "indent")
            indent = std::stoi(argument);
        else if (name == "align")
            align = argument;
        else if (name == "page") {
            out.height = std::stoi(argument);
            accepted.insert(name);
        } else if (name == "header" || name == "footer") {
            const Lines parts = split(argument, '|');
            auto &fields = name == "header" ? out.header : out.footer;
            std::copy(parts.begin(), parts.end(), fields.begin());
            accepted.insert(name);
        } else if (name == "newpage")
            pending = true;
        else if (name == "hyphenation") {
            const Lines parts = split(argument, ' ');
            out.additions.insert(out.additions.end(), parts.begin(), parts.end());
        } else if (name == "bib") {
            const auto first = argument.find(' ');
            const Lines parts = split(argument.substr(first + 1), '|');
            out.bibliography.push_back(
                {int(i + 1), argument.substr(0, first), parts[0], parts[1], parts[2], {}, {}, false});
        } else {
            const std::size_t index = create(kinds.at(name), i + 1, argument);
            Block &block = out.blocks[index];
            if (body_kind(block.kind)) {
                std::string body = argument;
                if (block.kind == Kind::term) {
                    const auto bar = argument.find('|');
                    block.term = argument.substr(0, bar);
                    body = argument.substr(bar + 1);
                }
                block.body.push_back({int(i + 1), body});
                open = index;
            } else if (block.kind == Kind::verbatim || block.kind == Kind::table) {
                if (block.kind == Kind::table) {
                    const auto first = argument.find(' ');
                    block.columns = argument.substr(0, first);
                    block.caption = first == std::string::npos ? "" : argument.substr(first + 1);
                }
                bool closed = false;
                while (i + 1 < lines.size()) {
                    ++i;
                    if (lines[i] == ".end") {
                        closed = true;
                        break;
                    }
                    block.inner.push_back({int(i + 1), lines[i]});
                }
                if (!closed)
                    out.warnings.push_back({block.line, block.kind == Kind::table ? "unterminated table"
                                                                                  : "unterminated verbatim"});
            }
        }
    }
    return out;
}
