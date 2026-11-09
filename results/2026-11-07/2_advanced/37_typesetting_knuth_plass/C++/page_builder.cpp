#include "typesetting.hpp"
std::vector<Page> build_pages(const std::vector<LayoutBlock> &blocks, const std::vector<Lines> &footnotes,
                              const Params &p, int height) {
    struct Boundary {
        int end, next;
        bool forced;
    };
    std::vector<LayoutLine> stream;
    std::vector<Boundary> boundaries;
    for (std::size_t i = 0; i < blocks.size(); ++i) {
        const LayoutBlock &block = blocks[i];
        if (i) {
            const int before = stream.size();
            if (!(blocks[i - 1].list && block.list))
                stream.push_back({});
            const int after = stream.size();
            if (block.page_break || blocks[i - 1].type != LayoutType::heading)
                boundaries.push_back({before, after, block.page_break});
        }
        const int start = stream.size();
        stream.insert(stream.end(), block.lines.begin(), block.lines.end());
        if (block.type == LayoutType::flow)
            for (int k = 1; k < int(block.lines.size()); ++k)
                if (k >= p.at("orphan_lines") && Integer(block.lines.size()) - k >= p.at("widow_lines"))
                    boundaries.push_back({start + k, start + k, false});
    }
    boundaries.push_back({int(stream.size()), int(stream.size()), true});
    std::sort(boundaries.begin(), boundaries.end(), [](const Boundary &a, const Boundary &b) {
        return std::tie(a.end, a.next, a.forced) < std::tie(b.end, b.next, b.forced);
    });
    std::vector<Page> pages;
    int start = 0;
    while (start < int(stream.size())) {
        std::optional<Boundary> selected;
        Page chosen;
        for (const Boundary &boundary : boundaries) {
            if (boundary.end <= start)
                continue;
            std::set<int> ids;
            for (int i = start; i < boundary.end; ++i)
                ids.insert(stream[i].footnotes.begin(), stream[i].footnotes.end());
            int page_height = boundary.end - start;
            if (!ids.empty()) {
                ++page_height;
                for (int id : ids)
                    page_height += footnotes[id].size();
            }
            if (page_height <= height) {
                selected = boundary;
                chosen.content.assign(stream.begin() + start, stream.begin() + boundary.end);
                chosen.footnotes.assign(ids.begin(), ids.end());
                chosen.height = page_height;
                chosen.forced = boundary.forced;
            }
            if (boundary.forced)
                break;
        }
        pages.push_back(std::move(chosen));
        start = selected->next;
    }
    return pages;
}
