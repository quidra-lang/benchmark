#include "ini_parser.h"

bool is_name(const char *text) {
    if (*text < 'a' || *text > 'z') return false;
    for (++text; *text; ++text)
        if (!((*text >= 'a' && *text <= 'z') || (*text >= '0' && *text <= '9') || *text == '_'))
            return false;
    return true;
}

bool is_section_name(const char *text) {
    Strings parts = split(text, '.');
    for (size_t i = 0; i < parts.len; ++i)
        if (!is_name(parts.data[i])) return false;
    return true;
}

static void parser_error(Document *document, int line, char *code, char *message) {
    report(&document->diagnostics, (Origin){document->name, line}, code, message);
}

static void add_statement(Document *document, StatementKind kind, int line, char *target, char *value) {
    Statement statement = {kind, line, target, value};
    PUSH(document->statements, statement);
}

static void trim_segments(Segments *segments) {
    Segment *first = &segments->data[0], *last = &segments->data[segments->len - 1];
    if (!first->quoted) {
        while (*first->text == ' ') ++first->text;
    }
    if (!last->quoted) {
        size_t length = strlen(last->text);
        while (length && last->text[length - 1] == ' ') --length;
        last->text = slice(last->text, 0, length);
    }
}

Document *parse_document(char *name, const char *text) {
    Document *document = checked_realloc(NULL, sizeof *document);
    *document = (Document){.name = name};
    char *section = NULL, *base = NULL;
    LogicalLines lines = lex_document(text);
    for (size_t i = 0; i < lines.len; ++i) {
        LogicalLine line = lines.data[i];
        if (line.code) {
            parser_error(document, line.number, line.code, line.message);
            continue;
        }
        Segments segments = line.segments;
        trim_segments(&segments);
        char *first = segments.data[0].text;
        if (segments.len == 1 && !*first) continue;
        if (*first == '[') {
            size_t length = strlen(first);
            bool valid = segments.len == 1 && length >= 2 && first[length - 1] == ']';
            char *inside = valid ? slice(first, 1, length - 2) : copy_text("");
            char *colon = strchr(inside, ':');
            char *parent = colon ? trim_spaces(colon + 1) : NULL;
            if (colon) *colon = '\0';
            char *header = trim_spaces(inside);
            bool relative = *header == '.' && is_section_name(header + 1);
            valid = valid && (!parent || is_section_name(parent)) &&
                    (relative || is_section_name(header));
            if (!valid || (relative && !base)) {
                parser_error(document, line.number, "E_SECTION",
                             valid ? "relative section without base" : "invalid section header");
                section = NULL;
            } else {
                if (relative) section = format("%s%s", base, header);
                else section = base = header;
                if (parent) add_statement(document, INHERIT, line.number, section, parent);
            }
            continue;
        }
        if (*first == '@') {
            Strings words = {0}, pieces = split(first, ' ');
            for (size_t j = 0; j < pieces.len; ++j)
                if (*pieces.data[j]) PUSH(words, pieces.data[j]);
            if (segments.len != 1 || words.len != 2 || !is_name(words.data[1]) ||
                (strcmp(words.data[0], "@include") && strcmp(words.data[0], "@unset"))) {
                parser_error(document, line.number, "E_SYNTAX", "invalid directive");
            } else if (!strcmp(words.data[0], "@include")) {
                add_statement(document, INCLUDE, line.number, words.data[1], "");
            } else if (!section) {
                parser_error(document, line.number, "E_NO_SECTION", "no current section");
            } else {
                add_statement(document, UNSET, line.number, format("%s.%s", section, words.data[1]), "");
            }
            continue;
        }
        bool has_equal = false;
        for (size_t j = 0; j < segments.len; ++j)
            if (!segments.data[j].quoted && strchr(segments.data[j].text, '=')) has_equal = true;
        char *equal = strchr(first, '=');
        if (!has_equal || !equal) {
            parser_error(document, line.number, "E_SYNTAX", has_equal ? "invalid key" : "invalid line");
            continue;
        }
        char *key = trim_spaces(slice(first, 0, (size_t)(equal - first)));
        size_t key_length = strlen(key);
        bool append = key_length && key[key_length - 1] == '+';
        if (append) key = trim_spaces(slice(key, 0, key_length - 1));
        if (!is_name(key)) {
            parser_error(document, line.number, "E_SYNTAX", "invalid key");
            continue;
        }
        segments.data[0].text = equal + 1;
        trim_segments(&segments);
        char *value = NULL;
        if (segments.len == 1) value = segments.data[0].text;
        else if (segments.len == 3 && !*segments.data[0].text && !*segments.data[2].text)
            value = segments.data[1].text;
        if (!value) {
            parser_error(document, line.number, "E_SYNTAX", "invalid value");
            continue;
        }
        if (!section) {
            parser_error(document, line.number, "E_NO_SECTION", "no current section");
            continue;
        }
        char *full_key = format("%s.%s", section, key);
        if (!append) {
            for (size_t j = document->statements.len; j > 0; --j) {
                Statement previous = document->statements.data[j - 1];
                if (previous.kind == ASSIGN && !strcmp(previous.target, full_key)) {
                    parser_error(document, line.number, "W_DUPLICATE",
                                 format("%s already set at line %d", full_key, previous.line));
                    break;
                }
            }
        }
        add_statement(document, append ? APPEND : ASSIGN, line.number, full_key, value);
    }
    return document;
}
