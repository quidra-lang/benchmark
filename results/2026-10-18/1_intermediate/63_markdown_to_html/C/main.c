#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void **allocations;
static size_t allocation_count, allocation_capacity;
static void *allocate(size_t bytes) {
    void *p = calloc(1, bytes ? bytes : 1);
    if (!p)
        exit(EXIT_FAILURE);
    if (allocation_count == allocation_capacity) {
        allocation_capacity = allocation_capacity ? allocation_capacity * 2 : 128;
        void **next = realloc(allocations, allocation_capacity * sizeof(void *));
        if (!next)
            exit(EXIT_FAILURE);
        allocations = next;
    }
    allocations[allocation_count++] = p;
    return p;
}
#define VECTOR(Type, Name)                                                                         \
    typedef struct {                                                                               \
        Type *data;                                                                                \
        size_t count, capacity;                                                                    \
    } Name
#define ADD(vector, value)                                                                         \
    do {                                                                                           \
        if ((vector).count == (vector).capacity) {                                                 \
            size_t capacity = (vector).capacity ? (vector).capacity * 2 : 8;                       \
            void *data = allocate(capacity * sizeof *(vector).data);                               \
            if ((vector).count)                                                                    \
                memcpy(data, (vector).data, (vector).count * sizeof *(vector).data);               \
            (vector).data = data;                                                                  \
            (vector).capacity = capacity;                                                          \
        }                                                                                          \
        (vector).data[(vector).count++] = (value);                                                 \
    } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} String;
VECTOR(char *, Strings);
static void reserve(String *s, size_t length) {
    if (length + 1 <= s->capacity)
        return;
    size_t capacity = s->capacity ? s->capacity : 32;
    while (capacity < length + 1)
        capacity *= 2;
    char *next = allocate(capacity);
    if (s->length)
        memcpy(next, s->data, s->length);
    s->data = next;
    s->capacity = capacity;
}
static void append_n(String *s, const char *text, size_t length) {
    reserve(s, s->length + length);
    memcpy(s->data + s->length, text, length);
    s->length += length;
    s->data[s->length] = 0;
}
static void append(String *s, const char *text) {
    append_n(s, text, strlen(text));
}
static void character(String *s, char ch) {
    append_n(s, &ch, 1);
}
static char *finish(String s) {
    return s.data ? s.data : "";
}
static char *slice(const char *text, size_t start, size_t end) {
    char *result = allocate(end - start + 1);
    memcpy(result, text + start, end - start);
    return result;
}
static char *decimal(size_t value) {
    char buffer[32];
    snprintf(buffer, sizeof buffer, "%zu", value);
    return slice(buffer, 0, strlen(buffer));
}
static const char *punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
static const char *toc_marker = "\001toc\002";
static int has(const char *set, char ch) {
    return ch && strchr(set, ch) != NULL;
}
static int starts(const char *text, const char *prefix) {
    return strncmp(text, prefix, strlen(prefix)) == 0;
}
static int alphanumeric(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}
static int label_character(char c) {
    return alphanumeric(c) || c == '-' || c == '_';
}
static int whitespace(char c) {
    return c == ' ' || c == '\n';
}
static char *lower(const char *text) {
    char *result = slice(text, 0, strlen(text));
    for (size_t i = 0; result[i]; i++)
        result[i] = (char)tolower((unsigned char)result[i]);
    return result;
}
static char *trim(const char *text) {
    size_t first = 0, end = strlen(text);
    while (first < end && text[first] == ' ')
        first++;
    while (end > first && text[end - 1] == ' ')
        end--;
    return slice(text, first, end);
}
static char *left_trim(const char *text) {
    while (*text == ' ')
        text++;
    return (char *)text;
}
static char *join(Strings values, const char *separator) {
    String result = {0};
    for (size_t i = 0; i < values.count; i++) {
        if (i)
            append(&result, separator);
        append(&result, values.data[i]);
    }
    return finish(result);
}
static void escape_into(String *html, const char *text) {
    for (; *text; text++) {
        switch (*text) {
        case '&':
            append(html, "&amp;");
            break;
        case '<':
            append(html, "&lt;");
            break;
        case '>':
            append(html, "&gt;");
            break;
        case '"':
            append(html, "&quot;");
            break;
        default:
            character(html, *text);
            break;
        }
    }
}
static char *escape_html(const char *text) {
    String result = {0};
    escape_into(&result, text);
    return finish(result);
}
static char *strip_tags(const char *text) {
    String result = {0};
    for (size_t at = 0; text[at];) {
        const char *end = text[at] == '<' ? strchr(text + at, '>') : NULL;
        if (end)
            at = (size_t)(end - text) + 1;
        else
            character(&result, text[at++]);
    }
    return finish(result);
}
static char *normalize(const char *text) {
    String result = {0};
    int space = 0;
    for (; *text; text++) {
        if (whitespace(*text))
            space = result.length != 0;
        else {
            if (space)
                character(&result, ' ');
            character(&result, (char)tolower((unsigned char)*text));
            space = 0;
        }
    }
    return finish(result);
}
static size_t skip_space(const char *text, size_t at) {
    while (whitespace(text[at]))
        at++;
    return at;
}
typedef struct {
    char *text;
    size_t end;
} Read;
static Read escaped_read(const char *text, size_t at, const char *stops) {
    String result = {0};
    while (text[at] && !has(stops, text[at])) {
        if (text[at] == '\\' && has(punctuation, text[at + 1]))
            at++;
        character(&result, text[at++]);
    }
    return (Read){finish(result), at};
}

