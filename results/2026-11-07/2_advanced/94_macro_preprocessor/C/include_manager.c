#include "preprocessor.h"
const char *directive_name(Tokens tokens) {
    return tokens.count >= 2 && equal(tokens.items[0].spelling, "#") &&
                   equal(tokens.items[1].kind, "identifier")
               ? tokens.items[1].spelling
               : "";
}
static char *detect_guard(LogicalLines logical) {
    TokenGroups lines = {0};
    for (int i = 0; i < logical.count; ++i)
        if (logical.items[i].tokens.count)
            PUSH(lines, logical.items[i].tokens);
    if (!lines.count)
        return "";
    Tokens first = lines.items[0], last = lines.items[lines.count - 1];
    if (first.count != 3 || !equal(first.items[0].spelling, "#") ||
        !equal(first.items[1].spelling, "ifndef") || !equal(first.items[1].kind, "identifier") ||
        !equal(first.items[2].kind, "identifier") || last.count != 2 ||
        !equal(last.items[0].spelling, "#") || !equal(last.items[1].spelling, "endif") ||
        !equal(last.items[1].kind, "identifier"))
        return "";
    int depth = 0;
    for (int i = 0; i < lines.count; ++i) {
        const char *name = directive_name(lines.items[i]);
        if (word_in("elif elifdef elifndef else", name) && depth == 1)
            return "";
        if (word_in("if ifdef ifndef", name))
            ++depth;
        else if (equal(name, "endif"))
            --depth;
        if (depth == 0 && i + 1 < lines.count)
            return "";
    }
    return depth == 0 ? (char *)first.items[2].spelling : "";
}
char *search_include(const char *name, bool quoted) {
    char *paths[2] = {(char *)name, ml_format("include/%s", name)};
    for (int i = quoted ? 0 : 1; i < 2; ++i) {
        struct stat info;
        if (stat(ml_format("input/%s", paths[i]), &info) == 0 && S_ISREG(info.st_mode))
            return paths[i];
    }
    return "";
}
FileData *find_file(IncludeManager *manager, const char *path) {
    for (int i = 0; i < manager->files.count; ++i)
        if (equal(manager->files.items[i]->path, path))
            return manager->files.items[i];
    return NULL;
}
FileData *load_file(IncludeManager *manager, const char *path) {
    FileData *file = find_file(manager, path);
    if (file)
        return file;
    FILE *input = fopen(ml_format("input/%s", path), "r");
    Text source = {0};
    int c;
    if (input) {
        while ((c = fgetc(input)) != EOF)
            text_char(&source, (char)c);
        fclose(input);
    }
    file = ml_alloc(sizeof(*file));
    file->path = path;
    file->lines = lex_source(text_value(&source));
    for (int i = 0; i < source.count; ++i)
        if (source.items[i] == '\n')
            ++file->physical_lines;
    file->guard = detect_guard(file->lines);
    PUSH(manager->files, file);
    return file;
}
