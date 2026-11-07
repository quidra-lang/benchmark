#include "typesetting.h"
char *render_line(Pieces pieces, Measure line, const char *align) {
    int gap = 1, remainder = 0;
    if (line.slack > 0 && !strcmp(align, "justify") && !line.last && line.gaps > 0) {
        gap += line.slack / line.gaps;
        remainder = line.slack % line.gaps;
    }
    Text out = {0};
    if (line.slack > 0) {
        if (!strcmp(align, "right"))
            text_add(&out, "%s", spaces(line.slack));
        else if (!strcmp(align, "center"))
            text_add(&out, "%s", spaces(line.slack / 2));
    }
    for (size_t i = 0; i < pieces.len; ++i) {
        if (i)
            text_add(&out, "%s", spaces(gap + ((int)i - 1 < remainder ? 1 : 0)));
        text_add(&out, "%s", pieces.data[i].text);
    }
    return out.data;
}
Lines render_table(const Block *block) {
    size_t count = strlen(block->columns);
    int *widths = allocate(count, sizeof *widths);
    for (size_t r = 0; r < block->inner.len; ++r)
        for (size_t c = 0; c < count; ++c)
            if ((int)strlen(block->cells[r].data[c]) > widths[c])
                widths[c] = (int)strlen(block->cells[r].data[c]);
    Lines out = {0};
    if (*block->caption)
        line_add(&out, "Table %s. %s", block->number, block->caption);
    for (size_t r = 0; r < block->inner.len; ++r) {
        Lines cells = {0};
        for (size_t c = 0; c < count; ++c) {
            const char *value = block->cells[r].data[c];
            int missing = widths[c] - (int)strlen(value);
            char align = block->columns[c];
            line_add(&cells, "%s%s%s",
                     align == 'r'   ? spaces(missing)
                     : align == 'c' ? spaces(missing / 2)
                                    : "",
                     value,
                     align == 'l'   ? spaces(missing)
                     : align == 'c' ? spaces(missing - missing / 2)
                                    : "");
        }
        line_add(&out, "%s", rtrim(join(cells, " | ")));
        if (!r) {
            Lines rules = {0};
            for (size_t c = 0; c < count; ++c) {
                char *rule = spaces(widths[c]);
                memset(rule, '-', (size_t)widths[c]);
                line_add(&rules, "%s", rule);
            }
            line_add(&out, "%s", join(rules, "-+-"));
        }
    }
    free(widths);
    return out;
}
static char *replace(const char *text, const char *key, const char *value) {
    Text out = {0};
    const char *cursor = text;
    size_t size = strlen(key);
    for (;;) {
        const char *found = strstr(cursor, key);
        if (!found) {
            text_add(&out, "%s", cursor);
            break;
        }
        text_add(&out, "%.*s%s", (int)(found - cursor), cursor, value);
        cursor = found + size;
    }
    return out.data;
}
char *running_head(char *const fields[3], HeadValues values, int width, int serial) {
    const char *keys[4] = {"{page}", "{pages}", "{chapter}", "{section}"};
    const char *contents[4] = {values.page, values.pages, values.chapter, values.section};
    char *parts[3];
    for (int i = 0; i < 3; ++i) {
        parts[i] = fields[i];
        for (int k = 0; k < 4; ++k)
            parts[i] = replace(parts[i], keys[k], contents[k]);
    }
    if (serial % 2 == 0) {
        char *value = parts[0];
        parts[0] = parts[2];
        parts[2] = value;
    }
    char *result = spaces(width);
    memcpy(result, parts[0], strlen(parts[0]));
    memcpy(result + (width - (int)strlen(parts[1])) / 2, parts[1], strlen(parts[1]));
    memcpy(result + width - strlen(parts[2]), parts[2], strlen(parts[2]));
    return rtrim(result);
}
Lines render_pages(Pages pages, Lines *footnotes, const Document *document, const int *block_pages,
                   int front) {
    Lines out = {0};
    for (size_t i = 0; i < pages.len; ++i) {
        Page page = pages.data[i];
        line_add(&out, "--- page %zu ---", i + 1);
        char *chapter = "", *section = "";
        for (size_t b = 0; b < document->blocks.len; ++b)
            if (block_pages[b] > 0 && block_pages[b] <= (int)i + 1) {
                Block block = document->blocks.data[b];
                if (block.kind == H1) {
                    chapter = format("%s %s", block.number, block.text);
                    section = "";
                } else if (block.kind == H2)
                    section = format("%s %s", block.number, block.text);
            }
        bool first_chapter = page.content.len && page.content.data[0].first_block >= 0 &&
                             document->blocks.data[page.content.data[0].first_block].kind == H1;
        HeadValues fields = {page.display, number((Integer)pages.len - front), chapter, section};
        line_add(&out, "%s",
                 page.blank || first_chapter
                     ? ""
                     : running_head(document->header, fields, document->width, (int)i + 1));
        line_add(&out, "");
        int note_height = 0;
        for (size_t n = 0; n < page.footnotes.len; ++n)
            note_height += (int)footnotes[page.footnotes.data[n]].len;
        for (size_t l = 0; l < page.content.len; ++l)
            line_add(&out, "%s", page.content.data[l].text);
        int pad = document->height - note_height - (page.footnotes.len ? 1 : 0) - (int)page.content.len;
        for (int l = 0; l < pad; ++l)
            line_add(&out, "");
        if (page.footnotes.len) {
            line_add(&out, "----------");
            for (size_t n = 0; n < page.footnotes.len; ++n)
                extend(&out, footnotes[page.footnotes.data[n]]);
        }
        line_add(&out, "");
        line_add(&out, "%s",
                 page.blank ? "" : running_head(document->footer, fields, document->width, (int)i + 1));
    }
    return out;
}
