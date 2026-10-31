#include "typesetting.h"
void *allocate(size_t count, size_t size) {
    void *value = calloc(count ? count : 1, size);
    if (!value)
        exit(EXIT_FAILURE);
    return value;
}
void grow(void **data, size_t *cap, size_t need, size_t size) {
    if (need <= *cap)
        return;
    size_t next = *cap ? *cap : 8;
    while (next < need)
        next *= 2;
    void *value = realloc(*data, next * size);
    if (!value)
        exit(EXIT_FAILURE);
    *data = value;
    *cap = next;
}
static char *vformat(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)count + 1, 1);
    vsnprintf(out, (size_t)count + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = vformat(pattern, args);
    va_end(args);
    return out;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    size_t length = strlen(value);
    grow((void **)&text->data, &text->cap, text->len + length + 1, 1);
    memcpy(text->data + text->len, value, length + 1);
    text->len += length;
    free(value);
}
void line_add(Lines *lines, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    grow((void **)&lines->data, &lines->cap, lines->len + 1, sizeof *lines->data);
    lines->data[lines->len++] = value;
}
void extend(Lines *out, Lines lines) {
    for (size_t i = 0; i < lines.len; ++i)
        line_add(out, "%s", lines.data[i]);
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(EXIT_FAILURE);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *data = allocate((size_t)length + 1, 1);
    size_t size = fread(data, 1, (size_t)length, file);
    fclose(file);
    Lines lines = {0};
    size_t first = 0;
    for (size_t i = 0; i < size; ++i)
        if (data[i] == '\n') {
            data[i] = 0;
            line_add(&lines, "%s", data + first);
            first = i + 1;
        }
    return lines;
}
void int_add(Ints *values, int value) {
    grow((void **)&values->data, &values->cap, values->len + 1, sizeof *values->data);
    values->data[values->len++] = value;
}
void source_add(SourceLines *values, int line, const char *text) {
    grow((void **)&values->data, &values->cap, values->len + 1, sizeof *values->data);
    values->data[values->len++] = (SourceLine){line, format("%s", text)};
}
void token_add(Tokens *values, const char *kind, const char *text, int id) {
    grow((void **)&values->data, &values->cap, values->len + 1, sizeof *values->data);
    values->data[values->len++] = (Inline){format("%s", kind), format("%s", text), id};
}
void warning_add(Document *doc, int line, const char *message) {
    grow((void **)&doc->warnings.data, &doc->warnings.cap, doc->warnings.len + 1, sizeof *doc->warnings.data);
    size_t index = doc->warnings.len++;
    doc->warnings.data[index] = (Warning){line, format("%s", message), index};
}
Lines split(const char *text, char delimiter) {
    Lines out = {0};
    size_t first = 0, length = strlen(text);
    for (size_t i = 0; i <= length; ++i)
        if (i == length || text[i] == delimiter) {
            line_add(&out, "%.*s", (int)(i - first), text + first);
            first = i + 1;
        }
    return out;
}
Lines words(const char *text) {
    Lines out = {0}, values = split(text, ' ');
    for (size_t i = 0; i < values.len; ++i)
        if (*values.data[i])
            line_add(&out, "%s", values.data[i]);
    return out;
}
char *join(Lines values, const char *delimiter) {
    Text out = {0};
    for (size_t i = 0; i < values.len; ++i)
        text_add(&out, "%s%s", i ? delimiter : "", values.data[i]);
    return out.data ? out.data : "";
}
char *number(Integer value) {
    return format("%" PRId64, value);
}
char *lower(const char *value) {
    char *out = format("%s", value);
    for (size_t i = 0; out[i]; ++i)
        if (out[i] >= 'A' && out[i] <= 'Z')
            out[i] = (char)(out[i] - 'A' + 'a');
    return out;
}
char *upper(const char *value) {
    char *out = format("%s", value);
    for (size_t i = 0; out[i]; ++i)
        if (out[i] >= 'a' && out[i] <= 'z')
            out[i] = (char)(out[i] - 'a' + 'A');
    return out;
}
char *rtrim(const char *value) {
    size_t n = strlen(value);
    while (n && value[n - 1] == ' ')
        --n;
    return format("%.*s", (int)n, value);
}
char *trim(const char *value) {
    while (*value == ' ')
        ++value;
    return rtrim(value);
}
char *spaces(int count) {
    char *out = allocate((size_t)count + 1, 1);
    memset(out, ' ', (size_t)count);
    return out;
}
bool letter(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}
LayoutLine layout_line(const char *text) {
    LayoutLine out = {0};
    out.text = format("%s", text);
    out.first_block = out.toc_target = out.index_entry = -1;
    return out;
}
void layout_line_add(LayoutLines *lines, LayoutLine line) {
    grow((void **)&lines->data, &lines->cap, lines->len + 1, sizeof *lines->data);
    lines->data[lines->len++] = line;
}
void page_add(Pages *pages, Page page) {
    grow((void **)&pages->data, &pages->cap, pages->len + 1, sizeof *pages->data);
    pages->data[pages->len++] = page;
}
typedef struct {
    char *key;
    int block;
} Label;
typedef struct {
    Label *data;
    size_t len, cap;
} Labels;
typedef struct {
    Document document;
    Params params;
    Dictionary dictionary;
    Labels labels;
    Ints bib_order;
    Lines footnotes, index_phrases;
} Context;
static int label_index(const Context *c, const char *key) {
    for (size_t i = 0; i < c->labels.len; ++i)
        if (!strcmp(c->labels.data[i].key, key))
            return (int)i;
    return -1;
}
static int bib_index(Bibs entries, const char *key) {
    for (size_t i = 0; i < entries.len; ++i)
        if (!strcmp(entries.data[i].key, key))
            return (int)i;
    return -1;
}
static void remove_label(char **text, char **label) {
    size_t size = strlen(*text);
    if (!size || (*text)[size - 1] != '}')
        return;
    char *position = NULL, *cursor = *text;
    while ((cursor = strstr(cursor, " {#")) != NULL) {
        position = cursor;
        ++cursor;
    }
    if (!position)
        return;
    *label = format("%.*s", (int)(*text + size - position - 4), position + 3);
    *text = format("%.*s", (int)(position - *text), *text);
}
static Lines author_parts(const char *author) {
    Lines out = {0};
    const char *first = author;
    for (;;) {
        const char *next = strstr(first, " and ");
        if (!next) {
            line_add(&out, "%s", first);
            break;
        }
        line_add(&out, "%.*s", (int)(next - first), first);
        first = next + 5;
    }
    return out;
}
static int bib_compare(const Context *c, int a, int b) {
    const Bib *x = &c->document.bibliography.data[a], *y = &c->document.bibliography.data[b];
    int value = strcmp(x->base, y->base);
    if (!value)
        value = strcmp(x->author, y->author);
    if (!value)
        value = strcmp(x->title, y->title);
    if (!value)
        value = strcmp(x->key, y->key);
    return value;
}
static int warning_compare(const void *pa, const void *pb) {
    const Warning *a = pa, *b = pb;
    if (a->line != b->line)
        return a->line < b->line ? -1 : 1;
    return a->sequence < b->sequence ? -1 : a->sequence > b->sequence;
}
static void prepare(Context *c) {
    Document *doc = &c->document;
    int chapter = 0, section = 0, table = 0, body = 0;
    for (size_t i = 0; i < doc->blocks.len; ++i) {
        Block *b = &doc->blocks.data[i];
        if (b->kind == H1 || b->kind == H2) {
            remove_label(&b->text, &b->label);
            if (b->kind == H1) {
                ++chapter;
                section = 0;
                b->number = number(chapter);
                if (i)
                    b->page_break = true;
            } else
                b->number = format("%d.%d", chapter, ++section);
        } else if (b->kind == TABLE) {
            remove_label(&b->caption, &b->label);
            if (*b->caption)
                b->number = number(++table);
        } else if (b->kind == ENUMERATION)
            b->number = number(i && doc->blocks.data[i - 1].kind == ENUMERATION
                                   ? atoi(doc->blocks.data[i - 1].number) + 1
                                   : 1);
        if (*b->label) {
            if (label_index(c, b->label) >= 0) {
                warning_add(doc, b->line, format("duplicate label %s", b->label));
                b->label = "";
            } else {
                grow((void **)&c->labels.data, &c->labels.cap, c->labels.len + 1, sizeof *c->labels.data);
                c->labels.data[c->labels.len++] = (Label){b->label, (int)i};
            }
        }
        if (b->kind == PARAGRAPH && i &&
            (doc->blocks.data[i - 1].kind == H1 || doc->blocks.data[i - 1].kind == H2))
            b->indent = 0;
        if (body_kind(b->kind))
            b->body_number = ++body;
    }
    Bibs unique = {0};
    for (size_t i = 0; i < doc->bibliography.len; ++i) {
        Bib entry = doc->bibliography.data[i];
        if (bib_index(unique, entry.key) >= 0)
            warning_add(doc, entry.line, format("duplicate bibliography key %s", entry.key));
        else {
            grow((void **)&unique.data, &unique.cap, unique.len + 1, sizeof *unique.data);
            unique.data[unique.len++] = entry;
        }
    }
    doc->bibliography = unique;
    for (size_t b = 0; b < doc->blocks.len; ++b) {
        Block *block = &doc->blocks.data[b];
        if (block->kind == TABLE) {
            size_t count = strlen(block->columns);
            block->cells = allocate(block->inner.len, sizeof *block->cells);
            for (size_t i = 0; i < block->inner.len; ++i) {
                SourceLine line = block->inner.data[i];
                Lines cells = split(line.text, '|');
                for (size_t j = 0; j < cells.len; ++j)
                    cells.data[j] = trim(cells.data[j]);
                if (cells.len != count)
                    warning_add(doc, line.line,
                                format("table row has %zu cells, expected %zu", cells.len, count));
                Lines corrected = {0};
                for (size_t j = 0; j < count; ++j)
                    line_add(&corrected, "%s", j < cells.len ? cells.data[j] : "");
                block->cells[i] = corrected;
            }
            Lines lines = render_table(block);
            size_t width = 0;
            for (size_t i = 0; i < lines.len; ++i)
                if (strlen(lines.data[i]) > width)
                    width = strlen(lines.data[i]);
            if (width > (size_t)block->width)
                warning_add(doc, block->line, format("table too wide by %zu", width - (size_t)block->width));
        } else if (block->kind == VERBATIM) {
            for (size_t i = 0; i < block->inner.len; ++i) {
                SourceLine line = block->inner.data[i];
                if (strlen(line.text) > (size_t)block->width)
                    warning_add(
                        doc, line.line,
                        format("verbatim line too long by %zu", strlen(line.text) - (size_t)block->width));
            }
        } else if (body_kind(block->kind)) {
            for (size_t l = 0; l < block->body.len; ++l) {
                if (l)
                    token_add(&block->tokens, "text", " ", -1);
                SourceLine source = block->body.data[l];
                const char *cursor = source.text;
                while (*cursor) {
                    const char *brace = strchr(cursor, '{');
                    if (!brace) {
                        token_add(&block->tokens, "text", cursor, -1);
                        break;
                    }
                    token_add(&block->tokens, "text", format("%.*s", (int)(brace - cursor), cursor), -1);
                    const char *close = strchr(brace + 1, '}');
                    if (!close) {
                        warning_add(doc, source.line, "unclosed brace");
                        token_add(&block->tokens, "text", brace, -1);
                        break;
                    }
                    char *content = format("%.*s", (int)(close - brace - 1), brace + 1);
                    char *colon = strchr(content, ':');
                    char *command = colon ? format("%.*s", (int)(colon - content), content) : content,
                         *argument = colon ? colon + 1 : "";
                    bool known = !strcmp(command, "ref") || !strcmp(command, "page") ||
                                 !strcmp(command, "fn") || !strcmp(command, "idx") ||
                                 !strcmp(command, "cite");
                    if (!colon || !*argument || !known)
                        warning_add(doc, source.line, format("bad command {%s}", content));
                    else {
                        int id = -1;
                        if (!strcmp(command, "ref") || !strcmp(command, "page")) {
                            if (label_index(c, argument) < 0)
                                warning_add(doc, source.line, format("undefined label %s", argument));
                        } else if (!strcmp(command, "cite")) {
                            Lines keys = split(argument, ',');
                            for (size_t k = 0; k < keys.len; ++k) {
                                int index = bib_index(doc->bibliography, keys.data[k]);
                                if (index < 0)
                                    warning_add(doc, source.line,
                                                format("undefined citation %s", keys.data[k]));
                                else
                                    doc->bibliography.data[index].cited = true;
                            }
                        } else if (!strcmp(command, "fn")) {
                            id = (int)c->footnotes.len;
                            line_add(&c->footnotes, "%s", argument);
                        } else {
                            id = (int)c->index_phrases.len;
                            line_add(&c->index_phrases, "%s", argument);
                        }
                        token_add(&block->tokens, command, argument, id);
                    }
                    cursor = close + 1;
                }
            }
        }
    }
    for (size_t i = 0; i < doc->bibliography.len; ++i) {
        Bib *entry = &doc->bibliography.data[i];
        if (!entry->cited) {
            warning_add(doc, entry->line, format("unused bibliography entry %s", entry->key));
            continue;
        }
        Lines surnames = author_parts(entry->author);
        Text base = {0};
        if (surnames.len == 1)
            text_add(&base, "%.3s", surnames.data[0]);
        else {
            size_t count = surnames.len >= 5 ? 3 : surnames.len;
            for (size_t j = 0; j < count; ++j)
                text_add(&base, "%c", surnames.data[j][0]);
            if (surnames.len >= 5)
                text_add(&base, "+");
        }
        text_add(&base, "%s", entry->year + 2);
        entry->base = base.data;
        int_add(&c->bib_order, (int)i);
    }
    for (size_t i = 1; i < c->bib_order.len; ++i) {
        int value = c->bib_order.data[i];
        size_t j = i;
        while (j && bib_compare(c, c->bib_order.data[j - 1], value) > 0) {
            c->bib_order.data[j] = c->bib_order.data[j - 1];
            --j;
        }
        c->bib_order.data[j] = value;
    }
    for (size_t i = 0; i < c->bib_order.len;) {
        size_t end = i + 1;
        while (end < c->bib_order.len && !strcmp(doc->bibliography.data[c->bib_order.data[end]].base,
                                                 doc->bibliography.data[c->bib_order.data[i]].base))
            ++end;
        for (size_t j = i; j < end; ++j) {
            Bib *entry = &doc->bibliography.data[c->bib_order.data[j]];
            entry->label = end - i > 1 ? format("%s%c", entry->base, 'a' + (int)(j - i)) : entry->base;
        }
        i = end;
    }
    qsort(doc->warnings.data, doc->warnings.len, sizeof *doc->warnings.data, warning_compare);
}
typedef struct {
    int word, position, id;
    bool footnote;
} Mark;
typedef struct {
    Mark *data;
    size_t len, cap;
} Marks;
typedef struct {
    int word, position;
    bool after, mid, hyphen;
} BreakPosition;
typedef struct {
    BreakPosition *data;
    size_t len, cap;
} BreakPositions;
typedef struct {
    Lines words;
    Marks marks;
    BreakPositions breaks;
    int *prefix;
} TextData;
static void mark_add(Marks *marks, Mark mark) {
    grow((void **)&marks->data, &marks->cap, marks->len + 1, sizeof *marks->data);
    marks->data[marks->len++] = mark;
}
static void break_add(BreakPositions *positions, BreakPosition point) {
    grow((void **)&positions->data, &positions->cap, positions->len + 1, sizeof *positions->data);
    positions->data[positions->len++] = point;
}
static TextData text_data(Lines values, Marks marks, const Context *c) {
    TextData out = {0};
    out.words = values;
    out.marks = marks;
    out.prefix = allocate(values.len + 1, sizeof *out.prefix);
    break_add(&out.breaks, (BreakPosition){0});
    for (size_t i = 0; i < values.len; ++i) {
        SplitPoints points = split_points(&c->dictionary, values.data[i], &c->params);
        for (size_t j = 0; j < points.len; ++j)
            break_add(&out.breaks,
                      (BreakPosition){(int)i, points.data[j].position, false, true, points.data[j].hyphen});
        break_add(&out.breaks, (BreakPosition){(int)i, (int)strlen(values.data[i]), true, false, false});
        out.prefix[i + 1] = out.prefix[i] + (int)strlen(values.data[i]);
    }
    return out;
}
static int string_compare(const void *pa, const void *pb) {
    const char *const *a = pa, *const *b = pb;
    return strcmp(*a, *b);
}
static TextData expand(const Block *block, const Context *c, char **page_values) {
    Text expanded = {0};
    Marks raw = {0};
    for (size_t i = 0; i < block->tokens.len; ++i) {
        Inline token = block->tokens.data[i];
        if (!strcmp(token.kind, "text"))
            text_add(&expanded, "%s", token.text);
        else if (!strcmp(token.kind, "ref") || !strcmp(token.kind, "page")) {
            int label = label_index(c, token.text);
            text_add(&expanded, "%s",
                     label < 0 ? "??"
                     : !strcmp(token.kind, "ref")
                         ? c->document.blocks.data[c->labels.data[label].block].number
                         : page_values[label]);
        } else if (!strcmp(token.kind, "fn")) {
            mark_add(&raw, (Mark){(int)expanded.len, 0, token.id, true});
            text_add(&expanded, "[%d]", token.id + 1);
        } else if (!strcmp(token.kind, "idx"))
            mark_add(&raw, (Mark){(int)expanded.len - 1, 0, token.id, false});
        else {
            Lines keys = split(token.text, ','), labels = {0};
            bool missing = false;
            for (size_t k = 0; k < keys.len; ++k) {
                int found = bib_index(c->document.bibliography, keys.data[k]);
                if (found < 0)
                    missing = true;
                else
                    line_add(&labels, "%s", c->document.bibliography.data[found].label);
            }
            qsort(labels.data, labels.len, sizeof *labels.data, string_compare);
            Lines unique = {0};
            for (size_t k = 0; k < labels.len; ++k)
                if (!k || strcmp(labels.data[k], labels.data[k - 1]))
                    line_add(&unique, "%s", labels.data[k]);
            if (missing)
                line_add(&unique, "?");
            text_add(&expanded, "[%s]", join(unique, ", "));
        }
    }
    Lines values = {0};
    Ints starts = {0};
    for (size_t i = 0; i < expanded.len;) {
        if (expanded.data[i] == ' ') {
            ++i;
            continue;
        }
        size_t start = i;
        while (i < expanded.len && expanded.data[i] != ' ')
            ++i;
        int_add(&starts, (int)start);
        line_add(&values, "%.*s", (int)(i - start), expanded.data + start);
    }
    Marks located = {0};
    for (size_t i = 0; i < raw.len; ++i) {
        Mark mark = raw.data[i];
        int word = 0;
        while (word + 1 < (int)starts.len && starts.data[word + 1] <= mark.word)
            ++word;
        mark_add(&located, (Mark){word, mark.word - starts.data[word], mark.id, mark.footnote});
    }
    return text_data(values, located, c);
}
typedef struct {
    const TextData *text;
    int first, later;
} MeasureContext;
static Measure measure_line(void *context, int a, int b) {
    MeasureContext *c = context;
    const TextData *t = c->text;
    BreakPosition start = t->breaks.data[a], end = t->breaks.data[b];
    int word = start.after ? start.word + 1 : start.word, position = start.after ? 0 : start.position,
        gaps = end.word - word,
        length =
            t->prefix[end.word] - t->prefix[word] - position + end.position + gaps + (end.hyphen ? 1 : 0);
    return (Measure){
        length,   (a == 0 ? c->first : c->later) - length, gaps, end.mid, b == (int)t->breaks.len - 1,
        start.mid};
}
static Pieces pieces(const TextData *t, int a, int b) {
    BreakPosition start = t->breaks.data[a], end = t->breaks.data[b];
    int word1 = start.after ? start.word + 1 : start.word, position = start.after ? 0 : start.position;
    Pieces out = {0};
    for (int word = word1; word <= end.word; ++word) {
        int first = word == word1 ? position : 0,
            last = word == end.word ? end.position : (int)strlen(t->words.data[word]);
        char *text = format("%.*s", last - first, t->words.data[word] + first);
        for (size_t i = 0; text[i]; ++i)
            if (text[i] == '~')
                text[i] = ' ';
        if (word == end.word && end.hyphen)
            text = format("%s-", text);
        grow((void **)&out.data, &out.cap, out.len + 1, sizeof *out.data);
        out.data[out.len++] = (Piece){word, first, last, text};
    }
    return out;
}
typedef struct {
    LayoutLines lines;
    Measures measures;
    Integer cost;
} TextResult;
static TextResult layout_text(const Context *c, const TextData *text, int first, int later,
                              const char *alignment, const char *first_prefix, const char *later_prefix,
                              bool greedy) {
    MeasureContext context = {text, first, later};
    Breaking breaking = break_lines((int)text->breaks.len - 1, measure_line, &context, &c->params, greedy);
    TextResult out = {0};
    out.cost = breaking.cost;
    int a = 0;
    for (size_t i = 0; i < breaking.ends.len; ++i) {
        int b = breaking.ends.data[i];
        Measure line = measure_line(&context, a, b);
        Pieces parts = pieces(text, a, b);
        LayoutLine displayed = layout_line(
            format("%s%s", a == 0 ? first_prefix : later_prefix, render_line(parts, line, alignment)));
        for (size_t j = 0; j < text->marks.len; ++j) {
            Mark mark = text->marks.data[j];
            for (size_t k = 0; k < parts.len; ++k) {
                Piece piece = parts.data[k];
                if (mark.word == piece.word && piece.first <= mark.position && mark.position < piece.last) {
                    if (mark.footnote)
                        int_add(&displayed.footnotes, mark.id);
                    else
                        int_add(&displayed.indices, mark.id);
                }
            }
        }
        layout_line_add(&out.lines, displayed);
        grow((void **)&out.measures.data, &out.measures.cap, out.measures.len + 1, sizeof *out.measures.data);
        out.measures.data[out.measures.len++] = line;
        a = b;
    }
    return out;
}
typedef struct {
    char *name, *alignment;
    bool body;
    Measures lines;
} BrokenReport;
typedef struct {
    BrokenReport *data;
    size_t len, cap;
} Reports;
typedef struct {
    int lines;
    Integer cost;
} BodyStat;
typedef struct {
    Pages pages;
    Lines *footnotes;
    int *block_pages, *index_pages;
    BodyStat *stats;
    size_t stat_count;
    Reports reports;
    int front, hyphenated;
} Layout;
static void report_add(Reports *reports, const char *name, const char *alignment, bool body, Measures lines) {
    grow((void **)&reports->data, &reports->cap, reports->len + 1, sizeof *reports->data);
    reports->data[reports->len++] = (BrokenReport){format("%s", name), format("%s", alignment), body, lines};
}
static char *roman(int value) {
    const char *small[10] = {"", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"};
    Text text = {0};
    for (int i = 0; i < value / 10; ++i)
        text_add(&text, "x");
    text_add(&text, "%s", small[value % 10]);
    return text.data;
}
static int integer_compare(const void *pa, const void *pb) {
    int a = *(const int *)pa, b = *(const int *)pb;
    return a < b ? -1 : a > b;
}
static char *page_list(Ints pages) {
    qsort(pages.data, pages.len, sizeof *pages.data, integer_compare);
    Ints unique = {0};
    for (size_t i = 0; i < pages.len; ++i)
        if (!i || pages.data[i] != pages.data[i - 1])
            int_add(&unique, pages.data[i]);
    Lines values = {0};
    for (size_t i = 0; i < unique.len;) {
        size_t end = i + 1;
        while (end < unique.len && unique.data[end] == unique.data[end - 1] + 1)
            ++end;
        if (end - i >= 3)
            line_add(&values, "%d-%d", unique.data[i], unique.data[end - 1]);
        else
            for (size_t j = i; j < end; ++j)
                line_add(&values, "%d", unique.data[j]);
        i = end;
    }
    return join(values, ", ");
}
typedef struct IndexEntry IndexEntry;
struct IndexEntry {
    char *name, *key;
    Ints pages;
    Lines references;
    IndexEntry *children;
    size_t child_count, child_cap;
};
static IndexEntry *index_entry(IndexEntry **data, size_t *count, size_t *cap, const char *name) {
    for (size_t i = 0; i < *count; ++i)
        if (!strcmp((*data)[i].name, name))
            return &(*data)[i];
    grow((void **)data, cap, *count + 1, sizeof **data);
    IndexEntry entry = {0};
    entry.name = format("%s", name);
    entry.key = lower(name);
    (*data)[(*count)++] = entry;
    return &(*data)[*count - 1];
}
static int index_compare(const void *pa, const void *pb) {
    const IndexEntry *a = pa, *b = pb;
    int result = strcmp(a->key, b->key);
    return result ? result : strcmp(a->name, b->name);
}
static char *index_line(const char *name, IndexEntry *entry) {
    Text text = {0};
    text_add(&text, "%s", name);
    if (entry->pages.len)
        text_add(&text, ", %s", page_list(entry->pages));
    if (entry->references.len) {
        qsort(entry->references.data, entry->references.len, sizeof *entry->references.data, string_compare);
        Lines unique = {0};
        for (size_t i = 0; i < entry->references.len; ++i)
            if (!i || strcmp(entry->references.data[i], entry->references.data[i - 1]))
                line_add(&unique, "%s", entry->references.data[i]);
        text_add(&text, ", see %s", join(unique, ", "));
    }
    return text.data;
}
static Lines index_lines(const Context *c, const int *pages) {
    IndexEntry *parents = NULL;
    size_t count = 0, cap = 0;
    for (size_t i = 0; i < c->index_phrases.len; ++i) {
        const char *phrase = c->index_phrases.data[i], *bar = strchr(phrase, '|');
        char *entry = bar ? format("%.*s", (int)(bar - phrase), phrase) : format("%s", phrase);
        char *bang = strchr(entry, '!'), *parent = bang ? format("%.*s", (int)(bang - entry), entry) : entry;
        IndexEntry *node = index_entry(&parents, &count, &cap, parent);
        if (bang)
            node = index_entry(&node->children, &node->child_count, &node->child_cap, bang + 1);
        if (bar)
            line_add(&node->references, "%s", bar + 1);
        else
            int_add(&node->pages, pages[i]);
    }
    qsort(parents, count, sizeof *parents, index_compare);
    Lines out = {0};
    char *previous = "";
    for (size_t i = 0; i < count; ++i) {
        IndexEntry *entry = &parents[i];
        char *group = letter(entry->name[0]) ? upper(format("%c", entry->name[0])) : "Symbols";
        if (strcmp(group, previous)) {
            line_add(&out, "%s", group);
            previous = group;
        }
        line_add(&out, "%s", index_line(entry->name, entry));
        qsort(entry->children, entry->child_count, sizeof *entry->children, index_compare);
        for (size_t j = 0; j < entry->child_count; ++j)
            line_add(&out, "%s", index_line(format("  %s", entry->children[j].name), &entry->children[j]));
    }
    return out;
}
static char *entry_line(const Block *target, int width, const char *page) {
    char *left = target->kind == TABLE
                     ? format("Table %s. %s", target->number, target->caption)
                     : format("%s%s %s", target->kind == H2 ? "  " : "", target->number, target->text);
    int count = width - (int)strlen(left) - (int)strlen(page) - 2;
    char *dots = spaces(count);
    memset(dots, '.', (size_t)count);
    return format("%s %s %s", left, dots, page);
}
static LayoutLines plain_lines(Lines lines) {
    LayoutLines out = {0};
    for (size_t i = 0; i < lines.len; ++i)
        layout_line_add(&out, layout_line(lines.data[i]));
    return out;
}
static void add_layout(LayoutBlocks *out, LayoutLines lines, LayoutType type, bool list, bool page_break,
                       bool *first, int block) {
    if (*first && lines.len)
        lines.data[0].first_block = block;
    LayoutBlock result = {lines, type, list, *first && page_break};
    grow((void **)&out->data, &out->cap, out->len + 1, sizeof *out->data);
    out->data[out->len++] = result;
    *first = false;
}
static Layout layout_once(const Context *c, char **page_values, bool greedy) {
    const Document *doc = &c->document;
    Layout out = {0};
    out.footnotes = allocate(c->footnotes.len, sizeof *out.footnotes);
    Reports footnote_reports = {0};
    for (size_t i = 0; i < c->footnotes.len; ++i) {
        char *prefix = format("[%zu] ", i + 1);
        TextData data = text_data(words(c->footnotes.data[i]), (Marks){0}, c);
        int capacity = doc->width - (int)strlen(prefix);
        TextResult text =
            layout_text(c, &data, capacity, capacity, "left", prefix, spaces((int)strlen(prefix)), greedy);
        for (size_t j = 0; j < text.lines.len; ++j)
            line_add(&out.footnotes[i], "%s", text.lines.data[j].text);
        report_add(&footnote_reports, format("footnote %zu", i + 1), "left", false, text.measures);
    }
    for (size_t b = 0; b < doc->blocks.len; ++b)
        if (doc->blocks.data[b].body_number > (int)out.stat_count)
            out.stat_count = (size_t)doc->blocks.data[b].body_number;
    out.stats = allocate(out.stat_count, sizeof *out.stats);
    LayoutBlocks layout_blocks = {0};
    int *unknown_index_pages = allocate(c->index_phrases.len, sizeof *unknown_index_pages);
    Lines index = index_lines(c, unknown_index_pages);
    int bibliography_prefix = 0;
    for (size_t i = 0; i < c->bib_order.len; ++i) {
        int width = (int)strlen(doc->bibliography.data[c->bib_order.data[i]].label) + 3;
        if (width > bibliography_prefix)
            bibliography_prefix = width;
    }
    for (size_t b = 0; b < doc->blocks.len; ++b) {
        const Block *block = &doc->blocks.data[b];
        bool first = true;
        if (body_kind(block->kind)) {
            int first_capacity = block->width, later_capacity = block->width;
            char *first_prefix = "", *later_prefix = "";
            if (block->kind == PARAGRAPH) {
                first_capacity -= block->indent;
                first_prefix = spaces(block->indent);
            } else if (block->kind == ITEM) {
                first_capacity -= 2;
                later_capacity -= 2;
                first_prefix = "- ";
                later_prefix = "  ";
            } else if (block->kind == ENUMERATION) {
                first_capacity -= 4;
                later_capacity -= 4;
                first_prefix = format("%2s. ", block->number);
                later_prefix = "    ";
            } else if (block->kind == QUOTE) {
                first_capacity -= 8;
                later_capacity -= 8;
                first_prefix = later_prefix = "    ";
            } else {
                first_capacity -= 12;
                later_capacity -= 12;
                int length = (int)strlen(block->term);
                first_prefix = length <= 10 ? format("%s%s", block->term, spaces(12 - length)) : spaces(12);
                later_prefix = spaces(12);
            }
            TextData data = expand(block, c, page_values);
            TextResult result = layout_text(c, &data, first_capacity, later_capacity, block->align,
                                            first_prefix, later_prefix, greedy);
            LayoutLines lines = {0};
            if (block->kind == TERM && strlen(block->term) >= 11)
                layout_line_add(&lines, layout_line(block->term));
            for (size_t i = 0; i < result.lines.len; ++i)
                layout_line_add(&lines, result.lines.data[i]);
            add_layout(&layout_blocks, lines, FLOW,
                       block->kind == ITEM || block->kind == ENUMERATION || block->kind == TERM,
                       block->page_break, &first, (int)b);
            report_add(&out.reports, format("paragraph %d", block->body_number), block->align, true,
                       result.measures);
            out.stats[block->body_number - 1] = (BodyStat){(int)result.measures.len, result.cost};
            for (size_t i = 0; i < result.measures.len; ++i)
                if (result.measures.data[i].mid)
                    ++out.hyphenated;
        } else if (block->kind == TITLE || block->kind == AUTHOR) {
            char *text = block->kind == TITLE ? upper(block->text) : block->text;
            Lines lines = {0};
            line_add(&lines, "%s%s", spaces((block->width - (int)strlen(text)) / 2), text);
            add_layout(&layout_blocks, plain_lines(lines), HEADING, false, block->page_break, &first, (int)b);
        } else if (block->kind == H1 || block->kind == H2) {
            char *text = format("%s %s", block->number, block->kind == H1 ? upper(block->text) : block->text),
                 *rule = spaces((int)strlen(text));
            memset(rule, block->kind == H1 ? '=' : '-', strlen(text));
            Lines lines = {0};
            line_add(&lines, "%s", text);
            line_add(&lines, "%s", rule);
            add_layout(&layout_blocks, plain_lines(lines), HEADING, false, block->page_break, &first, (int)b);
        } else if (block->kind == TABLE)
            add_layout(&layout_blocks, plain_lines(render_table(block)), SOLID, false, block->page_break,
                       &first, (int)b);
        else if (block->kind == VERBATIM) {
            Lines lines = {0};
            for (size_t i = 0; i < block->inner.len; ++i)
                line_add(&lines, "%s", block->inner.data[i].text);
            add_layout(&layout_blocks, plain_lines(lines), FLOW, false, block->page_break, &first, (int)b);
        } else if (block->kind == TOC || block->kind == LOT) {
            Lines heading = {0};
            line_add(&heading, "%s", block->kind == TOC ? "CONTENTS" : "TABLES");
            line_add(&heading, "%s", block->kind == TOC ? "========" : "======");
            add_layout(&layout_blocks, plain_lines(heading), HEADING, false, block->page_break, &first,
                       (int)b);
            LayoutLines lines = {0};
            for (size_t target = 0; target < doc->blocks.len; ++target) {
                const Block *entry = &doc->blocks.data[target];
                bool include = block->kind == TOC ? entry->kind == H1 || entry->kind == H2
                                                  : entry->kind == TABLE && *entry->caption;
                if (!include)
                    continue;
                LayoutLine line = layout_line(entry_line(entry, block->width, "??"));
                line.toc_target = (int)target;
                line.dynamic_width = block->width;
                layout_line_add(&lines, line);
            }
            add_layout(&layout_blocks, lines, FLOW, false, block->page_break, &first, (int)b);
        } else if (block->kind == INDEX) {
            Lines heading = {0};
            line_add(&heading, "INDEX");
            line_add(&heading, "=====");
            add_layout(&layout_blocks, plain_lines(heading), HEADING, false, block->page_break, &first,
                       (int)b);
            LayoutLines lines = {0};
            for (size_t i = 0; i < index.len; ++i) {
                LayoutLine line = layout_line(index.data[i]);
                line.index_entry = (int)i;
                layout_line_add(&lines, line);
            }
            add_layout(&layout_blocks, lines, FLOW, false, block->page_break, &first, (int)b);
        } else {
            Lines heading = {0};
            line_add(&heading, "REFERENCES");
            line_add(&heading, "==========");
            add_layout(&layout_blocks, plain_lines(heading), HEADING, false, block->page_break, &first,
                       (int)b);
            for (size_t i = 0; i < c->bib_order.len; ++i) {
                const Bib *entry = &doc->bibliography.data[c->bib_order.data[i]];
                char *label = format("[%s]", entry->label),
                     *prefix = format("%s%s", label, spaces(bibliography_prefix - (int)strlen(label)));
                TextData data = text_data(
                    words(format("%s. %s. %s", entry->author, entry->year, entry->title)), (Marks){0}, c);
                TextResult result = layout_text(c, &data, block->width - bibliography_prefix,
                                                block->width - bibliography_prefix, "left", prefix,
                                                spaces(bibliography_prefix), greedy);
                add_layout(&layout_blocks, result.lines, FLOW, true, block->page_break, &first, (int)b);
                report_add(&out.reports, format("reference %s", entry->label), "left", false,
                           result.measures);
            }
        }
    }
    Pages raw = build_pages(layout_blocks, out.footnotes, c->footnotes.len, &c->params, doc->height);
    for (size_t i = 0; i < raw.len; ++i) {
        Page page = raw.data[i];
        bool chapter = page.content.len && page.content.data[0].first_block >= 0 &&
                       doc->blocks.data[page.content.data[0].first_block].kind == H1;
        if (chapter && (out.pages.len + 1) % 2 == 0) {
            Page blank = {0};
            blank.blank = true;
            page_add(&out.pages, blank);
        }
        page_add(&out.pages, page);
    }
    out.block_pages = allocate(doc->blocks.len, sizeof *out.block_pages);
    for (size_t page = 0; page < out.pages.len; ++page)
        for (size_t l = 0; l < out.pages.data[page].content.len; ++l) {
            LayoutLine line = out.pages.data[page].content.data[l];
            if (line.first_block >= 0)
                out.block_pages[line.first_block] = (int)page + 1;
        }
    for (size_t b = 0; b < doc->blocks.len; ++b)
        if (doc->blocks.data[b].kind == H1) {
            out.front = out.block_pages[b] - 1;
            break;
        }
    for (size_t i = 0; i < out.pages.len; ++i) {
        Page *page = &out.pages.data[i];
        page->body_number = (int)i + 1 - out.front;
        page->display = (int)i + 1 <= out.front ? roman((int)i + 1) : number(page->body_number);
    }
    out.index_pages = allocate(c->index_phrases.len, sizeof *out.index_pages);
    for (size_t i = 0; i < out.pages.len; ++i) {
        Page page = out.pages.data[i];
        for (size_t l = 0; l < page.content.len; ++l)
            for (size_t j = 0; j < page.content.data[l].indices.len; ++j)
                out.index_pages[page.content.data[l].indices.data[j]] = page.body_number;
    }
    for (size_t i = 0; i < footnote_reports.len; ++i) {
        BrokenReport report = footnote_reports.data[i];
        report_add(&out.reports, report.name, report.alignment, report.body, report.lines);
    }
    return out;
}
static Layout layout(const Context *c, bool greedy) {
    char **values = allocate(c->labels.len, sizeof *values);
    for (size_t i = 0; i < c->labels.len; ++i)
        values[i] = "??";
    Layout result;
    for (;;) {
        result = layout_once(c, values, greedy);
        char **computed = allocate(c->labels.len, sizeof *computed);
        bool equal = true;
        for (size_t i = 0; i < c->labels.len; ++i) {
            computed[i] = result.pages.data[result.block_pages[c->labels.data[i].block] - 1].display;
            if (strcmp(values[i], computed[i]))
                equal = false;
        }
        if (equal)
            break;
        values = computed;
    }
    Lines index = index_lines(c, result.index_pages);
    for (size_t p = 0; p < result.pages.len; ++p)
        for (size_t l = 0; l < result.pages.data[p].content.len; ++l) {
            LayoutLine *line = &result.pages.data[p].content.data[l];
            if (line->toc_target >= 0) {
                int target = line->toc_target;
                line->text = entry_line(&c->document.blocks.data[target], line->dynamic_width,
                                        result.pages.data[result.block_pages[target] - 1].display);
            }
            if (line->index_entry >= 0)
                line->text = index.data[line->index_entry];
        }
    return result;
}
static Lines layout_warnings(const Context *c, const Layout *layout, const char *method) {
    Lines out = {0};
    for (size_t r = 0; r < layout->reports.len; ++r) {
        BrokenReport report = layout->reports.data[r];
        for (size_t i = 0; i < report.lines.len; ++i) {
            Measure line = report.lines.data[i];
            if (line.slack < 0)
                line_add(&out, "%s: %s line %zu: overfull by %d", method, report.name, i + 1, -line.slack);
            else if (report.body && !strcmp(report.alignment, "justify") && !line.last &&
                     line.slack >= c->params.underfull_slack)
                line_add(&out, "%s: %s line %zu: underfull, slack %d", method, report.name, i + 1,
                         line.slack);
        }
    }
    for (size_t i = 0; i < layout->pages.len; ++i) {
        Page page = layout->pages.data[i];
        int empty = c->document.height - page.height;
        if (!page.blank && !page.forced && empty >= c->params.underfull_page)
            line_add(&out, "%s: page %zu: underfull, %d empty lines", method, i + 1, empty);
    }
    line_add(&out, "%s: %zu pages, %d hyphenated lines", method, layout->pages.len, layout->hyphenated);
    return out;
}
static Params read_params(void) {
    Params p = {0};
    const char *names[12] = {"line_penalty",
                             "hyphen_penalty",
                             "double_hyphen_demerit",
                             "final_hyphen_demerit",
                             "fitness_demerit",
                             "overfull_penalty",
                             "left_min",
                             "right_min",
                             "orphan_lines",
                             "widow_lines",
                             "underfull_slack",
                             "underfull_page"};
    Integer *values[12] = {&p.line_penalty,
                           &p.hyphen_penalty,
                           &p.double_hyphen_demerit,
                           &p.final_hyphen_demerit,
                           &p.fitness_demerit,
                           &p.overfull_penalty,
                           &p.left_min,
                           &p.right_min,
                           &p.orphan_lines,
                           &p.widow_lines,
                           &p.underfull_slack,
                           &p.underfull_page};
    Lines lines = read_lines("input/params.txt");
    for (size_t i = 0; i < lines.len; ++i) {
        Lines fields = split(lines.data[i], ' ');
        for (int j = 0; j < 12; ++j)
            if (!strcmp(fields.data[0], names[j]))
                *values[j] = strtoll(fields.data[1], NULL, 10);
    }
    return p;
}
static void write(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "wb");
    if (!out)
        exit(EXIT_FAILURE);
    for (size_t i = 0; i < lines.len; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
int main(void) {
    Context c = {0};
    c.params = read_params();
    c.document = parse_document(read_lines("input/document.txt"));
    Lines dictionary = read_lines("input/hyphenation.txt");
    for (size_t i = 0; i < dictionary.len; ++i)
        register_word(&c.dictionary, dictionary.data[i]);
    for (size_t i = 0; i < c.document.additions.len; ++i)
        register_word(&c.dictionary, c.document.additions.data[i]);
    prepare(&c);
    Layout kp = layout(&c, false), greedy = layout(&c, true);
    write("pages.txt", render_pages(kp.pages, kp.footnotes, &c.document, kp.block_pages, kp.front));
    write("greedy_pages.txt",
          render_pages(greedy.pages, greedy.footnotes, &c.document, greedy.block_pages, greedy.front));
    Lines stats = {0};
    line_add(&stats, "paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy");
    Integer totals[4] = {0};
    for (size_t i = 0; i < kp.stat_count; ++i) {
        BodyStat a = kp.stats[i], b = greedy.stats[i];
        line_add(&stats, "%zu,%d,%" PRId64 ",%d,%" PRId64, i + 1, a.lines, a.cost, b.lines, b.cost);
        totals[0] += a.lines;
        totals[1] += a.cost;
        totals[2] += b.lines;
        totals[3] += b.cost;
    }
    line_add(&stats, "total,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64, totals[0], totals[1], totals[2],
             totals[3]);
    write("stats.csv", stats);
    Lines logs = {0};
    for (size_t i = 0; i < c.document.warnings.len; ++i)
        line_add(&logs, "line %d: %s", c.document.warnings.data[i].line, c.document.warnings.data[i].message);
    extend(&logs, layout_warnings(&c, &kp, "kp"));
    extend(&logs, layout_warnings(&c, &greedy, "greedy"));
    write("log.txt", logs);
    return 0;
}
