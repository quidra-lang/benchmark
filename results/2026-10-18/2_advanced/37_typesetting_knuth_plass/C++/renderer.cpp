#include "typesetting.hpp"
std::string render_line(const std::vector<Piece> &pieces, const Measure &line, const std::string &align) {
    int gap = 1, remainder = 0;
    if (line.slack > 0 && align == "justify" && !line.last && line.gaps > 0) {
        gap += line.slack / line.gaps;
        remainder = line.slack % line.gaps;
    }
    std::string result;
    for (std::size_t i = 0; i < pieces.size(); ++i) {
        if (i)
            result += std::string(gap + (int(i) - 1 < remainder ? 1 : 0), ' ');
        result += pieces[i].text;
    }
    if (line.slack > 0) {
        if (align == "right")
            result = std::string(line.slack, ' ') + result;
        else if (align == "center")
            result = std::string(line.slack / 2, ' ') + result;
    }
    return result;
}
Lines render_table(const Block &block) {
    std::vector<std::size_t> widths(block.columns.size());
    for (const Lines &row : block.cells)
        for (std::size_t c = 0; c < row.size(); ++c)
            widths[c] = std::max(widths[c], row[c].size());
    Lines out;
    if (!block.caption.empty())
        out.push_back("Table " + block.number + ". " + block.caption);
    for (std::size_t r = 0; r < block.cells.size(); ++r) {
        Lines cells;
        for (std::size_t c = 0; c < widths.size(); ++c) {
            const std::string &value = block.cells[r][c];
            const std::size_t missing = widths[c] - value.size();
            cells.push_back(block.columns[c] == 'l'   ? value + std::string(missing, ' ')
                            : block.columns[c] == 'r' ? std::string(missing, ' ') + value
                                                      : std::string(missing / 2, ' ') + value +
                                                            std::string(missing - missing / 2, ' '));
        }
        out.push_back(rtrim(join(cells, " | ")));
        if (r == 0) {
            Lines rules;
            for (std::size_t width : widths)
                rules.push_back(std::string(width, '-'));
            out.push_back(join(rules, "-+-"));
        }
    }
    return out;
}
static std::string replace(std::string text, const std::string &key, const std::string &value) {
    std::size_t position = 0;
    while ((position = text.find(key, position)) != std::string::npos) {
        text.replace(position, key.size(), value);
        position += value.size();
    }
    return text;
}
std::string running_head(std::array<std::string, 3> fields, const std::map<std::string, std::string> &values,
                         int width, int serial) {
    for (std::string &field : fields)
        for (const auto &entry : values)
            field = replace(field, "{" + entry.first + "}", entry.second);
    if (serial % 2 == 0)
        std::swap(fields[0], fields[2]);
    std::string result(width, ' ');
    result.replace(0, fields[0].size(), fields[0]);
    result.replace((width - int(fields[1].size())) / 2, fields[1].size(), fields[1]);
    result.replace(width - fields[2].size(), fields[2].size(), fields[2]);
    return rtrim(result);
}
Lines render_pages(const std::vector<Page> &pages, const std::vector<Lines> &footnotes,
                   const Document &document, const std::vector<int> &block_pages, int front_matter) {
    Lines out;
    for (std::size_t i = 0; i < pages.size(); ++i) {
        const Page &page = pages[i];
        out.push_back("--- page " + number(i + 1) + " ---");
        std::string chapter, section;
        for (std::size_t b = 0; b < document.blocks.size(); ++b)
            if (block_pages[b] > 0 && block_pages[b] <= int(i + 1)) {
                const Block &block = document.blocks[b];
                if (block.kind == Kind::h1) {
                    chapter = block.number + " " + block.text;
                    section.clear();
                } else if (block.kind == Kind::h2)
                    section = block.number + " " + block.text;
            }
        const bool first_chapter = !page.content.empty() && page.content[0].first_block >= 0 &&
                                   document.blocks[page.content[0].first_block].kind == Kind::h1;
        const std::map<std::string, std::string> fields = {
            {"page", page.display},
            {"pages", number(int(pages.size()) - front_matter)},
            {"chapter", chapter},
            {"section", section}};
        out.push_back(
            page.blank || first_chapter ? "" : running_head(document.header, fields, document.width, i + 1));
        out.push_back("");
        Lines body;
        for (const LayoutLine &line : page.content)
            body.push_back(line.text);
        int note_height = 0;
        for (int id : page.footnotes)
            note_height += footnotes[id].size();
        body.resize(document.height - note_height - (page.footnotes.empty() ? 0 : 1), "");
        if (!page.footnotes.empty()) {
            body.push_back("----------");
            for (int id : page.footnotes)
                body.insert(body.end(), footnotes[id].begin(), footnotes[id].end());
        }
        out.insert(out.end(), body.begin(), body.end());
        out.push_back("");
        out.push_back(page.blank ? "" : running_head(document.footer, fields, document.width, i + 1));
    }
    return out;
}
