#include "linker.h"
bool equal(const char *left, const char *right) {
    return left && right && strcmp(left, right) == 0;
}
bool word_in(const char *list, const char *word) {
    if (!word)
        return false;
    size_t n = strlen(word);
    for (const char *p = list; *p;) {
        const char *end = strchr(p, ' ');
        if (!end)
            end = p + strlen(p);
        if ((size_t)(end - p) == n && strncmp(p, word, n) == 0)
            return true;
        p = *end ? end + 1 : end;
    }
    return false;
}
bool belongs(const char *name, const char *base) {
    size_t n = strlen(base);
    return equal(name, base) || (strncmp(name, base, n) == 0 && name[n] == '.');
}
StringList read_lines(const char *path) {
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
StringList words(const char *line) {
    StringList result = {0};
    const char *at = line;
    while (*at) {
        const char *end = strchr(at, ' ');
        if (!end)
            end = at + strlen(at);
        char *word = ml_text(at, (size_t)(end - at));
        PUSH(result, word);
        at = *end ? end + 1 : end;
    }
    return result;
}
int64_t number(const char *text) {
    return strtoll(text, NULL, strncmp(text, "0x", 2) == 0 ? 16 : 10);
}
static Section *section_named(Object *object, const char *name) {
    for (int i = 0; i < object->sections.count; ++i)
        if (equal(object->sections.items[i]->name, name))
            return object->sections.items[i];
    return NULL;
}
static Symbol *symbol_named(Object *object, const char *name) {
    for (int i = 0; i < object->symbols.count; ++i)
        if (equal(object->symbols.items[i]->name, name))
            return object->symbols.items[i];
    return NULL;
}
static int hex_digit(char c) { return c <= '9' ? c - '0' : c - 'a' + 10; }
Object *parse_object(StringList lines, const char *name) {
    Object *object = ml_alloc(sizeof(*object));
    object->name = name;
    Section *current = NULL;
    for (int line = 0; line < lines.count; ++line) {
        StringList a = words(lines.items[line]);
        if (equal(a.items[0], "section")) {
            current = ml_alloc(sizeof(*current));
            current->name = a.items[1];
            current->alignment = number(a.items[2]);
            current->size = number(a.items[3]);
            current->object = object;
            current->order = object->sections.count;
            current->reason = "";
            PUSH(object->sections, current);
        } else if (equal(a.items[0], "data")) {
            for (int i = 0; a.items[1][i]; i += 2) {
                uint8_t byte =
                    (uint8_t)(16 * hex_digit(a.items[1][i]) + hex_digit(a.items[1][i + 1]));
                PUSH(current->data, byte);
            }
        } else if (equal(a.items[0], "comdat")) {
            COMDATGroup group = {0};
            group.signature = a.items[1];
            for (int i = 2; i < a.count; ++i) {
                Section *section = section_named(object, a.items[i]);
                PUSH(group.sections, section);
            }
            PUSH(object->groups, group);
        } else if (equal(a.items[0], "symbol")) {
            Symbol *symbol = ml_alloc(sizeof(*symbol));
            symbol->name = a.items[1];
            symbol->binding = a.items[2];
            symbol->location = a.items[3];
            symbol->object = object;
            symbol->alignment = 1;
            if (equal(a.items[3], "common")) {
                symbol->size = number(a.items[4]);
                symbol->alignment = number(a.items[5]);
            } else if (!equal(a.items[3], "undef")) {
                symbol->location = "section";
                symbol->section = section_named(object, a.items[3]);
                symbol->offset = number(a.items[4]);
            }
            PUSH(object->symbols, symbol);
        } else if (equal(a.items[0], "reloc")) {
            Relocation *relocation = ml_alloc(sizeof(*relocation));
            relocation->section = section_named(object, a.items[1]);
            relocation->offset = number(a.items[2]);
            relocation->type = a.items[3];
            relocation->symbol = symbol_named(object, a.items[4]);
            relocation->addend = number(a.items[5]);
            PUSH(relocation->section->relocations, relocation);
        }
    }
    return object;
}
