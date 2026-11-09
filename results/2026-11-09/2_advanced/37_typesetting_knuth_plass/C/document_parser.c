#include "typesetting.h"
bool body_kind(Kind kind) {
    return kind == PARAGRAPH || kind == ITEM || kind == ENUMERATION || kind == QUOTE || kind == TERM;
}
static bool digits(const char *text, int minimum, int maximum) {
    size_t length = strlen(text);
    if (length < (size_t)minimum || length > (size_t)maximum)
        return false;
    for (size_t i = 0; i < length; ++i)
        if (text[i] < '0' || text[i] > '9')
            return false;
    return true;
}
static bool dictionary_word(const char *word) {
    size_t n = strlen(word);
    if (!n || word[0] == '-' || word[n - 1] == '-')
        return false;
    for (size_t i = 0; i < n; ++i)
        if (!((word[i] >= 'a' && word[i] <= 'z') || word[i] == '-') ||
            (word[i] == '-' && i && word[i - 1] == '-'))
            return false;
    return true;
}
static bool valid(const char *name, const char *argument) {
    if (!strcmp(name, "width") || !strcmp(name, "indent") || !strcmp(name, "page")) {
        if (!digits(argument, 1, 9))
            return false;
        int value = atoi(argument);
        return !strcmp(name, "width")    ? value >= 20 && value <= 80
               : !strcmp(name, "indent") ? value <= 8
                                         : value >= 10 && value <= 100;
    }
    if (!strcmp(name, "align"))
        return !strcmp(argument, "left") || !strcmp(argument, "right") || !strcmp(argument, "center") ||
               !strcmp(argument, "justify");
    if (!strcmp(name, "header") || !strcmp(name, "footer")) {
        int count = 0;
        for (size_t i = 0; argument[i]; ++i)
            if (argument[i] == '|')
                ++count;
        return count == 2;
    }
    const char *empty_names[6] = {"newpage", "verbatim", "toc", "lot", "index", "bibliography"};
    for (int i = 0; i < 6; ++i)
        if (!strcmp(name, empty_names[i]))
            return !*argument;
    if (!strcmp(name, "hyphenation")) {
        Lines values = split(argument, ' ');
        for (size_t i = 0; i < values.len; ++i)
            if (!dictionary_word(values.data[i]))
                return false;
        return values.len > 0;
    }
    if (!strcmp(name, "bib")) {
        const char *first = strchr(argument, ' ');
        if (!first || first == argument)
            return false;
        for (const char *c = argument; c < first; ++c)
            if (!((*c >= 'a' && *c <= 'z') || (*c >= '0' && *c <= '9')))
                return false;
        Lines parts = split(first + 1, '|');
        return parts.len == 3 && *parts.data[0] && digits(parts.data[1], 4, 4) && *parts.data[2];
    }
    if (!strcmp(name, "term")) {
        const char *bar = strchr(argument, '|');
        return bar && bar > argument && bar[1];
    }
    if (!strcmp(name, "table")) {
        const char *end = strchr(argument, ' ');
        size_t length = end ? (size_t)(end - argument) : strlen(argument);
        if (!length)
            return false;
        for (size_t i = 0; i < length; ++i)
            if (argument[i] != 'l' && argument[i] != 'r' && argument[i] != 'c')
                return false;
        return true;
    }
    return *argument != 0;
}
static size_t create(Document *doc, Kind kind, int line, const char *argument, int width, int indent,
                     char *align, bool *pending) {
    if (!doc->blocks.len)
        doc->width = width;
    Block block = {0};
    block.kind = kind;
    block.line = line;
    block.width = width;
    block.indent = indent;
    block.align = align;
    block.text = format("%s", argument);
    block.term = block.columns = block.caption = block.label = block.number = "";
    block.page_break = *pending;
    *pending = false;
    grow((void **)&doc->blocks.data, &doc->blocks.cap, doc->blocks.len + 1, sizeof *doc->blocks.data);
    size_t index = doc->blocks.len++;
    doc->blocks.data[index] = block;
    return index;
}
Document parse_document(Lines lines) {
    Document doc = {0};
    doc.width = 60;
    doc.height = 40;
    for (int i = 0; i < 3; ++i)
        doc.header[i] = doc.footer[i] = "";
    int width = 60, indent = 0, open = -1;
    char *align = "left";
    bool pending = false, accepted[3] = {false, false, false};
    const char *block_names[14] = {"title", "author", "h1",       "h2",  "item", "enum",  "quote",
                                   "term",  "table",  "verbatim", "toc", "lot",  "index", "bibliography"};
    const Kind kinds[14] = {TITLE, AUTHOR, H1,       H2,  ITEM, ENUMERATION, QUOTE,
                            TERM,  TABLE,  VERBATIM, TOC, LOT,  INDEX,       BIBLIOGRAPHY};
    const char *setting_names[9] = {"width",  "indent",  "align",       "page", "header",
                                    "footer", "newpage", "hyphenation", "bib"};
    for (size_t i = 0; i < lines.len; ++i) {
        const char *line = lines.data[i];
        if (!*line) {
            open = -1;
            continue;
        }
        if (line[0] != '.') {
            if (open < 0)
                open = (int)create(&doc, PARAGRAPH, (int)i + 1, "", width, indent, align, &pending);
            source_add(&doc.blocks.data[open].body, (int)i + 1, line);
            continue;
        }
        open = -1;
        const char *space = strchr(line, ' ');
        char *name = space ? format("%.*s", (int)(space - line - 1), line + 1) : format("%s", line + 1);
        char *argument = space ? format("%s", space + 1) : "";
        int kind = -1;
        bool known = false;
        for (int k = 0; k < 14; ++k)
            if (!strcmp(name, block_names[k])) {
                kind = k;
                known = true;
            }
        for (int k = 0; k < 9; ++k)
            if (!strcmp(name, setting_names[k]))
                known = true;
        int preamble = !strcmp(name, "page")     ? 0
                       : !strcmp(name, "header") ? 1
                       : !strcmp(name, "footer") ? 2
                                                 : -1;
        char *warning = NULL;
        if (!known)
            warning = format("unknown directive .%s", name);
        else if (!valid(name, argument))
            warning = format("bad argument for .%s", name);
        else if (preamble >= 0 && doc.blocks.len)
            warning = format(".%s ignored after the preamble", name);
        else if (preamble >= 0 && accepted[preamble])
            warning = format("duplicate .%s", name);
        if (warning) {
            warning_add(&doc, (int)i + 1, warning);
            continue;
        }
        if (!strcmp(name, "width"))
            width = atoi(argument);
        else if (!strcmp(name, "indent"))
            indent = atoi(argument);
        else if (!strcmp(name, "align"))
            align = argument;
        else if (!strcmp(name, "page")) {
            doc.height = atoi(argument);
            accepted[0] = true;
        } else if (!strcmp(name, "header") || !strcmp(name, "footer")) {
            Lines fields = split(argument, '|');
            char **target = !strcmp(name, "header") ? doc.header : doc.footer;
            for (int k = 0; k < 3; ++k)
                target[k] = fields.data[k];
            accepted[preamble] = true;
        } else if (!strcmp(name, "newpage"))
            pending = true;
        else if (!strcmp(name, "hyphenation")) {
            Lines values = split(argument, ' ');
            extend(&doc.additions, values);
        } else if (!strcmp(name, "bib")) {
            const char *first = strchr(argument, ' ');
            Lines fields = split(first + 1, '|');
            Bib entry = {(int)i + 1,
                         format("%.*s", (int)(first - argument), argument),
                         fields.data[0],
                         fields.data[1],
                         fields.data[2],
                         "",
                         "",
                         false};
            grow((void **)&doc.bibliography.data, &doc.bibliography.cap, doc.bibliography.len + 1,
                 sizeof *doc.bibliography.data);
            doc.bibliography.data[doc.bibliography.len++] = entry;
        } else {
            size_t index = create(&doc, kinds[kind], (int)i + 1, argument, width, indent, align, &pending);
            Block *block = &doc.blocks.data[index];
            if (body_kind(block->kind)) {
                char *body = argument;
                if (block->kind == TERM) {
                    char *bar = strchr(argument, '|');
                    block->term = format("%.*s", (int)(bar - argument), argument);
                    body = bar + 1;
                }
                source_add(&block->body, (int)i + 1, body);
                open = (int)index;
            } else if (block->kind == VERBATIM || block->kind == TABLE) {
                if (block->kind == TABLE) {
                    char *first = strchr(argument, ' ');
                    block->columns = first ? format("%.*s", (int)(first - argument), argument) : argument;
                    block->caption = first ? first + 1 : "";
                }
                bool closed = false;
                while (i + 1 < lines.len) {
                    ++i;
                    if (!strcmp(lines.data[i], ".end")) {
                        closed = true;
                        break;
                    }
                    source_add(&block->inner, (int)i + 1, lines.data[i]);
                }
                if (!closed)
                    warning_add(&doc, block->line,
                                block->kind == TABLE ? "unterminated table" : "unterminated verbatim");
            }
        }
    }
    return doc;
}
