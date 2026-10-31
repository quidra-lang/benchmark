#include "preprocessor.h"
typedef struct Allocation {
    void *value;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
void *ml_alloc(size_t size) {
    void *value = calloc(1, size ? size : 1);
    Allocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    record->value = value;
    record->next = allocations;
    allocations = record;
    return value;
}
void *ml_grow(void *items, int *capacity, size_t size, int count) {
    int next = *capacity ? *capacity * 2 : 8;
    void *result = ml_alloc((size_t)next * size);
    if (count)
        memcpy(result, items, (size_t)count * size);
    *capacity = next;
    return result;
}
char *ml_text(const char *text, size_t length) {
    char *result = ml_alloc(length + 1);
    memcpy(result, text, length);
    return result;
}
char *ml_format(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *result = ml_alloc((size_t)count + 1);
    vsnprintf(result, (size_t)count + 1, format, args);
    va_end(args);
    return result;
}
void ml_cleanup(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
void text_add(Text *text, const char *value) {
    size_t length = strlen(value);
    while ((size_t)text->capacity < (size_t)text->count + length + 1)
        text->items = ml_grow(text->items, &text->capacity, 1, text->count);
    memcpy(text->items + text->count, value, length + 1);
    text->count += (int)length;
}
void text_char(Text *text, char c) {
    char value[2] = {c, 0};
    text_add(text, value);
}
char *text_value(Text *text) {
    if (!text->items)
        return ml_text("", 0);
    return text->items;
}
Position display_position(Inclusion *inclusion, int physical) {
    return (Position){inclusion->display_file, physical + inclusion->offset};
}
bool skipping(Inclusion *inclusion) {
    return inclusion->stack.count && !inclusion->stack.items[inclusion->stack.count - 1]->active;
}
Macro *find_macro(Preprocessor *p, const char *name) {
    for (MacroEntry *entry = p->macros; entry; entry = entry->next)
        if (equal(entry->name, name))
            return entry->macro;
    return NULL;
}
void set_macro(Preprocessor *p, const char *name, Macro *macro) {
    for (MacroEntry *entry = p->macros; entry; entry = entry->next)
        if (equal(entry->name, name)) {
            entry->macro = macro;
            return;
        }
    MacroEntry *entry = ml_alloc(sizeof(*entry));
    entry->name = name;
    entry->macro = macro;
    entry->next = p->macros;
    p->macros = entry;
}
void diagnostic(Preprocessor *p, Position position, const char *kind, const char *message) {
    char *line = ml_format("%s: %s: %s", position_text(position), kind, message);
    PUSH(p->diagnostics, line);
    if (equal(kind, "error"))
        ++p->errors;
    else
        ++p->warnings;
}
static void event(Preprocessor *p, Position position, const char *content) {
    char *line = ml_format("%s: %s", position_text(position), content);
    PUSH(p->history, line);
}
Header read_header(Tokens tokens, int index) {
    Header result = {0};
    if (index >= tokens.count)
        return result;
    Token token = tokens.items[index];
    if (equal(token.kind, "string") || equal(token.kind, "header")) {
        result.present = true;
        result.rendering = (char *)token.spelling;
        result.name = ml_text(token.spelling + 1, strlen(token.spelling) - 2);
        result.quoted = token.spelling[0] == '"';
        result.next = index + 1;
    } else if (equal(token.spelling, "<")) {
        int end = index + 1;
        while (end < tokens.count && !equal(tokens.items[end].spelling, ">"))
            ++end;
        if (end == tokens.count) {
            result.error = "missing terminating > character";
            return result;
        }
        Tokens middle = {tokens.items + index + 1, end - index - 1, 0};
        result.present = true;
        result.name = render(middle);
        result.rendering = ml_format("<%s>", result.name);
        result.next = end + 1;
    }
    return result;
}
static bool separator_needed(const char *left, const char *right) {
    if (equal(left, "/") && (right[0] == '/' || right[0] == '*'))
        return true;
    char *joined = ml_format("%s%s", left, right);
    return read_token(joined, 0, false).end != strlen(left);
}
static char *output_render(Tokens tokens) {
    Text result = {0};
    for (int i = 0; i < tokens.count; ++i) {
        if (i && (tokens.items[i].space ||
                  separator_needed(tokens.items[i - 1].spelling, tokens.items[i].spelling)))
            text_char(&result, ' ');
        text_add(&result, tokens.items[i].spelling);
    }
    return text_value(&result);
}
static bool decimal_token(Token token) {
    if (!equal(token.kind, "number") || !*token.spelling)
        return false;
    for (const char *c = token.spelling; *c; ++c)
        if (*c < '0' || *c > '9')
            return false;
    return true;
}
static void poison_check(Preprocessor *p, Inclusion *inclusion, Tokens tokens) {
    for (int i = 0; i < tokens.count; ++i) {
        Token token = tokens.items[i];
        if (equal(token.kind, "identifier") && string_member(p->poisoned, token.spelling))
            diagnostic(p, display_position(inclusion, token.line), "error",
                       ml_format("attempt to use poisoned \"%s\"", token.spelling));
    }
}
static void unused_check(Preprocessor *p, Macro *macro) {
    if (macro->main_file && !macro->expanded && !macro->tested)
        diagnostic(p, macro->position, "warning",
                   ml_format("macro \"%s\" is not used", macro->name));
}
static void define(Preprocessor *p, Tokens tokens, Position position, bool main_file) {
    char *error = NULL;
    Macro *macro = parse_definition(tokens, position, main_file, &error);
    if (error) {
        diagnostic(p, position, "error", error);
        return;
    }
    Macro *previous = find_macro(p, macro->name);
    const char *operation = "define";
    if (!previous) {
        set_macro(p, macro->name, macro);
        string_insert(&p->ever_defined, macro->name);
    } else if (identical(previous, macro))
        operation = "identical";
    else {
        unused_check(p, previous);
        diagnostic(p, position, "warning",
                   ml_format("\"%s\" redefined (previous definition at %s)", macro->name,
                             position_text(previous->position)));
        set_macro(p, macro->name, macro);
        string_insert(&p->ever_defined, macro->name);
        operation = "redefine";
    }
    event(p, position, ml_format("%s %s", operation, signature(macro)));
}
static void undefine(Preprocessor *p, Tokens tokens, Position position) {
    char *error = check_name(tokens, "undef");
    if (error) {
        diagnostic(p, position, "error", error);
        return;
    }
    if (tokens.count > 1)
        diagnostic(p, position, "warning", "extra tokens at end of #undef directive");
    const char *name = tokens.items[0].spelling;
    Macro *previous = find_macro(p, name);
    if (previous) {
        unused_check(p, previous);
        set_macro(p, name, NULL);
        event(p, position, ml_format("undef %s", name));
    } else
        event(p, position, ml_format("undef %s (not defined)", name));
}
static StringList read_lines(const char *path) {
    StringList result = {0};
    FILE *input = fopen(path, "r");
    if (!input)
        return result;
    Text line = {0};
    int c;
    while ((c = fgetc(input)) != EOF) {
        if (c == '\n') {
            char *value = text_value(&line);
            PUSH(result, value);
            line = (Text){0};
        } else
            text_char(&line, (char)c);
    }
    fclose(input);
    return result;
}
static void process_defines(Preprocessor *p) {
    StringList lines = read_lines("input/defines.txt");
    for (int i = 0; i < lines.count; ++i) {
        const char *line = lines.items[i];
        if (!*line)
            continue;
        const char *at = strchr(line, '=');
        char *text = at ? ml_format("%s %s", ml_text(line, (size_t)(at - line)), at + 1)
                        : ml_format("%s 1", line);
        define(p, lex_definition(text, i + 1), (Position){"defines.txt", i + 1}, false);
    }
}
static void marker(Preprocessor *p, const char *file, int line, int flag) {
    char *text =
        flag ? ml_format("# %d \"%s\" %d", line, file, flag) : ml_format("# %d \"%s\"", line, file);
    PUSH(p->output, text);
    p->previous = (Position){file, line - 1};
}
static void output_line(Preprocessor *p, Inclusion *inclusion, int physical, const char *text) {
    Position position = display_position(inclusion, physical);
    if (equal(position.file, p->previous.file) && p->previous.line < position.line &&
        (int64_t)position.line <= (int64_t)p->previous.line + 8) {
        for (int64_t i = (int64_t)p->previous.line + 1; i < position.line; ++i)
            PUSH(p->output, "");
    } else
        marker(p, position.file, position.line, 0);
    PUSH(p->output, (char *)text);
    p->previous = position;
    ++inclusion->source->output_lines;
}
static void flush(Preprocessor *p, Inclusion *inclusion) {
    Tokens segment = inclusion->segment;
    inclusion->segment = (Tokens){0};
    if (!segment.count)
        return;
    poison_check(p, inclusion, segment);
    Tokens expanded = expand(p, inclusion, segment);
    for (int start = 0; start < expanded.count;) {
        int end = start + 1;
        while (end < expanded.count && expanded.items[end].line == expanded.items[start].line)
            ++end;
        Tokens part = {expanded.items + start, end - start, 0};
        output_line(p, inclusion, expanded.items[start].line, output_render(part));
        start = end;
    }
}
static bool macro_defined(Preprocessor *p, const char *name) {
    Macro *macro = find_macro(p, name);
    if (macro) {
        ++macro->tested;
        return true;
    }
    return builtin(name) || equal(name, "__has_include");
}
static Tokens replace_operators(Preprocessor *p, Tokens operands, char **error) {
    Tokens result = {0};
    *error = NULL;
    for (int position = 0; position < operands.count;) {
        Token token = operands.items[position];
        int index = position + 1;
        bool value = false;
        if (equal(token.kind, "identifier") && equal(token.spelling, "defined")) {
            bool parenthesized =
                index < operands.count && equal(operands.items[index].spelling, "(");
            if (parenthesized)
                ++index;
            if (index == operands.count || !equal(operands.items[index].kind, "identifier")) {
                *error = "operator \"defined\" requires an identifier";
                return result;
            }
            const char *name = operands.items[index++].spelling;
            if (parenthesized) {
                if (index == operands.count || !equal(operands.items[index].spelling, ")")) {
                    *error = "missing ')' after \"defined\"";
                    return result;
                }
                ++index;
            }
            value = macro_defined(p, name);
        } else if (equal(token.kind, "identifier") && equal(token.spelling, "__has_include")) {
            if (index == operands.count || !equal(operands.items[index].spelling, "(")) {
                *error = "missing '(' after \"__has_include\"";
                return result;
            }
            Header header = read_header(operands, index + 1);
            if (header.error) {
                *error = header.error;
                return result;
            }
            if (!header.present || !*header.name) {
                *error = "operator \"__has_include\" requires a header-name";
                return result;
            }
            index = header.next;
            if (index == operands.count || !equal(operands.items[index].spelling, ")")) {
                *error = "missing ')' after \"__has_include\" operand";
                return result;
            }
            ++index;
            value = *search_include(header.name, header.quoted) != 0;
        } else {
            PUSH(result, token);
            ++position;
            continue;
        }
        Token replacement = {"number", value ? "1" : "0", token.line, token.space, {0}};
        PUSH(result, replacement);
        position = index;
    }
    return result;
}
typedef struct {
    bool valid;
    int64_t value;
    Tokens expanded;
    bool was_expanded;
} TestResult;
static TestResult test(Preprocessor *p, Inclusion *inclusion, LogicalLine line, const char *name,
                       Tokens operands) {
    Position position = display_position(inclusion, line.tokens.items[0].line);
    poison_check(p, inclusion, operands);
    TestResult result = {0};
    if (!equal(name, "if") && !equal(name, "elif")) {
        if (!operands.count) {
            diagnostic(p, position, "error",
                       ml_format("no macro name given in #%s directive", name));
            return result;
        }
        if (!equal(operands.items[0].kind, "identifier")) {
            diagnostic(p, position, "error", "macro names must be identifiers");
            return result;
        }
        if (operands.count > 1)
            diagnostic(p, position, "warning",
                       ml_format("extra tokens at end of #%s directive", name));
        bool defined = macro_defined(p, operands.items[0].spelling);
        if (equal(name, "ifndef") || equal(name, "elifndef"))
            defined = !defined;
        result.valid = true;
        result.value = defined;
        return result;
    }
    char *error = NULL;
    Tokens replaced = replace_operators(p, operands, &error);
    if (error) {
        diagnostic(p, position, "error", error);
        return result;
    }
    result.expanded = expand(p, inclusion, replaced);
    result.was_expanded = true;
    ConditionExpr *expression = parse_condition(result.expanded, name, &error);
    if (!error) {
        int64_t value = 0;
        if (evaluate_condition(p, position, expression, &value, &error)) {
            result.valid = true;
            result.value = value;
        }
    }
    if (error)
        diagnostic(p, position, "error", error);
    return result;
}
static char *test_description(const char *name, TestResult tested) {
    char *result = "not taken (error)";
    if (tested.valid) {
        result = tested.value ? "taken" : "not taken";
        if (equal(name, "if") || equal(name, "elif"))
            result = ml_format("%s (value %lld)", result, (long long)tested.value);
    }
    if (tested.was_expanded)
        result = ml_format("%s [%s]", result, output_render(tested.expanded));
    return result;
}
static void close_region(Preprocessor *p, Inclusion *inclusion, ConditionalBlock *block, int end) {
    int start = block->skip_start;
    if (start && end >= start) {
        Position first = display_position(inclusion, start),
                 last = display_position(inclusion, end);
        char *line =
            ml_format("%s:%d-%d lines=%d", first.file, first.line, last.line, end - start + 1);
        PUSH(p->regions, line);
        inclusion->source->skipped_lines += end - start + 1;
    }
    block->skip_start = 0;
}
static void conditional_record(Preprocessor *p, Position position, int depth, const char *name,
                               Tokens operands, const char *description) {
    char *directive =
        operands.count ? ml_format("#%s %s", name, render(operands)) : ml_format("#%s", name);
    char *indentation = ml_alloc((size_t)2 * depth + 1);
    memset(indentation, ' ', (size_t)2 * depth);
    char *record =
        ml_format("%s: %s%s => %s", position_text(position), indentation, directive, description);
    PUSH(p->conditionals, record);
    const char *prefixes[] = {"taken", "not taken", "skipped", "not evaluated", "closes"};
    for (int i = 0; i < 5; ++i)
        if (strncmp(description, prefixes[i], strlen(prefixes[i])) == 0) {
            ++p->condition_counts[i];
            break;
        }
}
static void conditional(Preprocessor *p, Inclusion *inclusion, LogicalLine line, const char *name,
                        Tokens operands) {
    Position position = display_position(inclusion, line.tokens.items[0].line);
    if (word_in("if ifdef ifndef", name)) {
        ConditionalBlock *block = ml_alloc(sizeof(*block));
        block->kind = name;
        block->start = position;
        block->parent = !skipping(inclusion);
        char *description = "skipped";
        if (block->parent) {
            TestResult tested = test(p, inclusion, line, name, operands);
            if (tested.valid && tested.value)
                block->chosen = block->active = true;
            else
                block->skip_start = line.end + 1;
            description = test_description(name, tested);
        }
        conditional_record(p, position, inclusion->stack.count, name, operands, description);
        PUSH(inclusion->stack, block);
        return;
    }
    if (!inclusion->stack.count) {
        diagnostic(p, position, "error", ml_format("#%s without #if", name));
        return;
    }
    int depth = inclusion->stack.count - 1;
    ConditionalBlock *block = inclusion->stack.items[depth];
    close_region(p, inclusion, block, line.start - 1);
    char *description = NULL;
    if (equal(name, "endif")) {
        --inclusion->stack.count;
        if (block->parent && operands.count)
            diagnostic(p, position, "warning", "extra tokens at end of #endif directive");
        description = ml_format("closes #%s at line %d", block->kind, block->start.line);
    } else {
        if (block->else_seen)
            diagnostic(p, position, "error", ml_format("#%s after #else", name));
        if (equal(name, "else")) {
            if (block->parent && operands.count)
                diagnostic(p, position, "warning", "extra tokens at end of #else directive");
            block->else_seen = true;
            if (block->parent) {
                block->active = !block->chosen;
                block->chosen = true;
                description = block->active ? "taken" : "not taken";
            } else {
                block->active = false;
                description = "skipped";
            }
        } else if (!block->parent) {
            block->active = false;
            description = "skipped";
        } else if (block->chosen) {
            block->active = false;
            description = "not evaluated";
        } else {
            TestResult tested = test(p, inclusion, line, name, operands);
            block->active = tested.valid && tested.value;
            if (block->active)
                block->chosen = true;
            description = test_description(name, tested);
        }
        if (block->parent && !block->active)
            block->skip_start = line.end + 1;
    }
    conditional_record(p, position, depth, name, operands, description);
}
static void process_file(Preprocessor *, const char *, int);
static void include(Preprocessor *p, Inclusion *inclusion, LogicalLine line, Tokens operands) {
    Position position = display_position(inclusion, line.tokens.items[0].line);
    Header header = read_header(operands, 0);
    if (header.error) {
        diagnostic(p, position, "error", header.error);
        return;
    }
    if (!header.present && operands.count) {
        operands = expand(p, inclusion, operands);
        header = read_header(operands, 0);
        if (header.error) {
            diagnostic(p, position, "error", header.error);
            return;
        }
    }
    if (!header.present) {
        diagnostic(p, position, "error", "#include expects \"FILENAME\" or <FILENAME>");
        return;
    }
    if (header.next < operands.count)
        diagnostic(p, position, "warning", "extra tokens at end of #include directive");
    if (!*header.name) {
        diagnostic(p, position, "error", "empty filename in #include");
        return;
    }
    char *indentation = ml_alloc((size_t)2 * (inclusion->depth + 1) + 1);
    memset(indentation, ' ', (size_t)2 * (inclusion->depth + 1));
    char *prefix = ml_format("%s%d: ", indentation, line.tokens.items[0].line);
    char *path = search_include(header.name, header.quoted);
    char *tree_line;
    if (!*path) {
        tree_line = ml_format("%s%s [not found]", prefix, header.rendering);
        PUSH(p->tree, tree_line);
        diagnostic(p, position, "error",
                   ml_format("cannot find include file %s", header.rendering));
        return;
    }
    FileData *previous = find_file(&p->manager, path);
    if (previous && previous->once) {
        tree_line = ml_format("%s%s [skipped: pragma once]", prefix, path);
        PUSH(p->tree, tree_line);
        ++previous->skipped;
        return;
    }
    if (previous && *previous->guard && find_macro(p, previous->guard)) {
        tree_line = ml_format("%s%s [skipped: guard %s]", prefix, path, previous->guard);
        PUSH(p->tree, tree_line);
        ++previous->skipped;
        return;
    }
    if (inclusion->depth + 1 > 8) {
        tree_line = ml_format("%s%s [too deep]", prefix, path);
        PUSH(p->tree, tree_line);
        diagnostic(p, position, "error", "#include nested too deeply");
        return;
    }
    tree_line = ml_format("%s%s", prefix, path);
    PUSH(p->tree, tree_line);
    marker(p, path, 1, 1);
    process_file(p, path, inclusion->depth + 1);
    Position next = display_position(inclusion, line.end + 1);
    marker(p, next.file, next.line, 2);
}
static void line_directive(Preprocessor *p, Inclusion *inclusion, LogicalLine line,
                           Tokens operands) {
    Position position = display_position(inclusion, line.tokens.items[0].line);
    if (!operands.count || !decimal_token(operands.items[0]))
        operands = expand(p, inclusion, operands);
    if (!operands.count || operands.count > 2 || !decimal_token(operands.items[0]) ||
        (operands.count == 2 && !equal(operands.items[1].kind, "string"))) {
        diagnostic(p, position, "error", "invalid #line directive");
        return;
    }
    int64_t number = strtoll(operands.items[0].spelling, NULL, 10);
    if (number < 1 || number > 2147483647LL) {
        diagnostic(p, position, "error", "line number out of range");
        return;
    }
    inclusion->offset = (int)number - (line.end + 1);
    if (operands.count == 2)
        inclusion->display_file =
            ml_text(operands.items[1].spelling + 1, strlen(operands.items[1].spelling) - 2);
}
static void macro_pragma(Preprocessor *p, Position position, Tokens operands,
                         const char *operation) {
    if (operands.count != 4 || !equal(operands.items[1].spelling, "(") ||
        !equal(operands.items[2].kind, "string") || !equal(operands.items[3].spelling, ")")) {
        diagnostic(p, position, "error", ml_format("invalid #pragma %s directive", operation));
        return;
    }
    char *name = ml_text(operands.items[2].spelling + 1, strlen(operands.items[2].spelling) - 2);
    Saved *saved = p->saved;
    while (saved && !equal(saved->name, name))
        saved = saved->next;
    if (!saved) {
        saved = ml_alloc(sizeof(*saved));
        saved->name = name;
        saved->next = p->saved;
        p->saved = saved;
    }
    if (equal(operation, "push_macro")) {
        Macro *macro = find_macro(p, name);
        PUSH(saved->stack, macro);
        event(p, position, ml_format("push %s", name));
        return;
    }
    if (!saved->stack.count) {
        diagnostic(p, position, "warning", ml_format("no matching push_macro for \"%s\"", name));
        return;
    }
    Macro *macro = saved->stack.items[--saved->stack.count];
    set_macro(p, name, macro);
    event(p, position, macro ? ml_format("pop %s", name) : ml_format("pop %s (undefined)", name));
}
static void pragma(Preprocessor *p, Inclusion *inclusion, LogicalLine line, Tokens operands) {
    Position position = display_position(inclusion, line.tokens.items[0].line);
    const char *name = operands.count && equal(operands.items[0].kind, "identifier")
                           ? operands.items[0].spelling
                           : "";
    if (equal(name, "once")) {
        if (operands.count > 1)
            diagnostic(p, position, "warning", "extra tokens at end of #pragma once directive");
        if (inclusion->depth == 0)
            diagnostic(p, position, "warning", "#pragma once in main file");
        inclusion->source->once = true;
    } else if (operands.count >= 2 && equal(operands.items[0].spelling, "GCC") &&
               equal(operands.items[1].spelling, "poison")) {
        for (int i = 2; i < operands.count; ++i)
            if (!equal(operands.items[i].kind, "identifier")) {
                diagnostic(p, position, "error", "invalid #pragma GCC poison directive");
                return;
            }
        for (int i = 2; i < operands.count; ++i) {
            const char *name = operands.items[i].spelling;
            if (find_macro(p, name))
                diagnostic(p, position, "warning",
                           ml_format("poisoning existing macro \"%s\"", name));
            string_insert(&p->poisoned, name);
        }
    } else if (equal(name, "push_macro") || equal(name, "pop_macro"))
        macro_pragma(p, position, operands, name);
    else
        output_line(p, inclusion, line.tokens.items[0].line,
                    operands.count ? ml_format("#pragma %s", render(operands)) : "#pragma");
}
static void directive(Preprocessor *p, Inclusion *inclusion, LogicalLine line, const char *name,
                      Tokens operands) {
    if (line.tokens.count == 1)
        return;
    bool poisoning = equal(name, "pragma") && operands.count >= 2 &&
                     equal(operands.items[0].spelling, "GCC") &&
                     equal(operands.items[1].spelling, "poison");
    if (!poisoning)
        poison_check(p, inclusion, operands);
    Position position = display_position(inclusion, line.tokens.items[0].line);
    if (equal(name, "define"))
        define(p, operands, position, inclusion->depth == 0);
    else if (equal(name, "undef"))
        undefine(p, operands, position);
    else if (equal(name, "include"))
        include(p, inclusion, line, operands);
    else if (equal(name, "line"))
        line_directive(p, inclusion, line, operands);
    else if (equal(name, "error") || equal(name, "warning"))
        diagnostic(p, position, name,
                   operands.count ? ml_format("#%s %s", name, render(operands))
                                  : ml_format("#%s", name));
    else if (equal(name, "pragma"))
        pragma(p, inclusion, line, operands);
    else
        diagnostic(p, position, "error",
                   ml_format("invalid preprocessing directive #%s", line.tokens.items[1].spelling));
}
static void process_file(Preprocessor *p, const char *path, int depth) {
    FileData *source = load_file(&p->manager, path);
    ++source->entered;
    Inclusion inclusion = {0};
    inclusion.source = source;
    inclusion.depth = depth;
    inclusion.display_file = path;
    for (int i = 0; i < source->lines.count; ++i) {
        LogicalLine line = source->lines.items[i];
        bool is_directive = line.tokens.count && equal(line.tokens.items[0].spelling, "#");
        const char *name = directive_name(line.tokens);
        Tokens operands = {0};
        if (line.tokens.count > 2)
            operands = (Tokens){line.tokens.items + 2, line.tokens.count - 2, 0};
        if (is_directive && word_in("if ifdef ifndef elif elifdef elifndef else endif", name)) {
            flush(p, &inclusion);
            conditional(p, &inclusion, line, name, operands);
        } else if (skipping(&inclusion))
            continue;
        else if (is_directive) {
            flush(p, &inclusion);
            directive(p, &inclusion, line, name, operands);
        } else
            for (int j = 0; j < line.tokens.count; ++j)
                PUSH(inclusion.segment, line.tokens.items[j]);
    }
    flush(p, &inclusion);
    for (int i = 0; i < inclusion.stack.count; ++i)
        close_region(p, &inclusion, inclusion.stack.items[i], source->physical_lines);
    for (int i = 0; i < inclusion.stack.count; ++i) {
        ConditionalBlock *block = inclusion.stack.items[i];
        diagnostic(p, block->start, "error", ml_format("unterminated #%s", block->kind));
    }
}
static int string_compare(const void *left, const void *right) {
    return strcmp(*(char *const *)left, *(char *const *)right);
}
static int macro_compare(const void *left, const void *right) {
    Macro *a = *(Macro *const *)left;
    Macro *b = *(Macro *const *)right;
    return strcmp(a->name, b->name);
}
static int file_compare(const void *left, const void *right) {
    FileData *a = *(FileData *const *)left;
    FileData *b = *(FileData *const *)right;
    return strcmp(a->path, b->path);
}
static MacroList sorted_macros(Preprocessor *p) {
    MacroList result = {0};
    for (MacroEntry *entry = p->macros; entry; entry = entry->next)
        if (entry->macro)
            PUSH(result, entry->macro);
    if (result.count > 1)
        qsort(result.items, (size_t)result.count, sizeof(Macro *), macro_compare);
    return result;
}
static bool macro_member(MacroList list, Macro *macro) {
    for (int i = 0; i < list.count; ++i)
        if (list.items[i] == macro)
            return true;
    return false;
}
static bool recursive_visit(Preprocessor *p, Macro *current, Macro *target, MacroList *seen) {
    PUSH(*seen, current);
    for (int i = 0; i < current->references.count; ++i) {
        Macro *next = find_macro(p, current->references.items[i]);
        if (next == target)
            return true;
        if (!macro_member(*seen, next) && recursive_visit(p, next, target, seen))
            return true;
    }
    return false;
}
static void write_lines(const char *name, StringList lines) {
    FILE *output = fopen(ml_format("output/%s", name), "w");
    if (!output)
        return;
    for (int i = 0; i < lines.count; ++i) {
        size_t n = strlen(lines.items[i]);
        while (n && lines.items[i][n - 1] == ' ')
            --n;
        fwrite(lines.items[i], 1, n, output);
        fputc('\n', output);
    }
    fclose(output);
}
static void write_reports(Preprocessor *p) {
    StringList includes = {0};
    for (int i = 0; i < p->tree.count; ++i)
        PUSH(includes, p->tree.items[i]);
    PUSH(includes, "");
    PUSH(includes, "== files ==");
    FileList ordered = {0};
    for (int i = 0; i < p->manager.files.count; ++i)
        PUSH(ordered, p->manager.files.items[i]);
    if (ordered.count > 1)
        qsort(ordered.items, (size_t)ordered.count, sizeof(FileData *), file_compare);
    for (int i = 0; i < ordered.count; ++i) {
        FileData *file = ordered.items[i];
        char *line = ml_format(
            "%s entered=%d skipped=%d lines=%d output_lines=%d skipped_lines=%d guard=%s once=%s",
            file->path, file->entered, file->skipped, file->physical_lines, file->output_lines,
            file->skipped_lines, *file->guard ? file->guard : "-", file->once ? "yes" : "no");
        PUSH(includes, line);
    }
    PUSH(includes, "");
    char *current = "main.o:";
    bool has_path = false;
    for (int i = 0; i < p->manager.files.count; ++i) {
        const char *path = p->manager.files.items[i]->path;
        if (strlen(current) + 1 + strlen(path) > 76 && has_path) {
            char *line = ml_format("%s \\", current);
            PUSH(includes, line);
            current = " ";
            has_path = false;
        }
        current = ml_format("%s %s", current, path);
        has_path = true;
    }
    PUSH(includes, current);
    StringList macros = {0};
    PUSH(macros, "== history ==");
    for (int i = 0; i < p->history.count; ++i)
        PUSH(macros, p->history.items[i]);
    PUSH(macros, "");
    PUSH(macros, "== table ==");
    MacroList table = sorted_macros(p);
    for (int i = 0; i < table.count; ++i) {
        Macro *macro = table.items[i];
        macro->references = (StringList){0};
        for (int j = 0; j < macro->replacement.count; ++j) {
            Token token = macro->replacement.items[j];
            if (equal(token.kind, "identifier") && find_macro(p, token.spelling) &&
                !string_member(macro->parameters, token.spelling))
                string_insert(&macro->references, token.spelling);
        }
        if (macro->references.count > 1)
            qsort(macro->references.items, (size_t)macro->references.count, sizeof(char *),
                  string_compare);
    }
    int objects = 0;
    for (int i = 0; i < table.count; ++i) {
        Macro *macro = table.items[i];
        char *definition = macro->replacement.count ? ml_format("#define %s %s", signature(macro),
                                                                render(macro->replacement))
                                                    : ml_format("#define %s", signature(macro));
        PUSH(macros, definition);
        MacroList seen = {0};
        bool recursive = recursive_visit(p, macro, macro, &seen);
        char *location =
            ml_format("  at %s expanded=%d tested=%d recursive=%s", position_text(macro->position),
                      macro->expanded, macro->tested, recursive ? "yes" : "no");
        PUSH(macros, location);
        Text refs = {0};
        text_add(&refs, "  refs:");
        for (int j = 0; j < macro->references.count; ++j) {
            text_char(&refs, ' ');
            text_add(&refs, macro->references.items[j]);
        }
        char *references = text_value(&refs);
        PUSH(macros, references);
        if (!macro->function)
            ++objects;
    }
    PUSH(macros, "");
    char *totals = ml_format("macros=%d object_like=%d function_like=%d", table.count, objects,
                             table.count - objects);
    PUSH(macros, totals);
    StringList names = {0};
    for (int i = 0; i < p->ever_defined.count; ++i)
        PUSH(names, p->ever_defined.items[i]);
    if (names.count > 1)
        qsort(names.items, (size_t)names.count, sizeof(char *), string_compare);
    Text undefined = {0};
    text_add(&undefined, "undefined:");
    for (int i = 0; i < names.count; ++i)
        if (!find_macro(p, names.items[i])) {
            text_char(&undefined, ' ');
            text_add(&undefined, names.items[i]);
        }
    char *undefined_line = text_value(&undefined);
    PUSH(macros, undefined_line);
    char *builtins_line =
        ml_format("builtins: __COUNTER__=%d __FILE__=%d __LINE__=%d", p->builtin_counts[0],
                  p->builtin_counts[1], p->builtin_counts[2]);
    PUSH(macros, builtins_line);
    StringList conditions = {0};
    for (int i = 0; i < p->conditionals.count; ++i)
        PUSH(conditions, p->conditionals.items[i]);
    PUSH(conditions, "");
    PUSH(conditions, "== skipped regions ==");
    for (int i = 0; i < p->regions.count; ++i)
        PUSH(conditions, p->regions.items[i]);
    PUSH(conditions, "");
    char *condition_totals = ml_format(
        "directives=%d taken=%d not_taken=%d skipped=%d not_evaluated=%d endif=%d regions=%d",
        p->conditionals.count, p->condition_counts[0], p->condition_counts[1],
        p->condition_counts[2], p->condition_counts[3], p->condition_counts[4], p->regions.count);
    PUSH(conditions, condition_totals);
    char *diagnostics_totals = ml_format("errors=%d warnings=%d", p->errors, p->warnings);
    PUSH(p->diagnostics, diagnostics_totals);
    mkdir("output", 0777);
    write_lines("preprocessed.txt", p->output);
    write_lines("includes.txt", includes);
    write_lines("macros.txt", macros);
    write_lines("conditionals.txt", conditions);
    write_lines("diagnostics.txt", p->diagnostics);
}
int main(void) {
    Preprocessor *p = ml_alloc(sizeof(*p));
    PUSH(p->tree, "main.c");
    process_defines(p);
    marker(p, "main.c", 1, 0);
    process_file(p, "main.c", 0);
    MacroList macros = sorted_macros(p);
    for (int i = 0; i < macros.count; ++i)
        unused_check(p, macros.items[i]);
    write_reports(p);
    ml_cleanup();
    return 0;
}