typedef enum { HEADING, PARAGRAPH, RULE, CODE, QUOTE, ALERT, LIST, TABLE, TOC } Kind;
typedef struct Block Block;
VECTOR(Block *, Blocks);
VECTOR(Blocks, Items);
VECTOR(Strings, Rows);
struct Block {
    Kind kind;
    char *text;
    int number, ordered;
    Strings lines, alignments;
    Blocks children;
    Items items;
    Rows rows;
};
static Block *block(Kind kind, char *text, int number) {
    Block *b = allocate(sizeof(Block));
    b->kind = kind;
    b->text = text ? text : "";
    b->number = number;
    return b;
}
typedef struct {
    char *name, *url, *title;
} Reference;
typedef struct {
    char *name, *body;
    size_t number, count;
} Footnote;
VECTOR(Reference, References);
VECTOR(Footnote, Footnotes);
typedef struct {
    References references;
    Footnotes footnotes;
} Parser;
static Reference *find_reference(Parser *p, const char *name) {
    for (size_t i = 0; i < p->references.count; i++)
        if (!strcmp(name, p->references.data[i].name))
            return &p->references.data[i];
    return NULL;
}
static Footnote *find_footnote(Parser *p, const char *name) {
    for (size_t i = 0; i < p->footnotes.count; i++)
        if (!strcmp(name, p->footnotes.data[i].name))
            return &p->footnotes.data[i];
    return NULL;
}
typedef struct {
    char ch;
    size_t length;
    char *info;
} Fence;
static Fence opening_fence(const char *line) {
    Fence fence = {0};
    if (!has("`~", line[0]))
        return fence;
    size_t end = 1;
    while (line[end] == line[0])
        end++;
    if (end < 3)
        return fence;
    char *info = trim(line + end);
    if (line[0] == '`' && strchr(info, '`'))
        return fence;
    return (Fence){line[0], end, info};
}
static Block *atx_heading(const char *line) {
    size_t n = 0;
    while (line[n] == '#')
        n++;
    if (!n || n > 6 || (line[n] && line[n] != ' '))
        return NULL;
    char *text = trim(line + n);
    size_t end = strlen(text);
    while (end && text[end - 1] == '#')
        end--;
    if (!end || text[end - 1] == ' ')
        text = trim(slice(text, 0, end));
    return block(HEADING, text, (int)n);
}
static int is_rule(const char *line) {
    char ch = 0;
    size_t n = 0;
    for (; *line; line++)
        if (*line != ' ') {
            if (!ch)
                ch = *line;
            if (!has("-*_", ch) || *line != ch)
                return 0;
            n++;
        }
    return n >= 3;
}
typedef struct {
    char marker;
    int ordered, number;
    char *content;
} ListMarker;
static ListMarker list_marker(const char *line) {
    ListMarker result = {0};
    if (is_rule(line))
        return result;
    size_t at = 0;
    int number = 0;
    if (has("-*+", line[0]))
        at = 1;
    else {
        while (line[at] >= '0' && line[at] <= '9') {
            if (at == 9)
                return result;
            number = number * 10 + line[at++] - '0';
        }
        if (!at || !has(".)", line[at]))
            return result;
        result.ordered = 1;
        at++;
    }
    if (line[at] != ' ')
        return (ListMarker){0};
    result.marker = line[at - 1];
    result.number = result.ordered ? number : 1;
    while (line[at] == ' ')
        at++;
    result.content = (char *)line + at;
    return result;
}
static int interrupts(const char *line) {
    return line[0] && line[0] != ' ' &&
           (opening_fence(line).ch || atx_heading(line) || is_rule(line) || line[0] == '>' ||
            list_marker(line).marker);
}
static Strings split_cells(const char *line) {
    char *text = trim(line);
    size_t at = text[0] == '|' ? 1 : 0;
    Strings cells = {0};
    String current = {0};
    int final_separator = 0;
    while (text[at]) {
        char ch = text[at++];
        final_separator = 0;
        if (ch == '\\' && text[at]) {
            if (text[at] != '|')
                character(&current, '\\');
            character(&current, text[at++]);
        } else if (ch == '|') {
            ADD(cells, trim(finish(current)));
            current = (String){0};
            final_separator = 1;
        } else
            character(&current, ch);
    }
    if (!final_separator)
        ADD(cells, trim(finish(current)));
    return cells;
}
static int delimiter_cell(const char *cell) {
    size_t at = cell[0] == ':' ? 1 : 0, first = at;
    while (cell[at] == '-')
        at++;
    if (at == first)
        return 0;
    if (cell[at] == ':')
        at++;
    return !cell[at];
}
static int definition(Parser *p, const char *line) {
    if (starts(line, "[^")) {
        size_t at = 2;
        while (label_character(line[at]))
            at++;
        if (at > 2 && line[at] == ']' && line[at + 1] == ':') {
            char *body = trim(line + at + 2);
            if (*body) {
                char *name = lower(slice(line, 2, at));
                if (!find_footnote(p, name))
                    ADD(p->footnotes, ((Footnote){name, body, 0, 0}));
                return 1;
            }
        }
    }
    if (line[0] != '[')
        return 0;
    const char *close = strchr(line, ']');
    if (!close || close[1] != ':')
        return 0;
    char *label = slice(line, 1, (size_t)(close - line));
    if (strchr(label, '[') || !*trim(label) || label[0] == '^')
        return 0;
    Read url = escaped_read(line, skip_space(line, (size_t)(close - line) + 2), " ");
    if (!*url.text)
        return 0;
    size_t at = skip_space(line, url.end);
    char *title = NULL;
    if (line[at]) {
        if (at == url.end || !has("\"'", line[at]))
            return 0;
        char stop[2] = {line[at], 0};
        Read quoted = escaped_read(line, at + 1, stop);
        if (quoted.end != strlen(line) - 1)
            return 0;
        title = quoted.text;
    }
    char *name = normalize(label);
    if (!find_reference(p, name))
        ADD(p->references, ((Reference){name, url.text, title}));
    return 1;
}
static Blocks parse(Parser *p, Strings lines) {
    Blocks blocks = {0};
    size_t at = 0;
    while (at < lines.count) {
        char *line = lines.data[at];
        if (!*line) {
            at++;
            continue;
        }
        if (starts(line, "    ")) {
            Block *code = block(CODE, NULL, 0);
            size_t end = at;
            while (end < lines.count && (!*lines.data[end] || starts(lines.data[end], "    ")))
                end++;
            while (end > at && !*lines.data[end - 1])
                end--;
            while (at < end) {
                char *row = lines.data[at++];
                ADD(code->lines, *row ? row + 4 : "");
            }
            ADD(blocks, code);
            continue;
        }
        if (line[0] != ' ') {
            Fence fence = opening_fence(line);
            if (fence.ch) {
                char *space = strchr(fence.info, ' ');
                Block *code = block(
                    CODE, space ? slice(fence.info, 0, (size_t)(space - fence.info)) : fence.info,
                    0);
                at++;
                while (at < lines.count) {
                    char *row = lines.data[at++];
                    size_t n = strspn(row, fence.ch == '`' ? "`" : "~");
                    if (n >= fence.length && !row[n])
                        break;
                    ADD(code->lines, row);
                }
                ADD(blocks, code);
                continue;
            }
            Block *heading = atx_heading(line);
            if (heading) {
                ADD(blocks, heading);
                at++;
                continue;
            }
            if (is_rule(line)) {
                ADD(blocks, block(RULE, NULL, 0));
                at++;
                continue;
            }
            if (line[0] == '>') {
                Strings content = {0};
                while (at < lines.count && lines.data[at][0] == '>') {
                    char *row = lines.data[at++] + 1;
                    if (*row == ' ')
                        row++;
                    ADD(content, row);
                }
                Block *quote = block(QUOTE, NULL, 0);
                const char *types[] = {"NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"};
                for (size_t i = 0; i < 5; i++) {
                    String marker = {0};
                    append(&marker, "[!");
                    append(&marker, types[i]);
                    character(&marker, ']');
                    if (!strcmp(content.data[0], finish(marker))) {
                        quote->kind = ALERT;
                        quote->text = (char *)types[i];
                        content.data++;
                        content.count--;
                        break;
                    }
                }
                quote->children = parse(p, content);
                ADD(blocks, quote);
                continue;
            }
            ListMarker marker = list_marker(line);
            if (marker.marker) {
                Block *list = block(LIST, NULL, marker.number);
                list->ordered = marker.ordered;
                char kind = marker.marker;
                while (1) {
                    Strings content = {0};
                    ADD(content, marker.content);
                    at++;
                    while (at < lines.count && starts(lines.data[at], "  ")) {
                        ADD(content, lines.data[at] + 2);
                        at++;
                    }
                    ADD(list->items, parse(p, content));
                    size_t next = at;
                    while (next < lines.count && !*lines.data[next])
                        next++;
                    marker = next < lines.count ? list_marker(lines.data[next]) : (ListMarker){0};
                    if (!marker.marker || marker.marker != kind || marker.ordered != list->ordered)
                        break;
                    at = next;
                }
                ADD(blocks, list);
                continue;
            }
            if (definition(p, line)) {
                at++;
                continue;
            }
            if (at + 1 < lines.count && strchr(line, '|') && strchr(lines.data[at + 1], '|')) {
                Strings header = split_cells(line), delimiters = split_cells(lines.data[at + 1]);
                int valid = header.count == delimiters.count;
                for (size_t i = 0; i < delimiters.count; i++)
                    if (!delimiter_cell(delimiters.data[i]))
                        valid = 0;
                if (valid) {
                    Block *table = block(TABLE, NULL, 0);
                    table->lines = header;
                    for (size_t i = 0; i < delimiters.count; i++) {
                        char *cell = delimiters.data[i];
                        int left = cell[0] == ':', right = cell[strlen(cell) - 1] == ':';
                        ADD(table->alignments,
                            left ? (right ? "center" : "left") : (right ? "right" : ""));
                    }
                    at += 2;
                    while (at < lines.count && strchr(lines.data[at], '|')) {
                        Strings row = split_cells(lines.data[at++]);
                        while (row.count < delimiters.count)
                            ADD(row, "");
                        row.count = delimiters.count;
                        ADD(table->rows, row);
                    }
                    ADD(blocks, table);
                    continue;
                }
            }
        }
        Strings text = {0};
        ADD(text, left_trim(line));
        at++;
        int level = 0;
        while (at < lines.count && *lines.data[at]) {
            char *row = lines.data[at];
            size_t n = strlen(row);
            if (n >= 3 && has("=-", row[0]) && strspn(row, row[0] == '=' ? "=" : "-") == n) {
                level = row[0] == '=' ? 1 : 2;
                at++;
                break;
            }
            if (interrupts(row))
                break;
            ADD(text, left_trim(row));
            at++;
        }
        char *combined = join(text, "\n");
        ADD(blocks, block(level                        ? HEADING
                          : !strcmp(combined, "[TOC]") ? TOC
                                                       : PARAGRAPH,
                          combined, level));
    }
    return blocks;
}

