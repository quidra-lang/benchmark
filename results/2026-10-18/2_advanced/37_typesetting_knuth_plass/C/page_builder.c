#include "typesetting.h"
typedef struct {
    int end, next;
    bool forced;
} Boundary;
static int boundary_compare(const void *pa, const void *pb) {
    const Boundary *a = pa, *b = pb;
    if (a->end != b->end)
        return a->end < b->end ? -1 : 1;
    if (a->next != b->next)
        return a->next < b->next ? -1 : 1;
    return (int)a->forced - (int)b->forced;
}
Pages build_pages(LayoutBlocks blocks, Lines *footnotes, size_t footnote_count, const Params *p, int height) {
    LayoutLines stream = {0};
    Boundary *boundaries = NULL;
    size_t count = 0, cap = 0;
    for (size_t i = 0; i < blocks.len; ++i) {
        LayoutBlock block = blocks.data[i];
        if (i) {
            int before = (int)stream.len;
            if (!(blocks.data[i - 1].list && block.list))
                layout_line_add(&stream, layout_line(""));
            int after = (int)stream.len;
            if (block.page_break || blocks.data[i - 1].type != HEADING) {
                grow((void **)&boundaries, &cap, count + 1, sizeof *boundaries);
                boundaries[count++] = (Boundary){before, after, block.page_break};
            }
        }
        int start = (int)stream.len;
        for (size_t j = 0; j < block.lines.len; ++j)
            layout_line_add(&stream, block.lines.data[j]);
        if (block.type == FLOW)
            for (int k = 1; k < (int)block.lines.len; ++k)
                if (k >= p->orphan_lines && (Integer)block.lines.len - k >= p->widow_lines) {
                    grow((void **)&boundaries, &cap, count + 1, sizeof *boundaries);
                    boundaries[count++] = (Boundary){start + k, start + k, false};
                }
    }
    grow((void **)&boundaries, &cap, count + 1, sizeof *boundaries);
    boundaries[count++] = (Boundary){(int)stream.len, (int)stream.len, true};
    qsort(boundaries, count, sizeof *boundaries, boundary_compare);
    Pages pages = {0};
    int start = 0;
    while (start < (int)stream.len) {
        Boundary selected = {0};
        Page chosen = {0};
        for (size_t b = 0; b < count; ++b) {
            Boundary boundary = boundaries[b];
            if (boundary.end <= start)
                continue;
            bool *ids = allocate(footnote_count, sizeof *ids);
            for (int i = start; i < boundary.end; ++i)
                for (size_t j = 0; j < stream.data[i].footnotes.len; ++j)
                    ids[stream.data[i].footnotes.data[j]] = true;
            Ints notes = {0};
            int page_height = boundary.end - start;
            for (size_t id = 0; id < footnote_count; ++id)
                if (ids[id]) {
                    int_add(&notes, (int)id);
                    page_height += (int)footnotes[id].len;
                }
            if (notes.len)
                ++page_height;
            if (page_height <= height) {
                selected = boundary;
                free(chosen.content.data);
                free(chosen.footnotes.data);
                chosen = (Page){0};
                for (int i = start; i < boundary.end; ++i)
                    layout_line_add(&chosen.content, stream.data[i]);
                chosen.footnotes = notes;
                chosen.height = page_height;
                chosen.forced = boundary.forced;
            } else
                free(notes.data);
            free(ids);
            if (boundary.forced)
                break;
        }
        page_add(&pages, chosen);
        start = selected.next;
    }
    free(boundaries);
    free(stream.data);
    return pages;
}