static size_t run_end(const char *text, size_t at) {
    char ch = text[at++];
    while (text[at] == ch)
        at++;
    return at;
}
static size_t backtick_closer(const char *text, size_t at, size_t length) {
    while (text[at]) {
        if (text[at] != '`') {
            at++;
            continue;
        }
        size_t end = run_end(text, at);
        if (end - at == length)
            return at;
        at = end;
    }
    return (size_t)-1;
}
static size_t closing_bracket(const char *text, size_t at) {
    int depth = 0;
    while (text[at]) {
        char ch = text[at];
        if (ch == '\\') {
            at += text[at + 1] ? 2 : 1;
            continue;
        }
        if (ch == '`') {
            size_t end = run_end(text, at), closer = backtick_closer(text, end, end - at);
            at = closer == (size_t)-1 ? end : closer + end - at;
            continue;
        }
        if (ch == '[')
            depth++;
        if (ch == ']' && --depth == 0)
            return at;
        at++;
    }
    return (size_t)-1;
}
typedef struct {
    char *html;
    char delimiter;
    size_t length;
    int can_open, can_close;
} Piece;
VECTOR(Piece, Pieces);
static void emphasis_into(String *html, Pieces pieces, size_t begin, size_t end) {
    for (size_t at = begin; at < end; at++) {
        Piece piece = pieces.data[at];
        if (!piece.delimiter) {
            append(html, piece.html);
            continue;
        }
        size_t close = at + 1;
        if (piece.can_open) {
            while (close < end &&
                   !(pieces.data[close].delimiter == piece.delimiter &&
                     pieces.data[close].length == piece.length && pieces.data[close].can_close))
                close++;
        } else
            close = end;
        if (close == end) {
            for (size_t i = 0; i < piece.length; i++)
                character(html, piece.delimiter);
            continue;
        }
        const char *opening, *closing;
        if (piece.delimiter == '~') {
            opening = "<del>";
            closing = "</del>";
        } else if (piece.length == 1) {
            opening = "<em>";
            closing = "</em>";
        } else if (piece.length == 2) {
            opening = "<strong>";
            closing = "</strong>";
        } else {
            opening = "<em><strong>";
            closing = "</strong></em>";
        }
        append(html, opening);
        emphasis_into(html, pieces, at + 1, close);
        append(html, closing);
        at = close;
    }
}
typedef struct Heading Heading;
VECTOR(Heading *, Headings);
struct Heading {
    int level;
    char *id, *label;
    Headings children;
};
VECTOR(Footnote *, NumberedNotes);
typedef struct {
    Parser *parser;
    Strings used_ids;
    Headings headings;
    NumberedNotes notes;
} Renderer;
static int string_in(Strings strings, const char *text) {
    for (size_t i = 0; i < strings.count; i++)
        if (!strcmp(strings.data[i], text))
            return 1;
    return 0;
}
static char *reference_id(size_t number, size_t count) {
    String id = {0};
    append(&id, "fnref-");
    append(&id, decimal(number));
    if (count > 1) {
        character(&id, '-');
        append(&id, decimal(count));
    }
    return finish(id);
}
static char *footnote_reference(Renderer *r, Footnote *note) {
    if (!note->number) {
        note->number = r->notes.count + 1;
        ADD(r->notes, note);
    }
    note->count++;
    String html = {0};
    append(&html, "<sup id=\"");
    append(&html, reference_id(note->number, note->count));
    append(&html, "\"><a href=\"#fn-");
    append(&html, decimal(note->number));
    append(&html, "\">");
    append(&html, decimal(note->number));
    append(&html, "</a></sup>");
    return finish(html);
}
typedef struct {
    Reference *reference;
    size_t end;
} Destination;
static Destination destination(Renderer *r, const char *text, size_t at, const char *label) {
    if (text[at] == '[') {
        const char *close = strchr(text + at + 1, ']');
        if (close) {
            char *key = slice(text, at + 1, (size_t)(close - text));
            if (!strchr(key, '['))
                return (Destination){find_reference(r->parser, normalize(*key ? key : label)),
                                     (size_t)(close - text) + 1};
        }
    } else if (text[at] == '(') {
        Read url = escaped_read(text, skip_space(text, at + 1), " \n)");
        size_t next = skip_space(text, url.end);
        char *title = NULL;
        int valid = 1;
        if (next > url.end && has("\"'", text[next])) {
            char stop[2] = {text[next], 0};
            Read quoted = escaped_read(text, next + 1, stop);
            if (!text[quoted.end])
                valid = 0;
            else {
                title = quoted.text;
                next = skip_space(text, quoted.end + 1);
            }
        }
        if (valid && text[next] == ')') {
            Reference *reference = allocate(sizeof(Reference));
            reference->url = url.text;
            reference->title = title;
            return (Destination){reference, next + 1};
        }
    }
    return (Destination){find_reference(r->parser, normalize(label)), at};
}
static int email_address(const char *text) {
    const char *at = strchr(text, '@');
    if (!at || at == text || strchr(at + 1, '@'))
        return 0;
    for (const char *p = text; p < at; p++)
        if (!alphanumeric(*p) && !has(".+-_", *p))
            return 0;
    int dots = 0, length = 0;
    for (const char *p = at + 1;; p++) {
        if (*p == '.' || !*p) {
            if (!length)
                return 0;
            if (!*p)
                break;
            dots++;
            length = 0;
        } else {
            if (!alphanumeric(*p) && *p != '-')
                return 0;
            length++;
        }
    }
    return dots >= 1;
}
static char *inline_html(Renderer *r, const char *text, int links, int notes) {
    Pieces pieces = {0};
    size_t at = 0;
    while (text[at]) {
        char ch = text[at];
        if (ch == '\\') {
            if (has(punctuation, text[at + 1])) {
                ADD(pieces, ((Piece){escape_html(slice(text, at + 1, at + 2)), 0, 0, 0, 0}));
                at += 2;
            } else if (text[at + 1] == '\n') {
                ADD(pieces, ((Piece){"<br />\n", 0, 0, 0, 0}));
                at += 2;
            } else {
                ADD(pieces, ((Piece){"\\", 0, 0, 0, 0}));
                at++;
            }
            continue;
        }
        if (ch == '`') {
            size_t end = run_end(text, at), closer = backtick_closer(text, end, end - at);
            if (closer == (size_t)-1) {
                ADD(pieces, ((Piece){slice(text, at, end), 0, 0, 0, 0}));
                at = end;
            } else {
                char *code = slice(text, end, closer);
                size_t length = strlen(code);
                for (size_t i = 0; i < length; i++)
                    if (code[i] == '\n')
                        code[i] = ' ';
                if (length && code[0] == ' ' && code[length - 1] == ' ' && *trim(code))
                    code = slice(code, 1, length - 1);
                String html = {0};
                append(&html, "<code>");
                escape_into(&html, code);
                append(&html, "</code>");
                ADD(pieces, ((Piece){finish(html), 0, 0, 0, 0}));
                at = closer + end - at;
            }
            continue;
        }
        if (links && ch == '<') {
            const char *close = strchr(text + at + 1, '>');
            if (close) {
                char *target = slice(text, at + 1, (size_t)(close - text));
                char *href = NULL;
                if (!strpbrk(target, " \n<") &&
                    ((starts(target, "http://") && strlen(target) > 7) ||
                     (starts(target, "https://") && strlen(target) > 8)))
                    href = target;
                if (!href && email_address(target)) {
                    String url = {0};
                    append(&url, "mailto:");
                    append(&url, target);
                    href = finish(url);
                }
                if (href) {
                    String html = {0};
                    append(&html, "<a href=\"");
                    escape_into(&html, href);
                    append(&html, "\">");
                    escape_into(&html, target);
                    append(&html, "</a>");
                    ADD(pieces, ((Piece){finish(html), 0, 0, 0, 0}));
                    at = (size_t)(close - text) + 1;
                    continue;
                }
            }
        }
        if (links && (starts(text + at, "http://") || starts(text + at, "https://")) &&
            (!at || has(" \n*_~(", text[at - 1]))) {
            size_t end = at;
            while (text[end] && !has(" \n<", text[end]))
                end++;
            while (end > at && has(".,:;!?*_~)", text[end - 1]))
                end--;
            char *url = slice(text, at, end);
            if (strcmp(url, "http://") && strcmp(url, "https://")) {
                String html = {0};
                append(&html, "<a href=\"");
                escape_into(&html, url);
                append(&html, "\">");
                escape_into(&html, url);
                append(&html, "</a>");
                ADD(pieces, ((Piece){finish(html), 0, 0, 0, 0}));
                at = end;
                continue;
            }
        }
        if (ch == '[' || (ch == '!' && text[at + 1] == '[')) {
            if (links && notes && starts(text + at, "[^")) {
                const char *close = strchr(text + at + 2, ']');
                if (close) {
                    Footnote *note = find_footnote(
                        r->parser, lower(slice(text, at + 2, (size_t)(close - text))));
                    if (note) {
                        ADD(pieces, ((Piece){footnote_reference(r, note), 0, 0, 0, 0}));
                        at = (size_t)(close - text) + 1;
                        continue;
                    }
                }
            }
            int image = ch == '!';
            size_t opening = at + (image ? 1 : 0), close = closing_bracket(text, opening);
            if ((image || links) && close != (size_t)-1) {
                char *label = slice(text, opening + 1, close);
                Destination dest = destination(r, text, close + 1, label);
                if (dest.reference) {
                    char *content = inline_html(r, label, 0, 0);
                    String html = {0};
                    append(&html, image ? "<img src=\"" : "<a href=\"");
                    escape_into(&html, dest.reference->url);
                    character(&html, '"');
                    if (image) {
                        append(&html, " alt=\"");
                        append(&html, strip_tags(content));
                        character(&html, '"');
                    }
                    if (dest.reference->title) {
                        append(&html, " title=\"");
                        escape_into(&html, dest.reference->title);
                        character(&html, '"');
                    }
                    if (image)
                        append(&html, " />");
                    else {
                        character(&html, '>');
                        append(&html, content);
                        append(&html, "</a>");
                    }
                    ADD(pieces, ((Piece){finish(html), 0, 0, 0, 0}));
                    at = dest.end;
                    continue;
                }
            }
        }
        if (has("*_~", ch)) {
            size_t end = run_end(text, at), length = end - at;
            char before = at ? text[at - 1] : ' ', after = text[end] ? text[end] : ' ';
            int open = !whitespace(after), close = !whitespace(before);
            if (ch == '_' && alphanumeric(before) && alphanumeric(after))
                open = close = 0;
            if ((ch != '~' && length <= 3) || (ch == '~' && length == 2))
                ADD(pieces, ((Piece){NULL, ch, length, open, close}));
            else
                ADD(pieces, ((Piece){slice(text, at, end), 0, 0, 0, 0}));
            at = end;
            continue;
        }
        ADD(pieces, ((Piece){escape_html(slice(text, at, at + 1)), 0, 0, 0, 0}));
        at++;
    }
    String html = {0};
    emphasis_into(&html, pieces, 0, pieces.count);
    return finish(html);
}
static char *render(Renderer *, Block *);
static char *render_blocks(Renderer *r, Blocks blocks) {
    String html = {0};
    for (size_t i = 0; i < blocks.count; i++) {
        append(&html, render(r, blocks.data[i]));
        character(&html, '\n');
    }
    return finish(html);
}
static char *render_heading(Renderer *r, Block *b) {
    char *text = b->text, *id = NULL;
    const char *last = NULL, *cursor = text;
    while ((cursor = strstr(cursor, " {#"))) {
        last = cursor;
        cursor++;
    }
    size_t length = strlen(text);
    if (length && text[length - 1] == '}' && last) {
        char *candidate = slice(last, 3, strlen(last) - 1);
        int valid = *candidate != 0;
        for (size_t i = 0; candidate[i]; i++)
            if (!label_character(candidate[i]))
                valid = 0;
        if (valid) {
            id = candidate;
            text = slice(text, 0, (size_t)(last - text));
            size_t end = strlen(text);
            while (end && text[end - 1] == ' ')
                text[--end] = 0;
        }
    }
    if (!id) {
        String slug = {0};
        for (char *p = lower(text); *p; p++) {
            if (label_character(*p))
                character(&slug, *p);
            else if (whitespace(*p))
                character(&slug, '-');
        }
        char *base = slug.length ? finish(slug) : "heading";
        id = base;
        for (size_t suffix = 1; string_in(r->used_ids, id); suffix++) {
            String value = {0};
            append(&value, base);
            character(&value, '-');
            append(&value, decimal(suffix));
            id = finish(value);
        }
    }
    ADD(r->used_ids, id);
    char *content = inline_html(r, text, 1, 1);
    Heading *heading = allocate(sizeof(Heading));
    heading->level = b->number;
    heading->id = id;
    heading->label = strip_tags(content);
    ADD(r->headings, heading);
    String html = {0};
    append(&html, "<h");
    append(&html, decimal((size_t)b->number));
    append(&html, " id=\"");
    append(&html, id);
    append(&html, "\">");
    append(&html, content);
    append(&html, "</h");
    append(&html, decimal((size_t)b->number));
    character(&html, '>');
    return finish(html);
}
static char *render_item(Renderer *r, Blocks blocks) {
    String html = {0};
    append(&html, "<li>");
    for (size_t i = 0; i < blocks.count; i++) {
        Block *b = blocks.data[i];
        if (b->kind == PARAGRAPH) {
            char *text = b->text;
            if (!i && strlen(text) > 4 &&
                (starts(text, "[ ] ") || starts(text, "[x] ") || starts(text, "[X] "))) {
                append(&html, text[1] == ' '
                                  ? "<input type=\"checkbox\" disabled=\"\" /> "
                                  : "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
                text += 4;
            }
            append(&html, inline_html(r, text, 1, 1));
        } else {
            if (html.data[html.length - 1] != '\n')
                character(&html, '\n');
            append(&html, render(r, b));
            character(&html, '\n');
        }
    }
    append(&html, "</li>");
    return finish(html);
}
static void table_cells(String *html, Renderer *r, Block *b, const char *tag, Strings cells) {
    for (size_t i = 0; i < cells.count; i++) {
        character(html, '<');
        append(html, tag);
        if (*b->alignments.data[i]) {
            append(html, " style=\"text-align:");
            append(html, b->alignments.data[i]);
            character(html, '"');
        }
        character(html, '>');
        append(html, inline_html(r, cells.data[i], 1, 1));
        append(html, "</");
        append(html, tag);
        append(html, ">\n");
    }
}
static char *render(Renderer *r, Block *b) {
    String html = {0};
    switch (b->kind) {
    case HEADING:
        return render_heading(r, b);
    case PARAGRAPH:
        append(&html, "<p>");
        append(&html, inline_html(r, b->text, 1, 1));
        append(&html, "</p>");
        break;
    case RULE:
        return "<hr />";
    case CODE:
        append(&html, "<pre><code");
        if (*b->text) {
            append(&html, " class=\"language-");
            escape_into(&html, b->text);
            character(&html, '"');
        }
        character(&html, '>');
        for (size_t i = 0; i < b->lines.count; i++) {
            escape_into(&html, b->lines.data[i]);
            character(&html, '\n');
        }
        append(&html, "</code></pre>");
        break;
    case QUOTE:
        append(&html, "<blockquote>\n");
        append(&html, render_blocks(r, b->children));
        append(&html, "</blockquote>");
        break;
    case ALERT: {
        char *name = lower(b->text), *title = slice(name, 0, strlen(name));
        title[0] = (char)toupper((unsigned char)title[0]);
        append(&html, "<div class=\"alert alert-");
        append(&html, name);
        append(&html, "\">\n<p class=\"alert-title\">");
        append(&html, title);
        append(&html, "</p>\n");
        append(&html, render_blocks(r, b->children));
        append(&html, "</div>");
        break;
    }
    case LIST: {
        char *tag = b->ordered ? "ol" : "ul";
        character(&html, '<');
        append(&html, tag);
        if (b->ordered && b->number != 1) {
            append(&html, " start=\"");
            append(&html, decimal((size_t)b->number));
            character(&html, '"');
        }
        append(&html, ">\n");
        for (size_t i = 0; i < b->items.count; i++) {
            append(&html, render_item(r, b->items.data[i]));
            character(&html, '\n');
        }
        append(&html, "</");
        append(&html, tag);
        character(&html, '>');
        break;
    }
    case TABLE:
        append(&html, "<table>\n<thead>\n<tr>\n");
        table_cells(&html, r, b, "th", b->lines);
        append(&html, "</tr>\n</thead>\n");
        if (b->rows.count) {
            append(&html, "<tbody>\n");
            for (size_t i = 0; i < b->rows.count; i++) {
                append(&html, "<tr>\n");
                table_cells(&html, r, b, "td", b->rows.data[i]);
                append(&html, "</tr>\n");
            }
            append(&html, "</tbody>\n");
        }
        append(&html, "</table>");
        break;
    case TOC:
        return (char *)toc_marker;
    }
    return finish(html);
}
static char *toc_list(Headings entries) {
    String html = {0};
    append(&html, "<ul>\n");
    for (size_t i = 0; i < entries.count; i++) {
        Heading *h = entries.data[i];
        append(&html, "<li><a href=\"#");
        append(&html, h->id);
        append(&html, "\">");
        append(&html, h->label);
        append(&html, "</a>");
        if (h->children.count) {
            character(&html, '\n');
            append(&html, toc_list(h->children));
            character(&html, '\n');
        }
        append(&html, "</li>\n");
    }
    append(&html, "</ul>");
    return finish(html);
}
static char *table_of_contents(Renderer *r) {
    if (!r->headings.count)
        return "<nav class=\"toc\">\n</nav>";
    Headings roots = {0}, parents = {0};
    for (size_t i = 0; i < r->headings.count; i++) {
        Heading *h = r->headings.data[i];
        while (parents.count && parents.data[parents.count - 1]->level >= h->level)
            parents.count--;
        if (parents.count)
            ADD(parents.data[parents.count - 1]->children, h);
        else
            ADD(roots, h);
        ADD(parents, h);
    }
    String html = {0};
    append(&html, "<nav class=\"toc\">\n");
    append(&html, toc_list(roots));
    append(&html, "\n</nav>");
    return finish(html);
}
static char *footnote_list(Renderer *r) {
    String html = {0};
    append(&html, "<section class=\"footnotes\">\n<ol>\n");
    for (size_t i = 0; i < r->notes.count; i++) {
        Footnote *note = r->notes.data[i];
        append(&html, "<li id=\"fn-");
        append(&html, decimal(note->number));
        append(&html, "\">");
        append(&html, inline_html(r, note->body, 1, 0));
        for (size_t count = 1; count <= note->count; count++) {
            append(&html, " <a href=\"#");
            append(&html, reference_id(note->number, count));
            append(&html, "\">&#8617;</a>");
        }
        append(&html, "</li>\n");
    }
    append(&html, "</ol>\n</section>\n");
    return finish(html);
}
static char *document(Renderer *r, Blocks blocks) {
    char *body = render_blocks(r, blocks);
    char *toc = table_of_contents(r);
    String html = {0};
    size_t marker_length = strlen(toc_marker);
    while (*body) {
        const char *found = strstr(body, toc_marker);
        if (!found) {
            append(&html, body);
            break;
        }
        append_n(&html, body, (size_t)(found - body));
        append(&html, toc);
        body = (char *)found + marker_length;
    }
    if (r->notes.count)
        append(&html, footnote_list(r));
    return finish(html);
}
int main(void) {
    Strings lines = {0};
    int ch;
    while (1) {
        String line = {0};
        while ((ch = getchar()) != EOF && ch != '\n')
            character(&line, (char)ch);
        if (line.length && line.data[line.length - 1] == '\r')
            line.data[--line.length] = 0;
        if (!strcmp(finish(line), "@@END@@") || (ch == EOF && !line.length))
            break;
        ADD(lines, finish(line));
        if (ch == EOF)
            break;
    }
    Parser parser = {0};
    Blocks blocks = parse(&parser, lines);
    Renderer renderer = {.parser = &parser};
    fputs(document(&renderer, blocks), stdout);
    for (size_t i = 0; i < allocation_count; i++)
        free(allocations[i]);
    free(allocations);
    return 0;
}
